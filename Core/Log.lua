-- Core/Log.lua
-- Debug log: /tf log on, play, then /reload or log out. The game writes the log to
--   WTF\Account\<ACCOUNT>\SavedVariables\TankForgeUI.lua
-- (addons can't write files themselves; saved variables are written on reload,
-- logout and quit). Send that file to get the run looked at.
--
-- What it records: a session header (version, client, class, spells, settings,
-- group), tank/healer changes, casts, hits, pulls, loose mobs, alerts, deaths
-- and errors; a probe of which game values are readable or secret, a few
-- seconds into the first pulls of each session; and a status sample every
-- few seconds in combat. Party members' names are included.
--
-- Costs nothing while off: every call returns at the first line.
local addonName, ns = ...
local TF = ns.TF
local API = ns.API

local Log = {}
ns.Log = Log

local MAX_LINES = 20000
local PROBE_PULLS = 3       -- probe the first few pulls of each session
local SAMPLE_EVERY = 3      -- seconds between status samples in combat

local store                 -- TankforgeUILog, account-wide
local sessionStart = 0
local probesThisSession = 0

function Log:IsOn()
    return store ~= nil and store.enabled == true
end

-- A value as text: its type and value, or "secret".
local function D(v)
    if API.IsSecret(v) then return "secret" end
    local t = type(v)
    if t == "nil" then return "nil" end
    if t == "number" then return string.format("%.6g", v) end
    if t == "string" then return '"' .. v:sub(1, 48) .. '"' end
    if t == "boolean" then return tostring(v) end
    return t
end
Log.D = D

local function Pack(...) return { n = select("#", ...), ... } end

