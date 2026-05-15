---@diagnostic disable: undefined-global

-- Branch-coverage scenarios for ui/isiLive_roster_panel_kill_row.lua.
-- The active-data update path (RI.UpdateKillTrackRow with
-- KillTrack.GetData() returning data.active = true) is fully
-- uncovered. This file drives every percentage band, the in-combat
-- pull-percent overlay, and the pull-width clamp by feeding a
-- KillTrack stub plus a row-shaped table directly into UpdateKillTrackRow.

local function NewBarStub(getWidth)
  local bar = {
    _shown = false,
    _width = 0,
    _color = nil,
  }
  function bar.SetWidth(self, w)
    self._width = w
  end
  function bar.SetVertexColor(self, r, g, b)
    self._color = { r, g, b }
  end
  function bar.SetTexture(self, _path) end
  function bar.SetPoint(self, ...) end
  function bar.Show(self)
    self._shown = true
  end
  function bar.Hide(self)
    self._shown = false
  end
  function bar.GetWidth(self)
    return getWidth and getWidth(self) or self._width
  end
  return bar
end

local function NewFontStringStub()
  local fs = {
    _text = "",
    _color = nil,
  }
  function fs.SetText(self, text)
    self._text = text
  end
  function fs.SetTextColor(self, r, g, b)
    self._color = { r, g, b }
  end
  function fs.SetJustifyH(self, justifyH)
    self._justifyH = justifyH
  end
  return fs
end

local function NewRow(barContainerWidth)
  return {
    killTrackBarContainer = {
      GetWidth = function()
        return barContainerWidth or 100
      end,
    },
    killTrackBarFill = NewBarStub(),
    killTrackBarPull = NewBarStub(),
    killTrackTargetText = NewFontStringStub(),
    killTrackPctText = NewFontStringStub(),
    killTrackPullText = NewFontStringStub(),
  }
end

