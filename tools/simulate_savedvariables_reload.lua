-- Standalone CLI tool: simulates settings writes, WoW SavedVariables persistence,
-- and a second addon session after /reload. It fails if persisted DB values or
-- the live settings callbacks diverge from the user's saved choices.
---@diagnostic disable: undefined-global
local io = io
---@diagnostic disable-next-line: undefined-global
local load = load

local function LoadLocal(path)
  local file = assert(io.open(path, "rb"))
  local source = file:read("*a")
  file:close()
  local chunk, err = load(source, "@" .. path)
  assert(chunk, err)
  return chunk()
end

local Harness = LoadLocal("testmodul/isilive_test_harness.lua")
local UIHelpers = LoadLocal("testmodul/isilive_test_ui_helpers.lua")

local failures = 0

local function Check(condition, message)
  if condition then
    print("  [CHECK PASS] " .. message)
    return
  end
  failures = failures + 1
  print("  [CHECK FAIL] " .. message)
end

local function CopyTable(source)
  local out = {}
  for key, value in pairs(source or {}) do
    out[key] = value
  end
  return out
end

local function ApplyFactorySettingsDefaults(db)
  if db.mobNameplateEnabled == nil then
    db.mobNameplateEnabled = true
    db.mplusForcesEstimate = false
  end
  if db.mobNameplateShowPercent == nil then
    db.mobNameplateShowPercent = true
  end
  if db.mobNameplateShowRemaining == nil then
    db.mobNameplateShowRemaining = true
  end
  if db.mobNameplateFontSize == nil then
    db.mobNameplateFontSize = 14
  end
  if db.mobNameplatePosition == nil then
    db.mobNameplatePosition = "RIGHT"
  end
  if db.mobNameplateXOffset == nil then
    db.mobNameplateXOffset = 0
  end
  if db.mobNameplateYOffset == nil then
    db.mobNameplateYOffset = 0
  end
  if db.lockMainFramePosition == nil then
    db.lockMainFramePosition = true
  end
end

local function ApplyLiveSettingsFromDB(db, live)
  live.bgAlpha = type(db.bgAlpha) == "number" and db.bgAlpha or 0.50
  live.uiScale = type(db.uiScale) == "number" and db.uiScale or 1
  live.lockMainFramePosition = db.lockMainFramePosition ~= false
  live.lfgFlagsEnabled = db.lfgFlagsEnabled ~= false
  live.tooltipFlagsEnabled = db.tooltipFlagsEnabled ~= false
  live.mplusForcesEstimate = db.mplusForcesEstimate == true
  live.mobNameplate = {
    enabled = db.mobNameplateEnabled == true,
    showPercent = db.mobNameplateShowPercent ~= false,
    showRemaining = db.mobNameplateShowRemaining ~= false,
    fontSize = tonumber(db.mobNameplateFontSize) or 14,
    position = type(db.mobNameplatePosition) == "string" and db.mobNameplatePosition or "RIGHT",
    xOffset = tonumber(db.mobNameplateXOffset) or 0,
    yOffset = tonumber(db.mobNameplateYOffset) or 0,
  }
end

