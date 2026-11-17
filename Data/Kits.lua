-- Data/Kits.lua
-- What each tanking class tracks on WoW: Forever. Spell IDs, ranks, cooldowns
-- and durations come from TankCompanion's Forever kits (MIT License, see
-- THIRD_PARTY_NOTICES.md).
--
--   posture   what "set up to tank" means: forms (form IDs), formSpells, auras
--   spell/alt one spell's ranks, lowest first; the highest known rank is used
--             and a cast of any rank counts
--   am        active mitigation, tracked from your own casts; `primary` is the
--             one the HUD, alerts and pull report judge you on. `forms` (form IDs)
--             and `shield` say what it needs to be castable, so you aren't told to
--             press it when you can't
--   icons     shown on the HUD, in this order, when known
--   flyout    what the HUD's stance flyout holds, for its tooltip
local _, ns = ...

---@type table<string, Kit> class file name -> kit
ns.Kits = {
    WARRIOR = {
        posture = { forms = { 18 }, formSpells = { 71 } },          -- Defensive Stance
        flyout = "Stances",
        power = "Rage",
        am = {
            -- Up to 2 blocks in 7s: the buff ends at the second block.
            { key = "shieldBlock", spell = 2565, buff = 2565, duration = 7, cd = 5, primary = true,
              physical = true, target = 0.75, blocks = 2, forms = { 18 }, shield = true },
            { key = "demoShout", spell = 1160, alt = { 6190, 11554, 11555, 11556 }, duration = 30 },
        },
        icons = {
            { spell = 871, cd = 1800, kind = "defensive", major = true },            -- Shield Wall
            { spell = 12975, cd = 600, kind = "defensive", major = true },           -- Last Stand
            { spell = 355, cd = 10, kind = "taunt" },                                -- Taunt
            { spell = 72, alt = { 1671, 1672 }, cd = 12, kind = "interrupt" },       -- Shield Bash
            { spell = 1161, cd = 600, kind = "aoeTaunt" },                           -- Challenging Shout
            { spell = 12809, cd = 45, kind = "stop" },                               -- Concussion Blow
            { spell = 2687, cd = 60, kind = "other" },                               -- Bloodrage
        },
    },
    DRUID = {
        posture = { forms = { 5, 8 }, formSpells = { 5487, 9634 } }, -- Bear, Dire Bear
        flyout = "Forms",
        power = "Rage",
        am = {
            { key = "demoRoar", spell = 99, alt = { 1735, 9490, 9747, 9898 }, duration = 30, primary = true,
              physical = true, target = 0.85, forms = { 5, 8 } },
        },
        icons = {
            { spell = 22842, alt = { 22895, 22896 }, cd = 180, kind = "defensive", major = true }, -- Frenzied Regen
            { spell = 22812, cd = 60, kind = "defensive" },                          -- Barkskin
            { spell = 6795, cd = 10, kind = "taunt" },                               -- Growl
            { spell = 16979, cd = 15, kind = "interrupt" },                          -- Feral Charge
            { spell = 5209, cd = 600, kind = "aoeTaunt" },                           -- Challenging Roar
            { spell = 5211, alt = { 6798, 8983 }, cd = 60, kind = "stop" },          -- Bash
            { spell = 5229, cd = 60, kind = "other" },                               -- Enrage
        },
    },
    PALADIN = {
        posture = { auras = { 25780 } },                             -- Righteous Fury
        flyout = "Auras",
        power = "Mana",
        am = {
            { key = "holyShield", spell = 20925, alt = { 20927, 20928 }, buff = 20925, duration = 10, cd = 10,
              primary = true, physical = true, target = 0.75, blocks = 4, shield = true },
            { key = "consecration", spell = 26573, alt = { 20116, 20922, 20923, 20924 }, duration = 8, cd = 8 },
        },
        icons = {
            { spell = 498, alt = { 5573 }, cd = 300, kind = "defensive", major = true },   -- Divine Protection
            { spell = 642, alt = { 1020 }, cd = 300, kind = "defensive", major = true },   -- Divine Shield
            { spell = 633, alt = { 2800, 10310 }, cd = 3600, kind = "defensive" },         -- Lay on Hands
            { spell = 20271, cd = 10, kind = "taunt" },                                    -- Judgement
            { spell = 853, alt = { 5588, 5589, 10308 }, cd = 60, kind = "stop" },          -- Hammer of Justice
        },
    },
}

-- Classes that can heal, for guessing the healer when the group has no roles.
ns.HEALER_CLASSES = { PRIEST = 3, DRUID = 1, PALADIN = 1, SHAMAN = 1 }
