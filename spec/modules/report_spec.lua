-- Modules/Report.lua: pull records, notes and the pull history.
local addon = require("support.addon")
local wow = require("support.wow")
local fixtures = require("support.fixtures")

describe("Report", function()
    local A, Report, TF
    local function load(db)
        A = addon.load({ db = db, world = { form = 18, known = { [2565] = true, [1160] = true } } })
        Report, TF = A.ns.Report, A.TF
    end
    local function finish(over) A.TF:Fire("PULL_END", fixtures.pull(over)) end
    after_each(function() wow.uninstall() end)

    it("Pct rounds and refuses a zero base", function()
        load()
        assert.are.equal(75, Report.Pct(15, 20))
        assert.are.equal(67, Report.Pct(2, 3))
        assert.is_nil(Report.Pct(1, 0))
        assert.is_nil(Report.Pct(1, nil))
    end)

    it("CoverageColorFor grades against the target", function()
        load()
        local C = A.ns.Style.colors
        assert.are.equal(C.good, Report.CoverageColorFor(75, 0.75))
        assert.are.equal(C.warn, Report.CoverageColorFor(60, 0.75))
        assert.are.equal(C.bad, Report.CoverageColorFor(59, 0.75))
        assert.are.equal(C.good, Report.CoverageColorFor(85, nil))
        assert.are.equal(C.muted, Report.CoverageColorFor(nil, 0.75))
    end)

    describe("MakeRecord", function()
        it("copies the pull's numbers and works out coverage", function()
            load()
            local r = Report.MakeRecord(fixtures.pull())
            assert.are.equal(75, r.coverage)
            assert.are.equal("Deadmines", r.zone)
            assert.are.equal(20, r.hits)
            assert.are.equal(30, r.tl.n) -- padded to the pull's length
            assert.are.equal("120" .. string.rep("0", 27), r.tl.s)
        end)

        it("names secondary mitigation never pressed on a boss or a long pull", function()
            load()
            wow.world.spellNames[1160] = "Demoralizing Shout"
            local function unused(over) return Report.MakeRecord(fixtures.pull(over)).unusedAM end
            assert.are.same({}, unused({ duration = 30 }))
            assert.are.same({ "Demoralizing Shout" }, unused({ duration = 30, encounter = "Commander Springvale" }))
            assert.are.same({ "Demoralizing Shout" }, unused({ duration = 50 }))
            assert.are.same({}, unused({ duration = 50, casts = { demoShout = 1 } }))
        end)
    end)

    describe("Notes", function()
        local function notes(over)
            local r = Report.MakeRecord(fixtures.pull(over))
            r.unusedAM = {}
            return Report.Notes(r)
        end

        it("has nothing to say about a clean pull", function()
            load()
            assert.are.same({}, notes())
        end)

        it("flags coverage under the target", function()
            load()
            assert.are.same({ "Shield Block covered 50% of the time you were being hit. Aim for 75%." },
                notes({ covered = 10 }))
        end)

        it("doesn't judge coverage for a short fight or an untracked spell", function()
            load()
            assert.are.same({}, notes({ covered = 1, underAttack = 4 }))
            assert.are.same({}, notes({ covered = 1, primaryKnown = false }))
        end)

        it("flags a long gap", function()
            load()
            assert.are.same({ "Longest stretch being hit without Shield Block: 4.5s." }, notes({ longestGap = 4.5 }))
        end)

        it("lists who got mobs, sorted, and a missing taunt", function()
            load()
            assert.are.same({ "Mobs went to someone else 3 times: Bob, Stabby x2. You didn't taunt." },
                notes({ aggroLost = 3, aggroLostTo = { Stabby = 2, Bob = 1 }, taunts = 0 }))
        end)

        it("flags mobs on the healer and deaths", function()
            load()
            assert.are.same({ "Mobs were on your healer for 3s.", "Died at 1:05 with Shield Wall still ready.",
                "Died at 2:00." },
                notes({ healerAttacked = 3, deaths = { { t = 65, ready = { "Shield Wall" } }, { t = 120, ready = {} } } }))
        end)
    end)

    describe("history", function()
        it("records dungeon pulls, newest first, and shows the report", function()
            load()
            finish({ zone = "First" })
            finish({ zone = "Second" })
            assert.are.equal("Second", TF.db.history[1].zone)
            assert.are.equal(2, #TF.db.history)
            assert.is_true(Report.frame:IsShown())
        end)

        it("skips short pulls, pulls with few hits, and the open world", function()
            load()
            finish({ duration = 5 })
            finish({ hits = 2 })
            finish({ instance = false })
            assert.are.equal(0, #TF.db.history)
        end)

        it("records the open world when asked", function()
            load({ report = { openWorld = true } })
            finish({ instance = false })
            assert.are.equal(1, #TF.db.history)
        end)

        it("keeps the last 100", function()
            load()
            for i = 1, 105 do finish({ zone = "Z" .. i }) end
            assert.are.equal(100, #TF.db.history)
            assert.are.equal("Z105", TF.db.history[1].zone)
            assert.are.equal("Z6", TF.db.history[100].zone)
        end)

        it("records nothing when turned off", function()
            load({ report = { enabled = false } })
            finish()
            assert.are.equal(0, #TF.db.history)
        end)

        it("hides itself after a while unless the mouse is on it", function()
            load()
            finish()
            wow.advance(26)
            wow.run(Report.frame, "OnUpdate", 0.1)
            assert.is_false(Report.frame:IsShown())
        end)

        it("pages through older pulls", function()
            load()
            finish({ zone = "Old" })
            finish({ zone = "New" })
            A.slash("report")
            assert.matches("New", Report.frame.title:GetText())
            assert.is_true(Report:Render(2))
            assert.matches("Old", Report.frame.title:GetText())
            assert.is_false(Report:Render(3))
        end)
    end)

    it("When says Today for today", function()
        load()
        assert.matches("^Today %d%d:%d%d$", Report.When(_G.time()))
        assert.matches("^%a%a%a %d%d %d%d:%d%d$", Report.When(_G.time() - 86400 * 3))
        assert.are.equal("", Report.When(nil))
    end)
end)
