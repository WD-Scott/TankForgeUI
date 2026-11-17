#!/bin/sh
# Installs the offline test toolchain into .lua/ (git-ignored): Lua 5.1 (the game's
# version), LuaRocks, busted, luacheck and luacov. Safe to run again.
# Needs Python 3 for hererocks. Then: scripts/test.sh
set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
TREE="$REPO/.lua"

if [ ! -x "$TREE/bin/lua" ]; then
    if ! python3 -c "import hererocks" 2>/dev/null; then
        python3 -m pip install --user --quiet hererocks
    fi
    # No readline: the tests need no REPL, and CI images lack its headers.
    python3 -m hererocks "$TREE" -l5.1 -r3.8.0 --no-readline
fi

for rock in busted luacheck luacov; do
    if ! "$TREE/bin/luarocks" show "$rock" >/dev/null 2>&1; then
        "$TREE/bin/luarocks" install "$rock"
    fi
done

echo "Toolchain ready in $TREE. Run scripts/test.sh"
