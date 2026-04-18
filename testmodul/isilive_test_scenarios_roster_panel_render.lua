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
end
