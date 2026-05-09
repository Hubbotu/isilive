---@diagnostic disable: undefined-global

-- Builds the minimal WoW global stubs needed to load isiLive_lfg_detect.lua.
-- Returns a fire(event, ...) helper that invokes the captured OnEvent handler.
local function BuildLFGDetectEnv(overrides)
  overrides = overrides or {}

  local onEvent = nil
  local prints = {}

  local globals = {
    CreateFrame = function()
      return {
        RegisterEvent = function() end,
        SetScript = function(_, scriptType, fn)
          if scriptType == "OnEvent" then
            onEvent = fn
          end
        end,
      }
    end,
    C_Timer = {
      -- Suppress the 5s ticker so tests control when CheckActiveGroup runs.
      NewTicker = function() end,
    },
    DEFAULT_CHAT_FRAME = {
      AddMessage = function(_, msg)
        table.insert(prints, tostring(msg))
      end,
    },
    IsInGroup = overrides.IsInGroup or function()
      return false
    end,
    IsInRaid = overrides.IsInRaid or function()
      return false
    end,
    GetNumGroupMembers = overrides.GetNumGroupMembers or function()
      return 0
    end,
  }

  -- Merge any extra globals the caller needs.
  if overrides.globals then
    for k, v in pairs(overrides.globals) do
      globals[k] = v
    end
  end

  return globals,
    function(event, ...)
      local addon = rawget(_G, "__isilive_last_loaded_addon")
      if addon and addon.LFGDetect and type(addon.LFGDetect.HandleEvent) == "function" then
        addon.LFGDetect.HandleEvent(event, ...)
      elseif onEvent then
        onEvent(nil, event, ...)
      end
    end,
    prints
end

-- Builds a minimal C_LFGList stub for invite scenarios.
-- searchResults maps searchResultID -> info table returned by GetSearchResultInfo.
local function BuildC_LFGList(searchResults, activeEntry)
  searchResults = searchResults or {}
  return {
    GetSearchResultInfo = function(id)
      return searchResults[id]
    end,
    GetActiveEntryInfo = function()
      return activeEntry
    end,
    GetActivityFullName = function(_activityID)
      return nil
    end,
    GetActivityInfoTable = function(_activityID)
      return nil
    end,
  }
end

local RegisterLFGDetectOwnListingAndReplayTests

