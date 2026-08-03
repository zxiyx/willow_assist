local quickcast_enabled = GetModConfigData("quickcast") ~= false
local continuous_spell_enabled = GetModConfigData("continuous_spell") ~= false
local continuous_quickcast_enabled = quickcast_enabled and continuous_spell_enabled
local fire_absorb_mode = GetModConfigData("willow_fire_absorb_mode") or "tap"
local current_spell

local function ShouldQuickcast()
    return quickcast_enabled and _G.TheWorld ~= nil
end

local function IsLocalMaster(player)
    local controller = player ~= nil
        and player.components ~= nil
        and player.components.playercontroller
        or nil
    return _G.TheWorld ~= nil
        and _G.TheWorld.ismastersim
        and controller ~= nil
        and controller.ismastersim
end

local function InGame()
    return ThePlayer and ThePlayer.HUD and not ThePlayer.HUD:HasInputFocus()
end

local function StringPath(...)
    local path = { ... }
    return function()
        local node = _G.STRINGS
        for i = 1, #path do
            node = node and node[path[i]]
        end
        return node
    end
end

local function ResolveString(value)
    return type(value) == "function" and value() or value
end

local function FindInItems(items, condition)
    for _, item in pairs(items or {}) do
        if item ~= nil and item:IsValid() and condition(item) then
            return item
        end
    end
end

local function FindItem(user, condition, include_equipped)
    if user == nil or not user:IsValid() or user.replica == nil or user.replica.inventory == nil then
        return nil
    end

    local fn = type(condition) == "string" and function(item) return item.prefab == condition end or condition
    local inventory = user.replica.inventory
    local item = FindInItems(inventory:GetItems(), fn)
    if item ~= nil then
        return item
    end

    local backpack = inventory:GetOverflowContainer()
    item = backpack ~= nil and FindInItems(backpack:GetItems(), fn) or nil
    if item ~= nil or include_equipped == false then
        return item
    end

    return FindInItems(inventory:GetEquips(), fn)
end

local function FindTargetedSpellBook(user)
	if user == nil or not user:IsValid() then return end
	return FindItem(user, function(item)
		if not item or not item:IsValid() or not item.replica then
			return false
		end
		return (user._targetbook == item.prefab or item:HasTag(user._targettag or ""))
		and item.replica.inventoryitem and item.replica.inventoryitem.classified
		and item.replica.inventoryitem.classified.percentused
		and item.replica.inventoryitem.classified.percentused:value() > 0
	end)
end

local function FindSpellByName(name, spellbook)
    name = ResolveString(name)
    if type(name) ~= "string" then
        return
    end
    spellbook = spellbook and spellbook.components and spellbook.components.spellbook
    if spellbook == nil or spellbook.items == nil then
        return
    end

    for k,v in pairs(spellbook.items) do
        if v.label == name then
            return k,v
        end
    end

    for k,v in pairs(spellbook.items) do
        local label = v.label:match(": (.+)") or v.label
        if label == name then
            return k,v
        end
    end

    name = name:lower()
    for k,v in pairs(spellbook.items) do
        if v.label:lower():find(name, 1, true) then
            return k,v
        end
    end

    return nil
end

local handler = {}
local callback = {}
local repeat_task = {}
local bound_key = {}
local key_owner = {}
local SINGLE_PRESS_BINDINGS = {
    willow_drop_bernie = true,
}
local PRESS_RELEASE_BINDINGS = {
    willow_fire_absorb = true,
}

local function UsesPressRelease(name)
    return PRESS_RELEASE_BINDINGS[name]
        or (continuous_quickcast_enabled and not SINGLE_PRESS_BINDINGS[name])
end

local function IsContinuousSpellBinding(name)
    return continuous_quickcast_enabled
        and not SINGLE_PRESS_BINDINGS[name]
        and not PRESS_RELEASE_BINDINGS[name]
end

local function RefreshContinuousSpellState()
    local active = false
    for _ in pairs(repeat_task) do
        active = true
        break
    end
    if _G.ThePlayer ~= nil then
        _G.ThePlayer.continuous_spell_active = active
    end
end

