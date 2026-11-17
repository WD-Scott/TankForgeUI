-- Core/Core.lua: settings, events, messages, combat queue and slash commands.
local addon = require("support.addon")
local wow = require("support.wow")

describe("Core", function()
    local A, TF
    before_each(function()
        A = addon.load({ upto = "Core/Core.lua", login = false })
        TF = A.TF
    end)
    after_each(function() wow.uninstall() end)

    describe("MergeDefaults", function()
        it("fills missing keys and keeps saved ones", function()
            local db = { scale = 2, hud = { alpha = 0.5 } }
            TF.MergeDefaults(db, { scale = 1, tankMode = "auto", hud = { alpha = 1, enabled = true } })
            assert.are.same({ scale = 2, tankMode = "auto", hud = { alpha = 0.5, enabled = true } }, db)
        end)

        it("keeps saved false values", function()
            local db = { enabled = false }
            TF.MergeDefaults(db, { enabled = true })
            assert.is_false(db.enabled)
        end)

        it("replaces a saved non-table where the default is a table", function()
            local db = { hud = true }
            TF.MergeDefaults(db, { hud = { enabled = true } })
            assert.are.same({ enabled = true }, db.hud)
        end)

        it("keeps keys the defaults don't know", function()
            local db = { old = 1 }
            TF.MergeDefaults(db, {})
            assert.are.equal(1, db.old)
        end)
    end)

    describe("loading", function()
        it("creates the saved settings with every default on ADDON_LOADED", function()
            assert.is_table(_G.TankForgeUIDB)
            assert.are.equal(_G.TankForgeUIDB, TF.db)
            assert.are.equal(3, TF.db.alerts.lapseSeconds)
            assert.are.same({ "LOADED" }, { A.fired[1].name })
        end)

        it("ignores ADDON_LOADED for other add-ons", function()
            A.clearMessages()
            A.fire("ADDON_LOADED", "SomethingElse")
            assert.are.same({}, A.messages())
        end)

        it("keeps existing saved settings", function()
            A = addon.load({ upto = "Core/Core.lua", login = false, db = { tankMode = "always" } })
            assert.are.equal("always", A.TF.db.tankMode)
            assert.are.equal(true, A.TF.db.hud.enabled)
        end)

        it("turns PLAYER_LOGIN and PLAYER_ENTERING_WORLD into messages", function()
            A.fire("PLAYER_LOGIN")
            A.fire("PLAYER_ENTERING_WORLD", false, true)
            assert.are.equal(1, #A.messages("LOGIN"))
            assert.are.same({ n = 2, false, true }, A.messages("ENTERING_WORLD")[1])
        end)
    end)

    describe("events", function()
        it("calls every handler for an event with its arguments", function()
            local got = {}
            TF:RegisterEvent("BAG_UPDATE", function(event, bag) got[#got + 1] = event .. bag end)
            TF:RegisterEvent("BAG_UPDATE", function(_, bag) got[#got + 1] = "second" .. bag end)
            A.fire("BAG_UPDATE", 3)
            assert.are.same({ "BAG_UPDATE3", "second3" }, got)
        end)

        it("returns false when the client rejects the event", function()
            -- Core's event frame already exists: make its RegisterEvent throw, as the client does.
            local function throw() error("unknown event") end
            for _, f in ipairs(wow.frames) do rawset(f, "RegisterEvent", throw) end
            _G.CreateFrame = function()
                local f = wow.NewFrame()
                rawset(f, "RegisterUnitEvent", throw)
                return f
            end
            assert.is_false(TF:RegisterEvent("NOT_AN_EVENT", function() end))
            assert.is_false(TF:RegisterUnitEvent("NOT_AN_EVENT", { "player" }, function() end))
        end)

        it("filters unit events by unit", function()
            local got = {}
            TF:RegisterUnitEvent("UNIT_HEALTH", { "player" }, function(event, unit) got[#got + 1] = event .. unit end)
            A.fire("UNIT_HEALTH", "party1")
            A.fire("UNIT_HEALTH", "player")
            assert.are.same({ "UNIT_HEALTHplayer" }, got)
        end)

        it("shares one frame between handlers for the same event and units", function()
            local n = #wow.frames
            TF:RegisterUnitEvent("UNIT_AURA", { "player" }, function() end)
            TF:RegisterUnitEvent("UNIT_AURA", { "player" }, function() end)
            assert.are.equal(n + 1, #wow.frames)
        end)

        it("reports a failing handler and still runs the rest", function()
            A = addon.load({ upto = "Core/Core.lua", login = false, catchErrors = true })
            local ran = false
            A.TF:RegisterEvent("BAG_UPDATE", function() error("broken") end)
            A.TF:RegisterEvent("BAG_UPDATE", function() ran = true end)
            A.fire("BAG_UPDATE")
            assert.is_true(ran)
            assert.matches("broken", wow.chatText())
        end)
    end)

    describe("messages", function()
        it("delivers to listeners in order", function()
            local got = {}
            TF:On("X", function(a) got[#got + 1] = "1" .. a end)
            TF:On("X", function(a) got[#got + 1] = "2" .. a end)
            TF:Fire("X", "a")
            assert.are.same({ "1a", "2a" }, got)
        end)

        it("ignores messages nobody listens for", function()
            assert.has_no.errors(function() TF:Fire("NOBODY") end)
        end)

        it("prints each distinct error once", function()
            A = addon.load({ upto = "Core/Core.lua", login = false, catchErrors = true })
            A.TF:On("X", function() error("same", 0) end)
            A.TF:Fire("X")
            A.TF:Fire("X")
            local n = 0
            for _, line in ipairs(wow.chat) do if line:match("same") then n = n + 1 end end
            assert.are.equal(1, n)
        end)
    end)

    describe("combat", function()
        it("tracks combat and fires COMBAT", function()
            A.combat(true)
            assert.is_true(TF.inCombat)
            A.combat(false)
            assert.is_false(TF.inCombat)
            assert.are.same({ { n = 1, true }, { n = 1, false } }, A.messages("COMBAT"))
        end)

        it("AfterCombat runs at once out of combat", function()
            local ran = false
            TF:AfterCombat(function() ran = true end)
            assert.is_true(ran)
        end)

        it("AfterCombat queues in combat and runs in order before COMBAT(false)", function()
            A.combat(true)
            local got = {}
            TF:AfterCombat(function() got[#got + 1] = 1 end)
            TF:AfterCombat(function() got[#got + 1] = 2 end)
            TF:On("COMBAT", function(on) if not on then got[#got + 1] = "combat" end end)
            assert.are.same({}, got)
            A.combat(false)
            assert.are.same({ 1, 2, "combat" }, got)
            A.combat(true)
            A.combat(false)
            assert.are.same({ 1, 2, "combat", "combat" }, got)
        end)
    end)

    describe("Coalesce", function()
        it("runs once on the next frame, however often it's triggered", function()
            local n = 0
            local trigger = TF:Coalesce(function() n = n + 1 end)
            for _ = 1, 10 do trigger() end
            assert.are.equal(0, n)
            wow.advance(0)
            assert.are.equal(1, n)
            wow.advance(1)
            assert.are.equal(1, n)
            trigger()
            trigger()
            wow.advance(0)
            assert.are.equal(2, n)
        end)

        it("reports an error and keeps working", function()
            A = addon.load({ upto = "Core/Core.lua", login = false, catchErrors = true })
            local n = 0
            local trigger = A.TF:Coalesce(function()
                n = n + 1
                error("coalesced boom", 0)
            end)
            trigger()
            wow.advance(0)
            trigger()
            wow.advance(0)
            assert.are.equal(2, n)
            assert.matches("coalesced boom", wow.chatText())
        end)
    end)

    describe("slash commands", function()
        it("parses help text into args and description", function()
            TF:AddCommand("demo", function() end, "<on|off> - turn the demo on or off", { group = "Setup" })
            local c = TF.commands.demo
            assert.are.equal("<on|off>", c.args)
            assert.are.equal("turn the demo on or off", c.help)
            assert.are.equal("Setup", c.group)
        end)

        it("passes the rest of the line, case-insensitive command", function()
            local got
            TF:AddCommand("demo", function(args) got = args end, "- demo")
            A.slash("  DEMO  Some Args ")
            assert.are.equal("Some Args", got)
        end)

        it("doesn't list a command twice when it's added again", function()
            local n = #TF.commands
            TF:AddCommand("demo", function() end, "- one")
            TF:AddCommand("demo", function() end, "- two")
            assert.are.equal(n + 1, #TF.commands)
            assert.are.equal("two", TF.commands.demo.help)
        end)

        it("prints help for an unknown command", function()
            A.slash("nope")
            assert.matches('unknown command "nope"', wow.chatText())
        end)

        it("escapes | in help so chat shows it", function()
            TF:AddCommand("demo", function() end, "<on|off> - demo")
            TF:PrintHelp("demo")
            assert.matches("<on||off>", wow.chatText(), 1, true)
        end)

        it("reports a failing command instead of raising", function()
            A = addon.load({ upto = "Core/Core.lua", login = false, catchErrors = true })
            A.TF:AddCommand("bad", function() error("nope", 0) end, "- bad")
            assert.has_no.errors(function() A.slash("bad") end)
            assert.matches("nope", wow.chatText())
        end)
    end)
end)
