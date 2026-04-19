local function RegisterFactoryPrimaryGroupSettleTests(test, Assert, LoadAddonModules, WithGlobals)
  test("Factory primary wires LFG group-settle diagnostics into the runtime log", function()
    local runtimeLogs = {}

    local globals = {
      IsInGroup = function()
        return true
      end,
      GetTime = function()
        return 12.5
      end,
      IsiLiveDB = {
        runtimeLogEnabled = true,
      },
    }

    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_factory_controllers.lua" })

      addon.LFGDetect = {
        GetDetectedMapID = function()
          return 559
        end,
        SetHighlightCallback = function() end,
        SetGroupRosterTraceLogger = function(fn)
          addon._capturedGroupRosterTraceLogger = fn
        end,
      }

      local factoryCtx = {
        modules = {
          controllerInit = {
            CreateControllers = function()
              return {
                highlightController = {
                  ResolveActiveTeleportSpellID = function()
                    return nil
                  end,
                  ResolveJoinedKeyMapID = function()
                    return nil
                  end,
                },
                rosterPanelController = {
                  ApplyLocalization = function() end,
                  GetRefreshButton = function()
                    return {}
                  end,
                  GetCountdownCancelButton = function()
                    return {}
                  end,
                  GetStatusLine = function()
                    return {}
                  end,
                  SetCollapseChangedHandler = function() end,
                  SetLayoutChangedHandler = function() end,
                  GetLayoutMode = function()
                    return "expanded"
                  end,
                  IsCollapsed = function()
                    return false
                  end,
                },
                teleportUIController = {
                  UpdateButtons = function() end,
                  BuildButtons = function() end,
                  GetButtons = function()
                    return {}
                  end,
                  SetLayoutMode = function() end,
                  SetVisible = function() end,
                },
                keySyncController = {
                  MarkIsiLiveUser = function() end,
                  UnitHasIsiLive = function()
                    return false
                  end,
                  RegisterIsiLiveSyncPrefix = function() end,
                  SendIsiLiveHello = function() end,
                  SendRefreshRequest = function() end,
                  SendLibKeystonePartyData = function() end,
                  GetOwnedKeystoneSnapshot = function() end,
                  SendOwnKeySnapshot = function() end,
                  SendOwnBackgroundSnapshot = function() end,
                  SendRefreshResponse = function() end,
                  ApplyKnownKeyToRosterEntry = function()
                    return false
                  end,
                  ForceRefreshSyncState = function() end,
                  RefreshLocalPlayerKey = function()
                    return false
                  end,
                  ResolveActiveKeyOwnerUnit = function()
                    return nil
                  end,
                },
                statsController = {
                  GetPlayerLastRunDps = function() end,
                  RecordRun = function() end,
                },
                recordRun = function() end,
              }
            end,
          },
          teleport = {
            ResolveTeleportSpellIDByMapID = function(mapID)
              if mapID == 559 then
                return 1254563
              end
              return nil
            end,
            ResolveMapIDByActivityID = function()
              return nil
            end,
            ResolveMapIDBySpellID = function()
              return nil
            end,
            ResolveMapIDsBySpellID = function()
              return {}
            end,
            BuildTeleportEntries = function()
              return {}
            end,
            GetDungeonName = function()
              return "Nexus-Point Xenas"
            end,
            GetDungeonShortCode = function()
              return "NPX"
            end,
            GetTeleportInfoByMapID = function()
              return nil
            end,
          },
          sync = {
            SendShareKeysRequest = function() end,
            IsUserKnown = function()
              return false
            end,
          },
          keySync = {},
          highlight = {},
          rosterPanel = {},
          teleportUI = {},
          stats = {},
          locale = {
            GetLanguageTooltipMarkup = function()
              return ""
            end,
          },
          roster = {
            BuildOrderedRoster = function()
              return {}
            end,
            HasFullSync = function()
              return false
            end,
            BuildDisplayData = function()
              return {}
            end,
          },
        },
        runtimeState = {
          IsStopped = function()
            return false
          end,
          IsPaused = function()
            return false
          end,
          GetLatestQueueState = function()
            return nil, nil, nil, nil
          end,
        },
        runtimeLogController = {
          Log = function(message)
            table.insert(runtimeLogs, message)
          end,
        },
        locale = "enUS",
        GetUnitNameAndRealm = function()
          return nil, nil
        end,
        GetAddonVersionRaw = function()
          return "0.9.154"
        end,
        mainFrame = {
          IsShown = function()
            return true
          end,
        },
        mainUI = {},
        GetL = function()
          return {}
        end,
        IsPlayerLeader = function()
          return true
        end,
        GetUnitRio = function()
          return nil
        end,
        SetMainFrameHeightSafe = function() end,
        SetMainFrameWidthSafe = function() end,
        MIN_FRAME_HEIGHT = 100,
        TruncateName = function(value)
          return value
        end,
        GetShortSpecLabel = function(value)
          return value
        end,
        GetLanguageTooltipMarkup = function()
          return ""
        end,
        GetRioDeltaForRosterInfo = function()
          return nil
        end,
        ResolveActiveKeyOwnerUnit = function()
          return nil
        end,
        ResolveStatusTargetMapID = function()
          return nil
        end,
        IsReadyCheckActive = function()
          return false
        end,
        GetReadyCheckReadyUntil = function()
          return nil
        end,
        GetReadyCheckDeclinedUntil = function()
          return nil
        end,
        ApplySecureSpellToButton = function() end,
        IsSpellKnownSafe = function()
          return false
        end,
        GetTeleportCooldownRemaining = function()
          return 0
        end,
        FormatCooldownSeconds = function(value)
          return tostring(value or 0)
        end,
        GetSpellCooldownSafe = function()
          return 0, 0, true
        end,
        ApplyCooldownFrameSafe = function() end,
        GetTeleportEmptyStateText = function()
          return ""
        end,
        GetTime = function()
          return 12.5
        end,
        shareKeysDebounceSeconds = 30,
        sendShareKeysRequest = function() end,
        isSyncUserKnown = function()
          return false
        end,
        SetMainFrameVisible = function()
          return true
        end,
      }

      addon._FactoryInternal.InitializeFactoryPrimaryControllers(factoryCtx)

      Assert.NotNil(addon._capturedGroupRosterTraceLogger, "factory must wire the LFG group-settle diagnostic logger")

      addon._capturedGroupRosterTraceLogger({
        event = "GROUP_ROSTER_UPDATE",
        inGroup = true,
        members = 5,
        detectedBefore = 559,
        detectedAfter = 559,
        pendingAccept = nil,
        latestQueueMap = nil,
      })

      Assert.Equal(#runtimeLogs, 1, "group-settle diagnostic logger must append one runtime log entry")
      Assert.True(runtimeLogs[1]:find("[LFG_GROUP5]", 1, true) ~= nil, "runtime log must use the LFG_GROUP5 tag")
      Assert.True(
        runtimeLogs[1]:find("detected_before=559", 1, true) ~= nil,
        "runtime log must include the detected map before the roster settle"
      )
      Assert.True(
        runtimeLogs[1]:find("resolved_spell=1254563", 1, true) ~= nil,
        "runtime log must include the resolved teleport spell for the detected map"
      )
    end)
  end)
end

return function(test, ctx)
  local Assert = ctx.assert
  local LoadAddonModules = ctx.load_modules
  local WithGlobals = ctx.with_globals

  RegisterFactoryPrimaryGroupSettleTests(test, Assert, LoadAddonModules, WithGlobals)
end
