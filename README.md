# isiLive

**A Mythic+ group helper for World of Warcraft.** One window that shows who has which key, how the group is doing, and what matters during a run.

- **For:** M+ players in pre-made groups and LFG runs
- **WoW version:** `12.0+` (Midnight) only
- **Current version:** `0.9.252`
- **Active season:** `midnight_s1` — 8 dungeons (Wing, MT, NPX, MC, AA, POS, SOT, SR)

---

## What it does

When you join a group, isiLive opens a single window with everything you want to see before and during a key:

- Who is in the group, their spec, item level, Raider.IO rating, and keystone
- One-click access to all 8 season dungeon portals, with live cooldowns
- Who can interrupt, and whose kick is still on cooldown
- Battle Res charges and Bloodlust cooldown during a run
- The M+ timer with `+3 / +2 / +1` cutoffs live
- Forces percentage with a live pull-prediction bar and combat-end refresh so completed pulls are reflected immediately
- Default-on **forces overlay on every enemy nameplate** during a key — shows what each individual mob contributes plus the verified remaining count needed to finish enemy forces
- Forces info on the **mouseover tooltip** for any mob in a key

Everything syncs automatically between group members who run isiLive — no manual import, no `/say` spam.

---

## Install

1. Download from **CurseForge** or **Wago**, or drop the folder `isiLive/` into `World of Warcraft/_retail_/Interface/AddOns/`.
2. Start the game. The window opens automatically the next time you join a 5-player group.

No setup required. Open the settings via **Escape → AddOns → isiLive** if you want to change language, sounds, or auto-open behavior.

---

## Main window

The window opens automatically when you join a group and closes when you leave. You can also open or close it yourself:

- **`Ctrl + F9`** — toggle the window
- **Red X** in the top-right corner — close it
- **Lock icon** in the top-right — prevents dragging so the window doesn't move by accident
- Drag the title bar to move the window. The position is remembered.

### Layouts

The window comes in four layouts. Click the button in the title bar to switch:

| Button | Layout | What you get |
|---|---|---|
| **M+** | Compact main | Full roster + all M+ tools stacked (default) |
| **M** | Main | Roster + tools in a classic stacked view |
| **H** | Horizontal | Slim tool strip — just the essentials |
| **V** | Vertical | Small palette with markers and group tools |

The selected layout is remembered across sessions.

---

## The roster

Columns in order: **Spec · Name · Lang · Key · iLvl · RIO · DPS · Kick**

- **Spec** — role-sorted: tanks first, then healers, then DPS
- **Lang** — spoken-language flag for the player
- **Key** — keystone and level, short code (e.g. `MT +14`, `DAWN+12`). Red if this player owns the key you joined for.
- **iLvl** — equipped item level
- **RIO** — current Raider.IO score. After a run, a green `(+X)` shows the gain: `(+12)3521`
- **DPS** — overall DPS from the last dungeon, read from Blizzard's in-game damage meter
- **Kick** — green `ready`, red seconds on cooldown, or `-` if the spec has no interrupt. Heal specs without interrupt (Holy Paladin, Mistweaver Monk, Restoration Druid, Discipline / Holy Priest) correctly show `-` instead of a stale cooldown. **Hover** over the cell to see extra interrupts the player has via talents (e.g. Protection Paladin's Avenger's Shield) — synced live across the group through isiLive.

### Markers next to names

- **Blue heart** — this player also runs isiLive
- **Crown** — this player is the group leader
- **Ghost row** (greyed out) — a player who left the group. Kept visible until the group dissolves or you reload, so you can still see who was there after a wipe or dungeon reset.
- **Right-click a row** to whisper that player

### Ready check

During a ready check, the row background changes color: **green** for ready, **red** for declined or no answer, **yellow** (with sandglass) for still waiting. After the ready check ends, ready/declined colors stay visible for 20 seconds so you can glance at who responded how.

---

## Tools in the main window

### M+ Utility Row

- **BR** — Battle Res charges and cooldown with icon
- **Lust** — Bloodlust/Heroism cooldown with icon and remaining time
- **M+ Timer** — `+3 / +2 / +1` cutoffs counting down live, plus death penalty

### Killtracker (Enemy Forces)

A bottom bar that shows your kill-count percentage:

- **Green** < 80%, **Yellow** < 95%, **Red** ≥ 95%
- After a verified LFG invite target announce, the bar shows the target dungeon and key level right-aligned until the key starts
- During an active key, the verified dungeon name stays visible on the progress bar as a left-aligned outlined label with a subtle contrast background
- During a pull, a light-blue segment on the right shows **how much the current pull will add** (`+X.XX%`) — so you can see mid-pull whether it's enough
- When combat ends, the tracker refreshes Blizzard's live scenario progress immediately, so the last pull is counted before the next pull or boss engagement

### Teleport Grid

All 8 season dungeon portals in one place:

- **Icon + short code** when ready (e.g. `MT`, `DAWN`)
- **Cooldown timer** when on cooldown, normalized to the current portal cooldown cycle
- **Highlight** when a portal becomes available
- **Highlight + gold border** on the right portal when you accept an LFG invite or create your own LFG listing for a dungeon

### Markers (for everyone)

Eight world-marker buttons: **Square, Triangle, Diamond, Cross, Star, Circle, Moon, Skull**. Anyone in the group can use them — not just the leader.

### Role icons = one-click marks

Click the **tank icon** in a roster row to put a **blue square** on that player. Click the **healer icon** for a **green triangle**. Works for everyone, not only the leader.

