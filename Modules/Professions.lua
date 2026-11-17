-- Modules/Professions.lua
-- A button on the edge of the minimap that pops out your profession spells
-- (Blacksmithing, Smelting, Cooking...), so they don't need action bar slots.
--
-- The rows are secure buttons, because casting a spell is protected. Secure
-- frames can't be shown, hidden or changed in combat, so the list is only
-- built and opened out of combat, and it closes as combat starts.
local _, ns = ...
local TF = ns.TF
local Style = ns.Style
local API = ns.API

local ROW_H, ROW_W, PAD = 22, 170, 6
local DEFAULT_ICON = "Interface\\Icons\\Trade_BlackSmithing"

local button, flyout
local rows = {}

local function Settings() return TF.db and TF.db.professions end

-- Spells ---------------------------------------------------------------------

-- One spellbook slot as { spellID, name, icon }, or nil for passives and gaps.
local function SpellAt(slot)
    local SB = _G.C_SpellBook
    if SB and type(SB.GetSpellBookItemInfo) == "function" then
        local bank = _G.Enum and _G.Enum.SpellBookSpellBank and _G.Enum.SpellBookSpellBank.Player or 0
        local ok, info = pcall(SB.GetSpellBookItemInfo, slot, bank)
        if not ok or type(info) ~= "table" or info.isPassive then return nil end
        local id = API.PlainNumber(info.spellID or info.actionID)
        if not id then return nil end
        return { spellID = id, name = API.PlainString(info.name) or API.GetSpellName(id),
            icon = info.iconID or API.GetSpellIcon(id) }
    end
    -- Older spellbook API.
    if type(_G.GetSpellBookItemInfo) == "function" then
        local ok, kind, id = pcall(_G.GetSpellBookItemInfo, slot, "spell")
        if not ok or kind ~= "SPELL" or not API.PlainNumber(id) then return nil end
        if type(_G.IsPassiveSpell) == "function" and _G.IsPassiveSpell(slot, "spell") then return nil end
        return { spellID = id, name = API.GetSpellName(id), icon = API.GetSpellIcon(id) }
    end
    return nil
end

