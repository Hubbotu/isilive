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
            SETTINGS_DEFAULT_OPEN_UI_M = "M",
            SETTINGS_DEFAULT_OPEN_UI_V = "V",
            SETTINGS_DEFAULT_OPEN_UI_H = "H",
            SETTINGS_DEFAULT_OPEN_UI_M2 = "M2",
            SETTINGS_MARKERS_LEADER_ONLY = "Markers Leader Only",
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

      Assert.NotNil(resetUiButton, "settings panel should create a resetui action button in the display section")
      Assert.NotNil(resetDbButton, "settings panel should create a reset all settings button")
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
      Assert.NotNil(onClickResetUi, "resetui button should define OnClick")
      Assert.NotNil(onClickResetDb, "reset all settings button should define OnClick")
      Assert.NotNil(onEnterResetDb, "reset all settings button should define OnEnter")
      Assert.NotNil(onLeaveResetDb, "reset all settings button should define OnLeave")

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

      Assert.NotNil(slider, "settings panel should create a background alpha slider")
      ---@diagnostic disable: undefined-field
      Assert.Equal(slider:GetValue(), 0.50, "slider should initialize with a 50 percent default")

      panel.Refresh()

      Assert.Nil(db.bgAlpha, "refresh should not persist the default background alpha")
      Assert.Equal(bgAlphaChanges, 0, "refresh should not fire background alpha change callbacks")

      local onValueChanged = slider._scripts and slider._scripts.OnValueChanged or nil
      Assert.NotNil(onValueChanged, "slider should define OnValueChanged")
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
            SETTINGS_SHOW_DPS_COLUMN = "Show DPS Column",
            SETTINGS_NAME_MAX_CHARS = "Name Length",
            SETTINGS_TELEPORT_COLUMNS = "Teleport Grid Columns",
            SETTINGS_MINIMAP_BUTTON = "Minimap Button",
            SETTINGS_SYNC_ENABLED = "Addon Sync",
            SETTINGS_AUTO_OPEN_QUEUE = "Auto Open Queue",
            SETTINGS_AUTO_CLOSE_MAIN_FRAME = "Auto Close Main Frame",
            SETTINGS_DEFAULT_OPEN_UI = "Default UI on Open",
            SETTINGS_DEFAULT_OPEN_UI_LAST = "Last Used",
            SETTINGS_DEFAULT_OPEN_UI_M = "M",
            SETTINGS_DEFAULT_OPEN_UI_V = "V",
            SETTINGS_DEFAULT_OPEN_UI_H = "H",
            SETTINGS_DEFAULT_OPEN_UI_M2 = "M2",
            SETTINGS_MARKERS_LEADER_ONLY = "Markers Leader Only",
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
      Assert.NotNil(m2Button, "settings panel should create an M2 default-layout button")
      Assert.NotNil(lastUsedButton, "settings panel should create a last-used default-layout button")
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
      Assert.NotNil(onClickM2, "M2 button should define OnClick")
      Assert.NotNil(onClickLast, "Last Used button should define OnClick")

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
      Assert.NotNil(m2Button, "settings panel should still expose the M2 layout option")
      ---@diagnostic disable: undefined-field
      Assert.Equal(
        m2Button._backdropColor[4],
        0.25,
        "persisted expanded defaults should be normalized onto the visible M2 option"
      )

      local onClickM2 = (m2Button._scripts and m2Button._scripts.OnClick) or nil
      Assert.NotNil(onClickM2, "M2 button should define OnClick")
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
            SETTINGS_DEFAULT_OPEN_UI_M = "M",
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

      Assert.NotNil(autoCloseCheck, "settings panel should create an auto-close checkbox")
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
            SETTINGS_DEFAULT_OPEN_UI_M = "M",
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

      Assert.NotNil(combatFadeCheck, "settings panel should create a combat fade checkbox")
      ---@diagnostic disable: undefined-field
      Assert.False(combatFadeCheck:GetChecked(), "combat fade should default to disabled when no saved value exists")

      panel.Refresh()

      Assert.Nil(db.combatFadeMM, "refresh should not persist the combat fade default")

      combatFadeCheck:SetChecked(true)
      local onClick = combatFadeCheck._scripts and combatFadeCheck._scripts.OnClick or nil
      Assert.NotNil(onClick, "combat fade checkbox should define OnClick")
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
            SETTINGS_DEFAULT_OPEN_UI_M = "M",
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

      Assert.NotNil(startupCheck, "settings panel should create a startup auto-show checkbox")
      Assert.NotNil(keyEndCheck, "settings panel should create a key-end auto-open checkbox")
      ---@diagnostic disable: undefined-field
      Assert.True(startupCheck:GetChecked(), "startup auto-show should default to enabled")
      Assert.True(keyEndCheck:GetChecked(), "key-end auto-open should default to enabled")

      local onClickStartup = startupCheck._scripts and startupCheck._scripts.OnClick or nil
      local onClickKeyEnd = keyEndCheck._scripts and keyEndCheck._scripts.OnClick or nil
      Assert.NotNil(onClickStartup, "startup checkbox should define OnClick")
      Assert.NotNil(onClickKeyEnd, "key-end checkbox should define OnClick")

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
            SETTINGS_DEFAULT_OPEN_UI_M = "M",
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

      Assert.NotNil(guideCheck, "settings panel should create a column-guides checkbox")
      ---@diagnostic disable: undefined-field
      Assert.False(guideCheck:GetChecked(), "column guides should default to disabled")

      local onClick = guideCheck._scripts and guideCheck._scripts.OnClick or nil
      Assert.NotNil(onClick, "column guides checkbox should define OnClick")

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
            SETTINGS_DEFAULT_OPEN_UI_M = "M",
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

      Assert.NotNil(navigatorCheck, "settings panel should create a portal navigator checkbox")
      ---@diagnostic disable: undefined-field
      Assert.True(navigatorCheck:GetChecked(), "portal navigator should default to enabled when no saved value exists")
      Assert.Equal(
        navigatorCheck.label:GetText(),
        "Show Timeways Navigator",
        "portal navigator label should use the English settings text"
      )

      local onClick = navigatorCheck._scripts and navigatorCheck._scripts.OnClick or nil
      Assert.NotNil(onClick, "portal navigator checkbox should define OnClick")

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
            SETTINGS_DEFAULT_OPEN_UI_M = "M",
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

      Assert.NotNil(hideButton, "settings panel should create a Raid Off raid-behavior button")
      ---@diagnostic disable: undefined-field
      Assert.Equal(hideButton._backdropColor[4], 0.25, "Raid Off should be highlighted by default")

      local onClickHide = hideButton._scripts and hideButton._scripts.OnClick or nil
      Assert.NotNil(onClickHide, "raid-behavior button should define OnClick")
      onClickHide(hideButton, "LeftButton")

      Assert.Equal(db.raidTransitionBehavior, "hide", "choosing Raid Off should persist the disabled mode")
      Assert.Equal(raidBehaviorChanges[1], "hide", "raid behavior selector should notify the callback")
      ---@diagnostic enable: undefined-field
    end)
  end)
