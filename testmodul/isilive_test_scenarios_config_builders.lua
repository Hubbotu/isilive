---@diagnostic disable: undefined-global
return function(test, ctx)
  local Assert = ctx.assert
  local LoadAddonModules = ctx.load_modules

  local function LoadBuilders()
    local addon = LoadAddonModules({ "isiLive_config_builders.lua" })
    return addon.ConfigBuilders
  end

  local function MakeSentinel(name)
    return { _sentinel = name }
  end

  test("ConfigBuilders BuildRefreshControllerOpts passes all fields", function()
    local builders = LoadBuilders()
    local ctx_input = {
      isStopped = MakeSentinel("isStopped"),
      isPaused = MakeSentinel("isPaused"),
      isTestMode = MakeSentinel("isTestMode"),
      isTestAllMode = MakeSentinel("isTestAllMode"),
      isInGroup = MakeSentinel("isInGroup"),
      isRosterEmpty = MakeSentinel("isRosterEmpty"),
      triggerGroupRosterUpdate = MakeSentinel("triggerGroupRosterUpdate"),
      refreshTestModeRoster = MakeSentinel("refreshTestModeRoster"),
      forceRefreshSyncState = MakeSentinel("forceRefreshSyncState"),
      sendIsiLiveHello = MakeSentinel("sendIsiLiveHello"),
      sendOwnKeySnapshot = MakeSentinel("sendOwnKeySnapshot"),
      sendOwnBackgroundSnapshot = MakeSentinel("sendOwnBackgroundSnapshot"),
      sendRefreshRequest = MakeSentinel("sendRefreshRequest"),
      queueForceRefreshData = MakeSentinel("queueForceRefreshData"),
      updateUI = MakeSentinel("updateUI"),
      refreshLocalPlayerKey = MakeSentinel("refreshLocalPlayerKey"),
      getActiveChallengeMapID = MakeSentinel("getActiveChallengeMapID"),
      getTime = MakeSentinel("getTime"),
      refreshDebounceSeconds = 5,
    }
    local result = builders.BuildRefreshControllerOpts(ctx_input)
    for key, val in pairs(ctx_input) do
      Assert.Equal(result[key], val, "BuildRefreshControllerOpts must pass through " .. key)
    end
  end)

  test("ConfigBuilders BuildTestModeControllerOpts passes all fields", function()
    local builders = LoadBuilders()
    local ctx_input = {
      getL = MakeSentinel("getL"),
      printFn = MakeSentinel("printFn"),
      getState = MakeSentinel("getState"),
      setState = MakeSentinel("setState"),
      buildDummyRoster = MakeSentinel("buildDummyRoster"),
      setRoster = MakeSentinel("setRoster"),
      setMainFrameVisible = MakeSentinel("setMainFrameVisible"),
      updateUI = MakeSentinel("updateUI"),
      updateLeaderButtons = MakeSentinel("updateLeaderButtons"),
      showCenterNotice = MakeSentinel("showCenterNotice"),
      resetInspectAll = MakeSentinel("resetInspectAll"),
      clearLatestQueueState = MakeSentinel("clearLatestQueueState"),
      updateMPlusTeleportButton = MakeSentinel("updateMPlusTeleportButton"),
      setCenterNoticeVisible = MakeSentinel("setCenterNoticeVisible"),
      hideInviteHint = MakeSentinel("hideInviteHint"),
      triggerGroupRosterUpdate = MakeSentinel("triggerGroupRosterUpdate"),
      captureRioBaselineSnapshot = MakeSentinel("captureRioBaselineSnapshot"),
      clearRioBaselineSnapshot = MakeSentinel("clearRioBaselineSnapshot"),
      enableRioDeltaDisplay = MakeSentinel("enableRioDeltaDisplay"),
    }
    local result = builders.BuildTestModeControllerOpts(ctx_input)
    for key, val in pairs(ctx_input) do
      Assert.Equal(result[key], val, "BuildTestModeControllerOpts must pass through " .. key)
    end
  end)

  test("ConfigBuilders BuildLeaderWatchControllerOpts passes all fields", function()
    local builders = LoadBuilders()
    local ctx_input = {
      isPlayerLeader = MakeSentinel("isPlayerLeader"),
      getWasGroupLeader = MakeSentinel("getWasGroupLeader"),
      setWasGroupLeader = MakeSentinel("setWasGroupLeader"),
      isStopped = MakeSentinel("isStopped"),
      isMainFrameShown = MakeSentinel("isMainFrameShown"),
      showCenterNotice = MakeSentinel("showCenterNotice"),
      printFn = MakeSentinel("printFn"),
      getL = MakeSentinel("getL"),
      updateLeaderButtons = MakeSentinel("updateLeaderButtons"),
    }
    local result = builders.BuildLeaderWatchControllerOpts(ctx_input)
    for key, val in pairs(ctx_input) do
      Assert.Equal(result[key], val, "BuildLeaderWatchControllerOpts must pass through " .. key)
    end
  end)

  test("ConfigBuilders BuildSlashCommandsOpts passes all fields", function()
    local builders = LoadBuilders()
    local ctx_input = {
      commands = MakeSentinel("commands"),
      printFn = MakeSentinel("printFn"),
      getL = MakeSentinel("getL"),
      getState = MakeSentinel("getState"),
      setState = MakeSentinel("setState"),
      triggerGroupRosterUpdate = MakeSentinel("triggerGroupRosterUpdate"),
      toggleStandardTestMode = MakeSentinel("toggleStandardTestMode"),
      enterFullDummyPreview = MakeSentinel("enterFullDummyPreview"),
      setMainFrameVisible = MakeSentinel("setMainFrameVisible"),
      updateLeaderButtons = MakeSentinel("updateLeaderButtons"),
      isPlayerLeader = MakeSentinel("isPlayerLeader"),
      setLanguage = MakeSentinel("setLanguage"),
      teleportDebugController = MakeSentinel("teleportDebugController"),
      queueDebugController = MakeSentinel("queueDebugController"),
      runtimeLogController = MakeSentinel("runtimeLogController"),
      traceChatFrameController = MakeSentinel("traceChatFrameController"),
    }
    local result = builders.BuildSlashCommandsOpts(ctx_input)
    for key, val in pairs(ctx_input) do
      Assert.Equal(result[key], val, "BuildSlashCommandsOpts must pass through " .. key)
    end
  end)

  test("ConfigBuilders BuildGateOpts passes fields and includes allowWhenHidden", function()
    local builders = LoadBuilders()
    local ctx_input = {
      events = MakeSentinel("events"),
      onEvent = MakeSentinel("onEvent"),
      onDispatchError = MakeSentinel("onDispatchError"),
      isStopped = MakeSentinel("isStopped"),
      isPaused = MakeSentinel("isPaused"),
      isTestMode = MakeSentinel("isTestMode"),
      isInCombat = MakeSentinel("isInCombat"),
      isInGroup = MakeSentinel("isInGroup"),
      isInPartyInstance = MakeSentinel("isInPartyInstance"),
      getActiveChallengeMapID = MakeSentinel("getActiveChallengeMapID"),
    }
    local result = builders.BuildGateOpts(ctx_input)
    Assert.Equal(result.events, ctx_input.events, "must pass events")
    Assert.Equal(result.dispatch, ctx_input.onEvent, "must map onEvent to dispatch")
    Assert.Equal(result.onDispatchError, ctx_input.onDispatchError, "must pass onDispatchError")
    Assert.Equal(result.isStopped, ctx_input.isStopped, "must pass isStopped")
    Assert.Equal(result.isPaused, ctx_input.isPaused, "must pass isPaused")
    Assert.Equal(result.isTestMode, ctx_input.isTestMode, "must pass isTestMode")
    Assert.Equal(result.isInCombat, ctx_input.isInCombat, "must pass isInCombat")
    Assert.Equal(result.isInGroup, ctx_input.isInGroup, "must pass isInGroup")
    Assert.Equal(result.isInPartyInstance, ctx_input.isInPartyInstance, "must pass isInPartyInstance")
    Assert.Equal(result.getActiveChallengeMapID, ctx_input.getActiveChallengeMapID, "must pass getActiveChallengeMapID")
    -- Verify allowWhenHidden contains expected events
    Assert.True(result.allowWhenHidden ~= nil, "must have allowWhenHidden")
    Assert.True(result.allowWhenHidden.CHAT_MSG_ADDON == true, "must allow CHAT_MSG_ADDON when hidden")
    Assert.True(result.allowWhenHidden.GROUP_ROSTER_UPDATE == true, "must allow GROUP_ROSTER_UPDATE when hidden")
    Assert.True(result.allowWhenHidden.ZONE_CHANGED == true, "must allow ZONE_CHANGED when hidden")
    Assert.True(result.allowWhenHidden.ZONE_CHANGED_INDOORS == true, "must allow ZONE_CHANGED_INDOORS when hidden")
    Assert.True(result.allowWhenHidden.ZONE_CHANGED_NEW_AREA == true, "must allow ZONE_CHANGED_NEW_AREA when hidden")
    Assert.True(result.allowWhenHidden.BAG_UPDATE_DELAYED == true, "must allow BAG_UPDATE_DELAYED when hidden")
    Assert.True(
      result.allowWhenHidden.CHALLENGE_MODE_MAPS_UPDATE == true,
      "must allow CHALLENGE_MODE_MAPS_UPDATE when hidden"
    )
    Assert.True(
      result.allowWhenHidden.PLAYER_EQUIPMENT_CHANGED == true,
      "must allow PLAYER_EQUIPMENT_CHANGED when hidden"
    )
    Assert.True(
      result.allowWhenHidden.PLAYER_SPECIALIZATION_CHANGED == true,
      "must allow PLAYER_SPECIALIZATION_CHANGED when hidden"
    )
  end)

  test("ConfigBuilders BuildGateOpts does not leak extra ctx fields", function()
    local builders = LoadBuilders()
    local ctx_input = {
      events = "ev",
      onEvent = "disp",
      onDispatchError = "err",
      isStopped = false,
      isPaused = false,
      isTestMode = false,
      isInCombat = false,
      isInGroup = false,
      isInPartyInstance = false,
      getActiveChallengeMapID = "fn",
      extraFieldNotInBuilder = "should_not_appear",
    }
    local result = builders.BuildGateOpts(ctx_input)
    Assert.Equal(result.extraFieldNotInBuilder, nil, "extra fields must not leak into result")
  end)

  test("ConfigBuilders BuildRefreshControllerOpts does not leak extra ctx fields", function()
    local builders = LoadBuilders()
    local ctx_input = {
      isStopped = false,
      extraField = "leak",
    }
    local result = builders.BuildRefreshControllerOpts(ctx_input)
    Assert.Equal(result.extraField, nil, "extra fields must not leak into result")
  end)

  -- =====================================================
  -- BuildSlashCommandsOpts inner closures
  -- =====================================================

  local function BuildSlashCtx(overrides)
    overrides = overrides or {}
    return {
      commands = {},
      printFn = function() end,
      getL = function()
        return {}
      end,
      mainUI = overrides.mainUI,
      mainFrame = overrides.mainFrame,
      panelUI = overrides.panelUI,
      settingsPanel = overrides.settingsPanel,
    }
  end

  test("ConfigBuilders slash getMainFrameLocked reads from mainUI when GetDragLocked exists", function()
    local builders = LoadBuilders()
    local mainUI = {
      GetDragLocked = function()
        return true
      end,
    }
    local opts = builders.BuildSlashCommandsOpts(BuildSlashCtx({ mainUI = mainUI }))
    local WithGlobals = ctx.with_globals
    WithGlobals({}, function()
      Assert.Equal(opts.getMainFrameLocked(), true, "mainUI.GetDragLocked must win over DB lookup")
    end)
  end)

  test("ConfigBuilders slash getMainFrameLocked falls back to IsiLiveDB.lockMainFramePosition", function()
    local builders = LoadBuilders()
    local opts = builders.BuildSlashCommandsOpts(BuildSlashCtx())
    local WithGlobals = ctx.with_globals
    WithGlobals({ IsiLiveDB = { lockMainFramePosition = false } }, function()
      Assert.Equal(opts.getMainFrameLocked(), false, "explicit false in DB must unlock")
    end)
    WithGlobals({ IsiLiveDB = {} }, function()
      Assert.Equal(opts.getMainFrameLocked(), true, "missing setting must default to locked")
    end)
  end)

  test("ConfigBuilders slash setMainFrameLocked writes DB + forwards to mainUI", function()
    local builders = LoadBuilders()
    local seenLocked
    local mainUI = {
      SetDragLocked = function(v)
        seenLocked = v
      end,
    }
    local opts = builders.BuildSlashCommandsOpts(BuildSlashCtx({ mainUI = mainUI }))
    local WithGlobals = ctx.with_globals
    local db = {}
    WithGlobals({ IsiLiveDB = db }, function()
      opts.setMainFrameLocked(true)
      Assert.Equal(db.lockMainFramePosition, true)
      Assert.Equal(seenLocked, true)
      opts.setMainFrameLocked(false)
      Assert.Equal(db.lockMainFramePosition, false)
      Assert.Equal(seenLocked, false)
    end)
  end)

  test("ConfigBuilders slash setMainFrameLocked seeds IsiLiveDB when missing", function()
    local builders = LoadBuilders()
    local opts = builders.BuildSlashCommandsOpts(BuildSlashCtx())
    local WithGlobals = ctx.with_globals
    WithGlobals({}, function()
      local previous = rawget(_G, "IsiLiveDB")
      rawset(_G, "IsiLiveDB", nil)
      opts.setMainFrameLocked(true)
      Assert.NotNil(rawget(_G, "IsiLiveDB"), "missing DB must be seeded lazily")
      rawset(_G, "IsiLiveDB", previous)
    end)
  end)

  test("ConfigBuilders slash resetMainFramePosition rewrites scale/alpha and calls mainUI.ResetPosition", function()
    local builders = LoadBuilders()
    local resetCalls = 0
    local scaleCalls = 0
    local lastBgAlpha = nil
    local mainUI = {
      ResetPosition = function()
        resetCalls = resetCalls + 1
      end,
    }
    local mainFrame = {}
    function mainFrame:SetScale(s)
      scaleCalls = scaleCalls + 1
      self._scale = s
    end
    function mainFrame:SetBackdropColor(_r, _g, _b, a)
      lastBgAlpha = a
    end
    local refreshCalls = 0
    local settingsPanel = {
      canvas = { SetBackdropColor = function() end },
      Refresh = function()
        refreshCalls = refreshCalls + 1
      end,
    }
    local panelUI = {
      panelFrame = { SetBackdropColor = function() end },
    }
    local builderCtx = BuildSlashCtx({
      mainUI = mainUI,
      mainFrame = mainFrame,
      settingsPanel = settingsPanel,
      panelUI = panelUI,
    })
    local opts = builders.BuildSlashCommandsOpts(builderCtx)
    local WithGlobals = ctx.with_globals
    local db = {}
    WithGlobals({ IsiLiveDB = db }, function()
      opts.resetMainFramePosition()
    end)
    Assert.Equal(db.uiScale, 1.0, "uiScale must be reset to 1.0")
    Assert.Equal(type(db.bgAlpha), "number", "bgAlpha must be reset to a numeric default")
    Assert.Equal(scaleCalls, 1, "mainFrame:SetScale(1.0) must be called")
    Assert.Equal(mainFrame._scale, 1.0)
    Assert.Equal(resetCalls, 1, "mainUI.ResetPosition must fire")
    Assert.Equal(lastBgAlpha, db.bgAlpha, "backdrop alpha must match the reset bgAlpha")
    Assert.Equal(refreshCalls, 1, "settingsPanel.Refresh must be called to repaint sliders")
  end)

  test("ConfigBuilders slash resetMainFramePosition seeds IsiLiveDB when missing and tolerates missing UI refs", function()
    local builders = LoadBuilders()
    local opts = builders.BuildSlashCommandsOpts(BuildSlashCtx())
    local WithGlobals = ctx.with_globals
    WithGlobals({}, function()
      local previous = rawget(_G, "IsiLiveDB")
      rawset(_G, "IsiLiveDB", nil)
      -- Must not raise even without mainUI / mainFrame / panelUI / settingsPanel.
      opts.resetMainFramePosition()
      Assert.NotNil(rawget(_G, "IsiLiveDB"))
      Assert.Equal(rawget(_G, "IsiLiveDB").uiScale, 1.0)
      rawset(_G, "IsiLiveDB", previous)
    end)
  end)
end
