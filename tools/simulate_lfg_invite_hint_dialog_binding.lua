-- Standalone CLI tool: pins the Notice.CreateInviteHint dialog-binding chain
-- introduced as Fix 3a in v0.9.211.
--
-- The hint is a 420x64 floating box that floats above whichever dialog WoW
-- currently shows for an incoming LFG invite. The binding chain (in order):
--   1. LFGListInviteDialog (the standard "you've been invited" dialog) —
--      anchor TOP -> dialog BOTTOM with -8 yOffset.
--   2. LFGDungeonReadyDialog (the random-finder ready dialog) — same anchor.
--   3. Global isiLiveMainFrame — fallback when no dialog is visible.
--   4. UIParent — last-resort default anchor at TOP, -220.
--
-- The Fix 3a bug class: when the player has multiple parallel invites for
-- the same dungeon (a "+12/+13/+14 push lobby" scenario), each invite renders
-- a hint with its own searchResultID. Only ONE LFGListInviteDialog is visible
-- at any moment (the most recent invite). If the visible dialog references a
-- DIFFERENT resultID than the hint's, the hint must HIDE rather than risk
-- labeling the wrong listing.
--
-- Verifies:
--   * Show with no dialogs visible -> anchored to UIParent (last-resort).
--   * Show with isiLiveMainFrame visible -> anchored to the main frame.
--   * Show with LFGDungeonReadyDialog visible -> anchored to it.
--   * Show with LFGListInviteDialog visible AND matching resultID ->
--     anchored to the invite dialog, hint shown.
--   * Show with LFGListInviteDialog visible BUT a different resultID ->
--     hint stays HIDDEN (Fix 3a guard).
--   * dialog-agnostic legacy callers (searchResultID=nil) never trigger
--     the mismatch guard.
--   * 8s auto-hide via the OnUpdate script.
--   * Mid-display dialog flip: the OnUpdate scan flips the hint to hidden
--     the next tick after the visible dialog's resultID changes.
--
-- End-to-end discipline (CLAUDE.md "Tests & simulators: end-to-end by default"):
-- the real Notice.CreateInviteHint factory is loaded; the OnUpdate script
-- the production code registers is captured and ticked explicitly so the
-- 8s auto-hide and dialog-flip checks run through the live closure.
---@diagnostic disable: undefined-global
local io = io
---@diagnostic disable-next-line: undefined-global
local load = load
---@diagnostic disable-next-line: undefined-global
local os = os

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
-- WoW-globals model. Each dialog can be flipped between shown/hidden and
-- gets a steerable resultID for the mismatch test.
-- ----------------------------------------------------------------------
local model = {
  now = 100,
  lfgListInviteShown = false,
  lfgListInviteResultID = nil,
  lfgDungeonReadyShown = false,
  mainFrameShown = false,
}

local function ResetModel()
  model.now = 100
  model.lfgListInviteShown = false
  model.lfgListInviteResultID = nil
  model.lfgDungeonReadyShown = false
  model.mainFrameShown = false
end

-- A frame mock that supports the surface Notice.CreateInviteHint touches:
-- IsShown, Show, Hide, SetSize, SetFrameStrata, SetPoint, ClearAllPoints,
-- CreateTexture, CreateFontString, SetScript.
local function NoOp() end

local function MakeTextureMock()
  return {
    SetAllPoints = NoOp,
    SetColorTexture = NoOp,
    SetTexture = NoOp,
    SetTexCoord = NoOp,
    SetVertexColor = NoOp,
    SetDrawLayer = NoOp,
    Show = NoOp,
    Hide = NoOp,
  }
end

local function MakeFontStringMock()
  local fs = {
    _text = "",
  }
  fs.SetPoint = NoOp
  fs.ClearAllPoints = NoOp
  fs.SetJustifyH = NoOp
  fs.SetJustifyV = NoOp
  fs.SetTextColor = NoOp
  fs.SetSpacing = NoOp
  fs.SetFont = NoOp
  fs.SetFontObject = NoOp
  fs.SetWordWrap = NoOp
  fs.SetWidth = NoOp
  fs.SetText = function(self, value)
    self._text = tostring(value or "")
  end
  fs.GetText = function(self)
    return self._text
  end
  fs.Show = NoOp
  fs.Hide = NoOp
  return fs
end

-- The hint frame itself. Records points and visibility so test scenarios
-- can assert how the binding chain resolved.
local function MakeHintFrameMock()
  local frame = {
    _shown = false,
    _strata = nil,
    _scripts = {},
    _points = {},
  }
  frame.SetSize = NoOp
  frame.SetFrameStrata = function(self, strata)
    self._strata = strata
  end
  frame.IsShown = function(self)
    return self._shown == true
  end
  frame.Show = function(self)
    self._shown = true
  end
  frame.Hide = function(self)
    self._shown = false
  end
  frame.SetPoint = function(self, point, relativeTo, relativePoint, x, y)
    self._points[#self._points + 1] = {
      point = point,
      relativeTo = relativeTo,
      relativePoint = relativePoint,
      x = x,
      y = y,
    }
  end
  frame.ClearAllPoints = function(self)
    self._points = {}
  end
  frame.CreateTexture = MakeTextureMock
  frame.CreateFontString = MakeFontStringMock
  frame.SetScript = function(self, scriptType, fn)
    self._scripts[scriptType] = fn
  end
  return frame
