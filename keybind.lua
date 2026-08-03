local G = GLOBAL
local C = G.UICOLOURS
local S = G.STRINGS.UI.CONTROLSSCREEN

local Widget = require('widgets/widget')
local Image = require('widgets/image')
local ImageButton = require('widgets/imagebutton')
local PopupDialogScreen = require('screens/redux/popupdialog')
local Text = require('widgets/text')
local TEMPLATES = require('widgets/redux/templates')
local OptionsScreen = require('screens/redux/optionsscreen')

local MOUSE_BINDINGS = {
  { name = '\238\132\128', code = 1000 },
  { name = '\238\132\129', code = 1001 },
  { name = '\238\132\130', code = 1002 },
  { name = '\238\132\131', code = 1005 },
  { name = '\238\132\132', code = 1006 },
}

local KEYBIND_NAMES = {
  willow_fire_absorb = true,
  willow_flame_cast = true,
  willow_combustion = true,
  willow_fireball = true,
  willow_frenzy = true,
  willow_lunar_fire = true,
  willow_shadow_fire = true,
  willow_drop_bernie = true,
}

local code_by_name = {}
local name_by_code = {}
for name, code in pairs(G) do
  if type(name) == 'string' and name:match('^KEY_') and type(code) == 'number' then
    code_by_name[name] = code
    name_by_code[code] = name
  end
end
for _, binding in ipairs(MOUSE_BINDINGS) do
  code_by_name[binding.name] = binding.code
  name_by_code[binding.code] = binding.name
end

local function Raw(name) return code_by_name[name] end
local function Stringify(code) return name_by_code[code] end

-- "KEY_*" and mouse button emoji => name or "- No Bind -"
local function Localize(key)
  local num = Raw(key)
  local label = num and S.INPUTS[1] and S.INPUTS[1][num] or nil
  return label or (num and key) or S.INPUTS[9][2]
end

local control_entries = {}
local keybind_configs = {}
local is_keybind = {}
local is_header = {}
for _, config in ipairs(modinfo.configuration_options) do
  if KEYBIND_NAMES[config.name] then
    is_keybind[config.name] = true
    table.insert(keybind_configs, config)
  elseif config.name and config.name:match('^HEADER_') then
    is_header[config.name] = true
  end
  table.insert(control_entries, config)
end

AddGamePostInit(function()
  for _, config in ipairs(keybind_configs) do
    _G.WeiluoKeyBind(config.name, Raw(GetModConfigData(config.name)))
  end
end)

-- Adapted from screens/redux/optionsscreen.lua: BuildControlGroup()
local BindButton = Class(Widget, function(self, param)
  Widget._ctor(self, modname .. ':KeyBindButton')
  self.title = param.title
  self.default = param.default
  self.initial = param.initial
  self.OnSet = param.OnSet
  self.OnChanged = param.OnChanged

  self.changed_image = self:AddChild(Image('images/global_redux.xml', 'wardrobe_spinner_bg.tex'))
  self.changed_image:ScaleToSize(param.width, param.height)
  self.changed_image:SetTint(1, 1, 1, 0.3)
  self.changed_image:Hide()

  self.binding_btn = self:AddChild(ImageButton('images/global_redux.xml', 'blank.tex', 'spinner_focus.tex'))
  self.binding_btn:SetOnClick(function() self:PopupKeyBindDialog() end)
  self.binding_btn:ForceImageSize(param.width, param.height)
  self.binding_btn:SetText(Localize(param.initial))
  self.binding_btn:SetTextSize(param.text_size or 30)
  self.binding_btn:SetTextColour(param.text_color or C.GOLD_CLICKABLE)
  self.binding_btn:SetTextFocusColour(C.GOLD_FOCUS)
  self.binding_btn:SetFont(G.CHATFONT)

  self.unbinding_btn = self:AddChild(ImageButton('images/global_redux.xml', 'close.tex', 'close.tex'))
  self.unbinding_btn:SetPosition(param.width / 2 + (param.offset or 10), 0)
  self.unbinding_btn:SetOnClick(function() self:Set('KEY_DISABLED') end)
  self.unbinding_btn:SetHoverText(S.UNBIND)
  self.unbinding_btn:SetScale(0.4, 0.4)

  self.focus_forward = self.binding_btn
end)

function BindButton:Set(key)
  self.binding_btn:SetText(Localize(key))
  self.OnSet(key)
  if key == self.initial then
    self.changed_image:Hide()
  else
    self.OnChanged()
    self.changed_image:Show()
  end
end

