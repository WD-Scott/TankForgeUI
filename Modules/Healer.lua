-- Modules/Healer.lua
-- Your healer at a glance: health, mana, what they're casting, and a status
-- tag (dead, being attacked, drinking, low mana, out of range).
--
-- The healer is, in order: the one you picked with /tf healer, the group's
-- assigned healer, or a guess from class (a priest first).
local _, ns = ...
local TF = ns.TF
local API = ns.API
local Style = ns.Style
local Tank = ns.Tank

local Healer = {}
ns.Healer = Healer

local WIDTH = 250
local PAD = 6
local PORTRAIT = 54
local LOW_MANA = 0.30

local f = Style.Panel(UIParent, "TankforgeUIHealer")
f:SetSize(WIDTH, 66)
f:Hide()
Healer.frame = f

-- Portrait on the left, like the party frames.
f.portrait = f:CreateTexture(nil, "ARTWORK")
f.portrait:SetPoint("TOPLEFT", 5, -6)
f.portrait:SetSize(PORTRAIT, PORTRAIT)
f.portrait:SetTexCoord(0.12, 0.88, 0.12, 0.88)
local LEFT = 5 + PORTRAIT + 6

f.role = Style.Text(f, 10)
f.role:SetPoint("TOPLEFT", LEFT, -PAD - 3)
f.role:SetText("HEALER")
f.role:SetTextColor(unpack(Style.colors.accent))
f.name = Style.Text(f, 12)
f.name:SetPoint("LEFT", f.role, "RIGHT", 6, 0)
f.name:SetJustifyH("LEFT")
f.tag = Style.Text(f, 11)
f.tag:SetPoint("TOPRIGHT", -PAD, -PAD - 3)
f.tag:SetJustifyH("RIGHT")
f.name:SetPoint("RIGHT", f.tag, "LEFT", -6, 0)

f.leader = Style.LeaderBadge(f, 14)

f.health = Style.Bar(f, 14, Style.colors.health, 10)
f.health:SetPoint("TOPLEFT", LEFT, -PAD - 19)
f.health:SetPoint("TOPRIGHT", -PAD, -PAD - 19)
f.mana = Style.Bar(f, 10, Style.colors.mana, 9)
f.mana:SetPoint("TOPLEFT", f.health, "BOTTOMLEFT", 0, -2)
f.mana:SetPoint("TOPRIGHT", f.health, "BOTTOMRIGHT", 0, -2)
f.cast = Style.Text(f, 10)
f.cast:SetPoint("TOPLEFT", f.mana, "BOTTOMLEFT", 0, -3)
f.cast:SetPoint("TOPRIGHT", f.mana, "BOTTOMRIGHT", 0, -3)
f.cast:SetJustifyH("LEFT")
f.cast:SetTextColor(unpack(Style.colors.muted))

Style.Movable(f, "healer", "Healer", { "CENTER", "CENTER", 250, -30 })

-- Clicking: an invisible secure button over the panel, so left-click targets
-- the healer and right-click opens their menu, in combat too. Which unit it
-- points at can only change out of combat; it hides itself when that unit is gone.
local click = CreateFrame("Button", "TankforgeUIHealerButton", UIParent, "SecureUnitButtonTemplate")
click:SetAllPoints(f)
click:SetFrameStrata(f:GetFrameStrata() or "MEDIUM")
click:SetFrameLevel((f:GetFrameLevel() or 1) + 10)
click:SetAttribute("type1", "target")
click:SetAttribute("type2", "togglemenu")
click:RegisterForClicks("AnyUp")
click:SetScript("OnEnter", function(self)
    local unit = self:GetAttribute("unit")
    if not unit then return end
    if GameTooltip_SetDefaultAnchor then GameTooltip_SetDefaultAnchor(GameTooltip, self) end
    if pcall(GameTooltip.SetUnit, GameTooltip, unit) then GameTooltip:Show() end
end)
click:SetScript("OnLeave", function() GameTooltip:Hide() end)
click:Hide()
Healer.click = click

-- Finding the healer -----------------------------------------------------------

