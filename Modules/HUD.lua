-- Modules/HUD.lua
-- The tank HUD: your portrait, health and rage (or mana) in one short panel,
-- with your stance buttons in a flyout off its right edge.
local _, ns = ...
local TF = ns.TF
local API = ns.API
local Style = ns.Style
local Tank = ns.Tank

local HUD = {}
ns.HUD = HUD

local WIDTH = 230
local PAD = 6
local BARS = 20 + 3 + 16          -- health, gap, power
local HEIGHT = PAD + 2 + BARS + PAD
local ARROW = "Interface\\ChatFrame\\ChatFrameExpandArrow"

-- The panel holds the portrait, health and power. The stance tab and column
-- hanging off its right edge are secure, which makes this frame protected: in
-- combat it can't be shown, hidden, resized or rescaled.
local f = Style.Panel(UIParent, "TankForgeUIHUD")
f:SetSize(WIDTH, HEIGHT)
f:Hide()
HUD.frame = f
HUD.HEIGHT = HEIGHT

-- Your portrait, round, as tall as the health and power bars beside it.
f.portrait = Style.RoundPortrait(f, BARS)
f.portrait:SetPoint("TOPLEFT", PAD, -PAD - 2)

f.health = Style.Bar(f, 20, Style.colors.health, 12)
f.health:SetPoint("TOPRIGHT", -PAD, -PAD - 2)
f.health.label:SetText("Health")

f.power = Style.Bar(f, 16, Style.colors.rage, 11)
f.power:SetPoint("TOPLEFT", f.health, "BOTTOMLEFT", 0, -3)
f.power:SetPoint("TOPRIGHT", f.health, "BOTTOMRIGHT", 0, -3)

-- Your own crown goes here, since your player frame is hidden.
f.leader = Style.LeaderBadge(f, 16)

-- The stance flyout. A grip strip on the panel's right edge opens and closes a
-- column holding Stances.lua's buttons. Both are anchored top and bottom to
-- the panel, overlapping its border by 1px, so the three read as one frame of
-- the same height. The grip is a secure handler, so it can show and hide the
-- (protected) column in combat. The column's own OnShow/OnHide remember the
-- choice and turn the arrow; they only touch our frames.
local GRIP = 10
local MUTED = Style.colors.muted

f.stanceTab = Style.PanelLook(CreateFrame("Button", "TankForgeUIStanceTab", f, "SecureHandlerClickTemplate"))
f.stanceTab:SetWidth(GRIP)
f.stanceTab:SetPoint("TOPLEFT", f, "TOPRIGHT", -1, 0)
f.stanceTab:SetPoint("BOTTOMLEFT", f, "BOTTOMRIGHT", -1, 0)
f.stanceTab:RegisterForClicks("AnyUp")
f.stanceTab:Hide()
f.stanceTab.arrow = f.stanceTab:CreateTexture(nil, "ARTWORK")
f.stanceTab.arrow:SetTexture(ARROW)
f.stanceTab.arrow:SetSize(8, 8)
f.stanceTab.arrow:SetPoint("CENTER", 0, -1)
f.stanceTab.arrow:SetVertexColor(MUTED[1], MUTED[2], MUTED[3])
f.stanceTab.hl = Style.Flat(f.stanceTab, "HIGHLIGHT", { Style.colors.accent[1], Style.colors.accent[2],
    Style.colors.accent[3], 0.12 })
f.stanceTab.hl:SetPoint("TOPLEFT", 1, -3)
f.stanceTab.hl:SetPoint("BOTTOMRIGHT", -1, 1)

f.stanceCol = Style.PanelLook(CreateFrame("Frame", "TankForgeUIStanceCol", f, "SecureFrameTemplate"))
f.stanceCol:SetPoint("TOPLEFT", f.stanceTab, "TOPRIGHT", -1, 0)
f.stanceCol:SetPoint("BOTTOMLEFT", f.stanceTab, "BOTTOMRIGHT", -1, 0)
f.stanceCol:SetWidth(1)
f.stanceCol:Hide()

f.stanceTab:SetFrameRef("col", f.stanceCol)
f.stanceTab:SetAttribute("_onclick", [=[
    local col = self:GetFrameRef("col")
    if col:IsShown() then col:Hide() else col:Show() end
]=])
f.stanceTab:SetScript("OnEnter", function(self)
    self.arrow:SetVertexColor(1, 1, 1)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local label = ns.Stances.Label(Tank.kit)
    GameTooltip:SetText(label, 1, 1, 1)
    GameTooltip:AddLine("Show or hide your " .. label:lower() .. ". Works in combat.", nil, nil, nil, true)
    GameTooltip:Show()
end)
f.stanceTab:SetScript("OnLeave", function(self)
    self.arrow:SetVertexColor(MUTED[1], MUTED[2], MUTED[3])
    GameTooltip:Hide()
end)

