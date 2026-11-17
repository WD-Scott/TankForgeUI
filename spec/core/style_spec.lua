-- Core/Style.lua: colors, frame opacity and movers.
local addon = require("support.addon")
local wow = require("support.wow")

describe("Style", function()
    local A, TF, Style
    local function load(db)
        A = addon.load({ db = db })
        TF, Style = A.TF, A.ns.Style
    end
    after_each(function() wow.uninstall() end)

    it("Hex rounds each channel", function()
        load()
        assert.are.equal("ff4d4d", Style.Hex({ 1, 0.3, 0.3 }))
        assert.are.equal("000000", Style.Hex({ 0, 0, 0 }))
        assert.are.equal(Style.Hex(Style.colors.bad), Style.HEX.bad)
    end)

    it("RoundPortrait has a masked texture and a ring that recolors", function()
        load()
        local p = Style.RoundPortrait(_G.UIParent, 39)
        assert.is_not_nil(p.tex)
        assert.is_not_nil(p.tex.mask)
        assert.are.equal(p.ring, p.borderTextures[1])
        local got
        local set = p.ring.SetVertexColor
        p.ring.SetVertexColor = function(self, r, ...) got = r return set(self, r, ...) end
        Style.SetBorderColor(p, 0.5, 0, 0, 1)
        assert.are.equal(0.5, got)
    end)

    it("PowerColor", function()
        load()
        assert.are.equal(Style.colors.rage, Style.PowerColor(1))
        assert.are.equal(Style.colors.energy, Style.PowerColor(3))
        assert.are.equal(Style.colors.mana, Style.PowerColor(0))
        assert.are.equal(Style.colors.mana, Style.PowerColor(nil))
    end)

    it("SetText only touches the widget when the text changes", function()
        load()
        local fs = wow.NewFrame("FontString")
        local calls = 0
        rawset(fs, "SetText", function() calls = calls + 1 end)
        Style.SetText(fs, "a")
        Style.SetText(fs, "a")
        Style.SetText(fs, nil)
        assert.are.equal(2, calls)
    end)

    it("SetRoleIcon shows known roles, hides the rest, and only redraws on a change", function()
        load()
        local tex = Style.RoleIcon(_G.UIParent, 14)
        assert.is_false(tex:IsShown())
        local calls = 0
        rawset(tex, "SetTexCoord", function() calls = calls + 1 end)
        Style.SetRoleIcon(tex, "TANK")
        Style.SetRoleIcon(tex, "TANK")
        assert.is_true(tex:IsShown())
        assert.are.equal("TANK", tex.role)
        assert.are.equal(1, calls)
        Style.SetRoleIcon(tex, "DAMAGER")
        assert.are.equal(2, calls)
        for _, role in ipairs({ "NONE", "nonsense" }) do
            Style.SetRoleIcon(tex, "HEALER")
            Style.SetRoleIcon(tex, role)
            assert.is_false(tex:IsShown())
        end
        Style.SetRoleIcon(tex, nil)
        assert.is_false(tex:IsShown())
    end)

    it("SetAlertBorder recolors only when the alert turns on or off", function()
        load()
        local f = wow.NewFrame("Frame")
        local tex = wow.NewFrame("Texture")
        f.borderTextures = { tex }
        local calls, last = 0, nil
        tex.SetVertexColor = function(_, r, g, b, a) calls = calls + 1 last = { r, g, b, a } end
        Style.SetAlertBorder(f, false)
        Style.SetAlertBorder(f, nil)
        assert.are.equal(1, calls)
        assert.are.same({ 0, 0, 0, 1 }, last)
        Style.SetAlertBorder(f, true, 0.95)
        Style.SetAlertBorder(f, true, 0.95)
        assert.are.equal(2, calls)
        assert.are.same({ 0.95, 0.15, 0.15, 1 }, last)
        Style.SetAlertBorder(f, false)
        assert.are.equal(3, calls)
    end)

    describe("FrameAlpha", function()
        it("uses the out-of-combat alpha out of combat", function()
            load()
            assert.are.equal(0.6, Style.FrameAlpha({ alpha = 1, oocAlpha = 0.6 }))
            assert.are.equal(0.8, Style.FrameAlpha({ alpha = 0.8 }))
        end)

        it("uses the in-combat alpha in combat", function()
            load()
            A.combat(true)
            assert.are.equal(1, Style.FrameAlpha({ alpha = 1, oocAlpha = 0.6 }))
        end)

        it("is fully opaque while unlocked or without settings", function()
            load()
            assert.are.equal(1, Style.FrameAlpha(nil))
            Style.SetUnlocked(true)
            assert.are.equal(1, Style.FrameAlpha({ alpha = 0.2, oocAlpha = 0.2 }))
        end)
    end)

    describe("movers", function()
        it("places frames at their saved position", function()
            load({ positions = { hud = { "TOP", "TOP", 10, -20 } } })
            local p = { Style.movers.hud:GetPoint(1) }
            assert.are.same({ "TOP", _G.UIParent, "TOP", 10, -20 }, p)
        end)

        it("falls back to the default for an unusable saved position", function()
            load({ positions = { hud = { 1, 2 }, threat = "junk" } })
            assert.are.equal("CENTER", (Style.movers.hud:GetPoint(1)))
            assert.are.equal("CENTER", (Style.movers.threat:GetPoint(1)))
        end)

        it("won't unlock in combat, and locks when combat starts", function()
            load()
            A.combat(true)
            Style.SetUnlocked(true)
            assert.is_false(Style.IsUnlocked())
            A.combat(false)
            Style.SetUnlocked(true)
            assert.is_true(Style.IsUnlocked())
            assert.is_true(Style.movers.hud.box:IsShown())
            A.combat(true)
            assert.is_false(Style.IsUnlocked())
        end)

        it("calls onLock once when locked again", function()
            load()
            local n = 0
            Style.SetUnlocked(true, { onLock = function() n = n + 1 end })
            Style.SetUnlocked(false)
            Style.SetUnlocked(false)
            assert.are.equal(1, n)
        end)

        it("reset forgets saved positions", function()
            load({ positions = { hud = { "TOP", "TOP", 10, -20 } } })
            A.slash("reset")
            assert.are.same({}, TF.db.positions)
            assert.are.equal("CENTER", (Style.movers.hud:GetPoint(1)))
        end)
    end)
end)
