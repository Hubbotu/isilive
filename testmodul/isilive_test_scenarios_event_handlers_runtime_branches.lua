---@diagnostic disable: undefined-global

-- Branch-coverage scenarios for logic/isiLive_event_handlers_runtime.lua.
-- The existing event_handlers test files drive happy paths through the
-- full event-handlers controller. This file targets the still-uncovered
-- defensive branches by building the runtime handler table directly via
-- RuntimeLifecycle.BuildHandlers(ctx) with focused stubs.

local function NewCtx(overrides)
  local ctx = {
    addonName = "isiLive",
    defaultLocale = "enUS",
    locales = { enUS = {} },
    isInGroup = function()
      return false
    end,
    isInChallengeMode = function()
      return false
    end,
    isInPartyInstance = function()
      return false
    end,
    isRaidGroup = function()
      return false
    end,
    isTestMode = function()
      return false
    end,
    isTestAllMode = function()
      return false
    end,
    exitTestMode = function() end,
    handleGroupRosterUpdate = function() end,
    isMainFrameShown = function()
      return true
    end,
    shouldShowMainFrameOnStartup = function()
      return true
    end,
    setMainFrameVisible = function() end,
    getMainFrame = function()
      return nil
    end,
    getUnitNameAndRealm = function()
      return "player", "realm"
    end,
    markIsiLiveUser = function() end,
    resolveLocaleTag = function(tag)
      return tag or "enUS"
    end,
    setLocaleTable = function() end,
    ensureQueueDebugStorage = function() end,
    setQueueDebugEnabled = function() end,
    ensureRuntimeLogStorage = function() end,
    setRuntimeLogEnabled = function() end,
    restoreRioBaseline = function() end,
    registerIsiLiveSyncPrefix = function() end,
    applyHotkeyBindings = function() end,
    startBindingWatchdog = function() end,
    applyLocalizationToUI = function() end,
    restoreLayoutState = function() end,
    updateCountdownCancelButton = function() end,
    updateLeaderButtons = function() end,
    updateCdTracker = function() end,
    sendOwnKeySnapshot = function() end,
    sendOwnKickState = function() end,
    sendOwnBackgroundSnapshot = function() end,
    maybeShowNonMythicDungeonEntryNotice = function() end,
    maybeShowPortalNavigatorNotice = function() end,
    updateStatusLine = function() end,
    checkIfEnteredTargetDungeon = function() end,
    handleOwnedKeyRefresh = function() end,
    onInspectReady = function()
      return false
    end,
    updateUI = function() end,
    updateMPlusTeleportButton = function() end,
    tryRestoreCenterNoticeTeleportButton = function() end,
    setMainFrameHeightSafe = function() end,
    setMainFrameWidthSafe = function() end,
    getPendingBindingApply = function()
      return false
    end,
    getPendingMainFrameHeight = function()
      return nil
    end,
    getPendingMainFrameWidth = function()
      return nil
    end,
    processAddonMessage = function()
      return nil
    end,
    sendIsiLiveHello = function() end,
    sendLibKeystonePartyData = function() end,
    sendRefreshResponse = function() end,
    sendOwnTargetSnapshot = function() end,
    sendOwnKeystoneToChat = function()
      return false
    end,
    showCombatAnnounce = function() end,
    playIncomingSummonSound = function() end,
    forEachRosterInfo = function() end,
    isSyncUserKnown = function()
      return false
    end,
    applyKnownKeyToRosterEntry = function()
      return false
    end,
    sendAck = function() end,
    getRoster = function()
      return {}
    end,
    timerAfter = function() end,
    activeMythicZeroMapID = nil,
    activeMythicZeroRosterSnapshot = nil,
    pendingMythicZeroRunCapture = nil,
    wasInPartyInstance = nil,
  }
  if overrides then
    for key, value in pairs(overrides) do
      ctx[key] = value
    end
  end
  return ctx
end

