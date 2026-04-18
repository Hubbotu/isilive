---@diagnostic disable: undefined-global
return function(test, ctx)
  local Assert = ctx.assert
  local LoadAddonModules = ctx.load_modules

  local function loadRI()
    return LoadAddonModules({ "isiLive_roster_layout.lua" })._RosterInternal
  end

  -- NormalizeLayoutMode

  test("RosterLayout NormalizeLayoutMode maps nil to expanded", function()
    local RI = loadRI()
    Assert.Equal(RI.NormalizeLayoutMode(nil), RI.LAYOUT_MODE_EXPANDED)
  end)

  test("RosterLayout NormalizeLayoutMode maps unknown string to expanded", function()
    local RI = loadRI()
    Assert.Equal(RI.NormalizeLayoutMode("not_a_real_mode"), RI.LAYOUT_MODE_EXPANDED)
  end)

  test("RosterLayout NormalizeLayoutMode returns compact_vertical unchanged", function()
    local RI = loadRI()
    Assert.Equal(RI.NormalizeLayoutMode(RI.LAYOUT_MODE_COMPACT_VERTICAL), RI.LAYOUT_MODE_COMPACT_VERTICAL)
  end)

  test("RosterLayout NormalizeLayoutMode returns compact_horizontal unchanged", function()
    local RI = loadRI()
    Assert.Equal(RI.NormalizeLayoutMode(RI.LAYOUT_MODE_COMPACT_HORIZONTAL), RI.LAYOUT_MODE_COMPACT_HORIZONTAL)
  end)

  test("RosterLayout NormalizeLayoutMode returns compact_main_horizontal unchanged", function()
    local RI = loadRI()
    Assert.Equal(RI.NormalizeLayoutMode(RI.LAYOUT_MODE_COMPACT_MAIN_HORIZONTAL), RI.LAYOUT_MODE_COMPACT_MAIN_HORIZONTAL)
  end)

  test("RosterLayout NormalizeLayoutMode migrates legacy compact_horizontal_2 to compact_main_horizontal", function()
    local RI = loadRI()
    Assert.Equal(RI.NormalizeLayoutMode("compact_horizontal_2"), RI.LAYOUT_MODE_COMPACT_MAIN_HORIZONTAL)
  end)

  -- IsCompactLayoutMode

  test("RosterLayout IsCompactLayoutMode returns true for compact_vertical", function()
    local RI = loadRI()
    Assert.True(RI.IsCompactLayoutMode(RI.LAYOUT_MODE_COMPACT_VERTICAL))
  end)

  test("RosterLayout IsCompactLayoutMode returns true for compact_horizontal", function()
    local RI = loadRI()
    Assert.True(RI.IsCompactLayoutMode(RI.LAYOUT_MODE_COMPACT_HORIZONTAL))
  end)

  test("RosterLayout IsCompactLayoutMode returns false for expanded", function()
    local RI = loadRI()
    Assert.False(RI.IsCompactLayoutMode(RI.LAYOUT_MODE_EXPANDED))
  end)

  test("RosterLayout IsCompactLayoutMode returns false for compact_main_horizontal", function()
    local RI = loadRI()
    Assert.False(
      RI.IsCompactLayoutMode(RI.LAYOUT_MODE_COMPACT_MAIN_HORIZONTAL),
      "M2 mode uses its own toolbar row — IsCompactLayoutMode must not include it"
    )
  end)

  -- IsHorizontalCompactLayoutMode

  test("RosterLayout IsHorizontalCompactLayoutMode returns true only for compact_horizontal", function()
    local RI = loadRI()
    Assert.True(RI.IsHorizontalCompactLayoutMode(RI.LAYOUT_MODE_COMPACT_HORIZONTAL))
    Assert.False(RI.IsHorizontalCompactLayoutMode(RI.LAYOUT_MODE_COMPACT_VERTICAL))
    Assert.False(RI.IsHorizontalCompactLayoutMode(RI.LAYOUT_MODE_COMPACT_MAIN_HORIZONTAL))
    Assert.False(RI.IsHorizontalCompactLayoutMode(RI.LAYOUT_MODE_EXPANDED))
  end)

  -- IsMainHorizontalLayoutMode

  test("RosterLayout IsMainHorizontalLayoutMode returns true only for compact_main_horizontal", function()
    local RI = loadRI()
    Assert.True(RI.IsMainHorizontalLayoutMode(RI.LAYOUT_MODE_COMPACT_MAIN_HORIZONTAL))
    Assert.False(RI.IsMainHorizontalLayoutMode(RI.LAYOUT_MODE_COMPACT_HORIZONTAL))
    Assert.False(RI.IsMainHorizontalLayoutMode(RI.LAYOUT_MODE_COMPACT_VERTICAL))
    Assert.False(RI.IsMainHorizontalLayoutMode(RI.LAYOUT_MODE_EXPANDED))
  end)

  test("RosterLayout IsMainHorizontalLayoutMode accepts legacy compact_horizontal_2 alias", function()
    local RI = loadRI()
    Assert.True(
      RI.IsMainHorizontalLayoutMode("compact_horizontal_2"),
      "legacy alias must resolve to compact_main_horizontal"
    )
  end)

  -- IsHorizontalToolbarLayoutMode

  test(
    "RosterLayout IsHorizontalToolbarLayoutMode returns true for compact_horizontal and compact_main_horizontal",
    function()
      local RI = loadRI()
      Assert.True(RI.IsHorizontalToolbarLayoutMode(RI.LAYOUT_MODE_COMPACT_HORIZONTAL))
      Assert.True(RI.IsHorizontalToolbarLayoutMode(RI.LAYOUT_MODE_COMPACT_MAIN_HORIZONTAL))
      Assert.False(RI.IsHorizontalToolbarLayoutMode(RI.LAYOUT_MODE_COMPACT_VERTICAL))
      Assert.False(RI.IsHorizontalToolbarLayoutMode(RI.LAYOUT_MODE_EXPANDED))
    end
  )

  -- GetFrameWidthForLayoutMode

  test("RosterLayout GetFrameWidthForLayoutMode returns full width for expanded", function()
    local RI = loadRI()
    Assert.Equal(RI.GetFrameWidthForLayoutMode(RI.LAYOUT_MODE_EXPANDED), RI.FULL_FRAME_WIDTH)
  end)

  test("RosterLayout GetFrameWidthForLayoutMode returns mini width for compact_vertical", function()
    local RI = loadRI()
    Assert.Equal(RI.GetFrameWidthForLayoutMode(RI.LAYOUT_MODE_COMPACT_VERTICAL), RI.MINI_FRAME_WIDTH)
  end)

  test("RosterLayout GetFrameWidthForLayoutMode returns mini horizontal width for compact_horizontal", function()
    local RI = loadRI()
    Assert.Equal(RI.GetFrameWidthForLayoutMode(RI.LAYOUT_MODE_COMPACT_HORIZONTAL), RI.MINI_HORIZONTAL_FRAME_WIDTH)
  end)

  test("RosterLayout GetFrameWidthForLayoutMode returns M2 width for compact_main_horizontal", function()
    local RI = loadRI()
    Assert.Equal(
      RI.GetFrameWidthForLayoutMode(RI.LAYOUT_MODE_COMPACT_MAIN_HORIZONTAL),
      RI.MINI_MAIN_HORIZONTAL_FRAME_WIDTH
    )
  end)

  test("RosterLayout GetFrameWidthForLayoutMode falls back to full width for unknown mode", function()
    local RI = loadRI()
    Assert.Equal(RI.GetFrameWidthForLayoutMode("unknown"), RI.FULL_FRAME_WIDTH)
  end)

  -- GetFrameHeightForLayoutMode

  test("RosterLayout GetFrameHeightForLayoutMode returns fixed mini height for compact_horizontal", function()
    local RI = loadRI()
    Assert.Equal(RI.GetFrameHeightForLayoutMode(RI.LAYOUT_MODE_COMPACT_HORIZONTAL), RI.MINI_HORIZONTAL_FRAME_HEIGHT)
  end)

  test(
    "RosterLayout GetFrameHeightForLayoutMode returns at least 272 for compact_main_horizontal with default min",
    function()
      local RI = loadRI()
      -- MINI_MAIN_HORIZONTAL_MIN_HEIGHT (244) + 28 = 272 when default minFrameHeight (236) is below the minimum
      local height = RI.GetFrameHeightForLayoutMode(RI.LAYOUT_MODE_COMPACT_MAIN_HORIZONTAL, nil)
      Assert.True(height >= 272, "M2 height must be at least MINI_MAIN_HORIZONTAL_MIN_HEIGHT + 28")
    end
  )

  test("RosterLayout GetFrameHeightForLayoutMode respects larger minFrameHeight for compact_main_horizontal", function()
    local RI = loadRI()
    local height = RI.GetFrameHeightForLayoutMode(RI.LAYOUT_MODE_COMPACT_MAIN_HORIZONTAL, 300)
    Assert.Equal(height, 328, "M2 height must be max(300, 244) + 28 = 328")
  end)

  test("RosterLayout GetFrameHeightForLayoutMode ignores minFrameHeight below M2 minimum", function()
    local RI = loadRI()
    local height = RI.GetFrameHeightForLayoutMode(RI.LAYOUT_MODE_COMPACT_MAIN_HORIZONTAL, 100)
    Assert.Equal(height, 272, "M2 height must clamp to MINI_MAIN_HORIZONTAL_MIN_HEIGHT (244) + 28 = 272")
  end)

  test("RosterLayout GetFrameHeightForLayoutMode returns default min for expanded mode", function()
    local RI = loadRI()
    Assert.Equal(
      RI.GetFrameHeightForLayoutMode(RI.LAYOUT_MODE_EXPANDED, nil),
      RI.DEFAULT_MIN_FRAME_HEIGHT,
      "expanded mode height must equal DEFAULT_MIN_FRAME_HEIGHT when no override given"
    )
  end)

  test("RosterLayout GetFrameHeightForLayoutMode honours custom min for expanded mode", function()
    local RI = loadRI()
    Assert.Equal(RI.GetFrameHeightForLayoutMode(RI.LAYOUT_MODE_EXPANDED, 400), 400)
  end)
end
