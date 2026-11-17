-- The frame modules: HUD, Party, Hide. These mostly draw; the checks here are on
-- the decisions they make (what shows, what's hidden, who goes where).
local addon = require("support.addon")
local wow = require("support.wow")

describe("HUD", function()
    after_each(function() wow.uninstall() end)

    it("shows while tanking and hides otherwise", function()
        local A = addon.load({ world = { form = 18, known = { [2565] = true } } })
        local HUD = A.ns.HUD
        assert.is_true(HUD.frame:IsShown())
        wow.world.form = false
        A.fire("UPDATE_SHAPESHIFT_FORM")
        wow.advance(11)
        assert.is_false(HUD.frame:IsShown())
    end)

    it("handles a cast without errors", function()
        local A = addon.load({ world = { form = 18, known = { [2565] = true, [871] = true } } })
        assert.has_no.errors(function()
            A.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 2565)
        end)
    end)

    it("never turns its border red, even hit in combat with Shield Block down", function()
        local A = addon.load({ world = { form = 18, known = { [2565] = true } } })
        local HUD = A.ns.HUD
        A.combat(true)
        A.fire("UNIT_COMBAT", "player", "WOUND", "", 100, 1)
        wow.advance(1)
        assert.is_nil(HUD.frame.tfAlert)
        assert.is_nil(HUD.frame.stanceCol.tfAlert)
        assert.is_nil(HUD.frame:GetScript("OnUpdate"))
    end)

    it("has no mitigation panel and drops the old collapse setting", function()
        local A = addon.load({ db = { hud = { collapsed = true } }, world = { form = 18, known = { [2565] = true } } })
        assert.is_nil(A.ns.HUD.frame.body)
        assert.is_nil(A.TF.db.hud.collapsed)
    end)
end)

describe("HUD layout", function()
    after_each(function() wow.uninstall() end)

    -- A warrior in Defensive Stance with a stance button (Battle Stance) to click.
    local function warrior(db)
        return addon.load({ db = db, world = { form = 18, formSpell = 2457, known = { [2565] = true, [2457] = true } } })
    end

    it("picks full, compact or hidden", function()
        local Mode = addon.load().ns.HUD.Mode
        assert.are.equal("full", Mode(true, true, true, false, true, true))
        assert.are.equal("full", Mode(true, true, false, true, false, false))
        assert.are.equal("compact", Mode(true, true, false, false, true, true))
        assert.are.equal("hidden", Mode(true, true, false, false, false, true))
        assert.are.equal("hidden", Mode(true, true, false, false, true, false))
        assert.are.equal("hidden", Mode(false, true, true, false, true, true))
        assert.are.equal("hidden", Mode(true, false, true, false, true, true))
    end)

    it("stays up, compact, out of tank stance so the stance buttons can be clicked", function()
        local A = warrior()
        local HUD = A.ns.HUD
        assert.are.equal(1, A.ns.Stances.count)
        wow.world.form = false
        A.fire("UPDATE_SHAPESHIFT_FORM")
        wow.advance(11)
        assert.are.equal("compact", HUD.mode)
        assert.is_true(HUD.frame:IsShown())
    end)

    it("hides out of tank stance when showIdle is off", function()
        local A = warrior({ hud = { showIdle = false } })
        wow.world.form = false
        A.fire("UPDATE_SHAPESHIFT_FORM")
        wow.advance(11)
        assert.is_false(A.ns.HUD.frame:IsShown())
    end)

    it("fades instead of hiding the protected top panel in combat, and hides it after", function()
        local A = warrior()
        local HUD = A.ns.HUD
        A.combat(true)
        A.TF.db.hud.enabled = false
        HUD:Refresh()
        assert.is_true(HUD.frame:IsShown())
        assert.are.equal(0, HUD.frame:GetAlpha())
        A.combat(false)
        assert.is_false(HUD.frame:IsShown())
    end)
end)

