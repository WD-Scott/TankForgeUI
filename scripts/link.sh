#!/bin/sh
# Points the game's AddOns/TankForgeUI at this repo, so edits here show up
# in game after /reload. Safe to run again.
set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
ADDONS="${WOW_ADDONS:-/Applications/World of Warcraft/_forever_/Interface/AddOns}"
LINK="$ADDONS/TankForgeUI"

if [ ! -d "$ADDONS" ]; then
    echo "AddOns folder not found: $ADDONS (set WOW_ADDONS to override)" >&2
    exit 1
fi

if [ -L "$LINK" ]; then
    if [ "$(readlink "$LINK")" = "$REPO" ]; then
        echo "Already linked: $LINK -> $REPO"
        exit 0
    fi
    echo "$LINK is a link to $(readlink "$LINK"), not this repo. Remove it and run again." >&2
    exit 1
fi

# macOS disks are case-insensitive, so this also catches an old "TankforgeUI" folder.
if [ -e "$LINK" ]; then
    echo "A real folder is in the way: $LINK" >&2
    echo "Move it out of AddOns (to keep as a backup), then run again." >&2
    exit 1
fi

ln -s "$REPO" "$LINK"
echo "Linked: $LINK -> $REPO"
echo "Restart the game client (not just /reload) so it sees the add-on."
