---@diagnostic disable: undefined-global

-- Builds the minimal WoW global stubs needed to load isiLive_combat_events.lua.
-- Returns the captured onEvent handler so tests can inject events directly,
-- plus the accumulated print buffer.
local function BuildCombatEventsEnv(overrides)
  overrides = overrides or {}

  local onEvent = nil
  local prints = {}
  local registered = {}

  local globals = {
    CreateFrame = function()
      return {
        RegisterEvent = function(_, event)
          registered[event] = true
        end,
        UnregisterEvent = function(_, event)
          registered[event] = nil
        end,
        SetScript = function(_, scriptType, fn)
          if scriptType == "OnEvent" then
            onEvent = fn
          end
        end,
      }
    end,
    DEFAULT_CHAT_FRAME = {
      AddMessage = function(_, msg)
        table.insert(prints, tostring(msg))
      end,
    },
    GetTime = overrides.GetTime or function()
      return 0
    end,
    C_ChallengeMode = overrides.C_ChallengeMode or {
      GetActiveChallengeMapID = function()
        return 0
      end,
    },
  }

  if overrides.globals then
    for k, v in pairs(overrides.globals) do
      globals[k] = v
    end
  end

  return globals,
    function(event, ...)
      if onEvent then
        onEvent(nil, event, ...)
      end
    end,
    prints,
    registered
end

local function RegisterCombatEventsAutoRegistrationTests(test, ctx)
  local Assert = ctx.assert
  local WithGlobals = ctx.with_globals
  local LoadAddonModules = ctx.load_modules

  test("CombatEvents registers UNIT_SPELLCAST_SUCCEEDED and challenge-mode events on load", function()
    local globals, _, _, registered = BuildCombatEventsEnv()
    WithGlobals(globals, function()
      LoadAddonModules({ "isiLive_combat_events.lua" })
    end)
    -- COMBAT_LOG_EVENT_UNFILTERED was removed from the addon API in 12.0.0
    -- and raises ADDON_ACTION_FORBIDDEN on registration. We listen to
    -- UNIT_SPELLCAST_SUCCEEDED (not taint-sensitive) instead.
    Assert.True(registered["UNIT_SPELLCAST_SUCCEEDED"], "must register UNIT_SPELLCAST_SUCCEEDED")
    Assert.True(registered["CHALLENGE_MODE_START"], "must register CHALLENGE_MODE_START")
    Assert.True(registered["CHALLENGE_MODE_COMPLETED"], "must register CHALLENGE_MODE_COMPLETED")
    Assert.Nil(registered["COMBAT_LOG_EVENT_UNFILTERED"], "must NOT register CLEU (forbidden in 12.0.0)")
  end)
end

local function BuildController(opts)
  opts = opts or {}
  local broadcasts = opts.broadcasts or {}
  local nowRef = opts.nowRef or { value = 0 }
  local inKeyRef = opts.inKeyRef or { value = true }
  local dbRef = opts.dbRef or { value = {} }
  local nameMap = opts.nameMap or {
    player = "Alice-Realm",
  }

  local addon = opts.addon
  return addon.CombatEvents.CreateController({
    getTime = function()
      return nowRef.value
    end,
    isInKey = function()
      return inKeyRef.value == true
    end,
    getUnitName = function(unit)
      return nameMap[unit] or unit
    end,
    broadcastCombatAnnounce = function(kind, sourceName, spellID)
      table.insert(broadcasts, { kind = kind, caster = sourceName, spellID = spellID })
    end,
    getDB = function()
      return dbRef.value
    end,
  })
end