describe("Stances", function()
    after_each(function() wow.uninstall() end)

    local function load(db)
        return addon.load({ db = db, world = { form = 18, formSpell = 71, known = { [2565] = true, [71] = true } } })
    end

    it("stacks the stance buttons in the HUD's flyout column", function()
        local A = load()
        local col = A.ns.HUD.frame.stanceCol
        local b = A.ns.Stances.buttons[1]
        assert.are.equal(col, b:GetParent())
        assert.are.equal(71, b:GetAttribute("spell"))
        local point, rel, relPoint = b:GetPoint(1)
        assert.are.equal("TOP", point)
        assert.are.equal(col, rel)
        assert.are.equal("TOP", relPoint)
        local size = A.ns.Stances.Fit(A.ns.Stances.count, A.ns.HUD.HEIGHT)
        assert.are.equal(size, b:GetWidth())
        assert.are.equal(size, b:GetHeight())
    end)

    it("stacks several stances downward", function()
        local A = load()
        local S = A.ns.Stances
        local api = A.ns.API
        local real = api.GetShapeshiftForms
        api.GetShapeshiftForms = function()
            return { { spellID = 2457, icon = 1 }, { spellID = 71, icon = 2, active = true }, { spellID = 2458, icon = 3 } }
        end
        A.TF:ApplyStances()
        api.GetShapeshiftForms = real
        assert.are.equal(3, S.count)
        local _, _, _, _, y1 = S.buttons[1]:GetPoint(1)
        local _, _, _, _, y2 = S.buttons[2]:GetPoint(1)
        local _, _, _, _, y3 = S.buttons[3]:GetPoint(1)
        assert.is_true(y2 < y1 and y3 < y2)
        -- The last button ends inside the column.
        assert.is_true(-y3 + S.Fit(3, A.ns.HUD.HEIGHT) <= A.ns.HUD.HEIGHT - 3)
    end)

    it("names the flyout for the class", function()
        local ns = addon.load().ns
        assert.are.equal("Stances", ns.Stances.Label(ns.Kits.WARRIOR))
        assert.are.equal("Forms", ns.Stances.Label(ns.Kits.DRUID))
        assert.are.equal("Auras", ns.Stances.Label(ns.Kits.PALADIN))
        assert.are.equal("Stances", ns.Stances.Label(nil))
    end)

    it("shrinks buttons so the column is the HUD's height", function()
        local Fit = addon.load().ns.Stances.Fit
        assert.are.equal(24, Fit(1, 53))
        assert.are.equal(14, Fit(3, 53))
        for n = 1, 5 do
            assert.is_true(n * Fit(n, 53) + (n - 1) * 2 <= 53 - 7)
        end
    end)

    it("hangs the grip and column off the HUD's top and bottom edges", function()
        local A = load()
        local f = A.ns.HUD.frame
        local function anchors(frame)
            local out = {}
            for i = 1, frame:GetNumPoints() do
                local point, rel, relPoint = frame:GetPoint(i)
                out[point] = { rel, relPoint }
            end
            return out
        end
        local tab, col = anchors(f.stanceTab), anchors(f.stanceCol)
        assert.are.same({ f, "TOPRIGHT" }, tab.TOPLEFT)
        assert.are.same({ f, "BOTTOMRIGHT" }, tab.BOTTOMLEFT)
        assert.are.same({ f.stanceTab, "TOPRIGHT" }, col.TOPLEFT)
        assert.are.same({ f.stanceTab, "BOTTOMRIGHT" }, col.BOTTOMLEFT)
    end)

    it("opens and closes from a secure tab", function()
        local A = load()
        local f = A.ns.HUD.frame
        assert.is_true(f.stanceTab:IsShown())
        assert.is_true(f.stanceCol:IsShown())
        assert.are.equal(f.stanceCol, f.stanceTab:GetAttribute("frameref-col"))
        assert.matches("col:Hide%(%)", f.stanceTab:GetAttribute("_onclick"))
    end)

    it("remembers whether the flyout is open", function()
        local A = load()
        local col = A.ns.HUD.frame.stanceCol
        col:Hide()
        wow.run(col, "OnHide")
        assert.is_false(A.TF.db.stances.open)
        col:Show()
        wow.run(col, "OnShow")
        assert.is_true(A.TF.db.stances.open)
    end)

    it("keeps the flyout closed after a rebuild when it was closed", function()
        local A = load({ stances = { open = false } })
        local f = A.ns.HUD.frame
        assert.is_true(f.stanceTab:IsShown())
        assert.is_false(f.stanceCol:IsShown())
    end)

    it("hides the tab and column when the stance buttons are off, without forgetting open", function()
        local A = load()
        local f = A.ns.HUD.frame
        A.TF.db.stances.enabled = false
        A.TF:ApplyStances()
        wow.run(f.stanceCol, "OnHide")
        assert.is_false(f.stanceTab:IsShown())
        assert.is_false(f.stanceCol:IsShown())
        assert.is_true(A.TF.db.stances.open)
    end)

    -- Counts GetShapeshiftFormInfo calls from here on.
    local function countReads()
        local n = { reads = 0 }
        local real = _G.GetShapeshiftFormInfo
        _G.GetShapeshiftFormInfo = function(...)
            n.reads = n.reads + 1
            return real(...)
        end
        return n
    end

    it("refreshes once per frame, however many usability and cooldown events arrive", function()
        local A = load()
        local n = countReads()
        for _ = 1, 10 do
            A.fire("ACTIONBAR_UPDATE_USABLE")
            A.fire("SPELL_UPDATE_COOLDOWN")
        end
        assert.are.equal(0, n.reads)
        wow.advance(0)
        assert.are.equal(A.ns.Stances.count, n.reads)
    end)

    it("doesn't read the forms while the flyout is closed, and catches up when it opens", function()
        local A = load({ stances = { open = false } })
        local col = A.ns.HUD.frame.stanceCol
        local b = A.ns.Stances.buttons[1]
        assert.is_false(col:IsShown())
        local n = countReads()
        A.fire("UPDATE_SHAPESHIFT_FORM")
        wow.advance(0)
        assert.are.equal(0, n.reads)
        col:Show()
        wow.run(col, "OnShow")
        assert.are.equal(1, n.reads)
        assert.is_true(b.active:IsShown())
    end)

    it("hides Blizzard's stance bar only while the HUD has the buttons", function()
        local A = load()
        local bar = wow.NewFrame("Frame", "StanceBar", _G.UIParent)
        _G.StanceBar = bar
        A.TF:ApplyStances()
        assert.are.equal(A.ns.Style.hiddenParent, bar:GetParent())
        A.TF.db.hud.enabled = false
        A.TF:ApplyStances()
        assert.are.equal(_G.UIParent, bar:GetParent())
        assert.are.equal(0, A.ns.Stances.count)
    end)
end)

