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
The add-on is spelled **TankForgeUI** in everything players see. Internal identifiers keep the
original `TankforgeUI` spelling and must not be renamed, or existing users lose data:
- SavedVariables `TankforgeUIDB`, `TankforgeUILog`
- the global `_G.TankforgeUI` and the `TankforgeUI*` frame names
- `ns.LAYOUT_NAME = "TankforgeUI"` (the Edit Mode layout `/tf setup` looks for)
