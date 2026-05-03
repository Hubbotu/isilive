-- Standalone CLI tool: reproduces the real-life multi-invite race that produced
-- three "Ziel-Dungeon" chat lines and a wrong invite-hint dungeon name.
--
-- Real-world scenario (player report 2026-05-03):
--   * Player has Nexus-Point Xenas +13 in their bag.
--   * Player listed for / received invites from THREE LFG groups in parallel:
--       A: "+12 farm"        (other dungeon)
--       B: "+13 NPX"         (same dungeon as own key)
--       C: "+14 NPX"         (the leader's actual key, different player)
--   * Player accepts C (the +14 NPX).
--   * Listing A delists ("LFG abgemeldet").
--   * The chat sees:
--       1.  "Ziel-Dungeon: Nexuspunkt Xenas +14"   (correct, from LFG-title hint)
--       2.  "Ziel-Dungeon: Nexuspunkt Xenas +13"   (WRONG — own key surfaced)
--       3.  "Ziel-Dungeon: Nexuspunkt Xenas"       (WRONG — level cleared entirely)
--   * The invite-hint above the Blizzard dialog showed the wrong dungeon
--     (latest invite text overwriting earlier text without dialog binding).
--
-- Verifies the three fixes:
--   * Fix 1 (game/isiLive_lfg_detect.lua, OnInviteDeclined): a delisted /
--     declined invite for a different searchResultID must NOT erase the
--     accepted invite's activeInviteTitleLevel / activeInviteLeader.
--   * Fix 2 (ui/isiLive_status.lua, MaybeAnnounceTargetDungeonChat): once a
--     dungeon was announced WITH a level, every later announce for the same
--     dungeon name (level downgrade, level clear) must be suppressed.
--   * Fix 3a (game/isiLive_lfg_detect.lua + ui/isiLive_notice.lua): the invite
--     hint must carry the searchResultID so the floating box can hide itself
--     when the visible LFGListInviteDialog references a different listing.
---@diagnostic disable: undefined-global
local io = io
---@diagnostic disable-next-line: undefined-global
local load = load

local function LoadLocal(path)
  local file = assert(io.open(path, "rb"))
  local source = file:read("*a")
  file:close()
  local chunk, err = (loadstring or load)(source, "@" .. path)
  assert(chunk, err)
  return chunk()
end

local Harness = LoadLocal("testmodul/isilive_test_harness.lua")

local failures = 0

local function Check(condition, message)
  if condition then
    print("  [CHECK PASS] " .. message)
    return
  end
  failures = failures + 1
  print("  [CHECK FAIL] " .. message)
end

-- ----------------------------------------------------------------------
-- Build the LFGDetect stubs (C_LFGList, IsInGroup, CreateFrame).
-- ----------------------------------------------------------------------

local function BuildC_LFGList(searchResults)
  return {
    GetSearchResultInfo = function(id)
      return searchResults[id]
    end,
    GetActiveEntryInfo = function()
      return nil
    end,
    GetActivityFullName = function()
      return nil
    end,
    GetActivityInfoTable = function()
      return nil
    end,
  }
end

local function BuildLFGDetectGlobals(searchResults, isInGroupRef, numGroupMembersRef)
  local capturedOnEvent
  return {
    CreateFrame = function()
      return {
        RegisterEvent = function() end,
        SetScript = function(_, scriptType, fn)
          if scriptType == "OnEvent" then
            capturedOnEvent = fn
          end
        end,
      }
    end,
    C_Timer = {
      NewTicker = function() end,
    },
    DEFAULT_CHAT_FRAME = {
      AddMessage = function() end,
    },
    C_LFGList = BuildC_LFGList(searchResults),
    IsInGroup = function()
      return isInGroupRef[1]
    end,
    IsInRaid = function()
      return false
    end,
    GetNumGroupMembers = function()
      return numGroupMembersRef[1]
    end,
  }, function(event, ...)
    local addon = rawget(_G, "__isilive_last_loaded_addon")
    if addon and addon.LFGDetect and type(addon.LFGDetect.HandleEvent) == "function" then
      addon.LFGDetect.HandleEvent(event, ...)
    elseif capturedOnEvent then
      capturedOnEvent(nil, event, ...)
    end
  end
end

-- ----------------------------------------------------------------------
-- Build the Status controller. Drives the chat-announce side directly so
-- we can assert the exact print sequence.
-- ----------------------------------------------------------------------

local function BuildStatusController(addon, deps)
  return addon.Status.CreateController({
    getL = function()
      return {
        STATUS_TARGET_DUNGEON_TEXT = "Target Dungeon: %s",
        STATUS_TARGET_DUNGEON_NONE = "Target Dungeon: -",
      }
    end,
    isInGroup = function()
      return deps.isInGroup()
    end,
    getTargetDungeonInfo = function()
      return deps.getTargetDungeonInfo()
    end,
    printFn = function(message)
      table.insert(deps.prints, tostring(message))
    end,
  })
end

-- ----------------------------------------------------------------------
-- Lightweight invite-hint stub. Captures every render call so we can
-- verify Fix 3a passes the searchResultID through. The hint frame's
-- dialog-binding is exercised by unit tests; here we only assert the
-- callback contract.
-- ----------------------------------------------------------------------

local function BuildHintCapture()
  local hints = {}
  return hints,
    function(message, durationSeconds, searchResultID)
      table.insert(hints, {
        message = message,
        duration = durationSeconds,
        searchResultID = searchResultID,
      })
    end
end

-- ----------------------------------------------------------------------
-- The single-driver simulator.
-- ----------------------------------------------------------------------

local function Run()
  print("========== Multi-invite + level-flicker target-chain simulator ==========\n")

  local isInGroup = { false }
  local numMembers = { 0 }

  -- Three parallel listings:
  --   1: "+12 ZA farm"                — other dungeon
  --   2: "+13 NPX self"               — same dungeon as the own +13 key
  --   3: "Nexuspunkt Xenas +14 push"  — the listing the player accepts
  local searchResults = {
    [1] = { activityID = 1542, name = "+12 Spire farm", leaderName = "Farmguy-Realm" },
    [2] = { activityID = 1768, name = "+13 NPX easy", leaderName = "Selfish-Realm" },
    [3] = { activityID = 1768, name = "Nexuspunkt Xenas +14 push", leaderName = "Pusher-Realm" },
  }

  local globals, fire = BuildLFGDetectGlobals(searchResults, isInGroup, numMembers)

  Harness.WithGlobals(globals, function()
    local addon = Harness.LoadAddonModules({ "isiLive_lfg_detect.lua", "isiLive_status.lua" })

    -- Wire the invite-hint capture.
    local hints, hintCallback = BuildHintCapture()
    addon.LFGDetect.SetInviteHintCallback(hintCallback)
    addon.LFGDetect.SetInviteHintEnabledFn(function()
      return true
    end)
    addon.LFGDetect.SetInviteHintLocaleFn(function()
      return {
        INVITE_HINT_GROUP = "Group: %s",
        INVITE_HINT_UNKNOWN_DUNGEON = "Unknown",
      }
    end)
    addon.LFGDetect.SetTeleportLookupByMapID(function(mapID)
      if mapID == 559 then
        return { mapName = "Nexus-Point Xenas" }
      elseif mapID == 557 then
        return { mapName = "Windrunner Spire" }
      end
      return nil
    end)

    -- Drive the status controller from a moving "what does the level
    -- resolver currently see" model — the same level-flicker pattern the
    -- production GetStatusTargetDungeonInfo experiences when the LFG-title
    -- hint disappears and the owner-key sync round-trip kicks in.
    local statusModel = {
      inGroup = false,
      target = nil, -- { name, level } | nil
      prints = {},
    }
    local statusController = BuildStatusController(addon, {
      isInGroup = function()
        return statusModel.inGroup
      end,
      getTargetDungeonInfo = function()
        return statusModel.target
      end,
      prints = statusModel.prints,
    })

    -- ------------------------------------------------------------------
    -- Phase 1: three invites arrive in quick succession.
    -- Each renders an invite-hint with its own searchResultID.
    -- ------------------------------------------------------------------
    print("---- Phase 1: three parallel invites arrive ----")
    fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "invited")
    fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 2, "invited")
    fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 3, "invited")

    Check(#hints == 3, "every incoming invite renders an invite-hint")
    Check(hints[1].searchResultID == 1, "hint #1 carries the listing-A searchResultID")
    Check(hints[2].searchResultID == 2, "hint #2 carries the listing-B searchResultID")
    Check(hints[3].searchResultID == 3, "hint #3 carries the listing-C searchResultID (Fix 3a wiring)")

    -- ------------------------------------------------------------------
    -- Phase 2: player accepts listing C (the +14 NPX push).
    -- activeInviteTitleLevel must lock onto 14 and acceptedInviteSearchResultID
    -- must point at listing 3.
    -- ------------------------------------------------------------------
    print("\n---- Phase 2: accept listing C (+14 NPX) ----")
    fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 3, "inviteaccepted")
    isInGroup[1] = true
    numMembers[1] = 2
    fire("GROUP_ROSTER_UPDATE")

    Check(addon.LFGDetect.GetDetectedMapID() == 559, "detectedMapID resolves to Nexus-Point Xenas")
    Check(
      addon.LFGDetect.GetActiveInviteTitleLevel() == 14,
      "activeInviteTitleLevel resolves to +14 from the accepted listing's title"
    )
    Check(
      addon.LFGDetect.GetActiveInviteLeader() == "Pusher-Realm",
      "activeInviteLeader resolves to the +14-listing's leader"
    )
    Check(
      addon.LFGDetect.GetAcceptedInviteSearchResultID() == 3,
      "acceptedInviteSearchResultID is captured (Fix 1 prerequisite)"
    )

    -- First Status announce: with the LFG-title hint =14, downstream sees
    -- { name="Nexus-Point Xenas", level=14 } and prints the +14 line.
    statusModel.inGroup = true
    statusModel.target = { name = "Nexus-Point Xenas", level = 14 }
    statusController.MaybeAnnounceTargetDungeonChat()
    Check(#statusModel.prints == 1, "first announce fires once for the locked-in +14 target")
    Check(
      statusModel.prints[1] == "Target Dungeon: |cffffd200Nexus-Point Xenas +14|r",
      "first announce carries the +14 level"
    )

    -- ------------------------------------------------------------------
    -- Phase 3: parallel listings get delisted ("+12 Spire abgemeldet" /
    -- "+13 NPX abgemeldet"). Each fires a NEGATIVE_STATUS update for a
    -- searchResultID OTHER than the accepted one. With Fix 1, neither
    -- may null out activeInviteTitleLevel / activeInviteLeader.
    -- ------------------------------------------------------------------
    print("\n---- Phase 3: parallel listings delist (Fix 1 guard) ----")
    fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "declined_delisted")
    Check(
      addon.LFGDetect.GetActiveInviteTitleLevel() == 14,
      "OnInviteDeclined for listing A (different mapID) keeps activeInviteTitleLevel"
    )
    fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 2, "declined_delisted")
    Check(
      addon.LFGDetect.GetActiveInviteTitleLevel() == 14,
      "OnInviteDeclined for listing B (same mapID, other searchResultID) keeps activeInviteTitleLevel"
    )
    Check(
      addon.LFGDetect.GetActiveInviteLeader() == "Pusher-Realm",
      "activeInviteLeader survives parallel-listing delists"
    )
    Check(
      addon.LFGDetect.GetDetectedMapID() == 559,
      "detectedMapID survives parallel-listing delists (highlight stays on)"
    )

    -- ------------------------------------------------------------------
    -- Phase 4: even WITHOUT Fix 1, the next status calls would have re-
    -- announced as level downgraded. Drive the same level-flicker pattern
    -- through MaybeAnnounceTargetDungeonChat to verify Fix 2 lock-in.
    --
    -- Step 4a: own-key surfaces (level=13, same dungeon name).
    -- Step 4b: sync flickers, level=nil entirely.
    -- Step 4c: level=14 again (settled).
    -- All three calls must remain silent because Fix 2 locked the dungeon.
    -- ------------------------------------------------------------------
    print("\n---- Phase 4: status-level flicker (Fix 2 lock-in) ----")

    statusModel.target = { name = "Nexus-Point Xenas", level = 13 }
    statusController.MaybeAnnounceTargetDungeonChat()
    Check(
      #statusModel.prints == 1,
      "+13 fallback (own key surfacing) must NOT produce a second chat line for the locked dungeon"
    )

    statusModel.target = { name = "Nexus-Point Xenas" }
    statusController.MaybeAnnounceTargetDungeonChat()
    statusController.MaybeAnnounceTargetDungeonChat() -- needs two calls to clear the level-less debounce
    Check(
      #statusModel.prints == 1,
      "level-less re-render (sync round-trip) must NOT produce a third chat line for the locked dungeon"
    )

    statusModel.target = { name = "Nexus-Point Xenas", level = 14 }
    statusController.MaybeAnnounceTargetDungeonChat()
    Check(#statusModel.prints == 1, "settled +14 again must not produce a duplicate line")

    -- ------------------------------------------------------------------
    -- Phase 5: end-of-cycle reset. After the player leaves the group, the
    -- next +N for the SAME dungeon must be free to announce again.
    -- ------------------------------------------------------------------
    print("\n---- Phase 5: leave + rejoin must allow a fresh announce ----")
    statusModel.inGroup = false
    statusController.MaybeAnnounceTargetDungeonChat() -- triggers ResetTargetDungeonChatState

    statusModel.inGroup = true
    statusModel.target = { name = "Nexus-Point Xenas", level = 14 }
    statusController.MaybeAnnounceTargetDungeonChat()
    Check(
      #statusModel.prints == 2,
      "leaving the group resets the lock-in so a fresh key joins later can announce again"
    )
    Check(
      statusModel.prints[2] == "Target Dungeon: |cffffd200Nexus-Point Xenas +14|r",
      "second-cycle announce carries the +14 level"
    )

    -- ------------------------------------------------------------------
    -- Phase 6: the symmetric Fix 1 case — verify that the ACTUALLY accepted
    -- listing's decline (e.g. when the player declines after accepting,
    -- which in production maps to ClearAllStateImpl via group-leave) is
    -- still allowed to clear state. We simulate it by calling ClearAllState.
    -- ------------------------------------------------------------------
    print("\n---- Phase 6: ClearAllState always wipes the accepted-resultID ----")
    addon.LFGDetect.ClearAllState()
    Check(
      addon.LFGDetect.GetAcceptedInviteSearchResultID() == nil,
      "ClearAllState drops acceptedInviteSearchResultID alongside the rest"
    )
    Check(addon.LFGDetect.GetActiveInviteTitleLevel() == nil, "ClearAllState drops activeInviteTitleLevel")
    Check(addon.LFGDetect.GetActiveInviteLeader() == nil, "ClearAllState drops activeInviteLeader")
  end)

  if failures > 0 then
    print(string.format("\nMulti-invite target-chain simulator failed: %d check(s) failed", failures))
    os.exit(1)
  end

  print("\nMulti-invite target-chain simulator passed.")
end

Run()
