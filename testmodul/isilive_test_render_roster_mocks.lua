-- Shared frame-mock + state-builder helpers for simulators that drive the
-- real RenderRosterImpl from `ui/isiLive_roster_panel_render.lua`.
--
-- Sims load this with the same `LoadLocal(path)` pattern they use for
-- `testmodul/isilive_test_harness.lua`:
--
--   local RosterMocks = LoadLocal("testmodul/isilive_test_render_roster_mocks.lua")
--
-- What's shared and what isn't:
--
--   * `MakeFontStringMock` — identical NoOp font string in every sim.
--   * `MakeFrameMock` — identical NoOp frame; sim-specific texture mocks
--     can be wired through `opts.makeTexture` so e.g. an instrumented
--     readyCheckBackground stays sim-local.
--   * `BuildDefaultRenderState` — the ~50-field state object that
--     `RenderRosterImpl` reads. Every field has a safe default; sims
--     override only the closures that drive their scenario (e.g.
--     `isReadyCheckActive`, `getReadyCheckReadyUntil`, `getTime`).
--
-- What stays sim-local (deliberately):
--
--   * Background mocks with instrumentation (frameLog, color recording).
--   * Role-button mocks with attribute capture.
--   * `BuildMemberRows` — different sims need different per-row wiring
--     (roleButton present vs. nil, instrumented bg vs. NoOp bg).
---@diagnostic disable: undefined-global
local M = {}

local function NoOp() end
M.NoOp = NoOp

function M.MakeFontStringMock()
  return {
    SetText = NoOp,
    SetTextColor = NoOp,
    SetPoint = NoOp,
    SetWidth = NoOp,
    SetJustifyH = NoOp,
    Show = NoOp,
    Hide = NoOp,
  }
end

--- Builds a generic frame mock with all the methods RenderRosterImpl /
--- CreateMemberRow / panel chrome ever call.
--- @param opts table|nil  optional overrides:
---   - makeTexture: function() returning the texture mock that
---     `frame:CreateTexture()` should return. Defaults to a NoOp texture.
function M.MakeFrameMock(opts)
  opts = opts or {}
  local makeTexture = opts.makeTexture
  local mock = {}
  mock.Show = NoOp
  mock.Hide = NoOp
  mock.SetPoint = NoOp
  mock.SetSize = NoOp
  mock.SetAllPoints = NoOp
  mock.GetFrameLevel = function()
    return 1
  end
  mock.SetFrameLevel = NoOp
  mock.CreateTexture = function()
    if makeTexture then
      return makeTexture()
    end
    return {
      Show = NoOp,
      Hide = NoOp,
      SetAllPoints = NoOp,
      SetColorTexture = NoOp,
      SetTexture = NoOp,
      SetTexCoord = NoOp,
      SetVertexColor = NoOp,
      SetDesaturated = NoOp,
    }
  end
  mock.CreateFontString = M.MakeFontStringMock
  mock.SetScript = NoOp
  mock.HookScript = NoOp
  mock.RegisterEvent = NoOp
  mock.UnregisterEvent = NoOp
  mock.EnableMouse = NoOp
  return mock
end

--- Builds the state table RenderRosterImpl reads from. Every field has a
--- safe default (no-op closure or empty value); the caller overrides only
--- the fields that drive their scenario.
--- @param memberRows table  the row mocks the sim already built.
--- @param addonRoster table  the loaded addon table from `Harness.LoadAddonModules({...})`.
---                            Used to wire `buildOrderedRoster` / `buildDisplayData`.
--- @param overrides table|nil  optional state-field overrides (closures, ints, etc.).
--- @return table state
function M.BuildDefaultRenderState(memberRows, addonRoster, overrides)
  overrides = overrides or {}
  local state = {
    memberRows = memberRows,
    mainFrame = M.MakeFrameMock(),
    shareKeysButton = (function()
      local btn = M.MakeFrameMock()
      btn.SetEnabled = NoOp
      btn.SetAlpha = NoOp
      btn.SetShareKeysAvailable = NoOp
      return btn
    end)(),
    rosterTooltip = nil,
    setMainFrameHeightSafe = NoOp,
    minFrameHeight = 100,
    raidNoticeLabel = nil,
    buildOrderedRoster = addonRoster.Roster.BuildOrderedRoster,
    rolePriority = { TANK = 1, HEALER = 2, DAMAGER = 3, NONE = 4 },
    unitPriority = { player = 1, party1 = 2, party2 = 3, party3 = 4, party4 = 5 },
    resolveActiveKeyOwnerUnit = function()
      return nil
    end,
    isReadyCheckActive = function()
      return false
    end,
    resolveTargetMapID = function()
      return nil
    end,
    buildDisplayData = addonRoster.Roster.BuildDisplayData,
    truncateName = function(text)
      return text
    end,
    getShortSpecLabel = function(text)
      return text
    end,
    getLanguageFlagMarkup = function()
      return ""
    end,
    getDungeonShortCode = function()
      return nil
    end,
    getDungeonName = function()
      return nil
    end,
    getRioDelta = function()
      return nil
    end,
    syncMarker = "",
    syncBadge = "",
    getPlayerSyncSummary = function()
      return nil
    end,
    getReadyCheckReadyUntil = function()
      return nil
    end,
    getReadyCheckDeclinedUntil = function()
      return nil
    end,
    getTime = function()
      return 100
    end,
    getL = function()
      return {}
    end,
    isRaidGroup = function()
      return false
    end,
    uiRef = nil,
    applyKnownKeyToRosterEntry = function()
      return false
    end,
    getPlayerLastRunDps = nil,
    getOwnedKeystoneSnapshot = nil,
    getLanguageTooltipMarkup = function()
      return ""
    end,
    showRosterColumnGuides = function()
      return false
    end,
  }
  for k, v in pairs(overrides) do
    state[k] = v
  end
  return state
end

return M
