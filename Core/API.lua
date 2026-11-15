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

function API.IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

-- v when it is a plain number, otherwise nil.
function API.PlainNumber(v)
    if type(v) ~= "number" then return nil end
    if API.IsSecret(v) then return nil end
    return v
end

-- v when it is a plain boolean, otherwise nil.
function API.PlainBool(v)
    if type(v) ~= "boolean" then return nil end
    if API.IsSecret(v) then return nil end
    return v
end

-- v when it is a plain, non-empty string, otherwise nil.
function API.PlainString(v)
    if type(v) ~= "string" then return nil end
    if API.IsSecret(v) then return nil end
    if v == "" then return nil end
    return v
end

-- Call fn, returning nil instead of raising.
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

function API.UnitExists(unit)
    return API.PlainBool((safe(_G.UnitExists, unit))) == true
end

function API.UnitClass(unit)
    local _, class = safe(_G.UnitClass, unit)
    if type(class) ~= "string" or API.IsSecret(class) then return nil end
    return class
end

function API.UnitName(unit)
    return API.PlainString((safe(_G.UnitName, unit)))
end

function API.UnitIsUnit(a, b)
    if not a or not b then return nil end
    return API.PlainBool((safe(_G.UnitIsUnit, a, b)))
end

function API.UnitCanAttack(a, b)
    return API.PlainBool((safe(_G.UnitCanAttack, a, b)))
end

function API.UnitAffectingCombat(unit)
    return API.PlainBool((safe(_G.UnitAffectingCombat, unit)))
end

function API.IsLeader(unit)
    return API.PlainBool((safe(_G.UnitIsGroupLeader, unit))) == true
end

function API.UnitRole(unit)
    local role = safe(_G.UnitGroupRolesAssigned, unit)
    if type(role) ~= "string" or API.IsSecret(role) then return nil end
    return role
end

function API.IsDeadOrGhost(unit)
    return API.PlainBool((safe(_G.UnitIsDeadOrGhost, unit))) == true
end

function API.IsConnected(unit)
    local r = safe(_G.UnitIsConnected, unit)
    if API.IsSecret(r) then return true end
    return r ~= false
end

function API.ClassColor(class)
    local colors = _G.RAID_CLASS_COLORS
    local c = class and colors and colors[class]
    if c then return c.r, c.g, c.b end
    return 0.85, 0.85, 0.85
end

-- Stance / form -------------------------------------------------------------

-- Defensive Stance 18, Bear Form 5, Dire Bear Form 8; nil in no form.
function API.GetShapeshiftFormID()
    return API.PlainNumber(safe(_G.GetShapeshiftFormID))
end

function API.GetActiveFormSpellID()
    local index = API.PlainNumber(safe(_G.GetShapeshiftForm))
    if not index or index <= 0 then return nil end
    local _, _, _, spellID = safe(_G.GetShapeshiftFormInfo, index)
    return API.PlainNumber(spellID)
end

-- Spells ---------------------------------------------------------------------

function API.IsSpellKnown(spellID)
    if type(spellID) ~= "number" then return false end
    local SB = _G.C_SpellBook
    if SB then
        for _, fn in ipairs({ SB.IsSpellKnownOrInSpellBook, SB.IsSpellKnown, SB.IsSpellInSpellBook }) do
            if type(fn) == "function" then
                local r = safe(fn, spellID)
                if not API.IsSecret(r) and r ~= nil then return r == true end
            end
        end
    end
    for _, fn in ipairs({ _G.IsSpellKnownOrOverridesKnown, _G.IsPlayerSpell, _G.IsSpellKnown }) do
        if type(fn) == "function" then
            local r = safe(fn, spellID)
            if not API.IsSecret(r) and r ~= nil then return r == true end
        end
    end
    return false
end

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

function API.GetSpellIcon(spellID)
    local CS = _G.C_Spell
    if CS and type(CS.GetSpellTexture) == "function" then
        local icon = safe(CS.GetSpellTexture, spellID)
        if not API.IsSecret(icon) and icon then return icon end
    end
    return 134400 -- question mark
end

-- start, duration as plain numbers, or nil when secret / unavailable.
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

-- Drive a Cooldown widget from a spell's cooldown, secret or not.
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

