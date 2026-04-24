# Changelog

## 2026-04-24 - Version 0.9.184 (patch)

- **Hotfix: 12.0 Secret-Value taint crash on nameplates during an active key ([ui/isiLive_mob_nameplate.lua](../ui/isiLive_mob_nameplate.lua)):**
  - Live bug reported by user: `595x ui/isiLive_mob_nameplate.lua:230: attempt to compare local 'guid' (a secret string value, while execution tainted by 'isiLive')`. Root cause: in `IsEligibleUnit`, the `guid == ""` comparison was evaluated **before** the `IsSecretValue(guid)` check. In 12.0-Midnight the `UnitGUID(unit)` return for some protected nameplate slots comes back as a Secret-Valued string — `type()` still returns `"string"` (safe), but the `==` operator on a Secret-String taints the execution stack and raises `ADDON_ACTION_FORBIDDEN`. Same pattern already fixed in [ui/isiLive_mob_tooltip.lua](../ui/isiLive_mob_tooltip.lua) in v0.9.180, but the brand-new nameplate module introduced in v0.9.182 reintroduced it.
  - Fix: `IsSecretValue(guid)` is now evaluated **before** `guid == ""` on line 230 (`IsEligibleUnit`). Short-circuit `or` guarantees the comparison is only reached once the Secret-Value check has ruled out a tainted GUID.
  - **Preventive audit** of the rest of the module found three analogous ordering mistakes on paths that did not crash in this report but could under different scenario shapes:
    - `GetActiveChallengeMapID()` — `mapID <= 0` before `IsSecretValue(mapID)`. A Secret-Valued numeric `mapID` would have tainted the comparison before the guard ran. Reordered to Secret-check first.
    - `ResolveScenarioProgress()` — `numCriteria <= 0` before `IsSecretValue(numCriteria)`. Same class of bug. Reordered, and moved the `tonumber()` conversion to after the Secret-check so we operate on the raw field.
    - `BuildText(percentString, ...)` — `percentString ~= ""` before `not IsSecretValue(percentString)`. The caller already Secret-checks `percentString` on line 344 before calling `BuildText`, so this path never crashed in practice, but the defensive ordering inside `BuildText` itself is now correct so the function is safe under any caller.
  - Root-cause class documented as "Secret-Value ordering invariant": any value coming through `pcall` from a Blizzard API in a protected context must be `IsSecretValue`-checked **before** any `==`, `~=`, `<`, `<=`, `>`, `>=`, `..`, or `string.match` / `string.format` operation. `type()`, `rawget`, and the Secret-check itself (`issecretvalue(v)` via `rawget`) are the only operations that are guaranteed non-tainting on Secret Values.
  - 1061/1061 use-case scenarios pass. No test changes: the existing `MobNameplate hides text when UnitGUID is a Secret Value` scenario exercises the logical path, but the Lua test harness cannot simulate runtime-taint on a primitive string (Lua metatables on strings are not customizable for `__eq` in 5.1 without global `debug.setmetatable` hacks), so the ordering invariant is preserved via code review. A future audit task in [todo.md](../todo.md) could lift the invariant into a lint rule if the need for recurrence-prevention grows.

## 2026-04-24 - Version 0.9.183 (patch)

- **Defaults fuer frische Installationen neu kalibriert auf "Namensplakette / Rest-Anzeige Aus / Schriftgroesse 12 / Position Rechts" (match settings-screenshot):**
  - `format.bossTargetMode` Default `"next"` → `"off"` in [ui/isiLive_mob_nameplate.lua](../ui/isiLive_mob_nameplate.lua), Factory-Helper `ResolveMobNameplateBossTargetMode` Fallback ebenso. Alle 3 Fallback-Stellen in [ui/isiLive_settings.lua](../ui/isiLive_settings.lua) (`NormalizeBossTargetMode`, `ResolveBossTargetModeFromDB`, Reset-Pfad) konsistent umgezogen.
  - `appearance.fontSize` Default `10` → `12` in allen 4 Fallback-Stellen (Modul, Factory initial, Factory onChange, Settings-Getter, Settings-Setter, Preview-Reader, Refresh-Hook).
  - M+-Forces-Display-Mode bei komplett leerer SavedVariable-DB: bisher `mplusForcesEstimate ~= false` (nil → true → "tooltip"). Neu: explizite One-Time-Migration beim Factory-Init schreibt `mobNameplateEnabled = true, mplusForcesEstimate = false` in die DB, wenn beide Keys `nil` sind — danach lesen alle Code-Pfade die persistierten Werte. Bestehende User behalten ihren Mode: wer 0.9.181 mit `mplusForcesEstimate == true` (explizit per Settings-Toggle aktiviert) installiert hatte, bleibt auf "tooltip".
  - `ResolveMplusForcesModeFromDB(db)` im Settings-Getter wurde strenger: `db.mplusForcesEstimate == true` statt `~= false`. Damit faellt das implizite Default-ON weg; die Wahl muss explizit in der DB stehen. Die Factory-Init-Migration stellt sicher dass der Default-Zustand dort auch wirklich hinterlegt ist.

- **Persistenz-Fix: Position-Selector wurde bei `panel.Refresh()` nicht neu mit der DB synchronisiert (z.B. nach Sprachwechsel oder Kategorie-Switch).**
  - `controls.nameplatePosition.UpdateHighlight()` fehlte in [ui/isiLive_settings.lua](../ui/isiLive_settings.lua) `RefreshSettingsControls`. Die 4 Position-Buttons haetten damit nach einem Refresh evtl. veraltete Highlight-States gezeigt, waehrend `db.mobNameplatePosition` korrekt im Hintergrund war.
  - Jetzt eingebaut analog zu `nameplateDisplayMode.UpdateHighlight()` und `nameplateBossTargetMode.UpdateHighlight()`.

- **Nameplate remainder anzeigen: "Next boss" vs. "Final boss" als 3-Weg-Selektor (`ui/isiLive_mob_nameplate.lua`, `ui/isiLive_settings.lua`):**
  - Der bisherige einzelne "Rest bis nächstem Boss anzeigen (+X%)"-Toggle wird durch einen **3-Options-Selektor** ersetzt: **Off / Next boss / Final boss**. Exklusiv (Radio), immer genau einer aktiv. Default `"next"`.
  - **`"next"`-Mode** (wie bisher): Remainder bis zum nächsten noch nicht besiegten Boss-Target aus [data/isiLive_mplus_boss_targets.lua](../data/isiLive_mplus_boss_targets.lua). Bsp. Skyreach, Progress 17%, Boss 1 Target 28.07 → `+11%`.
  - **`"end"`-Mode neu**: Remainder bis 100% Forces (Endboss-Schwelle, unabhängig von Boss-Anzahl). Bsp. Progress 17% → `+83%`. Nützlich als Gesamtfortschritts-Anzeige.
  - DB-Key `mobNameplateBossTargetMode` ∈ `{"off","next","end"}` ersetzt die frühere `mobNameplateShowBossTarget`-Boolean. Migration in [factory/isiLive_factory.lua](../factory/isiLive_factory.lua) (`ResolveMobNameplateBossTargetMode`): alter `== false` → `"off"`, sonst → `"next"`. Der alte Boolean wird weiterhin synchron geschrieben (für SavedVar-Rückwärtskompatibilität mit 0.9.182-Installationen die manuell downgraden).
  - Modul-API `MobNameplate.SetFormat` akzeptiert jetzt `bossTargetMode = "off"|"next"|"end"` statt `showBossTarget = bool`. Neuer Helper `ResolveBossRemainder(mode)` im Nameplate-Modul: "end" braucht nur die Scenario-API (kein Boss-Target-DB-Lookup), "next" funktioniert wie vorher. Preview in Settings simuliert beide Modi (`+13%` vs. `+83%`).
  - 4 neue Locale-Keys in allen 8 Sprachen: `SETTINGS_NAMEPLATE_BOSS_TARGET_MODE` + `_MODE_OFF`/`_NEXT`/`_END`. Alter Key `SETTINGS_NAMEPLATE_SHOW_BOSS_TARGET` in allen Sprachen entfernt.
  - Tests: Das `SetFormat(showBossTarget)`-Szenario wurde in zwei aufgeteilt — `bossTargetMode=next renders +X% remainder to next boss` + `bossTargetMode=end renders remainder to 100%`. `ui_settings`-Checkbox-Count 24→23 (ein Toggle weniger, Selector zählt als Buttons nicht als Checkbox). Gesamt 1060→1061 Szenarien.

## 2026-04-24 - Version 0.9.182 (minor)

