-- Modules/Party.lua
-- Minimal party frames with portraits: portrait, name, health, a thin power
-- bar. The border turns red when a mob is on that member, and a small plus
-- marks the healer. Left-click targets, right-click opens the unit menu.
--
-- Built from secure unit buttons, so they work in combat. They are created
-- and placed at load, and never moved in combat. Blizzard's party frames are
-- hidden while these are on (turning them back on needs a /reload).
--
-- Your healer is left out (they have their own panel) unless that's turned off.
-- Which member each button shows can only change out of combat, so a group
-- change mid-fight is applied when the fight ends.
local _, ns = ...
local TF = ns.TF
local API = ns.API
local Style = ns.Style

local Party = {}
ns.Party = Party

local W, H = 190, 40
local GAP = 6
local C = Style.colors

local container = CreateFrame("Frame", "TankForgeUIParty", UIParent, "SecureHandlerStateTemplate")
container:SetSize(W, H * 4 + GAP * 3)
Party.frame = container
Party.buttons = {}
local built = false

Style.Movable(container, "party", "Party", { "CENTER", "CENTER", -560, 40 })

local function Border(f)
    local t = {}
    for i, spec in ipairs({
        { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
        { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil },
    }) do
        local tex = f:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(Style.FLAT)
        tex:SetVertexColor(0, 0, 0, 1)
        tex:SetPoint(spec[1], f, spec[1])
        tex:SetPoint(spec[2], f, spec[2])
        if spec[3] then tex:SetWidth(spec[3]) end
        if spec[4] then tex:SetHeight(spec[4]) end
        t[i] = tex
    end
    f.borderTextures = t
end

local function MakeButton(i)
    local unit = "party" .. i
    local b = CreateFrame("Button", "TankForgeUIParty" .. i, container, "SecureUnitButtonTemplate")
    b:SetSize(W, H)
    b:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -(i - 1) * (H + GAP))
    b.unit = unit
    b:SetAttribute("unit", unit)
    b:SetAttribute("type1", "target")
    b:SetAttribute("type2", "togglemenu")
    b:RegisterForClicks("AnyUp")

    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetTexture(Style.FLAT)
    b.bg:SetVertexColor(unpack(C.bg))
    Border(b)

    b.portrait = b:CreateTexture(nil, "ARTWORK")
    b.portrait:SetPoint("TOPLEFT", 1, -1)
    b.portrait:SetSize(H - 2, H - 2)
    b.portrait:SetTexCoord(0.12, 0.88, 0.12, 0.88)

    b.name = Style.Text(b, 11)
    b.name:SetPoint("TOPLEFT", b.portrait, "TOPRIGHT", 6, -3)
    b.name:SetJustifyH("LEFT")
    b.status = Style.Text(b, 10)
    b.status:SetPoint("TOPRIGHT", -5, -4)
    b.status:SetJustifyH("RIGHT")
    b.name:SetPoint("RIGHT", b.status, "LEFT", -4, 0)

    b.health = Style.Bar(b, 13, C.health, 10)
    b.health:SetPoint("TOPLEFT", b.portrait, "TOPRIGHT", 4, -17)
    b.health:SetPoint("RIGHT", b, "RIGHT", -4, 0)
    b.health.label:Hide()
    b.power = Style.Bar(b, 4, C.mana, 0)
    b.power:SetPoint("TOPLEFT", b.health, "BOTTOMLEFT", 0, -1)
    b.power:SetPoint("TOPRIGHT", b.health, "BOTTOMRIGHT", 0, -1)

    b.leader = Style.LeaderBadge(b, 14)

    b.healerMark = Style.Text(b, 14)
    b.healerMark:SetPoint("BOTTOMRIGHT", b.portrait, "BOTTOMRIGHT", 1, -1)
    b.healerMark:SetText("+")
    b.healerMark:SetTextColor(0.3, 1, 0.45)

    b:SetScript("OnEnter", function(self)
        if GameTooltip_SetDefaultAnchor then GameTooltip_SetDefaultAnchor(GameTooltip, self) end
        if pcall(GameTooltip.SetUnit, GameTooltip, self.unit) then GameTooltip:Show() end
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Shown by the unit watch when someone joins: draw who it is right away.
    b:HookScript("OnShow", function(self)
        Party:UpdateIdentity(self)
        Party:UpdateButton(self)
    end)

    RegisterUnitWatch(b)
    return b
end

-- Updating -------------------------------------------------------------------

-- Who the button shows: portrait, name and class color. These only change
-- when the game says so (roster, portrait or name events), so they aren't
-- redrawn on the timer; a portrait is one of the costlier frame calls.
function Party:UpdateIdentity(b)
    local unit = b.unit
    if not API.UnitExists(unit) then return end
    local r, g, bl = API.ClassColor(API.UnitClass(unit))
    b.name:SetText(API.UnitName(unit) or "?")
    b.name:SetTextColor(r, g, bl)
    b.health:SetStatusBarColor(r * 0.8, g * 0.8, bl * 0.8)
    if SetPortraitTexture then pcall(SetPortraitTexture, b.portrait, unit) end
end

-- Everything that changes from moment to moment, on the 0.2s timer.
function Party:UpdateButton(b)
    local unit = b.unit
    if not API.UnitExists(unit) then return end
    API.SetBarValues(b.health, 0, API.UnitHealthMaxRaw(unit), API.UnitHealthRaw(unit))
    local pct = API.PercentDisplay(unit)
    if not (pct and pcall(b.health.value.SetFormattedText, b.health.value, "%.0f%%", pct)) then
        b.health.value:SetText("")
    end
    local ptype = API.UnitPowerType(unit) or 0
    local pc = Style.PowerColor(ptype)
    b.power:SetStatusBarColor(pc[1], pc[2], pc[3])
    API.SetBarValues(b.power, 0, API.UnitPowerMaxRaw(unit, ptype), API.UnitPowerRaw(unit, ptype))

    local dead, online = API.IsDeadOrGhost(unit), API.IsConnected(unit)
    if not online then
        Style.SetText(b.status, "OFFLINE")
        b.status:SetTextColor(unpack(C.muted))
    elseif dead then
        Style.SetText(b.status, "DEAD")
        b.status:SetTextColor(unpack(C.bad))
    else
        Style.SetText(b.status, "")
    end
    b.portrait:SetDesaturated(dead or not online)

    -- A mob is on them (threat status 2 or 3 on anything).
    local status = API.PlainNumber((API.Safe(UnitThreatSituation, unit)))
    if status and status >= 2 then
        Style.SetBorderColor(b, 0.95, 0.15, 0.15, 1)
    else
        Style.SetBorderColor(b, 0, 0, 0, 1)
    end

    b.healerMark:SetShown(ns.Healer and ns.Healer.unit == unit or false)
    b.leader:SetShown(API.IsLeader(unit))

    -- The container carries your opacity setting; this only adds range dimming.
    API.ApplyRangeAlpha(b, unit, 1, 0.5, TF.db.party.dimOutOfRange)
end

-- Give the buttons, top to bottom, every party member except the healer.
function Party:Assign()
    if not built then return end
    if InCombatLockdown() then
        if not self.assignQueued then
            self.assignQueued = true
            TF:AfterCombat(function() Party.assignQueued = false Party:Assign() end)
        end
        return
    end
    local skip = TF.db.party.hideHealer and TF.db.healer.enabled and ns.Healer and ns.Healer.unit
    local units = {}
    for i = 1, 4 do
        local u = "party" .. i
        if u ~= skip then units[#units + 1] = u end
    end
    for i, b in ipairs(self.buttons) do
        local u = units[i]
        if u then
            b.unit = u
            b:SetAttribute("unit", u)
            RegisterUnitWatch(b)
        else
            UnregisterUnitWatch(b)
            b:Hide()
        end
    end
    self:UpdateIdentityAll()
    self:UpdateAll()
end

function Party:UpdateIdentityAll()
    for _, b in ipairs(self.buttons) do self:UpdateIdentity(b) end
end

function Party:ApplyAlpha()
    container:SetAlpha(Style.FrameAlpha(TF.db.party))
end

function Party:UpdateAll()
    for _, b in ipairs(self.buttons) do
        if b:IsVisible() then self:UpdateButton(b) end
    end
end

-- Blizzard's party frames ------------------------------------------------------

local hiddenParent = CreateFrame("Frame")
hiddenParent:Hide()

local function HideBlizzard()
    if InCombatLockdown() then return end
    for _, name in ipairs({ "PartyFrame", "CompactPartyFrame" }) do
        local frame = _G[name]
        if frame and frame:GetParent() ~= hiddenParent then
            pcall(frame.SetParent, frame, hiddenParent)
        end
    end
end

-- Setup ----------------------------------------------------------------------

function Party:Build()
    if built or not TF.db.party.enabled then return end
    if InCombatLockdown() then
        TF:AfterCombat(function() Party:Build() end)
        return
    end
    built = true
    for i = 1, 4 do self.buttons[i] = MakeButton(i) end
    RegisterStateDriver(container, "visibility", "[group:raid] hide; [group:party] show; hide")
    container:SetScale(TF.db.scale or 1)
    Style.FitAnchor("party")
    HideBlizzard()
    self:Assign()
    self:ApplyAlpha()
end

TF:On("LOGIN", function() Party:Build() end)

-- Identity: the whole group on roster changes, one member on their own events.
TF:RegisterEvent("GROUP_ROSTER_UPDATE", function()
    if not built then return end
    HideBlizzard()
    Party:UpdateIdentityAll()
    Party:UpdateAll()
end)
for _, ev in ipairs({ "UNIT_PORTRAIT_UPDATE", "UNIT_NAME_UPDATE" }) do
    TF:RegisterEvent(ev, function(_, unit)
        if not built then return end
        for _, b in ipairs(Party.buttons) do
            if unit == nil or b.unit == unit then Party:UpdateIdentity(b) end
        end
    end)
end
-- Moment-to-moment state that has its own event, so it doesn't wait for the timer.
for _, ev in ipairs({ "PARTY_LEADER_CHANGED", "UNIT_CONNECTION", "UNIT_THREAT_SITUATION_UPDATE",
    "PLAYER_ROLES_ASSIGNED" }) do
    TF:RegisterEvent(ev, function()
        if built then Party:UpdateAll() end
    end)
end

TF:On("HEALER_CHANGED", function() Party:Assign() end)
TF:On("COMBAT", function() Party:ApplyAlpha() end)
TF:On("UNLOCKED", function() Party:ApplyAlpha() end)

local elapsed = 0
container:HookScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < 0.2 then return end
    elapsed = 0
    Party:UpdateAll()
end)
