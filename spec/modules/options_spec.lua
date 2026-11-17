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
end)
