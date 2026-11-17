-- Modules/Charts.lua
-- Small flat charts for the pull report and the run window: a pull timeline,
-- vertical bars, and a one-row dot plot. Everything is drawn with pooled flat
-- textures (no lines or rotation), and every mark has a hover tooltip.
local _, ns = ...
local Style = ns.Style
local API = ns.API

local Charts = {}
ns.Charts = Charts

local C = Style.colors

-- Categorical colors for comparing runs, validated as a set on the panel
-- background (all-pairs CVD and normal-vision separation pass for these three).
-- Compare is capped at three runs for that reason; each also gets a letter.
Charts.series = {
    { 0.224, 0.529, 0.898 },  -- blue   #3987e5
    { 0.851, 0.349, 0.149 },  -- orange #d95926
    { 0.098, 0.620, 0.439 },  -- aqua   #199e70
}
Charts.letters = { "A", "B", "C" }

-- Timeline encoding ------------------------------------------------------------
--
-- A pull's timeline is stored as two strings with one character per second:
--   s: "0" idle, "1" being hit with mitigation up, "2" being hit without it,
--      "3" being hit (mitigation not tracked for this class/level)
--   h: hits taken that second, 0-9
Charts.MAX_SECONDS = 900

--- Encode a pull's raw timeline (Tank.lua) as the two strings above, capped at
--- MAX_SECONDS. A second hit with coverage >= 0 counts as covered (ties go to "1").
---@param tl {n: integer, att: table, cov: table, hit: table, trunc: boolean?}|nil
---@param duration number|nil pull length; the timeline is padded to it
---@return EncodedTimeline|nil nil for an empty pull
function Charts.EncodeTimeline(tl, duration)
    if not tl then return nil end
    local n = math.min(math.max(math.ceil(duration or tl.n or 0), tl.n or 0), Charts.MAX_SECONDS)
    if n <= 0 then return nil end
    local s, h = {}, {}
    for i = 1, n do
        local state = "0"
        if tl.att[i] then
            local c = tl.cov[i]
            if c == nil then state = "3" elseif c >= 0 then state = "1" else state = "2" end
        end
        s[i] = state
        h[i] = tostring(math.min(tl.hit[i] or 0, 9))
    end
    return { n = n, s = table.concat(s), h = table.concat(h), trunc = tl.trunc or nil }
end

--- Runs of the same state in the first n characters of a band string.
---@param s string
---@param n integer|nil default #s
---@return {from: integer, to: integer, state: string}[]
function Charts.Spans(s, n)
    n = n or #s
    local out, i = {}, 1
    while i <= n do
        local state = s:sub(i, i)
        local j = i
        while j < n and s:sub(j + 1, j + 1) == state do j = j + 1 end
        out[#out + 1] = { from = i, to = j, state = state }
        i = j + 1
    end
    return out
end

--- Sum per-second hit digits into `cols` columns (each at least one second).
---@param h string one digit per second
---@param n integer seconds
---@param cols integer
---@return integer[] sums, integer peak
function Charts.Bin(h, n, cols)
    local per = n / cols
    local sums, peak = {}, 0
    for c = 1, cols do
        local s0, s1 = math.floor((c - 1) * per) + 1, math.floor(c * per)
        local sum = 0
        for k = s0, math.max(s0, s1) do sum = sum + (tonumber(h:sub(k, k)) or 0) end
        sums[c] = sum
        if sum > peak then peak = sum end
    end
    return sums, peak
end

-- Widget plumbing ------------------------------------------------------------

local function NewWidget(parent, w, h)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(w, h)
    f.tex, f.texUsed = {}, 0
    f.hits, f.hitsUsed = {}, 0
    f.texts, f.textsUsed = {}, 0
    return f
end

local function Reset(f)
    for i = 1, f.texUsed do f.tex[i]:Hide() end
    for i = 1, f.hitsUsed do f.hits[i]:Hide() end
    for i = 1, f.textsUsed do f.texts[i]:Hide() end
    f.texUsed, f.hitsUsed, f.textsUsed = 0, 0, 0
end

-- A flat texture at (x, y) from the widget's bottom-left.
local function Rect(f, x, y, w, h, color, alpha, layer, sub)
    f.texUsed = f.texUsed + 1
    local t = f.tex[f.texUsed]
    if not t then
        t = f:CreateTexture(nil, "ARTWORK")
        t:SetTexture(Style.FLAT)
        f.tex[f.texUsed] = t
    end
    t:SetDrawLayer(layer or "ARTWORK", sub or 0)
    t:SetVertexColor(color[1], color[2], color[3], alpha or color[4] or 1)
    t:ClearAllPoints()
    t:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, y)
    t:SetSize(math.max(w, 1), math.max(h, 1))
    t:Show()
    return t
