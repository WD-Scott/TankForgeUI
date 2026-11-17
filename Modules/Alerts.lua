-- Modules/Alerts.lua
-- Big text above your character for the moments that need a reaction:
--   a mob on your healer, a mob you were tanking going to someone else,
--   being hit with Shield Block down while it's ready, a major defensive
--   coming back, and what you still had when you died.
local _, ns = ...
local TF = ns.TF
local API = ns.API
local Style = ns.Style
local Tank = ns.Tank

local Alerts = {}
ns.Alerts = Alerts

local PRIORITY = { test = 9, healer = 5, death = 4, aggro = 3, lapse = 2, ready = 1 }

local f = CreateFrame("Frame", "TankForgeUIAlert", UIParent)
Alerts.frame = f
f:SetSize(520, 62)
f:SetFrameStrata("HIGH")
f:Hide()
f.backing = f:CreateTexture(nil, "BACKGROUND")
f.backing:SetTexture(Style.FLAT)
f.backing:SetVertexColor(0, 0, 0, 0.45)
f.text = Style.Text(f, 24)
f.text:SetPoint("TOP", 0, -6)
f.sub = Style.Text(f, 13)
f.sub:SetPoint("TOP", f.text, "BOTTOM", 0, -4)
f.backing:SetPoint("TOPLEFT", f.text, "TOPLEFT", -14, 6)
f.backing:SetPoint("BOTTOMRIGHT", f.sub, "BOTTOMRIGHT", 14, -6)

Style.Movable(f, "alerts", "Alerts", { "CENTER", "CENTER", 0, 170 })

local current        -- { priority, expires }
local lastShown = {} -- [key] = time

local function Cfg() return TF.db.alerts end

--- Show a big alert. Dropped when alerts are off (except kind "test"), when the
--- same key showed within opts.throttle seconds, or while a higher-priority
--- alert is still up.
---@param message string
---@param opts {sub: string?, color: number[]?, sound: string?, hold: number?, kind: string?, key: string?, throttle: number?}|nil
---   kind: test, healer, death, aggro, lapse or ready (highest priority first); hold: seconds shown (3)
function Alerts:Show(message, opts)
    opts = opts or {}
    if not Cfg().enabled and opts.kind ~= "test" then return end
    local now = API.Now()
    local key = opts.key or message
    if opts.throttle and lastShown[key] and now - lastShown[key] < opts.throttle then return end
    local prio = PRIORITY[opts.kind] or 1
    -- Don't let something minor cover something urgent that's still up.
    if current and current.expires > now and current.priority > prio then return end
    lastShown[key] = now
    TF:Log("ALERT", "%s | %s", tostring(message), tostring(opts.sub or ""))
    local hold = opts.hold or 3
    current = { priority = prio, expires = now + hold }

    local c = opts.color or Style.colors.text
    f.text:SetText(message)
    f.text:SetTextColor(c[1], c[2], c[3])
    f.sub:SetText(opts.sub or "")
    f:SetScale(TF.db.scale or 1)
    f:SetAlpha(1)
    f:Show()
    f.expires = now + hold
    if opts.sound and Cfg().sound then API.PlaySound(opts.sound) end
end

f:SetScript("OnUpdate", function(self)
    if Style.IsUnlocked() then return end
    local left = (self.expires or 0) - API.Now()
    if left <= 0 then
        self:Hide()
    elseif left < 0.5 then
        self:SetAlpha(left / 0.5)
    end
end)

-- Handlers -------------------------------------------------------------------

local C = Style.colors

----- "Taunt is ready" or "Taunt in 8s" for your single-target taunt, nil without one.
local function TauntState()
    for _, e in ipairs(Tank.icons) do
        if e.def.kind == "taunt" then
            local name = API.GetSpellName(e.spell) or "Taunt"
            if Tank:IsReady(e) then return name .. " is ready" end
            return string.format("%s in %.0fs", name, Tank:CooldownLeft(e))
        end
    end
    return nil
end

