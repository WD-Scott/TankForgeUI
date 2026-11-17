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

-- A little bigger than a party button (190x40) and the only one with the amber
-- top line, a full mana bar and an amber-edged portrait, so it reads as the
-- same family with a bit more weight.
local WIDTH, HEIGHT = 206, 48
local PAD = 5
local PORTRAIT = 39
local LOW_MANA = 0.30

local f = Style.Panel(UIParent, "TankForgeUIHealer")
f:SetSize(WIDTH, HEIGHT)
f:Hide()
Healer.frame = f

local A = Style.colors.accent
f.portrait = Style.Portrait(f, PORTRAIT)
f.portrait:SetPoint("TOPLEFT", 4, -5)
Style.SetBorderColor(f.portrait, A[1], A[2], A[3], 0.6)
local LEFT = 4 + PORTRAIT + 5

f.role = Style.RoleIcon(f, 13)
f.role:SetPoint("TOPLEFT", LEFT, -5)
Style.SetRoleIcon(f.role, "HEALER")
f.name = Style.Text(f, 11)
f.name:SetPoint("LEFT", f.role, "RIGHT", 5, 0)
f.name:SetJustifyH("LEFT")
f.tag = Style.Text(f, 10)
f.tag:SetPoint("TOPRIGHT", -PAD, -7)
f.tag:SetJustifyH("RIGHT")
f.name:SetPoint("RIGHT", f.tag, "LEFT", -5, 0)

f.leader = Style.LeaderBadge(f.portrait, 14)

f.health = Style.Bar(f, 13, Style.colors.health, 10)
f.health:SetPoint("TOPLEFT", LEFT, -20)
f.health:SetPoint("TOPRIGHT", -PAD, -20)
-- The mana bar's left side says what they're casting.
f.mana = Style.Bar(f, 10, Style.colors.mana, 9)
f.mana:SetPoint("TOPLEFT", f.health, "BOTTOMLEFT", 0, -2)
f.mana:SetPoint("TOPRIGHT", f.health, "BOTTOMRIGHT", 0, -2)
f.cast = f.mana.label
f.cast:SetTextColor(unpack(Style.colors.text))

Style.Movable(f, "healer", "Healer", { "CENTER", "CENTER", 250, -30 })

-- Clicking: an invisible secure button over the panel, so left-click targets
-- the healer and right-click opens their menu, in combat too. Which unit it
-- points at can only change out of combat; it hides itself when that unit is gone.
local click = CreateFrame("Button", "TankForgeUIHealerButton", UIParent, "SecureUnitButtonTemplate")
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

