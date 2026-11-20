-- Modules/Options.lua: the /tf window's collapsible sections and settings paths.
local addon = require("support.addon")
local wow = require("support.wow")

describe("Options collapse state", function()
    after_each(function() wow.uninstall() end)

    it("starts the heavy sections folded and the rest open", function()
        local A = addon.load()
        local Options, db = A.ns.Options, A.TF.db
        assert.is_true(Options.IsCollapsed(db, "Hide"))
        assert.is_true(Options.IsCollapsed(db, "Alerts"))
        assert.is_true(Options.IsCollapsed(db, "Frames"))
        assert.is_false(Options.IsCollapsed(db, "Pull report"))
        assert.is_false(Options.IsCollapsed(db, "Appearance"))
    end)

    it("round-trips a section's folded state through the saved settings", function()
        local A = addon.load()
        local Options, db = A.ns.Options, A.TF.db
        Options.SetCollapsed(db, "Hide", false)
        assert.is_false(Options.IsCollapsed(db, "Hide"))
        assert.is_false(db.options.collapsed.Hide)
        Options.SetCollapsed(db, "Hide", true)
        assert.is_true(Options.IsCollapsed(db, "Hide"))
    end)

    it("reads a section absent from the saved table as open", function()
        local A = addon.load()
        assert.is_false(A.ns.Options.IsCollapsed(A.TF.db, "NotASection"))
    end)
end)

describe("Options.FlowButtons", function()
    local FlowButtons
    setup(function()
        FlowButtons = require("support.addon").load().ns.Options.FlowButtons
    end)
    teardown(function() wow.uninstall() end)

    it("keeps buttons that fit on one row, a gap apart", function()
        local spots, h = FlowButtons({ 50, 60, 70 }, 200, 4, 22)
        assert.same({ { x = 0, y = 0 }, { x = 54, y = 0 }, { x = 118, y = 0 } }, spots)
        assert.equal(22, h)
    end)

    it("wraps a button that doesn't fit to the start of the next row", function()
        local spots, h = FlowButtons({ 100, 100, 100 }, 250, 4, 22)
        assert.same({ x = 104, y = 0 }, spots[2])
        assert.same({ x = 0, y = -26 }, spots[3])
        assert.equal(48, h)
    end)

    it("gives an over-wide button its own row and handles no buttons", function()
        local spots = FlowButtons({ 300, 50 }, 250, 4, 22)
        assert.same({ x = 0, y = 0 }, spots[1])
        assert.same({ x = 0, y = -26 }, spots[2])
        local none, h = FlowButtons({}, 250, 4, 22)
        assert.same({}, none)
        assert.equal(0, h)
    end)
end)

describe("Options window", function()
    after_each(function() wow.uninstall() end)

    it("opens without errors", function()
        local A = addon.load()
        assert.has_no.errors(function() A.slash("") end)
    end)

    it("reads and writes settings by key path", function()
        local A = addon.load()
        local TF = A.TF
        assert.is_true(TF.GetSetting({ "party", "enabled" }))
        TF.SetSetting({ "party", "enabled" }, false)
        assert.is_false(TF.db.party.enabled)
        TF.SetSetting({ "scale" }, 1.2)
        assert.are.equal(1.2, TF.GetSetting({ "scale" }))
    end)

    it("folds a collapsed section's rows away on open", function()
        local A = addon.load()
        A.slash("")
        -- Frames starts collapsed by default; Pull report starts open.
        assert.is_false(A.ns.Options.sections["Frames"].content:IsShown())
        assert.is_true(A.ns.Options.sections["Pull report"].content:IsShown())
    end)

    it("shows and hides a section's rows and resizes the window when toggled", function()
        local A = addon.load()
        A.slash("")
        local win = _G.TankForgeUIOptions
        local frames = A.ns.Options.sections["Frames"]

        local folded = win:GetHeight()
        wow.run(frames.header, "OnClick")          -- expand
        assert.is_true(frames.content:IsShown())
        assert.is_true(A.ns.Options.IsCollapsed(A.TF.db, "Frames") == false)
        assert.is_true(win:GetHeight() > folded)

        wow.run(frames.header, "OnClick")          -- collapse again
        assert.is_false(frames.content:IsShown())
        assert.are.equal(folded, win:GetHeight())
    end)

    it("honors saved folded state when the window is built", function()
        local A = addon.load({ db = { options = { collapsed = { Hide = false } } } })
        A.slash("")
        assert.is_true(A.ns.Options.sections["Hide"].content:IsShown())
    end)

    it("lays out the footer with a real size and a working Move frames button", function()
        local A = addon.load()
        A.slash("")
        local footer = A.ns.Options.footer
        local w, h = footer:GetSize()
        assert.is_true(w > 0 and h > 0, "footer needs a width and a height or nothing in it draws")
        local Style = A.ns.Style
        local real, got = Style.SetUnlocked, nil
        Style.SetUnlocked = function(on) got = on end
        wow.run(footer.buttons["Move frames"], "OnClick")
        Style.SetUnlocked = real
        assert.is_true(got)
        assert.is_false(_G.TankForgeUIOptions:IsShown())
    end)

    it("keeps choice buttons apart and inside their column", function()
        local A = addon.load()
        A.slash("")
        for _, key in ipairs({ "alerts.lapseWhere", "hideObjectives" }) do
            local group = A.ns.Options.choices[key]
            assert.is_true(#group > 0, key)
            for i, b in ipairs(group) do
                local _, x, y = b:GetPoint(1)
                assert.is_true(x + b:GetWidth() <= 270, key .. " button runs past the column")
                assert.is_true(b:GetWidth() >= b.label:GetStringWidth(), key .. " label wider than its button")
                for j = i + 1, #group do
                    local o = group[j]
                    local _, ox, oy = o:GetPoint(1)
                    if oy == y then
                        assert.is_true(x + b:GetWidth() <= ox or ox + o:GetWidth() <= x, key .. " buttons overlap")
                    end
                end
            end
        end
    end)
end)
