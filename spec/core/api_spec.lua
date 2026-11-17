-- Core/API.lua: the secret-value safety layer.
local addon = require("support.addon")
local wow = require("support.wow")

describe("API", function()
    local API, w
    before_each(function()
        local A = addon.load({ upto = "Core/API.lua", login = false })
        API, w = A.ns.API, wow.world
    end)
    after_each(function() wow.uninstall() end)

    describe("plain-value wrappers", function()
        it("passes plain values through", function()
            assert.are.equal(5, API.PlainNumber(5))
            assert.is_false(API.PlainBool(false))
            assert.are.equal("x", API.PlainString("x"))
        end)

        it("returns nil for the wrong type", function()
            assert.is_nil(API.PlainNumber("5"))
            assert.is_nil(API.PlainBool(1))
            assert.is_nil(API.PlainString(5))
            assert.is_nil(API.PlainNumber(nil))
        end)

        it("returns nil for an empty string", function()
            assert.is_nil(API.PlainString(""))
        end)

        it("returns nil for secrets without touching them", function()
            assert.is_true(API.IsSecret(wow.secret(5)))
            assert.is_nil(API.PlainNumber(wow.secret(5)))
            assert.is_nil(API.PlainBool(wow.secret(true)))
            assert.is_nil(API.PlainString(wow.secret("Bob")))
        end)

        it("Safe returns the results, or nil when the call raises", function()
            local a, b = API.Safe(function(x) return x, x + 1 end, 1)
            assert.are.same({ 1, 2 }, { a, b })
            assert.is_nil(API.Safe(function() error("boom") end))
            assert.is_nil(API.Safe(nil))
        end)
    end)

    describe("units", function()
        it("reads plain unit info", function()
            w.units.party1 = { name = "Holly", realm = "Elsewhere", class = "PRIEST", role = "HEALER", leader = true }
            assert.is_true(API.UnitExists("party1"))
            assert.is_false(API.UnitExists("party2"))
            assert.are.equal("PRIEST", API.UnitClass("party1"))
            assert.are.equal("Holly", API.UnitName("party1"))
            assert.are.equal("HEALER", API.UnitRole("party1"))
            assert.is_true(API.IsLeader("party1"))
            assert.is_true(API.IsConnected("party1"))
        end)

        it("gives nil for secret names, classes and roles", function()
            w.units.party1 = { name = wow.secret("Holly"), class = wow.secret("PRIEST"), role = wow.secret("HEALER") }
            assert.is_nil(API.UnitName("party1"))
            assert.is_nil(API.UnitClass("party1"))
            assert.is_nil(API.UnitRole("party1"))
        end)

        it("treats a secret connection state as connected", function()
            w.units.party1 = { name = "Holly", connected = wow.secret(false) }
            assert.is_true(API.IsConnected("party1"))
            w.units.party1.connected = false
            assert.is_false(API.IsConnected("party1"))
        end)

        it("UnitIsUnit is nil for a missing token", function()
            assert.is_nil(API.UnitIsUnit(nil, "player"))
            assert.is_true(API.UnitIsUnit("player", "player"))
        end)

        it("ClassColor falls back to grey", function()
            local r, g, b = API.ClassColor("NOPE")
            assert.are.same({ 0.85, 0.85, 0.85 }, { r, g, b })
            assert.are.equal(0.78, (API.ClassColor("WARRIOR")))
        end)
    end)

    describe("IsSpellKnown", function()
        it("uses the first spellbook API that answers", function()
            w.known[2565] = true
            assert.is_true(API.IsSpellKnown(2565))
            assert.is_false(API.IsSpellKnown(871))
            assert.is_false(API.IsSpellKnown("2565"))
        end)

        it("skips a missing first API instead of giving up", function()
            _G.C_SpellBook = { IsSpellKnown = function(id) return id == 72 end }
            assert.is_true(API.IsSpellKnown(72))
        end)

        it("skips a missing first global API instead of giving up", function()
            _G.C_SpellBook = nil
            _G.IsPlayerSpell = function(id) return id == 72 end
            assert.is_true(API.IsSpellKnown(72))
        end)

        it("asks the next API when one answers with a secret", function()
            _G.C_SpellBook = {
                IsSpellKnownOrInSpellBook = function() return wow.secret(true) end,
                IsSpellKnown = function() return true end,
            }
            assert.is_true(API.IsSpellKnown(72))
        end)
    end)

    describe("spells and auras", function()
        it("reads spell names", function()
            w.spellNames[2565] = "Shield Block"
            assert.are.equal("Shield Block", API.GetSpellName(2565))
        end)

        it("reads a plain cooldown and refuses a secret one", function()
            w.cooldowns[871] = { 100, 1800 }
            assert.are.same({ 100, 1800 }, { API.GetSpellCooldownPlain(871) })
            w.cooldowns[871] = { wow.secret(100), 1800 }
            assert.is_nil(API.GetSpellCooldownPlain(871))
            w.cooldowns[871] = wow.secret({})
            assert.is_nil(API.GetSpellCooldownPlain(871))
        end)

        it("finds a player aura by ID, then by name for another rank", function()
            w.spellNames[100] = "Holy Shield"
            w.spellNames[101] = "Holy Shield"
            w.auras[101] = { expirationTime = 1010, name = "Holy Shield" }
            assert.are.equal(1010, API.GetPlayerAura(101).expirationTime)
            assert.are.equal(1010, API.GetPlayerAura(100).expirationTime)
            assert.is_nil(API.GetPlayerAura("100"))
        end)

        it("reports an aura the client answers with a secret as hidden", function()
            w.auras[2565] = wow.secret({})
            assert.is_true(API.PlayerAuraHidden(2565))
            assert.is_nil(API.GetPlayerAura(2565))
            w.auras[2565] = nil
            assert.is_false(API.PlayerAuraHidden(2565))
        end)
    end)

    describe("GetShapeshiftForms", function()
        it("reads each form, refilling a passed list in place", function()
            w.formSpell = 71
            local list = API.GetShapeshiftForms()
            assert.are.equal(1, #list)
            assert.are.equal(71, list[1].spellID)
            assert.is_true(list[1].active)
            local entry = list[1]
            list[2] = { spellID = 99 }  -- a form that's gone since
            local again = API.GetShapeshiftForms(list)
            assert.are.equal(list, again)
            assert.are.equal(entry, again[1])
            assert.are.equal(1, #again)
            w.formSpell = nil
            assert.are.equal(0, #API.GetShapeshiftForms(list))
        end)
    end)

    describe("AddOnMetrics", function()
        it("is nil without the client's profiler", function()
            _G.C_AddOnProfiler = nil
            assert.is_nil(API.AddOnMetrics("TankForgeUI"))
        end)

        it("reads each metric the client has, leaving out secret and missing ones", function()
            _G.Enum.AddOnProfilerMetric = { RecentAverageTime = 1, SessionAverageTime = 0, PeakTime = 4,
                CountTimeOver5Ms = 7 }
            local asked = {}
            _G.C_AddOnProfiler = { GetAddOnMetric = function(name, metric)
                asked[#asked + 1] = name
                if metric == 1 then return 0.25 end
                if metric == 0 then return 0.5 end
                if metric == 4 then return 40 end
                return wow.secret(3)
            end }
            local m = API.AddOnMetrics("TankForgeUI")
            assert.are.same({ RecentAverageTime = 0.25, SessionAverageTime = 0.5, PeakTime = 40 }, m)
            assert.are.equal("TankForgeUI", asked[1])
            _G.C_AddOnProfiler, _G.Enum.AddOnProfilerMetric = nil, nil
        end)
    end)

    describe("HasShield", function()
        it("is true with a shield and false with anything else or nothing", function()
            assert.is_true(API.HasShield())
            w.offhand = "INVTYPE_WEAPONOFFHAND"
            assert.is_false(API.HasShield())
            w.offhand = nil
            assert.is_false(API.HasShield())
        end)

        it("counts an unreadable answer as a shield", function()
            w.offhand = wow.secret("INVTYPE_2HWEAPON")
            assert.is_true(API.HasShield())
            _G.GetInventoryItemID = function() error("nope") end
            assert.is_true(API.HasShield())
            _G.GetInventoryItemID = nil
            assert.is_true(API.HasShield())
        end)
    end)

    describe("unit values", function()
        it("computes a plain power fraction", function()
            assert.are.equal(0.5, API.PowerFraction("player"))
            w.units.player.power = wow.secret(50)
            assert.is_nil(API.PowerFraction("player"))
        end)

        it("gives a plain health percentage, 0 for no max", function()
            w.units.player.health = 2500
            assert.are.equal(50, API.PercentDisplay("player"))
            w.units.player.healthMax = 0
            assert.are.equal(0, API.PercentDisplay("player"))
        end)

        it("hands a secret percentage through the client's curve", function()
            w.units.player.health = wow.secret(2500)
            _G.CurveConstants = { ScaleTo100 = {} }
            local pct = wow.secret(50)
            _G.UnitHealthPercent = function() return pct end
            assert.are.equal(pct, API.PercentDisplay("player"))
            _G.CurveConstants = nil
            assert.is_nil(API.PercentDisplay("player"))
        end)

        it("abbreviates secrets only through the client", function()
            assert.are.equal("1.5k", API.AbbrevDisplay(1500))
            assert.is_nil(API.AbbrevDisplay(wow.secret(1500)))
            _G.AbbreviateLargeNumbers = function() return "1.5K" end
            assert.are.equal("1.5K", API.AbbrevDisplay(wow.secret(1500)))
        end)
    end)

    describe("range", function()
        it("counts out of range only when the client checked", function()
            assert.is_false((API.RangeState("party1")))
            w.inRange.party1 = { false, true }
            assert.is_true((API.RangeState("party1")))
            w.inRange.party1 = { true, true }
            assert.is_false((API.RangeState("party1")))
        end)

        it("hands back a secret answer for the widget", function()
            local s = wow.secret(false)
            w.inRange.party1 = { s, true }
            local out, secret = API.RangeState("party1")
            assert.is_false(out)
            assert.are.equal(s, secret)
        end)

        it("dims a region out of range", function()
            local f = wow.NewFrame("Frame")
            w.inRange.party1 = { false, true }
            API.ApplyRangeAlpha(f, "party1", 0.8, 0.5, true)
            assert.are.equal(0.4, f:GetAlpha())
            API.ApplyRangeAlpha(f, "party1", 0.8, 0.5, false)
            assert.are.equal(0.8, f:GetAlpha())
        end)
    end)

    describe("formatting", function()
        it("Abbrev", function()
            assert.are.equal("950", API.Abbrev(950))
            assert.are.equal("-950", API.Abbrev(-950))
            assert.are.equal("1k", API.Abbrev(1000))
            assert.are.equal("1.5k", API.Abbrev(1500))
            assert.are.equal("12.3k", API.Abbrev(12345))
            assert.are.equal("123k", API.Abbrev(123456))
            assert.are.equal("2.5M", API.Abbrev(2500000))
            assert.are.equal("3B", API.Abbrev(3e9))
            assert.are.equal("?", API.Abbrev(wow.secret(5)))
            assert.are.equal("?", API.Abbrev(nil))
        end)

        it("Abbrev moves up a unit instead of printing 1000k", function()
            assert.are.equal("1M", API.Abbrev(999999))
            assert.are.equal("1B", API.Abbrev(999999999))
        end)

        it("FormatSeconds", function()
            assert.are.equal("0:00", API.FormatSeconds(0))
            assert.are.equal("1:05", API.FormatSeconds(65.9))
            assert.are.equal("61:00", API.FormatSeconds(3660))
            assert.are.equal("0:00", API.FormatSeconds(-5))
            assert.are.equal("0:00", API.FormatSeconds("junk"))
        end)

        it("PowerType prefers the client's enum", function()
            assert.are.equal(0, API.PowerType("Mana"))
            _G.Enum = nil
            assert.are.equal(1, API.PowerType("Rage"))
            assert.is_nil(API.PowerType("Runic"))
        end)

        it("InstanceInfo keeps only plain values", function()
            w.instance = { name = wow.secret("Deadmines"), type = "party", difficultyID = 1, id = 36 }
            local info = API.InstanceInfo()
            assert.is_nil(info.name)
            assert.are.equal("party", info.type)
            assert.are.equal(36, info.id)
        end)
    end)

    it("detects the Forever client from the build", function()
        assert.are.equal(16002, API.buildNumber)
        assert.is_true(API.isForever)
    end)
end)
