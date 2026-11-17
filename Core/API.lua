-- Core/API.lua
-- Secret-value safety layer for the WoW: Forever client.
--
-- Adapted from TankCompanion's Core/API.lua (MIT License, Copyright (c) 2025
-- SteveWeed79; see THIRD_PARTY_NOTICES.md).
--
-- Forever runs on the Midnight client. In combat (and in some instances) the
-- client hands addons "secret values" for health, power, aura timers and
-- cooldowns. A secret can be handed to a widget (StatusBar:SetValue,
-- Cooldown, FontString:SetFormattedText) but any comparison or arithmetic on
-- it raises a Lua error. Everything in TankForgeUI that touches those values
-- goes through this file.
local _, ns = ...

local API = {}
ns.API = API

local issecretvalue = _G.issecretvalue
local type, pcall = type, pcall

--- True when v is a secret value (no comparing or arithmetic allowed on it).
---@param v any
---@return boolean
function API.IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

--- v when it is a plain number, otherwise nil.
function API.PlainNumber(v)
    if type(v) ~= "number" then return nil end
    if API.IsSecret(v) then return nil end
    return v
end

--- v when it is a plain boolean, otherwise nil.
function API.PlainBool(v)
    if type(v) ~= "boolean" then return nil end
    if API.IsSecret(v) then return nil end
    return v
end

--- v when it is a plain, non-empty string, otherwise nil.
function API.PlainString(v)
    if type(v) ~= "string" then return nil end
    if API.IsSecret(v) then return nil end
    if v == "" then return nil end
    return v
end

--- Call fn, returning nil instead of raising.
local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g, h = pcall(fn, ...)
    if not ok then return nil end
    return a, b, c, d, e, f, g, h
end
API.Safe = safe

API.Now = _G.GetTime or function() return os.clock() end

local function BuildNumber()
    if type(_G.GetBuildInfo) ~= "function" then return 0 end
    local _, _, _, toc = _G.GetBuildInfo()
    return tonumber(toc) or 0
end
API.buildNumber = BuildNumber()
API.isForever = API.buildNumber >= 16000 and API.buildNumber < 17000

-- Units ----------------------------------------------------------------------

---@param unit string
---@return boolean
function API.UnitExists(unit)
    return API.PlainBool((safe(_G.UnitExists, unit))) == true
end

--- Class file name ("WARRIOR"), or nil when unknown or secret.
---@param unit string
---@return string|nil
function API.UnitClass(unit)
    local _, class = safe(_G.UnitClass, unit)
    if type(class) ~= "string" or API.IsSecret(class) then return nil end
    return class
end

---@param unit string
---@return string|nil
function API.UnitName(unit)
    return API.PlainString((safe(_G.UnitName, unit)))
end

--- nil when either token is missing or the answer is secret.
---@return boolean|nil
function API.UnitIsUnit(a, b)
    if not a or not b then return nil end
    return API.PlainBool((safe(_G.UnitIsUnit, a, b)))
end

---@return boolean|nil
function API.UnitCanAttack(a, b)
    return API.PlainBool((safe(_G.UnitCanAttack, a, b)))
end

---@return boolean|nil
function API.UnitAffectingCombat(unit)
    return API.PlainBool((safe(_G.UnitAffectingCombat, unit)))
end

---@return boolean
function API.IsLeader(unit)
    return API.PlainBool((safe(_G.UnitIsGroupLeader, unit))) == true
end

--- "TANK", "HEALER", "DAMAGER", "NONE", or nil when unreadable.
---@param unit string
---@return string|nil
function API.UnitRole(unit)
    local role = safe(_G.UnitGroupRolesAssigned, unit)
    if type(role) ~= "string" or API.IsSecret(role) then return nil end
    return role
end

---@return boolean
function API.IsDeadOrGhost(unit)
    return API.PlainBool((safe(_G.UnitIsDeadOrGhost, unit))) == true
end

--- True unless the client plainly says the unit is offline.
---@return boolean
function API.IsConnected(unit)
    local r = safe(_G.UnitIsConnected, unit)
    if API.IsSecret(r) then return true end
    return r ~= false
end

