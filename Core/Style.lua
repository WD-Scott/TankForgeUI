-- Core/Style.lua
-- One look for every TankForgeUI frame: dark translucent panels with a thin
-- accent line, flat bars, square icons, and movers for /tf unlock.
local _, ns = ...
local TF = ns.TF

local Style = {}
ns.Style = Style

local FLAT = "Interface\\Buttons\\WHITE8X8"
Style.FLAT = FLAT

-- Where Blizzard frames go to be hidden: reparented here out of combat, they
-- stay invisible whatever Blizzard's code does, and nothing on them is touched
-- (calling their Show/Hide or writing fields taints them; see CLAUDE.md).
Style.hiddenParent = CreateFrame("Frame", "TankForgeUIHiddenParent", UIParent)
Style.hiddenParent:Hide()

Style.colors = {
    bg      = { 0.05, 0.06, 0.08, 0.82 },
    barBg   = { 0.12, 0.13, 0.16, 0.9 },
    border  = { 0, 0, 0, 1 },
    accent  = { 0.91, 0.64, 0.24 },  -- forge amber
    text    = { 0.92, 0.93, 0.95 },
    muted   = { 0.58, 0.61, 0.67 },
    health  = { 0.24, 0.75, 0.33 },
    rage    = { 0.82, 0.18, 0.18 },
    mana    = { 0.18, 0.45, 0.9 },
    energy  = { 0.95, 0.85, 0.25 },
    good    = { 0.35, 0.9, 0.45 },
    warn    = { 1, 0.7, 0.2 },
    bad     = { 1, 0.3, 0.3 },
    mitigation = { 0.35, 0.68, 1 },
}

--- "rrggbb" for a { r, g, b } color with 0..1 channels.
---@param c number[]
---@return string
function Style.Hex(c)
    return string.format("%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5),
        math.floor(c[3] * 255 + 0.5))
end

-- Color codes for every palette entry, built once: Style.HEX.bad -> "ff4d4d".
Style.HEX = {}
for key, c in pairs(Style.colors) do Style.HEX[key] = Style.Hex(c) end

--- Set a FontString's text only when it changed. Only for FontStrings that are
--- always set through this, so the remembered text can't go stale.
---@param fs table FontString
---@param text string|nil
function Style.SetText(fs, text)
    text = text or ""
    if fs.tfText ~= text then
        fs.tfText = text
        fs:SetText(text)
    end
end

--- Bar color for a power type (1 rage, 3 energy, anything else mana).
---@param ptype number|nil
---@return number[]
function Style.PowerColor(ptype)
    if ptype == 1 then return Style.colors.rage end
    if ptype == 3 then return Style.colors.energy end
    if ptype == 0 then return Style.colors.mana end
    return Style.colors.mana
end

-- Fonts ----------------------------------------------------------------------

local FONT = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

--- flags: font flags such as "OUTLINE" (default none).
--- A FontString in the add-on font.
---@param parent table
---@param size number
---@param layer string|nil draw layer, default "OVERLAY"
---@param flags string|nil
function Style.Text(parent, size, layer, flags)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFont(FONT, size or 11, flags or "")
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(1, -1)
    fs:SetTextColor(unpack(Style.colors.text))
    fs:SetWordWrap(false)
    return fs
end

-- Panels ---------------------------------------------------------------------

