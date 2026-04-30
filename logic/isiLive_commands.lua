local _, addonTable = ...

addonTable = addonTable or {}

local Commands = {}
addonTable.Commands = Commands

local function BuildDeps(opts)
  opts = opts or {}
  return {
    printFn = opts.printFn or print,
    getL = opts.getL or function()
      return {}
    end,
    getState = opts.getState or function()
      return {}
    end,
    setState = opts.setState or function(_patch) end,
    triggerGroupRosterUpdate = opts.triggerGroupRosterUpdate or function() end,
    toggleStandardTestMode = opts.toggleStandardTestMode or function() end,
    enterFullDummyPreview = opts.enterFullDummyPreview or function() end,
    setMainFrameVisible = opts.setMainFrameVisible or function(_visible) end,
    getMainFrameLocked = opts.getMainFrameLocked or function()
      return true
    end,
    setMainFrameLocked = opts.setMainFrameLocked or function(_locked) end,
    resetMainFramePosition = opts.resetMainFramePosition or function() end,
    updateLeaderButtons = opts.updateLeaderButtons or function() end,
    isPlayerLeader = opts.isPlayerLeader or function()
      return false
    end,
    setLanguage = opts.setLanguage or function(_language) end,
    forceTeleportTestTarget = opts.forceTeleportTestTarget or function() end,
    printTeleportDebug = opts.printTeleportDebug or function() end,
    setQueueDebugEnabled = opts.setQueueDebugEnabled or function(_enabled) end,
    getQueueDebugEnabled = opts.getQueueDebugEnabled or function()
      return false
    end,
    clearQueueDebugLog = opts.clearQueueDebugLog or function() end,
    getQueueDebugLogCount = opts.getQueueDebugLogCount or function()
      return 0
    end,
    getQueueDebugLogTail = opts.getQueueDebugLogTail or function(_limit)
      return {}
    end,
    setRuntimeLogEnabled = opts.setRuntimeLogEnabled or function(_enabled) end,
    getRuntimeLogEnabled = opts.getRuntimeLogEnabled or function()
      return false
    end,
    setRuntimeLogLevel = opts.setRuntimeLogLevel or function(_level) end,
    getRuntimeLogLevel = opts.getRuntimeLogLevel or function()
      return "normal"
    end,
    clearRuntimeLog = opts.clearRuntimeLog or function() end,
    getRuntimeLogCount = opts.getRuntimeLogCount or function()
      return 0
    end,
    getRuntimeLogTail = opts.getRuntimeLogTail or function(_limit)
      return {}
    end,
    getRuntimeLogTailFiltered = type(opts.getRuntimeLogTailFiltered) == "function" and opts.getRuntimeLogTailFiltered
      or nil,
    setRuntimeLogWatch = type(opts.setRuntimeLogWatch) == "function" and opts.setRuntimeLogWatch or nil,
    getRuntimeLogWatchActive = type(opts.getRuntimeLogWatchActive) == "function" and opts.getRuntimeLogWatchActive
      or nil,
    openTraceChatFrame = type(opts.openTraceChatFrame) == "function" and opts.openTraceChatFrame or nil,
    closeTraceChatFrame = type(opts.closeTraceChatFrame) == "function" and opts.closeTraceChatFrame or nil,
    isTraceChatFrameOpen = type(opts.isTraceChatFrameOpen) == "function" and opts.isTraceChatFrameOpen or nil,
    addTraceChatFrameMessage = type(opts.addTraceChatFrameMessage) == "function" and opts.addTraceChatFrameMessage
      or nil,
    resetDB = opts.resetDB or function() end,
    toggleNameplateTestMode = type(opts.toggleNameplateTestMode) == "function" and opts.toggleNameplateTestMode
      or function()
        return false
      end,
    dumpNameplateState = type(opts.dumpNameplateState) == "function" and opts.dumpNameplateState or function() end,
    logRuntimeTrace = type(opts.logRuntimeTrace) == "function" and opts.logRuntimeTrace or nil,
    logRuntimeTracef = type(opts.logRuntimeTracef) == "function" and opts.logRuntimeTracef or nil,
  }
end

