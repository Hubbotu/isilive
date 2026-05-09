---@diagnostic disable: undefined-global
local helpersChunk, helpersErr = loadfile("testmodul/isilive_test_ui_helpers.lua")
if not helpersChunk then
  error("cannot load UI helpers: " .. tostring(helpersErr))
end
local helpers = helpersChunk()
local BuildCreateFrameStub = helpers.BuildCreateFrameStub
local RequireValue = helpers.RequireValue

local function RegisterSettingsPanelResetActionTests(test, Assert, WithGlobals, LoadAddonModules)
  test("Settings panel exposes resetui action and styles Reset all Settings like the other buttons", function()
    local createFrameStub, createdFrames = BuildCreateFrameStub()
    local db = {}
    local resetUiCalls = 0
    local resetDbCalls = 0
    local lastPopupName = nil
    local staticPopupDialogs = {}

    WithGlobals({
      UIParent = {},
      IsiLiveDB = db,
      CreateFrame = createFrameStub,
      StaticPopupDialogs = staticPopupDialogs,
      StaticPopup_Show = function(name)
        lastPopupName = name
      end,
      Settings = {
        RegisterCanvasLayoutCategory = function(canvas, name)
          return { canvas = canvas, name = name }
        end,
        RegisterAddOnCategory = function() end,
      },
    }, function()
      local addon = LoadAddonModules({ "isiLive_ui_common.lua", "isiLive_settings.lua" })
      local panel = addon.SettingsPanel.Create({
        getL = function()
          return {
            SETTINGS_SECTION_GENERAL = "General",
            SETTINGS_SECTION_BEHAVIOR = "Behavior",
            SETTINGS_SECTION_DISPLAY = "Display",
            SETTINGS_SECTION_DEBUG = "Debug",
            SETTINGS_LANGUAGE = "Language",
            SETTINGS_COMBAT_LOGGING = "Combat Logging",
            SETTINGS_DM_RESET = "DM Reset",
            SETTINGS_ESC_PANEL = "ESC Panel",
            SETTINGS_BG_ALPHA = "Background Opacity",
            SETTINGS_UI_SCALE = "UI Scale",
            SETTINGS_RESET_UI_POSITION = "Reset UI position (/isilive resetui)",
            SETTINGS_RESET_UI_POSITION_HINT = "Default: position center, UI scale 100%, background opacity 50%",
            SETTINGS_MINIMAP_BUTTON = "Minimap Button",
            SETTINGS_SYNC_ENABLED = "Addon Sync",
            SETTINGS_AUTO_OPEN_QUEUE = "Auto Open Queue",
            SETTINGS_AUTO_CLOSE_MAIN_FRAME = "Auto Close Main Frame",
            SETTINGS_DEFAULT_OPEN_UI = "Default UI on Open",
            SETTINGS_DEFAULT_OPEN_UI_LAST = "Last Used",
            SETTINGS_DEFAULT_OPEN_UI_V = "V",
            SETTINGS_DEFAULT_OPEN_UI_H = "H",
            SETTINGS_DEFAULT_OPEN_UI_M2 = "M2",
            SETTINGS_QUEUE_DEBUG = "Queue Debug",
            SETTINGS_RUNTIME_LOG = "Runtime Log",
            SETTINGS_RESET_DB = "Reset All Settings",
          }
        end,
        getCurrentLocale = function()
          return "enUS"
        end,
        setLanguage = function() end,
        getDB = function()
          return db
        end,
        onResetMainFramePosition = function()
          resetUiCalls = resetUiCalls + 1
        end,
        onResetDB = function()
          resetDbCalls = resetDbCalls + 1
        end,
      })

      Assert.NotNil(panel, "settings panel should be created when Blizzard Settings API exists")

      local resetUiButton = nil
      local resetDbButton = nil
      for _, frame in ipairs(createdFrames) do
        if frame._settingKey == "SETTINGS_RESET_UI_POSITION" then
          resetUiButton = frame
        elseif frame._settingKey == "SETTINGS_RESET_DB" then
          resetDbButton = frame
        end
      end

      resetUiButton =
        Assert.NotNil(resetUiButton, "settings panel should create a resetui action button in the display section")
      resetDbButton = Assert.NotNil(resetDbButton, "settings panel should create a reset all settings button")
      ---@diagnostic disable: undefined-field
      Assert.Equal(
        resetUiButton.label:GetText(),
        "Reset UI position (/isilive resetui)",
        "resetui button should use the localized display label"
      )
      Assert.Equal(
        resetUiButton.label:GetText(),
        "Reset UI position (/isilive resetui)",
        "resetui button should keep its clickable label"
      )
      Assert.NotNil(resetUiButton.hint, "resetui hint should exist under the button")
      Assert.Equal(
        resetUiButton.hint:GetText(),
        "Default: position center, UI scale 100%, background opacity 50%",
        "resetui button should explain the default values"
      )
      Assert.Equal(
        resetDbButton.label:GetText(),
        "Reset All Settings",
        "reset all settings button should keep its label"
      )
      Assert.NotNil(resetUiButton.hoverGlow, "resetui button should expose a hover glow for clickable feedback")
      Assert.NotNil(
        resetDbButton.hoverGlow,
        "reset all settings button should expose a hover glow for clickable feedback"
      )
      Assert.NotNil(resetDbButton._backdropColor, "reset all settings button should use the styled backdrop")
      Assert.NotNil(
        resetDbButton._backdropBorderColor,
        "reset all settings button should use the styled backdrop border"
      )
      Assert.False(
        resetDbButton._template == "UIPanelButtonTemplate",
        "reset all settings button should no longer use the legacy UIPanelButtonTemplate"
      )
      local onClickResetUi = resetUiButton._scripts and resetUiButton._scripts.OnClick or nil
      local onClickResetDb = resetDbButton._scripts and resetDbButton._scripts.OnClick or nil
      local onEnterResetDb = resetDbButton._scripts and resetDbButton._scripts.OnEnter or nil
      local onLeaveResetDb = resetDbButton._scripts and resetDbButton._scripts.OnLeave or nil
      onClickResetUi = Assert.NotNil(onClickResetUi, "resetui button should define OnClick")
      onClickResetDb = Assert.NotNil(onClickResetDb, "reset all settings button should define OnClick")
      onEnterResetDb = Assert.NotNil(onEnterResetDb, "reset all settings button should define OnEnter")
      onLeaveResetDb = Assert.NotNil(onLeaveResetDb, "reset all settings button should define OnLeave")

      onEnterResetDb(resetDbButton)
      Assert.NotNil(
        resetDbButton._backdropColor,
        "hover should keep the reset all settings button visually highlighted"
      )
      onLeaveResetDb(resetDbButton)
      Assert.NotNil(resetDbButton._backdropColor, "leave should restore the reset all settings button backdrop")

      onClickResetUi(resetUiButton, "LeftButton")
      Assert.Equal(resetUiCalls, 0, "resetui button should wait for confirmation before calling the reset helper")
      Assert.NotNil(lastPopupName, "resetui button should open a confirmation popup")
      Assert.NotNil(staticPopupDialogs[lastPopupName], "resetui confirmation popup should be registered")
      staticPopupDialogs[lastPopupName].OnCancel()
      Assert.Equal(resetUiCalls, 0, "resetui cancel should abort the reset helper")

      onClickResetDb(resetDbButton, "LeftButton")
      Assert.Equal(
        resetDbCalls,
        0,
        "reset all settings button should wait for confirmation before calling the DB reset"
      )
      Assert.NotNil(lastPopupName, "reset all settings button should open a confirmation popup")
      Assert.NotNil(staticPopupDialogs[lastPopupName], "reset all settings confirmation popup should be registered")
      staticPopupDialogs[lastPopupName].OnAccept()
      ---@diagnostic enable: undefined-field

      Assert.Equal(resetUiCalls, 0, "resetui cancel should not call the reset-main-frame callback")
      Assert.Equal(resetDbCalls, 1, "reset all settings button should call the DB reset callback once")
    end)
  end)
end

