local fire_attack_enabled = GetModConfigData("willow_fire_attack") ~= false
local FIRE_HP_THRESHOLD = GetModConfigData("willow_fire_hp_threshold") or 200
local ATTACK_COMMIT_DELAY = 9 * FRAMES
local COMBAT_TIMEOUT = .6
local HP_RESPONSE_TIMEOUT = .5
local SWAP_TIMEOUT = 1
local MAX_SWAP_RETRIES = 2

local function IsLocalMasterMode()
    local player = ThePlayer
    local controller = player ~= nil
        and player.components ~= nil
        and player.components.playercontroller
        or nil
    return TUNING.DSA_ONE_PLAYER_MODE == true
        and TheWorld ~= nil
        and TheWorld.ismastersim
        and controller ~= nil
        and controller.ismastersim
end

local function GetInventory()
    return ThePlayer ~= nil and ThePlayer.replica.inventory or nil
end

local function GetHandItem()
    local inventory = GetInventory()
    return inventory ~= nil and inventory:GetEquippedItem(EQUIPSLOTS.HANDS) or nil
end

local function IsHeld(item)
    local inventory = GetInventory()
    return item ~= nil
        and item:IsValid()
        and inventory ~= nil
        and inventory:IsHolding(item, true)
end

local function CanEquip(item)
    local equippable = item ~= nil
        and item.replica ~= nil
        and item.replica.equippable
        or nil
    return IsHeld(item)
        and not item:HasTag("broken")
        and equippable ~= nil
        and equippable:EquipSlot() == EQUIPSLOTS.HANDS
        and (equippable.IsRestricted == nil or not equippable:IsRestricted(ThePlayer))
end

