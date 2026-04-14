return function(test, ctx)
  local Assert = ctx.assert
  local LoadAddonModules = ctx.load_modules
  local WithGlobals = ctx.with_globals

  local function RunHighlightPriorityScenario(opts, assertFn)
    local captured = { buttonsUpdate = nil }

    WithGlobals({
      IsInGroup = function()
        return true
      end,
      GetTime = function()
        return 0
      end,
      IsiLiveDB = {},
    }, function()
      local addon = LoadAddonModules({ "isiLive_factory_controllers.lua" })

      addon.LFGDetect = {
        GetDetectedMapID = function()
          return opts.detectedMapID
        end,
        SetHighlightCallback = function(fn)
          addon._capturedHighlightCallback = fn
        end,
        SetLocaleGetter = function() end,
      }

      local factoryCtx = {
        modules = {
          controllerInit = {
            CreateControllers = function()
              return {
                highlightController = {
                  ResolveActiveTeleportSpellID = function()
                    return opts.highlightSpellID
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
                  UpdateButtons = function(resolvedSpellID, soundContext)
                    captured.buttonsUpdate = {
                      resolvedSpellID = resolvedSpellID,
                      soundContext = soundContext,
                    }
                  end,
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
              local map = opts.teleportSpellForMapID or {}
              return map[mapID]
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
              return ""
            end,
            GetDungeonShortCode = function()
              return ""
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
          GetActiveJoinedKeyMapID = function()
            return nil
          end,
        },
        locale = "enUS",
        GetUnitNameAndRealm = function()
          return nil, nil
        end,
        GetAddonVersionRaw = function()
          return "0.9.158"
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
          return 0
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
      assertFn(factoryCtx, captured)
    end)
  end

  test("Factory primary highlight prefers LFG detected mapID over peer-synced resolver", function()
    RunHighlightPriorityScenario({
      detectedMapID = 559,
      highlightSpellID = 424197,
      teleportSpellForMapID = { [559] = 1254563 },
    }, function(factoryCtx, captured)
      factoryCtx.UpdateMPlusTeleportButton("invite")
      Assert.NotNil(captured.buttonsUpdate, "UpdateButtons must be called")
      Assert.Equal(
        captured.buttonsUpdate.resolvedSpellID,
        1254563,
        "LFG detected mapID must outrank peer-synced resolver spell"
      )
      Assert.Equal(captured.buttonsUpdate.soundContext, "invite", "soundContext must still propagate")
    end)
  end)

  test("Factory primary highlight uses LFG detected mapID when no other resolver is active", function()
    RunHighlightPriorityScenario({
      detectedMapID = 557,
      highlightSpellID = nil,
      teleportSpellForMapID = { [557] = 445441 },
    }, function(factoryCtx, captured)
      factoryCtx.UpdateMPlusTeleportButton("invite")
      Assert.NotNil(captured.buttonsUpdate, "UpdateButtons must be called")
      Assert.Equal(
        captured.buttonsUpdate.resolvedSpellID,
        445441,
        "LFG detected mapID must be the sole resolved spell when nothing else is active"
      )
    end)
  end)

  test("Factory primary highlight falls back to peer-synced resolver when LFGDetect is empty", function()
    RunHighlightPriorityScenario({
      detectedMapID = nil,
      highlightSpellID = 445444,
      teleportSpellForMapID = {},
    }, function(factoryCtx, captured)
      factoryCtx.UpdateMPlusTeleportButton("queue")
      Assert.NotNil(captured.buttonsUpdate, "UpdateButtons must be called")
      Assert.Equal(
        captured.buttonsUpdate.resolvedSpellID,
        445444,
        "peer-synced resolver must still drive the highlight when no LFG target is detected"
      )
      Assert.Equal(captured.buttonsUpdate.soundContext, "queue", "soundContext must propagate on queue updates")
    end)
  end)
end