function BindButton:PopupKeyBindDialog()
  local function Setup(key)
    self:Set(key)
    TheFrontEnd:PopScreen()
    TheFrontEnd:GetSound():PlaySound('dontstarve/HUD/click_move')
  end
  local buttons = {}
  for _, binding in ipairs(MOUSE_BINDINGS) do
    local key = binding.name
    table.insert(buttons, { text = key, cb = function() Setup(key) end })
  end
  table.insert(buttons, { text = S.CANCEL, cb = function() TheFrontEnd:PopScreen() end })
  local text = S.CONTROL_SELECT .. '\n\n' .. string.format(S.DEFAULT_CONTROL_TEXT, Localize(self.default))
  local dialog = PopupDialogScreen(self.title, text, buttons)

  dialog.OnRawKey = function(_, keycode, down)
    local key = Stringify(keycode)
    if not key or down then return end
    Setup(key)
    return true
  end

  TheFrontEnd:PushScreen(dialog)
end

local BUTTON_NAME = 'keybind_button@' .. modname

AddClassPostConstruct('screens/redux/modconfigurationscreen', function(self)
  if self.modname ~= modname or self.options_scroll_list == nil then return end

  local list = self.options_scroll_list
  local ApplyDataToWidget = list.update_fn
  list.update_fn = function(context, widget, data, ...)
    ApplyDataToWidget(context, widget, data, ...)

    local opt = widget and widget.opt or nil
    if opt == nil then return end
    if opt[BUTTON_NAME] then
      opt[BUTTON_NAME]:Kill()
      opt[BUTTON_NAME] = nil
    end

    local config = data and data.option or nil
    if config == nil or not is_keybind[config.name] then return end

    local spinner = opt.spinner
    spinner:Hide()
    local button = BindButton({
      width = 225,
      height = 40,
      text_size = 25,
      text_color = C.GOLD,
      offset = 0,
      title = config.label,
      default = config.default,
      initial = data.initial_value,
      OnSet = function(key)
        self.options[widget.real_index].value = key
        data.selected_value = key
      end,
      OnChanged = function() self:MakeDirty() end,
    })
    button:SetPosition(spinner:GetPosition())
    button:Set(data.selected_value or data.initial_value or config.default)
    button:Show()
    opt[BUTTON_NAME] = opt:AddChild(button)
    opt.focus_forward = button
  end
  list:RefreshView()
end)

local _key = {}
local _setting = {}

-- Adapted from screens/redux/optionsscreen.lua: _BuildControls()
local BindEntry = Class(Widget, function(self, parent, config)
  Widget._ctor(self, modname .. ':KeyBindEntry')
  local x = -371 -- x coord of the left edge
  local button_width = 250 -- controls_ui.action_btn_width
  local button_height = 48 -- controls_ui.action_height
  local label_width = 375 -- controls_ui.action_label_width

  self:SetHoverText(config.hover, { offset_x = -60, offset_y = 60, wordwrap = true })
  self:SetScale(1, 1, 0.75)

  self.bg = self:AddChild(TEMPLATES.ListItemBackground(700, button_height))
  self.bg:SetPosition(-60, 0)
  self.bg:SetScale(1.025, 1)

  self.label = self:AddChild(Text(G.CHATFONT, 28, config.label, C.GOLD_UNIMPORTANT))
  self.label:SetHAlign(G.ANCHOR_LEFT)
  self.label:SetRegionSize(label_width, 50)
  self.label:SetPosition(x + label_width / 2, 0)
  self.label:SetClickable(false)

  self[BUTTON_NAME] = self:AddChild(BindButton({
    width = button_width,
    height = button_height,
    title = config.label,
    default = config.default,
    initial = _key[config],
    OnSet = function(key) _key[config] = key end,
    OnChanged = function() parent:MakeDirty() end,
  }))
  self[BUTTON_NAME]:SetPosition(x + label_width + 15 + button_width / 2, 0)

  self.controlId, self.control = 0, {}
  self.changed_image = { Show = function() end, Hide = function() end }
  self.binding_btn = { SetText = function() end }

  self.focus_forward = self[BUTTON_NAME]
end)