local function RegisterLFGDetectResolutionTests(test, ctx)
  local Assert = ctx.assert
  local LoadAddonModules = ctx.load_modules
  local WithGlobals = ctx.with_globals

  -- ---------------------------------------------------------------------------
  -- Activity-ID resolution
  -- ---------------------------------------------------------------------------

  test("LFGDetect resolves mapID from static ACTIVITY_TO_MAP on invite", function()
    local globals, fire = BuildLFGDetectEnv({
      globals = {
        C_LFGList = BuildC_LFGList({
          [1] = { activityID = 1542 }, -- 1542 -> 557 (Windrunner Spire)
        }, nil),
      },
    })

    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_detect.lua" })

      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "invited")
      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "inviteaccepted")

      Assert.Equal(addon.LFGDetect.GetDetectedMapID(), 557, "static ACTIVITY_TO_MAP must resolve 1542 -> 557")
    end)
  end)

  test("LFGDetect keeps unknown invite activity unresolved instead of guessing from dungeon name", function()
    -- activityID 9999 is not in ACTIVITY_TO_MAP; name text must not be used as a fallback.
    local globals, fire = BuildLFGDetectEnv({
      globals = {
        C_LFGList = BuildC_LFGList({
          [1] = { activityID = 9999, name = "Windrunner Spire" },
        }, nil),
      },
    })

    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_detect.lua" })
      local callbackCount = 0
      addon.LFGDetect.SetHighlightCallback(function()
        callbackCount = callbackCount + 1
      end)

      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "invited")
      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "inviteaccepted")

      Assert.Nil(addon.LFGDetect.GetDetectedMapID(), "unknown activityID must stay unresolved without name fallback")
      Assert.Equal(callbackCount, 0, "unresolved invite must not trigger a highlight update")
    end)
  end)

  test("LFGDetect keeps conflicting invite activity maps unresolved", function()
    local globals, fire = BuildLFGDetectEnv({
      globals = {
        C_LFGList = BuildC_LFGList({
          [1] = { activityIDs = { 1542, 182 }, name = "Windrunner Spire" },
        }, nil),
      },
    })

    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_detect.lua" })
      local callbackCount = 0
      addon.LFGDetect.SetHighlightCallback(function()
        callbackCount = callbackCount + 1
      end)

      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "invited")
      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "inviteaccepted")

      Assert.Nil(addon.LFGDetect.GetDetectedMapID(), "conflicting activity maps must stay unresolved")
      Assert.Equal(callbackCount, 0, "ambiguous invite must not trigger a highlight update")
    end)
  end)

  test("LFGDetect keeps partially unresolved invite activity maps unresolved", function()
    local globals, fire = BuildLFGDetectEnv({
      globals = {
        C_LFGList = BuildC_LFGList({
          [1] = { activityID = 1542, activityIDs = { 1542, 9999 }, name = "Windrunner Spire" },
        }, nil),
      },
    })

    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_detect.lua" })
      local callbackCount = 0
      addon.LFGDetect.SetHighlightCallback(function()
        callbackCount = callbackCount + 1
      end)

      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "invited")
      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "inviteaccepted")

      Assert.Nil(addon.LFGDetect.GetDetectedMapID(), "partially unresolved activity maps must stay unresolved")
      Assert.Equal(callbackCount, 0, "partially unresolved invite must not trigger a highlight update")
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Status normalization (BUG-3)
  -- ---------------------------------------------------------------------------

  test("LFGDetect normalizes uppercase Invited status", function()
    local globals, fire = BuildLFGDetectEnv({
      globals = {
        C_LFGList = BuildC_LFGList({ [1] = { activityID = 1542 } }, nil),
      },
    })

    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_detect.lua" })

      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "Invited") -- uppercase
      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "inviteaccepted")

      Assert.Equal(addon.LFGDetect.GetDetectedMapID(), 557, "uppercase Invited must be normalized and processed")
    end)
  end)

  test("LFGDetect normalizes mixed-case InviteAccepted status", function()
    local globals, fire = BuildLFGDetectEnv({
      globals = {
        C_LFGList = BuildC_LFGList({ [1] = { activityID = 1542 } }, nil),
      },
    })

    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_detect.lua" })

      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "invited")
      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "InviteAccepted") -- mixed case

      Assert.Equal(addon.LFGDetect.GetDetectedMapID(), 557, "mixed-case InviteAccepted must be normalized and accepted")
    end)
  end)

  test("LFGDetect removes pending invite on declined status", function()
    local globals, fire = BuildLFGDetectEnv({
      IsInGroup = function()
        return false
      end,
      globals = {
        C_LFGList = BuildC_LFGList({ [1] = { activityID = 1542 } }, nil),
      },
    })

    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_detect.lua" })

      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "invited")
      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "declined")
      -- inviteaccepted arrives after decline â€” pendingInvites is empty, must be no-op
      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "inviteaccepted")

      Assert.Nil(addon.LFGDetect.GetDetectedMapID(), "declined invite must not produce a detectedMapID")
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Invite callback behavior (BUG-1, ARCH-1)
  -- ---------------------------------------------------------------------------

  test("LFGDetect exact invite stays pending until inviteaccepted and then highlights without sound", function()
    -- Incoming invites must stay pending until the exact activity data is confirmed.
    local callbackSoundContexts = {}

    local globals, fire = BuildLFGDetectEnv({
      globals = {
        C_LFGList = BuildC_LFGList({ [1] = { activityID = 1542 } }, nil),
      },
    })

    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_detect.lua" })
      addon.LFGDetect.SetHighlightCallback(function(soundContext)
        table.insert(callbackSoundContexts, soundContext)
      end)

      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "invited")

      Assert.Nil(addon.LFGDetect.GetDetectedMapID(), "invite must stay pending until inviteaccepted")
      Assert.Equal(#callbackSoundContexts, 0, "pending invite must not trigger a highlight update yet")

      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "inviteaccepted")

      Assert.Equal(
        addon.LFGDetect.GetDetectedMapID(),
        557,
        "inviteaccepted must set detectedMapID from the pending invite"
      )
      Assert.Equal(#callbackSoundContexts, 1, "highlight callback must fire once on inviteaccepted")
      Assert.Equal(
        callbackSoundContexts[1],
        "invite",
        "inviteaccepted callback must use soundContext='invite' to suppress portal sound"
      )

      -- Key start must not clear the confirmed invite highlight any more.
      fire("CHALLENGE_MODE_START")

      Assert.Equal(
        addon.LFGDetect.GetDetectedMapID(),
        557,
        "CHALLENGE_MODE_START must not clear a confirmed invite highlight before dungeon entry"
      )
      Assert.Equal(#callbackSoundContexts, 1, "CHALLENGE_MODE_START must not retrigger the highlight")

      addon.LFGDetect.ClearAllState()

      Assert.Nil(addon.LFGDetect.GetDetectedMapID(), "explicit clear must still reset detectedMapID")
      Assert.Equal(#callbackSoundContexts, 2, "explicit clear must trigger a second callback")
      Assert.Equal(callbackSoundContexts[2], "queue", "explicit clear callback must pass soundContext='queue'")
    end)
  end)

  test("Highlight invite-accepted state survives transient non-group roster updates", function()
    local callbackSoundContexts = {}
    local inGroup = false
    local groupMemberCount = 5

    local globals, fire = BuildLFGDetectEnv({
      IsInGroup = function()
        return inGroup
      end,
      GetNumGroupMembers = function()
        return groupMemberCount
      end,
      globals = {
        C_LFGList = BuildC_LFGList({ [1] = { activityID = 1542 } }, nil),
      },
    })

    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_detect.lua" })
      addon.LFGDetect.SetHighlightCallback(function(soundContext)
        table.insert(callbackSoundContexts, soundContext)
      end)

      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "invited")
      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "inviteaccepted")

      Assert.Equal(addon.LFGDetect.GetDetectedMapID(), 557, "inviteaccepted must set detectedMapID")
      Assert.Equal(#callbackSoundContexts, 1, "inviteaccepted must trigger one highlight update")

      fire("GROUP_ROSTER_UPDATE")

      Assert.Equal(
        addon.LFGDetect.GetDetectedMapID(),
        557,
        "transient not-in-group roster updates must not clear a confirmed invite highlight"
      )
      Assert.Equal(
        #callbackSoundContexts,
        1,
        "transient not-in-group roster updates must not retrigger or clear the confirmed highlight"
      )

      inGroup = true
      fire("GROUP_ROSTER_UPDATE")

      Assert.Equal(addon.LFGDetect.GetDetectedMapID(), 557, "confirmed invite highlight must survive group join")
      Assert.Equal(
        #callbackSoundContexts,
        1,
        "group join settlement must not emit an extra highlight update for an unchanged invite target"
      )
    end)
  end)

  test(
    "Highlight invite-accepted state survives transient zero-member roster updates before the group settles",
    function()
      local callbackSoundContexts = {}
      local inGroup = false
      local groupMemberCount = 0

      local globals, fire = BuildLFGDetectEnv({
        IsInGroup = function()
          return inGroup
        end,
        GetNumGroupMembers = function()
          return groupMemberCount
        end,
        globals = {
          C_LFGList = BuildC_LFGList({ [1] = { activityID = 1542 } }, nil),
        },
      })

      WithGlobals(globals, function()
        local addon = LoadAddonModules({ "isiLive_lfg_detect.lua" })
        addon.LFGDetect.SetHighlightCallback(function(soundContext)
          table.insert(callbackSoundContexts, soundContext)
        end)

        fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "invited")
        fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "inviteaccepted")

        Assert.Equal(addon.LFGDetect.GetDetectedMapID(), 557, "inviteaccepted must set detectedMapID")
        Assert.Equal(#callbackSoundContexts, 1, "inviteaccepted must trigger one highlight update")

        fire("GROUP_ROSTER_UPDATE")

        Assert.Equal(
          addon.LFGDetect.GetDetectedMapID(),
          557,
          "transient zero-member roster updates must not clear a confirmed invite highlight before group settle"
        )
        Assert.Equal(
          #callbackSoundContexts,
          1,
          "transient zero-member roster updates must not retrigger or clear the confirmed highlight"
        )

        inGroup = true
        groupMemberCount = 5
        fire("GROUP_ROSTER_UPDATE")

        Assert.Equal(
          addon.LFGDetect.GetDetectedMapID(),
          557,
          "confirmed invite highlight must survive the eventual group join"
        )
        Assert.Equal(#callbackSoundContexts, 1, "settled group join must not emit an extra highlight update")
      end)
    end
  )

  test(
    "Highlight invite-accepted state survives late roster false negatives while group members are still present",
    function()
      local callbackSoundContexts = {}
      local inGroup = true
      local groupMemberCount = 5

      local globals, fire = BuildLFGDetectEnv({
        IsInGroup = function()
          return inGroup
        end,
        GetNumGroupMembers = function()
          return groupMemberCount
        end,
        globals = {
          C_LFGList = BuildC_LFGList({ [1] = { activityID = 1542 } }, nil),
        },
      })

      WithGlobals(globals, function()
        local addon = LoadAddonModules({ "isiLive_lfg_detect.lua" })
        addon.LFGDetect.SetHighlightCallback(function(soundContext)
          table.insert(callbackSoundContexts, soundContext)
        end)

        fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "invited")
        fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "inviteaccepted")

        Assert.Equal(addon.LFGDetect.GetDetectedMapID(), 557, "inviteaccepted must set detectedMapID")
        Assert.Equal(#callbackSoundContexts, 1, "inviteaccepted must trigger one highlight update")

        inGroup = false
        fire("GROUP_ROSTER_UPDATE")

        Assert.Equal(
          addon.LFGDetect.GetDetectedMapID(),
          557,
          "late roster false negatives must not clear a confirmed invite while group members are still present"
        )
        Assert.Equal(
          #callbackSoundContexts,
          1,
          "late roster false negatives must not retrigger or clear the confirmed highlight while group members remain"
        )

        groupMemberCount = 0
        fire("GROUP_ROSTER_UPDATE")

        Assert.Nil(
          addon.LFGDetect.GetDetectedMapID(),
          "actual group leave must still clear the confirmed invite highlight"
        )
        Assert.Equal(#callbackSoundContexts, 2, "actual group leave must clear the confirmed highlight exactly once")
        Assert.Equal(callbackSoundContexts[2], "queue", "group leave clear must keep sound suppression")
      end)
    end
  )

  RegisterLFGDetectOwnListingAndReplayTests(test, ctx)