end

local function Label(f, size, color)
    f.textsUsed = f.textsUsed + 1
    local fs = f.texts[f.textsUsed]
    if not fs then
        fs = Style.Text(f, size or 10)
        f.texts[f.textsUsed] = fs
    end
    fs:SetFont(fs:GetFont(), size or 10, "")
    fs:SetTextColor(unpack(color or C.text))
    fs:ClearAllPoints()
    fs:Show()
    return fs
end

-- An invisible hover target. tip(GameTooltip) fills the tooltip.
local function HitBox(f, x, y, w, h, tip, onClick)
    f.hitsUsed = f.hitsUsed + 1
    local b = f.hits[f.hitsUsed]
    if not b then
        b = CreateFrame("Button", nil, f)
        b:SetScript("OnEnter", function(self)
            if not self.tip then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            self.tip(GameTooltip)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:SetScript("OnClick", function(self) if self.onClick then self.onClick() end end)
        f.hits[f.hitsUsed] = b
    end
    b.tip, b.onClick = tip, onClick
    b:ClearAllPoints()
    b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, y)
    b:SetSize(math.max(w, 1), math.max(h, 1))
    b:SetFrameLevel(f:GetFrameLevel() + 2)
    b:Show()
    return b
end

-- Small color swatch + text, laid out left to right. Returns the end x.
local function Legend(f, x, y, items)
    for _, it in ipairs(items) do
        Rect(f, x, y + 2, 7, 7, it[1], it[2])
        local fs = Label(f, 9, C.muted)
        fs:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x + 10, y)
        fs:SetText(it[3])
        x = x + 10 + (fs:GetStringWidth() or 30) + 10
    end
    return x
end

-- Timeline -------------------------------------------------------------------

local STATE_TEXT = { ["1"] = "Being hit, %s up", ["2"] = "Being hit without %s", ["3"] = "Being hit" }
local BAND_H = 8
local LEGEND_H = 14

--- A pull, left to right: a band showing when you were hit with and without
--- your mitigation, hit counts above it, and amber marks where you died.
--- opts.legend: draw a legend row on top (adds 14px to the height).
--- The pull timeline: a band (mitigation up / hit without it / untracked), hit
--- columns above it and death markers. opts.legend adds a legend row.
---@return table frame with :SetData(tl, deaths, amName)
function Charts.Timeline(parent, w, h, opts)
    opts = opts or {}
    local total = h + (opts.legend and LEGEND_H or 0)
    local f = NewWidget(parent, w, total)
    f.bg = Style.Flat(f, "BACKGROUND", C.barBg)
    f.bg:SetPoint("BOTTOMLEFT")
    f.bg:SetSize(w, h)

    -- tl: an encoded timeline; deaths: { {t=seconds}, ... }; amName: for tooltips.
    function f:SetData(tl, deaths, amName)
        Reset(self)
        if opts.legend then
            Legend(self, 0, h + 3, {
                { C.mitigation, 1, (amName or "Mitigation") .. " up" },
                { C.bad, 1, "Hit without it" },
                { C.muted, 0.8, "Hits / sec" },
            })
        end
        if not tl or not tl.n or tl.n <= 0 then return end
        local n = tl.n
        local scale = w / n
        local am = amName or "mitigation"

        -- Band: one rect per run of the same state.
        for _, span in ipairs(Charts.Spans(tl.s, n)) do
            local i, j, state = span.from, span.to, span.state
            local x0, x1 = (i - 1) * scale, j * scale
            if state ~= "0" then
                local color = state == "1" and C.mitigation or state == "2" and C.bad or C.muted
                Rect(self, x0, 0, x1 - x0, BAND_H, color, state == "3" and 0.6 or 1)
            end
            local a, b, st = i, j, state
            HitBox(self, x0, 0, x1 - x0, h, function(tt)
                tt:SetText(API.FormatSeconds(a - 1) .. " - " .. API.FormatSeconds(b), 1, 1, 1)
                if st == "0" then
                    tt:AddLine("Not being hit", C.muted[1], C.muted[2], C.muted[3])
                else
                    local c = st == "1" and C.mitigation or st == "2" and C.bad or C.text
                    tt:AddLine(string.format(STATE_TEXT[st], am), c[1], c[2], c[3])
                end
                local hits = 0
                for k = a, b do hits = hits + (tonumber(tl.h:sub(k, k)) or 0) end
                tt:AddLine(hits .. " hit" .. (hits == 1 and "" or "s"), 1, 1, 1)
            end)
        end

        -- Hit columns: bin seconds into columns at least 3px wide.
        local cols = math.max(1, math.min(n, math.floor(w / 3)))
        local sums, peak = Charts.Bin(tl.h, n, cols)
        local colW = w / cols
        local top = h - BAND_H - 3
        if peak > 0 then
            for c = 1, cols do
                if sums[c] > 0 then
                    local bh = math.max(2, sums[c] / peak * top)
                    Rect(self, (c - 1) * colW + 0.5, BAND_H + 2, math.max(colW - 1, 1), bh, C.muted, 0.8)
                end
            end
        end

        -- Deaths
        for _, d in ipairs(deaths or {}) do
            local t = type(d) == "table" and d.t or d
            if t and t <= n then
                Rect(self, math.min(t * scale, w - 2), 0, 2, h, C.accent, 1, "OVERLAY")
            end
        end
    end
    return f
