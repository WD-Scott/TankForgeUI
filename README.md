# TankForgeUI

A tank's UI for WoW: Forever. Replaces Quiet UI, and covers what you used from
TankCompanion (HUD, alerts, pull report), ForeverThreat and LH HideMe (bar art).

## Commands
- `/tf` options window
- `/tf help` every command, by section; `/tf help <command>` for its options (e.g. `/tf help log`)
- `/tf setup` install the TankForgeUI Edit Mode layout and turn on Target of Target and enemy nameplates
- `/tf unlock`, `/tf lock`, `/tf reset` move frames, or put them back
- `/tf healer` make your target the healer (no target: automatic)
- `/tf report` last pull report
- `/tf runs` saved dungeon and raid runs: the latest run, or a side-by-side comparison of up to three
  (turn on Options → Runs first). `/tf run` shows the run being recorded; `/tf run end` ends it now.
- `/tf test` test alert (`/tf test healer`: flip the healer panel, to test it in combat)
- `/tf perf` CPU use from the game's add-on profiler (per-frame averages and the worst frame)
- `/tf taint` list Blizzard frame fields an add-on has tainted (for chasing "blocked" errors)
- `/tf status` what TankForgeUI thinks is going on
- `/tf frame`, `/tf tooltips`, `/tf shift` hiding toggles
- `/tf stances` toggle the stance pop-out
- `/tf quests [never|always|dungeons|combat]` when to hide the quest tracker
- `/tf layout` show the layout string to import by hand

## Layout notes
- The tank HUD is one short panel: a round portrait, health and power. Your stance buttons sit in a
  vertical flyout on its right edge, opened and closed with the tab there (even in combat). When you aren't tanking the HUD stays
  up, so you can click back into your tanking stance.
- Blizzard's stance bar is hidden while the HUD's stance buttons are on (`/tf stances` brings it back).
- The cast bar sits at bottom center. Tooltips and bags open above the action bars, not on them.
- Quest, gossip, vendor, trainer, flight and bank windows open at the "NPC dialogs" box rather than
  Blizzard's top-left spot. Move it with `/tf unlock`; turn it off in Options → Move NPC windows.
- Action Bar 6 is a small profession bar above the right end of the action bars, next to the bags.
  Turn it on in Options → Gameplay → Action Bars, then drag profession spells onto it. Empty slots stay hidden.
- When an update ships a newer layout, TankForgeUI says so once at login.
- Running `/tf setup` again updates the TankForgeUI layout to the latest version. It asks first,
  because changes you made to that layout in Edit Mode are replaced.

## Charts and runs
- The pull report shows a timeline of the pull (when you were hit with and without your mitigation,
  hits per second, deaths) and your coverage over the last 10 pulls. Turn them off in Options → Pull report → Charts.
- With Options → Runs on, every pull in a dungeon or raid is kept with its run. A run ends when you enter
  another instance, after 15 minutes outside (corpse runs don't end it), or with `/tf run end`.
  Runs with fewer than 3 pulls aren't kept. The last 25 runs are saved per character.
- Comparisons use rates per minute of combat, so a slow clear and a fast one compare fairly.

## Debug log
`/tf log on`, play, then `/reload` or log out. The game writes the log to
`WTF\Account\<ACCOUNT>\SavedVariables\TankForgeUI.lua`. Your pull history is in
`WTF\Account\<ACCOUNT>\<Realm>\<Character>\SavedVariables\TankForgeUI.lua`.
The log is kept across logins and `/reload`s (each session starts with a `==== session` header) until
`/tf log clear`; past 5,000 lines the oldest half is dropped.
- `/tf log mark <note>` adds a note at that moment ("lost the healer here")
- `/tf log probe` records which game values are readable right now
- `/tf log show [lines]` shows the latest lines in a copy box
- `/tf log off`, `/tf log clear`

## Development
- `scripts/sync.sh` copies the add-on into
  `/Applications/World of Warcraft/_forever_/Interface/AddOns/TankForgeUI` (set `WOW_ADDONS` to
  override). Run it after editing, then `/reload` in game. Restart the client after adding a file to
  the `.toc`.
- Don't symlink that folder to the repo. Battle.net can't fix permissions through the link, and
  launches fail with error BLZBNTAGT00000871 (2161).
- `.pkgmeta` lists what's left out of the add-on. Both `scripts/sync.sh` and the BigWigs packager
  read it.

### Tests and lint
The add-on's logic runs offline against a stand-in for the game client, under Lua 5.1 (the game's
version), with [busted](https://lunarmodules.github.io/busted/) and
[luacheck](https://github.com/lunarmodules/luacheck). GitHub Actions runs the same on every push.

```sh
scripts/bootstrap.sh          # once: Lua 5.1 + LuaRocks + busted, luacheck, luacov into .lua/ (needs Python 3)
scripts/test.sh               # luacheck, then every spec
scripts/test.sh --coverage    # also writes luacov.report.out and prints the per-file summary
scripts/test.sh spec/modules/tank_spec.lua   # one file; other busted flags work too
```

- `spec/support/wow.lua` is the fake client: frames that record their state, a clock you move with
  `wow.advance(seconds)` (timers fire in order), units, spells, auras, cooldowns, threat and instance
  info in `wow.world`, and `wow.secret(v)` for secret values (comparing or doing arithmetic on one
  raises, as in game).
- `spec/support/addon.lua` loads every file in `.toc` order into a fresh client per test and logs in.
  Errors in event handlers and messages are raised instead of printed, so they fail the test.
  `A.fire(event, ...)`, `A.combat(on)`, `A.slash("status")`, `A.messages("PULL_END")`.
- `spec/support/fixtures.lua` builds pulls and runs.
- Specs mirror the source: `spec/core/`, `spec/data/`, `spec/modules/`. A change to logic comes with a
  spec; a bug fix comes with a spec that failed before it.
- The specs check decisions, not looks: anything that needs the real client (taint, secure frames,
  how frames are drawn) still needs a check in game.

### Editor support
Functions carry [LuaLS](https://luals.github.io/) annotations (`---@param`, `---@return`), and
`annotations/Types.lua` describes the shared data (settings, kits, pulls, runs) and every internal
message's arguments. With the Lua extension in VS Code you get hovers and type checks; add
[Ketho's WoW API extension](https://marketplace.visualstudio.com/items?itemName=ketho.wow-api) for the
game's API.

## Acknowledgements
Built in collaboration with Claude (Anthropic) via Claude Code.
