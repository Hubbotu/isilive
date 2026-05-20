local _, addonTable = ...

addonTable = addonTable or {}

local SettingsPanel = {}
addonTable.SettingsPanel = SettingsPanel

local Colors = addonTable.UICommon and addonTable.UICommon.Colors or {}
local DEFAULT_BG_ALPHA = addonTable.UICommon and addonTable.UICommon.DEFAULT_BG_ALPHA or 0.50
local ApplyBackdrop = addonTable.UICommon and addonTable.UICommon.ApplyBackdrop

local PADDING_X = 16
local PADDING_TOP = 16
local LINE_HEIGHT = 28
local SECTION_GAP = 22
local HEADER_HEIGHT = 20
local HEADER_LINE_GAP = 4
local LANG_BUTTON_WIDTH = 90
local LANG_BUTTON_HEIGHT = 22
local SLIDER_WIDTH = 180
local SLIDER_HEIGHT = 16
local SETTINGS_SCROLL_STEP = 32
local SETTINGS_CONTENT_WIDTH = 700
local SLIDER_LABEL_WIDTH = 150
local CHECKBOX_LABEL_WIDTH = SETTINGS_CONTENT_WIDTH - (PADDING_X * 2) - 28
local SHOW_NAME_MAX_CHARS_SETTING = false
local SHOW_TELEPORT_COLUMNS_SETTING = false
local STATS_BOX_SETTING_LABELS = {
  enUS = {
    enabled = "Show player stats box",
    locked = "Lock player stats box position",
    alpha = "Stats box background opacity",
    fontSize = "Stats box font size",
  },
  deDE = {
    enabled = "Spieler-Stats-Box anzeigen",
    locked = "Spieler-Stats-Box-Position sperren",
    alpha = "Stats-Box-Hintergrund-Deckkraft",
    fontSize = "Stats-Box-Schriftgroesse",
  },
}
-- Brand title with the `isi` prefix as plain text and only `Live` colored
-- in dodgerblue (`#1e90ff`). The plain `isi` prefix serves two purposes:
--
-- 1. Sort key: WoW sorts AddOn-list and Settings-sidebar entries by the
--    raw title string. If the title starts with `|c...` the sort key
--    begins with `|` (ASCII 0x7C), which lands after every A-Z entry.
--    Putting a plain alphabetic prefix in front makes the sort key start
--    with that letter, so the entry sorts in the expected I-section.
-- 2. Visual: the plain prefix takes the FontString's default color, which
--    keeps the brand visually identical to the legacy "isiLive" entry
--    without any custom SetTextColor calls.
local ISILIVE_BRAND_TITLE = "isi|cff1e90ffLive|r"
local DEFAULT_LAYOUT_MODE_EXPANDED = "expanded"
local DEFAULT_LAYOUT_MODE_COMPACT_VERTICAL = "compact_vertical"
local DEFAULT_LAYOUT_MODE_COMPACT_HORIZONTAL = "compact_horizontal"
local DEFAULT_LAYOUT_MODE_COMPACT_MAIN_HORIZONTAL = "compact_main_horizontal"
local DEFAULT_LAYOUT_MODE_COMPACT_HORIZONTAL_2_LEGACY = "compact_horizontal_2"
local DEFAULT_LAYOUT_MODE_LAST_USED = "last_used"

local function ApplySettingsBackdrop(frame)
  if type(ApplyBackdrop) == "function" then
    ApplyBackdrop(frame, "PRIMARY")
  end
end

local RESET_CONFIRM_POPUP_PREFIX = "ISILIVE_CONFIRM_RESET_ACTION_"
local pendingResetConfirmActions = {}
local YES_TEXT = rawget(_G, "YES") or "Yes"
local NO_TEXT = rawget(_G, "NO") or "No"

local function StyleResetConfirmPopup(dialog)
  if type(dialog) ~= "table" then
    return
  end

  if type(ApplyBackdrop) == "function" then
    ApplyBackdrop(dialog, "NOTICE")
  end

  if type(dialog.SetMovable) == "function" then
    dialog:SetMovable(false)
  end
  if type(dialog.SetResizable) == "function" then
    dialog:SetResizable(false)
  end

  if dialog.text and type(dialog.text.SetTextColor) == "function" then
    local tn = Colors.TEXT_NORMAL or { 0.85, 0.85, 0.9 }
    dialog.text:SetTextColor(tn[1], tn[2], tn[3], 1)
    if type(dialog.text.SetWordWrap) == "function" then
      dialog.text:SetWordWrap(true)
    end
  end

  local accent = Colors.ACCENT_BLUE or { 0.3, 0.65, 1 }
  local gold = Colors.ACCENT_GOLD or { 1, 0.82, 0 }
  local buttons = { dialog.button1, dialog.button2 }
  for index, button in ipairs(buttons) do
    if type(button) == "table" then
      if type(button.SetSize) == "function" then
        button:SetSize(96, 22)
      end
      if type(button.SetBackdrop) == "function" then
        button:SetBackdrop({
          bgFile = "Interface\\Buttons\\WHITE8X8",
          edgeFile = "Interface\\Buttons\\WHITE8X8",
          edgeSize = 1,
          insets = { left = 0, right = 0, top = 0, bottom = 0 },
        })
        button:SetBackdropColor(0.12, 0.12, 0.18, 0.95)
        button:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.45)
      elseif type(ApplyBackdrop) == "function" then
        ApplyBackdrop(button, "FLAT_BUTTON")
      end

      if button._isiLiveHoverGlow == nil and type(button.CreateTexture) == "function" then
        local glow = button:CreateTexture(nil, "BACKGROUND", nil, -1)
        if type(glow.SetAllPoints) == "function" then
          glow:SetAllPoints()
        end
        if type(glow.SetColorTexture) == "function" then
          glow:SetColorTexture(accent[1], accent[2], accent[3], 0.12)
        end
        if type(glow.Hide) == "function" then
          glow:Hide()
        end
        button._isiLiveHoverGlow = glow
      end

      local text = button.GetText and button:GetText() or (index == 1 and YES_TEXT or NO_TEXT)
      if type(button.SetText) == "function" then
        button:SetText(text)
      end
      if type(button.SetScript) == "function" then
        button:SetScript("OnEnter", function(self)
          if type(self.SetBackdropBorderColor) == "function" then
            self:SetBackdropBorderColor(gold[1], gold[2], gold[3], 0.85)
          end
          if self._isiLiveHoverGlow and type(self._isiLiveHoverGlow.Show) == "function" then
            self._isiLiveHoverGlow:Show()
          end
        end)
        button:SetScript("OnLeave", function(self)
          if type(self.SetBackdropBorderColor) == "function" then
            self:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.45)
          end
          if self._isiLiveHoverGlow and type(self._isiLiveHoverGlow.Hide) == "function" then
            self._isiLiveHoverGlow:Hide()
          end
        end)
      end
    end
  end
end

local function ShowResetConfirmation(dialogKey, confirmText, onAccept)
  local popupName = RESET_CONFIRM_POPUP_PREFIX .. tostring(dialogKey or "DEFAULT")
  local dialogs = rawget(_G, "StaticPopupDialogs")
  local showPopup = rawget(_G, "StaticPopup_Show")
  if type(dialogs) ~= "table" or type(showPopup) ~= "function" then
    if type(onAccept) == "function" then
      onAccept()
    end
    return
  end

  local dialog = dialogs[popupName]
  if not dialog then
    dialogs[popupName] = {
      text = confirmText or "Do you really want to reset?",
      button1 = YES_TEXT,
      button2 = NO_TEXT,
      timeout = 0,
      whileDead = 1,
      hideOnEscape = 1,
      preferredIndex = 3,
      OnShow = function(self)
        StyleResetConfirmPopup(self)
      end,
      OnAccept = function()
        local action = pendingResetConfirmActions[popupName]
        pendingResetConfirmActions[popupName] = nil
        if type(action) == "function" then
          action()
        end
      end,
      OnCancel = function()
        pendingResetConfirmActions[popupName] = nil
      end,
      OnHide = function()
        pendingResetConfirmActions[popupName] = nil
      end,
    }
  else
    dialog.text = confirmText or dialog.text
  end

  pendingResetConfirmActions[popupName] = onAccept
  showPopup(popupName)
end

local function CreateSectionHeader(parent, yOffset, text)
  local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  local td = Colors.TEXT_DIM or { 0.5, 0.5, 0.6 }
  header:SetTextColor(td[1], td[2], td[3], 1)
  header:SetPoint("TOPLEFT", parent, "TOPLEFT", PADDING_X, yOffset)
  header:SetJustifyH("LEFT")
  header:SetText(text or "")

  local line = parent:CreateTexture(nil, "ARTWORK")
  line:SetHeight(2)
  line:SetPoint("TOPLEFT", parent, "TOPLEFT", PADDING_X, yOffset - HEADER_HEIGHT)
  line:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -PADDING_X, yOffset - HEADER_HEIGHT)
  local ab = Colors.ACCENT_BLUE or { 0.3, 0.65, 1 }
  line:SetColorTexture(ab[1], ab[2], ab[3], 0.42)

  return header, yOffset - HEADER_HEIGHT - HEADER_LINE_GAP
end

local function MeasureWrappedTextHeight(textRegion, fallbackHeight, padding)
  local height = tonumber(fallbackHeight) or 0
  local measured = nil
  if type(textRegion) == "table" and type(textRegion.GetStringHeight) == "function" then
    measured = tonumber(textRegion:GetStringHeight())
  end
  if measured and measured > 0 then
    height = math.max(height, math.ceil(measured) + (tonumber(padding) or 0))
  end
  return height
end

local function CreateSettingsIntro(parent, yOffset, text)
  local intro = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  local td = Colors.TEXT_DIM or { 0.5, 0.5, 0.6 }
  intro:SetTextColor(td[1], td[2], td[3], 1)
  intro:SetPoint("TOPLEFT", parent, "TOPLEFT", PADDING_X, yOffset)
  intro:SetWidth(math.max(240, SETTINGS_CONTENT_WIDTH - (PADDING_X * 2)))
  intro:SetJustifyH("LEFT")
  if type(intro.SetWordWrap) == "function" then
    intro:SetWordWrap(true)
  end
  intro:SetText(text or "")
  local height = MeasureWrappedTextHeight(intro, 28, 8)

  return intro, yOffset - height
end

local function CreateSectionNote(parent, yOffset, text)
  local note = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  local td = Colors.TEXT_DIM or { 0.5, 0.5, 0.6 }
  note:SetTextColor(td[1], td[2], td[3], 1)
  note:SetPoint("TOPLEFT", parent, "TOPLEFT", PADDING_X, yOffset)
  note:SetWidth(math.max(120, SETTINGS_CONTENT_WIDTH - (PADDING_X * 2)))
  note:SetJustifyH("LEFT")
  if type(note.SetWordWrap) == "function" then
    note:SetWordWrap(true)
  end
  note:SetText(text or "")
  local height = MeasureWrappedTextHeight(note, 16, 6)

  return note, yOffset - height
end

local function CreateSettingsCheckbox(parent, yOffset, labelText, getter, setter, settingKey, options)
  options = type(options) == "table" and options or {}
  local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  check:SetPoint("TOPLEFT", parent, "TOPLEFT", PADDING_X, yOffset)
  if type(check.SetSize) == "function" then
    check:SetSize(24, 24)
  end
  if type(settingKey) == "string" and settingKey ~= "" then
    check._settingKey = settingKey
  end

  local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  local tn = Colors.TEXT_NORMAL or { 0.85, 0.85, 0.9 }
  label:SetTextColor(tn[1], tn[2], tn[3], 1)
  label:SetPoint("LEFT", check, "RIGHT", 4, 0)
  local labelWidth = tonumber(options.width) or CHECKBOX_LABEL_WIDTH
  if type(label.SetWidth) == "function" and labelWidth and labelWidth > 0 then
    label:SetWidth(labelWidth)
  end
  if type(label.SetJustifyH) == "function" then
    label:SetJustifyH(type(options.justifyH) == "string" and options.justifyH or "LEFT")
  end
  if type(label.SetWordWrap) == "function" and options.wordWrap ~= false then
    label:SetWordWrap(true)
  end
  label:SetText(labelText or "")
  check.label = label

  if type(getter) == "function" then
    check:SetChecked(getter())
  end

  check:SetScript("OnClick", function(self)
    if type(setter) == "function" then
      setter(self:GetChecked() and true or false)
    end
  end)

  local rowHeight = tonumber(options.rowHeight) or LINE_HEIGHT
  if options.rowHeight == nil and type(label.GetStringHeight) == "function" then
    local textHeight = tonumber(label:GetStringHeight()) or 0
    if textHeight > 0 then
      rowHeight = math.max(rowHeight, math.ceil(textHeight) + 8)
    end
  end
  return { check = check, label = label }, yOffset - rowHeight
end

