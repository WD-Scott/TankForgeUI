-- Modules/Stances.lua
-- Your stance / form buttons, stacked in a flyout off the tank HUD's right
-- edge, in place of Blizzard's stance bar.
--
-- The buttons are secure action buttons, so stances can be switched
-- mid-fight, and the HUD's tab opens and closes the flyout through a secure
-- handler, so that works in combat too. What can't happen in combat is
-- changing which spell a button casts, or adding, moving or hiding buttons,
-- so those wait until the fight ends. Because the flyout hangs off the HUD,
-- the HUD's panel is protected (see Modules/HUD.lua).
local _, ns = ...
local TF = ns.TF
local Style = ns.Style
local API = ns.API

local Stances = { count = 0 }
ns.Stances = Stances

-- Buttons shrink to fit the HUD's height, up to SIZE. TOP clears the
-- column's border and accent line; INSET is the side margin.
local SIZE, GAP, TOP, BOTTOM, INSET = 24, 2, 4, 3, 3
Stances.SIZE = SIZE
local C = Style.colors

local buttons = {}
Stances.buttons = buttons

--- True when the stance buttons should be in the HUD: they're turned on, the
--- HUD is on, and this class has a tank kit (so it has a HUD at all).
---@return boolean
function Stances.Wanted()
    local db = TF.db
    if not (db and db.stances.enabled and db.hud.enabled) then return false end
    return ns.Tank ~= nil and ns.Tank.kit ~= nil
end

--- Button size that stacks `count` buttons inside a column `height` tall.
---@param count integer
---@param height number column height (the HUD's)
---@return integer
function Stances.Fit(count, height)
    if count <= 0 then return SIZE end
    local fit = math.floor((height - TOP - BOTTOM - (count - 1) * GAP) / count)
    return math.max(1, math.min(SIZE, fit))
end

--- What the flyout holds for this kit, for its tooltip: "Stances", "Forms"...
---@param kit Kit|nil
---@return string
function Stances.Label(kit)
    return kit and kit.flyout or "Stances"
end

-- Buttons --------------------------------------------------------------------

local function HUDFrame() return ns.HUD and ns.HUD.frame end
local function Col() local f = HUDFrame() return f and f.stanceCol end

local function ButtonAt(i)
    if buttons[i] then return buttons[i] end
    local b = CreateFrame("Button", "TankForgeUIStance" .. i, Col(), "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type", "spell")
    b.index = i

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    Style.Outline(b, { 0, 0, 0, 1 })

    local ok, cd = pcall(CreateFrame, "Cooldown", nil, b, "CooldownFrameTemplate")
    if ok and cd then
        cd:SetAllPoints(b.icon)
        if cd.SetDrawEdge then cd:SetDrawEdge(false) end
        if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
        b.cooldown = cd
    end

    -- Lit-up frame for the form you're in.
    b.active = b:CreateTexture(nil, "OVERLAY")
    b.active:SetAllPoints(b.icon)
    b.active:SetTexture(Style.FLAT)
    b.active:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.25)
    b.active:SetBlendMode("ADD")
    b.active:Hide()

    b.hl = Style.Flat(b, "HIGHLIGHT", { 1, 1, 1, 0.15 })
    b.hl:SetAllPoints(b.icon)

    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if not (GameTooltip.SetShapeshift and pcall(GameTooltip.SetShapeshift, GameTooltip, self.index)) then
            if self.spellID and GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(self.spellID) end
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    buttons[i] = b
    return b
end

-- Highlight, usability and cooldowns. Not protected, so this runs any time.
-- The events behind it (cooldowns, usability) fire many times a second in
-- combat, so it only reads while the column is on screen, and only touches a
-- widget when its value changed. The column's OnShow (HUD.lua) brings it up
-- to date when it opens.
local formsBuf = {}
local function Refresh()
    if Stances.count == 0 then return end
    local col = Col()
    if not (col and col:IsVisible()) then return end
    local forms = API.GetShapeshiftForms(formsBuf)
    for i = 1, Stances.count do
        local b, form = buttons[i], forms[i]
        if b and form then
            if form.icon and b.tfIcon ~= form.icon then
                b.tfIcon = form.icon
                b.icon:SetTexture(form.icon)
            end
            local active = form.active == true
            if b.tfActive ~= active then
                b.tfActive = active
                b.active:SetShown(active)
                if active then
                    Style.SetBorderColor(b, unpack(Style.HOVER))
                else
                    Style.SetBorderColor(b, 0, 0, 0, 1)
                end
            end
            local unusable = form.castable == false
            if b.tfUnusable ~= unusable then
                b.tfUnusable = unusable
                b.icon:SetDesaturated(unusable)
            end
            if b.cooldown and _G.GetShapeshiftFormCooldown then
                local okCd, start, duration = pcall(_G.GetShapeshiftFormCooldown, i)
                if okCd and start and duration then
                    local ps, pd = API.PlainNumber(start), API.PlainNumber(duration)
                    -- Secret values can't be compared: those are always handed on.
                    if not (ps and pd and b.tfCdStart == ps and b.tfCdDuration == pd) then
                        b.tfCdStart, b.tfCdDuration = ps, pd
                        pcall(b.cooldown.SetCooldown, b.cooldown, start, duration)
                    end
                end
            end
        end
    end
