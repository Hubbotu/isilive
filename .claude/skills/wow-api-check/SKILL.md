---
name: wow-api-check
description: Scans the isiLive codebase for WoW 12.0+ (Midnight) API violations and known addon-restriction anti-patterns. Use when the user adds combat-log / event-registration / chat / sound / keystone / secure-code features, on code review of such changes, or when asked to "wow api check" / "12.0 compliance". Source of truth: https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes plus the rules in CLAUDE.md.
---

# isiLive WoW 12.0 API Compliance Check

Grep-based lint for the recurring addon-restriction traps documented in CLAUDE.md. Reports only; the fix always needs human judgment.

## Checks

Run each check from repo root. Exclude `libs/` (vendored libraries we don't own) and `testmodul/` (harness, not runtime) unless a hit specifically concerns a test stub.

### 1. Removed / forbidden combat-log APIs

Grep for:
- `COMBAT_LOG_EVENT_UNFILTERED` — event is removed; `RegisterEvent` raises `ADDON_ACTION_FORBIDDEN`.
- `CombatLogGetCurrentEventInfo` — not callable from tainted code.

Preferred replacement: `UNIT_SPELLCAST_SUCCEEDED` (see [game/isiLive_combat_events.lua](game/isiLive_combat_events.lua) for the BR/Lust template — caster-only, no target).

### 2. Dynamic RegisterEvent from protected dispatch

Grep for `RegisterEvent` calls. Flag any that live inside a handler for `CHALLENGE_MODE_START`, `CHALLENGE_MODE_COMPLETED`, `ENCOUNTER_START`, or any other event dispatched by protected code. Registration must happen in the main chunk or on `PLAYER_LOGIN`, never re-entering from a protected dispatch.

### 3. Removed keystone API

Grep for `C_MythicPlus.GetOwnedKeystoneLink` — the function is `nil` in retail even though `C_MythicPlus` table still exists. Manually constructed `|Hkeystone:...|h` links are server-rejected. Only reliable source: bag scan via `C_Container.GetContainerItemLink` for item ID `180653`.

### 4. Sound channel must be SFX, not Master

Grep for `PlaySoundFile`. Every call must use `"SFX"` as channel argument. Flag `"Master"` or missing channel arg.

### 5. Chat color-wrapped brackets

Grep for `SendChatMessage` calls and inspect adjacent / surrounding string construction. Flag any `|cff` + `[` + `]` + `|r` pattern that is NOT inside a real `|H...|h...|h` hyperlink — the server silently drops those messages.

Likely false-positive sources: printing to the local chat frame (not the server). Distinguish `SendChatMessage` from `DEFAULT_CHAT_FRAME:AddMessage` / `print` — only the former hits the server filter.

### 6. Tooltip sync-version wording (regression guard)

Per CLAUDE.md: the tooltip line is `"Client version: %s"` / `"Client-Version: %s"`, with no `(p%d)` protocol suffix. Grep for:
- `"Peer version"` / `"Peer-Version"` — must not reappear.
- `protocolVersion` in [ui/isiLive_roster_tooltip.lua](ui/isiLive_roster_tooltip.lua) — branch must not reappear.

### 7. Secret-values nil guards

When reading data in protected contexts (inside combat / M+ key dispatchers), the API may mask return values. Look at new code touching protected dispatchers and confirm `nil` / `0` are handled — no hard assumption that the API returns populated data. Heuristic only; report as "review recommended", not "violation".

## Reporting

For each check, list `file:line` hits as markdown links. Group by check number.

- **Pass**: `wow-api-check: PASS (no 12.0 restriction violations found)`.
- **Fail**: one section per failing check with every hit cited. Do not rank severity — every hit is worth a human look.

Do NOT auto-remove `COMBAT_LOG_EVENT_UNFILTERED` registrations or rewrite combat code without user confirmation — the replacement depends on the feature's intent (caster tracking vs. damage events vs. aura pulses all need different patterns).
