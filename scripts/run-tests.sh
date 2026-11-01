#!/usr/bin/env bash
# Runs the addon tests (Lua 5.1, headless WoW 3.3.5a API stub).
#   scripts/run-tests.sh
#   ROMANCE_WIRE=/path/to/mod-romance/build-tests/romance_wire scripts/run-tests.sh   # + C++ <-> Lua interop
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
command -v lua5.1 >/dev/null || { echo "lua5.1 is required (apt install lua5.1)"; exit 1; }
echo "== syntax"
find AzerothRomance -name '*.lua' -print0 | xargs -0 -n1 luac5.1 -p
echo "== addon tests"
lua5.1 tests/test_addon.lua AzerothRomance
if [ -n "${ROMANCE_WIRE:-}" ]; then
  echo "== C++ <-> Lua wire interop"
  lua5.1 tests/test_interop.lua AzerothRomance "$ROMANCE_WIRE"
fi
echo "All selected test suites passed."