- **New feature: Mythic+ enemy-forces overlay on nameplates (`ui/isiLive_mob_nameplate.lua`) — complements the existing mouseover-tooltip forces line with an always-on text over every hostile unit's nameplate during a key:**
  - Source of truth is Blizzard's native 12.0 API `C_ScenarioInfo.GetUnitCriteriaProgressValues(unit)` which returns `rawCount, _, percentString`. No MDT runtime dependency — the addon remains self-contained; our build-time [tools/sync_mdt_forces.lua](../tools/sync_mdt_forces.lua) already supplies the per-NPC + per-dungeon totals in [data/isiLive_mplus_forces.lua](../data/isiLive_mplus_forces.lua) and is now also consulted for the optional `count/total` format option. This explicitly avoids the `MDT:GetEnemyForces(npcID)` pattern Keystone Polaris uses, which forces every user to install MDT alongside.
  - Activation gate (all four must hold): `C_ChallengeMode.IsChallengeModeActive()` true, user toggle set via settings, `UnitReaction(unit,"player") ≤ 4` (hostile/neutral only — friendly units skipped), and `UnitGUID` is a real non-empty string that is not a Secret Value. Events driving refresh: `NAME_PLATE_UNIT_ADDED/REMOVED`, `CHALLENGE_MODE_START`, `PLAYER_ENTERING_WORLD`, `SCENARIO_UPDATE`. Frames are pooled per unit token so `CreateFrame` is called at most once per concurrent nameplate slot, not per event. 12.0 Secret-Value hardening applies to every protected-context return (`GetActiveChallengeMapID`, `UnitGUID`, `UnitReaction`, and both `rawCount` + `percentString` from `GetUnitCriteriaProgressValues`) — each is pcall-wrapped and routed through a local `IsSecretValue(v)` helper backed by `rawget(_G, "issecretvalue")`.
  - Configurable via new SavedVar keys on `IsiLiveDB` (flat, matching existing conventions like `mplusForcesEstimate`): `mobNameplateEnabled` (default `false` — see Plater/Platynator note below), `mobNameplateShowPercent` (default `true`), `mobNameplateShowCount` / `mobNameplateShowTotal` (default `false`, count-only vs `count/total` format), `mobNameplateFontSize` (8-24, default 10), `mobNameplatePosition` (`LEFT`/`RIGHT`/`TOP`/`BOTTOM`, default `RIGHT`), plus `mobNameplateXOffset`/`mobNameplateYOffset`. Factory wires `SetFormat` + `SetAppearance` + `Register` + `SetEnabled` through a new `onMobNameplateChange` callback so every settings checkbox/slider refreshes the live state without a reload.
  - Settings UI gets a dedicated new "Nameplates" section (between Display and Behavior) with toggle + percent/count/total checkboxes + font-size slider + position option-selector. A Plater/Platynator soft-detect (checks both `C_AddOns.IsAddOnLoaded` and the legacy global `IsAddOnLoaded`) shows a dezent warn-note at build time: "Plater/Platynator already shows M+ count? Leave this off." — no hard disable, no `hooksecurefunc` on their internals, user decides. Default-OFF is intentional: most Plater/M+ users already have a Wago script doing this (although many such scripts break in 12.0 because they chain `UnitGUID` → strsplit → `MDT:GetEnemyForces`, a path that Secret Values now taint — see the [gerritalex.de Midnight nameplate writeup](https://gerritalex.de/blog/nameplates-in-midnight)).
  - Full locale coverage across all 8 supported languages (enUS, deDE, frFR, esES, ptBR, itIT, ruRU, trTR) in [locale/isiLive_texts.lua](../locale/isiLive_texts.lua). 13 new keys: `SETTINGS_SECTION_NAMEPLATES`, `_HINT`, `NAMEPLATE_EXTERNAL_WARN`, `NAMEPLATE_FORCES`, `_SHOW_PERCENT`, `_SHOW_COUNT`, `_SHOW_TOTAL`, `_FONT_SIZE`, `_POSITION`, `_POS_LEFT/RIGHT/TOP/BOTTOM`. ASCII-only transliteration for ruRU and accent-stripped German/French/Italian/etc. kept consistent with the rest of the file.
  - 12 scenarios in [testmodul/isilive_test_scenarios_mob_nameplate.lua](../testmodul/isilive_test_scenarios_mob_nameplate.lua) cover: Register succeeds/fails for each missing API (`C_ScenarioInfo`, `C_NamePlate`), `SetEnabled(true)` registers exactly the 5 expected events on a dedicated frame and `SetEnabled(false)` unregisters them all, happy-path percent rendering for an eligible hostile unit, friendly units (`reaction > 4`) skipped, challenge-mode-inactive skipped, Secret-Valued GUID path, Secret-Valued `percentString` path, `SetFormat({showCount=true})` renders raw integer, `SetFormat({showCount=true,showTotal=true})` renders `count/total`, and frame-pool cleanup on disable. Tests are registered in [tools/usecase_scenarios.lua](../tools/usecase_scenarios.lua) and run as part of both local and CI usecase validation (total now 1060/1060 passing).
  - Existing regression test in [testmodul/isilive_test_scenarios_ui_settings.lua](../testmodul/isilive_test_scenarios_ui_settings.lua) that asserts the exact number of sliders and checkboxes in the settings panel was updated: 2→3 sliders (BG opacity, UI scale, nameplate font-size), 23→24 checkboxes (legacy `mplusForces`+`nameplateForces` toggles replaced by a 3-way display-mode selector; `showCount`+`showTotal` redundant toggles dropped — see next bullet for rationale; new `showBossTarget` toggle added). The position option-selector uses `Button` frames which are not counted.
  - No TOC `## Interface:` change — still `120005`. No new bundled libraries, no MDT runtime dependency added.

- **Nameplate overlay upgrade: section-% (bis nächstem Boss) statt redundanter count-anzeige (`ui/isiLive_mob_nameplate.lua`, `data/isiLive_mplus_boss_targets.lua`):**
  - Rationale: Die bisherigen Sub-Toggles `showCount` und `showTotal` zeigten exakt dieselbe Per-Mob-Contribution-Information wie `showPercent`, nur in anderer Formatierung (`5`, `5/431` vs. `1.16%`) — das ist redundant und für M+-Spieler nicht hilfreich. Der interessantere Datenpunkt ist "wie viel Forces fehlen noch bis zum nächsten Boss-Target". Beide alten Toggles entfernt (auch DB-Keys `mobNameplateShowCount`/`mobNameplateShowTotal` werden nicht mehr gelesen, bleiben aber als Legacy-Felder in alten SavedVars stumm liegen ohne Migration).
  - Neues Toggle `showBossTarget` (Default ON) + neuer DB-Key `mobNameplateShowBossTarget`. Output-Format jetzt z.B. `1.16% | +13%` — erster Wert ist der Per-Mob-Beitrag, zweiter ist "noch 13 %-Punkte bis die aktuelle Boss-Target-Schwelle erreicht ist".
  - Neue Daten-Datei [data/isiLive_mplus_boss_targets.lua](../data/isiLive_mplus_boss_targets.lua) mit kumulativen Boss-Target-Prozenten pro Dungeon. Werte sind Community-Konvention, adaptiert aus [community source](https://github.com/community-source/forces-data) (GPLv2, Attribution im File-Header) — KP pflegt das Mapping seit Jahren, und die Zahlen stammen ursprünglich aus Speedrun-Community-Konsens. Für die aktuellen 8 Midnight-Season-1-Dungeons: Skyreach {28.07, 52.2, 60.09, 100}, SotT {14.61, 56.87, 100, 100}, Algethar {21.52, 51.09, 77.17, 100}, PoS {58.63, 79.94, 100}, Windrunner {45.35, 57.36, 100, 100}, Magisters {27.81, 48.91, 78.06, 100}, NPX {29.36, 73.66, 100}, Maisara {48.6, 89.95, 100}. User-Override via `IsiLiveDB.bossTargetsOverride[mapID] = { ... }` möglich (kein UI dafür — manueller Lua-Edit).
  - Scenario-API-Integration in [ui/isiLive_mob_nameplate.lua](../ui/isiLive_mob_nameplate.lua): neue Helper `ResolveBossTargets(mapID)` + `ResolveScenarioProgress()` + `ResolveBossRemainder()`. `ResolveScenarioProgress` iteriert `C_ScenarioInfo.GetStepInfo().numCriteria` und für jeden `GetCriteriaInfo(i)`: Criteria mit `totalQuantity > 1` ist die Enemy-Forces (liefert aktuellen Progress via `quantity / totalQuantity`), Criteria mit `totalQuantity == 1` sind Bosse (Blizzard ordnet sie in bossOrder-Sequenz, daher ist der n-te Boss-Criteria-Index auch der n-te Boss-Target aus unserer DB). Erster nicht-`completed` Boss → nächster Target-Wert → Remainder = max(0, target - currentProgress). Alle API-Returns pcall-umhüllt und `IsSecretValue`-gecheckt (auch `totalQuantity`/`quantity`, für 12.0-Midnight-Secret-Value-Härtung).
  - Settings-Section angepasst: der Sub-Toggle-Block in der Nameplates-Sektion enthält jetzt nur noch `Show percentage` + `Show remainder to next boss (+X%)` statt der alten drei. Die Preview-Zeile simuliert das Zielformat mit festen Beispielwerten `1.16%` und `+13%` (statt früher `1.16% | 5/431`).
  - Locale: `SETTINGS_NAMEPLATE_SHOW_COUNT` und `SETTINGS_NAMEPLATE_SHOW_TOTAL` in allen 8 Sprachen entfernt, `SETTINGS_NAMEPLATE_SHOW_BOSS_TARGET` hinzugefügt (enUS: "Show remainder to next boss (+X%)", deDE: "Rest bis naechstem Boss anzeigen (+X%)", usw.).
  - Tests: `MobNameplate SetFormat(showCount)` und `SetFormat(showCount+showTotal)` durch zwei neue Szenarien ersetzt — `SetFormat(showBossTarget) renders +X% remainder` (arrangiert Scenario-Criteria-Mock mit 4 Bossen + Forces-Criteria, prüft "+11%" bei 17% current vs. 28.07% target) und `hides boss-target when no active challenge map matches` (mapID 99999 → kein DB-Entry → BossTarget-Teil fällt weg, `showPercent` rendert trotzdem). `testmodul/isilive_test_ui_helpers.lua` um Scenario-API-Mock erweitert (`GetStepInfo`/`GetCriteriaInfo` via `state.scenarioCriteria`).
  - Keine neue externe Runtime-Dependency. KP wird nicht geladen oder abgefragt — wir haben lediglich deren Zahlenwerte als Datenpunkte übernommen, genauso wie unsere Forces-DB MDT-Mob-Counts übernimmt.

## 2026-04-22 - Version 0.9.181 (patch)

- **WoW 12.0.5 client compatibility — `## Interface: 120005` in `isiLive.toc`:**
  - Bumped from `120001` so the AddOns screen stops flagging isiLive as out-of-date on 12.0.5 clients. Title and version strings in `isiLive.toc` aligned to `v0.9.181`.
  - No runtime code changes were required. The `wow-api-check` skill was run against the full 12.0+ addon-restriction rule set: no `COMBAT_LOG_EVENT_UNFILTERED` registration (the addon uses `UNIT_SPELLCAST_SUCCEEDED` for BR/Lust, see `game/isiLive_combat_events.lua`); every `RegisterEvent` call lives in a main chunk or a login/factory init callback, never re-entered from a protected dispatcher (`CHALLENGE_MODE_START`, `ENCOUNTER_START`, etc.); `C_MythicPlus.GetOwnedKeystoneLink` is defensively guarded with `type == "function"` and has the bag-scan fallback for item `180653` (`core/isiLive_context_helpers.lua`); both real `PlaySoundFile` call sites use the `"SFX"` channel; no `|cff[...]|r` color-bracket pattern is injected into `SendChatMessage` outside a real `|H...|h|h` hyperlink; the peer-tooltip wording in `ui/isiLive_roster_tooltip.lua` is `"Client version: %s"` without a `(pN)` protocol suffix and without the `protocolVersion` branch. All six rule families passed on the 0.9.180 codebase, so 0.9.181 ships the same binary surface with only the TOC flag bumped.
  - Baseline version fields synchronised across `isiLive.toc`, `CHANGELOG_RELEASE.md`, `README.md`, `docs/ARCHITECTURE.md`, and `docs/USECASES.md`.

## 2026-04-21 - Version 0.9.180 (patch)

- **M+ Forces DB lifetime gate (`tools/check_mplus_db_lifetime.lua`) — prevents shipping a stale `data/isiLive_mplus_forces.lua` that was generated against an outdated MDT clone:**
  - The forces DB carries `expiresAt = "YYYY-MM-DD"` (15 days after `generatedAt`, written by `tools/sync_mdt_forces.lua`). The new gate loads the file via `loadfile + chunk("isiLive", t)` (the same sandbox contract as the addon's TOC loader — no side-effects, no globals leak) and compares `expiresAt` against today's UTC date (`os.date("!%Y-%m-%d")`, overridable via `ISILIVE_TODAY_OVERRIDE` for deterministic tests). Exit codes: `0` = fresh or boundary (today ≤ expiresAt), `1` = stale (today > expiresAt), `2` = malformed / missing DB. Bypass for emergency releases: `ISILIVE_ALLOW_STALE_MPLUS_DB=1` (must be exactly `"1"`, not truthy — any other value still fails, so `=true` or `=yes` does not accidentally disable the gate).
  - Wired into both CI surfaces as a new step between Locale Drift and the usecase validator: `.github/workflows/lua-check.yml` step `M+ Forces DB Lifetime` and `tools/validate_ci_local.ps1` preflight call `Invoke-CheckedCommand "M+ Forces DB Lifetime" "lua tools/check_mplus_db_lifetime.lua"`. `testmodul/isilive_test_scenarios_architecture.lua` now asserts both files contain the lifetime step so the gate cannot be silently dropped from CI by a future refactor.
  - 10 scenarios in `testmodul/isilive_test_scenarios_mplus_db_lifetime.lua` cover: fresh DB, boundary (today == expiresAt), stale DB, `ALLOW_STALE=1` bypass, `ALLOW_STALE` with non-`"1"` value does **not** bypass, missing file, missing `MPlusForces` table, malformed date string, missing `expiresAt`, and the shipped production DB loading cleanly. The tests load the tool via `chunk("module")` so the CLI main-chunk `os.exit` path is skipped and the tool's exported functions become callable as a library.

- **Automated weekly M+ forces DB refresh (`.github/workflows/sync-mplus-forces.yml`) — zero-click end-to-end refresh timed against the MDT release window:**
  - Scheduled trigger `cron: "0 6 * * 4"` fires every Thursday 06:00 UTC (= 07:00 CET / 08:00 CEST), positioned after the US Tuesday patch day + EU Wednesday weekly reset when MDT releases typically cluster. `workflow_dispatch` is also wired for manual on-demand refresh. `concurrency: { group: sync-mplus-forces, cancel-in-progress: false }` guards against overlapping runs (scheduled + manual dispatch racing) — queues behind any in-flight run instead of cancelling it mid-push.
  - Pipeline: Checkout → Setup Lua 5.1 → `git clone --depth 1 https://github.com/Nnoggie/MythicDungeonTools tools/cache/mdt` → `lua tools/sync_mdt_forces.lua` → `rm -rf tools/cache` (strip MDT source before CI gates so only the committed DB is present) → `git diff --quiet -- data/isiLive_mplus_forces.lua` into `steps.diff.outputs.changed` → all subsequent steps are gated on `changed == 'true'`. No diff means zero-work days are silent (no commit, no LuaRocks install, no lint runs).
  - Pre-commit CI preflight mirrors `lua-check.yml` exactly: Setup LuaRocks → `luarocks install luacheck 1.2.0-1` + `luarocks install luafilesystem 1.8.0-1` → StyLua check → Luacheck → Lua Syntax Check → Lua Metrics Check → Locale Drift Check → **M+ Forces DB Lifetime Check** (validates that the freshly regenerated DB has a future `expiresAt`, which it always should — this catches generator regressions that produce a malformed date) → Deterministic Usecase + Rules Logic Validation. Only after all seven gates pass does the workflow commit.
  - Commit step: `github-actions[bot]` identity, `git add data/isiLive_mplus_forces.lua` (narrow staging — the cache was already cleaned in step 4), MDT version extracted from the regenerated file via a sandbox load (`local f=assert(loadfile(...)); local t={}; f("isiLive",t); io.write(t.MPlusForces.mdtVersion)`) rather than `dofile` so the `_, addonTable = ...` varargs contract is honoured. Commit message format: `data: refresh M+ forces DB from MDT <mdtVersion>`. `git push origin HEAD:main` pushes directly to `main` — no PR review gate, because the workflow is the review gate (seven CI checks run before the commit is even created).
  - Permissions: `contents: write` only. No external secrets, no branch creation, no PR API usage. Uses the default `GITHUB_TOKEN` — the manual "release to CurseForge" flow remains a separate, explicitly-authorised action.

- **Generator format fix (`tools/sync_mdt_forces.lua`) — blocks the auto-refresh from silent-no-op failing on every Thursday:**
  - `formatDbLua` was writing column-aligned keys (`season      = %q,`, `mdtVersion  = %q,`, `npcCount     = %d,`) to produce a visually tidy diff. StyLua's default ruleset normalises `=` padding to single-space, so any freshly regenerated DB failed `stylua --check .` on the next CI run. In the new auto-refresh workflow that would have meant: every Thursday the scheduled run would regenerate the DB, hit the StyLua gate, and bail before the commit step — producing no artefact and no visible error unless someone inspected Actions manually.
  - All six `add(string.format("<key><padding>= %q,", ...))` calls in `formatDbLua` switched to single-space `= ` format. The committed `data/isiLive_mplus_forces.lua` was regenerated from the local MDT clone and passes `stylua --check` cleanly; the on-disk layout now matches what the generator writes, so future refreshes are idempotent.

- **Mob tooltip forces line — taint hardening for 12.0 "secret" GUIDs (`ui/isiLive_mob_tooltip.lua`):**
  - In-game bug report: `57x isiLive/ui/isiLive_mob_tooltip.lua:53: attempt to compare field 'guid' (a secret string value tainted by 'isiLive')` originating from the `SetWorldCursor` → `TooltipDataHandler.ProcessInfo` → our `Enum.TooltipDataType.Unit` post-call path. The previous `ResolveGuid` implementation did `type(tooltipData.guid) == "string" and tooltipData.guid ~= ""`. In 12.0 the `tooltipData.guid` for protected world-cursor tooltips can be a *secret string* — `type()` still returns `"string"` (safe), but any comparison (`~= ""`) taints the call stack and raises the forbidden-function crash shown in the report. `NpcIdFromGuid`'s `guid == ""` check and the subsequent `guid:match(...)` would have tainted too once reached.
  - New `IsSecretValue(v)` helper (same pattern already used locally for `GetActiveChallengeMapID` and in `logic/isiLive_queue.lua` / `ui/isiLive_lfg_flags.lua`) reads `rawget(_G, "issecretvalue")` and returns `type(fn) == "function" and fn(v) == true`. `ResolveGuid` calls it on both potential inputs: `tooltipData.guid` (secret → fall through to the `UnitGUID("mouseover")` backup) and the `UnitGUID` return value (secret → return `nil`, the caller bails without appending a forces line). Reading the field and calling `type()` do not taint; only the comparison/pattern match do, so the helper gate sits exactly before those operations.
  - `testmodul/isilive_test_scenarios_mob_tooltip.lua` gained one scenario: `MobTooltip honors issecretvalue on tooltipData.guid and UnitGUID fallback`. Real-engine secret GUIDs still have `type == "string"`, so the test stubs `issecretvalue` to return `true` for specific string GUIDs, then drives the tooltip callback first with `{ guid = secretString }` (exercises the `tooltipData.guid` secret path) and then with `{ dataInstanceID = 42 }` (exercises the `UnitGUID("mouseover")` secret-fallback path). Both must yield `#tooltipLines == 0` without raising.

- **Group roster repopulates after /reload inside an active M+ key (`logic/isiLive_group.lua`):**
  - User report: "nach einem reload im dungeon sehe ich keine gruppenmitglieder mehr". Repro path: inside an active keystone run, the main frame is usually hidden during combat, which means the hidden-frame event gate in `core/isiLive_bootstrap.lua:166-175` (`shouldAllowWhenHidden`) suppresses `GROUP_ROSTER_UPDATE` (`if not inChallenge and isInPartyInstance()` → `false` for party non-challenge, and the trailing `return isInGroup() and not inChallenge` → `false` while the challenge is active). The existing backup in `logic/isiLive_event_handlers_runtime.lua:418-420` covers this by manually calling `ctx.handleGroupRosterUpdate()` from `PLAYER_ENTERING_WORLD` when `wasInPartyInstance == nil and ctx.isInGroup()` (i.e. on reload). But `HandleGroupRosterUpdate` in `logic/isiLive_group.lua:366-370` had an unconditional early return `if deps.getActiveChallengeMapID() then updateUI(); updateLeaderButtons(); return end` — the fallback called the function, the function bailed out before `AddPlayerToRoster` / `UpdatePartyMembersInRoster`, and the roster stayed empty. The "Active M+ key blocks roster rebuild" scenario (v0.9.36) explicitly asserted this behaviour without distinguishing the "ongoing update during key" case from the "post-reload cold-start during key" case.
  - Fix: the active-challenge branch now populates the roster when `joinedNow == true` (`inGroupNow and not wasInGroupBefore`). Inside an active keystone no one joins a group mid-dungeon, so `joinedNow` in the challenge branch is the clean signal for "fresh Lua state after /reload". The branch runs `AddPlayerToRoster` + `UpdatePartyMembersInRoster` and then falls through to the same `updateUI()` / `updateLeaderButtons()` it did before. Critically it does **not** fall through to the regular `if joinedNow then setRoster({}); setMainFrameVisible(true, {reason="queue"}); captureQueueJoinCandidate(); announceQueuedGroupJoin(); onGroupJoined(); ... end` block below — that would auto-open the frame the user had intentionally closed during the pull, capture a non-existent queue candidate and fire the group-join sound, all of which are wrong for a reload.
  - Test rewrite in `testmodul/isilive_test_scenarios_group.lua`: the existing `Active M+ key blocks roster rebuild` scenario, which passed the default `wasInGroup = false` (= `joinedNow = true` internally) and asserted `state.roster.player == nil`, was locking in the buggy reload behaviour. Renamed to `Active M+ key does not rebuild roster on ongoing updates`, flipped to `wasInGroup = true` so `joinedNow = false` and the skip-rebuild path is exercised for its real purpose (preserving per-member spec/ilvl/rio/keys across repeated `GROUP_ROSTER_UPDATE` bursts during a key). New scenario `Active M+ key rebuilds roster after /reload (joinedNow path)` explicitly drives `wasInGroup = false` + `getActiveChallengeMapID = 2649` and asserts `state.roster.player` and `state.roster.party1` / `party4` are populated while `state.queued == 0`, `state.announced == 0`, `state.groupJoinedCalls == 0` and `#state.mainFrameVisibleCalls == 0` — i.e. the roster is rebuilt without any of the join-side-effects firing.

- **Tests:**
  - `tools/usecase_scenarios.lua` registers `testmodul/isilive_test_scenarios_mplus_db_lifetime.lua` alongside the existing `_mob_tooltip` / `_killtrack` scenarios.
  - 760 / 760 use-case scenarios pass. Stylua, luacheck, syntax, metrics, locale drift, lifetime gate and the deterministic usecase/rules logic validator are all green on the full local preflight.

## 2026-04-20 - Version 0.9.179 (patch)

- **BR / Bloodlust group announce: switched from `SendChatMessage` to the isiLive addon-message channel to avoid the 12.0 `ADDON_ACTION_FORBIDDEN` regression:**
  - Since 12.0 (Midnight), `SendChatMessage` is a protected function when invoked from a tainted execution path. `HandleUnitSpellcastSucceeded` in `game/isiLive_combat_events.lua` fires inside an active M+ keystone / boss encounter, which is exactly the context the 12.0 "Secret Values" system marks as tainted. The v0.9.175 broadcast path (local `DefaultSendChat` → `SendChatMessage(msg, "INSTANCE_CHAT" | "RAID" | "PARTY")`) therefore raised `ADDON_ACTION_FORBIDDEN AddOn 'isiLive' tried to call the protected function 'UNKNOWN()'` on every BR / Lust cast in a live key (reported 3× in a single pull from BugGrabber; the underlying `pcall` silently ate the failure client-side but the protected-call popup still fired for the caster).
  - New transport: a dedicated `BRLUST:<KIND>:<caster>:<spellID>` addon-message payload routed through `Sync.SendCombatAnnounce` in `logic/isiLive_sync.lua`, which reuses the existing `DispatchAddonMessage` pipeline (ChatThrottleLib v24 with `"NORMAL"` priority, falling back to raw `C_ChatInfo.SendAddonMessage` if the lib is unavailable). Addon-message traffic is not gated by the 12.0 protected-chat taint because it never touches `SendChatMessage` — DBM / BigWigs / WeakAuras sync the same way mid-encounter without issue.
  - Receiver dispatch: `Sync.ProcessAddonMessage` now recognises `BRLUST:` as a new payload bucket and surfaces the parsed `{kind, caster, spellID}` in `result.combatAnnounce`. `HandleChatMsgAddonEvent` in `logic/isiLive_event_handlers_runtime.lua` invokes `ctx.showCombatAnnounce(syncResult.combatAnnounce)`, which renders the locale-resolved template (`COMBAT_CHAT_BR_USED` / `COMBAT_CHAT_LUST_STARTED`) via `ctx.Print` into `DEFAULT_CHAT_FRAME`. Unknown `BRLUST` kinds (anything other than `"BR"` / `"LUST"`) are silently dropped so older peers emitting a future variant cannot log-spam the receiver.
  - Self-cast visibility preserved: the sender also renders its own cast locally through the same `ctx.ShowCombatAnnounce` helper, so the Ego user still sees their own BR / Lust in chat even outside a group. The realm-stripping `FormatDisplayName` helper moved from `combat_events` into `factory/isiLive_factory_controllers.lua` so both the self-render path and the incoming-peer path share a single normalisation.
  - Non-isiLive players see nothing. This is intentional: the v0.9.175 iteration already hard-filtered on `unit == "player"` self-casts (to avoid the "table index is secret" spam from other players' `UNIT_SPELLCAST_SUCCEEDED` in protected zones), so the previous `SendChatMessage` broadcast was already the only way non-isiLive users could have seen the call. With `N` isiLive users in the group each caster is announced to the remaining `N-1` isiLive clients.
  - Architecture cleanup in `game/isiLive_combat_events.lua`: the `DefaultResolveChannel` / `DefaultSendChat` helpers and the `sendChat` / `getL` dependencies are deleted. `CombatEvents.CreateController` now takes a single new dependency `broadcastCombatAnnounce(kind, sourceName, spellID)` and the announce path no longer formats any chat strings — that responsibility lives entirely on the receiver side. Dedup (3 s window per `sourceName|spellID`) and the `chatAnnounceBR` / `chatAnnounceLust` sender toggles stay exactly as before; they now gate whether the addon-message goes out (and, symmetrically, whether the sender prints locally), not whether a chat-API call is attempted.

- **Tests:**
  - `testmodul/isilive_test_scenarios_combat_events.lua`: the `sendChat` mock (line-based capture) is replaced by a `broadcastCombatAnnounce` mock that captures `{kind, caster, spellID}` tuples. The BR / Lust / dedup / toggle / non-player-unit / `Reset` scenarios all re-assert on the new contract; the realm-strip assertion moved out because the sender now passes the raw unit name through and the receiver handles display formatting.
  - `testmodul/isilive_test_scenarios_sync.lua`: new assertions for `Sync.ProcessAddonMessage` on `BRLUST:BR:<caster>:<spellID>` and `BRLUST:LUST:<caster>:<spellID>` payloads, plus a negative test for `BRLUST:UNKNOWN:...` to confirm unknown kinds drop to `nil`.
  - `testmodul/isilive_test_fixtures.lua`: the `BuildEventHandlersBaseOptions` fixture gained a `showCombatAnnounce` no-op default so every existing event-handler scenario picks up the new required dependency via `Merge` without per-test wiring.
  - 723 / 723 use-case scenarios pass. Architecture-rules and locale-drift checks are clean.

## 2026-04-20 - Version 0.9.178 (patch)

- **Rename the "M2" main-horizontal layout to "M+" in all user-visible strings:**
  - The compact main-horizontal layout mode is the second "main" layout alongside the expanded M view. Historically the mode button in the title bar, the "default UI to open" dropdown in settings and the "fade out during combat" checkbox hint all labelled it as `M2`. That was an internal implementation term (the layout is the *second* Main-style layout) and not meaningful to users; the addon's whole purpose is Mythic+, so `M+` conveys its intent at a glance and stays consistent with existing references to `M+` queue / keystone / run across the rest of the UI.
  - `ui/isiLive_roster_layout.lua`: `LAYOUT_MODE_CONFIG[LAYOUT_MODE_COMPACT_MAIN_HORIZONTAL].label` switched from `"M2"` to `"M+"`. This feeds `CreateModeButton(mainFrame, def.xOffset, def.label, target, ...)` in `ui/isiLive_roster_panel.lua` and is the primary title-bar button label.
  - `ui/isiLive_roster_panel.lua`: `modeButtonDefs[1].label` (the separate static definition used for the tooltip / descriptor row) switched from `"M2"` to `"M+"`; the inline comment now reads `[M+][H][V]` instead of `[M2][H][V]`.
  - `ui/isiLive_settings.lua`: the fallback string for the "Default UI" dropdown entry changed from `"M2"` to `"M+"` so that locales without a translation also render the new label.
  - `locale/isiLive_texts.lua`: 16 values updated across all eight locales. `SETTINGS_DEFAULT_OPEN_UI_M2 = "M2"` becomes `"M+"` (8× identical). `SETTINGS_COMBAT_FADE_MM` loses the embedded `M2` reference in each language (e.g. `"Fade out during combat (M2 layout only)"` → `"Fade out during combat (M+ layout only)"`, `"Im Kampf ausblenden (nur M2-Layout)"` → `"Im Kampf ausblenden (nur M+-Layout)"`, plus the French/Spanish/Portuguese/Italian/Russian/Turkish variants). Locale **keys** (`SETTINGS_DEFAULT_OPEN_UI_M2`, `SETTINGS_COMBAT_FADE_MM`, `MODE_LAYOUT_M2`) are preserved — renaming the keys would have been a pure cosmetic rewrite touching every translation table and every test fixture.
  - Deliberately **not** renamed: the layout mode string `compact_main_horizontal` (persisted in `IsiLiveDB.rosterDefaultLayoutMode`), its legacy alias `compact_horizontal_2`, the `M2_ROW_LEFT_MARGIN` / `M2_MANAGEMENT_ROW_Y` / `M2_TOOLBAR_BUTTON_WIDTH` / etc. layout constants, and the `MODE_LAYOUT_M2` tooltip description text body. Touching any of those would have forced a SavedVariables migration and a mechanical churn diff across roster_layout, tests, docs and `.pkgmeta` with zero user-visible benefit.

- **Tests:**
  - `testmodul/isilive_test_scenarios_tank_helper.lua` adjusted the `m2Button._collapseButtonLabel` assertion from `"M2"` to `"M+"` (the internal `m2Button` variable name kept for historical continuity).
  - 723 / 723 use-case scenarios pass.

## 2026-04-20 - Version 0.9.177 (patch)

- **Readycheck 20 s-hold rendering: removed the split render pipeline that could drop the coloured background before the hold window ended:**
  - Root cause of the symptom "green/red row background disappears before the 20 s hold is up": `RenderRosterImpl` in `ui/isiLive_roster_panel_render.lua` cleared `readyCheckBackground` on every row via `ClearMemberRow` and rebuilt the row body without reapplying the ready-check colour. Reapplying it was deferred to a second pass, `RefreshReadyCheckStateImpl`, gated by `if isReadyCheckActive or HasReadyCheckHoldInRoster(state, roster) then ... end`. Any render triggered during a narrow window where the per-unit `readyCheckReadyUntil` / `readyCheckDeclinedUntil` maps had not yet been populated (e.g. between `READY_CHECK_FINISHED` firing and `PromoteReadyCheckReadyUnitsToHold` / `PromoteDeclinedReadyCheckUnitsToHold` filling the maps), or where `HasReadyCheckHoldInRoster` iterated the ordered roster and returned `false` for any other reason, cleared the background and never reapplied it — even though `displayData.readyCheckBackgroundColor` already carried the correct colour.
  - `RenderRosterImpl`'s main loop now calls `ApplyRowReadyCheckDisplay(row, displayData)` directly after `ApplyRowNameDisplay`, so the background is set (or hidden) in the same single pass that writes spec, name, key, ilvl, rio, dps and kick cells. The conditional `if isReadyCheckActive or HasReadyCheckHoldInRoster(...) then RefreshReadyCheckStateImpl({...}) end` block (23 lines) and the eleven unused local captures that only fed the `RefreshReadyCheckStateImpl` passthrough object (`buildDisplayData`, `truncateName`, `getShortSpecLabel`, `getLanguageFlagMarkup`, `getRioDelta`, `syncMarker`, `syncBadge`, `getPlayerSyncSummary`, `getReadyCheckReadyUntil`, `getReadyCheckDeclinedUntil`, `getTime`) were removed from `RenderRosterImpl`.
  - `RefreshReadyCheckStateImpl` itself stays: it is the public API surface consumed externally via `controller.RefreshReadyCheckState(roster)` in `ui/isiLive_roster_panel.lua` and invoked from `factory/isiLive_factory_controllers.lua:763` and `:1414` for targeted re-applies that must not rebuild the whole roster. `HasReadyCheckHoldInRoster` is also preserved as an `RI.HasReadyCheckHoldInRoster` export. The underlying state layer — per-unit `readyCheckReadyUntil` / `readyCheckDeclinedUntil` maps, the global `ctx.readyCheckHoldUntil` anchor and the `C_Timer.After`-based `ScheduleReadyCheckHoldClear` sweeper in `logic/isiLive_event_handlers_challenge.lua` — is untouched; the sweeper still triggers `RefreshReadyCheckUI` when the hold window elapses.
  - Side effect beyond the bug fix: render cost drops during the hold window because `BuildRowDisplayData`, `ApplyRowSpecDisplay` and `ApplyRowNameDisplay` no longer run twice per row per render.

- **Tests:**
  - 723 / 723 use-case scenarios pass. No test changes — the existing roster-render scenarios already exercised the single-pass contract.

## 2026-04-20 - Version 0.9.176 (patch)

- **Addon-message sync routed through ChatThrottleLib v24 with per-message priority:**
  - Embedded Mikk's Public Domain `ChatThrottleLib` (v24, ~534 lines) as `libs/ChatThrottleLib/ChatThrottleLib.lua` and loaded it as the first file in `isiLive.toc` so every sync send benefits from shared burst budgeting, CPS throttling and WoW's own congestion backpressure. WoW's addon-message pipe is a shared per-client bandwidth resource — hitting it raw (`C_ChatInfo.SendAddonMessage`) drops silently under contention; ChatThrottleLib queues, prioritises and redrives without loss.
  - New helper `DispatchAddonMessage(prefix, payload, channel, priority)` in `logic/isiLive_sync.lua` calls `ChatThrottleLib:SendAddonMessage(priority, prefix, text, chattype)` when the lib is loaded and falls back to raw `C_ChatInfo.SendAddonMessage` otherwise, so the addon still runs standalone if the lib ever fails to load.
  - Priority per message type reflects "speed vs. correctness" weighting: `KICK` and `REQSYNC` use `ALERT` (near-real-time — a missed kick broadcast degrades coordination during pulls); `STATS`, `DPS`, `LOC` use `BULK` (metrics can yield under load without hurting gameplay); `HELLO`, `KEY`, `TARGET`, `SHAREKEYS` and the LibKeystone party/request envelopes use `NORMAL`. All 11 send sites across the sync module were converted — no raw `C_ChatInfo.SendAddonMessage` call remains in `isiLive_sync.lua`.
  - Every send now logs its dispatch result as `sent=true|false` in the SyncLog trace, including the two LibKeystone flows (`send_libkeystone_request`, `send_libkeystone_party`) which were previously silent on failure. Drops are now visible in the debug log without needing ingame inspection of the chat pipe.
  - `.luacheckrc` split the `libs/` exclude into separate `/` and `\\` patterns so luacheck's Lua pattern matcher correctly skips the vendored lib on both Windows and Linux CI runners (char-class `[/\\]` is invalid in Lua patterns and triggered the `"Invalid pattern '^[]"` crash on first commit). Added `ChatThrottleLib` as a `read_globals` entry. The vendored lib file carries a `---@diagnostic disable` header so Sumneko Lua-LS doesn't surface inject-field hints on Blizzard / WoW API references in VS Code.

- **Tests:**
  - Added `RegisterChatThrottleLibRoutingTests` in `testmodul/isilive_test_scenarios_sync.lua` with two scenarios: one stubs `ChatThrottleLib` with a capturing mock and asserts the priority routing for all eight synchronous sends (`KICK=ALERT`, `REQSYNC=ALERT`, `STATS=BULK`, `DPS=BULK`, `LOC=BULK`, `KEY=NORMAL`, `TARGET=NORMAL`, `HELLO=NORMAL`); the other omits `ChatThrottleLib` entirely and asserts the raw `C_ChatInfo.SendAddonMessage` fallback path still dispatches with the `KICK:` payload and `ISILIVE` prefix.
  - Existing `send_reqsync` trace-log scenario was updated to expect the new `sent=%s` suffix.
  - 723 / 723 use-case scenarios pass.

## 2026-04-19 - Version 0.9.175 (patch)

- **BR/Lust announce: self-cast only, broadcast to group chat (fixes 6102x "table index is secret" spam in M+):**
  - Root cause: WoW 12.0.0's Secret Values system masks the `spellID` parameter of `UNIT_SPELLCAST_SUCCEEDED` for *other players'* casts inside M+ / boss combat-restriction zones. `type(spellID) == "number"` still returns true (Secrets masquerade as numbers), but the table lookup `BR_SPELL_IDS[spellID]` throws `"table index is secret"`. In a single live key this fired thousands of times.
  - `game/isiLive_combat_events.lua` `HandleUnitSpellcastSucceeded` now hard-filters on `unit == "player"` *before* any spellID inspection. The caster's own spellID is not Secret in their own context, so the table lookup is safe. Each isiLive client detects exactly its own cast — N isiLive users in a group cover all N casters automatically, no peer-sync needed.
  - Switched the announcement output from local `print` to `SendChatMessage` so the whole group (including non-isiLive members) sees the line. New `DefaultSendChat` resolves the channel via `IsInGroup(LE_PARTY_CATEGORY_INSTANCE)` → `INSTANCE_CHAT`, else `IsInRaid()` → `RAID`, else `IsInGroup()` → `PARTY`. Solo = no-op. The send is wrapped in `pcall` so a failed broadcast never throws.
  - The `IsGroupUnit` helper was removed (party/raid units are now rejected by the simpler `unit == "player"` check).
  - `factory/isiLive_factory_controllers.lua` no longer passes `print = ctx.Print` to `CombatEvents.SetDependencies` — the module's internal `DefaultSendChat` handles broadcast directly.
  - Locale templates (`COMBAT_CHAT_BR_USED`, `COMBAT_CHAT_LUST_STARTED`) and dedup behavior (3 s window, `Reset()` on `CHALLENGE_MODE_START` / `CHALLENGE_MODE_COMPLETED`) are unchanged.

- **Tests:**
  - Rewrote `testmodul/isilive_test_scenarios_combat_events.lua` for the self-cast contract: all BR / Lust scenarios drive `HandleUnitSpellcastSucceeded("player", ...)`, the BuildController `print` field was renamed to `sendChat` and the `prints` capture array to `messages`. The former "non-group units" test was extended to also cover `party1` and `raid3` and re-purposed as "ignores casts from units other than the player", documenting the self-cast-only invariant.
  - 721 / 721 use-case scenarios pass.

## 2026-04-19 - Version 0.9.174 (patch)

- **Chat announcements for Battle Res and Bloodlust in Mythic+:**
  - New module `game/isiLive_combat_events.lua` listens on `COMBAT_LOG_EVENT_UNFILTERED` while `C_ChallengeMode.GetActiveChallengeMapID()` reports an active key. `SPELL_RESURRECT` entries whose `spellID` matches the four battle-res spells (`20484` Rebirth, `61999` Raise Ally, `391054` Intercession, `20707` Soulstone Resurrection) produce a single chat line via the addon's `Print` helper, formatted with the localized `COMBAT_CHAT_BR_USED` template (e.g. `"Alice hat BR auf Bob benutzt"`). `SPELL_CAST_SUCCESS` entries whose `spellID` matches the twelve Bloodlust/Heroism/Time Warp/Drum/Pet variants (`2825`, `32182`, `80353`, `264667`, `390386`, `381301`, `178207`, `230935`, `256740`, `292463`, `90355`, `160452`) produce a single chat line via the `COMBAT_CHAT_LUST_STARTED` template. A 3-second dedup window keyed by `sourceGUID|spellID` swallows double-fires from the combat log; `CHALLENGE_MODE_START` / `CHALLENGE_MODE_COMPLETED` reset it so back-to-back keys do not inherit stale state.
  - Both announcements default to enabled and are individually toggleable in the Blizzard settings panel. `ui/isiLive_settings.lua` grows a dedicated **Chat Announcements** section between Sounds and Debug with two checkboxes (`chatAnnounceBR`, `chatAnnounceLust`), using the default-true idiom `db.chatAnnounceBR ~= false` so fresh installs light up both lines without touching the saved variables.
  - Realm suffixes are stripped for the local-realm case so the chat line reads `"Alice used BR on Bob"` instead of `"Alice-Realm used BR on Bob-Realm"`. Cross-realm names keep the realm segment when the combat log provides one.
  - Factory wiring in `factory/isiLive_factory_controllers.lua` calls `CombatEvents.SetDependencies({ getL = ctx.GetL, getDB = function() return IsiLiveDB or {} end, print = ctx.Print })` right after the LFGDetect block so the module picks up the addon's chat-prefix/print and localized templates.
  - Locale: added `SETTINGS_SECTION_CHAT`, `SETTINGS_SECTION_CHAT_HINT`, `SETTINGS_CHAT_BR_ANNOUNCE`, `SETTINGS_CHAT_LUST_ANNOUNCE`, `COMBAT_CHAT_BR_USED` (format `%s ... %s`) and `COMBAT_CHAT_LUST_STARTED` (format `%s`) to all eight language tables in `locale/isiLive_texts.lua`.

- **Tests:**
  - Added `testmodul/isilive_test_scenarios_combat_events.lua` with ten scenarios covering auto-registration of the three combat events, BR announcement in key, BR suppression outside key, BR gated by `chatAnnounceBR`, BR dedup inside the 3 s window with post-window re-fire, non-BR resurrect spells ignored, Bloodlust announced in key, Sated/Exhaustion aura IDs ignored (not in the cast-ID set), Lust gated by `chatAnnounceLust`, and `Reset()` clearing the dedup map so the same cast fires again.
  - Updated the checkbox count in `testmodul/isilive_test_scenarios_ui_settings.lua` from 20 to 22 to account for the two new chat-announce toggles.

## 2026-04-19 - Version 0.9.173 (patch)

- **Disambiguate active-key owner via LFG leader hint:**
  - Previously `ResolveActiveKeyOwnerUnit` in `logic/isiLive_keysync.lua` fell back to `nil` whenever more than one roster member held a keystone for the same `mapID`. That blocked both the chat announcement (`"Ziel-Dungeon: <name> +<level>"`) and the red highlight on the key owner's row in the roster panel for an ambiguous group.
  - `game/isiLive_lfg_detect.lua` now captures `info.leaderName` from `C_LFGList.GetSearchResultInfo` when an invite is seen (stored in `pendingInvites[searchResultID]`) and promotes it to a new module-level `activeInviteLeader` state on `inviteaccepted`. A new public accessor `LFGDetect.GetActiveInviteLeader()` exposes the value. `ClearDetectedState`/`ClearAllStateImpl` drop it alongside the detected mapID.
  - `logic/isiLive_keysync.lua` gained two helpers: `SplitNameRealm` parses the Blizzard LFG name form (`"Name"` or `"Name-Realm"`) and `FindRosterUnitByHint` matches it against the roster (realm is optional — Blizzard omits it when it matches the local realm). `ResolveActiveKeyOwnerUnit` now takes an optional third `preferredOwnerName` parameter: when the hinted roster unit holds a key for `targetMapID`, that unit wins over the ambiguity guard. When the hinted unit is in the roster but does not expose a matching `keyMapID` (e.g. the leader has no isiLive / LibKeystone sync), the function fails closed and returns `nil` — it must not silently fall back to another member's key for the same dungeon. Only when the hint resolves to no roster entry at all (e.g. boost runs where the applicant is not the key owner) does the unique-owner fallback run.
  - `factory/isiLive_factory_controllers.lua` wires the hint through both call sites — `ctx.ResolveActiveKeyOwnerUnit` and the direct `ctx.keySyncController.ResolveActiveKeyOwnerUnit` call inside `SendOwnTargetSnapshot` now fetch `addonTable.LFGDetect.GetActiveInviteLeader()` and forward it to the controller.
  - Net effect: after accepting an LFG invite for an M+ key, the chat announcement carries the leader's keystone level and the roster row's key text renders red for the exact leader we joined — even if another group member happens to carry a key for the same dungeon.

- **Teleport active-target highlight is now a calm hatched border instead of a goldish blink:**
  - Removed the `Interface\\SpellActivationOverlay\\IconAlert` glow texture (`button.activeGlow`) and the bouncing 1.2× scale animation that pulsed the whole teleport button. The goldish blinking was visually loud and distracting.
  - Replaced the solid goldish action-button border (`UI-ActionButton-Border`, vertex color `1, 0.85, 0.1`) with a container frame that hosts short dashed segments along all four edges, rendered from `Interface\\Buttons\\WHITE8X8` in a cool blue-white (`0.55, 0.85, 1.0, 0.95`) with additive blending. Dash length, gap, and edge counts are recomputed from the button size on `OnSizeChanged`, so the hatch stays consistent across layout modes.
  - The active-target overlay tint changed from a strong orange (`1, 0.5, 0.0, 0.5`) to a dezent cool blue (`0.15, 0.35, 0.55, 0.25`) so the icon itself stays readable.
  - The animation group now targets the new hatched border (no scale, no glow) and runs a single slow alpha pulse (0.55 → 1.0, 1.2 s BOUNCE), so the border breathes gently instead of blinking. `button:SetScale(1)` resets around the former scale animation are gone since no scaling happens anymore.

- **Tests:**
  - Added five `ResolveActiveKeyOwnerUnit` scenarios in `testmodul/isilive_test_scenarios_keysync.lua` covering bare-name hint disambiguation, realm-qualified hint selection, fail-closed when the hinted leader holds a different mapID, fail-closed when the hinted leader has no synced key at all, and hint ignored when unknown so the unique-owner resolution still fires.
  - Added three `GetActiveInviteLeader` scenarios in `testmodul/isilive_test_scenarios_lfg_detect.lua`: leader captured on `inviteaccepted` with a Blizzard-style `Name-Realm`, no leader surfaced for own-queue `detectedMapID`, and `ClearAllState` drops the hint.

## 2026-04-19 - Version 0.9.172 (patch)

- **LFG chat noise reduced — only the key-level announcement remains:**
  - Removed the two redundant chat prints that fired on the LFG detection path: `"LFG-Einladung erkannt: <dungeon>"` (`OnInviteAccepted` and the delayed `GROUP_ROSTER_UPDATE` fallback) and `"LFG-Eintrag erkannt: <dungeon>"` (own/group listing via `CheckActiveGroup`) in `game/isiLive_lfg_detect.lua`.
  - Rationale: isiLive is a Mythic+ tool; the status-panel announcement `"Ziel-Dungeon: <dungeon> +<level>"` (from `MaybeAnnounceTargetDungeonChat` in `ui/isiLive_status.lua`) already covers the only scenario where a chat line carries new information — a key-tied group context. For non-M+ LFG (Heroic/Normal Dungeon Finder) no chat line is emitted anymore; highlight and status panel are unaffected.
  - Cleanup: removed the now-unused `localeGetter`/`SetLocaleGetter` plumbing in `game/isiLive_lfg_detect.lua`, the matching `SetLocaleGetter` wiring in `factory/isiLive_factory_controllers.lua`, the unused `Print`/`GetDungeonName` helpers, and the `LFG_DETECT_INVITE` / `LFG_DETECT_QUEUE` locale keys across all 8 language tables in `locale/isiLive_texts.lua`.

- **Tests:**
  - Removed the now-obsolete `"LFGDetect uses injected locale getter for chat message"` and `"LFGDetect own listing chat dedup prints once for same mapID"` scenarios from `testmodul/isilive_test_scenarios_lfg_detect.lua`; renamed the remaining test group function from `RegisterLFGDetectResetAndLocaleTests` to `RegisterLFGDetectResetTests`.
  - Dropped the `SetLocaleGetter = function() end` stubs from `isilive_test_scenarios_factory_highlight_priority.lua`, `isilive_test_scenarios_factory_primary_part1.lua`, and `isilive_test_scenarios_factory_primary_part2.lua`.
  - Updated rule `RULE-TARGET-DUNGEON-CHAT-DEDUP` in `docs/RULES_LOGIC.md` to drop the removed LFG-print test from the required-tests list; the status target-dungeon dedup test remains.

## 2026-04-19 - Version 0.9.171 (patch)

- **LFG invite highlight no longer drops before the roster settles:**
  - Root cause: after `LFG_LIST_APPLICATION_STATUS_UPDATED=inviteaccepted` the player's own LFG application briefly stays visible in `C_LFGList.GetActiveEntryInfo` (so `CheckActiveGroup` promotes the map to `lastQueueMapID`), and a second `LFG_LIST_ACTIVE_ENTRY_UPDATE` immediately drops it. `GROUP_ROSTER_UPDATE` arrives ~300ms later, so `IsInGroup()` was still returning `false` in that window and `ClearDetectedState` wiped `detectedMapID` before the roster could settle.
  - Fix: `CheckActiveGroup` skips `ClearDetectedState` while `pendingAcceptedInviteMapID ~= nil` so the invite-set highlight survives the own-listing drop until `GROUP_ROSTER_UPDATE` promotes the group and clears the guard flag.
  - Net effect: after accepting an LFG invite, the teleport button for the matching dungeon stays highlighted without a visible flicker-off.

- **deDE dungeon name:**
  - Corrected `Windlaeuferturm` to `Windläuferturm` for mapID 557 in `game/isiLive_season_data.lua` (and the matching baseline test in `testmodul/isilive_test_scenarios_teleport.lua`).

- **Tests:**
  - Added regression test `"Highlight invite-accepted state survives own-listing drop before GROUP_ROSTER_UPDATE settles"` in `testmodul/isilive_test_scenarios_lfg_detect.lua` that reproduces the race: it fires `invited` → `inviteaccepted` → `LFG_LIST_ACTIVE_ENTRY_UPDATE` (entry present) → `LFG_LIST_ACTIVE_ENTRY_UPDATE` (entry dropped, still not in group) → `GROUP_ROSTER_UPDATE` (in group) and asserts `detectedMapID` stays at 557 throughout.

## 2026-04-18 - Version 0.9.170 (patch)

- **Factory load-order guard:**
  - Added `isiLive_factory_kick_tracker.lua` and `isiLive_factory_minimap.lua` to `IMPLICIT_DEPENDENCIES["isiLive_factory.lua"]`, and `isiLive_factory_kick_tracker.lua` to `IMPLICIT_DEPENDENCIES["isiLive_factory_controllers.lua"]`, so tests that load either umbrella file automatically pull in the split submodules at runtime.
  - Reordered `isiLive.toc` so `factory_kick_tracker.lua` loads before `factory_controllers.lua`, matching the runtime call direction (controllers invokes `FI.InitializeFactorySecondaryKickTracker`).
  - Added three architecture tests (`RegisterArchitectureLoadOrderTests` in `testmodul/isilive_test_scenarios_architecture.lua`) that verify every `IMPLICIT_DEPENDENCIES` key/value is listed in `isiLive.toc`, that each dependency appears before its dependent in load order, and that both sides are registered in the harness `FILE_PATHS` — regression guard for future splits.

- **UI scenario split:**
  - `testmodul/isilive_test_scenarios_ui.lua` was sitting at 3139/3200 lines (61 below the hard file cap). Extracted the ~430 lines of WoW frame stub helpers (`CreateTextureStub`, `CreateFontStringStub`, `CreateAnimationGroupStub`, `ApplyFrameMethods`, `BuildCreateFrameStub`, `FindCombatRetryFrame`, `RequireValue`) into the new `testmodul/isilive_test_ui_helpers.lua` module, loaded via `loadfile` from any scenario that needs them.
  - Moved the five SettingsPanel test groups (`RegisterSettingsPanelResetActionTests`, `RegisterSettingsPanelTests`, `RegisterSettingsPanelBehaviorTests`, `RegisterSettingsPanelAdvancedTests`, `RegisterSettingsPanelSoundAndLegacyTests`) into the new sibling file `testmodul/isilive_test_scenarios_ui_settings.lua` and registered it in `tools/usecase_scenarios.lua`.
  - Both scenario files now sit under 1400 lines, leaving comfortable headroom for new tests, and the helpers are reusable if more UI scenario files are added in the future.

- **Roster-Panel refactor (Phase 1):**
  - Extracted CdTracker row creation/update (`CreateCdTrackerRow`, `UpdateCdTrackerRow`) into `ui/isiLive_roster_panel_cd_row.lua`.
  - Extracted KillTrack row creation/update (`CreateKillTrackRow`, `UpdateKillTrackRow`) into `ui/isiLive_roster_panel_kill_row.lua`.
  - Moved shared font helpers (`ApplyFontStringSize`, `FormatMplusTime`, `SetFontStringTextColorSafe`) into `ui/isiLive_roster_panel_helpers.lua`, exposed via the existing `_RosterInternal` namespace.
  - `ui/isiLive_roster_panel.lua` shrinks from 2661 to 2085 lines; load order, test harness `FILE_PATHS` / `IMPLICIT_DEPENDENCIES`, and the architecture tests are kept in sync with the new modules.
  - Net effect: row rendering is isolated from the main panel controller, the main file stays well under the file cap, and all 704 usecase tests continue to pass.

- **Roster-Panel refactor (Phase 2):**
  - Extracted panel chrome (`CreateFlatButton`, `CreatePanelHeaders`, `CreateM2ColumnGuides`, `AttachPanelButtonTooltip`, `AttachModeButtonTooltip`, `CreateTankHelperButtons`) and the shared column position/width constants into a new `ui/isiLive_roster_panel_chrome.lua`.
  - The column constants (`SPEC_COL_X`, `NAME_COL_X`, …, `KICK_COL_WIDTH`) are now published via `_RosterInternal`; `roster_panel.lua` imports them instead of keeping a parallel copy, so header layout and row rendering stay aligned by construction.
  - `CreateShareKeysButton` and `CreatePanelButtons` stay in `roster_panel.lua` because they are tightly coupled to the keystone announce helpers.
  - `ui/isiLive_roster_panel.lua` shrinks further from 2085 to 1698 lines; load order, test harness, and architecture tests updated accordingly. All 704 usecase tests still pass.

- **Roster-Panel refactor (Phase 3):**
  - Extracted the row builder (`CreateMemberRow`) and the entire roster render pipeline (`RenderRosterImpl`, `RefreshReadyCheckStateImpl`, `BuildRowDisplayData`, `IsEntryAtTargetDungeon`, `ApplyRowNameDisplay`, `ApplyRowSpecDisplay`, `ApplyRowReadyCheckDisplay`, `HasReadyCheckHoldInRoster`, `ResolveReadyCheckActive`, `SetKickCellText`) into the new `ui/isiLive_roster_panel_render.lua` and exposed them through `_RosterInternal`.
  - `RosterPanel.SetTraceLogger` now also publishes the trace logger via `_RosterInternal._rosterPanelLogger` so the split render module can emit `RosterPanel:`-prefixed traces without sharing an upvalue.
  - Removed the now-orphan tooltip / column-constant / layout-helper imports from `roster_panel.lua` to keep the file free of dead locals; the controller methods reach the render and kick-cell helpers through small `RI` shims.
  - `ui/isiLive_roster_panel.lua` shrinks further from 1698 to 1039 lines; the new render module sits at 715 lines (well below the 3200-line file cap, with `RenderRosterImpl` at ~299 lines below the 420-line function cap). The architecture kick-column test now reads the kick-ready marker from the render module.
  - All 704 usecase tests continue to pass.

- **CI hygiene:**
  - Collapsed accidental double blank lines introduced by the recent scenario/UI splits to satisfy `stylua --check`.
  - Imported `CD_TRACKER_ROW_HEIGHT` into the new kill-row module and removed the now-unused `CD_TRACKER_ROW_BOTTOM_OFFSET` upvalue from `ui/isiLive_roster_panel.lua` to clear `luacheck` warnings.
  - Added `---@diagnostic disable: undefined-global` to `isilive_test_scenarios_ui.lua`, `isilive_test_scenarios_ui_settings.lua` and `tools/check_locale_drift.lua` so the Lua language server stops flagging `loadfile` / `io` / `os` in files that run under the real Lua stdlib.

## 2026-04-18 - Version 0.9.169 (patch)

- **Share-keys chat announcement fixed end-to-end:**
  - Root cause 1: WoW silently drops addon-sent chat messages that wrap square brackets in `|cffXXXXXX...|r` color codes (server-side fake-item-link filter). The plain-text keystone fallback no longer emits a color code.
  - Root cause 2: `C_MythicPlus.GetOwnedKeystoneLink` was removed in current WoW retail. `BuildKeystoneChatLink` now falls back to a bag scan for item `180653` and uses `C_Container.GetContainerItemLink` to obtain a real, server-accepted keystone link.
  - Net effect: the "Keys teilen" button now posts a clickable keystone link to party chat that group members actually see.

- **German locale:**
  - Replaced `Schluessel` with `Key` / `Keys` across keystone-related UI strings (`COL_KEY`, `BTN_SHARE_KEYS`, `TOOLTIP_ANNOUNCE_KEYS`, `TOOLTIP_SYNC_DEBUG_KEY`, `ANNOUNCE_PREFIX`, `TESTALL_DUMMY_GROUP`). The Blizzard item name "Persönlicher Schlüssel zur Arkantine" stays unchanged.

- **Cleanup:**
  - Removed temporary share-keys diagnostic traces that were only needed to locate the chat-filter and API-removal root causes.

## 2026-04-17 - Version 0.9.168 (patch)

- **Runtime-log noise reduction:**
  - `[SYNC] send_key_blocked` (unchanged / cooldown) moved to Deep-level: redundant same-tick key-send guards no longer spam the normal log. New `Sync.SetDeepTraceLogger` wires `runtimeLogController.TraceDeep`.
  - `[SYNC] message_applied` now logs at Normal level only when at least one flag (`key/stats/dps/loc/target/kick/ack/reqsync`) is true; all-false applies (pure duplicate peer traffic) go to Deep.
  - `[TP] update_button_called` with `soundContext=nil` moved to Deep; explicit trigger contexts (`queue`, `invite`, …) remain on Normal.
  - `[STATE] check_entered_target_dungeon` now logs on Normal only when `match=true`; `match=false` polls go to Deep.
  - `[INSPECT] enqueue` stays on Normal only when `forceRefresh=true`; routine post-roster re-enqueues go to Deep. New inspect-controller option `logRuntimeTracefDeep`.
  - `[LFG] group_roster_update` deduped against its previous signature (inGroup/members/pendingAccept); identical repeats go to Deep. New `LFGDetect.SetDeepTraceLogger`.
  - `[LFG_GROUP5]` trace deduped against its previous signature (event/inGroup/members/detected_before/detected_after/pendingAccept/latestQueueMap/localTargetMapID/resolvedSpell); identical repeats go to Deep.
  - These changes shorten observed group-run logs by roughly half without removing any information — Deep level (`/isilive log level deep`) surfaces every suppressed entry again for debugging.

- **Documentation / release sync:**
  - Synced `isiLive.toc`, `README.md`, `ARCHITECTURE.md`, `USECASES.md`, and `CHANGELOG_RELEASE.md` to `0.9.168`.

## 2026-04-17 - Version 0.9.167 (patch)

- **Runtime log expansion:**
  - Added deterministic runtime-log trace coverage for ready-check events when logging is enabled.
  - Added deterministic factory coverage for LFG group-settle diagnostics written into the runtime log.
  - Split the oversized factory-primary and ready-check test blocks into smaller helpers so the new trace coverage stays within the metric limits.
  - Added lazy runtime-log formatting via `Logf`, lazy trace builders via `Trace`, and a ring-buffer-backed log store so disabled logging avoids expensive message construction and active logging avoids per-entry array shifting after the cap is reached.
  - Added stable runtime-log sequence numbers, precise `GetTime`-based timestamps, and normalized `[TAG] event=<action>` formatting for trace readability.
  - Added a runtime-log session header when logging is enabled, `/isilive log level normal|deep` controls, and Deep-only trace paths for high-volume UI/teleport diagnostics.
  - Wired Sync and LFG diagnostics through lazy trace builders so runtime-log formatting stays deferred until the enabled logger actually consumes the trace.
  - Added Deep trace coverage for roster render decisions, leader-button decisions, teleport UI visibility, teleport button decisions, and high-detail teleport resolution flow.
  - Extended the rule validator so split scenario files referenced via `dofile` and `require` are indexed from the scenario manifest.
  - Added deterministic 2,000-entry burst coverage for runtime-log, Sync, and Group/Roster trace paths to prove capped storage and stable tail order.

- **Documentation / release sync:**
  - Synced `isiLive.toc` and `CHANGELOG_RELEASE.md` to `0.9.167`.
  - Updated the documented validator baseline to `619` scenarios / `619` indexed tests over `45` modules.

## 2026-04-16 - Version 0.9.166 (fix)

- **ReadyCheck hold:** `CHALLENGE_MODE_START` no longer calls `ResetReadyCheckDeclinedTracking` — the 20-second ready/declined hold state now persists when the key starts immediately after a ready check instead of being wiped.
- **Share Keys:** Fixed `sendOwnKeystoneToChat` in `isiLive_controller_wiring.lua` using `ctx.GetRoster`, `ctx.GetOwnedKeystoneSnapshot`, and `ctx.GetL` (capital G) — these keys do not exist on the runtime-setup dict; corrected to `ctx.getRoster`, `ctx.getOwnedKeystoneSnapshot`, and `ctx.getL`. Remote clients now post their keystone to party chat when a SHAREKEYS request is received. This was a regression introduced in v0.9.119.
- **Dungeon name locale:** `GetDungeonName` in `isiLive_lfg_detect.lua` now passes the active locale tag (`IsiLiveDB.locale` or `GetLocale()` fallback) to `SeasonData.GetDungeonName`, fixing the English-only dungeon name in LFG detect chat output.
- **LFG highlight reliability:** `MapIDFromActivityID` now falls back to `C_LFGList.GetActivityInfoTable` (pcall-protected) when an activity ID is not in the static `ACTIVITY_TO_MAP` table. The resolved mapID is cached for subsequent calls, fixing unreliable dungeon detection for dungeons whose activity IDs differ from the static entries.

## 2026-04-15 - Version 0.9.165 (patch)

- **Hidden sync test coverage:**
  - Added deterministic coverage for hidden addon sync pre-rendering, hidden refresh replies, hidden LibKeystone replies, real sync parsing while hidden, and sparse hidden background snapshots.
  - The new scenarios cover `Event handlers pre-render UI for hidden addon sync updates`, `Event handlers answer refresh requests while frame is hidden`, `Event handlers answer LibKeystone requests while frame is hidden`, `Event handlers process LibKeystone requests through the real sync parser and refresh hidden state`, `Event handlers process KEY through the real sync parser and apply roster key data`, `Event handlers process TARGET through the real sync parser and refresh target UI`, `Event handlers process STATS through the real sync parser and backfill roster stats`, `Event handlers process DPS through the real sync parser and backfill roster DPS`, `Event handlers process LOC through the real sync parser and backfill roster location`, `Event handlers answer SHAREKEYS requests while frame is hidden`, `Event handlers skip SHAREKEYS cooldown when no own key chat share was posted`, `Event handlers process SHAREKEYS through the real sync parser and trigger cooldown`, `Event handlers process REQSYNC through the real sync parser and answer hidden refreshes`, `Event handlers process KICK through the real sync parser and refresh hidden state`, `Event handlers process HELLO through the real sync parser and answer hidden onboarding`, and `Event handlers process ACK through the real sync parser and cache hello info`.

- **Documentation / release sync:**
  - Synced `README.md`, `ARCHITECTURE.md`, `USECASES.md`, `CHANGELOG_RELEASE.md`, and `isiLive.toc` to `0.9.165`.
  - Updated the documented validator baseline to `602` scenarios / tests over `45` modules.
  - No runtime behavior changed in this bump.

## 2026-04-14 - Version 0.9.164 (patch)

- **Highlight / LFG hardening:**
  - The queue highlight resolver now ignores `C_ChallengeMode.GetActiveChallengeMapID()` before actual dungeon entry and only suppresses against the live player map, so the portal highlight no longer clears too early while the player is still outside.
  - Added deterministic coverage for the pre-entry queue highlight path and the late-roster false-negative invite-confirmation path.

- **Documentation / release sync:**
  - Synced `README.md`, `ARCHITECTURE.md`, `USECASES.md`, `CHANGELOG_RELEASE.md`, and `isiLive.toc` to `0.9.164`.
  - Updated the documented validator baseline to `581` scenarios / tests over `43` modules.

## 2026-04-14 - Version 0.9.163 (patch)

- **Documentation / release sync:**
  - Synced `README.md`, `ARCHITECTURE.md`, `USECASES.md`, `CHANGELOG_RELEASE.md`, and `isiLive.toc` to `0.9.163`.
  - This was a pure version sync with no runtime or UI behavior change.
  - No new deterministic test scenarios were added in this bump.
  - Updated the documented validator baseline to `579` scenarios / tests over `43` modules.

## 2026-04-14 - Version 0.9.162 (patch)
- **Share Keys no-op cooldown fix:**
  - Fixed the Share Keys button so the 30-second local cooldown starts only after a real effect happened: either the local key was announced or a `SHAREKEYS` addon sync request was successfully published.
  - `Sync.SendShareKeysRequest()` now returns an explicit success state instead of failing silently, which lets the roster UI keep the button usable when no addon sync channel exists.
  - Added deterministic coverage for the live `SendChatMessage` path, the no-op click path without chat or sync success, and the explicit sync-request failure contract.

- **Documentation / release sync:**
  - Synced `README.md`, `ARCHITECTURE.md`, `USECASES.md`, `CHANGELOG_RELEASE.md`, and `isiLive.toc` to `0.9.162`.
  - Updated the documented validator baseline to `577` scenarios / tests over `42` modules.

## 2026-04-14 - Version 0.9.161 (patch)

- **Kick tracker matrix and cooldown hardening:**
  - Added deterministic interrupt coverage for the full mapped spec matrix, including the exact no-kick specs, so every supported class/spec path is now exercised explicitly instead of relying on a handful of spot checks.
  - Fixed kick cooldown reduction scanning to walk all active talent trees instead of only the first tree, so reduced interrupt cooldowns are recognized and synced even when the reduction lives on another class/spec tree.
  - Added deterministic coverage for the multi-tree cooldown-reduction path to prevent future regressions in interrupt remain sync.

- **Documentation / release sync:**
  - Synced `README.md`, `ARCHITECTURE.md`, `USECASES.md`, `RELEASE.md`, `CHANGELOG_RELEASE.md`, and `isiLive.toc` to `0.9.161`.
  - Updated the documented validator baseline to `574` scenarios / tests over `42` modules.

## 2026-04-14 - Version 0.9.160 (patch)

- **Sync version fallback fix:**
  - `ACK` sync messages now persist the peer addon version as hello metadata, so the roster hover can still show the client version even when no full `HELLO` was observed beforehand.
  - Hidden clients now keep sending their `HELLO` inside group sync, so version visibility no longer depends on whether the peer had the UI frame visible.
  - Deterministic coverage now locks in the `ACK` parsing path, the hidden `HELLO` path, and tooltip version rendering from `ACK`-only hello info.

- **Documentation / release sync:**
  - Synced `README.md`, `ARCHITECTURE.md`, `USECASES.md`, `RELEASE.md`, `CHANGELOG_RELEASE.md`, and `isiLive.toc` to `0.9.160`.
  - Updated the documented validator baseline to `571` scenarios / tests over `42` modules.

## 2026-04-14 - Version 0.9.159 (patch)

- **Highlight priority hardening:**
  - LFG-detected mapID now outranks peer-synced highlight resolution, so an accepted invite or own listing keeps the portal target aligned with the concrete LFG context instead of a stale synced target.
  - Added deterministic coverage for the priority path in a dedicated factory highlight scenario module.

- **Documentation / release sync:**
  - Synced `README.md`, `ARCHITECTURE.md`, `USECASES.md`, `RELEASE.md`, `CHANGELOG_RELEASE.md`, and `isiLive.toc` to `0.9.159`.
  - Updated the documented validator baseline to `568` scenarios / tests over `42` modules.

## 2026-04-13 - Version 0.9.158 (patch)

- **Version bump:**
  - The addon metadata, release stub, architecture baseline, and usecase baseline were aligned to `0.9.158`.

## 2026-04-13 - Version 0.9.157 (patch)

- **Arkantine shortcut localization fix:**
  - The ESC-menu Arkantine shortcut now uses the exact localized German item name again, so the secure `/use` macro resolves on deDE clients.
  - Added regression coverage for the Arkantine shortcut macro text to prevent transliteration regressions.

## 2026-04-13 - Version 0.9.156 (patch)

- **Shared teleport refresh wiring fix:**
  - Teleport column refreshes now route through the shared highlight updater instead of bypassing the LFG-aware path with a naked teleport-button refresh.
  - Added deterministic architecture coverage so the factory keeps the teleport refresh on the shared highlight path.

## 2026-04-13 - Version 0.9.155 (patch)

- **LFG highlight visibility fix:**
  - LFG-driven teleport updates now auto-open the main frame once when a concrete resolved teleport target exists, so invite/listing highlights remain visible instead of only updating a hidden UI.
  - The auto-open only applies to invite/queue highlight updates, preserves the existing sound suppression, and stays gated by the normal frame visibility / combat rules.
  - Added regression coverage for the hidden-frame invite highlight path.

## 2026-04-13 - Version 0.9.154 (patch)

- **Late-wire LFG highlight hardening:**
  - `LFGDetect.SetHighlightCallback()` now replays the current resolved highlight state once when the callback is wired after `detectedMapID` already exists, so the teleport UI cannot miss a valid invite/listing highlight because of callback ordering.
  - Added deterministic coverage for the late-wire replay path so the visible portal state stays in sync even when the callback registration happens after the LFG confirmation event.

- **Ready-check roster render fix:**
  - `isiLive_roster_panel.lua` now resolves ready-check activity safely when the runtime provides either a boolean or a function, instead of calling a boolean like a callback.
  - The roster panel controller preserves boolean ready-check state and the regression coverage now locks in the non-crashing boolean path.

## 2026-04-13 - Version 0.9.153 (patch)

- **No-guess LFG hardening:**
  - Removed dungeon-name and token-based fallback resolution from `isiLive_lfg_detect.lua` so invite and listing detection now stays unresolved unless exact activity data is available.
  - Moved invite state to a pending-confirmation flow and kept the portal highlight/sound dispatch deterministic on the exact confirmation path.
  - Updated the deterministic LFG coverage and rule-to-test mapping to enforce the fail-closed no-guess contract.

## 2026-04-13 - Version 0.9.152 (patch)

- **LFG invite highlight fix:**
  - Incoming LFG invites now stay pending until the exact activity data is confirmed; the matching portal icon highlights on `inviteaccepted` instead of guessing from dungeon names.
  - Portal sounds are suppressed for invite-driven and queue-driven target refreshes; the sound remains reserved for actual active-target changes.
  - Updated the deterministic LFG and TeleportUI coverage to lock in the invite-silent highlight path and the fail-closed no-guess flow.
  - Updated the validator baseline references to `559` scenarios / tests over `40` modules.

## 2026-04-13 - Version 0.9.151 (patch)

- **LFG detection hardening:**
  - Injected the highlight callback and locale getter into `isiLive_lfg_detect.lua` so the game-layer module no longer needs direct `_factoryCtx` access or hardcoded chat strings.
  - Normalized invite/listing status handling, preserved pending invites across the active-entry ticker race, and cleared the full LFG state on group leave or `CHALLENGE_MODE_START`.
  - Added deterministic `LFGDetect` scenario coverage and registered the new module in the usecase harness.

- **Documentation / release sync:**
  - Synced `README.md`, `ARCHITECTURE.md`, and `USECASES.md` to the current runtime state.
  - Updated the validator baseline references to `556` scenarios / tests over `40` modules.

- **Locale and UI text cleanup:**
  - Standardized the German UI copy for clearer terminology while keeping established add-on labels such as `M+`, `Lead`, `UI`, and `SavedVariables` intact.
  - Transliterated locale strings with in-game rendering issues to ASCII across `deDE`, `frFR`, `esES`, `ptBR`, `itIT`, `ruRU`, and `trTR`.
  - Kept the deterministic validation green after the text-only changes (`lua tools/validate_usecases.lua`: `557 passed, 0 failed`).

- **Workflow formatting fix:**
  - Normalized the touched Lua files to Unix line endings and re-ran the local CI preflight so the GitHub Actions `Lua Check` workflow no longer fails on `StyLua`.
  - Verified the full local gate again after the formatter pass (`tools/validate_ci_local.ps1` passed, along with `lua tools/validate_usecases.lua`).

## 2026-04-12 - Version 0.9.151 (patch)

- **Sound settings and settings refresh:**
  - Moved the built-in sound toggles into a dedicated `Sounds` section in Blizzard Settings and added the portal-ready toggle alongside lead transfer and group join.
  - Centralized the three built-in sounds through the shared sound registry so enable-state resolution stays deterministic and switchable from one source of truth.
  - Refreshed the Settings page with a short intro and per-section hint lines so the layout reads more clearly and is easier to scan.

- **Documentation / release sync:**
  - Synced `README.md`, `ARCHITECTURE.md`, `USECASES.md`, and `isiLive.toc` to version `0.9.151`.
  - Kept the validator baseline aligned with the current deterministic scenario count.

## 2026-04-12 - Version 0.9.150 (patch)

- **Main-frame lock and tooltip localization:**
  - Added a top-right lock toggle in the main UI to prevent accidental dragging, backed by the `Lock main frame position` Blizzard setting.
  - Added `/isilive lock` and `/isilive unlock` as direct slash-command controls for the same saved lock state.
  - Added `/isilive resetui` to recenter the main window and restore UI scale / background opacity defaults when it is dragged off-screen.
  - The Settings button for `/isilive resetui` now shows the default values as a separate hint line and asks for confirmation before applying the reset.
  - Added localized tooltips for the main close button and lock button, including the CTRL+F9 reopen hint on the close button.
- **Documentation / release sync:**
  - Synced `README.md`, `ARCHITECTURE.md`, `USECASES.md`, and `RELEASE.md` to the current UI and validator baseline state.
  - Updated the local validator baseline references to `536` scenarios / tests over `39` modules.

## 2026-04-11 - Version 0.9.149 (patch)

- **LFG dungeon detection fix (`isiLive_lfg_detect.lua`):**
  - `GROUP_ROSTER_UPDATE` handler rewritten after LFGTeleportButtonMidnight: when not in any group → clear state and return; when in group and `detectedMapID` is nil → apply pending invite or call `CheckActiveGroup()`. Fixes the race condition where the event fired while the LFG group was still assembling, causing a false `ClearDetectedState()` that wiped the highlight immediately after it was set.
  - `Norm()` now strips non-alphanumeric characters (except `'` and whitespace) before keyword matching, matching LFGTeleportButtonMidnight's approach and guarding against broken multibyte sequences from tainted/locale LFG API strings.
  - `IsInRaid()` added alongside `IsInGroup()` in the group-presence check, consistent with LFGTeleportButtonMidnight.

## 2026-04-11 - Version 0.9.148 (patch)

- **Readycheck render split:**
  - Normal roster refreshes now re-apply the ready-check background during the hold window instead of letting a full roster render clear it implicitly.
  - The ready-check dedicated refresh path remains the canonical place for row background, waiting marker, and hold-state reapplication.
  - Added deterministic coverage for the normal-render reapply path and the hold-expiry cleanup path.
  - The remaining verification step is now an in-game live trace for the exact event or timer that still neutralizes the background in the user's setup.

- **Documentation / release sync:**
  - Bumped `README.md`, `ARCHITECTURE.md`, `USECASES.md`, and `isiLive.toc` to `0.9.148`.
  - Updated the local validator baseline to `527` scenarios / tests.

## 2026-04-11 - Version 0.9.147 (feature)

- **LFG dungeon detection:**
  - New module `game/isiLive_lfg_detect.lua` detects which dungeon the player received an LFG group invite for, or which dungeon they queued for via their own active LFG listing.
  - Detection uses a static `activityID → mapID` map as the primary (fast) path, with API name lookup and locale-aware keyword matching as fallbacks.
  - Keyword matching supports both `enUS` and `deDE` dungeon names (including umlauts and typographic apostrophes); other locales fall through to the API name path.
  - Detected dungeon is announced in chat as `[isiLive] Invite erkannt: <name>` or `[isiLive] Queue erkannt: <name>`.
  - The corresponding portal icon in the Teleport Grid is highlighted (active border + glow animation) as long as the queue or accepted invite is active.
  - Highlight clears automatically when: the player cancels the queue, leaves the group before the key starts, the key starts (`CHALLENGE_MODE_START`), or the group dissolves (`GROUP_ROSTER_UPDATE` with `not IsInGroup()`).
  - A 5-second polling ticker (`C_Timer.NewTicker`) re-checks the active LFG listing in case events are missed.
  - Public accessor: `addonTable.LFGDetect.GetDetectedMapID()`.
  - `UpdateMPlusTeleportButton` falls back to `LFGDetect` when no active teleport spell is resolved.

- **Demo mode toggle (CTRL-ALT-F9) improved:**
  - `CTRL-ALT-F9` now toggles the demo mode on/off **without closing the visualisation** when deactivating.
  - Deactivating restores the real group state via a full roster update (`triggerGroupRosterUpdate`), including correct solo-player entry reconstruction.
  - Previously the hotkey called `ToggleStandardTestMode` which closed the frame on exit; it now calls the dedicated `ToggleDemoMode`.

- **Share Keys fallback hardened:**
  - The local Share Keys announcement keeps the keystone message clickable even when the owned-link API is unavailable.
  - The fallback still posts the dungeon short code and level, but now wraps it in a deterministic keystone hyperlink instead of plain text.

- **Leader notification suppressed on own group creation:**
  - When the local player creates a group and is immediately the leader, the "you are now leader" notification and sound no longer fire.
  - Fix: `wasGroupLeader` is pre-synced to `true` in `HandleGroupRosterUpdate` when `joinedNow == true` and `unitIsGroupLeader("player") == true`, so `PARTY_LEADER_CHANGED` sees no state change.

- **Title bar updated:**
  - `TITLE_HINT` text changed from locale-specific "Open/Close CTRL-F9" strings to the uniform label `BETA` across all 8 supported languages.
  - All three title elements (`isiLive`, version, badge) now share the same font size (14) and a common Y anchor for pixel-accurate horizontal alignment.
  - BETA badge colour: green (`0.45, 0.85, 0.45`).

- **LSP setup:**
  - `.vscode/settings.json` `Lua.workspace.library` path changed from `~\\.vscode\\…` to the fully expanded absolute path so lua-language-server resolves the `ketho.wow-api` annotations correctly on Windows.

## 2026-04-11 - Version 0.9.146 (patch)

- ESC-menu shortcut buttons: icons upgraded from static `Interface\\Icons\\*` textures to MicroMenu atlas entries (`UI-HUD-MicroMenu-*-Up`) for Professions, Talents, Achievements, Quests, Dungeons, Journal, Collections, Guild, and Housing. The Spellbook, ReloadUI, Hearthstone, and Arkantine buttons retain their existing icon paths (no matching MicroMenu atlas).
- Fixed label overlap with icon on buttons that use an atlas icon: `textOffsetX` now accounts for `iconAtlas` in addition to `iconPath`.
- `CreatePanelUIButton` accepts an `iconAtlas` parameter; when set, `SetAtlas` is used instead of `SetTexture`/`SetTexCoord`.

## 2026-04-11 - Version 0.9.145 (patch)

- Documentation sync:
  - Bumped `README.md`, `ARCHITECTURE.md`, `USECASES.md`, `RELEASE.md`, and `isiLive.toc` to `0.9.145`.
  - Updated the local validator baseline to `525` scenarios / tests.

## 2026-04-10 - Version 0.9.144 (patch)

- Roster layout rollback:
  - Reverted the temporary RIO-width experiment and restored the compact roster column budget.
  - Restored the M2 frame width and the associated layout/test expectations to the previous stable state.
- Docs / release baseline:
  - Synced `README.md`, `ARCHITECTURE.md`, `USECASES.md`, and `isiLive.toc` to `0.9.144`.

## 2026-04-10 - Version 0.9.143 (patch)

- Kick event routing fix:
  - The kick tracker no longer registers a separate kick frame during addon initialization.
  - `UNIT_SPELLCAST_SUCCEEDED`, `UNIT_PET`, `SPELLS_CHANGED`, and `COMBAT_LOG_EVENT_UNFILTERED` now flow through the main event dispatcher, which avoids the protected `Frame:RegisterEvent()` call that could fire in tainted init contexts.
  - Updated the affected deterministic factory and architecture regressions to match the main-dispatcher wiring.
- Docs / release baseline:
  - Synced `README.md`, `ARCHITECTURE.md`, `USECASES.md`, `RULES_LOGIC.md`, and `isiLive.toc` to `0.9.143`.

## 2026-04-10 - Version 0.9.142 (feature)

- Kick column icon display:
  - Kick status is now shown as a coloured icon (green = ready, red = on cooldown, grey = unknown/no kick) instead of text.
  - When on cooldown, the icon darkens and a countdown number overlays it (no "s" suffix, font size 8).
  - Icons anchor right-aligned under the Kick header. Multi-slot ready for future dual-kick specs.
- Counterspell base cooldown corrected from 25s to 20s in `SPEC_DATA`.
- Title bar: removed "Öffnen/Schliessen STRG-F9" hint text.
- Test mode auto-exit: closing the UI via X-button or CTRL-F9 now automatically exits test mode if active.
- Settings persistence: background opacity and UI scale are now written to `IsiLiveDB` on first load with their defaults; subsequent sessions preserve user-changed values instead of always resetting.

## 2026-04-10 - Version 0.9.141 (patch)

- Rule 41 / UnitExists guard fixes:
  - Added explicit `UnitExists("player")` guards before runtime `GetBestMapForUnit("player")` lookups in highlight, hidden sync, tracked M0 runtime handling, factory target-dungeon checks, and frame-bridge player-map helpers.
  - Reworked the factory kick-sync path to reuse the last verified local player identity so stale local kick cache entries are still cleared fail-closed during transient `UnitExists` races.
  - Added deterministic call-site coverage for the guarded player-map lookup paths and cached kick-identity cleanup.
- Kick tracker combat-log failure diagnostics:
  - `KickTracker` now records deterministic failed-kick signals from matching combat-log miss events for the currently tracked interrupt without changing the live cooldown contract.
  - The factory kick tracker forwards `COMBAT_LOG_EVENT_UNFILTERED` into the kick tracker so the local failure signal can be observed deterministically in tests.
  - Added deterministic regressions for the local failed-kick signal and the factory combat-log forwarding path.
- Slot-based kick display:
  - The kick tracker now exposes slot lists for resolved interrupts, the sync layer transports the slot data alongside the legacy kick fields, and the roster Kick column renders green/red point markers instead of the previous `ready` text fallback.
  - Added deterministic regressions for slot transport, slot application, and the roster point rendering path.
- Docs / release baseline:
  - Synced `README.md`, `ARCHITECTURE.md`, `USECASES.md`, `RULES_LOGIC.md`, `WARTUNG.md`, `RELEASE.md`, and `isiLive.toc` to `0.9.141`.

## 2026-04-10 - Version 0.9.140 (feature)

- M+ Killtracker row added to M2 layout:
  - New bottom row in M2 shows Enemy Forces percentage as a progress bar with colour coding: green (<80%), yellow (<95%), red (≥95%).
  - Displays `--,--` when no key is active; switches to `00,00%` immediately on key start and resets to `--,--` on key end or reset.
  - Pull prediction: during active combat the row shows the forces delta gained in the current pull as `+X,XX%` text and as a second light-blue bar segment appended to the right of the main fill bar.
  - Pull prediction uses a scenario-quantity delta approach (combat-start snapshot vs. current quantity) — the only method that works in Midnight M+ where all NPC identification APIs return secret values inside the instance.
  - Demo mode shows `47,34%` with `+3,21%` pull preview.
  - Row label: `M+Killtracker` (grey, left-anchored).
  - Data source: `game/isiLive_killtrack.lua` — reads `C_ScenarioInfo.GetScenarioStepInfo()` weighted-progress criterion; reacts to `CHALLENGE_MODE_START/COMPLETED/RESET`, `SCENARIO_CRITERIA_UPDATE`, `PLAYER_ENTERING_WORLD`, `PLAYER_REGEN_DISABLED/ENABLED`.
  - M2 frame height extended by 28px to accommodate the new row; management, teleport and CD-tracker rows each shifted up by 28px.
- Docs / release baseline:
  - Synced `README.md`, `ARCHITECTURE.md`, `USECASES.md`, and `isiLive.toc` to `0.9.140`.

## 2026-04-10 - Version 0.9.139 (patch)

- Title bar UI polish:
  - Added `BETA` label in M2 title bar (after version string, hover tooltip shows beta notice + GitHub issues URL).
  - `BETA` label is only visible in M2 layout; hidden in H and V.
  - Settings panel: added Beta section at the top (above language selector) with notice text and copyable GitHub issues URL.
  - Removed decorative grip lines from the drag handle in the title bar.
  - Adjusted title bar font sizes: version string 12px, BETA label 12px, open/close hint 10px.
  - Fixed anchor chain so version, BETA, and open/close hint are all vertically aligned.
- Docs / release baseline:
  - Synced `README.md`, `ARCHITECTURE.md`, `USECASES.md`, and `isiLive.toc` to `0.9.139`.

## 2026-04-09 - Version 0.9.138 (patch)

- LibKeystone compatibility:
  - `isiLive` now registers and handles the `LibKS` addon-message prefix in party groups.
  - Manual `Re-Sync` now also sends one `LibKS` party request so compatible non-`isiLive` addons can answer with `level,mapID,rio`.
  - Incoming `LibKS` payloads now backfill party-member `Key` and `RIO`, while preserving richer `isiLive` `Spec`/`iLvl` data when it already exists.
  - Hidden clients now answer incoming `LibKS` requests with one party payload containing the local key and rating.
  - Added deterministic coverage for `LibKS` request/reply handling, hidden-party replies, request throttling, and KeySync delegation.
- Docs / release baseline:
  - Synced `README.md`, `ARCHITECTURE.md`, `USECASES.md`, and `isiLive.toc` to `0.9.138`.
  - Validator baseline is now documented as 522 scenarios across 38 modules, with 522 deterministic tests indexed by the rule validators.

## 2026-04-09 - Version 0.9.137 (patch)

- KICK / No-Guess hardening:
  - `Sync.SendKick()` and `Sync.SetPlayerKickInfo()` now reject malformed or incomplete KICK inputs instead of inventing a kick state.
  - `ProcessAddonMessage()` now discards malformed `KICK` payloads fail-closed, so no guess is written into the roster cache from broken peer data.
  - `ProcessAddonMessage()` now also treats changing remaining kick cooldown as a visible sync update, so the roster countdown keeps moving when the sender refreshes the payload.
  - Added deterministic regressions for malformed outbound `SendKick` inputs, malformed inbound `KICK` payloads, and remaining-cooldown updates; the kick test suite now covers the explicit no-guess contract and the countdown refresh path.
- Docs / release baseline:
  - Synced `README.md`, `ARCHITECTURE.md`, `USECASES.md`, `RULES.md`, `WARTUNG.md`, `RELEASE.md`, and `isiLive.toc` to `0.9.137`.
  - Validator baseline is now documented as 516 scenarios across 38 modules, with 516 deterministic tests indexed by the rule validators.

## 2026-04-09 - Version 0.9.134 (patch)

- Hidden / raid runtime hardening:
  - The dedicated kick tracker now does nothing in raid, including its separate cast frame and ticker paths, and resumes cleanly only after raid exit.
  - Explicit `HELLO`/`REQSYNC` kick replies now use the same guarded recovery path, and post-raid kick recovery may resume only from exact state: observed kick casts, exact Blizzard cooldown data, or an exact `no kick` resolution, never from guesses.
  - If post-raid kick recovery still cannot verify an exact available-kick state, the kick column stays unresolved and no kick sync packet is sent until exact cooldown data or a new observed kick cast becomes available; unrelated casts do not lift suppression.
  - Kick availability is now modeled with an explicit split between `unresolved` and exact `no kick`; `spellID == nil` alone no longer collapses those states.
  - Unreadable or protected Blizzard cooldown payloads no longer clear an already observed local kick cooldown; exact recovery fails closed instead of guessing `ready`.
  - Successful post-raid kick recovery now emits exactly one recovered kick sync packet and one visible kick-column refresh, even when the cooldown refresh path reports a state change during recovery.
  - `Sync.ClearKnownUsers()` now also resets the `KICK` dedup/rate-limit state so the next identical local kick payload is not suppressed by stale sender state.
  - Deferred post-run refresh state now lives in `RuntimeState` instead of ad-hoc handler context fields, and runtime resume on `GROUP_ROSTER_UPDATE` reads that state through the shared RuntimeState API.
  - Hidden mode no longer keeps the utility/CD polling ticker alive; explicit event-driven tracker refresh still runs, and reopening the UI marks the utility tracker dirty so the first visible roster render performs exactly one fresh utility rescan.
  - Delayed post-run refresh no longer leaks through raid hard-off; if the callback becomes due in raid, it is deferred and resumes on the next roster update after raid exit.
- Docs / release baseline:
  - Synced `README.md`, `ARCHITECTURE.md`, `USECASES.md`, `RULES.md`, `WARTUNG.md`, `RELEASE.md`, and `isiLive.toc` to `0.9.134`.
  - Validator baseline is now documented as 510 scenarios across 37 modules, with 510 deterministic tests indexed by the rule validators.

## 2026-04-08 - Version 0.9.133 (fix)

- Fix client version tooltip not showing for peers on older addon versions:
  - `sendIsiLiveHello` was missing from `BuildEventHandlersBaseConfig` — addon crashed on startup.
  - `sendIsiLiveHello` also missing from `BuildEventHandlersDepsFromContext` (secondary path).
  - Both HELLO and REQSYNC response paths now send a forced HELLO before the full state snapshot, so peers on older versions reliably receive and store the version info.
- Fix post-challenge full sync (key, stats, DPS, loc):
  - `NotifyPostChallengeSync()` flag consumed in `HandleOwnedKeyRefresh` — fires forced snapshot when `BAG_UPDATE_DELAYED`/`CHALLENGE_MODE_MAPS_UPDATE` arrives after key end.
  - When key level changed: forced snapshot instead of background snapshot.
  - When key unchanged but post-challenge flag set: forced snapshot.

## 2026-04-08 - Version 0.9.132 (fix)

- Key sync after Mythic+ run:
  - Full force-sync (key, stats, DPS, location) to all peers after a run ends, not just key.
  - `NotifyPostChallengeSync()` flag set on `CHALLENGE_MODE_COMPLETED`; consumed in `HandleOwnedKeyRefresh` when `BAG_UPDATE_DELAYED` / `CHALLENGE_MODE_MAPS_UPDATE` fires and WoW has updated the key.
  - Previously force-sync fired on `CHALLENGE_MODE_COMPLETED` before the API had the new key level; now always fires at the correct time regardless of key level change.

## 2026-04-08 - Version 0.9.131 (patch)

- Restructure: all Lua source files moved into subdirectories (`core/`, `ui/`, `logic/`, `locale/`, `factory/`, `game/`); doc files moved to `docs/`.
- UI: Center notice text vertically centered in frame (`TOPLEFT`→`BOTTOMRIGHT` anchor so `JustifyV MIDDLE` is effective).
- `sync_release_baseline.ps1` updated to new doc and locale paths.

## 2026-04-08 - Version 0.9.130 (patch)

- Minimap button:
  - Always created hidden at file-load time; shown/hidden on `PLAYER_LOGIN` once `IsiLiveDB` is available (mimics LibDBIcon pattern).
  - Right-click opens the Blizzard settings panel for isiLive directly.
- Roster panel: title bar now reads version from `C_AddOns.GetAddOnMetadata` at runtime instead of a hardcoded string.

## 2026-04-08 - Version 0.9.129 (feature)

- Multilanguage support:
  - Added French (`frFR`), Spanish (`esES`), and Portuguese (`ptBR`) UI languages.
  - Introduced `isiLive_languages.lua` as single source of truth for all supported languages (`Languages.SUPPORTED`, `Languages.ResolveTag`, `Languages.IsSupported`).
  - Language selector in Settings now built dynamically from `Languages.SUPPORTED` — no hardcoded button list.
  - `ResolveLocaleTag` in `isiLive_locale.lua` and `NormalizeLocaleTag` in `isiLive_season_data.lua` delegate to `Languages.ResolveTag`.
  - Button text clamping added to `SetFlatButtonText` and language selector buttons to prevent overflow on 120×24px action buttons.
  - All BTN_* keys for new languages kept ≤14 characters.
- Docs:
  - Added "Adding a new UI language" and "Button text length" sections to `CLAUDE.md`.
  - Synced `README.md`, `ARCHITECTURE.md`, `USECASES.md`, and `isiLive.toc` to `0.9.129`.

## 2026-04-02 - Version 0.9.128 (patch)

- Docs / release baseline:
  - Synced `README.md`, `ARCHITECTURE.md`, `USECASES.md`, and `isiLive.toc` to `0.9.128`.
  - Updated the runtime-visible addon title string to `v0.9.128`.

## 2026-04-02 - Version 0.9.127 (patch)

- Keystone chat output:
  - Share-Keys now builds a deterministic keystone hyperlink from the owned map ID and level instead of forwarding a foreign item hyperlink.
  - Tooltip helper fallbacks now accept varargs so the roster panel stays diagnostics-clean while still tolerating missing internal helpers.
- Docs / release baseline:
  - Synced `README.md`, `ARCHITECTURE.md`, `USECASES.md`, and `isiLive.toc` to `0.9.127`.

## 2026-04-02 - Tooling: local CI wrappers

- Added `tools/check.ps1`, `tools/check.cmd`, and `tools/run_local_ci.ps1` as short local entrypoints for the full CI preflight.
- Added a repo-local `tools/luacheck.cmd` shim so Windows uses `lua` to launch the LuaRocks `luacheck` script and no longer opens the "choose an app" dialog.
- Updated the local CI documentation to point at the wrapper chain instead of the bare LuaRocks script.

## 2026-04-02 - Version 0.9.126 (patch)

- Release packaging:
  - Excluded the `.claude/` helper directory from the CurseForge package.

## 2026-04-02 - Version 0.9.125 (patch)

- Release packaging:
  - Replaced the packaged changelog with a tiny release-note stub that links back to the repository changelog.
  - Excluded the full `CHANGELOG.md` from the CurseForge package to save zip size.

## 2026-04-02 - Version 0.9.124 (patch)

- Docs / release baseline:
  - Reduced the normal `/isilive` help output to `testall`, `log`, `start`, and `stop`.
  - Raised README, architecture, use-case, and TOC baselines to `0.9.124`.
  - Updated the UI title string to `v0.9.124` through the release baseline sync.

## 2026-04-01 - Version 0.9.122 (patch)

- Docs / release baseline:
  - Raised README, architecture, use-case, and TOC baselines to `0.9.122`.
  - Documented the raid hard-off behavior: raid-size groups now hide the UI and suppress background processing instead of forcing H mode.

## 2026-03-31 - Version 0.9.120 (patch)

- Slash command: `/isk` renamed to `/il` (shorter alias for `/isilive`).
- New command `/il reset` (also `/isilive reset`): wipes `IsiLiveDB` and triggers `ReloadUI()` to restore all settings to their defaults.
- Settings panel: new "Reset All Settings" button at the bottom of the settings page, equivalent to `/il reset`.

## 2026-03-30 - Version 0.9.119 (patch)

- Keys teilen: fix clients not posting their keystone to party chat — `ctx.getRoster` was nil (typo: should be `ctx.GetRoster`), causing `sendOwnKeystoneToChat` to silently return early on all remote clients.

## 2026-03-30 - Version 0.9.118 (patch)

- Kick-state sync: add 15s heartbeat broadcast so peers that reload or join late always see up-to-date interrupt ready/cooldown state instead of a stale dash.
- Settings: option-selector labels for "Default Layout on Open" and "Raid Transition Behavior" now render above the buttons to prevent overlap with long label text.
- Combat fade (M/M2): fix ticker conflict — existing fade animation is now cancelled before starting a new one; extract shared `ApplyCombatFade` helper; use RI layout constants instead of magic strings.
- Kick tracker: cache `ScanOwnTalents` result via `talentScanDirty` flag; invalidated on spec/talent change — avoids full talent-tree traversal on every cast.
- UI close button: `frame:Hide()` is now called directly (combat-safe) so the frame closes immediately even during combat.
- Sound: all sounds now routed through `SoundUtils` module on the SFX channel with 1s spam protection.
- Group join sound: new `onMemberJoinedGroup` callback detects when other players join the group (not just the local player).
- Column guides: wired `showRosterColumnGuides` into `CreateRosterPanelController`.

## 2026-03-30 - Version 0.9.117 (patch)

- `canRespondToRefreshRequest` gate simplified: the active-M+ (`GetActiveChallengeMapID`) block has been removed, so hidden clients now answer incoming `REQSYNC` refresh requests even during an active Mythic+ run; only stopped and paused states still suppress replies.
- Share-Keys remote cooldown propagation:
  - When a client receives an incoming `SHAREKEYS` sync message it now calls `TriggerRemoteCooldown` on the local `Share Keys` button, locking the button for 30 s on all peer clients as well as on the initiating client (guarded: an already-running local cooldown is not reset).
  - `TriggerShareKeysCooldown` accessor plumbed from `RosterPanel` controller through `isiLive_factory_controllers.lua` and `isiLive_controller_wiring.lua` into the runtime event handler.
  - `sendOwnKickState` is now called alongside `sendOwnTargetSnapshot` when answering a refresh request, so responding clients include up-to-date kick state in their reply.
- Kick-tracker no-interrupt state transport:
  - `SendKick` encodes a no-interrupt state as `onCooldown = -1` in the `KICK:` payload when `hasKick` is `false`, letting peers distinguish "no interrupt available for this spec" from "kick is on cooldown".
  - `ProcessAddonMessage` parses the `-1` sentinel and stores `hasKick = false` via `SetPlayerKickInfo`.
  - `ApplyKnownKeyToRosterEntry` in `isiLive_keysync.lua` propagates `syncHasKick` to roster entries; `SetKickCellText` in the roster panel renders `-` when `syncHasKick == false`.
- Kick-tracker pet-interrupt support:
  - Warlock Affliction and Destruction now track the Felguard/Felhunter `Spell Lock` (ID 19647, 24 s) via pet-cast unit tracking.
  - Warlock Demonology prefers `Axe Toss` (ID 89766, 30 s) when available; falls back to `Spell Lock`; shows `-` in the `Kick` column when neither pet interrupt is castable (`requireAvailability`).
  - Demon Hunter Devourer spec (ID 1480) added to the interrupt table (Disrupt, 15 s).
  - `UNIT_SPELLCAST_SUCCEEDED` now monitors the `pet` unit in addition to `player`; `UNIT_PET` triggers a spec-recheck when the active pet changes.
  - `SyncOwnKickState` extracted to a shared helper, unifying cooldown-change callbacks, spec-change broadcasts, and ticker-driven state updates.
- Background sync improvements:
  - `DPS` is now always included in background snapshots regardless of frame visibility, so peers always receive the latest run stats even while the main window is hidden.
  - `TARGET` snapshots now auto-set `allowHidden = true` whenever the local frame is not visible, ensuring hidden-client target data reaches peers on refresh.
- RULES_LOGIC.md: rule 28 updated (active-M+ block removed, all sync buckets listed explicitly), rule 53 added (Share-Keys spam guard propagation).
- Tests: validator baseline raised from 460 to 470 scenarios; new coverage added for pet-interrupt specs, no-interrupt state transport, Share-Keys remote lockdown, and SHAREKEYS hidden-client handling.
- Fix: luacheck unused-parameter warning in `onCooldownChanged` callback (`cooldownRemain` → `_cooldownRemain`) after kick-state sync was moved into `SyncOwnKickState`.

## 2026-03-29 - Version 0.9.116 (patch)

- Kick sync reliability overhaul:
  - Ticker interval reduced from 1.0 s to 0.5 s for more responsive cooldown updates.
  - Receive timestamp stored alongside `cooldownRemain` so the roster `Kick` column counts down smoothly between sync packets via linear interpolation.
  - After a cooldown expires the ticker continues broadcasting the ready state for 3 extra seconds to guarantee delivery to all peers.
  - `KICK:0:0` payload is now sent as `math.ceil` to prevent a premature ready frame at sub-second remain.
  - Rate limit tightened to 1 s minimum between identical payloads.
  - Roster `Kick` column shows `-` instead of `0s` while the final packet is still in-flight, eliminating false red flicker.
- Hello / full-state sync on peer discovery:
  - When a new peer sends a HELLO the addon now immediately replies with the complete local state: key, stats, DPS, location, and kick (ready/cooldown), so the first roster render for that peer is already complete.
- Kick tracker correctness:
  - Changing specialization to a class with a different interrupt spell now immediately clears the old cooldown rather than leaving a stale timer running.
  - `ClearKnownUsers` now also clears the kick-info cache (`kickInfoByPlayerKey`), preventing ghost kick data after group resets.
- Docs / release baseline:
  - Synced `README.md`, `USECASES.md`, `ARCHITECTURE.md`, `RELEASE.md`, `CHANGELOG.md`, `isiLive_texts.lua`, and `isiLive.toc` to `0.9.116`.
  - Validator baseline remains `460` scenarios across `34` modules and `460` rule-indexed deterministic tests.
- Release metadata:
  - Bumped TOC/version strings to `0.9.116`.

## 2026-03-29 - Version 0.9.115 (patch)

- Distributed `Share Keys` flow:
  - `Share Keys` now posts the local player's own keystone to party chat immediately and then broadcasts a lightweight `SHAREKEYS` addon message so other `isiLive` users can post their own key line as well.
  - The `Share Keys` button now shows a visible `30s` cooldown in its label while blocked, matching the chat anti-spam guard.
  - Owned-keystone fallback links now include the dungeon name instead of a bare `[Keystone]` placeholder when the native Blizzard link is unavailable or incomplete.
- Sync / roster data polish:
  - Sync now clears stale kick-cache data on full known-user resets and stores receive timestamps so remote interrupt cooldowns in the roster `Kick` column can count down smoothly between sync updates.
  - Sync tooltips now show `Client version: x.y.z` / `Client-Version: x.y.z` without the protocol suffix.
- Combat utility / runtime fixes:
  - The Mythic+ timer now reads the correct elapsed-time return value from `GetWorldElapsedTime`, so the live `+3/+2/+1` cutoffs advance correctly during active keys.
  - Interrupt tracking now clears the old watched cooldown immediately when the player changes specialization to a different interrupt spell.
  - Kept ready-check finish behavior aligned with the active ready-check rule contract: the live ready-check state still ends immediately on finish, while explicit declines continue to linger for 20 seconds.
- Tests / docs / release baseline:
  - Added deterministic coverage for `SHAREKEYS` sync handling, hidden-mode key-share replies, the updated share-keys button wiring, and the simplified client-version tooltip text.
  - Synced `README.md`, `USECASES.md`, `ARCHITECTURE.md`, `RELEASE.md`, `CHANGELOG.md`, and `isiLive.toc` to `0.9.115`.
  - Validator baseline is now `460` scenarios across `34` modules and `460` rule-indexed deterministic tests.
- Release metadata:
  - Bumped TOC/version strings to `0.9.115`.

## 2026-03-29 - Version 0.9.114 (patch)

- Audio settings and group lifecycle:
  - Added localized Blizzard Settings toggles for `Sound: Lead Transfer` and `Sound: Group Join`.
  - Leader-transfer promotions still show the visible notice, but the sound can now be disabled explicitly; the new group-join sound hook stays off by default until the user enables it.
- Kick tracker refresh path:
  - Kick cooldown updates now refresh only the dedicated roster `Kick` column instead of forcing a full UI rerender.
  - Kick spell resolution now also refreshes on `PLAYER_SPECIALIZATION_CHANGED`, so spec swaps update the tracked interrupt immediately.
- Tests / docs / release baseline:
  - Added deterministic coverage for the new sound toggles, the optional first-group-join callback, the disabled leader-sound path, and the lightweight kick-refresh wiring.
  - Synced `README.md`, `USECASES.md`, `ARCHITECTURE.md`, `RELEASE.md`, `CHANGELOG.md`, and `isiLive.toc` to `0.9.114`.
  - Validator baseline is now `457` scenarios across `34` modules and `457` rule-indexed deterministic tests.
- Release metadata:
  - Bumped TOC/version strings to `0.9.114`.

## 2026-03-29 - Version 0.9.113 (patch)

- Combat utility refresh:
  - The one-second utility ticker now triggers a full UI rerender while an active Mythic+ timer is running, so the `+3/+2/+1` cutoff row keeps counting down live during a key.
- Metrics / release gate alignment:
  - Synced the Lua metrics hard limits to `3200` file lines and `420` function lines across `tools/lua_metrics_check.lua`, `.github/workflows/lua-check.yml`, and `tools/validate_ci_local.ps1` so local preflight and GitHub Actions enforce the same baseline.
  - Updated release and maintenance docs to use the current metrics baseline and local preflight expectations.
- Docs / release baseline:
  - Synced `README.md`, `USECASES.md`, `ARCHITECTURE.md`, `RELEASE.md`, `WARTUNG.md`, `CHANGELOG.md`, and `isiLive.toc` to `0.9.113`.
  - Validator baseline is now `452` scenarios across `34` modules and `452` rule-indexed deterministic tests.
- Release metadata:
  - Bumped TOC/version strings to `0.9.113`.

## 2026-03-29 - Version 0.9.112 (patch)

- Re-Sync flow:
  - Renamed the user-facing `Refresh` button to `Re-Sync` in both locales.
  - Increased the manual re-sync guard to `10` seconds and show the remaining cooldown directly on the button label while the action is blocked.
  - Real first-group joins now delay the forced `REQSYNC` trigger by `0.5s` so group state has settled before addon sync messages are sent.
- Main window title bar:
  - Removed the extra separator dot between title and version/hotkey hint; the compact header now renders as one cleaner title block.
  - Updated the compact-layout test/layout wiring so the simplified title head stays hidden correctly in `H` mode.
- Docs / release baseline:
  - Synced `README.md`, `USECASES.md`, `ARCHITECTURE.md`, `RELEASE.md`, `CHANGELOG.md`, and `isiLive.toc` to `0.9.112`.
  - Validator baseline remains `451` scenarios across `34` modules and `451` rule-indexed deterministic tests.
- Release metadata:
  - Bumped TOC/version strings to `0.9.112`.

## 2026-03-29 - Version 0.9.111 (patch)

- Main window title bar:
  - Added a small localized hotkey hint next to the version label: `Open/Close CTRL-F9` / `Öffnen/Schliessen STRG-F9`.
  - Compact `H` and `V` layouts now hide the title/version block completely, including the drag-grip lines, while drag-to-move still stays available.
- Roster combat info:
  - Added the `Kick` roster column with synced interrupt cooldown state (`ready` / remaining seconds) for party members.
  - Expanded the bottom combat utility area to include Mythic+ timer cutoffs (`+3/+2/+1`) and death-penalty tracking alongside `BRes` and lust timers.
  - Added the new runtime modules `isiLive_kick_tracker.lua` and `isiLive_mplus_timer.lua` and wired them into controller/bootstrap flow.
- Tooltip / demo / sync polish:
  - Peer version tooltip formatting now stays stable with protocol suffixes (`pN`) across locale overrides.
  - Demo full-preview rebuild tests now resolve ghost rows from the generated dataset instead of depending on a stale hardcoded dummy identity.
- Docs / release baseline:
  - Synced `README.md`, `USECASES.md`, `ARCHITECTURE.md`, `RELEASE.md`, `CHANGELOG.md`, and `isiLive.toc` to `0.9.111`.
  - Updated the documented validator counts to `451` scenarios across `34` modules and `451` rule-indexed deterministic tests.
- Release metadata:
  - Bumped TOC/version strings to `0.9.111`.

## 2026-03-29 - Version 0.9.110 (patch)

- Active Midnight Season 1 dungeon labels:
  - Corrected the localized `deDE` dungeon names to `Windlaeuferturm`, `Terrasse der Magister`, `Nexuspunkt Xenas`, `Maisarakavernen`, `Akademie von Algeth'ar`, `Grube von Saron`, `Sitz des Triumvirats`, and `Die Himmelsnadel`.
  - Unified the active Midnight Season 1 short codes for both `enUS` and `deDE` to `WRS / MT / NPX / MC / AA / POS / SOT / SR`.
  - Added deterministic coverage for the active-season short code baseline and the corrected `deDE` full-name baseline.
- Docs / release baseline:
  - Synced `README.md`, `USECASES.md`, `ARCHITECTURE.md`, `CHANGELOG.md`, and `isiLive.toc` to `0.9.110`.
  - Updated the documented validator counts to `450` scenarios across `34` modules and `450` rule-indexed deterministic tests.
- Release metadata:
  - Bumped TOC version to `0.9.110`.

## 2026-03-28 - Version 0.9.109 (patch)

- Code cleanup / dead code removal:
  - `SendRefreshResponse` now delegates to `SendOwnStateSnapshot` instead of duplicating the send logic.
  - `READY_CHECK_CONFIRM` no longer triggers a UI refresh when the `unit` parameter is invalid.
  - Removed `Teleport.ResetActivityCaches()` (unused export).
  - Removed 9 Season 3 legacy wrapper functions from `isiLive_teleport.lua` and their associated tests.
  - Removed `SeasonData.IsSeasonReady()` (unused export, superseded by `GetSeasonReadiness`).
- Docs / release baseline:
  - Synced `README.md`, `USECASES.md`, `ARCHITECTURE.md`, `RELEASE.md`, `CHANGELOG.md`, and `isiLive.toc` to `0.9.109`.
- Release metadata:
  - Bumped TOC version to `0.9.109`.

## 2026-03-28 - Version 0.9.108 (patch)

- Roster ghost ordering:
  - Persisted ghost rows no longer consume visible roster slots ahead of active group members.
  - The visible 5-row roster budget now guarantees active entries render before ghosts, so stale leavers cannot hide a current party member.
  - Added deterministic panel coverage for the exact `4 active + 2 ghosts` clipping case.
- Docs / release baseline:
  - Synced `README.md`, `USECASES.md`, `ARCHITECTURE.md`, `RELEASE.md`, `CHANGELOG.md`, and `isiLive.toc` to `0.9.108`.
  - Documented the new active-before-ghost roster guarantee across user docs and architecture docs.
  - Updated the documented validator counts to `449` scenarios across `34` modules and `449` rule-indexed deterministic tests.
- Release metadata:
  - Bumped TOC version to `0.9.108`.

## 2026-03-27 - Version 0.9.107 (patch)

- Ready-check UX:
  - Explicit `notready` answers now stay red for 20 seconds after `READY_CHECK_FINISHED` instead of clearing immediately.
  - Added deterministic coverage for runtime-state declined-hold tracking, event-handler timer cleanup, roster rendering during the hold window, and the dedicated post-hold refresh path.
- Docs / release baseline:
  - Synced `README.md`, `USECASES.md`, `ARCHITECTURE.md`, `RELEASE.md`, `CHANGELOG.md`, and `isiLive.toc` to `0.9.107`.
  - Corrected ready-check documentation from text-color wording to row-background + waiting sandglass + 20-second declined hold behavior.
  - Removed stale `Deaths`/`Kicks` references from architecture docs and updated documented validator counts to `448` scenarios across `34` modules and `448` rule-indexed deterministic tests.
- Release metadata:
  - Bumped TOC version to `0.9.107`.

## 2026-03-27 - Version 0.9.106 (patch)

- Group join / sync refresh:
  - A real first group join now forces the local `HELLO` + `KEY`/`STATS`/`DPS`/`LOC` snapshot and broadcasts `REQSYNC`, so roster data refreshes immediately after an invite accept instead of waiting for a manual `Refresh` click.
  - Added deterministic coverage that the first join path bypasses normal sync cooldowns and still avoids recursive auto-open side effects.
- Run snapshot / roster sync cleanup:
  - Removed unreliable `Deaths` and `Kicks` collection, transport, roster fallback, and tooltip rendering; last-run sync is now explicitly `DPS`-only.
  - Updated rules, docs, and deterministic coverage to reflect the verified `DPS`-only contract.
- Center notice / dungeon detection:
  - Removed dungeon/activity detection context from the runtime center-notice path; the visible right-side teleport grid remains unchanged.
  - Hardened the rules validator so multiline `test(` declarations remain indexable after `stylua` formatting.
- Esc menu taint hardening:
  - Reworked the optional `Esc` tooling and travel strips so both panels are mounted directly as prebuilt `GameMenuFrame` children instead of relying on a deferred external host-frame show/hide path.
  - During combat lockdown, the strip layout path is now strictly read-only: no `Show`, `Hide`, `ClearAllPoints`, `SetPoint`, `SetSize`, `EnableMouse`, or `SetAlpha` mutations run on the mounted overlays, insecure shortcut clicks no-op in combat, and secure refreshes stay queued until `PLAYER_REGEN_ENABLED`.
  - Added deterministic regression coverage for first combat-open visibility, parent-mounted panel ownership, and the absence of deferred host callbacks.
- Docs / release baseline:
  - Synced `README.md`, `USECASES.md`, `ARCHITECTURE.md`, `RELEASE.md`, `CHANGELOG.md`, and `isiLive.toc` to `0.9.106`.
  - Updated the documented validator counts to `432` scenarios across `34` modules and `428` rule-indexed deterministic tests.
- Release metadata:
  - Bumped TOC version to `0.9.106`.

## 2026-03-26 - Version 0.9.105 (patch)

- Queue join / ready-check / taint hardening:
  - Restored the active queue-join runtime wiring through factory, runtime setup, and controller wiring, and added live-path deterministic coverage for challenge-ignore, pending capture/reset, and grouped announce behavior.
  - Ready-check lifecycle now uses a dedicated roster refresh path instead of the generic full rerender, resetting name/spec colors cleanly after the ready check and avoiding secure role-button rewrites.
  - Combat-safe roster layout updates now skip secure button `SetPoint`/`SetSize` mutations during combat, preventing protected-call taint from M2 rerenders.
- Roster and notice UI polish:
  - Added a real leader marker in the roster: real group leaders render a 16x16 crown, and synced leaders keep the blue heart before the crown.
  - Unified center-notice body typography with the portal navigator via a shared helper, so body font and default color now stay aligned on one implementation path.
- Docs / release baseline:
  - Synced `README.md`, `USECASES.md`, `ARCHITECTURE.md`, `RELEASE.md`, `CHANGELOG.md`, and `isiLive.toc` to `0.9.105`.
  - Updated the documented validator counts to `419` scenarios across `34` modules and `415` rule-indexed deterministic tests.
- Release metadata:
  - Bumped TOC version to `0.9.105`.

## 2026-03-26 - Version 0.9.104 (patch)

- Queue join and ready-check hardening:
  - Documented the active queue-join runtime path as the factory/runtime-wired implementation, with deterministic parity coverage against the legacy `QueueFlow` helper.
  - Documented the dedicated ready-check refresh path that updates roster colors without rerunning the generic full render or rewriting secure role-button attributes.
  - Added deterministic coverage that a ready-check rerender resets spec color correctly after the ready check ends.
- Docs / release baseline:
  - Synced `README.md`, `USECASES.md`, `ARCHITECTURE.md`, `RELEASE.md`, `CHANGELOG.md`, and `isiLive.toc` to `0.9.104`.
  - Updated the documented validator counts to `412` scenarios across `34` modules and `408` rule-indexed deterministic tests.
- Release metadata:
  - Bumped TOC version to `0.9.104`.

## 2026-03-26 - Version 0.9.103 (patch)

- Docs / validation alignment:
  - Synced `README.md`, `USECASES.md`, `ARCHITECTURE.md`, `RELEASE.md`, and `isiLive.toc` to `0.9.103`.
  - Updated the documented deterministic gate counts to `400` scenarios across `34` modules and `396` rule-indexed deterministic tests.
  - Documented the current queue/runtime wiring shape: `isiLive_config_builders.lua` no longer exposes a dedicated queue-flow builder, and queue-target traceability now points at `isiLive_queue.lua` plus `isiLive_event_handlers_queue.lua`.
- Release metadata:
  - Bumped TOC version to `0.9.103`.

## 2026-03-26 - Version 0.9.102 (patch)
- **Removed / Queue Dungeon Detection:**
  - Removed queue dungeon recognition and highlighting entirely. Blizzard no longer delivers usable data via `LFG_LIST_APPLICATION_STATUS_UPDATED` or `LFG_LIST_SEARCH_RESULT_UPDATED` at the time of invite/join, making reliable detection impossible without guessing.
  - Queue join chat output now shows group name only: "Aus Queue beigetreten: [Gruppenname]" — no dungeon name.
  - `ShowQueueJoinPreview`, `setQueueTargetState`, `UpdatePendingQueueJoin`, `BuildAnnouncementSignature` and the full pending-queue-join-info pipeline removed from `isiLive_queue_flow.lua`.
  - `showQueueJoinPreview` removed from test mode controller.
- **Fixed / Hearthstone Button:**
  - Fallback Hearthstone button (item ID 6948) now sets `"item:6948"` (string) instead of `6948` (number) as the secure attribute, fixing the `C_Item.IsEquippableItem` error from Blizzard's SecureTemplates.
- **Changed / Administrative Settings:**
  - Debug section renamed to "Administrativ" (DE) / "Administrative" (EN).
  - Queue Debug Log and Runtime Log are no longer persisted across sessions — they always start disabled on login/reload. Labels updated to indicate this.
  - Settings checkboxes for these options now reflect live controller state instead of SavedVariables.
- **Docs / Release Sync:**
  - Synced `README.md`, `USECASES.md`, `ARCHITECTURE.md`, `RELEASE.md`, and `isiLive.toc` to `0.9.102`.
- **Tests / Validation:**
  - `lua tools/validate_rules_logic.lua` validates `397` deterministic tests indexed.
  - `lua tools/validate_usecases.lua` validates `401` scenarios across `34` modules.

## 2026-03-25 - Version 0.9.101 (patch)
- **Behavior / Main UI Auto-Close Default:**
  - The main UI no longer closes automatically by default on `CHALLENGE_MODE_START` or on the transition from group to solo.
  - Closing stays manual via `X` or `CTRL+F9`.
  - Blizzard Settings now expose `Auto-Close on Key Start / Solo` so the previous automatic close behavior can be re-enabled explicitly.
- **Tests / Validation:**
  - Added Lua regression coverage for the new auto-close option in settings, challenge-start handling, and group-to-solo transition handling.
  - Updated roster-panel deterministic test fixtures to satisfy the new required `setMainFrameWidthSafe` dependency.
  - `lua tools/validate_usecases.lua` validates `402` deterministic tests indexed and `406` scenarios across `34` modules.
- **Docs / Release Baseline:**
  - Bumped TOC version to `0.9.101`.
  - Synced `README.md`, `USECASES.md`, `ARCHITECTURE.md`, `RELEASE.md`, and `isiLive.toc` to `0.9.101`.

## 2026-03-25 - Version 0.9.100 (patch)
- **Bugfix / BRes Charges API Migration:**
  - `CdTracker` now unpacks `C_Spell.GetSpellCharges` struct-return (`currentCharges`, `maxCharges`, `cooldownStartTime`, `cooldownDuration`) instead of the removed multi-return signature, fixing the `attempt to compare table with nil` error.
- **Bugfix / Group Roster Reload Recovery:**
  - `PLAYER_ENTERING_WORLD` now triggers `handleGroupRosterUpdate()` when the player is already in a group after a UI reload, so the roster panel rebuilds immediately instead of staying blank. Previously the hidden-frame event gate blocked `GROUP_ROSTER_UPDATE` inside party instances, and the `PLAYER_ENTERING_WORLD` handler did not re-scan the group.

## 2026-03-24 - Version 0.9.99
- **Docs / Release Baseline:**
  - Bumped TOC version to `0.9.99`.
  - Synced `README.md`, `USECASES.md`, `ARCHITECTURE.md`, `RELEASE.md`, and `isiLive.toc` to `0.9.99`.
  - `lua tools/validate_usecases.lua` now validates `391` deterministic tests indexed and `395` scenarios across `34` modules.
- **Maintenance / Test Gate Cleanup:**
  - Removed dead TeleportUI cosmetic test blocks, deleted empty scenario placeholder modules, and trimmed the scenario manifest to active modules only.
  - Consolidated slash-command coverage into `isilive_test_scenarios_commands.lua`; the separate extended commands scenario file was removed.
  - Removed leftover dead roster-panel tooltip/layout test wiring after the cosmetic test cut.
- **Docs / Behavior Sync:**
  - Synced `README.md`, `USECASES.md`, `ARCHITECTURE.md`, and `RELEASE.md` to the cleaned validator counts and active scenario manifest.
  - Clarified that hidden leader promotions still play the transfer sound while suppressing center notice and chat output.
  - Clarified queue-join docs: there is no separate `Dungeon erkannt` chat line, grouped queue chat is member-only, and hidden `LFG_LIST_*` suppression prevents retroactive queue chat after a missed hidden capture.
- **Code Cleanup:**
  - Removed the duplicate `DidRecordRunSucceed` helper from the challenge and non-challenge run-capture paths.
  - Removed the dead hidden `soundEnabled` setting scaffolding from runtime startup, Blizzard Settings wiring, locale texts, and legacy tests; the unused BL sound file remains in `sounds/` by choice.
- **Bugfix / Bloodlust Zone-Reload Onset Guard:**
  - `UNIT_AURA` now forwards WoW's `isFullUpdate` flag into `CdTracker`, so zone/reload aura restores hydrate the active lust state without replaying the onset callback.
  - `SuppressOnset` now acts as a short 2-second safety net for early ticker scans before the full aura restore arrives.
- **Tests / Validation:**
  - Added regression coverage for `UNIT_AURA.isFullUpdate` forwarding, late full-update aura restores after the suppress window, and reload recovery while lust is already active.

## 2026-03-23 - Version 0.9.98
- **Docs / Release Baseline:**
  - Bumped TOC version to `0.9.98`.
  - Synced `README.md`, `USECASES.md`, `ARCHITECTURE.md`, `RELEASE.md`, and `isiLive.toc` to `0.9.98`.
  - `lua tools/validate_usecases.lua` validates `418` deterministic tests indexed and `425` scenarios across `37` modules.
- **Bugfix / Bloodlust Aura Scan Type Safety:**
  - `CdTracker` now accepts only real numeric aura `spellId` values for the harmful-aura lust lookup.
  - Protected, secret, string, or otherwise non-numeric `spellId` payloads are ignored safely instead of being coerced or used as table keys.
- **Tests:**
  - Added regression coverage so mixed invalid/non-numeric `spellId` payloads still allow a later valid lust aura to be detected.

## 2026-03-23 - Version 0.9.97
- **Docs / Release Baseline:**
  - Bumped TOC version to `0.9.97`.
  - Synced `README.md`, `USECASES.md`, `ARCHITECTURE.md`, `RELEASE.md`, and `isiLive.toc` to `0.9.97`.
  - `lua tools/validate_usecases.lua` validates `417` deterministic tests indexed and `424` scenarios across `37` modules.
- **Bugfix / Bloodlust Aura Scan Normalization:**
  - `CdTracker` now normalizes the lust-debuff `spellId` via `tonumber(...)` before the harmful-aura table lookup, so protected or string-tainted WoW aura payloads no longer break or bypass lust detection.
  - If one aura entry exposes an unusable `spellId`, later valid Bloodlust/Heroism/Time Warp exhaustion auras in the same scan are still detected correctly.
- **Tests:**
  - Existing regression coverage confirms `CdTracker` skips invalid aura `spellId` keys and still finds a later valid lust aura.

## 2026-03-23 - Version 0.9.96
- **Docs / Release Baseline:**
  - Bumped TOC version to `0.9.96`.
  - Synced `README.md`, `USECASES.md`, `ARCHITECTURE.md`, `RELEASE.md`, and `isiLive.toc` to `0.9.96`.
  - `lua tools/validate_usecases.lua` now validates `417` deterministic tests indexed and `424` scenarios across `37` modules.
- **Bugfix / Bloodlust Aura Scan Hardening:**
  - `CdTracker` now protects the lust-debuff `spellId` lookup with `pcall`, so WoW aura payloads with protected/invalid `spellId` values no longer abort the entire harmful-aura scan.
  - If one aura entry exposes an unusable `spellId`, later valid Bloodlust/Heroism/Time Warp exhaustion auras in the same scan still get detected correctly.
- **Tests:**
  - Added regression coverage for invalid/protected aura `spellId` keys so `CdTracker` stays stable and still finds a later valid lust aura.

## 2026-03-23 - Version 0.9.95
- **Docs / Release Baseline:**
  - Bumped TOC version to `0.9.95`.
  - Synced `README.md`, `USECASES.md`, `ARCHITECTURE.md`, `RELEASE.md`, and `isiLive.toc` to `0.9.95`.
  - `lua tools/validate_usecases.lua` now validates `416` deterministic tests indexed and `423` scenarios across `37` modules.
- **Bugfix / Bloodlust Zone Transition:**
  - `CdTracker` now mirrors `BResLustTracker` more closely by scanning player `HARMFUL` auras via `C_UnitAuras.GetAuraDataByIndex(...)` for lust exhaustion debuffs instead of relying on `GetPlayerAuraBySpellID`.
  - `UNIT_SPELLCAST_SUCCEEDED` for the local player is now registered so real lust casts can trigger the onset path immediately without waiting for the next ticker/aura pass.
  - Zone/world transition suppression now treats matching post-transition lust auras as continuations instead of new onsets, preventing false-positive Bloodlust/Heroism/Time Warp sounds on zoning or reload transitions.
- **Bugfix / Leader Promotion Sound:**
  - Leader gain detection now reacts to the first observed local leader transition across both `GROUP_ROSTER_UPDATE` and `PARTY_LEADER_CHANGED`, preventing missed promotion sounds when roster updates arrive first.
- **Bugfix / Esc Menu Combat Safety:**
  - Deferred game-menu side-panel host-frame `Show()` calls now stay combat-safe and replay through the existing `PLAYER_REGEN_ENABLED` retry path instead of triggering protected `Frame:Show()` calls in combat.
- **Bugfix / Hearthstone Fallback:**
  - The `Esc` travel-strip `Hearthstone` button now falls back to the default Hearthstone item (`6948`) when the player owns no Hearthstone toy, instead of leaving the secure button without a usable action.
- **Tests:**
  - Added regression coverage for harmful-aura lust scanning, zone-transition lust continuation, local lust spellcast forwarding, leader-promotion event ordering, game-menu combat-safe deferred host-frame shows, and Hearthstone toy/item fallback behavior.

## 2026-03-23 - Version 0.9.94
- **M2 Travel Short Codes:**
  - `M2` portal icons now render large localized dungeon short codes directly on the icon while the teleport is ready, so the destination is recognizable without mouseover.
  - The `M2` short-code overlay is hidden whenever the teleport is on cooldown, leaving the cooldown timer unobstructed.
  - Updated active Midnight Season 1 short codes to favor clearer `M2` readability: `Windrunner Spire` now uses `WRS` (`enUS`/`deDE`) and `Maisara Caverns` now uses `MAI` (`enUS`/`deDE`).
  - Added deterministic `TeleportUI` coverage for visible `M2` short-code rendering and cooldown-time overlay suppression.
- **Forward Compat / Blizzard 12.0.1 Cooldown Hotfix:**
  - `SpellUtils.ApplyCooldownFrameSafe` now prefers `SetCooldownFromDurationObject` (the only setter Blizzard guarantees for secret values post-hotfix) over `CooldownFrame_Set` and `SetCooldown`. Feature-detected: works on both current live and post-hotfix clients.
- **Bugfix / Sync Cooldown Reset:**
  - `Sync.ClearKnownUsers()` now resets all send cooldown timestamps and dedup payloads so the next identical snapshot fires immediately after a group change instead of being silently suppressed.
- **Bugfix / Realm Normalization:**
  - `Stats.NormalizeName()` now strips spaces, dashes, dots, parentheses, and quotes from realm names, matching the `Sync.NormalizePlayerKey()` convention. Previously, realm names with special characters (e.g. `Der Rat von Dalaran`) could fail to match between damage-meter sources and roster entries.
- **Bugfix / Arkantine Locale:**
  - The `Esc` travel strip `Arkantine` button now resolves the item name by WoW client locale at button creation time (`deDE` → German, all others → English). Previously, the macro was hardcoded to the German item name and would fail on non-German clients.
- **Bugfix / Highlight Determinism:**
  - Activity ID selection from multi-activity LFG listings now sorts candidates and picks the smallest ID instead of relying on non-deterministic `pairs()` iteration order.
- **Code Hardening / rawget Pattern:**
  - All `IsiLiveDB` global reads now use `rawget(_G, "IsiLiveDB")` consistently across all modules (`stats`, `sync`, `log_buffer`, `queue_debug`, `runtime_log`, `ui`, `factory_controllers`, `event_handlers_challenge`) to avoid triggering `__index` metamethods on `_G`.
  - `GetRealmName` access in both `isiLive_stats.lua` and `isiLive_sync.lua` switched to `rawget(_G, "GetRealmName")` with type guard, matching the defensive pattern used for all other WoW API globals.
  - Added nil-guards for `rawget(_G, "IsiLiveDB").stats` access in `isiLive_stats.lua` to prevent nil-index crashes if the call chain is ever reordered.
- **Code Cleanup / KeySync:**
  - Extracted `ResolveAverageItemLevel()` as a standalone function in `isiLive_keysync.lua`, eliminating the inline duplication between `C_Item` and legacy `GetAverageItemLevel` fallback paths.
- **Season Data:**
  - Cleared the inactive portal message for Midnight Season 1 now that the season is live (`inactivePortalMessageByLocale` is empty).
- **Tests:**
  - Added regression test for `Stats.NormalizeName` realm special-character stripping with `Der Rat von Dalaran` (spaces, stripped-variant lookup).
  - Added regression test for `Sync.ClearKnownUsers` cooldown/dedup reset (identical payload must fire immediately after clear).
  - New `isilive_test_scenarios_keysync.lua`: 17 dedicated KeySync controller tests covering `MarkIsiLiveUser`, `UnitHasIsiLive`, `RegisterIsiLiveSyncPrefix`, `ResolveActiveKeyOwnerUnit`, `RefreshLocalPlayerKey`, `ForceRefreshSyncState`, `GetOwnedKeystoneSnapshot`, `SendRefreshRequest`, and `ApplyKnownKeyToRosterEntry`.
  - New `isilive_test_scenarios_commands_extended.lua`: 13 extended commands tests covering `testall` (stopped/paused/running), `tptest`, `tpdebug`, `lead` (yes/no), `bindcheck`, unknown/empty input help, pause/resume while stopped, and `lang enus/dede` aliases.
  - New `isilive_test_scenarios_config_builders.lua`: 8 config builder tests verifying all 6 `BuildXxxOpts()` functions pass through context fields correctly and do not leak extra fields.
  - `lua tools/validate_usecases.lua` now validates `404` deterministic tests indexed and `408` scenarios across `37` modules.
- **Code Modernization / Shared Utilities:**
  - New `isiLive_validation_helpers.lua`: centralized `RequireFunction`, `RequireTable`, and `IsExistingUnit` — eliminates identical 4–13 line helper copies across 11+ modules.
  - New `isiLive_string_utils.lua`: centralized `Trim`, `StripWhitespace`, and `NormalizeRealmName` — replaces duplicate inline `gsub` patterns across 6+ modules.
  - All 11 modules with local `RequireFunction`/`RequireTable` now delegate to `addonTable.Validators`.
  - `IsExistingUnit` consolidated from 4 identical copies (units, locale, inspect, roster) into one canonical implementation.
  - Realm normalization in `Sync.NormalizePlayerKey`, `Stats.NormalizeName`, and `Locale.NormalizeRealmLookupKey` now uses `StringUtils.NormalizeRealmName`.
  - Trim patterns in `Status`, `FactoryControllers`, and `Sync.NormalizeSyncSource` now use `StringUtils.Trim`.
  - Test harness (`isilive_test_harness.lua`) extended with universal dependency loading for shared utility modules.
- **Code Modernization / Factory Decomposition:**
  - Split `InitializeFactoryRuntimeHelpers` (288 lines) into 4 focused sub-functions: `InitializeGameAPIHelpers`, `InitializeRuntimeStateDelegates`, `InitializeRioHelpers`, `InitializeStatusAndOperationalHelpers`.
- **Code Modernization / Sync Documentation:**
  - Replaced brief German inline comment with detailed English architecture note explaining the singleton state rationale, reset contract, and relationship to `ClearKnownUsers()`.
- **Tests:**
  - New `isilive_test_scenarios_validation_helpers.lua` (8 tests): RequireFunction/RequireTable pass/fail/default, IsExistingUnit nil/missing-API/delegation/pcall-safety.
  - New `isilive_test_scenarios_string_utils.lua` (7 tests): Trim/StripWhitespace/NormalizeRealmName with edge cases and canonical pattern verification.

## 2026-03-23 - Version 0.9.93
- **Sound / Leader Promotion:**
  - Plays `sounds/CartoonVoiceBaritone.ogg` (Master channel) when the local player is promoted to group leader via `PARTY_LEADER_CHANGED`.
  - Sound fires even when the isiLive frame is hidden; uses `PlaySoundFile` directly instead of `SOUNDKIT` constants.
- **Sound / Bloodlust & Heroism:**
  - Plays `sounds/BoxingArenaSound.ogg` (Master channel) on Bloodlust / Heroism / Time Warp onset, detected via `CdTracker`.
  - `CdTracker` gains an `onLustStart` callback and a `SuppressOnset(seconds)` method to prevent false positives from auras briefly disappearing during zone transitions or reloads.
  - `baselineCdTracker` (calls `SuppressOnset(3)`) is now wired into both `PLAYER_ENTERING_WORLD` and all `ZONE_CHANGED*` / `UPDATE_INSTANCE_INFO` handlers, covering portal traversals that do not trigger a loading screen.
- **Assets / Git:**
  - `sounds/` directory added; all sound files ignored by default except the two actively used (`CartoonVoiceBaritone.ogg`, `BoxingArenaSound.ogg`).
- **UI / Portal Navigator:**
  - Dungeon name text color changed from plain white to warm cream-gold for better visual harmony with the title.
  - Background alpha increased from `0.5` to `0.72` for improved readability.
  - Added a subtle gold separator line below the title to give the overlay more visual structure.

## 2026-03-22 - Version 0.9.92
- **Docs / Release Baseline:**
  - Bumped TOC version to `0.9.92`.
  - Synced `README.md`, `USECASES.md`, `ARCHITECTURE.md`, `RELEASE.md`, and `isiLive.toc` to `0.9.92`.
  - `lua tools/validate_usecases.lua` now validates `338` deterministic tests indexed and `341` scenarios across `32` modules.
- **UI / Stats / Utility Row:**
  - Roster run stats now include `Deaths` and `Kicks` alongside `DPS`, with matching tooltip lines for completed runs.
  - Added the live cooldown tracker row for `BRes` charges/cooldown and `Bloodlust`/`Heroism`/`Time Warp` countdowns.
  - The `Esc` menu now also exposes a second travel strip with `Arkantine`, `Hearthstone`, and `Housing`.

## 2026-03-22 - Version 0.9.91
- **Docs / Release Baseline:**
  - Bumped TOC version to `0.9.91`.
  - Synced `README.md`, `USECASES.md`, `ARCHITECTURE.md`, `RELEASE.md`, and `isiLive.toc` to `0.9.91`.
  - `lua tools/validate_usecases.lua` now validates `324` deterministic tests indexed and `327` scenarios across `31` modules.

## 2026-03-22 - Version 0.9.90
- **UI / Sync UX:**
  - Sync payloads now carry freshness metadata (`capturedAt`, `source`) and HELLO also carries the sync protocol version.
  - The roster tooltip shows sync age, source, peer version, and a Shift-only debug block for per-field sync provenance.
  - The roster row shows a compact sync icon badge next to the existing addon-presence heart marker; the visible `fullsync` row marker was removed.
- **UI / Settings Defaults:**
  - `Default UI on Open` now defaults to `M2` when no explicit choice is stored, while `Last Used` stays available as the explicit fallback sentinel.
  - `Auto-Hide when Solo` now defaults to enabled until the user turns it off.
  - Blizzard Settings now also expose the optional `Column Guides` debug toggle for roster layout tuning.
- **UI / Layout Cleanup:**
  - The roster panel keeps the `M2` main-horizontal layout as the default open view, shows the status line only in `M`, and removes the combat-logging / DM-reset toggles from the main panel UI.
  - Column guides stay hidden by default and are only shown in `M` and `M2` when explicitly enabled for tuning.
  - Portal buttons keep deterministic season-slot placement, and active-target highlighting remains unchanged.
- **UI / Portal Navigator:**
  - New overlay: when the player enters the Timeways portal room, a full-screen `Portal Navigator` notice appears showing the four portal destinations (half-left, left, right, half-right) with their dungeon names; closes via right-click or the X button; respects `Show Timeways Navigator` setting (defaults enabled); retries zone detection for one second if zone text is not yet available.
  - Zone matching uses Map ID first, then falls back to normalized `GetZoneText` / `GetSubZoneText` / `GetRealZoneText` / `C_Map.GetMapInfo` name matching across all registered portal-room names.
  - Non-group-member tooltip language flag now resolves correctly when LibRealmInfo is absent: `tooltipData.unitToken` is used as the unit source even in `preferTooltipDataOnly` mode so the static realm-data fallback in `GetUnitServerLanguage` stays reachable.
- **UI / Flag Icons:**
  - Flag texture markup corrected from portrait `14:10` to landscape `12:16`, matching the native 16×12 px asset dimensions; flags no longer appear squished.
  - Flag column (`SERVER_COL`) widened from 14 to 18 px; `NAME_COL_X` shifted +4 to 93 and `NAME_COL_WIDTH` reduced by 4 to 122 to keep the overall layout width unchanged.
- **UI / Polish:**
  - Title font reduced from `GameFontHighlightHuge` (~18 px after manual correction) to `GameFontNormalLarge` (~14 px); the manual `GetFont`/`SetFont` correction block is removed.
  - H-mode button labels (`RC`, `CD`, `CD 0`) are now fully localized: locale keys `BTN_READYCHECK_SHORT`, `BTN_COUNTDOWN10_SHORT`, `BTN_COUNTDOWN_CANCEL_SHORT` added to both `enUS` and `deDE` tables; hardcoded English strings removed from button construction.
  - Typo fixed in both locale tables: `LEAD_OPTIONS` was `"M+Managment"` → `"M+Management"`.
- **Code Cleanup:**
  - Removed 12 dead `RI.H2_*` alias exports from `isiLive_roster_layout.lua` (leftover from the internal H2→M2 rename; no consumer existed).
  - Portal Navigator `FormatPortalNavigatorEntryText`: unused `direction` parameter removed; function simplified.
  - Portal Navigator `BuildPortalNavigatorConfig`: removed unused `isInCombat` and `getL` config fields (text is passed as a pre-built layout; no combat gate on the navigator); factory call cleaned up accordingly.
  - Portal Navigator state fields (`wasInPortalRoom`, `lastPortalNavigatorSignature`, `portalNavigatorRetryToken`, `portalNavigatorRetryScheduledToken`) now explicitly initialized in the state table, consistent with all other state fields.
  - `restoreRioBaseline` callback was wired into `BuildEventHandlersDepsFromContext` but never forwarded to the EventHandlers config in `ExtendEventHandlersConfig`; the missing assignment is now in place.
- **Docs + Release Baseline:**
  - Bumped TOC version to `0.9.90`.
  - Synced `README.md`, `USECASES.md`, `ARCHITECTURE.md`, `RELEASE.md`, `TODO.md`, `CHANGELOG.md`, and `isiLive.toc` to `0.9.90`.
  - `lua tools/validate_usecases.lua` now validates `310` deterministic tests indexed and `312` scenarios across `30` modules.

## 2026-03-20 - Version 0.9.88
- **Runtime Bugfixes:**
  - Narrowed the `autoOpenOnQueue` gate so only queue-triggered frame opens are suppressed; dungeon-entry, key-end, and test-preview opens still show the main frame.
  - Kept pending force-refresh state row-local across group rebuilds, and blocked sync backfill from overwriting an in-flight local refresh until the inspect result arrives.
  - Reused the existing player row on leave/rebuild so pending refresh state, freshness flags, sync data, and live player data survive group churn instead of being dropped during a fresh table build.
  - The deferred `GameMenuFrame` close callback now ignores a stale reopen race so the host frame is not hidden if the menu was reopened before the timer fired.
  - Added `UnitExists`-guarded helpers around unit-token reads so missing or shifting group tokens no longer hit raw `UnitClass`, `UnitName`, `UnitLevel`, `UnitIsConnected`, `UnitGUID`, `UnitIsUnit`, `UnitIsVisible`, or `CanInspect` paths.
  - Added deterministic regression coverage for the queue gate, pending force-refresh rebuilds, the deferred game-menu close race, and the missing-unit race paths across group, inspect, locale, roster display/panel, test mode, sync, UI, and unit helpers.
- **Docs + Release Baseline:**
  - Bumped TOC version to `0.9.88`.
  - Synced `README.md`, `USECASES.md`, `ARCHITECTURE.md`, `RELEASE.md`, `TODO.md`, `CHANGELOG.md`, and `isiLive.toc` to `0.9.88`.
  - `lua tools/validate_usecases.lua` now validates `293` deterministic tests indexed and `295` scenarios across `30` modules.
- **Metrics Policy:**
  - Raised the `lua tools/lua_metrics_check.lua` file hard limit to `2600` lines so the current `testmodul/isilive_test_scenarios_roster_panel.lua` size stays within the release gate.

## 2026-03-18 - Version 0.9.86
- **UI - Combat-Safe Esc Shortcut Secure Refresh:**
  - Fixed the `ADDON_ACTION_BLOCKED` path where the `Esc`-menu `ReloadUI` secure button tried to refresh click registration / secure macro attributes while the protected `GameMenuFrame` was being shown during combat.
  - Game-menu secure shortcut updates now defer blocked secure refreshes and replay them on `PLAYER_REGEN_ENABLED` instead of touching the protected button immediately.
  - Added deterministic UI regression coverage for the combat `GameMenuFrame:OnShow` path so secure click registration, secure attributes, layout refresh, and visibility refresh stay combat-safe.
- **Internal Modernization:**
  - Extracted `isiLive_factory_frame_bridge.lua` (context creation, module wiring, frame bridge) and `isiLive_factory_controllers.lua` (runtime helpers, primary/secondary controllers, minimap button) from `isiLive_factory.lua`.
  - `isiLive_factory.lua` reduced from ~1413 to ~310 lines; sub-modules export via `addonTable._FactoryInternal`.
  - Extracted `isiLive_roster_tooltip.lua` (simple tooltip API, hover tooltip, content builders) and `isiLive_roster_layout.lua` (layout modes, collapse state, system option toggles) from `isiLive_roster_panel.lua`.
  - `isiLive_roster_panel.lua` reduced from ~2259 to ~1383 lines; sub-modules export via `addonTable._RosterInternal`.
  - Added `UICommon.BACKDROP_PRESETS` and `UICommon.ApplyBackdrop(frame, presetName)` in `isiLive_ui_common.lua`, replacing ~111 redundant inline `SetBackdrop` calls across UI files.
  - Replaced 23 individual `RegisterEvent` calls in `isiLive_bootstrap.lua` with a declarative `EVENT_REGISTRY` table; gate tables for combat/hidden/test modes are now generated from the registry.
  - Added `IMPLICIT_DEPENDENCIES` for `isiLive_roster_panel.lua` and `isiLive_factory.lua` so sub-modules auto-load in tests.
  - Updated architecture source-boundary tests to reference the new split files.
- **Docs + Release Baseline:**
  - Bumped TOC version to `0.9.86`.
  - Synced `README.md`, `USECASES.md`, `ARCHITECTURE.md`, `RELEASE.md`, `TODO.md`, `CHANGELOG.md`, and `isiLive.toc` to `0.9.86`.
  - `lua tools/validate_usecases.lua` now validates `287` deterministic tests indexed and `289` scenarios across `30` modules.

## 2026-03-16 - Version 0.9.85
- **Settings - Expanded Blizzard Settings + Hidden Legacy Defaults:**
  - Extended `Settings -> AddOns -> isiLive` with `UI Scale`, `Minimap Button`, `Addon Sync`, `Auto-Open on M+ Queue`, and `Auto-Hide when Solo`.
  - Temporarily hid `Name Length`, `Teleport Grid Columns`, `Show DPS Column`, `Markers: Leader Only`, and `Sound Notifications` from Blizzard Settings without removing their code paths.
  - While these controls stay hidden, runtime now keeps deterministic live defaults: fixed 12-char name truncation, legacy 2-column `Travel` grid, `DPS` column on, `Markers: Leader Only` off, and `Sound Notifications` off.
- **Runtime - Non-Challenge DPS Capture:**
  - Last-run DPS capture on instance exit now covers tracked normal and heroic party dungeons in addition to tracked non-challenge mythic exits and `M+` completions.
  - Non-challenge exit capture still uses the roster frozen on dungeon entry and retries briefly if the Blizzard damage-meter session is not finalized yet.
- **UI - Travel Grid Layout Restore:**
  - Restored the `Travel` grid to the legacy two-column layout and kept the button block aligned under the `Travel` header again.
- **Validation + Docs Sync:**
  - `lua tools/validate_usecases.lua` now validates `286` deterministic tests indexed and `288` scenarios across `30` modules.
  - Synced `README.md`, `USECASES.md`, `ARCHITECTURE.md`, `RELEASE.md`, `TODO.md`, `CHANGELOG.md`, and `isiLive.toc` to `0.9.85`.

## 2026-03-15 - Version 0.9.84
- **UI - Sync Heart Marker:**
  - Replaced the text-based `<3` addon-presence marker with a custom dark-blue 16x16 TGA heart icon (`media/heart_sync.tga`) rendered as inline texture behind synced member names.
- **UI - Background Opacity Slider:**
  - Added a `Background Opacity` slider to the Blizzard Settings canvas (`Settings -> AddOns -> isiLive`) with a configurable range from 30% to 100% (default 50%, step 5%).
  - Changing the slider live-updates the main frame, ESC panel, and settings canvas backdrop alpha; the value persists in `IsiLiveDB.bgAlpha`.
- **UI - Teleport Tooltip Dungeon Name:**
  - Center-notice teleport button tooltip now shows the dungeon name instead of the spell name, so users can identify which dungeon the teleport leads to.
- **UI - Flat Management Buttons:**
  - Replaced standard Blizzard `UIPanelButtonTemplate` management buttons (`Readycheck`, `Countdown10`, `Countdown 0`, `Share Keys`, `Refresh`) with flat dark `BackdropTemplate` buttons matching the ESC panel style, including blue hover accent borders.
- **UI - Compact Spec Labels:**
  - Tightened long spec shortcodes to a max visible width of 5 characters (for example `Resto`, `Retri`, `Boomy`, `Shado`, with hunter short labels kept as `MM`/`BM`) so the roster keeps its compact column fit.
- **UI - Combat-Safe Close Button:**
  - The main frame X (close) button now always hides the frame immediately, even during combat lockdown. Toggle via `CTRL+F9` remains combat-deferred for taint safety.
- **Sync - DPS and Location Sharing:**
  - Added `DPS:<value>` sync message: isiLive users now share their last-run DPS with group members. The DPS column falls back to synced DPS when local data is unavailable.
  - Added `LOC:<mapID>` sync message: isiLive users now share their current dungeon location. The roster portal icon uses synced location as fallback when local unit map info is unavailable.
  - Both messages are included in local snapshot sends, `REQSYNC` responses, zone/context refreshes, and self-update snapshot pushes.
  - Foreign DPS and LOC data is session-only and cleared on group leave.
- **Validation + Docs Sync:**
  - `lua tools/validate_usecases.lua` now validates `280` deterministic tests indexed and `282` scenarios across `29` modules.
  - Synced `README.md`, `USECASES.md`, `ARCHITECTURE.md`, `RELEASE.md`, `TODO.md`, and `CHANGELOG.md` to `0.9.84`.

## 2026-03-15 - Version 0.9.83
- **UI - Esc Menu + Settings Integration:**
  - Added a Blizzard `Settings -> AddOns -> isiLive` category with localized controls for language, `Advanced Combat Logging`, `DM Reset on Dungeon Entry`, `Show ESC Menu Shortcuts`, `Queue Debug Log`, and `Runtime Log`.
  - Wired the new settings canvas into the shared localization refresh path so locale changes immediately refresh both the Blizzard settings canvas and the optional `Esc`-menu shortcut strip.
  - The optional `Esc` shortcut strip now documents the actual 10 wired targets: `Professions`, `Talents`, `Spells`, `Achievements`, `Quests`, `Dungeons`, `Journal`, `Collections`, `Guild`, and a separated `ReloadUI` button.
  - The `ReloadUI` shortcut now runs through a secure macro (`/click GameMenuButtonContinue` + `/reload`) and mirrors `ActionButtonUseKeyDown` instead of dispatching an addon-side Lua reload call.
- **UI - Visual Refresh:**
  - Added a shared dark/gold/blue UI palette in `isiLive_ui_common.lua` and applied it across private tooltips, center notice, invite hint, roster hover treatment, and panel chrome.
  - Roster rows now use alternating background shading, split gradient header separators, and a softer blue hover highlight; the roster title also gets a stronger shadow treatment.
  - Center-notice teleport hover gains a subtle glow and the blinking text pulse was slowed down for readability.
- **Validation + Docs Sync:**
  - Added the new `isiLive_settings.lua` module to the `.toc` load order and bumped the addon/docs baseline to `0.9.83`.
  - `lua tools/validate_usecases.lua` now validates `275` deterministic tests indexed and `277` scenarios across `29` modules.
  - Synced `README.md`, `USECASES.md`, `ARCHITECTURE.md`, `RELEASE.md`, `TODO.md`, and `isiLive.toc` to `0.9.83`.

## 2026-03-14 - Version 0.9.82
- **UI - Combat Visibility Deferral:**
  - Main-frame show/hide requests are now deferred during combat lockdown and deterministically replayed on `PLAYER_REGEN_ENABLED`.
  - Runtime regen recovery now reapplies queued main-frame visibility before the pending post-combat height/layout refresh.
- **UI - Roster Panel Compacting:**
  - Tightened the expanded roster-panel width and shifted the right-side columns left to reduce wasted horizontal space.
  - Shortened the visible helper headers from `M+Marker` / `M+Travel` to `Marker` / `Travel`.
  - Unified member-row clearing so raid H-mode and normal rerenders use the same deterministic reset path.
- **Season Data - Midnight Season 1 Live Portal Pool:**
  - Replaced the placeholder `midnight_s1` dataset with concrete map IDs, spell IDs, display order, and localized short codes for all eight season dungeons.
  - Teleport-grid entries now keep their deterministic season slot positions even when shared spells collapse duplicate visible buttons.
- **Validation + Docs Sync:**
  - Updated combat-visibility deterministic tests and active rule mappings to the deferred regen-apply behavior.
  - Hardened `isiLive_event_handlers.lua` so the pending-visibility getter is wired as an explicit optional dependency and the regen visibility path is exercised by the deterministic handler tests.
  - Cleaned up `testmodul/isilive_test_scenarios_ui.lua` with explicit nil-guards / `rawget` access so LuaLS no longer reports false-positive `need-check-nil` / `undefined-field` diagnostics on the dynamic test fixtures.
  - Updated deterministic validator counters to `267` scenarios across `29` modules.
  - Synced `README.md`, `USECASES.md`, `ARCHITECTURE.md`, `RULES_LOGIC.md`, `TODO.md`, and `isiLive.toc` to `0.9.82`.

## 2026-03-13 - Version 0.9.81
- **Packaging - Exclude PNG Assets From Curse Release:**
  - CurseForge packaging now excludes the UI screenshot PNG files `isiLive_H_ui.png`, `isiLive_M_ui.png`, and `isiLive_V_ui.png` in addition to the already ignored logo/screenshot assets.
  - Release maintenance docs now explicitly state that PNG screenshots and logo assets stay out of packaged addon releases unless intentionally re-added.
- **Docs Sync:**
  - Synced `CHANGELOG.md`, `README.md`, `ARCHITECTURE.md`, `USECASES.md`, `RELEASE.md`, `TODO.md`, and `isiLive.toc` to `0.9.81`.
  - Updated deterministic validator counters to `263` scenarios across `29` modules.

## 2026-03-13 - Version 0.9.80
- **Stats — Character-Scoped Local DPS Persistence:**
  - The persisted local last-run DPS snapshot is now stored per local character key instead of a single account-wide slot.
  - Relogging to another own character no longer shows the previous character's persisted DPS entry.
  - Foreign-player DPS remains session-only and is still never persisted.
- **UI — Hidden Roster Hover Gating:**
  - Roster row hover frames now disable mouse interaction while the roster table is hidden in compact layouts, so invisible rows no longer keep tooltip/right-click hit areas active behind the compact tool palette.
- **Stats — Safe Legacy Migration:**
  - The legacy multi-entry `playerLastRuns` store is still migrated only for the exact current local character key.
  - The old single-slot `playerLastRun` snapshot is now discarded during migration because it has no owner identity and would otherwise be guessed onto whichever character logs in first.
- **Tests:**
  - Added deterministic regression coverage for per-character local DPS persistence and for discarding ambiguous legacy single-slot DPS during migration.
- **Docs Sync:**
  - Synced `CHANGELOG.md`, `README.md`, `ARCHITECTURE.md`, `USECASES.md`, `RELEASE.md`, `TODO.md`, and `isiLive.toc` to `0.9.80`.
  - Updated deterministic validator counters to `263` scenarios across `29` modules.

## 2026-03-13 - Version 0.9.79
- **UI — Static Layout Mode Buttons:**
  - Replaced the old mode-toggle behavior with three always-visible top-right mode buttons `H`, `V`, and `M`; the active layout is now indicated by a gold label while inactive modes stay grey.
- **UI — Horizontal Compact Mode Simplification:**
  - Removed the H-mode management carousel and its left/right cycle arrows.
  - Horizontal compact mode now shows all three leader actions side by side with short labels `RC`, `CD`, and `CD 0`.
  - `Share Keys` and `Refresh` remain available in expanded and vertical compact mode, but are intentionally hidden in H mode to keep the toolbar minimal.
- **UI — Raid Transition Behavior:**
  - Entering a raid-size group (`>5` members) no longer hides the addon window.
  - The roster panel now stays visible, automatically switches to H mode, keeps roster rows hidden, and prints a localized raid transition notice once per raid-size transition.
- **UI — Title Size:**
  - Reduced the addon title font size by an additional 2 pt (delta now `-4` instead of `-2`) for a cleaner compact look.
- **Bug Fix — Test Mode Cleanup:**
  - `roleButton` was re-shown for empty roster rows after `ExitTestMode()` because `UpdateCollapseState` unconditionally called `SetVisible(row.roleButton, show)`. Fixed to `SetVisible(row.roleButton, show and row.unit ~= nil)` so empty rows are never re-activated.
- **Runtime — Hidden Group Update Gate:**
  - Hidden `GROUP_ROSTER_UPDATE` processing no longer depends on small-group size and stays available for grouped non-challenge transitions, so pre-rendered roster state also remains current across raid-size transitions.
- **Refactor — Declarative Layout Visibility:**
  - Replaced the flat `SetVisible` list in `UpdateCollapseState` with a `UI_VISIBILITY_RULES` table that declares M/V/H visibility per element as explicit `true/false` columns. Adding or changing an element's per-mode visibility now requires touching only one row in that table.
  - Introduced `ui.columnButtons` as the canonical list of management-column buttons that stay outside H mode (`shareKeysButton`, `refreshButton`). `UpdateColumnPositions` now iterates `columnButtons` uniformly instead of using a separate special-case block.
- **Docs Sync:**
  - Synced `CHANGELOG.md`, `README.md`, `ARCHITECTURE.md`, `USECASES.md`, `RELEASE.md`, `TODO.md`, `RULES_LOGIC.md`, and `isiLive.toc` to the current `0.9.79` runtime/UI behavior.

## 2026-03-13 - Version 0.9.78
- **Refresh Sync Request:**
  - `Refresh` sends a dedicated `REQSYNC` addon message so hidden `isiLive` peers can answer with one forced `KEY` + `STATS` snapshot even while their UI is hidden.
  - Hidden refresh replies remain locally gated on the responder: no answer while `stopped`, `paused`, or during an active Mythic+ run.
  - Added deterministic regression coverage for refresh-triggered hidden replies, blocked reply states, and hidden event-handler processing.
- **UI â€” Compact Toggle Polish:**
  - Replaced the top-right compact-mode arrow icons with direct text toggles: `V` for vertical compact, `H` for horizontal compact, and `M` in compact modes to return to the main roster view.
  - Positioned the two compact toggles directly next to each other and kept the active alternate mode accessible from each compact layout.
- **UI â€” Panel Height Adjustment:**
  - Increased the default roster-panel base height so the lower M+Marker marker buttons keep clean visual separation from the `Target Dungeon` status line.
- **Docs Sync:**
  - Synced `CHANGELOG.md`, `README.md`, `ARCHITECTURE.md`, `USECASES.md`, `RELEASE.md`, `TODO.md`, and `isiLive.toc` to `0.9.78`.
  - Updated deterministic validator counters to `262` scenarios across `29` modules.

## 2026-03-13 - Version 0.9.77
- **Taint-Safe Hardening:**
  - Expanded deterministic `ADDON_ACTION_FORBIDDEN` regression coverage for deferred teleport spell attributes, insecure teleport-grid buttons, center-notice teleport handling, tank-helper secure macros, and collapse interaction while secure roster buttons already exist.
  - Added explicit combat-path regression tests so secure/insecure button boundaries are exercised before release instead of only being inferred from higher-level UI tests.
- **Code Review — Bug Fixes & Correctness:**
  - `isiLive_runtime_state.lua`: `GetSnapshot()` was returning a live reference to the internal roster table instead of a copy; callers holding a snapshot could observe subsequent group changes. Fixed by returning a shallow copy via `CopyTableShallow`.
  - `isiLive_units.lua`: Dead entry `["stärkung"]` in `SPEC_SHORT_LABELS` was never reachable because `NormalizeSpecKey` converts `ä→a` before the lookup; corrected key to `["starkung"]`. Also fixed the UTF-8 fallback path in `TruncateName` to roll back continuation bytes (`0x80–0xBF`) at the cut point so the returned string is always valid UTF-8.
  - `isiLive_controller_wiring.lua`: `timerAfter` callbacks were silently swallowing all runtime errors. Wrapped callbacks in `xpcall` with traceback and forwarded failures to WoW's global error handler (`geterrorhandler()`) so crashes surface as the standard red error frame.
  - `isiLive_highlight.lua`: `TryGet()` used `rawget(obj, key) or nil`, which coerces `false` to `nil`. An inactive LFG listing (`active = false`) was therefore indistinguishable from an absent field, causing `ResolveActiveListingTarget` to skip the inactive-listing guard. Fixed by using explicit `~= nil` checks so `false` propagates correctly.
  - `isiLive_stats.lua`: `localPlayerKey` was resolved and `MigrateAndPrunePersistentPlayerStats` was called at Lua file-execution time — before `ADDON_LOADED` fires, before SavedVariables are restored, and before `UnitExists("player")` is reliable. Both operations are now deferred via a lazy `EnsureInitialized()` called on the first `RecordRun` or `GetPlayerLastRunDps` invocation, which always happens after `ADDON_LOADED`.
  - `isiLive_event_handlers_queue.lua`: `ctx.setPendingQueueJoinInfo(nil)` appeared in both the `if` and `else` branches of `LFG_LIST_ACTIVE_ENTRY_UPDATE`. Deduplicated to a single unconditional call after the branch.
- **Code Review — Documentation & Dead-Path Annotation:**
  - `isiLive_group.lua`: Added inline comment to `PruneGhosts` explaining the intentional design: ghosts are only pruned when the group is at full capacity (5 active members), so a 4-member group still shows prior-member history.
  - `isiLive_sync.lua`: Added module-level comment documenting the deliberate Singleton pattern and explaining how `ClearKnownUsers()` scopes the session-global state.
  - `isiLive_locale.lua`: Added comment to `LocaleToLanguageTag` documenting that `KR`, `CN`, and `TW` tags are recognized but have no flag assets in `LANGUAGE_FLAG_TEXTURE_BY_TAG`.
- **Code Review — Round 2 Follow-Up:**
  - `isiLive_locale.lua`: `GetLanguageFlagMarkup` now shows the language tag as grey text (e.g. `KR`, `CN`, `TW`) instead of `??` when no flag texture exists, giving Korean/Chinese/Taiwanese players a recognizable label.
  - `isiLive_keysync.lua`: `ForceRefreshSyncState` was clearing the player roster entry's key fields in the loop and immediately overwriting them after the loop. The redundant loop-side clear is removed; the player's key is now set only once from the live keystone snapshot after the loop.
- **Code Review — Regression Tests:**
  - `isilive_test_scenarios_highlight.lua`: Added scenario verifying that a `C_LFGList.GetActiveEntryInfo` struct response with `active = false` correctly propagates through `GetNormalizedActiveEntryInfo` and causes `ResolveActiveListingTeleportSpellID` to return `nil`. Directly covers the `TryGet` false-propagation fix.
  - `isilive_test_scenarios_stats.lua`: Added scenario asserting that `CreateController` alone does not touch `IsiLiveDB` (migration is deferred). Updated the legacy-migration scenario: pruning assertions now run after the first `GetPlayerLastRunDps` call to match the lazy-init contract.
- **UI — M+Marker Column:**
  - Renamed "Tank Helper" to "M+Marker" in the roster panel header (`isiLive_texts.lua`, `isiLive_roster_panel.lua`).
  - Corrected the header label position: the `TOPRIGHT`-anchored `FontString` is now placed at `xPos + 18` so its visual centre aligns with the button column centre, matching the layout of all other column headers.
- **UI — World Marker Buttons Fix:**
  - Replaced the `/wm`/`/cwm` macro approach with the native `SecureActionButtonTemplate` attribute type `"worldmarker"`. Left-click uses `action1 = "set"`, right-click uses `action2 = "clear"` — no cursor-placement step required, marker is placed immediately.
  - Expanded the M+Marker palette from 5 to all 8 Blizzard world markers (`Square`, `Triangle`, `Diamond`, `Cross`, `Star`, `Circle`, `Moon`, `Skull`) and compacted the icon spacing so collapsed mode still fits cleanly.
  - Restored `RegisterForClicks("AnyUp", "AnyDown")` to match the required registration for the `worldmarker` attribute type.
- **UI - Second Compact Layout:**
  - Added a second collapse toggle next to the existing arrow. The original arrow still switches to the vertical compact palette; the new down-arrow switches to a slim horizontal compact layout.
  - Horizontal compact mode hides the roster/table area and `M+Travel`, keeps only `M+Managment` plus `M+Marker`, places all 8 marker icons next to each other in one row, and uses left/right cycle arrows so only one management action button is shown at a time.
  - Fixed the horizontal-layout restore bug: marker icons now return to their original vertical stack after switching back to the normal roster view.
  - Added deterministic layout and taint regressions for the new horizontal compact mode, including the combat-ignore path for the second collapse button, the management-action carousel, and the marker restore path.
- **UI - Compact Mode Polish:**
  - Vertical compact mode now also hides the title, header separator, and bottom version line, matching the stripped-down tool-palette intent.
  - Horizontal compact mode width was reduced to the minimum practical toolbar width, gained slightly larger carousel arrows and marker buttons, hides the header separator and bottom version line, and keeps a bit more air between the management carousel and the marker row.
- **Docs Sync:**
  - Synced `CHANGELOG.md`, `README.md`, `ARCHITECTURE.md`, `USECASES.md`, `RELEASE.md`, `TODO.md`, and `isiLive.toc` to `0.9.77`.
  - Updated deterministic validator counters to `258` scenarios across `29` modules.

## 2026-03-11 - Version 0.9.75
- **Tank Helper:**
  - Added a vertical bar of 5 secure world marker buttons (Blue Square, Green Triangle, Purple Diamond, Red Cross, Yellow Star) to the right of the DPS column.
  - Left-Click places the world marker (`/wm X`), Right-Click clears it (`/cwm X`).
- **Mini Mode (Collapse):**
  - Added a collapse toggle button (`<` / `>`) next to the top-right close button.
  - Toggling "Mini Mode" hides the roster table (left side) and `M+Travel`, while keeping Tank Helper and M+ Management visible.
  - Collapse state is persisted in `IsiLiveDB.rosterCollapsed` and restored on reload.
  - When collapsed, the window will not auto-close on key start or raid join, serving as a persistent compact tool palette.
- **Docs Sync:**
  - Synced all documentation files to `0.9.75` and updated the UI ASCII sketch in `ARCHITECTURE.md`.

## 2026-03-11 - Version 0.9.74
- **Manual Role Markers:**
  - Replaced the restricted "Auto-Mark" feature with interactive secure role icons in the roster.
  - Clicking the Tank icon securely applies **Blue Square** ({rt6}).
  - Clicking the Healer icon securely applies **Green Triangle** ({rt4}).
  - Removed the "Auto-Mark T/H" toggle from system options; the icons are now always interactive when a role is assigned.
- **Taint-Safe Hardening:**
  - Added a new automated test suite (`isilive_test_scenarios_taint.lua`) to proactively prevent `ADDON_ACTION_FORBIDDEN` errors.
  - The new "Härtetest" simulates a tainted environment and ensures that critical code paths (Group, Roster, Teleport, Bindings) do not call protected WoW APIs from insecure contexts.
- **Docs Sync:**
  - Synced `CHANGELOG.md`, `README.md`, `RELEASE.md`, `ARCHITECTURE.md`, `TODO.md`, and `USECASES.md` to `0.9.74`.

## 2026-03-11 - Version 0.9.73
- **Roster UI:**
  - Offline group members are now rendered in grey in the roster, matching ghost-style visual de-emphasis.
  - Ready-check status colors no longer override the offline-grey state.
- **Tests + Validation:**
  - Added deterministic coverage for offline roster-member grey rendering in `isilive_test_scenarios_roster_panel.lua`.
  - `tools/validate_usecases.lua` now validates `246` deterministic scenarios across `26` modules.
- **Docs Sync:**
  - Synced `CHANGELOG.md`, `README.md`, `RELEASE.md`, `ARCHITECTURE.md`, and `USECASES.md` to `0.9.73`.

## 2026-03-11 - Version 0.9.72
- **Auto-Mark Hotfix:**
  - Removed the forbidden direct `SetRaidTarget()` runtime path that triggered `ADDON_ACTION_FORBIDDEN` in retail.
  - Added an explicit runtime capability gate so Auto-Mark only touches raid-marker APIs when that API path is deliberately allowed; the default retail runtime now skips all marker API calls instead of tainting.
  - Kept the anti-spam behavior intact for explicitly allowed marker runtimes by still skipping units that already have the correct marker.
- **Rules + Validation Sync:**
  - Updated `RULES_LOGIC.md` rule `39` to the machine-checkable contract: markers require both the user toggle and an explicitly allowed marker API runtime; without that allowance, no marker API calls may occur.
  - Added deterministic coverage for the protected-API guard in `isilive_test_scenarios_group.lua`.
  - `tools/validate_usecases.lua` now validates `245` deterministic scenarios across `26` modules.
- **Docs Sync:**
  - Synced `CHANGELOG.md`, `README.md`, `RELEASE.md`, `ARCHITECTURE.md`, and `USECASES.md` to `0.9.72`.

## 2026-03-11 - Version 0.9.71
- **Runtime Hardening:**
  - Rolled the finalized `0.9.70` fix set forward into the next stable release after the archived accidental `0.9.70` package/tag.
  - Applied `pcall` protection to critical WoW API interactions in `isiLive_queue.lua`, `isiLive_spell_utils.lua`, `isiLive_units.lua`, `isiLive_inspect.lua`, `isiLive_status.lua`, and `isiLive_controller_wiring.lua` to prevent Lua errors during transient API failures or race conditions.
  - Added explicit `UnitExists` guards before unit-token API calls in `isiLive_units.lua` to handle group-member transitions more safely.
  - Corrected the argument order for `C_DamageMeter.GetCombatSessionFromType` in `isiLive_stats.lua` and hardened `IsUnitInspectable` in the inspect loop against API faults.
- **Tests + Validation:**
  - Added deterministic test coverage in `isiLive_test_scenarios_roster_display.lua` for roster value formatting, truncation rules, and key display logic.
  - Added deterministic `UnitExists` guard coverage in `isiLive_test_scenarios_units.lua` and inspect robustness scenarios for API error handling.
  - Consolidated `Roster.BuildDisplayData` tests into the dedicated roster-display module to remove duplicate test names and keep validation ownership clear.
  - `tools/validate_usecases.lua` now validates `244` deterministic scenarios across `26` modules.
- **Release Hardening:**
  - Deleted the accidental stable tag `isiLive_release_0.9.70` from Git and archived the corresponding CurseForge `0.9.70` artifact.
  - Documented the mandatory order `push main -> wait for green Lua Check on the exact commit -> create release tag`.
  - Documented rollback handling for accidental release tags and clarified that deleting a Git tag does not remove an already-created CurseForge artifact.
- **Docs Sync:**
  - Synced `CHANGELOG.md`, `README.md`, `RELEASE.md`, `TODO.md`, `WARTUNG.md`, `ARCHITECTURE.md`, and `USECASES.md` to `0.9.71`.
  - Removed a leftover conflict marker from `ARCHITECTURE.md`.

## 2026-03-10 - Version 0.9.70
- **Code Review & Robustness:**
  - **Defensive API Calls:** Applied `pcall` protection to critical WoW API interactions in `isiLive_queue.lua`, `isiLive_spell_utils.lua`, `isiLive_units.lua`, `isiLive_inspect.lua`, `isiLive_status.lua`, and `isiLive_controller_wiring.lua` to prevent Lua errors during transient API failures or race conditions.
  - **Unit Safety:** Added explicit `UnitExists` checks in `isiLive_units.lua` loops to handle group member transitions more gracefully.
  - **Damage Meter API:** Corrected the argument order for `C_DamageMeter.GetCombatSessionFromType` in `isiLive_stats.lua` to ensure reliable session retrieval.
  - **Inspect Stability:** Hardened `IsUnitInspectable` in the inspect loop against potential API errors.
- **Test Coverage:**
  - Added a new deterministic test module `isiLive_test_scenarios_roster_display.lua` covering roster value formatting, truncation rules, and key display logic.
  - Added robustness scenarios for API error handling in the inspect controller.
  - Added a new deterministic test module `isilive_test_scenarios_units.lua` to validate `UnitExists` guards.
  - Consolidated all `Roster.BuildDisplayData` unit tests into `isilive_test_scenarios_roster_display.lua` to resolve duplicate test names.
  - Deterministic validator coverage is now `242` scenarios across `26` modules.
- **Validation + Docs Sync:**
  - Synced `CHANGELOG.md`, `README.md`, `ARCHITECTURE.md`, `USECASES.md`, and `RELEASE.md` to `0.9.70`.

## 2026-03-10 - Version 0.9.69
- **Raid Notice in Roster Panel:**
  - Integrated the raid notice directly into the Roster Panel UI. When the group size exceeds 5 members, the roster rows are hidden and a localized "Raid warning" is displayed in the center of the roster area.
  - Removed the temporary `Center Notice` fallback for raid groups, consolidating all raid feedback into the main Roster Panel.
- **Auto-Marker Feature:**
  - Finalized the Auto-Marker feature for parties: Tanks are marked with **Blue Square** ({rt6}) and Healers with **Green Triangle** ({rt4}).
  - Removed the group leader restriction: any party member (regardless of lead status) can now automatically apply markers to group members.
  - Added an anti-spam check: the addon now verifies existing raid target indices before calling `SetRaidTarget` to avoid redundant API traffic.
  - Auto-marking logic is strictly scoped to 5-man parties; raid groups remain ignored for marking.
- **Architecture & Refactoring:**
  - **Dependency Injection Framework:** Refactored the `isRaidGroup` status to be passed through the factory context and controller wiring, ensuring clean separation between group state logic and UI rendering.
  - **Code Cleanup:** Removed deprecated `showCenterNotice` wiring and logic from `isiLive_group.lua` and `isiLive_controller_wiring.lua` in favor of the new integrated UI label.
  - **Mocking Strategy:** Standardized UI element mocks in the test suite (adding `Hide`/`Show` to `CreateFontString` mocks) to better reflect actual WoW API behavior and improve test reliability.
- **Robustness & UI:**
  - Improved `mainFrame:GetWidth()` robustness in `isiLive_roster_panel.lua` to handle mocked frame environments in tests.
  - Fixed the factory/runtime wiring regression for Auto-Mark state: the shared runtime state now forwards `getAutoMarkEnabled` / `setAutoMarkEnabled` back into roster-panel and controller wiring, preventing the startup crash in `isiLive_controller_wiring.lua`.
  - Reworked the bottom-left system-toggle layout so `Combat Logging`, `Auto-Mark T/H`, and `DM Reset on Entry` keep a fixed visible gap and no longer run into each other.
- **Validation + Docs Sync:**
  - Deterministic validator coverage is now `234` scenarios across `24` modules.
  - Synced `CHANGELOG.md`, `README.md`, and `ARCHITECTURE.md` to the current runtime/UI state.


## 2026-03-09 - Version 0.9.68
- **Post-Run DPS Capture Reliability:**
  - `M+` completed-run DPS capture now retries briefly when the Blizzard `C_DamageMeter` session is not ready on the first completion/reset event.
  - Tracked `M0` exit snapshots now use the same short retry path, so delayed damage-meter availability no longer leaves the roster `DPS` column empty permanently for that run.
  - Run capture still stays deterministic: no guessed player mapping, no duplicate completed-run records, and no persistent foreign-player history.
- **Validation + Docs Sync:**
  - Deterministic validator coverage is now `228` scenarios across `24` modules.
  - Synced `CHANGELOG.md`, `README.md`, `ARCHITECTURE.md`, `USECASES.md`, `RELEASE.md`, and `TODO.md` to `0.9.68`.

## 2026-03-09 - Version 0.9.67
- **Demo/Test Mode:**
  - `CTRL+ALT+F9` / `/isilive test` now use the exact same full dummy preview path as `/isilive testall`.
  - Both demo entries show a visible ghost/leaver row in the dummy roster so leave-state UI can be previewed without a live group.
  - Dummy preview rosters are rebuilt from fresh copies, so repeated refreshes do not accumulate mutated demo data.
- **Group Leave UI:**
  - Leaving or getting kicked from a normal party no longer auto-closes the main UI.
  - The local player stays active in the roster while former party members remain as grey ghost rows.
- **Midnight S1 Preparation:**
  - Added skeleton structure in `isiLive_season_data.lua` for the 8 upcoming Midnight Season 1 dungeons (Algeth'ar Academy, Magisters' Terrace, Maisara Caverns, Nexus-Point Xenas, Pit of Saron, Seat of the Triumvirate, Skyreach, Windrunner Spire).
  - Drafted English and German short codes for the new dungeons. MapIDs and SpellIDs remain commented out placeholders until the expansion hits the PTR.
- **Cleanup:**
  - Completely removed `tww_s3` data from `isiLive_season_data.lua` and replaced all test and documentation references with the new season context.
- **Feature:** Roster members now remain as greyed-out "ghosts" in the UI when they leave or the group disbands. Ghost rows are pruned deterministically on rejoin, fresh group join, or full-group rebuild instead of disappearing immediately.
- **Fix:** Corrected Midnight Season 1 M+ launch date from June 25, 2026, to March 25, 2026.
- **Hotfix:** `isiLive_roster_panel.lua` – Fixed a nil-crash related to `displayData.readyCheckMarkup` by adding an `or ""` fallback. This field was removed from `BuildDisplayData` in this session, missing a nil-check on the caller's side.
- **Code Review Pass 1 – Core Architecture Fixes:**
  - Extracted a single `GetL` helper in `isiLive.lua` to replace 7 duplicated `getL = function() return L end` lambdas.
  - Added `GetWasGroupLeader` wrapper for consistency with the existing `SetWasGroupLeader` wrapper.
  - Fixed duplicate `isInCombat` lambda that was defined twice in the main file.
  - Removed unnecessary `local _ = ...` assignments from fallback closures in `isiLive_events.lua`.
  - Fixed asymmetric `onEvent` handling in `isiLive_bootstrap.lua` (`BindMainFrameScripts`).
  - Removed unnecessary lambda wrapper around `opts.getUnitServerLanguage` in `isiLive_context_helpers.lua`.
  - Removed dead `ctx.dispatch` fallback code in `isiLive_config_builders.lua`.
  - Fixed `pcall` return type lint warning in `isiLive_event_handlers_runtime.lua`.
  - Added clarifying comment for intentional multiple `applyHotkeyBindings` calls on startup.
  - Added `CreatePrivateTooltip`, `PreparePrivateTooltip`, `HidePrivateTooltip` to `REQUIRED_FUNCTIONS` guards.
  - Renamed `self` → `frame` in challenge handler functions for consistency with WoW naming conventions.
- **Code Review Pass 2 – Module-Level Fixes:**
  - `isiLive_inspect.lua`: Wrapped `C_PaperDollInfo.GetInspectItemLevel` in `pcall` to prevent crash if API is absent. Moved `sendOwnKeySnapshot` from a public controller field to a local closure; exposed it via `TriggerOwnKeySnapshot()` method.
  - `isiLive_status.lua`: Fixed `GetDungeonDifficultyLabel` (internally calls `GetInstanceInfo`) being called twice inside `ConfirmAndShowNotice`; now called once, all 6 return values unpacked together.
  - `isiLive_highlight.lua`: Fixed `TryGet` calling `rawget(obj, nil)` when passed `nil` keys — guarded each key before calling `rawget`.
  - `isiLive_roster.lua`: Removed dead `readyCheckMarkup` variable (always `""`, never populated). Fixed `RAID_CLASS_COLORS` lint warning via `rawget(_G, ...)`.
  - `isiLive_log_buffer.lua`: Fixed O(n²) overflow trimming loop — now O(n) via in-place shift instead of repeated `table.remove(logs, 1)`.
  - `isiLive_units.lua`: Added `["stärkung"] = "Aug"` (DE: Augmentation Evoker) to spec short-label table.
  - `isiLive_spell_utils.lua`: Added explanatory comment for `issecretvalue` WoW-internal bug workaround.
  - `isiLive_queue_flow.lua`: Added comment explaining `AnnounceQueuedGroupJoin` forward-declaration pattern.
  - `isiLive_sync.lua`: Added comment noting `NormalizePlayerKey` is stricter than `NormalizeName` in `stats.lua` (potential key divergence on special-character realms).
  - `isiLive_keysync.lua`: Added comment documenting that `SeasonData.NormalizeMapID` is applied here (on read) and again in `sync.lua NormalizeKeyPayload` (idempotent).
  - `isiLive_stats.lua`: Added comment flagging potential parameter order question for `C_DamageMeter.GetCombatSessionFromType`.
- The code review items above do not change runtime behavior; they are internal code quality improvements.

## 2026-03-08 - Version 0.9.66
- **Tooltip Isolation Hardening:**
  - Roster row hover, roster control buttons, teleport grid buttons, and center-notice teleport hover now all use isolated `isiLive` tooltip frames instead of the shared Blizzard `GameTooltip`.
  - This removes the remaining shared `GameTooltip` anchor/unit path from `isiLive` and reduces exposure to external tooltip taint and anchor-family conflicts.
- **Tooltip Runtime Fixes:**
  - Fixed the post-isolation load-order regression by loading `isiLive_ui_common.lua` before tooltip consumers in `isiLive.toc`.
  - Fixed private tooltip rendering so isolated tooltips show their text content again instead of appearing empty.
  - Tightened private tooltip layout: narrower width, left-aligned wrapped text, and height derived from real line height so long strings no longer bleed past the tooltip edge.
- **Validation + Docs Sync:**
  - `lua tools/validate_usecases.lua` remains green at `221` deterministic scenarios across `24` modules.
  - Synced `CHANGELOG.md`, `README.md`, `ARCHITECTURE.md`, `USECASES.md`, `RELEASE.md`, and `TODO.md` to `0.9.66`.

## 2026-03-07 - Version 0.9.65
- **Post-Run DPS Snapshot:**
  - The addon now reads the Blizzard `C_DamageMeter` session after a dungeon run and exposes the latest run DPS for the current roster without guessing.
  - Supported completion paths are now `Mythic Plus` via `CHALLENGE_MODE_COMPLETED/RESET` and `Mythic 0` via tracked mythic non-challenge dungeon exit.
  - Roster tooltips now show a localized `Last run DPS` line when a matching post-run damage-meter value exists.
  - The main roster now includes a dedicated `DPS` column that renders the same latest completed-run snapshot.
  - Foreign-player DPS snapshots are now session-only and are no longer persisted to SavedVariables; only the local player's own last-run DPS remains persistent.
- **Stats Storage Pruning:**
  - Removed persistent foreign-player history from `IsiLiveDB.stats` so the database cannot grow unbounded with old group members.
  - Deprecated `Runs together` tooltip history has been removed together with the foreign-player persistence it relied on.
  - Removed the unused persistent dungeon-counter path and dead stats count APIs so the stats layer only keeps the bounded last-run DPS snapshot.
- **Roster Tooltip Expansion:**
  - Roster tooltips now also show the player's `Level` and server-language abbreviation (`DE`, `EN`, `FR`) in addition to the synced addon stats.
- **Roster Column Compression:**
  - The server-language column now renders only the flag icon, and its header is intentionally blank so no `....` placeholder appears.
  - The `Spec` column is now anchored further left, player names are clamped to Blizzard's 12-character limit, and spec labels are clamped to 5 characters.
  - `Key`, `iLvl`, `RIO`, and `DPS` column widths are now constrained to their real display maxima to free as much space as possible for the DPS snapshot.
  - Visible key short codes now allow up to 4 letters.
  - Unknown or unresolved dungeons no longer fall back to numeric map IDs in the roster or key-share text; the addon only shows fact-based short codes from season data.
- **Demo/Test Mode Fixes:**
  - Pressing `Refresh` while demo/test mode is active now rebuilds the full dummy roster instead of falling back to the live refresh path and showing only the local player.
  - Demo roster data now uses the canonical hunter spec name `Marksmanship`, so short-label resolution stays stable in preview mode.
- **Planning Docs:**
  - The hardcut rename plan in `TODO_RENAME.md` was moved from `after v0.9.65` to `after v0.9.70`.
  - Added `WARTUNG.md` as a maintenance runbook for long breaks and excluded it from CurseForge packaging.
- **Validation + Docs Sync:**
  - Deterministic validator coverage increased to `221` scenarios across `24` modules.
  - Synced `CHANGELOG.md`, `README.md`, `ARCHITECTURE.md`, `USECASES.md`, `RELEASE.md`, `TODO.md`, `TODO_RENAME.md`, and `WARTUNG.md` to the current runtime/release state.
- **Post-Review Fixes:**
  - `M0` snapshots no longer flush early on tracked mythic subzone/map changes; the frozen roster now stays bound to the original dungeon entry until real instance exit.
  - `M0` snapshots now hydrate from the first reliable post-entry group roster update when zoning finishes before the roster is fully available.
  - Unknown tooltip key short codes now stay unresolved as `?` instead of falling back to numeric `mapID` values.
  - Roster row hover now uses a private `isiLive` tooltip instead of the shared Blizzard `GameTooltip`, removing the risky `SetUnit`/global-hide path that could collide with external tooltip taint.
  - Roster control buttons, teleport buttons, and center-notice teleport hover now also use isolated `isiLive` tooltip frames instead of the shared Blizzard `GameTooltip`.
  - Fixed addon load order regression by moving `isiLive_ui_common.lua` ahead of tooltip consumers in `isiLive.toc`.
  - Internal teleport wiring now uses season-agnostic resolver names; legacy `Season3` exports remain only as compatibility wrappers.
  - Runtime event wiring now forwards `recordRun` correctly from the composition root, hidden addon-sync/group updates may pre-render event-driven UI state without polling, and dead queue/runtime wiring was removed.
  - Status-line `M+` text now safely handles missing Blizzard challenge APIs instead of calling `C_ChallengeMode` unguarded.
  - Hidden-gate policy for background sync is now owned centrally by `ConfigBuilders.BuildGateOpts(...)` instead of being patched later in `RuntimeSetup`.
  - The root now de-duplicates the shared `GROUP_ROSTER_UPDATE` trigger helper and trims unused `RuntimeSetup` return payloads.
  - `LeaderWatch` now keeps `wasGroupLeader` synchronized even while the main UI is hidden, without firing hidden notices or chat output.

## 2026-03-06 - Version 0.9.64
- **Midnight S1 Pre-Season Portal Messaging:**
  - Kept the active season dataset on `midnight_s1` pre-season mode.
  - `M+Travel` now shows a localized Midnight Season 1 start message instead of stale `tww_s3` portal icons when no active portal pool exists.
  - The status line keeps the matching pre-season placeholder so the empty portal area reads as intentional, not broken.
- **Roster Interaction Safety:**
  - Removed roster-row left-click targeting from the insecure row UI path.
  - Right-click whisper remains available.
  - Added deterministic regression coverage so protected `TargetUnit` calls do not reappear through the row interaction path.
- **Packaging + Planning Docs:**
  - Excluded `TODO_RENAME.md` from CurseForge packaging via `.pkgmeta`.
  - Added `TODO_RENAME.md` as the hardcut rename runbook for the planned rename migration after `v0.9.65`.
- **Validation + Docs Sync:**
  - Deterministic validator coverage increased to `188` scenarios across `24` modules.
  - Synced `README.md`, `ARCHITECTURE.md`, `USECASES.md`, `RELEASE.md`, `RULES.md`, and `TODO.md` to the current runtime/release state.

## 2026-03-05 - Version 0.9.63
- **Roster Tooltip Positioning:**
  - Forced roster tooltips to anchor at the mouse cursor (`ANCHOR_CURSOR`) instead of using the default UI position.
  - This keeps the tooltip near the mouse pointer for better context visibility.
  - Updated control buttons (Refresh, Readycheck, Share Keys) to also use `ANCHOR_CURSOR` for consistency.
- **"Runs Together" Tracker:**
  - The addon now tracks how often you have completed a dungeon with specific players.
  - If you have played with a group member before, a line `Runs together: X` appears in their roster tooltip.
  - Data is stored locally in `IsiLiveDB` and updates automatically on dungeon completion.
- **Ghost Members (Roster Persistence):**
  - Players leaving the group now remain visible as "ghosts" (greyed out) until their slot is filled or the UI is reloaded.
  - This improves context when forming groups, preventing rows from jumping immediately upon a leave.
- **Ghost Member Stability:**
  - Fixed data loss when group members shift slots (e.g. `party2` becomes `party1`).
  - Fixed duplicate ghost entries appearing during slot shifts.
  - RIO, iLvl, and Key data now correctly persists when a player moves slots or rejoins the group.
  - Ghosts are now reliably pruned when the group becomes full (5 members).
- **Background Data Sync:**
  - Relaxed Rule 28 ("Sparflamme"): Data synchronization (Addon messages, Roster updates) now continues in the background while the main window is hidden.
  - UI rendering remains suspended to conserve performance.
  - This ensures data (Keys, RIO, iLvl) is immediately available upon opening the window, improving responsiveness.
- **Smart Self-Update:**
  - The addon now automatically broadcasts a data snapshot (Key/Stats) when the player's own iLvl, RIO, or Spec changes (detected via inspect loop).
  - Previously, updates were only sent on group join, key end, or manual refresh.
  - This ensures the group always sees your current gear/score without manual intervention.
- **Roster Interaction:**
  - **Right-Click** on a roster row now opens a whisper to the player.
  - This adds direct whisper access from the isiLive list.
- **Ready Check Indicators:**
  - The roster now colors player names to indicate status during a ready check.
  - Green for "Ready", Red for "Not Ready", and Yellow for "Waiting".
  - This replaces the previous dot indicator for a cleaner look.
- **"At Dungeon" Indicator:**
  - Players in the group who are already inside the target dungeon are now marked with a summon-portal icon next to their name.
  - This provides a quick visual cue for who is ready at the summoning stone.
- **Midnight S1 Pre-Season Mode:**
  - Switched the active season dataset to `midnight_s1` pre-season mode instead of continuing to expose stale `tww_s3` portals.
  - `M+Travel` now shows an empty active portal pool until Midnight Season 1 dungeon/teleport mappings are complete.
  - The status line now explains the empty pool via a pre-season target-dungeon placeholder instead of looking broken.
  - The portal area itself now shows a `Midnight S1` season-start message instead of rendering obsolete `tww_s3` portal icons.
- **Architecture Refactor:**
  - Introduced central runtime state in `isiLive_runtime_state.lua` for roster, queue target, runtime flags, ready-check state, and RIO baseline ownership.
  - Reduced `isiLive.lua` toward a composition root by moving mutable runtime concerns behind the runtime-state controller.
  - Split `isiLive_event_handlers.lua` into lifecycle-specific modules: `isiLive_event_handlers_runtime.lua`, `isiLive_event_handlers_queue.lua`, and `isiLive_event_handlers_challenge.lua`.
  - Simplified wiring by adding context-based controller factories in `isiLive_controller_wiring.lua` and consuming them from `isiLive_runtime_setup.lua`.
- **Architecture Rule Gate:**
  - Added `ARCHITECTURE_RULES.md` as a dedicated contract source for structural module boundaries.
  - Added `tools/validate_architecture_rules.lua` and deterministic architecture scenarios for composition-root ownership, lifecycle aggregation, context-based wiring, runtime-state ownership, and focused config builders.
  - `tools/validate_usecases.lua` now validates both runtime rules and architecture rules before executing the full deterministic gate.
- **Runtime Fixes:**
  - Ready-check state is now fully wired through bootstrap, gating, event handling, and roster rendering.
  - Ghost roster members are excluded from forced inspect refresh paths so their cached data is preserved.
  - Completed-run recording is deduplicated across `CHALLENGE_MODE_COMPLETED` and `CHALLENGE_MODE_RESET`.
  - Removed insecure roster-row left-click targeting because direct `TargetUnit` calls from the current row UI can taint into protected-action errors ingame.
- **Test Coverage:**
  - Added dedicated `RuntimeState` regression scenarios.
  - Added dedicated architecture rule scenarios and validator coverage.
  - Test harness now supports implicit addon-module dependencies for aggregated controller modules.
  - Deterministic validator coverage increased to `186` scenarios across `24` modules.
- **Documentation:**
  - Updated `RULES_LOGIC.md` with Rule 32 (Ghost Member), Rule 33 (At Dungeon), Rule 34 (Ready Check), and updated Rule 28 (matching exact test names).
  - Added `ARCHITECTURE_RULES.md` and aligned docs with the architecture gate.
  - Synced `README.md`, `ARCHITECTURE.md`, `USECASES.md`, `RELEASE.md`, and `TODO.md` to 0.9.63.
  - Validator count increased to `186` deterministic scenarios across `24` modules.

## 2026-03-05 - Version 0.9.62
- **Bug Fix: Rich Roster Tooltip Guard:**
  - `ShowRosterInfoTooltip` now only fires when actual addon-synced data is present (`class`, `spec`, `iLvl`, or `RIO`).
  - Previously, players with only name/key data (no addon sync yet) could trigger the isiLive tooltip instead of the Blizzard unit tooltip, and double-anchor `GameTooltip`.
- **CI Fix: `SLASH_ISILIVE2` in luacheck whitelist:**
  - `.luacheckrc` globals list was missing `SLASH_ISILIVE2`. Lua Check CI gate is now fully green.
- **Off-Season Mode Infrastructure:**
  - Added `SeasonData.HasActiveDungeons()` helper: returns `true` when the active season has at least one mapped dungeon.
  - `MaybeShowNonMythicDungeonEntryNotice` is now gated in `isiLive_controller_wiring.lua`: the warning is suppressed automatically when `HasActiveDungeons()` is `false`.
  - Teleport grid already handles empty season mapping gracefully (renders no buttons). No extra code needed.
  - To activate off-season mode: set `ACTIVE_SEASON_ID` to an empty season scaffold (e.g. `midnight_s1` before data is ready).
- **Test Coverage:**
  - New deterministic test: `ADDON_LOADED` restores Rio baseline from `IsiLiveDB` (total: `156` scenarios across `21` modules).
  - Nil-guard fix for `delayedCallback` in event handler test.
  - Replaced broad `need-check-nil` diagnostic suppression in commands test with targeted `executor` type guard.

## 2026-03-05 - Version 0.9.61
- **`/isk` Slash Alias:**
  - `/isk` is now a registered shorthand for `/isilive`. All sub-commands work identically.
- **Persistent Rio Baseline:**
  - The Rio baseline captured on `CHALLENGE_MODE_START` is now persisted in `IsiLiveDB.rioBaseline` and restored on `ADDON_LOADED`.
  - A UI reload mid-session no longer loses the baseline. Delta display still only activates after a key completes and the post-run refresh fires.
  - Clearing the baseline (group leave, new key start) also clears the saved value from `IsiLiveDB`.
- **Rich Roster Hover Tooltip:**
  - Hovering a roster row now shows an isiLive-data tooltip: name (class-colored), realm, spec, iLvl, Rio, and key (if any).
  - Falls back to the WoW unit tooltip then plain name if isiLive data is unavailable.
- **Internal Refactor: Debug Log Command Handlers:**
  - Extracted shared `HandleDebugLogCommand` in `isiLive_commands.lua` to eliminate duplication between `HandleLogCommand` and `HandleQDebugCommand` (~90 lines → ~55 lines).
  - Minor inconsistency in qdebug `"cleared"` message normalized to match shared label pattern.
  - No user-facing behaviour change.

## 2026-03-05 - Version 0.9.60
- **Dungeon Announce Spam Softening:**
  - Grouped queue announces are now deduplicated by signature without a time-window fallback, so identical dungeon announce blocks do not re-fire later from timing jitter.
  - Dedup state is reset when no group is active, so the same dungeon can be announced again on a real leave/rejoin cycle.
  - Added deterministic QueueFlow coverage for "same target beyond debounce window" and "re-announce after regroup".
- **Release Metadata + Docs Sync:**
  - TOC version bumped to `0.9.60`.
  - Synced `README.md`, `ARCHITECTURE.md`, `USECASES.md`, `RELEASE.md`, and `TODO.md` to `0.9.60`.
- **Validation:**
  - `lua tools/validate_usecases.lua` passes with `155` deterministic scenarios across `21` modules.

## 2026-03-02 - Version 0.9.59
- **CurseForge Review Softening:**
  - Removed the remaining automatic Blizzard-CVar enforcement from runtime startup and challenge-start flows.
  - Added passive main-UI checkboxes for `advancedCombatLogging` and `damageMeterResetOnNewInstance`; the UI mirrors live Blizzard settings and writes only on explicit user clicks.
  - Reduced review-risk sync chatter further: no extra `HELLO` burst on main-window open, no delayed second sync wave on `PLAYER_ENTERING_WORLD`, and no `KEY/STATS` re-publish on incoming `HELLO`.
- **UI / Runtime Cleanup:**
  - Removed the stale `sendIsiLiveHello` dependency from the event-handler wiring path.
  - Added a lightweight live refresh watcher so the new Blizzard-setting checkboxes re-read current CVar state while the window remains open.
- **Validation:**
  - Deterministic runtime coverage increased to `153` scenarios across `21` modules (all passing).
  - `luacheck .` is clean across the repository.
- **Documentation + Packaging Sync:**
  - Synced `README.md`, `ARCHITECTURE.md`, `USECASES.md`, `RELEASE.md`, and `TODO.md` to `0.9.59` and current runtime semantics.
- **TOC:**
  - TOC version bumped to `0.9.59`.

## 2026-03-01 - Version 0.9.58
- **Window Auto-Open Tightening:**
  - Hidden-window auto-open now only triggers on a real fresh small-group join, on key end, and on real dungeon entry (`outside -> party instance`).
  - Repeated `GROUP_ROSTER_UPDATE` events while already grouped no longer re-open a manually hidden main window.
  - Hidden `GROUP_ROSTER_UPDATE` updates inside non-key party instances remain blocked, so normal/heroic dungeon roster refreshes do not pop the UI back open.
- **Peer Sync Expansion (Visible Window Only):**
  - `isiLive` peers now exchange `STATS` snapshots in addition to `HELLO/ACK/KEY`, so `Spec`, `iLvl`, and `RIO` can backfill without inspect range when both players use `isiLive`.
  - Opening the main window now forces an immediate sync refresh (`HELLO` + `KEY/STATS`), even if the normal sync cooldown is still active.
  - Remote sync data only backfills `Spec/iLvl/RIO` until a fresh local inspect result exists; fresh local inspect data wins afterward.
- **Damage Meter Defaults:**
  - `damageMeterResetOnNewInstance` is now hard-enforced to `ON`, alongside `advancedCombatLogging`.
  - The existing manual Blizzard damage-meter reset on `CHALLENGE_MODE_START` remains active as an additional reset path when the API is available.
- **Validation:**
  - Added deterministic coverage for visible-window peer stats sync, local-inspect precedence, non-key dungeon hidden reopen guards, fresh-join-only auto-open, and outdoor-to-dungeon auto-open transitions.
  - `tools/validate_usecases.lua` now validates `152` deterministic scenarios across `21` modules (all passing).
- **Documentation + Packaging Sync:**
  - Synced `README.md` and `ARCHITECTURE.md` to `0.9.58` and current runtime semantics.
- **TOC:**
  - TOC version bumped to `0.9.58`.

## 2026-02-28 - Version 0.9.57
- **Center Notice Font Regression Fix:**
  - Fixed center-notice font scaling so repeated non-Mythic warning notices no longer grow larger after each re-show.
  - Center notice font scaling now always applies relative to the cached base font instead of the last already-scaled size.
- **Validation:**
  - Added deterministic regression coverage for repeated center-notice font scaling.
  - `tools/validate_usecases.lua` now validates `144` deterministic scenarios across `21` modules (all passing).
- **Documentation + Packaging Sync:**
  - Synced `README.md`, `ARCHITECTURE.md`, `USECASES.md`, and `RELEASE.md` to `0.9.57`.
- **TOC:**
  - TOC version bumped to `0.9.57`.

## 2026-02-27 - Version 0.9.56
- **Documentation + Packaging Sync:**
  - Synced version references in `README.md`, `ARCHITECTURE.md`, `USECASES.md`, and `RELEASE.md` to `0.9.56`.
  - Added the release-example tag references for `0.9.56`.
- **TOC:**
  - TOC version bumped to `0.9.56`.

## 2026-02-27 - Documentation Sync (Workspace)
- **Combat UI Taint Hardening (`ADDON_ACTION_BLOCKED`):**
  - Teleport grid buttons now use `InsecureActionButtonTemplate` so `isiLiveMainFrame:Show()` remains combat-toggleable (`CTRL+F9`) without protected-frame promotion.
  - Center notice teleport button now also uses `InsecureActionButtonTemplate` so notice show/hide stays combat-safe.
  - Existing combat defer/retry behavior for teleport spell-attribute updates remains unchanged.
- **Validation:**
  - Added deterministic UI coverage that simulates protected-frame show blocking in combat and verifies no secure child template is attached to the main frame in the teleport UI path.
  - `tools/validate_usecases.lua` validates `143` deterministic scenarios across `21` modules (all passing).
- **Documentation:**
  - Synced `README.md`, `ARCHITECTURE.md`, and `USECASES.md` to reflect the insecure-action teleport template behavior and combat-toggle guarantees.

## 2026-02-27 - Version 0.9.55
- **Inspect Taint Fix (`ADDON_ACTION_BLOCKED`):**
  - Removed protected `CheckInteractDistance()` usage from inspect retry processing in `isiLive_inspect.lua`.
  - Unified inspectability gating to `UnitIsVisible + CanInspect` for both initial dispatch and retry requeue paths.
- **Validation:**
  - Added deterministic inspect retry coverage in new scenario module `testmodul/isilive_test_scenarios_inspect.lua`.
  - `tools/validate_usecases.lua` now validates `143` deterministic scenarios across `21` modules (all passing).
- **TOC:**
  - TOC version bumped to `0.9.55`.

## 2026-02-26 - Version 0.9.54
- **Lua Diagnostics Hardening:**
  - Replaced direct `debug.traceback` global access in event-gate error handling with guarded `_G.debug` lookup.
  - Normalized `GameTooltip:SetText` calls to explicit color-argument signatures for LuaLS compatibility.
  - Added explicit nil/type guards in roster-panel deterministic test handlers before invoking captured callbacks.
- **Validation:**
  - `tools/validate_usecases.lua` remains at `142` deterministic scenarios across `20` modules (all passing).
- **Docs Sync:**
  - Updated `README.md` and `ARCHITECTURE.md` with explicit Lua diagnostics compatibility notes.
- **TOC:**
  - TOC version bumped to `0.9.54`.

## 2026-02-26 - Version 0.9.53
- **Roster Hover Tooltip UX:**
  - Added Blizzard-style roster row mouseover tooltip via unit binding (`GameTooltip:SetUnit(unit)`).
  - Hover rows now keep unit context from current roster render (`player`/`partyX`) for deterministic tooltip targeting.
  - Added safe fallback tooltip text (`Name-Realm`) when unit tokens are temporarily unavailable (for example fast roster transition timing).
- **Validation:**
  - `tools/validate_usecases.lua` now validates `142` deterministic scenarios across `20` modules (all passing).
- **Docs Sync:**
  - Synced `README.md`, `ARCHITECTURE.md`, `USECASES.md`, and `RELEASE.md` to `0.9.53` references and current validator counts.
- **TOC:**
  - TOC version bumped to `0.9.53`.

## 2026-02-25 - Version 0.9.52
- **Share Keys Chat Output Fix:**
  - Fixed `Share Keys` no-output regression caused by invalid manually built keystone chat links.
  - `Share Keys` now uses Blizzard owned-keystone link payload for the local player when available (`C_MythicPlus.GetOwnedKeystoneLink`).
  - Added safe fallback to plain text key output when no valid owned keystone link is available.
  - Share line format is now `isiLive PartyKeys: <Name> -> <KeyLinkOrText>`.
- **Validation:**
  - `tools/validate_usecases.lua` remains at `140` deterministic scenarios across `20` modules (all passing).
- **Docs Sync:**
  - Synced `README.md`, `ARCHITECTURE.md`, `USECASES.md`, and `RELEASE.md` to `0.9.52` references and updated Share Keys output wording.
- **TOC:**
  - TOC version bumped to `0.9.52`.

## 2026-02-25 - Version 0.9.51
- **Runtime Reliability + Error Logging:**
  - Event gate dispatch now supports a safe error callback path (`onDispatchError`) so handler failures are captured without hard-crashing the gate loop.
  - Runtime setup now routes dispatch failures through addon logging (`Print(...)`), so enabled runtime-log sessions persist these failures in `IsiLiveDB.runtimeLog`.
  - Event-handler wiring now consistently restores `runtimeLogEnabled` state from SavedVariables on `ADDON_LOADED`.
- **Spam Guard + Roster Row Stability:**
  - Added debounce guard for `Refresh` full-refresh execution (`isiLive_refresh.lua`).
  - Added debounce guard for `Share Keys` button spam (`isiLive_roster_panel.lua`).
  - Hardened roster member row rendering to enforce single-line text behavior (no wrap) across all row columns.
- **Log Code De-duplication:**
  - Added shared log helper module `isiLive_log_buffer.lua`.
  - `isiLive_queue_debug.lua` and `isiLive_runtime_log.lua` now use the shared helper for storage init, ASCII sanitizing, append trim, and tail extraction.
- **Tests + Validation Coverage:**
  - Added new deterministic scenario modules:
    - `testmodul/isilive_test_scenarios_runtime_log.lua`
    - `testmodul/isilive_test_scenarios_roster_panel.lua`
  - Added dispatch-error callback coverage in `testmodul/isilive_test_scenarios_event_utils.lua`.
  - Added runtime-log restore coverage in `testmodul/isilive_test_scenarios_event_handlers.lua`.
  - `tools/validate_usecases.lua` now validates `140` deterministic scenarios across `20` modules (all passing).
- **Rules + Docs Sync:**
  - Filled rule-to-test mappings for:
    - `RULE-BUTTON-SPAM-GUARD`
    - `RULE-ROSTER-ZEILENUMBRUCH-VERBOT`
  - Synced `README.md`, `ARCHITECTURE.md`, `USECASES.md`, and `RELEASE.md` to `0.9.51` references and current validator counts.
- **TOC:**
  - Updated addon list title to `isiLive`.
  - TOC version bumped to `0.9.51`.

## 2026-02-25 - Documentation Sync (Workspace)
- **Rules/Contract Coverage:**
  - Added rule-detail blocks for rule numbers `26-31` in `RULES_LOGIC.md` with deterministic test mappings.
  - Clarified portal-slot contract wording: once sorted, portal icon slot order stays fixed (no re-sorting/switching).
- **Runtime Behavior Docs Sync:**
  - Synced docs to current hidden-mode behavior: queue/sync processing is suspended while UI is hidden.
  - Confirmed auto-open transition behavior remains active for group join and key end (`CHALLENGE_MODE_COMPLETED`/`RESET`).
  - Added deterministic coverage note for key-end auto-show while grouped.
- **Validation:**
  - `tools/validate_usecases.lua` now validates `131` deterministic scenarios across 18 modules (all passing).
- **Documentation:**
  - Updated `README.md`, `ARCHITECTURE.md`, `USECASES.md`, and `RELEASE.md` to current validator count and hidden-mode semantics.

## 2026-02-25 - Version 0.9.50
- **Season Scope Policy:**
  - Removed the hard **Season-3-only lock** from project rules/docs.
  - Season scope is now open and controlled via `SeasonData.ACTIVE_SEASON_ID`.
  - Current active season remains `tww_s3`; next target season is `midnight_s1` (prepared/inactive until IDs are complete).
- **UI Visibility Behavior:**
  - `CTRL+F9` now allows opening and closing the main window in every state, including combat.
  - Center notice visibility no longer defers opening during combat; close and open both apply immediately.
  - Removed legacy `pendingCenterNoticeVisible` regen-apply path (`PLAYER_REGEN_ENABLED`) and related dead wiring.
  - Removed legacy main-frame pending-visibility regen path (`GetPendingVisible/getPendingMainFrameVisible`) and dead wiring.
  - Main window and center notice drag remain available in all states, including combat.
  - Center notice position is no longer persisted; each open resets to screen center.
  - Deduplicated red close-button creation/style via shared `UICommon.CreateRedCloseButton`.
  - `CHALLENGE_MODE_START` auto-hide behavior remains unchanged.
  - Hidden-mode processing behavior remains unchanged (non-essential processing still halted while UI is hidden).
  - Combat runtime gate now suppresses non-essential event processing while in combat and only keeps essential event paths active.
- **Documentation Sync:**
  - Updated `RULES.md`, `RELEASE.md`, `USECASES.md`, and `README.md` to reflect the season-open workflow.
  - Synced `README.md`, `ARCHITECTURE.md`, `USECASES.md`, `RELEASE.md`, and `TODO.md` to `0.9.50` references.
- **Validation:**
  - `tools/validate_usecases.lua` validates `126` deterministic scenarios across 18 modules (all passing).
  - Split oversized test registration blocks in queue/UI/teleport scenario modules so no function exceeds the `lua_metrics_check` hard limit (`320` lines).
  - Refactored remaining oversized runtime/test validator functions (`commands`, `queue`, `ui`, `test_mode`, rules validator, scenario suites) so `lua_metrics_check` now reports **no metric warnings**.
- TOC version bumped to `0.9.50`.

## 2026-02-24 - Version 0.9.49
- **Sync/Refresh Key Visibility Fix:**
  - Fixed refresh handshake race where remote member keys could disappear after one client used `Refresh`.
  - `HELLO` messages that require `ACK` now also trigger an immediate forced own-key snapshot send.
  - This repopulates peer key caches deterministically after refresh-driven sync resets and prevents one-sided key visibility flip-flops between clients.
- **Validation:**
  - Extended deterministic event-handler sync coverage to assert `HELLO -> ACK -> forced KEY snapshot` behavior.
  - `tools/validate_usecases.lua` remains at `117` deterministic scenarios across 18 modules (all passing).
- **Documentation:**
  - Synced `README.md`, `ARCHITECTURE.md`, `USECASES.md`, `RELEASE.md`, and `TODO.md` to `0.9.49` references.
- TOC version bumped to `0.9.49`.

## 2026-02-24 - Version 0.9.48
- **Queue Join Dedup Reliability:**
  - Switched grouped queue-announce deduplication to stable queue source IDs instead of display-text signatures.
  - Stable dedup IDs now prioritize `applicationID`, then `searchResultID`, then `listingID`.
  - Queue capture now forwards stable source metadata into `QueueFlow` pending state and grouped announce signature generation.
  - This suppresses duplicate grouped announce output when group/dungeon text changes but the underlying queue event is unchanged.
- **Validation:**
  - Added deterministic coverage for:
    - stable search-result dedup ID forwarding in queue capture
    - stable application dedup ID forwarding in application scans
    - grouped announce deduplication by stable queue event ID in QueueFlow
  - `tools/validate_usecases.lua` now runs `117` deterministic scenarios across 18 modules (all passing).
- **Documentation:**
  - Synced `README.md`, `ARCHITECTURE.md`, `USECASES.md`, `RELEASE.md`, and `TODO.md` to `0.9.48` references and validator count updates.
- TOC version bumped to `0.9.48`.

## 2026-02-23 - Version 0.9.47
- **Key Mapping Reliability (S3):**
  - Added explicit challenge-map alias mapping for S3 key IDs:
    - `378 -> 2287` (Halls of Atonement)
    - `391 -> 2441` (Tazavesh: Streets of Wonder)
    - `392 -> 2441` (Tazavesh: So'leah's Gambit)
    - `499 -> 2649` (Priory of the Sacred Flame)
    - `503 -> 2660` (Ara-Kara, City of Echoes)
    - `505 -> 2662` (The Dawnbreaker)
    - `525 -> 2773` (Operation: Floodgate)
    - `542 -> 2830` (Eco-Dome Al'dani)
  - Incoming addon sync payloads (`KEY:<mapID>:<level>`) are now normalized through the same alias mapping before roster storage/rendering.
  - Fixed roster key column fallback-to-number behavior for known aliased challenge-map IDs.
- **Roster/UI Fixes:**
  - Fixed solo/manual-open path to always keep the local player row (including own key snapshot) visible.
  - Increased minimum frame height and moved status line further down to avoid overlap with bottom controls.
  - Removed `[fullsync]` roster marker override; detected `isiLive` users now consistently render the blue `<3` marker only.
- **Share Keys Output:**
  - `Share Keys` now sends one chat line per member key instead of one aggregated line.
  - Share action now keeps existing visible key values stable and only backfills missing key data from sync cache.
- **Validation/Docs:**
  - Added deterministic teleport/sync coverage for challenge-map alias normalization.
  - `tools/validate_usecases.lua` now runs `114` deterministic scenarios across 18 modules (all passing).
  - Synced `README.md`, `ARCHITECTURE.md`, `USECASES.md`, and `RELEASE.md` to current runtime behavior and versioning.
- TOC version bumped to `0.9.47`.

## 2026-02-23 - Version 0.9.46
- **Queue Join UX:**
  - Removed queue-join center notice popup (`Joined from queue ...`) from grouped announce flow.
  - Queue-join feedback now uses chat summary + invite hint only.
- **Runtime Logging:**
  - Added runtime log persistence controller (`isiLive_runtime_log.lua`) storing entries in `IsiLiveDB.runtimeLog`.
  - Added slash command `/isilive log [on|off|start|stop|status|clear|tail [n]]` for runtime log control.
  - Added runtime-log command regression coverage to deterministic command scenarios.
- **Documentation:**
  - Synced `README.md`, `ARCHITECTURE.md`, and `RELEASE.md` with runtime log command support and validator coverage updates.
  - Updated deterministic usecase gate references from `111` to `113` scenarios.
- TOC version bumped to `0.9.46`.

## 2026-02-23 - Version 0.9.45
- **Runtime Reliability:**
  - Removed duplicate forced key-sync payload behavior on `PLAYER_ENTERING_WORLD` by keeping immediate send forced and delayed follow-up send non-forced.
  - Added deterministic regression coverage to ensure no duplicate forced key snapshot sends in the entering-world flow.
  - Extended bottom status line with target dungeon context (`Target Dungeon: <Name> [+Level]`) sourced from resolved queue/joined-key state.
  - Unified target-map resolution across status/enter-check/highlight flows to a strict resolver path (no hidden API bypass in highlight map resolving).
  - Removed negative activity resolver cache locking so late-arriving activity map payloads can recover to concrete map/spell targets.
- **Code Cleanup:**
  - Removed dead helper `Teleport.AddActivityToTeleportCache` from `isiLive_teleport.lua`.
  - Removed unused season alias `SeasonData.MAP_SHORT_CODES_DE` from `isiLive_season_data.lua`.
  - Removed redundant early `OnEvent` script binding in bootstrap/main setup; runtime gate remains the single `OnEvent` owner.
- **Validation:**
  - Added contract source file `RULES_LOGIC.md` for enforceable usecase/rule definitions with `active|draft|deprecated|disabled` status.
  - Added rules-logic validator (`tools/validate_rules_logic.lua`, `tools/rules_logic_validator.lua`) and integrated it into `tools/validate_usecases.lua`.
  - `tools/validate_usecases.lua` now runs 111 deterministic scenarios across 18 modules (all passing).
  - Local hook `.githooks/pre-commit` now includes deterministic usecase/rules validation.
  - CI workflow `Lua Check` now includes deterministic usecase/rules validation.
- **Documentation:**
  - Synced `README.md`, `ARCHITECTURE.md`, `USECASES.md`, `RELEASE.md`, `RULES.md`, and `TODO.md` to `0.9.45` references and current runtime behavior.
  - Updated `RULES_LOGIC.md` to append-only rule maintenance (no forced sorting) and expanded draft usecase rule coverage; aligned `AGENTS.md` workflow accordingly.
- TOC version bumped to `0.9.45`.

## 2026-02-22 - Version 0.9.44
- **Season Data Maintainability:**
  - Refactored season configuration into centralized structured data in `isiLive_season_data.lua` with explicit `ACTIVE_SEASON_ID`.
  - Added season helper API (`GetSeasonConfig`, `GetMapToTeleport`, `GetShortCodes`, `GetDungeonShortCode`) so future season swaps only require one data-file update.
  - Updated teleport runtime to consume SeasonData helper API instead of hardwired map/shortcode tables.
- **Localized Dungeon Short Codes:**
  - Added locale-aware roster key short-code resolution by active addon locale.
  - `deDE` short-code overrides now render as:
    - `PSF -> PRI`
    - `EDA -> BIO`
    - `HOA -> HDS`
    - `OFG -> SCH`
    - `AK -> AK`
    - `DB -> MB`
    - `TAZ -> TAZ`
  - `enUS` short codes remain unchanged.
- **Validation:**
  - Added deterministic coverage for locale-specific short-code resolution and SeasonData central helper fallback behavior.
  - `tools/validate_usecases.lua` now runs 103 deterministic scenarios across 18 modules (all passing).
- **Documentation:**
  - Synced `README.md`, `ARCHITECTURE.md`, `USECASES.md`, `RELEASE.md`, and `TODO.md` to `0.9.44` references and current runtime behavior.
- TOC version bumped to `0.9.44`.

## 2026-02-22 - Version 0.9.43
- **Combat-Safe Secure UI:**
  - Fixed `ADDON_ACTION_BLOCKED` errors from center-notice teleport secure button updates in combat (`Hide`, `EnableMouse`, and anchor changes).
  - Center-notice teleport button visibility, mouse state, and anchor updates are now deferred while in combat and applied safely after combat ends.
- **Validation:**
  - `tools/validate_usecases.lua` remains at 102 deterministic scenarios across 18 modules (all passing).
- **Documentation:**
  - Synced `README.md`, `ARCHITECTURE.md`, `USECASES.md`, `RELEASE.md`, `RULES.md`, and `TODO.md` to `0.9.43` references and current runtime behavior.
- TOC version bumped to `0.9.43`.

## 2026-02-22 - Version 0.9.42
- **Queue/Highlight Reliability:**
  - Added negative-status race protection so fresh pending queue invite context is not cleared too early by follow-up declined/canceled application events, preventing missing initial dungeon detection/highlight immediately after join.
- **RIO Delta Reliability:**
  - Hidden-state event gate now allows `CHALLENGE_MODE_COMPLETED`/`CHALLENGE_MODE_RESET`, so delayed post-run refresh and delta activation still run even when the main window is currently hidden.
- **Packaging:**
  - Excluded the logo asset from CurseForge packaging via `.pkgmeta` ignore list.
- **Validation:**
  - `tools/validate_usecases.lua` remains at 102 deterministic scenarios across 18 modules (all passing).
- **Documentation:**
  - Synced `README.md`, `ARCHITECTURE.md`, `USECASES.md`, `RELEASE.md`, `RULES.md`, and `TODO.md` to `0.9.42` references and current runtime behavior.
- TOC version bumped to `0.9.42`.

## 2026-02-22 - Version 0.9.41
- **RIO Delta Reliability:**
  - Added two short post-run follow-up refresh passes after the first successful delayed refresh so late RIO backend updates no longer stay stuck at temporary `(+0)` until manual refresh.
- **Validation:**
  - Added deterministic regression coverage for successful delayed refresh follow-up scheduling.
  - `tools/validate_usecases.lua` now runs 102 deterministic scenarios across 18 modules.
- **Documentation:**
  - Synced `README.md`, `ARCHITECTURE.md`, `USECASES.md`, `RELEASE.md`, `RULES.md`, and `TODO.md` to `0.9.41` references and current post-run refresh behavior.
- TOC version bumped to `0.9.41`.

## 2026-02-22 - Version 0.9.40
- **RIO Delta Fixes:**
  - Fixed runtime wiring regression where `enableRioDeltaDisplay` was not forwarded into event-handler setup, which could keep delta display permanently disabled.
  - Delta display activation now happens after the delayed post-run refresh path (`CHALLENGE_MODE_COMPLETED`/`RESET`) instead of immediately at event time.
  - Added retry logic for delayed post-run refresh attempts when refresh is still temporarily blocked by active challenge-state timing.
  - Roster delta callback now receives the current roster unit token, so live unit RIO can be used during delta rendering.
- **Validation:**
  - Added deterministic regression coverage for delayed delta activation, retry behavior, and unit-aware delta rendering.
  - `tools/validate_usecases.lua` now runs 101 deterministic scenarios across 18 modules.
- **Documentation:**
  - Synced `README.md`, `ARCHITECTURE.md`, `USECASES.md`, `RELEASE.md`, `RULES.md`, and `TODO.md` to `0.9.40` references and current RIO-delta runtime behavior.
- TOC version bumped to `0.9.40`.

## 2026-02-21 - Version 0.9.39
- **Maintenance:**
  - Documentation/version sync only (no gameplay behavior changes).
  - Updated `README.md`, `ARCHITECTURE.md`, `USECASES.md`, `RELEASE.md`, and `TODO.md` version/tag references to `0.9.39`.
- TOC version bumped to `0.9.39`.

## 2026-02-21 - Version 0.9.38
- **RIO Delta Display:**
  - Added challenge-start RIO baseline capture and per-player roster delta rendering as prefix `(+X)RIO`.
  - Delta is now strictly non-negative (`+0` minimum; never minus).
  - Added deterministic test-mode preview for visible positive RIO deltas in `/isilive test` and `/isilive testall`.
- **UI & Labels:**
  - Increased RIO-column spacing and adjusted right-side header/button offsets to avoid overlap with the management panel.
  - Reduced language-column width to reclaim horizontal table space.
  - Updated right-side column labels to `M+Managment` and `M+Travel`.
- **Validation:**
  - Added deterministic roster and event-handler coverage for RIO baseline/delta rules.
  - `tools/validate_usecases.lua` now runs 98 deterministic scenarios across 18 modules.
- **Documentation:**
  - Synced `README.md`, `ARCHITECTURE.md`, `USECASES.md`, `RELEASE.md`, `RULES.md`, and `TODO.md` to current runtime/UI behavior.
- TOC version bumped to `0.9.38`.

## 2026-02-21 - Version 0.9.37
- **Deterministic Target Resolution:**
  - Switched queue/highlight/teleport resolution to strict `activityID -> mapID -> spellID` flow.
  - Removed dungeon-name/token fallback resolution and removed first-candidate guessing when no concrete activity map exists.
  - Added explicit queue target `mapID` runtime state (`latestQueueMapID`) and map-first target clear behavior.
  - Fixed late queue-capture race: if LFG target data arrives after `GROUP_ROSTER_UPDATE`, grouped members now still get queue chat/notice/teleport preview immediately.
  - Added grouped announce deduplication for identical queue targets to prevent repeated chat spam and center-notice timer resets.
- **UI & UX:**
  - Fixed teleport-grid button layering to inherit main-frame strata/level instead of forcing `HIGH` (issue #14).
  - Fixed non-Mythic warning flow to also trigger on in-instance difficulty switches (for example `Normal -> Heroic`) and recognize heroic fallback difficulty ID `174`.
  - Widened roster `Key` column and disabled key-text wrapping so `SHORT +LEVEL` values stay on one line.
  - Updated `CTRL+F9` behavior: frame can always be closed in combat, but opening via hotkey is blocked during combat.
- **Validation:**
  - Added regression coverage for strict no-guess queue activity selection, strict no-name teleport resolution, unresolved-map caching, TeleportUI strata sync, and non-Mythic status transitions.
  - `tools/validate_usecases.lua` now runs 94 deterministic scenarios.
- TOC version bumped to `0.9.37`.

## 2026-02-20 - Version 0.9.36
- **Code Quality:**
  - Simplified `EventUtils.IsNegativeApplicationStatusEvent` by removing redundant explicit checks for arg positions 2 and 3; unified into a single loop that checks all arguments uniformly (both strings and numbers at every position).
  - Normalized inline comments in `isiLive_teleport.lua` from German to English for codebase-wide language consistency.
  - Wrapped `Guards.Validate` in `pcall` with user-friendly red error message instead of crashing the entire addon on load failures.
- **Combat Safety:**
  - Fixed `OnDragStop` handlers on main frame and drag handle to always call `StopMovingOrSizing()` before the combat guard, preventing the frame from getting stuck in a moving state if combat starts mid-drag.
  - Removed inconsistent `RightButton` drag registration from main frame; drag is now `LeftButton`-only, matching the drag handle behavior.
- **UI & UX:**
  - Added localized chat notification when addon hides due to raid group (>5 members), so the user understands why the window disappeared.
  - Fixed `deDE` `LOADED_HINT` to be fully German instead of mixed English/German.
- **Test Coverage:**
  - Added 40 new offline test scenarios across 9 new modules (Group, EventUtils, Locale, Sync, Guards, TestMode, LeaderWatch, Refresh, Commands), bringing total from 42 to 82.
- TOC version bumped to `0.9.36`.

## 2026-02-20 - Version 0.9.35
- **Teleport/Queue Detection:**
  - Fixed localized queue target resolution for Eco-Dome Al'dani variants (for example `Biokuppel Al'dani`) when activity map data is missing or incomplete.
  - Added localized fallback token matching so queue join notices and active teleport highlight resolve correctly for Biokuppel listings.
- **Runtime Defaults:**
  - Re-enabled former `DM Reset` behavior as hardcoded default: on `CHALLENGE_MODE_START`, Blizzard damage meter sessions are reset when `C_DamageMeter` APIs are available.
  - Enforced `advancedCombatLogging` as hardcoded `ON` (`1`) across startup/challenge lifecycle events.
- **Validation:**
  - Added deterministic regression tests for localized Eco-Dome name fallback and activity-name fallback without `mapID`.
  - Added deterministic regression tests for hardcoded advanced-combat-log enforcement and challenge-start damage-meter reset.
  - `tools/validate_usecases.lua` now runs 42 scenarios.

## 2026-02-19 - Version 0.9.34
- **Highlight Stability:**
  - Fixed queue-target clear regression on negative `LFG_LIST_APPLICATION_STATUS_UPDATED` events while already grouped (for example when the 5th member joins and other applications get declined).
  - Active teleport highlight now remains stable across full-group transition follow-up events.
- **Validation:**
  - Added deterministic regression coverage in `testmodul/isilive_test_scenarios_event_handlers.lua`.
  - `tools/validate_usecases.lua` now runs 38 scenarios.

## 2026-02-19 - Version 0.9.33
- **UI & UX:**
  - Increased main frame minimum height from `200` to `212` so the `Share Keys` / `Keys teilen` button no longer sits on the bottom edge.
  - Renamed the right-side countdown stop action label from `Countdown Cancel` to `Countdown 0` (behavior remains `DoCountdown(0)`).
- **Combat Safety:**
  - Fixed protected-call drag taint (`ADDON_ACTION_BLOCKED: isiLiveMainFrame:StartMoving()`) by skipping frame drag start/stop while in combat lockdown.
- **Documentation:**
  - Synced `README.md`, `ARCHITECTURE.md`, `USECASES.md`, `RULES.md`, `RELEASE.md`, and `TODO.md` with current UI labels and combat-drag behavior.

## 2026-02-19 - Version 0.9.32
- **Architecture & Stability:**
  - Fixed global variable leaks in realm data; moved to `addonTable.RealmData`.
  - Added combat-queue for teleport buttons to ensure updates apply correctly after combat ends (`PLAYER_REGEN_ENABLED`).
  - Fixed roster panel overflow in raid groups by strictly limiting display to 5 rows.
  - Improved realm language detection for same-realm players.
  - Fixed center-notice teleport resolution to also work with `activityID` when dungeon name is missing.
  - Added deterministic shared-teleport map handling (e.g. both Tazavesh wings on one portcast).
  - Fixed active-listing highlight suppression for shared portcasts by prioritizing exact activity map matching before shared-spell suppression.
  - Harmonized active-listing detection in event handlers to avoid premature queue-target clears when API variants omit explicit `active` booleans.
  - Hardened queue activity-name lookups with protected `GetActivityInfoTable` access.
- **UI & UX:**
  - Share Keys button is now disabled/dimmed if no keys are available to share.
  - Fixed typos in German localization (`Managment` -> `Management`, `Groupenfuehrer` -> `Gruppenfuehrer`).
- **Code Quality:**
  - reduced oversized function blocks across controller/UI modules
  - `tools/lua_metrics_check.lua` reports no function-size warnings at default thresholds (`warn>120`, `hard>320`)
  - added deterministic runtime usecase validator `tools/validate_usecases.lua` for queue/highlight/cooldown edge-case gates
  - validator refactored to modular offline simulation suite (`testmodul/isilive_test_*.lua`) with 37 deterministic scenarios
  - expanded CurseForge packaging ignore list in `.pkgmeta` to exclude non-runtime docs/dev assets (`tools/`, `testmodul/`, architecture/usecase docs, repo metadata)
  - wired `README.md` + `RELEASE.md` quality gates to include `lua tools/validate_usecases.lua`
  - removed 7 unused localization keys from `isiLive_texts.lua`:
    - `INVITE_HINT_TITLE`
    - `LEAD_TRANSFERRED`
    - `TELEPORT_ERR_NO_TARGET`
    - `TELEPORT_ERR_COMBAT`
    - `TELEPORT_ERR_FAILED`
    - `TIMEOUT_INSPECT`
    - `TOOLTIP_TELEPORT_NO_TARGET`

## 2026-02-18 - Version 0.9.31
- Runtime stability fixes:
  - fixed combat taint/protected-call error (`ADDON_ACTION_BLOCKED: Button:SetScale()`) by skipping teleport-button scale resets during combat and applying the reset after `PLAYER_REGEN_ENABLED`
  - fixed invite dungeon detection ambiguity by preferring concrete teleport-mapped activity IDs over generic dungeon candidates in queue application parsing (fixes `Halls of Atonement` / `Hallen der Suehne` mis-detection after invite)
  - updated right control headers: former `M+ Management` renamed to `M+travel`, former `Lead Options` renamed to `M+ Managment`
  - replaced obsolete `DM Reset` toggle with a leader-only `Countdown Cancel` action (`DoCountdown(0)`) and moved `Refresh` to the bottom slot in the right control stack
  - replaced the tiny key-speaker icon with a full-size `Share Keys` button below `Refresh` in the right control stack
- Documentation sync:
  - added `ARCHITECTURE.md` (runtime architecture + ASCII UI sketch)
  - added `USECASES.md` (invite/highlight/cooldown use-case plan)
  - updated `README.md`, `RELEASE.md`, `RULES.md`, and `TODO.md` to `0.9.31` baseline/examples
- TOC version bumped to `0.9.31`.

## 2026-02-18 - Version 0.9.30
- **Key Announce:** Added a speaker button to the roster panel to post all known party keys to chat.
- **Season Data:** Extracted season data (dungeons, teleports) into `isiLive_season_data.lua` for easier updates.
- **Season Data:** Updated/locked dungeon list and teleports for **Season 3 (S3)**.
- **UI Behavior:** The main window is now "frozen" instead of strictly hidden during M+ runs; it can be opened via hotkey (`CTRL+F9`) to view cached data.
- **Auto-Refresh:** Added automatic group data refresh (iLvl/RIO) 5 seconds after dungeon completion.
- **UI Layout:** Moved addon version label from bottom-right to top-right in the main window.
- **Teleport UI:** Active dungeon target now shows the yellow border even if the teleport spell is not yet learned (locked), improving clarity for alts.
- **Teleport:** Optimized caching for teleport spell lookups (Tazavesh tokens).
- **Teleport Mapping:** Added support for multiple mapped spell IDs per dungeon map (for variant/faction-safe resolution).
- **Teleport Highlight:** Fixed self-hosted key highlight resolution for localized listing names (e.g. `Morgenbringer`) and solo-host active listings.
- **Teleport Highlight:** Highlight now turns off once the player is already inside the matching target dungeon.
- **Sync:** Improved realm name normalization for stricter sync matching.
- **Fixes:**
  - **Combat Safety:** Added retry logic for teleport buttons loaded during combat to prevent broken states.
  - Fixed queue invite detection when `pendingStatus` is returned as `0`.
  - Fixed persistence of debug settings (`qdebug`) and global variable usage (`issecretvalue`).
- TOC version bumped to `0.9.30`.

## 2026-02-17 - Version 0.9.29
- Maintenance/CI release (no gameplay behavior changes):
  - fixed `main` quality-gate stability by aligning CI runtime dependencies for Lua metrics check
  - CI now installs `luafilesystem` and loads LuaRocks paths before running `tools/lua_metrics_check.lua`
  - CI metrics hard limit for function size adjusted to `360` to match current modularization baseline and avoid false release blocking
- Code quality cleanup:
  - applied formatting-only normalization in touched modules
  - removed one unused local (`groupController`) in `isiLive.lua`
- Documentation/release metadata sync:
  - updated `README.md` and `RELEASE.md` examples to `0.9.29`
- TOC version bumped to `0.9.29`.

## 2026-02-17 - Version 0.9.28
- Runtime stability fixes:
  - fixed `QueueFlow` initialization-order regression (`updateUI` is now assigned before controller wiring), resolving startup error `QueueFlow requires updateUI`
  - fixed combat taint/protected-call error (`ADDON_ACTION_BLOCKED: Button:Enable()`) by removing runtime `Enable()` calls from secure teleport button update path
- Tooling/editor diagnostics:
  - fixed LuaLS false-positive diagnostics in `tools/lua_metrics_check.lua` for CLI globals (`require`, `io`, `os`) in standalone metrics script
- Documentation/release metadata sync:
  - updated `README.md` and `RELEASE.md` examples to `0.9.28`
- TOC version bumped to `0.9.28`.

## 2026-02-17 - Version 0.9.27
- Big refactoring and modularization pass:
  - split large runtime responsibilities into dedicated modules (wiring/bootstrap, event handlers, group lifecycle, queue flow, bindings, helpers)
- Refactor stabilization after modularization:
  - fixed runtime event-gate wiring regression where `dispatch` could be `nil` during setup (`onEvent` is now accepted as dispatch fallback)
- Release safety hardening:
  - stable CurseForge trigger restricted to `isiLive_release_*`
  - manual release trigger now requires confirmation and validates that the provided tag exists
  - added isolated pre-release workflow for `isiLive_alpha_*` and `isiLive_beta_*`
- Documentation and release metadata sync:
  - updated README/RELEASE examples and tag samples to `0.9.27`
- TOC version bumped to `0.9.27`.

## 2026-02-16 - Version 0.9.26
- Pre-key key visibility rework:
  - removed bottom key header line and replaced it with a new roster column `Key`
  - key values now render as `DungeonShortcut +Level` (for example `DB +14`)
  - added Season 3 dungeon short codes for key display (`PSF`, `EDA`, `HOA`, `OFG`, `AK`, `TAZ`, `DB`)
- Group key sync (isiLive users only):
  - added addon sync payload `KEY:<mapID>:<level>` and per-player key cache
  - roster key values are populated from sync data when party members also run `isiLive`
  - key sync/send remains visibility-bound; no key sync processing in hidden/sleep mode
  - clears known-isiLive runtime markers when the group is fully left, so next group starts with clean detection state
- UI layout adjustments:
  - widened main frame to reduce table overlap with right-side controls
  - widened `Key` column and shifted `iLvl`/`RIO` positions to avoid line wrapping/collision
- Teleport highlight stability:
  - fixed edge-case where highlight could stop around full-group transition (for example when the 5th member joins)
  - active-listing resolver now falls back to known queue/join target when listing activity cannot be resolved transiently
- Spec column readability:
  - added short-label mapping for long localized spec names (for example `Wiederherstellung -> Resto`, `Vergeltung -> Retri`)
- Active key indicator in roster:
  - added red key text marker for the active joined key (invite/join flow)
  - strict ownership rule: marker is only shown when key owner can be identified unambiguously from synced group keys
  - hosting flow is excluded from automatic ownership assumptions (active listing no longer implies own key owner)
- Refresh behavior:
  - `Refresh` now performs a full forced refresh for group data (`Spec/iLvl/RIO` + `hasIsiLive` + key sync state)
  - refresh flow now forces fresh `HELLO` and `KEY` sync broadcasts and resets stale per-roster sync hints before rebuilding
- TOC version bumped to `0.9.26`.

## 2026-02-15 - Version 0.9.25
- CI/release follow-up:
  - fixed Lua quality-gate regressions on `main` (Luacheck + StyLua compliance)
  - no gameplay/feature behavior changes; release refresh for stable packaging
- TOC version bumped to `0.9.25`.

## 2026-02-15 - Version 0.9.24
- Teleport highlight behavior:
  - activation is now strict: highlight appears only after actual group join or while actively hosting your own listing
  - no pre-invite/pre-group highlight anymore
- Teleport reliability:
  - hardened cooldown handling against secret values from `C_Spell.GetSpellCooldown`
  - fixed queue secret-table errors in `isiLive_queue.lua`
  - improved Tazavesh resolution with normalized/localized name matching
- Queue/LFG flow:
  - block `LFG_LIST_*` processing during active Mythic+ key
  - prevent "Joined from queue" message when player is leader/host
  - allow dungeon-category queue capture even when no teleport spell is mapped
- Debug cleanup:
  - simplified `tpdebug` output to actionable fields only (removed raw dumps and debug-side cache mutation)
  - added `/isilive qdebug tail [n]` (default `20`, clamped `1..100`)
  - removed stale debug state (`latestQueueCapturedAt`) and dead debug branching
- TOC version bumped to `0.9.24`.

## 2026-02-15 - Version 0.9.23
- Bugfixes:
  - Fixed teleport highlight disappearing when the group becomes full (listing removal caused queue info to be overwritten with empty data).
  - Fixed Lua error `attempt to compare local 'enabled' (a secret boolean value)` in `GetTeleportCooldownRemaining` by sanitizing secret values from `C_Spell.GetSpellCooldown`.
  - Fixed multiple Lua errors `table expected, got secret` in `isiLive_queue.lua` (including `ExtractApplicationSnapshot`).
  - Debug cleanup: reduced `tpdebug` output to actionable fields only (removed raw table dumps and debug-side cache mutation).
  - Added `qdebug tail [n]` (clamped to 1..100, default 20) to inspect recent queue debug entries without log spam.
  - Optimization: Completely block LFG event processing (`LFG_LIST_*`) when a Mythic+ key is active to prevent unnecessary background work and potential taint/secret errors.
  - Added robust teleport resolution for Tazavesh (Streets/Gambit) via normalized name matching (handles split wings sharing one teleport, including localized map names).
  - Fixed "Joined from queue" message appearing when hosting your own key (added leader check).
  - Fixed missing notifications for dungeons without mapped teleport spells (e.g. leveling dungeons or unmapped IDs).
    - Queue capture now validates activities via WoW API category (Dungeon/M+) instead of relying solely on teleport spell existence.
- Teleport highlight:
  - made visual pulse stronger/faster and overlay more dominant (scale 1.2, faster loop, stronger color)
  - highlight activation is now strict to real context only: shown only after actual group join or while actively hosting your own listing
- TOC version bumped to `0.9.23`.

## 2026-02-15 - Version 0.9.22
- Test mode flow:
  - added dedicated `ExitTestMode()` handling to leave test mode with a consistent cleanup/reset path
- TOC version bumped to `0.9.22`.

## 2026-02-14 - Version 0.9.21
- Queue capture reliability:
  - added `LFG_LIST_SEARCH_RESULT_UPDATED` event handling to trigger `CaptureQueueJoinCandidate(...)`
  - registered `LFG_LIST_SEARCH_RESULT_UPDATED` on the main frame and test-mode event gate allowlist
- TOC version bumped to `0.9.21`.

## 2026-02-14 - Version 0.9.20
- Queue capture cleanup:
  - removed redundant single-table fallback parsing in `Queue.CaptureQueueJoinFromApplications`
  - queue application status/pending extraction now uses the direct values path only
- TOC version bumped to `0.9.20`.

## 2026-02-14 - Version 0.9.19
- UI/Mainframe refresh:
  - title now shows `isiLive` branding.
  - added native-style backdrop and subtle header separator
  - roster rows now support hover highlight
  - roster name column now includes role icons (tank/healer/damager)
- Teleport/queue behavior:
  - replaced per-frame `OnUpdate` pulse with `AnimationGroup`-based active target animation
  - active teleport fallback now checks current challenge map ID
  - improved reset behavior when leaving test mode and after challenge start
- Data/role handling:
  - added player-role fallback via specialization role when assigned group role is unavailable
  - test roster generation now adapts party composition to the local player role
- Event gating:
  - test mode now supports configurable allowed events (`allowInTestMode`) and keeps required events active
- Packaging/docs:
  - added `TODO.md` and excluded it from CurseForge package via `.pkgmeta`
  - README title updated with rename note
- TOC version bumped to `0.9.19`.

## 2026-02-13 - Version 0.9.18
- Teleport target/highlight:
  - updated all 8 M+ dungeon mapIDs for Season 3 in `SEASON3_MAP_TO_TELEPORT` table:
    * Priory of Sacred Flame: 2649
    * Eco-Dome Al'dani: 2830
    * Halls of Atonement: 2287
    * Operation: Floodgate: 2773
    * Ara-Kara, City of Echoes: 2660
    * Tazavesh: Streets of Wonder / So'leah's Gambit: 2441
    * The Dawnbreaker: 2662
  - removed redundant name-based fallback logic and kept strict mapID/activityID-based resolution
  - removed unused local variable in teleport activity resolver
- Queue/event processing cleanup:
  - removed duplicate application rescans in `LFG_LIST_APPLICATION_STATUS_UPDATED` and `LFG_LIST_ACTIVE_ENTRY_UPDATE`
  - queue apply scan now runs through the existing queue capture path only (single source of truth)
- UX/Warnings:
  - non-Mythic dungeon warning changed from persistent to 120-second timeout
  - non-Mythic warning now auto-hides immediately upon dungeon exit
- TOC version bumped to `0.9.18`.

## 2026-02-13 - Version 0.9.17
- Release update after post-release architecture and repo-hardening changes.
- Repo quality/tooling hardening:
  - added `.gitattributes` to enforce LF line endings for core file types
  - added optional `.githooks/pre-commit` checks (`stylua --check`, `luacheck`)
  - finalized strict lint/format setup (`StyLua`, `Luacheck`, CI quality gate)
- Documentation refresh:
  - updated README with modular file inventory (including TOC/ui/teleport/status/units/demo modules)
  - added developer setup, CI quality gate, and optional git hook usage notes
- Bumped TOC version to `0.9.17`.

## 2026-02-12 - Version 0.9.16
- Fixed LuaLS `redundant-parameter` diagnostics after modularization by aligning fallback callback signatures with real call sites in:
  - `isiLive.lua`
  - `isiLive_commands.lua`
  - `isiLive_demo.lua`
  - `isiLive_events.lua`
  - `isiLive_notice.lua`
  - `isiLive_status.lua`
- Corrected status-controller method calls to consistent dot-style invocation where functions are defined without implicit `self`.
- Bumped TOC version to `0.9.16`.

## 2026-02-12 - Version 0.9.15
- Continued modularization and moved additional logic out of `isiLive.lua` into:
  - `isiLive_units.lua`
  - `isiLive_demo.lua`
  - `isiLive_status.lua`
- Added repo-wide Lua quality tooling and config:
  - `.stylua.toml`
  - `.luacheckrc` (strict globals + WoW API allowlist)
  - `.editorconfig`
  - `.styluaignore`
  - `.vscode/tasks.json`
- Hardened CI quality gate:
  - pinned `StyLua` check in workflow
  - integrated `luacheck` and syntax checks
  - fixed `stylua-action` auth handling (`github.token`)
  - excluded `.luarocks` noise from CI lint/syntax scope
  - fixed `luacheck` CLI arg parsing (`--` separator)
- Standardized release/tag naming to `isiLive_*` and aligned workflow/docs.
- Added `RELEASE.md` runbook for the repeatable release flow.
- Bumped TOC version to `0.9.15`.

## 2026-02-12 - Version 0.9.14
- Modularized addon architecture into dedicated files:
  - `isiLive_locale.lua`
  - `isiLive_sync.lua`
  - `isiLive_queue.lua`
  - `isiLive_inspect.lua`
  - `isiLive_roster.lua`
  - `isiLive_events.lua`
  - `isiLive_commands.lua`
- Added addon-presence roster markers:
  - blue `<3` marker for detected `isiLive` users
  - green `[fullsync]` marker when all visible roster members are detected as `isiLive` users
- Updated test/dummy roster so the local player is always used as `player` entry in test modes.
- Added bottom-right version line in the main window (`V.x.y.z`) sourced from TOC metadata.
- Updated load chat message to: `isiLive: Loaded Version x.x.x.x Press STRG+F9 to open`.
- Kept hidden-window behavior strict with minimal transition path: no non-essential processing while hidden; hotkey/binding flow remains active; small-group `GROUP_ROSTER_UPDATE` still allows auto-open.
- Fixed Lua diagnostics `redundant-parameter` warnings in modular fallbacks by aligning fallback function signatures with call sites.

## 2026-02-12 - Version 0.9.13
- Release-only republish to force a unique CurseForge package artifact after `.11` and `.12` pointed to the same commit.
- No code changes compared to `0.9.12`.

## 2026-02-12 - Version 0.9.12
- Fixed main window drag reliability:
  - window now supports direct left/right mouse drag
  - top drag handle is forced above overlays to prevent mouse event blocking
- Fixed combat lockdown taint error (`ADDON_ACTION_BLOCKED`) by deferring protected `isiLiveMainFrame:SetHeight()` updates until `PLAYER_REGEN_ENABLED`.

## 2026-02-12 - Version 0.9.11
- Fixed queue-teleport highlight reliability so invite-detected dungeon targets are applied immediately and remain stable across follow-up LFG status events.
- Prioritized invite/queue dungeon target for M+ teleport highlighting regardless of current player location/instance.
- Added dedicated mapID-to-teleport helper flow and tightened activity selection to prefer teleport-mappable activities.
- Fixed local function declaration order regression (`ResolveSeason3TeleportSpellIDByMapID`) that could cause a nil-call error in teleport cache building.
- Removed dead code in `isiLive.lua` (`GetUnitID`, unused `mplusActiveSpellID`, inactive duplicate dungeon line updater).

## 2026-02-12 - Version 0.9.10
- Reduced Lua diagnostics noise in `isiLive.lua`:
  - removed deprecated spell-known fallbacks
  - added safer dynamic field/global access (`rawget`) for Blizzard runtime-provided fields/frames
  - improved analyzer-friendly typing around teleport icon handling and rating summary reads
- Restored Russian realm entries in `realm_language_data.lua` with proper UTF-8 names and normalized keys.
- Removed corrupted `????` placeholder keys that produced duplicate-index diagnostics.

## 2026-02-12 - Version 0.9.9
- Reworked right-side M+ teleport UI from single button to multi-button grid (one button per mapped dungeon teleport).
- Added active-target highlight for the currently resolved teleport (strong pulse/glow + tinted overlay).
- Improved active teleport target resolution with fallbacks:
  - queue-derived dungeon/activity
  - active challenge map
  - current instance map/name
- Fixed non-Mythic entry warning timing by adding delayed confirmation to avoid false positives during instance-load transitions.
- Updated roster language display to include `flag + 2-letter code` (for example `DE`, `FR`).

## 2026-02-12 - Version 0.9.8
- Added inspect-based specialization (`Spec`) detection for party members and integrated it into the group table.
- Added a new `Spec` column before `Name`, with class-color rendering and localization support.
- Updated roster table alignment and labels:
  - `Name` column is left-aligned
  - German header `Flagge` renamed to `Sprache`
- Added non-Mythic dungeon entry warning as a center-screen notice with 30-second duration.
- Improved center notice interaction:
  - left-click drag to move
  - right-click to dismiss immediately
  - persisted position restore across reload/login
- Updated dummy/test roster values and sample specs to match current test expectations.

## 2026-02-11 - Version 0.9.2
- Improved dungeon teleport secure-button compatibility by expanding secure spell attributes for reliable click-cast behavior.
- Fixed hidden-state queue handling so `LFG_LIST_APPLICATION_STATUS_UPDATED` is still captured and dungeon targets do not stick to test/default values.
- Added automated Lua quality checks via GitHub Actions (`.github/workflows/lua-check.yml`).
- Added README quality-check section with local `luacheck` command.
- Added explicit versioning rules (`MAJOR.MINOR.PATCH`) in `RULES.md`.

## 2026-02-11 - Version 0.9.1
- Added server-language detection based on Blizzard EU realm status data (`realm_language_data.lua`) with normalized realm-name fallback.
- Replaced server/language text in roster with country flag icons (`DE/EN/FR/ES/IT/PT/RU`).
- Added `/isilive tpdebug` to inspect current teleport target resolution, secure attributes, known/cooldown state, and button visibility.
- Added `/isilive tptest` to force a dummy teleport target (`The Dawnbreaker`) for isolated teleport-button testing.
- Reduced chat noise by suppressing inspect-timeout chat lines (`Timeout beim Inspizieren von ...`).
- Improved hidden-frame behavior:
  - fully stops scan/processing work while the main window is hidden
  - keeps required transition handling so auto-open on small-group join still works
  - keeps auto-hide behavior on Mythic+ key start

## 2026-02-11 - Version 0.9
- Upgraded the center queue teleport control from text button to spell icon button (secure cast button with spell texture).
- Center queue notice now lasts 20 seconds by default.
- Center queue notice frame is now movable and persists position via `IsiLiveDB.centerNoticePosition`.
- Improved test preview dungeon for teleport testing (`/isilive testall`) by switching dummy dungeon to `The Dawnbreaker`.
- Added a new right-side column `M+ Management`.
- Added a second dungeon teleport icon button under `M+ Management`, synchronized with the latest queued invite dungeon/activity.
- Expanded teleport state handling for both teleport buttons:
  - no target dungeon yet
  - locked teleport (not learned)
  - combat lockdown blocked setup
- Fixed teleport icon/button setup for WoW `12.0.1` secure-cast behavior, including reliable icon visibility and click-cast updates.
- Added teleport cooldown detection with live button state updates and remaining time display in `HH:MM`.
- Fixed `OnEvent` nil-call regression by routing manual event refreshes through the frame's registered event script.
- Fixed protected frame visibility calls during combat by deferring blocked show/hide updates until `PLAYER_REGEN_ENABLED`.
- Improved main window dragging behavior to avoid click conflicts with UI controls while keeping the frame movable.

## 2026-02-10 - Version 0.7
- Fixed queue dungeon resolution to avoid wrong dungeon names from mixed numeric event args.
- Dungeon lookup now prefers the actual `searchResult` activity mapping for invite/application updates.
- Prevented cross-application dungeon carry-over unless the group name matches.
- Improved hotkey robustness for `CTRL+F9` / `CTRL+ALT+F9`:
  - watchdog now re-applies bindings safely after combat if a rebind was blocked in combat lockdown
  - binding click buttons now listen on key down/up and execute on key down for more reliable triggering
- Improved queue join chat visibility by adding white separator lines before and after the message block.
- Added right-side dungeon difficulty indicator (`Normal`/`Heroic`/`Mythic`) with live updates on instance/difficulty changes and key-readiness color hint.
- Added a center notice teleport button for queued invites:
  - maps Season 3 dungeons to their teleport spell IDs (based on spell-database compilation data)
  - enables direct click-cast when the dungeon teleport is known
  - shows locked state when teleport is not unlocked yet and handles combat lockdown safely

## 2026-02-09 - Version 0.7
- Set addon compatibility policy to WoW `12.0+` only.
- Improved hotkey handling and rebinding reliability for:
  - `CTRL+F9` (window toggle)
  - `CTRL+ALT+F9` (test mode toggle)
- Added full test preview mode (`/isilive testall`) and improved test visuals.
- Added right-side control area updates:
  - `Readycheck`
  - `Countdown10`
  - `Refresh` (force re-read of all iLvl/RIO values)
  - `DM Reset: ON/OFF` (auto-reset Blizzard Damage Meter on key start)
- Added persistent DM reset setting via `IsiLiveDB.autoDamageMeterReset`.
- Added and improved queue join detection:
  - chat output
  - 10-second center message
  - invite hint panel near invite UI (with fallback positioning)
- Improved roster behavior when reopening the window and refreshing while list is empty.
- Implemented stable role sorting (`Tank -> Healer -> Damager`) and reduced row jumping.
- Reworked table layout and alignment:
  - fixed columns (`Name`, `iLvl`, `RIO`)
  - name truncation to 10 characters
  - spacing and visual tuning around lead options/buttons
- Added lead transfer center notification and warning sound.
- Added status line with `Lead`, `M+`, and addon runtime state.
- Fixed multiple scope/order Lua errors (`UpdateUI`, `UpdateLeaderButtons`, `OnEvent`).
- Standardized visible addon strings to English output.
- Added runtime language switching via `/isilive lang [en|de]` with persisted setting in `IsiLiveDB.locale`.
