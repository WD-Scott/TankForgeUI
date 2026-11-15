# TankForgeUI

A tank's UI for WoW: Forever. Replaces Quiet UI, and covers what you used from
TankCompanion (HUD, alerts, pull report), ForeverThreat and LH HideMe (bar art).

## Commands
- `/tf` options window
- `/tf setup` install the TankForgeUI Edit Mode layout and turn on Target of Target and enemy nameplates
- `/tf unlock`, `/tf lock`, `/tf reset` move frames, or put them back
- `/tf healer` make your target the healer (no target: automatic)
- `/tf report` last pull report
- `/tf test` test alert
- `/tf status` what TankForgeUI thinks is going on
- `/tf frame`, `/tf tooltips`, `/tf shift` hiding toggles
- `/tf quests [never|always|dungeons|combat]` when to hide the quest tracker
- `/tf layout` show the layout string to import by hand

## Debug log
`/tf log on`, play, then `/reload` or log out. The game writes the log to
`WTF\Account\<ACCOUNT>\SavedVariables\TankForgeUI.lua`. Your pull history is in
`WTF\Account\<ACCOUNT>\<Realm>\<Character>\SavedVariables\TankForgeUI.lua`.
- `/tf log mark <note>` adds a note at that moment ("lost the healer here")
- `/tf log probe` records which game values are readable right now
- `/tf log show [lines]` shows the latest lines in a copy box
- `/tf log off`, `/tf log clear`