local SettingEntry = Class(Widget, function(self, parent, config)
  Widget._ctor(self, modname .. ':SettingEntry')
  local x = -371
  local button_width = 250
  local button_height = 48
  local label_width = 375
  local initial = GetModConfigData(config.name)
  if initial == nil then initial = config.default end

  self.config = config
  self.initial = initial
  _setting[config] = initial

  if config.hover then
    self:SetHoverText(config.hover, { offset_x = -60, offset_y = 60, wordwrap = true })
  end
  self:SetScale(1, 1, 0.75)

  self.bg = self:AddChild(TEMPLATES.ListItemBackground(700, button_height))
  self.bg:SetPosition(-60, 0)
  self.bg:SetScale(1.025, 1)

  self.label = self:AddChild(Text(G.CHATFONT, 28, config.label, C.GOLD_UNIMPORTANT))
  self.label:SetHAlign(G.ANCHOR_LEFT)
  self.label:SetRegionSize(label_width, 50)
  self.label:SetPosition(x + label_width / 2, 0)
  self.label:SetClickable(false)

  local spinner_options = {}
  for _, option in ipairs(config.options or {}) do
    spinner_options[#spinner_options + 1] = {
      text = option.description,
      data = option.data,
    }
  end

  local spinner_x = x + label_width + 15 + button_width / 2
  self.setting_changed_image = self:AddChild(Image('images/global_redux.xml', 'wardrobe_spinner_bg.tex'))
  self.setting_changed_image:SetTint(1, 1, 1, 0.3)
  self.setting_changed_image:ScaleToSize(button_width, button_height)
  self.setting_changed_image:SetPosition(spinner_x, 0)
  self.setting_changed_image:Hide()

  self.spinner = self:AddChild(TEMPLATES.StandardSpinner(spinner_options, button_width, button_height))
  self.spinner:SetPosition(spinner_x, 0)
  self.spinner:SetSelected(initial)
  self.spinner:SetOnChangedFn(function(value)
    _setting[config] = value
    if value == self.initial then
      self.setting_changed_image:Hide()
    else
      self.setting_changed_image:Show()
    end
    parent:MakeDirty()
  end)

  self.control = {}
  self.binding_btn = { SetText = function() end }
  self.focus_forward = self.spinner
end)

function SettingEntry:SetDefault()
  self.spinner:SetSelected(self.config.default)
end

local Header = Class(Widget, function(self, title)
  Widget._ctor(self, modname .. ':Header')

  self.txt = self:AddChild(Text(G.HEADERFONT, 32, title, C.GOLD_SELECTED))
  self.txt:SetPosition(-60, 0)

  self.bg = self:AddChild(TEMPLATES.ListItemBackground(700, 48))
  self.bg:SetImageNormalColour(0, 0, 0, 0)
  self.bg:SetImageFocusColour(0, 0, 0, 0)
  self.bg:SetPosition(-60, 0)
  self.bg:SetScale(1.025, 1)

  self.controlId, self.control = 0, {}
  self.changed_image = { Show = function() end, Hide = function() end }
  self.binding_btn = { SetText = function() end }
end)

AddClassPostConstruct('screens/redux/optionsscreen', function(self)
  local list = self.kb_controllist
  local items = list.items

  local new_items = {}
  if #control_entries > 0 then table.insert(new_items, list:AddChild(Header(modinfo.name))) end
  for _, config in ipairs(control_entries) do
    if is_keybind[config.name] then
      _key[config] = GetModConfigData(config.name)
      table.insert(new_items, list:AddChild(BindEntry(self, config)))
    elseif is_header[config.name] then
      table.insert(new_items, list:AddChild(Header(config.label)))
    else
      table.insert(new_items, list:AddChild(SettingEntry(self, config)))
    end
  end
  table.insert(new_items, list:AddChild(Header("──────────────────")))

  for _, item in ipairs(items) do
    table.insert(new_items, item)
  end

  list:SetList(new_items, true)
end)

local OldLoadDefaultControls = OptionsScreen.LoadDefaultControls
function OptionsScreen:LoadDefaultControls()
  for _, widget in ipairs(self.kb_controllist.items) do
    local button = widget[BUTTON_NAME]
    if button then
      button:Set(button.default)
    elseif widget.SetDefault then
      widget:SetDefault()
    end
  end
  return OldLoadDefaultControls(self)
end

local OldSave = OptionsScreen.Save
function OptionsScreen:Save(...)
  for _, config in ipairs(keybind_configs) do
    local key = _key[config]
    _G.WeiluoKeyBind(config.name, Raw(key))
    G.KnownModIndex:SetConfigurationOption(modname, config.name, key)
  end
  for config, value in pairs(_setting) do
    G.KnownModIndex:SetConfigurationOption(modname, config.name, value)
    if _G.WillowAssistApplyRuntimeConfig then
      _G.WillowAssistApplyRuntimeConfig(config.name, value)
    end
  end
  G.KnownModIndex:SaveHostConfiguration(modname)
  return OldSave(self, ...)
end
