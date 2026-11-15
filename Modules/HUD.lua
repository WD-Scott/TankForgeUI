-- Modules/HUD.lua
-- The tank HUD: health, rage (or mana), a timer bar for each active
-- mitigation (Shield Block first), and your defensive and utility cooldowns.
local _, ns = ...
local TF = ns.TF
local API = ns.API
local Style = ns.Style
local Tank = ns.Tank

local HUD = {}
ns.HUD = HUD

local WIDTH = 230
local PAD = 6
local ICON = 28
local ICON_GAP = 4

local f = Style.Panel(UIParent, "TankForgeUIHUD")
f:SetSize(WIDTH, 100)
f:Hide()
HUD.frame = f

f.health = Style.Bar(f, 20, Style.colors.health, 12)
f.health:SetPoint("TOPLEFT", PAD, -PAD - 2)
f.health:SetPoint("TOPRIGHT", -PAD, -PAD - 2)
f.health.label:SetText("Health")

f.power = Style.Bar(f, 16, Style.colors.rage, 11)
f.power:SetPoint("TOPLEFT", f.health, "BOTTOMLEFT", 0, -3)
f.power:SetPoint("TOPRIGHT", f.health, "BOTTOMRIGHT", 0, -3)

-- Your own crown goes here, since your player frame is hidden.
f.leader = Style.LeaderBadge(f, 16)

f.amRows = {}
f.iconButtons = {}

local anchor = Style.Movable(f, "hud", "Tank HUD", { "CENTER", "CENTER", -300, -110 })

-- Building -------------------------------------------------------------------

local function AMRow(i)
    local row = f.amRows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, f)
    row:SetHeight(20)
    row.icon = Style.Icon(row, 20)
    row.icon:SetPoint("LEFT")
    row.bar = Style.Bar(row, 20, Style.colors.mitigation, 11)
    row.bar:SetPoint("LEFT", row.icon, "RIGHT", 3, 0)
    row.bar:SetPoint("RIGHT")
    f.amRows[i] = row
    return row
end

local function IconButton(i)
    local b = f.iconButtons[i]
    if b then return b end
    b = Style.Icon(f, ICON)
    b:EnableMouse(true)
    b:SetScript("OnEnter", function(self)
        if not self.spell then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if GameTooltip.SetSpellByID then pcall(GameTooltip.SetSpellByID, GameTooltip, self.spell) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.iconButtons[i] = b
    return b
end

function HUD:Build()
    local y = PAD + 2 + 20 + 3 + 16
    local kit = Tank.kit
    local ptype = kit and API.PowerType(kit.power) or API.UnitPowerType("player") or 1
    f.power.ptype = ptype
    local pc = Style.PowerColor(ptype)
    f.power:SetStatusBarColor(pc[1], pc[2], pc[3])
    f.power.label:SetText(kit and kit.power or "Power")

    for _, row in ipairs(f.amRows) do row:Hide() end
    local n = 0
    for _, entry in ipairs(Tank.am) do
        if entry.known then
            n = n + 1
            local row = AMRow(n)
            row.entry = entry
            row.icon.icon:SetTexture(API.GetSpellIcon(entry.spell))
            row.bar.value.tfText = nil
            row.bar.label:SetText(API.GetSpellName(entry.spell) or "?")
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(y + 4))
            row:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -(y + 4))
            row:Show()
            y = y + 4 + 20
        end
    end

    for _, b in ipairs(f.iconButtons) do b:Hide() end
    local perRow = math.floor((WIDTH - 2 * PAD + ICON_GAP) / (ICON + ICON_GAP))
    local count = #Tank.icons
    if count > 0 then y = y + 6 end
    for i, entry in ipairs(Tank.icons) do
        local b = IconButton(i)
        b.entry, b.spell = entry, entry.spell
        b.icon:SetTexture(API.GetSpellIcon(entry.spell))
        b.lastReady = nil
        local col, line = (i - 1) % perRow, math.floor((i - 1) / perRow)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + col * (ICON + ICON_GAP), -(y + line * (ICON + ICON_GAP)))
        b:Show()
    end
    if count > 0 then
        y = y + math.ceil(count / perRow) * (ICON + ICON_GAP) - ICON_GAP
    end
    f:SetHeight(y + PAD)
    f:SetScale(TF.db.scale or 1)
    Style.FitAnchor("hud")
    HUD:UpdateHealth()
    HUD:UpdatePower()
    HUD:UpdateCooldowns()
    HUD:UpdateTimers()
end

-- Updating -------------------------------------------------------------------

function HUD:UpdateHealth()
    local bar = f.health
    local cur, max = API.UnitHealthRaw("player"), API.UnitHealthMaxRaw("player")
    API.SetBarValues(bar, 0, max, cur)
    local pc, pm = API.PlainNumber(cur), API.PlainNumber(max)
    if pc and pm and pm > 0 then
        bar.value:SetFormattedText("%s / %s  %d%%", API.Abbrev(pc), API.Abbrev(pm), pc / pm * 100)
        return
    end
    -- Secret in combat: let the game abbreviate what we can't read.
    local a, m = API.AbbrevDisplay(cur), API.AbbrevDisplay(max)
    local pct = API.PercentDisplay("player")
    local shown = false
    if a and m and pct then shown = pcall(bar.value.SetFormattedText, bar.value, "%s / %s  %.0f%%", a, m, pct) end
    if not shown and pct then shown = pcall(bar.value.SetFormattedText, bar.value, "%.0f%%", pct) end
    if not shown and a then shown = pcall(bar.value.SetFormattedText, bar.value, "%s", a) end
    if not shown then bar.value:SetText("") end
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

