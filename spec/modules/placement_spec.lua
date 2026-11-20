-- Placement: NPC windows open at the "NPC dialogs" mover instead of Blizzard's
-- top-left panel slot.
local addon = require("support.addon")
local wow = require("support.wow")

describe("Placement NPC windows", function()
    local A, quest, leftPanel
    local function load(db, opts)
        opts = opts or {}
        leftPanel = nil
        A = addon.load({ db = db, setup = function(w)
            quest = w.NewFrame("Frame", "QuestFrame", _G.UIParent)
            quest:Hide()
            if opts.uiPanels then _G.GetUIPanel = function(slot) if slot == "left" then return leftPanel end end end
            if opts.panelPositions then _G.UpdateUIPanelPositions = function() end end
        end })
    end
    -- Blizzard opening the window: shown in the default spot, then OnShow.
    local function open(f)
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", _G.UIParent, "TOPLEFT", 16, -116)
        f:Show()
        wow.run(f, "OnShow")
    end
    local function atDialog(f)
        local point, rel = f:GetPoint(1)
        return f:GetNumPoints() == 1 and point == "TOPLEFT" and rel == A.ns.Placement.dialog
    end
    after_each(function()
        _G.GetUIPanel, _G.UpdateUIPanelPositions = nil, nil
        wow.uninstall()
    end)

    it("opens the quest window at the NPC dialogs box", function()
        load()
        open(quest)
        assert.is_true(atDialog(quest))
    end)

    it("puts it back after Blizzard re-places it a frame later", function()
        load()
        open(quest)
        quest:ClearAllPoints()
        quest:SetPoint("TOPLEFT", _G.UIParent, "TOPLEFT", 16, -116)
        wow.advance(0)
        assert.is_true(atDialog(quest))
    end)

    it("re-places after Blizzard lays out its panels", function()
        load(nil, { panelPositions = true })
        open(quest)
        quest:ClearAllPoints()
        _G.UpdateUIPanelPositions()
        assert.is_true(atDialog(quest))
    end)

    it("leaves windows alone with the setting off", function()
        load({ npcDialogs = { enabled = false } })
        open(quest)
        wow.advance(0)
        assert.is_false(atDialog(quest))
    end)

    it("only moves the window in the left panel slot", function()
        load(nil, { uiPanels = true })
        leftPanel = wow.NewFrame("Frame", "CharacterFrame", _G.UIParent)
        open(quest)
        wow.advance(0)
        assert.is_false(atDialog(quest))
        leftPanel = quest
        assert.is_true(A.ns.Placement.ShouldPlaceDialog(quest))
    end)

    it("hooks load-on-demand windows when their add-on loads", function()
        load()
        local trainer = wow.NewFrame("Frame", "ClassTrainerFrame", _G.UIParent)
        A.fire("ADDON_LOADED", "Blizzard_TrainerUI")
        open(trainer)
        assert.is_true(atDialog(trainer))
    end)

    it("skips hidden or missing windows", function()
        load()
        assert.is_false(A.ns.Placement.ShouldPlaceDialog(nil))
        assert.is_false(A.ns.Placement.ShouldPlaceDialog(quest))
        assert.has_no.errors(function() A.ns.Placement.PlaceDialogs() end)
    end)

    it("uses a saved position for the box", function()
        load({ positions = { npcDialog = { "CENTER", "CENTER", 120, 40 } } })
        local point, rel, relPoint, x, y = A.ns.Style.movers.npcDialog:GetPoint(1)
        assert.are.same({ "CENTER", _G.UIParent, "CENTER", 120, 40 }, { point, rel, relPoint, x, y })
    end)
end)

describe("Placement micro-button alerts", function()
    local tip, talent, active
    local function load(db, opts)
        opts = opts or {}
        addon.load({ db = db, setup = function(w)
            tip = w.NewFrame("Frame", nil, _G.UIParent)
            active = {}
            talent = w.NewFrame("Frame", "TalentMicroButtonAlert", _G.UIParent)
            _G.MainMenuMicroButton_ShowAlert = function() end
            if not opts.noHelpTip then
                _G.HelpTip = {
                    Show = function() end,
                    framePool = { EnumerateActive = function() return pairs(active) end },
                }
            end
        end })
    end
    after_each(function()
        _G.HelpTip, _G.MainMenuMicroButton_ShowAlert = nil, nil
        wow.uninstall()
    end)

    it("clamps named alerts at login", function()
        load()
        assert.is_true(talent:IsClampedToScreen())
    end)

    it("clamps active help tips when an alert shows", function()
        load()
        assert.is_false(tip:IsClampedToScreen())
        active[tip] = true
        _G.MainMenuMicroButton_ShowAlert(talent, "You have unspent Talent points.")
        assert.is_true(tip:IsClampedToScreen())
        _G.HelpTip:Show(_G.UIParent, {})
        assert.is_true(tip:IsClampedToScreen())
    end)

    it("leaves alerts alone with keepClear off", function()
        load({ keepClear = false })
        active[tip] = true
        _G.MainMenuMicroButton_ShowAlert(talent, "x")
        _G.HelpTip:Show(_G.UIParent, {})
        assert.is_false(talent:IsClampedToScreen())
        assert.is_false(tip:IsClampedToScreen())
    end)

    it("works without HelpTip", function()
        load(nil, { noHelpTip = true })
        _G.MainMenuMicroButton_ShowAlert(talent, "x")
        assert.is_true(talent:IsClampedToScreen())
    end)
end)
