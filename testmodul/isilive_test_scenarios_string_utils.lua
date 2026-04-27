---@diagnostic disable: undefined-global
return function(test, ctx)
  local Assert = ctx.assert
  local LoadAddonModules = ctx.load_modules

  test("StringUtils.Trim removes leading and trailing whitespace", function()
    local addon = LoadAddonModules({ "isiLive_string_utils.lua" })
    Assert.Equal(addon.StringUtils.Trim("  hello  "), "hello", "must trim both sides")
    Assert.Equal(addon.StringUtils.Trim("hello"), "hello", "must leave clean string unchanged")
    Assert.Equal(addon.StringUtils.Trim("  "), "", "whitespace-only must become empty")
    Assert.Equal(addon.StringUtils.Trim("\t\n hello \n\t"), "hello", "must trim tabs and newlines")
  end)

  test("StringUtils.Trim handles non-string inputs gracefully", function()
    local addon = LoadAddonModules({ "isiLive_string_utils.lua" })
    Assert.Equal(addon.StringUtils.Trim(nil), "", "nil must return empty string")
    Assert.Equal(addon.StringUtils.Trim(123), "", "number must return empty string")
    Assert.Equal(addon.StringUtils.Trim(true), "", "boolean must return empty string")
  end)

  test("StringUtils.StripWhitespace removes all whitespace", function()
    local addon = LoadAddonModules({ "isiLive_string_utils.lua" })
    Assert.Equal(addon.StringUtils.StripWhitespace("a b c"), "abc", "must remove internal spaces")
    Assert.Equal(addon.StringUtils.StripWhitespace("  a  b  "), "ab", "must remove all whitespace")
    Assert.Equal(addon.StringUtils.StripWhitespace("abc"), "abc", "no-space string must be unchanged")
  end)

  test("StringUtils.StripWhitespace handles non-string inputs gracefully", function()
    local addon = LoadAddonModules({ "isiLive_string_utils.lua" })
    Assert.Equal(addon.StringUtils.StripWhitespace(nil), "", "nil must return empty string")
    Assert.Equal(addon.StringUtils.StripWhitespace(42), "", "number must return empty string")
  end)

  test("StringUtils.NormalizeRealmName strips spaces, dashes, dots, parens, and quotes", function()
    local addon = LoadAddonModules({ "isiLive_string_utils.lua" })
    Assert.Equal(addon.StringUtils.NormalizeRealmName("Der Rat von Dalaran"), "DerRatvonDalaran", "must strip spaces")
    Assert.Equal(addon.StringUtils.NormalizeRealmName("Mal'Ganis"), "MalGanis", "must strip single quotes")
    Assert.Equal(addon.StringUtils.NormalizeRealmName("Area-52"), "Area52", "must strip dashes")
    Assert.Equal(
      addon.StringUtils.NormalizeRealmName("Test.Realm(EU)`s"),
      "TestRealmEUs",
      "must strip dots, parens, and backticks"
    )
  end)

  test("StringUtils.NormalizeRealmName handles non-string inputs gracefully", function()
    local addon = LoadAddonModules({ "isiLive_string_utils.lua" })
    Assert.Equal(addon.StringUtils.NormalizeRealmName(nil), "", "nil must return empty string")
    Assert.Equal(addon.StringUtils.NormalizeRealmName(99), "", "number must return empty string")
  end)

  test("StringUtils.NormalizeRealmName matches canonical pattern used by Sync and Stats", function()
    local addon = LoadAddonModules({ "isiLive_string_utils.lua" })
    -- Verify the exact same characters are stripped as in the canonical pattern [%s%-%.%(%)'`]
    local input = "A B-C.D(E)F'G`H"
    local expected = "ABCDEFGH"
    Assert.Equal(
      addon.StringUtils.NormalizeRealmName(input),
      expected,
      "must strip exactly the canonical character set"
    )
  end)

  test("StringUtils.IsBlank returns true for nil, empty string, and non-strings", function()
    local addon = LoadAddonModules({ "isiLive_string_utils.lua" })
    Assert.Equal(addon.StringUtils.IsBlank(nil), true, "nil must be blank")
    Assert.Equal(addon.StringUtils.IsBlank(""), true, "empty string must be blank")
    Assert.Equal(addon.StringUtils.IsBlank(0), true, "number must be blank (non-string)")
    Assert.Equal(addon.StringUtils.IsBlank(false), true, "false must be blank (non-string)")
    Assert.Equal(addon.StringUtils.IsBlank({}), true, "table must be blank (non-string)")
  end)

  test("StringUtils.IsBlank returns false for any non-empty string", function()
    local addon = LoadAddonModules({ "isiLive_string_utils.lua" })
    Assert.Equal(addon.StringUtils.IsBlank("x"), false, "single char must not be blank")
    Assert.Equal(addon.StringUtils.IsBlank(" "), false, "whitespace-only is intentionally NOT blank")
    Assert.Equal(addon.StringUtils.IsBlank("hello"), false, "regular string must not be blank")
  end)
end
