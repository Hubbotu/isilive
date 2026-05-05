---@diagnostic disable: undefined-global
return function(test, ctx)
  local Assert = ctx.assert
  local WithGlobals = ctx.with_globals
  local LoadAddonModules = ctx.load_modules

  local function LoadErrorLog(globals)
    local addon
    WithGlobals(globals or {}, function()
      addon = LoadAddonModules({ "isiLive_error_log.lua" })
    end)
    return addon.ErrorLog
  end

  local function ResetIsiLiveDB()
    rawset(_G, "IsiLiveDB", {})
  end

  -- ----------------------------------------------------------------------
  -- Capture filter: only isiLive-mentioning errors land in the buffer
  -- ----------------------------------------------------------------------

  test("ErrorLog.Capture stores an error mentioning isiLive", function()
    ResetIsiLiveDB()
    local ErrorLog = LoadErrorLog()
    ErrorLog.Capture("isiLive: something broke", "stack-trace-with-isiLive-frame", nil)
    Assert.Equal(ErrorLog.GetCount(), 1, "isiLive-mentioning error must be captured")
  end)

  test("ErrorLog.Capture skips errors that do not mention isiLive (filter)", function()
    ResetIsiLiveDB()
    local ErrorLog = LoadErrorLog()
    ErrorLog.Capture("Plater: tooltip rendering failed", "Plater stack frame only", nil)
    ErrorLog.Capture("Blizzard UI: SetPoint failed", "FrameXML/Frame.lua:42", nil)
    Assert.Equal(ErrorLog.GetCount(), 0, "non-isiLive errors must be filtered out")
  end)

  test("ErrorLog.Capture detects isiLive in stack trace even if message does not mention it", function()
    ResetIsiLiveDB()
    local ErrorLog = LoadErrorLog()
    ErrorLog.Capture("attempt to index nil value", "Interface\\AddOns\\isiLive\\logic\\foo.lua:10", nil)
    Assert.Equal(ErrorLog.GetCount(), 1, "stack-frame-detected isiLive error must be captured")
  end)

  -- ----------------------------------------------------------------------
  -- Dedup: identical errors increment the count, do not duplicate
  -- ----------------------------------------------------------------------

  test("ErrorLog.Capture deduplicates identical errors via count++", function()
    ResetIsiLiveDB()
    local ErrorLog = LoadErrorLog()
    for _ = 1, 50 do
      ErrorLog.Capture("isiLive: storm", "isiLive-stack-A", nil)
    end
    Assert.Equal(ErrorLog.GetCount(), 1, "50 identical errors must collapse to 1 entry")
    local entries = ErrorLog.GetTail(10)
    Assert.Equal(entries[1].count, 50, "count must be 50")
  end)

  test("ErrorLog.Capture creates separate entries for different errors", function()
    ResetIsiLiveDB()
    local ErrorLog = LoadErrorLog()
    ErrorLog.Capture("isiLive: error A", "isiLive-stack-A", nil)
    ErrorLog.Capture("isiLive: error B", "isiLive-stack-B", nil)
    Assert.Equal(ErrorLog.GetCount(), 2, "different errors must be distinct entries")
  end)

  -- ----------------------------------------------------------------------
  -- Bounded ring: cap at MAX_ENTRIES
  -- ----------------------------------------------------------------------

  test("ErrorLog enforces MAX_ENTRIES cap (100)", function()
    ResetIsiLiveDB()
    local ErrorLog = LoadErrorLog()
    Assert.Equal(ErrorLog.GetMaxEntries(), 100, "MAX_ENTRIES must be 100")
    -- Push 150 distinct errors to exceed the cap.
    for i = 1, 150 do
      ErrorLog.Capture(string.format("isiLive: error %d", i), string.format("isiLive-stack-%d", i), nil)
    end
    Assert.True(ErrorLog.GetCount() <= 100, "ring buffer must cap at 100 entries")
  end)

  -- ----------------------------------------------------------------------
  -- Chain-of-responsibility: previous handler is always called
  -- ----------------------------------------------------------------------

  test("ErrorLog.Install chains to previous error handler", function()
    ResetIsiLiveDB()
    local previousCalls = {}
    local previousHandler = function(message)
      previousCalls[#previousCalls + 1] = message
    end
    local installedHandler
    -- Install() reads geterrorhandler/seterrorhandler from _G, so the call
    -- must happen INSIDE the WithGlobals scope (otherwise the test globals
    -- are gone by the time Install() runs).
    WithGlobals({
      geterrorhandler = function()
        return previousHandler
      end,
      seterrorhandler = function(h)
        installedHandler = h
      end,
    }, function()
      local addon = LoadAddonModules({ "isiLive_error_log.lua" })
      addon.ErrorLog.Install()
      Assert.Equal(addon.ErrorLog.IsInstalled(), true, "Install() must mark installed")
      Assert.Equal(type(installedHandler), "function", "seterrorhandler must receive a function")
      installedHandler("isiLive: test error")
      Assert.Equal(#previousCalls, 1, "previous handler must be called")
      Assert.Equal(previousCalls[1], "isiLive: test error", "previous handler must receive the error message")
    end)
  end)

  test("ErrorLog.Install is idempotent", function()
    ResetIsiLiveDB()
    local setCalls = 0
    WithGlobals({
      geterrorhandler = function()
        return nil
      end,
      seterrorhandler = function()
        setCalls = setCalls + 1
      end,
    }, function()
      local addon = LoadAddonModules({ "isiLive_error_log.lua" })
      addon.ErrorLog.Install()
      addon.ErrorLog.Install()
      addon.ErrorLog.Install()
      Assert.Equal(setCalls, 1, "seterrorhandler must be called exactly once across multiple Install() calls")
    end)
  end)

  -- ----------------------------------------------------------------------
  -- Boundary: missing globals
  -- ----------------------------------------------------------------------

  test("ErrorLog.Install no-ops when geterrorhandler is missing", function()
    ResetIsiLiveDB()
    WithGlobals({
      geterrorhandler = false, -- explicit nil-out via false-sentinel pattern
      seterrorhandler = false,
    }, function()
      local addon = LoadAddonModules({ "isiLive_error_log.lua" })
      local ok = pcall(addon.ErrorLog.Install)
      Assert.True(ok, "Install() must not throw when error-handler globals are absent")
      Assert.Equal(addon.ErrorLog.IsInstalled(), false, "IsInstalled() must report false")
    end)
  end)

  test("ErrorLog.Capture handles nil IsiLiveDB gracefully", function()
    rawset(_G, "IsiLiveDB", nil)
    local ErrorLog = LoadErrorLog()
    local ok = pcall(ErrorLog.Capture, "isiLive: error", "isiLive-stack", nil)
    Assert.True(ok, "Capture must not throw when IsiLiveDB is nil")
  end)

  -- ----------------------------------------------------------------------
  -- GetTail / Clear / GetCount API
  -- ----------------------------------------------------------------------

  test("ErrorLog.GetTail returns the most recent entries", function()
    ResetIsiLiveDB()
    local ErrorLog = LoadErrorLog()
    for i = 1, 5 do
      ErrorLog.Capture(string.format("isiLive: error %d", i), string.format("isiLive-stack-%d", i), nil)
    end
    local tail = ErrorLog.GetTail(3)
    Assert.Equal(#tail, 3, "GetTail(3) must return 3 entries")
    Assert.Equal(tail[#tail].message, "isiLive: error 5", "last entry must be the most recent")
  end)

  test("ErrorLog.GetTail clamps limit to [1, 100]", function()
    ResetIsiLiveDB()
    local ErrorLog = LoadErrorLog()
    for i = 1, 10 do
      ErrorLog.Capture(string.format("isiLive: error %d", i), string.format("isiLive-stack-%d", i), nil)
    end
    Assert.Equal(#ErrorLog.GetTail(0), 1, "limit 0 clamps to 1")
    Assert.Equal(#ErrorLog.GetTail(1000), 10, "limit 1000 clamps to total count")
  end)

  test("ErrorLog.Clear empties the buffer", function()
    ResetIsiLiveDB()
    local ErrorLog = LoadErrorLog()
    ErrorLog.Capture("isiLive: error", "isiLive-stack", nil)
    Assert.Equal(ErrorLog.GetCount(), 1, "pre-Clear count")
    ErrorLog.Clear()
    Assert.Equal(ErrorLog.GetCount(), 0, "post-Clear count must be 0")
  end)

  -- ----------------------------------------------------------------------
  -- Schema-sanitizer integration: maxMapEntries trim on errorLog
  -- ----------------------------------------------------------------------

  test("DBSchema sanitizer trims errorLog when over maxMapEntries cap", function()
    local addon = LoadAddonModules({ "isiLive_db_schema.lua" })
    local DBSchema = addon.DBSchema
    -- Fabricate an oversized errorLog with 250 entries (cap is 200 in schema).
    local oversized = {}
    for i = 1, 250 do
      oversized[i] = { message = "fake-" .. i, count = 1 }
    end
    local db = { errorLog = oversized }
    DBSchema.Sanitize(db)
    local count = 0
    for _ in pairs(db.errorLog) do
      count = count + 1
    end
    Assert.True(count <= 200, "errorLog must be trimmed to <= 200 by sanitizer")
  end)

  test("DBSchema sanitizer trims rioBaseline when over maxMapEntries cap", function()
    local addon = LoadAddonModules({ "isiLive_db_schema.lua" })
    local DBSchema = addon.DBSchema
    -- Simulate a rioBaseline that grew to 6000 entries (cap is 5000).
    local oversized = {}
    for i = 1, 6000 do
      oversized["Player" .. i .. "-Realm"] = 2400
    end
    local db = { rioBaseline = oversized }
    DBSchema.Sanitize(db)
    local count = 0
    for _ in pairs(db.rioBaseline) do
      count = count + 1
    end
    Assert.True(count <= 5000, "rioBaseline must be trimmed to <= 5000 by sanitizer")
  end)

  test("DBSchema sanitizer trims stats.playerLastRunByCharacter when over cap", function()
    local addon = LoadAddonModules({ "isiLive_db_schema.lua" })
    local DBSchema = addon.DBSchema
    local oversized = {}
    for i = 1, 5500 do
      oversized["Player" .. i .. "-Realm"] = { dps = 2000000 }
    end
    local db = { stats = { playerLastRunByCharacter = oversized } }
    DBSchema.Sanitize(db)
    local count = 0
    for _ in pairs(db.stats.playerLastRunByCharacter) do
      count = count + 1
    end
    Assert.True(count <= 5000, "playerLastRunByCharacter must be trimmed to <= 5000")
  end)

  test("DBSchema sanitizer leaves under-cap maps untouched", function()
    local addon = LoadAddonModules({ "isiLive_db_schema.lua" })
    local DBSchema = addon.DBSchema
    local intact = {}
    for i = 1, 100 do
      intact["Player" .. i .. "-Realm"] = 2400
    end
    local db = { rioBaseline = intact }
    DBSchema.Sanitize(db)
    local count = 0
    for _ in pairs(db.rioBaseline) do
      count = count + 1
    end
    Assert.Equal(count, 100, "under-cap rioBaseline must be preserved exactly")
  end)

  test("DBSchema sanitizer logs trim action via callback", function()
    local addon = LoadAddonModules({ "isiLive_db_schema.lua" })
    local DBSchema = addon.DBSchema
    local oversized = {}
    for i = 1, 6000 do
      oversized["Player" .. i .. "-Realm"] = 2400
    end
    local db = { rioBaseline = oversized }
    local trimMessages = {}
    DBSchema.Sanitize(db, function(msg)
      if type(msg) == "string" and msg:find("trimmed", 1, true) then
        trimMessages[#trimMessages + 1] = msg
      end
    end)
    Assert.True(#trimMessages > 0, "trim action must be logged via callback")
    Assert.True(trimMessages[1]:find("rioBaseline", 1, true) ~= nil, "trim log must name the trimmed field")
  end)
end