local function Labels()
  return {
    SETTINGS_SECTION_GENERAL = "General",
    SETTINGS_SECTION_DISPLAY = "Display",
    SETTINGS_SECTION_NAMEPLATES = "Nameplates",
    SETTINGS_SECTION_BEHAVIOR = "Behavior",
    SETTINGS_SECTION_SOUND = "Sound",
    SETTINGS_SECTION_CHAT = "Chat",
    SETTINGS_SECTION_DEBUG = "Debug",
    SETTINGS_LANGUAGE = "Language",
    SETTINGS_BG_ALPHA = "Background Opacity",
    SETTINGS_UI_SCALE = "UI Scale",
    SETTINGS_LFG_FLAGS = "LFG Flags",
    SETTINGS_TOOLTIP_FLAGS = "Tooltip Flags",
    SETTINGS_LOCK_MAIN_FRAME_POSITION = "Lock main frame position",
    SETTINGS_MPLUS_FORCES_DISPLAY_MODE = "M+ forces display",
    SETTINGS_MPLUS_FORCES_MODE_OFF = "Off",
    SETTINGS_MPLUS_FORCES_MODE_TOOLTIP = "Tooltip",
    SETTINGS_MPLUS_FORCES_MODE_NAMEPLATE = "Nameplate",
    SETTINGS_NAMEPLATE_SHOW_PERCENT = "Show percentage",
    SETTINGS_NAMEPLATE_SHOW_REMAINING = "Show remaining needed",
    SETTINGS_NAMEPLATE_FONT_SIZE = "Font size",
    SETTINGS_NAMEPLATE_POSITION = "Position",
    SETTINGS_NAMEPLATE_POS_LEFT = "Left",
    SETTINGS_NAMEPLATE_POS_RIGHT = "Right",
    SETTINGS_NAMEPLATE_POS_TOP = "Top",
    SETTINGS_NAMEPLATE_POS_BOTTOM = "Bottom",
    SETTINGS_NAMEPLATE_X_OFFSET = "X offset",
    SETTINGS_NAMEPLATE_Y_OFFSET = "Y offset",
    SETTINGS_DEFAULT_OPEN_UI = "Default UI on Open",
    SETTINGS_DEFAULT_OPEN_UI_LAST = "Last Used",
    SETTINGS_DEFAULT_OPEN_UI_V = "V",
    SETTINGS_DEFAULT_OPEN_UI_H = "H",
    SETTINGS_DEFAULT_OPEN_UI_M2 = "M+",
  }
end

local function FindFrame(frames, frameType, settingKey)
  for _, frame in ipairs(frames or {}) do
    if frame._frameType == frameType and frame._settingKey == settingKey then
      return frame
    end
  end
  return nil
end

local function FindOptionButton(frames, value)
  for _, frame in ipairs(frames or {}) do
    if frame._frameType == "Button" and frame._optionValue == value and frame._scripts and frame._scripts.OnClick then
      return frame
    end
  end
  return nil
end

local function ClickCheckbox(frames, settingKey, checked)
  local check = assert(FindFrame(frames, "CheckButton", settingKey), "missing checkbox " .. settingKey)
  check:SetChecked(checked == true)
  assert(check._scripts and check._scripts.OnClick, "checkbox has no OnClick: " .. settingKey)(check)
  return check
end

local function SetSlider(frames, settingKey, value)
  local slider = assert(FindFrame(frames, "Slider", settingKey), "missing slider " .. settingKey)
  assert(slider._scripts and slider._scripts.OnValueChanged, "slider has no OnValueChanged: " .. settingKey)(
    slider,
    value
  )
  return slider
end

local function ClickOption(frames, value)
  local button = assert(FindOptionButton(frames, value), "missing option button " .. tostring(value))
  button._scripts.OnClick(button)
  return button
end

local function BuildPanelSession(db)
  local createFrame, frames = UIHelpers.BuildCreateFrameStub()
  local live = {}

  ApplyFactorySettingsDefaults(db)
  ApplyLiveSettingsFromDB(db, live)

  Harness.WithGlobals({
    UIParent = {},
    IsiLiveDB = db,
    CreateFrame = createFrame,
    Settings = {
      RegisterCanvasLayoutCategory = function(canvas, name)
        return { canvas = canvas, name = name }
      end,
      RegisterAddOnCategory = function() end,
    },
    C_AddOns = {
      IsAddOnLoaded = function()
        return false
      end,
    },
  }, function()
    local addon = Harness.LoadAddonModules({ "isiLive_ui_common.lua", "isiLive_settings.lua" })
    local panel = addon.SettingsPanel.Create({
      getL = Labels,
      getCurrentLocale = function()
        return "enUS"
      end,
      setLanguage = function() end,
      getDB = function()
        return db
      end,
      onBgAlphaChange = function(value)
        live.bgAlpha = value
      end,
      onUiScaleChange = function(value)
        live.uiScale = value
      end,
      onLfgFlagsToggle = function(enabled)
        live.lfgFlagsEnabled = enabled == true
      end,
      onTooltipFlagsToggle = function(enabled)
        live.tooltipFlagsEnabled = enabled == true
      end,
      onMplusForcesToggle = function(enabled)
        live.mplusForcesEstimate = enabled == true
      end,
      onMainFramePositionLockToggle = function(enabled)
        live.lockMainFramePosition = enabled == true
      end,
      onMobNameplateChange = function()
        ApplyLiveSettingsFromDB(db, live)
      end,
    })
    assert(panel ~= nil, "settings panel must build")
  end)

  return {
    db = db,
    live = live,
    frames = frames,
  }
