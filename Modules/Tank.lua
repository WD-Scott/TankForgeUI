-- Modules/Tank.lua
-- Am I tanking, what have I pressed, and how is this pull going?
--
-- Built only from data the client keeps readable in combat (the same approach
-- TankCompanion takes): your own casts (UNIT_SPELLCAST_SUCCEEDED), the timing of
-- hits on you (UNIT_COMBAT fires even when the amount is secret), your stance
-- or form, and the group's roles. Buff timers and cooldowns are modelled from
-- your casts and corrected from the real values whenever they are readable.
local _, ns = ...
local TF = ns.TF
local API = ns.API

local Tank = {}
ns.Tank = Tank

local GRACE = 10        -- seconds out of stance, out of combat, before you stop counting as the tank
local HIT_WINDOW = 2.5  -- seconds after a hit during which you count as being hit
local TICK = 0.25
local TIMELINE_MAX = 900 -- seconds of per-second timeline kept per pull (Charts.MAX_SECONDS)

Tank.isTank = false
---@type TankEntry[]
Tank.entries = {}       -- every tracked spell
---@type TankEntry[]
Tank.am = {}            -- active mitigation entries, primary first
---@type TankEntry[]
Tank.icons = {}         -- HUD icon entries that are known
---@type TankEntry|nil
Tank.primary = nil      -- the mitigation you're judged on
---@type Pull|nil
Tank.pull = nil         -- the pull being recorded
Tank.lastHit = 0
Tank.lastRelevantHit = 0
---@type string|nil
Tank.encounter = nil    -- the boss encounter in progress (ENCOUNTER_START to ENCOUNTER_END)

local byId = {}
local state = {}        -- [def] = { readyAt, lastCast, expiry } (survives rebuilds)

--- The modelled timers for an entry (shared by every rank, kept across rebuilds).
---@param entry TankEntry
---@return {readyAt: number, lastCast: number|nil, expiry: number, blocksLeft: number|nil}
local function St(entry)
    local s = state[entry.def]
    if not s then
        s = { readyAt = 0, lastCast = nil, expiry = 0 }
        state[entry.def] = s
    end
    return s
end
Tank.State = St

-- Kit ------------------------------------------------------------------------