-- Points right (away from the HUD) to open, left to close.
local function StanceArrow(open)
    f.stanceTab.arrow:SetRotation(open and math.pi or 0)
end
StanceArrow(false)
-- These also run when the whole HUD shows or hides; the column's own shown
-- flag (IsShown) only changes when the tab or Stances.lua flips it.
f.stanceCol:SetScript("OnShow", function(self)
    if TF.db then TF.db.stances.open = true end
    StanceArrow(self:IsShown())
    -- Highlights and cooldowns aren't drawn while it's closed.
    if ns.Stances and ns.Stances.Refresh then ns.Stances.Refresh() end
end)
f.stanceCol:SetScript("OnHide", function(self)
    -- Stances.lua hides the tab first when there's nothing to show; that
    -- isn't a choice to remember.
    if TF.db and not self:IsShown() and f.stanceTab:IsShown() then TF.db.stances.open = false end
    StanceArrow(self:IsShown())
end)

-- With the portrait on, the bars start to its right; off, at the panel edge.
local function LayoutTop()
    local show = TF.db and TF.db.hud.portrait ~= false
    f.portrait:SetShown(show)
    f.leader:ClearAllPoints()
    f.leader:SetPoint("TOPLEFT", show and f.portrait or f, "TOPLEFT", -4, 5)
    f.health:ClearAllPoints()
    f.health:SetPoint("TOPRIGHT", -PAD, -PAD - 2)
    if show then
        f.health:SetPoint("TOPLEFT", f.portrait, "TOPRIGHT", 4, 0)
    else
        f.health:SetPoint("TOPLEFT", PAD, -PAD - 2)
    end
end

local function StanceCount() return ns.Stances and ns.Stances.count or 0 end

-- Size and scale of the (protected) panel: out of combat only.
local sizeQueued = false
local function SizeTop()
    if InCombatLockdown() then
        if not sizeQueued then
            sizeQueued = true
            TF:AfterCombat(function()
                sizeQueued = false
                SizeTop()
            end)
        end
        return
    end
    f:SetHeight(HEIGHT)
    f:SetScale(TF.db.scale or 1)
    Style.FitAnchor("hud")
end

Style.Movable(f, "hud", "Tank HUD", { "CENTER", "CENTER", -300, -110 })

-- Building -------------------------------------------------------------------

function HUD:UpdatePortrait()
    if SetPortraitTexture then pcall(SetPortraitTexture, f.portrait.tex, "player") end
end

--- Set up the bars for the current kit.
function HUD:Build()
    LayoutTop()
    HUD:UpdatePortrait()
    local kit = Tank.kit
    local ptype = kit and API.PowerType(kit.power) or API.UnitPowerType("player") or 1
    f.power.ptype = ptype
    local pc = Style.PowerColor(ptype)
    f.power:SetStatusBarColor(pc[1], pc[2], pc[3])
    f.power.label:SetText(kit and kit.power or "Power")
    SizeTop()
    HUD:UpdateHealth()
    HUD:UpdatePower()
end

-- Updating -------------------------------------------------------------------

function HUD:UpdateHealth()
    local bar = f.health
    local cur, max = API.UnitHealthRaw("player"), API.UnitHealthMaxRaw("player")
    API.SetBarValues(bar, 0, max, cur)
    f.portrait.tex:SetDesaturated(API.IsDeadOrGhost("player") and true or false)
    -- Just the percentage, like the healer and party frames. PercentDisplay
    -- reads it directly out of combat and through the game when it's secret.
    local pct = API.PercentDisplay("player")
    if not (pct and pcall(bar.value.SetFormattedText, bar.value, "%.0f%%", pct)) then
        -- No percentage from this client: the abbreviated amount, else nothing.
        local a = API.AbbrevDisplay(cur)
        if not (a and pcall(bar.value.SetFormattedText, bar.value, "%s", a)) then bar.value:SetText("") end
    end
end

function HUD:UpdatePower()
    local bar = f.power
    local ptype = bar.ptype or 1
    local cur, max = API.UnitPowerRaw("player", ptype), API.UnitPowerMaxRaw("player", ptype)
    API.SetBarValues(bar, 0, max, cur)
    local plain = API.PlainNumber(cur)
    if plain then
        bar.value:SetFormattedText("%d", plain)
    elseif not (type(cur) == "number" and pcall(bar.value.SetFormattedText, bar.value, "%d", cur)) then
        bar.value:SetText("")
    end
end