end

local function RegisterSettingsPanelSoundAndLegacyTests(test, Assert, WithGlobals, LoadAddonModules)
  test("Settings panel exposes lead-transfer and group-join sound toggles with the intended defaults", function()
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
            SETTINGS_SOUND_GROUP_JOIN_ENABLED = "Sound: Group Join",
            SETTINGS_SOUND_PORTAL_AVAILABLE = "Sound: Portal Available",
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

      local soundSectionHeader = nil
      local leadSoundCheck = nil
      local groupJoinSoundCheck = nil
      local portalSoundCheck = nil
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
        end
      end

      Assert.NotNil(soundSectionHeader, "settings panel should create a dedicated sounds section")
      Assert.NotNil(leadSoundCheck, "settings panel should create a leader-transfer sound checkbox")
      Assert.NotNil(groupJoinSoundCheck, "settings panel should create a group-join sound checkbox")
      Assert.NotNil(portalSoundCheck, "settings panel should create a portal sound checkbox")
      ---@diagnostic disable: undefined-field
      Assert.True(leadSoundCheck:GetChecked(), "leader-transfer sound should default to enabled")
      Assert.False(groupJoinSoundCheck:GetChecked(), "group-join sound should default to disabled")
      Assert.True(portalSoundCheck:GetChecked(), "portal sound should default to enabled")

      local onClickLead = leadSoundCheck._scripts and leadSoundCheck._scripts.OnClick or nil
      local onClickJoin = groupJoinSoundCheck._scripts and groupJoinSoundCheck._scripts.OnClick or nil
      local onClickPortal = portalSoundCheck._scripts and portalSoundCheck._scripts.OnClick or nil
      Assert.NotNil(onClickLead, "leader-transfer sound checkbox should define OnClick")
      Assert.NotNil(onClickJoin, "group-join sound checkbox should define OnClick")
      Assert.NotNil(onClickPortal, "portal sound checkbox should define OnClick")

      leadSoundCheck:SetChecked(false)
      onClickLead(leadSoundCheck)
      groupJoinSoundCheck:SetChecked(true)
      onClickJoin(groupJoinSoundCheck)
      portalSoundCheck:SetChecked(false)
      onClickPortal(portalSoundCheck)

      Assert.False(db.soundLeadEnabled, "disabling leader-transfer sound should persist false")
      Assert.True(db.soundGroupJoinEnabled, "enabling group-join sound should persist true")
      Assert.False(db.soundPortalAvailableEnabled, "disabling portal sound should persist false")

      panel.Refresh()
      Assert.False(leadSoundCheck:GetChecked(), "refresh should keep the disabled leader-transfer sound state")
      Assert.True(groupJoinSoundCheck:GetChecked(), "refresh should keep the enabled group-join sound state")
      Assert.False(portalSoundCheck:GetChecked(), "refresh should keep the disabled portal sound state")
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
      SETTINGS_SOUND_GROUP_JOIN_ENABLED = "Sound: Group Join",
      SETTINGS_SOUND_PORTAL_AVAILABLE = "Sound: Portal Available",
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
      SETTINGS_SOUND_GROUP_JOIN_ENABLED = "Sound: Group Join",
      SETTINGS_SOUND_PORTAL_AVAILABLE = "Sound: Portal Available",
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
      showDpsColumn = true,
      nameMaxChars = 18,
      markersLeaderOnly = true,
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
            SETTINGS_SHOW_DPS_COLUMN = "Show DPS Column",
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
            SETTINGS_MARKERS_LEADER_ONLY = "Markers Leader Only",
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
      Assert.Equal(sliderCount, 2, "settings should only expose the background opacity and UI scale sliders")
      Assert.Equal(
        checkboxCount,
        20,
        "settings should hide only the legacy DPS, markers, name-length,"
          .. " and teleport-column controls while keeping the startup/key-end, navigator, sound,"
          .. " and combat-fade toggles visible"
      )

      panel.Refresh()
      Assert.Equal(sliderCount, 2, "refresh should keep the legacy sliders hidden")
      Assert.Equal(
        checkboxCount,
        20,
        "refresh should keep the hidden legacy checkboxes out of the settings UI"
          .. " while preserving the visible sound and combat-fade toggles"
      )
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
end
