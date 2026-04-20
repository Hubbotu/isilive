---
name: release-check
description: Runs the full isiLive local CI gate before a commit or release. Use when the user asks to "release-check", "ship check", "pre-commit check", before any `release(vX.Y.Z)` commit, or when verifying that stylua/luacheck/metrics/locale-drift/usecases/rules-logic all pass. Also verifies TOC version + changelog consistency when a release commit is being prepared.
---

# isiLive Release Check

One-shot quality gate that mirrors the GitHub Actions CI workflow. Run this before every release commit and before pushing non-trivial changes.

## What to do

1. Run the local CI preflight from repo root:

   ```
   powershell -NoProfile -File tools/validate_ci_local.ps1
   ```

   This covers: stylua format check, luacheck, Lua syntax, metrics (file ≤3200 lines, function ≤420 lines), locale drift, deterministic usecase + rules-logic validation.

2. If the user is preparing a **release commit** (commit message starts with `release(vX.Y.Z)` or the user said "bump + release"), additionally verify version consistency:
   - `isiLive.toc` — both `## Title: isiLive vX.Y.Z` and `## Version: X.Y.Z` match.
   - `CHANGELOG_RELEASE.md` — `Current release: \`X.Y.Z\`.` line matches.
   - `docs/CHANGELOG.md` — top-most entry header is the new version.

3. Check `git status` for any unexpected unstaged files.

## Reporting

- **Pass**: one-line summary `release-check: PASS (stylua, luacheck, syntax, metrics, locale, usecases, rules)`. If release-commit mode, append `TOC/CHANGELOG aligned at vX.Y.Z`.
- **Fail**: do NOT just dump the PowerShell output. Extract the failing step name and the specific error lines, and report in this shape:

  ```
  release-check: FAIL at <step-name>
  <offending file:line>: <error>
  ...
  ```

  Then stop and wait for the user — do not attempt to auto-fix without confirmation.

## Notes

- Use `powershell` (Windows), not `pwsh` — the user's machine has the 5.x built-in.
- Do NOT skip hooks with `--no-verify` even if the user is in a hurry. If the gate fails, the fix is real.
- `ISILIVE_MAX_FILE_LINES=3200` and `ISILIVE_MAX_FUNCTION_LINES=420` are set by the script — do not override.
- The script runs from repo root (uses `Push-Location`), so invoke it from anywhere inside the repo.