local function RegisterCombatEventsBRTests(test, ctx)
  local Assert = ctx.assert
  local WithGlobals = ctx.with_globals
  local LoadAddonModules = ctx.load_modules

  test("CombatEvents broadcasts own BR when in key", function()
    local addon = nil
    WithGlobals(BuildCombatEventsEnv(), function()
      addon = LoadAddonModules({ "isiLive_combat_events.lua" })
    end)
    local broadcasts = {}
    local controller = BuildController({ addon = addon, broadcasts = broadcasts })
    controller.HandleUnitSpellcastSucceeded("player", "cast-1", 20484)
    Assert.Equal(#broadcasts, 1, "must broadcast exactly one BR call")
    Assert.Equal(broadcasts[1].kind, "BR", "broadcast kind must be BR")
    Assert.Equal(broadcasts[1].caster, "Alice-Realm", "broadcast must pass raw unit name (realm strip happens in receiver)")
    Assert.Equal(broadcasts[1].spellID, 20484, "broadcast must include spellID")
  end)

  test("CombatEvents suppresses BR when not in key", function()
    local addon = nil
    WithGlobals(BuildCombatEventsEnv(), function()
      addon = LoadAddonModules({ "isiLive_combat_events.lua" })
    end)
    local broadcasts = {}
    local controller = BuildController({
      addon = addon,
      broadcasts = broadcasts,
      inKeyRef = { value = false },
    })
    controller.HandleUnitSpellcastSucceeded("player", "cast-1", 20484)
    Assert.Equal(#broadcasts, 0, "no BR broadcast outside M+")
  end)

  test("CombatEvents respects chatAnnounceBR=false toggle", function()
    local addon = nil
    WithGlobals(BuildCombatEventsEnv(), function()
      addon = LoadAddonModules({ "isiLive_combat_events.lua" })
    end)
    local broadcasts = {}
    local controller = BuildController({
      addon = addon,
      broadcasts = broadcasts,
      dbRef = { value = { chatAnnounceBR = false } },
    })
    controller.HandleUnitSpellcastSucceeded("player", "cast-1", 20484)
    Assert.Equal(#broadcasts, 0, "BR broadcast must be gated by chatAnnounceBR")
  end)

  test("CombatEvents dedups identical BR events within 3s", function()
    local addon = nil
    WithGlobals(BuildCombatEventsEnv(), function()
      addon = LoadAddonModules({ "isiLive_combat_events.lua" })
    end)
    local broadcasts = {}
    local nowRef = { value = 100 }
    local controller = BuildController({ addon = addon, broadcasts = broadcasts, nowRef = nowRef })
    controller.HandleUnitSpellcastSucceeded("player", "cast-1", 20484)
    nowRef.value = 102
    controller.HandleUnitSpellcastSucceeded("player", "cast-2", 20484)
    Assert.Equal(#broadcasts, 1, "second BR within dedup window must be dropped")
    nowRef.value = 104
    controller.HandleUnitSpellcastSucceeded("player", "cast-3", 20484)
    Assert.Equal(#broadcasts, 2, "BR after dedup window elapses must fire again")
  end)

  test("CombatEvents ignores casts from units other than the player", function()
    local addon = nil
    WithGlobals(BuildCombatEventsEnv(), function()
      addon = LoadAddonModules({ "isiLive_combat_events.lua" })
    end)
    local broadcasts = {}
    local controller = BuildController({ addon = addon, broadcasts = broadcasts })
    -- Only the caster announces their own cast; other units are ignored to
    -- avoid "table index is secret" from the 12.0.0 Secret Values system.
    controller.HandleUnitSpellcastSucceeded("party1", "cast-1", 20484)
    controller.HandleUnitSpellcastSucceeded("raid3", "cast-2", 20484)
    controller.HandleUnitSpellcastSucceeded("target", "cast-3", 20484)
    controller.HandleUnitSpellcastSucceeded("boss1", "cast-4", 20484)
    controller.HandleUnitSpellcastSucceeded("focus", "cast-5", 20484)
    Assert.Equal(#broadcasts, 0, "BR from non-player units must be ignored (self-casts only)")
  end)
end

local function RegisterCombatEventsLustTests(test, ctx)
  local Assert = ctx.assert
  local WithGlobals = ctx.with_globals
  local LoadAddonModules = ctx.load_modules

  test("CombatEvents broadcasts own Bloodlust cast when in key", function()
    local addon = nil
    WithGlobals(BuildCombatEventsEnv(), function()
      addon = LoadAddonModules({ "isiLive_combat_events.lua" })
    end)
    local broadcasts = {}
    local controller = BuildController({ addon = addon, broadcasts = broadcasts })
    controller.HandleUnitSpellcastSucceeded("player", "cast-1", 2825)
    Assert.Equal(#broadcasts, 1, "must broadcast the Bloodlust cast")
    Assert.Equal(broadcasts[1].kind, "LUST", "broadcast kind must be LUST")
    Assert.Equal(broadcasts[1].spellID, 2825, "broadcast must carry the Bloodlust spellID")
  end)

  test("CombatEvents ignores unrelated spell IDs", function()
    local addon = nil
    WithGlobals(BuildCombatEventsEnv(), function()
      addon = LoadAddonModules({ "isiLive_combat_events.lua" })
    end)
    local broadcasts = {}
    local controller = BuildController({ addon = addon, broadcasts = broadcasts })
    -- 1459 = Arcane Intellect: a cast but neither BR nor Lust.
    controller.HandleUnitSpellcastSucceeded("player", "cast-1", 1459)
    Assert.Equal(#broadcasts, 0, "unrelated cast IDs must not broadcast anything")
  end)

  test("CombatEvents respects chatAnnounceLust=false toggle", function()
    local addon = nil
    WithGlobals(BuildCombatEventsEnv(), function()
      addon = LoadAddonModules({ "isiLive_combat_events.lua" })
    end)
    local broadcasts = {}
    local controller = BuildController({
      addon = addon,
      broadcasts = broadcasts,
      dbRef = { value = { chatAnnounceLust = false } },
    })
    controller.HandleUnitSpellcastSucceeded("player", "cast-1", 2825)
    Assert.Equal(#broadcasts, 0, "Lust broadcast must be gated by chatAnnounceLust")
  end)

  test("CombatEvents Reset clears dedup so same cast fires again", function()
    local addon = nil
    WithGlobals(BuildCombatEventsEnv(), function()
      addon = LoadAddonModules({ "isiLive_combat_events.lua" })
    end)
    local broadcasts = {}
    local nowRef = { value = 50 }
    local controller = BuildController({ addon = addon, broadcasts = broadcasts, nowRef = nowRef })
    controller.HandleUnitSpellcastSucceeded("player", "cast-1", 2825)
    controller.HandleUnitSpellcastSucceeded("player", "cast-2", 2825)
    Assert.Equal(#broadcasts, 1, "dedup must suppress repeat before Reset")
    controller.Reset()
    controller.HandleUnitSpellcastSucceeded("player", "cast-3", 2825)
    Assert.Equal(#broadcasts, 2, "Reset must clear dedup state")
  end)
end

return function(test, ctx)
  RegisterCombatEventsAutoRegistrationTests(test, ctx)
  RegisterCombatEventsBRTests(test, ctx)
  RegisterCombatEventsLustTests(test, ctx)
end