end

-- Production calls `rawget(dialog, "resultID")` (bypassing metatables), so
-- the mock must expose resultID as a real table field, not via __index.
local function MakeDialogMock(resultID)
  local dialog = {
    _shown = false,
    resultID = resultID,
  }
  dialog.IsShown = function()
    return dialog._shown == true
  end
  return dialog
end

local function MakeMainFrameMock(holder)
  local frame = {}
  frame.IsShown = function()
    return holder.shown == true
  end
  return frame
end

local capturedHintFrame = nil

local function buildGlobals()
  -- Build fresh dialog mocks every call so a model.lfgListInviteResultID
  -- change between Show / tick is reflected on the next API call. Production
  -- reads `rawget(dialog, "resultID")` so the resultID has to live on the
  -- dialog table itself.
  local lfgListInviteDialog = MakeDialogMock(model.lfgListInviteResultID)
  lfgListInviteDialog._shown = model.lfgListInviteShown

  local lfgDungeonReadyDialog = MakeDialogMock(nil)
  lfgDungeonReadyDialog._shown = model.lfgDungeonReadyShown

  local mainFrameHolder = { shown = model.mainFrameShown }
  local globalMainFrame = MakeMainFrameMock(mainFrameHolder)

  return {
    GetTime = function()
      return model.now
    end,
    UIParent = { _name = "UIParent" },
    isiLiveMainFrame = globalMainFrame,
    LFGListInviteDialog = lfgListInviteDialog,
    LFGDungeonReadyDialog = lfgDungeonReadyDialog,
    CreateFrame = function()
      capturedHintFrame = MakeHintFrameMock()
      return capturedHintFrame
    end,
  }
end

