local continuous_spell_enabled = GetModConfigData("continuous_spell") ~= false

local function SetContinuousSpell(active)
    if ThePlayer then
        ThePlayer.continuous_spell_active = active
    end
end

AddComponentPostInit("aoetargeting", function(self)
    local old_CanRepeatCast = self.CanRepeatCast
    local old_ShouldRepeatCast = self.ShouldRepeatCast

    self.CanRepeatCast = function(self)
        if continuous_spell_enabled and ThePlayer and ThePlayer.continuous_spell_active then
            return true
        end
        return old_CanRepeatCast ~= nil and old_CanRepeatCast(self) or false
    end

    self.ShouldRepeatCast = function(self, doer)
        if continuous_spell_enabled and ThePlayer and ThePlayer.continuous_spell_active then
            return true
        end
        return old_ShouldRepeatCast ~= nil and old_ShouldRepeatCast(self, doer) or false
    end
end)

_G.WillowAssistSetContinuousSpellEnabled = function(value)
    continuous_spell_enabled = value ~= false
    if not continuous_spell_enabled then
        SetContinuousSpell(false)
    end
end

AddComponentPostInit("playercontroller", function(self)
    local old_OnRightClick = self.OnRightClick
    self.OnRightClick = function(self, ...)
        if self.inst == ThePlayer and self:IsAOETargeting() then
            SetContinuousSpell(false)
        end
        return old_OnRightClick(self, ...)
    end

    local old_OnLeftClick = self.OnLeftClick
    self.OnLeftClick = function(self, ...)
        if self.inst == ThePlayer and self:IsAOETargeting() then
            SetContinuousSpell(true)
        elseif self.inst == ThePlayer and ThePlayer and ThePlayer.continuous_spell_active then
            SetContinuousSpell(false)
        end
        return old_OnLeftClick(self, ...)
    end

    local old_CancelAOETargeting = self.CancelAOETargeting
    if old_CancelAOETargeting then
        self.CancelAOETargeting = function(self, ...)
            if self.inst == ThePlayer then
                SetContinuousSpell(false)
            end
            return old_CancelAOETargeting(self, ...)
        end
    end
end)

AddPlayerPostInit(function(inst)
    inst:DoTaskInTime(0, function()
        if inst == ThePlayer then
            SetContinuousSpell(false)
        end
    end)
end)
