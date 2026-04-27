---@diagnostic disable: undefined-global

-- Branch-coverage scenarios for the pure formatters in
-- ui/isiLive_roster_tooltip.lua. Commit 54b019f exposed the local
-- helpers (BuildFallbackTooltipPlayerName, FormatCompactTooltipNumber,
-- FormatSyncAge, FormatSyncDebugField, ResolveTooltipClassName,
-- IsSecretValue) via _RosterInternal so this file can drive every
-- branch of their formatting logic without going through the deeply
-- nested ShowRosterInfoTooltip pipeline.

return function(test, ctx)
  local Assert = ctx.assert
  local LoadAddonModules = ctx.load_modules
  local WithGlobals = ctx.with_globals

  local function LoadTooltip(globals)
    local addon
    WithGlobals(globals or {}, function()
      addon = LoadAddonModules({ "isiLive_roster_tooltip.lua" })
    end)
    return addon
  end

  -- IsSecretValue --------------------------------------------------------------

  test("IsSecretValue returns false when issecretvalue is not registered", function()
    local addon = LoadTooltip()
    Assert.False(addon._RosterInternal.IsSecretValue("anything"), "no issecretvalue must yield false")
  end)

  test("IsSecretValue returns true only when issecretvalue reports true", function()
    -- The local IsSecretValue calls the global at every invocation, so
    -- mutating _G.issecretvalue between calls works.
    local addon = LoadTooltip({
      issecretvalue = function(v)
        return v == "secret"
      end,
    })
    -- WithGlobals strips issecretvalue after the loader returns; we
    -- need to reinstall it to drive the real call sites.
    rawset(_G, "issecretvalue", function(v)
      return v == "secret"
    end)
    Assert.True(addon._RosterInternal.IsSecretValue("secret"), "matching predicate must yield true")
    Assert.False(addon._RosterInternal.IsSecretValue("plain"), "non-matching predicate must yield false")
    rawset(_G, "issecretvalue", nil)
  end)

  -- BuildFallbackTooltipPlayerName --------------------------------------------

  test("BuildFallbackTooltipPlayerName joins name and realm with a dash", function()
    local addon = LoadTooltip()
    Assert.Equal(addon._RosterInternal.BuildFallbackTooltipPlayerName("Aria", "Sanguino"), "Aria-Sanguino")
  end)

  test("BuildFallbackTooltipPlayerName returns name only when realm is empty", function()
    local addon = LoadTooltip()
    Assert.Equal(addon._RosterInternal.BuildFallbackTooltipPlayerName("Solo", ""), "Solo")
    Assert.Equal(addon._RosterInternal.BuildFallbackTooltipPlayerName("Solo", nil), "Solo")
  end)

  test("BuildFallbackTooltipPlayerName returns nil when name is blank or non-string", function()
    local addon = LoadTooltip()
    Assert.Nil(addon._RosterInternal.BuildFallbackTooltipPlayerName(nil, "Realm"))
    Assert.Nil(addon._RosterInternal.BuildFallbackTooltipPlayerName("", "Realm"))
    Assert.Nil(addon._RosterInternal.BuildFallbackTooltipPlayerName(42, "Realm"))
  end)

  -- FormatCompactTooltipNumber -------------------------------------------------

  test("FormatCompactTooltipNumber returns nil for non-numeric input", function()
    local addon = LoadTooltip()
    Assert.Nil(addon._RosterInternal.FormatCompactTooltipNumber("not-a-number"))
    Assert.Nil(addon._RosterInternal.FormatCompactTooltipNumber(nil))
  end)

  test("FormatCompactTooltipNumber prefers AbbreviateNumbers when present", function()
    local addon = LoadTooltip()
    rawset(_G, "AbbreviateNumbers", function(v)
      return "abbr-" .. tostring(v)
    end)
    Assert.Equal(addon._RosterInternal.FormatCompactTooltipNumber(12345), "abbr-12345")
    rawset(_G, "AbbreviateNumbers", nil)
  end)

  test("FormatCompactTooltipNumber falls back to in-house unit suffixing when AbbreviateNumbers is missing", function()
    local addon = LoadTooltip()
    rawset(_G, "AbbreviateNumbers", nil)
    Assert.Equal(addon._RosterInternal.FormatCompactTooltipNumber(2500000000), "2.5B", "billions suffix")
    Assert.Equal(addon._RosterInternal.FormatCompactTooltipNumber(2500000), "2.5M", "millions suffix")
    Assert.Equal(addon._RosterInternal.FormatCompactTooltipNumber(2500), "2.5K", "thousands suffix")
    -- .0 suffix is stripped via gsub
    Assert.Equal(addon._RosterInternal.FormatCompactTooltipNumber(3000), "3K", ".0 suffix must be stripped")
    Assert.Equal(addon._RosterInternal.FormatCompactTooltipNumber(2000000), "2M", ".0 suffix must be stripped")
    Assert.Equal(addon._RosterInternal.FormatCompactTooltipNumber(42), "42", "small numbers stay as-is")
  end)

  test("FormatCompactTooltipNumber falls back when AbbreviateNumbers raises or returns empty", function()
    local addon = LoadTooltip()
    rawset(_G, "AbbreviateNumbers", function()
      error("blizz error")
    end)
    Assert.Equal(addon._RosterInternal.FormatCompactTooltipNumber(2500), "2.5K", "pcall failure must trigger fallback")
    rawset(_G, "AbbreviateNumbers", function()
      return ""
    end)
    Assert.Equal(addon._RosterInternal.FormatCompactTooltipNumber(2500), "2.5K", "empty result must trigger fallback")
    rawset(_G, "AbbreviateNumbers", nil)
  end)

  -- FormatSyncAge --------------------------------------------------------------

  test("FormatSyncAge returns nil for negative or non-numeric input", function()
    local addon = LoadTooltip()
    Assert.Nil(addon._RosterInternal.FormatSyncAge(-1))
    Assert.Nil(addon._RosterInternal.FormatSyncAge("not-a-number"))
  end)

  test("FormatSyncAge formats sub-minute durations as Ns", function()
    local addon = LoadTooltip()
    Assert.Equal(addon._RosterInternal.FormatSyncAge(0), "0s", "zero seconds")
    Assert.Equal(addon._RosterInternal.FormatSyncAge(30), "30s", "30 seconds")
    Assert.Equal(addon._RosterInternal.FormatSyncAge(59), "59s", "boundary")
  end)

  test("FormatSyncAge formats minute durations as Nm or Nm Ms", function()
    local addon = LoadTooltip()
    Assert.Equal(addon._RosterInternal.FormatSyncAge(60), "1m", "exactly one minute")
    Assert.Equal(addon._RosterInternal.FormatSyncAge(125), "2m 5s", "minutes plus seconds")
    Assert.Equal(addon._RosterInternal.FormatSyncAge(3599), "59m 59s", "just under an hour")
  end)

  test("FormatSyncAge formats hour durations as Nh or Nh Mm", function()
    local addon = LoadTooltip()
    Assert.Equal(addon._RosterInternal.FormatSyncAge(3600), "1h", "exactly one hour")
    Assert.Equal(addon._RosterInternal.FormatSyncAge(3700), "1h 1m", "hour plus minute remainder")
    Assert.Equal(addon._RosterInternal.FormatSyncAge(7200), "2h", "two hours flat")
  end)

  -- FormatSyncDebugField ------------------------------------------------------

  test("FormatSyncDebugField returns nil for non-table info", function()
    local addon = LoadTooltip()
    Assert.Nil(addon._RosterInternal.FormatSyncDebugField("Label", nil, 100))
    Assert.Nil(addon._RosterInternal.FormatSyncDebugField("Label", "not-a-table", 100))
  end)

  test("FormatSyncDebugField returns nil when neither source nor age can be resolved", function()
    local addon = LoadTooltip()
    Assert.Nil(addon._RosterInternal.FormatSyncDebugField("Label", {}, 100))
  end)

  test("FormatSyncDebugField formats source-only when no timestamp is present", function()
    local addon = LoadTooltip()
    Assert.Equal(addon._RosterInternal.FormatSyncDebugField("Key", { source = "remote" }, 100), "Key: remote")
  end)

  test("FormatSyncDebugField formats source + age when capturedAt yields a positive delta", function()
    local addon = LoadTooltip()
    Assert.Equal(
      addon._RosterInternal.FormatSyncDebugField("Key", { source = "remote", capturedAt = 90 }, 100),
      "Key: remote (10s)",
      "must include both source and age"
    )
  end)

  test("FormatSyncDebugField falls back to receivedAt when capturedAt is missing", function()
    local addon = LoadTooltip()
    Assert.Equal(
      addon._RosterInternal.FormatSyncDebugField("Key", { source = "remote", receivedAt = 70 }, 100),
      "Key: remote (30s)"
    )
  end)

  test("FormatSyncDebugField formats age-only when source is missing", function()
    local addon = LoadTooltip()
    Assert.Equal(addon._RosterInternal.FormatSyncDebugField("Key", { capturedAt = 70 }, 100), "Key: 30s")
  end)

  -- ResolveTooltipClassName ---------------------------------------------------

  test("ResolveTooltipClassName returns nil for non-table or empty class", function()
    local addon = LoadTooltip()
    Assert.Nil(addon._RosterInternal.ResolveTooltipClassName(nil))
    Assert.Nil(addon._RosterInternal.ResolveTooltipClassName({}))
    Assert.Nil(addon._RosterInternal.ResolveTooltipClassName({ class = "" }))
  end)

  test("ResolveTooltipClassName prefers LOCALIZED_CLASS_NAMES_MALE", function()
    local addon = LoadTooltip()
    rawset(_G, "LOCALIZED_CLASS_NAMES_MALE", { MAGE = "Magier" })
    Assert.Equal(addon._RosterInternal.ResolveTooltipClassName({ class = "MAGE" }), "Magier")
    rawset(_G, "LOCALIZED_CLASS_NAMES_MALE", nil)
  end)

  test("ResolveTooltipClassName falls back to LOCALIZED_CLASS_NAMES_FEMALE", function()
    local addon = LoadTooltip()
    rawset(_G, "LOCALIZED_CLASS_NAMES_MALE", nil)
    rawset(_G, "LOCALIZED_CLASS_NAMES_FEMALE", { ROGUE = "Schurkin" })
    Assert.Equal(addon._RosterInternal.ResolveTooltipClassName({ class = "ROGUE" }), "Schurkin")
    rawset(_G, "LOCALIZED_CLASS_NAMES_FEMALE", nil)
  end)

  test("ResolveTooltipClassName falls back to the english class name table when no localized table is set", function()
    local addon = LoadTooltip()
    -- Both globals are nil after WithGlobals; the function must still
    -- resolve a sensible English name (or echo the input class) for
    -- known WoW class tokens. We assert it produces *some* non-empty
    -- string for a valid token.
    rawset(_G, "LOCALIZED_CLASS_NAMES_MALE", nil)
    rawset(_G, "LOCALIZED_CLASS_NAMES_FEMALE", nil)
    local resolved = addon._RosterInternal.ResolveTooltipClassName({ class = "MAGE" })
    Assert.True(type(resolved) == "string" and resolved ~= "", "fallback must produce a non-empty class name")
  end)
end