local function BuildSession()
  capturedHintFrame = nil
  local addon
  Harness.WithGlobals(buildGlobals(), function()
    addon = Harness.LoadAddonModules({ "isiLive_ui_common.lua", "isiLive_notice.lua" })
  end)

  local hint
  Harness.WithGlobals(buildGlobals(), function()
    hint = addon.Notice.CreateInviteHint({})
  end)

  return {
    addon = addon,
    hint = hint,
    frame = capturedHintFrame,
    show = function(message, duration, searchResultID)
      Harness.WithGlobals(buildGlobals(), function()
        hint.Show(message, duration, searchResultID)
      end)
    end,
    tick = function()
      local onUpdate = capturedHintFrame and capturedHintFrame._scripts.OnUpdate
      if onUpdate then
        Harness.WithGlobals(buildGlobals(), function()
          onUpdate(capturedHintFrame)
        end)
      end
    end,
    advance = function(seconds)
      model.now = model.now + (seconds or 0)
    end,
    -- Helper: returns the most recent SetPoint relativeTo for assertions.
    lastAnchor = function()
      local p = capturedHintFrame._points[#capturedHintFrame._points]
      return p and p.relativeTo, p and p.relativePoint, p and p.y
    end,
  }
end

-- ----------------------------------------------------------------------
-- Phase 1: no dialog visible, no main frame -> anchored to UIParent.
-- ----------------------------------------------------------------------
local function ScenarioFallbackToUIParent()
  print("\n========== Scenario 1: no dialogs, no main frame -> UIParent fallback ==========")
  ResetModel()
  local session = BuildSession()

  session.show("Test: +14 NPX\nGroup: Push", 8, 1234)
  Check(session.frame:IsShown(), "hint is shown when no dialog mismatch")
  local anchor, point, y = session.lastAnchor()
  Check(anchor and anchor._name == "UIParent", "anchored to UIParent (last-resort fallback)")
  Check(point == "TOP" and y == -220, "UIParent anchor uses TOP / -220 yOffset")
end

-- ----------------------------------------------------------------------
-- Phase 2: main frame visible -> anchored to main frame.
-- ----------------------------------------------------------------------
local function ScenarioMainFrameAnchor()
  print("\n========== Scenario 2: main frame visible -> anchored to main frame ==========")
  ResetModel()
  model.mainFrameShown = true
  local session = BuildSession()

  session.show("Test: +14 NPX\nGroup: Push", 8, 1234)
  Check(session.frame:IsShown(), "hint shown")
  local _, point, y = session.lastAnchor()
  Check(point == "BOTTOM" and y == -8, "main-frame anchor uses BOTTOM / -8 yOffset (slots under the main UI)")
end

-- ----------------------------------------------------------------------
-- Phase 3: LFGDungeonReadyDialog visible -> anchored to it.
-- ----------------------------------------------------------------------
local function ScenarioReadyDialogAnchor()
  print("\n========== Scenario 3: LFGDungeonReadyDialog visible -> anchored to it ==========")
  ResetModel()
  model.lfgDungeonReadyShown = true
  local session = BuildSession()

  session.show("Test: +14 NPX\nGroup: Push", 8, 1234)
  Check(session.frame:IsShown(), "hint shown when ready-dialog is visible (no resultID mismatch)")
  local _, point, y = session.lastAnchor()
  Check(point == "BOTTOM" and y == -8, "ready-dialog anchor uses BOTTOM / -8 yOffset")
end

-- ----------------------------------------------------------------------
-- Phase 4: LFGListInviteDialog visible with MATCHING resultID -> shown.
-- ----------------------------------------------------------------------
local function ScenarioInviteDialogMatching()
  print("\n========== Scenario 4: LFGListInviteDialog visible + matching resultID -> shown ==========")
  ResetModel()
  model.lfgListInviteShown = true
  model.lfgListInviteResultID = 1234
  local session = BuildSession()

  session.show("Test: +14 NPX\nGroup: Push", 8, 1234)
  Check(session.frame:IsShown(), "matching resultID: hint is shown next to the invite dialog")
end

-- ----------------------------------------------------------------------
-- Phase 5: LFGListInviteDialog visible with DIFFERENT resultID -> hidden.
-- This is the Fix 3a regression pin.
-- ----------------------------------------------------------------------
local function ScenarioInviteDialogMismatched()
  print("\n========== Scenario 5: LFGListInviteDialog visible + different resultID -> HIDDEN (Fix 3a pin) ==========")
  ResetModel()
  model.lfgListInviteShown = true
  model.lfgListInviteResultID = 9999 -- visible dialog is for a DIFFERENT listing
  local session = BuildSession()

  session.show("Test: +14 NPX\nGroup: Push", 8, 1234) -- hint is for resultID 1234
  Check(
    not session.frame:IsShown(),
    "Fix 3a: hint stays HIDDEN when the visible LFGListInviteDialog references a different resultID"
  )
end

-- ----------------------------------------------------------------------
-- Phase 6: legacy callers without a searchResultID never trigger the
-- mismatch guard.
-- ----------------------------------------------------------------------
local function ScenarioLegacyCallersNoMismatch()
  print("\n========== Scenario 6: legacy caller (searchResultID=nil) is dialog-agnostic ==========")
  ResetModel()
  model.lfgListInviteShown = true
  model.lfgListInviteResultID = 5678 -- some arbitrary visible dialog
  local session = BuildSession()

  -- Show without a searchResultID: the dialog-mismatch guard must not fire.
  session.show("Legacy hint", 8, nil)
  Check(session.frame:IsShown(), "legacy caller (nil searchResultID) is shown regardless of which dialog is visible")
end

-- ----------------------------------------------------------------------
-- Phase 7: 8s auto-hide via OnUpdate. After endsAt the next tick hides.
-- ----------------------------------------------------------------------
local function ScenarioAutoHideAfter8Seconds()
  print("\n========== Scenario 7: OnUpdate auto-hides after the durationSeconds window ==========")
  ResetModel()
  local session = BuildSession()

  session.show("Test: +14 NPX\nGroup: Push", 8, nil)
  Check(session.frame:IsShown(), "shown at t=0")

  session.advance(5)
  session.tick()
  Check(session.frame:IsShown(), "still shown at t=+5s (within the 8s window)")

  session.advance(4) -- now t=+9s, past endsAt
  session.tick()
  Check(not session.frame:IsShown(), "hidden after t=+9s (past the 8s endsAt)")
end

-- ----------------------------------------------------------------------
-- Phase 8: mid-display dialog flip. Hint was shown OK at t=0 with matching
-- resultID; at t=+1s the visible dialog flips to a different resultID
-- (a second invite arrived). The next OnUpdate tick must hide the hint.
-- ----------------------------------------------------------------------
local function ScenarioDialogFlipMidDisplay()
  print("\n========== Scenario 8: mid-display dialog flip -> next tick hides ==========")
  ResetModel()
  model.lfgListInviteShown = true
  model.lfgListInviteResultID = 1234
  local session = BuildSession()

  session.show("Test: +14 NPX\nGroup: Push", 8, 1234)
  Check(session.frame:IsShown(), "matching resultID shown at t=0")

  -- Second invite arrives: dialog now references a different resultID.
  model.lfgListInviteResultID = 9999
  session.advance(1)
  session.tick()
  Check(
    not session.frame:IsShown(),
    "OnUpdate tick after dialog-flip hides the hint (production IsHintMismatchedToVisibleDialog re-checks each tick)"
  )
end

ScenarioFallbackToUIParent()
ScenarioMainFrameAnchor()
ScenarioReadyDialogAnchor()
ScenarioInviteDialogMatching()
ScenarioInviteDialogMismatched()
ScenarioLegacyCallersNoMismatch()
ScenarioAutoHideAfter8Seconds()
ScenarioDialogFlipMidDisplay()

if failures > 0 then
  print(string.format("\nLFG invite-hint dialog-binding simulator failed: %d check(s) failed", failures))
  os.exit(1)
end

print("\nLFG invite-hint dialog-binding simulator passed.")