----- party1..party4 that exist, only in a 5-player party (never in a raid).
local function PartyUnits()
    local list = {}
    if IsInGroup() and not IsInRaid() then
        for i = 1, 4 do
            if API.UnitExists("party" .. i) then list[#list + 1] = "party" .. i end
        end
    end
    return list
end

--- Your healer, in order: the one picked with /tf healer, the party's HEALER role,
--- then the most likely healing class (priest first) not assigned TANK or DAMAGER.
---@return string|nil unit, string|nil how "picked", "role" or "guess"
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

--- "Name (how)" for /tf status and the log, "none" without a healer.
---@return string
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

--- The status tag, most urgent first: DEAD, OFFLINE, ATTACKED, DRINKING,
--- LOW MANA n%, OUT OF RANGE, or "".
---@param unit string
---@return string text, string colorKey a key of Style.colors
function Healer.StatusTag(unit)
    if API.IsDeadOrGhost(unit) then return "DEAD", "bad" end
    if not API.IsConnected(unit) then return "OFFLINE", "muted" end
    if ns.Threat and ns.Threat.healerAttacked then return "ATTACKED", "bad" end
    drinkName = drinkName or API.GetSpellName(430) or "Drink"
    if API.GetAuraByName(unit, drinkName, "HELPFUL") then return "DRINKING", "mana" end
    local manaFrac = API.PowerFraction(unit, API.PowerType("Mana"))
    if manaFrac and manaFrac < LOW_MANA then return string.format("LOW MANA %d%%", manaFrac * 100), "warn" end
    if API.RangeState(unit) then return "OUT OF RANGE", "warn" end
    return "", "muted"
end

--- Redraw name, bars, cast, status tag, opacity and border for the healer.
function Healer:Update()
    local unit = self.unit
    if not unit then
        f.name:SetText("|cff" .. Style.Hex(C.muted) .. "none found|r")
        Tag("", C.muted)
        API.SetBarValues(f.health, 0, 1, 0)
        API.SetBarValues(f.mana, 0, 1, 0)
        f.health.value:SetText("")
        f.mana.value:SetText("")
        f.cast:SetText("Target them, /tf healer")
        f.leader:Hide()
        f.portrait.tex:SetTexture(nil)
        if not self.combatHidden then f:SetAlpha(Style.FrameAlpha(TF.db.healer)) end
        return
    end
    local r, g, b = API.ClassColor(API.UnitClass(unit))
    f.name:SetText(API.UnitName(unit) or "?")
    f.name:SetTextColor(r, g, b)
    f.leader:SetShown(API.IsLeader(unit))
    f.portrait.tex:SetDesaturated(API.IsDeadOrGhost(unit) or not API.IsConnected(unit))

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
        if not pcall(f.cast.SetFormattedText, f.cast, "%s", spell) then f.cast:SetText("") end
    else
        f.cast:SetText("")
    end

    local text, colorKey = Healer.StatusTag(unit)
    Tag(text, C[colorKey])

    -- Your opacity setting, dimmed further only when they're confirmed out of range.
    -- Left at 0 while the panel waits to be hidden after combat (see ApplyShown).
    if not self.combatHidden then
        API.ApplyRangeAlpha(f, unit, Style.FrameAlpha(TF.db.healer), 0.55, TF.db.healer.dimOutOfRange)
    end

    -- Red border while a mob is on them.
    Style.SetAlertBorder(f, ns.Threat and ns.Threat.healerAttacked)
end

--- Re-find the healer (firing HEALER_CHANGED on a change) and decide whether the
--- panel shows: enabled, and unlocked or in a party while tanking (or with no kit).
function Healer:Refresh()
    local old = self.unit
    self.unit, self.how = self:Find()
    if not TF.db.healer.enabled then self.unit, self.how = nil, nil end
    if self.unit ~= old then TF:Fire("HEALER_CHANGED", self.unit) end
    local inParty = IsInGroup() and not IsInRaid()
    local show = TF.db.healer.enabled and (Style.IsUnlocked()
        or (inParty and (self.unit or not TF.inCombat) and (Tank.isTank or not Tank.kit)))
    show = show and true or false
    if self.testShow ~= nil then show = self.testShow end
    self:ApplyShown(show)
    if self.unit ~= old then self:UpdatePortrait() end
    if show then self:Update() end
    self:SyncClick()
end

-- The click button is anchored to the panel, which makes the panel protected:
-- the game blocks showing or hiding it in combat. So in combat a panel that
-- should hide only goes transparent, one that should appear waits, and both
-- are settled once the fight ends.
local shownQueued = false
--- Show or hide the (protected) panel; in combat, fade it and settle after.
---@param show boolean
function Healer:ApplyShown(show)
    if not InCombatLockdown() then
        if self.combatHidden then
            TF:Log("HEALER", "panel %s now that combat ended", show and "kept (it's needed again)" or "hidden")
        end
        if f:IsShown() ~= show then f:SetShown(show) end
        self.combatHidden = nil
        return
    end
    if show then
        -- Already up: undo a transparent hide from earlier in this fight.
        if f:IsShown() then
            self.combatHidden = nil
            return
        end
    elseif f:IsShown() and not self.combatHidden then
        self.combatHidden = true
        f:SetAlpha(0)
    elseif not f:IsShown() then
        return
    end
    if not shownQueued then
        shownQueued = true
        TF:AfterCombat(function()
            shownQueued = false
            Healer:Refresh()
        end)
    end
end

--- /tf test healer: flips the panel without needing a party, to check the
--- in-combat path above. Run it again to go back to normal.
function Healer:Test()
    if self.testShow == nil then
        self.testShow = not (f:IsShown() and not self.combatHidden)
        TF:Print("healer panel test: forcing it " .. (self.testShow and "shown" or "hidden")
            .. (InCombatLockdown() and " (in combat)" or "") .. ". /tf test healer again to stop.")
    else
        self.testShow = nil
        TF:Print("healer panel test: off.")
    end
    local D = ns.Log and ns.Log.D or tostring
    TF:Log("TEST", "healer panel test: %s, in combat %s, panel shown %s, alpha %s",
        self.testShow == nil and "off" or (self.testShow and "force shown" or "force hidden"),
        tostring(InCombatLockdown() and true or false), tostring(f:IsShown()), D(f:GetAlpha()))
    self:Refresh()
    if self.testShow ~= nil or InCombatLockdown() then
        TF:Log("TEST", "  after: panel shown %s, alpha %s, waiting for combat to end %s",
            tostring(f:IsShown()), D(f:GetAlpha()), tostring(shownQueued))
    end
end

function Healer:UpdatePortrait()
    if self.unit and SetPortraitTexture then pcall(SetPortraitTexture, f.portrait.tex, self.unit) end
end

--- Point the click button at the healer while the panel shows them.
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
end, "- show what opacity the healer and party frames are using, and why", { group = "Tanking" })

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
end, "- make your target the healer", { group = "Tanking", details = {
    "Target a party member first, then /tf healer: they're your healer from now on.",
    "With no party member targeted: back to automatic (their group role, then class).",
} })
