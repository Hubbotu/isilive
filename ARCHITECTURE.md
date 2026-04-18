# isiLive Architecture

## Overview

isiLive is a WoW retail addon (Interface 120001) for M+ dungeon and group management. It follows a **Composition Root / Dependency Injection** pattern: all module wiring happens in `factory/`, keeping business logic modules free of direct circular dependencies.

## Layer Structure

```
isiLive/
├── core/       Shared utilities — no WoW API, no game logic
├── locale/     Language data and text tables
├── game/       Thin WoW API wrappers (pcall-guarded)
├── logic/      Business logic (sync, queue, inspect, keysync, …)
├── ui/         UI components (roster, panel, settings, …)
├── factory/    Composition root — wires all modules together
└── testmodul/  Test suite (51 scenario files)
```

**Load order** is defined in `isiLive.toc` and enforced by the `factory/` implicit-dependency map in `isilive_test_harness.lua`.

## Key Modules

### core/

| File | Responsibility |
|------|---------------|
| `isiLive_guards.lua` | Validates 120+ required module exports at startup |
| `isiLive_bootstrap.lua` | Event-gating, slash-command registry |
| `isiLive_runtime_state.lua` | State machine: IDLE → ACTIVE → PAUSED → STOPPED |
| `isiLive_runtime_log.lua` | Ring-buffer trace log (delegates to `log_buffer`) |
| `isiLive_context_helpers.lua` | WoW API facade with layered fallbacks |
| `isiLive_string_utils.lua` | Shared normalization (realm name, whitespace) |

### logic/

| File | Responsibility |
|------|---------------|
| `isiLive_sync.lua` | Peer-to-peer addon messaging; module-level singleton state (see note below) |
| `isiLive_keysync.lua` | Owns keystone + stats sync send/receive controller |
| `isiLive_queue.lua` | LFG application-flow state extraction |
| `isiLive_queue_flow.lua` | Higher-level queue flow orchestration |
| `isiLive_inspect.lua` | Player inspection with caching (ilvl, rio, spec) |
| `isiLive_group.lua` | Group roster management |
| `isiLive_highlight.lua` | LFG-list highlighting logic |
| `isiLive_events.lua` + `event_handlers_*.lua` | Event dispatch and gating |

### factory/

| File | Responsibility |
|------|---------------|
| `isiLive_factory.lua` | Top-level composition root, called on PLAYER_LOGIN |
| `isiLive_controller_wiring.lua` | Constructs all controllers with injected dependencies |
| `isiLive_controller_init.lua` | Per-controller initialization hooks |
| `isiLive_config_builders.lua` | Builds typed config objects passed to controllers |
| `isiLive_frame_bridge.lua` | Bridges WoW frame events to controller callbacks |

## Sync Module — Singleton State

`logic/isiLive_sync.lua` intentionally uses module-level (not controller-scoped) state:

- **Why:** Cooldown timestamps and peer-data caches (`keyInfoByPlayerKey`, etc.) must survive controller re-creations within the same session.
- **Reset contract:** `Sync.ClearKnownUsers()` resets ALL mutable state — called by `isiLive_controller_wiring.lua` and `isiLive_keysync.lua` on group disband.
- **Payload validation:** Incoming `CHAT_MSG_ADDON` messages are validated: non-string or `#message > 255` are silently dropped before any parsing.

## Queue Module — State Machine

`logic/isiLive_queue.lua` extracts normalized snapshots from `C_LFGList.GetApplicationInfo` results via a four-step pipeline in `ExtractApplicationSnapshot`:

1. **SeedSnapshotFromSingleStruct** — single-table call form: parse all fields upfront
2. **AccumulateStatusFlags** — check positional `appStatus` arg for invite/accepted keywords
3. **ScanApplicationTupleValues** — iterate all positional args; resolve activityID, accumulate IDs
4. **ApplySingleStructFallback** — last-resort: scan `activityIDs` list if unresolved

`updatePendingQueueJoin()` is called only when `isInviteLike == true` and `pendingStatus == nil`.

## Secret Values

WoW wraps certain API return values in "secret" objects that cannot be read directly. All numeric fields from WoW APIs are checked with `issecretvalue()` before use:

```lua
if _G.issecretvalue and _G.issecretvalue(value) then
  value = safeDefault
end
```

This pattern is applied in `spell_utils.lua`, `queue.lua`, `cd_tracker.lua`, and `sync.lua`.

## Protocol Versioning and Compatibility

The sync protocol uses version 2 (`ISILIVE_SYNC_PROTOCOL_VERSION` in `logic/isiLive_sync.lua`).

### Version Negotiation

- The `HELLO` payload includes the sender's `protocolVersion` in field 3 (`HELLO:version:protoVer:timestamp:source`).
- Any version >= 1 is currently accepted — there is no rejection for old peers.
- `Sync.GetProtocolVersion()` exposes the local version for outgoing payloads.
- **Upgrade path:** A future version 3 would add a negotiation phase inside `SendHello`/`ProcessAddonMessage` before payload format changes take effect.

