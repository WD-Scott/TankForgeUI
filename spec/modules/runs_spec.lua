-- Modules/Runs.lua: whole dungeon runs, their metrics and comparisons.
local addon = require("support.addon")
local wow = require("support.wow")
local fixtures = require("support.fixtures")

local DEADMINES = { name = "The Deadmines", type = "party", difficultyID = 1, difficultyName = "Normal", id = 36 }
local STOCKADE = { name = "The Stockade", type = "party", difficultyID = 1, difficultyName = "Normal", id = 34 }
local OUTSIDE = { name = "Eastern Kingdoms", type = "none", difficultyID = 0, id = 0 }

describe("Runs", function()
    local A, Runs, TF, w
    local function load(db, reload)
        db = db or {}
        db.runs = db.runs or { enabled = true }
        A = addon.load({ db = db, world = { form = 18 }, reload = reload })
        Runs, TF, w = A.ns.Runs, A.TF, wow.world
    end
    local function go(instance)
        w.instance = instance
        A.fire("ZONE_CHANGED_NEW_AREA")
    end
    local function pull(over) TF:Fire("PULL_END", fixtures.pull(over)) end
    after_each(function() wow.uninstall() end)

    describe("recording", function()
        it("starts a run on entering a dungeon", function()
            load()
            go(DEADMINES)
            local run = TF.db.currentRun
            assert.are.equal("The Deadmines", run.instance)
            assert.are.equal("36:1", run.key)
            assert.are.equal("Normal", run.difficulty)
        end)

        it("does nothing while turned off", function()
            load({ runs = { enabled = false } })
            go(DEADMINES)
            assert.is_nil(TF.db.currentRun)
        end)

        it("adds dungeon pulls in compact form", function()
            load()
            go(DEADMINES)
            pull({ duration = 61.26, deaths = { { t = 12.34, ready = {} } }, encounter = "VanCleef" })
            pull({ duration = 3 })
            pull({ instance = false })
            local pulls = TF.db.currentRun.pulls
            assert.are.equal(1, #pulls)
            assert.are.equal(61.3, pulls[1].d)
            assert.are.same({ 12.3 }, pulls[1].deaths)
            assert.are.equal("VanCleef", pulls[1].boss)
            assert.is_true(pulls[1].known)
            assert.are.equal("Shield Block", TF.db.currentRun.am)
        end)

        it("records boss kills and wipes", function()
            load()
            go(DEADMINES)
            A.fire("ENCOUNTER_END", 1, "VanCleef", 1, 5, 0)
            A.fire("ENCOUNTER_END", 1, "VanCleef", 1, 5, 1)
            local bosses = TF.db.currentRun.bosses
            assert.are.equal(2, #bosses)
            assert.is_false(bosses[1].ok)
            assert.is_true(bosses[2].ok)
        end)

        it("keeps the run through a short trip outside", function()
            load()
            go(DEADMINES)
            local id = TF.db.currentRun.id
            go(OUTSIDE)
            assert.is_number(TF.db.currentRun.leftAt)
            wow.advance(600)
            go(DEADMINES)
            assert.are.equal(id, TF.db.currentRun.id)
            assert.is_nil(TF.db.currentRun.leftAt)
        end)

        it("ends the run 15 minutes after leaving, keeping it with 3+ pulls", function()
            load()
            go(DEADMINES)
            for _ = 1, 3 do pull() end
            wow.advance(1200)
            go(OUTSIDE)
            wow.advance(15 * 60 - 5)
            assert.is_table(TF.db.currentRun)
            wow.advance(10)
            assert.is_nil(TF.db.currentRun)
            assert.are.equal(1, #TF.db.runHistory)
            local run = TF.db.runHistory[1]
            assert.is_nil(run.leftAt)
            assert.is_true(run.finish > run.start)
        end)

        it("drops a run with fewer than 3 pulls", function()
            load()
            go(DEADMINES)
            pull()
            go(OUTSIDE)
            wow.advance(15 * 60 + 5)
            assert.is_nil(TF.db.currentRun)
            assert.are.equal(0, #TF.db.runHistory)
        end)

        it("ends the run on entering a different dungeon", function()
            load()
            go(DEADMINES)
            for _ = 1, 3 do pull() end
            go(STOCKADE)
            assert.are.equal("The Stockade", TF.db.currentRun.instance)
            assert.are.equal("The Deadmines", TF.db.runHistory[1].instance)
        end)

        it("ends a run last seen over 15 minutes ago on a fresh login, but not on a reload", function()
            local function stale()
                return { id = 1, key = "36:1", instance = "The Deadmines", start = 0, pulls = {}, bosses = {},
                    lastSeen = 1767225600 + 1000 - 3600 } -- an hour before the test clock's time()
            end
            load({ currentRun = stale() }, true)
            assert.is_table(TF.db.currentRun)
            wow.uninstall()
            load({ currentRun = stale() })
            assert.is_nil(TF.db.currentRun)
        end)

        it("ends the run when recording is turned off", function()
            load()
            go(DEADMINES)
            TF.db.runs.enabled = false
            Runs:Check()
            assert.is_nil(TF.db.currentRun)
        end)

        it("keeps only runs.keep runs", function()
            load({ runs = { enabled = true, keep = 2, toast = false } })
            for i = 1, 3 do
                go(i % 2 == 1 and DEADMINES or STOCKADE)
                for _ = 1, 3 do pull() end
            end
            A.slash("run end")
            assert.are.equal(2, #TF.db.runHistory)
        end)

        it("/tf run says what's going on and ends it", function()
            load()
            A.slash("run")
            assert.matches("not in a run", wow.chatText())
            go(DEADMINES)
            A.slash("run")
            assert.matches("recording The Deadmines: 0 pulls so far", wow.chatText())
            A.slash("run end")
            assert.matches("wasn't kept %(runs need 3%)", wow.chatText())
            assert.is_nil(TF.db.currentRun)
        end)
    end)

    describe("Metrics", function()
        it("adds up pulls and rates per minute of combat", function()
            load()
            local run = fixtures.run(3, { bosses = {
                { name = "Rhahk'Zor", ok = true }, { name = "VanCleef", ok = false }, { name = "VanCleef", ok = true },
            } })
            run.pulls[2].deaths = { 30 }
            run.pulls[3].lost = 3
            local m = Runs.Metrics(run)
            assert.are.equal(3, m.pulls)
            assert.are.equal(180, m.combat)
            assert.are.equal(1800, m.clear)
            assert.are.equal(75, m.coverage)
            assert.are.equal(3, m.longest)
            assert.are.equal(6, m.unmitPM)
            assert.are.equal(1, m.lostPM)
            assert.are.equal(1, m.deaths)
            assert.are.same({ 2, 2, 1 }, { m.bosses, m.bossTotal, m.wipes })
        end)

        it("leaves mitigation numbers out when it wasn't tracked", function()
            load()
            local run = fixtures.run(2)
            for _, p in ipairs(run.pulls) do p.known = nil end
            local m = Runs.Metrics(run)
            assert.is_nil(m.coverage)
            assert.is_nil(m.longest)
            assert.is_nil(m.unmitPM)
        end)

        it("handles a run with no combat", function()
            load()
            local m = Runs.Metrics(fixtures.run(0))
            assert.are.equal(0, m.lostPM)
            assert.is_nil(m.coverage)
        end)
    end)

    describe("Delta", function()
        it("knows which direction is better", function()
            load()
            assert.are.same({ -10, true, false }, { Runs.Delta({ lower = true }, 90, 100) })
            assert.are.same({ 5, true, false }, { Runs.Delta({ lower = false }, 80, 75) })
            assert.are.same({ 5, false, false }, { Runs.Delta({ lower = true }, 80, 75) })
            assert.is_true(select(3, Runs.Delta({ lower = true }, 1, 1)))
        end)

        it("formats every metric's value and delta", function()
            load()
            for _, def in ipairs(Runs.METRICS) do
                assert.is_string(def.fmt(12.5))
                assert.is_string(def.delta(-2.5))
            end
        end)
    end)

    it("opens the run window and the comparison without errors", function()
        load()
        TF.db.runHistory = { fixtures.run(3, { id = 3 }), fixtures.run(4, { id = 2 }), fixtures.run(3, { id = 1 }) }
        assert.has_no.errors(function()
            A.slash("runs")
            Runs:Show("compare")
            Runs:Show("latest")
            Runs:Toast(TF.db.runHistory[1])
        end)
    end)
end)
