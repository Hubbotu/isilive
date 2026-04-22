---@diagnostic disable: undefined-global, undefined-field

-- Scenarios for ui/isiLive_trace_chat_frame.lua - exercises the full
-- Controller surface (Open/Close/Toggle/AddMessage/IsOpen) against
-- simulated Blizzard chat-frame APIs, covering both the "pre-existing
-- frame found" and "create a new frame" branches plus the defensive
-- no-API paths.

local function BuildChatFrameStub(name)
  local frame = {
    _name = name,
    _shown = false,
    _messages = {},
  }
  function frame:Show()
    self._shown = true
  end
  function frame:Hide()
    self._shown = false
  end
  function frame:IsShown()
    return self._shown == true
  end
  function frame:AddMessage(text, r, g, b)
    table.insert(self._messages, { text = text, r = r, g = g, b = b })
  end
  return frame
end

local function BuildTraceGlobals(overrides)
  overrides = overrides or {}
  local chatFrames = overrides.chatFrames or {}
  local removedGroupsFor = {}
  local selectedTab = nil

  local globals = {
    NUM_CHAT_WINDOWS = overrides.NUM_CHAT_WINDOWS or 3,
    GetChatWindowInfo = overrides.GetChatWindowInfo or function(i)
      local f = chatFrames[i]
      if f then
        return f._name
      end
      return nil
    end,
    FCF_OpenNewWindow = overrides.FCF_OpenNewWindow or function(name)
      local f = BuildChatFrameStub(name)
      -- Emulate the Blizzard behavior: after opening, the frame is
      -- exposed as a numbered ChatFrame global and picked up on the
      -- next FindExistingFrame scan.
      local idx = #chatFrames + 1
      chatFrames[idx] = f
      rawset(_G, "ChatFrame" .. idx, f)
      return f
    end,
    ChatFrame_RemoveAllMessageGroups = overrides.ChatFrame_RemoveAllMessageGroups or function(frame)
      removedGroupsFor[frame] = true
    end,
    FCF_SelectChatFrame = overrides.FCF_SelectChatFrame or function(frame)
      selectedTab = frame
    end,
  }

  for i, f in ipairs(chatFrames) do
    globals["ChatFrame" .. i] = f
  end

  -- Return the live state handles so tests can inspect post-conditions.
  return globals,
    {
      chatFrames = chatFrames,
      removedGroupsFor = removedGroupsFor,
      getSelectedTab = function()
        return selectedTab
      end,
    }
end