-- A group member picked up a mob. Mob names are hidden in combat on Forever,
-- so the alert names who has it. `mob` is nil unless a future client says.
TF:On("LOOSE", function(mob, victim, onHealer, _, key)
    if not Tank.isTank then return end
    if onHealer and Cfg().healerAttacked then
        Alerts:Show(mob and string.format("%s is on your healer!", mob) or "A mob is on your healer!",
            { sub = TauntState(), color = C.bad, sound = "warning", kind = "healer", key = "loose" .. key,
              throttle = 6, hold = 3 })
    elseif not onHealer and Cfg().lostAggro then
        Alerts:Show(string.format("Mob on %s", victim),
            { sub = TauntState(), color = C.warn, sound = "alarm", kind = "aggro", key = "loose" .. key,
              throttle = 6, hold = 2.5 })
    end
end)

--- Whether the lapse alert applies here. Solo in the open world it's mostly noise.
---@param where "always"|"group"|"instance"|nil the alerts.lapseWhere setting ("group" when nil)
---@param inGroup boolean
---@param inInstance boolean
---@return boolean
function Alerts.LapseWanted(where, inGroup, inInstance)
    if where == "always" then return true end
    if where == "instance" then return inInstance == true end
    return inGroup == true or inInstance == true
end

TF:On("LAPSE", function(entry, gap)
    if not Cfg().mitigationLapse then return end
    local inInstance = API.Safe(IsInInstance)
    if not Alerts.LapseWanted(Cfg().lapseWhere, API.PlainBool(API.Safe(IsInGroup)) == true,
        API.PlainBool(inInstance) == true) then return end
    local name = API.GetSpellName(entry.spell) or "Mitigation"
    Alerts:Show(name .. "!", { sub = string.format("Being hit without it for %.0fs", gap), color = C.mitigation,
        kind = "lapse", key = "lapse", throttle = 8, hold = 2 })
end)

TF:On("DEATH", function(ready)
    if not Cfg().death then return end
    local sub = #ready > 0 and ("Still ready: " .. table.concat(ready, ", ")) or "No major defensive was ready"
    Alerts:Show("You died", { sub = sub, color = C.bad, kind = "death", hold = 6 })
    if #ready > 0 then TF:Print("you died with " .. table.concat(ready, ", ") .. " still ready.") end
end)

local wasReady = {}
TF:On("PULL_START", function()
    wipe(wasReady)
    for _, e in ipairs(Tank.icons) do
        if e.def.major then wasReady[e] = Tank:IsReady(e) end
    end
end)

TF:On("PULL_TICK", function(_, now)
    if not Cfg().defensiveReady then return end
    for _, e in ipairs(Tank.icons) do
        if e.def.major then
            local ready = Tank:IsReady(e, now)
            if ready and wasReady[e] == false then
                Alerts:Show((API.GetSpellName(e.spell) or "Defensive") .. " ready",
                    { color = C.good, kind = "ready", key = "ready" .. e.spell, throttle = 20, hold = 2 })
            end
            wasReady[e] = ready
        end
    end
end)

-- Throttle entries are keyed per mob, so drop old ones after each fight
-- instead of keeping one for every mob ever seen.
TF:On("COMBAT", function(inCombat)
    if inCombat then return end
    local now = API.Now()
    for key, t in pairs(lastShown) do
        if now - t > 60 then lastShown[key] = nil end
    end
end)

TF:On("UNLOCKED", function(on)
    if on then
        f.text:SetText("Alerts")
        f.text:SetTextColor(unpack(C.text))
        f.sub:SetText("Drag the box to move")
        f:SetAlpha(1)
        f:Show()
    else
        f:Hide()
    end
    Style.FitAnchor("alerts")
end)

TF:AddCommand("test", function(args)
    if strlower(strtrim(args or "")) == "healer" then
        if ns.Healer then ns.Healer:Test() end
        return
    end
    Alerts:Show("Kobold Geomancer is on your healer!", { sub = "Taunt is ready", color = C.bad,
        sound = "warning", kind = "test", hold = 4 })
end, "[healer] - show a test alert", { group = "Debugging", details = {
    "(no argument) - show a sample alert, to check where it appears and how it sounds",
    "healer - force the healer panel shown/hidden without a party; use in combat to test it, again to stop",
} })
