---@diagnostic disable: undefined-global

-- Branch-coverage scenarios for ui/isiLive_lfg_flags.lua. The existing
-- isilive_test_scenarios_lfg_flags.lua file exercises the public
-- Register / SetEnabled / HookSearchPanel surface but cannot reach
-- the eight private helpers (SplitNameRealm, GetTagForResult,
-- EnsureFlagTexture, ApplyFlagToButton, UpdateButton, HookButton,
-- HookButtons, RefreshAll) — they live behind Blizzard hook
-- closures. Commit 11da43f exposed them via addonTable._LFGFlagsInternal
-- so this file can drive them directly.

local function NewButtonStub(opts)
  opts = opts or {}
  local hookEnter
  local createdTexture
  local createdFontString
  return {
    resultID = opts.resultID,
    Playstyle = opts.Playstyle,
    HookScript = function(_, scriptType, fn)
      if scriptType == "OnEnter" then
        hookEnter = fn
      end
    end,
    CreateTexture = function()
      local tex = {
        _set = {},
        _shown = false,
      }
      function tex.SetSize(self, w, h)
        self._size = { w, h }
      end
      function tex.SetPoint(self, ...)
        self._point = { ... }
      end
      function tex.SetTexture(self, path)
        self._texture = path
      end
      function tex.Show(self)
        self._shown = true
      end
      function tex.Hide(self)
        self._shown = false
      end
      createdTexture = tex
      return tex
    end,
    CreateFontString = opts.CreateFontString or function()
      local fs = {
        _text = "",
        _shown = false,
      }
      function fs.SetPoint(self, ...)
        self._point = { ... }
      end
      function fs.ClearAllPoints(self)
        self._point = nil
      end
      function fs.SetJustifyH(self, value)
        self._justifyH = value
      end
      function fs.SetWidth(self, value)
        self._width = value
      end
      function fs.SetHeight(self, value)
        self._height = value
      end
      function fs.SetShadowColor(self, ...)
        self._shadowColor = { ... }
      end
      function fs.SetShadowOffset(self, ...)
        self._shadowOffset = { ... }
      end
      function fs.SetTextColor(self, ...)
        self._textColor = { ... }
      end
      function fs.SetText(self, value)
        self._text = value
      end
      function fs.GetText(self)
        return self._text
      end
      function fs.Show(self)
        self._shown = true
      end
      function fs.Hide(self)
        self._shown = false
      end
      createdFontString = fs
      return fs
    end,
    GetCreatedTexture = function()
      return createdTexture
    end,
    GetCreatedFontString = function()
      return createdFontString
    end,
    GetEnterHook = function()
      return hookEnter
    end,
  }
end

local function MinimalGlobals()
  return {
    CreateFrame = function()
      return {
        RegisterEvent = function() end,
        SetScript = function() end,
        UnregisterEvent = function() end,
      }
    end,
    C_Timer = {
      After = function(_, fn)
        if type(fn) == "function" then
          fn()
        end
      end,
    },
    hooksecurefunc = function() end,
  }
end

local function BonusGlobals(overrides)
  overrides = overrides or {}
  local globals = MinimalGlobals()
  globals.UnitClass = overrides.UnitClass
    or function(unit)
      if unit == "player" then
        return "Mage", "MAGE"
      end
      return nil, nil
    end
  globals.GetSpecialization = overrides.GetSpecialization or function()
    return 1
  end
  globals.GetSpecializationInfo = overrides.GetSpecializationInfo or function()
    return 63
  end
  globals.GetLocale = overrides.GetLocale or function()
    return "enUS"
  end
  if overrides.IsiLiveDB ~= nil then
    globals.IsiLiveDB = overrides.IsiLiveDB
  end
  if overrides.C_LFGList ~= nil then
    globals.C_LFGList = overrides.C_LFGList
  end
  if overrides.GameTooltip ~= nil then
    globals.GameTooltip = overrides.GameTooltip
  end
  return globals
end

local function LoadBonusModules(LoadAddonModules)
  return LoadAddonModules({ "isiLive_languages.lua", "isiLive_texts.lua", "isiLive_lfg_flags.lua" })
end

local function StripColors(text)
  if type(text) ~= "string" then
    return ""
  end
  local stripped = text:gsub("|c%x%x%x%x%x%x%x%x", "")
  stripped = stripped:gsub("|r", "")
  return stripped
end