### Payload Validation Pipeline

All incoming `CHAT_MSG_ADDON` messages pass through this chain before any data is stored:

| Step | Check | On failure |
|------|-------|-----------|
| 1 | `prefix == "ISILIVE"` or `"LibKS"` | `return nil` |
| 2 | `type(sender) == "string" and sender ~= ""` | `return nil` |
| 3 | `type(message) == "string" and #message > 0 and #message <= 255` | `return nil` |
| 4 | Type prefix match (`KEY:`, `STATS:`, …) | payload type silently skipped |
| 5 | `SplitPayload` returns at most 10 fields | excess fields truncated |
| 6 | Field-level `tonumber()` / boolean coercion | nil fields use safe defaults or clear the entry |

### Known Message Formats

| Payload | Format | Max fields |
|---------|--------|-----------|
| `HELLO` | `HELLO:version:protoVer:ts:source` | 5 |
| `ACK` | `ACK:version` | 2 |
| `KEY` | `KEY:mapID:level:ts:source` | 5 |
| `STATS` | `STATS:specID:ilvl:rio:ts:source` | 6 |
| `DPS` | `DPS:dps:ts:source` | 4 |
| `LOC` | `LOC:mapID:ts:source` | 4 |
| `TARGET` | `TARGET:mapID:level:ts:source` | 5 |
| `KICK` | `KICK:state:remain` | 3 |
| `REQSYNC` | `REQSYNC` | 1 |
| `SHAREKEYS` | `SHAREKEYS` | 1 |
| LibKS data | `level,mapID,rio` | — |
| LibKS request | `R` | — |

---

## Error Handling and Recovery

### Silent Drops

The following conditions result in a silent `nil` return with no log entry:

- Unrecognized prefix
- Empty or oversized message (`#message == 0` or `> 255`)
- Empty sender string
- LibKS payload on a non-PARTY channel
- LibKS payload with negative level or mapID

### Graceful Degradation

Malformed-but-accepted payloads are normalized to safe defaults:

- Missing numeric fields → `tonumber()` returns `nil` → downstream normalizer substitutes 0 or clears entry
- Invalid `mapID`/`level` (0) → `SetPlayerKeyInfo` clears the stored entry rather than storing garbage
- Missing `source` field → defaults to `"local"`
- Missing `capturedAt` → falls back to `GetSyncTimestamp()` at receive time

### Cooldown Recovery

- Send cooldowns (`lastIsiLiveKeyAt`, etc.) are never extended on failure — the client retries on the next relevant event.
- `ClearKnownUsers()` resets **all** cooldown timestamps and dedup trackers, not just the lookup tables. This is intentional: after a group disband the first send of any payload type should always go through immediately.

### Failure Modes Reference

| Condition | Location | Result |
|-----------|----------|--------|
| `#message > 255` | `ProcessAddonMessage` | silent drop |
| Negative level/mapID in LibKS | `ProcessLibKeystoneMessage` | `return nil` |
| `realm == ""` with no `-` in name | `NormalizePlayerKey` | falls back to `GetRealmName()` |
| `hasKick` not explicit boolean | `SetPlayerKickInfo` | `return false` |
| All stats fields invalid | `SetPlayerStatsInfo` | entry cleared, `return hadValue` |
| `SplitPayload` > 10 fields | `SplitPayload` | excess fields truncated silently |

---

## Test Suite

Tests live in `testmodul/` and are registered in `tools/usecase_scenarios.lua`. Each scenario file exports `function(test, ctx)`.

The harness (`isilive_test_harness.lua`) provides:
- `ctx.load_modules(files)` — loads modules into a fresh isolated addonTable
- `ctx.with_globals(stubs, fn)` — temporarily overrides `_G` keys for the duration of `fn`
- `ctx.assert` — assertion library (`Equal`, `True`, `False`, `Nil`, `NotNil`)

**Coverage estimates:**
- Business logic (sync, queue, inspect, keysync): ~85%
- UI rendering (roster, panel): ~50%
- Integration (factory + runtime): ~55%
- Stress / large-group scenarios: in `testmodul/isilive_test_scenarios_stress.lua`

## Module Interaction Diagram

```
PLAYER_LOGIN
    │
    ▼
factory.lua ──► controller_wiring.lua
                    │
                    ├──► Sync (singleton)
                    ├──► KeySync controller
                    ├──► Group controller
                    ├──► Inspect controller
                    ├──► Queue / QueueFlow
                    ├──► Highlight controller
                    ├──► Refresh controller
                    ├──► UI (RosterPanel, Settings, Notice)
                    └──► EventHandlers (wired to Bootstrap)

CHAT_MSG_ADDON ──► EventHandlers ──► Sync.ProcessAddonMessage
                                         │
                                         ├──► KeySync.ApplyKnownKeyToRosterEntry
                                         └──► UI refresh trigger

LFG_LIST_APPLICATION_STATUS_UPDATED ──► Queue.CaptureQueueJoinCandidate
                                             │
                                             └──► updatePendingQueueJoin ──► QueueFlow
```