end

local function RegisterLFGDetectInviteAcceptRaceTests(test, ctx)
  local Assert = ctx.assert
  local LoadAddonModules = ctx.load_modules
  local WithGlobals = ctx.with_globals

  test("Highlight invite-accepted state survives own-listing drop before GROUP_ROSTER_UPDATE settles", function()
    -- Race condition: after LFG_LIST_APPLICATION_STATUS_UPDATED=inviteaccepted the
    -- own LFG application is still briefly visible in C_LFGList.GetActiveEntryInfo
    -- (so lastQueueMapID gets set by CheckActiveGroup), and a second
    -- LFG_LIST_ACTIVE_ENTRY_UPDATE immediately drops it. In that window IsInGroup()
    -- can still return false because GROUP_ROSTER_UPDATE fires ~300ms later. The
    -- ClearDetectedState path must not clear the invite-set highlight while
    -- pendingAcceptedInviteMapID is still waiting for the roster to settle.
    local callbackSoundContexts = {}
    local inGroup = false
    local groupMemberCount = 0
    local currentActiveEntry = { activityIDs = { 1542 } }

    local globals, fire = BuildLFGDetectEnv({
      IsInGroup = function()
        return inGroup
      end,
      GetNumGroupMembers = function()
        return groupMemberCount
      end,
      globals = {
        C_LFGList = {
          GetSearchResultInfo = function(id)
            if id == 1 then
              return { activityID = 1542 }
            end
            return nil
          end,
          GetActiveEntryInfo = function()
            return currentActiveEntry
          end,
          GetActivityFullName = function()
            return nil
          end,
          GetActivityInfoTable = function()
            return nil
          end,
        },
      },
    })

    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_detect.lua" })
      addon.LFGDetect.SetHighlightCallback(function(soundContext)
        table.insert(callbackSoundContexts, soundContext)
      end)

      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "invited")
      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "inviteaccepted")

      Assert.Equal(addon.LFGDetect.GetDetectedMapID(), 557, "inviteaccepted must set detectedMapID=557")

      -- Own application still present (activityIDs=[1542]) -> lastQueueMapID=557.
      fire("LFG_LIST_ACTIVE_ENTRY_UPDATE")

      Assert.Equal(
        addon.LFGDetect.GetDetectedMapID(),
        557,
        "queue listing matching the accepted invite must keep detectedMapID=557"
      )

      -- Own application gets dropped between the two event firings and IsInGroup()
      -- still reports false because GROUP_ROSTER_UPDATE has not yet arrived.
      currentActiveEntry = nil

      fire("LFG_LIST_ACTIVE_ENTRY_UPDATE")

      Assert.Equal(
        addon.LFGDetect.GetDetectedMapID(),
        557,
        "transient own-listing drop before GROUP_ROSTER_UPDATE must not clear the invite-set highlight"
      )

      -- Roster finally settles with the accepted group present.
      inGroup = true
      groupMemberCount = 5
      fire("GROUP_ROSTER_UPDATE")

      Assert.Equal(
        addon.LFGDetect.GetDetectedMapID(),
        557,
        "GROUP_ROSTER_UPDATE with the joined group must preserve detectedMapID=557"
      )
    end)
  end)
end

RegisterLFGDetectOwnListingAndReplayTests = function(test, ctx)
  local Assert = ctx.assert
  local LoadAddonModules = ctx.load_modules
  local WithGlobals = ctx.with_globals

  test("LFGDetect replays an already resolved highlight when the callback is wired late", function()
    local callbackSoundContexts = {}

    local globals, fire = BuildLFGDetectEnv({
      globals = {
        C_LFGList = BuildC_LFGList({ [1] = { activityID = 1542 } }, nil),
      },
    })

    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_detect.lua" })

      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "invited")
      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "inviteaccepted")

      Assert.Equal(
        addon.LFGDetect.GetDetectedMapID(),
        557,
        "resolved invite must keep detectedMapID even without callback"
      )

      addon.LFGDetect.SetHighlightCallback(function(soundContext)
        table.insert(callbackSoundContexts, soundContext)
      end)

      Assert.Equal(#callbackSoundContexts, 1, "late callback wiring must replay the current highlight state once")
      Assert.Equal(
        callbackSoundContexts[1],
        "queue",
        "late replay must suppress portal sound the same way as other state-sync updates"
      )
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Own listing flow (BUG-1)
  -- ---------------------------------------------------------------------------

  test("LFGDetect own listing sets detectedMapID and calls callback with queue soundContext", function()
    local callbackSoundContexts = {}

    local globals, fire = BuildLFGDetectEnv({
      globals = {
        C_LFGList = BuildC_LFGList({}, { activityID = 1542 }),
      },
    })

    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_detect.lua" })
      addon.LFGDetect.SetHighlightCallback(function(soundContext)
        table.insert(callbackSoundContexts, soundContext)
      end)

      fire("LFG_LIST_ACTIVE_ENTRY_UPDATE")

      Assert.Equal(addon.LFGDetect.GetDetectedMapID(), 557, "own listing must set detectedMapID")
      Assert.Equal(#callbackSoundContexts, 1, "highlight callback must fire once")
      Assert.Equal(
        callbackSoundContexts[1],
        "queue",
        "own-listing callback must pass soundContext='queue' to suppress portal sound"
      )
    end)
  end)

  test("LFGDetect active listing stays unresolved when only dungeon name text is available", function()
    local globals, fire = BuildLFGDetectEnv({
      globals = {
        C_LFGList = BuildC_LFGList({}, { activityID = 9999, name = "Windrunner Spire" }),
      },
    })

    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_detect.lua" })
      local callbackCount = 0
      addon.LFGDetect.SetHighlightCallback(function()
        callbackCount = callbackCount + 1
      end)

      fire("LFG_LIST_ACTIVE_ENTRY_UPDATE")

      Assert.Nil(
        addon.LFGDetect.GetDetectedMapID(),
        "active listing must stay unresolved without exact activity mapping"
      )
      Assert.Equal(callbackCount, 0, "unresolved active listing must not trigger a highlight update")
    end)
  end)
end

