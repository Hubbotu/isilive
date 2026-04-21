---@diagnostic disable: undefined-global
local function RequireRosterPanelHelpers()
  local chunk, loadErr = loadfile("testmodul/isilive_test_scenarios_roster_panel.lua")
  if not chunk then
    error(string.format("cannot load roster panel scenario helper: %s", tostring(loadErr)))
  end

  local helperAddon = {}
  local ok, runErr = pcall(chunk, "isiLive", helperAddon)
  if not ok then
    error(string.format("cannot execute roster panel scenario helper: %s", tostring(runErr)))
  end

  local helpers = helperAddon._RosterPanelTests or {}
  if
    type(helpers.NewRecordedFrame) ~= "function"
    or type(helpers.NewRecordedMainFrame) ~= "function"
    or type(helpers.NewRecordedFontString) ~= "function"
  then
    error("Roster panel test helpers are unavailable")
  end
  return helpers
end

-- Upvalue locals — set once from the scenario entry point before any test is called.
local NewRecordedFrame
local NewRecordedMainFrame
local test, Assert, WithGlobals, LoadAddonModules
local RegisterShareKeysRemoteCooldownTests

local function RegisterShareKeysGlobalPathTest()
  test("Roster panel share keys button uses the global SendChatMessage runtime path", function()
    local createdFrames = {}
    local createdFontStrings = {}
    local sentMessages = {}
    local shareKeyRequests = 0
    local currentTime = 300

    WithGlobals({
      CreateFrame = function()
        return NewRecordedFrame(createdFrames, createdFontStrings)
      end,
      GameTooltip = {
        SetOwner = function() end,
        SetText = function() end,
        AddLine = function() end,
        Show = function() end,
        Hide = function() end,
      },
      SendChatMessage = function(text, channel)
        table.insert(sentMessages, {
          text = text,
          channel = channel,
        })
      end,
      print = function() end,
    }, function()
      local addon = LoadAddonModules({ "isiLive_roster_panel.lua" })
      local controller = addon.RosterPanel.CreateController({
        mainFrame = NewRecordedMainFrame(createdFontStrings),
        getL = function()
          return {}
        end,
        isPlayerLeader = function()
          return true
        end,
        getAddonVersionText = function()
          return ""
        end,
        updateStatusLine = function() end,
        setMainFrameHeightSafe = function() end,
        setMainFrameWidthSafe = function() end,
        buildOrderedRoster = function(roster)
          return {
            { unit = "player", info = roster.player },
          }
        end,
        hasFullSync = function()
          return false
        end,
        buildDisplayData = function()
          return {
            colorHex = "ffffffff",
            displayName = "Self",
            languageDisplay = "EN",
            specText = "",
            ilvlText = "",
            rioText = "",
            keyText = "DB +10",
            addonMarker = "",
            atDungeonMarker = "",
            readyCheckMarkup = "",
            roleIconMarkup = "",
          }
        end,
        truncateName = function(text)
          return text
        end,
        getShortSpecLabel = function(text)
          return text
        end,
        getLanguageFlagMarkup = function()
          return ""
        end,
        getDungeonShortCode = function()
          return "DB"
        end,
        resolveActiveKeyOwnerUnit = function()
          return nil
        end,
        getRoster = function()
          return {
            player = {
              name = "Self",
              role = "DAMAGER",
              keyMapID = 2662,
              keyLevel = 10,
            },
          }
        end,
        isInGroup = function()
          return true
        end,
        rolePriority = {
          DAMAGER = 1,
          NONE = 2,
        },
        unitPriority = {
          player = 1,
        },
        getTime = function()
          return currentTime
        end,
        shareKeysDebounceSeconds = 1,
        sendShareKeysRequest = function()
          shareKeyRequests = shareKeyRequests + 1
          return true
        end,
      })

      controller.RenderRoster({
        player = {
          name = "Self",
          role = "DAMAGER",
          keyMapID = 2662,
          keyLevel = 10,
        },
      })

      local shareKeysButton = nil
      for _, frame in ipairs(createdFrames) do
        if frame.pointY == -150 then
          shareKeysButton = frame
          break
        end
      end

      Assert.NotNil(shareKeysButton, "share-keys button should exist")
      ---@diagnostic disable: undefined-field
      shareKeysButton.OnClick()
      ---@diagnostic enable: undefined-field

      Assert.Equal(#sentMessages, 1, "share-keys should use the global SendChatMessage path in runtime")
      Assert.Equal(sentMessages[1].channel, "PARTY", "share-keys global chat path should still announce to party chat")
      Assert.Equal(shareKeyRequests, 1, "share-keys global chat path should still broadcast the sync request")
    end)
  end)
end

local function RegisterShareKeysDeterministicLinkTest()
  test("Roster panel share keys button builds a deterministic keystone link", function()
    local createdFrames = {}
    local createdFontStrings = {}
    local sentMessages = {}
    local shareKeyRequests = 0
    local currentTime = 300

    WithGlobals({
      CreateFrame = function()
        return NewRecordedFrame(createdFrames, createdFontStrings)
      end,
      C_ChallengeMode = {
        GetMapUIInfo = function(mapID)
          if mapID == 2662 then
            return "Mists of Tirna Scithe"
          end
          return nil
        end,
      },
      C_MythicPlus = {
        GetOwnedKeystoneLink = function()
          return "|Hitem:19019|h[Thunderfury, Blessed Blade of the Windseeker]|h"
        end,
      },
      GameTooltip = {
        SetOwner = function() end,
        SetText = function() end,
        AddLine = function() end,
        Show = function() end,
        Hide = function() end,
      },
      C_ChatInfo = {
        SendChatMessage = function(text, channel)
          table.insert(sentMessages, {
            text = text,
            channel = channel,
          })
        end,
      },
      print = function() end,
    }, function()
      local addon = LoadAddonModules({ "isiLive_roster_panel.lua" })
      local controller = addon.RosterPanel.CreateController({
        mainFrame = NewRecordedMainFrame(createdFontStrings),
        getL = function()
          return {}
        end,
        isPlayerLeader = function()
          return true
        end,
        getAddonVersionText = function()
          return ""
        end,
        updateStatusLine = function() end,
        setMainFrameHeightSafe = function() end,
        setMainFrameWidthSafe = function() end,
        buildOrderedRoster = function(roster)
          return {
            { unit = "player", info = roster.player },
          }
        end,
        hasFullSync = function()
          return false
        end,
        buildDisplayData = function()
          return {
            colorHex = "ffffffff",
            displayName = "Self",
            languageDisplay = "EN",
            specText = "",
            ilvlText = "",
            rioText = "",
            keyText = "DB +10",
            addonMarker = "",
            atDungeonMarker = "",
            readyCheckMarkup = "",
            roleIconMarkup = "",
          }
        end,
        truncateName = function(text)
          return text
        end,
        getShortSpecLabel = function(text)
          return text
        end,
        getLanguageFlagMarkup = function()
          return ""
        end,
        getDungeonShortCode = function()
          return "DB"
        end,
        resolveActiveKeyOwnerUnit = function()
          return nil
        end,
        getRoster = function()
          return {
            player = {
              name = "Self",
              role = "DAMAGER",
              keyMapID = 2662,
              keyLevel = 10,
            },
          }
        end,
        isInGroup = function()
          return true
        end,
        rolePriority = {
          DAMAGER = 1,
          NONE = 2,
        },
        unitPriority = {
          player = 1,
        },
        getTime = function()
          return currentTime
        end,
        shareKeysDebounceSeconds = 1,
        sendShareKeysRequest = function()
          shareKeyRequests = shareKeyRequests + 1
        end,
      })

      controller.RenderRoster({
        player = {
          name = "Self",
          role = "DAMAGER",
          keyMapID = 2662,
          keyLevel = 10,
        },
      })

      local shareKeysButton = nil
      for _, frame in ipairs(createdFrames) do
        if frame.pointY == -150 then
          shareKeysButton = frame
          break
        end
      end

      Assert.NotNil(shareKeysButton, "share-keys button should exist")
      ---@diagnostic disable: undefined-field
      shareKeysButton.OnClick()
      ---@diagnostic enable: undefined-field

      Assert.Equal(#sentMessages, 1, "share-keys should emit one chat message")
      Assert.Equal(sentMessages[1].channel, "PARTY", "share-keys should still announce to party chat")
      Assert.True(
        sentMessages[1].text:find("|Hkeystone:", 1, true) == nil,
        "share-keys fallback must not construct a manual keystone hyperlink (WoW silently drops those)"
      )
      Assert.True(
        sentMessages[1].text:find("%+10", 1) ~= nil,
        "share-keys fallback must still surface the keystone level in the plain-text announcement"
      )
      Assert.True(
        sentMessages[1].text:find("|Hitem:", 1, true) == nil,
        "share-keys must not forward a foreign item hyperlink"
      )
      Assert.Equal(shareKeyRequests, 1, "share-keys should still broadcast the sync request")
    end)
  end)
end

local function RegisterShareKeysFallbackLinkTest()
  test("Roster panel share keys button keeps the fallback keystone message clickable", function()
    local createdFrames = {}
    local createdFontStrings = {}
    local sentMessages = {}
    local shareKeyRequests = 0
    local currentTime = 300

    WithGlobals({
      CreateFrame = function()
        return NewRecordedFrame(createdFrames, createdFontStrings)
      end,
      C_ChallengeMode = {
        GetMapUIInfo = function()
          return nil
        end,
      },
      GameTooltip = {
        SetOwner = function() end,
        SetText = function() end,
        AddLine = function() end,
        Show = function() end,
        Hide = function() end,
      },
      C_ChatInfo = {
        SendChatMessage = function(text, channel)
          table.insert(sentMessages, {
            text = text,
            channel = channel,
          })
        end,
      },
      print = function() end,
    }, function()
      local addon = LoadAddonModules({
        "core/isiLive_context_helpers.lua",
        "isiLive_roster_panel.lua",
      })

      addon.ContextHelpers.BuildKeystoneChatLink = function()
        return nil
      end

      local controller = addon.RosterPanel.CreateController({
        mainFrame = NewRecordedMainFrame(createdFontStrings),
        getL = function()
          return {}
        end,
        isPlayerLeader = function()
          return true
        end,
        getAddonVersionText = function()
          return ""
        end,
        updateStatusLine = function() end,
        setMainFrameHeightSafe = function() end,
        setMainFrameWidthSafe = function() end,
        buildOrderedRoster = function(roster)
          return {
            { unit = "player", info = roster.player },
          }
        end,
        hasFullSync = function()
          return false
        end,
        buildDisplayData = function()
          return {
            colorHex = "ffffffff",
            displayName = "Self",
            languageDisplay = "EN",
            specText = "",
            ilvlText = "",
            rioText = "",
            keyText = "DB +10",
            addonMarker = "",
            atDungeonMarker = "",
            readyCheckMarkup = "",
            roleIconMarkup = "",
          }
        end,
        truncateName = function(text)
          return text
        end,
        getShortSpecLabel = function(text)
          return text
        end,
        getLanguageFlagMarkup = function()
          return ""
        end,
        getDungeonShortCode = function()
          return "DB"
        end,
        resolveActiveKeyOwnerUnit = function()
          return nil
        end,
        getRoster = function()
          return {
            player = {
              name = "Self",
              role = "DAMAGER",
              keyMapID = 2662,
              keyLevel = 10,
            },
          }
        end,
        isInGroup = function()
          return true
        end,
        rolePriority = {
          DAMAGER = 1,
          NONE = 2,
        },
        unitPriority = {
          player = 1,
        },
        getTime = function()
          return currentTime
        end,
        shareKeysDebounceSeconds = 1,
        sendShareKeysRequest = function()
          shareKeyRequests = shareKeyRequests + 1
        end,
      })

      controller.RenderRoster({
        player = {
          name = "Self",
          role = "DAMAGER",
          keyMapID = 2662,
          keyLevel = 10,
        },
      })

      local shareKeysButton = nil
      for _, frame in ipairs(createdFrames) do
        if frame.pointY == -150 then
          shareKeysButton = frame
          break
        end
      end

      Assert.NotNil(shareKeysButton, "share-keys button should exist")
      ---@diagnostic disable: undefined-field
      shareKeysButton.OnClick()
      ---@diagnostic enable: undefined-field

      Assert.Equal(#sentMessages, 1, "share-keys should still emit one chat message")
      Assert.Equal(sentMessages[1].channel, "PARTY", "fallback share-keys message should still announce to party chat")
      -- Manually constructed |Hkeystone:...|h links are server-rejected in
      -- retail — SendChatMessage silently drops them. The fallback must stay
      -- plain-text so the message actually reaches the party.
      Assert.True(
        sentMessages[1].text:find("|Hkeystone:", 1, true) == nil,
        "fallback share-keys message must not contain a manually constructed keystone link"
      )
      Assert.True(
        sentMessages[1].text:find("DB +10", 1, true) ~= nil,
        "fallback share-keys message should still carry the dungeon short code label"
      )
      Assert.Equal(shareKeyRequests, 1, "fallback share-keys flow should still broadcast the sync request")
    end)
  end)
end

local function RegisterShareKeysLiveSnapshotTest()
  test("Roster panel share keys button prefers the live owned keystone snapshot over a stale roster cache", function()
    local createdFrames = {}
    local createdFontStrings = {}
    local sentMessages = {}
    local shareKeyRequests = 0
    local currentTime = 300

    WithGlobals({
      CreateFrame = function()
        return NewRecordedFrame(createdFrames, createdFontStrings)
      end,
      GameTooltip = {
        SetOwner = function() end,
        SetText = function() end,
        AddLine = function() end,
        Show = function() end,
        Hide = function() end,
      },
      C_ChatInfo = {
        SendChatMessage = function(text, channel)
          table.insert(sentMessages, {
            text = text,
            channel = channel,
          })
        end,
      },
      print = function() end,
    }, function()
      local addon = LoadAddonModules({
        "core/isiLive_context_helpers.lua",
        "isiLive_roster_panel.lua",
      })
      local controller = addon.RosterPanel.CreateController({
        mainFrame = NewRecordedMainFrame(createdFontStrings),
        getL = function()
          return {}
        end,
        isPlayerLeader = function()
          return true
        end,
        getAddonVersionText = function()
          return ""
        end,
        updateStatusLine = function() end,
        setMainFrameHeightSafe = function() end,
        setMainFrameWidthSafe = function() end,
        buildOrderedRoster = function(roster)
          return {
            { unit = "player", info = roster.player },
          }
        end,
        hasFullSync = function()
          return false
        end,
        buildDisplayData = function()
          return {
            colorHex = "ffffffff",
            displayName = "Self",
            languageDisplay = "EN",
            specText = "",
            ilvlText = "",
            rioText = "",
            keyText = "-",
            addonMarker = "",
            atDungeonMarker = "",
            readyCheckMarkup = "",
            roleIconMarkup = "",
          }
        end,
        truncateName = function(text)
          return text
        end,
        getShortSpecLabel = function(text)
          return text
        end,
        getLanguageFlagMarkup = function()
          return ""
        end,
        getDungeonShortCode = function()
          return "MOTS"
        end,
        getOwnedKeystoneSnapshot = function()
          return 2662, 10
        end,
        resolveActiveKeyOwnerUnit = function()
          return nil
        end,
        getRoster = function()
          return {
            player = {
              name = "Self",
              role = "DAMAGER",
              keyMapID = 0,
              keyLevel = 0,
            },
          }
        end,
        isInGroup = function()
          return true
        end,
        rolePriority = {
          DAMAGER = 1,
          NONE = 2,
        },
        unitPriority = {
          player = 1,
        },
        getTime = function()
          return currentTime
        end,
        shareKeysDebounceSeconds = 1,
        sendShareKeysRequest = function()
          shareKeyRequests = shareKeyRequests + 1
          return true
        end,
      })

      controller.RenderRoster({
        player = {
          name = "Self",
          role = "DAMAGER",
          keyMapID = 0,
          keyLevel = 0,
        },
      })

      local shareKeysButton = nil
      for _, frame in ipairs(createdFrames) do
        if frame.pointY == -150 then
          shareKeysButton = frame
          break
        end
      end

      Assert.NotNil(shareKeysButton, "share-keys button should exist")
      ---@cast shareKeysButton any
      Assert.True(shareKeysButton.enabled, "live owned keystone data should keep the share-keys button available")
      ---@diagnostic disable: undefined-field
      shareKeysButton.OnClick()
      ---@diagnostic enable: undefined-field

      Assert.Equal(#sentMessages, 1, "share-keys should announce the live owned keystone snapshot")
      Assert.Equal(sentMessages[1].channel, "PARTY", "live owned keystone snapshot should still announce to party chat")
      Assert.True(
        sentMessages[1].text:find("|Hkeystone:", 1, true) == nil,
        "live owned keystone snapshot must not emit a manual keystone hyperlink (WoW drops those)"
      )
      Assert.True(
        sentMessages[1].text:find("%+10", 1) ~= nil,
        "live owned keystone snapshot must still surface the keystone level in the plain-text announcement"
      )
      Assert.Equal(shareKeyRequests, 1, "share-keys should still broadcast the peer sync request")
    end)
  end)
end

local function RegisterShareKeysDebounceTests()
  test("Roster panel share keys button debounces rapid clicks", function()
    local createdFrames = {}
    local createdFontStrings = {}
    local sentMessages = {}
    local shareKeyRequests = 0
    local currentTime = 100

    WithGlobals({
      CreateFrame = function()
        return NewRecordedFrame(createdFrames, createdFontStrings)
      end,
      GameTooltip = {
        SetOwner = function() end,
        SetText = function() end,
        AddLine = function() end,
        Show = function() end,
        Hide = function() end,
      },
      C_ChatInfo = {
        SendChatMessage = function(text, channel)
          table.insert(sentMessages, {
            text = text,
            channel = channel,
          })
        end,
      },
      print = function() end,
    }, function()
      local addon = LoadAddonModules({ "isiLive_roster_panel.lua" })
      local controller = addon.RosterPanel.CreateController({
        mainFrame = NewRecordedMainFrame(createdFontStrings),
        getL = function()
          return {}
        end,
        isPlayerLeader = function()
          return true
        end,
        getAddonVersionText = function()
          return ""
        end,
        updateStatusLine = function() end,
        setMainFrameHeightSafe = function() end,
        setMainFrameWidthSafe = function() end,
        buildOrderedRoster = function(roster)
          return {
            { unit = "player", info = roster.player },
          }
        end,
        hasFullSync = function()
          return false
        end,
        buildDisplayData = function()
          return {
            colorHex = "ffffffff",
            displayName = "Self",
            languageDisplay = "EN",
            specText = "",
            ilvlText = "",
            rioText = "",
            keyText = "DB +10",
            addonMarker = "",
            atDungeonMarker = "",
            readyCheckMarkup = "",
            roleIconMarkup = "",
          }
        end,
        truncateName = function(text)
          return text
        end,
        getShortSpecLabel = function(text)
          return text
        end,
        getLanguageFlagMarkup = function()
          return ""
        end,
        getDungeonShortCode = function()
          return "DB"
        end,
        resolveActiveKeyOwnerUnit = function()
          return nil
        end,
        getRoster = function()
          return {
            player = {
              name = "Self",
              role = "DAMAGER",
              keyMapID = 2441,
              keyLevel = 10,
            },
          }
        end,
        isInGroup = function()
          return true
        end,
        rolePriority = {
          DAMAGER = 1,
          NONE = 2,
        },
        unitPriority = {
          player = 1,
        },
        getTime = function()
          return currentTime
        end,
        shareKeysDebounceSeconds = 1,
        sendShareKeysRequest = function()
          shareKeyRequests = shareKeyRequests + 1
        end,
      })

      controller.RenderRoster({
        player = {
          name = "Self",
          role = "DAMAGER",
          keyMapID = 2441,
          keyLevel = 10,
        },
      })

      local shareKeysButton = nil
      for _, frame in ipairs(createdFrames) do
        if frame.pointY == -150 then
          shareKeysButton = frame
          break
        end
      end

      Assert.NotNil(shareKeysButton, "share-keys button should exist")
      ---@diagnostic disable: undefined-field
      shareKeysButton.OnClick()
      shareKeysButton.OnClick()
      Assert.Equal(#sentMessages, 1, "rapid repeated share-keys clicks should be debounced")
      Assert.Equal(sentMessages[1].channel, "PARTY", "share-keys should announce to party chat")
      Assert.Equal(shareKeyRequests, 1, "share-keys should send one sync request on the first click")

      currentTime = 101.5
      shareKeysButton.OnClick()
      ---@diagnostic enable: undefined-field
      Assert.Equal(#sentMessages, 2, "share-keys click should fire again after debounce window")
      Assert.Equal(shareKeyRequests, 2, "share-keys should send another sync request after the debounce window")
    end)
  end)

  test("Roster panel share keys button does not treat the local print fallback as a successful party share", function()
    local createdFrames = {}
    local createdFontStrings = {}
    local printedMessages = {}
    local shareKeyRequests = 0
    local currentTime = 700

    WithGlobals({
      CreateFrame = function()
        return NewRecordedFrame(createdFrames, createdFontStrings)
      end,
      GameTooltip = {
        SetOwner = function() end,
        SetText = function() end,
        AddLine = function() end,
        Show = function() end,
        Hide = function() end,
      },
      SendChatMessage = function()
        error("party chat blocked")
      end,
      print = function(message)
        table.insert(printedMessages, tostring(message))
      end,
    }, function()
      local addon = LoadAddonModules({ "isiLive_roster_panel.lua" })
      local controller = addon.RosterPanel.CreateController({
        mainFrame = NewRecordedMainFrame(createdFontStrings),
        getL = function()
          return {}
        end,
        isPlayerLeader = function()
          return true
        end,
        getAddonVersionText = function()
          return ""
        end,
        updateStatusLine = function() end,
        setMainFrameHeightSafe = function() end,
        setMainFrameWidthSafe = function() end,
        buildOrderedRoster = function(roster)
          return {
            { unit = "player", info = roster.player },
          }
        end,
        hasFullSync = function()
          return false
        end,
        buildDisplayData = function()
          return {
            colorHex = "ffffffff",
            displayName = "Self",
            languageDisplay = "EN",
            specText = "",
            ilvlText = "",
            rioText = "",
            keyText = "DB +10",
            addonMarker = "",
            atDungeonMarker = "",
            readyCheckMarkup = "",
            roleIconMarkup = "",
          }
        end,
        truncateName = function(text)
          return text
        end,
        getShortSpecLabel = function(text)
          return text
        end,
        getLanguageFlagMarkup = function()
          return ""
        end,
        getDungeonShortCode = function()
          return "DB"
        end,
        resolveActiveKeyOwnerUnit = function()
          return nil
        end,
        getRoster = function()
          return {
            player = {
              name = "Self",
              role = "DAMAGER",
              keyMapID = 2441,
              keyLevel = 10,
            },
          }
        end,
        isInGroup = function()
          return true
        end,
        rolePriority = {
          DAMAGER = 1,
          NONE = 2,
        },
        unitPriority = {
          player = 1,
        },
        getTime = function()
          return currentTime
        end,
        shareKeysDebounceSeconds = 30,
        sendShareKeysRequest = function()
          shareKeyRequests = shareKeyRequests + 1
          return false
        end,
      })

      controller.RenderRoster({
        player = {
          name = "Self",
          role = "DAMAGER",
          keyMapID = 2441,
          keyLevel = 10,
        },
      })

      local shareKeysButton = nil
      for _, frame in ipairs(createdFrames) do
        if frame.pointY == -150 then
          shareKeysButton = frame
          break
        end
      end

      Assert.NotNil(shareKeysButton, "share-keys button should exist")
      ---@cast shareKeysButton any
      ---@diagnostic disable: undefined-field
      shareKeysButton.OnClick()
      shareKeysButton.OnClick()
      ---@diagnostic enable: undefined-field
      Assert.Equal(#printedMessages, 2, "local print fallback should still run on every failed click attempt")
      Assert.Equal(
        shareKeyRequests,
        2,
        "failed party-chat sends must not start the share-keys cooldown when the sync request also fails"
      )
      Assert.True(shareKeysButton.enabled, "failed party-chat sends must leave the share-keys button usable")
    end)
  end)
end

local function RegisterShareKeysNoOpAndRemoteTests()
  test("Roster panel share keys button ignores no-op clicks without chat or sync success", function()
    local createdFrames = {}
    local createdFontStrings = {}
    local sentMessages = {}
    local shareKeyRequests = 0
    local currentTime = 500

    WithGlobals({
      CreateFrame = function()
        return NewRecordedFrame(createdFrames, createdFontStrings)
      end,
      GameTooltip = {
        SetOwner = function() end,
        SetText = function() end,
        AddLine = function() end,
        Show = function() end,
        Hide = function() end,
      },
      C_ChatInfo = {},
      print = function() end,
    }, function()
      local addon = LoadAddonModules({ "isiLive_roster_panel.lua" })
      local controller = addon.RosterPanel.CreateController({
        mainFrame = NewRecordedMainFrame(createdFontStrings),
        getL = function()
          return {}
        end,
        isPlayerLeader = function()
          return true
        end,
        getAddonVersionText = function()
          return ""
        end,
        updateStatusLine = function() end,
        setMainFrameHeightSafe = function() end,
        setMainFrameWidthSafe = function() end,
        buildOrderedRoster = function(roster)
          return {
            { unit = "player", info = roster.player },
            { unit = "party1", info = roster.party1 },
          }
        end,
        hasFullSync = function()
          return false
        end,
        buildDisplayData = function(info)
          return {
            colorHex = "ffffffff",
            displayName = info.name,
            languageDisplay = "EN",
            specText = "",
            ilvlText = "",
            rioText = "",
            keyText = tonumber(info.keyLevel) and tonumber(info.keyLevel) > 0 and "DB +10" or "-",
            addonMarker = "",
            atDungeonMarker = "",
            readyCheckMarkup = "",
            roleIconMarkup = "",
          }
        end,
        truncateName = function(text)
          return text
        end,
        getShortSpecLabel = function(text)
          return text
        end,
        getLanguageFlagMarkup = function()
          return ""
        end,
        getDungeonShortCode = function()
          return "DB"
        end,
        resolveActiveKeyOwnerUnit = function()
          return nil
        end,
        getRoster = function()
          return {
            player = {
              name = "Self",
              role = "DAMAGER",
              keyMapID = 0,
              keyLevel = 0,
            },
            party1 = {
              name = "Mate",
              role = "DAMAGER",
              keyMapID = 2441,
              keyLevel = 10,
            },
          }
        end,
        isInGroup = function()
          return true
        end,
        rolePriority = {
          DAMAGER = 1,
          NONE = 2,
        },
        unitPriority = {
          player = 1,
          party1 = 2,
        },
        getTime = function()
          return currentTime
        end,
        shareKeysDebounceSeconds = 30,
        sendShareKeysRequest = function()
          shareKeyRequests = shareKeyRequests + 1
          return false
        end,
      })

      controller.RenderRoster({
        player = {
          name = "Self",
          role = "DAMAGER",
          keyMapID = 0,
          keyLevel = 0,
        },
        party1 = {
          name = "Mate",
          role = "DAMAGER",
          keyMapID = 2441,
          keyLevel = 10,
        },
      })

      local shareKeysButton = nil
      for _, frame in ipairs(createdFrames) do
        if frame.pointY == -150 then
          shareKeysButton = frame
          break
        end
      end

      Assert.NotNil(shareKeysButton, "share-keys button should exist")
      ---@cast shareKeysButton any
      Assert.True(shareKeysButton.enabled, "foreign group keys should still make the button clickable")
      ---@diagnostic disable: undefined-field
      shareKeysButton.OnClick()
      shareKeysButton.OnClick()
      ---@diagnostic enable: undefined-field
      Assert.Equal(#sentMessages, 0, "no-op clicks must not emit chat output")
      Assert.Equal(shareKeyRequests, 2, "failed no-op clicks must stay usable and not start the debounce lock")
      Assert.True(shareKeysButton.enabled, "no-op clicks must leave the share-keys button enabled")
    end)
  end)

  RegisterShareKeysRemoteCooldownTests()
end

RegisterShareKeysRemoteCooldownTests = function()
  test("Roster panel share keys button locks on remote SHAREKEYS signal", function()
    local createdFrames = {}
    local createdFontStrings = {}
    local shareKeyRequests = 0
    local currentTime = 200

    WithGlobals({
      CreateFrame = function()
        return NewRecordedFrame(createdFrames, createdFontStrings)
      end,
      GameTooltip = {
        SetOwner = function() end,
        SetText = function() end,
        AddLine = function() end,
        Show = function() end,
        Hide = function() end,
      },
      C_ChatInfo = { SendChatMessage = function() end },
      print = function() end,
    }, function()
      local addon = LoadAddonModules({ "isiLive_roster_panel.lua" })
      local controller = addon.RosterPanel.CreateController({
        mainFrame = NewRecordedMainFrame(createdFontStrings),
        getL = function()
          return {}
        end,
        isPlayerLeader = function()
          return true
        end,
        getAddonVersionText = function()
          return ""
        end,
        updateStatusLine = function() end,
        setMainFrameHeightSafe = function() end,
        setMainFrameWidthSafe = function() end,
        buildOrderedRoster = function(roster)
          return { { unit = "player", info = roster.player } }
        end,
        hasFullSync = function()
          return false
        end,
        buildDisplayData = function()
          return {
            colorHex = "ffffffff",
            displayName = "Self",
            languageDisplay = "EN",
            specText = "",
            ilvlText = "",
            rioText = "",
            keyText = "DB +10",
            addonMarker = "",
            atDungeonMarker = "",
            readyCheckMarkup = "",
            roleIconMarkup = "",
          }
        end,
        truncateName = function(text)
          return text
        end,
        getShortSpecLabel = function(text)
          return text
        end,
        getLanguageFlagMarkup = function()
          return ""
        end,
        getDungeonShortCode = function()
          return "DB"
        end,
        resolveActiveKeyOwnerUnit = function()
          return nil
        end,
        getRoster = function()
          return { player = { name = "Self", role = "DAMAGER", keyMapID = 2441, keyLevel = 10 } }
        end,
        isInGroup = function()
          return true
        end,
        rolePriority = { DAMAGER = 1, NONE = 2 },
        unitPriority = { player = 1 },
        getTime = function()
          return currentTime
        end,
        shareKeysDebounceSeconds = 30,
        sendShareKeysRequest = function()
          shareKeyRequests = shareKeyRequests + 1
        end,
      })

      controller.RenderRoster({
        player = { name = "Self", role = "DAMAGER", keyMapID = 2441, keyLevel = 10 },
      })

      local shareKeysButton = nil
      for _, frame in ipairs(createdFrames) do
        if frame.pointY == -150 then
          shareKeysButton = frame
          break
        end
      end

      Assert.NotNil(shareKeysButton, "share-keys button should exist")
      ---@diagnostic disable: undefined-field

      controller.TriggerShareKeysCooldown()

      shareKeysButton.OnClick()
      Assert.Equal(shareKeyRequests, 0, "local click must be blocked after remote SHAREKEYS locks the button")

      currentTime = 231
      shareKeysButton.OnClick()
      ---@diagnostic enable: undefined-field
      Assert.Equal(shareKeyRequests, 1, "local click must succeed once debounce window has passed")
    end)
  end)

  test("Roster panel share keys remote cooldown survives a normal roster rerender", function()
    local createdFrames = {}
    local createdFontStrings = {}
    local shareKeyRequests = 0
    local currentTime = 200
    local roster = {
      player = { name = "Self", role = "DAMAGER", keyMapID = 2441, keyLevel = 10 },
    }

    WithGlobals({
      CreateFrame = function()
        return NewRecordedFrame(createdFrames, createdFontStrings)
      end,
      GameTooltip = {
        SetOwner = function() end,
        SetText = function() end,
        AddLine = function() end,
        Show = function() end,
        Hide = function() end,
      },
      C_ChatInfo = { SendChatMessage = function() end },
      print = function() end,
    }, function()
      local addon = LoadAddonModules({ "isiLive_roster_panel.lua" })
      local controller = addon.RosterPanel.CreateController({
        mainFrame = NewRecordedMainFrame(createdFontStrings),
        getL = function()
          return {}
        end,
        isPlayerLeader = function()
          return true
        end,
        getAddonVersionText = function()
          return ""
        end,
        updateStatusLine = function() end,
        setMainFrameHeightSafe = function() end,
        setMainFrameWidthSafe = function() end,
        buildOrderedRoster = function(currentRoster)
          return { { unit = "player", info = currentRoster.player } }
        end,
        hasFullSync = function()
          return false
        end,
        buildDisplayData = function()
          return {
            colorHex = "ffffffff",
            displayName = "Self",
            languageDisplay = "EN",
            specText = "",
            ilvlText = "",
            rioText = "",
            keyText = "DB +10",
            addonMarker = "",
            atDungeonMarker = "",
            readyCheckMarkup = "",
            roleIconMarkup = "",
          }
        end,
        truncateName = function(text)
          return text
        end,
        getShortSpecLabel = function(text)
          return text
        end,
        getLanguageFlagMarkup = function()
          return ""
        end,
        getDungeonShortCode = function()
          return "DB"
        end,
        resolveActiveKeyOwnerUnit = function()
          return nil
        end,
        getRoster = function()
          return roster
        end,
        isInGroup = function()
          return true
        end,
        rolePriority = { DAMAGER = 1, NONE = 2 },
        unitPriority = { player = 1 },
        getTime = function()
          return currentTime
        end,
        shareKeysDebounceSeconds = 30,
        sendShareKeysRequest = function()
          shareKeyRequests = shareKeyRequests + 1
          return true
        end,
      })

      controller.RenderRoster(roster)

      local shareKeysButton = nil
      for _, frame in ipairs(createdFrames) do
        if frame.pointY == -150 then
          shareKeysButton = frame
          break
        end
      end

      Assert.NotNil(shareKeysButton, "share-keys button should exist")
      ---@diagnostic disable: undefined-field
      controller.TriggerShareKeysCooldown()
      controller.RenderRoster(roster)
      shareKeysButton.OnClick()
      ---@diagnostic enable: undefined-field

      Assert.Equal(
        shareKeyRequests,
        0,
        "normal roster rerenders must not drop the remotely triggered share-keys cooldown"
      )

      currentTime = 231
      ---@diagnostic disable: undefined-field
      shareKeysButton.OnClick()
      ---@diagnostic enable: undefined-field
      Assert.Equal(shareKeyRequests, 1, "share-keys should become usable again once the cooldown expires")
    end)
  end)
end

return function(test_arg, ctx)
  test = test_arg
  Assert = ctx.assert
  WithGlobals = ctx.with_globals
  LoadAddonModules = ctx.load_modules
  local Helpers = RequireRosterPanelHelpers()
  NewRecordedFrame = Helpers.NewRecordedFrame
  NewRecordedMainFrame = Helpers.NewRecordedMainFrame
  RegisterShareKeysGlobalPathTest()
  RegisterShareKeysDeterministicLinkTest()
  RegisterShareKeysFallbackLinkTest()
  RegisterShareKeysLiveSnapshotTest()
  RegisterShareKeysDebounceTests()
  RegisterShareKeysNoOpAndRemoteTests()
end