return function(test, ctx)
  local Assert = ctx.assert
  local LoadAddonModules = ctx.load_modules
  local WithGlobals = ctx.with_globals

  local function LoadKillRow(killTrackData)
    local addon = LoadAddonModules({ "isiLive_roster_panel_helpers.lua", "isiLive_roster_panel_kill_row.lua" })
    addon.KillTrack = {
      GetData = function()
        return killTrackData
      end,
    }
    return addon
  end

  -- Early return ---------------------------------------------------------------

  test("UpdateKillTrackRow returns silently for nil row", function()
    WithGlobals({}, function()
      local addon = LoadKillRow(nil)
      addon._RosterInternal.UpdateKillTrackRow(nil)
    end)
  end)

  -- Inactive data: reset path (already partly covered, asserted explicitly) ----

  test("UpdateKillTrackRow hides bars and resets pct text when data is missing", function()
    WithGlobals({}, function()
      local addon = LoadKillRow(nil) -- KillTrack returns nil data
      local row = NewRow()
      row.killTrackBarFill._shown = true
      row.killTrackBarPull._shown = true
      addon._RosterInternal.UpdateKillTrackRow(row)
      Assert.True(row.killTrackBarFill._shown == false, "fill bar must hide")
      Assert.True(row.killTrackBarPull._shown == false, "pull bar must hide")
      Assert.Equal(row.killTrackTargetText._text, "", "target text must clear")
      Assert.Equal(row.killTrackPctText._text, "--,--", "pct text must reset")
      Assert.Equal(row.killTrackPullText._text, "", "pull text must clear")
    end)
  end)

  test("UpdateKillTrackRow resets bars when data.active is false", function()
    WithGlobals({}, function()
      local addon = LoadKillRow({ active = false, percent = 50 })
      local row = NewRow()
      row.killTrackBarFill._shown = true
      addon._RosterInternal.UpdateKillTrackRow(row)
      Assert.True(row.killTrackBarFill._shown == false, "inactive must hide fill bar")
      Assert.Equal(row.killTrackPctText._text, "--,--", "inactive must reset pct text")
    end)
  end)

  test(
    "UpdateKillTrackRow renders verified target key as right-aligned combined text before challenge start",
    function()
      WithGlobals({}, function()
        local addon = LoadKillRow({ active = false, percent = 0 })
        local row = NewRow()
        row.killTrackBarFill._shown = true
        row.killTrackBarPull._shown = true
        addon._RosterInternal.UpdateKillTrackRow(row, {
          getTargetDungeonInfo = function()
            return {
              name = "  Windlaeufer Turm  ",
              level = 14,
            }
          end,
          isInChallengeMode = function()
            return false
          end,
        })
        Assert.True(row.killTrackBarFill._shown == false, "pre-key target must hide percent fill")
        Assert.True(row.killTrackBarPull._shown == false, "pre-key target must hide pull overlay")
        Assert.Equal(
          row.killTrackTargetText._text,
          "Windlaeufer Turm +14",
          "pre-key target must show dungeon and level"
        )
        Assert.Equal(row.killTrackTargetText._justifyH, "RIGHT", "pre-key target must be right-aligned")
        Assert.Equal(row.killTrackPctText._text, "", "pre-key target must not split the level into the percent field")
        Assert.Equal(row.killTrackPullText._text, "", "pre-key target must clear pull text")
      end)
    end
  )

  test("UpdateKillTrackRow suppresses target key after challenge start until percent data is active", function()
    WithGlobals({}, function()
      local addon = LoadKillRow({ active = false, percent = 0 })
      local row = NewRow()
      addon._RosterInternal.UpdateKillTrackRow(row, {
        getTargetDungeonInfo = function()
          return {
            name = "Windlaeufer Turm",
            level = 14,
          }
        end,
        isInChallengeMode = function()
          return true
        end,
      })
      Assert.Equal(row.killTrackTargetText._text, "", "key-start boundary must clear pre-key target text")
      Assert.Equal(row.killTrackPctText._text, "--,--", "inactive post-start row must use the percent placeholder")
    end)
  end)

  -- Active path: green band (pct < 80) -----------------------------------------

  test("UpdateKillTrackRow renders green fill when percent < 80", function()
    WithGlobals({}, function()
      local addon = LoadKillRow({ active = true, percent = 50 })
      local row = NewRow(200)
      addon._RosterInternal.UpdateKillTrackRow(row)
      local fill = row.killTrackBarFill
      Assert.True(fill._shown == true, "fill must show for active data")
      Assert.Equal(fill._width, 100, "fill width must be 50% of 200")
      Assert.Equal(fill._color[1], 0.2, "green r")
      Assert.Equal(fill._color[2], 0.75, "green g")
      Assert.Equal(fill._color[3], 0.35, "green b")
      Assert.Equal(row.killTrackPctText._text, "50,00%", "pct text must be 50,00%% with comma")
      Assert.Equal(row.killTrackPctText._color[1], 0.2, "pct text color matches band")
    end)
  end)

  -- Active path: yellow band (80 <= pct < 95) ---------------------------------

  test("UpdateKillTrackRow renders yellow fill when 80 <= percent < 95", function()
    WithGlobals({}, function()
      local addon = LoadKillRow({ active = true, percent = 90 })
      local row = NewRow(200)
      addon._RosterInternal.UpdateKillTrackRow(row)
      Assert.Equal(row.killTrackBarFill._color[1], 0.9, "yellow r")
      Assert.Equal(row.killTrackBarFill._color[2], 0.75, "yellow g")
      Assert.Equal(row.killTrackBarFill._color[3], 0.1, "yellow b")
    end)
  end)

  -- Active path: red band (pct >= 95) ------------------------------------------

  test("UpdateKillTrackRow renders red fill when percent >= 95", function()
    WithGlobals({}, function()
      local addon = LoadKillRow({ active = true, percent = 99 })
      local row = NewRow(200)
      addon._RosterInternal.UpdateKillTrackRow(row)
      Assert.Equal(row.killTrackBarFill._color[1], 0.9, "red r")
      Assert.Equal(row.killTrackBarFill._color[2], 0.3, "red g")
      Assert.Equal(row.killTrackBarFill._color[3], 0.15, "red b")
    end)
  end)

  -- Active path: percent clamped to 100 ----------------------------------------

  test("UpdateKillTrackRow clamps percent to [0, 100]", function()
    WithGlobals({}, function()
      local addon = LoadKillRow({ active = true, percent = 130 })
      local row = NewRow(200)
      addon._RosterInternal.UpdateKillTrackRow(row)
      Assert.Equal(row.killTrackBarFill._width, 200, "clamped percent must yield full width")
      Assert.Equal(row.killTrackPctText._text, "100,00%", "pct text must be clamped to 100")
    end)
  end)

  -- Active path: zero-width fill bar hides instead of showing ------------------

  test("UpdateKillTrackRow hides fill bar when computed width rounds to 0", function()
    WithGlobals({}, function()
      local addon = LoadKillRow({ active = true, percent = 0 })
      local row = NewRow(200)
      addon._RosterInternal.UpdateKillTrackRow(row)
      Assert.True(row.killTrackBarFill._shown == false, "0%% percent must hide fill bar")
    end)
  end)

  -- Active path: in-combat pull overlay ----------------------------------------

  test("UpdateKillTrackRow shows pull overlay during combat with pullPercent > 0", function()
    WithGlobals({}, function()
      local addon = LoadKillRow({ active = true, percent = 50, inCombat = true, pullPercent = 20 })
      local row = NewRow(200)
      addon._RosterInternal.UpdateKillTrackRow(row)
      Assert.True(row.killTrackBarPull._shown == true, "pull bar must show in combat")
      Assert.Equal(row.killTrackBarPull._width, 40, "pull width = 20% of 200 = 40")
      Assert.Equal(row.killTrackPullText._text, "+20,00%", "pull text must show pull percent with plus prefix")
      Assert.Equal(row.killTrackPullText._color[1], 0.6, "pull text color r")
    end)
  end)

  test("UpdateKillTrackRow clamps pull width when fill + pull would exceed bar width", function()
    WithGlobals({}, function()
      -- 200 wide, fill = 80% (160), pull = 30% (60). 160 + 60 = 220 > 200,
      -- so pull width must be clamped to (200 - 160) = 40.
      local addon = LoadKillRow({ active = true, percent = 80, inCombat = true, pullPercent = 30 })
      local row = NewRow(200)
      addon._RosterInternal.UpdateKillTrackRow(row)
      Assert.Equal(row.killTrackBarPull._width, 40, "pull width must be clamped to remaining space")
    end)
  end)

  test("UpdateKillTrackRow hides pull overlay outside of combat", function()
    WithGlobals({}, function()
      local addon = LoadKillRow({ active = true, percent = 50, inCombat = false, pullPercent = 20 })
      local row = NewRow(200)
      addon._RosterInternal.UpdateKillTrackRow(row)
      Assert.True(row.killTrackBarPull._shown == false, "no combat must hide pull bar")
      Assert.Equal(row.killTrackPullText._text, "", "no combat must clear pull text")
    end)
  end)

  test("UpdateKillTrackRow hides pull overlay when pullPercent is zero", function()
    WithGlobals({}, function()
      local addon = LoadKillRow({ active = true, percent = 50, inCombat = true, pullPercent = 0 })
      local row = NewRow(200)
      addon._RosterInternal.UpdateKillTrackRow(row)
      Assert.True(row.killTrackBarPull._shown == false, "zero pull must hide pull bar")
    end)
  end)
end
