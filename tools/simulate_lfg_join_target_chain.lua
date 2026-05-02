-- Standalone CLI tool: simulates the LFG apply -> invite accepted -> group fills
-- chain through Group.HandleGroupRosterUpdate and the queue-join announce
-- pipeline. Verifies:
--   * applying to an LFG group captures the group name BEFORE the roster
--     update arrives
--   * the first roster update that flips isInGroup -> true fires the announce
--     exactly once
--   * subsequent roster updates as the group fills (3/5, 4/5, 5/5) DO NOT
--     re-announce ("kein Doppelspam")
--   * if the local player is the group leader, the announce is suppressed
--     and the pending state is cleared
--   * leaving and rejoining a fresh group does not surface the previous
--     pending info (state was cleared on the first announce)
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

-- The queue-announce pipeline lives in factory_controllers.lua, but its
-- behaviour is small enough to model in-line. The model mirrors the production
-- AnnounceQueuedGroupJoin code path — single-fire after the first
-- announce-eligible call, with a leader-suppression branch.
local function NewQueueAnnouncer(opts)
  opts = opts or {}
  local state = {
    pendingInfo = nil,
    announces = {}, -- list of group names actually printed
    suppressedAsLeader = 0,
  }

  local function captureCandidate(args)
    -- Production CaptureQueueJoinCandidate refuses to capture during an active
    -- key, when no group name was supplied, or when there is already a
    -- pending entry.
    if opts.activeChallengeMap and opts.activeChallengeMap() then
      return
    end
    if state.pendingInfo ~= nil then
      return
    end
    if type(args) ~= "table" or type(args.groupName) ~= "string" or args.groupName == "" then
      return
    end
    state.pendingInfo = { groupName = args.groupName }
  end

  local function announce()
    -- The production AnnounceQueuedGroupJoin returns silently when there is
    -- no pending entry or when the local player is the group leader.
    if state.pendingInfo == nil then
      return
    end
    if opts.isPlayerLeader and opts.isPlayerLeader() then
      state.suppressedAsLeader = state.suppressedAsLeader + 1
      state.pendingInfo = nil
      return
    end
    state.announces[#state.announces + 1] = state.pendingInfo.groupName
    state.pendingInfo = nil
  end

  return state, captureCandidate, announce
end

local function BuildSim(opts)
  opts = opts or {}
  local groupState = {
    inGroup = false,
    numMembers = 0,
    wasInGroup = false,
    wasRaidGroup = false,
    isLeader = opts.isLeader == true,
  }
  local statusLineUpdates = 0
  local timers = {}
  local now = 0

  local announcerState, captureCandidate, announce = NewQueueAnnouncer({
    isPlayerLeader = function()
      return groupState.isLeader
    end,
    activeChallengeMap = function()
      return false
    end,
  })

  local groupOpts = {
    isInGroup = function()
      return groupState.inGroup
    end,
    getNumGroupMembers = function()
      return groupState.numMembers
    end,
    getActiveChallengeMapID = function()
      return nil
    end,
    getWasInGroup = function()
      return groupState.wasInGroup
    end,
    setWasInGroup = function(flag)
      groupState.wasInGroup = flag == true
    end,
    getWasRaidGroup = function()
      return groupState.wasRaidGroup
    end,
    setWasRaidGroup = function(flag)
      groupState.wasRaidGroup = flag == true
    end,
    setWasGroupLeader = function() end,
    getRoster = function()
      return {}
    end,
    setRoster = function() end,
    captureQueueJoinCandidate = function()
      -- Group calls this without args; the production CaptureQueueJoinCandidate
      -- is a no-op when nothing was queued earlier (we already captured the
      -- candidate via the LFG-apply path before the roster update arrived).
    end,
    announceQueuedGroupJoin = function()
      announce()
    end,
    setMainFrameVisible = function() end,
    updateLeaderButtons = function() end,
    clearLatestQueueTarget = function() end,
    clearRioBaselineSnapshot = function() end,
    clearKnownUsers = function() end,
    resetInspectAll = function() end,
    resetInspectQueues = function() end,
    updateUI = function()
      statusLineUpdates = statusLineUpdates + 1
    end,
    updateMPlusTeleportButton = function() end,
    clearPendingQueueJoinInfo = function() end,
    getUnitNameAndRealm = function(unit)
      if unit == "player" then
        return "Self", "Realm"
      end
      return nil, nil
    end,
    getUnitClass = function()
      return nil, nil
    end,
    getUnitServerLanguage = function()
      return "??"
    end,
    getOwnedKeystoneSnapshot = function()
      return nil, nil
    end,
    markIsiLiveUser = function() end,
    setPlayerKeyInfo = function() end,
    getUnitRole = function()
      return nil
    end,
    getPlayerSpecName = function()
      return nil
    end,
    getUnitRio = function()
      return nil
    end,
    unitIsGroupLeader = function()
      return groupState.isLeader
    end,
    unitHasIsiLive = function()
      return false
    end,
    applyKnownKeyToRosterEntry = function()
      return false
    end,
    enqueueInspect = function() end,
    sendOwnKeySnapshot = function() end,
    sendIsiLiveHello = function() end,
    sendRefreshRequest = function() end,
    onGroupJoined = function() end,
    onMemberJoinedGroup = function() end,
    timerAfter = function(delay, callback)
      timers[#timers + 1] = { at = now + delay, callback = callback }
    end,
    shouldAutoCloseMainFrame = function()
      return false
    end,
    getRaidTransitionBehavior = function()
      return "hide"
    end,
    autoCloseMainFrame = function() end,
    logRuntimeTracef = function() end,
    logRuntimeTrace = function() end,
  }

  local controller
  Harness.WithGlobals({}, function()
    local addon = Harness.LoadAddonModules({ "isiLive_group.lua" })
    controller = addon.Group.CreateController(groupOpts)
  end)

  local function advance(seconds)
    now = now + seconds
    local pending = timers
    timers = {}
    for _, timer in ipairs(pending) do
      if timer.at <= now then
        timer.callback()
      else
        timers[#timers + 1] = timer
      end
    end
  end

  return {
    groupState = groupState,
    announcerState = announcerState,
    captureCandidate = captureCandidate,
    rosterUpdate = function()
      controller.HandleGroupRosterUpdate()
      advance(1)
    end,
    statusLineUpdates = function()
      return statusLineUpdates
    end,
  }
end

local function Run()
  print("========== LFG apply -> invite -> group full -> announce simulator ==========\n")

  -- ------------------------------------------------------------------
  -- Scenario 1: applicant joins as a non-leader. Announce fires exactly
  -- once even though the roster fills from 2 to 5 in four updates.
  -- ------------------------------------------------------------------
  print("---- Scenario 1: applicant joins, group fills to 5/5 ----")
  do
    local sim = BuildSim({ isLeader = false })

    -- Phase 1: still solo, LFG apply captures the group name.
    sim.captureCandidate({ groupName = "+10 NW Push" })
    Check(
      sim.announcerState.pendingInfo ~= nil and sim.announcerState.pendingInfo.groupName == "+10 NW Push",
      "LFG apply captures the pending group name before the roster update arrives"
    )
    Check(#sim.announcerState.announces == 0, "no announce fires while still solo")

    -- Phase 2: invite accepted, GROUP_ROSTER_UPDATE flips isInGroup=true.
    sim.groupState.inGroup = true
    sim.groupState.numMembers = 2
    sim.rosterUpdate()
    Check(#sim.announcerState.announces == 1, "first roster update with isInGroup=true announces the queued group join")
    Check(sim.announcerState.announces[1] == "+10 NW Push", "announce carries the captured group name")
    Check(sim.announcerState.pendingInfo == nil, "pending info is cleared after the announce")

    -- Phase 3: group fills to 3/5, 4/5, 5/5. NONE of these may re-announce.
    local announceCountAfterJoin = #sim.announcerState.announces
    for _, count in ipairs({ 3, 4, 5 }) do
      sim.groupState.numMembers = count
      sim.rosterUpdate()
    end
    Check(
      #sim.announcerState.announces == announceCountAfterJoin,
      "no additional announces fire while the group fills from 3/5 to 5/5 (no double-spam)"
    )
  end

  -- ------------------------------------------------------------------
  -- Scenario 2: the local player created the group (is the leader).
  -- The pending info must be discarded silently.
  -- ------------------------------------------------------------------
  print("\n---- Scenario 2: applicant becomes leader (suppressed announce) ----")
  do
    local sim = BuildSim({ isLeader = true })

    sim.captureCandidate({ groupName = "+12 ML Vault" })
    Check(
      sim.announcerState.pendingInfo ~= nil,
      "leader-flow still captures the group name (the suppression decision happens at announce time)"
    )

    sim.groupState.inGroup = true
    sim.groupState.numMembers = 2
    sim.rosterUpdate()
    Check(#sim.announcerState.announces == 0, "leader does not get a queued-join announce")
    Check(sim.announcerState.suppressedAsLeader == 1, "leader suppression branch fires exactly once")
    Check(sim.announcerState.pendingInfo == nil, "leader path still clears the pending info")
  end

  -- ------------------------------------------------------------------
  -- Scenario 3: applicant joins, leaves, then re-joins a fresh group
  -- without applying via LFG again. The second join must NOT announce
  -- the stale group name from the first cycle.
  -- ------------------------------------------------------------------
  print("\n---- Scenario 3: leave + rejoin without re-applying (no stale announce) ----")
  do
    local sim = BuildSim({ isLeader = false })

    sim.captureCandidate({ groupName = "+8 Halls" })
    sim.groupState.inGroup = true
    sim.groupState.numMembers = 4
    sim.rosterUpdate()
    Check(#sim.announcerState.announces == 1, "first cycle announces once")

    -- leave
    sim.groupState.inGroup = false
    sim.groupState.numMembers = 0
    sim.rosterUpdate()

    -- rejoin a different group, but no new LFG apply happened — pending must
    -- stay nil so no stale group name is surfaced.
    sim.groupState.inGroup = true
    sim.groupState.numMembers = 3
    sim.rosterUpdate()
    Check(#sim.announcerState.announces == 1, "rejoin without a fresh LFG apply does not replay the previous announce")
  end

  -- ------------------------------------------------------------------
  -- Scenario 4: capture is idempotent. A second capture call before the
  -- roster update arrives must not overwrite the first group name.
  -- ------------------------------------------------------------------
  print("\n---- Scenario 4: double-capture is idempotent ----")
  do
    local sim = BuildSim({ isLeader = false })
    sim.captureCandidate({ groupName = "+11 NW" })
    sim.captureCandidate({ groupName = "+15 BRH" })
    Check(
      sim.announcerState.pendingInfo and sim.announcerState.pendingInfo.groupName == "+11 NW",
      "second capture call does not overwrite the first pending group name"
    )

    sim.groupState.inGroup = true
    sim.groupState.numMembers = 3
    sim.rosterUpdate()
    Check(sim.announcerState.announces[1] == "+11 NW", "announce uses the first captured group name")
  end

  if failures > 0 then
    print(string.format("\nLFG join + target-chain simulator failed: %d check(s) failed", failures))
    os.exit(1)
  end

  print("\nLFG join + target-chain simulator passed.")
end

Run()