local function RegisterLFGDetectQueueStateTests(test, ctx)
  local Assert = ctx.assert
  local LoadAddonModules = ctx.load_modules
  local WithGlobals = ctx.with_globals

  -- ---------------------------------------------------------------------------
  -- pendingInvites survive ticker (BUG-2)
  -- ---------------------------------------------------------------------------

  test("LFGDetect pending invites survive CheckActiveGroup when no listing exists", function()
    local globals, fire = BuildLFGDetectEnv({
      globals = {
        C_LFGList = BuildC_LFGList({ [1] = { activityID = 1542 } }, nil),
      },
    })

    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_detect.lua" })

      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "invited")
      -- Simulate ticker: LFG_LIST_ACTIVE_ENTRY_UPDATE with no listing
      fire("LFG_LIST_ACTIVE_ENTRY_UPDATE") -- GetActiveEntryInfo returns nil
      -- Now inviteaccepted arrives after the tick
      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "inviteaccepted")

      Assert.Equal(
        addon.LFGDetect.GetDetectedMapID(),
        557,
        "pendingInvites must survive CheckActiveGroup so late inviteaccepted still resolves"
      )
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Invite-set detectedMapID survives ticker (BUG-LFG-4)
  -- ---------------------------------------------------------------------------

  test("LFGDetect invite-set detectedMapID survives CheckActiveGroup when no listing exists", function()
    local globals, fire = BuildLFGDetectEnv({
      globals = {
        C_LFGList = BuildC_LFGList({ [1] = { activityID = 1542 } }, nil),
      },
    })

    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_detect.lua" })

      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "invited")
      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "inviteaccepted")
      Assert.Equal(addon.LFGDetect.GetDetectedMapID(), 557, "detectedMapID must be set after invite accept")

      -- Simulate the 5s ticker: no active listing found
      fire("LFG_LIST_ACTIVE_ENTRY_UPDATE") -- GetActiveEntryInfo returns nil

      Assert.Equal(
        addon.LFGDetect.GetDetectedMapID(),
        557,
        "invite-set detectedMapID must survive CheckActiveGroup (BUG-LFG-4 guard)"
      )
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Queue-set detectedMapID IS cleared when listing goes away
  -- ---------------------------------------------------------------------------

  test("LFGDetect queue-set detectedMapID is cleared when listing is removed", function()
    local activeEntry = { activityID = 1542 }

    local globals, fire = BuildLFGDetectEnv({
      globals = {
        C_LFGList = {
          GetSearchResultInfo = function()
            return nil
          end,
          GetActiveEntryInfo = function()
            return activeEntry
          end,
          GetActivityFullName = function()
            return nil
          end,
          GetActivityInfoTable = function()
            return nil
          end,
        },
      },
    })

    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_detect.lua" })

      fire("LFG_LIST_ACTIVE_ENTRY_UPDATE") -- listing present
      Assert.Equal(addon.LFGDetect.GetDetectedMapID(), 557, "queue listing must set detectedMapID")

      activeEntry = nil -- listing removed
      fire("LFG_LIST_ACTIVE_ENTRY_UPDATE") -- no listing

      Assert.Nil(addon.LFGDetect.GetDetectedMapID(), "queue-set detectedMapID must be cleared when listing is removed")
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- GetActiveInviteLeader: leader hint captured on inviteaccepted
  -- ---------------------------------------------------------------------------

  test("LFGDetect GetActiveInviteLeader returns leaderName after invite accepted", function()
    local globals, fire = BuildLFGDetectEnv({
      globals = {
        C_LFGList = BuildC_LFGList({
          [1] = { activityID = 1542, leaderName = "Mematiwow-Blackmoore" },
        }, nil),
      },
    })

    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_detect.lua" })

      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "invited")
      Assert.Nil(addon.LFGDetect.GetActiveInviteLeader(), "pending invite must not expose leader yet")

      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "inviteaccepted")
      Assert.Equal(
        addon.LFGDetect.GetActiveInviteLeader(),
        "Mematiwow-Blackmoore",
        "inviteaccepted must capture the LFG leaderName"
      )
    end)
  end)

  test("LFGDetect GetActiveInviteLeader is nil for queue-set detectedMapID", function()
    local globals, fire = BuildLFGDetectEnv({
      globals = {
        C_LFGList = BuildC_LFGList({}, { activityID = 1542 }),
      },
    })

    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_detect.lua" })

      fire("LFG_LIST_ACTIVE_ENTRY_UPDATE")
      Assert.Equal(addon.LFGDetect.GetDetectedMapID(), 557, "own listing must set detectedMapID")
      Assert.Nil(addon.LFGDetect.GetActiveInviteLeader(), "own queue path must not produce an invite leader hint")
    end)
  end)

  test("LFGDetect GetActiveInviteLeader clears after ClearAllState", function()
    local globals, fire = BuildLFGDetectEnv({
      globals = {
        C_LFGList = BuildC_LFGList({
          [1] = { activityID = 1542, leaderName = "Leader-Realm" },
        }, nil),
      },
    })

    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_detect.lua" })

      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "invited")
      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "inviteaccepted")
      Assert.Equal(addon.LFGDetect.GetActiveInviteLeader(), "Leader-Realm", "setup: leader captured")

      addon.LFGDetect.ClearAllState()
      Assert.Nil(addon.LFGDetect.GetActiveInviteLeader(), "ClearAllState must drop the leader hint")
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Fix 1: OnInviteDeclined must only clear active state for the accepted
  -- searchResultID. Parallel listings ("+12/+13/+14" of the same dungeon)
  -- delisting after invite-accept must not destroy activeInviteTitleLevel.
  -- ---------------------------------------------------------------------------

  test("LFGDetect OnInviteDeclined for a different searchResultID keeps active invite state", function()
    local globals, fire = BuildLFGDetectEnv({
      IsInGroup = function()
        return true
      end,
      globals = {
        C_LFGList = BuildC_LFGList({
          [1] = { activityID = 1768, name = "+13 NPX", leaderName = "Other-Realm" },
          [2] = { activityID = 1768, name = "+14 NPX push", leaderName = "Pusher-Realm" },
        }, nil),
      },
    })

    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_detect.lua" })

      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "invited")
      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 2, "invited")
      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 2, "inviteaccepted")

      Assert.Equal(addon.LFGDetect.GetActiveInviteTitleLevel(), 14, "setup: +14 listing was accepted")
      Assert.Equal(
        addon.LFGDetect.GetAcceptedInviteSearchResultID(),
        2,
        "setup: acceptedInviteSearchResultID points at the +14 listing"
      )

      -- Listing 1 ("+13 NPX") delists in parallel. Same dungeon mapID, but a
      -- different searchResultID — must not erase the +14 invite state.
      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "declined_delisted")

      Assert.Equal(
        addon.LFGDetect.GetActiveInviteTitleLevel(),
        14,
        "delisting a different parallel listing must not null out activeInviteTitleLevel"
      )
      Assert.Equal(
        addon.LFGDetect.GetActiveInviteLeader(),
        "Pusher-Realm",
        "delisting a different parallel listing must not null out activeInviteLeader"
      )
      Assert.Equal(
        addon.LFGDetect.GetDetectedMapID(),
        559,
        "delisting a different parallel listing must not null out detectedMapID"
      )
    end)
  end)

  test("LFGDetect OnInvited passes the searchResultID through to the invite-hint callback", function()
    local globals, fire = BuildLFGDetectEnv({
      globals = {
        C_LFGList = BuildC_LFGList({
          [42] = { activityID = 1768, name = "+14 NPX", leaderName = "Pusher-Realm" },
        }, nil),
      },
    })

    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_detect.lua" })
      local capturedResultID = nil
      addon.LFGDetect.SetInviteHintCallback(function(_message, _duration, searchResultID)
        capturedResultID = searchResultID
      end)
      addon.LFGDetect.SetInviteHintEnabledFn(function()
        return true
      end)
      addon.LFGDetect.SetInviteHintLocaleFn(function()
        return { INVITE_HINT_GROUP = "Group: %s", INVITE_HINT_UNKNOWN_DUNGEON = "Unknown" }
      end)

      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 42, "invited")
      Assert.Equal(
        capturedResultID,
        42,
        "Fix 3a: MaybeShowInviteHint must forward the originating searchResultID to the hint callback"
      )
    end)
  end)
end

