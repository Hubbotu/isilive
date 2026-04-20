---
name: locale-audit
description: Audits isiLive locale files for consistency across all 8 supported languages (enUS, deDE, frFR, esES, ptBR, itIT, ruRU, trTR). Use when the user adds a new language, renames a text key, touches `locale/isiLive_texts.lua` / `isiLive_languages.lua` / `isiLive_locale.lua`, or asks to "locale audit" / "check translations" / "prüfe locales". Goes beyond the existing drift tool by checking button-label length limits and language-set coverage.
---

# isiLive Locale Audit

Verifies the three locale sources of truth stay in sync. Covers what `tools/check_locale_drift.lua` does NOT.

## Sources of truth

1. [locale/isiLive_languages.lua](locale/isiLive_languages.lua) — `Languages.SUPPORTED` list (canonical).
2. [locale/isiLive_texts.lua](locale/isiLive_texts.lua) — per-locale string tables (`enUS`, `deDE`, …).
3. [locale/isiLive_locale.lua](locale/isiLive_locale.lua) — `LANGUAGE_NAME_BY_LOCALE` display names.

## Steps

### 1. Run the existing drift tool (keys + `%s`/`%d` placeholder counts)

```
lua tools/check_locale_drift.lua
```

Exit 0 = clean. Exit 1 = drift — report each issue verbatim.

### 2. Button-label length check (CLAUDE.md rule: ≤ 14 chars)

Grep `locale/isiLive_texts.lua` for all `BTN_*` keys across every locale table. Flag any string value > 14 visible chars.

- Strip `|cff......` / `|r` color codes before counting — they don't render as glyphs.
- Ignore leading/trailing whitespace.
- Also flag `*_SHORT` / `*_hModeText` variants > 10 chars (those exist specifically because the main key was too long — the short variant must be genuinely short).

Report shape:
```
BTN_READYCHECK (deDE): "Bereit-Abfrage" = 14 chars [OK]
BTN_REFRESH (ruRU): "Обновить список" = 15 chars [OVER LIMIT]
```

### 3. Languages.SUPPORTED ↔ texts coverage

For every entry in `Languages.SUPPORTED` (tag field), verify:
- A locale table `locales.<tag>` exists in `isiLive_texts.lua`.
- A `LANG_SET_<TAG_UPPER>` key exists in every locale table (e.g. `LANG_SET_DEDE`).
- `LANG_USAGE` and `HELP_LANG` strings in every locale mention the new tag's alias (grep for one existing alias like `"de"` — new tag should appear alongside).

### 4. LANGUAGE_NAME_BY_LOCALE coverage

For every supported tag, verify `LANGUAGE_NAME_BY_LOCALE[<anyLocale>][<tag>]` exists in `isiLive_locale.lua`. The drift tool catches missing keys, but double-check after adding a new language — it's the fourth of the five steps in CLAUDE.md that's easy to forget.

## Reporting

- **Pass**: `locale-audit: PASS (drift clean, button labels within limit, Languages.SUPPORTED fully covered in texts + locale)`.
- **Fail**: one section per failing check, in the order above. Cite file:line for each issue using markdown links so the user can jump.

Do NOT auto-fix translations. Report only — the user decides the wording.