local function Border(f, r, g, b, a)
    local t = {}
    for i, spec in ipairs({
        { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
        { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil },
    }) do
        local tex = f:CreateTexture(nil, "BORDER")
        tex:SetTexture(FLAT)
        tex:SetVertexColor(r, g, b, a)
        tex:SetPoint(spec[1], f, spec[1], 0, 0)
        tex:SetPoint(spec[2], f, spec[2], 0, 0)
        if spec[3] then tex:SetWidth(spec[3]) end
        if spec[4] then tex:SetHeight(spec[4]) end
        t[i] = tex
    end
    return t
end

--- Recolor the 1px border made by Panel, Portrait or Outline.
function Style.SetBorderColor(f, r, g, b, a)
    local list = f.borderTextures
    if not list then return end
    for _, tex in ipairs(list) do tex:SetVertexColor(r, g, b, a or 1) end
end

--- A red alert border while `on`, black otherwise. Recolors only when `on`
--- changes, so per-tick callers don't repaint an unchanged border.
---@param f table frame with borderTextures
---@param on boolean|nil
---@param r number|nil red channel of the alert color (default 0.9)
function Style.SetAlertBorder(f, on, r)
    on = on and true or false
    if f.tfAlert == on then return end
    f.tfAlert = on
    if on then
        Style.SetBorderColor(f, r or 0.9, 0.15, 0.15, 1)
    else
        Style.SetBorderColor(f, 0, 0, 0, 1)
    end
end

--- Give an existing frame the panel look: a dark background, a 1px border and
--- a 2px accent line along the top. For frames Panel can't make, such as
--- secure buttons.
---@param f table
---@return table f, with .bg, .borderTextures and .accent
function Style.PanelLook(f)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetTexture(FLAT)
    f.bg:SetVertexColor(unpack(Style.colors.bg))
    f.borderTextures = Border(f, unpack(Style.colors.border))
    f.accent = f:CreateTexture(nil, "ARTWORK")
    f.accent:SetTexture(FLAT)
    f.accent:SetPoint("TOPLEFT", 1, -1)
    f.accent:SetPoint("TOPRIGHT", -1, -1)
    f.accent:SetHeight(2)
    f.accent:SetVertexColor(Style.colors.accent[1], Style.colors.accent[2], Style.colors.accent[3], 0.9)
    return f
end

--- A dark panel with a 1px border and a 2px accent line along the top.
---@param parent table
---@param name string|nil global frame name
---@return table frame with .bg
function Style.Panel(parent, name)
    return Style.PanelLook(CreateFrame("Frame", name, parent or UIParent))
end

-- Bars -----------------------------------------------------------------------

--- A flat status bar with a background, a label on the left and a value on
--- the right. The text is outlined so it stays readable on bright fills.
---@param color number[] fill color
---@return table StatusBar with .bg, .label, .value
function Style.Bar(parent, height, color, labelSize)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetHeight(height)
    bar:SetStatusBarTexture(FLAT)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    color = color or Style.colors.health
    bar:SetStatusBarColor(color[1], color[2], color[3])
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetTexture(FLAT)
    bar.bg:SetVertexColor(unpack(Style.colors.barBg))
    bar.borderTextures = Border(bar, 0, 0, 0, 1)
    if labelSize and labelSize > 0 then
        bar.label = Style.Text(bar, labelSize, nil, "OUTLINE")
        bar.label:SetPoint("LEFT", 5, 0)
        bar.label:SetJustifyH("LEFT")
        bar.value = Style.Text(bar, labelSize, nil, "OUTLINE")
        bar.value:SetPoint("RIGHT", -5, 0)
        bar.value:SetJustifyH("RIGHT")
        bar.label:SetPoint("RIGHT", bar.value, "LEFT", -4, 0)
    end
    return bar
end

-- Icons ----------------------------------------------------------------------

--- A square spell icon with a cooldown sweep and a border.
---@return table frame with .tex and .cd (Cooldown)
function Style.Icon(parent, size)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetPoint("TOPLEFT", 1, -1)
    f.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.borderTextures = Border(f, 0, 0, 0, 1)
    local ok, cd = pcall(CreateFrame, "Cooldown", nil, f, "CooldownFrameTemplate")
    if ok and cd then
        cd:SetAllPoints(f.icon)
        if cd.SetDrawEdge then cd:SetDrawEdge(false) end
        if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(false) end
        f.cooldown = cd
    end
    return f
end

--- A square unit portrait: the round art cropped flat, inside a 1px border
--- (recolorable with Style.SetBorderColor). The texture is `p.tex`.
function Style.Portrait(parent, size)
    local p = CreateFrame("Frame", nil, parent)
    p:SetSize(size, size)
    p.tex = p:CreateTexture(nil, "ARTWORK")
    p.tex:SetPoint("TOPLEFT", 1, -1)
    p.tex:SetPoint("BOTTOMRIGHT", -1, 1)
    p.tex:SetTexCoord(0.12, 0.88, 0.12, 0.88)
    p.bg = p:CreateTexture(nil, "BACKGROUND")
    p.bg:SetAllPoints()
    p.bg:SetTexture(FLAT)
    p.bg:SetVertexColor(unpack(Style.colors.barBg))
    p.borderTextures = Border(p, 0, 0, 0, 1)
    return p
end

local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
Style.CIRCLE = CIRCLE

-- A texture clipped to a circle by its own mask.
local function Disc(p, layer, inset)
    local t = p:CreateTexture(nil, layer)
    t:SetPoint("TOPLEFT", inset, -inset)
    t:SetPoint("BOTTOMRIGHT", -inset, inset)
    local m = p:CreateMaskTexture()
    m:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    m:SetAllPoints(t)
    t:AddMaskTexture(m)
    t.mask = m
    return t
end

--- A round unit portrait inside a thin ring in the accent color (recolorable
--- with Style.SetBorderColor). The texture is `p.tex`, as with Style.Portrait.
---@param parent table
---@param size number
---@return table frame with .tex, .ring, .bg
function Style.RoundPortrait(parent, size)
    local p = CreateFrame("Frame", nil, parent)
    p:SetSize(size, size)
    p.ring = Disc(p, "BACKGROUND", 0)
    p.ring:SetTexture(FLAT)
    p.ring:SetVertexColor(Style.colors.accent[1], Style.colors.accent[2], Style.colors.accent[3], 1)
    p.bg = Disc(p, "BORDER", 2)
    p.bg:SetTexture(FLAT)
    p.bg:SetVertexColor(unpack(Style.colors.barBg))
    p.tex = Disc(p, "ARTWORK", 2)
    p.tex:SetTexCoord(0, 1, 0, 1)
    p.borderTextures = { p.ring }
    return p
end

--- The party leader crown, as a badge on a frame's top-left corner.
function Style.LeaderBadge(parent, size)
    local tex = parent:CreateTexture(nil, "OVERLAY", nil, 7)
    tex:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
    tex:SetSize(size or 14, size or 14)
    tex:SetPoint("TOPLEFT", parent, "TOPLEFT", -4, 5)
    tex:Hide()
    return tex
end

-- Role icons: the group finder's tank / healer / damage icons.
Style.ROLE_TEXTURE = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"
Style.ROLE_COORDS = {
    TANK = { 0, 19 / 64, 22 / 64, 41 / 64 },
    HEALER = { 20 / 64, 39 / 64, 1 / 64, 20 / 64 },
    DAMAGER = { 20 / 64, 39 / 64, 22 / 64, 41 / 64 },
}

--- A hidden role icon on `parent`; place it, then set it with Style.SetRoleIcon.
---@param parent table
---@param size number|nil
---@return table texture
function Style.RoleIcon(parent, size)
    local tex = parent:CreateTexture(nil, "OVERLAY", nil, 7)
    tex:SetTexture(Style.ROLE_TEXTURE)
    tex:SetSize(size or 14, size or 14)
    tex:Hide()
    return tex
end

--- Show `role`'s icon ("TANK", "HEALER" or "DAMAGER"), or hide it for anything else.
--- Only touches the texture when the role changes, since party frames call it on a timer.
---@param tex table a texture from Style.RoleIcon
---@param role string|nil
function Style.SetRoleIcon(tex, role)
    local coords = role and Style.ROLE_COORDS[role]
    role = coords and role or false
    if tex.role == role then return end
    tex.role = role
    if coords then
        tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        tex:Show()
    else
        tex:Hide()
    end
end

-- Flat widgets (shared by the options window and the unlock bar) ------------

local C = Style.colors
--- A flat-colored texture.
function Style.Flat(parent, layer, color)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    t:SetTexture(Style.FLAT)
    t:SetVertexColor(unpack(color))
    return t
end

--- A 1px outline around `f`, recolorable with Style.SetBorderColor.
function Style.Outline(f, color)
    local list = {}
    for i, spec in ipairs({
        { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
        { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil },
    }) do
        local t = Style.Flat(f, "BORDER", color)
        t:SetPoint(spec[1], f, spec[1])
        t:SetPoint(spec[2], f, spec[2])
        if spec[3] then t:SetWidth(spec[3]) end
        if spec[4] then t:SetHeight(spec[4]) end
        list[i] = t
    end
    f.borderTextures = list
end

Style.BORDER = { 0.27, 0.29, 0.33, 1 }
local BORDER = Style.BORDER
Style.HOVER = { C.accent[1], C.accent[2], C.accent[3], 1 }
local HOVER = Style.HOVER

local function Hover(f)
    f:SetScript("OnEnter", function(self)
        Style.SetBorderColor(self, unpack(HOVER))
        if self.note then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.title or "", 1, 1, 1)
            GameTooltip:AddLine(self.note, nil, nil, nil, true)
            GameTooltip:Show()
        end
    end)
    f:SetScript("OnLeave", function(self)
        Style.SetBorderColor(self, unpack(BORDER))
        GameTooltip:Hide()
    end)
end

--- A flat button: dark fill, grey outline, amber outline on hover.
---@param onClick fun()|nil
function Style.Button(parent, text, width, height, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, height or 26)
    b.bg = Style.Flat(b, "BACKGROUND", { 0.13, 0.14, 0.17, 1 })
    b.bg:SetAllPoints()
    Style.Outline(b, BORDER)
    b.label = Style.Text(b, 12)
    b.label:SetPoint("CENTER", 0, 0)
    b.label:SetText(text)
    b.text = text
    Hover(b)
    b:SetScript("OnMouseDown", function(self) self.bg:SetVertexColor(0.09, 0.1, 0.12, 1) end)
    b:SetScript("OnMouseUp", function(self) self.bg:SetVertexColor(0.13, 0.14, 0.17, 1) end)
    b:SetScript("OnClick", function() onClick() end)
    return b
end

-- Movers ---------------------------------------------------------------------
--
-- Every movable TankForgeUI frame hangs off a plain anchor frame. /tf unlock
-- shows the anchors as labelled boxes that can be dragged; positions are saved
-- per character. Frames are never moved in combat, because some (the party
-- frames) are secure.

Style.movers = {}
local unlocked = false

local function SavePosition(anchor)
    local point, _, relPoint, x, y = anchor:GetPoint(1)
    TF.db.positions[anchor.key] = { point, relPoint, x, y }
end

-- Saved position, or the default when none is saved or the saved one is unusable.
local function ApplyPosition(anchor)
    local p = TF.db and TF.db.positions[anchor.key]
    if type(p) ~= "table" or type(p[1]) ~= "string" or type(p[2]) ~= "string" then p = anchor.default end
    anchor:ClearAllPoints()
    anchor:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

--- frame: the frame to move. default: { point, relativePoint, x, y } on UIParent.
--- Hang `frame` off a draggable anchor shown by /tf unlock; positions save to TF.db.positions[key].
---@param frame table
---@param key string saved-position key
---@param label string shown on the drag box
---@param default table { point, relativePoint, x, y } on UIParent
---@return table anchor
function Style.Movable(frame, key, label, default)
    local anchor = CreateFrame("Frame", "TankForgeUIAnchor_" .. key, UIParent)
    anchor.key, anchor.label, anchor.default, anchor.target = key, label, default, frame
    anchor:SetSize(10, 10)
    anchor:SetClampedToScreen(true)
    anchor:SetMovable(true)

    local box = CreateFrame("Frame", nil, anchor)
    box:SetAllPoints()
    box:SetFrameStrata("DIALOG")
    box.bg = box:CreateTexture(nil, "BACKGROUND")
    box.bg:SetAllPoints()
    box.bg:SetTexture(FLAT)
    box.bg:SetVertexColor(0.91, 0.64, 0.24, 0.35)
    box.text = Style.Text(box, 12)
    box.text:SetPoint("CENTER")
    box.text:SetText(label)
    box:EnableMouse(true)
    box:RegisterForDrag("LeftButton")
    box:SetScript("OnDragStart", function()
        if InCombatLockdown() then return end
        anchor:StartMoving()
    end)
    box:SetScript("OnDragStop", function()
        anchor:StopMovingOrSizing()
        SavePosition(anchor)
    end)
    box:Hide()
    anchor.box = box

    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
    Style.movers[key] = anchor
    if TF.db then ApplyPosition(anchor) else anchor:SetPoint(default[1], UIParent, default[2], default[3], default[4]) end
    Style.FitAnchor(key)
    return anchor
end

--- Resize an anchor to its frame (call after the frame changes size or scale).
---@param key string the key given to Style.Movable
function Style.FitAnchor(key)
    local anchor = Style.movers[key]
    if not anchor then return end
    local f = anchor.target
    local s = f:GetScale() or 1
    local w, h = f:GetWidth() or 0, f:GetHeight() or 0
    if w < 10 then w = 10 end
    if h < 10 then h = 10 end
    if InCombatLockdown() and f.IsProtected and f:IsProtected() then return end
    anchor:SetSize(w * s, h * s)
end

--- True while /tf unlock is moving frames.
---@return boolean
function Style.IsUnlocked() return unlocked end

--- The opacity a frame should have right now from its { alpha, oocAlpha } settings.
--- Fully opaque while frames are unlocked, so they're easy to place.
---@param cfg {alpha: number?, oocAlpha: number?}|nil
---@return number
function Style.FrameAlpha(cfg)
    if unlocked or not cfg then return 1 end
    if TF.inCombat then return cfg.alpha or 1 end
    return cfg.oocAlpha or cfg.alpha or 1
end

-- The bar shown while frames are unlocked: what to do, and buttons to finish.
local unlockBar, onLock
local function UnlockBar()
    if unlockBar then return unlockBar end
    local bar = Style.Panel(UIParent, "TankForgeUIUnlockBar")
    bar.bg:SetVertexColor(0.055, 0.06, 0.075, 0.97)
    bar:SetFrameStrata("FULLSCREEN_DIALOG")
    bar:SetSize(420, 74)
    bar:SetPoint("TOP", UIParent, "TOP", 0, -90)
    bar:EnableMouse(true)
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function(self) self:StartMoving() end)
    bar:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    local text = Style.Text(bar, 12)
    text:SetPoint("TOP", 0, -12)
    text:SetText("|cff" .. TF.COLOR .. "Moving frames:|r drag the amber boxes where you want them.")
    local done = Style.Button(bar, "Done", 150, 28, function() Style.SetUnlocked(false) end)
    done:SetPoint("BOTTOMRIGHT", bar, "BOTTOM", -5, 12)
    local reset = Style.Button(bar, "Reset positions", 150, 28, function() Style.ResetPositions() end)
    reset:SetPoint("BOTTOMLEFT", bar, "BOTTOM", 5, 12)
    bar.done, bar.reset = done, reset
    bar:Hide()
    unlockBar = bar
    return bar