local function PartyUnits()
    local list = {}
    if IsInGroup() and not IsInRaid() then
        for i = 1, 4 do
            if API.UnitExists("party" .. i) then list[#list + 1] = "party" .. i end
        end
    end
    return list
end

function Healer:Find()
    local units = PartyUnits()
    local picked = TF.db.healerName
    if picked then
        for _, u in ipairs(units) do
            if API.UnitName(u) == picked then return u, "picked" end
        end
    end
    for _, u in ipairs(units) do
        if API.UnitRole(u) == "HEALER" then return u, "role" end
    end
    local best, bestWeight = nil, 0
    for _, u in ipairs(units) do
        local role = API.UnitRole(u)
        local w = ns.HEALER_CLASSES[API.UnitClass(u) or ""] or 0
        if role ~= "TANK" and role ~= "DAMAGER" and w > bestWeight then best, bestWeight = u, w end
    end
    if best then return best, "guess" end
    return nil
end

function Healer:Describe()
    if not self.unit then return "none" end
    return string.format("%s (%s)", API.UnitName(self.unit) or self.unit, self.how or "?")
end

-- Updating -------------------------------------------------------------------

local C = Style.colors
local drinkName

local function Tag(text, color)
    f.tag:SetText(text)
    f.tag:SetTextColor(unpack(color))
end

function Healer:Update()
    local unit = self.unit
    if not unit then
        f.name:SetText("|cff" .. Style.Hex(C.muted) .. "none found|r")
        Tag("", C.muted)
        API.SetBarValues(f.health, 0, 1, 0)
        API.SetBarValues(f.mana, 0, 1, 0)
        f.health.value:SetText("")
        f.mana.value:SetText("")
        f.cast:SetText("Target your healer and type /tf healer")
        f.leader:Hide()
        f.portrait:SetTexture(nil)
        f:SetAlpha(Style.FrameAlpha(TF.db.healer))
        return
    end
    local r, g, b = API.ClassColor(API.UnitClass(unit))
    f.name:SetText(API.UnitName(unit) or "?")
    f.name:SetTextColor(r, g, b)
    f.leader:SetShown(API.IsLeader(unit))
    f.portrait:SetDesaturated(API.IsDeadOrGhost(unit) or not API.IsConnected(unit))

    -- Health and mana; both may be secret in combat, which the bars accept.
    API.SetBarValues(f.health, 0, API.UnitHealthMaxRaw(unit), API.UnitHealthRaw(unit))
    local hp = API.PercentDisplay(unit)
    if not (hp and pcall(f.health.value.SetFormattedText, f.health.value, "%.0f%%", hp)) then
        f.health.value:SetText("")
    end
    local MANA = API.PowerType("Mana")
    API.SetBarValues(f.mana, 0, API.UnitPowerMaxRaw(unit, MANA), API.UnitPowerRaw(unit, MANA))
    local mp = API.PercentDisplay(unit, MANA)
    if not (mp and pcall(f.mana.value.SetFormattedText, f.mana.value, "%.0f%%", mp)) then
        f.mana.value:SetText("")
    end

    -- What they're casting.
    -- In combat the spell name is hidden; the text widget can still show it.
    local spell = API.Safe(UnitCastingInfo, unit)
    if not API.IsSecret(spell) and spell == nil then spell = API.Safe(UnitChannelInfo, unit) end
    if API.IsSecret(spell) or type(spell) == "string" then
        if not pcall(f.cast.SetFormattedText, f.cast, "Casting %s", spell) then f.cast:SetText("") end
    else
        f.cast:SetText("")
    end

    -- Status tag, most urgent first.
    local manaFrac = API.PowerFraction(unit, MANA)
    drinkName = drinkName or API.GetSpellName(430) or "Drink"
    local outOfRange = API.RangeState(unit)
    if API.IsDeadOrGhost(unit) then
        Tag("DEAD", C.bad)
    elseif not API.IsConnected(unit) then
        Tag("OFFLINE", C.muted)
    elseif ns.Threat and ns.Threat.healerAttacked then
        Tag("ATTACKED", C.bad)
    elseif API.GetAuraByName(unit, drinkName, "HELPFUL") then
        Tag("DRINKING", C.mana)
    elseif manaFrac and manaFrac < LOW_MANA then
        Tag(string.format("LOW MANA %d%%", manaFrac * 100), C.warn)
    elseif outOfRange then
        Tag("OUT OF RANGE", C.warn)
    else
        Tag("", C.muted)
    end

    -- Your opacity setting, dimmed further only when they're confirmed out of range.
    API.ApplyRangeAlpha(f, unit, Style.FrameAlpha(TF.db.healer), 0.55, TF.db.healer.dimOutOfRange)

    -- Red border while a mob is on them.
    if ns.Threat and ns.Threat.healerAttacked then
        Style.SetBorderColor(f, 0.9, 0.15, 0.15, 1)
    else
        Style.SetBorderColor(f, 0, 0, 0, 1)
    end
end

function Healer:Refresh()
    local old = self.unit
    self.unit, self.how = self:Find()
    if not TF.db.healer.enabled then self.unit, self.how = nil, nil end
    if self.unit ~= old then TF:Fire("HEALER_CHANGED", self.unit) end
    local inParty = IsInGroup() and not IsInRaid()
    local show = TF.db.healer.enabled and (Style.IsUnlocked()
        or (inParty and (self.unit or not TF.inCombat) and (Tank.isTank or not Tank.kit)))
    f:SetShown(show and true or false)
    if self.unit ~= old then self:UpdatePortrait() end
    if show then self:Update() end
    self:SyncClick()
end

function Healer:UpdatePortrait()
    if self.unit and SetPortraitTexture then pcall(SetPortraitTexture, f.portrait, self.unit) end
end

-- Point the click button at the healer while the panel shows them.
function Healer:SyncClick()
    if InCombatLockdown() then
        if not self.clickQueued then
            self.clickQueued = true
            TF:AfterCombat(function() Healer.clickQueued = false Healer:SyncClick() end)
        end
        return
    end
    if f:IsShown() and self.unit then
        click:SetAttribute("unit", self.unit)
        RegisterUnitWatch(click)
    else
        UnregisterUnitWatch(click)
        click:SetAttribute("unit", nil)
        click:Hide()
    end
end

local elapsed = 0
f:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < 0.2 then return end
    elapsed = 0
    Healer:Update()
end)

