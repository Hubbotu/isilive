---@diagnostic disable: undefined-global
return function(test, ctx)
  local Assert = ctx.assert
  local LoadAddonModules = ctx.load_modules

  local function LoadHelpers()
    local addon = LoadAddonModules({ "isiLive_roster_panel_helpers.lua" })
    return addon._RosterInternal
  end

  test("ApplyFontStringSize returns silently for nil fontString", function()
    local RI = LoadHelpers()
    -- Must not throw; uncovered early-return guard.
    RI.ApplyFontStringSize(nil, 12)
  end)

  test("ApplyFontStringSize ignores objects without GetFont/SetFont", function()
    local RI = LoadHelpers()
    RI.ApplyFontStringSize({}, 14)
    RI.ApplyFontStringSize({ GetFont = function() end }, 14)
  end)

  test("ApplyFontStringSize ignores empty or non-string fontPath", function()
    local RI = LoadHelpers()
    local setCalls = 0
    local stub = {
      GetFont = function()
        return "", 12, "OUTLINE"
      end,
      SetFont = function()
        setCalls = setCalls + 1
      end,
    }
    RI.ApplyFontStringSize(stub, 18)
    Assert.Equal(setCalls, 0, "empty fontPath must skip SetFont")

    stub.GetFont = function()
      return nil, 12, "OUTLINE"
    end
    RI.ApplyFontStringSize(stub, 18)
    Assert.Equal(setCalls, 0, "nil fontPath must skip SetFont")
  end)

  test("ApplyFontStringSize calls SetFont with new size and preserved flags", function()
    local RI = LoadHelpers()
    local captured
    local stub = {
      GetFont = function()
        return "Fonts\\FRIZQT__.TTF", 11, "OUTLINE"
      end,
      SetFont = function(_, path, size, flags)
        captured = { path = path, size = size, flags = flags }
      end,
    }
    RI.ApplyFontStringSize(stub, 22)
    Assert.Equal(captured.path, "Fonts\\FRIZQT__.TTF", "font path must be preserved")
    Assert.Equal(captured.size, 22, "size must be the new value")
    Assert.Equal(captured.flags, "OUTLINE", "flags must be preserved")
  end)

  test("FormatMplusTime formats positive seconds as M:SS", function()
    local RI = LoadHelpers()
    Assert.Equal(RI.FormatMplusTime(0), "0:00", "zero seconds")
    Assert.Equal(RI.FormatMplusTime(5), "0:05", "single digit seconds pad to two digits")
    Assert.Equal(RI.FormatMplusTime(59), "0:59", "boundary just before minute")
    Assert.Equal(RI.FormatMplusTime(60), "1:00", "exactly one minute")
    Assert.Equal(RI.FormatMplusTime(125), "2:05", "two minutes five seconds")
    Assert.Equal(RI.FormatMplusTime(3599), "59:59", "just under one hour")
  end)

  test("FormatMplusTime treats negative seconds via abs (no leading minus)", function()
    local RI = LoadHelpers()
    -- Helper returns the absolute formatted time; the minus prefix for
    -- "over time" is added by callers (see roster_panel_cd_row mp1Text path).
    Assert.Equal(RI.FormatMplusTime(-30), "0:30", "negative seconds use abs value")
    Assert.Equal(RI.FormatMplusTime(-125), "2:05", "negative minutes/seconds use abs value")
  end)

  test("SetFontStringTextColorSafe forwards rgb to SetTextColor", function()
    local RI = LoadHelpers()
    local captured
    local stub = {
      SetTextColor = function(_, r, g, b)
        captured = { r, g, b }
      end,
    }
    RI.SetFontStringTextColorSafe(stub, 0.4, 1.0, 0.4)
    Assert.Equal(captured[1], 0.4, "r forwarded")
    Assert.Equal(captured[2], 1.0, "g forwarded")
    Assert.Equal(captured[3], 0.4, "b forwarded")
  end)

  test("SetFontStringTextColorSafe is a no-op for nil and SetTextColor-less objects", function()
    local RI = LoadHelpers()
    -- Both branches must not throw.
    RI.SetFontStringTextColorSafe(nil, 1, 1, 1)
    RI.SetFontStringTextColorSafe({}, 1, 1, 1)
  end)
end
