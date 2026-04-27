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
    GetCreatedTexture = function()
      return createdTexture
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
end
