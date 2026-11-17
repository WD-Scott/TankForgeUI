-- spec/support/wow.lua
-- A stand-in for the WoW client, enough to load TankForgeUI and drive its logic
-- offline. `wow.install(world)` puts fresh globals into _G; tests then shape the
-- game through `wow.world` (units, spells, auras, instance, combat) and the fake
-- clock (`wow.advance`).
--
-- Frames: any method whose name starts with an upper-case letter exists and does
-- nothing unless defined below (Get* return 0, Is*/Has* return false), so add-on
-- frame code runs without a client. Lower-case keys are plain fields and start nil,
-- like on a real frame. State that matters to logic is tracked: shown, alpha, text,
-- size, scripts, attributes, registered events.
--
-- Secret values: `wow.secret(v)` wraps v so that arithmetic, ordering and
-- concatenation raise, as on the Midnight client, and `issecretvalue` sees it.
-- `type()` reports the wrapped value's type, also as on the client.

local wow = {}

local realType = type

-- Secret values -------------------------------------------------------------------

local SecretMT = {}
local function refuse(what)
    return function() error("attempt to " .. what .. " a secret value", 2) end
end
SecretMT.__add, SecretMT.__sub, SecretMT.__mul = refuse("add"), refuse("subtract"), refuse("multiply")
SecretMT.__div, SecretMT.__mod, SecretMT.__pow = refuse("divide"), refuse("mod"), refuse("raise")
SecretMT.__unm, SecretMT.__concat, SecretMT.__len = refuse("negate"), refuse("concatenate"), refuse("measure")
SecretMT.__lt, SecretMT.__le, SecretMT.__eq = refuse("compare"), refuse("compare"), refuse("compare")
SecretMT.__index = function() error("attempt to index a secret value", 2) end
SecretMT.__tostring = function() return "<secret>" end

--- Wrap v as a secret value.
---@param v any
---@return table
function wow.secret(v)
    return setmetatable({ value = v }, SecretMT)
end

--- True when v came from wow.secret.
function wow.isSecret(v)
    return realType(v) == "table" and getmetatable(v) == SecretMT
end

-- type() as the client reports it: a secret has its value's type.
local function clientType(v)
    if realType(v) == "table" and getmetatable(v) == SecretMT then return realType(rawget(v, "value")) end
    return realType(v)
end

-- Frames ---------------------------------------------------------------------------

local Frame = {}
local function noop() end
local function zero() return 0 end
local function no() return false end

local FrameMT = {
    __index = function(_, key)
        local m = Frame[key]
        if m ~= nil then return m end
        if realType(key) ~= "string" or not key:match("^%u") then return nil end
        if key:match("^Get") then return zero end
        if key:match("^Is") or key:match("^Has") or key:match("^Can") then return no end
        return noop
    end,
}