function HUD:UpdateCooldowns()
    for _, b in ipairs(f.iconButtons) do
        if b:IsShown() and b.cooldown then API.ApplySpellCooldown(b.cooldown, b.spell) end
    end
    for _, row in ipairs(f.amRows) do
        if row:IsShown() and row.icon.cooldown and row.entry.def.cd then
            API.ApplySpellCooldown(row.icon.cooldown, row.entry.spell)
        end
    end
end

local C = Style.colors
function HUD:UpdateTimers()
    local now = API.Now()
    local hit = Tank:BeingHit(now)
    for _, row in ipairs(f.amRows) do
        if row:IsShown() then
            local entry = row.entry
            local dur = entry.def.duration or 1
            local left = Tank:Remaining(entry, now)
            local bar = row.bar
            bar:SetMinMaxValues(0, dur)
            bar:SetValue(left)
            if left > 0 then
                bar:SetStatusBarColor(C.mitigation[1], C.mitigation[2], C.mitigation[3])
                Style.SetText(bar.value, string.format("%.1fs", left))
                bar.value:SetTextColor(unpack(C.text))
                bar.bg:SetVertexColor(unpack(C.barBg))
            elseif Tank:IsReady(entry, now) then
                local urgent = hit and entry == Tank.primary and TF.inCombat
                Style.SetText(bar.value, urgent and "DOWN" or "Ready")
                bar.value:SetTextColor(unpack(urgent and C.bad or C.good))
                if urgent then
                    bar.bg:SetVertexColor(0.45, 0.08, 0.08, 0.95)
                else
                    bar.bg:SetVertexColor(unpack(C.barBg))
                end
            else
                Style.SetText(bar.value, string.format("%.1fs", Tank:CooldownLeft(entry, now)))
                bar.value:SetTextColor(unpack(C.muted))
                bar.bg:SetVertexColor(unpack(C.barBg))
            end
        end
    end
    for _, b in ipairs(f.iconButtons) do
        if b:IsShown() then
            local ready = Tank:IsReady(b.entry, now)
            if b.lastReady ~= ready then
                b.lastReady = ready
                b.icon:SetDesaturated(not ready)
                b.icon:SetAlpha(ready and 1 or 0.65)
            end
        end
    end
    -- The border turns red while you're being hit with your mitigation down.
    local primary = Tank.primary
    if TF.inCombat and hit and primary and primary.known and not Tank:IsActive(primary, now) then
        Style.SetBorderColor(f, 0.9, 0.15, 0.15, 1)
    else
        Style.SetBorderColor(f, 0, 0, 0, 1)
    end
end

-- Visibility -----------------------------------------------------------------

function HUD:UpdateLeader()
    f.leader:SetShown(IsInGroup() and API.IsLeader("player"))
end

function HUD:Refresh()
    HUD:UpdateLeader()
    local show = TF.db.hud.enabled and (Tank.isTank or Style.IsUnlocked()) and Tank.kit ~= nil
    f:SetShown(show and true or false)
    f:SetAlpha(Style.FrameAlpha(TF.db.hud))
end

local elapsed = 0
f:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < 0.1 then return end
    elapsed = 0
    HUD:UpdateTimers()
end)

TF:On("KIT_CHANGED", function() HUD:Build() HUD:Refresh() end)
TF:On("TANK_CHANGED", function() HUD:Refresh() end)
TF:On("COMBAT", function() HUD:Refresh() HUD:UpdateCooldowns() end)
TF:On("UNLOCKED", function() HUD:Refresh() end)
TF:On("CAST", function() HUD:UpdateCooldowns() end)
TF:On("LOADED", function()
    f:SetScale(TF.db.scale or 1)
    -- 1.0.0 had a single "fade out of combat" switch; keep its choice.
    local cfg = TF.db.hud
    if cfg.fadeOutOfCombat == false then cfg.oocAlpha = cfg.alpha or 1 end
    cfg.fadeOutOfCombat = nil
end)
TF:RegisterEvent("SPELL_UPDATE_COOLDOWN", function() HUD:UpdateCooldowns() end)
TF:RegisterEvent("PARTY_LEADER_CHANGED", function() HUD:UpdateLeader() end)
TF:RegisterEvent("GROUP_ROSTER_UPDATE", function() HUD:UpdateLeader() end)

TF:RegisterUnitEvent("UNIT_HEALTH", { "player" }, function() HUD:UpdateHealth() end)
TF:RegisterUnitEvent("UNIT_MAXHEALTH", { "player" }, function() HUD:UpdateHealth() end)
TF:RegisterUnitEvent("UNIT_POWER_UPDATE", { "player" }, function() HUD:UpdatePower() end)
TF:RegisterUnitEvent("UNIT_POWER_FREQUENT", { "player" }, function() HUD:UpdatePower() end)
TF:RegisterUnitEvent("UNIT_MAXPOWER", { "player" }, function() HUD:UpdatePower() end)
TF:RegisterUnitEvent("UNIT_DISPLAYPOWER", { "player" }, function() HUD:UpdatePower() end)
