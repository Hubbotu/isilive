local _, addonTable = ...

addonTable = addonTable or {}

local QueueDebug = {}
addonTable.QueueDebug = QueueDebug
local logBuffer = assert(addonTable.LogBuffer, "isiLive: LogBuffer module missing")
local EnsureStorage = logBuffer.EnsureSavedTable("queueDebugLog")

function QueueDebug.CreateController(opts)
  opts = opts or {}

  local printFn = opts.printFn or print
  local queueSetDebugEnabled = opts.queueSetDebugEnabled or function(_enabled) end
  local queueIsDebugEnabled = opts.queueIsDebugEnabled or function()
    return nil
  end
  local getTimestamp = opts.getTimestamp
    or function()
      local dateFn = rawget(_G, "date")
      if type(dateFn) == "function" then
        return dateFn("%H:%M:%S")
      end
      local getTimeFn = rawget(_G, "GetTime")
      return tostring(type(getTimeFn) == "function" and getTimeFn() or 0)
    end

  local maxEntries = tonumber(opts.maxEntries) or 400
  if maxEntries < 1 then
    maxEntries = 1
  end

  assert(type(printFn) == "function", "isiLive: QueueDebug requires printFn")
  assert(type(queueSetDebugEnabled) == "function", "isiLive: QueueDebug requires queueSetDebugEnabled")
  assert(type(queueIsDebugEnabled) == "function", "isiLive: QueueDebug requires queueIsDebugEnabled")
  assert(type(getTimestamp) == "function", "isiLive: QueueDebug requires getTimestamp")

  local controller = {}

  function controller.EnsureStorage()
    return EnsureStorage()
  end

  function controller.AppendLog(message)
    logBuffer.Append(EnsureStorage(), getTimestamp(), message, maxEntries)
  end

  function controller.Log(message)
    printFn(message)
    controller.AppendLog(message)
  end

  function controller.SetEnabled(enabled)
    local normalized = enabled and true or false
    queueSetDebugEnabled(normalized)
    -- SavedVariables are restored before ADDON_LOADED and SetEnabled only runs
    -- from the /isilive qdebug slash command (post-load). Lazy-creating
    -- IsiLiveDB pre-load would race the SavedVariables restore and clobber
    -- other settings.
    local db = rawget(_G, "IsiLiveDB")
    if type(db) == "table" then
      db.queueDebug = normalized
    end
  end

  function controller.IsEnabled()
    local moduleState = queueIsDebugEnabled()
    if moduleState ~= nil then
      return moduleState == true
    end
    local db = rawget(_G, "IsiLiveDB")
    return db ~= nil and db.queueDebug == true
  end

  function controller.ClearLog()
    local wipeFn = rawget(_G, "wipe")
    local storage = EnsureStorage()
    if type(wipeFn) == "function" then
      wipeFn(storage)
    else
      for key in pairs(storage) do
        storage[key] = nil
      end
    end
  end

  function controller.GetLogCount()
    return logBuffer.Count(EnsureStorage())
  end

  function controller.GetLogTail(limit)
    return logBuffer.GetTail(EnsureStorage(), limit, 20, 100)
  end

  return controller
end