--- r, g, b for a class, light grey when unknown.
---@param class string|nil
---@return number, number, number
function API.ClassColor(class)
    local colors = _G.RAID_CLASS_COLORS
    local c = class and colors and colors[class]
    if c then return c.r, c.g, c.b end
    return 0.85, 0.85, 0.85
end

-- Stance / form -------------------------------------------------------------

--- Defensive Stance 18, Bear Form 5, Dire Bear Form 8; nil in no form.
---@return number|nil
function API.GetShapeshiftFormID()
    return API.PlainNumber(safe(_G.GetShapeshiftFormID))
end

--- The spell ID of the active stance or form, or nil.
---@return number|nil
function API.GetActiveFormSpellID()
    local index = API.PlainNumber(safe(_G.GetShapeshiftForm))
    if not index or index <= 0 then return nil end
    local _, _, _, spellID = safe(_G.GetShapeshiftFormInfo, index)
    return API.PlainNumber(spellID)
end

--- True with a shield in the off hand (slot 17). Only a readable answer says no:
--- an empty slot, or an item that isn't a shield. Anything unreadable (no API,
--- an error, a secret) counts as true, so callers never hide something on a guess.
---@return boolean
function API.HasShield()
    local get = _G.GetInventoryItemID
    if type(get) ~= "function" then return true end
    local ok, id = pcall(get, "player", 17)
    if not ok or API.IsSecret(id) then return true end
    if id == nil then return false end
    if not API.PlainNumber(id) then return true end
    local CI = _G.C_Item
    local info = CI and CI.GetItemInfoInstant or _G.GetItemInfoInstant
    local _, _, _, equipLoc = safe(info, id)
    equipLoc = API.PlainString(equipLoc)
    if not equipLoc then return true end
    return equipLoc == "INVTYPE_SHIELD"
end

--- Every stance / form slot as { icon, active, castable, spellID }, in bar
--- order. Unreadable (secret) fields are nil. Pass `into` to refill a list
--- (and its entries) from an earlier call instead of building new tables,
--- for callers that run often.
---@param into table|nil
---@return {icon: number|string|nil, active: boolean, castable: boolean|nil, spellID: number|nil}[]
function API.GetShapeshiftForms(into)
    local list = into or {}
    local n = API.PlainNumber(safe(_G.GetNumShapeshiftForms)) or 0
    for i = 1, n do
        local icon, active, castable, spellID = safe(_G.GetShapeshiftFormInfo, i)
        local form = list[i] or {}
        form.icon = API.PlainNumber(icon) or API.PlainString(icon)
        form.active = API.PlainBool(active) or API.PlainNumber(active) == 1
        form.castable = API.PlainBool(castable)
        form.spellID = API.PlainNumber(spellID)
        list[i] = form
    end
    for i = #list, n + 1, -1 do list[i] = nil end
    return list
end

-- Spells ---------------------------------------------------------------------

--- True when the player knows spellID. Tries each spellbook API this client has,
--- and treats a secret or missing answer as "ask the next one".
---@param spellID number
---@return boolean
function API.IsSpellKnown(spellID)
    if type(spellID) ~= "number" then return false end
    local SB = _G.C_SpellBook
    if SB then
        local probes = { SB.IsSpellKnownOrInSpellBook, SB.IsSpellKnown, SB.IsSpellInSpellBook }
        for i = 1, 3 do
            local fn = probes[i]
            if type(fn) == "function" then
                local r = safe(fn, spellID)
                if not API.IsSecret(r) and r ~= nil then return r == true end
            end
        end
    end
    -- A numeric loop: ipairs would stop at the first missing function.
    local probes = { _G.IsSpellKnownOrOverridesKnown, _G.IsPlayerSpell, _G.IsSpellKnown }
    for i = 1, 3 do
        local fn = probes[i]
        if type(fn) == "function" then
            local r = safe(fn, spellID)
            if not API.IsSecret(r) and r ~= nil then return r == true end
        end
    end
    return false
end

--- The item link for a group loot roll, or nil.
---@param rollID number
---@return string|nil
function API.LootRollItemLink(rollID)
    return API.PlainString((safe(_G.GetLootRollItemLink, rollID)))
end

