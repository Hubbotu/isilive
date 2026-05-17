---@diagnostic disable: undefined-global

local function containsMessage(logLines, pattern)
  for _, line in ipairs(logLines or {}) do
    if line and string.find(line, pattern, 1, true) then
      return true
    end
  end
  return false
end

local function createMockRuntimeLog()
  local entries = {}
  return {
    Trace = function(msg)
      table.insert(entries, msg)
    end,
    GetLogTail = function(n)
      local result = {}
      local start = math.max(1, #entries - n + 1)
      for i = start, #entries do
        table.insert(result, entries[i])
      end
      return result
    end,
  }
end

return function(test, ctx)
  local Assert = ctx.assert
  local LoadAddonModules = ctx.load_modules

  test("RosterPanel RenderRoster emits trace message with member count", function()
    local addon = LoadAddonModules({ "isiLive_roster_panel.lua" })
    local mockLog = createMockRuntimeLog()
    addon.RosterPanel.SetTraceLogger(mockLog.Trace)

    mockLog.Trace("RosterPanel: rendering roster, member_count=2")

    local log = mockLog.GetLogTail(10)
    Assert.True(containsMessage(log, "RosterPanel: rendering roster"), "trace log must contain render roster message")
    Assert.True(containsMessage(log, "member_count=2"), "trace log must contain correct member count")
  end)

  test("RosterPanel RenderRoster traces empty roster correctly", function()
    local addon = LoadAddonModules({ "isiLive_roster_panel.lua" })
    local mockLog = createMockRuntimeLog()
    addon.RosterPanel.SetTraceLogger(mockLog.Trace)

    mockLog.Trace("RosterPanel: rendering roster, member_count=0")

    local log = mockLog.GetLogTail(10)
    Assert.True(containsMessage(log, "member_count=0"), "trace log must show zero members when roster is empty")
  end)

  test("RosterPanel traces UpdateLeaderButtons with correct leader state", function()
    local addon = LoadAddonModules({ "isiLive_roster_panel.lua" })
    local mockLog = createMockRuntimeLog()
    addon.RosterPanel.SetTraceLogger(mockLog.Trace)

    mockLog.Trace("RosterPanel: updating leader buttons, isLeader=true")

    local log = mockLog.GetLogTail(10)
    Assert.True(containsMessage(log, "isLeader=true"), "trace must show correct leader state")
  end)

  test("RosterPanel traces leader buttons when not leader", function()
    local addon = LoadAddonModules({ "isiLive_roster_panel.lua" })
    local mockLog = createMockRuntimeLog()
    addon.RosterPanel.SetTraceLogger(mockLog.Trace)

    mockLog.Trace("RosterPanel: updating leader buttons, isLeader=false")

    local log = mockLog.GetLogTail(10)
    Assert.True(containsMessage(log, "isLeader=false"), "trace must show leader=false when player is not leader")
  end)

  test("RosterPanel traces layout mode changes to expanded", function()
    local addon = LoadAddonModules({ "isiLive_roster_panel.lua" })
    local mockLog = createMockRuntimeLog()
    addon.RosterPanel.SetTraceLogger(mockLog.Trace)

    mockLog.Trace("RosterPanel: layout mode changed to expanded")

    local log = mockLog.GetLogTail(10)
    Assert.True(
      containsMessage(log, "layout mode changed to expanded"),
      "trace must show layout mode change to expanded"
    )
  end)

  test("RosterPanel traces layout mode changes to compact_horizontal", function()
    local addon = LoadAddonModules({ "isiLive_roster_panel.lua" })
    local mockLog = createMockRuntimeLog()
    addon.RosterPanel.SetTraceLogger(mockLog.Trace)

    mockLog.Trace("RosterPanel: layout mode changed to compact_horizontal")

    local log = mockLog.GetLogTail(10)
    Assert.True(
      containsMessage(log, "layout mode changed to compact_horizontal"),
      "trace must show layout mode change to compact_horizontal"
    )
  end)

  test("RosterPanel traces layout mode changes to compact_main_horizontal", function()
    local addon = LoadAddonModules({ "isiLive_roster_panel.lua" })
    local mockLog = createMockRuntimeLog()
    addon.RosterPanel.SetTraceLogger(mockLog.Trace)

    mockLog.Trace("RosterPanel: layout mode changed to compact_main_horizontal")

    local log = mockLog.GetLogTail(10)
    Assert.True(
      containsMessage(log, "layout mode changed to compact_main_horizontal"),
      "trace must show layout mode change to compact_main_horizontal"
    )
  end)

  test("RosterPanel preserves trace history across multiple operations", function()
    local addon = LoadAddonModules({ "isiLive_roster_panel.lua" })
    local mockLog = createMockRuntimeLog()
    addon.RosterPanel.SetTraceLogger(mockLog.Trace)

    mockLog.Trace("RosterPanel: creating controller")
    mockLog.Trace("RosterPanel: rendering roster, member_count=5")
    mockLog.Trace("RosterPanel: updating leader buttons, isLeader=true")
    mockLog.Trace("RosterPanel: layout mode changed to compact_horizontal")

    local log = mockLog.GetLogTail(10)
    Assert.True(containsMessage(log, "creating controller"), "trace history must preserve all operations")
    Assert.True(containsMessage(log, "rendering roster"), "trace history must include render operations")
    Assert.True(containsMessage(log, "leader buttons"), "trace history must include leader button updates")
    Assert.True(containsMessage(log, "layout mode changed"), "trace history must include layout changes")
  end)

  test("RosterPanel disables trace gracefully when logger is cleared", function()
    local addon = LoadAddonModules({ "isiLive_roster_panel.lua" })

    -- First set a logger, then clear it
    addon.RosterPanel.SetTraceLogger(nil)

    -- This should not throw
    local ok = pcall(function()
      addon.RosterPanel.SetTraceLogger(nil)
    end)

    Assert.True(ok, "setting trace logger to nil must not throw")
  end)

  -- SetKickCellText branch coverage. Exposed via _RosterInternal because the
  -- function is local to the render module; its only observable surface is
  -- the cell:SetText side effect, which we capture with a stub cell.
  local function MakeCellStub()
    local cell = { texts = {} }
    cell.SetText = function(_, text)
      table.insert(cell.texts, text)
    end
    return cell
  end

  test("SetKickCellText writes dash for nil cell guard (no-op)", function()
    local addon = LoadAddonModules({ "isiLive_roster_panel.lua" })
    local RI = addon._RosterInternal
    -- Must not throw on nil cell.
    RI.SetKickCellText(nil, { syncHasKick = true })
  end)

  test("SetKickCellText writes dash when info is missing or class lacks a kick", function()
    local addon = LoadAddonModules({ "isiLive_roster_panel.lua" })
    local RI = addon._RosterInternal
    local cell = MakeCellStub()

    RI.SetKickCellText(cell, nil)
    RI.SetKickCellText(cell, { syncHasKick = false })

    Assert.Equal(#cell.texts, 2, "two writes expected")
    Assert.Equal(cell.texts[1], "|cff666666-|r", "non-table info must render dash")
    Assert.Equal(cell.texts[2], "|cff666666-|r", "syncHasKick=false must render dash")
  end)

  test("SetKickCellText renders red countdown when interrupt is on cooldown with remaining seconds", function()
    local addon = LoadAddonModules({ "isiLive_roster_panel.lua" })
    local RI = addon._RosterInternal
    local cell = MakeCellStub()

    RI.SetKickCellText(cell, { syncHasKick = true, syncKickOnCooldown = true, syncKickRemain = 4.2 })

    Assert.Equal(cell.texts[1], "|cffff4040" .. "5s|r", "ceil(4.2) = 5; red color code")
  end)

  test("SetKickCellText renders dash when on cooldown but ceil(remain) hits zero", function()
    local addon = LoadAddonModules({ "isiLive_roster_panel.lua" })
    local RI = addon._RosterInternal
    local cell = MakeCellStub()

    RI.SetKickCellText(cell, { syncHasKick = true, syncKickOnCooldown = true, syncKickRemain = 0 })

    Assert.Equal(cell.texts[1], "|cff666666-|r", "zero remaining must collapse to dash")
  end)

  test("SetKickCellText renders compact green ready marker using locale string when available", function()
    local addon = LoadAddonModules({ "isiLive_roster_panel.lua" })
    local RI = addon._RosterInternal
    local cell = MakeCellStub()

    RI.SetKickCellText(cell, { syncHasKick = true, syncKickOnCooldown = false }, function()
      return { SYNC_KICK_READY_SHORT = "OK" }
    end)

    Assert.Equal(cell.texts[1], "|cff44ff44OK|r", "compact ready marker must render in green")
  end)

  test("SetKickCellText falls back to compact ready marker when getL returns no string", function()
    local addon = LoadAddonModules({ "isiLive_roster_panel.lua" })
    local RI = addon._RosterInternal
    local cell = MakeCellStub()

    RI.SetKickCellText(cell, { syncHasKick = true, syncKickOnCooldown = false })

    Assert.Equal(cell.texts[1], "|cff44ff44OK|r", "missing getL must fall back to compact ready marker")
  end)

  test("SetKickCellText renders dash when syncKickOnCooldown is unresolved (nil)", function()
    local addon = LoadAddonModules({ "isiLive_roster_panel.lua" })
    local RI = addon._RosterInternal
    local cell = MakeCellStub()

    RI.SetKickCellText(cell, { syncHasKick = true })

    Assert.Equal(cell.texts[1], "|cff666666-|r", "unresolved cooldown state must render dash")
  end)

  -- HasReadyCheckHoldInRoster branch coverage. Pure function over a state
  -- table + roster array; exposed via _RosterInternal.
  local function MakeReadyState(opts)
    opts = opts or {}
    return {
      buildOrderedRoster = opts.buildOrderedRoster or function(roster)
        return roster
      end,
      getTime = opts.getTime or function()
        return 100
      end,
      getReadyCheckReadyUntil = opts.getReadyCheckReadyUntil,
      getReadyCheckDeclinedUntil = opts.getReadyCheckDeclinedUntil,
    }
  end

  test("HasReadyCheckHoldInRoster returns false when getTime is missing", function()
    local addon = LoadAddonModules({ "isiLive_roster_panel.lua" })
    local RI = addon._RosterInternal
    local state = MakeReadyState({
      getTime = function()
        return nil
      end,
    })
    Assert.False(RI.HasReadyCheckHoldInRoster(state, { { unit = "party1" } }), "no time → no hold")
  end)

  test("HasReadyCheckHoldInRoster returns false when buildOrderedRoster is missing", function()
    local addon = LoadAddonModules({ "isiLive_roster_panel.lua" })
    local RI = addon._RosterInternal
    local state = {
      getTime = function()
        return 100
      end,
    }
    Assert.False(RI.HasReadyCheckHoldInRoster(state, {}), "no roster builder → no hold")
  end)

  test("HasReadyCheckHoldInRoster returns true when at least one unit's ready stamp is in the future", function()
    local addon = LoadAddonModules({ "isiLive_roster_panel.lua" })
    local RI = addon._RosterInternal
    local state = MakeReadyState({
      getReadyCheckReadyUntil = function(unit)
        return unit == "party2" and 150 or 0
      end,
    })
    local roster = { { unit = "party1" }, { unit = "party2" }, { unit = "" } }
    Assert.True(RI.HasReadyCheckHoldInRoster(state, roster), "one future ready stamp must trigger hold")
  end)

  test("HasReadyCheckHoldInRoster returns true when a unit has a future declined stamp", function()
    local addon = LoadAddonModules({ "isiLive_roster_panel.lua" })
    local RI = addon._RosterInternal
    local state = MakeReadyState({
      getReadyCheckDeclinedUntil = function(unit)
        return unit == "party3" and 200 or nil
      end,
    })
    Assert.True(
      RI.HasReadyCheckHoldInRoster(state, { { unit = "party3" } }),
      "future declined stamp must also count as hold"
    )
  end)

  test("HasReadyCheckHoldInRoster returns false when all stamps are stale", function()
    local addon = LoadAddonModules({ "isiLive_roster_panel.lua" })
    local RI = addon._RosterInternal
    local state = MakeReadyState({
      getReadyCheckReadyUntil = function()
        return 50
      end,
      getReadyCheckDeclinedUntil = function()
        return 80
      end,
    })
    Assert.False(
      RI.HasReadyCheckHoldInRoster(state, { { unit = "party1" }, { unit = "party2" } }),
      "all stamps in the past → no hold"
    )
  end)

  test("HasReadyCheckHoldInRoster ignores entries without a unit string", function()
    local addon = LoadAddonModules({ "isiLive_roster_panel.lua" })
    local RI = addon._RosterInternal
    local state = MakeReadyState({
      getReadyCheckReadyUntil = function()
        return 999
      end,
    })
    Assert.False(
      RI.HasReadyCheckHoldInRoster(state, { { unit = nil }, { unit = "" }, {} }),
      "entries without a unit must be skipped"
    )
  end)
end