-- A helpful aura on `unit` by spell name, as a readable table, or nil.
function API.GetAuraByName(unit, name, filter)
    local UA = _G.C_UnitAuras
    if not name or not (UA and type(UA.GetAuraDataBySpellName) == "function") then return nil end
    local aura = safe(UA.GetAuraDataBySpellName, unit, name, filter or "HELPFUL")
    if type(aura) == "table" and not API.IsSecret(aura) then return aura end
    return nil
end

-- A buff on the player, readable, or nil. On Forever every rank of a buff is
-- its own spell ID, so a miss by ID is retried by name.
function API.GetPlayerAura(spellID)
    if type(spellID) ~= "number" then return nil end
    local UA = _G.C_UnitAuras
    if UA and type(UA.GetPlayerAuraBySpellID) == "function" then
        local aura = safe(UA.GetPlayerAuraBySpellID, spellID)
        if type(aura) == "table" and not API.IsSecret(aura) then return aura end
    end
    return API.GetAuraByName("player", API.GetSpellName(spellID), "HELPFUL")
end

-- True when the client answered for the aura with a secret: it may be up,
-- and nothing about it can be read.
function API.PlayerAuraHidden(spellID)
    local UA = _G.C_UnitAuras
    if type(spellID) ~= "number" or not (UA and type(UA.GetPlayerAuraBySpellID) == "function") then
        return false
    end
    return API.IsSecret(safe(UA.GetPlayerAuraBySpellID, spellID))
end

-- Unit values ----------------------------------------------------------------

function API.UnitHealthRaw(unit) return safe(_G.UnitHealth, unit) end
function API.UnitHealthMaxRaw(unit) return safe(_G.UnitHealthMax, unit) end
function API.UnitPowerRaw(unit, ptype) return safe(_G.UnitPower, unit, ptype) end
function API.UnitPowerMaxRaw(unit, ptype) return safe(_G.UnitPowerMax, unit, ptype) end

function API.UnitPowerType(unit)
    return API.PlainNumber((safe(_G.UnitPowerType, unit)))
end

-- Power as a fraction 0..1 when readable, else nil.
function API.PowerFraction(unit, ptype)
    local cur = API.PlainNumber(API.UnitPowerRaw(unit, ptype))
    local max = API.PlainNumber(API.UnitPowerMaxRaw(unit, ptype))
    if cur and max and max > 0 then return cur / max end
    return nil
end

-- Widgets --------------------------------------------------------------------

-- StatusBar min/max/value; the widget accepts secrets.
function API.SetBarValues(bar, minV, maxV, value)
    if not bar then return end
    pcall(bar.SetMinMaxValues, bar, minV or 0, maxV or 1)
    pcall(bar.SetValue, bar, value or 0)
end

-- Abbreviated number for a label, secret or not; nil when impossible.
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

-- Percentage 0..100 for health or power, secret or not; nil when impossible.
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

-- Alpha from a boolean that may be secret. Falls back to a plain test, and to
-- alphaTrue when the answer can't be read at all.
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

-- Is `unit` out of range? true only when the game says it actually checked
-- and the unit is out of range (UnitInRange returns false, false when it
-- couldn't check, which must not count). false when in range or unknown.
-- Also returns the raw answer for widgets that can show a secret one.
function API.RangeState(unit)
    local inRange, checked = safe(_G.UnitInRange, unit)
    if API.PlainBool(checked) ~= true then return false, nil end
    local plain = API.PlainBool(inRange)
    if plain ~= nil then return not plain, nil end
    return false, inRange  -- checked, but the answer itself is secret
end

-- Set `region` to `base` opacity, dimmed by `dim` when the unit is out of range.
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
function API.Abbrev(n)
    n = API.PlainNumber(n)
    if not n then return "?" end
    local a = math.abs(n)
    if a < 1000 then return string.format("%d", n) end
    for _, u in ipairs(SIZE_UNITS) do
        if a >= u[1] then
            local v = n / u[1]
            local digits = math.abs(v) >= 100 and 0 or (math.abs(v) >= 10 and 1 or 2)
            local text = string.format("%." .. digits .. "f", v)
            if digits > 0 then text = text:gsub("0+$", ""):gsub("%.$", "") end
            return text .. u[2]
        end
    end
end

function API.FormatSeconds(s)
    s = math.max(math.floor(tonumber(s) or 0), 0)
    return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

local POWER = { Mana = 0, Rage = 1, Focus = 2, Energy = 3 }
function API.PowerType(name)
    local E = _G.Enum and _G.Enum.PowerType
    if E and E[name] ~= nil then return E[name] end
    return POWER[name]
end

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
