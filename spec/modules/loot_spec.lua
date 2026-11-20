-- Loot: Need / Greed / Pass windows are held back in combat and come back
-- when it ends, or early when a roll is about to run out.
local addon = require("support.addon")
local wow = require("support.wow")

describe("Loot.ShouldHide", function()
    local A, Loot
    setup(function()
        A = addon.load()
        Loot = A.ns.Loot
    end)
    teardown(function() wow.uninstall() end)

    it("hides only in combat with the setting on", function()
        assert.is_true(Loot.ShouldHide(true, true, {}, 0, 10))
        assert.is_false(Loot.ShouldHide(false, true, {}, 0, 10))
        assert.is_false(Loot.ShouldHide(true, false, {}, 0, 10))
    end)

    it("shows when a roll is within revealAt of running out", function()
        assert.is_true(Loot.ShouldHide(true, true, { [1] = 60 }, 0, 10))
        assert.is_false(Loot.ShouldHide(true, true, { [1] = 60, [2] = 8 }, 0, 10))
    end)

    it("finds the soonest expiry", function()
        assert.is_nil(Loot.SoonestExpiry({}))
        assert.equal(5, Loot.SoonestExpiry({ [1] = 30, [2] = 5, [3] = 12 }))
    end)
end)

describe("Loot roll windows", function()
    local A, container, roll
    local function load(db)
        A = addon.load({ db = db, setup = function(w)
            container = w.NewFrame("Frame", "GroupLootContainer", _G.UIParent)
            -- On the client the roll frames are anchored to the container, not parented to it.
            roll = w.NewFrame("Frame", "GroupLootFrame1", _G.UIParent)
            _G.GetLootRollItemLink = function(id) return "[Item " .. id .. "]" end
        end })
    end
    local function hidden()
        local h = A.ns.Style.hiddenParent
        local c, r = container:GetParent() == h, roll:GetParent() == h
        assert.equal(c, r, "container and roll frame should move together")
        return c
    end
    after_each(function()
        _G.GetLootRollItemLink = nil
        wow.uninstall()
    end)

    it("hides in combat and comes back after", function()
        load()
        A.combat(true)
        assert.is_true(hidden())
        A.fire("START_LOOT_ROLL", 7, 60000)
        assert.matches("loot roll waiting until combat ends: %[Item 7%]", wow.chatText())
        A.combat(false)
        assert.equal(_G.UIParent, container:GetParent())
        assert.equal(_G.UIParent, roll:GetParent())
    end)

    it("hides roll frames that only the container lists, and restores them", function()
        load()
        local pooled = wow.NewFrame("Frame", nil, _G.UIParent)
        container.rollFrames = { pooled }
        A.combat(true)
        assert.equal(A.ns.Style.hiddenParent, pooled:GetParent())
        container.rollFrames = {} -- answered while hidden: still has to go back
        A.combat(false)
        assert.equal(_G.UIParent, pooled:GetParent())
    end)

    it("shows a roll early when it's about to run out", function()
        load()
        A.combat(true)
        A.fire("START_LOOT_ROLL", 7, 60000)
        wow.advance(49)
        assert.is_true(hidden())
        wow.advance(1.5)
        assert.is_false(hidden())
        A.combat(false)
        assert.equal(0, wow.pendingTimers())
    end)

    it("hides again once the urgent roll is answered", function()
        load()
        A.combat(true)
        A.fire("START_LOOT_ROLL", 7, 5000)
        assert.is_false(hidden())
        A.fire("CANCEL_LOOT_ROLL", 7)
        assert.is_true(hidden())
    end)

    it("leaves rolls alone out of combat", function()
        load()
        A.fire("START_LOOT_ROLL", 7, 60000)
        assert.is_false(hidden())
        assert.not_matches("waiting", wow.chatText())
    end)

    it("leaves rolls alone with the setting off, and turning it off restores them", function()
        load({ loot = { delay = false } })
        A.combat(true)
        assert.is_false(hidden())
        A.TF.db.loot.delay = true
        A.TF:ApplyLoot()
        assert.is_true(hidden())
        A.TF.db.loot.delay = false
        A.TF:ApplyLoot()
        assert.is_false(hidden())
    end)
end)