local function CreateSettingsSlider(
  parent,
  yOffset,
  labelText,
  minVal,
  maxVal,
  step,
  getter,
  setter,
  formatFunc,
  settingKey
)
  local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  local tn = Colors.TEXT_NORMAL or { 0.85, 0.85, 0.9 }
  label:SetTextColor(tn[1], tn[2], tn[3], 1)
  label:SetPoint("TOPLEFT", parent, "TOPLEFT", PADDING_X, yOffset - 3)
  label:SetText(labelText or "")
  if type(label.SetWidth) == "function" then
    label:SetWidth(SLIDER_LABEL_WIDTH)
  end
  if type(label.SetJustifyH) == "function" then
    label:SetJustifyH("LEFT")
  end
  if type(label.SetWordWrap) == "function" then
    label:SetWordWrap(true)
  end

  local slider = CreateFrame("Slider", nil, parent, "BackdropTemplate")
  slider:SetSize(SLIDER_WIDTH, SLIDER_HEIGHT)
  slider:SetPoint("TOPLEFT", parent, "TOPLEFT", PADDING_X + 160, yOffset - 2)
  slider:SetOrientation("HORIZONTAL")
  slider:SetMinMaxValues(minVal, maxVal)
  slider:SetValueStep(step)
  slider:SetObeyStepOnDrag(true)
  if type(settingKey) == "string" and settingKey ~= "" then
    slider._settingKey = settingKey
  end

  if type(slider.SetBackdrop) == "function" then
    slider:SetBackdrop({
      bgFile = "Interface\\Buttons\\WHITE8X8",
      edgeFile = "Interface\\Buttons\\WHITE8X8",
      edgeSize = 1,
      insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    local bgSec = Colors.BG_SECONDARY or { 0.12, 0.12, 0.18, 0.7 }
    slider:SetBackdropColor(bgSec[1], bgSec[2], bgSec[3], bgSec[4])
    local bd = Colors.BORDER_DEFAULT or { 0.25, 0.25, 0.35, 0.5 }
    slider:SetBackdropBorderColor(bd[1], bd[2], bd[3], bd[4])
  end

  if type(slider.SetThumbTexture) == "function" then
    local thumb = slider:CreateTexture(nil, "OVERLAY")
    if type(thumb.SetSize) == "function" then
      thumb:SetSize(10, SLIDER_HEIGHT)
    end
    local acBlue = Colors.ACCENT_BLUE or { 0.3, 0.65, 1 }
    if type(thumb.SetColorTexture) == "function" then
      thumb:SetColorTexture(acBlue[1], acBlue[2], acBlue[3], 0.8)
    end
    slider:SetThumbTexture(thumb)
  end

  local valueLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  valueLabel:SetTextColor(tn[1], tn[2], tn[3], 1)
  valueLabel:SetPoint("LEFT", slider, "RIGHT", 8, 0)
  local suppressValueChanged = false

  local function UpdateValueLabel(val)
    if type(formatFunc) == "function" then
      valueLabel:SetText(formatFunc(val))
    else
      valueLabel:SetText(string.format("%.0f%%", val * 100))
    end
  end

  local function SetValueSilently(val)
    suppressValueChanged = true
    slider:SetValue(val)
    suppressValueChanged = false
    UpdateValueLabel(val)
  end

  if type(getter) == "function" then
    local currentVal = getter()
    SetValueSilently(currentVal)
  end

  slider:SetScript("OnValueChanged", function(_, val)
    UpdateValueLabel(val)
    if suppressValueChanged then
      return
    end
    if type(setter) == "function" then
      setter(val)
    end
  end)

  local rowHeight = LINE_HEIGHT
  if type(label.GetStringHeight) == "function" then
    local textHeight = tonumber(label:GetStringHeight()) or 0
    if textHeight > 0 then
      rowHeight = math.max(rowHeight, math.ceil(textHeight) + 8)
    end
  end

  return {
    label = label,
    slider = slider,
    valueLabel = valueLabel,
    UpdateValueLabel = UpdateValueLabel,
    SetValueSilently = SetValueSilently,
  },
    yOffset - rowHeight
end

local function CreateSettingsActionButton(parent, yOffset, labelText, width, onClick, settingKey, subtitleText)
  local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
  local buttonWidth = tonumber(width) or 200
  local hasSubtitle = type(subtitleText) == "string" and subtitleText ~= ""
  local confirmText = nil
  if type(settingKey) == "table" then
    confirmText = settingKey.confirmText
    settingKey = settingKey.settingKey
  end
  local buttonHeight = hasSubtitle and 40 or 30
  button:SetSize(buttonWidth, buttonHeight)
  button:SetPoint("TOPLEFT", parent, "TOPLEFT", PADDING_X, yOffset)
  if type(settingKey) == "string" and settingKey ~= "" then
    button._settingKey = settingKey
  end

  if type(button.SetBackdrop) == "function" then
    button:SetBackdrop({
      bgFile = "Interface\\Buttons\\WHITE8X8",
      edgeFile = "Interface\\Buttons\\WHITE8X8",
      edgeSize = 1,
      insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    local bgSec = Colors.BG_SECONDARY or { 0.12, 0.12, 0.18, 0.7 }
    button:SetBackdropColor(bgSec[1], bgSec[2], bgSec[3], bgSec[4])
    local bd = Colors.BORDER_DEFAULT or { 0.25, 0.25, 0.35, 0.5 }
    button:SetBackdropBorderColor(bd[1], bd[2], bd[3], bd[4])
  end

  local hoverGlow = button:CreateTexture(nil, "BACKGROUND", nil, -1)
  if type(hoverGlow.SetAllPoints) == "function" then
    hoverGlow:SetAllPoints()
  end
  if type(hoverGlow.SetColorTexture) == "function" then
    local acBlue = Colors.ACCENT_BLUE or { 0.3, 0.65, 1 }
    hoverGlow:SetColorTexture(acBlue[1], acBlue[2], acBlue[3], 0.16)
  end
  if type(hoverGlow.Hide) == "function" then
    hoverGlow:Hide()
  end
  button.hoverGlow = hoverGlow

  local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  local tn = Colors.TEXT_NORMAL or { 0.85, 0.85, 0.9 }
  local hoverLabelColor = Colors.ACCENT_BLUE or { 0.3, 0.65, 1 }
  if hasSubtitle then
    label:SetPoint("TOPLEFT", button, "TOPLEFT", 8, -6)
    if type(label.SetWidth) == "function" then
      label:SetWidth(buttonWidth - 16)
    end
    if type(label.SetJustifyH) == "function" then
      label:SetJustifyH("CENTER")
    end
    if type(label.SetWordWrap) == "function" then
      label:SetWordWrap(true)
    end
  else
    label:SetPoint("CENTER", 0, 0)
    if type(label.SetWidth) == "function" then
      label:SetWidth(buttonWidth - 12)
    end
    if type(label.SetJustifyH) == "function" then
      label:SetJustifyH("CENTER")
    end
    if type(label.SetWordWrap) == "function" then
      label:SetWordWrap(true)
    end
  end
  label:SetTextColor(tn[1], tn[2], tn[3], 1)
  label:SetText(labelText or "")
  button.label = label

  local labelHeight = 0
  if type(label.GetStringHeight) == "function" then
    labelHeight = tonumber(label:GetStringHeight()) or 0
  end
  if labelHeight > 0 then
    local desiredHeight = math.ceil(labelHeight) + (hasSubtitle and 18 or 14)
    if desiredHeight > buttonHeight then
      buttonHeight = desiredHeight
      button:SetSize(buttonWidth, buttonHeight)
    end
  end

  local subtitle = nil
  if hasSubtitle then
    subtitle = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    local td = Colors.TEXT_DIM or { 0.5, 0.5, 0.6 }
    subtitle:SetTextColor(td[1], td[2], td[3], 1)
    subtitle:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 8, 5)
    if type(subtitle.SetWidth) == "function" then
      subtitle:SetWidth(buttonWidth - 16)
    end
    if type(subtitle.SetJustifyH) == "function" then
      subtitle:SetJustifyH("CENTER")
    end
    if type(subtitle.SetWordWrap) == "function" then
      subtitle:SetWordWrap(true)
    end
    subtitle:SetText(subtitleText)
  end
  button.subtitle = subtitle

  local function SetHoverState(isHover)
    local bgSec = Colors.BG_SECONDARY or { 0.12, 0.12, 0.18, 0.7 }
    local bd = Colors.BORDER_DEFAULT or { 0.25, 0.25, 0.35, 0.5 }
    if isHover then
      if type(button.SetBackdropColor) == "function" then
        button:SetBackdropColor(0.14, 0.14, 0.20, 0.92)
      end
      if type(button.SetBackdropBorderColor) == "function" then
        button:SetBackdropBorderColor(hoverLabelColor[1], hoverLabelColor[2], hoverLabelColor[3], 0.95)
      end
      if type(label.SetTextColor) == "function" then
        label:SetTextColor(1, 1, 1, 1)
      end
      if subtitle and type(subtitle.SetTextColor) == "function" then
        subtitle:SetTextColor(0.88, 0.92, 1, 1)
      end
      if hoverGlow and type(hoverGlow.Show) == "function" then
        hoverGlow:Show()
      end
    else
      if type(button.SetBackdropColor) == "function" then
        button:SetBackdropColor(bgSec[1], bgSec[2], bgSec[3], bgSec[4])
      end
      if type(button.SetBackdropBorderColor) == "function" then
        button:SetBackdropBorderColor(bd[1], bd[2], bd[3], bd[4])
      end
      if type(label.SetTextColor) == "function" then
        label:SetTextColor(tn[1], tn[2], tn[3], 1)
      end
      if subtitle and type(subtitle.SetTextColor) == "function" then
        local td = Colors.TEXT_DIM or { 0.5, 0.5, 0.6 }
        subtitle:SetTextColor(td[1], td[2], td[3], 1)
      end
      if hoverGlow and type(hoverGlow.Hide) == "function" then
        hoverGlow:Hide()
      end
    end
  end

  button:SetScript("OnEnter", function()
    SetHoverState(true)
  end)
  button:SetScript("OnLeave", function()
    SetHoverState(false)
  end)

  button:SetScript("OnClick", function()
    if type(onClick) == "function" then
      if type(confirmText) == "string" and confirmText ~= "" then
        ShowResetConfirmation(settingKey, confirmText, onClick)
      else
        onClick()
      end
    end
  end)

  return {
    button = button,
    label = label,
    subtitle = subtitle,
  }, yOffset - buttonHeight - LINE_HEIGHT
end

local LANG_BUTTONS_PER_ROW = 5

local function CreateLanguageSelector(parent, yOffset, labelText, getCurrentLocale, setLanguage)
  local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  local tn = Colors.TEXT_NORMAL or { 0.85, 0.85, 0.9 }
  label:SetTextColor(tn[1], tn[2], tn[3], 1)
  label:SetPoint("TOPLEFT", parent, "TOPLEFT", PADDING_X, yOffset - 3)
  label:SetText(labelText or "")

  local bgSec = Colors.BG_SECONDARY or { 0.12, 0.12, 0.18, 0.7 }
  local acBlue = Colors.ACCENT_BLUE or { 0.3, 0.65, 1 }

  local supported = addonTable.Languages and addonTable.Languages.SUPPORTED or {}
  local buttons = {}
  local rowIndex = 0

  for i, lang in ipairs(supported) do
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(LANG_BUTTON_WIDTH, LANG_BUTTON_HEIGHT)
    local posInRow = (i - 1) % LANG_BUTTONS_PER_ROW
    if posInRow == 0 then
      -- First button in this row: anchor to top-left, offset by row number
      local rowY = yOffset - 1 - (math.floor((i - 1) / LANG_BUTTONS_PER_ROW) * (LANG_BUTTON_HEIGHT + 3))
      btn:SetPoint("TOPLEFT", parent, "TOPLEFT", PADDING_X + 120, rowY)
    else
      btn:SetPoint("LEFT", buttons[#buttons].btn, "RIGHT", 2, 0)
    end
    if type(btn.SetBackdrop) == "function" then
      btn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    end
    local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("CENTER", 0, 0)
    lbl:SetWidth(LANG_BUTTON_WIDTH - 4)
    if type(lbl.SetWordWrap) == "function" then
      lbl:SetWordWrap(false)
    end
    if type(lbl.SetNonSpaceWrap) == "function" then
      lbl:SetNonSpaceWrap(false)
    end
    lbl:SetText(lang.buttonLabel)

    local tag = lang.tag
    btn:SetScript("OnClick", function()
      if type(setLanguage) == "function" then
        setLanguage(tag)
      end
      -- UpdateHighlight is defined below; forward reference via closure is safe
      -- because OnClick fires after the function is created.
    end)

    buttons[#buttons + 1] = { btn = btn, tag = tag }
    rowIndex = math.floor((i - 1) / LANG_BUTTONS_PER_ROW)
  end

  local numRows = rowIndex + 1
  local totalHeight = numRows * LINE_HEIGHT

  local function UpdateHighlight()
    local current = type(getCurrentLocale) == "function" and getCurrentLocale() or "enUS"
    local resolved = addonTable.Languages and addonTable.Languages.ResolveTag(current) or current
    for _, entry in ipairs(buttons) do
      if type(entry.btn.SetBackdropColor) == "function" then
        if entry.tag == resolved then
          entry.btn:SetBackdropColor(acBlue[1], acBlue[2], acBlue[3], 0.25)
        else
          entry.btn:SetBackdropColor(bgSec[1], bgSec[2], bgSec[3], bgSec[4])
        end
      end
    end
  end

  -- Wire UpdateHighlight into each button's OnClick now that the function exists.
  for _, entry in ipairs(buttons) do
    local existingScript = entry.btn:GetScript("OnClick")
    entry.btn:SetScript("OnClick", function()
      if existingScript then
        existingScript()
      end
      UpdateHighlight()
    end)
  end

  UpdateHighlight()

  return { label = label, buttons = buttons, UpdateHighlight = UpdateHighlight }, yOffset - totalHeight
end

local function NormalizeStoredLayoutMode(layoutMode)
  if layoutMode == nil or layoutMode == false or layoutMode == "" then
    return DEFAULT_LAYOUT_MODE_COMPACT_MAIN_HORIZONTAL
  end
  if layoutMode == DEFAULT_LAYOUT_MODE_LAST_USED then
    return DEFAULT_LAYOUT_MODE_LAST_USED
  end
  if layoutMode == DEFAULT_LAYOUT_MODE_EXPANDED then
    return DEFAULT_LAYOUT_MODE_COMPACT_MAIN_HORIZONTAL
  end
  if layoutMode == DEFAULT_LAYOUT_MODE_COMPACT_HORIZONTAL_2_LEGACY then
    return DEFAULT_LAYOUT_MODE_COMPACT_MAIN_HORIZONTAL
  end
  if
    layoutMode == DEFAULT_LAYOUT_MODE_COMPACT_VERTICAL
    or layoutMode == DEFAULT_LAYOUT_MODE_COMPACT_HORIZONTAL
    or layoutMode == DEFAULT_LAYOUT_MODE_COMPACT_MAIN_HORIZONTAL
  then
    return layoutMode
  end
  return nil
end

local function CreateSettingsOptionSelector(
  parent,
  yOffset,
  labelKey,
  fallbackLabel,
  options,
  getLabels,
  getter,
  setter,
  normalizeValue,
  labelOnTop
)
  local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  local tn = Colors.TEXT_NORMAL or { 0.85, 0.85, 0.9 }
  label:SetTextColor(tn[1], tn[2], tn[3], 1)
  label:SetPoint("TOPLEFT", parent, "TOPLEFT", PADDING_X, yOffset - 3)
  label:SetText(fallbackLabel or "")

  local buttons = {}
  local buttonX = labelOnTop and PADDING_X or (PADDING_X + 160)
  local buttonYOffset = labelOnTop and (yOffset - LINE_HEIGHT + 4) or yOffset
  local bgSec = Colors.BG_SECONDARY or { 0.12, 0.12, 0.18, 0.7 }
  local acBlue = Colors.ACCENT_BLUE or { 0.3, 0.65, 1 }
  local borderDefault = Colors.BORDER_DEFAULT or { 0.25, 0.25, 0.35, 0.5 }

  local function ApplyButtonStyle(button, selected)
    if type(button.SetBackdropColor) == "function" then
      if selected then
        button:SetBackdropColor(acBlue[1], acBlue[2], acBlue[3], 0.25)
      else
        button:SetBackdropColor(bgSec[1], bgSec[2], bgSec[3], bgSec[4])
      end
    end
    if type(button.SetBackdropBorderColor) == "function" then
      if selected then
        button:SetBackdropBorderColor(acBlue[1], acBlue[2], acBlue[3], 0.9)
      else
        button:SetBackdropBorderColor(borderDefault[1], borderDefault[2], borderDefault[3], borderDefault[4])
      end
    end
    if button.label and type(button.label.SetTextColor) == "function" then
      if selected then
        button.label:SetTextColor(1, 0.85, 0, 1)
      else
        button.label:SetTextColor(tn[1], tn[2], tn[3], 1)
      end
    end
  end

  for _, option in ipairs(options or {}) do
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    local buttonWidth = tonumber(option.width) or 40
    button:SetSize(buttonWidth, LANG_BUTTON_HEIGHT)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", buttonX, buttonYOffset - 1)
    if type(button.SetBackdrop) == "function" then
      button:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    end

    local buttonLabel = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    buttonLabel:SetPoint("CENTER", 0, 0)
    button.label = buttonLabel
    button._optionValue = option.value
    button._optionLabelKey = option.labelKey
    button._optionFallback = option.fallback or ""

    button:SetScript("OnClick", function()
      if type(setter) == "function" then
        setter(option.value)
      end
      local freshL = type(getLabels) == "function" and getLabels() or {}
      label:SetText((freshL and freshL[labelKey]) or fallbackLabel or "")
      local selectedMode = type(normalizeValue) == "function"
          and normalizeValue(type(getter) == "function" and getter() or nil)
        or (type(getter) == "function" and getter() or nil)
      for _, btn in ipairs(buttons) do
        local btnText = freshL and freshL[btn._optionLabelKey] or btn._optionFallback or ""
        if btn.label and type(btn.label.SetText) == "function" then
          btn.label:SetText(btnText)
        end
        ApplyButtonStyle(btn, selectedMode == btn._optionValue)
      end
    end)

    table.insert(buttons, button)
    buttonX = buttonX + buttonWidth + 4
  end

  local function UpdateHighlight()
    local freshL = type(getLabels) == "function" and getLabels() or {}
    label:SetText((freshL and freshL[labelKey]) or fallbackLabel or "")
    local selectedMode = type(normalizeValue) == "function"
        and normalizeValue(type(getter) == "function" and getter() or nil)
      or (type(getter) == "function" and getter() or nil)
    for _, button in ipairs(buttons) do
      local buttonText = freshL and freshL[button._optionLabelKey] or button._optionFallback or ""
      if button.label and type(button.label.SetText) == "function" then
        button.label:SetText(buttonText)
      end
      ApplyButtonStyle(button, selectedMode == button._optionValue)
    end
  end

  UpdateHighlight()

  return {
    label = label,
    buttons = buttons,
    UpdateHighlight = UpdateHighlight,
  },
    yOffset - (labelOnTop and LINE_HEIGHT * 2 or LINE_HEIGHT)
end

local function ResolveSettingsOptions(opts)
  opts = opts or {}

  return {
    getL = type(opts.getL) == "function" and opts.getL or function()
      return {}
    end,
    setLanguage = opts.setLanguage,
    getCurrentLocale = opts.getCurrentLocale,
    getDB = type(opts.getDB) == "function" and opts.getDB or function()
      return {}
    end,
    onEscPanelToggle = opts.onEscPanelToggle,
    onBgAlphaChange = opts.onBgAlphaChange,
    onStatsBoxToggle = opts.onStatsBoxToggle,
    onStatsBoxLockToggle = opts.onStatsBoxLockToggle,
    onStatsBoxBgAlphaChange = opts.onStatsBoxBgAlphaChange,
    onStatsBoxFontSizeOffsetChange = opts.onStatsBoxFontSizeOffsetChange,
    onUiScaleChange = opts.onUiScaleChange,
    onSyncToggle = opts.onSyncToggle,
    onMinimapButtonToggle = opts.onMinimapButtonToggle,
    onAutoOpenQueueToggle = opts.onAutoOpenQueueToggle,
    onAutoCloseOnKeyStartToggle = opts.onAutoCloseOnKeyStartToggle,
    onAutoCloseOnSoloChangeToggle = opts.onAutoCloseOnSoloChangeToggle,
    onMainFramePositionLockToggle = opts.onMainFramePositionLockToggle,
    onCombatFadeMMToggle = opts.onCombatFadeMMToggle,
    onAutoShowMainFrameOnStartupToggle = opts.onAutoShowMainFrameOnStartupToggle,
    onAutoOpenMainFrameOnKeyEndToggle = opts.onAutoOpenMainFrameOnKeyEndToggle,
    onRaidTransitionBehaviorChange = opts.onRaidTransitionBehaviorChange,
    onPortalNavigatorToggle = opts.onPortalNavigatorToggle,
    onDefaultLayoutModeChange = opts.onDefaultLayoutModeChange,
    onNameMaxCharsChange = opts.onNameMaxCharsChange,
    onRosterColumnGuidesToggle = opts.onRosterColumnGuidesToggle,
    onTeleportColumnsChange = opts.onTeleportColumnsChange,
    getQueueDebugEnabled = opts.getQueueDebugEnabled,
    onQueueDebugToggle = opts.onQueueDebugToggle,
    getRuntimeLogEnabled = opts.getRuntimeLogEnabled,
    onRuntimeLogToggle = opts.onRuntimeLogToggle,
    onClearRuntimeLog = opts.onClearRuntimeLog,
    onClearQueueDebugLog = opts.onClearQueueDebugLog,
    onLfgFlagsToggle = opts.onLfgFlagsToggle,
    onTooltipFlagsToggle = opts.onTooltipFlagsToggle,
    onMplusForcesToggle = opts.onMplusForcesToggle,
    onMobNameplateChange = opts.onMobNameplateChange,
    onResetDB = opts.onResetDB,
    onResetMainFramePosition = opts.onResetMainFramePosition,
  }
end

local function ResolveSettingsLocale(config)
  local db = type(config.getDB) == "function" and config.getDB() or nil
  if type(db) == "table" and STATS_BOX_SETTING_LABELS[db.locale] then
    return db.locale
  end
  if type(config.getCurrentLocale) == "function" then
    local locale = config.getCurrentLocale()
    if STATS_BOX_SETTING_LABELS[locale] then
      return locale
    end
  end
  return "enUS"
end

local function GetStatsBoxSettingLabel(config, key)
  local labels = STATS_BOX_SETTING_LABELS[ResolveSettingsLocale(config)] or STATS_BOX_SETTING_LABELS.enUS
  return labels[key] or STATS_BOX_SETTING_LABELS.enUS[key] or key
end

local function GetCVarEnabled(name)
  local getCVar = rawget(_G, "GetCVar")
  if type(getCVar) == "function" then
    return getCVar(name) == "1"
  end

  return false
end

local function SetCVarEnabled(name, checked)
  local setCVar = rawget(_G, "SetCVar")
  if type(setCVar) == "function" then
    setCVar(name, checked and "1" or "0")
  end
end

local function CreateSettingsTitle(canvas)
  local title = canvas:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  -- Accent-gold baseline so the plain `isi` prefix in ISILIVE_BRAND_TITLE
  -- renders in the historical brand color. The `Live` segment overrides
  -- this default via its embedded |cff1e90ff...|r color code.
  local ag = Colors.ACCENT_GOLD or { 1, 0.82, 0 }
  title:SetTextColor(ag[1], ag[2], ag[3], 1)
  title:SetPoint("TOPLEFT", canvas, "TOPLEFT", PADDING_X, -PADDING_TOP)
  title:SetText(ISILIVE_BRAND_TITLE)

  return title
end

local function BuildGeneralSettingsSection(canvas, yOffset, labels, config, controls)
  controls.generalHeader, yOffset = CreateSectionHeader(canvas, yOffset, labels.SETTINGS_SECTION_GENERAL or "General")
  controls.generalHint, yOffset = CreateSectionNote(
    canvas,
    yOffset,
    labels.SETTINGS_SECTION_GENERAL_HINT or "Language, startup behavior, and utility links."
  )
  if controls.generalHint then
    controls.generalHint._sectionKey = "SETTINGS_SECTION_GENERAL"
  end

  controls.lang, yOffset = CreateLanguageSelector(
    canvas,
    yOffset,
    labels.SETTINGS_LANGUAGE or "Language",
    config.getCurrentLocale,
    config.setLanguage
  )

  controls.defaultLayout, yOffset = CreateSettingsOptionSelector(
    canvas,
    yOffset,
    "SETTINGS_DEFAULT_OPEN_UI",
    labels.SETTINGS_DEFAULT_OPEN_UI or "Default UI on Open",
    {
      {
        value = DEFAULT_LAYOUT_MODE_LAST_USED,
        labelKey = "SETTINGS_DEFAULT_OPEN_UI_LAST",
        fallback = labels.SETTINGS_DEFAULT_OPEN_UI_LAST or "Last Used",
        width = 78,
      },
      {
        value = DEFAULT_LAYOUT_MODE_COMPACT_VERTICAL,
        labelKey = "SETTINGS_DEFAULT_OPEN_UI_V",
        fallback = labels.SETTINGS_DEFAULT_OPEN_UI_V or "V",
        width = 34,
      },
      {
        value = DEFAULT_LAYOUT_MODE_COMPACT_HORIZONTAL,
        labelKey = "SETTINGS_DEFAULT_OPEN_UI_H",
        fallback = labels.SETTINGS_DEFAULT_OPEN_UI_H or "H",
        width = 34,
      },
      {
        value = DEFAULT_LAYOUT_MODE_COMPACT_MAIN_HORIZONTAL,
        labelKey = "SETTINGS_DEFAULT_OPEN_UI_M2",
        fallback = labels.SETTINGS_DEFAULT_OPEN_UI_M2 or "M+",
        width = 40,
      },
    },
    config.getL,
    function()
      local db = config.getDB()
      return NormalizeStoredLayoutMode(db.rosterDefaultLayoutMode)
    end,
    function(mode)
      local db = config.getDB()
      db.rosterDefaultLayoutMode = NormalizeStoredLayoutMode(mode)
      if type(config.onDefaultLayoutModeChange) == "function" then
        local callbackMode = db.rosterDefaultLayoutMode
        if callbackMode == DEFAULT_LAYOUT_MODE_LAST_USED then
          callbackMode = nil
        end
        config.onDefaultLayoutModeChange(callbackMode)
      end
    end,
    NormalizeStoredLayoutMode,
    true
  )

  controls.combatLog, yOffset = CreateSettingsCheckbox(
    canvas,
    yOffset,
    labels.SETTINGS_COMBAT_LOGGING or "Advanced Combat Logging",
    function()
      return GetCVarEnabled("advancedCombatLogging")
    end,
    function(checked)
      SetCVarEnabled("advancedCombatLogging", checked)
    end
  )

  controls.dmReset, yOffset = CreateSettingsCheckbox(
    canvas,
    yOffset,
    labels.SETTINGS_DM_RESET or "Reset Blizzard Damage Meter on dungeon entry",
    function()
      return GetCVarEnabled("damageMeterResetOnNewInstance")
    end,
    function(checked)
      SetCVarEnabled("damageMeterResetOnNewInstance", checked)
    end
  )

  controls.escPanel, yOffset = CreateSettingsCheckbox(
    canvas,
    yOffset,
    labels.SETTINGS_ESC_PANEL or "Show ESC Menu Shortcuts",
    function()
      local db = config.getDB()
      return db.showEscPanel ~= false
    end,
    function(checked)
      local db = config.getDB()
      db.showEscPanel = checked
      if type(config.onEscPanelToggle) == "function" then
        config.onEscPanelToggle(checked)
      end
    end
  )

  controls.portalNavigator, yOffset = CreateSettingsCheckbox(
    canvas,
    yOffset,
    labels.SETTINGS_SHOW_TIMEWAYS_NAVIGATOR or "Show Timeways Navigator",
    function()
      local db = config.getDB()
      return db.showPortalNavigator ~= false
    end,
    function(checked)
      local db = config.getDB()
      db.showPortalNavigator = checked
      if type(config.onPortalNavigatorToggle) == "function" then
        config.onPortalNavigatorToggle(checked)
      end
    end,
    "SETTINGS_SHOW_TIMEWAYS_NAVIGATOR"
  )

  return yOffset
end

local function BuildDisplaySettingsSection(canvas, yOffset, labels, config, controls)
  controls.displayHeader, yOffset = CreateSectionHeader(canvas, yOffset, labels.SETTINGS_SECTION_DISPLAY or "Display")
  controls.displayHint, yOffset =
    CreateSectionNote(canvas, yOffset, labels.SETTINGS_SECTION_DISPLAY_HINT or "Scale, opacity, and UI recovery tools.")
  if controls.displayHint then
    controls.displayHint._sectionKey = "SETTINGS_SECTION_DISPLAY"
  end

  controls.uiScale, yOffset = CreateSettingsSlider(
    canvas,
    yOffset,
    labels.SETTINGS_UI_SCALE or "UI Scale",
    0.5,
    2.0,
    0.05,
    function()
      local db = config.getDB()
      return type(db.uiScale) == "number" and db.uiScale or 1.0
    end,
    function(val)
      local db = config.getDB()
      db.uiScale = val
      if type(config.onUiScaleChange) == "function" then
        config.onUiScaleChange(val)
      end
    end,
    function(val)
      return string.format("%.0f%%", val * 100)
    end,
    "SETTINGS_UI_SCALE"
  )

  controls.bgAlpha, yOffset = CreateSettingsSlider(
    canvas,
    yOffset,
    labels.SETTINGS_BG_ALPHA or "Background Opacity",
    0.3,
    1.0,
    0.05,
    function()
      local db = config.getDB()
      return type(db.bgAlpha) == "number" and db.bgAlpha or DEFAULT_BG_ALPHA
    end,
    function(val)
      local db = config.getDB()
      db.bgAlpha = val
      if type(config.onBgAlphaChange) == "function" then
        config.onBgAlphaChange(val)
      end
    end,
    function(val)
      return string.format("%.0f%%", val * 100)
    end,
    "SETTINGS_BG_ALPHA"
  )

  controls.statsBoxEnabled, yOffset = CreateSettingsCheckbox(
    canvas,
    yOffset,
    GetStatsBoxSettingLabel(config, "enabled"),
    function()
      local db = config.getDB()
      return db.statsBoxEnabled == true
    end,
    function(checked)
      local db = config.getDB()
      db.statsBoxEnabled = checked
      if type(config.onStatsBoxToggle) == "function" then
        config.onStatsBoxToggle(checked)
      end
    end,
    "SETTINGS_STATS_BOX_ENABLED"
  )

  controls.statsBoxLocked, yOffset = CreateSettingsCheckbox(
    canvas,
    yOffset,
    GetStatsBoxSettingLabel(config, "locked"),
    function()
      local db = config.getDB()
      return db.statsBoxLocked == true
    end,
    function(checked)
      local db = config.getDB()
      db.statsBoxLocked = checked == true
      if type(config.onStatsBoxLockToggle) == "function" then
        config.onStatsBoxLockToggle(db.statsBoxLocked)
      end
    end,
    "SETTINGS_STATS_BOX_LOCKED"
  )

  controls.statsBoxBgAlpha, yOffset = CreateSettingsSlider(
    canvas,
    yOffset,
    GetStatsBoxSettingLabel(config, "alpha"),
    0.0,
    1.0,
    0.05,
    function()
      local db = config.getDB()
      return type(db.statsBoxBgAlpha) == "number" and db.statsBoxBgAlpha or 0
    end,
    function(val)
      local db = config.getDB()
      db.statsBoxBgAlpha = val
      if type(config.onStatsBoxBgAlphaChange) == "function" then
        config.onStatsBoxBgAlphaChange(val)
      end
    end,
    function(val)
      return string.format("%.0f%%", val * 100)
    end,
    "SETTINGS_STATS_BOX_BG_ALPHA"
  )

  controls.statsBoxFontSizeOffset, yOffset = CreateSettingsSlider(
    canvas,
    yOffset,
    GetStatsBoxSettingLabel(config, "fontSize"),
    -3,
    3,
    1,
    function()
      local db = config.getDB()
      return type(db.statsBoxFontSizeOffset) == "number" and db.statsBoxFontSizeOffset or 0
    end,
    function(val)
      local db = config.getDB()
      db.statsBoxFontSizeOffset = math.floor((tonumber(val) or 0) + 0.5)
      if type(config.onStatsBoxFontSizeOffsetChange) == "function" then
        config.onStatsBoxFontSizeOffsetChange(db.statsBoxFontSizeOffset)
      end
    end,
    function(val)
      val = tonumber(val) or 0
      if val > 0 then
        return string.format("+%d", val)
      end
      return tostring(math.floor(val + 0.5))
    end,
    "SETTINGS_STATS_BOX_FONT_SIZE_OFFSET"
  )

  controls.resetUiBtn, yOffset = CreateSettingsActionButton(
    canvas,
    yOffset,
    labels.SETTINGS_RESET_UI_POSITION or "/isilive resetui",
    320,
    function()
      if type(config.onResetMainFramePosition) == "function" then
        config.onResetMainFramePosition()
      end
    end,
    {
      settingKey = "SETTINGS_RESET_UI_POSITION",
      confirmText = labels.SETTINGS_RESET_CONFIRM_TEXT or "Do you really want to reset?",
    },
    nil
  )

  local resetUiHint = canvas:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  local td = Colors.TEXT_DIM or { 0.5, 0.5, 0.6 }
  resetUiHint:SetTextColor(td[1], td[2], td[3], 1)
  resetUiHint:SetPoint("TOPLEFT", controls.resetUiBtn.button, "BOTTOMLEFT", 8, -4)
  resetUiHint:SetWidth(304)
  resetUiHint:SetJustifyH("CENTER")
  if type(resetUiHint.SetWordWrap) == "function" then
    resetUiHint:SetWordWrap(true)
  end
  resetUiHint:SetText(
    labels.SETTINGS_RESET_UI_POSITION_HINT or "Default: position center, UI scale 100%, background opacity 50%"
  )
  controls.resetUiHint = resetUiHint
  if controls.resetUiBtn then
    controls.resetUiBtn.hint = resetUiHint
    if controls.resetUiBtn.button then
      controls.resetUiBtn.button.hint = resetUiHint
    end
  end
  yOffset = yOffset - 18

  if SHOW_NAME_MAX_CHARS_SETTING then
    controls.nameMaxChars, yOffset = CreateSettingsSlider(
      canvas,
      yOffset,
      labels.SETTINGS_NAME_MAX_CHARS or "Name Length",
      4,
      20,
      1,
      function()
        local db = config.getDB()
        return type(db.nameMaxChars) == "number" and db.nameMaxChars or 10
      end,
      function(val)
        local db = config.getDB()
        db.nameMaxChars = math.floor(val + 0.5)
        if type(config.onNameMaxCharsChange) == "function" then
          config.onNameMaxCharsChange(db.nameMaxChars)
        end
      end,
      function(val)
        return string.format("%.0f", val)
      end
    )
  end

  if SHOW_TELEPORT_COLUMNS_SETTING then
    controls.tpColumns, yOffset = CreateSettingsSlider(
      canvas,
      yOffset,
      labels.SETTINGS_TELEPORT_COLUMNS or "Teleport Grid Columns",
      2,
      8,
      1,
      function()
        local db = config.getDB()
        return type(db.teleportColumns) == "number" and db.teleportColumns or 4
      end,
      function(val)
        local db = config.getDB()
        db.teleportColumns = math.floor(val + 0.5)
        if type(config.onTeleportColumnsChange) == "function" then
          config.onTeleportColumnsChange(db.teleportColumns)
        end
      end,
      function(val)
        return string.format("%.0f", val)
      end
    )
  end

  controls.minimapBtn, yOffset = CreateSettingsCheckbox(
    canvas,
    yOffset,
    labels.SETTINGS_MINIMAP_BUTTON or "Minimap Button",
    function()
      local db = config.getDB()
      return db.showMinimapButton == true
    end,
    function(checked)
      local db = config.getDB()
      db.showMinimapButton = checked
      if type(config.onMinimapButtonToggle) == "function" then
        config.onMinimapButtonToggle(checked)
      end
    end
  )

  controls.lfgFlags, yOffset = CreateSettingsCheckbox(
    canvas,
    yOffset,
    labels.SETTINGS_LFG_FLAGS or "Group Finder: Language Flags",
    function()
      local db = config.getDB()
      return db.lfgFlagsEnabled ~= false
    end,
    function(checked)
      local db = config.getDB()
      db.lfgFlagsEnabled = checked
      if type(config.onLfgFlagsToggle) == "function" then
        config.onLfgFlagsToggle(checked)
      end
    end,
    "SETTINGS_LFG_FLAGS"
  )

  controls.tooltipFlags, yOffset = CreateSettingsCheckbox(
    canvas,
    yOffset,
    labels.SETTINGS_TOOLTIP_FLAGS or "Tooltip: Language Flags",
    function()
      local db = config.getDB()
      return db.tooltipFlagsEnabled ~= false
    end,
    function(checked)
      local db = config.getDB()
      db.tooltipFlagsEnabled = checked
      if type(config.onTooltipFlagsToggle) == "function" then
        config.onTooltipFlagsToggle(checked)
      end
    end,
    "SETTINGS_TOOLTIP_FLAGS"
  )

  controls.inviteHint, yOffset = CreateSettingsCheckbox(
    canvas,
    yOffset,
    labels.SETTINGS_INVITE_HINT_ENABLED or "LFG invite hint",
    function()
      local db = config.getDB()
      return db.inviteHintEnabled ~= false
    end,
    function(checked)
      local db = config.getDB()
      db.inviteHintEnabled = checked
    end,
    "SETTINGS_INVITE_HINT_ENABLED"
  )

  controls.acceptedInviteNotice, yOffset = CreateSettingsCheckbox(
    canvas,
    yOffset,
    labels.SETTINGS_ACCEPTED_INVITE_NOTICE_ENABLED or "Accepted-invite notice",
    function()
      local db = config.getDB()
      return db.acceptedInviteNoticeEnabled ~= false
    end,
    function(checked)
      local db = config.getDB()
      db.acceptedInviteNoticeEnabled = checked
    end,
    "SETTINGS_ACCEPTED_INVITE_NOTICE_ENABLED"
  )

  return yOffset
end

local NAMEPLATE_POSITIONS = { "LEFT", "RIGHT", "TOP", "BOTTOM" }

local function NormalizeNameplatePosition(val)
  if type(val) == "string" then
    for _, p in ipairs(NAMEPLATE_POSITIONS) do
      if val == p then
        return p
      end
    end
  end
  return "RIGHT"
end

local MPLUS_FORCES_MODES = { "off", "tooltip", "nameplate" }

local function NormalizeMplusForcesMode(val)
  if type(val) == "string" then
    for _, m in ipairs(MPLUS_FORCES_MODES) do
      if val == m then
        return m
      end
    end
  end
  -- Default aligned with ResolveMplusForcesModeFromDB fresh-install branch.
  return "nameplate"
end

local function ResolveMplusForcesModeFromDB(db)
  if type(db) ~= "table" then
    return "nameplate"
  end
  if db.mobNameplateEnabled == true then
    return "nameplate"
  end
  if db.mplusForcesEstimate == true then
    return "tooltip"
  end
  if db.mobNameplateEnabled == nil and db.mplusForcesEstimate == nil then
    -- Fresh install: nameplate overlay is ON by default so the M+ forces
    -- percent appears in keys without a manual setup step.
    -- The factory migration writes the same default into the DB once.
    return "nameplate"
  end
  return "off"
end

local function IsExternalNameplateAddonLoaded()
  local cAddOns = rawget(_G, "C_AddOns")
  local isLoaded = nil
  if type(cAddOns) == "table" and type(cAddOns.IsAddOnLoaded) == "function" then
    isLoaded = function(name)
      local ok, loaded = pcall(cAddOns.IsAddOnLoaded, name)
      return ok and loaded == true
    end
  else
    local legacy = rawget(_G, "IsAddOnLoaded")
    if type(legacy) == "function" then
      isLoaded = function(name)
        local ok, loaded = pcall(legacy, name)
        return ok and loaded == true
      end
    end
  end
  if not isLoaded then
    return false
  end
  return isLoaded("Plater") or isLoaded("Platynator")
end

local function BuildNameplatesSettingsSection(canvas, yOffset, labels, config, controls)
  controls.nameplatesHeader, yOffset =
    CreateSectionHeader(canvas, yOffset, labels.SETTINGS_SECTION_NAMEPLATES or "Nameplates")
  controls.nameplatesHint, yOffset = CreateSectionNote(
    canvas,
    yOffset,
    labels.SETTINGS_SECTION_NAMEPLATES_HINT or "Enemy forces overlay on Mythic+ nameplates."
  )
  if controls.nameplatesHint then
    controls.nameplatesHint._sectionKey = "SETTINGS_SECTION_NAMEPLATES"
  end

  if IsExternalNameplateAddonLoaded() then
    controls.nameplatesExternalWarn, yOffset = CreateSectionNote(
      canvas,
      yOffset,
      labels.SETTINGS_NAMEPLATE_EXTERNAL_WARN
        or "Plater or Platynator detected: if that addon already shows M+ count, leave this off."
    )
    if controls.nameplatesExternalWarn then
      controls.nameplatesExternalWarn._sectionKey = "SETTINGS_NAMEPLATE_EXTERNAL_WARN"
    end
  end

  controls.nameplateDisplayMode, yOffset = CreateSettingsOptionSelector(
    canvas,
    yOffset,
    "SETTINGS_MPLUS_FORCES_DISPLAY_MODE",
    labels.SETTINGS_MPLUS_FORCES_DISPLAY_MODE or "Display mode",
    {
      {
        value = "off",
        labelKey = "SETTINGS_MPLUS_FORCES_MODE_OFF",
        fallback = labels.SETTINGS_MPLUS_FORCES_MODE_OFF or "Off",
        width = 70,
      },
      {
        value = "tooltip",
        labelKey = "SETTINGS_MPLUS_FORCES_MODE_TOOLTIP",
        fallback = labels.SETTINGS_MPLUS_FORCES_MODE_TOOLTIP or "Tooltip",
        width = 90,
      },
      {
        value = "nameplate",
        labelKey = "SETTINGS_MPLUS_FORCES_MODE_NAMEPLATE",
        fallback = labels.SETTINGS_MPLUS_FORCES_MODE_NAMEPLATE or "Nameplate",
        width = 100,
      },
    },
    config.getL,
    function()
      return ResolveMplusForcesModeFromDB(config.getDB())
    end,
    function(mode)
      mode = NormalizeMplusForcesMode(mode)
      local db = config.getDB()
      db.mplusForcesEstimate = (mode == "tooltip")
      db.mobNameplateEnabled = (mode == "nameplate")
      if type(config.onMplusForcesToggle) == "function" then
        config.onMplusForcesToggle(db.mplusForcesEstimate == true)
      end
      if type(config.onMobNameplateChange) == "function" then
        config.onMobNameplateChange()
      end
      if type(controls.nameplatePreviewUpdate) == "function" then
        controls.nameplatePreviewUpdate()
      end
    end,
    NormalizeMplusForcesMode,
    true
  )

  controls.nameplateShowPercent, yOffset = CreateSettingsCheckbox(
    canvas,
    yOffset,
    labels.SETTINGS_NAMEPLATE_SHOW_PERCENT or "Show percentage",
    function()
      return config.getDB().mobNameplateShowPercent ~= false
    end,
    function(checked)
      local db = config.getDB()
      db.mobNameplateShowPercent = checked
      if type(config.onMobNameplateChange) == "function" then
        config.onMobNameplateChange()
      end
      if type(controls.nameplatePreviewUpdate) == "function" then
        controls.nameplatePreviewUpdate()
      end
    end,
    "SETTINGS_NAMEPLATE_SHOW_PERCENT"
  )

  controls.nameplateShowRemaining, yOffset = CreateSettingsCheckbox(
    canvas,
    yOffset,
    labels.SETTINGS_NAMEPLATE_SHOW_REMAINING or "Show remaining needed",
    function()
      return config.getDB().mobNameplateShowRemaining ~= false
    end,
    function(checked)
      local db = config.getDB()
      db.mobNameplateShowRemaining = checked
      if type(config.onMobNameplateChange) == "function" then
        config.onMobNameplateChange()
      end
      if type(controls.nameplatePreviewUpdate) == "function" then
        controls.nameplatePreviewUpdate()
      end
    end,
    "SETTINGS_NAMEPLATE_SHOW_REMAINING"
  )

  controls.nameplateFontSize, yOffset = CreateSettingsSlider(
    canvas,
    yOffset,
    labels.SETTINGS_NAMEPLATE_FONT_SIZE or "Font size",
    8,
    28,
    1,
    function()
      return tonumber(config.getDB().mobNameplateFontSize) or 14
    end,
    function(val)
      local db = config.getDB()
      db.mobNameplateFontSize = tonumber(val) or 14
      if type(config.onMobNameplateChange) == "function" then
        config.onMobNameplateChange()
      end
      if type(controls.nameplatePreviewUpdate) == "function" then
        controls.nameplatePreviewUpdate()
      end
    end,
    function(val)
      return string.format("%d", val)
    end,
    "SETTINGS_NAMEPLATE_FONT_SIZE"
  )

  controls.nameplatePosition, yOffset = CreateSettingsOptionSelector(
    canvas,
    yOffset,
    "SETTINGS_NAMEPLATE_POSITION",
    labels.SETTINGS_NAMEPLATE_POSITION or "Position",
    {
      {
        value = "LEFT",
        labelKey = "SETTINGS_NAMEPLATE_POS_LEFT",
        fallback = labels.SETTINGS_NAMEPLATE_POS_LEFT or "Left",
        width = 70,
      },
      {
        value = "RIGHT",
        labelKey = "SETTINGS_NAMEPLATE_POS_RIGHT",
        fallback = labels.SETTINGS_NAMEPLATE_POS_RIGHT or "Right",
        width = 70,
      },
      {
        value = "TOP",
        labelKey = "SETTINGS_NAMEPLATE_POS_TOP",
        fallback = labels.SETTINGS_NAMEPLATE_POS_TOP or "Top",
        width = 70,
      },
      {
        value = "BOTTOM",
        labelKey = "SETTINGS_NAMEPLATE_POS_BOTTOM",
        fallback = labels.SETTINGS_NAMEPLATE_POS_BOTTOM or "Bottom",
        width = 70,
      },
    },
    config.getL,
    function()
      return NormalizeNameplatePosition(config.getDB().mobNameplatePosition)
    end,
    function(pos)
      local db = config.getDB()
      db.mobNameplatePosition = NormalizeNameplatePosition(pos)
      if type(config.onMobNameplateChange) == "function" then
        config.onMobNameplateChange()
      end
      if type(controls.nameplatePreviewUpdate) == "function" then
        controls.nameplatePreviewUpdate()
      end
    end,
    NormalizeNameplatePosition,
    true
  )

  controls.nameplateXOffset, yOffset = CreateSettingsSlider(
    canvas,
    yOffset,
    labels.SETTINGS_NAMEPLATE_X_OFFSET or "X offset",
    -50,
    50,
    1,
    function()
      return tonumber(config.getDB().mobNameplateXOffset) or 0
    end,
    function(val)
      local db = config.getDB()
      db.mobNameplateXOffset = tonumber(val) or 0
      if type(config.onMobNameplateChange) == "function" then
        config.onMobNameplateChange()
      end
      if type(controls.nameplatePreviewUpdate) == "function" then
        controls.nameplatePreviewUpdate()
      end
    end,
    function(val)
      return string.format("%d", val)
    end,
    "SETTINGS_NAMEPLATE_X_OFFSET"
  )

  controls.nameplateYOffset, yOffset = CreateSettingsSlider(
    canvas,
    yOffset,
    labels.SETTINGS_NAMEPLATE_Y_OFFSET or "Y offset",
    -50,
    50,
    1,
    function()
      return tonumber(config.getDB().mobNameplateYOffset) or 0
    end,
    function(val)
      local db = config.getDB()
      db.mobNameplateYOffset = tonumber(val) or 0
      if type(config.onMobNameplateChange) == "function" then
        config.onMobNameplateChange()
      end
      if type(controls.nameplatePreviewUpdate) == "function" then
        controls.nameplatePreviewUpdate()
      end
    end,
    function(val)
      return string.format("%d", val)
    end,
    "SETTINGS_NAMEPLATE_Y_OFFSET"
  )

  yOffset = yOffset - 4

  local previewLabel = canvas:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  local tnPreview = Colors.TEXT_NORMAL or { 0.85, 0.85, 0.9 }
  previewLabel:SetTextColor(tnPreview[1], tnPreview[2], tnPreview[3], 1)
  previewLabel:SetPoint("TOPLEFT", canvas, "TOPLEFT", PADDING_X, yOffset - 6)
  previewLabel:SetText(labels.SETTINGS_NAMEPLATE_PREVIEW or "Preview")
  controls.nameplatePreviewLabel = previewLabel

  local preview = CreateFrame("Frame", nil, canvas, "BackdropTemplate")
  preview:SetSize(140, 24)
  preview:SetPoint("TOPLEFT", canvas, "TOPLEFT", PADDING_X + 160, yOffset - 4)
  if type(preview.SetBackdrop) == "function" then
    preview:SetBackdrop({
      bgFile = "Interface\\Buttons\\WHITE8X8",
      edgeFile = "Interface\\Buttons\\WHITE8X8",
      edgeSize = 1,
      insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    if type(preview.SetBackdropColor) == "function" then
      preview:SetBackdropColor(0.55, 0.12, 0.12, 0.75)
    end
    if type(preview.SetBackdropBorderColor) == "function" then
      preview:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.9)
    end
  end

  preview.name = preview:CreateFontString(nil, "OVERLAY", "GameFontNormalSmallOutline")
  preview.name:SetPoint("CENTER", preview, "CENTER", 0, 0)
  preview.name:SetText(labels.SETTINGS_NAMEPLATE_PREVIEW_MOB or "Test Mob")
  if type(preview.name.SetTextColor) == "function" then
    preview.name:SetTextColor(1, 1, 1, 1)
  end

  preview.overlay = preview:CreateFontString(nil, "OVERLAY", "GameFontNormalOutline")
  if type(preview.overlay.SetTextColor) == "function" then
    preview.overlay:SetTextColor(1, 1, 1, 1)
  end
  controls.nameplatePreview = preview

  local function UpdatePreview()
    local db = config.getDB()
    local enabled = db.mobNameplateEnabled == true
    if not enabled then
      preview.overlay:SetText("")
      if type(preview.overlay.Hide) == "function" then
        preview.overlay:Hide()
      end
      return
    end

    local showPercent = db.mobNameplateShowPercent ~= false
    local parts = {}
    if showPercent then
      local text = "1.16%"
      if db.mobNameplateShowRemaining ~= false then
        text = text .. "/24.34%"
      end
      parts[#parts + 1] = text
    end
    if #parts == 0 then
      preview.overlay:SetText("")
      if type(preview.overlay.Hide) == "function" then
        preview.overlay:Hide()
      end
      return
    end

    preview.overlay:SetText(table.concat(parts, " | "))
    if type(preview.overlay.Show) == "function" then
      preview.overlay:Show()
    end

    local pos = NormalizeNameplatePosition(db.mobNameplatePosition)
    local xo = tonumber(db.mobNameplateXOffset) or 0
    local yo = tonumber(db.mobNameplateYOffset) or 0
    if type(preview.overlay.ClearAllPoints) == "function" then
      preview.overlay:ClearAllPoints()
    end
    if pos == "LEFT" then
      preview.overlay:SetPoint("RIGHT", preview, "LEFT", xo, yo)
    elseif pos == "TOP" then
      preview.overlay:SetPoint("BOTTOM", preview, "TOP", xo, yo)
    elseif pos == "BOTTOM" then
      preview.overlay:SetPoint("TOP", preview, "BOTTOM", xo, yo)
    else
      preview.overlay:SetPoint("LEFT", preview, "RIGHT", xo, yo)
    end

    local fontSize = tonumber(db.mobNameplateFontSize) or 14
    if type(preview.overlay.GetFont) == "function" and type(preview.overlay.SetFont) == "function" then
      local fontPath, _, flags = preview.overlay:GetFont()
      if type(fontPath) ~= "string" or fontPath == "" then
        fontPath = "Fonts\\FRIZQT__.TTF"
      end
      preview.overlay:SetFont(fontPath, fontSize, flags or "OUTLINE")
    end
  end

  controls.nameplatePreviewUpdate = UpdatePreview
  UpdatePreview()

  yOffset = yOffset - (LINE_HEIGHT + 16)

  return yOffset
end

local function BuildBehaviorSettingsSection(canvas, yOffset, labels, config, controls)
  controls.behaviorHeader, yOffset =
    CreateSectionHeader(canvas, yOffset, labels.SETTINGS_SECTION_BEHAVIOR or "Behavior")
  controls.behaviorHint, yOffset = CreateSectionNote(
    canvas,
    yOffset,
    labels.SETTINGS_SECTION_BEHAVIOR_HINT or "Sync, auto-open, combat, and raid handling."
  )
  if controls.behaviorHint then
    controls.behaviorHint._sectionKey = "SETTINGS_SECTION_BEHAVIOR"
  end

  controls.sync, yOffset = CreateSettingsCheckbox(
    canvas,
    yOffset,
    labels.SETTINGS_SYNC_ENABLED or "Addon Sync",
    function()
      local db = config.getDB()
      return db.syncEnabled ~= false
    end,
    function(checked)
      local db = config.getDB()
      db.syncEnabled = checked
      if type(config.onSyncToggle) == "function" then
        config.onSyncToggle(checked)
      end
    end
  )

  controls.lockMainFramePosition, yOffset = CreateSettingsCheckbox(
    canvas,
    yOffset,
    labels.SETTINGS_LOCK_MAIN_FRAME_POSITION or "Lock main frame position",
    function()
      local db = config.getDB()
      return db.lockMainFramePosition ~= false
    end,
    function(checked)
      local db = config.getDB()
      db.lockMainFramePosition = checked
      if type(config.onMainFramePositionLockToggle) == "function" then
        config.onMainFramePositionLockToggle(checked)
      end
    end,
    "SETTINGS_LOCK_MAIN_FRAME_POSITION"
  )

  controls.combatFadeMM, yOffset = CreateSettingsCheckbox(
    canvas,
    yOffset,
    labels.SETTINGS_COMBAT_FADE_MM or "Fade out in Combat (M2 only)",
    function()
      local db = config.getDB()
      return db.combatFadeMM == true
    end,
    function(checked)
      local db = config.getDB()
      db.combatFadeMM = checked
      if type(config.onCombatFadeMMToggle) == "function" then
        config.onCombatFadeMMToggle(checked)
      end
    end,
    "SETTINGS_COMBAT_FADE_MM"
  )

  -- Group the four auto-show/hide triggers together with an explanatory note.
  -- They are evaluated independently; multiple can be active at once.
  controls.autoTriggersNote, yOffset = CreateSectionNote(
    canvas,
    yOffset,
    labels.SETTINGS_AUTO_TRIGGERS_NOTE or "Automatic show/hide: each trigger below is independent. Hover for details."
  )
  if controls.autoTriggersNote then
    controls.autoTriggersNote._sectionKey = "SETTINGS_AUTO_TRIGGERS_NOTE"
  end

  controls.autoShowStartup, yOffset = CreateSettingsCheckbox(
    canvas,
    yOffset,
    labels.SETTINGS_AUTO_SHOW_MAIN_FRAME_ON_STARTUP or "Show on Login / Reload",
    function()
      local db = config.getDB()
      return db.autoShowMainFrameOnStartup ~= false
    end,
    function(checked)
      local db = config.getDB()
      db.autoShowMainFrameOnStartup = checked
      if type(config.onAutoShowMainFrameOnStartupToggle) == "function" then
        config.onAutoShowMainFrameOnStartupToggle(checked)
      end
    end,
    "SETTINGS_AUTO_SHOW_MAIN_FRAME_ON_STARTUP"
  )

  controls.autoOpen, yOffset = CreateSettingsCheckbox(
    canvas,
    yOffset,
    labels.SETTINGS_AUTO_OPEN_QUEUE or "Auto-Open on M+ Queue",
    function()
      local db = config.getDB()
      return db.autoOpenOnQueue ~= false
    end,
    function(checked)
      local db = config.getDB()
      db.autoOpenOnQueue = checked
      if type(config.onAutoOpenQueueToggle) == "function" then
        config.onAutoOpenQueueToggle(checked)
      end
    end,
    "SETTINGS_AUTO_OPEN_QUEUE"
  )

  controls.autoOpenKeyEnd, yOffset = CreateSettingsCheckbox(
    canvas,
    yOffset,
    labels.SETTINGS_AUTO_OPEN_MAIN_FRAME_ON_KEY_END or "Auto-Open on Key End",
    function()
      local db = config.getDB()
      return db.autoOpenMainFrameOnKeyEnd ~= false
    end,
    function(checked)
      local db = config.getDB()
      db.autoOpenMainFrameOnKeyEnd = checked
      if type(config.onAutoOpenMainFrameOnKeyEndToggle) == "function" then
        config.onAutoOpenMainFrameOnKeyEndToggle(checked)
      end
    end,
    "SETTINGS_AUTO_OPEN_MAIN_FRAME_ON_KEY_END"
  )

  controls.autoCloseOnKeyStart, yOffset = CreateSettingsCheckbox(
    canvas,
    yOffset,
    labels.SETTINGS_AUTO_CLOSE_ON_KEY_START or "Auto-close when key starts",
    function()
      local db = config.getDB()
      return db.autoCloseOnKeyStart == true
    end,
    function(checked)
      local db = config.getDB()
      db.autoCloseOnKeyStart = checked
      if type(config.onAutoCloseOnKeyStartToggle) == "function" then
        config.onAutoCloseOnKeyStartToggle(checked)
      end
    end,
    "SETTINGS_AUTO_CLOSE_ON_KEY_START"
  )

  controls.autoCloseOnSoloChange, yOffset = CreateSettingsCheckbox(
    canvas,
    yOffset,
    labels.SETTINGS_AUTO_CLOSE_ON_SOLO_CHANGE or "Auto-close when leaving the group",
    function()
      local db = config.getDB()
      return db.autoCloseOnSoloChange == true
    end,
    function(checked)
      local db = config.getDB()
      db.autoCloseOnSoloChange = checked
      if type(config.onAutoCloseOnSoloChangeToggle) == "function" then
        config.onAutoCloseOnSoloChangeToggle(checked)
      end
    end,
    "SETTINGS_AUTO_CLOSE_ON_SOLO_CHANGE"
  )

  -- Raid behaviour is a one-option future stub. Rendering it as a selector
  -- with a single button confuses users more than it informs them. Show a
  -- status note that explains the current always-hide behaviour instead;
  -- db.raidTransitionBehavior stays in the schema so the stub is still
  -- threaded through the runtime untouched.
  controls.raidBehaviorNote, yOffset = CreateSectionNote(
    canvas,
    yOffset,
    labels.SETTINGS_RAID_TRANSITION_NOTE or "Raid: main window hides automatically while in a raid group."
  )
  if controls.raidBehaviorNote then
    controls.raidBehaviorNote._sectionKey = "SETTINGS_RAID_TRANSITION_BEHAVIOR"
  end

  return yOffset
end

local SOUND_SETTING_FALLBACKS = {
  leader_transfer = {
    labelKey = "SETTINGS_SOUND_LEAD_ENABLED",
    labelFallback = "Sound: Lead Transfer",
    settingKey = "soundLeadEnabled",
    defaultEnabled = true,
  },
  group_join = {
    labelKey = "SETTINGS_SOUND_GROUP_JOIN_ENABLED",
    labelFallback = "Sound: Full Group",
    settingKey = "soundGroupJoinEnabled",
    defaultEnabled = true,
  },
  portal_available = {
    labelKey = "SETTINGS_SOUND_PORTAL_AVAILABLE",
    labelFallback = "Sound: Incoming Summon",
    settingKey = "soundPortalAvailableEnabled",
    defaultEnabled = true,
  },
  battle_res = {
    labelKey = "SETTINGS_SOUND_BATTLE_RES",
    labelFallback = "Sound: Battle Res",
    settingKey = "soundBattleResEnabled",
    defaultEnabled = true,
  },
  bloodlust = {
    labelKey = "SETTINGS_SOUND_BLOODLUST",
    labelFallback = "Sound: Bloodlust",
    settingKey = "soundBloodlustEnabled",
    defaultEnabled = true,
  },
}

local function GetSoundSettingEntries()
  local soundUtils = addonTable.SoundUtils
  local registry = type(soundUtils) == "table" and type(soundUtils.Registry) == "table" and soundUtils.Registry or nil
  local order = type(soundUtils) == "table" and type(soundUtils.SettingsOrder) == "table" and soundUtils.SettingsOrder
    or { "leader_transfer", "group_join", "portal_available", "battle_res", "bloodlust" }
  local entries = {}

  for _, key in ipairs(order) do
    local entry = registry and registry[key] or nil
    local fallback = SOUND_SETTING_FALLBACKS[key] or {}
    entries[#entries + 1] = {
      key = key,
      labelKey = type(entry) == "table" and entry.labelKey or fallback.labelKey,
      labelFallback = type(entry) == "table" and entry.labelFallback or fallback.labelFallback,
      settingKey = type(entry) == "table" and entry.settingKey or fallback.settingKey,
      defaultEnabled = type(entry) == "table" and entry.defaultEnabled or fallback.defaultEnabled,
    }
  end

  return entries
end

local function BuildSoundSettingsSection(canvas, yOffset, labels, config, controls)
  controls.soundHeader, yOffset = CreateSectionHeader(canvas, yOffset, labels.SETTINGS_SECTION_SOUNDS or "Sounds")
  if controls.soundHeader then
    controls.soundHeader._sectionKey = "SETTINGS_SECTION_SOUNDS"
  end

  controls.soundHint, yOffset =
    CreateSectionNote(canvas, yOffset, labels.SETTINGS_SECTION_SOUNDS_HINT or "Toggle the built-in audio cues.")
  if controls.soundHint then
    controls.soundHint._sectionKey = "SETTINGS_SECTION_SOUNDS"
  end

  controls.soundChecks = controls.soundChecks or {}

  for _, entry in ipairs(GetSoundSettingEntries()) do
    local checkbox, nextY = CreateSettingsCheckbox(
      canvas,
      yOffset,
      labels[entry.labelKey] or entry.labelFallback or entry.labelKey or entry.key or "Sound",
      function()
        local db = config.getDB()
        local settingKey = entry.settingKey
        if type(settingKey) == "string" and settingKey ~= "" then
          local stored = db[settingKey]
          if stored ~= nil then
            return stored == true
          end
        end
        return entry.defaultEnabled ~= false
      end,
      function(checked)
        local db = config.getDB()
        local settingKey = entry.settingKey
        if type(settingKey) == "string" and settingKey ~= "" then
          db[settingKey] = checked
        end
      end,
      entry.labelKey
    )

    if checkbox and checkbox.check then
      checkbox.check._sectionKey = "SETTINGS_SECTION_SOUNDS"
      checkbox.check._soundKey = entry.key
    end
    controls.soundChecks[entry.key] = checkbox
    yOffset = nextY
  end

  return yOffset
end

local function BuildChatSettingsSection(canvas, yOffset, labels, config, controls)
  controls.chatHeader, yOffset =
    CreateSectionHeader(canvas, yOffset, labels.SETTINGS_SECTION_CHAT or "Chat Announcements")
  if controls.chatHeader then
    controls.chatHeader._sectionKey = "SETTINGS_SECTION_CHAT"
  end

  controls.chatHint, yOffset = CreateSectionNote(
    canvas,
    yOffset,
    labels.SETTINGS_SECTION_CHAT_HINT or "Toggle automatic chat messages during Mythic+ runs."
  )
  if controls.chatHint then
    controls.chatHint._sectionKey = "SETTINGS_SECTION_CHAT"
  end

  controls.chatAnnounceBR, yOffset = CreateSettingsCheckbox(
    canvas,
    yOffset,
    labels.SETTINGS_CHAT_BR_ANNOUNCE or "Chat: Announce Battle Res usage in M+",
    function()
      local db = config.getDB()
      return db.chatAnnounceBR ~= false
    end,
    function(checked)
      local db = config.getDB()
      db.chatAnnounceBR = checked
    end,
    "SETTINGS_CHAT_BR_ANNOUNCE"
  )

  controls.chatAnnounceLust, yOffset = CreateSettingsCheckbox(
    canvas,
    yOffset,
    labels.SETTINGS_CHAT_LUST_ANNOUNCE or "Chat: Announce Bloodlust casts in M+",
    function()
      local db = config.getDB()
      return db.chatAnnounceLust ~= false
    end,
    function(checked)
      local db = config.getDB()
      db.chatAnnounceLust = checked
    end,
    "SETTINGS_CHAT_LUST_ANNOUNCE"
  )

  return yOffset
end

local function BuildDebugSettingsSection(canvas, yOffset, labels, config, controls)
  controls.debugHeader, yOffset = CreateSectionHeader(canvas, yOffset, labels.SETTINGS_SECTION_DEBUG or "Debug")
  controls.debugHint, yOffset = CreateSectionNote(
    canvas,
    yOffset,
    labels.SETTINGS_SECTION_DEBUG_HINT or "Logs reset on reload and help with support."
  )
  if controls.debugHint then
    controls.debugHint._sectionKey = "SETTINGS_SECTION_DEBUG"
  end

  controls.queueDebug, yOffset = CreateSettingsCheckbox(
    canvas,
    yOffset,
    labels.SETTINGS_QUEUE_DEBUG or "Queue Debug Log (resets on reload)",
    function()
      if type(config.getQueueDebugEnabled) == "function" then
        return config.getQueueDebugEnabled()
      end
      return false
    end,
    function(checked)
      if type(config.onQueueDebugToggle) == "function" then
        config.onQueueDebugToggle(checked)
      end
    end,
    "SETTINGS_QUEUE_DEBUG"
  )

  controls.clearQueueDebugBtn, yOffset = CreateSettingsActionButton(
    canvas,
    yOffset,
    labels.SETTINGS_QUEUE_DEBUG_CLEAR or "Clear Queue Debug Log",
    240,
    function()
      if type(config.onClearQueueDebugLog) == "function" then
        config.onClearQueueDebugLog()
      end
    end,
    "SETTINGS_QUEUE_DEBUG_CLEAR",
    nil
  )

  controls.runtimeLog, yOffset = CreateSettingsCheckbox(
    canvas,
    yOffset,
    labels.SETTINGS_RUNTIME_LOG or "Runtime Log (resets on reload)",
    function()
      if type(config.getRuntimeLogEnabled) == "function" then
        return config.getRuntimeLogEnabled()
      end
      return false
    end,
    function(checked)
      if type(config.onRuntimeLogToggle) == "function" then
        config.onRuntimeLogToggle(checked)
      end
    end,
    "SETTINGS_RUNTIME_LOG"
  )

  controls.clearRuntimeLogBtn, yOffset = CreateSettingsActionButton(
    canvas,
    yOffset,
    labels.SETTINGS_RUNTIME_LOG_CLEAR or "Clear Runtime Log",
    240,
    function()
      if type(config.onClearRuntimeLog) == "function" then
        config.onClearRuntimeLog()
      end
    end,
    "SETTINGS_RUNTIME_LOG_CLEAR",
    nil
  )

  controls.columnGuides, yOffset = CreateSettingsCheckbox(
    canvas,
    yOffset,
    labels.SETTINGS_ROSTER_COLUMN_GUIDES or "Column Guides",
    function()
      local db = config.getDB()
      return db.showRosterColumnGuides == true
    end,
    function(checked)
      local db = config.getDB()
      db.showRosterColumnGuides = checked
      if type(config.onRosterColumnGuidesToggle) == "function" then
        config.onRosterColumnGuidesToggle(checked)
      end
    end,
    "SETTINGS_ROSTER_COLUMN_GUIDES"
  )

  return yOffset
end

local function BuildResetSection(canvas, yOffset, labels, config, controls)
  controls.resetHint, yOffset = CreateSectionNote(
    canvas,
    yOffset,
    labels.SETTINGS_SECTION_RESET_HINT or "Use these actions to restore the frame or all settings."
  )
  if controls.resetHint then
    controls.resetHint._sectionKey = "SETTINGS_SECTION_RESET"
  end
  controls.resetDBBtn, yOffset = CreateSettingsActionButton(
    canvas,
    yOffset,
    labels.SETTINGS_RESET_DB or "Reset All Settings",
    320,
    function()
      if type(config.onResetDB) == "function" then
        config.onResetDB()
      end
    end,
    {
      settingKey = "SETTINGS_RESET_DB",
      confirmText = labels.SETTINGS_RESET_CONFIRM_TEXT or "Do you really want to reset?",
    }
  )

  return yOffset
end

local BETA_ISSUES_URL = "https://github.com/byi77/isilive/issues"

local function BuildBetaSection(canvas, yOffset, labels, controls)
  controls.betaHeader, yOffset = CreateSectionHeader(canvas, yOffset, labels.SETTINGS_BETA_NOTICE or "Beta")

  local noticeText = canvas:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  noticeText:SetTextColor(1, 0.75, 0.2, 1)
  noticeText:SetPoint("TOPLEFT", canvas, "TOPLEFT", PADDING_X, yOffset - 4)
  noticeText:SetJustifyH("LEFT")
  noticeText:SetWidth(math.max(240, SETTINGS_CONTENT_WIDTH - (PADDING_X * 2)))
  if type(noticeText.SetWordWrap) == "function" then
    noticeText:SetWordWrap(true)
  end
  noticeText:SetText(labels.BETA_NOTICE_TEXT or "This addon is in BETA status. Please report bugs at:")
  controls.betaNoticeText = noticeText

  yOffset = yOffset - MeasureWrappedTextHeight(noticeText, LINE_HEIGHT, 6)

  local function CreateBetaUrlBox(text, offsetY)
    local urlBox = CreateFrame("EditBox", nil, canvas, "InputBoxTemplate")
    urlBox:SetSize(SETTINGS_CONTENT_WIDTH - (PADDING_X * 2) - 12, 20)
    urlBox:SetPoint("TOPLEFT", canvas, "TOPLEFT", PADDING_X + 6, offsetY - 4)
    urlBox:SetAutoFocus(false)
    urlBox:SetText(text)
    urlBox:SetCursorPosition(0)
    urlBox:SetScript("OnEscapePressed", function(self)
      self:ClearFocus()
    end)
    urlBox:SetScript("OnEditFocusGained", function(self)
      self:HighlightText()
    end)
    return urlBox
  end

  local urlBox = CreateFrame("EditBox", nil, canvas, "InputBoxTemplate")
  urlBox:SetSize(SETTINGS_CONTENT_WIDTH - (PADDING_X * 2) - 12, 20)
  urlBox:SetPoint("TOPLEFT", canvas, "TOPLEFT", PADDING_X + 6, yOffset - 4)
  urlBox:SetAutoFocus(false)
  urlBox:SetText(BETA_ISSUES_URL)
  urlBox:SetCursorPosition(0)
  urlBox:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
  end)
  urlBox:SetScript("OnEditFocusGained", function(self)
    self:HighlightText()
  end)
  controls.betaUrlBox = urlBox

  yOffset = yOffset - LINE_HEIGHT

  local betaCommentsUrl = "https://www.curseforge.com/wow/addons/isilive/comments"
  controls.betaCommentsUrlBox = CreateBetaUrlBox(betaCommentsUrl, yOffset)

  return yOffset - LINE_HEIGHT
end

local function RefreshSettingsControls(controls, config)
  local freshL = config.getL()
  local db = config.getDB()

  if controls.introText then
    controls.introText:SetText(
      freshL.SETTINGS_PAGE_HINT or "Use the sections below to tune layout, behavior, and audio cues."
    )
  end
  controls.generalHeader:SetText(freshL.SETTINGS_SECTION_GENERAL or "General")
  if controls.generalHint then
    controls.generalHint:SetText(
      freshL.SETTINGS_SECTION_GENERAL_HINT or "Language, startup behavior, and utility links."
    )
  end
  controls.displayHeader:SetText(freshL.SETTINGS_SECTION_DISPLAY or "Display")
  if controls.displayHint then
    controls.displayHint:SetText(freshL.SETTINGS_SECTION_DISPLAY_HINT or "Scale, opacity, and UI recovery tools.")
  end
  if controls.nameplatesHeader then
    controls.nameplatesHeader:SetText(freshL.SETTINGS_SECTION_NAMEPLATES or "Nameplates")
  end
  if controls.nameplatesHint then
    controls.nameplatesHint:SetText(
      freshL.SETTINGS_SECTION_NAMEPLATES_HINT or "Enemy forces overlay on Mythic+ nameplates."
    )
  end
  if controls.nameplatesExternalWarn then
    controls.nameplatesExternalWarn:SetText(
      freshL.SETTINGS_NAMEPLATE_EXTERNAL_WARN
        or "Plater or Platynator detected: if that addon already shows M+ count, leave this off."
    )
  end
  controls.behaviorHeader:SetText(freshL.SETTINGS_SECTION_BEHAVIOR or "Behavior")
  if controls.behaviorHint then
    controls.behaviorHint:SetText(
      freshL.SETTINGS_SECTION_BEHAVIOR_HINT or "Sync, auto-open, combat, and raid handling."
    )
  end
  if controls.soundHeader then
    controls.soundHeader:SetText(freshL.SETTINGS_SECTION_SOUNDS or "Sounds")
  end
  if controls.soundHint then
    controls.soundHint:SetText(freshL.SETTINGS_SECTION_SOUNDS_HINT or "Toggle the built-in audio cues.")
  end
  if controls.chatHeader then
    controls.chatHeader:SetText(freshL.SETTINGS_SECTION_CHAT or "Chat Announcements")
  end
  if controls.chatHint then
    controls.chatHint:SetText(
      freshL.SETTINGS_SECTION_CHAT_HINT or "Toggle automatic chat messages during Mythic+ runs."
    )
  end
  if controls.chatAnnounceBR and controls.chatAnnounceBR.label then
    controls.chatAnnounceBR.label:SetText(freshL.SETTINGS_CHAT_BR_ANNOUNCE or "Chat: Announce Battle Res usage in M+")
    controls.chatAnnounceBR.check:SetChecked(db.chatAnnounceBR ~= false)
  end
  if controls.chatAnnounceLust and controls.chatAnnounceLust.label then
    controls.chatAnnounceLust.label:SetText(
      freshL.SETTINGS_CHAT_LUST_ANNOUNCE or "Chat: Announce Bloodlust casts in M+"
    )
    controls.chatAnnounceLust.check:SetChecked(db.chatAnnounceLust ~= false)
  end
  controls.debugHeader:SetText(freshL.SETTINGS_SECTION_DEBUG or "Debug")
  if controls.debugHint then
    controls.debugHint:SetText(freshL.SETTINGS_SECTION_DEBUG_HINT or "Logs reset on reload and help with support.")
  end
  controls.lang.label:SetText(freshL.SETTINGS_LANGUAGE or "Language")
  controls.combatLog.label:SetText(freshL.SETTINGS_COMBAT_LOGGING or "Advanced Combat Logging")
  controls.dmReset.label:SetText(freshL.SETTINGS_DM_RESET or "Reset Blizzard Damage Meter on dungeon entry")
  controls.escPanel.label:SetText(freshL.SETTINGS_ESC_PANEL or "Show ESC Menu Shortcuts")
  controls.bgAlpha.label:SetText(freshL.SETTINGS_BG_ALPHA or "Background Opacity")
  if controls.statsBoxEnabled and controls.statsBoxEnabled.label then
    controls.statsBoxEnabled.label:SetText(GetStatsBoxSettingLabel(config, "enabled")) -- i18n-ok
  end
  if controls.statsBoxLocked and controls.statsBoxLocked.label then
    controls.statsBoxLocked.label:SetText(GetStatsBoxSettingLabel(config, "locked")) -- i18n-ok
  end
  if controls.statsBoxBgAlpha and controls.statsBoxBgAlpha.label then
    controls.statsBoxBgAlpha.label:SetText(GetStatsBoxSettingLabel(config, "alpha")) -- i18n-ok
  end
  if controls.statsBoxFontSizeOffset and controls.statsBoxFontSizeOffset.label then
    controls.statsBoxFontSizeOffset.label:SetText(GetStatsBoxSettingLabel(config, "fontSize")) -- i18n-ok
  end
  controls.uiScale.label:SetText(freshL.SETTINGS_UI_SCALE or "UI Scale")
  if controls.resetUiBtn then
    controls.resetUiBtn.label:SetText(freshL.SETTINGS_RESET_UI_POSITION or "/isilive resetui")
  end
  if controls.resetUiHint then
    controls.resetUiHint:SetText(
      freshL.SETTINGS_RESET_UI_POSITION_HINT or "Default: position center, UI scale 100%, background opacity 50%"
    )
    if type(controls.resetUiHint.SetWidth) == "function" then
      controls.resetUiHint:SetWidth(304)
    end
  end
  controls.minimapBtn.label:SetText(freshL.SETTINGS_MINIMAP_BUTTON or "Minimap Button")
  controls.sync.label:SetText(freshL.SETTINGS_SYNC_ENABLED or "Addon Sync")
  controls.autoOpen.label:SetText(freshL.SETTINGS_AUTO_OPEN_QUEUE or "Auto-Open on M+ Queue")
  controls.autoCloseOnKeyStart.label:SetText(freshL.SETTINGS_AUTO_CLOSE_ON_KEY_START or "Auto-close when key starts")
  controls.autoCloseOnSoloChange.label:SetText(
    freshL.SETTINGS_AUTO_CLOSE_ON_SOLO_CHANGE or "Auto-close when leaving the group"
  )
  controls.lockMainFramePosition.label:SetText(freshL.SETTINGS_LOCK_MAIN_FRAME_POSITION or "Lock main frame position")
  controls.combatFadeMM.label:SetText(freshL.SETTINGS_COMBAT_FADE_MM or "Fade out in Combat (M2 only)")
  controls.autoShowStartup.label:SetText(freshL.SETTINGS_AUTO_SHOW_MAIN_FRAME_ON_STARTUP or "Show on Login / Reload")
  controls.autoOpenKeyEnd.label:SetText(freshL.SETTINGS_AUTO_OPEN_MAIN_FRAME_ON_KEY_END or "Auto-Open on Key End")
  if controls.raidBehavior then
    controls.raidBehavior.UpdateHighlight()
  end
  if controls.defaultLayout then
    controls.defaultLayout.UpdateHighlight()
  end
  controls.queueDebug.label:SetText(freshL.SETTINGS_QUEUE_DEBUG or "Queue Debug Log")
  controls.runtimeLog.label:SetText(freshL.SETTINGS_RUNTIME_LOG or "Runtime Log")
  if controls.clearQueueDebugBtn and controls.clearQueueDebugBtn.label then
    controls.clearQueueDebugBtn.label:SetText(freshL.SETTINGS_QUEUE_DEBUG_CLEAR or "Clear Queue Debug Log")
  end
  if controls.clearRuntimeLogBtn and controls.clearRuntimeLogBtn.label then
    controls.clearRuntimeLogBtn.label:SetText(freshL.SETTINGS_RUNTIME_LOG_CLEAR or "Clear Runtime Log")
  end

  if controls.nameMaxChars then
    controls.nameMaxChars.label:SetText(freshL.SETTINGS_NAME_MAX_CHARS or "Name Length")
  end
  if controls.tpColumns then
    controls.tpColumns.label:SetText(freshL.SETTINGS_TELEPORT_COLUMNS or "Teleport Grid Columns")
  end
  if controls.columnGuides then
    controls.columnGuides.label:SetText(freshL.SETTINGS_ROSTER_COLUMN_GUIDES or "Column Guides")
  end
  if controls.resetDBBtn then
    controls.resetDBBtn.label:SetText(freshL.SETTINGS_RESET_DB or "Reset All Settings")
  end
  if controls.resetHint then
    controls.resetHint:SetText(
      freshL.SETTINGS_SECTION_RESET_HINT or "Use these actions to restore the frame or all settings."
    )
  end
  if controls.portalNavigator then
    controls.portalNavigator.label:SetText(freshL.SETTINGS_SHOW_TIMEWAYS_NAVIGATOR or "Show Timeways Navigator")
  end
  if controls.soundChecks then
    for _, entry in ipairs(GetSoundSettingEntries()) do
      local soundControl = controls.soundChecks[entry.key]
      if soundControl then
        local fallback = SOUND_SETTING_FALLBACKS[entry.key] or {}
        soundControl.label:SetText(
          freshL[entry.labelKey]
            or fallback.labelFallback
            or fallback.labelKey
            or entry.labelKey
            or entry.key
            or "Sound"
        )
      end
    end
  end
  controls.lang.UpdateHighlight()
  controls.combatLog.check:SetChecked(GetCVarEnabled("advancedCombatLogging"))
  controls.dmReset.check:SetChecked(GetCVarEnabled("damageMeterResetOnNewInstance"))
  controls.escPanel.check:SetChecked(db.showEscPanel ~= false)
  controls.bgAlpha.SetValueSilently(type(db.bgAlpha) == "number" and db.bgAlpha or DEFAULT_BG_ALPHA)
  if controls.statsBoxEnabled then
    controls.statsBoxEnabled.check:SetChecked(db.statsBoxEnabled == true)
  end
  if controls.statsBoxLocked then
    controls.statsBoxLocked.check:SetChecked(db.statsBoxLocked == true)
  end
  if controls.statsBoxBgAlpha then
    controls.statsBoxBgAlpha.SetValueSilently(type(db.statsBoxBgAlpha) == "number" and db.statsBoxBgAlpha or 0)
  end
  if controls.statsBoxFontSizeOffset then
    controls.statsBoxFontSizeOffset.SetValueSilently(
      type(db.statsBoxFontSizeOffset) == "number" and db.statsBoxFontSizeOffset or 0
    )
  end
  controls.uiScale.SetValueSilently(type(db.uiScale) == "number" and db.uiScale or 1.0)
  controls.minimapBtn.check:SetChecked(db.showMinimapButton == true)
  controls.sync.check:SetChecked(db.syncEnabled ~= false)
  controls.autoOpen.check:SetChecked(db.autoOpenOnQueue ~= false)
  controls.autoCloseOnKeyStart.check:SetChecked(db.autoCloseOnKeyStart == true)
  controls.autoCloseOnSoloChange.check:SetChecked(db.autoCloseOnSoloChange == true)
  controls.lockMainFramePosition.check:SetChecked(db.lockMainFramePosition ~= false)
  controls.combatFadeMM.check:SetChecked(db.combatFadeMM == true)
  controls.autoShowStartup.check:SetChecked(db.autoShowMainFrameOnStartup ~= false)
  controls.autoOpenKeyEnd.check:SetChecked(db.autoOpenMainFrameOnKeyEnd ~= false)
  controls.queueDebug.check:SetChecked(
    type(config.getQueueDebugEnabled) == "function" and config.getQueueDebugEnabled() or false
  )
  controls.runtimeLog.check:SetChecked(
    type(config.getRuntimeLogEnabled) == "function" and config.getRuntimeLogEnabled() or false
  )
  if controls.columnGuides then
    controls.columnGuides.check:SetChecked(db.showRosterColumnGuides == true)
  end
  if controls.portalNavigator then
    controls.portalNavigator.check:SetChecked(db.showPortalNavigator ~= false)
  end
  if controls.soundChecks then
    for _, entry in ipairs(GetSoundSettingEntries()) do
      local soundControl = controls.soundChecks[entry.key]
      if soundControl then
        local settingKey = entry.settingKey
        local defaultEnabled = entry.defaultEnabled ~= false
        local nextValue = defaultEnabled
        if type(settingKey) == "string" and settingKey ~= "" and db[settingKey] ~= nil then
          nextValue = db[settingKey] == true
        end
        soundControl.check:SetChecked(nextValue)
      end
    end
  end
  if controls.lfgFlags then
    controls.lfgFlags.label:SetText(freshL.SETTINGS_LFG_FLAGS or "Group Finder: Language Flags")
    controls.lfgFlags.check:SetChecked(db.lfgFlagsEnabled ~= false)
  end
  if controls.tooltipFlags then
    controls.tooltipFlags.label:SetText(freshL.SETTINGS_TOOLTIP_FLAGS or "Tooltip: Language Flags")
    controls.tooltipFlags.check:SetChecked(db.tooltipFlagsEnabled ~= false)
  end
  if controls.inviteHint then
    controls.inviteHint.label:SetText(freshL.SETTINGS_INVITE_HINT_ENABLED or "LFG invite hint")
    controls.inviteHint.check:SetChecked(db.inviteHintEnabled ~= false)
  end
  if controls.acceptedInviteNotice then
    controls.acceptedInviteNotice.label:SetText(
      freshL.SETTINGS_ACCEPTED_INVITE_NOTICE_ENABLED or "Accepted-invite notice"
    )
    controls.acceptedInviteNotice.check:SetChecked(db.acceptedInviteNoticeEnabled ~= false)
  end
  if controls.nameplateDisplayMode and type(controls.nameplateDisplayMode.UpdateHighlight) == "function" then
    controls.nameplateDisplayMode.UpdateHighlight()
  end
  if controls.nameplateShowPercent then
    controls.nameplateShowPercent.label:SetText(freshL.SETTINGS_NAMEPLATE_SHOW_PERCENT or "Show percentage")
    controls.nameplateShowPercent.check:SetChecked(db.mobNameplateShowPercent ~= false)
  end
  if controls.nameplateShowRemaining then
    controls.nameplateShowRemaining.label:SetText(freshL.SETTINGS_NAMEPLATE_SHOW_REMAINING or "Show remaining needed")
    controls.nameplateShowRemaining.check:SetChecked(db.mobNameplateShowRemaining ~= false)
  end
  if controls.nameplatePosition and type(controls.nameplatePosition.UpdateHighlight) == "function" then
    controls.nameplatePosition.UpdateHighlight()
  end
  if controls.nameplateFontSize then
    controls.nameplateFontSize.label:SetText(freshL.SETTINGS_NAMEPLATE_FONT_SIZE or "Font size")
    controls.nameplateFontSize.SetValueSilently(tonumber(db.mobNameplateFontSize) or 14)
  end
  if controls.nameplateXOffset then
    controls.nameplateXOffset.label:SetText(freshL.SETTINGS_NAMEPLATE_X_OFFSET or "X offset")
    controls.nameplateXOffset.SetValueSilently(tonumber(db.mobNameplateXOffset) or 0)
  end
  if controls.nameplateYOffset then
    controls.nameplateYOffset.label:SetText(freshL.SETTINGS_NAMEPLATE_Y_OFFSET or "Y offset")
    controls.nameplateYOffset.SetValueSilently(tonumber(db.mobNameplateYOffset) or 0)
  end
  if controls.nameplatePreviewLabel then
    controls.nameplatePreviewLabel:SetText(freshL.SETTINGS_NAMEPLATE_PREVIEW or "Preview")
  end
  if type(controls.nameplatePreviewUpdate) == "function" then
    controls.nameplatePreviewUpdate()
  end

  if controls.nameMaxChars then
    controls.nameMaxChars.SetValueSilently(type(db.nameMaxChars) == "number" and db.nameMaxChars or 10)
  end
  if controls.tpColumns then
    controls.tpColumns.SetValueSilently(type(db.teleportColumns) == "number" and db.teleportColumns or 4)
  end
  if controls.betaHeader then
    controls.betaHeader:SetText(freshL.SETTINGS_BETA_NOTICE or "Beta")
  end
  if controls.betaNoticeText then
    controls.betaNoticeText:SetText(freshL.BETA_NOTICE_TEXT or "This addon is in BETA status. Please report bugs at:")
  end
end

function SettingsPanel.Create(opts)
  local config = ResolveSettingsOptions(opts)

  local blizzardSettings = rawget(_G, "Settings")
  if type(blizzardSettings) ~= "table" or type(blizzardSettings.RegisterCanvasLayoutCategory) ~= "function" then
    return nil
  end

  local canvas = CreateFrame("Frame", nil, rawget(_G, "UIParent"), "BackdropTemplate")
  ApplySettingsBackdrop(canvas)
  local scrollFrame = CreateFrame("ScrollFrame", nil, canvas, "UIPanelScrollFrameTemplate")
  scrollFrame:SetPoint("TOPLEFT", canvas, "TOPLEFT", PADDING_X, -PADDING_TOP)
  scrollFrame:SetPoint("BOTTOMRIGHT", canvas, "BOTTOMRIGHT", -PADDING_X, PADDING_TOP)
  if type(scrollFrame.EnableMouseWheel) == "function" then
    scrollFrame:EnableMouseWheel(true)
  end

  local content = CreateFrame("Frame", nil, scrollFrame)
  content:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)
  if type(content.SetWidth) == "function" then
    content:SetWidth(SETTINGS_CONTENT_WIDTH)
  elseif type(content.SetSize) == "function" then
    content:SetSize(SETTINGS_CONTENT_WIDTH, 1)
  end
  if type(scrollFrame.SetScrollChild) == "function" then
    scrollFrame:SetScrollChild(content)
  end

  if type(scrollFrame.SetScript) == "function" then
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
      local currentScroll = type(self.GetVerticalScroll) == "function" and (self:GetVerticalScroll() or 0) or 0
      local maxScroll = type(self.GetVerticalScrollRange) == "function" and (self:GetVerticalScrollRange() or 0) or 0
      local nextScroll = currentScroll - ((tonumber(delta) or 0) * SETTINGS_SCROLL_STEP)
      if nextScroll < 0 then
        nextScroll = 0
      elseif nextScroll > maxScroll then
        nextScroll = maxScroll
      end
      if type(self.SetVerticalScroll) == "function" then
        self:SetVerticalScroll(nextScroll)
      end
    end)
  end

  local L = config.getL()
  local controls = {}

  CreateSettingsTitle(content)

  local y = -PADDING_TOP - 30
  controls.introText, y = CreateSettingsIntro(
    content,
    y,
    L.SETTINGS_PAGE_HINT or "Use the sections below to tune layout, behavior, and audio cues."
  )
  y = BuildBetaSection(content, y, L, controls)
  y = y - SECTION_GAP
  y = BuildGeneralSettingsSection(content, y, L, config, controls)
  y = y - SECTION_GAP
  y = BuildDisplaySettingsSection(content, y, L, config, controls)
  y = y - SECTION_GAP
  y = BuildNameplatesSettingsSection(content, y, L, config, controls)
  y = y - SECTION_GAP
  y = BuildBehaviorSettingsSection(content, y, L, config, controls)
  y = y - SECTION_GAP
  y = BuildSoundSettingsSection(content, y, L, config, controls)
  y = y - SECTION_GAP
  y = BuildChatSettingsSection(content, y, L, config, controls)
  y = y - SECTION_GAP
  y = BuildDebugSettingsSection(content, y, L, config, controls)
  y = y - SECTION_GAP
  y = BuildResetSection(content, y, L, config, controls)

  local finalYOffset = tonumber(y) or 0
  local contentHeight = math.max(212, math.ceil(-finalYOffset + PADDING_TOP))
  local contentWidth = type(content.GetWidth) == "function" and content:GetWidth() or SETTINGS_CONTENT_WIDTH
  if type(content.SetSize) == "function" then
    content:SetSize(contentWidth, contentHeight)
  elseif type(content.SetHeight) == "function" then
    content:SetHeight(contentHeight)
  end
  if type(scrollFrame.UpdateScrollChildRect) == "function" then
    scrollFrame:UpdateScrollChildRect()
  end

  local category = blizzardSettings.RegisterCanvasLayoutCategory(canvas, ISILIVE_BRAND_TITLE)
  if type(blizzardSettings.RegisterAddOnCategory) == "function" then
    blizzardSettings.RegisterAddOnCategory(category)
  end

  local function Refresh()
    RefreshSettingsControls(controls, config)
  end

  return {
    category = category,
    canvas = canvas,
    scrollFrame = scrollFrame,
    content = content,
    Refresh = Refresh,
  }
end