local function RegisterSettingsPanelTests(test, Assert, WithGlobals, LoadAddonModules)
  test("UICommon background alpha defaults to 50 percent and honors saved override", function()
    WithGlobals({
      IsiLiveDB = nil,
    }, function()
      local addon = LoadAddonModules({ "isiLive_ui_common.lua" })
      Assert.Equal(addon.UICommon.GetBackgroundAlpha(), 0.50, "default background alpha should be 50 percent")
    end)

    WithGlobals({
      IsiLiveDB = { bgAlpha = 0.65 },
    }, function()
      local addon = LoadAddonModules({ "isiLive_ui_common.lua" })
      Assert.Equal(addon.UICommon.GetBackgroundAlpha(), 0.65, "saved background alpha should override the default")
    end)
  end)

  test("Settings panel background opacity keeps 50 percent default until user changes it", function()
    local createFrameStub, createdFrames = BuildCreateFrameStub()
    local db = {}
    local bgAlphaChanges = 0
    local lastBgAlpha = nil

    WithGlobals({
      UIParent = {},
      IsiLiveDB = db,
      CreateFrame = createFrameStub,
      Settings = {
        RegisterCanvasLayoutCategory = function(canvas, name)
          return { canvas = canvas, name = name }
        end,
        RegisterAddOnCategory = function() end,
      },
    }, function()
      local addon = LoadAddonModules({ "isiLive_ui_common.lua", "isiLive_settings.lua" })
      local panel = addon.SettingsPanel.Create({
        getL = function()
          return {
            SETTINGS_SECTION_GENERAL = "General",
            SETTINGS_SECTION_DEBUG = "Debug",
            SETTINGS_LANGUAGE = "Language",
            SETTINGS_COMBAT_LOGGING = "Combat Logging",
            SETTINGS_DM_RESET = "DM Reset",
            SETTINGS_ESC_PANEL = "ESC Panel",
            SETTINGS_BG_ALPHA = "Background Opacity",
            SETTINGS_QUEUE_DEBUG = "Queue Debug",
            SETTINGS_RUNTIME_LOG = "Runtime Log",
          }
        end,
        getCurrentLocale = function()
          return "enUS"
        end,
        setLanguage = function() end,
        getDB = function()
          return db
        end,
        onBgAlphaChange = function(val)
          bgAlphaChanges = bgAlphaChanges + 1
          lastBgAlpha = val
        end,
      })

      Assert.NotNil(panel, "settings panel should be created when Blizzard Settings API exists")
      Assert.Nil(db.bgAlpha, "default background alpha should not be written just by opening settings")

      local slider = nil
      for _, frame in ipairs(createdFrames) do
        if frame._frameType == "Slider" and frame._settingKey == "SETTINGS_BG_ALPHA" then
          slider = frame
          break
        end
      end

      slider = Assert.NotNil(slider, "settings panel should create a background alpha slider")
      ---@diagnostic disable: undefined-field
      Assert.Equal(slider:GetValue(), 0.50, "slider should initialize with a 50 percent default")

      panel.Refresh()

      Assert.Nil(db.bgAlpha, "refresh should not persist the default background alpha")
      Assert.Equal(bgAlphaChanges, 0, "refresh should not fire background alpha change callbacks")

      local onValueChanged = slider._scripts and slider._scripts.OnValueChanged or nil
      onValueChanged = Assert.NotNil(onValueChanged, "slider should define OnValueChanged")
      onValueChanged(slider, 0.70)
      ---@diagnostic enable: undefined-field

      Assert.Equal(db.bgAlpha, 0.70, "user changes should be persisted")
      Assert.Equal(lastBgAlpha, 0.70, "user changes should call the background alpha callback")
      Assert.Equal(bgAlphaChanges, 1, "user changes should fire exactly one callback")
    end)
  end)

  RegisterSettingsPanelResetActionTests(test, Assert, WithGlobals, LoadAddonModules)

  test("Settings panel lets the user choose the default layout on open", function()
    local createFrameStub, createdFrames = BuildCreateFrameStub()
    local db = {}
    local defaultLayoutChanges = {}

    WithGlobals({
      UIParent = {},
      IsiLiveDB = db,
      CreateFrame = createFrameStub,
      Settings = {
        RegisterCanvasLayoutCategory = function(canvas, name)
          return { canvas = canvas, name = name }
        end,
        RegisterAddOnCategory = function() end,
      },
    }, function()
      local addon = LoadAddonModules({ "isiLive_ui_common.lua", "isiLive_settings.lua" })
      local panel = addon.SettingsPanel.Create({
        getL = function()
          return {
            SETTINGS_SECTION_GENERAL = "General",
            SETTINGS_SECTION_DISPLAY = "Display",
            SETTINGS_SECTION_BEHAVIOR = "Behavior",
            SETTINGS_SECTION_DEBUG = "Debug",
            SETTINGS_LANGUAGE = "Language",
            SETTINGS_COMBAT_LOGGING = "Combat Logging",
            SETTINGS_DM_RESET = "DM Reset",
            SETTINGS_ESC_PANEL = "ESC Panel",
            SETTINGS_BG_ALPHA = "Background Opacity",
            SETTINGS_UI_SCALE = "UI Scale",
            SETTINGS_NAME_MAX_CHARS = "Name Length",
            SETTINGS_TELEPORT_COLUMNS = "Teleport Grid Columns",
            SETTINGS_MINIMAP_BUTTON = "Minimap Button",
            SETTINGS_SYNC_ENABLED = "Addon Sync",
            SETTINGS_AUTO_OPEN_QUEUE = "Auto Open Queue",
            SETTINGS_AUTO_CLOSE_MAIN_FRAME = "Auto Close Main Frame",
            SETTINGS_DEFAULT_OPEN_UI = "Default UI on Open",
            SETTINGS_DEFAULT_OPEN_UI_LAST = "Last Used",
            SETTINGS_DEFAULT_OPEN_UI_V = "V",
            SETTINGS_DEFAULT_OPEN_UI_H = "H",
            SETTINGS_DEFAULT_OPEN_UI_M2 = "M2",
            SETTINGS_QUEUE_DEBUG = "Queue Debug",
            SETTINGS_RUNTIME_LOG = "Runtime Log",
          }
        end,
        getCurrentLocale = function()
          return "enUS"
        end,
        setLanguage = function() end,
        getDB = function()
          return db
        end,
        onDefaultLayoutModeChange = function(mode)
          defaultLayoutChanges[#defaultLayoutChanges + 1] = mode or false
        end,
      })

      Assert.NotNil(panel, "settings panel should be created when Blizzard Settings API exists")
      Assert.Nil(db.rosterDefaultLayoutMode, "default layout should stay unset until the user chooses one")

      local expandedButton = nil
      local m2Button = nil
      local lastUsedButton = nil
      for _, frame in ipairs(createdFrames) do
        if frame._optionValue == "expanded" then
          expandedButton = frame
        elseif frame._optionValue == "compact_main_horizontal" then
          m2Button = frame
        elseif frame._optionValue == "last_used" and frame._optionLabelKey == "SETTINGS_DEFAULT_OPEN_UI_LAST" then
          lastUsedButton = frame
        end
      end

      Assert.Nil(expandedButton, "settings panel should hide the expanded default-layout option")
      m2Button = Assert.NotNil(m2Button, "settings panel should create an M2 default-layout button")
      lastUsedButton = Assert.NotNil(lastUsedButton, "settings panel should create a last-used default-layout button")
      ---@diagnostic disable: undefined-field
      Assert.Equal(
        m2Button._backdropColor[4],
        0.25,
        "M2 should be highlighted by default when no saved default layout exists"
      )
      Assert.Equal(
        lastUsedButton._backdropColor[4],
        0.7,
        "Last Used should stay unselected by default when no saved default layout exists"
      )
      local onClickM2 = (m2Button._scripts and m2Button._scripts.OnClick) or nil
      local onClickLast = (lastUsedButton._scripts and lastUsedButton._scripts.OnClick) or nil
      onClickM2 = Assert.NotNil(onClickM2, "M2 button should define OnClick")
      onClickLast = Assert.NotNil(onClickLast, "Last Used button should define OnClick")

      onClickM2(m2Button, "LeftButton")
      onClickLast(lastUsedButton, "LeftButton")

      Assert.Equal(
        db.rosterDefaultLayoutMode,
        "last_used",
        "choosing Last Used should store the explicit last-used sentinel"
      )
      Assert.Equal(
        defaultLayoutChanges[1],
        "compact_main_horizontal",
        "clicking M2 should persist the normalized layout mode and notify the callback"
      )
      Assert.Equal(
        defaultLayoutChanges[2],
        false,
        "clicking Last Used should notify the callback with a nil layout mode"
      )
    end)
  end)

  test("Settings panel normalizes persisted expanded default layout to M2", function()
    local createFrameStub, createdFrames = BuildCreateFrameStub()
    local db = {
      rosterDefaultLayoutMode = "expanded",
    }
    local defaultLayoutChanges = {}

    WithGlobals({
      UIParent = {},
      IsiLiveDB = db,
      CreateFrame = createFrameStub,
      Settings = {
        RegisterCanvasLayoutCategory = function(canvas, name)
          return { canvas = canvas, name = name }
        end,
        RegisterAddOnCategory = function() end,
      },
    }, function()
      local addon = LoadAddonModules({ "isiLive_ui_common.lua", "isiLive_settings.lua" })
      local panel = addon.SettingsPanel.Create({
        getL = function()
          return {
            SETTINGS_SECTION_GENERAL = "General",
            SETTINGS_SECTION_DISPLAY = "Display",
            SETTINGS_SECTION_BEHAVIOR = "Behavior",
            SETTINGS_SECTION_DEBUG = "Debug",
            SETTINGS_LANGUAGE = "Language",
            SETTINGS_COMBAT_LOGGING = "Combat Logging",
            SETTINGS_DM_RESET = "DM Reset",
            SETTINGS_ESC_PANEL = "ESC Panel",
            SETTINGS_BG_ALPHA = "Background Opacity",
            SETTINGS_UI_SCALE = "UI Scale",
            SETTINGS_MINIMAP_BUTTON = "Minimap Button",
            SETTINGS_SYNC_ENABLED = "Addon Sync",
            SETTINGS_AUTO_OPEN_QUEUE = "Auto Open Queue",
            SETTINGS_AUTO_CLOSE_MAIN_FRAME = "Auto Close Main Frame",
            SETTINGS_DEFAULT_OPEN_UI = "Default UI on Open",
            SETTINGS_DEFAULT_OPEN_UI_LAST = "Last Used",
            SETTINGS_DEFAULT_OPEN_UI_V = "V",
            SETTINGS_DEFAULT_OPEN_UI_H = "H",
            SETTINGS_DEFAULT_OPEN_UI_M2 = "M2",
            SETTINGS_QUEUE_DEBUG = "Queue Debug",
            SETTINGS_RUNTIME_LOG = "Runtime Log",
          }
        end,
        getCurrentLocale = function()
          return "enUS"
        end,
        setLanguage = function() end,
        getDB = function()
          return db
        end,
        onDefaultLayoutModeChange = function(mode)
          defaultLayoutChanges[#defaultLayoutChanges + 1] = mode or false
        end,
      })

      Assert.NotNil(panel, "settings panel should be created when Blizzard Settings API exists")

      local expandedButton = nil
      local m2Button = nil
      for _, frame in ipairs(createdFrames) do
        if frame._optionValue == "expanded" then
          expandedButton = frame
        elseif frame._optionValue == "compact_main_horizontal" then
          m2Button = frame
        end
      end

      Assert.Nil(expandedButton, "settings panel should not expose the expanded layout option")
      m2Button = Assert.NotNil(m2Button, "settings panel should still expose the M2 layout option")
      ---@diagnostic disable: undefined-field
      Assert.Equal(
        m2Button._backdropColor[4],
        0.25,
        "persisted expanded defaults should be normalized onto the visible M2 option"
      )

      local onClickM2 = (m2Button._scripts and m2Button._scripts.OnClick) or nil
      onClickM2 = Assert.NotNil(onClickM2, "M2 button should define OnClick")
      onClickM2(m2Button, "LeftButton")
      ---@diagnostic enable: undefined-field

      Assert.Equal(
        db.rosterDefaultLayoutMode,
        "compact_main_horizontal",
        "saving the normalized visible option should persist M2 instead of expanded"
      )
      Assert.Equal(
        defaultLayoutChanges[1],
        "compact_main_horizontal",
        "callback should receive the normalized visible layout mode"
      )
    end)
  end)
end

local function RegisterSettingsPanelBehaviorTests(test, Assert, WithGlobals, LoadAddonModules)
  test("Settings panel defaults Auto-Close on Key Start / Solo to disabled until the user turns it on", function()
    local createFrameStub, createdFrames = BuildCreateFrameStub()
    local db = {}

    WithGlobals({
      UIParent = {},
      IsiLiveDB = db,
      CreateFrame = createFrameStub,
      Settings = {
        RegisterCanvasLayoutCategory = function(canvas, name)
          return { canvas = canvas, name = name }
        end,
        RegisterAddOnCategory = function() end,
      },
    }, function()
      local addon = LoadAddonModules({ "isiLive_ui_common.lua", "isiLive_settings.lua" })
      local panel = addon.SettingsPanel.Create({
        getL = function()
          return {
            SETTINGS_SECTION_GENERAL = "General",
            SETTINGS_SECTION_DISPLAY = "Display",
            SETTINGS_SECTION_BEHAVIOR = "Behavior",
            SETTINGS_SECTION_DEBUG = "Debug",
            SETTINGS_LANGUAGE = "Language",
            SETTINGS_COMBAT_LOGGING = "Combat Logging",
            SETTINGS_DM_RESET = "DM Reset",
            SETTINGS_ESC_PANEL = "ESC Panel",
            SETTINGS_BG_ALPHA = "Background Opacity",
            SETTINGS_UI_SCALE = "UI Scale",
            SETTINGS_MINIMAP_BUTTON = "Minimap Button",
            SETTINGS_SYNC_ENABLED = "Addon Sync",
            SETTINGS_AUTO_OPEN_QUEUE = "Auto Open Queue",
            SETTINGS_AUTO_CLOSE_MAIN_FRAME = "Auto Close Main Frame",
            SETTINGS_DEFAULT_OPEN_UI = "Default UI on Open",
            SETTINGS_DEFAULT_OPEN_UI_LAST = "Last Used",
            SETTINGS_DEFAULT_OPEN_UI_V = "V",
            SETTINGS_DEFAULT_OPEN_UI_H = "H",
            SETTINGS_DEFAULT_OPEN_UI_M2 = "M2",
            SETTINGS_QUEUE_DEBUG = "Queue Debug",
            SETTINGS_RUNTIME_LOG = "Runtime Log",
          }
        end,
        getCurrentLocale = function()
          return "enUS"
        end,
        setLanguage = function() end,
        getDB = function()
          return db
        end,
      })

      Assert.NotNil(panel, "settings panel should be created when Blizzard Settings API exists")
      Assert.Nil(db.autoCloseMainFrame, "opening settings should not persist the default auto-close value")

      local autoCloseCheck = nil
      for _, frame in ipairs(createdFrames) do
        if frame._settingKey == "SETTINGS_AUTO_CLOSE_MAIN_FRAME" then
          autoCloseCheck = frame
          break
        end
      end

      autoCloseCheck = Assert.NotNil(autoCloseCheck, "settings panel should create an auto-close checkbox")
      ---@diagnostic disable: undefined-field
      Assert.False(autoCloseCheck:GetChecked(), "auto-close should default to disabled when no saved value exists")

      db.autoCloseMainFrame = true
      panel.Refresh()

      Assert.True(autoCloseCheck:GetChecked(), "refresh should honor an explicit true override")
      ---@diagnostic enable: undefined-field
    end)
  end)

  test("Settings panel defaults combat fade to disabled until the user turns it on", function()
    local createFrameStub, createdFrames = BuildCreateFrameStub()
    local db = {}

    WithGlobals({
      UIParent = {},
      IsiLiveDB = db,
      CreateFrame = createFrameStub,
      Settings = {
        RegisterCanvasLayoutCategory = function(canvas, name)
          return { canvas = canvas, name = name }
        end,
        RegisterAddOnCategory = function() end,
      },
    }, function()
      local addon = LoadAddonModules({ "isiLive_ui_common.lua", "isiLive_settings.lua" })
      local panel = addon.SettingsPanel.Create({
        getL = function()
          return {
            SETTINGS_SECTION_GENERAL = "General",
            SETTINGS_SECTION_DISPLAY = "Display",
            SETTINGS_SECTION_BEHAVIOR = "Behavior",
            SETTINGS_SECTION_DEBUG = "Debug",
            SETTINGS_LANGUAGE = "Language",
            SETTINGS_COMBAT_LOGGING = "Combat Logging",
            SETTINGS_DM_RESET = "DM Reset",
            SETTINGS_ESC_PANEL = "ESC Panel",
            SETTINGS_BG_ALPHA = "Background Opacity",
            SETTINGS_UI_SCALE = "UI Scale",
            SETTINGS_MINIMAP_BUTTON = "Minimap Button",
            SETTINGS_SYNC_ENABLED = "Addon Sync",
            SETTINGS_AUTO_OPEN_QUEUE = "Auto Open Queue",
            SETTINGS_AUTO_CLOSE_MAIN_FRAME = "Auto Close Main Frame",
            SETTINGS_DEFAULT_OPEN_UI = "Default UI on Open",
            SETTINGS_DEFAULT_OPEN_UI_LAST = "Last Used",
            SETTINGS_DEFAULT_OPEN_UI_V = "V",
            SETTINGS_DEFAULT_OPEN_UI_H = "H",
            SETTINGS_DEFAULT_OPEN_UI_M2 = "M2",
            SETTINGS_COMBAT_FADE_MM = "Fade out in Combat (M2 only)",
            SETTINGS_QUEUE_DEBUG = "Queue Debug",
            SETTINGS_RUNTIME_LOG = "Runtime Log",
          }
        end,
        getCurrentLocale = function()
          return "enUS"
        end,
        setLanguage = function() end,
        getDB = function()
          return db
        end,
      })

      Assert.NotNil(panel, "settings panel should be created when Blizzard Settings API exists")
      Assert.Nil(db.combatFadeMM, "opening settings should not persist the combat fade default")

      local combatFadeCheck = nil
      for _, frame in ipairs(createdFrames) do
        if frame._settingKey == "SETTINGS_COMBAT_FADE_MM" then
          combatFadeCheck = frame
          break
        end
      end

      combatFadeCheck = Assert.NotNil(combatFadeCheck, "settings panel should create a combat fade checkbox")
      ---@diagnostic disable: undefined-field
      Assert.False(combatFadeCheck:GetChecked(), "combat fade should default to disabled when no saved value exists")

      panel.Refresh()

      Assert.Nil(db.combatFadeMM, "refresh should not persist the combat fade default")

      combatFadeCheck:SetChecked(true)
      local onClick = combatFadeCheck._scripts and combatFadeCheck._scripts.OnClick or nil
      onClick = Assert.NotNil(onClick, "combat fade checkbox should define OnClick")
      onClick(combatFadeCheck)
      ---@diagnostic enable: undefined-field

      Assert.True(db.combatFadeMM, "user enabling combat fade should be persisted")
      Assert.True(combatFadeCheck:GetChecked(), "user enabling combat fade should keep the checkbox checked")
    end)
  end)

  test("Settings panel defaults Login / Reload auto-show and Key-End auto-open to enabled", function()
    local createFrameStub, createdFrames = BuildCreateFrameStub()
    local db = {}
    local startupToggleStates = {}
    local keyEndToggleStates = {}

    WithGlobals({
      UIParent = {},
      IsiLiveDB = db,
      CreateFrame = createFrameStub,
      Settings = {
        RegisterCanvasLayoutCategory = function(canvas, name)
          return { canvas = canvas, name = name }
        end,
        RegisterAddOnCategory = function() end,
      },
    }, function()
      local addon = LoadAddonModules({ "isiLive_ui_common.lua", "isiLive_settings.lua" })
      local panel = addon.SettingsPanel.Create({
        getL = function()
          return {
            SETTINGS_SECTION_GENERAL = "General",
            SETTINGS_SECTION_DISPLAY = "Display",
            SETTINGS_SECTION_BEHAVIOR = "Behavior",
            SETTINGS_SECTION_DEBUG = "Debug",
            SETTINGS_LANGUAGE = "Language",
            SETTINGS_COMBAT_LOGGING = "Combat Logging",
            SETTINGS_DM_RESET = "DM Reset",
            SETTINGS_ESC_PANEL = "ESC Panel",
            SETTINGS_BG_ALPHA = "Background Opacity",
            SETTINGS_UI_SCALE = "UI Scale",
            SETTINGS_MINIMAP_BUTTON = "Minimap Button",
            SETTINGS_SYNC_ENABLED = "Addon Sync",
            SETTINGS_AUTO_OPEN_QUEUE = "Auto Open Queue",
            SETTINGS_AUTO_CLOSE_MAIN_FRAME = "Auto Close Main Frame",
            SETTINGS_AUTO_SHOW_MAIN_FRAME_ON_STARTUP = "Show on Login / Reload",
            SETTINGS_AUTO_OPEN_MAIN_FRAME_ON_KEY_END = "Auto Open on Key End",
            SETTINGS_DEFAULT_OPEN_UI = "Default UI on Open",
            SETTINGS_DEFAULT_OPEN_UI_LAST = "Last Used",
            SETTINGS_DEFAULT_OPEN_UI_V = "V",
            SETTINGS_DEFAULT_OPEN_UI_H = "H",
            SETTINGS_DEFAULT_OPEN_UI_M2 = "M2",
            SETTINGS_RAID_TRANSITION_BEHAVIOR = "Raid Behavior",
            SETTINGS_RAID_TRANSITION_BEHAVIOR_HIDE = "Raid Off",
            SETTINGS_QUEUE_DEBUG = "Queue Debug",
            SETTINGS_RUNTIME_LOG = "Runtime Log",
          }
        end,
        getCurrentLocale = function()
          return "enUS"
        end,
        setLanguage = function() end,
        getDB = function()
          return db
        end,
        onAutoShowMainFrameOnStartupToggle = function(enabled)
          startupToggleStates[#startupToggleStates + 1] = enabled and true or false
        end,
        onAutoOpenMainFrameOnKeyEndToggle = function(enabled)
          keyEndToggleStates[#keyEndToggleStates + 1] = enabled and true or false
        end,
      })

      Assert.NotNil(panel, "settings panel should be created when Blizzard Settings API exists")
      Assert.Nil(db.autoShowMainFrameOnStartup, "opening settings should not persist the default startup auto-show")
      Assert.Nil(db.autoOpenMainFrameOnKeyEnd, "opening settings should not persist the default key-end auto-open")

      local startupCheck = nil
      local keyEndCheck = nil
      for _, frame in ipairs(createdFrames) do
        if frame._settingKey == "SETTINGS_AUTO_SHOW_MAIN_FRAME_ON_STARTUP" then
          startupCheck = frame
        elseif frame._settingKey == "SETTINGS_AUTO_OPEN_MAIN_FRAME_ON_KEY_END" then
          keyEndCheck = frame
        end
      end

      startupCheck = Assert.NotNil(startupCheck, "settings panel should create a startup auto-show checkbox")
      keyEndCheck = Assert.NotNil(keyEndCheck, "settings panel should create a key-end auto-open checkbox")
      ---@diagnostic disable: undefined-field
      Assert.True(startupCheck:GetChecked(), "startup auto-show should default to enabled")
      Assert.True(keyEndCheck:GetChecked(), "key-end auto-open should default to enabled")

      local onClickStartup = startupCheck._scripts and startupCheck._scripts.OnClick or nil
      local onClickKeyEnd = keyEndCheck._scripts and keyEndCheck._scripts.OnClick or nil
      onClickStartup = Assert.NotNil(onClickStartup, "startup checkbox should define OnClick")
      onClickKeyEnd = Assert.NotNil(onClickKeyEnd, "key-end checkbox should define OnClick")

      startupCheck:SetChecked(false)
      onClickStartup(startupCheck)
      keyEndCheck:SetChecked(false)
      onClickKeyEnd(keyEndCheck)

      Assert.False(db.autoShowMainFrameOnStartup, "disabling startup auto-show should persist false")
      Assert.False(db.autoOpenMainFrameOnKeyEnd, "disabling key-end auto-open should persist false")
      Assert.Equal(startupToggleStates[1], false, "startup checkbox should notify its callback")
      Assert.Equal(keyEndToggleStates[1], false, "key-end checkbox should notify its callback")
      ---@diagnostic enable: undefined-field
    end)
  end)
end

local function RegisterSettingsPanelAdvancedTests(test, Assert, WithGlobals, LoadAddonModules)
  test("Settings panel keeps column guides disabled by default and lets the user enable them", function()
    local createFrameStub, createdFrames = BuildCreateFrameStub()
    local db = {}
    local callbackStates = {}

    WithGlobals({
      UIParent = {},
      IsiLiveDB = db,
      CreateFrame = createFrameStub,
      Settings = {
        RegisterCanvasLayoutCategory = function(canvas, name)
          return { canvas = canvas, name = name }
        end,
        RegisterAddOnCategory = function() end,
      },
    }, function()
      local addon = LoadAddonModules({ "isiLive_ui_common.lua", "isiLive_settings.lua" })
      local panel = addon.SettingsPanel.Create({
        getL = function()
          return {
            SETTINGS_SECTION_GENERAL = "General",
            SETTINGS_SECTION_DISPLAY = "Display",
            SETTINGS_SECTION_BEHAVIOR = "Behavior",
            SETTINGS_SECTION_DEBUG = "Debug",
            SETTINGS_LANGUAGE = "Language",
            SETTINGS_COMBAT_LOGGING = "Combat Logging",
            SETTINGS_DM_RESET = "DM Reset",
            SETTINGS_ESC_PANEL = "ESC Panel",
            SETTINGS_BG_ALPHA = "Background Opacity",
            SETTINGS_UI_SCALE = "UI Scale",
            SETTINGS_MINIMAP_BUTTON = "Minimap Button",
            SETTINGS_SYNC_ENABLED = "Addon Sync",
            SETTINGS_AUTO_OPEN_QUEUE = "Auto Open Queue",
            SETTINGS_AUTO_CLOSE_MAIN_FRAME = "Auto Close Main Frame",
            SETTINGS_DEFAULT_OPEN_UI = "Default UI on Open",
            SETTINGS_DEFAULT_OPEN_UI_LAST = "Last Used",
            SETTINGS_DEFAULT_OPEN_UI_V = "V",
            SETTINGS_DEFAULT_OPEN_UI_H = "H",
            SETTINGS_DEFAULT_OPEN_UI_M2 = "M2",
            SETTINGS_ROSTER_COLUMN_GUIDES = "Column Guides",
            SETTINGS_QUEUE_DEBUG = "Queue Debug",
            SETTINGS_RUNTIME_LOG = "Runtime Log",
          }
        end,
        getCurrentLocale = function()
          return "enUS"
        end,
        setLanguage = function() end,
        getDB = function()
          return db
        end,
        onRosterColumnGuidesToggle = function(enabled)
          callbackStates[#callbackStates + 1] = enabled and true or false
        end,
      })

      Assert.NotNil(panel, "settings panel should be created when Blizzard Settings API exists")
      Assert.Nil(db.showRosterColumnGuides, "column guides should stay unset until the user chooses them")

      local guideCheck = nil
      for _, frame in ipairs(createdFrames) do
        if frame._settingKey == "SETTINGS_ROSTER_COLUMN_GUIDES" then
          guideCheck = frame
          break
        end
      end

      guideCheck = Assert.NotNil(guideCheck, "settings panel should create a column-guides checkbox")
      ---@diagnostic disable: undefined-field
      Assert.False(guideCheck:GetChecked(), "column guides should default to disabled")

      local onClick = guideCheck._scripts and guideCheck._scripts.OnClick or nil
      onClick = Assert.NotNil(onClick, "column guides checkbox should define OnClick")

      guideCheck:SetChecked(true)
      onClick(guideCheck)
      Assert.True(db.showRosterColumnGuides, "enabling the checkbox should persist the enabled setting")
      Assert.Equal(callbackStates[1], true, "enabling the checkbox should notify the callback")

      panel.Refresh()
      Assert.True(guideCheck:GetChecked(), "refresh should keep the enabled checkbox state")

      guideCheck:SetChecked(false)
      onClick(guideCheck)
      Assert.False(db.showRosterColumnGuides, "disabling the checkbox should persist the disabled setting")
      Assert.Equal(callbackStates[2], false, "disabling the checkbox should notify the callback")
      ---@diagnostic enable: undefined-field
    end)
  end)

  test("Settings panel defaults Timeways Navigator to enabled until the user turns it off", function()
    local createFrameStub, createdFrames = BuildCreateFrameStub()
    local db = {}
    local callbackStates = {}

    WithGlobals({
      UIParent = {},
      IsiLiveDB = db,
      CreateFrame = createFrameStub,
      Settings = {
        RegisterCanvasLayoutCategory = function(canvas, name)
          return { canvas = canvas, name = name }
        end,
        RegisterAddOnCategory = function() end,
      },
    }, function()
      local addon = LoadAddonModules({ "isiLive_ui_common.lua", "isiLive_settings.lua" })
      local panel = addon.SettingsPanel.Create({
        getL = function()
          return {
            SETTINGS_SECTION_GENERAL = "General",
            SETTINGS_SECTION_DISPLAY = "Display",
            SETTINGS_SECTION_BEHAVIOR = "Behavior",
            SETTINGS_SECTION_DEBUG = "Debug",
            SETTINGS_LANGUAGE = "Language",
            SETTINGS_COMBAT_LOGGING = "Combat Logging",
            SETTINGS_DM_RESET = "DM Reset",
            SETTINGS_ESC_PANEL = "ESC Panel",
            SETTINGS_BG_ALPHA = "Background Opacity",
            SETTINGS_UI_SCALE = "UI Scale",
            SETTINGS_MINIMAP_BUTTON = "Minimap Button",
            SETTINGS_SYNC_ENABLED = "Addon Sync",
            SETTINGS_AUTO_OPEN_QUEUE = "Auto Open Queue",
            SETTINGS_AUTO_CLOSE_MAIN_FRAME = "Auto Close Main Frame",
            SETTINGS_DEFAULT_OPEN_UI = "Default UI on Open",
            SETTINGS_DEFAULT_OPEN_UI_LAST = "Last Used",
            SETTINGS_DEFAULT_OPEN_UI_V = "V",
            SETTINGS_DEFAULT_OPEN_UI_H = "H",
            SETTINGS_DEFAULT_OPEN_UI_M2 = "M2",
            SETTINGS_ROSTER_COLUMN_GUIDES = "Column Guides",
            SETTINGS_SHOW_TIMEWAYS_NAVIGATOR = "Show Timeways Navigator",
            SETTINGS_QUEUE_DEBUG = "Queue Debug",
            SETTINGS_RUNTIME_LOG = "Runtime Log",
          }
        end,
        getCurrentLocale = function()
          return "enUS"
        end,
        setLanguage = function() end,
        getDB = function()
          return db
        end,
        onPortalNavigatorToggle = function(enabled)
          callbackStates[#callbackStates + 1] = enabled and true or false
        end,
      })

      Assert.NotNil(panel, "settings panel should be created when Blizzard Settings API exists")
      Assert.Nil(db.showPortalNavigator, "opening settings should not persist the default portal navigator value")

      local navigatorCheck = nil
      for _, frame in ipairs(createdFrames) do
        if frame._settingKey == "SETTINGS_SHOW_TIMEWAYS_NAVIGATOR" then
          navigatorCheck = frame
          break
        end
      end

      navigatorCheck = Assert.NotNil(navigatorCheck, "settings panel should create a portal navigator checkbox")
      ---@diagnostic disable: undefined-field
      Assert.True(navigatorCheck:GetChecked(), "portal navigator should default to enabled when no saved value exists")
      Assert.Equal(
        navigatorCheck.label:GetText(),
        "Show Timeways Navigator",
        "portal navigator label should use the English settings text"
      )

      local onClick = navigatorCheck._scripts and navigatorCheck._scripts.OnClick or nil
      onClick = Assert.NotNil(onClick, "portal navigator checkbox should define OnClick")

      navigatorCheck:SetChecked(false)
      onClick(navigatorCheck)
      Assert.False(db.showPortalNavigator, "disabling the checkbox should persist the disabled setting")
      Assert.Equal(callbackStates[1], false, "disabling the checkbox should notify the callback")

      panel.Refresh()
      Assert.False(navigatorCheck:GetChecked(), "refresh should keep the disabled portal navigator state")
      ---@diagnostic enable: undefined-field
    end)
  end)

  test("Settings panel defaults Raid behavior to Raid Off and persists user choice", function()
    local createFrameStub, createdFrames = BuildCreateFrameStub()
    local db = {}
    local raidBehaviorChanges = {}

    WithGlobals({
      UIParent = {},
      IsiLiveDB = db,
      CreateFrame = createFrameStub,
      Settings = {
        RegisterCanvasLayoutCategory = function(canvas, name)
          return { canvas = canvas, name = name }
        end,
        RegisterAddOnCategory = function() end,
      },
    }, function()
      local addon = LoadAddonModules({ "isiLive_ui_common.lua", "isiLive_settings.lua" })
      local panel = addon.SettingsPanel.Create({
        getL = function()
          return {
            SETTINGS_SECTION_GENERAL = "General",
            SETTINGS_SECTION_DISPLAY = "Display",
            SETTINGS_SECTION_BEHAVIOR = "Behavior",
            SETTINGS_SECTION_DEBUG = "Debug",
            SETTINGS_LANGUAGE = "Language",
            SETTINGS_COMBAT_LOGGING = "Combat Logging",
            SETTINGS_DM_RESET = "DM Reset",
            SETTINGS_ESC_PANEL = "ESC Panel",
            SETTINGS_BG_ALPHA = "Background Opacity",
            SETTINGS_UI_SCALE = "UI Scale",
            SETTINGS_MINIMAP_BUTTON = "Minimap Button",
            SETTINGS_SYNC_ENABLED = "Addon Sync",
            SETTINGS_AUTO_OPEN_QUEUE = "Auto Open Queue",
            SETTINGS_AUTO_CLOSE_MAIN_FRAME = "Auto Close Main Frame",
            SETTINGS_AUTO_SHOW_MAIN_FRAME_ON_STARTUP = "Show on Login / Reload",
            SETTINGS_AUTO_OPEN_MAIN_FRAME_ON_KEY_END = "Auto Open on Key End",
            SETTINGS_DEFAULT_OPEN_UI = "Default UI on Open",
            SETTINGS_DEFAULT_OPEN_UI_LAST = "Last Used",
            SETTINGS_DEFAULT_OPEN_UI_V = "V",
            SETTINGS_DEFAULT_OPEN_UI_H = "H",
            SETTINGS_DEFAULT_OPEN_UI_M2 = "M2",
            SETTINGS_RAID_TRANSITION_BEHAVIOR = "Raid Behavior",
            SETTINGS_RAID_TRANSITION_BEHAVIOR_HIDE = "Raid Off",
            SETTINGS_ROSTER_COLUMN_GUIDES = "Column Guides",
            SETTINGS_SHOW_TIMEWAYS_NAVIGATOR = "Show Timeways Navigator",
            SETTINGS_QUEUE_DEBUG = "Queue Debug",
            SETTINGS_RUNTIME_LOG = "Runtime Log",
          }
        end,
        getCurrentLocale = function()
          return "enUS"
        end,
        setLanguage = function() end,
        getDB = function()
          return db
        end,
        onRaidTransitionBehaviorChange = function(value)
          raidBehaviorChanges[#raidBehaviorChanges + 1] = value
        end,
      })

      Assert.NotNil(panel, "settings panel should be created when Blizzard Settings API exists")
      Assert.Nil(db.raidTransitionBehavior, "opening settings should not persist the default raid behavior")

      local hideButton = nil
      for _, frame in ipairs(createdFrames) do
        if frame._optionValue == "hide" then
          hideButton = frame
        end
      end

      hideButton = Assert.NotNil(hideButton, "settings panel should create a Raid Off raid-behavior button")
      ---@diagnostic disable: undefined-field
      Assert.Equal(hideButton._backdropColor[4], 0.25, "Raid Off should be highlighted by default")

      local onClickHide = hideButton._scripts and hideButton._scripts.OnClick or nil
      onClickHide = Assert.NotNil(onClickHide, "raid-behavior button should define OnClick")
      onClickHide(hideButton, "LeftButton")

      Assert.Equal(db.raidTransitionBehavior, "hide", "choosing Raid Off should persist the disabled mode")
      Assert.Equal(raidBehaviorChanges[1], "hide", "raid behavior selector should notify the callback")
      ---@diagnostic enable: undefined-field
    end)
  end)
end

local function RegisterSettingsPanelSoundAndLegacyTests(test, Assert, WithGlobals, LoadAddonModules)
  test("Settings panel exposes sound toggles with the intended defaults", function()
    local createFrameStub, createdFrames = BuildCreateFrameStub()
    local db = {}

    WithGlobals({
      UIParent = {},
      IsiLiveDB = db,
      CreateFrame = createFrameStub,
      Settings = {
        RegisterCanvasLayoutCategory = function(canvas, name)
          return { canvas = canvas, name = name }
        end,
        RegisterAddOnCategory = function() end,
      },
    }, function()
      local addon = LoadAddonModules({ "isiLive_ui_common.lua", "isiLive_settings.lua" })
      local panel = addon.SettingsPanel.Create({
        getL = function()
          return {
            SETTINGS_SECTION_GENERAL = "General",
            SETTINGS_SECTION_DISPLAY = "Display",
            SETTINGS_SECTION_BEHAVIOR = "Behavior",
            SETTINGS_SECTION_DEBUG = "Debug",
            SETTINGS_LANGUAGE = "Language",
            SETTINGS_COMBAT_LOGGING = "Combat Logging",
            SETTINGS_DM_RESET = "DM Reset",
            SETTINGS_ESC_PANEL = "ESC Panel",
            SETTINGS_BG_ALPHA = "Background Opacity",
            SETTINGS_UI_SCALE = "UI Scale",
            SETTINGS_MINIMAP_BUTTON = "Minimap Button",
            SETTINGS_SYNC_ENABLED = "Addon Sync",
            SETTINGS_AUTO_OPEN_QUEUE = "Auto Open Queue",
            SETTINGS_AUTO_CLOSE_MAIN_FRAME = "Auto Close Main Frame",
            SETTINGS_AUTO_SHOW_MAIN_FRAME_ON_STARTUP = "Show on Login / Reload",
            SETTINGS_AUTO_OPEN_MAIN_FRAME_ON_KEY_END = "Auto Open on Key End",
            SETTINGS_RAID_TRANSITION_BEHAVIOR = "Raid Behavior",
            SETTINGS_RAID_TRANSITION_BEHAVIOR_HIDE = "Raid Off",
            SETTINGS_ROSTER_COLUMN_GUIDES = "Column Guides",
            SETTINGS_SHOW_TIMEWAYS_NAVIGATOR = "Show Timeways Navigator",
            SETTINGS_SECTION_SOUNDS = "Sounds",
            SETTINGS_SOUND_LEAD_ENABLED = "Sound: Lead Transfer",
            SETTINGS_SOUND_GROUP_JOIN_ENABLED = "Sound: Full Group",
            SETTINGS_SOUND_PORTAL_AVAILABLE = "Sound: Incoming Summon",
            SETTINGS_SOUND_BATTLE_RES = "Sound: Battle Res",
            SETTINGS_SOUND_BLOODLUST = "Sound: Bloodlust",
            SETTINGS_QUEUE_DEBUG = "Queue Debug",
            SETTINGS_RUNTIME_LOG = "Runtime Log",
          }
        end,
        getCurrentLocale = function()
          return "enUS"
        end,
        setLanguage = function() end,
        getDB = function()
          return db
        end,
      })

      Assert.NotNil(panel, "settings panel should be created when Blizzard Settings API exists")
      Assert.Nil(db.soundLeadEnabled, "opening settings should not persist the default leader-sound state")
      Assert.Nil(db.soundGroupJoinEnabled, "opening settings should not persist the default group-join sound state")
      Assert.Nil(db.soundPortalAvailableEnabled, "opening settings should not persist the default portal sound state")
      Assert.Nil(db.soundBattleResEnabled, "opening settings should not persist the default battle-res sound state")
      Assert.Nil(db.soundBloodlustEnabled, "opening settings should not persist the default bloodlust sound state")

      local soundSectionHeader = nil
      local leadSoundCheck = nil
      local groupJoinSoundCheck = nil
      local portalSoundCheck = nil
      local battleResSoundCheck = nil
      local bloodlustSoundCheck = nil
      for _, frame in ipairs(createdFrames) do
        if frame._sectionKey == "SETTINGS_SECTION_SOUNDS" then
          soundSectionHeader = frame
        end
        if frame._settingKey == "SETTINGS_SOUND_LEAD_ENABLED" then
          leadSoundCheck = frame
        elseif frame._settingKey == "SETTINGS_SOUND_GROUP_JOIN_ENABLED" then
          groupJoinSoundCheck = frame
        elseif frame._settingKey == "SETTINGS_SOUND_PORTAL_AVAILABLE" then
          portalSoundCheck = frame
        elseif frame._settingKey == "SETTINGS_SOUND_BATTLE_RES" then
          battleResSoundCheck = frame
        elseif frame._settingKey == "SETTINGS_SOUND_BLOODLUST" then
          bloodlustSoundCheck = frame
        end
      end

      Assert.NotNil(soundSectionHeader, "settings panel should create a dedicated sounds section")
      leadSoundCheck = Assert.NotNil(leadSoundCheck, "settings panel should create a leader-transfer sound checkbox")
      groupJoinSoundCheck =
        Assert.NotNil(groupJoinSoundCheck, "settings panel should create a group-join sound checkbox")
      portalSoundCheck = Assert.NotNil(portalSoundCheck, "settings panel should create a portal sound checkbox")
      battleResSoundCheck =
        Assert.NotNil(battleResSoundCheck, "settings panel should create a battle-res sound checkbox")
      bloodlustSoundCheck =
        Assert.NotNil(bloodlustSoundCheck, "settings panel should create a bloodlust sound checkbox")
      ---@diagnostic disable: undefined-field
      Assert.True(leadSoundCheck:GetChecked(), "leader-transfer sound should default to enabled")
      Assert.True(groupJoinSoundCheck:GetChecked(), "group-join sound should default to enabled")
      Assert.True(portalSoundCheck:GetChecked(), "portal sound should default to enabled")
      Assert.True(battleResSoundCheck:GetChecked(), "battle-res sound should default to enabled")
      Assert.True(bloodlustSoundCheck:GetChecked(), "bloodlust sound should default to enabled")

      local onClickLead = leadSoundCheck._scripts and leadSoundCheck._scripts.OnClick or nil
      local onClickJoin = groupJoinSoundCheck._scripts and groupJoinSoundCheck._scripts.OnClick or nil
      local onClickPortal = portalSoundCheck._scripts and portalSoundCheck._scripts.OnClick or nil
      local onClickBattleRes = battleResSoundCheck._scripts and battleResSoundCheck._scripts.OnClick or nil
      local onClickBloodlust = bloodlustSoundCheck._scripts and bloodlustSoundCheck._scripts.OnClick or nil
      onClickLead = Assert.NotNil(onClickLead, "leader-transfer sound checkbox should define OnClick")
      onClickJoin = Assert.NotNil(onClickJoin, "group-join sound checkbox should define OnClick")
      onClickPortal = Assert.NotNil(onClickPortal, "portal sound checkbox should define OnClick")
      onClickBattleRes = Assert.NotNil(onClickBattleRes, "battle-res sound checkbox should define OnClick")
      onClickBloodlust = Assert.NotNil(onClickBloodlust, "bloodlust sound checkbox should define OnClick")

      leadSoundCheck:SetChecked(false)
      onClickLead(leadSoundCheck)
      groupJoinSoundCheck:SetChecked(true)
      onClickJoin(groupJoinSoundCheck)
      portalSoundCheck:SetChecked(false)
      onClickPortal(portalSoundCheck)
      battleResSoundCheck:SetChecked(false)
      onClickBattleRes(battleResSoundCheck)
      bloodlustSoundCheck:SetChecked(true)
      onClickBloodlust(bloodlustSoundCheck)

      Assert.False(db.soundLeadEnabled, "disabling leader-transfer sound should persist false")
      Assert.True(db.soundGroupJoinEnabled, "enabling group-join sound should persist true")
      Assert.False(db.soundPortalAvailableEnabled, "disabling portal sound should persist false")
      Assert.False(db.soundBattleResEnabled, "disabling battle-res sound should persist false")
      Assert.True(db.soundBloodlustEnabled, "enabling bloodlust sound should persist true")

      panel.Refresh()
      Assert.False(leadSoundCheck:GetChecked(), "refresh should keep the disabled leader-transfer sound state")
      Assert.True(groupJoinSoundCheck:GetChecked(), "refresh should keep the enabled group-join sound state")
      Assert.False(portalSoundCheck:GetChecked(), "refresh should keep the disabled portal sound state")
      Assert.False(battleResSoundCheck:GetChecked(), "refresh should keep the disabled battle-res sound state")
      Assert.True(bloodlustSoundCheck:GetChecked(), "refresh should keep the enabled bloodlust sound state")
      ---@diagnostic enable: undefined-field
    end)
  end)

  test("Settings panel expands layout height for wrapped intro and hint text", function()
    local function BuildPanelHeight(textSet)
      local createFrameStub = BuildCreateFrameStub()
      local db = {}
      local panel = nil

      WithGlobals({
        UIParent = {},
        IsiLiveDB = db,
        CreateFrame = createFrameStub,
        Settings = {
          RegisterCanvasLayoutCategory = function(canvas, name)
            return { canvas = canvas, name = name }
          end,
          RegisterAddOnCategory = function() end,
        },
      }, function()
        local addon = LoadAddonModules({ "isiLive_ui_common.lua", "isiLive_settings.lua" })
        panel = addon.SettingsPanel.Create({
          getL = function()
            return textSet
          end,
          getCurrentLocale = function()
            return "enUS"
          end,
          setLanguage = function() end,
          getDB = function()
            return db
          end,
        })
      end)

      return RequireValue(panel, "settings panel should exist").content:GetHeight()
    end

    local shortHeight = BuildPanelHeight({
      SETTINGS_SECTION_GENERAL = "General",
      SETTINGS_SECTION_GENERAL_HINT = "Short general hint.",
      SETTINGS_SECTION_DISPLAY = "Display",
      SETTINGS_SECTION_DISPLAY_HINT = "Short display hint.",
      SETTINGS_SECTION_BEHAVIOR = "Behavior",
      SETTINGS_SECTION_BEHAVIOR_HINT = "Short behavior hint.",
      SETTINGS_SECTION_SOUNDS = "Sounds",
      SETTINGS_SECTION_SOUNDS_HINT = "Short sounds hint.",
      SETTINGS_SECTION_DEBUG = "Debug",
      SETTINGS_SECTION_DEBUG_HINT = "Short debug hint.",
      SETTINGS_SECTION_RESET_HINT = "Short reset hint.",
      SETTINGS_PAGE_HINT = "Short intro.",
      SETTINGS_BETA_NOTICE = "Beta",
      BETA_NOTICE_TEXT = "Short beta notice.",
      SETTINGS_LANGUAGE = "Language",
      SETTINGS_COMBAT_LOGGING = "Combat Logging",
      SETTINGS_DM_RESET = "DM Reset",
      SETTINGS_ESC_PANEL = "ESC Panel",
      SETTINGS_BG_ALPHA = "Background Opacity",
      SETTINGS_UI_SCALE = "UI Scale",
      SETTINGS_MINIMAP_BUTTON = "Minimap Button",
      SETTINGS_SYNC_ENABLED = "Addon Sync",
      SETTINGS_AUTO_OPEN_QUEUE = "Auto Open Queue",
      SETTINGS_AUTO_CLOSE_MAIN_FRAME = "Auto Close Main Frame",
      SETTINGS_AUTO_SHOW_MAIN_FRAME_ON_STARTUP = "Show on Login / Reload",
      SETTINGS_AUTO_OPEN_MAIN_FRAME_ON_KEY_END = "Auto Open on Key End",
      SETTINGS_RAID_TRANSITION_BEHAVIOR = "Raid Behavior",
      SETTINGS_RAID_TRANSITION_BEHAVIOR_HIDE = "Raid Off",
      SETTINGS_ROSTER_COLUMN_GUIDES = "Column Guides",
      SETTINGS_SHOW_TIMEWAYS_NAVIGATOR = "Show Timeways Navigator",
      SETTINGS_SOUND_LEAD_ENABLED = "Sound: Lead Transfer",
      SETTINGS_SOUND_GROUP_JOIN_ENABLED = "Sound: Full Group",
      SETTINGS_SOUND_PORTAL_AVAILABLE = "Sound: Incoming Summon",
      SETTINGS_SOUND_BATTLE_RES = "Sound: Battle Res",
      SETTINGS_SOUND_BLOODLUST = "Sound: Bloodlust",
      SETTINGS_QUEUE_DEBUG = "Queue Debug",
      SETTINGS_RUNTIME_LOG = "Runtime Log",
    })
    local longHeight = BuildPanelHeight({
      SETTINGS_SECTION_GENERAL = "General",
      SETTINGS_SECTION_GENERAL_HINT = "This is a much longer general section hint "
        .. "that wraps across multiple lines and should increase the layout height.",
      SETTINGS_SECTION_DISPLAY = "Display",
      SETTINGS_SECTION_DISPLAY_HINT = "This display hint is intentionally long so "
        .. "the wrapped helper has to measure a taller block of text in the settings page.",
      SETTINGS_SECTION_BEHAVIOR = "Behavior",
      SETTINGS_SECTION_BEHAVIOR_HINT = "This behavior hint is intentionally long so "
        .. "the wrapped helper has to measure a taller block of text in the settings page.",
      SETTINGS_SECTION_SOUNDS = "Sounds",
      SETTINGS_SECTION_SOUNDS_HINT = "This sounds hint is intentionally long so "
        .. "the wrapped helper has to measure a taller block of text in the settings page.",
      SETTINGS_SECTION_DEBUG = "Debug",
      SETTINGS_SECTION_DEBUG_HINT = "This debug hint is intentionally long so "
        .. "the wrapped helper has to measure a taller block of text in the settings page.",
      SETTINGS_SECTION_RESET_HINT = "This reset hint is intentionally long so "
        .. "the wrapped helper has to measure a taller block of text in the settings page.",
      SETTINGS_PAGE_HINT = "This is a much longer intro text for the settings page "
        .. "that should wrap and reserve additional vertical space before the first section starts.",
      SETTINGS_BETA_NOTICE = "Beta",
      BETA_NOTICE_TEXT = "This beta notice text is intentionally much longer so it "
        .. "wraps and increases the height of the beta block above the URL fields.",
      SETTINGS_LANGUAGE = "Language",
      SETTINGS_COMBAT_LOGGING = "Combat Logging",
      SETTINGS_DM_RESET = "DM Reset",
      SETTINGS_ESC_PANEL = "ESC Panel",
      SETTINGS_BG_ALPHA = "Background Opacity",
      SETTINGS_UI_SCALE = "UI Scale",
      SETTINGS_MINIMAP_BUTTON = "Minimap Button",
      SETTINGS_SYNC_ENABLED = "Addon Sync",
      SETTINGS_AUTO_OPEN_QUEUE = "Auto Open Queue",
      SETTINGS_AUTO_CLOSE_MAIN_FRAME = "Auto Close Main Frame",
      SETTINGS_AUTO_SHOW_MAIN_FRAME_ON_STARTUP = "Show on Login / Reload",
      SETTINGS_AUTO_OPEN_MAIN_FRAME_ON_KEY_END = "Auto Open on Key End",
      SETTINGS_RAID_TRANSITION_BEHAVIOR = "Raid Behavior",
      SETTINGS_RAID_TRANSITION_BEHAVIOR_HIDE = "Raid Off",
      SETTINGS_ROSTER_COLUMN_GUIDES = "Column Guides",
      SETTINGS_SHOW_TIMEWAYS_NAVIGATOR = "Show Timeways Navigator",
      SETTINGS_SOUND_LEAD_ENABLED = "Sound: Lead Transfer",
      SETTINGS_SOUND_GROUP_JOIN_ENABLED = "Sound: Full Group",
      SETTINGS_SOUND_PORTAL_AVAILABLE = "Sound: Incoming Summon",
      SETTINGS_SOUND_BATTLE_RES = "Sound: Battle Res",
      SETTINGS_SOUND_BLOODLUST = "Sound: Bloodlust",
      SETTINGS_QUEUE_DEBUG = "Queue Debug",
      SETTINGS_RUNTIME_LOG = "Runtime Log",
    })

    Assert.True(
      longHeight > shortHeight,
      "wrapped settings hints must increase the total content height when texts become longer"
    )
  end)

  test("Settings panel hides disabled legacy display and behavior controls", function()
    local createFrameStub, createdFrames = BuildCreateFrameStub()
    local db = {
      nameMaxChars = 18,
      teleportColumns = 2,
    }

    WithGlobals({
      UIParent = {},
      IsiLiveDB = db,
      CreateFrame = createFrameStub,
      Settings = {
        RegisterCanvasLayoutCategory = function(canvas, name)
          return { canvas = canvas, name = name }
        end,
        RegisterAddOnCategory = function() end,
      },
    }, function()
      local addon = LoadAddonModules({ "isiLive_ui_common.lua", "isiLive_settings.lua" })
      local panel = addon.SettingsPanel.Create({
        getL = function()
          return {
            SETTINGS_SECTION_GENERAL = "General",
            SETTINGS_SECTION_DISPLAY = "Display",
            SETTINGS_SECTION_BEHAVIOR = "Behavior",
            SETTINGS_SECTION_DEBUG = "Debug",
            SETTINGS_LANGUAGE = "Language",
            SETTINGS_COMBAT_LOGGING = "Combat Logging",
            SETTINGS_DM_RESET = "DM Reset",
            SETTINGS_ESC_PANEL = "ESC Panel",
            SETTINGS_BG_ALPHA = "Background Opacity",
            SETTINGS_UI_SCALE = "UI Scale",
            SETTINGS_NAME_MAX_CHARS = "Name Length",
            SETTINGS_TELEPORT_COLUMNS = "Teleport Grid Columns",
            SETTINGS_MINIMAP_BUTTON = "Minimap Button",
            SETTINGS_SYNC_ENABLED = "Addon Sync",
            SETTINGS_AUTO_OPEN_QUEUE = "Auto Open Queue",
            SETTINGS_AUTO_CLOSE_MAIN_FRAME = "Auto Close Main Frame",
            SETTINGS_AUTO_SHOW_MAIN_FRAME_ON_STARTUP = "Show on Login / Reload",
            SETTINGS_AUTO_OPEN_MAIN_FRAME_ON_KEY_END = "Auto Open on Key End",
            SETTINGS_RAID_TRANSITION_BEHAVIOR = "Raid Behavior",
            SETTINGS_RAID_TRANSITION_BEHAVIOR_HIDE = "Raid Off",
            SETTINGS_QUEUE_DEBUG = "Queue Debug",
            SETTINGS_RUNTIME_LOG = "Runtime Log",
          }
        end,
        getCurrentLocale = function()
          return "enUS"
        end,
        setLanguage = function() end,
        getDB = function()
          return db
        end,
      })

      Assert.NotNil(panel, "settings panel should still be created")
      Assert.NotNil(panel.scrollFrame, "settings panel should expose a scroll frame for overflowing content")
      Assert.NotNil(panel.content, "settings panel should expose a scroll child for overflowing content")
      Assert.Equal(
        panel.scrollFrame:GetScrollChild(),
        panel.content,
        "settings scroll frame should be wired to the content child"
      )
      Assert.True(
        panel.content:GetHeight() > panel.scrollFrame:GetHeight(),
        "settings content should exceed the viewport height so the lower controls remain reachable via scrolling"
      )
      Assert.True(
        panel.scrollFrame:GetVerticalScrollRange() > 0,
        "settings scroll frame should expose a positive scroll range when content overflows"
      )

      local sliderCount = 0
      local checkboxCount = 0
      local scrollFrameCount = 0
      for _, frame in ipairs(createdFrames) do
        if frame._frameType == "Slider" then
          sliderCount = sliderCount + 1
        elseif frame._frameType == "CheckButton" then
          checkboxCount = checkboxCount + 1
        elseif frame._frameType == "ScrollFrame" then
          scrollFrameCount = scrollFrameCount + 1
        end
      end

      Assert.Equal(scrollFrameCount, 1, "settings should allocate exactly one content scroll frame")
      Assert.Equal(
        sliderCount,
        5,
        "settings should expose bg-alpha, UI-scale, nameplate font-size,"
          .. " nameplate X-offset, and nameplate Y-offset sliders"
      )
      Assert.Equal(
        checkboxCount,
        28,
        "settings should hide only the legacy name-length"
          .. " and teleport-column controls while keeping the startup/key-end, navigator, sound,"
          .. " chat-announce, combat-fade, nameplate-subtoggle, and accepted-invite-notice checkboxes visible"
          .. " (M+ forces tooltip/nameplate toggles replaced by a single 3-way display-mode selector)"
      )

      panel.Refresh()
      Assert.Equal(sliderCount, 5, "refresh should keep the nameplate font-size and offset sliders visible")
      Assert.Equal(
        checkboxCount,
        28,
        "refresh should keep the hidden legacy checkboxes out of the settings UI"
          .. " while preserving the visible sound, chat-announce, combat-fade, nameplate-subtoggle,"
          .. " and accepted-invite-notice checkboxes"
      )
    end)
  end)

  test("Settings nameplate font-size slider invokes onMobNameplateChange so live MobNameplate refreshes", function()
    -- Regression: ResolveSettingsOptions previously dropped onMobNameplateChange,
    -- so dragging the slider only persisted to DB but never reapplied SetAppearance
    -- on the live module — the rendered font size only changed after /reload.
    local createFrameStub, createdFrames = BuildCreateFrameStub()
    local db = { mobNameplateEnabled = true, mobNameplateFontSize = 12 }
    local nameplateChangeCalls = 0

    WithGlobals({
      UIParent = {},
      IsiLiveDB = db,
      CreateFrame = createFrameStub,
      Settings = {
        RegisterCanvasLayoutCategory = function(canvas, name)
          return { canvas = canvas, name = name }
        end,
        RegisterAddOnCategory = function() end,
      },
    }, function()
      local addon = LoadAddonModules({ "isiLive_ui_common.lua", "isiLive_settings.lua" })
      local panel = addon.SettingsPanel.Create({
        getL = function()
          return {
            SETTINGS_SECTION_GENERAL = "General",
            SETTINGS_SECTION_DISPLAY = "Display",
            SETTINGS_SECTION_BEHAVIOR = "Behavior",
            SETTINGS_SECTION_DEBUG = "Debug",
            SETTINGS_LANGUAGE = "Language",
            SETTINGS_NAMEPLATE_FONT_SIZE = "Font size",
          }
        end,
        getCurrentLocale = function()
          return "enUS"
        end,
        setLanguage = function() end,
        getDB = function()
          return db
        end,
        onMobNameplateChange = function()
          nameplateChangeCalls = nameplateChangeCalls + 1
        end,
      })

      Assert.NotNil(panel, "settings panel should be created when Blizzard Settings API exists")

      local slider = nil
      for _, frame in ipairs(createdFrames) do
        if frame._frameType == "Slider" and frame._settingKey == "SETTINGS_NAMEPLATE_FONT_SIZE" then
          slider = frame
          break
        end
      end
      slider = Assert.NotNil(slider, "settings should create the nameplate font-size slider")

      ---@diagnostic disable: undefined-field
      local onValueChanged = slider._scripts and slider._scripts.OnValueChanged or nil
      onValueChanged = Assert.NotNil(onValueChanged, "font-size slider should define OnValueChanged")
      onValueChanged(slider, 18)
      ---@diagnostic enable: undefined-field

      Assert.Equal(db.mobNameplateFontSize, 18, "slider drag should persist the new font size")
      Assert.Equal(
        nameplateChangeCalls,
        1,
        "slider drag must invoke onMobNameplateChange so the live MobNameplate module reapplies SetAppearance"
      )
    end)
  end)

  test(
    "Settings debug-log checkboxes reflect live controller state via getQueueDebugEnabled / getRuntimeLogEnabled",
    function()
      -- Regression: ResolveSettingsOptions used to drop both getters, so the
      -- queue-debug + runtime-log checkboxes always rendered unchecked when
      -- the settings panel was opened, even if the loggers were actively
      -- capturing.
      local createFrameStub, createdFrames = BuildCreateFrameStub()
      local db = {}

      WithGlobals({
        UIParent = {},
        IsiLiveDB = db,
        CreateFrame = createFrameStub,
        Settings = {
          RegisterCanvasLayoutCategory = function(canvas, name)
            return { canvas = canvas, name = name }
          end,
          RegisterAddOnCategory = function() end,
        },
      }, function()
        local addon = LoadAddonModules({ "isiLive_ui_common.lua", "isiLive_settings.lua" })
        local panel = addon.SettingsPanel.Create({
          getL = function()
            return {
              SETTINGS_SECTION_DEBUG = "Debug",
              SETTINGS_QUEUE_DEBUG = "Queue Debug Log",
              SETTINGS_RUNTIME_LOG = "Runtime Log",
            }
          end,
          getCurrentLocale = function()
            return "enUS"
          end,
          setLanguage = function() end,
          getDB = function()
            return db
          end,
          getQueueDebugEnabled = function()
            return true
          end,
          getRuntimeLogEnabled = function()
            return true
          end,
        })

        Assert.NotNil(panel, "settings panel should be created when Blizzard Settings API exists")

        local queueCheck, runtimeCheck = nil, nil
        for _, frame in ipairs(createdFrames) do
          if frame._settingKey == "SETTINGS_QUEUE_DEBUG" then
            queueCheck = frame
          elseif frame._settingKey == "SETTINGS_RUNTIME_LOG" then
            runtimeCheck = frame
          end
        end
        queueCheck = Assert.NotNil(queueCheck, "settings should expose the queue-debug checkbox")
        runtimeCheck = Assert.NotNil(runtimeCheck, "settings should expose the runtime-log checkbox")

        ---@diagnostic disable: undefined-field
        Assert.True(
          queueCheck:GetChecked() == true,
          "queue-debug checkbox must mirror getQueueDebugEnabled() == true on initial render"
        )
        Assert.True(
          runtimeCheck:GetChecked() == true,
          "runtime-log checkbox must mirror getRuntimeLogEnabled() == true on initial render"
        )
        ---@diagnostic enable: undefined-field
      end)
    end
  )

  test("Settings Refresh resyncs chatAnnounce checkboxes from DB after a reset", function()
    -- Regression: Refresh() updated the chat-announce checkbox labels but
    -- never called SetChecked, so the visible state could lag DB after
    -- /isilive reset until the panel was reopened.
    local createFrameStub, createdFrames = BuildCreateFrameStub()
    local db = { chatAnnounceBR = true, chatAnnounceLust = true }

    WithGlobals({
      UIParent = {},
      IsiLiveDB = db,
      CreateFrame = createFrameStub,
      Settings = {
        RegisterCanvasLayoutCategory = function(canvas, name)
          return { canvas = canvas, name = name }
        end,
        RegisterAddOnCategory = function() end,
      },
    }, function()
      local addon = LoadAddonModules({ "isiLive_ui_common.lua", "isiLive_settings.lua" })
      local panel = addon.SettingsPanel.Create({
        getL = function()
          return {
            SETTINGS_CHAT_BR_ANNOUNCE = "Chat BR",
            SETTINGS_CHAT_LUST_ANNOUNCE = "Chat Lust",
          }
        end,
        getCurrentLocale = function()
          return "enUS"
        end,
        setLanguage = function() end,
        getDB = function()
          return db
        end,
      })

      Assert.NotNil(panel, "settings panel should be created when Blizzard Settings API exists")

      local brCheck, lustCheck = nil, nil
      for _, frame in ipairs(createdFrames) do
        if frame._settingKey == "SETTINGS_CHAT_BR_ANNOUNCE" then
          brCheck = frame
        elseif frame._settingKey == "SETTINGS_CHAT_LUST_ANNOUNCE" then
          lustCheck = frame
        end
      end
      brCheck = Assert.NotNil(brCheck, "settings should expose the chatAnnounceBR checkbox")
      lustCheck = Assert.NotNil(lustCheck, "settings should expose the chatAnnounceLust checkbox")

      ---@diagnostic disable: undefined-field
      Assert.True(brCheck:GetChecked(), "chatAnnounceBR should start checked when DB says true")
      Assert.True(lustCheck:GetChecked(), "chatAnnounceLust should start checked when DB says true")

      -- Simulate /isilive reset: DB defaults flip to nil/false; Refresh must resync.
      db.chatAnnounceBR = false
      db.chatAnnounceLust = false
      panel.Refresh()

      Assert.False(brCheck:GetChecked(), "Refresh must resync chatAnnounceBR to false after DB reset")
      Assert.False(lustCheck:GetChecked(), "Refresh must resync chatAnnounceLust to false after DB reset")
      ---@diagnostic enable: undefined-field
    end)
  end)
end

local function RegisterSettingsPanelNameplateRoundtripTests(test, Assert, WithGlobals, LoadAddonModules)
  local function BuildPanel(db, createFrameStub, extraOpts)
    local addon = LoadAddonModules({ "isiLive_ui_common.lua", "isiLive_settings.lua" })
    local opts = {
      getL = function()
        return {
          SETTINGS_SECTION_GENERAL = "General",
          SETTINGS_SECTION_DISPLAY = "Display",
          SETTINGS_SECTION_BEHAVIOR = "Behavior",
          SETTINGS_SECTION_DEBUG = "Debug",
          SETTINGS_SECTION_NAMEPLATES = "Nameplates",
          SETTINGS_LANGUAGE = "Language",
          SETTINGS_NAMEPLATE_FONT_SIZE = "Font size",
          SETTINGS_NAMEPLATE_SHOW_PERCENT = "Show percentage",
          SETTINGS_NAMEPLATE_SHOW_REMAINING = "Show remaining needed",
          SETTINGS_NAMEPLATE_X_OFFSET = "X offset",
          SETTINGS_NAMEPLATE_Y_OFFSET = "Y offset",
          SETTINGS_NAMEPLATE_POSITION = "Position",
          SETTINGS_MPLUS_FORCES_DISPLAY_MODE = "Display mode",
        }
      end,
      getCurrentLocale = function()
        return "enUS"
      end,
      setLanguage = function() end,
      getDB = function()
        return db
      end,
      onMobNameplateChange = function() end,
      onMplusForcesToggle = function() end,
    }
    if type(extraOpts) == "table" then
      for k, v in pairs(extraOpts) do
        opts[k] = v
      end
    end
    return addon.SettingsPanel.Create(opts)
  end

  local function FindFrame(createdFrames, frameType, settingKey)
    for _, frame in ipairs(createdFrames) do
      if frame._frameType == frameType and frame._settingKey == settingKey then
        return frame
      end
    end
    return nil
  end

  local function FindOptionButton(createdFrames, settingKey, value)
    -- Option-selector buttons store the option value on `_optionValue` and
    -- inherit the parent selector's setting key only via the label frame's
    -- `_settingKey`; the button itself doesn't carry the key. Match by
    -- combining `_optionValue` with the click handler that closes over the
    -- selector's setter.
    for _, frame in ipairs(createdFrames) do
      if frame._frameType == "Button" and frame._optionValue == value and frame._scripts and frame._scripts.OnClick then
        return frame
      end
    end
    return nil
  end

  test("Settings nameplate font-size slider roundtrip persists user value across Refresh", function()
    local createFrameStub, createdFrames = BuildCreateFrameStub()
    local db = { mobNameplateEnabled = true }
    WithGlobals({
      UIParent = {},
      IsiLiveDB = db,
      CreateFrame = createFrameStub,
      Settings = {
        RegisterCanvasLayoutCategory = function(canvas, name)
          return { canvas = canvas, name = name }
        end,
        RegisterAddOnCategory = function() end,
      },
    }, function()
      local panel = Assert.NotNil(BuildPanel(db, createFrameStub), "settings panel must build")
      local slider =
        Assert.NotNil(FindFrame(createdFrames, "Slider", "SETTINGS_NAMEPLATE_FONT_SIZE"), "font-size slider must exist")
      ---@diagnostic disable: undefined-field
      local onValueChanged = Assert.NotNil(slider._scripts.OnValueChanged, "slider must define OnValueChanged")
      onValueChanged(slider, 22)
      Assert.Equal(db.mobNameplateFontSize, 22, "slider drag must persist fontSize=22 to DB")
      panel.Refresh()
      Assert.Equal(db.mobNameplateFontSize, 22, "Refresh must NOT overwrite the user-set fontSize")
      Assert.Equal(slider:GetValue(), 22, "Refresh must restore the slider's visible value to the DB value")
      ---@diagnostic enable: undefined-field
    end)
  end)

  test("Settings nameplate showPercent checkbox roundtrip persists user value across Refresh", function()
    local createFrameStub, createdFrames = BuildCreateFrameStub()
    local db = { mobNameplateEnabled = true, mobNameplateShowPercent = true }
    WithGlobals({
      UIParent = {},
      IsiLiveDB = db,
      CreateFrame = createFrameStub,
      Settings = {
        RegisterCanvasLayoutCategory = function(canvas, name)
          return { canvas = canvas, name = name }
        end,
        RegisterAddOnCategory = function() end,
      },
    }, function()
      local panel = Assert.NotNil(BuildPanel(db, createFrameStub), "settings panel must build")
      local check = Assert.NotNil(
        FindFrame(createdFrames, "CheckButton", "SETTINGS_NAMEPLATE_SHOW_PERCENT"),
        "showPercent checkbox must exist"
      )
      ---@diagnostic disable: undefined-field
      check:SetChecked(false)
      local onClick = Assert.NotNil(check._scripts.OnClick, "checkbox must define OnClick")
      onClick(check)
      Assert.Equal(db.mobNameplateShowPercent, false, "uncheck must persist false to DB")
      panel.Refresh()
      Assert.Equal(db.mobNameplateShowPercent, false, "Refresh must NOT overwrite false back to default")
      Assert.False(check:GetChecked(), "Refresh must keep the checkbox visually unchecked")
      ---@diagnostic enable: undefined-field
    end)
  end)

  test("Settings nameplate showRemaining checkbox roundtrip persists user value across Refresh", function()
    local createFrameStub, createdFrames = BuildCreateFrameStub()
    local db = { mobNameplateEnabled = true, mobNameplateShowRemaining = false }
    local changeCalls = 0
    WithGlobals({
      UIParent = {},
      IsiLiveDB = db,
      CreateFrame = createFrameStub,
      Settings = {
        RegisterCanvasLayoutCategory = function(canvas, name)
          return { canvas = canvas, name = name }
        end,
        RegisterAddOnCategory = function() end,
      },
    }, function()
      local panel = Assert.NotNil(
        BuildPanel(db, createFrameStub, {
          onMobNameplateChange = function()
            changeCalls = changeCalls + 1
          end,
        }),
        "settings panel must build"
      )
      local check = Assert.NotNil(
        FindFrame(createdFrames, "CheckButton", "SETTINGS_NAMEPLATE_SHOW_REMAINING"),
        "showRemaining checkbox must exist"
      )
      ---@diagnostic disable: undefined-field
      check:SetChecked(true)
      local onClick = Assert.NotNil(check._scripts.OnClick, "checkbox must define OnClick")
      onClick(check)
      Assert.Equal(db.mobNameplateShowRemaining, true, "checking must persist true to DB")
      Assert.Equal(changeCalls, 1, "checking must invoke live MobNameplate refresh")
      panel.Refresh()
      Assert.Equal(db.mobNameplateShowRemaining, true, "Refresh must NOT overwrite true back to default")
      Assert.True(check:GetChecked(), "Refresh must keep the checkbox visually checked")
      ---@diagnostic enable: undefined-field
    end)
  end)

  test("Settings nameplate position selector roundtrip persists user value across Refresh", function()
    local createFrameStub, createdFrames = BuildCreateFrameStub()
    local db = { mobNameplateEnabled = true, mobNameplatePosition = "RIGHT" }
    WithGlobals({
      UIParent = {},
      IsiLiveDB = db,
      CreateFrame = createFrameStub,
      Settings = {
        RegisterCanvasLayoutCategory = function(canvas, name)
          return { canvas = canvas, name = name }
        end,
        RegisterAddOnCategory = function() end,
      },
    }, function()
      local panel = Assert.NotNil(BuildPanel(db, createFrameStub), "settings panel must build")
      local topButton = Assert.NotNil(
        FindOptionButton(createdFrames, "SETTINGS_NAMEPLATE_POSITION", "TOP"),
        "TOP position option button must exist"
      )
      ---@diagnostic disable: undefined-field
      topButton._scripts.OnClick(topButton)
      Assert.Equal(db.mobNameplatePosition, "TOP", "selecting TOP must persist to DB")
      panel.Refresh()
      Assert.Equal(db.mobNameplatePosition, "TOP", "Refresh must NOT overwrite TOP back to RIGHT")
      ---@diagnostic enable: undefined-field
    end)
  end)

  test("Settings nameplate xOffset / yOffset sliders persist user values across Refresh", function()
    local createFrameStub, createdFrames = BuildCreateFrameStub()
    local db = { mobNameplateEnabled = true }
    WithGlobals({
      UIParent = {},
      IsiLiveDB = db,
      CreateFrame = createFrameStub,
      Settings = {
        RegisterCanvasLayoutCategory = function(canvas, name)
          return { canvas = canvas, name = name }
        end,
        RegisterAddOnCategory = function() end,
      },
    }, function()
      local panel = Assert.NotNil(BuildPanel(db, createFrameStub), "settings panel must build")
      local xSlider =
        Assert.NotNil(FindFrame(createdFrames, "Slider", "SETTINGS_NAMEPLATE_X_OFFSET"), "X offset slider must exist")
      local ySlider =
        Assert.NotNil(FindFrame(createdFrames, "Slider", "SETTINGS_NAMEPLATE_Y_OFFSET"), "Y offset slider must exist")
      ---@diagnostic disable: undefined-field
      xSlider._scripts.OnValueChanged(xSlider, 17)
      ySlider._scripts.OnValueChanged(ySlider, -8)
      Assert.Equal(db.mobNameplateXOffset, 17, "X offset slider drag must persist to DB")
      Assert.Equal(db.mobNameplateYOffset, -8, "Y offset slider drag must persist to DB")
      panel.Refresh()
      Assert.Equal(db.mobNameplateXOffset, 17, "Refresh must NOT overwrite user X offset")
      Assert.Equal(db.mobNameplateYOffset, -8, "Refresh must NOT overwrite user Y offset")
      Assert.Equal(xSlider:GetValue(), 17, "Refresh must restore X slider visible value")
      Assert.Equal(ySlider:GetValue(), -8, "Refresh must restore Y slider visible value")
      ---@diagnostic enable: undefined-field
    end)
  end)

  test("Settings nameplate displayMode survives a /reload simulation (session-1 → save → session-2)", function()
    -- Reproduces the user-visible bug "I enable nameplate percent, /reload, it's
    -- off again". Simulates two addon sessions sharing the same SavedVariables
    -- table: session 1 enables 'nameplate', then session 2 boots with that DB
    -- and must NOT revert it to the fresh-install 'off' default.
    local function SimulateSession(initialDB)
      local createFrameStub, createdFrames = BuildCreateFrameStub()
      local db = {}
      if type(initialDB) == "table" then
        for k, v in pairs(initialDB) do
          db[k] = v
        end
      end
      local panel
      WithGlobals({
        UIParent = {},
        IsiLiveDB = db,
        CreateFrame = createFrameStub,
        Settings = {
          RegisterCanvasLayoutCategory = function(canvas, name)
            return { canvas = canvas, name = name }
          end,
          RegisterAddOnCategory = function() end,
        },
      }, function()
        panel = BuildPanel(db, createFrameStub)
      end)
      return panel, createdFrames, db
    end

    -- Session 1: legacy/off install. The user enables 'nameplate', then the
    -- next session must preserve that explicit choice.
    local sessionOneDB = {
      mobNameplateEnabled = false,
      mplusForcesEstimate = false,
      mobNameplateShowPercent = true,
      mobNameplateFontSize = 14,
      mobNameplatePosition = "RIGHT",
      mobNameplateXOffset = 0,
      mobNameplateYOffset = 0,
    }

    local _, createdFrames1, db1 = SimulateSession(sessionOneDB)
    local nameplateButton =
      Assert.NotNil(FindOptionButton(createdFrames1, nil, "nameplate"), "session-1 'nameplate' button must exist")
    ---@diagnostic disable: undefined-field
    nameplateButton._scripts.OnClick(nameplateButton)
    ---@diagnostic enable: undefined-field
    Assert.Equal(db1.mobNameplateEnabled, true, "session-1 click must enable the nameplate flag in DB")

    -- Simulate "WoW saves the DB on logout" — copy db1 into a sessionTwoDB so
    -- the reference doesn't carry over.
    local sessionTwoDB = {}
    for k, v in pairs(db1) do
      sessionTwoDB[k] = v
    end

    -- Session 2: addon boots with session-1's saved values.
    local _, createdFrames2, db2 = SimulateSession(sessionTwoDB)
    Assert.Equal(
      db2.mobNameplateEnabled,
      true,
      "session-2 boot must NOT revert mobNameplateEnabled back to false — that is the user-reported regression"
    )
    -- The selector must visually reflect the saved value too. We check the
    -- 'nameplate' button's selected state via its backdrop colour applied by
    -- ApplyButtonStyle when selectedMode == optionValue.
    local nameplateButton2 =
      Assert.NotNil(FindOptionButton(createdFrames2, nil, "nameplate"), "session-2 'nameplate' button must exist")
    Assert.Equal(
      type(nameplateButton2._optionValue),
      "string",
      "session-2 'nameplate' button must carry an option value"
    )
  end)

  test("Settings nameplate displayMode selector persists 'nameplate' / 'tooltip' / 'off' choice", function()
    local createFrameStub, createdFrames = BuildCreateFrameStub()
    local db = {}
    WithGlobals({
      UIParent = {},
      IsiLiveDB = db,
      CreateFrame = createFrameStub,
      Settings = {
        RegisterCanvasLayoutCategory = function(canvas, name)
          return { canvas = canvas, name = name }
        end,
        RegisterAddOnCategory = function() end,
      },
    }, function()
      local panel = Assert.NotNil(BuildPanel(db, createFrameStub), "settings panel must build")
      local nameplateButton =
        Assert.NotNil(FindOptionButton(createdFrames, nil, "nameplate"), "'nameplate' display-mode button must exist")
      local tooltipButton =
        Assert.NotNil(FindOptionButton(createdFrames, nil, "tooltip"), "'tooltip' display-mode button must exist")
      local offButton =
        Assert.NotNil(FindOptionButton(createdFrames, nil, "off"), "'off' display-mode button must exist")

      ---@diagnostic disable: undefined-field
      nameplateButton._scripts.OnClick(nameplateButton)
      Assert.Equal(db.mobNameplateEnabled, true, "selecting 'nameplate' must enable the nameplate flag")
      Assert.Equal(db.mplusForcesEstimate, false, "selecting 'nameplate' must disable the tooltip flag")
      panel.Refresh()
      Assert.Equal(db.mobNameplateEnabled, true, "Refresh must keep the 'nameplate' selection")

      tooltipButton._scripts.OnClick(tooltipButton)
      Assert.Equal(db.mobNameplateEnabled, false, "selecting 'tooltip' must disable the nameplate flag")
      Assert.Equal(db.mplusForcesEstimate, true, "selecting 'tooltip' must enable the tooltip flag")

      offButton._scripts.OnClick(offButton)
      Assert.Equal(db.mobNameplateEnabled, false, "selecting 'off' must disable nameplate")
      Assert.Equal(db.mplusForcesEstimate, false, "selecting 'off' must disable tooltip")
      ---@diagnostic enable: undefined-field
    end)
  end)
end

return function(test, ctx)
  local Assert = RequireValue(ctx.assert, "UI settings scenario ctx.assert should exist")
  local WithGlobals = RequireValue(ctx.with_globals, "UI settings scenario ctx.with_globals should exist")
  local LoadAddonModules = RequireValue(ctx.load_modules, "UI settings scenario ctx.load_modules should exist")

  RegisterSettingsPanelTests(test, Assert, WithGlobals, LoadAddonModules)
  RegisterSettingsPanelBehaviorTests(test, Assert, WithGlobals, LoadAddonModules)
  RegisterSettingsPanelAdvancedTests(test, Assert, WithGlobals, LoadAddonModules)
  RegisterSettingsPanelSoundAndLegacyTests(test, Assert, WithGlobals, LoadAddonModules)
  RegisterSettingsPanelNameplateRoundtripTests(test, Assert, WithGlobals, LoadAddonModules)
end
