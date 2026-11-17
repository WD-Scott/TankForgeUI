-- Modules/Charts.lua: the timeline encoding and chart math.
local addon = require("support.addon")
local wow = require("support.wow")

describe("Charts", function()
    local Charts
    before_each(function() Charts = addon.load().ns.Charts end)
    after_each(function() wow.uninstall() end)

    local function tl(n, att, cov, hit) return { n = n, att = att or {}, cov = cov or {}, hit = hit or {} } end

    describe("EncodeTimeline", function()
        it("encodes each second's state and hits", function()
            local e = Charts.EncodeTimeline(tl(4, { [2] = true, [3] = true, [4] = true },
                { [2] = 2, [3] = -1 }, { [2] = 3, [4] = 12 }), 4)
            assert.are.same({ n = 4, s = "0123", h = "0309" }, e)
        end)

        it("counts a tie between covered and uncovered ticks as covered", function()
            assert.are.equal("1", Charts.EncodeTimeline(tl(1, { true }, { 0 }), 1).s)
        end)

        it("pads to the pull's duration", function()
            assert.are.equal(6, Charts.EncodeTimeline(tl(2), 5.2).n)
        end)

        it("caps at MAX_SECONDS and keeps the truncated flag", function()
            local raw = tl(Charts.MAX_SECONDS)
            raw.trunc = true
            local e = Charts.EncodeTimeline(raw, 5000)
            assert.are.equal(Charts.MAX_SECONDS, e.n)
            assert.are.equal(Charts.MAX_SECONDS, #e.s)
            assert.is_true(e.trunc)
        end)

        it("is nil for nothing to show", function()
            assert.is_nil(Charts.EncodeTimeline(nil, 10))
            assert.is_nil(Charts.EncodeTimeline(tl(0), 0))
        end)
    end)

    describe("Spans", function()
        it("merges runs of the same state", function()
            assert.are.same({
                { from = 1, to = 2, state = "0" }, { from = 3, to = 5, state = "1" }, { from = 6, to = 6, state = "2" },
            }, Charts.Spans("001112"))
        end)

        it("handles one state and the empty string", function()
            assert.are.same({ { from = 1, to = 3, state = "3" } }, Charts.Spans("333"))
            assert.are.same({}, Charts.Spans(""))
        end)
    end)

    describe("Bin", function()
        it("sums seconds into columns and finds the peak", function()
            local sums, peak = Charts.Bin("123456", 6, 3)
            assert.are.same({ 3, 7, 11 }, sums)
            assert.are.equal(11, peak)
        end)

        it("gives every column at least one second", function()
            local sums = Charts.Bin("21", 2, 2)
            assert.are.same({ 2, 1 }, sums)
        end)

        it("covers every second exactly once", function()
            local h = "123456789123456789123"
            local sums = Charts.Bin(h, #h, 5)
            local total, want = 0, 0
            for _, s in ipairs(sums) do total = total + s end
            for d in h:gmatch("%d") do want = want + tonumber(d) end
            assert.are.equal(want, total)
        end)
    end)

    it("draws a timeline without errors", function()
        local t = Charts.Timeline(wow.NewFrame(), 290, 30, { legend = true })
        assert.has_no.errors(function()
            t:SetData({ n = 8, s = "00112230", h = "01234500" }, { { t = 3 } }, "Shield Block")
            t:SetData(nil)
        end)
    end)

    it("draws bars and dots without errors", function()
        local b = Charts.Bars(wow.NewFrame(), 200, 26)
        local d = Charts.Dots(wow.NewFrame(), 200, 26)
        assert.has_no.errors(function()
            b:SetData({ { value = 80, weight = 2 }, { value = nil }, { value = 120, outline = { 1, 1, 1 } } },
                { max = 100, ref = 75 })
            b:SetData({})
            d:SetData({
                { value = 3, color = Charts.series[1], letter = "A" },
                { value = 3, color = Charts.series[2], letter = "B" },
                { value = nil, color = Charts.series[3] },
            })
            d:SetData({})
        end)
    end)
end)
