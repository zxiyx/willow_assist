GLOBAL.setmetatable(env, {__index = function(t, k) return GLOBAL.rawget(GLOBAL, k) end})

modimport("scripts/continuous_spell.lua")
modimport("scripts/willow_keybind.lua")
modimport("scripts/willow_fire_attack.lua")
modimport("scripts/fire_duration_display.lua")
