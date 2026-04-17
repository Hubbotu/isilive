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

  return globals, function(event, ...)
    if onEvent then
      onEvent(nil, event, ...)
    end
  end, prints
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

  test("LFGDetect own listing chat dedup prints once for same mapID", function()
    local globals, fire, prints = BuildLFGDetectEnv({
      globals = {
        C_LFGList = BuildC_LFGList({}, { activityID = 1542 }),
      },
    })

    WithGlobals(globals, function()
      LoadAddonModules({ "isiLive_lfg_detect.lua" })

      fire("LFG_LIST_ACTIVE_ENTRY_UPDATE")
      fire("LFG_LIST_ACTIVE_ENTRY_UPDATE") -- same listing, same mapID

      local lfgPrints = {}
      for _, msg in ipairs(prints) do
        if msg:find("LFG") then
          table.insert(lfgPrints, msg)
        end
      end
      Assert.Equal(#lfgPrints, 1, "identical mapID must print only once (Rule 22 chat dedup)")
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
end

local function RegisterLFGDetectResetAndLocaleTests(test, ctx)
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

      Assert.Equal(type(capturedBuilder), "function", "LFG trace logger must receive a lazy message builder")
      Assert.True(
        capturedBuilder():find("%[LFG%] queue_listing_detected mapID=557 lastQueueMapID=nil") ~= nil,
        "LFG trace builder must format on demand"
      )
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- SetLocaleGetter injection (MINOR-1)
  -- ---------------------------------------------------------------------------

  test("LFGDetect uses injected locale getter for chat message", function()
    local prints = {}
    local localeHits = 0

    local globals, fire = BuildLFGDetectEnv({
      globals = {
        C_LFGList = BuildC_LFGList({ [1] = { activityID = 1542 } }, nil),
        DEFAULT_CHAT_FRAME = {
          AddMessage = function(_, msg)
            table.insert(prints, tostring(msg))
          end,
        },
      },
    })

    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_detect.lua" })
      addon.LFGDetect.SetLocaleGetter(function()
        localeHits = localeHits + 1
        return { LFG_DETECT_INVITE = "Einladung erkannt: %s" }
      end)

      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "invited")
      fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "inviteaccepted")

      Assert.True(localeHits >= 1, "locale getter must be called when printing the invite message")
      local found = false
      for _, msg in ipairs(prints) do
        if msg:find("Einladung erkannt") then
          found = true
        end
      end
      Assert.True(found, "localized invite message must appear in chat output")
    end)
  end)
end

return function(test, ctx)
  RegisterLFGDetectResolutionTests(test, ctx)
  RegisterLFGDetectQueueStateTests(test, ctx)
  RegisterLFGDetectResetAndLocaleTests(test, ctx)
end
