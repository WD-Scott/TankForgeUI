# TankForgeUI

A WoW: Forever add-on (Lua, no build step). The .toc targets `## Interface: 16001, 16002`.

## Layout
- `TankForgeUI.toc` lists load order. Add new files there or the game won't load them.
- `Core/` shared plumbing (events, style, secret-value-safe API wrappers, debug log)
- `Data/` spell kits and the Edit Mode layout string
- `Modules/` features (HUD, threat, healer, party, alerts, report, options, setup)

## Running it
- The game loads the add-on straight from this repo: `AddOns/TankForgeUI` is a symlink here
  (`/Applications/World of Warcraft/_forever_/Interface/AddOns`). Recreate it with `scripts/link.sh`.
- After editing Lua: `/reload` in game. After adding a file to the .toc or renaming the folder: restart the client.
- Useful in game: `/tf status`, `/tf log on` / `/tf log probe` / `/tf log show`, `/tf test`.
- Saved variables: `WTF/Account/<ACCOUNT>/SavedVariables/TankForgeUI.lua` (log) and
  `WTF/Account/<ACCOUNT>/<Realm>/<Character>/SavedVariables/TankForgeUI.lua` (settings, pull history).

## Naming rule
Everything is spelled **TankForgeUI**: SavedVariables `TankForgeUIDB` / `TankForgeUILog`, the
global `_G.TankForgeUI`, frame names, and the Edit Mode layout (`ns.LAYOUT_NAME`).
Renaming a SavedVariables global drops existing data unless you add a migration.
Changing `## SavedVariables` lines needs a full client restart, not `/reload`.