TF:RegisterEvent("GROUP_ROSTER_UPDATE", function() Healer:Refresh() end)
TF:RegisterEvent("UNIT_PORTRAIT_UPDATE", function(_, unit)
    if unit and unit == Healer.unit then Healer:UpdatePortrait() end
end)
TF:RegisterEvent("PLAYER_ROLES_ASSIGNED", function() Healer:Refresh() end)
TF:On("ENTERING_WORLD", function() Healer:Refresh() end)
TF:On("TANK_CHANGED", function() Healer:Refresh() end)
TF:On("UNLOCKED", function() Healer:Refresh() end)
TF:On("COMBAT", function() Healer:Refresh() end)
TF:On("LOADED", function() f:SetScale(TF.db.scale or 1) end)

-- What each frame's opacity actually is right now, and why.
TF:AddCommand("alpha", function()
    local function pct(v) return string.format("%d%%", (v or 0) * 100 + 0.5) end
    local function range(unit)
        local inRange, checked = API.Safe(UnitInRange, unit)
        local function show(v)
            if API.IsSecret(v) then return "hidden" end
            return tostring(v)
        end
        return "in range " .. show(inRange) .. ", checked " .. show(checked)
    end
    local cfg = TF.db.healer
    TF:Print(string.format("healer panel: setting %s in / %s out of combat, showing %s%s",
        pct(cfg.alpha), pct(cfg.oocAlpha), pct(f:GetAlpha()),
        Healer.unit and (" (" .. (API.UnitName(Healer.unit) or "?") .. ": " .. range(Healer.unit) .. ")") or ""))
    local P = ns.Party
    if P and P.frame then
        local pc = TF.db.party
        TF:Print(string.format("party frames: setting %s in / %s out of combat, showing %s",
            pct(pc.alpha), pct(pc.oocAlpha), pct(P.frame:GetAlpha())))
        for _, b in ipairs(P.buttons) do
            if b:IsVisible() then
                TF:Print(string.format("  %s: %s (%s)", API.UnitName(b.unit) or b.unit, pct(b:GetAlpha()), range(b.unit)))
            end
        end
    end
end, "- show what opacity the healer and party frames are using, and why")

TF:AddCommand("healer", function()
    local name = API.UnitExists("target") and API.UnitName("target")
    local inGroup = name and (API.PlainBool((API.Safe(UnitInParty, "target")))
        or API.PlainNumber((API.Safe(UnitInRaid, "target"))) ~= nil)
    if inGroup and not API.UnitIsUnit("target", "player") then
        TF.db.healerName = name
        TF:Print("healer set to " .. name .. ".")
    else
        TF.db.healerName = nil
        TF:Print("healer back to automatic (role, then class). Target a party member first to pick one.")
    end
    Healer:Refresh()
end, "- make your target the healer (no target: automatic)")
