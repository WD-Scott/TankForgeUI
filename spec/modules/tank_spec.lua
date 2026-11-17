-- Modules/Tank.lua: tanking detection, the cast model, and pull recording.
local addon = require("support.addon")
local wow = require("support.wow")

-- Warrior spells used below.
local SHIELD_BLOCK, DEMO_SHOUT, SHIELD_WALL, LAST_STAND, TAUNT = 2565, 1160, 871, 12975, 355
local DEFENSIVE_STANCE = 18

describe("Tank", function()
    local A, TF, Tank, w

    -- A level-60 warrior in Defensive Stance who knows Shield Block, Shield Wall,
    -- Taunt and two ranks of Demoralizing Shout. `opts` may override world/db.
    local function load(opts)
        opts = opts or {}
        local world = { form = DEFENSIVE_STANCE, known = {
            [SHIELD_BLOCK] = true, [SHIELD_WALL] = true, [TAUNT] = true,
            [DEMO_SHOUT] = true, [6190] = true,
        } }
        for k, v in pairs(opts.world or {}) do world[k] = v end
        A = addon.load({ world = world, db = opts.db })
        TF, Tank, w = A.TF, A.ns.Tank, wow.world
        w.spellNames[SHIELD_BLOCK] = "Shield Block"
        w.spellNames[SHIELD_WALL] = "Shield Wall"
    end
    local function cast(id) A.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", id) end
    local function hit(kind, mask) A.fire("UNIT_COMBAT", "player", kind or "WOUND", "", 100, mask or 1) end
    local function entry(id) return Tank:EntryFor(id) end

    after_each(function() wow.uninstall() end)

    describe("Build", function()
        it("loads the class kit with the primary mitigation first", function()
            load()
            assert.are.equal("WARRIOR", Tank.class)
            assert.are.equal("shieldBlock", Tank.primary.def.key)
            assert.are.equal(Tank.primary, Tank.am[1])
            assert.are.equal(2, #Tank.am)
            assert.are.equal(1, #A.messages("KIT_CHANGED"))
        end)

        it("uses the highest known rank and maps every rank to the entry", function()
            load()
            local e = entry(DEMO_SHOUT)
            assert.are.equal(6190, e.spell)
            assert.is_true(e.known)
            assert.are.equal(e, entry(11556))
        end)

        it("keeps unknown spells, at their highest rank, off the HUD", function()
            load()
            local e = entry(LAST_STAND)
            assert.is_false(e.known)
            assert.are.equal(LAST_STAND, e.spell)
            local onHud = {}
            for _, i in ipairs(Tank.icons) do onHud[i.spell] = true end
            assert.are.same({ [SHIELD_WALL] = true, [TAUNT] = true }, onHud)
        end)

        it("rebuilds when spells change", function()
            load()
            w.known[LAST_STAND] = true
            A.fire("SPELLS_CHANGED")
            assert.is_true(entry(LAST_STAND).known)
        end)

        it("has no kit for a class that can't tank", function()
            load({ world = { units = { player = { name = "Zap", class = "MAGE" } } } })
            assert.is_nil(Tank.kit)
            assert.is_nil(Tank.primary)
            assert.is_false(Tank.isTank)
            assert.is_nil(Tank:Reason())
        end)
    end)

    describe("whether you're tanking", function()
        it("counts Defensive Stance", function()
            load()
            assert.are.equal("stance", Tank:Reason())
            assert.is_true(Tank.isTank)
            assert.are.same({ n = 1, true }, A.messages("TANK_CHANGED")[1])
        end)

        it("counts the stance by its spell when the form ID is unreadable", function()
            load({ world = { form = wow.secret(18), formSpell = 71 } })
            assert.are.equal("stance", Tank:Reason())
        end)

        it("counts the tank role first, and the setting before that", function()
            load({ world = { form = false } })
            assert.is_nil(Tank:Reason())
            w.units.player.role = "TANK"
            assert.are.equal("role", Tank:Reason())
            TF.db.tankMode = "always"
            assert.are.equal("always", Tank:Reason())
        end)

        it("counts a paladin's Righteous Fury", function()
            load({ world = { form = false, units = { player = { name = "Pal", class = "PALADIN" } } } })
            assert.is_nil(Tank:Reason())
            w.auras[25780] = { expirationTime = 0 }
            A.fire("UNIT_AURA", "player")
            wow.advance(0.3)
            assert.is_true(Tank.isTank)
        end)

        it("stops counting only after 10s out of stance", function()
            load()
            w.form = nil
            A.fire("UPDATE_SHAPESHIFT_FORM")
            assert.is_true(Tank.isTank)
            wow.advance(9.5)
            assert.is_true(Tank.isTank)
            wow.advance(1)
            assert.is_false(Tank.isTank)
            assert.are.same({ n = 1, false }, A.messages("TANK_CHANGED")[2])
        end)

        it("keeps counting when you go back into stance within the grace", function()
            load()
            w.form = nil
            A.fire("UPDATE_SHAPESHIFT_FORM")
            wow.advance(5)
            w.form = DEFENSIVE_STANCE
            A.fire("UPDATE_SHAPESHIFT_FORM")
            wow.advance(30)
            assert.is_true(Tank.isTank)
            assert.are.equal(1, #A.messages("TANK_CHANGED"))
        end)

        it("doesn't start the grace in combat (stance dancing)", function()
            load()
            A.combat(true)
            w.form = nil
            A.fire("UPDATE_SHAPESHIFT_FORM")
            wow.advance(30)
            assert.is_true(Tank.isTank)
            A.combat(false)
            wow.advance(10.5)
            assert.is_false(Tank.isTank)
        end)

        it("starts recording when you take up the stance mid-fight", function()
            load({ world = { form = false } })
            A.combat(true)
            assert.is_nil(Tank.pull)
            w.form = DEFENSIVE_STANCE
            A.fire("UPDATE_SHAPESHIFT_FORM")
            assert.is_table(Tank.pull)
        end)
    end)

    describe("CanUse", function()
        it("needs the stance, a shield and the cooldown", function()
            load()
            local sb = Tank.primary
            assert.is_true(Tank:CanUse(sb))
            w.form = 17
            assert.is_false(Tank:CanUse(sb))
            assert.is_false(Tank:Usable(sb))
            w.form = DEFENSIVE_STANCE
            w.offhand = "INVTYPE_2HWEAPON"
            assert.is_false(Tank:CanUse(sb))
            w.offhand = "INVTYPE_SHIELD"
            cast(SHIELD_BLOCK)
            assert.is_true(Tank:Usable(sb))
            assert.is_false(Tank:CanUse(sb))
        end)

        it("needs bear form for Demoralizing Roar", function()
            load({ world = { units = { player = { name = "Bear", class = "DRUID" } }, form = 1,
                known = { [99] = true } } })
            assert.is_false(Tank:CanUse(Tank.primary))
            w.form = 5
            assert.is_true(Tank:CanUse(Tank.primary))
        end)

        it("is false for an unknown spell", function()
            load()
            assert.is_false(Tank:CanUse(entry(LAST_STAND)))
        end)
    end)

    describe("the cast model", function()
        it("starts the cooldown and the buff on a cast", function()
            load()
            local sb = Tank.primary
            assert.is_true(Tank:IsReady(sb))
            cast(SHIELD_BLOCK)
            assert.is_false(Tank:IsReady(sb))
            assert.are.equal(5, Tank:CooldownLeft(sb))
            assert.is_true(Tank:IsActive(sb))
            assert.are.equal(7, Tank:Remaining(sb))
            assert.are.equal(sb, A.messages("CAST")[1][1])
            wow.advance(5)
            assert.is_true(Tank:IsReady(sb))
            wow.advance(2.1)
            assert.is_false(Tank:IsActive(sb))
            assert.are.equal(0, Tank:Remaining(sb))
        end)

        it("restarts the buff on a recast, capped at maxDuration", function()
            load()
            local demo = entry(DEMO_SHOUT)
            cast(DEMO_SHOUT)
            wow.advance(10)
            cast(6190)
            assert.are.equal(30, Tank:Remaining(demo))

            A.ns.Kits.WARRIOR.am[1].maxDuration = 10
            Tank:Build()
            local sb = Tank.primary
            cast(SHIELD_BLOCK)
            wow.advance(2)
            cast(SHIELD_BLOCK)
            assert.are.equal(10, Tank:Remaining(sb))
        end)

        it("ignores spells it doesn't track and secret spell IDs", function()
            load()
            cast(12345)
            A.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", wow.secret(SHIELD_BLOCK))
            assert.are.equal(0, #A.messages("CAST"))
        end)

        it("ends Shield Block at its second full block", function()
            load()
            local sb = Tank.primary
            cast(SHIELD_BLOCK)
            hit("BLOCK")
            assert.is_true(Tank:IsActive(sb))
            hit("BLOCK")
            assert.is_false(Tank:IsActive(sb))
        end)

        it("doesn't count blocks while the buff is down", function()
            load()
            hit("BLOCK")
            assert.is_nil(Tank.State(Tank.primary).blocksLeft)
        end)

        it("corrects cooldowns from readable values, ignoring the global cooldown", function()
            load()
            local wall = entry(SHIELD_WALL)
            w.cooldowns[SHIELD_WALL] = { 990, 1800 }
            A.fire("SPELL_UPDATE_COOLDOWN")
            wow.advance(0)
            assert.are.equal(2790, Tank.State(wall).readyAt)
            w.cooldowns[SHIELD_WALL] = { 1000, 1.5 }
            A.fire("SPELL_UPDATE_COOLDOWN")
            wow.advance(0)
            assert.are.equal(2790, Tank.State(wall).readyAt)
            w.cooldowns[SHIELD_WALL] = { 0, 0 }
            A.fire("SPELL_UPDATE_COOLDOWN")
            wow.advance(0)
            assert.are.equal(0, Tank.State(wall).readyAt)
            w.cooldowns[SHIELD_WALL] = { wow.secret(5), 1800 }
            A.fire("SPELL_UPDATE_COOLDOWN")
            wow.advance(0)
            assert.are.equal(0, Tank.State(wall).readyAt)
        end)

        it("reads the cooldowns once per frame, however many SPELL_UPDATE_COOLDOWNs arrive", function()
            load()
            local reads = 0
            local real = A.ns.API.GetSpellCooldownPlain
            A.ns.API.GetSpellCooldownPlain = function(...)
                reads = reads + 1
                return real(...)
            end
            for _ = 1, 10 do A.fire("SPELL_UPDATE_COOLDOWN") end
            assert.are.equal(0, reads)
            wow.advance(0)
            local once = reads
            assert.is_true(once > 0)
            A.fire("SPELL_UPDATE_COOLDOWN")
            wow.advance(0)
            assert.are.equal(once * 2, reads)
        end)

        it("corrects the buff from a readable aura", function()
            load()
            local sb = Tank.primary
            w.auras[SHIELD_BLOCK] = { expirationTime = 1004 }
            A.fire("UNIT_AURA", "player")
            wow.advance(0)
            assert.are.equal(4, Tank:Remaining(sb))
        end)

        it("syncs auras once per frame however many UNIT_AURA events arrive", function()
            load()
            local sb = Tank.primary
            local calls = 0
            local sync = Tank.SyncAuras
            Tank.SyncAuras = function(self) calls = calls + 1 return sync(self) end
            w.auras[SHIELD_BLOCK] = { expirationTime = 1004 }
            for _ = 1, 5 do A.fire("UNIT_AURA", "player") end
            assert.are.equal(0, calls)
            wow.advance(0)
            assert.are.equal(1, calls)
            assert.are.equal(4, Tank:Remaining(sb))
            A.fire("UNIT_AURA", "player")
            wow.advance(0)
            assert.are.equal(2, calls)
        end)

        it("ends the buff when the aura is gone out of combat, but not in combat or when hidden", function()
            load()
            local sb = Tank.primary
            cast(SHIELD_BLOCK)
            w.auras[SHIELD_BLOCK] = wow.secret({})
            A.fire("UNIT_AURA", "player")
            wow.advance(0)
            assert.is_true(Tank:IsActive(sb))
            w.auras[SHIELD_BLOCK] = nil
            A.combat(true)
            A.fire("UNIT_AURA", "player")
            wow.advance(0)
            assert.is_true(Tank:IsActive(sb))
            A.combat(false)
            assert.is_false(Tank:IsActive(sb))
        end)
    end)

    describe("hits", function()
        it("counts being hit for 2.5s after a hit", function()
            load()
            assert.is_false(Tank:BeingHit())
            hit()
            assert.is_true(Tank:BeingHit())
            wow.advance(2.4)
            assert.is_true(Tank:BeingHit())
            wow.advance(0.2)
            assert.is_false(Tank:BeingHit())
        end)

        it("ignores spell hits for a physical-only mitigation", function()
            load()
            for _, mask in ipairs({ 2, 4, 8, 16, 32, 64, 0x21 }) do hit("WOUND", mask) end
            assert.is_false(Tank:BeingHit())
            assert.is_true(Tank.lastHit > 0)
        end)

        it("counts hits of unknown school and secret kind", function()
            load()
            A.fire("UNIT_COMBAT", "player", wow.secret("WOUND"), "", 100, wow.secret(4))
            assert.is_true(Tank:BeingHit())
        end)

        it("ignores combat text that isn't a hit", function()
            load()
            hit("HEAL")
            assert.are.equal(0, Tank.lastHit)
        end)
    end)

    describe("pulls", function()
        it("records a pull from combat start to end while tanking", function()
            load({ world = { inInstance = true, instanceType = "party", zone = "Deadmines" } })
            A.combat(true)
            local p = Tank.pull
            assert.are.equal("Deadmines", p.zone)
            assert.is_true(p.instance)
            assert.are.equal("Shield Block", p.primaryName)
            assert.are.equal(0.75, p.primaryTarget)
            assert.are.equal(1, #A.messages("PULL_START"))
            wow.advance(12)
            A.combat(false)
            assert.is_nil(Tank.pull)
            local ended = A.messages("PULL_END")[1][1]
            assert.are.equal(p, ended)
            assert.are.equal(12, ended.duration)
            assert.is_nil(ended.gap)
        end)

        it("names the boss when the encounter starts before or during combat", function()
            load()
            A.fire("ENCOUNTER_START", 1, "Wolf Master Nandos", 1, 5)
            A.combat(true)
            assert.are.equal("Wolf Master Nandos", Tank.pull.encounter)
            A.fire("ENCOUNTER_END", 1, "Wolf Master Nandos", 1, 5, 1)
            A.combat(false)
            A.combat(true)
            assert.is_nil(Tank.pull.encounter)
            A.fire("ENCOUNTER_START", 2, "Archmage Arugal", 1, 5)
            assert.are.equal("Archmage Arugal", Tank.pull.encounter)
        end)

        it("doesn't record when you aren't tanking", function()
            load({ world = { form = false } })
            A.combat(true)
            assert.is_nil(Tank.pull)
            A.combat(false)
            assert.are.equal(0, #A.messages("PULL_END"))
        end)

        it("counts casts, taunts and defensives", function()
            load()
            A.combat(true)
            cast(TAUNT)
            cast(SHIELD_WALL)
            cast(SHIELD_BLOCK)
            cast(SHIELD_BLOCK)
            local p = Tank.pull
            assert.are.equal(1, p.taunts)
            assert.are.same({ "Shield Wall" }, p.defensives)
            assert.are.equal(2, p.casts.shieldBlock)
        end)

        it("counts hits, relevant hits and hits without mitigation", function()
            load()
            A.combat(true)
            hit()
            hit("WOUND", 4)
            cast(SHIELD_BLOCK)
            hit("PARRY")
            local p = Tank.pull
            assert.are.equal(3, p.hits)
            assert.are.equal(2, p.hitsRelevant)
            assert.are.equal(1, p.hitsUnmitigated)
            assert.are.equal(3, p.tl.hit[1])
        end)

        it("measures time under attack, covered time and the longest gap", function()
            load()
            A.combat(true)
            hit()
            wow.advance(2)          -- 2s hit without Shield Block
            cast(SHIELD_BLOCK)
            hit()
            wow.advance(2)          -- 2s hit with it
            wow.advance(5)          -- not hit for the rest
            local p = Tank.pull
            assert.are.near(4.5, p.underAttack, 0.01)
            assert.are.near(2.5, p.covered, 0.01)
            assert.are.near(2, p.longestGap, 0.01)
            assert.are.equal(0, p.gap)
        end)

        it("writes a per-second timeline of hits and coverage", function()
            load()
            A.combat(true)
            hit()
            wow.advance(1)
            cast(SHIELD_BLOCK)
            wow.advance(3)
            local tl = Tank.pull.tl
            assert.are.equal(5, tl.n)
            assert.is_true(tl.att[1] and tl.att[2] and tl.att[3])
            assert.is_nil(tl.att[5])
            assert.is_true(tl.cov[1] < 0)
            assert.is_true(tl.cov[2] > 0)
        end)

        it("fires LAPSE when hit without Shield Block while it's ready", function()
            load()
            A.combat(true)
            for _ = 1, 4 do hit() wow.advance(1) end
            local lapses = A.messages("LAPSE")
            assert.is_true(#lapses > 0)
            assert.are.equal(Tank.primary, lapses[1][1])
            assert.is_true(lapses[1][2] >= 3)
        end)

        it("doesn't fire LAPSE while Shield Block is on cooldown", function()
            load()
            A.combat(true)
            cast(SHIELD_BLOCK)
            Tank.State(Tank.primary).expiry = 0
            Tank.State(Tank.primary).readyAt = wow.now + 60
            for _ = 1, 5 do hit() wow.advance(1) end
            assert.are.equal(0, #A.messages("LAPSE"))
        end)

        it("doesn't fire LAPSE out of Defensive Stance, where Shield Block can't be cast", function()
            load({ db = { tankMode = "always" }, world = { form = 17 } })
            A.combat(true)
            for _ = 1, 5 do hit() wow.advance(1) end
            assert.are.equal(0, #A.messages("LAPSE"))
        end)

        it("doesn't fire LAPSE without a shield", function()
            load({ world = { offhand = "INVTYPE_WEAPONOFFHAND" } })
            A.combat(true)
            for _ = 1, 5 do hit() wow.advance(1) end
            assert.are.equal(0, #A.messages("LAPSE"))
        end)

        it("respects the lapse setting", function()
            load({ db = { alerts = { lapseSeconds = 1 } } })
            A.combat(true)
            hit()
            wow.advance(1.3)
            assert.is_true(#A.messages("LAPSE") > 0)
        end)

        it("adds up time with loose mobs and an attacked healer", function()
            load()
            A.combat(true)
            A.ns.Threat.looseCount = 1
            A.ns.Threat.healerAttacked = true
            wow.advance(2)
            local p = Tank.pull
            assert.are.near(2, p.looseTime, 0.01)
            assert.are.near(2, p.healerAttacked, 0.01)
        end)

        it("skips a tick after a long stall", function()
            load()
            A.combat(true)
            hit()
            local p = Tank.pull
            p.lastTick = wow.now - 5
            wow.advance(0.25)
            assert.are.equal(0, p.underAttack)
        end)

        it("records the encounter name", function()
            load()
            A.combat(true)
            A.fire("ENCOUNTER_START", 1, "Edwin VanCleef", 1, 5)
            assert.are.equal("Edwin VanCleef", Tank.pull.encounter)
        end)

        it("stops the ticker after the pull", function()
            load()
            A.combat(true)
            wow.advance(1)
            assert.are.equal(4, #A.messages("PULL_TICK"))
            A.combat(false)
            A.clearMessages()
            wow.advance(1)
            assert.are.equal(0, #A.messages("PULL_TICK"))
        end)
    end)

    describe("death", function()
        it("lists the major defensives still ready", function()
            load()
            A.combat(true)
            wow.advance(3)
            A.fire("PLAYER_DEAD")
            assert.are.same({ "Shield Wall" }, A.messages("DEATH")[1][1])
            local d = Tank.pull.deaths[1]
            assert.are.equal(3, d.t)
            assert.are.same({ "Shield Wall" }, d.ready)
        end)

        it("leaves out defensives on cooldown", function()
            load()
            cast(SHIELD_WALL)
            A.fire("PLAYER_DEAD")
            assert.are.same({}, A.messages("DEATH")[1][1])
        end)
    end)

    it("/tf status says what it thinks", function()
        load()
        A.slash("status")
        assert.matches("class WARRIOR, tanking: yes %(stance%)", wow.chatText())
    end)
end)