-- Every castable profession spell, primary professions first, plus the icon
-- of the first profession.
local function ProfessionSpells()
    local list, firstIcon = {}, nil
    if type(_G.GetProfessions) ~= "function" or type(_G.GetProfessionInfo) ~= "function" then
        return list, firstIcon
    end
    local ok, prof1, prof2, arch, fish, cook = pcall(_G.GetProfessions)
    if not ok then return list, firstIcon end
    for _, index in ipairs({ prof1 or false, prof2 or false, cook or false, fish or false, arch or false }) do
        if index then
            local ok2, _, icon, _, _, numAbilities, spellOffset = pcall(_G.GetProfessionInfo, index)
            if ok2 then
                firstIcon = firstIcon or icon
                for i = 1, (API.PlainNumber(numAbilities) or 0) do
                    local spell = SpellAt((API.PlainNumber(spellOffset) or 0) + i)
                    if spell and spell.name then list[#list + 1] = spell end
                end
            end
        end
    end
    return list, firstIcon
end

-- Flyout ---------------------------------------------------------------------

local function Row(i)
    if rows[i] then return rows[i] end
    local r = CreateFrame("Button", nil, flyout, "SecureActionButtonTemplate")
    r:SetSize(ROW_W, ROW_H)
    r:SetPoint("TOPLEFT", PAD, -PAD - 2 - (i - 1) * ROW_H)
    r:RegisterForClicks("AnyUp", "AnyDown")
    r:SetAttribute("type", "spell")
    r.hl = Style.Flat(r, "HIGHLIGHT", { Style.colors.accent[1], Style.colors.accent[2], Style.colors.accent[3], 0.2 })
    r.hl:SetAllPoints()
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(ROW_H - 4, ROW_H - 4)
    r.icon:SetPoint("LEFT", 2, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.text = Style.Text(r, 12)
    r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.text:SetPoint("RIGHT", -4, 0)
    r.text:SetJustifyH("LEFT")
    -- Close once the click has finished, whether the game casts on key down or up.
    r:SetScript("PostClick", function(_, _, down)
        if not down and not InCombatLockdown() then flyout:Hide() end
    end)
    rows[i] = r
    return r
end

local function BuildFlyout()
    flyout = Style.Panel(UIParent, "TankForgeUIProfessions")
    flyout:SetFrameStrata("DIALOG")
    flyout:SetClampedToScreen(true)
    flyout:EnableMouse(true)
    flyout.empty = Style.Text(flyout, 12)
    flyout.empty:SetPoint("TOPLEFT", PAD + 2, -PAD - 6)
    flyout.empty:SetTextColor(unpack(Style.colors.muted))
    flyout.empty:SetText("No professions learned")
    flyout:Hide()
end

-- Opens on whichever side of the button faces the middle of the screen.
local function PlaceFlyout()
    local x, y = button:GetCenter()
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    local v = (y or 0) > h / 2 and "TOP" or "BOTTOM"
    local right = (x or 0) > w / 2
    flyout:ClearAllPoints()
    flyout:SetPoint(v .. (right and "RIGHT" or "LEFT"), button, v .. (right and "LEFT" or "RIGHT"), right and -2 or 2, 0)
end

-- Out of combat only: sets secure attributes and shows secure frames.
local function OpenFlyout()
    if not flyout then BuildFlyout() end
    local spells = ProfessionSpells()
    for i, spell in ipairs(spells) do
        local r = Row(i)
        r:SetAttribute("spell", spell.spellID)
        r.icon:SetTexture(spell.icon or DEFAULT_ICON)
        r.text:SetText(spell.name)
        r:Show()
    end
    for i = #spells + 1, #rows do rows[i]:Hide() end
    flyout.empty:SetShown(#spells == 0)
    flyout:SetSize(ROW_W + 2 * PAD, math.max(#spells, 1) * ROW_H + 2 * PAD + 4)
    PlaceFlyout()
    flyout:Show()
end

local function CloseFlyout()
    if flyout and flyout:IsShown() and not InCombatLockdown() then flyout:Hide() end
end

-- Minimap button -------------------------------------------------------------

local function PlaceButton()
    local s = Settings()
    local angle = math.rad(s and s.angle or 225)
    local radius = (Minimap:GetWidth() or 140) / 2 + 5
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function UpdateIcon()
    if not button then return end
    local _, icon = ProfessionSpells()
    button.icon:SetTexture(icon or DEFAULT_ICON)
end

local function DragUpdate()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    local dx, dy = px / scale - mx, py / scale - my
    local atan2 = math.atan2 or math.atan
    TF.db.professions.angle = math.deg(atan2(dy, dx)) % 360
    PlaceButton()
end

local function BuildButton()
    -- Same geometry as the common minimap button library, so it lines up with other addons' buttons.
    button = CreateFrame("Button", "TankForgeUIProfessionsButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(50, 50)
    border:SetPoint("TOPLEFT")
    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(24, 24)
    bg:SetPoint("CENTER")
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(18, 18)
    button.icon:SetPoint("CENTER")
    if button.CreateMaskTexture then
        local mask = button:CreateMaskTexture()
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(button.icon)
        button.icon:AddMaskTexture(mask)
    else
        button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end

    button:SetScript("OnClick", function()
        if InCombatLockdown() then
            TF:Print("professions: not in combat.")
            return
        end
        if flyout and flyout:IsShown() then CloseFlyout() else OpenFlyout() end
    end)
    button:SetScript("OnDragStart", function(self)
        CloseFlyout()
        self:SetScript("OnUpdate", DragUpdate)
    end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Professions", 1, 1, 1)
        GameTooltip:AddLine("Click: open    Drag: move around the minimap", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    PlaceButton()
    UpdateIcon()
end

-- Wiring ---------------------------------------------------------------------

--- Show or hide the minimap professions button from the settings.
function TF:ApplyProfessions()
    if not Minimap then return end
    local s = Settings()
    if s and s.enabled then
        if not button then BuildButton() end
        PlaceButton()
        button:Show()
    elseif button then
        CloseFlyout()
        button:Hide()
    end
end

TF:On("LOGIN", function() TF:ApplyProfessions() end)

-- Hiding secure frames is still allowed while PLAYER_REGEN_DISABLED is handled.
TF:On("COMBAT", function(inCombat)
    if inCombat and flyout and flyout:IsShown() then flyout:Hide() end
end)

TF:RegisterEvent("SKILL_LINES_CHANGED", function() UpdateIcon() end)

TF:AddCommand("prof", function()
    TF.db.professions.enabled = not TF.db.professions.enabled
    TF:ApplyProfessions()
    TF:Print("professions button: " .. (TF.db.professions.enabled and "|cff40ff40on|r" or "|cffff4040off|r"))
end, "- toggle the professions button on the minimap", { group = "Frames" })