local function RegisterLFGDetectResetTests(test, ctx)
  local Assert = ctx.assert
  local LoadAddonModules = ctx.load_modules
  local WithGlobals = ctx.with_globals

  -- ---------------------------------------------------------------------------
  -- ClearAllState paths
  -- ---------------------------------------------------------------------------

  test("LFGDetect GROUP_ROSTER_UPDATE not in group clears all state including pendingInvites", function()
    local callbackCount = 0

    local globals, fire = BuildLFGDetectEnv({
      IsInGroup = function()
        return false
      end,
      globals = {
        C_LFGList = BuildC_LFGList({ [1] = { activityID = 1542 } }, nil),
      },
    })

    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_detect.lua" })
      addon.LFGDetect.SetHighlightCallback(function()
        callbackCount = callbackCount + 1
      end)

      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "invited")
      -- Leave group before accepting
      fire("GROUP_ROSTER_UPDATE") -- IsInGroup() returns false

      -- pendingInvites must be gone: late inviteaccepted must not set detectedMapID
      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "inviteaccepted")

      Assert.Nil(
        addon.LFGDetect.GetDetectedMapID(),
        "group leave must clear all state; late inviteaccepted must not resurrect detectedMapID"
      )
    end)
  end)

  test("LFGDetect CHALLENGE_MODE_START keeps confirmed invite highlight until explicit clear", function()
    local globals, fire = BuildLFGDetectEnv({
      globals = {
        C_LFGList = BuildC_LFGList({ [1] = { activityID = 1542 } }, nil),
      },
    })

    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_detect.lua" })

      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "invited")
      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "inviteaccepted")
      Assert.Equal(addon.LFGDetect.GetDetectedMapID(), 557, "setup: detectedMapID must be set before key start")

      fire("CHALLENGE_MODE_START")

      Assert.Equal(
        addon.LFGDetect.GetDetectedMapID(),
        557,
        "CHALLENGE_MODE_START must not clear the confirmed invite highlight"
      )

      addon.LFGDetect.ClearAllState()

      Assert.Nil(addon.LFGDetect.GetDetectedMapID(), "explicit clear must still reset the confirmed invite highlight")
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- GROUP_ROSTER_UPDATE fallback path
  -- ---------------------------------------------------------------------------

  test("LFGDetect GROUP_ROSTER_UPDATE applies pendingInvites when detectedMapID is unset", function()
    -- Race: GROUP_ROSTER_UPDATE fires before inviteaccepted. The handler must apply
    -- pendingInvites immediately so detectedMapID is set without waiting for the event.
    local globals, fire = BuildLFGDetectEnv({
      IsInGroup = function()
        return true
      end,
      globals = {
        C_LFGList = BuildC_LFGList({ [1] = { activityID = 1542 } }, nil),
      },
    })

    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_detect.lua" })

      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "invited")
      -- GROUP_ROSTER_UPDATE fires before inviteaccepted (race condition path)
      fire("GROUP_ROSTER_UPDATE")

      Assert.Equal(
        addon.LFGDetect.GetDetectedMapID(),
        557,
        "GROUP_ROSTER_UPDATE fallback must apply pendingInvites when detectedMapID is unset"
      )
    end)
  end)

  test("LFGDetect GROUP_ROSTER_UPDATE preserves pending invite title level", function()
    local globals, fire = BuildLFGDetectEnv({
      IsInGroup = function()
        return true
      end,
      globals = {
        C_LFGList = BuildC_LFGList({
          [1] = { activityID = 1542, name = "+13 vault", leaderName = "Leader-Realm" },
        }, nil),
      },
    })

    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_detect.lua" })

      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "invited")
      fire("GROUP_ROSTER_UPDATE")

      Assert.Equal(
        addon.LFGDetect.GetDetectedMapID(),
        557,
        "GROUP_ROSTER_UPDATE fallback must apply pending invite map"
      )
      Assert.Equal(
        addon.LFGDetect.GetActiveInviteTitleLevel(),
        13,
        "GROUP_ROSTER_UPDATE fallback must preserve the LFG title level"
      )
      Assert.Equal(
        addon.LFGDetect.GetActiveInviteLeader(),
        "Leader-Realm",
        "GROUP_ROSTER_UPDATE fallback must preserve the LFG leader hint"
      )
    end)
  end)

  test("LFGDetect inviteaccepted preserves title level when own listing already set the same map", function()
    local currentActiveEntry = { activityID = 1542 }
    local globals, fire = BuildLFGDetectEnv({
      IsInGroup = function()
        return false
      end,
      globals = {
        C_LFGList = {
          GetSearchResultInfo = function(id)
            if id == 1 then
              return { activityID = 1542, name = "+13 vault", leaderName = "Leader-Realm" }
            end
            return nil
          end,
          GetActiveEntryInfo = function()
            return currentActiveEntry
          end,
          GetActivityInfoTable = function()
            return nil
          end,
        },
      },
    })

    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_detect.lua" })
      local callbackCount = 0
      local lastSoundContext = nil
      addon.LFGDetect.SetHighlightCallback(function(soundContext)
        callbackCount = callbackCount + 1
        lastSoundContext = soundContext
      end)

      fire("LFG_LIST_ACTIVE_ENTRY_UPDATE")
      Assert.Equal(addon.LFGDetect.GetDetectedMapID(), 557, "own listing must set detectedMapID first")

      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "invited")
      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "inviteaccepted")

      Assert.Equal(addon.LFGDetect.GetDetectedMapID(), 557, "same-map invite must keep the detected map")
      Assert.Equal(callbackCount, 2, "same-map inviteaccepted must refresh consumers after capturing invite metadata")
      Assert.Equal(lastSoundContext, "invite", "same-map inviteaccepted refresh must use invite sound context")
      Assert.Equal(
        addon.LFGDetect.GetActiveInviteTitleLevel(),
        13,
        "same-map inviteaccepted must still capture the LFG title level"
      )
      Assert.Equal(
        addon.LFGDetect.GetActiveInviteLeader(),
        "Leader-Realm",
        "same-map inviteaccepted must still capture the LFG leader hint"
      )

      currentActiveEntry = nil
      fire("LFG_LIST_ACTIVE_ENTRY_UPDATE")

      Assert.Equal(
        addon.LFGDetect.GetDetectedMapID(),
        557,
        "same-map inviteaccepted must protect the target when the listing drops before group settle"
      )
      Assert.Equal(
        addon.LFGDetect.GetActiveInviteTitleLevel(),
        13,
        "same-map inviteaccepted must keep the title level across the pre-settle listing drop"
      )
      Assert.Equal(
        addon.LFGDetect.GetActiveInviteLeader(),
        "Leader-Realm",
        "same-map inviteaccepted must keep the leader hint across the pre-settle listing drop"
      )
    end)
  end)

  test("LFGDetect inviteaccepted resolves search result when invited event was missed", function()
    local globals, fire = BuildLFGDetectEnv({
      globals = {
        C_LFGList = BuildC_LFGList({
          [1] = { activityID = 1768, name = "Nexuspunkt Xenas +10", leaderName = "Leader-Realm" },
        }, nil),
      },
    })

    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_detect.lua" })

      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "inviteaccepted")

      Assert.Equal(
        addon.LFGDetect.GetDetectedMapID(),
        559,
        "inviteaccepted must resolve mapID directly from search result"
      )
      Assert.Equal(
        addon.LFGDetect.GetActiveInviteTitleLevel(),
        10,
        "inviteaccepted must parse the key level directly from the LFG title"
      )
      Assert.Equal(
        addon.LFGDetect.GetActiveInviteLeader(),
        "Leader-Realm",
        "inviteaccepted must capture the LFG leader directly from the search result"
      )
    end)
  end)

  test("LFGDetect CheckActiveGroup keeps detectedMapID while grouped even when no active listing exists", function()
    local globals, fire = BuildLFGDetectEnv({
      IsInGroup = function()
        return true
      end,
      GetNumGroupMembers = function()
        return 5
      end,
      globals = {
        C_LFGList = BuildC_LFGList({ [1] = { activityID = 1542 } }, nil),
      },
    })

    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_detect.lua" })

      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "invited")
      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "inviteaccepted")
      Assert.Equal(addon.LFGDetect.GetDetectedMapID(), 557, "setup: detectedMapID must be set before settle")

      fire("LFG_LIST_ACTIVE_ENTRY_UPDATE")

      Assert.Equal(
        addon.LFGDetect.GetDetectedMapID(),
        557,
        "grouped no-listing checks must keep detectedMapID until dungeon entry or group leave"
      )
    end)
  end)

  test("LFGDetect GROUP_ROSTER_UPDATE emits diagnostic snapshot for group-settle highlight debugging", function()
    local snapshots = {}

    local globals, fire = BuildLFGDetectEnv({
      IsInGroup = function()
        return true
      end,
      GetNumGroupMembers = function()
        return 5
      end,
      globals = {
        C_LFGList = BuildC_LFGList({ [1] = { activityID = 1542 } }, nil),
      },
    })

    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_detect.lua" })
      addon.LFGDetect.SetGroupRosterTraceLogger(function(snapshot)
        table.insert(snapshots, snapshot)
      end)

      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "invited")
      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "inviteaccepted")
      fire("GROUP_ROSTER_UPDATE")

      Assert.Equal(#snapshots, 1, "group roster update must emit one diagnostic snapshot")
      Assert.Equal(snapshots[1].event, "GROUP_ROSTER_UPDATE", "diagnostic snapshot must record the source event")
      Assert.Equal(snapshots[1].members, 5, "diagnostic snapshot must record the settled group size")
      Assert.Equal(snapshots[1].detectedBefore, 557, "diagnostic snapshot must capture detectedMapID before settle")
      Assert.Equal(snapshots[1].detectedAfter, 557, "diagnostic snapshot must keep detectedMapID after settle")
      Assert.Nil(snapshots[1].pendingAccept, "diagnostic snapshot must reflect the cleared pending accept")
    end)
  end)

  test("LFGDetect runtime trace logger passes a lazy builder to runtime logging", function()
    local capturedBuilder = nil

    local globals, fire = BuildLFGDetectEnv({
      globals = {
        C_LFGList = BuildC_LFGList({}, { activityID = 1542 }),
      },
    })

    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_detect.lua" })
      addon.LFGDetect.SetTraceLogger(function(builder)
        capturedBuilder = capturedBuilder or builder
      end)

      fire("LFG_LIST_ACTIVE_ENTRY_UPDATE")

      capturedBuilder = Assert.NotNil(capturedBuilder, "LFG trace logger must receive a lazy message builder")
      Assert.Equal(type(capturedBuilder), "function", "LFG trace logger must receive a lazy message builder")
      Assert.True(
        (capturedBuilder() or ""):find("%[LFG%] queue_listing_detected mapID=557 lastQueueMapID=nil") ~= nil,
        "LFG trace builder must format on demand"
      )
    end)
  end)