-- Ordered list mirrors the command handlers in TryHandle*Commands below.
-- Keep in sync when adding a new slash command.
local HELP_KEYS = {
  "HELP_HEADER",
  "HELP_TEST",
  "HELP_TESTALL",
  "HELP_TPTEST",
  "HELP_TPDEBUG",
  "HELP_LOG",
  "HELP_QDEBUG",
  "HELP_LOCK",
  "HELP_UNLOCK",
  "HELP_RESETUI",
  "HELP_BINDCHECK",
  "HELP_PAUSE",
  "HELP_RESUME",
  "HELP_STOP",
  "HELP_START",
  "HELP_LEAD",
  "HELP_LANG",
  "HELP_RESET",
}

local function PrintHelp(printFn, L)
  for _, key in ipairs(HELP_KEYS) do
    local line = L[key]
    if type(line) == "string" and line ~= "" then
      printFn(line)
    end
  end
end

local ARG_ON = { on = true, ["1"] = true, ["true"] = true }
local ARG_OFF = { off = true, ["0"] = true, ["false"] = true }

-- Generic handler for debug log sub-commands (shared by "log" and "qdebug").
-- cfg fields: prefix, label, extraOn (table), extraOff (table),
--             getEnabled, setEnabled, getLevel, setLevel, clearLog, getCount,
--             getTail, usageStr
local function HandleDebugLogCommand(ctx, cmd, cfg)
  local arg, restText = cmd:match("^" .. cfg.prefix .. "%s+(%S+)%s*(.-)%s*$")
  if not arg or arg == "status" then
    local levelText = cfg.getLevel and (" | level: " .. tostring(cfg.getLevel())) or ""
    ctx.printFn(
      cfg.label
        .. ": "
        .. (cfg.getEnabled() and "ON" or "OFF")
        .. levelText
        .. " | entries: "
        .. tostring(cfg.getCount())
    )
    return
  end

  if cfg.setLevel and cfg.getLevel and (arg == "level" or arg == "normal" or arg == "deep") then
    local requestedLevel = arg == "level" and tostring(restText or "") or arg
    if requestedLevel == "normal" or requestedLevel == "deep" then
      cfg.setLevel(requestedLevel)
      ctx.printFn(cfg.label .. " level: " .. tostring(cfg.getLevel()))
      return
    end
    ctx.printFn(cfg.label .. " level: " .. tostring(cfg.getLevel()))
    return
  end

  if ARG_ON[arg] or (cfg.extraOn and cfg.extraOn[arg]) then
    cfg.setEnabled(true)
    ctx.printFn(cfg.label .. ": ON")
    return
  end
  if ARG_OFF[arg] or (cfg.extraOff and cfg.extraOff[arg]) then
    cfg.setEnabled(false)
    ctx.printFn(cfg.label .. ": OFF")
    return
  end
  if arg == "clear" then
    cfg.clearLog()
    ctx.printFn(cfg.label .. ": cleared")
    return
  end

  if arg == "tail" or arg == "dump" then
    local limitStr, tagFilter = (restText or ""):match("^(%S*)%s*(.-)%s*$")
    local limit = tonumber(limitStr) or 20
    if limit < 1 then
      limit = 1
    elseif limit > 100 then
      limit = 100
    end
    local lines, totalFiltered
    if cfg.getFilteredTail and tagFilter and tagFilter ~= "" then
      lines, totalFiltered = cfg.getFilteredTail(limit, tagFilter)
    else
      lines = cfg.getTail(limit)
    end
    local header = cfg.label .. " tail: " .. tostring(#lines)
    if totalFiltered then
      header = header .. "/" .. tostring(totalFiltered) .. " (filter=" .. tagFilter .. ")"
    else
      header = header .. "/" .. tostring(cfg.getCount()) .. " entries"
    end
    ctx.printFn(header)
    for _, line in ipairs(lines) do
      ctx.printFn(tostring(line))
    end
    return
  end

  if arg == "watch" then
    if not cfg.setWatchFn then
      ctx.printFn(cfg.label .. ": watch not supported")
      return
    end
    if cfg.getWatchActive and cfg.getWatchActive() then
      cfg.setWatchFn(nil)
      if cfg.closeTraceChatFrame then
        cfg.closeTraceChatFrame()
      end
      ctx.printFn(cfg.label .. ": watch OFF")
    else
      local inWatch = false
      local rawPrint = rawget(_G, "print") or print
      local sink
      if cfg.openTraceChatFrame and cfg.addTraceChatFrameMessage then
        cfg.openTraceChatFrame()
        sink = cfg.addTraceChatFrameMessage
        ctx.printFn(cfg.label .. ": watch ON (entries stream to trace chat tab)")
      else
        sink = function(entry)
          rawPrint("[watch] " .. tostring(entry))
        end
        ctx.printFn(cfg.label .. ": watch ON (new entries will be printed live)")
      end
      cfg.setWatchFn(function(entry)
        if inWatch then
          return
        end
        inWatch = true
        local ok, err = pcall(sink, entry)
        inWatch = false
        if not ok then
          rawPrint("isiLive watch sink error: " .. tostring(err))
        end
      end)
    end
    return
  end

  ctx.printFn(cfg.usageStr)
end

local function HandleLogCommand(ctx, cmd)
  HandleDebugLogCommand(ctx, cmd, {
    prefix = "log",
    label = "Runtime log",
    extraOn = { start = true },
    extraOff = { stop = true },
    getEnabled = ctx.getRuntimeLogEnabled,
    setEnabled = ctx.setRuntimeLogEnabled,
    getLevel = ctx.getRuntimeLogLevel,
    setLevel = ctx.setRuntimeLogLevel,
    clearLog = ctx.clearRuntimeLog,
    getCount = ctx.getRuntimeLogCount,
    getTail = ctx.getRuntimeLogTail,
    getFilteredTail = ctx.getRuntimeLogTailFiltered,
    setWatchFn = ctx.setRuntimeLogWatch,
    getWatchActive = ctx.getRuntimeLogWatchActive,
    openTraceChatFrame = ctx.openTraceChatFrame,
    closeTraceChatFrame = ctx.closeTraceChatFrame,
    addTraceChatFrameMessage = ctx.addTraceChatFrameMessage,
    usageStr = "Usage: /isilive log [on|off|start|stop|status|level normal|deep|clear|tail [n [TAG]]|watch]",
  })
end

local function HandleQDebugCommand(ctx, cmd)
  HandleDebugLogCommand(ctx, cmd, {
    prefix = "qdebug",
    label = "Queue debug",
    getEnabled = ctx.getQueueDebugEnabled,
    setEnabled = ctx.setQueueDebugEnabled,
    clearLog = ctx.clearQueueDebugLog,
    getCount = ctx.getQueueDebugLogCount,
    getTail = ctx.getQueueDebugLogTail,
    usageStr = "Usage: /isilive qdebug [on|off|status|clear|tail [n]]",
  })
end

local function HandleBindCheck(printFn)
  local action1 = GetBindingAction("CTRL-F9", true)
  local action2 = GetBindingAction("CTRL-ALT-F9", true)
  local action3 = GetBindingAction("ALT-CTRL-F9", true)
  printFn("CTRL-F9 => " .. (action1 and action1 ~= "" and action1 or "<none>"))
  printFn("CTRL-ALT-F9 => " .. (action2 and action2 ~= "" and action2 or "<none>"))
  printFn("ALT-CTRL-F9 => " .. (action3 and action3 ~= "" and action3 or "<none>"))
end

local function TryHandleTestCommands(ctx, L, state, cmd)
  if cmd == "test" then
    ctx.toggleStandardTestMode()
    return true
  end

  if cmd == "testall" then
    if state.isStopped then
      ctx.printFn(L.ERR_STOPPED_TEST)
      return true
    end
    if state.isPaused then
      ctx.printFn(L.ERR_PAUSED_TEST)
      return true
    end
    ctx.enterFullDummyPreview()
    return true
  end

  return false
end

local function TryHandleStateCommands(ctx, L, state, cmd)
  if cmd == "stop" then
    ctx.setState({
      isStopped = true,
      isPaused = false,
      isTestMode = false,
      isTestAllMode = false,
      wasGroupLeader = nil,
    })
    ctx.setMainFrameVisible(false)
    ctx.updateLeaderButtons()
    ctx.printFn(L.STOPPED)
    return true
  end

  if cmd == "pause" then
    if state.isStopped then
      ctx.printFn(L.ERR_STOPPED_USE_START)
      return true
    end
    ctx.setState({
      isPaused = true,
      isTestMode = false,
      isTestAllMode = false,
    })
    ctx.setMainFrameVisible(false)
    ctx.updateLeaderButtons()
    ctx.printFn(L.PAUSED)
    return true
  end

  if cmd == "resume" then
    if state.isStopped then
      ctx.printFn(L.ERR_STOPPED_USE_START)
      return true
    end
    ctx.setState({
      isPaused = false,
      isTestMode = false,
      isTestAllMode = false,
    })
    ctx.updateLeaderButtons()
    ctx.printFn(L.RESUMED)
    ctx.triggerGroupRosterUpdate()
    return true
  end

  if cmd == "start" then
    ctx.setState({
      isStopped = false,
      isPaused = false,
      isTestMode = false,
      isTestAllMode = false,
    })
    ctx.updateLeaderButtons()
    ctx.printFn(L.STARTED)
    ctx.triggerGroupRosterUpdate()
    return true
  end

  return false
end

local function TryHandleLockCommands(ctx, L, cmd)
  if cmd == "lock" then
    ctx.setMainFrameLocked(true)
    ctx.printFn(L.LOCKED)
    return true
  end

  if cmd == "unlock" then
    ctx.setMainFrameLocked(false)
    ctx.printFn(L.UNLOCKED)
    return true
  end

  if cmd == "resetui" then
    ctx.resetMainFramePosition()
    ctx.printFn(L.RESETUI_DONE)
    return true
  end

  return false
end

local function TryHandleInfoCommands(ctx, L, cmd)
  if cmd == "lead" then
    ctx.printFn(ctx.isPlayerLeader() and L.LEAD_STATUS_YES or L.LEAD_STATUS_NO)
    return true
  end

  if cmd:find("^lang") == 1 then
    local arg = cmd:match("^lang%s+(%S+)$")
    if arg and addonTable.Languages.IsSupported(arg) then
      ctx.setLanguage(arg)
    else
      ctx.printFn(L.LANG_USAGE)
    end
    return true
  end

  return false
end

local function TryHandleUtilityCommands(ctx, cmd)
  if cmd == "tptest" then
    ctx.forceTeleportTestTarget()
    return true
  end

  if cmd == "tpdebug" then
    ctx.printTeleportDebug()
    return true
  end

  if cmd == "log" or cmd:find("^log%s+") == 1 then
    HandleLogCommand(ctx, cmd)
    return true
  end

  if cmd == "qdebug" or cmd:find("^qdebug%s+") == 1 then
    HandleQDebugCommand(ctx, cmd)
    return true
  end

  if cmd == "bindcheck" then
    HandleBindCheck(ctx.printFn)
    return true
  end

  if cmd == "reset" then
    ctx.resetDB()
    return true
  end

  if cmd == "nptest" or cmd:find("^nptest%s+") == 1 then
    local arg = nil
    local space = cmd:find("%s+")
    if space then
      arg = strtrim(cmd:sub(space + 1))
    end
    local active = ctx.toggleNameplateTestMode(arg)
    if active then
      ctx.printFn("Nameplate test mode ON — target/mouseover any hostile mob to see the fake percent.")
    else
      ctx.printFn("Nameplate test mode OFF.")
    end
    return true
  end

  if cmd == "npstate" or cmd:find("^npstate%s+") == 1 then
    local arg = nil
    local space = cmd:find("%s+")
    if space then
      arg = strtrim(cmd:sub(space + 1))
    end
    ctx.dumpNameplateState(arg)
    return true
  end

  return false
end

local function ExecuteSlashCommand(ctx, msg)
  local L = ctx.getL() or {}
  local state = ctx.getState() or {}
  local cmd = string.lower(strtrim(msg or ""))
  if ctx.logRuntimeTracef then
    ctx.logRuntimeTracef("[CMD] execute cmd=%s", tostring(cmd))
  end

  if TryHandleTestCommands(ctx, L, state, cmd) then
    return
  end
  if TryHandleStateCommands(ctx, L, state, cmd) then
    return
  end
  if TryHandleLockCommands(ctx, L, cmd) then
    return
  end
  if TryHandleInfoCommands(ctx, L, cmd) then
    return
  end
  if TryHandleUtilityCommands(ctx, cmd) then
    return
  end

  PrintHelp(ctx.printFn, L)
end

function Commands.RegisterSlashCommands(opts)
  local deps = BuildDeps(opts)

  SLASH_ISILIVE1 = "/isilive"
  SLASH_ISILIVE2 = "/il"
  SlashCmdList["ISILIVE"] = function(msg)
    ExecuteSlashCommand(deps, msg)
  end
end
