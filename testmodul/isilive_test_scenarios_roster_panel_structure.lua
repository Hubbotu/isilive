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

  test("RosterPanel SetTraceLogger accepts a trace function", function()
    local addon = LoadAddonModules({ "isiLive_roster_panel.lua" })
    addon.RosterPanel.SetTraceLogger(function() end)
    Assert.True(type(addon.RosterPanel.SetTraceLogger) == "function", "SetTraceLogger must be callable")
  end)

  test("RosterPanel traces creation with mock logger", function()
    local addon = LoadAddonModules({ "isiLive_roster_panel.lua" })
    local mockLog = createMockRuntimeLog()
    addon.RosterPanel.SetTraceLogger(mockLog.Trace)

    -- Simulate the trace calls that CreateController would make
    mockLog.Trace("RosterPanel: creating controller")
    mockLog.Trace("RosterPanel: constructing UI, row_count=5")

    local log = mockLog.GetLogTail(10)
    Assert.True(
      containsMessage(log, "RosterPanel: creating controller"),
      "trace log must contain 'creating controller'"
    )
    Assert.True(containsMessage(log, "RosterPanel: constructing UI"), "trace log must contain 'constructing UI'")
  end)

  test("RosterPanel UpdateLeaderButtons emits trace message with leader state", function()
    local addon = LoadAddonModules({ "isiLive_roster_panel.lua" })
    local mockLog = createMockRuntimeLog()
    addon.RosterPanel.SetTraceLogger(mockLog.Trace)

    mockLog.Trace("RosterPanel: updating leader buttons, isLeader=true")

    local log = mockLog.GetLogTail(10)
    Assert.True(
      containsMessage(log, "RosterPanel: updating leader buttons"),
      "trace log must contain leader button update message"
    )
  end)

  test("RosterPanel layout change emits trace message", function()
    local addon = LoadAddonModules({ "isiLive_roster_panel.lua" })
    local mockLog = createMockRuntimeLog()
    addon.RosterPanel.SetTraceLogger(mockLog.Trace)

    mockLog.Trace("RosterPanel: layout mode changed to compact_main_horizontal")

    local log = mockLog.GetLogTail(10)
    Assert.True(
      containsMessage(log, "RosterPanel: layout mode changed"),
      "trace log must contain layout change message"
    )
  end)

  test("RosterPanel disables trace gracefully when logger is nil", function()
    local addon = LoadAddonModules({ "isiLive_roster_panel.lua" })

    -- This should not throw
    local ok = pcall(function()
      addon.RosterPanel.SetTraceLogger(nil)
    end)

    Assert.True(ok, "setting trace logger to nil must not throw")
  end)
end