end

local function RegisterLFGDetectInviteHintTests(test, ctx)
  local Assert = ctx.assert
  local LoadAddonModules = ctx.load_modules
  local WithGlobals = ctx.with_globals

  local function BuildLocale()
    return {
      INVITE_HINT_GROUP = "Group: %s",
      INVITE_HINT_DUNGEON = "Dungeon: %s",
      INVITE_HINT_UNKNOWN_DUNGEON = "Unknown dungeon",
    }
  end

  test("LFGDetect.OnInvited surfaces a two-line invite hint with mapName + group title", function()
    local globals, fire = BuildLFGDetectEnv({
      globals = {
        C_LFGList = BuildC_LFGList({
          [1] = { activityID = 1542, name = "+12 NW Push, no jail", leaderName = "Tankadin-Realm" },
        }, nil),
      },
    })

    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_detect.lua" })
      local hints = {}
      addon.LFGDetect.SetInviteHintCallback(function(message, durationSeconds)
        hints[#hints + 1] = { message = message, duration = durationSeconds }
      end)
      addon.LFGDetect.SetInviteHintEnabledFn(function()
        return true
      end)
      addon.LFGDetect.SetTeleportLookupByMapID(function(mapID)
        if mapID == 557 then
          return { mapName = "Windrunner Spire" }
        end
        return nil
      end)
      addon.LFGDetect.SetInviteHintLocaleFn(BuildLocale)

      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "invited")

      Assert.Equal(#hints, 1, "OnInvited must trigger one InviteHint render")
      Assert.NotNil(hints[1], "InviteHint payload must be captured")
      Assert.Equal(hints[1].duration, 8, "InviteHint must request the 8s auto-hide window")
      local message = hints[1].message
      Assert.True(message:find("Windrunner Spire", 1, true) ~= nil, "InviteHint must mention the resolved dungeon name")
      Assert.True(message:find("+12", 1, true) ~= nil, "InviteHint must surface the parsed key level")
      Assert.True(
        message:find("+12 NW Push, no jail", 1, true) ~= nil,
        "InviteHint must surface the raw group title (lobby conventions)"
      )
      Assert.True(message:find("\n", 1, true) ~= nil, "InviteHint must be two-line")
    end)
  end)

  test("LFGDetect.OnInvited respects the inviteHintEnabled setting", function()
    local globals, fire = BuildLFGDetectEnv({
      globals = {
        C_LFGList = BuildC_LFGList({
          [1] = { activityID = 1542, name = "+10 spire" },
        }, nil),
      },
    })

    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_detect.lua" })
      local hints = {}
      addon.LFGDetect.SetInviteHintCallback(function(message)
        hints[#hints + 1] = message
      end)
      addon.LFGDetect.SetInviteHintEnabledFn(function()
        return false
      end)
      addon.LFGDetect.SetInviteHintLocaleFn(BuildLocale)

      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "invited")
      Assert.Equal(#hints, 0, "InviteHint must stay silent when SETTINGS_INVITE_HINT_ENABLED is off")
    end)
  end)

  test("LFGDetect.OnInvited falls back to UNKNOWN_DUNGEON when teleport lookup misses", function()
    local globals, fire = BuildLFGDetectEnv({
      globals = {
        C_LFGList = BuildC_LFGList({
          [1] = { activityID = 1542, name = "+9 group" },
        }, nil),
      },
    })

    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_detect.lua" })
      local hints = {}
      addon.LFGDetect.SetInviteHintCallback(function(message)
        hints[#hints + 1] = message
      end)
      addon.LFGDetect.SetInviteHintEnabledFn(function()
        return true
      end)
      addon.LFGDetect.SetTeleportLookupByMapID(function()
        return nil
      end)
      addon.LFGDetect.SetInviteHintLocaleFn(BuildLocale)

      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "invited")
      Assert.Equal(#hints, 1, "InviteHint must still render when the teleport lookup returns nil")
      Assert.True(
        hints[1]:find("Unknown dungeon", 1, true) ~= nil,
        "InviteHint headline must use the localized fallback when mapName is unresolved"
      )
    end)
  end)

  test("LFGDetect.OnInvited stays silent when the invite hint callback is not wired", function()
    local globals, fire = BuildLFGDetectEnv({
      globals = {
        C_LFGList = BuildC_LFGList({
          [1] = { activityID = 1542, name = "+5" },
        }, nil),
      },
    })

    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_detect.lua" })
      -- No SetInviteHintCallback call: factory wiring not done yet.
      addon.LFGDetect.SetInviteHintEnabledFn(function()
        return true
      end)
      addon.LFGDetect.SetInviteHintLocaleFn(BuildLocale)

      -- Must not crash. Replay the full invited -> inviteaccepted flow so the
      -- OnInvited path runs and the post-accept stage confirms pendingInvites
      -- got populated (mapID then surfaces via GetDetectedMapID).
      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "invited")
      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "inviteaccepted")
      Assert.Equal(
        addon.LFGDetect.GetDetectedMapID(),
        557,
        "missing hint-callback wiring must not break the existing pending-invite resolution chain"
      )
    end)
  end)
