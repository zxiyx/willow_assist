local chinese = locale == "zh" or locale == "zhr" or locale == "zhs"

name = chinese and "薇洛辅助" or "Willow Assist"
description = chinese and
[[挂火攻击、快捷施法、快捷吸火、快捷丢熊、技能快捷键，以及燃烧时间显示。]]

author = "鸡腿饭"
version = "1.0.5"

forumthread = ""

api_version = 10

dont_starve_compatible = false
reign_of_giants_compatible = false
dst_compatible = true

client_only_mod = true
all_clients_require_mod = false

local enabled_options = {
    { description = chinese and "启用" or "Enabled", data = true },
    { description = chinese and "禁用" or "Disabled", data = false },
}

local keybind_options = {
    { description = chinese and "禁用" or "Disabled", data = "KEY_DISABLED" },
}

local function AddKey(data, description)
    keybind_options[#keybind_options + 1] = {
        description = description or data:sub(5),
        data = data,
    }
end

for i = 1, 12 do
    AddKey("KEY_F" .. i, "F" .. i)
end

local characters = "1234567890ABCDEFGHIJKLMNOPQRSTUVWXYZ"
for i = 1, #characters do
    local key = characters:sub(i, i)
    AddKey("KEY_" .. key, key)
end

local named_keys = {
    "TAB", "MINUS", "EQUALS", "SPACE", "ENTER", "ESCAPE", "HOME", "INSERT", "DELETE", "END",
    "PAUSE", "PRINT", "CAPSLOCK", "SCROLLOCK", "RSHIFT", "LSHIFT", "RCTRL", "LCTRL", "RALT", "LALT",
    "LSUPER", "RSUPER", "ALT", "CTRL", "SHIFT", "BACKSPACE", "PERIOD", "SLASH", "SEMICOLON",
    "LEFTBRACKET", "BACKSLASH", "RIGHTBRACKET", "TILDE", "UP", "DOWN", "RIGHT", "LEFT", "PAGEUP", "PAGEDOWN",
}
for i = 1, #named_keys do
    AddKey("KEY_" .. named_keys[i])
end

for i = 0, 9 do
    AddKey("KEY_KP_" .. i, "Numpad " .. i)
end
local numpad_keys = { "PERIOD", "DIVIDE", "MULTIPLY", "MINUS", "PLUS", "ENTER", "EQUALS" }
for i = 1, #numpad_keys do
    AddKey("KEY_KP_" .. numpad_keys[i], "Numpad " .. numpad_keys[i])
end

local mouse_keys = { '\238\132\128', '\238\132\129', '\238\132\130', '\238\132\131', '\238\132\132' }
for i = 1, #mouse_keys do
    keybind_options[#keybind_options + 1] = { description = mouse_keys[i], data = mouse_keys[i] }
end

configuration_options = {
    {
        name = "HEADER_GENERAL",
        label = chinese and "常规设置" or "General Settings",
        options = {{description="",data=0}},
        default = 0,
    },
    {
        name = "quickcast",
        label = chinese and "快速施法" or "Quick Cast",
        hover = chinese and "允许快捷键直接施法，跳过目标选择" or "Allows hotkeys to cast spells instantly, skipping targeting",
        options = enabled_options,
        default = true,
    },
    {
        name = "continuous_spell",
        label = chinese and "连续施法" or "Continuous Spell",
        hover = chinese and "施法后自动重新进入瞄准状态(右键取消)；快速施法模式下长按快捷键连续施法" or "Auto re-enter targeting after casting (RMB to cancel); Hold hotkey to cast continuously in quick cast mode",
        options = enabled_options,
        default = true,
    },
    {
        name = "fire_duration_display",
        label = chinese and "火焰燃烧显示" or "Fire Duration Display",
        hover = chinese and "显示燃烧物、光源（火球/矮星）等的剩余时间" or "Show remaining time for burning objects, fire pits, lanterns, Dwarf Stars and Polar Lights",
        options = enabled_options,
        default = true,
    },
    {
        name = "willow_fire_attack",
        label = chinese and "挂火打架" or "Fire Attack",
        hover = chinese and "攻击可燃烧目标时自动切换点火道具" or "Auto-switch to fire tool when attacking burnable targets",
        options = enabled_options,
        default = true,
    },
    {
        name = "willow_fire_hp_threshold",
        label = chinese and "挂火血量" or "Fire Attack HP Limit",
        hover = chinese and "目标当前血量低于此值才会自动挂火 (需要服务器安装显血类模组, 否则一律挂火)" or "Only auto fire-attack targets below this HP (requires a server-side HP display mod, otherwise always applies)",
        options = {
            { description = "200", data = 200 },
            { description = "250", data = 250 },
            { description = "300", data = 300 },
            { description = "350", data = 350 },
            { description = "400", data = 400 },
            { description = "450", data = 450 },
            { description = "500", data = 500 },
        },
        default = 200,
    },
    {
        name = "willow_fire_absorb_mode",
        label = chinese and "吸火模式" or "Quick Fire Absorb Mode",
        options = {
            { description = chinese and "点按吸火" or "Tap", data = "tap" },
            { description = chinese and "长按吸火" or "Hold", data = "hold" },
        },
        default = "tap",
    },
    { 
        name = "HEADER_HOTKEYS",
        label = chinese and "快捷键设置" or "Hotkeys (click, then press a key)",
        options = {{description="",data=0}},
        default = 0 
    },
    { name = "willow_drop_bernie", label = chinese and "快捷丢熊" or "Drop Bernie", options = keybind_options, default = "KEY_DISABLED" },
    { name = "willow_fire_absorb", label = chinese and "快速吸火" or "Quick Fire Absorb", options = keybind_options, default = "KEY_DISABLED" },
    { name = "willow_flame_cast", label = chinese and "火焰投掷" or "Flame Cast", options = keybind_options, default = "KEY_DISABLED" },
    { name = "willow_combustion", label = chinese and "燃烧术" or "Combustion", options = keybind_options, default = "KEY_DISABLED" },
    { name = "willow_fireball", label = chinese and "火球术" or "Fire Ball", options = keybind_options, default = "KEY_DISABLED" },
    { name = "willow_frenzy", label = chinese and "狂热焚烧" or "Burning Frenzy", options = keybind_options, default = "KEY_DISABLED" },
    { name = "willow_lunar_fire", label = chinese and "月焰纵火犯" or "Lunar Flame", options = keybind_options, default = "KEY_DISABLED" },
    { name = "willow_shadow_fire", label = chinese and "暗影纵火犯" or "Shadow Fire", options = keybind_options, default = "KEY_DISABLED" },
    
}
