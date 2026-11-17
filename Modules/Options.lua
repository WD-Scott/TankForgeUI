-- Modules/Options.lua
-- The /tf window. Everything in it is drawn in TankForgeUI's own style: flat
-- buttons, square checkboxes and sliders, on a solid dark window with amber
-- section headings. The sections are a collapsible accordion: each heading is a
-- clickable header with a chevron that folds its rows away and remembers the
-- choice. Two columns of switches, then a full-width Appearance section, then a
-- footer (always shown) with the debug log and the action buttons.
local _, ns = ...
local TF = ns.TF
local Style = ns.Style
local C = Style.colors

ns.Options = ns.Options or {}
local Options = ns.Options
Options.sections = Options.sections or {}   -- section records by id, for reflow and specs

local WIDTH = 600
local COL_W = 270
local LEFT_X, RIGHT_X = 20, 316
local ROW = 22
local HEADER_H = 20
local SECTION_GAP = 12
local BOTTOM_MARGIN = 16
local CHECK_MARK = "Interface\\Buttons\\UI-CheckBox-Check"
local ARROW = "Interface\\ChatFrame\\ChatFrameExpandArrow"

local win
local controls = {}   -- everything with a :Refresh(), re-read when the window opens
local Lcol, Rcol, appCol, footer
local Relayout        -- assigned in Build; referenced by section headers

-- Collapse state --------------------------------------------------------------

--- Whether the /tf section `id` is folded away. Sections absent from the saved
--- table read as expanded.
---@param db TankForgeUISettings
---@param id string
---@return boolean
function Options.IsCollapsed(db, id)
    local o = db and db.options
    return not not (o and o.collapsed and o.collapsed[id])
end

--- Fold or unfold the /tf section `id`, writing it to the saved settings.
---@param db TankForgeUISettings
---@param id string
---@param collapsed boolean
function Options.SetCollapsed(db, id, collapsed)
    db.options = db.options or {}
    db.options.collapsed = db.options.collapsed or {}
    db.options.collapsed[id] = collapsed and true or false
end

-- Settings access -------------------------------------------------------------

