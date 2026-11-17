-- Core/Log.lua: the debug log.
local addon = require("support.addon")
local wow = require("support.wow")

describe("Log", function()
    local A, TF, Log
    local function load(log)
        A = addon.load({ log = log })
        TF, Log = A.TF, A.ns.Log
    end
    local function lines() return _G.TankForgeUILog.lines end
    local function has(pattern)
        for _, l in ipairs(lines()) do if l:match(pattern) then return true end end
        return false
    end
    after_each(function() wow.uninstall() end)

    it("is off by default and costs nothing", function()
        load()
        assert.is_false(Log:IsOn())
        TF:Log("TEST", "hello")
        assert.are.same({}, lines())
    end)

    it("keeps an earlier session's lines across a login", function()
        load({ enabled = false, lines = { "old" } })
        assert.are.same({ "old" }, lines())
    end)

    it("appends a new session header after the earlier lines when on", function()
        load({ enabled = true, lines = { "old" } })
        wow.advance(1.1)
        assert.are.equal("old", lines()[1])
        assert.is_true(has("==== session"))
    end)

    it("clear empties lines from earlier sessions", function()
        load({ enabled = false, lines = { "old" } })
        A.slash("log clear")
        assert.are.same({}, lines())
    end)

    it("writes a session header a second after login when on", function()
        load({ enabled = true })
        assert.is_false(has("==== session"))
        wow.advance(1.1)
        assert.is_true(has("==== session"))
        assert.is_true(has("class WARRIOR"))
    end)

    it("formats lines with session time and category", function()
        load({ enabled = true })
        wow.advance(2.5)
        TF:Log("CAST", "%s (%d)", "Taunt", 355)
        assert.are.equal("[    2.50] CAST   Taunt (355)", lines()[#lines()])
    end)

    it("writes the format itself when the arguments don't fit", function()
        load({ enabled = true })
        TF:Log("X", "%d things", "not a number")
        assert.matches("%%d things", lines()[#lines()])
    end)

    it("keeps the newest half behind a marker when full", function()
        load({ enabled = true })
        Log.MAX_LINES = 10
        for k in pairs(lines()) do lines()[k] = nil end
        for i = 1, 11 do TF:Log("N", "%d", i) end
        local l = lines()
        assert.are.equal(6, #l)
        assert.are.equal("... older lines dropped ...", l[1])
        for i = 2, 6 do assert.matches("N +" .. (i + 5) .. "$", l[i]) end
    end)

    it("turns on and off with /tf log", function()
        load({ enabled = false })
        A.slash("log on")
        assert.is_true(Log:IsOn())
        assert.is_true(has("==== session"))
        A.slash("log mark before the wipe")
        assert.is_true(has("MARK +before the wipe"))
        A.slash("log off")
        assert.is_false(Log:IsOn())
        A.slash("log clear")
        assert.are.same({}, lines())
    end)

    it("probes plain and secret values without errors", function()
        load({ enabled = true })
        wow.world.units.player.health = wow.secret(10)
        wow.world.auras[2565] = wow.secret({})
        A.slash("log probe")
        assert.is_true(has("player health secret / 5000"))
        assert.is_true(has("Shield Block aura by ID secret"))
    end)

    it("probes 3s into the first pulls only", function()
        load({ enabled = true })
        for _ = 1, 4 do
            A.combat(true)
            wow.advance(3.5)
            A.combat(false)
        end
        local n = 0
        for _, l in ipairs(lines()) do if l:match("PROBE  %-%-%-%- 3s into combat") then n = n + 1 end end
        assert.are.equal(3, n)
    end)

    it("logs a blocked action once, then counts repeats until the fight ends", function()
        load({ enabled = true })
        A.fire("ADDON_ACTION_BLOCKED", "TankForgeUI", "StanceButton1:Show()")
        A.fire("ADDON_ACTION_BLOCKED", "TankForgeUI", "StanceButton2:Show()")
        A.fire("ADDON_ACTION_BLOCKED", "OtherAddon", "Foo()")
        A.combat(true)
        assert.is_true(has("BLOCK +ADDON_ACTION_BLOCKED: StanceButton1:Show%(%)"))
        assert.is_true(has("StanceButtonN:Show%(%): repeated 1 more times"))
        assert.is_false(has("Foo"))
        assert.matches("the game blocked", wow.chatText())
    end)

    it("describes values with D", function()
        load()
        assert.are.equal("nil", Log.D(nil))
        assert.are.equal("1.5", Log.D(1.5))
        assert.are.equal('"hi"', Log.D("hi"))
        assert.are.equal("true", Log.D(true))
        assert.are.equal("table", Log.D({}))
        assert.are.equal("secret", Log.D(wow.secret(1)))
        assert.are.equal(50, #Log.D(string.rep("x", 100)))
    end)
end)