-- Visibility -----------------------------------------------------------------

function HUD:UpdateLeader()
    f.leader:SetShown(IsInGroup() and API.IsLeader("player"))
end

--- Whether the HUD shows: "full" while tanking or unlocked; "compact" while
--- not tanking but it stays up so you can click back into your tanking
--- stance (it looks the same); "hidden" otherwise.
---@param enabled boolean HUD turned on
---@param hasKit boolean this class has a tank kit
---@param isTank boolean tanking right now
---@param unlocked boolean frames unlocked with /tf unlock
---@param showIdle boolean stay up, compact, when not tanking
---@param hasStances boolean stance buttons on the HUD
---@return "full"|"compact"|"hidden"
function HUD.Mode(enabled, hasKit, isTank, unlocked, showIdle, hasStances)
    if not (enabled and hasKit) then return "hidden" end
    if isTank or unlocked then return "full" end
    if showIdle and hasStances then return "compact" end
    return "hidden"
end

-- The panel is protected (it holds the stance flyout), so the game
-- blocks showing or hiding it in combat. In combat a HUD that should hide
-- only goes transparent, one that should appear waits, and both are settled
-- once the fight ends. Same as the healer panel.
local shownQueued = false
local function ApplyShown(show)
    if not InCombatLockdown() then
        if f:IsShown() ~= show then f:SetShown(show) end
        HUD.combatHidden = nil
        return
    end
    if show then
        if f:IsShown() then
            HUD.combatHidden = nil
            return
        end
    elseif f:IsShown() and not HUD.combatHidden then
        HUD.combatHidden = true
    elseif not f:IsShown() then
        return
    end
    if not shownQueued then
        shownQueued = true
        TF:AfterCombat(function()
            shownQueued = false
            HUD:Refresh()
        end)
    end
end

--- Show the HUD while tanking (or unlocked, or compact when not) and it is enabled.
function HUD:Refresh()
    HUD:UpdateLeader()
    local cfg = TF.db.hud
    local mode = HUD.Mode(cfg.enabled, Tank.kit ~= nil, Tank.isTank, Style.IsUnlocked(), cfg.showIdle,
        StanceCount() > 0)
    HUD.mode = mode
    ApplyShown(mode ~= "hidden")
    f:SetAlpha(HUD.combatHidden and 0 or Style.FrameAlpha(cfg))
end

TF:On("KIT_CHANGED", function() HUD:Build() HUD:Refresh() end)
TF:On("TANK_CHANGED", function() HUD:Refresh() end)
TF:On("COMBAT", function() HUD:Refresh() end)
TF:On("UNLOCKED", function() HUD:Refresh() end)
TF:On("ENTERING_WORLD", function() HUD:UpdatePortrait() end)
TF:On("STANCES_CHANGED", function() SizeTop() HUD:Refresh() end)
TF:On("LOADED", function()
    if not InCombatLockdown() then f:SetScale(TF.db.scale or 1) end
    LayoutTop()
    -- 1.0.0 had a single "fade out of combat" switch; keep its choice.
    local cfg = TF.db.hud
    if cfg.fadeOutOfCombat == false then cfg.oocAlpha = cfg.alpha or 1 end
    cfg.fadeOutOfCombat = nil
    -- The mitigation and cooldown panel (and its collapse switch) is gone.
    cfg.collapsed = nil
end)
TF:RegisterEvent("PARTY_LEADER_CHANGED", function() HUD:UpdateLeader() end)
TF:RegisterEvent("GROUP_ROSTER_UPDATE", function() HUD:UpdateLeader() end)
TF:RegisterUnitEvent("UNIT_PORTRAIT_UPDATE", { "player" }, function() HUD:UpdatePortrait() end)
TF:RegisterUnitEvent("UNIT_HEALTH", { "player" }, function() HUD:UpdateHealth() end)
TF:RegisterUnitEvent("UNIT_MAXHEALTH", { "player" }, function() HUD:UpdateHealth() end)
-- UNIT_POWER_FREQUENT covers every change UNIT_POWER_UPDATE does (and sooner);
-- listening to both drew the bar twice per change. The slower one only without it.
if not TF:RegisterUnitEvent("UNIT_POWER_FREQUENT", { "player" }, function() HUD:UpdatePower() end) then
    TF:RegisterUnitEvent("UNIT_POWER_UPDATE", { "player" }, function() HUD:UpdatePower() end)
end
TF:RegisterUnitEvent("UNIT_MAXPOWER", { "player" }, function() HUD:UpdatePower() end)
TF:RegisterUnitEvent("UNIT_DISPLAYPOWER", { "player" }, function() HUD:UpdatePower() end)
