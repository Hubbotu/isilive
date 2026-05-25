local _, addonTable = ...
addonTable = addonTable or {}

local SettingsSections = {}
addonTable.SettingsSections = SettingsSections

local Colors = addonTable.UICommon and addonTable.UICommon.Colors or {}
local DEFAULT_BG_ALPHA = addonTable.UICommon and addonTable.UICommon.DEFAULT_BG_ALPHA or 0.50

local CreateSectionHeader = addonTable.SettingsControls.CreateSectionHeader
local CreateSectionNote = addonTable.SettingsControls.CreateSectionNote
local CreateSettingsCheckbox = addonTable.SettingsControls.CreateSettingsCheckbox
local CreateSettingsSlider = addonTable.SettingsControls.CreateSettingsSlider
local CreateSettingsActionButton = addonTable.SettingsControls.CreateSettingsActionButton
local CreateLanguageSelector = addonTable.SettingsControls.CreateLanguageSelector
local CreateSettingsOptionSelector = addonTable.SettingsControls.CreateSettingsOptionSelector
local CreateSettingsDropdownSelector = addonTable.SettingsControls.CreateSettingsDropdownSelector

local SHOW_NAME_MAX_CHARS_SETTING = false
local SHOW_TELEPORT_COLUMNS_SETTING = false
local DEFAULT_LAYOUT_MODE_EXPANDED = "expanded"
local DEFAULT_LAYOUT_MODE_COMPACT_VERTICAL = "compact_vertical"
local DEFAULT_LAYOUT_MODE_COMPACT_HORIZONTAL = "compact_horizontal"
local DEFAULT_LAYOUT_MODE_COMPACT_MAIN_HORIZONTAL = "compact_main_horizontal"
local DEFAULT_LAYOUT_MODE_COMPACT_HORIZONTAL_2_LEGACY = "compact_horizontal_2"
local DEFAULT_LAYOUT_MODE_LAST_USED = "last_used"

local STATS_BOX_SETTING_LABELS = {
  enUS = {
    enabled = "Show player stats box",
    locked = "Lock player stats box position",
    alpha = "Stats box background opacity",
    fontSize = "Stats box font size",
  },
  deDE = {
    enabled = "Spielerwerte-Box anzeigen",
    locked = "Position der Spielerwerte-Box sperren",
    alpha = "Hintergrund-Deckkraft der Spielerwerte-Box",
    fontSize = "Schriftgroesse der Spielerwerte-Box",
  },
}

local BuildHearthstoneSettingsOptions = addonTable.SettingsHearthstone
    and type(addonTable.SettingsHearthstone.BuildOptions) == "function"
    and addonTable.SettingsHearthstone.BuildOptions
  or function(_config, labels)
    labels = type(labels) == "table" and labels or {}
    return {
      {
        value = "random",
        fallback = labels.SETTINGS_HEARTHSTONE_RANDOM or "Random owned Hearthstone",
      },
      {
        value = "item:6948",
        fallback = labels.SETTINGS_HEARTHSTONE_DEFAULT or "Default Hearthstone (6948)",
      },
    }
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

local function SetLocalizedText(control, labels, key, fallback)
  if control and type(control.SetText) == "function" then
    control:SetText(labels[key] or fallback)
  end
end

function SettingsSections.BuildGeneralSection(canvas, yOffset, labels, config, controls)
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

  controls.hearthstoneSelect, yOffset = CreateSettingsDropdownSelector(
    canvas,
    yOffset,
    "SETTINGS_HEARTHSTONE_SELECT",
    labels.SETTINGS_HEARTHSTONE_SELECT or "Hearthstone",
    BuildHearthstoneSettingsOptions(config, labels),
    config.getL,
    function()
      local db = config.getDB()
      return db.hearthstoneChoice or "random"
    end,
    function(val)
      local db = config.getDB()
      db.hearthstoneChoice = val
      if type(config.onHearthstoneChoiceChange) == "function" then
        config.onHearthstoneChoiceChange()
      end
    end
  )

  return yOffset
