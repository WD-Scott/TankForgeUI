-- Modules/Alerts.lua: what gets shouted, and what doesn't.
local addon = require("support.addon")
local wow = require("support.wow")

describe("Alerts", function()
    local A, Alerts, TF, Tank, f
    local function load(db)
        A = addon.load({ db = db, world = { form = 18, known = { [2565] = true, [871] = true, [355] = true } } })
        Alerts, TF, Tank = A.ns.Alerts, A.TF, A.ns.Tank
        f = Alerts.frame
        wow.world.spellNames[2565] = "Shield Block"
        wow.world.spellNames[871] = "Shield Wall"
        wow.world.spellNames[355] = "Taunt"
    end
    local function shown() return f:IsShown() and f.text:GetText() or nil end
    local function hide() f:Hide() end
    after_each(function() wow.uninstall() end)

    describe("loose mobs", function()
        it("warns about a mob on the healer, with your taunt's state", function()
            load()
            TF:Fire("LOOSE", nil, "Holly", true, false, "party2")
            assert.are.equal("A mob is on your healer!", shown())
            assert.are.equal("Taunt is ready", f.sub:GetText())
            assert.are.same({ 8959 }, wow.sounds)
        end)

        it("says who has a mob, and when taunt comes back", function()
            load()
            A.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 355)
            wow.advance(2)
            TF:Fire("LOOSE", nil, "Stabby", false, false, "party1")
            assert.are.equal("Mob on Stabby", shown())
            assert.are.equal("Taunt in 8s", f.sub:GetText())
        end)

        it("stays quiet when you aren't tanking or the alert is off", function()
            load({ alerts = { lostAggro = false } })
            TF:Fire("LOOSE", nil, "Stabby", false, false, "party1")
            assert.is_nil(shown())
            Tank.isTank = false
            TF:Fire("LOOSE", nil, "Holly", true, false, "party2")
            assert.is_nil(shown())
        end)

        it("throttles repeats for the same member", function()
            load()
            TF:Fire("LOOSE", nil, "Stabby", false, false, "party1")
            hide()
            wow.advance(5)
            TF:Fire("LOOSE", nil, "Stabby", false, false, "party1")
            assert.is_nil(shown())
            TF:Fire("LOOSE", nil, "Bow", false, false, "party3")
            assert.are.equal("Mob on Bow", shown())
            hide()
            wow.advance(1.5)
            TF:Fire("LOOSE", nil, "Stabby", false, false, "party1")
            assert.are.equal("Mob on Stabby", shown())
        end)

        it("doesn't cover a more urgent alert that's still up", function()
            load()
            TF:Fire("LOOSE", nil, "Holly", true, false, "party2")
            TF:Fire("LOOSE", nil, "Stabby", false, false, "party1")
            assert.are.equal("A mob is on your healer!", shown())
            wow.advance(3.1)
            TF:Fire("LOOSE", nil, "Stabby", false, false, "party1")
            assert.are.equal("Mob on Stabby", shown())
        end)
    end)

    it("calls out a mitigation lapse", function()
        load()
        wow.world.inGroup = true
        TF:Fire("LAPSE", Tank.primary, 3.2)
        assert.are.equal("Shield Block!", shown())
        assert.are.equal("Being hit without it for 3s", f.sub:GetText())
    end)

    it("decides where the lapse alert applies", function()
        local W = Alerts.LapseWanted
        assert.is_true(W("always", false, false))
        assert.is_false(W("group", false, false))
        assert.is_true(W("group", true, false))
        assert.is_true(W("group", false, true))
        assert.is_true(W(nil, true, false))
        assert.is_false(W("instance", true, false))
        assert.is_true(W("instance", false, true))
    end)

    it("keeps the lapse alert quiet solo in the open world unless asked", function()
        load()
        TF:Fire("LAPSE", Tank.primary, 3.2)
        assert.is_nil(shown())
        wow.world.inInstance = true
        TF:Fire("LAPSE", Tank.primary, 3.2)
        assert.are.equal("Shield Block!", shown())
    end)

    it("calls out a solo lapse with the setting on Everywhere", function()
        load({ alerts = { lapseWhere = "always" } })
        TF:Fire("LAPSE", Tank.primary, 3.2)
        assert.are.equal("Shield Block!", shown())
    end)

    it("lists what was still ready when you died", function()
        load()
        TF:Fire("DEATH", { "Shield Wall" })
        assert.are.equal("You died", shown())
        assert.are.equal("Still ready: Shield Wall", f.sub:GetText())
        assert.matches("you died with Shield Wall still ready", wow.chatText())
    end)

    it("says when a major defensive comes back mid-pull, when asked", function()
        load({ alerts = { defensiveReady = true } })
        A.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 871)
        Tank.State(Tank:EntryFor(871)).readyAt = wow.now + 2
        A.combat(true)
        wow.advance(1)
        assert.is_nil(shown())
        wow.advance(1.5)
        assert.are.equal("Shield Wall ready", shown())
    end)

    it("is silent with alerts off, except the test alert", function()
        load({ alerts = { enabled = false } })
        TF:Fire("DEATH", {})
        assert.is_nil(shown())
        A.slash("test")
        assert.matches("on your healer", shown())
    end)

    it("fades out after its hold time", function()
        load()
        TF:Fire("DEATH", {})
        wow.advance(5.7)
        wow.run(f, "OnUpdate", 0.1)
        assert.is_true(f:GetAlpha() < 1)
        wow.advance(1)
        wow.run(f, "OnUpdate", 0.1)
        assert.is_false(f:IsShown())
    end)
end)