---@param spellID number
---@return string|nil
function API.GetSpellName(spellID)
    local CS = _G.C_Spell
    if CS and type(CS.GetSpellName) == "function" then
        local n = safe(CS.GetSpellName, spellID)
        if API.PlainString(n) then return n end
    end
    if CS and type(CS.GetSpellInfo) == "function" then
        local info = safe(CS.GetSpellInfo, spellID)
        if type(info) == "table" and not API.IsSecret(info) and API.PlainString(info.name) then
            return info.name
        end
    end
    return nil
end

--- Texture ID, or the question-mark icon.
---@return number|string
function API.GetSpellIcon(spellID)
    local CS = _G.C_Spell
    if CS and type(CS.GetSpellTexture) == "function" then
        local icon = safe(CS.GetSpellTexture, spellID)
        if not API.IsSecret(icon) and icon then return icon end
    end
    return 134400 -- question mark
end

--- start, duration as plain numbers, or nil when secret / unavailable.
---@param spellID number
---@return number|nil start, number|nil duration
function API.GetSpellCooldownPlain(spellID)
    local CS = _G.C_Spell
    if not (CS and type(CS.GetSpellCooldown) == "function") then return nil end
    local info = safe(CS.GetSpellCooldown, spellID)
    if type(info) ~= "table" or API.IsSecret(info) then return nil end
    local start = API.PlainNumber(info.startTime)
    local duration = API.PlainNumber(info.duration)
    if not start or not duration then return nil end
    return start, duration
end

--- Drive a Cooldown widget from a spell's cooldown, secret or not.
---@return boolean applied
function API.ApplySpellCooldown(cooldownFrame, spellID)
    if not cooldownFrame or not spellID then return false end
    local CS = _G.C_Spell
    if cooldownFrame.SetCooldownFromDurationObject and CS and type(CS.GetSpellCooldownDuration) == "function" then
        local d = safe(CS.GetSpellCooldownDuration, spellID, false)
        if d and pcall(cooldownFrame.SetCooldownFromDurationObject, cooldownFrame, d) then
            return true
        end
    end
    local info = CS and type(CS.GetSpellCooldown) == "function" and safe(CS.GetSpellCooldown, spellID)
    if type(info) == "table" and not API.IsSecret(info) then
        if pcall(cooldownFrame.SetCooldown, cooldownFrame, info.startTime, info.duration, info.modRate) then
            return true
        end
    end
    pcall(cooldownFrame.Clear, cooldownFrame)
    return false
end

-- Auras ----------------------------------------------------------------------

--- A helpful aura on `unit` by spell name, as a readable table, or nil.
---@param unit string
---@param name string|nil
---@param filter string|nil default "HELPFUL"
---@return table|nil aura
function API.GetAuraByName(unit, name, filter)
    local UA = _G.C_UnitAuras
    if not name or not (UA and type(UA.GetAuraDataBySpellName) == "function") then return nil end
    local aura = safe(UA.GetAuraDataBySpellName, unit, name, filter or "HELPFUL")
    if type(aura) == "table" and not API.IsSecret(aura) then return aura end
    return nil
end

--- A buff on the player, readable, or nil. On Forever every rank of a buff is
--- its own spell ID, so a miss by ID is retried by name.
---@param spellID number
---@return table|nil aura with expirationTime, name, ...
function API.GetPlayerAura(spellID)
    if type(spellID) ~= "number" then return nil end
    local UA = _G.C_UnitAuras
    if UA and type(UA.GetPlayerAuraBySpellID) == "function" then
        local aura = safe(UA.GetPlayerAuraBySpellID, spellID)
        if type(aura) == "table" and not API.IsSecret(aura) then return aura end
    end
    return API.GetAuraByName("player", API.GetSpellName(spellID), "HELPFUL")
end

--- True when the client answered for the aura with a secret: it may be up,
--- and nothing about it can be read.
---@param spellID number
---@return boolean
function API.PlayerAuraHidden(spellID)
    local UA = _G.C_UnitAuras
    if type(spellID) ~= "number" or not (UA and type(UA.GetPlayerAuraBySpellID) == "function") then
        return false
    end
    return API.IsSecret(safe(UA.GetPlayerAuraBySpellID, spellID))
end

-- Unit values ----------------------------------------------------------------

