return function(test, ctx)
  local Assert = ctx.assert
  local LoadAddonModules = ctx.load_modules
  local WithGlobals = ctx.with_globals

  test("Factory primary highlight auto-opens hidden main frame on invite target", function()
    local capturedButtonsUpdate = nil
    local capturedShowArgs = nil

    local globals = {
      IsInGroup = function()
        return true
      end,
      GetTime = function()
        return 0
      end,
      IsiLiveDB = {},
    }

    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_factory_controllers.lua" })

      addon.LFGDetect = {
        GetDetectedMapID = function()
          return 559
        end,
        SetHighlightCallback = function(fn)
          addon._capturedHighlightCallback = fn
        end,
        SetLocaleGetter = function() end,
      }

      local state = {
        mainFrameShown = false,
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
                  UpdateButtons = function(resolvedSpellID, soundContext)
                    capturedButtonsUpdate = {
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
        locale = "enUS",
        GetUnitNameAndRealm = function()
          return nil, nil
        end,
        GetAddonVersionRaw = function()
          return "0.9.154"
        end,
        mainFrame = {
          IsShown = function()
            return state.mainFrameShown == true
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
        SetMainFrameVisible = function(visible, opts)
          state.mainFrameShown = visible == true
          capturedShowArgs = { visible = visible, opts = opts }
          return true
        end,
      }

      addon._FactoryInternal.InitializeFactoryPrimaryControllers(factoryCtx)

      Assert.NotNil(addon._capturedHighlightCallback, "factory must wire the LFG highlight callback")

      factoryCtx.UpdateMPlusTeleportButton("invite")

      Assert.True(state.mainFrameShown, "invite highlight should auto-open the hidden main frame")
      Assert.NotNil(capturedShowArgs, "invite highlight should request the main frame to be shown")
      if capturedShowArgs then
        Assert.Equal(capturedShowArgs.visible, true, "auto-open must request visible=true")
        Assert.Equal(capturedShowArgs.opts.reason, "lfg-highlight", "auto-open must mark the lfg-highlight reason")
        Assert.Equal(capturedShowArgs.opts.skipShowCallbacks, true, "auto-open must skip show callbacks")
      end
      Assert.NotNil(capturedButtonsUpdate, "highlight must still update the teleport buttons")
      if capturedButtonsUpdate then
        Assert.Equal(
          capturedButtonsUpdate.resolvedSpellID,
          1254563,
          "invite highlight must resolve the matching teleport spell"
        )
        Assert.Equal(capturedButtonsUpdate.soundContext, "invite", "invite highlight must preserve sound suppression")
      end
    end)
  end)
end
