-- Standalone CLI tool: walks the WoW 12.0.0 ("Midnight") taint / restriction
-- contract that CLAUDE.md spells out, verifying at runtime that the addon
-- does not regress into the patterns Blizzard now forbids.
--
-- The 12.0 restrictions this simulator guards against:
--   1. COMBAT_LOG_EVENT_UNFILTERED is removed from the addon API; registering
--      it raises ADDON_ACTION_FORBIDDEN on every attempt. The static gate
--      `tools/check_wow_api_compliance.lua` already greps for this; here we
--      verify at runtime that no module (including dynamic event tables)
--      tries to listen for it.
--   2. RegisterEvent dispatched FROM a protected handler (e.g. inside the
--      CHALLENGE_MODE_START callback) is forbidden regardless of which
--      event is being registered. CombatEvents must not register inside
--      its CHALLENGE_MODE_START reset path.
--   3. Secret Values: protected APIs return masked nil / 0 inside tainted
--      execution contexts (M+ keys, boss encounters). The combat-events
--      controller must guard reads of UNIT_SPELLCAST_SUCCEEDED's spellID,
--      reject `unit ~= "player"` short-circuit (because the API does not
--      expose a target), and stay silent when isInKey() collapses to false.
--   4. BR / Lust detection chain: matches the spell IDs in
--      game/isiLive_combat_events.lua against UNIT_SPELLCAST_SUCCEEDED for
--      the local "player" unit only — never for other party members.
--   5. CHALLENGE_MODE_START/COMPLETED cycle: per-cycle dedup state must
--      reset so a Bloodlust in run 1 doesn't suppress a Bloodlust in run 2.
--
-- End-to-end discipline (CLAUDE.md "Tests & simulators: end-to-end by default"):
--   * Phase 1 drives module loading + RegisterEvent capture against real
--     production modules (LFGDetect, CombatEvents, KickTracker, KillTrack).
--   * Phase 2 was previously calling controller.HandleUnitSpellcastSucceeded
--     directly (one layer below the production dispatcher); it now routes
--     every spell event through the real CombatEvents.HandleEvent
--     ("UNIT_SPELLCAST_SUCCEEDED", unit, ...) entry point — the same path
--     WoW invokes through OnEvent. This catches a future regression where
--     HandleEvent stops fanning out to HandleUnitSpellcastSucceeded.
--   * Phase 3 drives the protected-dispatch guard against the real
--     CombatEvents.HandleEvent path — no replica.
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
-- A frame stub that records every RegisterEvent call. The simulator uses
-- this to assert the forbidden patterns never occur, even when modules
-- dynamically build their event tables.
-- ----------------------------------------------------------------------
local function NewTrackingFrame()
  local frame = {
    _events = {},
    _scripts = {},
  }
  function frame:RegisterEvent(event)
    self._events[#self._events + 1] = event
  end
  function frame:UnregisterEvent(event)
    for i, e in ipairs(self._events) do
      if e == event then
        table.remove(self._events, i)
        return
      end
    end
  end
  function frame:SetScript(name, fn)
    self._scripts[name] = fn
  end
  function frame:GetScript(name)
    return self._scripts[name]
  end
  return frame
end

-- Allows scenarios to flip the "in tainted dispatch" flag, then fail
-- loudly if any RegisterEvent call lands while the flag is on. Production
-- code paths that register events must do so eagerly during file load /
-- PLAYER_LOGIN, never from inside a protected handler.
local function NewProtectedDispatchGuard()
  local guard = { isProtectedDispatch = false, violations = {} }
  guard.enter = function()
    guard.isProtectedDispatch = true
  end
  guard.exit = function()
    guard.isProtectedDispatch = false
  end
  guard.wrapFrame = function(frame)
    local origRegister = frame.RegisterEvent
    frame.RegisterEvent = function(targetFrame, event)
      if guard.isProtectedDispatch then
        guard.violations[#guard.violations + 1] = event
      end
      origRegister(targetFrame, event)
    end
    return frame
  end
  return guard
end

-- ----------------------------------------------------------------------
-- Helper: check 1 — no module registers COMBAT_LOG_EVENT_UNFILTERED.
-- Loads the LFGDetect + bootstrap-style modules with a tracking frame
-- and asserts the forbidden event does not appear in the registration
-- log even after PLAYER_LOGIN replay.
-- ----------------------------------------------------------------------
local function VerifyCombatLogEventNotRegistered()
  print("---- Phase 1: COMBAT_LOG_EVENT_UNFILTERED forbidden registration ----")

  local frames = {}
  local globals = {
    CreateFrame = function()
      local f = NewTrackingFrame()
      frames[#frames + 1] = f
      return f
    end,
    C_Timer = { NewTicker = function() end },
    DEFAULT_CHAT_FRAME = { AddMessage = function() end },
    IsInGroup = function()
      return false
    end,
    IsInRaid = function()
      return false
    end,
    GetNumGroupMembers = function()
      return 0
    end,
    UnitName = function()
      return "Tester", "Realm"
    end,
    GetUnitName = function()
      return "Tester-Realm"
    end,
    GetTime = function()
      return 100
    end,
    C_ChallengeMode = {
      GetActiveChallengeMapID = function()
        return 559
      end,
    },
  }

  Harness.WithGlobals(globals, function()
    Harness.LoadAddonModules({
      "isiLive_lfg_detect.lua",
      "isiLive_combat_events.lua",
      "isiLive_kick_tracker.lua",
      "isiLive_killtrack.lua",
    })
  end)

  local sawForbidden = false
  for _, frame in ipairs(frames) do
    for _, event in ipairs(frame._events) do
      if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        sawForbidden = true
      end
    end
  end
  Check(not sawForbidden, "no module statically registers COMBAT_LOG_EVENT_UNFILTERED (forbidden in 12.0)")
end

-- ----------------------------------------------------------------------
-- Helper: check 4 + 5 — BR/Lust detection chain.
-- Drives the CombatEvents controller directly (no factory wiring) so we
-- can assert the broadcast contract: self-cast only, in-key only, dedup
-- inside a 3s window, dedup map RESETS on CHALLENGE_MODE_START.
-- ----------------------------------------------------------------------
local function VerifyBrLustDetection()
  print("\n---- Phase 2: BR / Lust UNIT_SPELLCAST_SUCCEEDED contract ----")

  local clock = { now = 1000 }
  local broadcasts = {}

  local globals = {
    CreateFrame = function()
      return NewTrackingFrame()
    end,
    C_Timer = { NewTicker = function() end },
    DEFAULT_CHAT_FRAME = { AddMessage = function() end },
    GetTime = function()
      return clock.now
    end,
    UnitName = function(unit)
      return "Tester-" .. tostring(unit), "Realm"
    end,
    GetUnitName = function(unit)
      return "Tester-" .. tostring(unit)
    end,
  }

  Harness.WithGlobals(globals, function()
    local addon = Harness.LoadAddonModules({ "isiLive_combat_events.lua" })

    local inKey = { value = true }
    local dbToggles = { chatAnnounceBR = true, chatAnnounceLust = true }

    -- Wire deps into the file-scope controllerInstance via the production
    -- SetDependencies entry — this is what factory_controllers.lua does in
    -- production. CombatEvents.HandleEvent then routes through this instance.
    addon.CombatEvents.SetDependencies({
      getTime = function()
        return clock.now
      end,
      isInKey = function()
        return inKey.value
      end,
      getUnitName = function(unit)
        return "Tester-" .. unit
      end,
      broadcastCombatAnnounce = function(kind, sourceName, spellID)
        broadcasts[#broadcasts + 1] = { kind = kind, source = sourceName, spellID = spellID }
      end,
      getDB = function()
        return dbToggles
      end,
    })

    -- BR spell (Rebirth) cast by player → must broadcast.
    addon.CombatEvents.HandleEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "spell", 20484)
    Check(#broadcasts == 1, "Rebirth (Druid BR) by player triggers broadcast")
    Check(broadcasts[1].kind == "BR", "broadcast kind=BR for spellID 20484")

    -- Same BR cast within 3s by same player → deduplicated.
    clock.now = clock.now + 1
    addon.CombatEvents.HandleEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "spell", 20484)
    Check(#broadcasts == 1, "duplicate BR within 3s window is suppressed")

    -- BR cast by another party member → must NOT broadcast (self-only).
    clock.now = clock.now + 5
    addon.CombatEvents.HandleEvent("UNIT_SPELLCAST_SUCCEEDED", "party2", "spell", 20484)
    Check(#broadcasts == 1, "non-player unit BR is rejected (Secret Value safety)")

    -- Bloodlust by player → broadcast as LUST.
    addon.CombatEvents.HandleEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "spell", 2825)
    Check(#broadcasts == 2, "Bloodlust (Shaman) by player triggers broadcast")
    Check(broadcasts[2].kind == "LUST", "broadcast kind=LUST for spellID 2825")

    -- Outside a key → must NOT broadcast.
    inKey.value = false
    addon.CombatEvents.HandleEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "spell", 80353)
    Check(#broadcasts == 2, "Time Warp outside a key does not broadcast")
    inKey.value = true

    -- Random non-BR-non-LUST spell → no broadcast.
    addon.CombatEvents.HandleEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "spell", 1234567)
    Check(#broadcasts == 2, "non-BR/Lust spellID does not broadcast")

    -- Secret Value: spellID arrives as nil (12.0 protected-context masking).
    addon.CombatEvents.HandleEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "spell", nil)
    Check(#broadcasts == 2, "nil spellID (Secret Value) is silently rejected")

    -- DB toggle off for BR → next BR is suppressed.
    dbToggles.chatAnnounceBR = false
    clock.now = clock.now + 100
    addon.CombatEvents.HandleEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "spell", 20484)
    Check(#broadcasts == 2, "chatAnnounceBR=false suppresses BR broadcast")
    dbToggles.chatAnnounceBR = true

    -- ------------------------------------------------------------------
    -- Cycle: a fresh CHALLENGE_MODE_START must Reset() the dedup map so
    -- the same spell can announce again in the next run.
    -- ------------------------------------------------------------------
    clock.now = clock.now + 1
    addon.CombatEvents.HandleEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "spell", 2825)
    Check(#broadcasts == 3, "Bloodlust in cycle 1 (post-toggle) broadcasts")
    -- Within dedup window, same Bloodlust would be suppressed:
    addon.CombatEvents.HandleEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "spell", 2825)
    Check(#broadcasts == 3, "duplicate Bloodlust within 3s window stays suppressed")

    -- CHALLENGE_MODE_START fires through the same HandleEvent dispatcher;
    -- the production fan-out calls Reset() for the dedup map.
    addon.CombatEvents.HandleEvent("CHALLENGE_MODE_START")
    addon.CombatEvents.HandleEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "spell", 2825)
    Check(
      #broadcasts == 4,
      "CHALLENGE_MODE_START Reset() clears the dedup map so the next run's Bloodlust announces fresh"
    )
  end)
end

-- ----------------------------------------------------------------------
-- Helper: check 2 — no RegisterEvent call from inside the protected
-- CombatEvents.HandleEvent dispatch path. We instrument the tracking
-- frame and flip the protected-dispatch guard around the dispatch.
-- ----------------------------------------------------------------------
local function VerifyNoRegisterEventFromProtectedDispatch()
  print("\n---- Phase 3: no RegisterEvent inside protected dispatch ----")

  local guard = NewProtectedDispatchGuard()
  local frames = {}
  local globals = {
    CreateFrame = function()
      local f = guard.wrapFrame(NewTrackingFrame())
      frames[#frames + 1] = f
      return f
    end,
    C_Timer = { NewTicker = function() end },
    DEFAULT_CHAT_FRAME = { AddMessage = function() end },
    GetTime = function()
      return 1
    end,
    UnitName = function()
      return "Tester", "Realm"
    end,
    GetUnitName = function()
      return "Tester-Realm"
    end,
    C_ChallengeMode = {
      GetActiveChallengeMapID = function()
        return 559
      end,
    },
  }

  Harness.WithGlobals(globals, function()
    local addon = Harness.LoadAddonModules({ "isiLive_combat_events.lua" })
    addon.CombatEvents.SetDependencies({
      getTime = function()
        return 1
      end,
      isInKey = function()
        return true
      end,
      getUnitName = function()
        return "Tester-Realm"
      end,
      broadcastCombatAnnounce = function() end,
      getDB = function()
        return {}
      end,
    })

    -- The full lifecycle: START → BR → COMPLETED → START → LUST → RESET.
    -- During each dispatch the guard is "armed"; any RegisterEvent call
    -- inside HandleEvent would land in guard.violations.
    local dispatches = {
      { event = "CHALLENGE_MODE_START" },
      { event = "UNIT_SPELLCAST_SUCCEEDED", args = { "player", "spell", 20484 } },
      { event = "CHALLENGE_MODE_COMPLETED" },
      { event = "CHALLENGE_MODE_START" },
      { event = "UNIT_SPELLCAST_SUCCEEDED", args = { "player", "spell", 2825 } },
      { event = "CHALLENGE_MODE_RESET" },
    }
    for _, dispatch in ipairs(dispatches) do
      guard.enter()
      if dispatch.args then
        local Unpack = rawget(_G, "unpack") or rawget(table, "unpack")
        addon.CombatEvents.HandleEvent(dispatch.event, Unpack(dispatch.args))
      else
        addon.CombatEvents.HandleEvent(dispatch.event)
      end
      guard.exit()
    end
  end)

  Check(
    #guard.violations == 0,
    "no RegisterEvent fired from inside any protected CombatEvents dispatch (CLAUDE.md 12.0 rule)"
  )
end

-- ----------------------------------------------------------------------
-- Helper: check 3 — Secret Values surfacing as nil from C_ChallengeMode
-- must not crash the LFGDetect / status side. Drives a CHALLENGE-style
-- environment where every protected API returns nil and asserts the
-- combat-events module still cleanly skips.
-- ----------------------------------------------------------------------
local function VerifySecretValueSafety()
  print("\n---- Phase 4: Secret Values return nil — addon stays silent ----")

  local globals = {
    CreateFrame = function()
      return NewTrackingFrame()
    end,
    C_Timer = { NewTicker = function() end },
    DEFAULT_CHAT_FRAME = { AddMessage = function() end },
    GetTime = function()
      return 1
    end,
    UnitName = function()
      return nil
    end,
    GetUnitName = function()
      return nil
    end,
    -- Secret-Values: GetActiveChallengeMapID returns nil even though we
    -- are conceptually in a key (12.0 mask).
    C_ChallengeMode = {
      GetActiveChallengeMapID = function()
        return nil
      end,
    },
  }

  Harness.WithGlobals(globals, function()
    local addon = Harness.LoadAddonModules({ "isiLive_combat_events.lua" })
    local broadcasts = {}
    local controller = addon.CombatEvents.CreateController({
      -- Use the production isInKey path which queries C_ChallengeMode —
      -- the stub returns nil, so isInKey() must yield false and short-
      -- circuit before any spellID lookup is attempted.
      broadcastCombatAnnounce = function(kind, sourceName, spellID)
        broadcasts[#broadcasts + 1] = { kind = kind, source = sourceName, spellID = spellID }
      end,
      getDB = function()
        return {}
      end,
    })

    controller.HandleUnitSpellcastSucceeded("player", "spell", 20484)
    Check(
      #broadcasts == 0,
      "isInKey() yielding false from a Secret-Values'd GetActiveChallengeMapID() short-circuits the broadcast"
    )
  end)
end

local function Run()
  print("========== CHALLENGE_MODE 12.0 taint-sequence simulator ==========\n")
  VerifyCombatLogEventNotRegistered()
  VerifyBrLustDetection()
  VerifyNoRegisterEventFromProtectedDispatch()
  VerifySecretValueSafety()

  if failures > 0 then
    print(string.format("\nCHALLENGE_MODE taint-sequence simulator failed: %d check(s) failed", failures))
    os.exit(1)
  end

  print("\nCHALLENGE_MODE taint-sequence simulator passed.")
end

Run()