local function NewFontStringStub()
  local fs = {
    _text = "",
    _shown = false,
  }
  function fs.SetPoint(self, ...)
    self._point = { ... }
  end
  function fs.ClearAllPoints(self)
    self._point = nil
  end
  function fs.SetJustifyH(self, value)
    self._justifyH = value
  end
  function fs.SetWidth(self, value)
    self._width = value
  end
  function fs.SetHeight(self, value)
    self._height = value
  end
  function fs.SetShadowColor(self, ...)
    self._shadowColor = { ... }
  end
  function fs.SetShadowOffset(self, ...)
    self._shadowOffset = { ... }
  end
  function fs.SetTextColor(self, ...)
    self._textColor = { ... }
  end
  function fs.SetText(self, value)
    self._text = value
  end
  function fs.GetText(self)
    return self._text
  end
  function fs.Show(self)
    self._shown = true
  end
  function fs.Hide(self)
    self._shown = false
  end
  return fs
end

return function(test, ctx)
  local Assert = ctx.assert
  local LoadAddonModules = ctx.load_modules
  local WithGlobals = ctx.with_globals

  -- SplitNameRealm -------------------------------------------------------------

  test("LI.SplitNameRealm splits Name-Realm and falls back to bare name", function()
    WithGlobals(MinimalGlobals(), function()
      local addon = LoadAddonModules({ "isiLive_lfg_flags.lua" })
      local LI = addon._LFGFlagsInternal
      local name, realm = LI.SplitNameRealm("Aria-Sanguino")
      Assert.Equal(name, "Aria", "name part must be split off")
      Assert.Equal(realm, "Sanguino", "realm part must be split off")
      name, realm = LI.SplitNameRealm("Bare")
      Assert.Equal(name, "Bare", "name without dash returns input as name")
      Assert.Nil(realm, "name without dash yields nil realm")
      name, realm = LI.SplitNameRealm(nil)
      Assert.Nil(name, "nil input yields nil name")
      Assert.Nil(realm, "nil input yields nil realm")
    end)
  end)

  -- GetTagForResult ------------------------------------------------------------

  test("LI.GetTagForResult returns nil and caches false when C_LFGList is missing", function()
    WithGlobals(MinimalGlobals(), function()
      local addon = LoadAddonModules({ "isiLive_lfg_flags.lua" })
      local LI = addon._LFGFlagsInternal
      Assert.Nil(LI.GetTagForResult(42), "no C_LFGList yields nil")
    end)
  end)

  test("LI.GetTagForResult uses cached value on repeated lookups", function()
    local globals = MinimalGlobals()
    globals.C_LFGList = {
      GetSearchResultInfo = function()
        return { leaderName = "Hero-RealmA" }
      end,
    }
    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_flags.lua" })
      addon.LFGFlags.Register({
        localeModule = {
          GetUnitServerLanguage = function(_unit, realm)
            return realm == "RealmA" and "EN" or nil
          end,
          GetLanguageFlagTexturePath = function(tag)
            return "media/" .. tag
          end,
        },
      })
      local LI = addon._LFGFlagsInternal
      local first = LI.GetTagForResult(7)
      Assert.Equal(first, "EN", "first lookup must resolve via locale module")
      -- Replace GetSearchResultInfo so we can prove the cache short-circuits.
      globals.C_LFGList.GetSearchResultInfo = function()
        error("must not be called when cache hits")
      end
      Assert.Equal(LI.GetTagForResult(7), "EN", "cached lookup must not re-query Blizzard API")
    end)
  end)

  test("LI.GetTagForResult returns nil when GetSearchResultInfo raises", function()
    local globals = MinimalGlobals()
    globals.C_LFGList = {
      GetSearchResultInfo = function()
        error("api error")
      end,
    }
    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_flags.lua" })
      Assert.Nil(addon._LFGFlagsInternal.GetTagForResult(11), "pcall failure yields nil")
    end)
  end)

  test("LI.GetTagForResult returns nil when issecretvalue marks the info as protected", function()
    local globals = MinimalGlobals()
    globals.C_LFGList = {
      GetSearchResultInfo = function()
        return { leaderName = "Hero-Realm" }
      end,
    }
    globals.issecretvalue = function()
      return true
    end
    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_flags.lua" })
      Assert.Nil(addon._LFGFlagsInternal.GetTagForResult(15), "secret value must yield nil")
    end)
  end)

  test("LI.GetTagForResult returns nil when leaderName is missing", function()
    local globals = MinimalGlobals()
    globals.C_LFGList = {
      GetSearchResultInfo = function()
        return {} -- no leaderName
      end,
    }
    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_flags.lua" })
      Assert.Nil(addon._LFGFlagsInternal.GetTagForResult(20), "missing leaderName yields nil")
    end)
  end)

  test("LI.GetTagForResult falls back to GetRealmName when leaderName has no realm part", function()
    local globals = MinimalGlobals()
    globals.C_LFGList = {
      GetSearchResultInfo = function()
        return { leaderName = "Solo" }
      end,
    }
    globals.GetRealmName = function()
      return "HomeRealm"
    end
    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_flags.lua" })
      addon.LFGFlags.Register({
        localeModule = {
          GetUnitServerLanguage = function(_unit, realm)
            return realm == "HomeRealm" and "DE" or nil
          end,
          GetLanguageFlagTexturePath = function(tag)
            return "media/" .. tag
          end,
        },
      })
      Assert.Equal(addon._LFGFlagsInternal.GetTagForResult(99), "DE", "GetRealmName fallback must drive locale lookup")
    end)
  end)

  test("LI.GetTagForResult ignores empty / placeholder language tags", function()
    local globals = MinimalGlobals()
    globals.C_LFGList = {
      GetSearchResultInfo = function()
        return { leaderName = "Hero-Foreign" }
      end,
    }
    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_flags.lua" })
      addon.LFGFlags.Register({
        localeModule = {
          GetUnitServerLanguage = function()
            return "??"
          end,
          GetLanguageFlagTexturePath = function()
            return nil
          end,
        },
      })
      Assert.Nil(addon._LFGFlagsInternal.GetTagForResult(33), "?? tag must be discarded")
    end)
  end)

  test("LI.GetTagForResult returns nil and caches when getLanguageTag pcall fails", function()
    local globals = MinimalGlobals()
    globals.C_LFGList = {
      GetSearchResultInfo = function()
        return { leaderName = "Hero-RealmX" }
      end,
    }
    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_flags.lua" })
      addon.LFGFlags.Register({
        localeModule = {
          GetUnitServerLanguage = function()
            error("locale lookup failure")
          end,
          GetLanguageFlagTexturePath = function()
            return nil
          end,
        },
      })
      Assert.Nil(addon._LFGFlagsInternal.GetTagForResult(44), "locale failure yields nil")
    end)
  end)

  -- EnsureFlagTexture / ApplyFlagToButton -------------------------------------

  test("LI.EnsureFlagTexture creates the texture once and caches it on the button", function()
    WithGlobals(MinimalGlobals(), function()
      local addon = LoadAddonModules({ "isiLive_lfg_flags.lua" })
      local button = NewButtonStub()
      local tex1 = addon._LFGFlagsInternal.EnsureFlagTexture(button)
      local tex2 = addon._LFGFlagsInternal.EnsureFlagTexture(button)
      Assert.NotNil(tex1, "first call must create texture")
      Assert.True(tex1 == tex2, "second call must reuse cached texture")
      Assert.Equal(tex1._size[1], 16, "texture width must be FLAG_WIDTH")
      Assert.Equal(tex1._size[2], 12, "texture height must be FLAG_HEIGHT")
    end)
  end)

  test("LI.EnsureFlagTexture anchors to Playstyle label when present", function()
    WithGlobals(MinimalGlobals(), function()
      local addon = LoadAddonModules({ "isiLive_lfg_flags.lua" })
      local playstyle = {
        GetRight = function()
          return 63
        end,
      }
      local button = NewButtonStub({ Playstyle = playstyle })
      local tex = addon._LFGFlagsInternal.EnsureFlagTexture(button)
      Assert.Equal(tex._point[1], "LEFT", "must anchor LEFT")
      Assert.True(tex._point[2] == playstyle, "anchor target must be Playstyle when available")
    end)
  end)

  test("LI.ApplyFlagToButton hides texture when no resultID is provided", function()
    WithGlobals(MinimalGlobals(), function()
      local addon = LoadAddonModules({ "isiLive_lfg_flags.lua" })
      local button = NewButtonStub()
      addon._LFGFlagsInternal.ApplyFlagToButton(button, nil)
      local tex = button.GetCreatedTexture()
      Assert.True(tex._shown == false, "no resultID must keep texture hidden")
    end)
  end)

  test("LI.ApplyFlagToButton hides texture when LFG flags are disabled", function()
    local globals = MinimalGlobals()
    globals.C_LFGList = {
      GetSearchResultInfo = function()
        return { leaderName = "Hero-RealmA" }
      end,
    }
    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_flags.lua" })
      addon.LFGFlags.Register({
        localeModule = {
          GetUnitServerLanguage = function()
            return "EN"
          end,
          GetLanguageFlagTexturePath = function(tag)
            return "media/" .. tag
          end,
        },
      })
      addon.LFGFlags.SetEnabled(false)
      local button = NewButtonStub({ resultID = 7 })
      addon._LFGFlagsInternal.ApplyFlagToButton(button, 7)
      Assert.True(button.GetCreatedTexture()._shown == false, "disabled flags must hide texture")
    end)
  end)

  test("LI.ApplyFlagToButton sets texture and shows it for a resolved tag", function()
    local globals = MinimalGlobals()
    globals.C_LFGList = {
      GetSearchResultInfo = function()
        return { leaderName = "Hero-RealmA" }
      end,
    }
    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_flags.lua" })
      addon.LFGFlags.Register({
        localeModule = {
          GetUnitServerLanguage = function()
            return "EN"
          end,
          GetLanguageFlagTexturePath = function(tag)
            return "media/" .. tag
          end,
        },
      })
      addon.LFGFlags.SetEnabled(true)
      local button = NewButtonStub({ resultID = 7 })
      addon._LFGFlagsInternal.ApplyFlagToButton(button, 7)
      local tex = button.GetCreatedTexture()
      Assert.Equal(tex._texture, "media/EN", "texture path must be set from locale module")
      Assert.True(tex._shown == true, "resolved flag must show texture")
    end)
  end)

  -- UpdateButton / HookButton / HookButtons / RefreshAll -----------------------

  test("LI.UpdateButton reads resultID directly off the button via rawget", function()
    WithGlobals(MinimalGlobals(), function()
      local addon = LoadAddonModules({ "isiLive_lfg_flags.lua" })
      local button = NewButtonStub({ resultID = 99 })
      addon._LFGFlagsInternal.UpdateButton(button) -- must not throw, hides texture (no C_LFGList)
      Assert.True(button.GetCreatedTexture()._shown == false, "no globals -> texture hidden")
    end)
  end)

  test("LI.UpdateButton renders and anchors the search-result bonus badge", function()
    local globals = BonusGlobals({
      C_LFGList = {
        GetSearchResultInfo = function()
          return { numMembers = 1 }
        end,
        GetSearchResultPlayerInfo = function()
          return { classFilename = "HUNTER", specID = 253, className = "Hunter", specName = "Beast Mastery" }
        end,
      },
    })
    WithGlobals(globals, function()
      local addon = LoadBonusModules(LoadAddonModules)
      local button = NewButtonStub({ resultID = 17 })

      addon._LFGFlagsInternal.UpdateButton(button)

      local badge = Assert.NotNil(button.GetCreatedFontString(), "search result badge must create a font string")
      Assert.Equal(badge._text, "++", "Hunter BL must render the major bonus marker")
      Assert.True(badge._shown == true, "resolved search result bonus badge must be visible")
      Assert.True(badge._point[2] == button._isiFlagTex, "badge must anchor after the flag texture when it exists")
      Assert.Equal(badge._textColor[1], 1.00, "major utility badge must use the major utility color")
      Assert.Equal(badge._width, 18, "badge keeps the compact fixed width")
    end)
  end)

  test("LI.UpdateButton hides the existing search-result bonus badge when disabled", function()
    local globals = BonusGlobals({
      C_LFGList = {
        GetSearchResultInfo = function()
          return { numMembers = 1 }
        end,
        GetSearchResultPlayerInfo = function()
          return { classFilename = "HUNTER", specID = 253 }
        end,
      },
    })
    WithGlobals(globals, function()
      local addon = LoadBonusModules(LoadAddonModules)
      local button = NewButtonStub({ resultID = 17 })

      addon._LFGFlagsInternal.UpdateButton(button)
      local badge = Assert.NotNil(button.GetCreatedFontString(), "first update must create a visible badge")
      Assert.Equal(badge._text, "++", "precondition: badge must be populated")

      addon.LFGFlags.SetGroupBonusesEnabled(false)
      addon._LFGFlagsInternal.UpdateButton(button)

      Assert.Equal(badge._text, "", "disabled group bonuses must clear the search-result badge text")
      Assert.True(badge._shown == false, "disabled group bonuses must hide the search-result badge")
    end)
  end)

  test("LI.HookButton skips already hooked buttons (idempotent)", function()
    WithGlobals(MinimalGlobals(), function()
      local addon = LoadAddonModules({ "isiLive_lfg_flags.lua" })
      local LI = addon._LFGFlagsInternal
      local hookCount = 0
      local button = {
        resultID = 1,
        HookScript = function(_, scriptType)
          if scriptType == "OnEnter" then
            hookCount = hookCount + 1
          end
        end,
        CreateTexture = function()
          return {
            SetSize = function() end,
            SetPoint = function() end,
            Hide = function() end,
            Show = function() end,
            SetTexture = function() end,
          }
        end,
      }
      LI.HookButton(button)
      LI.HookButton(button)
      Assert.Equal(hookCount, 1, "second HookButton on same button must be a no-op")
    end)
  end)

  test("LI.HookButton ignores nil button input", function()
    WithGlobals(MinimalGlobals(), function()
      local addon = LoadAddonModules({ "isiLive_lfg_flags.lua" })
      addon._LFGFlagsInternal.HookButton(nil) -- must not throw
    end)
  end)

  test("LI.HookButtons hooks every button in the supplied table", function()
    WithGlobals(MinimalGlobals(), function()
      local addon = LoadAddonModules({ "isiLive_lfg_flags.lua" })
      local LI = addon._LFGFlagsInternal
      local function makeBtn(id)
        return {
          resultID = id,
          HookScript = function() end,
          CreateTexture = function()
            return {
              SetSize = function() end,
              SetPoint = function() end,
              Hide = function() end,
              Show = function() end,
              SetTexture = function() end,
            }
          end,
        }
      end
      LI.HookButtons({ makeBtn(1), makeBtn(2), makeBtn(3) })
      -- No assertion on count needed; cache size grows by 3 in the
      -- weak hooked map. Smoke-test: must not throw.
      LI.RefreshAll() -- must iterate the freshly hooked buttons
    end)
  end)

  test("LI.HookButton OnEnter callback re-runs UpdateButton on the hooked button", function()
    WithGlobals(MinimalGlobals(), function()
      local addon = LoadAddonModules({ "isiLive_lfg_flags.lua" })
      local LI = addon._LFGFlagsInternal
      local applyCalls = 0
      local button = {
        resultID = 7,
        _isiFlagTex = nil,
        HookScript = function(self, scriptType, fn)
          if scriptType == "OnEnter" then
            self._enterHook = fn
          end
        end,
        CreateTexture = function()
          local tex = {
            SetSize = function() end,
            SetPoint = function() end,
            Hide = function()
              applyCalls = applyCalls + 1
            end,
            Show = function() end,
            SetTexture = function() end,
          }
          return tex
        end,
      }
      LI.HookButton(button)
      local before = applyCalls
      button._enterHook(button)
      Assert.True(applyCalls > before, "OnEnter hook must drive UpdateButton -> ApplyFlagToButton")
    end)
  end)

  test("LI.ResetCacheForTests clears the result tag cache observable via GetCacheForTests", function()
    local globals = MinimalGlobals()
    globals.C_LFGList = {
      GetSearchResultInfo = function()
        return { leaderName = "Hero-RealmA" }
      end,
    }
    WithGlobals(globals, function()
      local addon = LoadAddonModules({ "isiLive_lfg_flags.lua" })
      addon.LFGFlags.Register({
        localeModule = {
          GetUnitServerLanguage = function()
            return "EN"
          end,
          GetLanguageFlagTexturePath = function(tag)
            return "media/" .. tag
          end,
        },
      })
      addon._LFGFlagsInternal.GetTagForResult(123) -- populates cache
      addon._LFGFlagsInternal.ResetCacheForTests()
      local cache = addon._LFGFlagsInternal.GetCacheForTests()
      Assert.True(next(cache) == nil, "ResetCacheForTests must clear the cache")
    end)
  end)

  -- Group bonus feature -------------------------------------------------------

  test("LI.BuildBonusSuffix localizes class bonuses and keeps German text for deDE only", function()
    WithGlobals(BonusGlobals({ IsiLiveDB = { locale = "deDE" } }), function()
      local addon = LoadBonusModules(LoadAddonModules)
      local LI = addon._LFGFlagsInternal
      local suffix = StripColors(LI.BuildBonusSuffix("DEMONHUNTER", nil, { dealsMagicDamage = true }))
      Assert.True(suffix:find("%+3%% Magie", 1, false) ~= nil, "German locale must use the German magic label")
    end)

    WithGlobals(BonusGlobals({ IsiLiveDB = { locale = "frFR" } }), function()
      local addon = LoadBonusModules(LoadAddonModules)
      local LI = addon._LFGFlagsInternal
      local suffix = StripColors(LI.BuildBonusSuffix("DEMONHUNTER", nil, { dealsMagicDamage = true }))
      Assert.True(suffix:find("%+3%% Magic", 1, false) ~= nil, "non-German locales must keep English bonus labels")
    end)
  end)

  test("LI.BuildApplicantBonusBadge treats verified BL and BR as major utility", function()
    WithGlobals(BonusGlobals(), function()
      local addon = LoadBonusModules(LoadAddonModules)
      local badge = addon._LFGFlagsInternal.BuildApplicantBonusBadge("HUNTER", 253, { dealsPhysicalDamage = true })
      Assert.Equal(badge, "++", "Beast Mastery Hunter Bloodlust must produce the major utility badge")
      badge = addon._LFGFlagsInternal.BuildApplicantBonusBadge("HUNTER", 255, { dealsPhysicalDamage = true })
      Assert.Equal(badge, "++", "Survival Hunter Bloodlust must produce the major utility badge")
      badge = addon._LFGFlagsInternal.BuildApplicantBonusBadge("DRUID", nil, { dealsMagicDamage = true })
      Assert.Equal(badge, "++", "Druid battle resurrection must produce the major utility badge")
    end)
  end)

  test("LI.BuildApplicantBonusBadge does not treat Marksmanship Hunter as Bloodlust", function()
    WithGlobals(BonusGlobals(), function()
      local addon = LoadBonusModules(LoadAddonModules)
      local badge = addon._LFGFlagsInternal.BuildApplicantBonusBadge("HUNTER", 254, { dealsPhysicalDamage = true })
      Assert.Equal(badge, "+", "Marksmanship Hunter must keep Hunter's Mark but not the Bloodlust major badge")
    end)
  end)

  test("LI.BuildApplicantBonusBadge respects the logged-in player's relevant stats", function()
    WithGlobals(BonusGlobals(), function()
      local addon = LoadBonusModules(LoadAddonModules)
      local LI = addon._LFGFlagsInternal
      local mageProfile = { usesIntellect = true, dealsMagicDamage = true }
      Assert.Equal(
        LI.BuildApplicantBonusBadge("DEMONHUNTER", nil, mageProfile),
        "+",
        "magic-damage buff must be relevant for a magic-damage player"
      )
      Assert.Nil(
        LI.BuildApplicantBonusBadge("WARRIOR", nil, mageProfile),
        "attack-power buff must not be relevant for an intellect caster"
      )
    end)
  end)

  test("LI.BuildSearchResultBonusBadge returns plus-plus when a search result offers BL", function()
    local globals = BonusGlobals({
      C_LFGList = {
        GetSearchResultInfo = function()
          return { numMembers = 1 }
        end,
        GetSearchResultPlayerInfo = function()
          return { classFilename = "HUNTER", specID = 253, className = "Hunter", specName = "Beast Mastery" }
        end,
      },
    })
    WithGlobals(globals, function()
      local addon = LoadBonusModules(LoadAddonModules)
      local badge = addon._LFGFlagsInternal.BuildSearchResultBonusBadge(17)
      Assert.Equal(badge, "++", "search-result badge must surface major BL utility")
    end)
  end)

  test("LI.BuildSearchResultMemberBonuses resolves German Verstärkung only for Evoker", function()
    local currentClass = "SHAMAN"
    local globals = BonusGlobals({
      IsiLiveDB = { locale = "deDE" },
      C_LFGList = {
        GetSearchResultInfo = function()
          return { numMembers = 1 }
        end,
        GetSearchResultPlayerInfo = function()
          return {
            classFilename = currentClass,
            className = currentClass == "EVOKER" and "Rufer" or "Schamane",
            specName = "Verstärkung",
          }
        end,
      },
    })
    WithGlobals(globals, function()
      local addon = LoadBonusModules(LoadAddonModules)
      local LI = addon._LFGFlagsInternal
      local members = Assert.NotNil(
        LI.BuildSearchResultMemberBonuses(17),
        "shaman enhancement text must still produce shaman class bonuses"
      )
      local shamanSuffix = StripColors(members[1].suffix)
      Assert.True(
        shamanSuffix:find("Meisterschaft", 1, true) ~= nil,
        "German enhancement shaman must keep the shaman mastery bonus"
      )
      Assert.True(
        shamanSuffix:find("Schwarzmacht", 1, true) == nil,
        "German enhancement shaman must not be interpreted as augmentation evoker"
      )

      LI.ResetCacheForTests()
      currentClass = "EVOKER"
      members = Assert.NotNil(
        LI.BuildSearchResultMemberBonuses(17),
        "German augmentation evoker text must produce evoker spec bonuses"
      )
      local evokerSuffix = StripColors(members[1].suffix)
      Assert.True(
        evokerSuffix:find("Schwarzmacht", 1, true) ~= nil,
        "German augmentation evoker must resolve Ebon Might"
      )
    end)
  end)

  test("LI.BuildSearchResultBonusBadge accepts tuple spec IDs only for their matching class", function()
    local currentClass = "SHAMAN"
    local currentNumeric = 253
    local globals = BonusGlobals({
      C_LFGList = {
        GetSearchResultInfo = function()
          return { numMembers = 1 }
        end,
        GetSearchResultPlayerInfo = function()
          return currentNumeric, currentClass
        end,
      },
    })
    WithGlobals(globals, function()
      local addon = LoadBonusModules(LoadAddonModules)
      local LI = addon._LFGFlagsInternal
      Assert.Equal(
        LI.BuildSearchResultBonusBadge(17),
        "++",
        "Shaman must keep its own Bloodlust but not inherit Hunter spec bonuses from tuple noise"
      )
      local members = Assert.NotNil(LI.BuildSearchResultMemberBonuses(17), "shaman bonuses must still resolve")
      local shamanSuffix = StripColors(members[1].suffix)
      Assert.True(shamanSuffix:find("Mastery", 1, true) ~= nil, "shaman tuple result must keep mastery")
      Assert.True(
        shamanSuffix:find("5%% dmg", 1, false) == nil,
        "shaman tuple result must not inherit Hunter's Mark from numeric tuple noise"
      )

      LI.ResetCacheForTests()
      currentClass = "HUNTER"
      currentNumeric = 253
      Assert.Equal(
        LI.BuildSearchResultBonusBadge(17),
        "++",
        "matching Hunter tuple spec ID must keep the verified Bloodlust bonus"
      )
    end)
  end)

  test("LFGFlags.SetGroupBonusesEnabled disables search-result bonus computation", function()
    local globals = BonusGlobals({
      C_LFGList = {
        GetSearchResultInfo = function()
          return { numMembers = 1 }
        end,
        GetSearchResultPlayerInfo = function()
          return { classFilename = "HUNTER", specID = 253 }
        end,
      },
    })
    WithGlobals(globals, function()
      local addon = LoadBonusModules(LoadAddonModules)
      addon.LFGFlags.SetGroupBonusesEnabled(false)
      Assert.Nil(
        addon._LFGFlagsInternal.BuildSearchResultBonusBadge(17),
        "disabled class-bonus setting must fail closed for search-result badges"
      )
      addon.LFGFlags.SetGroupBonusesEnabled(true)
      Assert.Equal(
        addon._LFGFlagsInternal.BuildSearchResultBonusBadge(17),
        "++",
        "reenabling class bonuses must restore search-result badge computation"
      )
    end)
  end)

  test("LI.BuildSearchResultBonusBadge caches search-result bonus lookups", function()
    local infoCalls = 0
    local memberCalls = 0
    local globals = BonusGlobals({
      C_LFGList = {
        GetSearchResultInfo = function()
          infoCalls = infoCalls + 1
          return { numMembers = 1 }
        end,
        GetSearchResultPlayerInfo = function()
          memberCalls = memberCalls + 1
          return { classFilename = "HUNTER", specID = 253 }
        end,
      },
    })
    WithGlobals(globals, function()
      local addon = LoadBonusModules(LoadAddonModules)
      local LI = addon._LFGFlagsInternal
      Assert.Equal(LI.BuildSearchResultBonusBadge(17), "++", "first lookup must resolve the badge")
      Assert.Equal(LI.BuildSearchResultBonusBadge(17), "++", "second lookup must reuse cached badge data")
      Assert.Equal(infoCalls, 1, "cached badge lookup must not re-read search-result info")
      Assert.Equal(memberCalls, 1, "cached badge lookup must not re-read member info")
    end)
  end)

  test("LFG search-entry tooltip hook clears the bonus cache for the updated result", function()
    local currentClass = "WARRIOR"
    local currentSpecID = 71
    local hookSecureCalls = {}
    local globals = BonusGlobals({
      C_LFGList = {
        GetSearchResultInfo = function()
          return { numMembers = 1 }
        end,
        GetSearchResultPlayerInfo = function()
          return { classFilename = currentClass, specID = currentSpecID }
        end,
      },
    })
    globals.LFGListFrame = {
      SearchPanel = {
        ScrollBox = {
          GetFrames = function()
            return {}
          end,
        },
      },
    }
    globals.ScrollBoxUtil = {
      OnViewFramesChanged = function() end,
      OnViewScrollChanged = function() end,
    }
    globals.hooksecurefunc = function(name, fn)
      hookSecureCalls[name] = fn
    end
    WithGlobals(globals, function()
      local addon = LoadBonusModules(LoadAddonModules)
      local LI = addon._LFGFlagsInternal
      Assert.Nil(LI.BuildSearchResultBonusBadge(17), "initial warrior AP bonus is irrelevant for a mage and caches nil")

      addon.LFGFlags.HookSearchPanel()
      currentClass = "HUNTER"
      currentSpecID = 253
      local tooltipHook =
        Assert.NotNil(hookSecureCalls.LFGListUtil_SetSearchEntryTooltip, "search-entry tooltip hook must be registered")
      tooltipHook(nil, 17)

      Assert.Equal(
        LI.BuildSearchResultBonusBadge(17),
        "++",
        "updated result must recompute after the specific bonus cache entry was cleared"
      )
    end)
  end)

  test("LI.ApplyApplicantBonusToButton does not append duplicate tooltip bonus lines", function()
    local addLineCalls = 0
    local tooltipLines = {}
    local globals = BonusGlobals({
      C_LFGList = {
        GetApplicantInfo = function()
          return { numMembers = 1 }
        end,
        GetApplicantMemberInfo = function()
          return "Ariphinne", "HUNTER", "Hunter", 80, 280, 0, false, false, true, "DAMAGER", nil, 0, 0, nil, nil, 253
        end,
      },
    })
    local button = { applicantID = 77 }
    globals.GameTooltip = {
      GetOwner = function()
        return button
      end,
      NumLines = function()
        return #tooltipLines
      end,
      AddLine = function(_, text)
        addLineCalls = addLineCalls + 1
        tooltipLines[#tooltipLines + 1] = text
      end,
      Show = function() end,
    }
    globals.GameTooltipTextLeft1 = {
      GetText = function()
        return tooltipLines[1]
      end,
    }
    WithGlobals(globals, function()
      local addon = LoadBonusModules(LoadAddonModules)
      addon._LFGFlagsInternal.ApplyApplicantBonusToButton(button)
      addon._LFGFlagsInternal.ApplyApplicantBonusToButton(button)
      Assert.Equal(addLineCalls, 1, "same open tooltip must receive the applicant bonus line only once")
    end)
  end)

  test("LI.ApplyApplicantBonusToMemberFrame writes and clears the applicant plus badge", function()
    local globals = BonusGlobals({
      C_LFGList = {
        GetApplicantInfo = function()
          return { numMembers = 1 }
        end,
        GetApplicantMemberInfo = function()
          return "Ariphinne", "HUNTER", "Hunter", 80, 280, 0, false, false, true, "DAMAGER", nil, 0, 0, nil, nil, 253
        end,
      },
    })
    WithGlobals(globals, function()
      local addon = LoadBonusModules(LoadAddonModules)
      local member = {
        memberIdx = 1,
        Name = NewFontStringStub(),
        CreateFontString = function()
          return NewFontStringStub()
        end,
      }

      addon._LFGFlagsInternal.ApplyApplicantBonusToMemberFrame(member, 51, 1)
      Assert.NotNil(member._isiLiveBonusBadge, "applicant member frame must get a bonus badge font string")
      Assert.Equal(member._isiLiveBonusBadge._text, "++", "Hunter applicant must render the major utility badge")
      Assert.True(member._isiLiveBonusBadge._shown == true, "badge must be shown after applying a bonus")

      addon.LFGFlags.SetGroupBonusesEnabled(false)
      Assert.Equal(member._isiLiveBonusBadge._text, "", "disabling class bonuses must clear known applicant badges")
      Assert.True(member._isiLiveBonusBadge._shown == false, "disabling class bonuses must hide known applicant badges")
    end)
  end)

  test("LI.ApplyGroupBonusTooltipLines appends localized suffixes to matching search-result member lines", function()
    local line2 = NewFontStringStub()
    line2:SetText("Mitglieder")
    local line3 = NewFontStringStub()
    line3:SetText("Druide - Wächter")
    local line4 = NewFontStringStub()
    line4:SetText("Erstellt: vor 1 Min.")

    local globals = BonusGlobals({
      IsiLiveDB = { locale = "deDE" },
      C_LFGList = {
        GetSearchResultInfo = function()
          return { numMembers = 1 }
        end,
        GetSearchResultPlayerInfo = function()
          return {
            classFilename = "DRUID",
            specID = 104,
            className = "Druide",
            specName = "Wächter",
          }
        end,
      },
      GameTooltip = {
        NumLines = function()
          return 4
        end,
      },
    })
    globals.GameTooltipTextLeft1 = NewFontStringStub()
    globals.GameTooltipTextLeft2 = line2
    globals.GameTooltipTextLeft3 = line3
    globals.GameTooltipTextLeft4 = line4

    WithGlobals(globals, function()
      local addon = LoadBonusModules(LoadAddonModules)
      addon._LFGFlagsInternal.ApplyGroupBonusTooltipLines(99)
      local plain = StripColors(line3:GetText())
      Assert.True(plain:find("%+3%% Versa", 1, false) ~= nil, "tooltip member line must include the Druid versa bonus")
      Assert.True(plain:find("BR", 1, true) ~= nil, "tooltip member line must include the Druid BR utility")
    end)
  end)

  test(
    "LI.ApplyGroupBonusTooltipLines matches exact member lines without a German or English section header",
    function()
      local line1 = NewFontStringStub()
      line1:SetText("Membres")
      local line2 = NewFontStringStub()
      line2:SetText("Druide - Wächter")
      local line3 = NewFontStringStub()
      line3:SetText("Créé : il y a 1 min.")

      local globals = BonusGlobals({
        IsiLiveDB = { locale = "frFR" },
        C_LFGList = {
          GetSearchResultInfo = function()
            return { numMembers = 1 }
          end,
          GetSearchResultPlayerInfo = function()
            return {
              classFilename = "DRUID",
              specID = 104,
              className = "Druide",
              specName = "Wächter",
            }
          end,
        },
        GameTooltip = {
          NumLines = function()
            return 3
          end,
        },
      })
      globals.GameTooltipTextLeft1 = line1
      globals.GameTooltipTextLeft2 = line2
      globals.GameTooltipTextLeft3 = line3

      WithGlobals(globals, function()
        local addon = LoadBonusModules(LoadAddonModules)
        addon._LFGFlagsInternal.ApplyGroupBonusTooltipLines(99)
        local plain = StripColors(line2:GetText())
        Assert.True(
          plain:find("%+3%% Versa", 1, false) ~= nil,
          "fallback matching must append bonuses to the exact class/spec line"
        )
        Assert.True(
          StripColors(line1:GetText()):find("%+3%% Versa", 1, false) == nil,
          "fallback matching must not append bonuses to a non-member header line"
        )
      end)
    end
  )
end