local function StopSpellRepeat(name, cancelled)
    if repeat_task[name] ~= nil then
        repeat_task[name]:Cancel()
        repeat_task[name] = nil
    end
    if callback[name] ~= nil then
        callback[name](false, cancelled)
    end
    RefreshContinuousSpellState()
end

local function StartSpellRepeat(name)
    if repeat_task[name] ~= nil or callback[name] == nil then return end

    local player = _G.ThePlayer
    if callback[name](true) == false then return end
    if player == nil then return end

    repeat_task[name] = player:DoPeriodicTask(2 * _G.FRAMES, function()
        if player ~= _G.ThePlayer or not InGame() then
            StopSpellRepeat(name, true)
        elseif callback[name] == nil or callback[name](true) == false then
            StopSpellRepeat(name, true)
        end
    end)
    RefreshContinuousSpellState()
end

local function StopAllSpellRepeats()
    local names = {}
    for name in pairs(repeat_task) do
        names[#names + 1] = name
    end
    for _, name in ipairs(names) do
        StopSpellRepeat(name, true)
    end
end

local function DispatchPressRelease(name, down)
    if IsContinuousSpellBinding(name) then
        if down then
            StartSpellRepeat(name)
        else
            StopSpellRepeat(name, false)
        end
    elseif callback[name] ~= nil then
        callback[name](down)
    end
end

local function KeyBind(name, key)
    local old_key = bound_key[name]
    if old_key ~= nil and key_owner[old_key] == name then
        key_owner[old_key] = nil
    end

    if handler[name] then
        if IsContinuousSpellBinding(name) then
            StopSpellRepeat(name, true)
        elseif PRESS_RELEASE_BINDINGS[name] and callback[name] then
            callback[name](false, true)
        end
        handler[name]:Remove()
        handler[name] = nil
    end

    if key ~= nil and key ~= -1 then
        local owner = key_owner[key]
        if owner ~= nil and owner ~= name then
            KeyBind(owner, nil)
        end
        bound_key[name] = key
        key_owner[key] = name

        if UsesPressRelease(name) then
            if key >= 1000 then
                handler[name] = _G.TheInput:AddMouseButtonHandler(function(button, down)
                    if button == key then
                        if callback[name] and (not down or InGame()) then
                            DispatchPressRelease(name, down)
                        end
                        return true
                    end
                    return false
                end)
            else
                handler[name] = _G.TheInput:AddKeyHandler(function(key_pressed, down)
                    if key_pressed == key
                        and callback[name]
                        and (not down or InGame()) then
                        DispatchPressRelease(name, down)
                    end
                end)
            end
            return
        end

        if key >= 1000 then
            handler[name] = _G.TheInput:AddMouseButtonHandler(function(button, down, x, y)
                if button == key then
                    if not down and InGame() and callback[name] then
                        callback[name]()
                    end
                    return true
                end
                return false
            end)
        else
            handler[name] = _G.TheInput:AddKeyUpHandler(key, function()
                if InGame() and callback[name] then
                    callback[name]()
                end
            end)
        end
    else
        bound_key[name] = nil
        handler[name] = nil
    end
end

local function RefreshSpellBindingModes()
    local bindings = {}
    for name, key in pairs(bound_key) do
        if not SINGLE_PRESS_BINDINGS[name] and not PRESS_RELEASE_BINDINGS[name] then
            bindings[#bindings + 1] = { name = name, key = key }
        end
    end
    for _, binding in ipairs(bindings) do
        KeyBind(binding.name, binding.key)
    end
end

_G.WeiluoKeyBind = KeyBind

local function GetLockedSpellTarget()
    local getter = _G.rawget(_G, "MYCMOD_GetLockedTarget")
    local target = getter and getter() or nil
    if target and target:IsValid() then
        return target
    end
    return nil
end

local FIRE_THROW_PULLBACK = 1.5

local function GetAimWorldPosition()
    local target = GetLockedSpellTarget()
    if target then
        return target:GetPosition()
    end
    return _G.TheInput:GetWorldPosition()
end

local function SendCastRPC(controller, action, book, spell_id, is_released)
    local pos = action and action.pos
    local point = pos and pos.local_pt
    if point == nil then return end

    local platform = pos.walkable_platform
    local controlmods = controller.EncodeControlMods and controller:EncodeControlMods() or nil
    _G.TheNet:SendRPCToServer(
        _G.RPC.LeftClick,
        _G.ACTIONS.CASTAOE.code,
        point.x,
        point.z,
        nil,
        is_released,
        controlmods,
        nil,
        _G.ACTIONS.CASTAOE.mod_name,
        platform,
        platform ~= nil,
        book,
        spell_id
    )
end

local function CastAOE(player, book, spell_id, x, z)
    local controller = player.components and player.components.playercontroller
    if controller == nil then return end

    local action = _G.BufferedAction(
        player,
        nil,
        _G.ACTIONS.CASTAOE,
        book,
        _G.Vector3(x, 0, z)
    )
    if action == nil then return end

    if IsLocalMaster(player) then
        local spellbook = book.components and book.components.spellbook
        if spellbook == nil then return end
        spellbook:SelectSpell(spell_id)
        controller:DoAction(action, book)
        return
    end

    if controller.locomotor ~= nil and controller:CanLocomote() then
        action.preview_cb = function()
            SendCastRPC(controller, action, book, spell_id, true)
        end
        controller:DoAction(action, book)
    else
        SendCastRPC(controller, action, book, spell_id)
    end
end

local function WillowBindCallback(spell_name)
    return function(down, cancelled)
        local player = _G.ThePlayer
        if continuous_quickcast_enabled and (not down or cancelled) then
            return true
        end

        if not InGame() or not _G.ThePlayer:HasTag("pyromaniac") then
            return false
        end

        local spell_name = ResolveString(spell_name)
        player = _G.ThePlayer
        local book = FindTargetedSpellBook(player)
        if not book then return false end

        local spell_id, spell = FindSpellByName(spell_name, book)
        if not spell then return false end

        if not ShouldQuickcast() then
            player.HUD:CloseSpellWheel()

            if current_spell == spell_name and player.components.playercontroller:IsAOETargeting() then
                player.components.playercontroller:CancelAOETargeting()
                return true
            end

            book.components.spellbook:SelectSpell(spell_id)
            spell.execute(book)
            current_spell = spell_name
        else
            if player:IsChannelCasting() then
                return true
            end

            local x, _, z = GetAimWorldPosition():Get()

            if spell_name == _G.STRINGS.PYROMANCY.FIRE_THROW then
                local ent = GetLockedSpellTarget() or _G.TheInput:GetWorldEntityUnderMouse()
                if ent then
                    x, _, z = ent.Transform:GetWorldPosition()
                    local px, _, pz = player.Transform:GetWorldPosition()
                    local dx, dz = x - px, z - pz
                    local dist = math.sqrt(dx * dx + dz * dz)
                    if dist > FIRE_THROW_PULLBACK then
                        local k = (dist - FIRE_THROW_PULLBACK) / dist
                        x, z = px + dx * k, pz + dz * k
                    end
                end
            elseif spell_name == _G.STRINGS.PYROMANCY.LUNAR_FIRE then
                local ent = GetLockedSpellTarget() or _G.TheInput:GetWorldEntityUnderMouse()
                if ent then x, _, z = ent.Transform:GetWorldPosition() end
                local cx, _, cz = player.Transform:GetWorldPosition()
                x = cx + (x - cx) * 0.5
                z = cz + (z - cz) * 0.5
            elseif spell_name == _G.STRINGS.PYROMANCY.FIRE_BURST or
                   spell_name == _G.STRINGS.PYROMANCY.FIRE_FRENZY or
                   spell_name == _G.STRINGS.PYROMANCY.SHADOW_FIRE then
                x, _, z = player.Transform:GetWorldPosition()
            end

            CastAOE(player, book, spell_id, x, z)
        end
        return true
    end
end

callback['willow_flame_cast'] = WillowBindCallback(StringPath("PYROMANCY", "FIRE_THROW"))
callback['willow_combustion'] = WillowBindCallback(StringPath("PYROMANCY", "FIRE_BURST"))
callback['willow_fireball'] = WillowBindCallback(StringPath("PYROMANCY", "FIRE_BALL"))
callback['willow_frenzy'] = WillowBindCallback(StringPath("PYROMANCY", "FIRE_FRENZY"))
callback['willow_lunar_fire'] = WillowBindCallback(StringPath("PYROMANCY", "LUNAR_FIRE"))
callback['willow_shadow_fire'] = WillowBindCallback(StringPath("PYROMANCY", "SHADOW_FIRE"))

callback['willow_drop_bernie'] = function()
    if not InGame() or not _G.ThePlayer:HasTag("pyromaniac") then return end

    local player = _G.ThePlayer
    local controller = player.components and player.components.playercontroller
    local bernie = FindItem(player, "bernie_inactive", false)
    if controller == nil or controller:IsBusy() or bernie == nil then return end

    controller:DoControllerDropItemFromInvTile(bernie)
end

local fire_absorb = {
    active = false,
    key_down = false,
    previous_equipment = nil,
    token = 0,
}

local function GetInvAction(player, item, right, code)
    local picker = player.components.playeractionpicker
    if picker == nil or item == nil then return end

    local actions = {}
    item:CollectActions("INVENTORY", player, actions, right)
    actions = picker:SortActionList(actions, nil, item)
    for _, action in ipairs(actions) do
        if action and action.action and (code == nil or action.action.id == code) then
            return action
        end
    end
end

local function DoAction(player, action, rpc, ...)
    local controller = player.components.playercontroller
    if controller == nil or action == nil then return false end

    if IsLocalMaster(player) then
        controller:DoAction(action)
        return true
    end

    if rpc == nil then return false end

    local args = {...}
    action.preview_cb = function()
        _G.TheNet:SendRPCToServer(rpc, (_G.unpack or table.unpack)(args))
    end
    if controller.locomotor then
        controller:DoAction(action)
    else
        action.preview_cb()
    end
    return true
end

local function FindEquippedLighter(player)
    local item = player.replica.inventory:GetEquippedItem(_G.EQUIPSLOTS.HANDS)
    return item ~= nil and item.prefab == "lighter" and item or nil
end

local function RememberHandItem(player)
    local item = player.replica.inventory:GetEquippedItem(_G.EQUIPSLOTS.HANDS)
    fire_absorb.previous_equipment = item ~= nil and item.prefab ~= "lighter" and item or nil
end

local function EquipItem(player, item)
    if item == nil or not item:IsValid() then return false end
    if IsLocalMaster(player) then
        local inventory = player.components and player.components.inventory
        if inventory == nil then return false end
        inventory:Equip(item)
    else
        _G.TheNet:SendRPCToServer(
            _G.RPC.ControllerUseItemOnSelfFromInvTile,
            _G.ACTIONS.EQUIP.code,
            item
        )
    end
    return true
end

local function RestorePreviousEquipment(player)
    local previous = fire_absorb.previous_equipment
    fire_absorb.previous_equipment = nil
    if previous ~= nil then
        local item = FindItem(player, function(candidate)
            return candidate == previous and candidate:IsValid()
        end)
        if item ~= nil then EquipItem(player, item) end
    end
end

local function DoChannelAction(player, lighter, action_id, rpc_fallback)
    local action = GetInvAction(player, lighter, true, action_id)
    if action ~= nil then
        return DoAction(player, action, _G.RPC.UseItemFromInvTile, action.action.code, action.invobject)
    end

    if rpc_fallback and not IsLocalMaster(player) then
        local action_type = _G.ACTIONS[action_id]
        if action_type ~= nil then
            _G.TheNet:SendRPCToServer(_G.RPC.UseItemFromInvTile, action_type.code, lighter)
            return true
        end
    end
    return false
end

local function StopFireAbsorb(player)
    if not fire_absorb.active and fire_absorb.previous_equipment == nil then return end

    fire_absorb.active = false
    fire_absorb.token = fire_absorb.token + 1

    if player ~= nil and player:IsValid() then
        local lighter = FindEquippedLighter(player) or FindItem(player, "lighter")
        if lighter ~= nil then
            DoChannelAction(player, lighter, "STOP_CHANNELCAST", true)
        end
        RestorePreviousEquipment(player)
    else
        fire_absorb.previous_equipment = nil
    end
end

local function StartFireAbsorb(player)
    if fire_absorb.active then return true end

    local lighter = FindItem(player, "lighter")
    if lighter == nil then return false end

    RememberHandItem(player)
    fire_absorb.active = true
    fire_absorb.token = fire_absorb.token + 1
    local token = fire_absorb.token

    if FindEquippedLighter(player) == nil and not EquipItem(player, lighter) then
        fire_absorb.active = false
        fire_absorb.previous_equipment = nil
        return false
    end

    local attempts = 0
    local function TryStart()
        if not fire_absorb.active
            or fire_absorb.token ~= token
            or not player:IsValid() then
            return
        end

        local equipped = FindEquippedLighter(player)
        if equipped ~= nil and player:IsChannelCasting() then
            return
        end

        attempts = attempts + 1
        if equipped ~= nil then
            DoChannelAction(player, equipped, "START_CHANNELCAST")
        end

        if attempts < 6 then
            player:DoTaskInTime(.1, TryStart)
        else
            fire_absorb.active = false
            fire_absorb.token = fire_absorb.token + 1
            RestorePreviousEquipment(player)
        end
    end

    TryStart()
    return true
end

callback['willow_fire_absorb'] = function(down, cancelled)
    if down then
        if fire_absorb.key_down
            or not InGame()
            or not _G.ThePlayer:HasTag("pyromaniac") then
            return
        end

        fire_absorb.key_down = true
        if fire_absorb_mode == "hold" then
            StartFireAbsorb(_G.ThePlayer)
        end
        return
    end

    if cancelled then
        fire_absorb.key_down = false
        StopFireAbsorb(_G.ThePlayer)
        return
    end

    if not fire_absorb.key_down then return end
    fire_absorb.key_down = false

    local player = _G.ThePlayer
    if fire_absorb_mode == "hold" then
        StopFireAbsorb(player)
        return
    end

    if fire_absorb.active then
        StopFireAbsorb(player)
    elseif InGame() and player:HasTag("pyromaniac") then
        StartFireAbsorb(player)
    end
end

local function ResetFireAbsorb()
    fire_absorb.active = false
    fire_absorb.key_down = false
    fire_absorb.previous_equipment = nil
    fire_absorb.token = fire_absorb.token + 1
end

_G.WillowAssistApplyRuntimeConfig = function(name, value)
    if name == "willow_fire_absorb_mode" then
        local mode = value == "hold" and "hold" or "tap"
        if mode ~= fire_absorb_mode then
            fire_absorb_mode = mode
            fire_absorb.key_down = false
            StopFireAbsorb(_G.ThePlayer)
        end
    elseif name == "quickcast" or name == "continuous_spell" then
        StopAllSpellRepeats()
        if name == "quickcast" then
            quickcast_enabled = value ~= false
        else
            continuous_spell_enabled = value ~= false
            if _G.WillowAssistSetContinuousSpellEnabled ~= nil then
                _G.WillowAssistSetContinuousSpellEnabled(continuous_spell_enabled)
            end
        end
        continuous_quickcast_enabled = quickcast_enabled and continuous_spell_enabled
        RefreshSpellBindingModes()
    elseif name == "fire_duration_display" and _G.WillowAssistSetFireDurationEnabled ~= nil then
        _G.WillowAssistSetFireDurationEnabled(value)
    elseif name == "willow_fire_attack" and _G.WillowAssistSetFireAttackEnabled ~= nil then
        _G.WillowAssistSetFireAttackEnabled(value)
    elseif name == "willow_fire_hp_threshold" and _G.WillowAssistSetFireAttackThreshold ~= nil then
        _G.WillowAssistSetFireAttackThreshold(value)
    end
end

local function SetupCharacter(player)
    ResetFireAbsorb()
    if player:HasTag("pyromaniac") then
        player._targetbook = "willow_ember"
        player._targettag = ""
    end

    player._targettag = player._targettag or ""
end

AddPlayerPostInit(function(inst)
    inst:DoTaskInTime(0, function()
        if inst == _G.ThePlayer then
            SetupCharacter(inst)
        end
    end)
end)

modimport('keybind')