end

local function PrintState(label, session)
  local db = session.db
  local live = session.live
  local np = live.mobNameplate or {}
  print("---- " .. label)
  print(
    string.format(
      "  db: nameplate=%s tooltip=%s showPercent=%s showRemaining=%s font=%s pos=%s x=%s y=%s",
      tostring(db.mobNameplateEnabled),
      tostring(db.mplusForcesEstimate),
      tostring(db.mobNameplateShowPercent),
      tostring(db.mobNameplateShowRemaining),
      tostring(db.mobNameplateFontSize),
      tostring(db.mobNameplatePosition),
      tostring(db.mobNameplateXOffset),
      tostring(db.mobNameplateYOffset)
    )
  )
  print(
    string.format(
      "  live: nameplate=%s tooltip=%s lfgFlags=%s tooltipFlags=%s bg=%.2f scale=%.2f lock=%s",
      tostring(np.enabled),
      tostring(live.mplusForcesEstimate),
      tostring(live.lfgFlagsEnabled),
      tostring(live.tooltipFlagsEnabled),
      tonumber(live.bgAlpha) or 0,
      tonumber(live.uiScale) or 0,
      tostring(live.lockMainFramePosition)
    )
  )
end

local function AssertSessionTwo(session)
  local db = session.db
  local live = session.live
  local frames = session.frames
  local np = live.mobNameplate or {}

  Check(db.mobNameplateEnabled == true, "SavedVariables keep display mode on nameplates")
  Check(db.mplusForcesEstimate == false, "SavedVariables keep tooltip forces disabled")
  Check(db.mobNameplateShowPercent == false, "SavedVariables keep showPercent=false")
  Check(db.mobNameplateShowRemaining == false, "SavedVariables keep showRemaining=false")
  Check(db.mobNameplateFontSize == 22, "SavedVariables keep nameplate font size")
  Check(db.mobNameplatePosition == "TOP", "SavedVariables keep nameplate position")
  Check(db.mobNameplateXOffset == 17, "SavedVariables keep nameplate X offset")
  Check(db.mobNameplateYOffset == -8, "SavedVariables keep nameplate Y offset")
  Check(db.bgAlpha == 0.7, "SavedVariables keep background opacity")
  Check(db.uiScale == 1.2, "SavedVariables keep UI scale")
  Check(db.lockMainFramePosition == false, "SavedVariables keep unlocked main frame")
  Check(db.lfgFlagsEnabled == false, "SavedVariables keep LFG flags disabled")
  Check(db.tooltipFlagsEnabled == false, "SavedVariables keep tooltip flags disabled")

  Check(np.enabled == true, "live MobNameplate sees persisted enabled state")
  Check(np.showPercent == false, "live MobNameplate sees persisted showPercent=false")
  Check(np.showRemaining == false, "live MobNameplate sees persisted showRemaining=false")
  Check(np.fontSize == 22, "live MobNameplate sees persisted font size")
  Check(np.position == "TOP", "live MobNameplate sees persisted position")
  Check(np.xOffset == 17, "live MobNameplate sees persisted X offset")
  Check(np.yOffset == -8, "live MobNameplate sees persisted Y offset")
  Check(live.mplusForcesEstimate == false, "live MobTooltip sees persisted disabled state")
  Check(live.lfgFlagsEnabled == false, "live LFG flags sees persisted disabled state")
  Check(live.tooltipFlagsEnabled == false, "live tooltip flags sees persisted disabled state")
  Check(live.bgAlpha == 0.7, "live UI background opacity sees persisted value")
  Check(live.uiScale == 1.2, "live UI scale sees persisted value")
  Check(live.lockMainFramePosition == false, "live main-frame lock sees persisted unlocked state")

  Check(
    FindFrame(frames, "CheckButton", "SETTINGS_NAMEPLATE_SHOW_PERCENT"):GetChecked() == false,
    "UI checkbox reflects showPercent=false after reload"
  )
  Check(
    FindFrame(frames, "CheckButton", "SETTINGS_NAMEPLATE_SHOW_REMAINING"):GetChecked() == false,
    "UI checkbox reflects showRemaining=false after reload"
  )
  Check(
    FindFrame(frames, "CheckButton", "SETTINGS_LFG_FLAGS"):GetChecked() == false,
    "UI checkbox reflects LFG flags=false after reload"
  )
  Check(
    FindFrame(frames, "CheckButton", "SETTINGS_TOOLTIP_FLAGS"):GetChecked() == false,
    "UI checkbox reflects tooltip flags=false after reload"
  )
  Check(
    FindFrame(frames, "CheckButton", "SETTINGS_LOCK_MAIN_FRAME_POSITION"):GetChecked() == false,
    "UI checkbox reflects lock=false after reload"
  )
  Check(
    FindFrame(frames, "Slider", "SETTINGS_NAMEPLATE_FONT_SIZE"):GetValue() == 22,
    "UI slider reflects nameplate font size after reload"
  )
  Check(
    FindFrame(frames, "Slider", "SETTINGS_NAMEPLATE_X_OFFSET"):GetValue() == 17,
    "UI slider reflects X offset after reload"
  )
  Check(
    FindFrame(frames, "Slider", "SETTINGS_NAMEPLATE_Y_OFFSET"):GetValue() == -8,
    "UI slider reflects Y offset after reload"
  )
  Check(
    FindFrame(frames, "Slider", "SETTINGS_BG_ALPHA"):GetValue() == 0.7,
    "UI slider reflects background opacity after reload"
  )
  Check(FindFrame(frames, "Slider", "SETTINGS_UI_SCALE"):GetValue() == 1.2, "UI slider reflects UI scale after reload")