end

--- opts.onLock: called once when the frames are locked again (the options
--- window uses it to come back).
--- Show or hide the movers. Refused in combat.
---@param on boolean
---@param opts {onLock: fun()?}|nil
function Style.SetUnlocked(on, opts)
    if on and InCombatLockdown() then
        TF:Print("can't unlock frames in combat.")
        return
    end
    unlocked = on and true or false
    for _, anchor in pairs(Style.movers) do
        Style.FitAnchor(anchor.key)
        anchor.box:SetShown(unlocked)
    end
    UnlockBar():SetShown(unlocked)
    TF:Fire("UNLOCKED", unlocked)
    if unlocked then
        onLock = opts and opts.onLock or nil
        TF:Print("frames unlocked: drag the amber boxes, then click Done.")
    else
        TF:Print("frames locked.")
        local fn = onLock
        onLock = nil
        if fn and not InCombatLockdown() then fn() end
    end
end

--- Forget saved positions and move every frame back to its default. Refused in combat.
function Style.ResetPositions()
    if InCombatLockdown() then
        TF:Print("can't move frames in combat.")
        return
    end
    wipe(TF.db.positions)
    for _, anchor in pairs(Style.movers) do ApplyPosition(anchor) end
    TF:Print("frame positions reset.")
end

TF:On("LOADED", function()
    for _, anchor in pairs(Style.movers) do ApplyPosition(anchor) end
end)

TF:On("COMBAT", function(inCombat)
    if inCombat and unlocked then Style.SetUnlocked(false) end
end)

TF:AddCommand("unlock", function() Style.SetUnlocked(true) end, "- move TankForgeUI's frames", { group = "Frames" })
TF:AddCommand("lock", function() Style.SetUnlocked(false) end, "- stop moving frames", { group = "Frames" })
TF:AddCommand("reset", function() Style.ResetPositions() end, "- put every frame back where it started", { group = "Frames" })
