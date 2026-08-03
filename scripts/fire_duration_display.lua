local FollowText = require("widgets/followtext")

local display_enabled = GetModConfigData("fire_duration_display") ~= false
local UPDATE_PERIOD = 0.2
local SMOOTH_UPDATE_PERIOD = 0.1
local TOTAL_DAY_TIME = TUNING.TOTAL_DAY_TIME or 480
local TEXT_SIZE = 30
local BURN_TARGET_SEARCH_RADIUS = 0.1
local MAX_DISPLAY_DISTANCE_SQ = 40 * 40
local updater_states = setmetatable({}, { __mode = "k" })
local locale_code = LOC ~= nil and LOC.GetLocaleCode ~= nil and LOC.GetLocaleCode() or ""
local BURNING_LABEL = string.sub(locale_code, 1, 2) == "zh" and "燃烧中" or "Burning"

local function Clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function IsValid(inst)
    return inst ~= nil and inst.IsValid ~= nil and inst:IsValid()
end

local function HideWidget(state)
    if state.widget ~= nil and state.widget:IsVisible() then
        state.widget:Hide()
    end
end

local function MakeWidget(state, target, offset)
    if state.widget ~= nil then
        if IsValid(target) then
            state.widget:SetTarget(target)
        end
        return state.widget
    end

    local player = ThePlayer
    if player == nil or player.HUD == nil or player.HUD.overlayroot == nil or not IsValid(target) then
        return nil
    end

    local widget = player.HUD.overlayroot:AddChild(FollowText(BODYTEXTFONT, TEXT_SIZE))
    widget:SetHUD(player.HUD.inst)
    widget:SetOffset(offset)
    widget:SetTarget(target)
    state.widget = widget
    return widget
end

local function Cleanup(state)
    if state.cleaned then
        return
    end
    state.cleaned = true
    updater_states[state] = nil
    if state.task ~= nil then
        state.task:Cancel()
        state.task = nil
    end
    if state.widget ~= nil then
        state.widget:Kill()
        state.widget = nil
    end
end

local function IsNearPlayer(inst)
    local player = ThePlayer
    if player == nil or player.Transform == nil or inst.Transform == nil then
        return false
    end
    return player:GetDistanceSqToInst(inst) <= MAX_DISPLAY_DISTANCE_SQ
end

local function StartUpdaterTask(state)
    if state.cleaned or state.task ~= nil or not display_enabled or not IsValid(state.inst) then
        return
    end

    local function Update()
        local inst = state.inst
        if not IsValid(inst) then
            Cleanup(state)
            return
        end
        if not display_enabled or not IsNearPlayer(inst) then
            HideWidget(state)
            return
        end

        local ok, err = pcall(state.updatefn, inst, state)
        if not ok then
            print("[Willow Assist] Fire duration display stopped for " .. tostring(inst.prefab) .. ": " .. tostring(err))
            Cleanup(state)
        end
    end

    state.task = state.inst:DoPeriodicTask(state.period, Update, 0)
end

local function StartSafeUpdater(inst, state, updatefn, period)
    state.inst = inst
    state.updatefn = updatefn
    state.period = period or UPDATE_PERIOD
    updater_states[state] = true

    inst:ListenForEvent("onremove", function()
        Cleanup(state)
    end)
    StartUpdaterTask(state)
end

local function FindNearest(inst, radius, predicate)
    if TheSim == nil or inst.Transform == nil then
        return nil
    end

    local x, y, z = inst.Transform:GetWorldPosition()
    local nearest = nil
    local nearest_distance = nil
    for _, candidate in ipairs(TheSim:FindEntities(x, y, z, radius)) do
        if candidate ~= inst and IsValid(candidate) and predicate(candidate) then
            local cx, cy, cz = candidate.Transform:GetWorldPosition()
            local distance = (cx - x) * (cx - x) + (cy - y) * (cy - y) + (cz - z) * (cz - z)
            if nearest_distance == nil or distance < nearest_distance then
                nearest = candidate
                nearest_distance = distance
            end
        end
    end
    return nearest
end