-- Every return value of a call, described.
local function Call(fn, ...)
    if type(fn) ~= "function" then return "missing" end
    local res = Pack(pcall(fn, ...))
    if not res[1] then return "error: " .. tostring(res[2]):sub(1, 80) end
    local out = {}
    for i = 2, res.n do out[#out + 1] = D(res[i]) end
    if #out == 0 then return "(nothing)" end
    return table.concat(out, ", ")
end

local function Add(line)
    local lines = store.lines
    lines[#lines + 1] = line
    if #lines > MAX_LINES then
        -- Drop the oldest half in one go, so trimming stays cheap on average.
        local keep = math.floor(MAX_LINES / 2)
        local from = #lines - keep
        for i = 1, keep do lines[i] = lines[from + i] end
        for i = #lines, keep + 1, -1 do lines[i] = nil end
        lines[1] = "... older lines dropped ..."
    end
end

-- TF:Log("CAST", "%s (%d)", name, id)
function TF:Log(category, fmt, ...)
    if not (store and store.enabled) then return end
    local ok, text = pcall(string.format, fmt or "", ...)
    if not ok then text = tostring(fmt) end
    Add(string.format("[%8.2f] %-6s %s", API.Now() - sessionStart, category, text))
end

-- Session header -----------------------------------------------------------------

local function Header()
    local version, build, _, toc = GetBuildInfo()
    TF:Log("SESS", "==== session %s, TankForgeUI %s, client %s (%s) interface %s",
        date("%Y-%m-%d %H:%M:%S"), TF.version, tostring(version), tostring(build), tostring(toc))
    local Tank = ns.Tank
    TF:Log("SESS", "player %s, class %s, kit %s, tanking %s (%s)", tostring(API.UnitName("player")),
        tostring(Tank and Tank.class), tostring(Tank and Tank.kit ~= nil), tostring(Tank and Tank.isTank),
        tostring(Tank and Tank:Reason()))
    if Tank then
        for _, e in ipairs(Tank.entries) do
            TF:Log("SESS", "  spell %s id %d known %s cd %s", tostring(API.GetSpellName(e.spell)), e.spell,
                tostring(e.known), tostring(e.def.cd))
        end
    end
    local db = TF.db
    TF:Log("SESS", "settings: hidePlayer %s, tooltips %s, barArt %s, tankMode %s, scale %s", tostring(db.hidePlayerFrame),
        tostring(db.hideActionTooltips), tostring(db.hideBarArt), tostring(db.tankMode), tostring(db.scale))
    for _, key in ipairs({ "hud", "threat", "healer", "party", "alerts", "report" }) do
        local parts = {}
        for k, v in pairs(db[key]) do parts[#parts + 1] = k .. "=" .. tostring(v) end
        table.sort(parts)
        TF:Log("SESS", "  %s: %s", key, table.concat(parts, " "))
    end
    TF:Log("SESS", "functions: issecretvalue %s, SetAlphaFromBoolean %s, SetCooldownFromDurationObject %s, "
        .. "GetSpellCooldownDuration %s, UnitHealthPercent %s, UnitPowerPercent %s, CurveConstants %s, "
        .. "EditMode ImportLayout %s",
        tostring(type(issecretvalue) == "function"), tostring(UIParent.SetAlphaFromBoolean ~= nil),
        (function()
            local ok, cd = pcall(CreateFrame, "Cooldown", nil, UIParent, "CooldownFrameTemplate")
            return tostring(ok and cd and cd.SetCooldownFromDurationObject ~= nil or false)
        end)(),
        tostring(C_Spell and C_Spell.GetSpellCooldownDuration ~= nil), tostring(UnitHealthPercent ~= nil),
        tostring(UnitPowerPercent ~= nil), tostring(CurveConstants ~= nil),
        tostring(EditModeManagerFrame and EditModeManagerFrame.ImportLayout ~= nil))
    Log:Group("session start")
end

function Log:Group(why)
    if not self:IsOn() then return end
    local _, instanceType = IsInInstance()
    TF:Log("GROUP", "%s: zone %s (%s), in group %s, raid %s, healer %s", why,
        tostring(API.PlainString(GetRealZoneText and GetRealZoneText())), tostring(instanceType),
        tostring(IsInGroup()), tostring(IsInRaid()), ns.Healer and ns.Healer:Describe() or "?")
    if IsInGroup() and not IsInRaid() then
        for i = 1, 4 do
            local u = "party" .. i
            if API.UnitExists(u) then
                TF:Log("GROUP", "  %s %s %s role %s", u, tostring(API.UnitName(u)), tostring(API.UnitClass(u)),
                    tostring(API.UnitRole(u)))
            end
        end
    end
end

-- Probe: which values can an addon read, here and now? ---------------------------

function Log:Probe(context)
    if not self:IsOn() then return end
    TF:Log("PROBE", "---- %s (in combat %s)", context, tostring(InCombatLockdown()))
    TF:Log("PROBE", "player health %s / %s, rage %s / %s, form %s, role %s",
        Call(UnitHealth, "player"), Call(UnitHealthMax, "player"), Call(UnitPower, "player", 1),
        Call(UnitPowerMax, "player", 1), Call(GetShapeshiftFormID), Call(UnitGroupRolesAssigned, "player"))
    TF:Log("PROBE", "Shield Block aura by ID %s; cooldown %s", Call(C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID, 2565),
        (function()
            local ok, info = pcall(C_Spell.GetSpellCooldown, 2565)
            if not ok then return "error" end
            if API.IsSecret(info) then return "secret table" end
            if type(info) ~= "table" then return D(info) end
            return "start " .. D(info.startTime) .. ", duration " .. D(info.duration)
        end)())
    if API.UnitExists("target") then
        TF:Log("PROBE", "target name %s, guid %s, attackable %s, my threat on it %s",
            Call(UnitName, "target"), Call(UnitGUID, "target"), Call(UnitCanAttack, "player", "target"),
            Call(UnitDetailedThreatSituation, "player", "target"))
        TF:Log("PROBE", "target's target %s, is me %s", Call(UnitName, "targettarget"),
            Call(UnitIsUnit, "targettarget", "player"))
    end
    -- The Shield Block buff by name, and the buffs that are up, to find its real ID.
    local UA = C_UnitAuras
    TF:Log("PROBE", "Shield Block aura by name %s", Call(UA and UA.GetAuraDataBySpellName, "player",
        API.GetSpellName(2565) or "Shield Block", "HELPFUL"))
    local buffs = {}
    for i = 1, 16 do
        local ok, a = pcall(UA.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok then buffs[#buffs + 1] = "error" break end
        if API.IsSecret(a) then buffs[#buffs + 1] = "secret" break end
        if a == nil then break end
        buffs[#buffs + 1] = D(a.name) .. " " .. D(a.spellId)
    end
    TF:Log("PROBE", "buffs: %s", #buffs > 0 and table.concat(buffs, "; ") or "none")
    local getCVar = (C_CVar and C_CVar.GetCVar) or GetCVar
    TF:Log("PROBE", "nameplateShowEnemies %s, nameplates seen %d, my threat status %s",
        Call(getCVar, "nameplateShowEnemies"), ns.Threat and ns.Threat.PlateCount and ns.Threat.PlateCount() or -1,
        Call(UnitThreatSituation, "player"))
    local plate = ns.Threat and ns.Threat.FirstPlate and ns.Threat.FirstPlate()
    if plate then
        TF:Log("PROBE", "%s name %s, guid %s, in combat %s, my threat %s, its target %s (is me %s)", plate,
            Call(UnitName, plate), Call(UnitGUID, plate), Call(UnitAffectingCombat, plate),
            Call(UnitDetailedThreatSituation, "player", plate), Call(UnitName, plate .. "target"),
            Call(UnitIsUnit, plate .. "target", "player"))
    else
        TF:Log("PROBE", "no enemy nameplates visible")
    end
    if IsInGroup() and not IsInRaid() then
        for i = 1, 4 do
            local u = "party" .. i
            if API.UnitExists(u) then
                TF:Log("PROBE", "%s health %s, mana %s, range %s, threat status %s, casting %s, leader %s", u,
                    Call(UnitHealth, u), Call(UnitPower, u, 0), Call(UnitInRange, u), Call(UnitThreatSituation, u),
                    Call(UnitCastingInfo, u), Call(UnitIsGroupLeader, u))
            end
        end
    end
end

-- Samples in combat ----------------------------------------------------------------

local sampleTimer = 0
local sampler = CreateFrame("Frame")
sampler:Hide()
sampler:SetScript("OnUpdate", function(_, dt)
    sampleTimer = sampleTimer + dt
    if sampleTimer < SAMPLE_EVERY then return end
    sampleTimer = 0
    local Tank, Threat, Healer = ns.Tank, ns.Threat, ns.Healer
    local p = Tank and Tank.pull
    local primary = Tank and Tank.primary
    TF:Log("SAMPLE", "being hit %s, %s up %.1fs ready %s, loose %d, healer attacked %s, healer tag %s, "
        .. "alpha healer %.2f party %.2f, pull hits %s covered %.1f/%.1fs",
        tostring(Tank:BeingHit()), tostring(primary and API.GetSpellName(primary.spell)),
        primary and Tank:Remaining(primary) or 0, tostring(primary and Tank:IsReady(primary)),
        Threat and Threat.looseCount or 0, tostring(Threat and Threat.healerAttacked),
        tostring(Healer and Healer.frame.tag:GetText()), Healer and Healer.frame:GetAlpha() or 0,
        ns.Party and ns.Party.frame:GetAlpha() or 0,
        tostring(p and p.hits), p and p.covered or 0, p and p.underAttack or 0)
end)

-- Hooks ----------------------------------------------------------------------------

TF:On("COMBAT", function(inCombat)
    if not Log:IsOn() then sampler:Hide() return end
    TF:Log("COMBAT", inCombat and "entered combat" or "left combat")
    sampler:SetShown(inCombat)
    sampleTimer = 0
    -- Only fights that last 3s count toward the probe budget.
    if inCombat and probesThisSession < PROBE_PULLS then
        C_Timer.After(3, function()
            if InCombatLockdown() and probesThisSession < PROBE_PULLS then
                probesThisSession = probesThisSession + 1
                Log:Probe("3s into combat, probe " .. probesThisSession .. " of " .. PROBE_PULLS)
            end
        end)
    end
end)

TF:On("TANK_CHANGED", function(on)
    TF:Log("TANK", "tanking %s (%s, form %s, role %s)", tostring(on), tostring(ns.Tank:Reason()),
        tostring(API.GetShapeshiftFormID()), tostring(API.UnitRole("player")))
end)

TF:On("KIT_CHANGED", function()
    TF:Log("TANK", "spells rebuilt: %d tracked, %d icons", #ns.Tank.entries, #ns.Tank.icons)
end)

TF:On("CAST", function(entry)
    TF:Log("CAST", "%s (%d)", tostring(API.GetSpellName(entry.spell)), entry.spell)
end)

TF:On("HIT", function(kind, physical, secretKind)
    local Tank = ns.Tank
    TF:Log("HIT", "%s physical %s%s, mitigation up %s", kind, tostring(physical), secretKind and " (kind secret)" or "",
        tostring(Tank.primary and Tank:IsActive(Tank.primary)))
end)

TF:On("LOOSE", function(mob, victim, onHealer, wasOnMe)
    TF:Log("LOOSE", "%s -> %s (healer %s, was on me %s)", tostring(mob or "a mob"), tostring(victim), tostring(onHealer),
        tostring(wasOnMe))
end)

TF:On("PULL_START", function(p)
    TF:Log("PULL", "start in %s (instance %s)", tostring(p.zone), tostring(p.instance))
end)

TF:On("PULL_END", function(p)
    TF:Log("PULL", "end after %.1fs: hits %d (relevant %d, unmitigated %d), under attack %.1fs, covered %.1fs, "
        .. "longest gap %.1fs, taunts %d, interrupts %d, lost %d, healer attacked %.1fs, deaths %d",
        p.duration, p.hits, p.hitsRelevant, p.hitsUnmitigated, p.underAttack, p.covered, p.longestGap,
        p.taunts, p.interrupts, p.aggroLost, p.healerAttacked, #p.deaths)
end)

TF:On("DEATH", function(ready)
    TF:Log("DEATH", "died; still ready: %s", #ready > 0 and table.concat(ready, ", ") or "nothing")
end)

TF:On("HEALER_CHANGED", function(unit)
    TF:Log("HEALER", "healer is now %s", ns.Healer and ns.Healer:Describe() or tostring(unit))
end)

TF:RegisterEvent("GROUP_ROSTER_UPDATE", function()
    if not Log:IsOn() then return end
    C_Timer.After(0.5, function() Log:Group("group changed") end)
end)

TF:On("ENTERING_WORLD", function()
    if Log:IsOn() then Log:Group("entered world") end
end)

-- Setup ------------------------------------------------------------------------

TF:On("LOGIN", function()
    if type(TankforgeUILog) ~= "table" then TankforgeUILog = {} end
    store = TankforgeUILog
    store.lines = store.lines or {}
    sessionStart = API.Now()
    if store.enabled then
        -- After the other modules have built their state.
        C_Timer.After(1, Header)
    end
end)

local copyBox
local function ShowLines(count)
    local lines = store.lines
    local first = math.max(1, #lines - count + 1)
    local text = table.concat(lines, "\n", first, #lines)
    if not copyBox then
        local Style = ns.Style
        copyBox = Style.Panel(UIParent, "TankforgeUILogBox")
        copyBox:SetSize(640, 400)
        copyBox:SetPoint("CENTER")
        copyBox:SetFrameStrata("DIALOG")
        copyBox:EnableMouse(true)
        local scroll = CreateFrame("ScrollFrame", nil, copyBox, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 12, -12)
        scroll:SetPoint("BOTTOMRIGHT", -32, 44)
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetFontObject(ChatFontNormal)
        edit:SetWidth(590)
        edit:SetAutoFocus(false)
        edit:SetScript("OnEscapePressed", function() copyBox:Hide() end)
        scroll:SetScrollChild(edit)
        copyBox.edit = edit
        local close = CreateFrame("Button", nil, copyBox, "UIPanelButtonTemplate")
        close:SetSize(100, 24)
        close:SetPoint("BOTTOM", 0, 12)
        close:SetText("Close")
        close:SetScript("OnClick", function() copyBox:Hide() end)
    end
    copyBox.edit:SetText(text)
    copyBox:Show()
    copyBox.edit:SetFocus()
    copyBox.edit:HighlightText()
end

function Log:SetEnabled(on)
    if not store then return end
    store.enabled = on and true or false
    if on then
        sessionStart = API.Now()
        probesThisSession = 0
        Header()
        TF:Print("debug log |cff40ff40on|r. Play as usual, then /reload or log out to write it to "
            .. "WTF\\Account\\<account>\\SavedVariables\\TankForgeUI.lua and send me that file.")
    else
        TF:Log("SESS", "log turned off")
        TF:Print("debug log |cffff4040off|r. " .. #store.lines .. " lines kept; /tf log clear to empty it.")
    end
    sampler:SetShown(on and InCombatLockdown() and true or false)
end

TF:AddCommand("log", function(args)
    if not store then return end
    local sub, rest = (args or ""):match("^(%S*)%s*(.-)$")
    sub = strlower(sub or "")
    if sub == "on" then
        Log:SetEnabled(true)
    elseif sub == "off" then
        Log:SetEnabled(false)
    elseif sub == "clear" then
        wipe(store.lines)
        TF:Print("debug log cleared.")
        if store.enabled then Header() end
    elseif sub == "mark" then
        TF:Log("MARK", "%s", rest ~= "" and rest or "(mark)")
        TF:Print("marked" .. (store.enabled and "." or ", but the log is off: /tf log on"))
    elseif sub == "probe" then
        if not store.enabled then TF:Print("the log is off: /tf log on") return end
        Log:Probe("manual")
        TF:Print("probe written to the log.")
    elseif sub == "show" then
        ShowLines(tonumber(rest) or 400)
    else
        TF:Print(string.format("debug log is %s, %d lines. /tf log on | off | mark <note> | probe | show [lines] | clear",
            store.enabled and "on" or "off", #store.lines))
    end
end, "on|off|mark <note>|probe|show|clear - debug log you can send me")