--- A setting by key path: Get({ "party", "enabled" }) is TF.db.party.enabled.
---@param path string[]
---@return any
local function Get(path)
    local t = TF.db
    for i = 1, #path - 1 do t = t[path[i]] end
    return t[path[#path]]
end

---@param path string[]
---@param value any
local function Set(path, value)
    local t = TF.db
    for i = 1, #path - 1 do t = t[path[i]] end
    t[path[#path]] = value
end

TF.GetSetting, TF.SetSetting = Get, Set

local function ApplyAll()
    TF:ApplyHiding()
    if ns.HUD then ns.HUD:Refresh() end
    if ns.Threat then ns.Threat:Refresh() end
    if ns.Healer then ns.Healer:Refresh() end
    if ns.Party then
        ns.Party:Assign()
        ns.Party:ApplyAlpha()
    end
    if ns.Tank then ns.Tank:Evaluate() end
end

-- Widgets ----------------------------------------------------------------------

local Flat, Outline, Button = Style.Flat, Style.Outline, Style.Button
local BORDER, HOVER = Style.BORDER, Style.HOVER

-- A checkbox row: square box, amber tick, label. The whole row is clickable.
-- get/set read and write the setting.
local function Checkbox(parent, label, x, y, get, set, note, width)
    local cb = CreateFrame("Button", nil, parent)
    cb:SetSize(width or COL_W, ROW)
    cb:SetPoint("TOPLEFT", x, y)
    cb.isCheck = true
    cb.box = CreateFrame("Frame", nil, cb)
    cb.box:SetSize(14, 14)
    cb.box:SetPoint("LEFT", 0, 0)
    local fill = Flat(cb.box, "BACKGROUND", { 0.1, 0.11, 0.13, 1 })
    fill:SetAllPoints()
    Outline(cb.box, BORDER)
    cb.tick = cb.box:CreateTexture(nil, "OVERLAY")
    cb.tick:SetTexture(CHECK_MARK)
    cb.tick:SetSize(20, 20)
    cb.tick:SetPoint("CENTER", 1, 1)
    cb.tick:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
    cb.label = Style.Text(cb, 12)
    cb.label:SetPoint("LEFT", cb.box, "RIGHT", 8, 0)
    cb.label:SetPoint("RIGHT", cb, "RIGHT", 0, 0)
    cb.label:SetJustifyH("LEFT")
    cb.label:SetText(label)
    cb.title, cb.note = label, note

    function cb:Refresh()
        self.checked = get() and true or false
        self.tick:SetShown(self.checked)
    end
    function cb:GetChecked() return self.checked end
    cb:SetScript("OnEnter", function(self)
        Style.SetBorderColor(self.box, unpack(HOVER))
        if self.note then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.title, 1, 1, 1)
            GameTooltip:AddLine(self.note, nil, nil, nil, true)
            GameTooltip:Show()
        end
    end)
    cb:SetScript("OnLeave", function(self)
        Style.SetBorderColor(self.box, unpack(BORDER))
        GameTooltip:Hide()
    end)
    cb:SetScript("OnClick", function(self)
        set(not self.checked)
        self:Refresh()
    end)
    controls[#controls + 1] = cb
    return cb
end

-- A slider: track, amber fill, thumb and a value on the right. Drag, click or
-- scroll the mouse wheel; values snap to `step`.
local function Slider(parent, x, y, width, minV, maxV, step, get, set, format)
    local s = CreateFrame("Frame", nil, parent)
    s:SetSize(width, 18)
    s:SetPoint("TOPLEFT", x, y)
    s:EnableMouse(true)
    if s.EnableMouseWheel then s:EnableMouseWheel(true) end
    s.isSlider = true

    local track = Flat(s, "BACKGROUND", { 0.16, 0.17, 0.2, 1 })
    track:SetPoint("LEFT", 0, 0)
    track:SetPoint("RIGHT", 0, 0)
    track:SetHeight(4)
    s.fill = Flat(s, "ARTWORK", { C.accent[1], C.accent[2], C.accent[3], 0.9 })
    s.fill:SetPoint("LEFT", 0, 0)
    s.fill:SetHeight(4)
    s.thumb = Flat(s, "OVERLAY", { 0.92, 0.93, 0.95, 1 })
    s.thumb:SetSize(6, 14)
    s.value = Style.Text(parent, 12)
    s.value:SetPoint("LEFT", s, "RIGHT", 10, 0)
    s.value:SetWidth(44)
    s.value:SetJustifyH("LEFT")

    function s:Refresh()
        local v = get()
        local frac = (v - minV) / (maxV - minV)
        frac = math.max(0, math.min(1, frac))
        self.fill:SetWidth(math.max(1, frac * width))
        self.thumb:ClearAllPoints()
        self.thumb:SetPoint("CENTER", self, "LEFT", frac * width, 0)
        self.value:SetText(format(v))
    end

    -- Set from the user; snaps, clamps, and only writes real changes.
    function s:SetFromUser(v)
        v = math.floor(v / step + 0.5) * step
        v = math.max(minV, math.min(maxV, v))
        if math.abs(v - get()) > step / 10 then set(v) end
        self:Refresh()
    end

    local function FromCursor()
        local left = s:GetLeft()
        if not left then return end
        local cx = GetCursorPosition() / s:GetEffectiveScale()
        s:SetFromUser(minV + (cx - left) / width * (maxV - minV))
    end
    s:SetScript("OnMouseDown", function(self)
        self.dragging = true
        FromCursor()
    end)
    s:SetScript("OnMouseUp", function(self) self.dragging = false end)
    s:SetScript("OnUpdate", function(self)
        if not self.dragging then return end
        if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
            self.dragging = false
            return
        end
        FromCursor()
    end)
    s:SetScript("OnMouseWheel", function(self, delta) self:SetFromUser(get() + delta * step) end)
    controls[#controls + 1] = s
    return s
end

local function Percent(v) return string.format("%d%%", v * 100 + 0.5) end

-- A clickable section header: a chevron that turns, an amber title and an amber
-- underline. The whole row toggles the section. :SetCollapsed turns the chevron.
local function SectionHeader(parent, title, width)
    local h = CreateFrame("Button", nil, parent)
    h:SetSize(width, HEADER_H)
    h.arrow = h:CreateTexture(nil, "ARTWORK")
    h.arrow:SetTexture(ARROW)
    h.arrow:SetSize(10, 10)
    h.arrow:SetPoint("LEFT", 0, -1)
    h.arrow:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
    h.label = Style.Text(h, 13)
    h.label:SetPoint("LEFT", h.arrow, "RIGHT", 6, 1)
    h.label:SetText(title)
    h.label:SetTextColor(unpack(C.accent))
    local line = Flat(h, "ARTWORK", { C.accent[1], C.accent[2], C.accent[3], 0.45 })
    line:SetPoint("BOTTOMLEFT", 0, 0)
    line:SetSize(width, 1)

    -- The chevron points down when the section is open, right when it's folded.
    function h:SetCollapsed(collapsed)
        self.arrow:SetRotation(collapsed and 0 or -math.pi / 2)
    end
    h:SetScript("OnEnter", function(self) self.label:SetTextColor(1, 1, 1) end)
    h:SetScript("OnLeave", function(self) self.label:SetTextColor(unpack(C.accent)) end)
    return h
end

-- A column of collapsible sections. Each section owns a content frame; its rows
-- are parented into it and laid out with a cursor from 0 downwards, so folding
-- it is one SetShown and the reflow only moves the header and the content.
local function Column(x, y0, width)
    local col = { x = x, y0 = y0, width = width or COL_W, sections = {}, cur = nil }

    function col:Section(id, title)
        local content = CreateFrame("Frame", nil, win)
        content:SetWidth(self.width)
        local s = { id = id, header = SectionHeader(win, title, self.width), content = content, cy = 0 }
        self.cur = s
        self.sections[#self.sections + 1] = s
        Options.sections[id] = s
        s.header:SetScript("OnClick", function()
            Options.SetCollapsed(TF.db, id, not Options.IsCollapsed(TF.db, id))
            Relayout()
        end)
        return s
    end

    -- A label and a row of buttons, one per choice; the chosen one is lit amber.
    function col:Choice(label, path, choices, note)
        local c = self.cur.content
        local fs = Style.Text(c, 12)
        fs:SetPoint("TOPLEFT", 0, self.cur.cy - 4)
        fs:SetText(label)
        self.cur.cy = self.cur.cy - ROW
        local gap = 4
        local bw = math.floor((self.width - gap * (#choices - 1)) / #choices)
        local group = {}
        for i, ch in ipairs(choices) do
            local b = Button(c, ch[2], bw, 22, function()
                Set(path, ch[1])
                ApplyAll()
                for _, other in ipairs(group) do other:Refresh() end
            end)
            b:SetPoint("TOPLEFT", (i - 1) * (bw + gap), self.cur.cy)
            b.value, b.title, b.note = ch[1], label, note
            b.Refresh = function(btn)
                btn.selected = Get(path) == btn.value
                local tint = btn.selected and C.accent or C.muted
                btn.label:SetTextColor(tint[1], tint[2], tint[3])
                Style.SetBorderColor(btn, unpack(btn.selected and HOVER or BORDER))
                btn.bg:SetVertexColor(btn.selected and 0.17 or 0.13, btn.selected and 0.15 or 0.14,
                    btn.selected and 0.12 or 0.17, 1)
            end
            -- Keep the chosen one's amber outline when the mouse leaves.
            b:HookScript("OnLeave", function(btn) btn:Refresh() end)
            group[#group + 1] = b
            controls[#controls + 1] = b
        end
        self.cur.cy = self.cur.cy - 28
    end

    -- path: a setting path, or { get = fn, set = fn }.
    function col:Check(label, path, note, opts)
        opts = opts or {}
        local indent = opts.indent and 22 or 0
        local get, set
        if path.get then
            get, set = path.get, path.set
        else
            get = function()
                local v = Get(path)
                if opts.invert then return v == "always" end
                return v
            end
            set = function(v)
                if opts.invert then Set(path, v and "always" or "auto") else Set(path, v) end
                ApplyAll()
                if opts.onChange then opts.onChange(v) end
            end
        end
        Checkbox(self.cur.content, label, indent, self.cur.cy, get, set, note, (opts.width or self.width) - indent)
        self.cur.cy = self.cur.cy - ROW
    end

    -- An indented action button on its own row (e.g. "Open runs").
    function col:ActionButton(label, w, onClick)
        local b = Button(self.cur.content, label, w, 22, onClick)
        b:SetPoint("TOPLEFT", 22, self.cur.cy - 2)
        self.cur.cy = self.cur.cy - 30
        return b
    end

    return col
end

-- Building -------------------------------------------------------------------

local function ApplyScale(v)
    if InCombatLockdown() then
        TF:Print("can't change scale in combat.")
        return
    end
    TF.db.scale = v
    for _, anchor in pairs(Style.movers) do
        anchor.target:SetScale(v)
        Style.FitAnchor(anchor.key)
    end
end

-- Stack a column's sections from `top`, folding the collapsed ones away, and
-- return the y below the last one.
local function LayoutColumn(col, top)
    local y = top
    for _, s in ipairs(col.sections) do
        s.header:ClearAllPoints()
        s.header:SetPoint("TOPLEFT", col.x, y)
        s.header:SetCollapsed(Options.IsCollapsed(TF.db, s.id))
        y = y - HEADER_H
        local h = math.max(1, -s.cy)
        s.content:SetSize(col.width, h)
        s.content:ClearAllPoints()
        s.content:SetPoint("TOPLEFT", col.x, y)
        if Options.IsCollapsed(TF.db, s.id) then
            s.content:Hide()
        else
            s.content:Show()
            y = y - h
        end
        y = y - SECTION_GAP
    end
    return y
end

-- Appearance (scale and opacity sliders, range dimming). Full width.
local function BuildAppearance()
    appCol = Column(LEFT_X, 0, WIDTH - 2 * LEFT_X)
    local s = appCol:Section("Appearance", "Appearance")
    local c = s.content
    local SLIDER_W = 150
    local IN_X, OUT_X = 150, 380   -- relative to the content frame (anchored at LEFT_X)
    local y = -4

    local scaleLabel = Style.Text(c, 12)
    scaleLabel:SetPoint("TOPLEFT", 4, y - 3)
    scaleLabel:SetText("Frame scale")
    Slider(c, IN_X, y - 2, SLIDER_W, 0.6, 1.6, 0.05,
        function() return TF.db.scale or 1 end, ApplyScale, Percent)
    y = y - 30

    local inHead = Style.Text(c, 11)
    inHead:SetPoint("TOPLEFT", IN_X, y)
    inHead:SetText("Opacity in combat")
    inHead:SetTextColor(unpack(C.muted))
    local outHead = Style.Text(c, 11)
    outHead:SetPoint("TOPLEFT", OUT_X, y)
    outHead:SetText("Out of combat")
    outHead:SetTextColor(unpack(C.muted))
    y = y - 20
    for _, row in ipairs({ { "hud", "Tank HUD" }, { "healer", "Healer panel" }, { "party", "Party frames" } }) do
        local key = row[1]
        local label = Style.Text(c, 12)
        label:SetPoint("TOPLEFT", 4, y - 3)
        label:SetText(row[2])
        for _, spec in ipairs({ { "alpha", IN_X }, { "oocAlpha", OUT_X } }) do
            local field = spec[1]
            Slider(c, spec[2], y - 2, SLIDER_W, 0.1, 1, 0.05,
                function() return TF.db[key][field] or 1 end,
                function(v)
                    TF.db[key][field] = v
                    ApplyAll()
                end, Percent)
        end
        y = y - 28
    end
    y = y - 4
    appCol.cur.cy = y
    appCol:Check("Dim the healer panel when your healer is out of range", { "healer", "dimOutOfRange" })
    appCol:Check("Dim party members who are out of range", { "party", "dimOutOfRange" })
end

-- Footer: a divider, the debug log, a hint and the action buttons. Always shown;
-- lives in its own frame so the reflow only has to move it.
local function BuildFooter()
    footer = CreateFrame("Frame", nil, win)
    local fullW = WIDTH - 2 * LEFT_X
    footer:SetWidth(fullW)
    local y = 0

    local divider = Flat(footer, "ARTWORK", { 1, 1, 1, 0.08 })
    divider:SetPoint("TOPLEFT", 0, y)
    divider:SetSize(fullW, 1)
    y = y - 10
    footer.log = Checkbox(footer, "Debug log  |cff" .. Style.HEX.muted .. "(saved on /reload or logout; /tf log for more)|r",
        0, y,
        function() return ns.Log and ns.Log:IsOn() end,
        function(v) ns.Log:SetEnabled(v) end,
        "Records what happens in your runs to a file you can share. See /tf log.", fullW)
    y = y - ROW - 2
    local hint = Style.Text(footer, 11)
    hint:SetPoint("TOPLEFT", 0, y)
    hint:SetTextColor(unpack(C.muted))
    hint:SetText("/tf help lists every command.  /tf healer makes your target the healer.")
    y = y - 26

    local buttons = {
        { "Set up layout", function() win:Hide() TF:RunSetup() end },
        { "Move frames", function()
            -- Out of the way while moving; Done brings it back.
            win:Hide()
            Style.SetUnlocked(true, { onLock = function() TF:OpenOptions() end })
        end },
        { "Reset positions", function() Style.ResetPositions() end },
        { "Last pull", function() ns.Report:Open(1) end },
        { "Test alert", function() TF.commands.test.fn("") end },
    }
    local gap = 8
    local bw = math.floor((fullW - gap * (#buttons - 1)) / #buttons)
    for i, spec in ipairs(buttons) do
        local b = Button(footer, spec[1], bw, 28, spec[2])
        b:SetPoint("TOPLEFT", (i - 1) * (bw + gap), y)
    end
    y = y - 28
    footer.h = -y
end

local function Build()
    win = Style.Panel(UIParent, "TankForgeUIOptions")
    win.bg:SetVertexColor(0.055, 0.06, 0.075, 0.98)
    win:SetFrameStrata("DIALOG")
    win:SetPoint("CENTER")
    win:EnableMouse(true)
    win:SetMovable(true)
    win:SetClampedToScreen(true)
    table.insert(UISpecialFrames, "TankForgeUIOptions")

    -- Title bar: drag the window by it.
    local titleBar = CreateFrame("Frame", nil, win)
    titleBar:SetPoint("TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", -44, 0)  -- stops short of the close button
    titleBar:SetHeight(40)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() win:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() win:StopMovingOrSizing() end)
    local title = Style.Text(win, 17)
    title:SetPoint("TOPLEFT", LEFT_X, -14)
    title:SetText("|cff" .. TF.COLOR .. "TankForgeUI|r  |cff" .. Style.HEX.muted .. TF.version .. "|r")
    local close = Button(win, "X", 24, 24, function() win:Hide() end)
    close:SetPoint("TOPRIGHT", -10, -10)
    close:SetFrameLevel(titleBar:GetFrameLevel() + 5)
    win.close = close

    -- Left column
    Lcol = Column(LEFT_X, 0)
    Lcol:Section("Hide", "Hide")
    Lcol:Check("Player frame", { "hidePlayerFrame" },
        "Hides your portrait, health and power bars. Other addons' HUDs on it stay visible.")
    Lcol:Check("Action bar tooltips", { "hideActionTooltips" })
    Lcol:Check("...but show them while Shift is held", { "shiftShowsTooltips" }, nil, { indent = true })
    Lcol:Check("Action bar end caps and border", { "hideBarArt" })
    Lcol:Choice("Quest tracker", { "hideObjectives" }, {
        { "never", "Never" }, { "always", "Always" }, { "instance", "Dungeons" }, { "combat", "Combat" },
    }, "When to hide the \"All Objectives\" quest tracker. It always shows in Edit Mode so you can move it.")
    Lcol:Check("Keep tooltips and bags off the action bars", { "keepClear" },
        "Tooltips and bags open above your action bars instead of on top of them.")
    Lcol:Check("Move NPC windows", { "npcDialogs", "enabled" },
        "Quest, gossip, vendor, trainer, flight and bank windows open at the \"NPC dialogs\" box "
        .. "instead of the top left. Move the box with /tf unlock.",
        { onChange = function() if TF.ApplyNpcDialogs then TF:ApplyNpcDialogs() end end })
    Lcol:Check("Loot rolls wait until after combat", { "loot", "delay" },
        "Need / Greed / Pass windows stay hidden in combat and appear when it ends. "
        .. "A roll about to run out (10 seconds left) shows anyway, so it isn't passed for you.",
        { onChange = function() if TF.ApplyLoot then TF:ApplyLoot() end end })

    Lcol:Section("Alerts", "Alerts")
    Lcol:Check("Alerts on", { "alerts", "enabled" })
    Lcol:Check("Sounds", { "alerts", "sound" }, nil, { indent = true })
    Lcol:Check("A mob is on your healer", { "alerts", "healerAttacked" }, nil, { indent = true })
    Lcol:Check("A mob is on someone else", { "alerts", "lostAggro" }, nil, { indent = true })
    Lcol:Check("Being hit with Shield Block down", { "alerts", "mitigationLapse" },
        "Your main mitigation (Shield Block, Demoralizing Roar or Holy Shield) is down while you're being hit, "
        .. "and you could cast it: off cooldown, in the right stance or form, with a shield if it needs one.",
        { indent = true })
    Lcol:Choice("...where", { "alerts", "lapseWhere" }, {
        { "always", "Everywhere" }, { "group", "Groups & dungeons" }, { "instance", "Dungeons only" },
    }, "Solo in the open world it's mostly noise, so by default it only fires in a group or a dungeon.")
    Lcol:Check("What was ready when you died", { "alerts", "death" }, nil, { indent = true })
    Lcol:Check("A big defensive came back", { "alerts", "defensiveReady" }, nil, { indent = true })

    -- Right column
    Rcol = Column(RIGHT_X, 0)
    Rcol:Section("Frames", "Frames")
    Rcol:Check("Tank HUD", { "hud", "enabled" }, nil,
        { onChange = function() if TF.ApplyStances then TF:ApplyStances() end end })
    Rcol:Check("...show your portrait", { "hud", "portrait" },
        "Your portrait on the left of the HUD's health and power bars, since the player frame is hidden.",
        { indent = true, onChange = function() if ns.HUD then ns.HUD:Build() end end })
    Rcol:Check("...stance buttons", { "stances", "enabled" },
        "Your stance or form buttons in a flyout on the HUD's right edge, in place of Blizzard's stance bar. "
        .. "The tab opens and closes it, and both work in combat.",
        { indent = true, onChange = function() if TF.ApplyStances then TF:ApplyStances() end end })
    Rcol:Check("...stay up, compact, when not tanking", { "hud", "showIdle" },
        "Keeps your portrait, bars and stance buttons up while you're not tanking, "
        .. "so you can click back into your tanking stance.",
        { indent = true, onChange = function() if ns.HUD then ns.HUD:Refresh() end end })
    Rcol:Check("Threat and loose mobs", { "threat", "enabled" })
    Rcol:Check("Healer panel", { "healer", "enabled" })
    Rcol:Check("Party frames  |cff" .. Style.HEX.muted .. "(needs /reload)|r", { "party", "enabled" },
        "Minimal party frames with portraits. Blizzard's party frames are hidden while these are on.",
        { onChange = function() TF:Print("party frame changes take effect after a /reload.") end })
    Rcol:Check("...leave out your healer", { "party", "hideHealer" },
        "Your healer already has their own panel, so they're left off the party frames. "
        .. "Only applies while the healer panel is on.", { indent = true })
    Rcol:Check("Professions button on minimap", { "professions", "enabled" },
        "A button on the edge of the minimap that lists your profession spells. Drag it to move it around the edge.",
        { onChange = function() if TF.ApplyProfessions then TF:ApplyProfessions() end end })

    Rcol:Section("Pull report", "Pull report")
    Rcol:Check("Record pulls", { "report", "enabled" })
    Rcol:Check("Open after each pull", { "report", "autoShow" }, nil, { indent = true })
    Rcol:Check("Also outside dungeons and raids", { "report", "openWorld" }, nil, { indent = true })
    Rcol:Check("Charts", { "report", "charts" },
        "A timeline of the pull (when you were hit with and without your mitigation) and your coverage over recent pulls.",
        { indent = true, onChange = function()
            if ns.Report.frame:IsShown() then ns.Report:Render(ns.Report.shownIndex or 1) end
        end })

    Rcol:Section("Runs", "Runs")
    Rcol:Check("Record dungeon and raid runs", { "runs", "enabled" },
        "Keeps every pull of a dungeon or raid run together, so you can look back at a whole run and compare runs. "
        .. "A run ends when you go into another instance, after 15 minutes outside, or with /tf run end.",
        { onChange = function() if ns.Runs then ns.Runs:Check() end end })
    Rcol:Check("Show a summary when a run ends", { "runs", "toast" }, nil, { indent = true })
    Rcol:ActionButton("Open runs", 120, function() win:Hide() ns.Runs:Open() end)

    Rcol:Section("Tanking", "Tanking")
    Rcol:Check("Always treat me as the tank", { "tankMode" },
        "Normally TankForgeUI turns on when you're in Defensive Stance, Bear Form or Righteous Fury, "
        .. "or the group made you the tank.", { invert = true })

    BuildAppearance()
    BuildFooter()
    win.log = footer.log

    Relayout()
end

-- Position every header, fold the collapsed sections, and size the window.
Relayout = function()
    if not win then return end
    local top = -50
    local lb = LayoutColumn(Lcol, top)
    local rb = LayoutColumn(Rcol, top)
    local ab = LayoutColumn(appCol, math.min(lb, rb))
    local footerTop = ab - 4
    footer:ClearAllPoints()
    footer:SetPoint("TOPLEFT", LEFT_X, footerTop)
    win:SetSize(WIDTH, -footerTop + footer.h + BOTTOM_MARGIN)
end

--- Open the /tf options window, re-reading every control.
function TF:OpenOptions()
    if not win then Build() end
    for _, c in ipairs(controls) do c:Refresh() end
    win:Show()
end

TF:AddCommand("options", function() TF:OpenOptions() end, "- open the options window (same as /tf)", { group = "Setup" })

-- An entry under Options > AddOns that opens the window.
TF:On("LOGIN", function()
    local S = _G.Settings
    if not (S and S.RegisterCanvasLayoutCategory and S.RegisterAddOnCategory) then return end
    local panel = CreateFrame("Frame")
    panel.name = "TankForgeUI"
    local text = Style.Text(panel, 13)
    text:SetPoint("TOPLEFT", 16, -16)
    text:SetText("TankForgeUI's settings have their own window.")
    local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    b:SetSize(180, 26)
    b:SetPoint("TOPLEFT", 16, -44)
    b:SetText("Open TankForgeUI options")
    b:SetScript("OnClick", function()
        if _G.SettingsPanel and _G.SettingsPanel:IsShown() then HideUIPanel(_G.SettingsPanel) end
        TF:OpenOptions()
    end)
    pcall(function()
        local category = S.RegisterCanvasLayoutCategory(panel, "TankForgeUI")
        S.RegisterAddOnCategory(category)
    end)
end)
