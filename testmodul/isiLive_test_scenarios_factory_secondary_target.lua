return function(test, ctx)
  local Assert = ctx.assert
  local WithGlobals = ctx.with_globals
  local LoadAddonModules = ctx.load_modules

  local chunk, loadErr = loadfile("testmodul/isilive_test_scenarios_factory_secondary.lua")
  if not chunk then
    error(string.format("cannot load factory secondary scenario helper: %s", tostring(loadErr)))
  end

  local helperAddon = {}
  local ok, runErr = pcall(chunk, "isiLive", helperAddon)
  if not ok then
    error(string.format("cannot execute factory secondary scenario helper: %s", tostring(runErr)))
  end

  local factorySecondaryTests = helperAddon._FactorySecondaryTests or {}
  local BuildFactorySecondaryControllerState = factorySecondaryTests.BuildFactorySecondaryControllerState
  if type(BuildFactorySecondaryControllerState) ~= "function" then
    error("Factory secondary test helper is unavailable")
  end

  test("Factory target dungeon clear waits for actual player map entry", function()
    local clearCalls = 0
    local updateCalls = 0
    local latestQueueClears = 0
    local currentMapID = nil

    local state = BuildFactorySecondaryControllerState(WithGlobals, LoadAddonModules, {
      mainFrameShown = true,
    })

    state.ctx.addonTable.LFGDetect = {
      ClearAllState = function()
        clearCalls = clearCalls + 1
      end,
    }
    state.ctx.ResolveStatusTargetMapID = function()
      return 557
    end
    state.ctx.ClearLatestQueueTarget = function()
      latestQueueClears = latestQueueClears + 1
    end
    state.ctx.UpdateMPlusTeleportButton = function()
      updateCalls = updateCalls + 1
    end

    WithGlobals({
      UnitExists = function()
        return true
      end,
      C_Map = {
        GetBestMapForUnit = function()
          return currentMapID
        end,
      },
      C_ChallengeMode = {
        GetActiveChallengeMapID = function()
          return 557
        end,
      },
    }, function()
      state.ctx.CheckIfEnteredTargetDungeon()
      Assert.Equal(clearCalls, 0, "challenge map alone must not clear the target highlight")
      Assert.Equal(latestQueueClears, 0, "challenge map alone must not clear the latest queue target")
      Assert.Equal(updateCalls, 0, "challenge map alone must not refresh the teleport button")

      currentMapID = 557
      state.ctx.CheckIfEnteredTargetDungeon()
      Assert.Equal(clearCalls, 1, "actual player map entry must clear the target highlight once")
      Assert.Equal(latestQueueClears, 1, "actual player map entry must clear the latest queue target once")
      Assert.Equal(updateCalls, 1, "actual player map entry must refresh the teleport button once")
    end)
  end)
end