end
Stances.Refresh = Refresh

-- Out of combat only: sets secure attributes, stacks the buttons (sized to
-- the HUD's height, centered) and sizes, shows or hides the flyout. Fires
-- STANCES_CHANGED with the new count.
local function Rebuild()
    local count = 0
    local col = Col()
    local forms = {}
    if Stances.Wanted() and col then
        for i, form in ipairs(API.GetShapeshiftForms()) do
            if form.spellID then
                forms[i] = form
                count = i
            end
        end
    end
    local height = ns.HUD and ns.HUD.HEIGHT or 0
    local size = Stances.Fit(count, height)
    local stack = count * size + math.max(0, count - 1) * GAP
    local top = TOP + math.floor((height - TOP - BOTTOM - stack) / 2)
    for i = 1, count do
        local form = forms[i]
        if form then
            local b = ButtonAt(i)
            b.spellID = form.spellID
            b:SetAttribute("spell", form.spellID)
            b:SetSize(size, size)
            b:ClearAllPoints()
            b:SetPoint("TOP", col, "TOP", 0, -(top + (i - 1) * (size + GAP)))
            b:Show()
        elseif buttons[i] then
            buttons[i]:Hide()
        end
    end
    for i = count + 1, #buttons do buttons[i]:Hide() end
    if col then
        local tab = HUDFrame().stanceTab
        col:SetWidth(size + 2 * INSET)
        -- The tab goes first, so hiding an empty column isn't saved as "closed".
        tab:SetShown(count > 0)
        col:SetShown(count > 0 and TF.db.stances.open ~= false)
    end
    local changed = Stances.count ~= count
    Stances.count = count
    Refresh()
    if changed then TF:Fire("STANCES_CHANGED", count) end
end

-- Blizzard's stance bar ------------------------------------------------------
--
-- Hidden by moving it under a hidden frame, out of combat. Blizzard can show
-- it all it likes; it stays invisible with its parent. Nothing else here calls
-- the bar's methods or writes its fields: doing that (Show/Hide/SetAlpha and
-- hooks on them) tainted Blizzard's stance bar updates, so in combat the game
-- blocked them and blamed TankForgeUI, and the taint spread to the action bars.
-- It stays hidden in Edit Mode too; /tf stances brings it back.

local hiddenParent = Style.hiddenParent
local blizzParent           -- the bar's parent before it was moved
local blizzQueued = false

local function BlizzBar() return _G.StanceBar or _G.StanceBarFrame end

local ApplyBlizz
local function QueueBlizz()
    if blizzQueued then return end
    blizzQueued = true
    TF:AfterCombat(function()
        blizzQueued = false
        ApplyBlizz()
    end)
end

ApplyBlizz = function()
    local bar = BlizzBar()
    if not bar then return end
    if InCombatLockdown() then
        QueueBlizz()
        return
    end
    local parent = bar:GetParent()
    if Stances.Wanted() then
        if parent ~= hiddenParent then
            blizzParent = parent or UIParent
            bar:SetParent(hiddenParent)
        end
    elseif parent == hiddenParent then
        bar:SetParent(blizzParent or UIParent)
        blizzParent = nil
    end
end

-- Wiring ---------------------------------------------------------------------

local applyQueued = false
--- Apply the stance button setting (deferred until out of combat).
function TF:ApplyStances()
    if InCombatLockdown() then
        if not applyQueued then
            applyQueued = true
            TF:AfterCombat(function()
                applyQueued = false
                TF:ApplyStances()
            end)
        end
        ApplyBlizz()
        return
    end
    Rebuild()
    ApplyBlizz()
end

TF:On("LOGIN", function() TF:ApplyStances() end)
TF:On("KIT_CHANGED", function() TF:ApplyStances() end)
-- In case anything put the bar back during a loading screen.
TF:On("ENTERING_WORLD", function() ApplyBlizz() end)

-- New forms are learned out of combat; anything that arrives mid-fight waits.
for _, ev in ipairs({ "UPDATE_SHAPESHIFT_FORMS", "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB" }) do
    TF:RegisterEvent(ev, function() TF:ApplyStances() end)
end
-- These come in bursts (ACTIONBAR_UPDATE_USABLE on most rage changes,
-- SPELL_UPDATE_COOLDOWN several times per global cooldown): refresh once per frame.
local refreshSoon = TF:Coalesce(Refresh)
for _, ev in ipairs({ "UPDATE_SHAPESHIFT_FORM", "UPDATE_SHAPESHIFT_USABLE", "UPDATE_SHAPESHIFT_COOLDOWN",
    "SPELL_UPDATE_COOLDOWN", "ACTIONBAR_UPDATE_USABLE" }) do
    TF:RegisterEvent(ev, refreshSoon)
end

TF:AddCommand("stances", function()
    TF.db.stances.enabled = not TF.db.stances.enabled
    TF:ApplyStances()
    local msg = "stance buttons: " .. (TF.db.stances.enabled and "|cff40ff40on|r" or "|cffff4040off|r")
    if InCombatLockdown() then msg = msg .. " (after combat)" end
    TF:Print(msg)
end, "- toggle the HUD's stance flyout (off brings Blizzard's stance bar back)", { group = "Frames" })
