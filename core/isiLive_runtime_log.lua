local _, addonTable = ...

addonTable = addonTable or {}

local RuntimeLog = {}
addonTable.RuntimeLog = RuntimeLog
local logBuffer = assert(addonTable.LogBuffer, "isiLive: LogBuffer module missing")
local EnsureStorage = logBuffer.EnsureSavedTable("runtimeLog")
local DEFAULT_LEVEL = "normal"
local DEEP_LEVEL = "deep"

local function NormalizeLevel(level)
  local text = tostring(level or DEFAULT_LEVEL):lower()
  if text == DEEP_LEVEL then
    return DEEP_LEVEL
  end
  return DEFAULT_LEVEL
end

local function NormalizeRuntimeMessage(message)
  local text = tostring(message or "")
  local tag, firstToken, rest = text:match("^(%[[%w_%-]+%])%s+(%S+)%s*(.*)$")
  if not tag or not firstToken or firstToken:find("=", 1, true) then
    return text
  end
  if rest and rest ~= "" then
    return string.format("%s event=%s %s", tag, firstToken, rest)
  end
  return string.format("%s event=%s", tag, firstToken)
end

function RuntimeLog.CreateController(opts)
  opts = opts or {}

  local getTimestamp = opts.getTimestamp
    or function()
      if GetTime then
        return string.format("%.3f", tonumber(GetTime()) or 0)
      end
      return date and date("%H:%M:%S") or "0.000"
    end

  local maxEntries = tonumber(opts.maxEntries) or 800
  if maxEntries < 1 then
    maxEntries = 1
  end
  local buildSessionHeader = type(opts.buildSessionHeader) == "function" and opts.buildSessionHeader or nil

  assert(type(getTimestamp) == "function", "isiLive: RuntimeLog requires getTimestamp")

  local controller = {}
  local sequence = 0

  function controller.EnsureStorage()
    return EnsureStorage()
  end

  function controller.SetEnabled(enabled)
    local db = rawget(_G, "IsiLiveDB")
    if not db then
      db = {}
      IsiLiveDB = db
    end
    local wasEnabled = db.runtimeLogEnabled == true
    local nextEnabled = enabled and true or false
    db.runtimeLogEnabled = nextEnabled
    if nextEnabled and not wasEnabled and buildSessionHeader then
      controller.AppendLog("[RUNTIME] session_start " .. tostring(buildSessionHeader()))
    end
  end

  function controller.IsEnabled()
    local db = rawget(_G, "IsiLiveDB")
    return db ~= nil and db.runtimeLogEnabled == true
  end

  function controller.SetLevel(level)
    local db = rawget(_G, "IsiLiveDB")
    if not db then
      db = {}
      IsiLiveDB = db
    end
    db.runtimeLogLevel = NormalizeLevel(level)
  end

  function controller.GetLevel()
    local db = rawget(_G, "IsiLiveDB")
    return NormalizeLevel(db and db.runtimeLogLevel or DEFAULT_LEVEL)
  end

  function controller.IsLevelEnabled(level)
    if not controller.IsEnabled() then
      return false
    end
    local normalizedLevel = NormalizeLevel(level)
    return normalizedLevel == DEFAULT_LEVEL or controller.GetLevel() == DEEP_LEVEL
  end

  function controller.AppendLog(message)
    sequence = sequence + 1
    logBuffer.Append(
      EnsureStorage(),
      "",
      string.format("seq=%d t=%s %s", sequence, tostring(getTimestamp()), NormalizeRuntimeMessage(message)),
      maxEntries
    )
  end

  function controller.Log(message)
    if not controller.IsLevelEnabled(DEFAULT_LEVEL) then
      return
    end
    controller.AppendLog(message)
  end

  function controller.LogAt(level, message)
    if not controller.IsLevelEnabled(level) then
      return
    end
    controller.AppendLog(message)
  end

  function controller.Logf(formatText, ...)
    if not controller.IsLevelEnabled(DEFAULT_LEVEL) then
      return
    end
    controller.AppendLog(string.format(tostring(formatText or ""), ...))
  end

  function controller.LogfAt(level, formatText, ...)
    if not controller.IsLevelEnabled(level) then
      return
    end
    controller.AppendLog(string.format(tostring(formatText or ""), ...))
  end

  function controller.TraceAt(level, buildMessage)
    if not controller.IsLevelEnabled(level) then
      return
    end
    if type(buildMessage) ~= "function" then
      controller.AppendLog(buildMessage)
      return
    end
    local ok, message = pcall(buildMessage)
    if ok then
      controller.AppendLog(message)
    else
      controller.AppendLog("[LOG_ERROR] " .. tostring(message))
    end
  end

  function controller.Trace(buildMessage)
    controller.TraceAt(DEFAULT_LEVEL, buildMessage)
  end

  function controller.LogDeep(message)
    controller.LogAt(DEEP_LEVEL, message)
  end

  function controller.LogfDeep(formatText, ...)
    controller.LogfAt(DEEP_LEVEL, formatText, ...)
  end

  function controller.TraceDeep(buildMessage)
    controller.TraceAt(DEEP_LEVEL, buildMessage)
  end

  function controller.ClearLog()
    wipe(EnsureStorage())
    sequence = 0
  end

  function controller.GetLogCount()
    return logBuffer.Count(EnsureStorage())
  end

  function controller.GetLogTail(limit)
    return logBuffer.GetTail(EnsureStorage(), limit, 20, 100)
  end

  return controller
end