local function NewFrame(objectType, name, parent)
    local f = setmetatable({}, FrameMT)
    rawset(f, "__state", {
        type = objectType or "Frame", name = name, parent = parent, shown = true, alpha = 1, scale = 1,
        width = 0, height = 0, scripts = {}, attributes = {}, events = {}, points = {}, text = nil,
    })
    wow.frames[#wow.frames + 1] = f
    if name then _G[name] = f end
    return f
end
wow.NewFrame = NewFrame

local function S(f) return rawget(f, "__state") end

function Frame:GetName() return S(self).name end
function Frame:GetObjectType() return S(self).type end
function Frame:GetParent() return S(self).parent end
function Frame:SetParent(p) S(self).parent = p end

function Frame:Show() S(self).shown = true end
function Frame:Hide() S(self).shown = false end
function Frame:SetShown(v) S(self).shown = v and true or false end
function Frame:IsShown() return S(self).shown end
function Frame:IsVisible() return S(self).shown end

function Frame:SetAlpha(a) S(self).alpha = a end
function Frame:GetAlpha() return S(self).alpha end
function Frame:SetScale(s) S(self).scale = s end
function Frame:GetScale() return S(self).scale end
function Frame:GetEffectiveScale() return S(self).scale end

function Frame:SetSize(w, h) S(self).width, S(self).height = w, h or w end
function Frame:SetWidth(w) S(self).width = w end
function Frame:SetHeight(h) S(self).height = h end
function Frame:GetWidth() return S(self).width end
function Frame:GetHeight() return S(self).height end
function Frame:GetSize() return S(self).width, S(self).height end

function Frame:SetPoint(...) table.insert(S(self).points, { ... }) end
function Frame:ClearAllPoints() S(self).points = {} end
function Frame:GetNumPoints() return #S(self).points end
function Frame:GetPoint(i)
    local p = S(self).points[i or 1]
    if not p then return nil end
    return unpack(p)
end

function Frame:SetText(t) S(self).text = t end
function Frame:GetText() return S(self).text end
function Frame:SetFormattedText(fmt, ...)
    local args = { ... }
    for i = 1, select("#", ...) do
        if wow.isSecret(args[i]) then args[i] = rawget(args[i], "value") end
    end
    S(self).text = string.format(fmt, unpack(args, 1, select("#", ...)))
end
function Frame:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
function Frame:GetFrameLevel() return 1 end
function Frame:GetFrameStrata() return "MEDIUM" end
function Frame:GetChildren() return end
function Frame:GetRegions() return end

function Frame:SetScript(kind, fn) S(self).scripts[kind] = fn end
function Frame:GetScript(kind) return S(self).scripts[kind] end
function Frame:HookScript(kind, fn)
    local old = S(self).scripts[kind]
    S(self).scripts[kind] = old and function(...) old(...) return fn(...) end or fn
end
function Frame:HasScript() return true end

function Frame:SetAttribute(k, v) S(self).attributes[k] = v end
function Frame:GetAttribute(k) return S(self).attributes[k] end
-- SecureHandlerBaseTemplate: frame refs are stored as "frameref-<name>" attributes.
function Frame:SetFrameRef(k, frame) S(self).attributes["frameref-" .. k] = frame end

function Frame:RegisterEvent(event)
    S(self).events[event] = true
    wow.eventFrames[event] = wow.eventFrames[event] or {}
    wow.eventFrames[event][self] = true
end
function Frame:RegisterUnitEvent(event, ...)
    Frame.RegisterEvent(self, event)
    S(self).units = S(self).units or {}
    S(self).units[event] = { ... }
end
function Frame:UnregisterEvent(event)
    S(self).events[event] = nil
    if wow.eventFrames[event] then wow.eventFrames[event][self] = nil end
end
function Frame:UnregisterAllEvents()
    for event in pairs(S(self).events) do Frame.UnregisterEvent(self, event) end
end
function Frame:IsEventRegistered(event) return S(self).events[event] == true end

local function Region(self, objectType)
    local r = NewFrame(objectType, nil, self)
    return r
end
function Frame:CreateTexture() return Region(self, "Texture") end
function Frame:CreateMaskTexture() return Region(self, "MaskTexture") end
function Frame:CreateFontString() return Region(self, "FontString") end
function Frame:CreateLine() return Region(self, "Line") end
function Frame:CreateAnimationGroup() return Region(self, "AnimationGroup") end
function Frame:CreateAnimation() return Region(self, "Animation") end

--- Run a frame's script directly, as the client would.
function wow.run(frame, kind, ...)
    local fn = S(frame).scripts[kind]
    if fn then return fn(frame, ...) end
end

--- The frame's tracked state (shown, alpha, text, attributes, ...).
wow.state = S

-- Clock and timers ---------------------------------------------------------------

local EPOCH = 1767225600 -- 2026-01-01 00:00:00 UTC

local function NewTimer(delay, fn, interval, iterations)
    local t = { due = wow.now + delay, fn = fn, interval = interval, left = iterations, cancelled = false }
    function t:Cancel() self.cancelled = true end
    function t:IsCancelled() return self.cancelled end
    wow.timers[#wow.timers + 1] = t
    return t
end

local function NextDue(limit)
    local best
    for _, t in ipairs(wow.timers) do
        if not t.cancelled and t.due <= limit and (not best or t.due < best.due) then best = t end
    end
    return best
end

--- Move the clock forward, running every timer that falls due, in order.
---@param seconds number
function wow.advance(seconds)
    local target = wow.now + seconds
    while true do
        local t = NextDue(target)
        if not t then break end
        wow.now = math.max(wow.now, t.due)
        if t.interval then
            t.due = t.due + t.interval
            if t.left then
                t.left = t.left - 1
                if t.left <= 0 then t.cancelled = true end
            end
            t.fn(t)
        else
            t.cancelled = true
            t.fn()
        end
    end
    wow.now = target
    local live = {}
    for _, t in ipairs(wow.timers) do if not t.cancelled then live[#live + 1] = t end end
    wow.timers = live
end

--- Number of timers waiting to run.
function wow.pendingTimers()
    local n = 0
    for _, t in ipairs(wow.timers) do if not t.cancelled then n = n + 1 end end
    return n
end

-- Events ---------------------------------------------------------------------------

--- Deliver a game event to every frame registered for it (unit filters honoured).
function wow.fire(event, ...)
    local frames = {}
    for f in pairs(wow.eventFrames[event] or {}) do frames[#frames + 1] = f end
    table.sort(frames, function(a, b) return tostring(a) < tostring(b) end)
    for _, f in ipairs(frames) do
        local units = S(f).units and S(f).units[event]
        local unit = ...
        local pass = true
        if units and #units > 0 then
            pass = false
            for _, u in ipairs(units) do if u == unit then pass = true end end
        end
        local fn = S(f).scripts.OnEvent
        if pass and fn then fn(f, event, ...) end
    end
end

-- World ------------------------------------------------------------------------------

--- A fresh world: a level-60 warrior alone in the open world, out of combat.
local function DefaultWorld()
    return {
        units = {
            player = { name = "Tanky", class = "WARRIOR", health = 5000, healthMax = 5000,
                power = 50, powerMax = 100, powerType = 1, role = "NONE" },
        },
        inGroup = false, inRaid = false,
        inCombat = false,
        inInstance = false, instanceType = "none", zone = "Elwynn Forest",
        instance = { name = "Eastern Kingdoms", type = "none", difficultyID = 0, difficultyName = "",
            maxPlayers = 0, id = 0 },
        known = {},        -- [spellID] = true
        form = nil,        -- GetShapeshiftFormID()
        formSpell = nil,   -- spell of the active form
        offhand = "INVTYPE_SHIELD", -- equip slot of the off-hand item (nil: empty)
        auras = {},        -- [spellID] = { expirationTime = t, name = ... } on the player
        unitAuras = {},    -- [unit] = { [name] = aura }
        cooldowns = {},    -- [spellID] = { startTime, duration }
        spellNames = {},   -- [spellID] = name (default "Spell <id>")
        threat = {},       -- [unit] = UnitThreatSituation status
        targetThreat = {}, -- [unit] = { isTanking, status, scaled }
        inRange = {},      -- [unit] = { inRange, checked }
        cvars = {},
        shift = false,
        build = { "1.15.8", "60000", "Nov 1 2026", 16002 },
    }
end

local function Unit(token)
    local w = wow.world
    if token == nil then return nil end
    return w.units[token]
end

-- A world value may be a function (computed per call) or a plain value.
local function Val(v, ...)
    if realType(v) == "function" then return v(...) end
    return v
end

local function InstallAPI(G)
    local w = wow.world

    -- Lua-level helpers WoW adds.
    G.type = clientType
    G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    G.strtrim = function(s, chars)
        if chars then
            local set = "[" .. chars:gsub("[%]%^%-]", "%%%0") .. "]"
            return (s:gsub("^" .. set .. "+", ""):gsub(set .. "+$", ""))
        end
        return (s:gsub("^%s+", ""):gsub("%s+$", ""))
    end
    G.strlower, G.strupper, G.strsplit = string.lower, string.upper, nil
    G.tinsert, G.tremove = table.insert, table.remove
    G.issecretvalue = function(v) return wow.isSecret(v) end
    G.issecurevariable = function() return true, nil end
    G.hooksecurefunc = function(a, b, c)
        local tbl, name, fn = a, b, c
        if realType(a) == "string" then tbl, name, fn = _G, a, b end
        local old = tbl[name]
        tbl[name] = function(...)
            local r = { old(...) }
            fn(...)
            return unpack(r)
        end
    end

    -- Time
    G.GetTime = function() return wow.now end
    G.time = function(t) if t then return os.time(t) end return EPOCH + math.floor(wow.now) end
    G.date = function(fmt, t) return os.date(fmt, t or (EPOCH + math.floor(wow.now))) end
    G.C_Timer = {
        After = function(delay, fn) NewTimer(delay, fn) end,
        NewTimer = function(delay, fn) return NewTimer(delay, fn) end,
        NewTicker = function(interval, fn, iterations) return NewTimer(interval, fn, interval, iterations) end,
    }

    -- Build and add-on info
    G.GetBuildInfo = function() return unpack(w.build) end
    G.C_AddOns = { GetAddOnMetadata = function(_, field) if field == "Version" then return "test" end end }

    -- Frames and UI globals
    G.CreateFrame = function(objectType, name, parent) return NewFrame(objectType, name, parent) end
    G.UIParent = NewFrame("Frame", "UIParent")
    G.WorldFrame = NewFrame("Frame", "WorldFrame")
    G.Minimap = NewFrame("Minimap", "Minimap")
    G.GameTooltip = NewFrame("GameTooltip", "GameTooltip")
    G.ChatFontNormal = NewFrame("Font", "ChatFontNormal")
    G.DEFAULT_CHAT_FRAME = NewFrame("ScrollingMessageFrame", "DEFAULT_CHAT_FRAME")
    rawset(G.DEFAULT_CHAT_FRAME, "AddMessage", function(_, msg) wow.chat[#wow.chat + 1] = msg end)
    G.UISpecialFrames = {}
    G.SlashCmdList = {}
    G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    G.RAID_CLASS_COLORS = {
        WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, PALADIN = { r = 0.96, g = 0.55, b = 0.73 },
        DRUID = { r = 1, g = 0.49, b = 0.04 }, PRIEST = { r = 1, g = 1, b = 1 },
        SHAMAN = { r = 0, g = 0.44, b = 0.87 }, MAGE = { r = 0.25, g = 0.78, b = 0.92 },
        ROGUE = { r = 1, g = 0.96, b = 0.41 },
    }
    G.Enum = { PowerType = { Mana = 0, Rage = 1, Focus = 2, Energy = 3 } }
    G.GetCursorPosition = function() return 0, 0 end
    G.IsMouseButtonDown = function() return false end
    G.IsShiftKeyDown = function() return w.shift end
    G.GetMouseFoci = function() return {} end
    G.HideUIPanel = function(f) f:Hide() end
    G.SetPortraitTexture = function() end
    G.RegisterStateDriver = function() end
    G.UnregisterStateDriver = function() end
    G.RegisterUnitWatch = function() end
    G.UnregisterUnitWatch = function() end
    G.GetCVar = function(k) return w.cvars[k] end
    G.SetCVar = function(k, v) w.cvars[k] = tostring(v) end
    G.C_CVar = { GetCVar = G.GetCVar, SetCVar = G.SetCVar }
    G.PlaySound = function(id) wow.sounds[#wow.sounds + 1] = id end

    -- Combat and location
    G.InCombatLockdown = function() return w.inCombat end
    G.IsInGroup = function() return w.inGroup end
    G.IsInRaid = function() return w.inRaid end
    G.IsInInstance = function() return w.inInstance, w.instanceType end
    G.GetRealZoneText = function() return w.zone end
    G.GetInstanceInfo = function()
        local i = w.instance
        return i.name, i.type, i.difficultyID, i.difficultyName, i.maxPlayers, 0, false, i.id
    end

    -- Units
    local function Field(unit, key)
        local u = Unit(unit)
        if not u then return nil end
        return Val(u[key], unit)
    end
    G.UnitExists = function(unit) return Unit(unit) ~= nil end
    G.UnitName = function(unit) return Field(unit, "name"), Field(unit, "realm") end
    G.UnitClass = function(unit)
        local c = Field(unit, "class")
        if not c then return nil end
        return c:sub(1, 1) .. c:sub(2):lower(), c
    end
    G.UnitGUID = function(unit) return Unit(unit) and ("Player-1-" .. tostring(Field(unit, "name"))) or nil end
    G.UnitIsUnit = function(a, b)
        local ua, ub = Unit(a), Unit(b)
        return ua ~= nil and ua == ub
    end
    G.UnitCanAttack = function(_, b) return Field(b, "hostile") == true end
    G.UnitAffectingCombat = function(unit) return Field(unit, "inCombat") == true end
    G.UnitIsGroupLeader = function(unit) return Field(unit, "leader") == true end
    G.UnitGroupRolesAssigned = function(unit) return Field(unit, "role") or "NONE" end
    G.UnitIsDeadOrGhost = function(unit) return Field(unit, "dead") == true end
    G.UnitIsConnected = function(unit)
        local c = Field(unit, "connected")
        if c == nil then return Unit(unit) ~= nil end
        return c
    end
    G.UnitHealth = function(unit) return Field(unit, "health") or 0 end
    G.UnitHealthMax = function(unit) return Field(unit, "healthMax") or 0 end
    G.UnitPower = function(unit) return Field(unit, "power") or 0 end
    G.UnitPowerMax = function(unit) return Field(unit, "powerMax") or 0 end
    G.UnitPowerType = function(unit) return Field(unit, "powerType") or 0 end
    G.UnitInParty = function(unit) return Unit(unit) ~= nil and w.inGroup end
    G.UnitInRaid = function(unit) return Unit(unit) ~= nil and w.inRaid end
    G.UnitInRange = function(unit)
        local r = w.inRange[unit]
        if not r then return false, false end
        return Val(r[1]), Val(r[2])
    end
    G.UnitCastingInfo = function(unit) return Field(unit, "casting") end
    G.UnitChannelInfo = function(unit) return Field(unit, "channeling") end
    G.UnitThreatSituation = function(unit) return Val(w.threat[unit], unit) end
    G.UnitDetailedThreatSituation = function(unit)
        local t = w.targetThreat[unit]
        if not t then return nil end
        return Val(t[1]), Val(t[2]), Val(t[3]), Val(t[3]), 0
    end

    -- Stances and forms
    G.GetShapeshiftFormID = function() return Val(w.form) end
    G.GetShapeshiftForm = function() return w.formSpell and 1 or 0 end
    G.GetNumShapeshiftForms = function() return w.formSpell and 1 or 0 end
    G.GetShapeshiftFormInfo = function(i)
        if i == 1 and w.formSpell then return 132341, true, true, w.formSpell end
    end

    -- Gear: only the off hand (slot 17) is modelled, as an equip location.
    G.GetInventoryItemID = function(_, slot)
        if slot ~= 17 then return nil end
        local loc = Val(w.offhand)
        if wow.isSecret(loc) then return loc end
        return loc and 4000 or nil
    end
    G.C_Item = {
        GetItemInfoInstant = function(id)
            if id ~= 4000 then return nil end
            return id, "Weapon", "Shield", Val(w.offhand), 134955, 4, 6
        end,
    }

    -- Spells, cooldowns, auras
    local function SpellName(id) return w.spellNames[id] or ("Spell " .. tostring(id)) end
    G.C_SpellBook = { IsSpellKnownOrInSpellBook = function(id) return w.known[id] == true end }
    G.C_Spell = {
        GetSpellName = function(id) return SpellName(id) end,
        GetSpellInfo = function(id) return { name = SpellName(id), spellID = id } end,
        GetSpellTexture = function() return 134400 end,
        GetSpellCooldown = function(id)
            local c = w.cooldowns[id]
            if wow.isSecret(c) then return c end
            c = c or { 0, 0 }
            return { startTime = c[1], duration = c[2], isEnabled = true, modRate = 1 }
        end,
    }
    G.C_UnitAuras = {
        GetPlayerAuraBySpellID = function(id) return Val(w.auras[id]) end,
        GetAuraDataBySpellName = function(unit, name)
            local list = w.unitAuras[unit]
            if list and list[name] then return list[name] end
            if unit == "player" then
                for id, a in pairs(w.auras) do
                    if not wow.isSecret(a) and SpellName(id) == name then return a end
                end
            end
            return nil
        end,
    }
end

-- Install --------------------------------------------------------------------------

local installed = {}

--- Put a fresh client into _G. `world` overrides fields of the default world.
---@param world table|nil
function wow.install(world)
    wow.uninstall()
    wow.now = 1000
    wow.timers, wow.frames, wow.eventFrames = {}, {}, {}
    wow.chat, wow.sounds = {}, {}
    wow.world = DefaultWorld()
    for k, v in pairs(world or {}) do wow.world[k] = v end

    local G = {}
    InstallAPI(G)
    for k, v in pairs(G) do
        if installed[k] == nil then installed[k] = { old = rawget(_G, k) } end
        rawset(_G, k, v)
    end
    -- Frame names CreateFrame put into _G are removed by uninstall too.
    wow.globalsBefore = {}
    for k in pairs(_G) do wow.globalsBefore[k] = true end
end

--- Restore _G to how it was before install (busted also isolates _G per file).
function wow.uninstall()
    for k, rec in pairs(installed) do rawset(_G, k, rec.old) end
    installed = {}
    if wow.globalsBefore then
        for k in pairs(_G) do
            if not wow.globalsBefore[k] then rawset(_G, k, nil) end
        end
        wow.globalsBefore = nil
    end
end

--- Messages printed to chat since install, as one string (handy for `match`).
function wow.chatText() return table.concat(wow.chat, "\n") end

--- Add a group member. `unit` "party1".."party4" or "raid1".. ; fields as in world.units.
function wow.addUnit(unit, fields)
    wow.world.units[unit] = fields
    return fields
end

return wow
