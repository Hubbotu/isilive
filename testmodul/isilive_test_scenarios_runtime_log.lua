---@diagnostic disable: undefined-global

return function(test, ctx)
  local Assert = ctx.assert
  local WithGlobals = ctx.with_globals
  local LoadAddonModules = ctx.load_modules

  test("Runtime log controller appends entries only when enabled", function()
    WithGlobals({
      IsiLiveDB = {},
    }, function()
      local addon = LoadAddonModules({ "isiLive_log_buffer.lua", "isiLive_runtime_log.lua" })
      local controller = addon.RuntimeLog.CreateController({
        getTimestamp = function()
          return "12:00:00"
        end,
        maxEntries = 10,
      })

      controller.Log("before-enable")
      Assert.Equal(controller.GetLogCount(), 0, "disabled runtime log must ignore entries")

      controller.SetEnabled(true)
      controller.Log("after-enable")
      Assert.Equal(controller.GetLogCount(), 1, "enabled runtime log must append entries")
    end)
  end)

  test("Runtime log controller trims old entries beyond max entries", function()
    WithGlobals({
      IsiLiveDB = {},
    }, function()
      local tick = 0
      local addon = LoadAddonModules({ "isiLive_log_buffer.lua", "isiLive_runtime_log.lua" })
      local controller = addon.RuntimeLog.CreateController({
        getTimestamp = function()
          tick = tick + 1
          return string.format("12:00:%02d", tick)
        end,
        maxEntries = 2,
      })
      controller.SetEnabled(true)

      controller.Log("one")
      controller.Log("two")
      controller.Log("three")

      local tail = controller.GetLogTail(10)
      Assert.Equal(#tail, 2, "runtime log must keep only maxEntries newest entries")
      Assert.True(tail[1]:find("two", 1, true) ~= nil, "oldest retained entry should be second message")
      Assert.True(tail[2]:find("three", 1, true) ~= nil, "newest retained entry should be third message")
    end)
  end)

  test("Runtime log controller prefixes entries with sequence and timestamp", function()
    WithGlobals({
      IsiLiveDB = {},
    }, function()
      local tick = 0
      local addon = LoadAddonModules({ "isiLive_log_buffer.lua", "isiLive_runtime_log.lua" })
      local controller = addon.RuntimeLog.CreateController({
        getTimestamp = function()
          tick = tick + 1
          return string.format("%.3f", 100 + tick / 10)
        end,
        maxEntries = 10,
      })
      controller.SetEnabled(true)

      controller.Log("[TEST] event=one")
      controller.Log("[TEST] event=two")

      local tail = controller.GetLogTail(2)
      Assert.True(
        tail[1]:find("^seq=1 t=100%.100 %[TEST%] event=one") ~= nil,
        "first entry must include seq and precise timestamp"
      )
      Assert.True(tail[2]:find("^seq=2 t=100%.200 %[TEST%] event=two") ~= nil, "second entry must increment seq")
    end)
  end)

  test("Runtime log controller normalizes tag action messages to event field", function()
    WithGlobals({
      IsiLiveDB = {},
    }, function()
      local addon = LoadAddonModules({ "isiLive_log_buffer.lua", "isiLive_runtime_log.lua" })
      local controller = addon.RuntimeLog.CreateController({
        getTimestamp = function()
          return "100.000"
        end,
        maxEntries = 10,
      })
      controller.SetEnabled(true)

      controller.Log("[TP] update_button_called soundContext=queue")
      controller.Log("[READYCHECK] event=READY_CHECK active=true")

      local tail = controller.GetLogTail(2)
      Assert.True(
        tail[1]:find("%[TP%] event=update_button_called soundContext=queue") ~= nil,
        "tag action messages must be normalized to event=action"
      )
      Assert.True(
        tail[2]:find("%[READYCHECK%] event=READY_CHECK active=true") ~= nil,
        "messages already using event= must stay unchanged"
      )
    end)
  end)

  test("Runtime log controller uses precise GetTime timestamp by default", function()
    WithGlobals({
      IsiLiveDB = {},
      GetTime = function()
        return 123.4567
      end,
    }, function()
      local addon = LoadAddonModules({ "isiLive_log_buffer.lua", "isiLive_runtime_log.lua" })
      local controller = addon.RuntimeLog.CreateController({
        maxEntries = 10,
      })
      controller.SetEnabled(true)

      controller.Log("[TEST] event=clock")

      local tail = controller.GetLogTail(1)
      Assert.True(
        tail[1]:find("^seq=1 t=123%.457 %[TEST%] event=clock") ~= nil,
        "default timestamp must use GetTime with milliseconds"
      )
    end)
  end)

  test("Runtime log controller formats lazily only when enabled", function()
    WithGlobals({
      IsiLiveDB = {},
    }, function()
      local addon = LoadAddonModules({ "isiLive_log_buffer.lua", "isiLive_runtime_log.lua" })
      local controller = addon.RuntimeLog.CreateController({
        getTimestamp = function()
          return "12:00:00"
        end,
        maxEntries = 10,
      })

      local value = setmetatable({}, {
        __tostring = function()
          error("disabled formatter argument should not be converted")
        end,
      })
      controller.Logf("value=%s", value)
    end)
  end)

  test("Runtime log controller trace builder runs only when enabled", function()
    WithGlobals({
      IsiLiveDB = {},
    }, function()
      local buildCount = 0
      local addon = LoadAddonModules({ "isiLive_log_buffer.lua", "isiLive_runtime_log.lua" })
      local controller = addon.RuntimeLog.CreateController({
        getTimestamp = function()
          return "12:00:00"
        end,
        maxEntries = 10,
      })

      controller.Trace(function()
        buildCount = buildCount + 1
        return "disabled"
      end)
      Assert.Equal(buildCount, 0, "disabled trace must not evaluate the builder")

      controller.SetEnabled(true)
      controller.Trace(function()
        buildCount = buildCount + 1
        return "enabled"
      end)
      Assert.Equal(buildCount, 1, "enabled trace must evaluate the builder exactly once")
      Assert.True(controller.GetLogTail(1)[1]:find("enabled", 1, true) ~= nil, "trace should append builder output")
    end)
  end)

  test("Runtime log controller writes session header only when enabling", function()
    WithGlobals({
      IsiLiveDB = {},
    }, function()
      local addon = LoadAddonModules({ "isiLive_log_buffer.lua", "isiLive_runtime_log.lua" })
      local controller = addon.RuntimeLog.CreateController({
        getTimestamp = function()
          return "12:00:00"
        end,
        buildSessionHeader = function()
          return "version=1.2.3 locale=deDE level=normal maxEntries=10"
        end,
        maxEntries = 10,
      })

      controller.SetEnabled(false)
      Assert.Equal(controller.GetLogCount(), 0, "disabled transition must not write a session header")
      controller.SetEnabled(true)
      controller.SetEnabled(true)

      local tail = controller.GetLogTail(10)
      Assert.Equal(#tail, 1, "session header must be written only on disabled to enabled transition")
      Assert.True(
        tail[1]:find("%[RUNTIME%] event=session_start version=1%.2%.3 locale=deDE level=normal maxEntries=10") ~= nil,
        "session header must include runtime context"
      )
    end)
  end)

  test("Runtime log controller filters deep trace unless deep level is enabled", function()
    WithGlobals({
      IsiLiveDB = {},
    }, function()
      local buildCount = 0
      local addon = LoadAddonModules({ "isiLive_log_buffer.lua", "isiLive_runtime_log.lua" })
      local controller = addon.RuntimeLog.CreateController({
        getTimestamp = function()
          return "12:00:00"
        end,
        maxEntries = 10,
      })
      controller.SetEnabled(true)

      controller.TraceDeep(function()
        buildCount = buildCount + 1
        return "[DEEP] hidden"
      end)
      Assert.Equal(buildCount, 0, "normal level must not evaluate deep trace builders")
      Assert.Equal(controller.GetLogCount(), 0, "normal level must not append deep traces")

      controller.SetLevel("deep")
      controller.TraceDeep(function()
        buildCount = buildCount + 1
        return "[DEEP] visible"
      end)

      Assert.Equal(buildCount, 1, "deep level must evaluate deep trace builder once")
      Assert.True(controller.GetLogTail(1)[1]:find("%[DEEP%] event=visible") ~= nil, "deep trace must be appended")
    end)
  end)

  test("Runtime log controller preserves tail order across ring overwrite", function()
    WithGlobals({
      IsiLiveDB = {},
    }, function()
      local addon = LoadAddonModules({ "isiLive_log_buffer.lua", "isiLive_runtime_log.lua" })
      local controller = addon.RuntimeLog.CreateController({
        getTimestamp = function()
          return "12:00:00"
        end,
        maxEntries = 3,
      })
      controller.SetEnabled(true)

      for i = 1, 6 do
        controller.Log("entry-" .. tostring(i))
      end

      local tail = controller.GetLogTail(3)
      Assert.Equal(controller.GetLogCount(), 3, "ring buffer count must stay capped")
      Assert.True(
        tail[1]:find("^seq=4 ", 1, false) ~= nil,
        "oldest retained ring entry should preserve global sequence"
      )
      Assert.True(
        tail[3]:find("^seq=6 ", 1, false) ~= nil,
        "newest retained ring entry should preserve global sequence"
      )
      Assert.True(tail[1]:find("entry-4", 1, true) ~= nil, "oldest retained ring entry should be entry-4")
      Assert.True(tail[2]:find("entry-5", 1, true) ~= nil, "middle retained ring entry should be entry-5")
      Assert.True(tail[3]:find("entry-6", 1, true) ~= nil, "newest retained ring entry should be entry-6")
    end)
  end)

  test("Runtime log controller sanitizes non-ASCII bytes", function()
    WithGlobals({
      IsiLiveDB = {},
    }, function()
      local addon = LoadAddonModules({ "isiLive_log_buffer.lua", "isiLive_runtime_log.lua" })
      local controller = addon.RuntimeLog.CreateController({
        getTimestamp = function()
          return "12:00:00"
        end,
        maxEntries = 10,
      })
      controller.SetEnabled(true)

      controller.Log("abc\195\164xyz")
      local tail = controller.GetLogTail(1)

      Assert.Equal(#tail, 1, "sanitizing test should produce one log entry")
      Assert.True(
        tail[1]:find("abc?xyz", 1, true) ~= nil,
        "non-ASCII UTF-8 sequence must collapse to a single ? in stored log text"
      )
    end)
  end)

  test("Runtime log controller tail enforces min/max limits", function()
    WithGlobals({
      IsiLiveDB = {},
    }, function()
      local addon = LoadAddonModules({ "isiLive_log_buffer.lua", "isiLive_runtime_log.lua" })
      local controller = addon.RuntimeLog.CreateController({
        getTimestamp = function()
          return "12:00:00"
        end,
        maxEntries = 150,
      })
      controller.SetEnabled(true)

      for i = 1, 120 do
        controller.Log("entry-" .. tostring(i))
      end

      Assert.Equal(#controller.GetLogTail(0), 1, "tail limit below 1 must clamp to one entry")
      Assert.Equal(#controller.GetLogTail(500), 100, "tail limit above cap must clamp to 100 entries")
    end)
  end)

  test("Runtime log controller keeps cap and tail stable across 2000 entry burst", function()
    WithGlobals({
      IsiLiveDB = {},
    }, function()
      local tick = 0
      local addon = LoadAddonModules({ "isiLive_log_buffer.lua", "isiLive_runtime_log.lua" })
      local controller = addon.RuntimeLog.CreateController({
        getTimestamp = function()
          tick = tick + 1
          return string.format("%.3f", tick / 1000)
        end,
        maxEntries = 100,
      })
      controller.SetEnabled(true)

      for i = 1, 2000 do
        controller.Logf("[PERF] burst index=%d", i)
      end

      local tail = controller.GetLogTail(100)
      Assert.Equal(controller.GetLogCount(), 100, "runtime log burst must stay capped")
      Assert.Equal(#tail, 100, "runtime log tail must expose only capped entries")
      Assert.True(tail[1]:find("^seq=1901 ", 1, false) ~= nil, "tail must start at the oldest retained sequence")
      Assert.True(tail[#tail]:find("^seq=2000 ", 1, false) ~= nil, "tail must end at the newest sequence")
      Assert.True(
        tail[#tail]:find("%[PERF%] event=burst index=2000") ~= nil,
        "tail must preserve normalized newest burst entry"
      )
    end)
  end)

  test("LogBuffer Append and GetTail behave correctly at cap=1", function()
    local addon = LoadAddonModules({ "isiLive_log_buffer.lua" })
    local logs = {}

    addon.LogBuffer.Append(logs, "t1", "one", 1)
    Assert.Equal(addon.LogBuffer.Count(logs), 1, "cap=1: first append must yield count 1")
    local tail = addon.LogBuffer.GetTail(logs, 5, 5, 10)
    Assert.Equal(#tail, 1, "cap=1: tail must return exactly one entry")
    Assert.True(tail[1]:find("one", 1, true) ~= nil, "cap=1: tail must contain newest entry")

    addon.LogBuffer.Append(logs, "t2", "two", 1)
    Assert.Equal(addon.LogBuffer.Count(logs), 1, "cap=1: second append must still yield count 1")
    tail = addon.LogBuffer.GetTail(logs, 5, 5, 10)
    Assert.Equal(#tail, 1, "cap=1: overwrite must not grow tail")
    Assert.True(tail[1]:find("two", 1, true) ~= nil, "cap=1: tail must reflect overwritten entry")

    addon.LogBuffer.Append(logs, "t3", "three", 1)
    tail = addon.LogBuffer.GetTail(logs, 5, 5, 10)
    Assert.Equal(#tail, 1, "cap=1: third append must keep tail length 1")
    Assert.True(tail[1]:find("three", 1, true) ~= nil, "cap=1: tail must reflect newest overwrite")
  end)

  test("LogBuffer recovers from corrupted _count larger than cap", function()
    local addon = LoadAddonModules({ "isiLive_log_buffer.lua" })
    local logs = { "a", "b", "c", _count = 999, _head = 1 }

    local tail = addon.LogBuffer.GetTail(logs, 10, 10, 50)
    Assert.Equal(#tail, 3, "GetTail must clamp corrupted _count to actual cap")
    Assert.True(tail[3]:find("c", 1, true) ~= nil, "GetTail must keep newest entry after normalization")
    Assert.Equal(logs._count, 3, "NormalizeRing must rewrite _count to cap")
  end)

  test("LogBuffer recovers from missing _count and _head metadata", function()
    local addon = LoadAddonModules({ "isiLive_log_buffer.lua" })
    local logs = { "x", "y", "z" }

    local tail = addon.LogBuffer.GetTail(logs, 10, 10, 50)
    Assert.Equal(#tail, 3, "GetTail must read legacy arrays without _count/_head")
    Assert.True(tail[1]:find("x", 1, true) ~= nil, "legacy array: first tail entry must be x")
    Assert.True(tail[3]:find("z", 1, true) ~= nil, "legacy array: last tail entry must be z")
    Assert.Equal(logs._count, 3, "NormalizeRing must seed _count for legacy arrays")
    Assert.Equal(logs._head, 1, "NormalizeRing must seed _head for legacy arrays")
  end)

  test("LogBuffer recovers from _head out of range", function()
    local addon = LoadAddonModules({ "isiLive_log_buffer.lua" })
    local logs = { "one", "two", "three", _count = 3, _head = 99 }

    local tail = addon.LogBuffer.GetTail(logs, 10, 10, 50)
    Assert.Equal(#tail, 3, "GetTail must tolerate _head outside [1, cap]")
    Assert.Equal(logs._head, 1, "NormalizeRing must reset invalid _head to 1")
  end)

  test("LogBuffer Append after corruption recovery uses normalized state", function()
    local addon = LoadAddonModules({ "isiLive_log_buffer.lua" })
    local logs = { "a", "b", "c", _count = -5, _head = 0 }

    addon.LogBuffer.Append(logs, "t", "new", 3)
    Assert.Equal(addon.LogBuffer.Count(logs), 3, "Append after corruption must fill up to cap")
    local tail = addon.LogBuffer.GetTail(logs, 10, 10, 50)
    Assert.Equal(#tail, 3, "tail after corruption recovery must contain cap entries")
    Assert.True(tail[#tail]:find("new", 1, true) ~= nil, "newest entry must land at the tail")
  end)

  test("LogBuffer GetTail returns empty for empty ring", function()
    local addon = LoadAddonModules({ "isiLive_log_buffer.lua" })
    local logs = {}

    local tail = addon.LogBuffer.GetTail(logs, 10, 10, 50)
    Assert.Equal(#tail, 0, "empty ring must produce empty tail")
  end)
end