local SMALL_BURNTIME = TUNING.SMALL_BURNTIME or 7.5
local MED_BURNTIME = TUNING.MED_BURNTIME or 15
local LARGE_BURNTIME = TUNING.LARGE_BURNTIME or 30
local TREE_BURN_TIME = TUNING.TREE_BURN_TIME or 45
local TREE_STAGES = { "short", "normal", "tall" }

local STANDARD_BURN_TIME_BY_LEVEL = {
    [2] = 10,
    [3] = 20,
    [4] = 30,
}

local PREFAB_BURN_TIMES = {
    acorn_sapling = SMALL_BURNTIME,
    blueprint = SMALL_BURNTIME,
    boards = LARGE_BURNTIME,
    charcoal = MED_BURNTIME,
    cutgrass = SMALL_BURNTIME,
    driftwood_log = MED_BURNTIME,
    livingtree_root = SMALL_BURNTIME,
    livingtree_root_planted = SMALL_BURNTIME,
    livinglog = MED_BURNTIME,
    log = MED_BURNTIME,
    magician_chest = 10,
    oceanvine_cocoon = 15,
    lumpy_sapling = SMALL_BURNTIME,
    moonbutterfly_sapling = SMALL_BURNTIME,
    palmcone_sapling = SMALL_BURNTIME,
    pinecone = SMALL_BURNTIME,
    pinecone_sapling = SMALL_BURNTIME,
    portablefirepit = 30,
    propsign = 5,
    resurrectionstatue = 10,
    rope = LARGE_BURNTIME,
    sapling = 20,
    sapling_moon = 20,
    seeds = SMALL_BURNTIME,
    spore_medium = 1,
    spore_moon = 1,
    spore_small = 1,
    spore_tall = 1,
    stagehand = 10,
    stageusher = 10,
    tumbleweed = 10,
    tree_rock_sapling = SMALL_BURNTIME,
    twigs = SMALL_BURNTIME,
    twiggy_nut_sapling = SMALL_BURNTIME,
    winona_teleport_pad = 20,
    winter_treestand = 20,
}

local RANDOM_BURN_TIMES = {
    gunpowder = { 3, 6 },
    slurtleslime = { 3, 6 },
}

local function GetFireLevel(inst)
    if inst.AnimState == nil then
        return nil
    end
    for level = 1, 6 do
        if inst.AnimState:IsCurrentAnimation("level" .. level)
            or inst.AnimState:IsCurrentAnimation("level" .. level .. "_controlled_burn") then
            return level
        end
    end
    return nil
end

local function FindBurningTarget(inst)
    if IsValid(inst.parent) and not inst.parent:HasTag("FX") then
        return inst.parent
    end

    return FindNearest(inst, BURN_TARGET_SEARCH_RADIUS, function(candidate)
        return candidate.prefab ~= nil and not candidate:HasTag("FX") and candidate:HasTag("fire")
    end)
end