return function(test, ctx)
  local Assert = ctx.assert
  local WithGlobals = ctx.with_globals
  local LoadAddonModules = ctx.load_modules

  local function LoadHandlers(ctxOverrides, globals)
    local addon
    WithGlobals(globals or {}, function()
      addon = LoadAddonModules({ "isiLive_event_handlers_runtime.lua" })
    end)
    local stub = NewCtx(ctxOverrides)
    return addon.EventHandlersRuntimeLifecycle.BuildHandlers(stub), stub
  end

  -- HandleUpdateBindingsEvent --------------------------------------------------

  test("UPDATE_BINDINGS forwards to applyHotkeyBindings", function()
    local calls = 0
    local handlers = LoadHandlers({
      applyHotkeyBindings = function()
        calls = calls + 1
      end,
    })
    handlers.UPDATE_BINDINGS(nil)
    Assert.Equal(calls, 1, "applyHotkeyBindings must be invoked once")
  end)

  -- HandleAddonLoadedEvent: addon-name mismatch early return -------------------

  test("ADDON_LOADED ignores other addons", function()
    local resolveCalls = 0
    local handlers = LoadHandlers({
      resolveLocaleTag = function(tag)
        resolveCalls = resolveCalls + 1
        return tag or "enUS"
      end,
    })
    handlers.ADDON_LOADED(nil, "OtherAddon")
    Assert.Equal(resolveCalls, 0, "must early-return for foreign addon name")
  end)

  -- HandleOwnedKeyContextEvent -------------------------------------------------

  test("BAG_UPDATE_DELAYED bails out in raid mode", function()
    local calls = 0
    local handlers = LoadHandlers({
      isRaidGroup = function()
        return true
      end,
      handleOwnedKeyRefresh = function()
        calls = calls + 1
      end,
    })
    handlers.BAG_UPDATE_DELAYED(nil)
    Assert.Equal(calls, 0, "owned-key handler must not fire in raid mode")
  end)

  test("BAG_UPDATE_DELAYED runs the owned-key refresh outside raid mode", function()
    local calls = { status = 0, key = 0, notice = 0, dungeon = 0 }
    local handlers = LoadHandlers({
      updateStatusLine = function()
        calls.status = calls.status + 1
      end,
      handleOwnedKeyRefresh = function()
        calls.key = calls.key + 1
      end,
      maybeShowNonMythicDungeonEntryNotice = function()
        calls.notice = calls.notice + 1
      end,
      checkIfEnteredTargetDungeon = function()
        calls.dungeon = calls.dungeon + 1
      end,
    })
    handlers.BAG_UPDATE_DELAYED(nil)
    Assert.Equal(calls.status, 1, "status line must refresh")
    Assert.Equal(calls.key, 1, "owned-key refresh must run")
    Assert.Equal(calls.notice, 1, "non-mythic notice must run")
    Assert.Equal(calls.dungeon, 1, "dungeon-entry check must run")
  end)

  test("CHALLENGE_MODE_MAPS_UPDATE shares the owned-key handler", function()
    local calls = 0
    local handlers = LoadHandlers({
      handleOwnedKeyRefresh = function()
        calls = calls + 1
      end,
    })
    handlers.CHALLENGE_MODE_MAPS_UPDATE(nil)
    Assert.Equal(calls, 1, "shared handler must run for CHALLENGE_MODE_MAPS_UPDATE")
  end)

  test("CONFIRM_SUMMON plays incoming-summon sound outside raid mode", function()
    local calls = 0
    local handlers = LoadHandlers({
      playIncomingSummonSound = function()
        calls = calls + 1
      end,
    })
    handlers.CONFIRM_SUMMON(nil)
    Assert.Equal(calls, 1, "incoming summon confirmation must play the configured summon sound")
  end)

  test("CONFIRM_SUMMON suppresses incoming-summon sound in raid mode", function()
    local calls = 0
    local handlers = LoadHandlers({
      isRaidGroup = function()
        return true
      end,
      playIncomingSummonSound = function()
        calls = calls + 1
      end,
    })
    handlers.CONFIRM_SUMMON(nil)
    Assert.Equal(calls, 0, "incoming summon confirmation must stay silent in raid mode")
  end)

  -- HandleInspectReadyEvent ----------------------------------------------------

  test("INSPECT_READY bails out in raid mode", function()
    local calls = 0
    local handlers = LoadHandlers({
      isRaidGroup = function()
        return true
      end,
      onInspectReady = function()
        calls = calls + 1
        return true
      end,
    })
    handlers.INSPECT_READY(nil, "guid-1")
    Assert.Equal(calls, 0, "must skip inspect handling in raid mode")
  end)

  test("INSPECT_READY bails out when main frame is hidden", function()
    local calls = 0
    local handlers = LoadHandlers({
      isMainFrameShown = function()
        return false
      end,
      onInspectReady = function()
        calls = calls + 1
        return true
      end,
    })
    handlers.INSPECT_READY(nil, "guid-1")
    Assert.Equal(calls, 0, "must skip inspect handling while frame hidden")
  end)

  test("INSPECT_READY refreshes UI when onInspectReady reports change", function()
    local uiCalls = 0
    local handlers = LoadHandlers({
      onInspectReady = function()
        return true
      end,
      updateUI = function()
        uiCalls = uiCalls + 1
      end,
    })
    handlers.INSPECT_READY(nil, "guid-1")
    Assert.Equal(uiCalls, 1, "updateUI must fire when inspect introduced changes")
  end)

  test("INSPECT_READY does not refresh UI when onInspectReady reports no change", function()
    local uiCalls = 0
    local handlers = LoadHandlers({
      onInspectReady = function()
        return false
      end,
      updateUI = function()
        uiCalls = uiCalls + 1
      end,
    })
    handlers.INSPECT_READY(nil, "guid-1")
    Assert.Equal(uiCalls, 0, "updateUI must stay silent when inspect reported no change")
  end)

  -- HandleSpellUpdateCooldownEvent / HandleSpellUpdateChargesEvent -------------

  test("SPELL_UPDATE_COOLDOWN refreshes the teleport button outside raid", function()
    local calls = 0
    local handlers = LoadHandlers({
      updateMPlusTeleportButton = function()
        calls = calls + 1
      end,
    })
    handlers.SPELL_UPDATE_COOLDOWN(nil)
    Assert.Equal(calls, 1, "teleport button must refresh on cooldown event")
  end)

  test("SPELL_UPDATE_CHARGES refreshes cd tracker outside raid", function()
    local calls = 0
    local handlers = LoadHandlers({
      updateCdTracker = function()
        calls = calls + 1
      end,
    })
    handlers.SPELL_UPDATE_CHARGES(nil)
    Assert.Equal(calls, 1, "cd tracker must refresh on charges event")
  end)

  test("SPELL_UPDATE_CHARGES bails out in raid mode", function()
    local calls = 0
    local handlers = LoadHandlers({
      isRaidGroup = function()
        return true
      end,
      updateCdTracker = function()
        calls = calls + 1
      end,
    })
    handlers.SPELL_UPDATE_CHARGES(nil)
    Assert.Equal(calls, 0, "cd tracker must not refresh in raid mode")
  end)

  -- HandleUnitAuraEvent --------------------------------------------------------

  test("UNIT_AURA refreshes cd tracker only for player unit outside raid", function()
    local calls = 0
    local handlers = LoadHandlers({
      updateCdTracker = function()
        calls = calls + 1
      end,
    })
    handlers.UNIT_AURA(nil, "party1")
    Assert.Equal(calls, 0, "non-player unit must be ignored")
    handlers.UNIT_AURA(nil, "player")
    Assert.Equal(calls, 1, "player unit must refresh")
  end)

  test("UNIT_AURA bails out in raid mode even for player unit", function()
    local calls = 0
    local handlers = LoadHandlers({
      isRaidGroup = function()
        return true
      end,
      updateCdTracker = function()
        calls = calls + 1
      end,
    })
    handlers.UNIT_AURA(nil, "player")
    Assert.Equal(calls, 0, "raid mode must veto cd tracker refresh")
  end)

  -- HandleChatMsgAddonEvent ----------------------------------------------------

  test("CHAT_MSG_ADDON bails out in raid mode without calling processAddonMessage", function()
    local calls = 0
    local handlers = LoadHandlers({
      isRaidGroup = function()
        return true
      end,
      processAddonMessage = function()
        calls = calls + 1
        return nil
      end,
    })
    handlers.CHAT_MSG_ADDON(nil, "isiLive", "msg", "PARTY", "Sender-Realm")
    Assert.Equal(calls, 0, "raid mode must skip addon-message processing")
  end)

  test("CHAT_MSG_ADDON forwards combatAnnounce payload to showCombatAnnounce", function()
    local captured
    local handlers = LoadHandlers({
      processAddonMessage = function()
        return { combatAnnounce = { mode = "kick", spellID = 1234 } }
      end,
      showCombatAnnounce = function(info)
        captured = info
      end,
    })
    handlers.CHAT_MSG_ADDON(nil, "isiLive", "msg", "PARTY", "Sender")
    Assert.Equal(captured.mode, "kick", "combat-announce payload must be forwarded")
    Assert.Equal(captured.spellID, 1234, "spell id must be preserved")
  end)

  test("CHAT_MSG_ADDON triggers share-keys cooldown when sendOwnKeystoneToChat succeeds", function()
    local cooldownCalls = 0
    local handlers = LoadHandlers({
      processAddonMessage = function()
        return { shouldShareKeys = true }
      end,
      sendOwnKeystoneToChat = function()
        return true
      end,
      triggerShareKeysCooldown = function()
        cooldownCalls = cooldownCalls + 1
      end,
    })
    handlers.CHAT_MSG_ADDON(nil, "isiLive", "msg", "PARTY", "Sender")
    Assert.Equal(cooldownCalls, 1, "share-keys cooldown must fire when posting succeeded")
  end)

  -- HandlePlayerEnteringWorldEvent: raid early-return + reload-roster --------

  test("PLAYER_ENTERING_WORLD captures wasInPartyInstance and bails out in raid", function()
    local rosterCalls = 0
    local handlers, stub = LoadHandlers({
      isRaidGroup = function()
        return true
      end,
      isInPartyInstance = function()
        return true
      end,
      handleGroupRosterUpdate = function()
        rosterCalls = rosterCalls + 1
      end,
    })
    handlers.PLAYER_ENTERING_WORLD(nil)
    Assert.Equal(rosterCalls, 0, "raid mode must skip the post-reload roster build")
    Assert.Equal(stub.wasInPartyInstance, true, "wasInPartyInstance must be cached for next non-raid call")
  end)

  test("PLAYER_ENTERING_WORLD shows main frame on instance-entry transition", function()
    local visibilityCalls = {}
    local handlers, stub = LoadHandlers({
      isInPartyInstance = function()
        return true
      end,
      isInGroup = function()
        return true
      end,
      setMainFrameVisible = function(visible)
        table.insert(visibilityCalls, visible)
      end,
    })
    stub.wasInPartyInstance = false -- non-nil prior state
    handlers.PLAYER_ENTERING_WORLD(nil)
    Assert.True(#visibilityCalls > 0, "setMainFrameVisible must fire during instance entry")
    Assert.Equal(visibilityCalls[#visibilityCalls], true, "frame must be made visible on instance entry")
  end)

  -- HandlePlayerRegenEnabledEvent: pending-binding + pending-frame paths ------

  test("PLAYER_REGEN_ENABLED applies pending bindings when getPendingBindingApply is true", function()
    local bindingCalls = 0
    local handlers = LoadHandlers({
      getPendingBindingApply = function()
        return true
      end,
      applyHotkeyBindings = function()
        bindingCalls = bindingCalls + 1
      end,
    })
    handlers.PLAYER_REGEN_ENABLED(nil)
    Assert.Equal(bindingCalls, 1, "pending bindings must be applied once combat ends")
  end)

  test("PLAYER_REGEN_ENABLED applies pendingMainFrameWidth when present", function()
    local widthCalls = {}
    local handlers = LoadHandlers({
      getPendingMainFrameWidth = function()
        return 320
      end,
      setMainFrameWidthSafe = function(width)
        table.insert(widthCalls, width)
      end,
    })
    handlers.PLAYER_REGEN_ENABLED(nil)
    Assert.Equal(widthCalls[1], 320, "pending width must be applied once combat ends")
  end)

  test("PLAYER_REGEN_ENABLED bails out in raid mode after combat fade is applied", function()
    local heightCalls = 0
    local handlers = LoadHandlers({
      isRaidGroup = function()
        return true
      end,
      getPendingMainFrameHeight = function()
        heightCalls = heightCalls + 1
        return 100
      end,
    })
    handlers.PLAYER_REGEN_ENABLED(nil)
    Assert.Equal(heightCalls, 0, "raid mode must skip pending-height application")
  end)

  test("PLAYER_REGEN_ENABLED applies pending visibility but vetoes it in raid", function()
    local visibilityCalls = {}
    local handlers = LoadHandlers({
      isRaidGroup = function()
        return true
      end,
      getPendingMainFrameVisible = function()
        return true
      end,
      setMainFrameVisible = function(visible)
        table.insert(visibilityCalls, visible)
      end,
    })
    handlers.PLAYER_REGEN_ENABLED(nil)
    Assert.Equal(visibilityCalls[1], false, "raid mode must clamp pending visibility to false")
  end)

  -- HandleGroupRosterUpdateEvent ---------------------------------------------

  test("GROUP_ROSTER_UPDATE exits test mode when entering a group", function()
    local exits = 0
    local handlers = LoadHandlers({
      isInGroup = function()
        return true
      end,
      isTestMode = function()
        return true
      end,
      exitTestMode = function()
        exits = exits + 1
      end,
    })
    handlers.GROUP_ROSTER_UPDATE(nil)
    Assert.Equal(exits, 1, "test mode must be exited when group joined")
  end)
end