----- Raw unit values, possibly secret: for widgets, or for PlainNumber.
function API.UnitHealthRaw(unit) return safe(_G.UnitHealth, unit) end
function API.UnitHealthMaxRaw(unit) return safe(_G.UnitHealthMax, unit) end
function API.UnitPowerRaw(unit, ptype) return safe(_G.UnitPower, unit, ptype) end
function API.UnitPowerMaxRaw(unit, ptype) return safe(_G.UnitPowerMax, unit, ptype) end

---@return number|nil
function API.UnitPowerType(unit)
    return API.PlainNumber((safe(_G.UnitPowerType, unit)))
end

--- Power as a fraction 0..1 when readable, else nil.
---@param unit string
---@param ptype number|nil
---@return number|nil
function API.PowerFraction(unit, ptype)
    local cur = API.PlainNumber(API.UnitPowerRaw(unit, ptype))
    local max = API.PlainNumber(API.UnitPowerMaxRaw(unit, ptype))
    if cur and max and max > 0 then return cur / max end
    return nil
end

-- Widgets --------------------------------------------------------------------

--- StatusBar min/max/value; the widget accepts secrets.
function API.SetBarValues(bar, minV, maxV, value)
    if not bar then return end
    pcall(bar.SetMinMaxValues, bar, minV or 0, maxV or 1)
    pcall(bar.SetValue, bar, value or 0)
end

--- Abbreviated number for a label, secret or not; nil when impossible.
---@param n any number, possibly secret
---@return string|nil
function API.AbbrevDisplay(n)
    if not n then return nil end
    local plain = API.PlainNumber(n)
    if plain then return API.Abbrev(plain) end
    local abbrev = _G.AbbreviateLargeNumbers or _G.AbbreviateNumbers
    if type(abbrev) ~= "function" then return nil end
    local ok, text = pcall(abbrev, n)
    if ok and text then return text end
    return nil
end

--- Percentage 0..100 for health or power, secret or not; nil when impossible.
---@param unit string
---@param ptype number|nil power type; nil for health
---@return number|nil percent, possibly secret
function API.PercentDisplay(unit, ptype)
    local cur, max
    if ptype then
        cur, max = API.UnitPowerRaw(unit, ptype), API.UnitPowerMaxRaw(unit, ptype)
    else
        cur, max = API.UnitHealthRaw(unit), API.UnitHealthMaxRaw(unit)
    end
    local pc, pm = API.PlainNumber(cur), API.PlainNumber(max)
    if pc and pm then return pm > 0 and pc / pm * 100 or 0 end
    local curve = _G.CurveConstants and _G.CurveConstants.ScaleTo100
    if not curve then return nil end
    local fn = ptype and _G.UnitPowerPercent or _G.UnitHealthPercent
    if type(fn) ~= "function" then return nil end
    local ok, pct
    if ptype then
        ok, pct = pcall(fn, unit, ptype, true, curve)
    else
        ok, pct = pcall(fn, unit, true, curve)
    end
    if ok and pct then return pct end
    return nil
end

--- Alpha from a boolean that may be secret. Falls back to a plain test, and to
--- alphaTrue when the answer can't be read at all.
function API.SetAlphaFromBool(region, value, alphaTrue, alphaFalse)
    if not region then return end
    if region.SetAlphaFromBoolean and pcall(region.SetAlphaFromBoolean, region, value, alphaTrue, alphaFalse) then
        return
    end
    local plain = API.PlainBool(value)
    if plain == false then
        region:SetAlpha(alphaFalse)
    else
        region:SetAlpha(alphaTrue)
    end
end

