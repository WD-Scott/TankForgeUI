-- Modules/Threat.lua
-- Threat on your target, and loose mobs.
--
-- The list shows each group member's scaled threat on your target: 100% is
-- where a non-tank would pull it off you. Below it: who in the group has a mob
-- on them. That comes from each member's own threat status
-- (UnitThreatSituation), which Forever keeps readable in combat; mob names,
-- GUIDs and "who is it targeting" are hidden in combat, so nameplates can't be
-- used for this. Fires LOOSE when a member picks up a mob, for the alerts and
-- the pull report. Every threat value is checked for secrecy before it's read.
--
-- Cost: the group roster is cached and only rebuilt when the group changes.
-- Each tick reads one threat status per group member: O(G). The list and the
-- check share one 0.2s tick, which only runs in combat or while the panel is
-- up, and the list reuses its tables between updates.
local _, ns = ...
local TF = ns.TF
local API = ns.API
local Style = ns.Style
local Tank = ns.Tank

local Threat = {}
ns.Threat = Threat
Threat.looseCount = 0
Threat.healerAttacked = false

local WIDTH = 210
local ROW_H = 16
local PAD = 6
local MAX_ROWS = 10
local TICK = 0.2

local C, HEX = Style.colors, Style.HEX
local SetText = Style.SetText

local f = Style.Panel(UIParent, "TankForgeUIThreat")
f:SetSize(WIDTH, 60)
f:Hide()
Threat.frame = f

f.title = Style.Text(f, 12)
f.title:SetPoint("TOPLEFT", PAD, -PAD - 2)
f.title:SetPoint("RIGHT", f, "RIGHT", -70, 0)
f.title:SetJustifyH("LEFT")
f.status = Style.Text(f, 11)
f.status:SetPoint("TOPRIGHT", -PAD, -PAD - 3)
f.status:SetJustifyH("RIGHT")
f.footer = Style.Text(f, 11)
f.footer:SetJustifyH("LEFT")
f.rows = {}

Style.Movable(f, "threat", "Threat", { "CENTER", "CENTER", 230, -110 })

local function Row(i)
    local r = f.rows[i]
    if r then return r end
    r = Style.Bar(f, ROW_H, Style.colors.muted, 11)
    r:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(PAD + 18 + (i - 1) * (ROW_H + 2)))
    r:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -(PAD + 18 + (i - 1) * (ROW_H + 2)))
    r:SetMinMaxValues(0, 100)
    f.rows[i] = r
    return r
end

-- Group roster (cached) -----------------------------------------------------------

local roster = {
    units = {},   -- every group unit and pet, players first
    byName = {},  -- "Name" or "Name-Realm" -> unit
    info = {},    -- unit -> { name, class, isPet, me }
}
local rosterDirty = true

--- "Name-Realm" for someone from another realm, "Name" otherwise; nil when unreadable.
local function FullName(unit)
    local name, realm = API.Safe(UnitName, unit)
    name = API.PlainString(name)
    if not name then return nil end
    realm = API.PlainString(realm)
    return realm and (name .. "-" .. realm) or name
end