end

-- Branch coverage for ParseTitleKeyLevel pattern-B ("N+" trailing-plus form),
-- the Log/LogDeep helpers when a logger is wired, MapIDFromActivityIDs cache
-- population, and ResolveInviteEntry early returns.
local function RegisterLFGDetectBranchCoverageTests(test, ctx)
  local Assert = ctx.assert
  local LoadAddonModules = ctx.load_modules
  local WithGlobals = ctx.with_globals

  test("LFGDetect ParseTitleKeyLevel resolves 'N+' trailing-plus form via OnInvited title", function()
    -- activityID 1542 → mapID 557 (Windrunner Spire) is statically mapped, so
    -- the invite resolves and the title level is promoted on inviteaccepted.
    local globals, fire = BuildLFGDetectEnv({
      IsInGroup = function()
        return true
      end,
      globals = {
        C_LFGList = BuildC_LFGList({
          [42] = {
            -- Pattern A "+N" intentionally absent; only trailing-plus form.
            activityID = 1542,
            name = "12+ NPX gogo",
            leaderName = "Pusher-Realm",
          },
        }, nil),
      },
    })
    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_detect.lua" })
      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 42, "invited")
      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 42, "inviteaccepted")
      Assert.Equal(addon.LFGDetect.GetActiveInviteTitleLevel(), 12, "pattern B '12+' must resolve to 12")
    end)
  end)

  test("LFGDetect ParseTitleKeyLevel rejects out-of-range numbers (>40)", function()
    local globals, fire = BuildLFGDetectEnv({
      IsInGroup = function()
        return true
      end,
      globals = {
        C_LFGList = BuildC_LFGList({
          [43] = { activityID = 1542, name = "+99 farm", leaderName = "X" },
        }, nil),
      },
    })
    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_detect.lua" })
      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 43, "invited")
      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 43, "inviteaccepted")
      Assert.Nil(addon.LFGDetect.GetActiveInviteTitleLevel(), "+99 must be rejected as out of [1,40]")
    end)
  end)

  test("LFGDetect ParseTitleKeyLevel picks the highest level when multiple +N tags appear", function()
    local globals, fire = BuildLFGDetectEnv({
      IsInGroup = function()
        return true
      end,
      globals = {
        C_LFGList = BuildC_LFGList({
          [44] = { activityID = 1542, name = "+10/+12/+14 NPX", leaderName = "Push" },
        }, nil),
      },
    })
    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_detect.lua" })
      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 44, "invited")
      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 44, "inviteaccepted")
      Assert.Equal(addon.LFGDetect.GetActiveInviteTitleLevel(), 14, "must select the highest +N tag")
    end)
  end)

  test("LFGDetect Log helpers route through wired logger and trace-logger callbacks", function()
    local logCalls = {}
    local traceCalls = {}
    local deepTraceCalls = {}
    local globals, fire = BuildLFGDetectEnv({
      IsInGroup = function()
        return false
      end,
    })
    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_detect.lua" })
      addon.LFGDetect.SetLogger(function(msg)
        table.insert(logCalls, msg)
      end)
      addon.LFGDetect.SetTraceLogger(function(msg)
        table.insert(traceCalls, msg)
      end)
      addon.LFGDetect.SetDeepTraceLogger(function(msg)
        table.insert(deepTraceCalls, msg)
      end)

      -- Drive any event that flows through Log; GROUP_ROSTER_UPDATE always fires.
      fire("GROUP_ROSTER_UPDATE")
    end)
    Assert.True(#logCalls + #traceCalls + #deepTraceCalls > 0, "at least one logger callback must receive a line")
  end)

  test("LFGDetect MapIDFromActivityIDs caches the resolved mapID for repeat lookups", function()
    local activityCalls = 0
    local globals, fire = BuildLFGDetectEnv({
      IsInGroup = function()
        return true
      end,
      globals = {
        C_LFGList = {
          GetSearchResultInfo = function(id)
            if id == 50 then
              return {
                activityID = nil, -- not directly resolvable
                activityIDs = { 9001 },
                name = "+15 SH",
                leaderName = "Lead",
              }
            end
            return nil
          end,
          GetActiveEntryInfo = function()
            return nil
          end,
          GetActivityFullName = function()
            return nil
          end,
          GetActivityInfoTable = function(activityID)
            activityCalls = activityCalls + 1
            if activityID == 9001 then
              return { mapID = 2773 }
            end
            return nil
          end,
        },
      },
    })
    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_detect.lua" })
      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 50, "invited")
      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 50, "inviteaccepted")
      Assert.Equal(addon.LFGDetect.GetDetectedMapID(), 2773, "first lookup must populate cache and resolve")
      local callsAfterFirst = activityCalls
      -- Trigger a second resolve-path entry: clear and re-invite.
      addon.LFGDetect.ClearAllState()
      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 50, "invited")
      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 50, "inviteaccepted")
      Assert.Equal(addon.LFGDetect.GetDetectedMapID(), 2773, "cached lookup must still resolve")
      Assert.Equal(activityCalls, callsAfterFirst, "GetActivityInfoTable must NOT be called again (cache hit)")
    end)
  end)

  test("LFGDetect ResolveInviteEntry returns nil when C_LFGList global is absent", function()
    local globals, fire = BuildLFGDetectEnv({
      IsInGroup = function()
        return true
      end,
      globals = { C_LFGList = false }, -- explicit nil-out
    })
    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_detect.lua" })
      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 99, "invited")
      Assert.Nil(addon.LFGDetect.GetDetectedMapID(), "no C_LFGList → invite cannot resolve")
    end)
  end)
end

