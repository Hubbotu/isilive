---@diagnostic disable: undefined-global
return function(test, ctx)
  local Assert = ctx.assert
  local LoadAddonModules = ctx.load_modules
  local WithGlobals = ctx.with_globals

  test("All enUS keys exist in deDE locale", function()
    local addon = LoadAddonModules({ "isiLive_texts.lua" })
    local locales = addon.Texts.GetLocaleTables()

    Assert.NotNil(locales.enUS, "enUS locale must exist")
    Assert.NotNil(locales.deDE, "deDE locale must exist")

    for key, _ in pairs(locales.enUS) do
      Assert.NotNil(locales.deDE[key], "deDE must have key: " .. tostring(key))
    end
  end)

  test("All deDE keys exist in enUS locale", function()
    local addon = LoadAddonModules({ "isiLive_texts.lua" })
    local locales = addon.Texts.GetLocaleTables()

    for key, _ in pairs(locales.deDE) do
      Assert.NotNil(locales.enUS[key], "enUS must have key: " .. tostring(key))
    end
  end)

  test("All enUS keys exist in frFR locale", function()
    local addon = LoadAddonModules({ "isiLive_texts.lua" })
    local locales = addon.Texts.GetLocaleTables()

    Assert.NotNil(locales.frFR, "frFR locale must exist")

    for key, _ in pairs(locales.enUS) do
      Assert.NotNil(locales.frFR[key], "frFR must have key: " .. tostring(key))
    end
  end)

  test("All frFR keys exist in enUS locale", function()
    local addon = LoadAddonModules({ "isiLive_texts.lua" })
    local locales = addon.Texts.GetLocaleTables()

    for key, _ in pairs(locales.frFR) do
      Assert.NotNil(locales.enUS[key], "enUS must have key: " .. tostring(key))
    end
  end)

  test("All enUS keys exist in esES locale", function()
    local addon = LoadAddonModules({ "isiLive_texts.lua" })
    local locales = addon.Texts.GetLocaleTables()

    Assert.NotNil(locales.esES, "esES locale must exist")

    for key, _ in pairs(locales.enUS) do
      Assert.NotNil(locales.esES[key], "esES must have key: " .. tostring(key))
    end
  end)

  test("All esES keys exist in enUS locale", function()
    local addon = LoadAddonModules({ "isiLive_texts.lua" })
    local locales = addon.Texts.GetLocaleTables()

    for key, _ in pairs(locales.esES) do
      Assert.NotNil(locales.enUS[key], "enUS must have key: " .. tostring(key))
    end
  end)

  test("All enUS keys exist in ptBR locale", function()
    local addon = LoadAddonModules({ "isiLive_texts.lua" })
    local locales = addon.Texts.GetLocaleTables()

    Assert.NotNil(locales.ptBR, "ptBR locale must exist")

    for key, _ in pairs(locales.enUS) do
      Assert.NotNil(locales.ptBR[key], "ptBR must have key: " .. tostring(key))
    end
  end)

  test("All ptBR keys exist in enUS locale", function()
    local addon = LoadAddonModules({ "isiLive_texts.lua" })
    local locales = addon.Texts.GetLocaleTables()

    for key, _ in pairs(locales.ptBR) do
      Assert.NotNil(locales.enUS[key], "enUS must have key: " .. tostring(key))
    end
  end)

  test("LOADED_HINT contains format placeholder in both locales", function()
    local addon = LoadAddonModules({ "isiLive_texts.lua" })
    local locales = addon.Texts.GetLocaleTables()

    Assert.True(locales.enUS.LOADED_HINT:find("%%s") ~= nil, "enUS LOADED_HINT must contain %s placeholder")
    Assert.True(locales.deDE.LOADED_HINT:find("%%s") ~= nil, "deDE LOADED_HINT must contain %s placeholder")
  end)

  test("Format placeholder counts match enUS across all locales", function()
    local addon = LoadAddonModules({ "isiLive_texts.lua" })
    local locales = addon.Texts.GetLocaleTables()

    -- string.format crashes at runtime if a locale has a different %s/%d count
    -- than the call site expects. Guard against silent placeholder drift by
    -- comparing every translated string against its enUS counterpart.
    local function countPlaceholders(s)
      local count = 0
      for _ in s:gmatch("%%[sd]") do
        count = count + 1
      end
      return count
    end

    for localeName, localeTable in pairs(locales) do
      if localeName ~= "enUS" then
        for key, enValue in pairs(locales.enUS) do
          local translated = localeTable[key]
          if type(enValue) == "string" and type(translated) == "string" then
            local enCount = countPlaceholders(enValue)
            local trCount = countPlaceholders(translated)
            Assert.Equal(
              trCount,
              enCount,
              localeName
                .. "."
                .. tostring(key)
                .. " has "
                .. tostring(trCount)
                .. " %s/%d placeholders but enUS has "
                .. tostring(enCount)
                .. ': enUS="'
                .. enValue
                .. '" '
                .. localeName
                .. '="'
                .. translated
                .. '"'
            )
          end
        end
      end
    end
  end)

  test("Locale title key is present in all locales", function()
    local addon = LoadAddonModules({ "isiLive_texts.lua" })
    local locales = addon.Texts.GetLocaleTables()

    Assert.Equal(locales.enUS.TITLE, "isiLive", "enUS TITLE must be present")
    Assert.Equal(locales.deDE.TITLE, "isiLive", "deDE TITLE must be present")
  end)

  test("Locale tag resolver returns enUS as default fallback", function()
    local addon = LoadAddonModules({ "isiLive_languages.lua", "isiLive_locale.lua" })

    Assert.Equal(addon.Locale.ResolveLocaleTag(nil), "enUS", "nil tag must default to enUS")
    Assert.Equal(addon.Locale.ResolveLocaleTag("fr"), "frFR", "fr tag must resolve to frFR")
    Assert.Equal(addon.Locale.ResolveLocaleTag("frfr"), "frFR", "frfr tag must resolve to frFR")
    Assert.Equal(addon.Locale.ResolveLocaleTag("de"), "deDE", "de tag must resolve to deDE")
    Assert.Equal(addon.Locale.ResolveLocaleTag("dede"), "deDE", "dede tag must resolve to deDE")
    Assert.Equal(addon.Locale.ResolveLocaleTag("en"), "enUS", "en tag must resolve to enUS")
    Assert.Equal(addon.Locale.ResolveLocaleTag("es"), "esES", "es tag must resolve to esES")
    Assert.Equal(addon.Locale.ResolveLocaleTag("eses"), "esES", "eses tag must resolve to esES")
    Assert.Equal(addon.Locale.ResolveLocaleTag("pt"), "ptBR", "pt tag must resolve to ptBR")
    Assert.Equal(addon.Locale.ResolveLocaleTag("ptbr"), "ptBR", "ptbr tag must resolve to ptBR")
    Assert.Equal(addon.Locale.ResolveLocaleTag("xx"), "enUS", "unsupported tag must fallback to enUS")
  end)

  test("enUS values must not contain German-only stopwords", function()
    local addon = LoadAddonModules({ "isiLive_texts.lua" })
    local locales = addon.Texts.GetLocaleTables()

    -- Words that are unambiguously German and must never appear in English text.
    -- Catches accidental cross-locale copy/paste like CHAT_QUEUE_PREFIX
    -- ("Warteschlangenbeitritt") leaking into the enUS table.
    local germanStopwords = {
      "Warteschlange",
      "Schlüssel",
      "Hauptfenster",
      "Befehle",
      "Sprache",
      "Gesperrt",
      "Entsperr",
      "Einstellung",
      "Gruppe",
      "Bereit",
      "Gilde",
      "Charakter",
      "Berufe",
      "Talente",
      "Zauber",
      "Erfolge",
      "Sammlung",
      "Ruhestein",
      "ä",
      "ö",
      "ü",
      "Ä",
      "Ö",
      "Ü",
      "ß",
    }

    for key, value in pairs(locales.enUS) do
      if type(value) == "string" then
        for _, stopword in ipairs(germanStopwords) do
          Assert.True(
            value:find(stopword, 1, true) == nil,
            "enUS." .. tostring(key) .. ' contains German stopword "' .. stopword .. '": ' .. tostring(value)
          )
        end
      end
    end
  end)

  test("deDE values must not contain English-only stopwords", function()
    local addon = LoadAddonModules({ "isiLive_texts.lua" })
    local locales = addon.Texts.GetLocaleTables()

    -- Words that are unambiguously English and must never appear in German text.
    -- Whitelist of keys that legitimately keep English shared terms (technical
    -- WoW vocabulary, slash commands, brand names).
    local englishStopwordKeyAllowlist = {
      HELP_HEADER = true,
      HELP_TEST = true,
      HELP_TESTALL = true,
      HELP_TPTEST = true,
      HELP_TPDEBUG = true,
      HELP_LOG = true,
      HELP_LOCK = true,
      HELP_UNLOCK = true,
      HELP_RESETUI = true,
      HELP_BINDCHECK = true,
      HELP_PAUSE = true,
      HELP_RESUME = true,
      HELP_STOP = true,
      HELP_START = true,
      HELP_LANG = true,
      HELP_LEAD = true,
      HELP_RESET = true,
      -- Proper nouns: WoW dungeon names stay English in every locale.
      TESTALL_DUMMY_DUNGEON = true,
    }

    local englishStopwords = {
      " the ",
      " and ",
      " with ",
      " from ",
      " your ",
    }

    for key, value in pairs(locales.deDE) do
      if type(value) == "string" and not englishStopwordKeyAllowlist[key] then
        local lowered = " " .. value:lower() .. " "
        for _, stopword in ipairs(englishStopwords) do
          Assert.True(
            lowered:find(stopword, 1, true) == nil,
            "deDE." .. tostring(key) .. ' contains English stopword "' .. stopword .. '": ' .. tostring(value)
          )
        end
      end
    end
  end)

  test("Full-width action button labels stay within 14 characters", function()
    local addon = LoadAddonModules({ "isiLive_texts.lua" })
    local locales = addon.Texts.GetLocaleTables()

    -- Per CLAUDE.md: action buttons in the main UI are 120x24px and labels
    -- must stay <= 14 characters to avoid visual truncation.
    local fullWidthActionButtonKeys = {
      "BTN_READYCHECK",
      "BTN_COUNTDOWN10",
      "BTN_COUNTDOWN_CANCEL",
      "BTN_REFRESH",
      "BTN_SHARE_KEYS",
    }

    local localeNames = { "enUS", "deDE", "frFR", "esES", "ptBR", "itIT", "ruRU", "trTR" }
    for _, localeName in ipairs(localeNames) do
      local localeTable = locales[localeName]
      if localeTable then
        for _, key in ipairs(fullWidthActionButtonKeys) do
          local value = localeTable[key]
          if type(value) == "string" then
            Assert.True(
              #value <= 14,
              localeName .. "." .. key .. " must be <= 14 chars (is " .. tostring(#value) .. '): "' .. value .. '"'
            )
          end
        end
      end
    end
  end)

  test("Locale GetUnitServerLanguage skips missing units without UnitGUID or UnitIsUnit", function()
    WithGlobals({
      UnitExists = function(unit)
        return unit == "player"
      end,
      UnitGUID = function(_unit)
        error("UnitGUID must not be called for missing units")
      end,
      UnitIsUnit = function(_unit, _other)
        error("UnitIsUnit must not be called for missing units")
      end,
    }, function()
      local addon = LoadAddonModules({ "isiLive_languages.lua", "isiLive_locale.lua" })
      local language = addon.Locale.GetUnitServerLanguage("party1", "TestRealm", function()
        return nil
      end)

      Assert.Equal(language, "??", "missing units must resolve to unknown language without raw unit API calls")
    end)
  end)
end
