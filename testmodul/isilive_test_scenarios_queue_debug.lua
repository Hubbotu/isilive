---@diagnostic disable: undefined-global

-- Scenarios for logic/isiLive_queue_debug.lua - exercises the full
-- controller surface (Log, SetEnabled gating, IsEnabled fallback chain,
-- ClearLog, tail accessors) and the getTimestamp/maxEntries defaults
-- that the existing suite never touched.

return function(test, ctx)
  local Assert = ctx.assert
  local WithGlobals = ctx.with_globals
  local LoadAddonModules = ctx.load_modules

  local function Load()
    return LoadAddonModules({ "isiLive_log_buffer.lua", "isiLive_queue_debug.lua" })
  end

  test("queue_debug: Log prints via printFn and appends to the ring buffer", function()
    WithGlobals({ IsiLiveDB = {} }, function()
      local addon = Load()
      local printed = {}
      local controller = addon.QueueDebug.CreateController({
        printFn = function(msg)
          table.insert(printed, msg)
        end,
        queueSetDebugEnabled = function() end,
        queueIsDebugEnabled = function()
          return false
        end,
        getTimestamp = function()
          return "t1"
        end,
        maxEntries = 10,
      })
      controller.Log("[Q] event=one")
      controller.Log("[Q] event=two")
      Assert.Equal(#printed, 2, "printFn must fire once per Log")
      Assert.Equal(controller.GetLogCount(), 2, "ring buffer must hold both entries")
      local tail = controller.GetLogTail(5)
      Assert.True(tail[1]:find("event=one", 1, true) ~= nil)
      Assert.True(tail[2]:find("event=two", 1, true) ~= nil)
    end)
  end)

  test("queue_debug: SetEnabled propagates to queue module and writes IsiLiveDB", function()
    WithGlobals({ IsiLiveDB = {} }, function()
      local addon = Load()
      local propagated = {}
      local controller = addon.QueueDebug.CreateController({
        printFn = function() end,
        queueSetDebugEnabled = function(v)
          table.insert(propagated, v)
        end,
        queueIsDebugEnabled = function()
          return nil
        end,
        getTimestamp = function()
          return "t"
        end,
      })
      controller.SetEnabled(true)
      Assert.Equal(propagated[1], true)
      Assert.Equal(rawget(_G, "IsiLiveDB").queueDebug, true)

      controller.SetEnabled(false)
      Assert.Equal(propagated[2], false)
      Assert.Equal(rawget(_G, "IsiLiveDB").queueDebug, false)
    end)
  end)

  test("queue_debug: SetEnabled no-ops persistence when IsiLiveDB is absent", function()
    WithGlobals({}, function()
      local previous = rawget(_G, "IsiLiveDB")
      rawset(_G, "IsiLiveDB", nil)
      local addon = Load()
      local moduleEnabled = nil
      local controller = addon.QueueDebug.CreateController({
        printFn = function() end,
        queueSetDebugEnabled = function(value)
          moduleEnabled = value
        end,
        queueIsDebugEnabled = function()
          return nil
        end,
        getTimestamp = function()
          return "t"
        end,
      })
      -- Production never enters this branch (qdebug slash runs post-ADDON_LOADED
      -- so IsiLiveDB is always present); lazy-seeding pre-load would race the
      -- SavedVariables restore and clobber other settings.
      controller.SetEnabled(true)
      Assert.Nil(rawget(_G, "IsiLiveDB"), "missing DB must NOT be lazily allocated")
      Assert.Equal(moduleEnabled, true, "queueSetDebugEnabled still fires regardless of DB state")
      rawset(_G, "IsiLiveDB", previous)
    end)
  end)

  test("queue_debug: IsEnabled prefers queue module state over IsiLiveDB", function()
    WithGlobals({ IsiLiveDB = { queueDebug = false } }, function()
      local addon = Load()
      local moduleState = true
      local controller = addon.QueueDebug.CreateController({
        printFn = function() end,
        queueSetDebugEnabled = function() end,
        queueIsDebugEnabled = function()
          return moduleState
        end,
        getTimestamp = function()
          return "t"
        end,
      })
      Assert.Equal(controller.IsEnabled(), true, "module state overrides DB when non-nil")
      moduleState = false
      Assert.Equal(controller.IsEnabled(), false)
    end)
  end)

  test("queue_debug: IsEnabled falls back to IsiLiveDB when module state is nil", function()
    WithGlobals({ IsiLiveDB = { queueDebug = true } }, function()
      local addon = Load()
      local controller = addon.QueueDebug.CreateController({
        printFn = function() end,
        queueSetDebugEnabled = function() end,
        queueIsDebugEnabled = function()
          return nil
        end,
        getTimestamp = function()
          return "t"
        end,
      })
      Assert.Equal(controller.IsEnabled(), true)
    end)
  end)

  test("queue_debug: IsEnabled returns false when both sources are absent", function()
    WithGlobals({}, function()
      local previous = rawget(_G, "IsiLiveDB")
      rawset(_G, "IsiLiveDB", nil)
      local addon = Load()
      local controller = addon.QueueDebug.CreateController({
        printFn = function() end,
        queueSetDebugEnabled = function() end,
        queueIsDebugEnabled = function()
          return nil
        end,
        getTimestamp = function()
          return "t"
        end,
      })
      Assert.Equal(controller.IsEnabled(), false)
      rawset(_G, "IsiLiveDB", previous)
    end)
  end)

  test("queue_debug: maxEntries below 1 is clamped to 1", function()
    WithGlobals({ IsiLiveDB = {} }, function()
      local addon = Load()
      local controller = addon.QueueDebug.CreateController({
        printFn = function() end,
        queueSetDebugEnabled = function() end,
        queueIsDebugEnabled = function()
          return false
        end,
        getTimestamp = function()
          return "t"
        end,
        maxEntries = 0,
      })
      controller.Log("a")
      controller.Log("b")
      Assert.Equal(controller.GetLogCount(), 1, "clamped cap=1 must keep only the newest entry")
    end)
  end)

  test("queue_debug: ClearLog wipes the buffer", function()
    WithGlobals({
      IsiLiveDB = {},
      wipe = function(t)
        for k in pairs(t) do
          t[k] = nil
        end
        return t
      end,
    }, function()
      local addon = Load()
      local controller = addon.QueueDebug.CreateController({
        printFn = function() end,
        queueSetDebugEnabled = function() end,
        queueIsDebugEnabled = function()
          return false
        end,
        getTimestamp = function()
          return "t"
        end,
        maxEntries = 10,
      })
      controller.Log("one")
      controller.Log("two")
      Assert.Equal(controller.GetLogCount(), 2)
      controller.ClearLog()
      Assert.Equal(controller.GetLogCount(), 0)
    end)
  end)

  test("queue_debug: default getTimestamp is installed when opts omits it", function()
    WithGlobals({
      IsiLiveDB = {},
      GetTime = function()
        return 123.456
      end,
    }, function()
      local addon = Load()
      local controller = addon.QueueDebug.CreateController({
        printFn = function() end,
        queueSetDebugEnabled = function() end,
        queueIsDebugEnabled = function()
          return nil
        end,
      })
      controller.Log("payload")
      -- No assertion on the actual timestamp format (Lua 5.4 may expose
      -- date(), WoW does) - just that the code path runs and stores one.
      Assert.Equal(controller.GetLogCount(), 1)
    end)
  end)

  test("queue_debug: default printFn falls back to print and is callable", function()
    WithGlobals({ IsiLiveDB = {} }, function()
      local addon = Load()
      local controller = addon.QueueDebug.CreateController({
        queueSetDebugEnabled = function() end,
        queueIsDebugEnabled = function()
          return nil
        end,
        getTimestamp = function()
          return "t"
        end,
      })
      -- Don't assert on stdout, just that calling Log does not raise.
      controller.Log("stdout path")
      Assert.Equal(controller.GetLogCount(), 1)
    end)
  end)
end