end

function SettingsSections.BuildDisplaySection(canvas, yOffset, labels, config, controls)
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

  controls.lfgGroupBonuses, yOffset = CreateSettingsCheckbox(
    canvas,
    yOffset,
    labels.SETTINGS_LFG_GROUP_BONUSES or "Group Finder: Show class bonuses",
    function()
      local db = config.getDB()
      return db.lfgGroupBonusesEnabled ~= false
    end,
    function(checked)
      local db = config.getDB()
      db.lfgGroupBonusesEnabled = checked
      if type(config.onLfgGroupBonusesToggle) == "function" then
        config.onLfgGroupBonusesToggle(checked)
      end
    end,
    "SETTINGS_LFG_GROUP_BONUSES"
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

function SettingsSections.RefreshGeneralControls(controls, labels, db, config)
  if controls.generalHeader then
    controls.generalHeader:SetText(labels.SETTINGS_SECTION_GENERAL or "General")
  end
  SetLocalizedText(
    controls.generalHint,
    labels,
    "SETTINGS_SECTION_GENERAL_HINT",
    "Language, startup behavior, and utility links."
  )
  if controls.lang then
    controls.lang.label:SetText(labels.SETTINGS_LANGUAGE or "Language")
    controls.lang.UpdateHighlight()
  end
  if controls.combatLog then
    controls.combatLog.label:SetText(labels.SETTINGS_COMBAT_LOGGING or "Advanced Combat Logging")
    controls.combatLog.check:SetChecked(GetCVarEnabled("advancedCombatLogging"))
  end
  if controls.dmReset then
    controls.dmReset.label:SetText(labels.SETTINGS_DM_RESET or "Reset Blizzard Damage Meter on dungeon entry")
    controls.dmReset.check:SetChecked(GetCVarEnabled("damageMeterResetOnNewInstance"))
  end
  if controls.escPanel then
    controls.escPanel.label:SetText(labels.SETTINGS_ESC_PANEL or "Show ESC Menu Shortcuts")
    controls.escPanel.check:SetChecked(db.showEscPanel ~= false)
  end
  if controls.portalNavigator then
    controls.portalNavigator.label:SetText(labels.SETTINGS_SHOW_TIMEWAYS_NAVIGATOR or "Show Timeways Navigator")
    controls.portalNavigator.check:SetChecked(db.showPortalNavigator ~= false)
  end
  if controls.hearthstoneSelect then
    controls.hearthstoneSelect.UpdateOptions(BuildHearthstoneSettingsOptions(config, labels))
  end
  if controls.defaultLayout then
    controls.defaultLayout.UpdateHighlight()
  end
end

function SettingsSections.RefreshDisplayControls(controls, labels, db, config)
  if controls.displayHeader then
    controls.displayHeader:SetText(labels.SETTINGS_SECTION_DISPLAY or "Display")
  end
  SetLocalizedText(
    controls.displayHint,
    labels,
    "SETTINGS_SECTION_DISPLAY_HINT",
    "Scale, opacity, and UI recovery tools."
  )

  if controls.bgAlpha then
    controls.bgAlpha.label:SetText(labels.SETTINGS_BG_ALPHA or "Background Opacity")
    controls.bgAlpha.SetValueSilently(type(db.bgAlpha) == "number" and db.bgAlpha or DEFAULT_BG_ALPHA)
  end
  if controls.statsBoxEnabled and controls.statsBoxEnabled.label then
    controls.statsBoxEnabled.label:SetText(GetStatsBoxSettingLabel(config, "enabled")) -- i18n-ok
    controls.statsBoxEnabled.check:SetChecked(db.statsBoxEnabled == true)
  end
  if controls.statsBoxLocked and controls.statsBoxLocked.label then
    controls.statsBoxLocked.label:SetText(GetStatsBoxSettingLabel(config, "locked")) -- i18n-ok
    controls.statsBoxLocked.check:SetChecked(db.statsBoxLocked == true)
  end
  if controls.statsBoxBgAlpha and controls.statsBoxBgAlpha.label then
    controls.statsBoxBgAlpha.label:SetText(GetStatsBoxSettingLabel(config, "alpha")) -- i18n-ok
    controls.statsBoxBgAlpha.SetValueSilently(type(db.statsBoxBgAlpha) == "number" and db.statsBoxBgAlpha or 0)
  end
  if controls.statsBoxFontSizeOffset and controls.statsBoxFontSizeOffset.label then
    controls.statsBoxFontSizeOffset.label:SetText(GetStatsBoxSettingLabel(config, "fontSize")) -- i18n-ok
    controls.statsBoxFontSizeOffset.SetValueSilently(
      type(db.statsBoxFontSizeOffset) == "number" and db.statsBoxFontSizeOffset or 0
    )
  end
  if controls.uiScale then
    controls.uiScale.label:SetText(labels.SETTINGS_UI_SCALE or "UI Scale")
    controls.uiScale.SetValueSilently(type(db.uiScale) == "number" and db.uiScale or 1.0)
  end
  if controls.resetUiBtn then
    controls.resetUiBtn.label:SetText(labels.SETTINGS_RESET_UI_POSITION or "/isilive resetui")
  end
  if controls.resetUiHint then
    controls.resetUiHint:SetText(
      labels.SETTINGS_RESET_UI_POSITION_HINT or "Default: position center, UI scale 100%, background opacity 50%"
    )
    if type(controls.resetUiHint.SetWidth) == "function" then
      controls.resetUiHint:SetWidth(304)
    end
  end
  if controls.minimapBtn then
    controls.minimapBtn.label:SetText(labels.SETTINGS_MINIMAP_BUTTON or "Minimap Button")
    controls.minimapBtn.check:SetChecked(db.showMinimapButton == true)
  end
  if controls.nameMaxChars then
    controls.nameMaxChars.label:SetText(labels.SETTINGS_NAME_MAX_CHARS or "Name Length")
    controls.nameMaxChars.SetValueSilently(type(db.nameMaxChars) == "number" and db.nameMaxChars or 10)
  end
  if controls.tpColumns then
    controls.tpColumns.label:SetText(labels.SETTINGS_TELEPORT_COLUMNS or "Teleport Grid Columns")
    controls.tpColumns.SetValueSilently(type(db.teleportColumns) == "number" and db.teleportColumns or 4)
  end
  if controls.lfgFlags then
    controls.lfgFlags.label:SetText(labels.SETTINGS_LFG_FLAGS or "Group Finder: Language Flags")
    controls.lfgFlags.check:SetChecked(db.lfgFlagsEnabled ~= false)
  end
  if controls.lfgGroupBonuses then
    controls.lfgGroupBonuses.label:SetText(labels.SETTINGS_LFG_GROUP_BONUSES or "Group Finder: Show class bonuses")
    controls.lfgGroupBonuses.check:SetChecked(db.lfgGroupBonusesEnabled ~= false)
  end
  if controls.tooltipFlags then
    controls.tooltipFlags.label:SetText(labels.SETTINGS_TOOLTIP_FLAGS or "Tooltip: Language Flags")
    controls.tooltipFlags.check:SetChecked(db.tooltipFlagsEnabled ~= false)
  end
  if controls.inviteHint then
    controls.inviteHint.label:SetText(labels.SETTINGS_INVITE_HINT_ENABLED or "LFG invite hint")
    controls.inviteHint.check:SetChecked(db.inviteHintEnabled ~= false)
  end
  if controls.acceptedInviteNotice then
    controls.acceptedInviteNotice.label:SetText(
      labels.SETTINGS_ACCEPTED_INVITE_NOTICE_ENABLED or "Accepted-invite notice"
    )
    controls.acceptedInviteNotice.check:SetChecked(db.acceptedInviteNoticeEnabled ~= false)
  end
end