--- Every rank of a kit spell, lowest first.
local function Ranks(def)
    local list = { def.spell }
    for _, id in ipairs(def.alt or {}) do list[#list + 1] = id end
    return list
end

--- Rebuild the tracked spells from the player's class kit and known ranks. Fires KIT_CHANGED.
function Tank:Build()
    local class = API.UnitClass("player")
    self.class = class
    self.kit = class and ns.Kits[class] or nil
    wipe(byId)
    wipe(self.entries)
    wipe(self.am)
    wipe(self.icons)
    self.primary = nil
    if not self.kit then
        TF:Fire("KIT_CHANGED")
        return
    end
    local function Add(def, isAM)
        local ranks = Ranks(def)
        local known
        for i = #ranks, 1, -1 do
            if API.IsSpellKnown(ranks[i]) then known = ranks[i] break end
        end
        local entry = { def = def, spell = known or ranks[#ranks], known = known ~= nil, isAM = isAM }
        for _, id in ipairs(ranks) do byId[id] = entry end
        if def.buff then byId[def.buff] = byId[def.buff] or entry end
        self.entries[#self.entries + 1] = entry
        return entry
    end
    for _, def in ipairs(self.kit.am) do
        local e = Add(def, true)
        if def.primary then
            self.primary = e
            table.insert(self.am, 1, e)
        else
            self.am[#self.am + 1] = e
        end
    end
    for _, def in ipairs(self.kit.icons) do
        local e = Add(def, false)
        if e.known then self.icons[#self.icons + 1] = e end
    end
    self:Calibrate()
    TF:Fire("KIT_CHANGED")
end

--- The tracked entry for any rank (or buff) spell ID.
---@param spellID number
---@return TankEntry|nil
function Tank:EntryFor(spellID) return byId[spellID] end

-- Readiness and mitigation ----------------------------------------------------

--- True when a known spell is off its modelled cooldown (50ms slack).
---@param entry TankEntry|nil
---@param now number|nil defaults to API.Now()
---@return boolean
function Tank:IsReady(entry, now)
    if not entry or not entry.known then return false end
    now = now or API.Now()
    return now >= (St(entry).readyAt or 0) - 0.05
end

--- Seconds until ready, 0 when ready.
---@param entry TankEntry
---@param now number|nil
---@return number
function Tank:CooldownLeft(entry, now)
    now = now or API.Now()
    return math.max((St(entry).readyAt or 0) - now, 0)
end

--- True while a mitigation's modelled buff is up.
---@param entry TankEntry|nil
---@param now number|nil
---@return boolean
function Tank:IsActive(entry, now)
    if not entry then return false end
    return (St(entry).expiry or 0) > (now or API.Now())
end

--- Seconds left on a mitigation's modelled buff, 0 when down.
---@param entry TankEntry|nil
---@param now number|nil
---@return number
function Tank:Remaining(entry, now)
    if not entry then return 0 end
    return math.max((St(entry).expiry or 0) - (now or API.Now()), 0)
end

--- Correct the cast model from the real cooldowns whenever they are readable.
--- Readable cooldowns of 1.6s or less are taken as the global cooldown and ignored.
function Tank:Calibrate()
    for _, entry in ipairs(self.entries) do
        if entry.known and entry.def.cd then
            local start, duration = API.GetSpellCooldownPlain(entry.spell)
            if start then
                if start == 0 or duration == 0 then
                    St(entry).readyAt = 0
                elseif duration > 1.6 then
                    St(entry).readyAt = start + duration
                end
            end
        end
    end
end

--- Correct mitigation timers from the real buffs whenever they are readable.
--- An aura that is gone out of combat (and not hidden) ends the modelled buff;
--- in combat a missing aura proves nothing, so the model is kept.
function Tank:SyncAuras()
    local now = API.Now()
    for _, entry in ipairs(self.am) do
        local buff = entry.def.buff
        if buff then
            local aura = API.GetPlayerAura(buff)
            if aura then
                local exp = API.PlainNumber(aura.expirationTime)
                if exp and exp > 0 then St(entry).expiry = exp end
            elseif not TF.inCombat and not API.PlayerAuraHidden(buff) then
                local s = St(entry)
                if s.expiry > now then s.expiry = now end
            end
        end
    end
end

-- Tanking or not ---------------------------------------------------------------

local function Contains(list, v)
    if v == nil or not list then return false end
    for _, x in ipairs(list) do
        if x == v then return true end
    end
    return false
end

--- True in a kit posture: a tanking form, form spell or aura (Righteous Fury).
---@return boolean
function Tank:InPosture()
    local p = self.kit and self.kit.posture
    if not p then return false end
    if Contains(p.forms, API.GetShapeshiftFormID()) then return true end
    if Contains(p.formSpells, API.GetActiveFormSpellID()) then return true end
    if p.auras then
        for _, id in ipairs(p.auras) do
            if API.GetPlayerAura(id) then return true end
        end
    end
    return false
end

--- True when a known spell's stance/form and shield needs are met right now
--- (Shield Block in Defensive Stance with a shield), cooldown aside.
---@param entry TankEntry|nil
---@return boolean
function Tank:Usable(entry)
    if not entry or not entry.known then return false end
    local def = entry.def
    if def.forms and not Contains(def.forms, API.GetShapeshiftFormID()) then return false end
    if def.shield and not API.HasShield() then return false end
    return true
end

--- True when you could press it now: usable and off its modelled cooldown.
---@param entry TankEntry|nil
---@param now number|nil
---@return boolean
function Tank:CanUse(entry, now)
    return self:Usable(entry) and self:IsReady(entry, now)
end

--- Why you count as the tank: "always" (setting), "role", "stance", or nil.
---@return string|nil
function Tank:Reason()
    if not self.kit then return nil end
    if TF.db.tankMode == "always" then return "always" end
    if API.UnitRole("player") == "TANK" then return "role" end
    if self:InPosture() then return "stance" end
    return nil
end

local lossSince, graceTimer
-- Set Tank.isTank, firing TANK_CHANGED only on a change.
local function SetTank(on)
    if Tank.isTank == on then return end
    Tank.isTank = on
    TF:Fire("TANK_CHANGED", on)
end

--- Decide whether you're tanking. Gaining a reason counts at once; losing it
--- counts only after GRACE seconds out of combat and outside a pull.
function Tank:Evaluate()
    if self:Reason() then
        lossSince = nil
        SetTank(true)
        -- Took up the stance mid-fight: this is the pull to record.
        if TF.inCombat and not self.pull then self:StartPull() end
        return
    end
    if not self.isTank then return end
    -- A stance dance mid-fight is part of tanking; the grace starts after.
    if TF.inCombat or self.pull then
        lossSince = nil
        return
    end
    local now = API.Now()
    lossSince = lossSince or now
    local left = GRACE - (now - lossSince)
    if left <= 0 then
        lossSince = nil
        SetTank(false)
    elseif not graceTimer then
        graceTimer = true
        C_Timer.After(left + 0.1, function()
            graceTimer = nil
            Tank:Evaluate()
        end)
    end
end

-- Casts and hits -------------------------------------------------------------

--- Update the cast model for one of your casts: cooldown, buff expiry (stacking
--- up to maxDuration), block charges, and the pull's cast counts. Fires CAST.
---@param spellID number
function Tank:OnCast(spellID)
    local entry = byId[spellID]
    if not entry then return end
    local now = API.Now()
    local s = St(entry)
    local def = entry.def
    s.lastCast = now
    if def.cd then s.readyAt = now + def.cd end
    if entry.isAM and def.duration then
        local base = math.max(s.expiry or 0, now)
        s.expiry = math.min(base + def.duration, now + (def.maxDuration or def.duration))
        s.blocksLeft = def.blocks
    end
    local p = self.pull
    if p then
        local key = def.key or def.spell
        p.casts[key] = (p.casts[key] or 0) + 1
        if def.kind == "taunt" or def.kind == "aoeTaunt" then p.taunts = p.taunts + 1 end
        if def.kind == "interrupt" then p.interrupts = p.interrupts + 1 end
        if def.kind == "defensive" then
            p.defensives[#p.defensives + 1] = API.GetSpellName(entry.spell) or "?"
        end
    end
    TF:Fire("CAST", entry, now)
end

local HIT_KINDS = { WOUND = true, BLOCK = true, DODGE = true, PARRY = true, ABSORB = true,
    MISS = true, RESIST = true, IMMUNE = true, DEFLECT = true, EVADE = true }

--- Record a hit on you. Hits of the wrong school for a physical-only
--- mitigation don't count against it.
---@param _kind string combat-log kind (WOUND, BLOCK, ... or "hit" when secret)
---@param physical boolean|nil nil when the school is unreadable
function Tank:OnHit(_kind, physical)
    local now = API.Now()
    self.lastHit = now
    local primary = self.primary
    local relevant = not (primary and primary.def.physical and physical == false)
    if relevant then self.lastRelevantHit = now end
    local p = self.pull
    if not p then return end
    p.hits = p.hits + 1
    local sec = math.floor(now - p.start) + 1
    if sec <= TIMELINE_MAX then p.tl.hit[sec] = (p.tl.hit[sec] or 0) + 1 end
    if relevant then
        p.hitsRelevant = p.hitsRelevant + 1
        if primary and primary.known and not self:IsActive(primary, now) then
            p.hitsUnmitigated = p.hitsUnmitigated + 1
        end
    end
end

--- A full block uses up a charge of a block-limited mitigation (Shield Block's
--- two). Partial blocks arrive as ordinary hits and can't be counted, so this
--- can only end the buff early, never late.
function Tank:OnBlock()
    local now = API.Now()
    for _, entry in ipairs(self.am) do
        local s = St(entry)
        if entry.def.blocks and self:IsActive(entry, now) and s.blocksLeft then
            s.blocksLeft = s.blocksLeft - 1
            if s.blocksLeft <= 0 then s.expiry = now end
        end
    end
end

--- True within HIT_WINDOW seconds of a hit that counts against your mitigation.
---@param now number|nil
---@return boolean
function Tank:BeingHit(now)
    return ((now or API.Now()) - self.lastRelevantHit) <= HIT_WINDOW
end

-- Pulls ----------------------------------------------------------------------

local ticker

--- Per-second timeline for the pull report's chart: was I being hit, and was
--- my mitigation up (+1 per covered tick, -1 per uncovered tick)?
local function Sample(p, now, hit, active)
    local tl = p.tl
    local sec = math.floor(now - p.start) + 1
    if sec > TIMELINE_MAX then
        tl.trunc = true
        return
    end
    if sec > tl.n then tl.n = sec end
    if not hit then return end
    tl.att[sec] = true
    if active ~= nil then tl.cov[sec] = (tl.cov[sec] or 0) + (active and 1 or -1) end
end

-- Every TICK seconds during a pull: time under attack, covered time, the
-- current and longest gap, LAPSE, and time with loose mobs or an attacked healer.
local function Tick()
    local p = Tank.pull
    if not p then return end
    local now = API.Now()
    local dt = now - (p.lastTick or now)
    p.lastTick = now
    if dt <= 0 or dt > 2 then return end
    local primary = Tank.primary
    local beingHit = Tank:BeingHit(now)
    local tracked = primary and primary.known
    local active
    if tracked then active = Tank:IsActive(primary, now) and true or false end
    Sample(p, now, beingHit, active)
    if beingHit then
        p.underAttack = p.underAttack + dt
        if tracked then
            if active then
                p.covered = p.covered + dt
                p.gap = 0
            else
                p.gap = p.gap + dt
                if p.gap > p.longestGap then p.longestGap = p.gap end
                if p.gap >= (TF.db.alerts.lapseSeconds or 3) and Tank:CanUse(primary, now) then
                    TF:Fire("LAPSE", primary, p.gap)
                end
            end
        end
    else
        p.gap = 0
    end
    local T = ns.Threat
    if T then
        if T.healerAttacked then p.healerAttacked = p.healerAttacked + dt end
        if (T.looseCount or 0) > 0 then p.looseTime = p.looseTime + dt end
    end
    TF:Fire("PULL_TICK", p, now)
end

--- Start recording a pull (only while tanking). Fires PULL_START.
function Tank:StartPull()
    if self.pull or not self.isTank then return end
    local now = API.Now()
    local inInstance, instanceType = IsInInstance()
    self.pull = {
        start = now, lastTick = now, time = time(),
        zone = API.PlainString(GetRealZoneText and GetRealZoneText()) or "?",
        instance = inInstance and (instanceType == "party" or instanceType == "raid" or instanceType == "scenario"),
        hits = 0, hitsRelevant = 0, hitsUnmitigated = 0,
        underAttack = 0, covered = 0, gap = 0, longestGap = 0,
        casts = {}, taunts = 0, interrupts = 0, defensives = {},
        aggroLost = 0, aggroLostTo = {}, healerAttacked = 0, looseTime = 0,
        deaths = {},
        tl = { n = 0, att = {}, cov = {}, hit = {} },
        primaryName = self.primary and API.GetSpellName(self.primary.spell),
        primaryTarget = self.primary and self.primary.def.target,
        primaryKnown = self.primary and self.primary.known,
        -- ENCOUNTER_START often arrives before combat does.
        encounter = self.encounter,
    }
    if not ticker then ticker = C_Timer.NewTicker(TICK, Tick) end
    TF:Fire("PULL_START", self.pull)
end

--- Finish the pull, if any: fires PULL_END with the pull, then re-evaluates tanking.
function Tank:EndPull()
    local p = self.pull
    if not p then return end
    self.pull = nil
    if ticker then ticker:Cancel() ticker = nil end
    p.duration = API.Now() - p.start
    p.lastTick, p.gap = nil, nil
    TF:Fire("PULL_END", p)
    self:Evaluate()
end

--- Record a death and which major defensives were still ready. Fires DEATH while tanking.
function Tank:OnDeath()
    local p = self.pull
    local ready = {}
    for _, entry in ipairs(self.icons) do
        if entry.def.major and self:IsReady(entry) then
            ready[#ready + 1] = API.GetSpellName(entry.spell) or "?"
        end
    end
    if p then p.deaths[#p.deaths + 1] = { t = API.Now() - p.start, ready = ready } end
    if self.isTank then TF:Fire("DEATH", ready) end
end

-- Events ---------------------------------------------------------------------

TF:On("LOGIN", function()
    Tank:Build()
    Tank:Evaluate()
end)

for _, ev in ipairs({ "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "PLAYER_LEVEL_UP" }) do
    TF:RegisterEvent(ev, function()
        if TF.db then Tank:Build() end
    end)
end

for _, ev in ipairs({ "UPDATE_SHAPESHIFT_FORM", "PLAYER_ROLES_ASSIGNED", "GROUP_ROSTER_UPDATE" }) do
    TF:RegisterEvent(ev, function()
        if TF.db then Tank:Evaluate() end
    end)
end

-- SPELL_UPDATE_COOLDOWN fires several times per global cooldown; read the
-- cooldowns once, on the next frame.
TF:RegisterEvent("SPELL_UPDATE_COOLDOWN", TF:Coalesce(function() Tank:Calibrate() end))

-- UNIT_AURA can fire many times a frame in combat; sync the buff timers once,
-- on the next frame, however many arrive.
local auraPending = false
local syncAuras = TF:Coalesce(function() Tank:SyncAuras() end)
TF:RegisterUnitEvent("UNIT_AURA", { "player" }, function()
    syncAuras()
    -- Righteous Fury is an aura; re-check posture out of combat, debounced.
    if TF.inCombat or auraPending then return end
    auraPending = true
    C_Timer.After(0.2, function()
        auraPending = false
        Tank:Evaluate()
    end)
end)

TF:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", { "player" }, function(_, _, _, spellID)
    spellID = API.PlainNumber(spellID)
    if spellID then Tank:OnCast(spellID) end
end)

TF:RegisterUnitEvent("UNIT_COMBAT", { "player" }, function(_, unit, event, _, _, schoolMask)
    if unit ~= "player" then return end
    local mask = API.PlainNumber(schoolMask)
    local physical
    if mask then physical = (mask == 1) end
    if API.IsSecret(event) then
        Tank:OnHit("hit", physical)
        if ns.Log:IsOn() then TF:Fire("HIT", "hit", physical, true) end
    elseif HIT_KINDS[event] then
        Tank:OnHit(event, physical)
        if event == "BLOCK" then Tank:OnBlock() end
        if ns.Log:IsOn() then TF:Fire("HIT", event, physical, false) end
    end
end)

TF:RegisterEvent("PLAYER_DEAD", function() Tank:OnDeath() end)

TF:RegisterEvent("ENCOUNTER_START", function(_, _, name)
    Tank.encounter = API.PlainString(name)
    if Tank.pull then Tank.pull.encounter = Tank.encounter end
end)

TF:RegisterEvent("ENCOUNTER_END", function()
    Tank.encounter = nil
end)

-- A missed ENCOUNTER_END (a release and run back) mustn't name the next zone's pulls.
TF:On("ENTERING_WORLD", function() Tank.encounter = nil end)

TF:On("COMBAT", function(inCombat)
    if inCombat then
        Tank:Evaluate()
        Tank:StartPull()
    else
        Tank:EndPull()
        Tank:Calibrate()
        Tank:SyncAuras()
        Tank:Evaluate()
    end
end)

TF:AddCommand("status", function()
    local reason = Tank:Reason()
    TF:Print(string.format("class %s, tanking: %s%s. Healer: %s.",
        tostring(Tank.class), Tank.isTank and "yes" or "no",
        reason and (" (" .. reason .. ")") or "",
        ns.Healer and ns.Healer:Describe() or "?"))
end, "- what TankForgeUI thinks is going on (tanking, kit, healer, ...)", { group = "Tanking" })