-- Tests for the post-accept Center Notice trigger. The notice is rendered
-- exclusively from the pendingInvites entry of the accepted searchResultID:
-- sibling listings (other searchResultIDs) must not influence the payload,
-- and missing data (no "+N" in title) must surface as nil rather than be
-- inferred from roster/sync state.
local function RegisterLFGDetectAcceptedInviteNoticeTests(test, ctx)
  local Assert = ctx.assert
  local LoadAddonModules = ctx.load_modules
  local WithGlobals = ctx.with_globals

  -- Test A: multiple pendingInvites for the SAME dungeon at different levels.
  -- Accepting the higher-level listing must not let the lower-level sibling
  -- bleed into the notice payload.
  test("AcceptedInviteNotice picks the level of the accepted listing among same-dungeon parallel invites", function()
    local globals, fire = BuildLFGDetectEnv({
      globals = {
        C_LFGList = BuildC_LFGList({
          [101] = { activityID = 1542, name = "+12 spire chill", leaderName = "Tank-A" },
          [102] = { activityID = 1542, name = "+15 spire push", leaderName = "Tank-B" },
        }, nil),
      },
    })

    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_detect.lua" })
      local payloads = {}
      addon.LFGDetect.SetAcceptedInviteNoticeCallback(function(payload)
        payloads[#payloads + 1] = payload
      end)
      addon.LFGDetect.SetAcceptedInviteNoticeEnabledFn(function()
        return true
      end)

      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 101, "invited")
      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 102, "invited")
      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 102, "inviteaccepted")

      Assert.Equal(#payloads, 1, "AcceptedInviteNotice must fire exactly once on inviteaccepted")
      Assert.Equal(payloads[1].level, 15, "level must be the +15 of the accepted listing, not the +12 sibling")
      Assert.Equal(payloads[1].mapID, 557, "mapID must resolve from accepted listing")
      Assert.Equal(payloads[1].activityID, 1542, "activityID must propagate for teleport-button wiring")
      Assert.Equal(payloads[1].searchResultID, 102, "searchResultID must be the accepted one")
      Assert.Equal(payloads[1].leaderName, "Tank-B", "leaderName must be from accepted listing")
    end)
  end)

  -- Test B: parallel invites for DIFFERENT dungeons. Accepting one must
  -- surface its mapID and level; the unaccepted sibling must not contribute.
  test(
    "AcceptedInviteNotice surfaces the dungeon of the accepted listing among different-dungeon parallel invites",
    function()
      local globals, fire = BuildLFGDetectEnv({
        globals = {
          C_LFGList = BuildC_LFGList({
            [201] = { activityID = 1542, name = "+13 spire", leaderName = "S" }, -- mapID 557
            [202] = { activityID = 182, name = "+10 sky", leaderName = "K" }, -- mapID 161
          }, nil),
        },
      })

      WithGlobals(globals, function()
        local addon = LoadAddonModules({ "isiLive_lfg_detect.lua" })
        local payloads = {}
        addon.LFGDetect.SetAcceptedInviteNoticeCallback(function(payload)
          payloads[#payloads + 1] = payload
        end)
        addon.LFGDetect.SetAcceptedInviteNoticeEnabledFn(function()
          return true
        end)

        fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 201, "invited")
        fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 202, "invited")
        fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 202, "inviteaccepted")

        Assert.Equal(#payloads, 1, "exactly one notice on accept")
        Assert.Equal(payloads[1].mapID, 161, "mapID must be from the Skyreach listing the player accepted")
        Assert.Equal(payloads[1].level, 10, "level must be Skyreach's +10, not Spire's +13")
        Assert.Equal(payloads[1].activityID, 182, "activityID must be Skyreach's, for the teleport button")
      end)
    end
  )

  -- Test C: a sibling listing is delisted/declined AFTER the accept fires.
  -- The notice must not re-fire and must not have its content mutated.
  test("AcceptedInviteNotice ignores sibling-listing declines after the accept fired", function()
    local globals, fire = BuildLFGDetectEnv({
      globals = {
        C_LFGList = BuildC_LFGList({
          [301] = { activityID = 1542, name = "+12 spire", leaderName = "A" },
          [302] = { activityID = 1542, name = "+14 spire", leaderName = "B" },
        }, nil),
      },
    })

    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_detect.lua" })
      local payloads = {}
      addon.LFGDetect.SetAcceptedInviteNoticeCallback(function(payload)
        payloads[#payloads + 1] = payload
      end)
      addon.LFGDetect.SetAcceptedInviteNoticeEnabledFn(function()
        return true
      end)

      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 301, "invited")
      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 302, "invited")
      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 302, "inviteaccepted")
      -- Sibling listing 301 gets delisted after our accept landed.
      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 301, "declined_delisted")

      Assert.Equal(#payloads, 1, "decline of a sibling listing must not re-trigger the notice")
      Assert.Equal(payloads[1].level, 14, "accepted listing's level must remain unchanged after sibling decline")
    end)
  end)

  -- Test D: group title without "+N" suffix. The notice must surface
  -- level=nil rather than guess from defaults or sibling data.
  test("AcceptedInviteNotice surfaces level=nil when the group title has no '+N' marker", function()
    local globals, fire = BuildLFGDetectEnv({
      globals = {
        C_LFGList = BuildC_LFGList({
          [401] = { activityID = 1542, name = "chill spire run", leaderName = "Z" },
        }, nil),
      },
    })

    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_detect.lua" })
      local payloads = {}
      addon.LFGDetect.SetAcceptedInviteNoticeCallback(function(payload)
        payloads[#payloads + 1] = payload
      end)
      addon.LFGDetect.SetAcceptedInviteNoticeEnabledFn(function()
        return true
      end)

      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 401, "invited")
      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 401, "inviteaccepted")

      Assert.Equal(#payloads, 1, "notice must still fire even without a level")
      Assert.Nil(payloads[1].level, "level must stay nil rather than be inferred")
      Assert.Equal(payloads[1].mapID, 557, "mapID must still resolve")
      Assert.Equal(payloads[1].groupName, "chill spire run", "raw group title must propagate for the subline")
    end)
  end)

  -- Test E: when the toggle is off, the callback must not be invoked.
  test("AcceptedInviteNotice stays silent when the enabled-fn returns false", function()
    local globals, fire = BuildLFGDetectEnv({
      globals = {
        C_LFGList = BuildC_LFGList({
          [501] = { activityID = 1542, name = "+11 spire", leaderName = "X" },
        }, nil),
      },
    })

    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_detect.lua" })
      local payloads = {}
      addon.LFGDetect.SetAcceptedInviteNoticeCallback(function(payload)
        payloads[#payloads + 1] = payload
      end)
      addon.LFGDetect.SetAcceptedInviteNoticeEnabledFn(function()
        return false
      end)

      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 501, "invited")
      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 501, "inviteaccepted")

      Assert.Equal(#payloads, 0, "disabled toggle must suppress the notice callback entirely")
    end)
  end)

  -- Test F: when only the enabled-fn is wired (no callback), MaybeShow must
  -- early-return without crashing — i.e. callback wiring is independent of
  -- enabled-fn wiring.
  test("AcceptedInviteNotice early-returns cleanly when callback is unwired", function()
    local globals, fire = BuildLFGDetectEnv({
      globals = {
        C_LFGList = BuildC_LFGList({
          [601] = { activityID = 1542, name = "+9", leaderName = "Q" },
        }, nil),
      },
    })

    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_detect.lua" })
      addon.LFGDetect.SetAcceptedInviteNoticeEnabledFn(function()
        return true
      end)
      -- No callback set.
      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 601, "invited")
      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 601, "inviteaccepted")
      Assert.Equal(
        addon.LFGDetect.GetDetectedMapID(),
        557,
        "missing notice callback must not break the existing pipeline"
      )
    end)
  end)
end

return function(test, ctx)
  RegisterLFGDetectResolutionTests(test, ctx)
  RegisterLFGDetectInviteAcceptRaceTests(test, ctx)
  RegisterLFGDetectQueueStateTests(test, ctx)
  RegisterLFGDetectResetTests(test, ctx)
  RegisterLFGDetectInviteHintTests(test, ctx)
  RegisterLFGDetectAcceptedInviteNoticeTests(test, ctx)
  RegisterLFGDetectBranchCoverageTests(test, ctx)
end
