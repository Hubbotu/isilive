---@diagnostic disable: undefined-global
local helpersChunk, helpersErr = loadfile("testmodul/isilive_test_ui_helpers.lua")
if not helpersChunk then
  error("cannot load UI helpers: " .. tostring(helpersErr))
end
local helpers = helpersChunk()
local BuildCreateFrameStub = helpers.BuildCreateFrameStub
local RequireValue = helpers.RequireValue

local function BuildPanel(db, createFrameStub, extraOpts, LoadAddonModules)
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

return function(test, ctx)
  local Assert = RequireValue(ctx.assert, "UI settings descriptions scenario ctx.assert should exist")
  local WithGlobals = RequireValue(ctx.with_globals, "UI settings descriptions scenario ctx.with_globals should exist")
  local LoadAddonModules =
    RequireValue(ctx.load_modules, "UI settings descriptions scenario ctx.load_modules should exist")

  test("Settings display checkboxes render inline descriptions and refresh localized text", function()
    local createFrameStub, createdFrames = BuildCreateFrameStub()
    local db = { showMinimapButton = true, lfgGroupBonusesEnabled = true }
    local labels = {
      SETTINGS_SECTION_GENERAL = "General",
      SETTINGS_SECTION_DISPLAY = "Display",
      SETTINGS_SECTION_BEHAVIOR = "Behavior",
      SETTINGS_SECTION_DEBUG = "Debug",
      SETTINGS_SECTION_NAMEPLATES = "Nameplates",
      SETTINGS_LANGUAGE = "Language",
      SETTINGS_MINIMAP_BUTTON = "Show minimap button",
      SETTINGS_MINIMAP_BUTTON_DESC = "Shows the isiLive minimap button.",
      SETTINGS_LFG_GROUP_BONUSES = "Group Finder: Show class bonuses",
      SETTINGS_LFG_GROUP_BONUSES_DESC = "Marks relevant class bonuses on groups and applicants.",
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
      local panel = Assert.NotNil(
        BuildPanel(db, createFrameStub, {
          getL = function()
            return labels
          end,
        }, LoadAddonModules),
        "settings panel must build"
      )
      local minimapCheck = Assert.NotNil(
        FindFrame(createdFrames, "CheckButton", "SETTINGS_MINIMAP_BUTTON"),
        "minimap checkbox must carry its setting key"
      )
      local bonusCheck = Assert.NotNil(
        FindFrame(createdFrames, "CheckButton", "SETTINGS_LFG_GROUP_BONUSES"),
        "LFG group-bonus checkbox must exist"
      )
      ---@diagnostic disable: undefined-field
      Assert.NotNil(minimapCheck.description, "minimap checkbox must render a description font string")
      Assert.NotNil(bonusCheck.description, "LFG group-bonus checkbox must render a description font string")
      Assert.Equal(minimapCheck.description._fontObject, "GameFontNormalSmall", "description must use the small font")
      Assert.Equal(
        minimapCheck.description._text,
        "Shows the isiLive minimap button.",
        "minimap description must use localized text"
      )
      Assert.Equal(
        bonusCheck.description._text,
        "Marks relevant class bonuses on groups and applicants.",
        "LFG group-bonus description must use localized text"
      )
      Assert.Equal(
        minimapCheck.description._point[2],
        minimapCheck.label,
        "description must anchor after the main label"
      )
      Assert.Equal(minimapCheck.description._wordWrap, false, "inline descriptions must stay on one row")

      labels.SETTINGS_LFG_GROUP_BONUSES_DESC = "Updated class bonus description."
      panel.Refresh()
      Assert.Equal(
        bonusCheck.description._text,
        "Updated class bonus description.",
        "Refresh must update checkbox descriptions after locale text changes"
      )
      ---@diagnostic enable: undefined-field
    end)
  end)
end