return function(test, ctx)
  local Assert = ctx.assert
  local LoadAddonModules = ctx.load_modules
  local WithGlobals = ctx.with_globals

  local function Load()
    return LoadAddonModules({ "isiLive_trace_chat_frame.lua" })
  end

  test("trace_chat_frame: Open finds an existing frame and activates its tab", function()
    local existing = BuildChatFrameStub("isiLive Trace")
    local globals, state = BuildTraceGlobals({ chatFrames = { BuildChatFrameStub("General"), existing } })
    WithGlobals(globals, function()
      local addon = Load()
      local controller = addon.TraceChatFrame.CreateController()
      controller.Open()
      Assert.Equal(existing._shown, true, "existing trace frame must be shown")
      Assert.Equal(state.getSelectedTab(), existing, "tab must be activated after Open")
    end)
  end)

  test("trace_chat_frame: Open creates a new frame and strips message groups when none exists", function()
    local globals, state = BuildTraceGlobals()
    WithGlobals(globals, function()
      local addon = Load()
      local controller = addon.TraceChatFrame.CreateController()
      controller.Open()
      local frame = state.chatFrames[1]
      Assert.NotNil(frame, "FCF_OpenNewWindow must be called to create the frame")
      Assert.Equal(frame._name, "isiLive Trace")
      Assert.Equal(frame._shown, true)
      Assert.Equal(state.removedGroupsFor[frame], true, "ChatFrame_RemoveAllMessageGroups must strip defaults")
    end)
  end)

  test("trace_chat_frame: Open is a no-op when FCF_OpenNewWindow is unavailable", function()
    local globals, state = BuildTraceGlobals()
    -- WithGlobals stubs iterate via pairs() which skips nil entries, so
    -- use rawset in the block body to actively remove the API.
    globals.FCF_OpenNewWindow = nil
    local previousFcf = rawget(_G, "FCF_OpenNewWindow")
    rawset(_G, "FCF_OpenNewWindow", nil)
    local ok, err = pcall(function()
      WithGlobals(globals, function()
        local addon = Load()
        local controller = addon.TraceChatFrame.CreateController()
        controller.Open()
        Assert.Equal(#state.chatFrames, 0, "missing FCF API must block frame creation")
      end)
    end)
    rawset(_G, "FCF_OpenNewWindow", previousFcf)
    if not ok then
      error(err, 0)
    end
  end)

  test("trace_chat_frame: Open without GetChatWindowInfo still creates a new frame", function()
    local globals = BuildTraceGlobals()
    globals.GetChatWindowInfo = false
    WithGlobals(globals, function()
      local addon = Load()
      local controller = addon.TraceChatFrame.CreateController()
      controller.Open()
      Assert.Equal(controller.IsOpen(), false, "IsOpen is false when FindExistingFrame cannot scan")
    end)
  end)

  test("trace_chat_frame: Close hides an existing trace frame", function()
    local existing = BuildChatFrameStub("isiLive Trace")
    existing._shown = true
    local globals = BuildTraceGlobals({ chatFrames = { existing } })
    WithGlobals(globals, function()
      local addon = Load()
      local controller = addon.TraceChatFrame.CreateController()
      controller.Close()
      Assert.Equal(existing._shown, false)
    end)
  end)

  test("trace_chat_frame: Close is a no-op when no trace frame has been created", function()
    local globals = BuildTraceGlobals()
    WithGlobals(globals, function()
      local addon = Load()
      local controller = addon.TraceChatFrame.CreateController()
      controller.Close()
      -- Nothing to assert beyond "did not raise"; verify no frame was created.
      Assert.Equal(controller.IsOpen(), false)
    end)
  end)

  test("trace_chat_frame: Toggle opens then closes", function()
    local globals, state = BuildTraceGlobals()
    WithGlobals(globals, function()
      local addon = Load()
      local controller = addon.TraceChatFrame.CreateController()
      controller.Toggle()
      Assert.Equal(controller.IsOpen(), true, "first toggle must open")
      controller.Toggle()
      Assert.Equal(controller.IsOpen(), false, "second toggle must close")
      local frame = state.chatFrames[1]
      Assert.NotNil(frame)
      Assert.Equal(frame._shown, false)
    end)
  end)

  test("trace_chat_frame: AddMessage forwards text with default rgb when called without color", function()
    local globals, state = BuildTraceGlobals()
    WithGlobals(globals, function()
      local addon = Load()
      local controller = addon.TraceChatFrame.CreateController()
      controller.AddMessage("hello")
      local frame = state.chatFrames[1]
      Assert.NotNil(frame)
      local msg = frame._messages[1]
      Assert.NotNil(msg)
      Assert.Equal(msg.text, "hello")
      Assert.Equal(msg.r, 0.7)
      Assert.Equal(msg.g, 0.9)
      Assert.Equal(msg.b, 1.0)
    end)
  end)

  test("trace_chat_frame: AddMessage respects explicit rgb values", function()
    local globals, state = BuildTraceGlobals()
    WithGlobals(globals, function()
      local addon = Load()
      local controller = addon.TraceChatFrame.CreateController()
      controller.AddMessage(42, 0.1, 0.2, 0.3)
      local frame = state.chatFrames[1]
      Assert.NotNil(frame)
      local msg = frame._messages[1]
      Assert.Equal(msg.text, "42", "non-string input must be coerced via tostring")
      Assert.Equal(msg.r, 0.1)
      Assert.Equal(msg.g, 0.2)
      Assert.Equal(msg.b, 0.3)
    end)
  end)

  test("trace_chat_frame: IsOpen returns false when FindExistingFrame returns nil", function()
    local globals = BuildTraceGlobals()
    WithGlobals(globals, function()
      local addon = Load()
      local controller = addon.TraceChatFrame.CreateController()
      Assert.Equal(controller.IsOpen(), false)
    end)
  end)

  test("trace_chat_frame: IsOpen reflects the current shown-state of an existing frame", function()
    local existing = BuildChatFrameStub("isiLive Trace")
    local globals = BuildTraceGlobals({ chatFrames = { existing } })
    WithGlobals(globals, function()
      local addon = Load()
      local controller = addon.TraceChatFrame.CreateController()
      Assert.Equal(controller.IsOpen(), false, "hidden frame must resolve IsOpen=false")
      existing._shown = true
      Assert.Equal(controller.IsOpen(), true)
    end)
  end)

  test("trace_chat_frame: reopening reuses the cached frameRef instead of creating a new one", function()
    local globals, state = BuildTraceGlobals()
    WithGlobals(globals, function()
      local addon = Load()
      local controller = addon.TraceChatFrame.CreateController()
      controller.Open()
      controller.Close()
      controller.Open()
      Assert.Equal(#state.chatFrames, 1, "cached frameRef must prevent a second FCF_OpenNewWindow call")
    end)
  end)
end