### Group leader buttons

Only enabled when you are the leader:
- **Ready Check**
- **Countdown 10s / Countdown 0s** (pull timers)

### Share Keys

Posts everyone's keystone in group chat — yours first, then other isiLive users reply with their own. The button has a 30-second cooldown after a real local share or successful peer request; receiving clients only lock their button when they actually post their own key.

### Re-Sync

Forces a fresh sync round. Use it if someone's iLvl or key looks stuck. Asks compatible LibKeystone addons for their keys too. 10-second cooldown.

---

## Mythic+ features

### Forces on mob tooltips

When you hover a mob during a key, the tooltip gains a line:

```
+3 progress (1.25% of 240)
```

That tells you how much that mob is worth and what fraction of the dungeon-total it represents — handy to decide whether a pull gets you over a threshold. Localized in all 8 supported languages (DE: `+3 Fortschritt (1,25% von 240)`).

The percent is computed from the bundled MDT-synced forces DB, **not** from Blizzard's `GetUnitCriteriaProgressValues` API directly. That API in 12.0+ protected contexts can return cumulative dungeon progress instead of the per-mob contribution; reading from the DB is deterministic and immune to that drift.

### Forces overlay on enemy nameplates

Default-on text over every hostile unit's nameplate during a key; Settings -> Nameplates can disable it or hide the remaining-needed suffix.

```
1.16%
```

Configurable: percent toggle, font size 8-24, position around the nameplate (LEFT/RIGHT/TOP/BOTTOM). Same DB-based source as the tooltip — deterministic mob contribution, never the cumulative progress.

Plater / Platynator users: a soft warning is shown in Settings if either is loaded — both addons can already display M+ forces on nameplates via their own scripts, so you can disable isiLive's overlay there if you prefer to avoid duplication.

### Battle Res / Bloodlust chat announce

During an active key, every time someone in the group casts a Battle Res or starts Bloodlust, isiLive posts a short line:

```
Alice used BR
Bob started Bloodlust
```

You can turn either announce off in the settings. Non-isiLive group members won't see the message — it's shared only between isiLive users.

### Pre-key group view

When you get an LFG invite, the matching portal highlights and the chat tells you which dungeon and level you joined — so you know before loading in. The bottom M+ killtracker mirrors that verified target as a right-aligned dungeon + key-level label until the key starts.

### Ghost rows after wipes / reloads

If the group breaks up or someone disconnects, their data stays visible as a greyed-out row. You can still see what spec/key they had. Joining a new group clears the old ghosts.

---

## Hotkeys

| Key | Action |
|---|---|
| `Ctrl + F9` | Toggle the main window |
| `Ctrl + Alt + F9` | Toggle demo mode (for testing without a group) |

## Slash commands

```
/isilive start        — enable the addon
/isilive stop         — disable (no processing, no sync)
/isilive lock         — lock window position
/isilive unlock       — unlock window position
/isilive resetui      — recenter window and reset scale + opacity (asks for confirmation)
/isilive testall      — full preview mode with dummy data
/isilive log on|off   — enable/disable runtime trace log
/isilive log tail 50  — print the last 50 log entries
/isilive log clear    — clear the log buffer
```

## Settings

Open via **Escape → AddOns → isiLive**. Everything takes effect immediately.

- **General** — language, startup auto-show, minimap button
- **Display** — UI scale, background opacity, default layout (M+, M, H, V), lock main frame position, reset UI
- **Behavior** — addon sync, auto-show/hide triggers (show on login, auto-open on M+ queue, auto-open on key end, auto-close on key start, auto-close on leaving the group), lock main frame position, fade in combat, raid behavior status
- **Sounds** — lead transfer, full group, incoming summon, Battle Res, Bloodlust
- **Nameplates** — enable forces overlay, font size, position, percent toggle
- **Chat Announcements** — announce Battle Res / announce Bloodlust
- **Administrative** — queue debug log, runtime log (both reset on reload, for support), plus dedicated **Clear Queue Debug Log** / **Clear Runtime Log** buttons in the panel for one-click log purge without using the slash command

### Auto-open defaults

- Open on joining a group — **on**
- Open when a key ends — **on**
- Close automatically when the key starts — **off** (separate toggle)
- Close automatically when leaving the group — **off** (separate toggle)
- Show on login/reload — **on** (except in raid groups)
- Raid groups hide the window completely and pause all background processing

---

## FAQ

**Why don't I see DPS after a run?**
DPS is read from Blizzard's own damage meter. If Blizzard hasn't finalized the session yet, isiLive briefly retries. If the damage meter has no data for a player (e.g. late joiner), the DPS column stays empty rather than showing a guess.

**Why is the Key column empty for another player?**
They either don't have a keystone, or they don't have isiLive or a LibKeystone-compatible addon to share it.

**Why did my portal highlight disappear?**
You're already inside the dungeon, or the LFG queue was cancelled, or the group dissolved — any of those clears the highlight.

**Why is the main window gone in a raid?**
Raid groups (6+ members) are a hard-off state: UI hidden, background sync off. It comes back when the group drops to party size.

**Why did the chat announce not fire?**
BR/Lust announce only fires during an active M+ key. Also check the Chat Announcements toggles in the settings.

---

## Links

- **Source code:** [github.com/byi77/isilive](https://github.com/byi77/isilive)
- **Bug reports / feature requests:** GitHub issues
- **Technical documentation:** [`docs/`](docs/)

Also published on CurseForge and Wago — search for *isiLive*.