----- Cache every group unit (players first, then pets) with its last readable
----- name, class and role.
local function RebuildRoster()
    local units, byName, info = roster.units, roster.byName, roster.info
    wipe(units)
    wipe(byName)
    local function Add(unit, isPet)
        if not API.UnitExists(unit) then return end
        units[#units + 1] = unit
        local e = info[unit] or {}
        info[unit] = e
        -- Names, classes and identity can be hidden in combat: keep the last
        -- readable answer for this slot rather than showing "?".
        e.name = API.UnitName(unit) or e.name or "?"
        e.class = API.UnitClass(unit) or e.class
        e.isPet = isPet
        local isMe = unit == "player" or API.UnitIsUnit(unit, "player")
        if isMe ~= nil then e.me = isMe end
        e.role = API.UnitRole(unit)
        -- Another real tank (by role and a tanking class) isn't a loose mob.
        e.otherTank = not e.me and e.role == "TANK" and ns.Kits[e.class or ""] ~= nil or false
        local key = FullName(unit)
        -- Players are added first, so a pet sharing a player's name never wins.
        if key and not byName[key] then byName[key] = unit end
    end
    if IsInRaid() then
        for i = 1, 40 do Add("raid" .. i, false) end
        for i = 1, 40 do Add("raidpet" .. i, true) end
    else
        Add("player", false)
        for i = 1, 4 do Add("party" .. i, false) end
        Add("pet", true)
        for i = 1, 4 do Add("partypet" .. i, true) end
    end
    rosterDirty = false
end

local GROUP_UNIT = { player = true, pet = true }
for i = 1, 4 do GROUP_UNIT["party" .. i] = true GROUP_UNIT["partypet" .. i] = true end
for i = 1, 40 do GROUP_UNIT["raid" .. i] = true GROUP_UNIT["raidpet" .. i] = true end

--- True for a group unit token (player, pet, partyN, partypetN, raidN, raidpetN),
--- false for nameplates, target and the rest. nil (some events omit the unit) counts.
---@param unit string|nil
---@return boolean
function Threat.IsGroupUnit(unit)
    if unit == nil then return true end
    return GROUP_UNIT[unit] == true
end

local function Roster()
    if rosterDirty then RebuildRoster() end
    return roster
end

--- Every group unit token, players first, then pets.
---@return string[]
function Threat.GroupUnits() return Roster().units end

-- Target threat list ---------------------------------------------------------------

local list, pool = {}, {}

local function ByScaled(a, b) return a.scaled > b.scaled end

----- Fill `list` with each group member's scaled threat on `mob`, highest first.
----- Returns true when the client hid some of it.
local function Collect(mob)
    for i = #list, 1, -1 do
        pool[#pool + 1] = list[i]
        list[i] = nil
    end
    local restricted = false
    local r = Roster()
    for _, unit in ipairs(r.units) do
        local ok, isTanking, status, scaled = pcall(UnitDetailedThreatSituation, unit, mob)
        if ok then
            local s = API.PlainNumber(scaled)
            if s then
                local info = r.info[unit]
                local e = table.remove(pool) or {}
                e.unit, e.scaled, e.name, e.class = unit, s, info.name, info.class
                e.tanking = API.PlainBool(isTanking) == true
                e.me, e.isPet = info.me, info.isPet
                list[#list + 1] = e
            elseif API.IsSecret(scaled) or API.IsSecret(status) then
                restricted = true
            end
        end
    end
    table.sort(list, ByScaled)
    return restricted
end

--- The header status for a threat list: "holding", "next N%" (colored by how
--- close), "NOT ON YOU", "hidden" when the client hides it all, or "".
---@param entries {scaled: number, me: boolean?, tanking: boolean}[] highest threat first
---@param hasTarget boolean
---@param restricted boolean some threat values were secret
---@return string
function Threat.StatusFor(entries, hasTarget, restricted)
    if not hasTarget then return "" end
    if restricted and #entries == 0 then return "|cff" .. HEX.muted .. "hidden|r" end
    -- Am I holding it, and how close is the next person?
    local mine, nextUp
    for _, e in ipairs(entries) do
        if e.me then mine = e elseif not nextUp then nextUp = e end
    end
    if mine and mine.tanking then
        if not nextUp then return "|cff" .. HEX.good .. "holding|r" end
        local col = nextUp.scaled >= 90 and HEX.bad or (nextUp.scaled >= 70 and HEX.warn or HEX.good)
        return string.format("|cff%snext %d%%|r", col, nextUp.scaled)
    end
    if #entries > 0 then return "|cff" .. HEX.bad .. "NOT ON YOU|r" end
    return ""
end

--- Redraw the threat list and footer.
function Threat:Update()
    local rows = math.min(TF.db.threat.rows or 5, MAX_ROWS)
    local hasTarget = API.UnitExists("target") and API.UnitCanAttack("player", "target")
    local name = hasTarget and API.Safe(UnitName, "target")
    if hasTarget and API.IsSecret(name) then
        -- Hidden in combat: the text widget can show it even though we can't read it.
        f.title.tfText = nil
        if not pcall(f.title.SetFormattedText, f.title, "|cff" .. HEX.accent .. "Threat|r  %s", name) then
            f.title:SetText("|cff" .. HEX.accent .. "Threat|r")
        end
    else
        name = API.PlainString(name)
        SetText(f.title, name and ("|cff" .. HEX.accent .. "Threat|r  " .. name) or ("|cff" .. HEX.accent .. "Threat|r"))
    end

    local restricted = false
    if hasTarget then
        restricted = Collect("target")
    else
        for i = #list, 1, -1 do pool[#pool + 1] = list[i] list[i] = nil end
    end

    SetText(f.status, Threat.StatusFor(list, hasTarget, restricted))

    local shown = 0
    for i = 1, math.min(#list, rows) do
        local e = list[i]
        local r = Row(i)
        shown = i
        local cr, cg, cb = API.ClassColor(e.class)
        if e.isPet then cr, cg, cb = 0.6, 0.6, 0.6 end
        r:SetStatusBarColor(cr * 0.75, cg * 0.75, cb * 0.75)
        r:SetValue(math.min(e.scaled, 100))
        SetText(r.label, e.tanking and ("|cff" .. HEX.accent .. "[T]|r " .. e.name) or e.name)
        SetText(r.value, string.format("%d%%", e.scaled))
        if not e.me and not e.tanking and e.scaled >= 90 then
            r.value:SetTextColor(unpack(C.bad))
        else
            r.value:SetTextColor(unpack(C.text))
        end
        r:Show()
    end
    for i = shown + 1, #f.rows do f.rows[i]:Hide() end

    local y = PAD + 18 + shown * (ROW_H + 2)
    local footer = ""
    if Threat.looseCount > 0 then
        footer = "|cff" .. HEX.bad .. "Mob on " .. table.concat(Threat.victims, ", ") .. "|r"
        if Threat.healerAttacked then footer = footer .. "  |cff" .. HEX.bad .. "(healer!)|r" end
    elseif TF.inCombat and IsInGroup() then
        footer = "|cff" .. HEX.muted .. "All mobs on you|r"
    end
    SetText(f.footer, footer)
    if footer ~= "" then
        f.footer:ClearAllPoints()
        f.footer:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(y + 1))
        y = y + 15
    end
    -- Resize (and refit the mover) only when the row count or footer changed.
    if f.lastHeight ~= y then
        f.lastHeight = y
        f:SetHeight(y + PAD - 2)
        Style.FitAnchor("threat")
    end
end

-- Mobs on other group members ----------------------------------------------------

local plates = {}   -- [unit token] = true; only used by the debug log's probe

--- Enemy nameplates seen; for the debug log's probe.
function Threat.PlateCount()
    local n = 0
    for _ in pairs(plates) do n = n + 1 end
    return n
end

--- For the debug log's probe.
function Threat.FirstPlate()
    for unit in pairs(plates) do
        if API.UnitExists(unit) and API.UnitCanAttack("player", unit) then return unit end
    end
    return nil
end

local aggro = {}     -- [unit] = true while that member has a mob on them
local clearSince = {} -- [unit] = when that member last stopped having a mob on them, this fight
Threat.victims = {} -- names of members with a mob on them right now

--- Seconds a member must have been clear before a mob on them counts as another loss.
--- A caster or a mob that flips target picks someone up and drops them again every
--- second or two; that is one loss, not several.
Threat.RECOUNT = 3

--- Whether a member picking up a mob counts as a new loss for the pull.
---@param since number|nil when they last stopped having a mob on them (nil: not this fight)
---@param now number
---@return boolean
function Threat.CountsAsNewLoss(since, now)
    return since == nil or now - since >= Threat.RECOUNT
end

--- Count group members with a mob on them (threat status 2 or 3), skipping you,
--- pets and other real tanks. A member newly attacked fires LOOSE, and counts
--- toward the pull's aggroLost unless they were clear for less than
--- Threat.RECOUNT seconds (Threat.CountsAsNewLoss); a change in the count or in whether your
--- healer is attacked fires LOOSE_COUNT. Runs every TICK in combat.
function Threat.Scan()
    local healerUnit = ns.Healer and ns.Healer.unit
    local loose, onHealer = 0, false
    wipe(Threat.victims)
    if Tank.isTank and TF.inCombat and IsInGroup() then
        local now = API.Now()
        local r = Roster()
        for _, unit in ipairs(r.units) do
            local info = r.info[unit]
            if info and not info.me and not info.isPet and not info.otherTank then
                -- 2 or 3: something is attacking them.
                local status = API.PlainNumber((API.Safe(UnitThreatSituation, unit)))
                local has = status ~= nil and status >= 2
                if has then
                    loose = loose + 1
                    Threat.victims[#Threat.victims + 1] = info.name
                    if unit == healerUnit then onHealer = true end
                    if not aggro[unit] then
                        local counted = Threat.CountsAsNewLoss(clearSince[unit], now)
                        if counted and Tank.pull then
                            Tank.pull.aggroLost = Tank.pull.aggroLost + 1
                            local to = Tank.pull.aggroLostTo
                            to[info.name] = (to[info.name] or 0) + 1
                        end
                        TF:Fire("LOOSE", nil, info.name, unit == healerUnit, false, unit, counted)
                    end
                elseif aggro[unit] then
                    clearSince[unit] = now
                end
                aggro[unit] = has or nil
            end
        end
    else
        wipe(aggro)
        wipe(clearSince)
    end
    local changed = loose ~= Threat.looseCount or onHealer ~= Threat.healerAttacked
    Threat.looseCount, Threat.healerAttacked = loose, onHealer
    if changed then TF:Fire("LOOSE_COUNT", loose, onHealer) end
end

-- One tick for both: the scan in combat, the list when it's showing and
-- something changed (always in combat). Runs only in combat or while the
-- panel is up; otherwise the frame is hidden and costs nothing.
local ticker = CreateFrame("Frame")
ticker:Hide()
local elapsed, dirty = 0, true

ticker:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < TICK then return end
    elapsed = 0
    if not TF.db then return end
    if TF.inCombat then
        local ok, err = pcall(Threat.Scan)
        if not ok then TF:Error(err) end
    end
    if f:IsShown() and (dirty or TF.inCombat) then
        dirty = false
        Threat:Update()
    end
end)

local function SyncTicker()
    ticker:SetShown((TF.inCombat or f:IsShown()) and true or false)
end

--- Show or hide the panel: enabled, a tanking kit, and either unlocked or
--- tanking with a target or in combat.
function Threat:Refresh()
    local hasTarget = API.UnitExists("target") and API.UnitCanAttack("player", "target")
    local show = TF.db.threat.enabled and Tank.kit ~= nil
        and (Style.IsUnlocked() or (Tank.isTank and (hasTarget or TF.inCombat)))
    f:SetShown(show and true or false)
    if show then
        dirty = false
        Threat:Update()
    end
    SyncTicker()
end

-- Events ---------------------------------------------------------------------

TF:RegisterEvent("NAME_PLATE_UNIT_ADDED", function(_, unit) if unit then plates[unit] = true end end)
TF:RegisterEvent("NAME_PLATE_UNIT_REMOVED", function(_, unit) if unit then plates[unit] = nil end end)

for _, ev in ipairs({ "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE" }) do
    TF:RegisterEvent(ev, function() dirty = true end)
end
for _, ev in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "PLAYER_ROLES_ASSIGNED" }) do
    TF:RegisterEvent(ev, function() rosterDirty = true dirty = true end)
end
-- These fire for every nameplate too; only a group member's change touches the roster.
for _, ev in ipairs({ "UNIT_PET", "UNIT_NAME_UPDATE" }) do
    TF:RegisterEvent(ev, function(_, unit)
        if Threat.IsGroupUnit(unit) then rosterDirty = true dirty = true end
    end)
end
TF:RegisterEvent("PLAYER_TARGET_CHANGED", function() Threat:Refresh() end)
TF:RegisterEvent("GROUP_ROSTER_UPDATE", function() Threat:Refresh() end)
TF:On("TANK_CHANGED", function() Threat:Refresh() end)
TF:On("KIT_CHANGED", function() Threat:Refresh() end)
TF:On("UNLOCKED", function() Threat:Refresh() end)
TF:On("LOADED", function() f:SetScale(TF.db.scale or 1) end)
TF:On("COMBAT", function(inCombat)
    if not inCombat then
        wipe(aggro)
        wipe(clearSince)
        wipe(Threat.victims)
        Threat.looseCount, Threat.healerAttacked = 0, false
    end
    Threat:Refresh()
end)
