-- Modules/Healer.lua: finding the healer, the status tag, and when the panel shows.
local addon = require("support.addon")
local wow = require("support.wow")

describe("Healer", function()
    local A, Healer, w

    local function load(units, extra)
        local world = { form = 18, inGroup = true, units = { player = { name = "Tanky", class = "WARRIOR" } } }
        for k, v in pairs(units or {}) do world.units[k] = v end
        for k, v in pairs(extra or {}) do world[k] = v end
        A = addon.load({ world = world })
        Healer, w = A.ns.Healer, wow.world
    end
    after_each(function() wow.uninstall() end)

    describe("Find", function()
        it("prefers the HEALER role", function()
            load({ party1 = { name = "P", class = "PRIEST", role = "DAMAGER" },
                   party2 = { name = "S", class = "SHAMAN", role = "HEALER" } })
            assert.are.same({ "party2", "role" }, { Healer:Find() })
        end)

        it("guesses by class without roles, priest first", function()
            load({ party1 = { name = "D", class = "DRUID" }, party2 = { name = "P", class = "PRIEST" },
                   party3 = { name = "M", class = "MAGE" } })
            assert.are.same({ "party2", "guess" }, { Healer:Find() })
        end)

        it("doesn't guess someone assigned TANK or DAMAGER", function()
            load({ party1 = { name = "P", class = "PRIEST", role = "DAMAGER" },
                   party2 = { name = "D", class = "DRUID", role = "TANK" },
                   party3 = { name = "S", class = "SHAMAN" } })
            assert.are.same({ "party3", "guess" }, { Healer:Find() })
        end)

        it("finds nobody without a healing class", function()
            load({ party1 = { name = "M", class = "MAGE" } })
            assert.is_nil(Healer:Find())
            assert.are.equal("none", Healer:Describe())
        end)

        it("uses the healer picked with /tf healer over everything", function()
            load({ party1 = { name = "Holly", class = "PRIEST", role = "HEALER" },
                   party2 = { name = "Druidy", class = "DRUID" } })
            w.units.target = w.units.party2
            A.slash("healer")
            assert.are.equal("Druidy", A.TF.db.healerName)
            assert.are.same({ "party2", "picked" }, { Healer.unit, Healer.how })
            assert.are.equal("Druidy (picked)", Healer:Describe())
        end)

        it("goes back to automatic without a party member targeted", function()
            load({ party1 = { name = "Holly", class = "PRIEST" } }, nil)
            A.TF.db.healerName = "Gone"
            A.slash("healer")
            assert.is_nil(A.TF.db.healerName)
        end)

        it("only looks in a 5-player party", function()
            load({ party1 = { name = "Holly", class = "PRIEST" } }, { inRaid = true })
            assert.is_nil(Healer:Find())
        end)

        it("fires HEALER_CHANGED when the healer changes", function()
            load({ party1 = { name = "Holly", class = "PRIEST" } })
            A.clearMessages()
            w.units.party1 = nil
            A.fire("GROUP_ROSTER_UPDATE")
            assert.are.same({ { n = 1, nil } }, A.messages("HEALER_CHANGED"))
        end)
    end)

    describe("StatusTag", function()
        local holly
        before_each(function()
            load({ party1 = { name = "Holly", class = "PRIEST", power = 800, powerMax = 1000, powerType = 0 } })
            holly = w.units.party1
        end)

        it("is empty when all is well", function()
            assert.are.same({ "", "muted" }, { Healer.StatusTag("party1") })
        end)

        it("orders problems by urgency", function()
            w.inRange.party1 = { false, true }
            assert.are.equal("OUT OF RANGE", (Healer.StatusTag("party1")))
            holly.power = 250
            assert.are.equal("LOW MANA 25%", (Healer.StatusTag("party1")))
            w.unitAuras.party1 = { ["Spell 430"] = {} }
            assert.are.equal("DRINKING", (Healer.StatusTag("party1")))
            A.ns.Threat.healerAttacked = true
            assert.are.equal("ATTACKED", (Healer.StatusTag("party1")))
            holly.connected = false
            assert.are.equal("OFFLINE", (Healer.StatusTag("party1")))
            holly.dead = true
            assert.are.same({ "DEAD", "bad" }, { Healer.StatusTag("party1") })
        end)

        it("doesn't call secret mana low", function()
            holly.power = wow.secret(10)
            assert.are.equal("", (Healer.StatusTag("party1")))
        end)

        it("is drawn on the panel", function()
            holly.dead = true
            Healer:Update()
            assert.are.equal("DEAD", Healer.frame.tag:GetText())
        end)
    end)

    describe("panel", function()
        it("shows in a party while tanking", function()
            load({ party1 = { name = "Holly", class = "PRIEST" } })
            assert.is_true(Healer.frame:IsShown())
        end)

        it("hides out of a party, or when not tanking", function()
            load({ party1 = { name = "Holly", class = "PRIEST" } }, { inGroup = false })
            assert.is_false(Healer.frame:IsShown())
            w.inGroup = true
            A.fire("GROUP_ROSTER_UPDATE")
            assert.is_true(Healer.frame:IsShown())
            w.form = false
            A.fire("UPDATE_SHAPESHIFT_FORM")
            wow.advance(11) -- past the tanking grace
            assert.is_false(Healer.frame:IsShown())
        end)

        it("only goes transparent in combat, and hides once combat ends", function()
            load({ party1 = { name = "Holly", class = "PRIEST" } })
            A.combat(true)
            w.units.party1 = nil
            w.inGroup = false
            A.fire("GROUP_ROSTER_UPDATE")
            assert.is_true(Healer.frame:IsShown())
            assert.are.equal(0, Healer.frame:GetAlpha())
            A.combat(false)
            assert.is_false(Healer.frame:IsShown())
        end)

        it("waits for combat to end to appear", function()
            load({}, { inGroup = false })
            A.combat(true)
            w.inGroup = true
            w.units.party1 = { name = "Holly", class = "PRIEST" }
            A.fire("GROUP_ROSTER_UPDATE")
            assert.is_false(Healer.frame:IsShown())
            A.combat(false)
            assert.is_true(Healer.frame:IsShown())
        end)

        it("points the click button at the healer out of combat", function()
            load({ party1 = { name = "Holly", class = "PRIEST" } })
            assert.are.equal("party1", Healer.click:GetAttribute("unit"))
        end)
    end)
end)