end

-- Bars -----------------------------------------------------------------------

--- Vertical bars from a common baseline.
--- items: { value = number|nil, weight = width share (default 1), color = {r,g,b},
---          outline = color|nil, tip = fn(GameTooltip), onClick = fn }
--- opts: max (top of the scale), ref (a dashed-looking reference level), gap px.
---@return table frame with :SetData(items, opts)
function Charts.Bars(parent, w, h)
    local f = NewWidget(parent, w, h)
    function f:SetData(items, opts)
        Reset(self)
        opts = opts or {}
        local gap = opts.gap or 2
        local max = opts.max
        if not max then
            max = 0
            for _, it in ipairs(items) do if (it.value or 0) > max then max = it.value end end
        end
        if max <= 0 then max = 1 end
        local totalW = 0
        for _, it in ipairs(items) do totalW = totalW + (it.weight or 1) end
        local avail = w - gap * math.max(#items - 1, 0)
        -- Baseline
        Rect(self, 0, 0, w, 1, C.muted, 0.5)
        local x = 0
        for _, it in ipairs(items) do
            local bw = math.max(2, avail * (it.weight or 1) / math.max(totalW, 1))
            if it.value then
                local bh = math.max(2, math.min(it.value / max, 1) * (h - 2))
                if it.outline then
                    Rect(self, x - 1, 0, bw + 2, bh + 2, it.outline, 1, "ARTWORK", -1)
                end
                Rect(self, x, 1, bw, bh, it.color or C.mitigation)
            else
                Rect(self, x, 1, bw, 2, C.muted, 0.6)
            end
            HitBox(self, x, 0, bw + gap, h, it.tip, it.onClick)
            x = x + bw + gap
        end
        if opts.ref and opts.ref > 0 and opts.ref <= max then
            -- A dotted reference line: short dashes so it reads as a guide, not data.
            local y = opts.ref / max * (h - 2) + 1
            for dx = 0, w - 1, 6 do Rect(self, dx, y, 3, 1, C.text, 0.55, "OVERLAY") end
        end
    end
    return f
end

-- Dot plot -------------------------------------------------------------------

local function MakeRound(f, t)
    if not f.CreateMaskTexture then return end
    local ok, mask = pcall(f.CreateMaskTexture, f)
    if not ok or not mask then return end
    mask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(t)
    t:AddMaskTexture(mask)
end

--- One row: a faint track with a dot per series on a shared scale.
--- points: { value, color, letter, tip = fn(GameTooltip) }
---@return table frame with :SetData(points)
function Charts.Dots(parent, w, h)
    local f = NewWidget(parent, w, h)
    f.dots = {}
    local DOT = 9
    local function Dot(i)
        local d = f.dots[i]
        if d then return d end
        d = {}
        d.ring = f:CreateTexture(nil, "ARTWORK", nil, 1)
        d.ring:SetTexture(Style.FLAT)
        d.ring:SetSize(DOT + 4, DOT + 4)
        MakeRound(f, d.ring)
        d.dot = f:CreateTexture(nil, "ARTWORK", nil, 2)
        d.dot:SetTexture(Style.FLAT)
        d.dot:SetSize(DOT, DOT)
        MakeRound(f, d.dot)
        d.dot:SetPoint("CENTER", d.ring, "CENTER")
        f.dots[i] = d
        return d
    end

    function f:SetData(points)
        Reset(self)
        for _, d in ipairs(self.dots) do d.ring:Hide() d.dot:Hide() end
        local cy = math.floor(h / 2) - 4
        Rect(self, 0, cy, w, 1, C.muted, 0.35)
        local lo, hi
        for _, p in ipairs(points) do
            if p.value then
                lo = lo and math.min(lo, p.value) or p.value
                hi = hi and math.max(hi, p.value) or p.value
            end
        end
        if not lo then return end
        local span = hi - lo
        if span <= 0 then span = math.max(math.abs(hi), 1) lo = lo - span / 2 end
        lo = lo - span * 0.12
        span = span * 1.24
        local inner = w - DOT - 4
        local placed = {}
        for i, p in ipairs(points) do
            if p.value then
                local x = (p.value - lo) / span * inner + (DOT + 4) / 2
                local d = Dot(i)
                d.ring:ClearAllPoints()
                d.ring:SetPoint("CENTER", self, "BOTTOMLEFT", x, cy + 0.5)
                d.ring:SetVertexColor(unpack(C.bg))
                d.ring:SetAlpha(1)
                d.dot:SetVertexColor(p.color[1], p.color[2], p.color[3], 1)
                d.ring:Show()
                d.dot:Show()
                -- Letter beside the dot; flip below when it would collide.
                local below = false
                for _, px in ipairs(placed) do
                    if math.abs(px.x - x) < 12 and not px.below then below = true end
                end
                placed[#placed + 1] = { x = x, below = below }
                local fs = Label(self, 9, C.text)
                if below then
                    fs:SetPoint("TOP", self, "BOTTOMLEFT", x, cy - 5)
                else
                    fs:SetPoint("BOTTOM", self, "BOTTOMLEFT", x, cy + 6)
                end
                fs:SetText(p.letter or "")
                HitBox(self, x - 8, 0, 16, h, p.tip)
            end
        end
    end
    return f
end

-- Segment control --------------------------------------------------------------

--- A row of flat buttons where one is lit amber, like the options' choice rows.
---@param labels string[]
---@param onSelect fun(index: integer)
---@return table frame with :Select(index)
function Charts.Segment(parent, labels, width, onSelect)
    local seg = { buttons = {}, selected = 1 }
    local gap = 4
    local bw = math.floor((width - gap * (#labels - 1)) / #labels)
    local function Refresh()
        for i, b in ipairs(seg.buttons) do
            local on = i == seg.selected
            local col = on and C.accent or C.muted
            b.label:SetTextColor(col[1], col[2], col[3])
            Style.SetBorderColor(b, unpack(on and Style.HOVER or Style.BORDER))
            b.bg:SetVertexColor(on and 0.17 or 0.13, on and 0.15 or 0.14, on and 0.12 or 0.17, 1)
        end
    end
    for i, text in ipairs(labels) do
        local b = Style.Button(parent, text, bw, 22, function()
            seg:Select(i)
            if onSelect then onSelect(i) end
        end)
        b:HookScript("OnLeave", Refresh)
        b:SetPoint("TOPLEFT", (i - 1) * (bw + gap), 0)
        seg.buttons[i] = b
    end
    function seg:Select(i)
        self.selected = i
        Refresh()
    end
    function seg:SetPoint(...)
        local first = self.buttons[1]
        first:ClearAllPoints()
        first:SetPoint(...)
        for i = 2, #self.buttons do
            self.buttons[i]:ClearAllPoints()
            self.buttons[i]:SetPoint("LEFT", self.buttons[i - 1], "RIGHT", gap, 0)
        end
    end
    Refresh()
    return seg
end