local function StartsWith(value, prefix)
    return value ~= nil and string.sub(value, 1, #prefix) == prefix
end

local function EndsWith(value, suffix)
    return value ~= nil and string.sub(value, -#suffix) == suffix
end

local function GetServerBurnTime(target)
    local burnable = target.components ~= nil and target.components.burnable or nil
    if burnable == nil or type(burnable.burntime) ~= "number" then
        return nil
    end

    local task = burnable.task
    if task ~= nil and type(GetTaskRemaining) == "function" then
        local ok, remaining = pcall(GetTaskRemaining, task)
        if ok and type(remaining) == "number" then
            return math.max(0, remaining)
        end
    end

    local multiplier = 1
    if burnable.controlled_burn ~= nil
        and target.components.health ~= nil
        and burnable.CalculateControlledBurnDuration ~= nil then
        multiplier = burnable:CalculateControlledBurnDuration() or 1
    end
    return burnable.burntime * multiplier
end

local function GetTreeBurnTime(target, level)
    local prefab = target.prefab
    local is_moon_tree = StartsWith(prefab, "moon_tree")
    local is_palmcone_tree = StartsWith(prefab, "palmconetree")

    if is_moon_tree or is_palmcone_tree then
        local stage = EndsWith(prefab, "_short") and "short"
            or EndsWith(prefab, "_normal") and "normal"
            or EndsWith(prefab, "_tall") and "tall"
            or nil
        if stage == nil and target.AnimState ~= nil then
            for _, name in ipairs(TREE_STAGES) do
                if target.AnimState:IsCurrentAnimation("burning_loop_" .. name) then
                    stage = name
                    break
                end
            end
        end
        stage = stage or (level == 2 and "short" or level == 3 and "normal" or "tall")

        if target:HasTag("stump") then
            return stage == "short" and 10 or stage == "normal" and 20 or 30
        end
        return stage == "short" and TREE_BURN_TIME / 2
            or stage == "normal" and TREE_BURN_TIME
            or TREE_BURN_TIME * 1.5
    end

    if StartsWith(prefab, "tree_rock") then
        return TUNING.TREE_ROCK ~= nil and TUNING.TREE_ROCK.BURN_TIME or 3
    elseif prefab == "mushroomsprout" then
        return TREE_BURN_TIME
    elseif StartsWith(prefab, "winter_") then
        return level == 4 and TREE_BURN_TIME or 20
    elseif target:HasTag("stump") then
        return 10
    elseif StartsWith(prefab, "evergreen")
        or StartsWith(prefab, "twiggytree")
        or StartsWith(prefab, "twiggy_")
        or StartsWith(prefab, "deciduoustree")
        or StartsWith(prefab, "oceantree") then
        return TREE_BURN_TIME
    elseif prefab == "cave_banana_tree" then
        return 20
    elseif prefab == "marsh_tree"
        or StartsWith(prefab, "livingtree")
        or StartsWith(prefab, "mushtree")
        or StartsWith(prefab, "driftwood_") then
        return 30
    end
end

local function GetBurnTime(target, level)
    local exact = GetServerBurnTime(target)
    if exact ~= nil then
        return exact, exact
    end

    local prefab = target.prefab
    local random = RANDOM_BURN_TIMES[prefab]
    if random ~= nil then
        return random[1], random[2]
    end

    local fixed = PREFAB_BURN_TIMES[prefab]
    if fixed ~= nil then
        return fixed, fixed
    elseif StartsWith(prefab, "turf_") then
        return MED_BURNTIME, MED_BURNTIME
    elseif prefab == "spiderden" then
        fixed = level == 4 and 30 or 20
    elseif target:HasTag("tree") or target:HasTag("stump") or prefab == "mushroomsprout" then
        fixed = GetTreeBurnTime(target, level)
    end

    fixed = fixed or STANDARD_BURN_TIME_BY_LEVEL[level]
    return fixed, fixed
end

local function ResetBurningObject(state, target, level)
    state.target = target
    state.level = level
    state.minimum, state.maximum = GetBurnTime(target, level)
    state.started = GetTime()
end

local function UpdateBurningObject(inst, state)
    local target = IsValid(state.target) and state.target or FindBurningTarget(inst)
    local level = state.level or GetFireLevel(inst)
    if target == nil or level == nil then
        HideWidget(state)
        return
    end

    if target ~= state.target or state.minimum == nil then
        ResetBurningObject(state, target, level)
    else
        state.level = level
        local exact = GetServerBurnTime(target)
        if exact ~= nil then
            state.minimum = exact
            state.maximum = exact
            state.started = GetTime()
        end
    end

    if state.minimum == nil then
        HideWidget(state)
        return
    end

    local elapsed = GetTime() - state.started
    local minimum = math.max(0, state.minimum - elapsed)
    local maximum = math.max(0, state.maximum - elapsed)
    local widget = MakeWidget(state, inst, Vector3(0, -100, 0))
    if widget == nil then
        return
    end

    widget.text:SetString(maximum <= 0
        and BURNING_LABEL
        or minimum == maximum and string.format("%.2fs", maximum)
        or string.format("%.1f-%.1fs", minimum, maximum))
    if maximum > 12 then
        widget.text:SetColour(1, 1, 1, 1)
    else
        local danger = 1 - maximum / 12
        widget.text:SetColour(1, Clamp(1 - danger * 0.8, 0.2, 1), Clamp(1 - danger, 0, 1), 1)
    end
    if not widget:IsVisible() then
        widget:Show()
    end
end

local function AddBurningObjectTimer(inst)
    StartSafeUpdater(inst, {}, UpdateBurningObject, SMOOTH_UPDATE_PERIOD)
end

local function WalterTuning(name, fallback)
    local skills = TUNING.SKILLS
    local walter = skills ~= nil and skills.WALTER or nil
    return walter ~= nil and walter[name] or fallback
end

local STANDARD_FIRE_LEVELS = {
    { anim = "level1", radius = 2 },
    { anim = "level2", radius = 3 },
    { anim = "level3", radius = 4 },
    { anim = "level4", radius = 5 },
}

local COLD_FIRE_LEVELS = {
    { anim = "level1_redux", radius = 2 },
    { anim = "level2_redux", radius = 3 },
    { anim = "level3_redux", radius = 4 },
    { anim = "level4_redux", radius = 5 },
}

local PORTABLE_FIRE_LEVELS = {
    { anim = "level1", radius = 2.5 },
    { anim = "level1a", radius = 3 },
    { anim = "level2", radius = 3.5 },
}

local CAMPFIRE_SPECS = {
    campfire = { maxfuel = TUNING.CAMPFIRE_FUEL_MAX or 90, rainrate = TUNING.CAMPFIRE_RAIN_RATE or 2.5, levels = STANDARD_FIRE_LEVELS },
    firepit = { maxfuel = TUNING.FIREPIT_FUEL_MAX or 120, rainrate = TUNING.FIREPIT_RAIN_RATE or 2, levels = STANDARD_FIRE_LEVELS },
    coldfire = { maxfuel = TUNING.COLDFIRE_FUEL_MAX or 90, rainrate = TUNING.COLDFIRE_RAIN_RATE or 2.5, levels = COLD_FIRE_LEVELS },
    coldfirepit = { maxfuel = TUNING.COLDFIREPIT_FUEL_MAX or 120, rainrate = TUNING.COLDFIREPIT_RAIN_RATE or 2, levels = COLD_FIRE_LEVELS },
    nightlight = { maxfuel = TUNING.NIGHTLIGHT_FUEL_MAX or 180, rainrate = 0, levels = STANDARD_FIRE_LEVELS },
    portablefirepit = {
        maxfuel = WalterTuning("PORTABLE_FIREPIT_FUEL_MAX", 90),
        rainrate = WalterTuning("PORTABLE_FIREPIT_RAIN_RATE", 2.5),
        levels = PORTABLE_FIRE_LEVELS,
    },
}

local function FindCampfireTarget(inst)
    return FindNearest(inst, 2.5, function(candidate)
        return CAMPFIRE_SPECS[candidate.prefab] ~= nil
    end)
end

local function FindLightSource(inst)
    return FindNearest(inst, 0.75, function(candidate)
        return candidate.Light ~= nil and candidate:HasTag("lightsource")
    end)
end

local function GetFuelPercent(inst, light, levels)
    if inst.AnimState == nil or light == nil or light.Light == nil then
        return nil
    end

    local radius = light.Light:GetRadius()
    for index, level in ipairs(levels) do
        if inst.AnimState:IsCurrentAnimation(level.anim) then
            local low_radius = index == 1 and 0 or levels[index - 1].radius
            local range = level.radius - low_radius
            local section = range > 0 and Clamp((radius - low_radius) / range, 0, 1) or 0
            return Clamp((index - 1 + section) / #levels, 0, 1)
        end
    end
    return nil
end

local function GetWeatherFuelRate(rainrate)
    local world = TheWorld
    local state = world ~= nil and world.state or nil
    if rainrate > 0 and state ~= nil and state.israining then
        return 1 + rainrate * Clamp(state.precipitationrate or 0, 0, 1)
    end
    return 1
end

local function UpdateCampfire(inst, state)
    state.target = IsValid(state.target) and state.target or FindCampfireTarget(inst)
    if state.target == nil then
        HideWidget(state)
        return
    end

    local spec = CAMPFIRE_SPECS[state.target.prefab]
    state.light = IsValid(state.light) and state.light or FindLightSource(inst)
    local percent = GetFuelPercent(inst, state.light, spec.levels)
    if percent == nil then
        HideWidget(state)
        return
    end

    local widget = MakeWidget(state, inst, Vector3(9, inst.prefab == "coldfirefire" and -155 or -90, 0))
    if widget == nil then
        return
    end

    local seconds = spec.maxfuel * percent / GetWeatherFuelRate(spec.rainrate)
    widget.text:SetString(string.format("%d%%\n%d:%02d", math.ceil(percent * 100), math.floor(seconds / 60), math.floor(seconds % 60)))
    if not widget:IsVisible() then
        widget:Show()
    end
end

local function AddCampfireTimer(inst)
    StartSafeUpdater(inst, {}, UpdateCampfire)
end

local function UpdateLantern(inst, state)
    if inst.Light == nil then
        HideWidget(state)
        return
    end

    local percent = Clamp((inst.Light:GetRadius() - 3) / 2, 0, 1)
    local widget = MakeWidget(state, inst, Vector3(9, -110, 0))
    if widget == nil then
        return
    end

    local seconds = (TUNING.LANTERN_LIGHTTIME or 156) * percent
    widget.text:SetString(string.format("%d%%\n%d:%02d", math.ceil(percent * 100), math.floor(seconds / 60), math.floor(seconds % 60)))
    if not widget:IsVisible() then
        widget:Show()
    end
end

local function AddLanternTimer(inst)
    StartSafeUpdater(inst, {}, UpdateLantern)
end

local function UpdateStar(inst, state)
    local pulse = inst._pulsetime ~= nil and inst._pulsetime:value() or 0
    if pulse ~= state.pulse then
        state.pulse = pulse
        state.correction = inst:GetTimeAlive()
    end

    local remaining = state.duration - pulse - (inst:GetTimeAlive() - state.correction)
    if remaining < 0 then
        HideWidget(state)
        return
    end

    local widget = MakeWidget(state, inst, Vector3(9, -240, 0))
    if widget == nil then
        return
    end

    widget.text:SetString(string.format("%.1f d\n%d:%02d", remaining / TOTAL_DAY_TIME, math.floor(remaining / 60), math.floor(remaining % 60)))
    if inst.prefab == "staffcoldlight" then
        widget.text:SetColour(0.55, 0.75, 1, 1)
    elseif inst.prefab == "emberlight" then
        widget.text:SetColour(1, 0.55, 0.15, 1)
    else
        widget.text:SetColour(1, 0.85, 0.3, 1)
    end
    if not widget:IsVisible() then
        widget:Show()
    end
end

local function AddStarTimer(inst)
    local duration = TUNING.OPALSTAFF_STAR_DURATION or TOTAL_DAY_TIME * 2
    if inst.prefab == "stafflight" then
        duration = TUNING.YELLOWSTAFF_STAR_DURATION or TOTAL_DAY_TIME * 3.5
    elseif inst.prefab == "emberlight" then
        duration = TUNING.EMBER_STAR_DURATION or TOTAL_DAY_TIME
    end

    local state = {
        pulse = inst._pulsetime ~= nil and inst._pulsetime:value() or 0,
        correction = 0,
        duration = duration,
    }
    StartSafeUpdater(inst, state, UpdateStar)
end

AddPrefabPostInit("fire", AddBurningObjectTimer)
AddPrefabPostInit("campfirefire", AddCampfireTimer)
AddPrefabPostInit("coldfirefire", AddCampfireTimer)
AddPrefabPostInit("nightlight_flame", AddCampfireTimer)
AddPrefabPostInit("portable_campfirefire", AddCampfireTimer)
AddPrefabPostInit("lanternlight", AddLanternTimer)
AddPrefabPostInit("stafflight", AddStarTimer)
AddPrefabPostInit("staffcoldlight", AddStarTimer)
AddPrefabPostInit("emberlight", AddStarTimer)

_G.WillowAssistSetFireDurationEnabled = function(value)
    display_enabled = value ~= false
    for state in pairs(updater_states) do
        if display_enabled then
            StartUpdaterTask(state)
        else
            if state.task ~= nil then
                state.task:Cancel()
                state.task = nil
            end
            HideWidget(state)
        end
    end
end
