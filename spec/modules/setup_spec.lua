-- Modules/Setup.lua, Options.lua and Placement.lua: layout install, settings paths, bag placement.
local addon = require("support.addon")
local wow = require("support.wow")

describe("Setup", function()
    local A, Setup, ns, saved
    local function load(layouts)
        saved = nil
        A = addon.load({ world = { form = 18 } })
        ns = A.ns
        Setup = ns.Setup
        _G.C_EditMode = {
            GetLayouts = function() return { activeLayout = 1, layouts = layouts or {} } end,
            SaveLayouts = function(info) saved = info end,
            ConvertStringToLayoutInfo = function() return { systems = { "new systems" } } end,
            SetActiveLayout = function() end,
        }
    end
    after_each(function() wow.uninstall() end)

    it("FindLayout ignores case", function()
        load()
        local layouts = { { layoutName = "Mine" }, { layoutName = "TANKFORGEUI" }, {} }
        assert.are.equal(2, Setup.FindLayout(layouts, "TankForgeUI"))
        assert.is_nil(Setup.FindLayout({ {} }, "TankForgeUI"))
    end)

    it("installs the layout after the presets and makes it active", function()
        load({ { layoutName = "Mine", systems = {} } })
        local info = Setup.ReadLayouts()
        assert.are.equal("installed", Setup.WriteLayout(info))
        assert.are.equal(2, #saved.layouts)
        assert.are.equal(ns.LAYOUT_NAME, saved.layouts[2].layoutName)
        assert.are.equal(4, saved.activeLayout) -- 2 presets + index 2
    end)

    it("updates an existing layout's systems in place", function()
        load({ { layoutName = ns and ns.LAYOUT_NAME or "TankForgeUI", systems = { "old" }, extra = 1 } })
        assert.are.equal("updated", Setup.WriteLayout(Setup.ReadLayouts()))
        assert.are.same({ "new systems" }, saved.layouts[1].systems)
        assert.are.equal(1, saved.layouts[1].extra)
        assert.are.equal(1, #saved.layouts)
    end)

    it("says why it can't read layouts", function()
        load()
        _G.C_EditMode = nil
        assert.are.same({ nil, "Edit Mode isn't available" }, { Setup.ReadLayouts() })
    end)

    it("reports a layout string the client rejects", function()
        load()
        _G.C_EditMode.ConvertStringToLayoutInfo = function() error("bad") end
        assert.are.same({ nil, "the client didn't accept the layout" }, { Setup.WriteLayout(Setup.ReadLayouts()) })
    end)

    it("/tf setup turns on the CVars and installs the layout", function()
        load()
        A.slash("setup")
        assert.are.equal("1", wow.world.cvars.showTargetOfTarget)
        assert.are.equal("1", wow.world.cvars.nameplateShowEnemies)
        assert.is_table(saved)
        assert.is_true(A.TF.db.welcomed)
    end)

    it("/tf setup waits for the end of combat", function()
        load()
        A.combat(true)
        A.slash("setup")
        assert.is_nil(saved)
        assert.matches("out of combat", wow.chatText())
    end)

    it("LayoutHash is stable and changes with the string", function()
        load()
        assert.are.equal(Setup.LayoutHash("abc"), Setup.LayoutHash("abc"))
        assert.are_not.equal(Setup.LayoutHash("abc"), Setup.LayoutHash("abd"))
        assert.matches("^%x%x%x%x%x%x%x%x$", Setup.LayoutHash(ns.LAYOUT_STRING))
    end)

    it("/tf setup remembers which layout it wrote", function()
        load()
        A.slash("setup")
        assert.are.equal(Setup.LayoutHash(ns.LAYOUT_STRING), A.TF.db.layoutHash)
    end)

    it("LayoutNotice only for a welcomed player with an older TankForgeUI layout, once", function()
        load()
        assert.is_true(Setup.LayoutNotice({ welcomed = true }, true, "h"))
        assert.is_false(Setup.LayoutNotice({ welcomed = true, layoutHash = "h" }, true, "h"))
        assert.is_false(Setup.LayoutNotice({ welcomed = true, layoutNoticed = "h" }, true, "h"))
        assert.is_false(Setup.LayoutNotice({ welcomed = true }, false, "h"))
        assert.is_false(Setup.LayoutNotice({ welcomed = false }, true, "h"))
    end)

    it("says at login, once, that a newer layout is available", function()
        load({ { layoutName = "TANKFORGEUI", systems = {} } })
        A.TF.db.welcomed = true
        A.fire("PLAYER_ENTERING_WORLD", true, false)
        wow.advance(4.1)
        local _, n = wow.chatText():gsub("newer TankForgeUI layout", "")
        assert.are.equal(1, n)
        A.fire("PLAYER_ENTERING_WORLD", true, false)
        wow.advance(4.1)
        _, n = wow.chatText():gsub("newer TankForgeUI layout", "")
        assert.are.equal(1, n)
    end)

    describe("active layout", function()
        -- The user's client: GetLayouts lists 7 (TankForgeUI last), Edit Mode's own list
        -- puts it at 10, one more than presets (2) + 7.
        local function userLayouts()
            local l = {}
            for i = 1, 6 do l[i] = { layoutName = "L" .. i, systems = {} } end
            l[7] = { layoutName = "TANKFORGEUI", systems = { "old" } }
            return l
        end
        local function manager(active)
            local list = { {}, {}, {} }
            for _, x in ipairs(userLayouts()) do list[#list + 1] = { layoutName = x.layoutName } end
            _G.EditModeManagerFrame = { layoutInfo = { layouts = list, activeLayout = active },
                IsShown = function() return false end }
        end
        after_each(function() _G.EditModeManagerFrame = nil end)

        it("takes the number from Edit Mode's own list, not presets + index", function()
            load()
            manager(10)
            local mgr = _G.EditModeManagerFrame.layoutInfo.layouts
            assert.are.equal(10, Setup.ActiveIndexFor(mgr, userLayouts(), "TankForgeUI"))
            assert.are.equal(9, Setup.ActiveIndexFor(nil, userLayouts(), "TankForgeUI"))
        end)

        it("puts a new layout at the end of Edit Mode's list", function()
            load()
            local layouts = userLayouts()
            layouts[7].layoutName = "Other"
            layouts[8] = { layoutName = "TankForgeUI" }
            assert.are.equal(11, Setup.ActiveIndexFor({ {}, {}, {}, {}, {}, {}, {}, {}, {}, {} }, layouts, "TankForgeUI"))
        end)

        it("updates the user's layout and keeps it active", function()
            load(userLayouts())
            manager(10)
            assert.are.equal("updated", Setup.WriteLayout(Setup.ReadLayouts()))
            assert.are.equal(10, saved.activeLayout)
        end)

        it("warns once after the reload when another layout is active", function()
            load()
            A.TF.db.layoutCheck = true
            manager(9)
            A.fire("PLAYER_ENTERING_WORLD", false, true)
            wow.advance(2.1)
            assert.matches('Edit Mode is using "L6", not TankForgeUI', wow.chatText())
            assert.is_nil(A.TF.db.layoutCheck)
        end)

        it("says nothing when TankForgeUI is active", function()
            load()
            A.TF.db.layoutCheck = true
            manager(10)
            assert.is_nil(Setup.WrongActiveLayout())
            A.fire("PLAYER_ENTERING_WORLD", false, true)
            wow.advance(2.1)
            assert.is_nil(wow.chatText():match("Edit Mode is using"))
        end)
    end)

    it("offers setup a few seconds after the first login", function()
        load()
        local before = #wow.frames
        wow.advance(5)
        assert.is_true(#wow.frames > before)
    end)
end)

describe("Placement", function()
    local A, bags
    -- Three 200x300 bags open, on a 1920x1080 screen.
    local function load(opts)
        opts = opts or {}
        A = addon.load({ catchErrors = opts.catchErrors, setup = function(w)
            _G.UpdateContainerFrameAnchors = function() end
            bags = {}
            for i = 1, opts.bags or 3 do
                local f = w.NewFrame("Frame", "ContainerFrame" .. i)
                f:SetSize(200, 300)
                rawset(f, "GetBagID", function() return i - 1 end)
                bags[i] = f
            end
            _G.UIParent:SetSize(1920, 1080)
        end })
    end
    local function point(f) return { select(4, f:GetPoint(1)) } end
    after_each(function() wow.uninstall() end)

    it("stacks bags up from the bottom right", function()
        load()
        _G.UpdateContainerFrameAnchors()
        assert.are.same({ 1914, 6 }, point(bags[1]))
        assert.are.same({ 1914, 312 }, point(bags[2]))
        assert.are.same({ 1914, 618 }, point(bags[3]))
    end)

    it("wraps into a new column before the top of the screen", function()
        load({ bags = 4 })
        _G.UpdateContainerFrameAnchors()
        assert.are.same({ 1708, 6 }, point(bags[4]))
    end)

    it("leaves bags alone when turned off", function()
        load()
        A.TF.db.keepClear = false
        _G.UpdateContainerFrameAnchors()
        assert.is_nil(bags[1]:GetPoint(1))
    end)

    it("keeps placing bags after a failed layout", function()
        load({ catchErrors = true })
        rawset(bags[2], "GetEffectiveScale", function() error("broken bag") end)
        _G.UpdateContainerFrameAnchors()
        rawset(bags[2], "GetEffectiveScale", nil)
        _G.UpdateContainerFrameAnchors()
        assert.are.same({ 1914, 312 }, point(bags[2]))
    end)
end)