end

local function Run()
  print("========== SavedVariables reload simulator ==========")
  local sessionOne = BuildPanelSession({})
  PrintState("1. session 1 after defaults", sessionOne)

  ClickOption(sessionOne.frames, "tooltip")
  Check(sessionOne.db.mobNameplateEnabled == false, "session 1 can switch display mode to tooltip")
  Check(sessionOne.live.mplusForcesEstimate == true, "session 1 tooltip mode reaches live callback")

  ClickOption(sessionOne.frames, "nameplate")
  ClickCheckbox(sessionOne.frames, "SETTINGS_NAMEPLATE_SHOW_PERCENT", false)
  ClickCheckbox(sessionOne.frames, "SETTINGS_NAMEPLATE_SHOW_REMAINING", false)
  SetSlider(sessionOne.frames, "SETTINGS_NAMEPLATE_FONT_SIZE", 22)
  ClickOption(sessionOne.frames, "TOP")
  SetSlider(sessionOne.frames, "SETTINGS_NAMEPLATE_X_OFFSET", 17)
  SetSlider(sessionOne.frames, "SETTINGS_NAMEPLATE_Y_OFFSET", -8)
  SetSlider(sessionOne.frames, "SETTINGS_BG_ALPHA", 0.7)
  SetSlider(sessionOne.frames, "SETTINGS_UI_SCALE", 1.2)
  ClickCheckbox(sessionOne.frames, "SETTINGS_LOCK_MAIN_FRAME_POSITION", false)
  ClickCheckbox(sessionOne.frames, "SETTINGS_LFG_FLAGS", false)
  ClickCheckbox(sessionOne.frames, "SETTINGS_TOOLTIP_FLAGS", false)
  PrintState("2. session 1 after user changes", sessionOne)

  local savedVariablesOnLogout = CopyTable(sessionOne.db)
  local sessionTwo = BuildPanelSession(CopyTable(savedVariablesOnLogout))
  PrintState("3. session 2 after /reload", sessionTwo)
  AssertSessionTwo(sessionTwo)

  if failures > 0 then
    print(string.format("\nSavedVariables reload simulator failed: %d check(s) failed", failures))
    os.exit(1)
  end

  print("\nSavedVariables reload simulator passed.")
end

Run()