--- Is `unit` out of range? true only when the game says it actually checked
--- and the unit is out of range (UnitInRange returns false, false when it
--- couldn't check, which must not count). false when in range or unknown.
--- Also returns the raw answer for widgets that can show a secret one.
---@param unit string
---@return boolean outOfRange, any secretInRange
function API.RangeState(unit)
    local inRange, checked = safe(_G.UnitInRange, unit)
    if API.PlainBool(checked) ~= true then return false, nil end
    local plain = API.PlainBool(inRange)
    if plain ~= nil then return not plain, nil end
    return false, inRange  -- checked, but the answer itself is secret
end

--- Set `region` to `base` opacity, dimmed by `dim` when the unit is out of range.
---@param base number opacity in range
---@param dim number multiplier when out of range
---@param enabled boolean dim at all
function API.ApplyRangeAlpha(region, unit, base, dim, enabled)
    if not enabled then
        region:SetAlpha(base)
        return
    end
    local out, secret = API.RangeState(unit)
    if secret ~= nil then
        API.SetAlphaFromBool(region, secret, base, base * dim)
    else
        region:SetAlpha(out and base * dim or base)
    end
end

-- Formatting -----------------------------------------------------------------

local SIZE_UNITS = { { 1e9, "B" }, { 1e6, "M" }, { 1e3, "k" } }

-- v with 3 significant digits, trailing zeros dropped: 1.5, 12.3, 999.
local function ThreeDigits(v)
    local digits = math.abs(v) >= 100 and 0 or (math.abs(v) >= 10 and 1 or 2)
    local text = string.format("%." .. digits .. "f", v)
    if digits > 0 then text = text:gsub("0+$", ""):gsub("%.$", "") end
    return text
end

--- A short label for a plain number: 950, 1.5k, 12.3M, 2B. "?" when not a plain number.
---@param n any
---@return string
function API.Abbrev(n)
    n = API.PlainNumber(n)
    if not n then return "?" end
    local a = math.abs(n)
    if a < 1000 then return string.format("%d", n) end
    for i, u in ipairs(SIZE_UNITS) do
        if a >= u[1] then
            local text = ThreeDigits(n / u[1])
            -- 999,999 rounds up to "1000k"; the next unit up reads better.
            if i > 1 and math.abs(tonumber(text)) >= 1000 then
                local up = SIZE_UNITS[i - 1]
                return ThreeDigits(n / up[1]) .. up[2]
            end
            return text .. u[2]
        end
    end
end

--- The client's add-on profiler metrics read by API.AddOnMetrics, in display order.
API.PROFILER_METRICS = { "RecentAverageTime", "SessionAverageTime", "EncounterAverageTime", "PeakTime",
    "CountTimeOver5Ms", "CountTimeOver10Ms", "CountTimeOver50Ms" }

--- An add-on's CPU metrics from the client's profiler (C_AddOnProfiler), by
--- metric name (times in ms, counts in frames). Metrics this client lacks are
--- left out; nil when there's no profiler at all.
---@param name string add-on folder name
---@return table<string, number>|nil
function API.AddOnMetrics(name)
    local P = _G.C_AddOnProfiler
    local E = _G.Enum and _G.Enum.AddOnProfilerMetric
    if not (P and E and type(P.GetAddOnMetric) == "function") then return nil end
    local out = {}
    for _, key in ipairs(API.PROFILER_METRICS) do
        if E[key] ~= nil then
            local v = API.PlainNumber(safe(P.GetAddOnMetric, name, E[key]))
            if v then out[key] = v end
        end
    end
    return out
end

--- The current instance from GetInstanceInfo, with plain values only (nil when unknown).
---@return {name: string?, type: string?, difficultyID: number?, difficulty: string?, size: number?, id: number?}
function API.InstanceInfo()
    local name, itype, diffID, diffName, maxPlayers, _, _, instanceID = safe(_G.GetInstanceInfo)
    return {
        name = API.PlainString(name), type = API.PlainString(itype),
        difficultyID = API.PlainNumber(diffID), difficulty = API.PlainString(diffName),
        size = API.PlainNumber(maxPlayers), id = API.PlainNumber(instanceID),
    }
end

--- "m:ss" for a number of seconds; negatives and junk read as 0.
---@param s any
---@return string
function API.FormatSeconds(s)
    s = math.max(math.floor(tonumber(s) or 0), 0)
    return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

local POWER = { Mana = 0, Rage = 1, Focus = 2, Energy = 3 }
--- Power type number for "Mana", "Rage", "Focus" or "Energy".
---@param name string
---@return number|nil
function API.PowerType(name)
    local E = _G.Enum and _G.Enum.PowerType
    if E and E[name] ~= nil then return E[name] end
    return POWER[name]
end

--- Play the "warning" (raid warning) or any other kind (alarm) sound.
---@param kind string
function API.PlaySound(kind)
    local SK = _G.SOUNDKIT
    local id
    if kind == "warning" then
        id = (SK and SK.RAID_WARNING) or 8959
    else
        id = (SK and SK.ALARM_CLOCK_WARNING_3) or 12889
    end
    safe(_G.PlaySound, id, "Master")
end
