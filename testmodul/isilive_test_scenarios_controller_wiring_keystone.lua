---@diagnostic disable: undefined-global

-- Branch-coverage scenarios for the sendOwnKeystoneToChat closure built
-- inside factory/isiLive_controller_wiring.lua's
-- BuildEventHandlersDepsFromContext. The existing
-- isilive_test_scenarios_controller_wiring_events.lua scenarios stop
-- at "builds deps from ctx" — the ~100 lines of the keystone-chat
-- closure stay untested. This file drives every branch by capturing
-- the config that the wiring passes to eventHandlersModule.CreateController
-- and then calling config.sendOwnKeystoneToChat directly under
-- per-test global / ContextHelpers stubs.

local function Noop() end

local function CaptureEventModule()
  local captured
  local module = {
    CreateController = function(config)
      captured = config
      return { Handle = Noop }
    end,
  }
  return module, function()
    return captured
  end
end

-- Build a ctx skeleton that satisfies every RequireFunction /
-- RequireTable in BuildEventHandlersBaseConfig + ExtendEventHandlersConfig
-- with no-op functions, then layer the per-test fields on top. The
-- runtime-log controller and getOwnedKeystoneSnapshot are exposed as
-- explicit fields so each test can swap them in.
local function BuildKeystoneCtx(overrides)
  local ctx = {
    addonName = "isiLive",
    isRosterCollapsed = Noop,
    defaultLocale = "enUS",
    locales = { enUS = {} },
    resolveLocaleTag = Noop,
    setLocaleTable = Noop,
    isInGroup = function()
      return false
    end,
    isInChallengeMode = Noop,
    isRaidGroup = Noop,
    isNegativeApplicationStatusEvent = Noop,
    getNormalizedActiveEntryInfo = Noop,
    sendIsiLiveHello = Noop,
    sendOwnKeySnapshot = Noop,
    sendOwnBackgroundSnapshot = Noop,
    sendRefreshResponse = Noop,
    ensureQueueDebugStorage = Noop,
    setQueueDebugEnabled = Noop,
    registerIsiLiveSyncPrefix = Noop,
    applyHotkeyBindings = Noop,
    startBindingWatchdog = Noop,
    getUnitNameAndRealm = Noop,
    markIsiLiveUser = Noop,
    applyKnownKeyToRosterEntry = Noop,
    isTestMode = Noop,
    isTestAllMode = Noop,
    setPendingQueueJoinInfo = Noop,
    setPendingPostChallengeRefresh = Noop,
    getActiveJoinedKeyMapID = Noop,
    setActiveJoinedKeyMapID = Noop,
    getPendingBindingApply = Noop,
    getRoster = function()
      return {}
    end,
    getOwnedKeystoneSnapshot = function()
      return { mapID = 2649, level = 12 }
    end,
    getL = function()
      return {}
    end,
    locale = "enUS",
    modules = {
      teleport = {
        GetDungeonShortCode = function()
          return "PSF"
        end,
      },
    },
    mainFrame = {
      IsShown = function()
        return false
      end,
    },
    mainUI = {
      GetPendingHeight = Noop,
      GetPendingWidth = Noop,
      GetPendingVisible = Noop,
    },
    applySecureSpellToButton = Noop,
    groupController = { HandleGroupRosterUpdate = Noop },
    exitTestMode = Noop,
    clearLatestQueueTarget = Noop,
    updateMPlusTeleportButton = Noop,
    captureQueueJoinCandidate = Noop,
    updateUI = Noop,
    refreshReadyCheckUI = Noop,
    setMainFrameVisible = Noop,
    updateLeaderButtons = Noop,
    updateStatusLine = Noop,
    applyLocalizationToUI = Noop,
    restoreLayoutState = Noop,
    updateCountdownCancelButton = Noop,
    checkIfEnteredTargetDungeon = Noop,
    setMainFrameHeightSafe = Noop,
    setMainFrameWidthSafe = Noop,
    sync = {
      ProcessAddonMessage = Noop,
      GetPrefix = function()
        return "ISILIVE"
      end,
      IsUserKnown = function()
        return false
      end,
    },
    runFullRefresh = Noop,
    getAddonVersionRaw = function()
      return "0.9.180"
    end,
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
  local LoadAddonModules = ctx.load_modules
  local WithGlobals = ctx.with_globals

  -- Helper: load module, install ContextHelpers / globals, build the
  -- controller, return the captured deps (with sendOwnKeystoneToChat).
  -- We monkey-patch ControllerWiring.CreateEventHandlersController to
  -- intercept the deps table that BuildEventHandlersDepsFromContext
  -- produces — sendOwnKeystoneToChat is a deps field, not a config
  -- field, so a CaptureEventModule that only sees config can't reach
  -- it. The mocked eventHandlersModule still no-ops the inner
  -- CreateController call so the test setup never has to satisfy the
  -- full required-deps surface.
  local function WireKeystone(opts)
    opts = opts or {}
    local addon = LoadAddonModules({ "isiLive_controller_wiring.lua" })
    addon.ContextHelpers.BuildOwnKeystoneAnnounceLine = opts.BuildOwnKeystoneAnnounceLine
      or function()
        return "[KEY] PSF +12"
      end
    addon.ContextHelpers.SendPartyChatMessage = opts.SendPartyChatMessage
    local module = CaptureEventModule()
    local capturedDeps
    local origCreateEH = addon.ControllerWiring.CreateEventHandlersController
    addon.ControllerWiring.CreateEventHandlersController = function(_module, deps)
      capturedDeps = deps
      return { Handle = Noop }
    end
    local controllerCtx = BuildKeystoneCtx(opts.ctxOverrides)
    addon.ControllerWiring.CreateEventHandlersControllerFromContext(module, controllerCtx)
    addon.ControllerWiring.CreateEventHandlersController = origCreateEH
    return capturedDeps, controllerCtx
  end

  -- Cooldown short-circuit -----------------------------------------------------

  test("sendOwnKeystoneToChat returns false within 30s of the previous post", function()
    WithGlobals({
      GetTime = function()
        return 1000
      end,
    }, function()
      local config, controllerCtx = WireKeystone({})
      controllerCtx._lastKeystoneChatAt = 990 -- 10s ago < 30s cooldown
      Assert.False(config.sendOwnKeystoneToChat(), "must abort during cooldown window")
    end)
  end)

  -- No-line abort --------------------------------------------------------------

  test("sendOwnKeystoneToChat aborts when BuildOwnKeystoneAnnounceLine returns nil", function()
    local logCalls = {}
    WithGlobals({
      GetTime = function()
        return 1000
      end,
    }, function()
      local config = WireKeystone({
        BuildOwnKeystoneAnnounceLine = function()
          return nil
        end,
        ctxOverrides = {
          runtimeLogController = {
            Log = function(message)
              table.insert(logCalls, message)
            end,
            Logf = Noop,
            TraceDeep = Noop,
          },
        },
      })
      Assert.False(config.sendOwnKeystoneToChat(), "no line must yield false")
    end)

    local sawAbort = false
    for _, message in ipairs(logCalls) do
      if message == "[KEYSTONE] aborted reason=no_line" then
        sawAbort = true
      end
    end
    Assert.True(sawAbort, "no_line abort reason must be logged")
  end)

  test("sendOwnKeystoneToChat aborts when BuildOwnKeystoneAnnounceLine returns empty string", function()
    WithGlobals({
      GetTime = function()
        return 1000
      end,
    }, function()
      local config = WireKeystone({
        BuildOwnKeystoneAnnounceLine = function()
          return ""
        end,
      })
      Assert.False(config.sendOwnKeystoneToChat(), "empty line must yield false")
    end)
  end)

  -- In-group success path via ContextHelpers.SendPartyChatMessage --------------

  test("sendOwnKeystoneToChat sends via ContextHelpers.SendPartyChatMessage when in group", function()
    local sentLines = {}
    WithGlobals({
      GetTime = function()
        return 5000
      end,
    }, function()
      local config, controllerCtx = WireKeystone({
        SendPartyChatMessage = function(line)
          table.insert(sentLines, line)
          return true
        end,
        ctxOverrides = {
          isInGroup = function()
            return true
          end,
        },
      })
      Assert.True(config.sendOwnKeystoneToChat(), "successful send must return true")
      Assert.Equal(controllerCtx._lastKeystoneChatAt, 5000, "successful send must update _lastKeystoneChatAt")
    end)
    Assert.Equal(sentLines[1], "[KEY] PSF +12", "line must be forwarded to SendPartyChatMessage")
  end)

  -- In-group failure path: SendPartyChatMessage returns false -> log + return false

  test("sendOwnKeystoneToChat logs send_failed when ContextHelpers.SendPartyChatMessage returns false", function()
    local logCalls = {}
    WithGlobals({
      GetTime = function()
        return 5000
      end,
    }, function()
      local config = WireKeystone({
        SendPartyChatMessage = function()
          return false
        end,
        ctxOverrides = {
          isInGroup = function()
            return true
          end,
          runtimeLogController = {
            Log = function(message)
              table.insert(logCalls, message)
            end,
            Logf = Noop,
            TraceDeep = Noop,
          },
        },
      })
      Assert.False(config.sendOwnKeystoneToChat(), "failed send must return false")
    end)

    local sawAbort = false
    for _, message in ipairs(logCalls) do
      if message == "[KEYSTONE] aborted reason=send_failed" then
        sawAbort = true
      end
    end
    Assert.True(sawAbort, "send_failed abort reason must be logged")
  end)

  -- Solo path: not in group, _G.print available --------------------------------

  test("sendOwnKeystoneToChat falls back to print when player is not in a group", function()
    local printed = {}
    WithGlobals({
      GetTime = function()
        return 5000
      end,
      print = function(line)
        table.insert(printed, line)
      end,
    }, function()
      local config, controllerCtx = WireKeystone({})
      Assert.True(config.sendOwnKeystoneToChat(), "solo print must report success")
      Assert.Equal(controllerCtx._lastKeystoneChatAt, 5000, "successful solo print must update _lastKeystoneChatAt")
    end)
    Assert.Equal(printed[1], "[KEY] PSF +12", "line must be forwarded to print")
  end)

  -- Solo path: print missing -> false ------------------------------------------

  test("sendOwnKeystoneToChat returns false when neither party chat nor print is available", function()
    WithGlobals({
      GetTime = function()
        return 5000
      end,
      -- Replace _G.print with a non-function value so the closure's
      -- type(printFn) == "function" guard rejects it. (Lua always has
      -- a global `print`; we have to actively neuter it.)
      print = false,
    }, function()
      local config = WireKeystone({})
      Assert.False(config.sendOwnKeystoneToChat(), "no print must yield false")
    end)
  end)

  -- runFullRefresh closure: present-controller and missing-controller paths ---

  test("runFullRefresh closure delegates to ctx.refreshController.RunFullRefresh when present", function()
    local runs = 0
    local config = WireKeystone({
      ctxOverrides = {
        refreshController = {
          RunFullRefresh = function()
            runs = runs + 1
            return true
          end,
        },
      },
    })
    Assert.True(config.runFullRefresh() == true, "delegated full refresh must report true")
    Assert.Equal(runs, 1, "RunFullRefresh must be invoked exactly once")
  end)

  test("runFullRefresh closure returns false when ctx.refreshController is missing", function()
    local config = WireKeystone({})
    Assert.False(config.runFullRefresh(), "missing refresh controller must yield false")
  end)
end
