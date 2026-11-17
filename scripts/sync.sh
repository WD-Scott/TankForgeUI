#!/bin/sh
# Copies the add-on from this repo into the game's AddOns/TankForgeUI.
# Run after editing, then /reload in game. Safe to run again.
# What gets left out comes from the ignore: list in .pkgmeta (plus all dotfiles).
#
# Don't symlink AddOns/TankForgeUI to this repo instead. Before every launch the
# Battle.net Agent fixes permissions across the install. It can't follow a link
# into ~/Documents, so it fails with error 2161 (BLZBNTAGT00000871) and the game
# won't launch.
set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
ADDONS="${WOW_ADDONS:-/Applications/World of Warcraft/_forever_/Interface/AddOns}"
DEST="$ADDONS/TankForgeUI"

if [ ! -d "$ADDONS" ]; then
    echo "AddOns folder not found: $ADDONS (set WOW_ADDONS to override)" >&2
    exit 1
fi

if [ -L "$DEST" ]; then
    echo "$DEST is a symlink (it breaks Battle.net launches). Remove it, then run again:" >&2
    echo "  rm \"$DEST\"" >&2
    exit 1
fi

# One rsync filter rule per line, from the list items under "ignore:" in .pkgmeta.
# Plain paths are anchored to the repo root; glob patterns match anywhere.
FILTERS="$(mktemp)"
trap 'rm -f "$FILTERS"' EXIT
echo "- .*" > "$FILTERS"
if [ -f "$REPO/.pkgmeta" ]; then
    awk '
        /^[^[:space:]#]/ { inlist = ($0 ~ /^ignore:[[:space:]]*$/); next }
        inlist && /^[[:space:]]*-[[:space:]]*/ {
            sub(/^[[:space:]]*-[[:space:]]*/, ""); sub(/[[:space:]]+$/, "")
            gsub(/^["\047]|["\047]$/, "")
            if ($0 == "") next
            if ($0 ~ /[*?[]/) print "- " $0; else print "- /" $0
        }
    ' "$REPO/.pkgmeta" >> "$FILTERS"
fi

mkdir -p "$DEST"
rsync -a --delete --delete-excluded --filter="merge $FILTERS" "$REPO/" "$DEST/"

echo "Synced: $REPO -> $DEST"
echo "/reload in game (restart the client if you added a file to the .toc)."
