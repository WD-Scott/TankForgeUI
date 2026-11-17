-- Core/Log.lua
-- Debug log: /tf log on, play, then /reload or log out. The game writes the log to
--   WTF\Account\<ACCOUNT>\SavedVariables\TankForgeUI.lua
-- (addons can't write files themselves; saved variables are written on reload,
-- logout and quit). Attach that file to a bug report. Lines are kept across
-- logins and reloads (each session starts with a "==== session" header) until
-- /tf log clear, trimmed to the newest Log.MAX_LINES.
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

Log.MAX_LINES = 5000        -- trimmed to half when exceeded
local PROBE_PULLS = 3       -- probe the first few pulls of each session
local SAMPLE_EVERY = 3      -- seconds between status samples in combat

local store                 -- TankForgeUILog, account-wide
local sessionStart = 0
local probesThisSession = 0

--- True while the debug log is recording.
---@return boolean
function Log:IsOn()
    return store ~= nil and store.enabled == true
end

--- A value as text for the log: numbers to 6 digits, strings quoted and cut
--- to 48 characters, other types by name, and "secret" for secret values.
---@param v any
---@return string
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

-- Append a line; past Log.MAX_LINES, keep the newest half behind a marker line.
local function Add(line)
    local lines = store.lines
    lines[#lines + 1] = line
    if #lines > Log.MAX_LINES then
        -- Drop the oldest half in one go, so trimming stays cheap on average.
        local keep = math.floor(Log.MAX_LINES / 2)
        local from = #lines - keep
        lines[1] = "... older lines dropped ..."
        for i = 1, keep do lines[i + 1] = lines[from + i] end
        for i = #lines, keep + 2, -1 do lines[i] = nil end
    end
end

--- Write a line to the debug log, when it's on: TF:Log("CAST", "%s (%d)", name, id).
--- A format error writes the format string instead of raising.
---@param category string short tag, padded to 6 characters
---@param fmt string string.format pattern
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

--- Log the zone, group and healer, and each party member's name, class and role.
---@param why string
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

--- Write which game values are readable (plain) or secret right now.
---@param context string why the probe ran
function Log:Probe(context)
    if not self:IsOn() then return end
    TF:Log("PROBE", "---- %s (in combat %s)", context, tostring(InCombatLockdown()))
    TF:Log("PROBE", "player health %s / %s, rage %s / %s, form %s, role %s",
        Call(UnitHealth, "player"), Call(UnitHealthMax, "player"), Call(UnitPower, "player", 1),
        Call(UnitPowerMax, "player", 1), Call(GetShapeshiftFormID), Call(UnitGroupRolesAssigned, "player"))
    TF:Log("PROBE", "Shield Block aura by ID %s; cooldown %s", Call(C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID, 2565),
        (function()
            local ok, info = pcall(C_Spell and C_Spell.GetSpellCooldown, 2565)
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
    -- Three ways to list buffs; which work in combat on this client varies, so
    -- each one's result (or its error message) is logged.
    local function ScanBuffs(fn)
        if type(fn) ~= "function" then return "missing" end
        local out = {}
        for i = 1, 16 do
            local ok, a = pcall(fn, "player", i, "HELPFUL")
            if not ok then
                out[#out + 1] = "error at " .. i .. ": " .. tostring(a):sub(1, 80)
                break
            end
            if API.IsSecret(a) then out[#out + 1] = "secret" break end
            if a == nil then break end
            if type(a) == "table" then
                local okRead, text = pcall(function() return D(a.name) .. " " .. D(a.spellId) end)
                out[#out + 1] = okRead and text or "unreadable"
            else
                out[#out + 1] = D(a)
            end
        end
        return #out > 0 and table.concat(out, "; ") or "none"
    end
    TF:Log("PROBE", "buffs by GetAuraDataByIndex: %s", ScanBuffs(UA and UA.GetAuraDataByIndex))
    TF:Log("PROBE", "buffs by GetBuffDataByIndex: %s", ScanBuffs(UA and UA.GetBuffDataByIndex))
    TF:Log("PROBE", "buffs by UnitBuff: %s", ScanBuffs(_G.UnitBuff))
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
        tostring(Tank and Tank:BeingHit()), tostring(primary and API.GetSpellName(primary.spell)),
        primary and Tank:Remaining(primary) or 0, tostring(primary and Tank:IsReady(primary)),
        Threat and Threat.looseCount or 0, tostring(Threat and Threat.healerAttacked),
        tostring(Healer and Healer.frame.tag and Healer.frame.tag:GetText()), Healer and Healer.frame:GetAlpha() or 0,
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

TF:On("LOOSE", function(mob, victim, onHealer, wasOnMe, _, counted)
    TF:Log("LOOSE", "%s -> %s (healer %s, was on me %s, counted %s)", tostring(mob or "a mob"), tostring(victim),
        tostring(onHealer), tostring(wasOnMe), tostring(counted))
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

-- The game blocked a protected call because TankForgeUI's code was in the
-- call chain (taint). Record which call, and say so once per session.
--
-- One taint can block the same calls every second of a fight (StanceButton1
-- through 10, over and over), which once filled most of the log. So each kind
-- of call (numbers in frame names ignored) is written the first time it's seen
-- in a fight, and repeats are counted and written as one line when the fight
-- ends (or at logout).
local blockWarned = false
local blockRepeats = {}     -- kind -> repeats not yet written
local blockOrder = {}       -- kinds in the order first seen

local function FlushBlocks()
    for _, kind in ipairs(blockOrder) do
        local n = blockRepeats[kind]
        if n and n > 0 then TF:Log("BLOCK", "%s: repeated %d more times", kind, n) end
    end
    wipe(blockRepeats)
    wipe(blockOrder)
end

local function OnBlocked(event, addon, func)
    if addon ~= addonName then return end
    local kind = tostring(event) .. ": " .. tostring(func):gsub("%d+", "N")
    if blockRepeats[kind] then
        blockRepeats[kind] = blockRepeats[kind] + 1
    else
        blockRepeats[kind] = 0
        blockOrder[#blockOrder + 1] = kind
        TF:Log("BLOCK", "%s: %s", tostring(event), tostring(func))
    end
    if blockWarned then return end
    blockWarned = true
    TF:Print("the game blocked " .. tostring(func) .. " from TankForgeUI. To track it down: |cff" .. TF.COLOR
        .. "/tf log on|r, /reload, do the same thing again, then attach the log file to a bug report. |cff"
        .. TF.COLOR .. "/tf taint|r shows what's affected.")
end
TF:RegisterEvent("ADDON_ACTION_BLOCKED", OnBlocked)
TF:RegisterEvent("ADDON_ACTION_FORBIDDEN", OnBlocked)
-- A fight's repeats are written when it ends; ones from outside a fight when the next starts.
TF:On("COMBAT", FlushBlocks)
TF:RegisterEvent("PLAYER_LOGOUT", FlushBlocks)

-- Setup ------------------------------------------------------------------------

TF:On("LOGIN", function()
    if type(TankForgeUILog) ~= "table" then TankForgeUILog = {} end
    store = TankForgeUILog
    -- Keep earlier sessions: a /reload after a run must not lose the run's lines.
    -- Add() trims to Log.MAX_LINES; /tf log clear empties it.
    if type(store.lines) ~= "table" then store.lines = {} end
    sessionStart = API.Now()
    if store.enabled then
        TF:Print(string.format("debug log is recording (%d lines). |cff%s/tf log off|r to stop.",
            #store.lines, TF.COLOR))
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
        copyBox = Style.Panel(UIParent, "TankForgeUILogBox")
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

--- Turn recording on (writes a fresh session header) or off. Needs PLAYER_LOGIN first.
---@param on boolean
function Log:SetEnabled(on)
    if not store then return end
    store.enabled = on and true or false
    if on then
        sessionStart = API.Now()
        probesThisSession = 0
        Header()
        TF:Print("debug log |cff40ff40on|r. Play as usual. It's saved when you /reload or log out, to "
            .. "WTF\\Account\\<account>\\SavedVariables\\TankForgeUI.lua. Read it in game with |cff"
            .. TF.COLOR .. "/tf log show|r, or attach that file to a bug report.")
    else
        TF:Log("SESS", "log turned off")
        TF:Print("debug log |cffff4040off|r. " .. #store.lines .. " lines kept until |cff" .. TF.COLOR
            .. "/tf log clear|r.")
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
end, "on|off|mark|probe|show|clear - debug log to send for a bug report", { group = "Debugging", details = {
    "on - start recording (written to disk on /reload or logout; kept across reloads)",
    "off - stop recording; what's there is kept until /tf log clear",
    "mark <note> - add a note to the log, e.g. right before something goes wrong",
    "probe - write which game values are readable right now",
    "show [lines] - open the last 400 (or [lines]) lines in a box you can copy",
    "clear - empty the log",
    "(no argument) - say whether it's on and how many lines it has",
} })

-- Taint check ------------------------------------------------------------------
--
-- Blizzard frames whose fields have been written by addon code. When Blizzard's
-- own code later reads one of those in combat, its protected calls are blocked
-- and the game blames whichever addon wrote it. Run out of combat; anything
-- listed under TankForgeUI is ours to fix. /console taintLog 2 has the full story.

local TAINT_FRAMES = {
    "StanceBar", "StanceBarFrame", "MainActionBar", "MainMenuBar", "MultiBarBottomLeft",
    "MultiBarBottomRight", "ObjectiveTrackerFrame", "EditModeManagerFrame",
    "PlayerSpellsFrame", "SpellBookFrame", "PlayerFrame", "PartyFrame", "CompactPartyFrame",
}
for i = 1, 10 do TAINT_FRAMES[#TAINT_FRAMES + 1] = "StanceButton" .. i end
for i = 1, 12 do TAINT_FRAMES[#TAINT_FRAMES + 1] = "ActionButton" .. i end

local function TaintScan()
    if type(issecurevariable) ~= "function" then
        TF:Print("this client can't check taint from inside the game. /console taintLog 2 makes the game "
            .. "write Logs\\taint.log instead.")
        return
    end
    local frames, keys, ours = 0, 0, 0
    for _, name in ipairs(TAINT_FRAMES) do
        local t = _G[name]
        if type(t) == "table" then
            frames = frames + 1
            local bad = {}
            local okG, secureG, byG = pcall(issecurevariable, name)
            if okG and not secureG then bad[#bad + 1] = "(the global itself, " .. tostring(byG) .. ")" end
            for k in pairs(t) do
                local ok, secure, by = pcall(issecurevariable, t, k)
                if ok and not secure then
                    keys = keys + 1
                    if by == addonName then ours = ours + 1 end
                    bad[#bad + 1] = tostring(k) .. " (" .. tostring(by) .. ")"
                end
            end
            if #bad > 0 then
                table.sort(bad)
                local line = table.concat(bad, ", ", 1, math.min(#bad, 12))
                if #bad > 12 then line = line .. string.format(", +%d more", #bad - 12) end
                TF:Print(name .. ": " .. line)
                TF:Log("TAINT", "%s: %s", name, table.concat(bad, ", "))
            end
        end
    end
    local summary = string.format("taint check: %d frames, %d tainted fields, %d by %s%s.",
        frames, keys, ours, addonName, InCombatLockdown() and " (in combat)" or "")
    TF:Print(summary)
    TF:Log("TAINT", "%s", summary)
end

-- How much CPU TankForgeUI uses, from the client's own add-on profiler. Peak is
-- one worst frame (usually login or /reload); the averages are what matter.
TF:AddCommand("perf", function()
    local m = API.AddOnMetrics(addonName)
    if not m then
        TF:Print("this client has no add-on profiler.")
        return
    end
    local function ms(key) return m[key] and string.format("%.3fms", m[key]) or "?" end
    local function n(key) return m[key] and tostring(m[key]) or "?" end
    TF:Print(string.format("CPU per frame: recent %s, session %s, encounter %s, peak %s.",
        ms("RecentAverageTime"), ms("SessionAverageTime"), ms("EncounterAverageTime"), ms("PeakTime")))
    TF:Print(string.format("Frames over 5ms: %s, over 10ms: %s, over 50ms: %s.",
        n("CountTimeOver5Ms"), n("CountTimeOver10Ms"), n("CountTimeOver50Ms")))
end, "- CPU use from the game's add-on profiler (averages per frame, and the worst frame)", { group = "Debugging" })

TF:AddCommand("taint", TaintScan, "- list Blizzard frame fields tainted by add-ons (should be none by TankForgeUI)",
    { group = "Debugging" })