describe("Party", function()
    after_each(function() wow.uninstall() end)

    local function load(db)
        return addon.load({ db = db, world = { form = 18, inGroup = true, units = {
            player = { name = "Tanky", class = "WARRIOR" },
            party1 = { name = "Stabby", class = "ROGUE", role = "DAMAGER" },
            party2 = { name = "Holly", class = "PRIEST", role = "HEALER" },
            party3 = { name = "Bow", class = "HUNTER", role = "DAMAGER" },
        } } })
    end
    local function units(A)
        local out = {}
        for _, b in ipairs(A.ns.Party.buttons) do
            if b:IsShown() and b:GetAttribute("unit") then out[#out + 1] = b:GetAttribute("unit") end
        end
        return out
    end

    it("leaves the healer to the healer panel", function()
        local A = load()
        assert.are.same({ "party1", "party3", "party4" }, units(A))
    end)

    it("includes the healer when asked to", function()
        local A = load({ party = { hideHealer = false } })
        assert.are.same({ "party1", "party2", "party3", "party4" }, units(A))
    end)

    it("waits for combat to end to reassign", function()
        local A = load()
        A.combat(true)
        wow.world.units.party2.role = "DAMAGER"
        wow.world.units.party3.role = "HEALER"
        A.fire("GROUP_ROSTER_UPDATE")
        assert.are.same({ "party1", "party3", "party4" }, units(A))
        A.combat(false)
        assert.are.same({ "party1", "party2", "party4" }, units(A))
    end)

    local function roles(A)
        local out = {}
        for _, b in ipairs(A.ns.Party.buttons) do
            if b:IsShown() then out[b.unit] = b.role:IsShown() and b.role.role or "none" end
        end
        return out
    end

    it("shows each member's role icon and follows role changes", function()
        local A = load({ party = { hideHealer = false } })
        A.ns.Party:UpdateAll()
        assert.are.same({ party1 = "DAMAGER", party2 = "HEALER", party3 = "DAMAGER", party4 = "none" }, roles(A))
        wow.world.units.party1.role = "TANK"
        A.fire("PLAYER_ROLES_ASSIGNED")
        -- Drawn on the container's next frame, not inside the event.
        wow.run(A.ns.Party.frame, "OnUpdate", 0.01)
        assert.are.equal("TANK", roles(A).party1)
    end)

    it("finds the button for a member, and none for other units", function()
        local A = load()
        local Party = A.ns.Party
        assert.are.equal(Party.buttons[1], Party.ButtonFor("party1"))
        assert.is_nil(Party.ButtonFor("party2"))  -- the healer has their own panel
        assert.is_nil(Party.ButtonFor("nameplate1"))
        assert.is_nil(Party.ButtonFor("target"))
        assert.is_nil(Party.ButtonFor(nil))
    end)

    it("ignores nameplate threat changes and redraws once for a member's", function()
        local A = load()
        local reads = 0
        local real = _G.UnitThreatSituation
        _G.UnitThreatSituation = function(...)
            reads = reads + 1
            return real(...)
        end
        for i = 1, 20 do A.fire("UNIT_THREAT_SITUATION_UPDATE", "nameplate" .. i) end
        assert.are.equal(0, reads)
        wow.run(A.ns.Party.frame, "OnUpdate", 0.01)
        assert.are.equal(0, reads)
        for _ = 1, 20 do A.fire("UNIT_THREAT_SITUATION_UPDATE", "party1") end
        assert.are.equal(0, reads)
        wow.run(A.ns.Party.frame, "OnUpdate", 0.01)
        assert.is_true(reads > 0 and reads <= #A.ns.Party.buttons)
        _G.UnitThreatSituation = real
    end)

    it("gives a role-less healer the healer icon", function()
        local A = addon.load({ db = { party = { hideHealer = false } }, world = { form = 18, inGroup = true, units = {
            player = { name = "Tanky", class = "WARRIOR" },
            party1 = { name = "Stabby", class = "ROGUE" },
            party2 = { name = "Holly", class = "PRIEST" },
        } } })
        assert.are.equal("party2", A.ns.Healer.unit)
        A.ns.Party:UpdateAll()
        local r = roles(A)
        assert.are.equal("HEALER", r.party2)
        assert.are.equal("none", r.party1)
    end)
end)

describe("Hide", function()
    local A, tracker
    local function load(db)
        A = addon.load({ db = db, setup = function(w)
            tracker = w.NewFrame("Frame", "ObjectiveTrackerFrame", _G.UIParent)
        end })
    end
    local function hidden() return tracker:GetParent() == A.ns.Style.hiddenParent end
    after_each(function() wow.uninstall() end)

    it("hides the quest tracker by default", function()
        load()
        assert.is_true(hidden())
        A.slash("quests never")
        assert.is_false(hidden())
        assert.are.equal(_G.UIParent, tracker:GetParent())
    end)

    it("steps through the modes with no argument", function()
        load({ hideObjectives = "never" })
        A.slash("quests")
        assert.are.equal("always", A.TF.db.hideObjectives)
        A.slash("quests")
        assert.are.equal("instance", A.TF.db.hideObjectives)
        A.slash("quests dungeons")
        assert.are.equal("instance", A.TF.db.hideObjectives)
        A.slash("quests")
        A.slash("quests")
        assert.are.equal("never", A.TF.db.hideObjectives)
    end)

    it("in combat mode, fades the tracker in combat and moves it after", function()
        load({ hideObjectives = "combat" })
        assert.is_false(hidden())
        A.combat(true)
        assert.is_false(hidden())
        assert.are.equal(0, tracker:GetAlpha())
        A.combat(false)
        assert.is_false(hidden())
        assert.are.equal(1, tracker:GetAlpha())
    end)

    it("in dungeon mode, hides it only in an instance", function()
        load({ hideObjectives = "instance" })
        assert.is_false(hidden())
        wow.world.inInstance, wow.world.instanceType = true, "party"
        A.fire("ZONE_CHANGED_NEW_AREA")
        assert.is_true(hidden())
    end)

    it("hides action bar tooltips unless Shift is held, when asked", function()
        load({ shiftShowsTooltips = true })
        local tip = _G.GameTooltip
        tip:Show()
        tip:SetAction(1)
        assert.is_false(tip:IsShown())
        wow.world.shift = true
        tip:Show()
        tip:SetAction(1)
        assert.is_true(tip:IsShown())
        A.slash("tooltips")
        wow.world.shift = false
        tip:SetAction(1)
        assert.is_true(tip:IsShown())
    end)
end)
