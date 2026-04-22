#!/usr/bin/env bash
# Source this from Git Bash / MSYS to expose luarocks-installed Lua
# modules (luacheck, luacov, luafilesystem) to the current shell.
#
# Usage:
#   source tools/env.sh
#   luacheck --version
#   lua -lluacov tools/validate_usecases.lua
#
# Background: On Windows, `luarocks path` emits cmd.exe-style
# `SET NAME=VALUE` lines instead of shell-compatible `export NAME=VALUE`.
# Running `eval "$(luarocks path)"` in Git Bash both fails to parse the
# SET syntax AND overwrites PATH with the cmd.exe-formatted version,
# which breaks core Unix tools like head/sed/grep. We narrow the scope
# to the two variables Lua actually needs (LUA_PATH, LUA_CPATH) and
# rewrite SET to export on the fly.

if ! command -v luarocks >/dev/null 2>&1; then
  echo "tools/env.sh: luarocks not found on PATH" >&2
  return 1 2>/dev/null || exit 1
fi

eval "$(luarocks path \
  | grep -E '^SET (LUA_PATH|LUA_CPATH)=' \
  | sed -E 's|^SET ([A-Z_]+)=(.*)$|export \1="\2"|')"
