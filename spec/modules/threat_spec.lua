-- Modules/Threat.lua: loose mobs and the threat list.
local addon = require("support.addon")
local wow = require("support.wow")

describe("Threat", function()
    local A, Threat, Tank, w

    -- A warrior tank in a party with a rogue, a priest (healer) and a hunter with a pet.
    local function load(extra)
        local world = {
            form = 18, inGroup = true,
            units = {
                player = { name = "Tanky", class = "WARRIOR" },
                party1 = { name = "Stabby", class = "ROGUE", role = "DAMAGER" },
                party2 = { name = "Holly", class = "PRIEST", role = "HEALER" },
                party3 = { name = "Bow", realm = "Elsewhere", class = "HUNTER", role = "DAMAGER" },
                partypet3 = { name = "Wolf" },
            },
        }
        for k, v in pairs(extra or {}) do world[k] = v end
        A = addon.load({ world = world })
        Threat, Tank, w = A.ns.Threat, A.ns.Tank, wow.world
    end
    local function scan()
        A.clearMessages()
        Threat.Scan()
    end
    after_each(function() wow.uninstall() end)

    describe("IsGroupUnit", function()
        it("knows group tokens from nameplates and the rest", function()
            load()
            for _, u in ipairs({ "player", "pet", "party1", "party4", "partypet2", "raid1", "raid40", "raidpet7" }) do
                assert.is_true(Threat.IsGroupUnit(u), u)
            end
            for _, u in ipairs({ "nameplate1", "target", "focus", "party5", "raid41", "boss1", "mouseover" }) do
                assert.is_false(Threat.IsGroupUnit(u), u)
            end
            assert.is_true(Threat.IsGroupUnit(nil))
        end)

        it("rebuilds the roster for a member's name change, not a nameplate's", function()
            load()
            Threat.GroupUnits()  -- settle the roster
            local reads = 0
            local real = A.ns.API.UnitName
            A.ns.API.UnitName = function(...)
                reads = reads + 1
                return real(...)
            end
            A.fire("UNIT_NAME_UPDATE", "nameplate3")
            A.fire("UNIT_PET", "nameplate3")
            Threat.GroupUnits()
            assert.are.equal(0, reads)
            A.fire("UNIT_NAME_UPDATE", "party2")
            Threat.GroupUnits()
            assert.is_true(reads > 0)
            A.ns.API.UnitName = real
        end)
    end)

    describe("Scan", function()
        it("finds the healer for the checks below", function()
            load()
            assert.are.equal("party2", A.ns.Healer.unit)
        end)

        it("fires LOOSE when a member picks up a mob, once", function()
            load()
            A.combat(true)
            w.threat.party1 = 3
            scan()
            assert.are.same({ { n = 6, nil, "Stabby", false, false, "party1", true } }, A.messages("LOOSE"))
            assert.are.same({ { n = 2, 1, false } }, A.messages("LOOSE_COUNT"))
            assert.are.equal(1, Threat.looseCount)
            assert.are.same({ "Stabby" }, Threat.victims)
            scan()
            assert.are.same({}, A.messages())
        end)

        it("counts it against the pull", function()
            load()
            A.combat(true)
            w.threat.party1 = 2
            scan()
            w.threat.party1 = 0
            scan()
            wow.advance(Threat.RECOUNT)
            w.threat.party1 = 3
            scan()
            assert.are.equal(2, Tank.pull.aggroLost)
            assert.are.same({ Stabby = 2 }, Tank.pull.aggroLostTo)
        end)

        it("counts a mob flipping back within RECOUNT seconds once, but still fires LOOSE", function()
            load()
            A.combat(true)
            w.threat.party1 = 3
            scan()
            w.threat.party1 = 0
            scan()
            wow.advance(1)
            w.threat.party1 = 3
            scan()
            assert.are.equal(1, Tank.pull.aggroLost)
            assert.is_false(A.messages("LOOSE")[1][6])
            w.threat.party1 = 0
            scan()
            wow.advance(4)
            w.threat.party1 = 3
            scan()
            assert.are.equal(2, Tank.pull.aggroLost)
            assert.is_true(A.messages("LOOSE")[1][6])
        end)

        it("decides a new loss by time clear", function()
            load()
            assert.is_true(Threat.CountsAsNewLoss(nil, 10))
            assert.is_false(Threat.CountsAsNewLoss(9, 10))
            assert.is_true(Threat.CountsAsNewLoss(7, 10))
        end)

        it("flags a mob on the healer", function()
            load()
            A.combat(true)
            w.threat.party2 = 2
            scan()
            assert.is_true(A.messages("LOOSE")[1][3])
            assert.is_true(Threat.healerAttacked)
            assert.are.same({ n = 2, 1, true }, A.messages("LOOSE_COUNT")[1])
        end)

        it("fires LOOSE_COUNT when mobs come back", function()
            load()
            A.combat(true)
            w.threat.party1 = 3
            scan()
            w.threat.party1 = 1
            scan()
            assert.are.same({ { n = 2, 0, false } }, A.messages("LOOSE_COUNT"))
            assert.are.same({}, Threat.victims)
        end)

        it("ignores status 1 (high threat, not attacked), secret status and pets", function()
            load()
            A.combat(true)
            w.threat.party1 = 1
            w.threat.party2 = wow.secret(3)
            w.threat.partypet3 = 3
            scan()
            assert.are.equal(0, Threat.looseCount)
            assert.are.same({}, A.messages("LOOSE"))
        end)

        it("leaves mobs on another real tank alone", function()
            load()
            w.units.party1 = { name = "Beary", class = "DRUID", role = "TANK" }
            w.units.party3.role = "TANK" -- a hunter can't be the tank
            A.fire("GROUP_ROSTER_UPDATE")
            A.combat(true)
            w.threat.party1 = 3
            w.threat.party3 = 3
            scan()
            assert.are.same({ "Bow" }, Threat.victims)
        end)

        it("only runs while tanking in combat in a group", function()
            load()
            w.threat.party1 = 3
            scan()
            assert.are.equal(0, Threat.looseCount)
            A.combat(true)
            Tank.isTank = false
            scan()
            assert.are.equal(0, Threat.looseCount)
        end)

        it("resets when combat ends", function()
            load()
            A.combat(true)
            w.threat.party1 = 3
            scan()
            A.combat(false)
            assert.are.equal(0, Threat.looseCount)
            assert.is_false(Threat.healerAttacked)
            A.combat(true)
            scan()
            assert.are.equal(1, #A.messages("LOOSE"))
        end)

        it("keeps the last readable name when names go secret", function()
            load()
            Threat.GroupUnits() -- built while the name is readable
            w.units.party1.name = wow.secret("Stabby")
            A.fire("GROUP_ROSTER_UPDATE")
            A.combat(true)
            w.threat.party1 = 3
            scan()
            assert.are.same({ "Stabby" }, Threat.victims)
        end)

        it("picks up roster changes", function()
            load()
            w.units.party4 = { name = "Late", class = "MAGE" }
            A.fire("GROUP_ROSTER_UPDATE")
            A.combat(true)
            w.threat.party4 = 3
            scan()
            assert.are.same({ "Late" }, Threat.victims)
        end)
    end)

    describe("StatusFor", function()
        local S
        before_each(function()
            load()
            S = function(...) return (Threat.StatusFor(...):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
        end)

        it("is empty without a target", function()
            assert.are.equal("", S({ { me = true, tanking = true, scaled = 100 } }, false, false))
        end)

        it("says hidden when every value is secret", function()
            assert.are.equal("hidden", S({}, true, true))
        end)

        it("says holding when you tank it alone", function()
            assert.are.equal("holding", S({ { me = true, tanking = true, scaled = 100 } }, true, false))
        end)

        it("shows how close the next person is, colored by danger", function()
            local function next(scaled)
                return Threat.StatusFor({ { me = true, tanking = true, scaled = 100 }, { scaled = scaled } }, true, false)
            end
            assert.are.equal("next 50%", S({ { me = true, tanking = true, scaled = 100 }, { scaled = 50 } }, true, false))
            local HEX = A.ns.Style.HEX
            assert.matches(HEX.good, next(50))
            assert.matches(HEX.warn, next(70))
            assert.matches(HEX.bad, next(95))
        end)

        it("shouts when someone else has it", function()
            assert.are.equal("NOT ON YOU", S({ { scaled = 100, tanking = true }, { me = true, scaled = 80 } }, true, false))
        end)
    end)

    describe("panel", function()
        it("lists threat on your target", function()
            load()
            w.units.target = { name = "Kobold", hostile = true }
            w.targetThreat.player = { true, 3, 100 }
            w.targetThreat.party1 = { false, 1, 85.4 }
            w.targetThreat.party2 = { false, 0, wow.secret(5) }
            A.fire("PLAYER_TARGET_CHANGED")
            local f = Threat.frame
            assert.is_true(f:IsShown())
            assert.matches("Kobold", f.title:GetText())
            assert.matches("next 85%%", f.status:GetText())
            assert.matches("Tanky", f.rows[1].label:GetText())
            assert.are.equal("85%", f.rows[2].value:GetText())
            assert.is_nil(f.rows[3])
        end)

        it("is hidden when not tanking, or turned off", function()
            load({ form = false })
            w.units.target = { name = "Kobold", hostile = true }
            A.fire("PLAYER_TARGET_CHANGED")
            assert.is_false(Threat.frame:IsShown())
            w.form = 18
            A.fire("UPDATE_SHAPESHIFT_FORM")
            assert.is_true(Threat.frame:IsShown())
            A.TF.db.threat.enabled = false
            Threat:Refresh()
            assert.is_false(Threat.frame:IsShown())
        end)

        it("names who has a mob in the footer", function()
            load()
            A.combat(true)
            w.threat.party1 = 3
            Threat.Scan()
            Threat:Update()
            assert.matches("Mob on Stabby", Threat.frame.footer:GetText())
        end)

        it("resizes only when the rows or footer change", function()
            load()
            w.units.target = { name = "Kobold", hostile = true }
            w.targetThreat.player = { true, 3, 100 }
            A.fire("PLAYER_TARGET_CHANGED")
            local f = Threat.frame
            local sizes = 0
            local setHeight = f.SetHeight
            f.SetHeight = function(...) sizes = sizes + 1 return setHeight(...) end
            Threat:Update()
            Threat:Update()
            assert.are.equal(0, sizes)
            w.targetThreat.party1 = { false, 1, 50 }
            Threat:Update()
            assert.are.equal(1, sizes)
            assert.is_true(f.rows[2]:IsShown())
        end)
    end)
end)
