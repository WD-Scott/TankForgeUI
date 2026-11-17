-- Core/Core.lua
-- Namespace, settings, events, internal messages and slash commands.
local addonName, ns = ...

---@type TankForgeUI
local TF = {}
ns.TF = TF
_G.TankForgeUI = TF

TF.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version"))
    or (GetAddOnMetadata and GetAddOnMetadata(addonName, "Version")) or "?"

-- Settings -------------------------------------------------------------------

ns.defaults = {
    -- Hiding (formerly Quiet UI / Hide Player Frame / LH HideMe)
    hidePlayerFrame = true,
    hideActionTooltips = true,
    shiftShowsTooltips = false,
    hideBarArt = true,
    hideObjectives = "always", -- quest tracker: "never", "always", "instance", "combat"
    keepClear = true,         -- open tooltips and bags above the action bars

    scale = 1,
    tankMode = "auto",        -- "auto": role or stance decides; "always"

    -- alpha: opacity in combat; oocAlpha: opacity out of combat. showIdle: stay
    -- up, compact, when not tanking (so the stance buttons stay reachable).
    hud = { enabled = true, alpha = 1, oocAlpha = 0.6, portrait = true, showIdle = true },
    threat = { enabled = true, rows = 5 },
    healer = { enabled = true, alpha = 1, oocAlpha = 1, dimOutOfRange = true },
    party = { enabled = true, alpha = 1, oocAlpha = 1, hideHealer = true, dimOutOfRange = true },
    alerts = {
        enabled = true,
        sound = true,
        mitigationLapse = true,   -- being hit with Shield Block down and ready
        lostAggro = true,         -- a mob you were tanking went to someone else
        healerAttacked = true,    -- a mob is hitting your healer
        death = true,             -- what was still available when you died
        defensiveReady = false,   -- a major defensive came back mid-pull
        lapseSeconds = 3,
        lapseWhere = "group",     -- "always", "group" (groups and dungeons) or "instance"
    },
    -- Minimap button that pops out your profession spells. angle: degrees around the minimap.
    professions = { enabled = true, angle = 225 },
    -- Your stance / form buttons in a flyout on the HUD, in place of Blizzard's
    -- stance bar. open: the flyout is out (the HUD's tab flips it).
    stances = { enabled = true, open = true },
    -- Quest, gossip, vendor, trainer, flight and bank windows open at the "NPC dialogs" mover.
    npcDialogs = { enabled = true },
    -- Need / Greed / Pass windows wait for combat to end, unless a roll has revealAt seconds left.
    loot = { delay = true, revealAt = 10 },
    report = { enabled = true, autoShow = true, openWorld = false, hideAfter = 25, charts = true },
    -- Options window: which collapsible sections are folded away. Heavy ones
    -- start collapsed; sections absent from the table read as expanded.
    options = { collapsed = { Hide = true, Alerts = true, Frames = true } },
    -- Whole dungeon / raid runs: recorded only when enabled. keep: runs saved.
    runs = { enabled = false, toast = true, keep = 25 },

    positions = {},
    history = {},
    runHistory = {},          -- finished runs, newest first (Modules/Runs.lua)
    currentRun = nil,         -- the run in progress, kept across /reload
    healerName = nil,
    welcomed = false,
}

--- Fill dst with every key of src that dst lacks, recursing into tables. Saved
--- values are kept; a saved non-table where the default is a table is replaced.
---@param dst table saved settings, changed in place
---@param src table defaults
local function Merge(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            Merge(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end
TF.MergeDefaults = Merge

-- Events ---------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local handlers = {}

--- Register fn for a game event. Unknown events throw on this client, so the
--- registration is guarded and reported as false. Handler errors go to TF:Error.
---@param event string
---@param fn fun(event: string, ...)
---@return boolean registered
function TF:RegisterEvent(event, fn)
    if not handlers[event] then
        local ok = pcall(eventFrame.RegisterEvent, eventFrame, event)
        if not ok then return false end
        handlers[event] = {}
    end
    table.insert(handlers[event], fn)
    return true
end

local unitFrames = {}
--- Register fn for a unit event, filtered to `units` (one frame per event and unit list).
---@param event string
---@param units string[] e.g. { "player" }
---@param fn fun(event: string, unit: string, ...)
---@return boolean registered
function TF:RegisterUnitEvent(event, units, fn)
    local key = event .. ":" .. table.concat(units, ",")
    local f = unitFrames[key]
    if not f then
        f = CreateFrame("Frame")
        f.fns = {}
        local ok
        if f.RegisterUnitEvent then
            ok = pcall(f.RegisterUnitEvent, f, event, unpack(units))
        else
            ok = pcall(f.RegisterEvent, f, event)
        end
        if not ok then return false end
        f:SetScript("OnEvent", function(frame, ...)
            for _, h in ipairs(frame.fns) do
                local ok2, err = pcall(h, ...)
                if not ok2 then TF:Error(err) end
            end
        end)
        unitFrames[key] = f
    end
    table.insert(f.fns, fn)
    return true
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for _, fn in ipairs(list) do
        local ok, err = pcall(fn, event, ...)
        if not ok then TF:Error(err) end
    end
end)

-- Internal messages between modules (see Core/Types.lua for each message's arguments).
local listeners = {}

--- Listen for an internal message. Listeners run in registration order.
---@param message TFMessage
---@param fn function
function TF:On(message, fn)
    listeners[message] = listeners[message] or {}
    table.insert(listeners[message], fn)
end

--- Send an internal message to its listeners. A failing listener is reported
--- through TF:Error and doesn't stop the others.
---@param message TFMessage
function TF:Fire(message, ...)
    local list = listeners[message]
    if not list then return end
    for _, fn in ipairs(list) do
        local ok, err = pcall(fn, ...)
        if not ok then TF:Error(err) end
    end
end

-- Output ---------------------------------------------------------------------

TF.COLOR = "e8a33d"

--- Print to the chat frame with the add-on's prefix.
---@param msg any
function TF:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff" .. TF.COLOR .. "TankForgeUI:|r " .. tostring(msg))
end

local errorsShown = {}
--- Report an error once per session (repeats of the same text are dropped) and log it.
---@param err any
function TF:Error(err)
    err = tostring(err)
    if errorsShown[err] then return end
    errorsShown[err] = true
    TF:Print("|cffff6060error:|r " .. err)
    if TF.Log then TF:Log("ERROR", "%s", err) end
end

-- Combat state ---------------------------------------------------------------

TF.inCombat = InCombatLockdown and InCombatLockdown() or false

local afterCombat = {}
--- Run fn now if out of combat, otherwise once combat ends (in queue order).
---@param fn fun()
function TF:AfterCombat(fn)
    if not InCombatLockdown() then
        fn()
    else
        table.insert(afterCombat, fn)
    end
end

--- Wrap fn so that any number of calls in one frame run it once, on the next
--- frame. For handlers of events that fire in bursts (SPELL_UPDATE_COOLDOWN,
--- ACTIONBAR_UPDATE_USABLE, UNIT_AURA). Arguments are dropped. Errors go to TF:Error.
---@param fn fun()
---@return fun() trigger
function TF:Coalesce(fn)
    local pending = false
    local function Run()
        pending = false
        local ok, err = pcall(fn)
        if not ok then TF:Error(err) end
    end
    return function()
        if pending then return end
        pending = true
        C_Timer.After(0, Run)
    end
end

TF:RegisterEvent("PLAYER_REGEN_DISABLED", function()
    TF.inCombat = true
    TF:Fire("COMBAT", true)
end)

TF:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    TF.inCombat = false
    local queued = afterCombat
    afterCombat = {}
    for _, fn in ipairs(queued) do
        local ok, err = pcall(fn)
        if not ok then TF:Error(err) end
    end
    TF:Fire("COMBAT", false)
end)

-- Loading --------------------------------------------------------------------

TF:RegisterEvent("ADDON_LOADED", function(_, name)
    if name ~= addonName then return end
    if type(TankForgeUIDB) ~= "table" then TankForgeUIDB = {} end
    Merge(TankForgeUIDB, ns.defaults)
    TF.db = TankForgeUIDB
    TF:Fire("LOADED")
end)

TF:RegisterEvent("PLAYER_LOGIN", function()
    TF:Fire("LOGIN")
end)

TF:RegisterEvent("PLAYER_ENTERING_WORLD", function(_, isLogin, isReload)
    TF:Fire("ENTERING_WORLD", isLogin, isReload)
end)

-- Slash commands -------------------------------------------------------------

TF.commands = {}

-- Sections of /tf help, in order. Commands without a group are listed last.
local GROUPS = { "Setup", "Frames", "Hiding", "Tanking", "Debugging" }

--- Add a /tf subcommand. Adding a name again replaces its handler.
---@param name string lower-case, typed after /tf
---@param fn fun(args: string) gets the rest of the line
---@param help string|nil "description", or "args - description"
---@param opts {group: string?, args: string?, details: string[]?, hidden: boolean?}|nil
---   details: "sub - what it does" lines for /tf help <name>
function TF:AddCommand(name, fn, help, opts)
    opts = opts or {}
    local args, desc = opts.args, help
    if not args and help then
        local a, d = help:match("^(.-)%s*%- (.*)$")
        if a then args, desc = a, d end
    end
    if not TF.commands[name] then table.insert(TF.commands, name) end
    TF.commands[name] = { fn = fn, help = desc, args = args ~= "" and args or nil, group = opts.group,
        details = opts.details, hidden = opts.hidden }
end

-- Chat reads "|" as the start of an escape code ("|c" is a color), so a
-- literal one, as in "on|off", has to be written "||".
local function Esc(text) return (text:gsub("|", "||")) end

local function CommandLine(name, c)
    local line = "  |cff" .. TF.COLOR .. "/tf " .. name .. "|r"
    if c.args then line = line .. " |cff999999" .. Esc(c.args) .. "|r" end
    if c.help and c.help ~= "" then line = line .. "  " .. Esc(c.help) end
    return line
end

--- /tf help: every command by section. /tf help <command>: that one, with details.
---@param name string|nil
function TF:PrintHelp(name)
    local out = DEFAULT_CHAT_FRAME
    name = name and strlower(strtrim(name)) or ""
    if name ~= "" then
        local c = TF.commands[name]
        if c then
            out:AddMessage(CommandLine(name, c))
            for _, d in ipairs(c.details or {}) do
                local sub, text = d:match("^(.-)%s+%- (.*)$")
                if sub == "(no argument)" then
                    out:AddMessage("      |cff" .. TF.COLOR .. "/tf " .. name .. "|r  " .. Esc(text))
                elseif sub then
                    out:AddMessage("      |cff" .. TF.COLOR .. "/tf " .. name .. " " .. Esc(sub) .. "|r  " .. Esc(text))
                else
                    out:AddMessage("      " .. Esc(d))
                end
            end
            return
        end
        TF:Print('unknown command "' .. name .. '".')
    end
    TF:Print("version " .. TF.version .. ": /tf <command>   (|cff" .. TF.COLOR
        .. "/tf help <command>|r for details; |cff" .. TF.COLOR .. "/tf|r alone opens options)")
    local seen = {}
    local function Section(title, match)
        local lines = {}
        for _, n in ipairs(TF.commands) do
            local c = TF.commands[n]
            if not c.hidden and not seen[n] and match(c) then
                seen[n] = true
                lines[#lines + 1] = CommandLine(n, c)
            end
        end
        if #lines == 0 then return end
        out:AddMessage("|cffffd100" .. title .. "|r")
        for _, l in ipairs(lines) do out:AddMessage(l) end
    end
    for _, g in ipairs(GROUPS) do Section(g, function(c) return c.group == g end) end
    Section("Other", function() return true end)
end

SLASH_TANKFORGEUI1 = "/tf"
SLASH_TANKFORGEUI2 = "/tankforge"
SlashCmdList.TANKFORGEUI = function(msg)
    msg = strtrim(msg or "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = strlower(cmd or "")
    if cmd == "" then
        if TF.OpenOptions then TF:OpenOptions() else TF:PrintHelp() end
        return
    end
    local c = TF.commands[cmd]
    if not c then
        TF:PrintHelp(cmd)
        return
    end
    local ok, err = pcall(c.fn, rest or "")
    if not ok then TF:Error(err) end
end

TF:AddCommand("help", function(args) TF:PrintHelp(args) end, "[command] - this list", { hidden = true })
