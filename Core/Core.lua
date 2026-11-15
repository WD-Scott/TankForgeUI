-- Core/Core.lua
-- Namespace, settings, events, internal messages and slash commands.
local addonName, ns = ...

local TF = {}
ns.TF = TF
_G.TankforgeUI = TF -- internal global name, kept as-is

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

    scale = 1,
    tankMode = "auto",        -- "auto": role or stance decides; "always"

    -- alpha: opacity in combat; oocAlpha: opacity out of combat.
    hud = { enabled = true, alpha = 1, oocAlpha = 0.6 },
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
    },
    report = { enabled = true, autoShow = true, openWorld = false, hideAfter = 25 },

    positions = {},
    history = {},
    healerName = nil,
    welcomed = false,
}

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

-- Events ---------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local handlers = {}

-- Register fn for a game event. Unknown events throw on this client, so the
-- registration is guarded and reported as false.
function TF:RegisterEvent(event, fn)
    if not handlers[event] then
        local ok = pcall(eventFrame.RegisterEvent, eventFrame, event)
        if not ok then return false end
        handlers[event] = {}
    end
    table.insert(handlers[event], fn)
    return true
end

-- Unit events registered once for a fixed list of units.
local unitFrames = {}
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
        f:SetScript("OnEvent", function(self, ...)
            for _, h in ipairs(self.fns) do
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

-- Internal messages between modules.
local listeners = {}
function TF:On(message, fn)
    listeners[message] = listeners[message] or {}
    table.insert(listeners[message], fn)
end

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

function TF:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff" .. TF.COLOR .. "TankForgeUI:|r " .. tostring(msg))
end

local errorsShown = {}
function TF:Error(err)
    err = tostring(err)
    if errorsShown[err] then return end
    errorsShown[err] = true
    TF:Print("|cffff6060error:|r " .. err)
    if TF.Log then TF:Log("ERROR", "%s", err) end
end

-- Combat state ---------------------------------------------------------------

TF.inCombat = InCombatLockdown and InCombatLockdown() or false

-- Run fn now if out of combat, otherwise once combat ends.
local afterCombat = {}
function TF:AfterCombat(fn)
    if not InCombatLockdown() then
        fn()
    else
        table.insert(afterCombat, fn)
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
    if type(TankforgeUIDB) ~= "table" then TankforgeUIDB = {} end
    Merge(TankforgeUIDB, ns.defaults)
    TF.db = TankforgeUIDB
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

-- name, handler(args), help line
function TF:AddCommand(name, fn, help)
    TF.commands[name] = { fn = fn, help = help, order = #TF.commands + 1 }
    table.insert(TF.commands, name)
end

function TF:PrintHelp()
    TF:Print("version " .. TF.version .. ". Commands:")
    for _, name in ipairs(TF.commands) do
        local c = TF.commands[name]
        if c.help then
            DEFAULT_CHAT_FRAME:AddMessage("  |cff" .. TF.COLOR .. "/tf " .. name .. "|r " .. c.help)
        end
    end
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
        TF:PrintHelp()
        return
    end
    c.fn(rest or "")
end

TF:AddCommand("help", function() TF:PrintHelp() end, "- this list")