local function CollectItems()
    local inventory = GetInventory()
    local items, seen = {}, {}
    if inventory == nil then
        return items
    end

    local function Add(item)
        if item ~= nil and not seen[item] then
            seen[item] = true
            items[#items + 1] = item
        end
    end

    for _, item in pairs(inventory:GetEquips()) do Add(item) end
    for _, item in pairs(inventory:GetItems()) do Add(item) end
    Add(inventory:GetActiveItem())

    local overflow = inventory:GetOverflowContainer()
    if overflow ~= nil then
        for _, item in pairs(overflow:GetItems()) do Add(item) end
    end

    return items
end

local function FindWillowLighter()
    for _, item in ipairs(CollectItems()) do
        if item.prefab == "lighter" and CanEquip(item) then
            return item
        end
    end
end

local function IsIgnitable(target)
    return target ~= nil
        and target:IsValid()
        and target:HasAnyTag("animal", "character", "largecreature", "monster", "smallcreature")
        and not target:HasTag("noember")
        and target:HasAnyTag("canlight", "nolight")
        and not target:HasAnyTag("fire", "fireimmune", "burnt")
end

local ShowMeHealth = { listener_added = false }

function ShowMeHealth:IsAvailable()
    return MOD_RPC ~= nil
        and MOD_RPC.ShowMeSHint ~= nil
        and MOD_RPC.ShowMeSHint.Hint ~= nil
end

local function ParseShowMeHealth(message)
    return tonumber(message:match("a(%d+)") or message:match("b(%d+)"))
end

function ShowMeHealth:EnsureListener()
    if self.listener_added then
        return
    end

    local classified = ThePlayer and ThePlayer.player_classified or nil
    if classified == nil then
        return
    end

    self.listener_added = true
    classified:ListenForEvent("showme_hint_dirty2", function(inst)
        local hint = inst.net_showme_hint2 ~= nil and inst.net_showme_hint2:value() or inst.showme_hint2
        if type(hint) ~= "string" then
            return
        end

        local separator = string.find(hint, ";", 1, true)
        if separator == nil then
            return
        end

        local target = Ents[tonumber(hint:sub(1, separator - 1))]
        local current = ParseShowMeHealth(hint:sub(separator + 1))
        if target ~= nil and current ~= nil then
            target._wfa_hp = { current = current, time = GetTime() }
            target._wfa_hp_pending = nil
        end
    end)
end

function ShowMeHealth:Request(target)
    self:EnsureListener()
    local now = GetTime()
    if target._wfa_hp_req ~= nil and now - target._wfa_hp_req < .35 then
        return
    end

    target._wfa_hp_req = now
    SendModRPCToServer(MOD_RPC.ShowMeSHint.Hint, target.GUID, target)
end

local function ShouldFireByHealth(target)
    if IsLocalMasterMode() then
        local health = target.components and target.components.health
        return health == nil or health.currenthealth < FIRE_HP_THRESHOLD
    end

    if not ShowMeHealth:IsAvailable() then
        return true
    end

    local now = GetTime()
    ShowMeHealth:Request(target)
    local hp = target._wfa_hp
    if hp ~= nil and now - hp.time < 2 then
        target._wfa_hp_pending = nil
        return hp.current < FIRE_HP_THRESHOLD
    end

    target._wfa_hp_pending = target._wfa_hp_pending or now
    return now - target._wfa_hp_pending >= HP_RESPONSE_TIMEOUT
end

local function IsAttackPending()
    local sg = ThePlayer and ThePlayer.sg or nil
    return sg ~= nil and sg:HasStateTag("abouttoattack")
end

local function IsAttackCommitted()
    local sg = ThePlayer and ThePlayer.sg or nil
    return sg ~= nil
        and sg:HasStateTag("attack")
        and not sg:HasStateTag("abouttoattack")
end

local function IsAttacking()
    return TheInput ~= nil
        and (TheInput:IsControlPressed(CONTROL_ATTACK)
        or TheInput:IsControlPressed(CONTROL_CONTROLLER_ATTACK)
        )
end

local function SendHandAction(item, action)
    local player = ThePlayer
    local inventory = GetInventory()
    if player == nil or inventory == nil or item == nil or not item:IsValid() then
        return false
    end

    if IsLocalMasterMode() then
        local server_inventory = player.components.inventory
        if server_inventory == nil then
            return false
        end
        if action == ACTIONS.EQUIP then
            server_inventory:Equip(item)
            return server_inventory:GetEquippedItem(EQUIPSLOTS.HANDS) == item
        elseif action == ACTIONS.UNEQUIP
            and server_inventory:GetEquippedItem(EQUIPSLOTS.HANDS) == item then
            server_inventory:GiveItem(item)
            return server_inventory:GetEquippedItem(EQUIPSLOTS.HANDS) ~= item
        end
        return false
    elseif TheWorld.ismastersim then
        local server_inventory = player.components.inventory
        if server_inventory == nil then return false end
        local ok = pcall(
            server_inventory.ControllerUseItemOnSelfFromInvTile,
            server_inventory, item, action.code, action.mod_name
        )
        return ok
    end

    SendRPCToServer(RPC.ControllerUseItemOnSelfFromInvTile, action.code, item)
    return true
end

local state = {
    target = nil,
    last_attack = 0,
    acquired_at = 0,
    phase = "idle",
    fire_item = nil,
    saved_hand = nil,
    pending_since = nil,
    retries = 0,
    restore_after_equip = false,
    thread = nil,
}

local function ResetState(keep_thread)
    state.target = nil
    state.last_attack = 0
    state.acquired_at = 0
    state.phase = "idle"
    state.fire_item = nil
    state.saved_hand = nil
    state.pending_since = nil
    state.retries = 0
    state.restore_after_equip = false
    if not keep_thread then
        state.thread = nil
    end
end

local function SendRestore()
    if CanEquip(state.saved_hand) then
        return SendHandAction(state.saved_hand, ACTIONS.EQUIP)
    elseif state.fire_item ~= nil and state.fire_item:IsValid() then
        return SendHandAction(state.fire_item, ACTIONS.UNEQUIP)
    end
    return false
end

local function BeginRestore(now)
    if state.fire_item == nil
        or state.saved_hand == state.fire_item then
        ResetState(true)
        return
    end

    if state.phase == "equipping_fire" then
        state.restore_after_equip = true
        return
    end

    if GetHandItem() ~= state.fire_item then
        ResetState(true)
        return
    end

    state.phase = "waiting_restore"
    state.pending_since = now
    state.retries = 0
end

local function AbortPendingEquip()
    if state.fire_item ~= nil and GetHandItem() == state.fire_item then
        state.phase = "waiting_restore"
        state.pending_since = GetTime()
        state.retries = 0
        if SendRestore() then
            state.phase = "restoring"
        end
    else
        ResetState(true)
    end
end

local function UpdateWaitingAttack(now)
    if IsLocalMasterMode() then
        if not IsAttackCommitted() then
            return
        end
    else
        if IsAttackPending() or now - state.acquired_at < ATTACK_COMMIT_DELAY then
            return
        end
    end

    local target = state.target
    if not IsIgnitable(target) then
        ResetState(true)
        return
    end

    if not ShouldFireByHealth(target) then
        return
    end

    local lighter = FindWillowLighter()
    if lighter == nil then
        ResetState(true)
        return
    end

    state.saved_hand = GetHandItem()
    state.fire_item = lighter
    if state.saved_hand == lighter then
        state.phase = "fire"
    elseif SendHandAction(lighter, ACTIONS.EQUIP) then
        state.phase = "equipping_fire"
        state.pending_since = now
        state.retries = 0
    else
        ResetState(true)
    end
end

local function UpdateEquippingFire(now)
    if GetHandItem() == state.fire_item then
        state.pending_since = nil
        state.retries = 0
        if state.restore_after_equip then
            state.phase = "waiting_restore"
        else
            state.phase = "fire"
        end
        return
    end

    if not IsIgnitable(state.target) or now - state.last_attack > COMBAT_TIMEOUT then
        state.restore_after_equip = true
    end

    if now - state.pending_since < SWAP_TIMEOUT then
        return
    end

    if state.retries < MAX_SWAP_RETRIES and not IsAttackPending() then
        SendHandAction(state.fire_item, ACTIONS.EQUIP)
        state.pending_since = now
        state.retries = state.retries + 1
    else
        AbortPendingEquip()
    end
end

local function UpdateFire(now)
    if GetHandItem() ~= state.fire_item then
        ResetState(true)
    elseif not IsIgnitable(state.target) or now - state.last_attack > COMBAT_TIMEOUT then
        BeginRestore(now)
    end
end

local function RestoreSucceeded()
    if state.saved_hand == nil then
        return GetHandItem() ~= state.fire_item
    end
    if CanEquip(state.saved_hand) then
        return GetHandItem() == state.saved_hand
    end
    return GetHandItem() ~= state.fire_item
end

local function UpdateRestore(now)
    if RestoreSucceeded() then
        ResetState(true)
        return
    end

    if GetHandItem() ~= state.fire_item then
        ResetState(true)
        return
    end

    if state.phase == "waiting_restore" then
        if not IsAttackPending() and SendRestore() then
            state.phase = "restoring"
            state.pending_since = now
        end
        return
    end

    if now - state.pending_since >= SWAP_TIMEOUT then
        if IsAttackPending() then
            return
        end
        if SendRestore() then
            state.pending_since = now
            state.retries = state.retries + 1
        else
            state.pending_since = now
        end
    end
end

local function FireThread()
    local thread = state.thread
    Sleep(FRAMES)

    while state.thread == thread and ThePlayer ~= nil and ThePlayer.prefab == "willow" do
        local now = GetTime()
        if state.phase == "idle" then
            break
        end

        if IsAttacking() then
            state.last_attack = now
        end

        if state.phase == "waiting_attack" then
            if now - state.last_attack > COMBAT_TIMEOUT then
                ResetState(true)
            else
                UpdateWaitingAttack(now)
            end
        elseif state.phase == "equipping_fire" then
            UpdateEquippingFire(now)
        elseif state.phase == "fire" then
            UpdateFire(now)
        elseif state.phase == "waiting_restore" or state.phase == "restoring" then
            UpdateRestore(now)
        end

        Sleep(FRAMES)
    end

    if state.thread == thread then
        ResetState()
    end
end

AddComponentPostInit("playercontroller", function(self, inst)
    if self._willow_fire_attack_hooked or type(self.GetAttackTarget) ~= "function" then
        return
    end
    self._willow_fire_attack_hooked = true

    local old_get_attack_target = self.GetAttackTarget
    self.GetAttackTarget = function(controller, ...)
        local target = old_get_attack_target(controller, ...)
        if target ~= nil
            and type(target) == "table"
            and fire_attack_enabled
            and inst == ThePlayer
            and ThePlayer ~= nil
            and ThePlayer.prefab == "willow" then
            local now = GetTime()
            local changed = state.target ~= target
            state.target = target
            state.last_attack = now

            if state.thread == nil then
                state.phase = "waiting_attack"
                state.acquired_at = now
                state.thread = StartThread(FireThread, "willow_fire_attack")
            elseif state.phase == "waiting_attack" and changed then
                state.acquired_at = now
            end
        end
        return target
    end
end)

_G.WillowAssistSetFireAttackEnabled = function(value)
    fire_attack_enabled = value ~= false
    if fire_attack_enabled or state.phase == "idle" then
        return
    end

    if state.phase == "equipping_fire" then
        state.restore_after_equip = true
    elseif state.fire_item ~= nil and GetHandItem() == state.fire_item then
        state.phase = "waiting_restore"
        state.pending_since = GetTime()
        state.retries = 0
    else
        ResetState()
    end
end

_G.WillowAssistSetFireAttackThreshold = function(value)
    local threshold = tonumber(value)
    if threshold ~= nil then
        FIRE_HP_THRESHOLD = threshold
    end
end

AddPrefabPostInit("world", function(world)
    world:ListenForEvent("playeractivated", function(_, player)
        if player == ThePlayer then
            ResetState()
            ShowMeHealth.listener_added = false
        end
    end)
end)
