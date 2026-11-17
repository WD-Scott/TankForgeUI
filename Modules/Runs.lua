-- Modules/Runs.lua
-- Whole dungeon and raid runs (Options > Runs, off by default). Every pull of
-- a run is kept together; when the run ends a small summary offers the run's
-- report or a comparison with earlier runs. /tf runs opens the window.
--
-- A run starts when you enter a dungeon or raid and ends when you enter a
-- different one, after 15 minutes outside (corpse runs and hearthing back
-- don't end it), or with /tf run end. Runs with fewer than 3 pulls are dropped.
local _, ns = ...
local TF = ns.TF
local API = ns.API
local Style = ns.Style
local Charts = ns.Charts
local Report = ns.Report

local Runs = {}
ns.Runs = Runs

local TIMEOUT = 15 * 60
local MIN_PULLS = 3
local WIDTH = 480
local PAD = 12
local CW = WIDTH - 2 * PAD
local C = Style.colors
local MUTED = "|cff" .. Style.HEX.muted

local function Round(v, digits)
    local m = 10 ^ (digits or 1)
    return math.floor((v or 0) * m + 0.5) / m
end

local function Plural(n, word)
    return n .. " " .. word .. (n == 1 and "" or "s")
end

-- Recording ------------------------------------------------------------------

local function InDungeon(info) return info.type == "party" or info.type == "raid" end
local function Key(info) return tostring(info.id or info.name or "?") .. ":" .. tostring(info.difficultyID or 0) end

----- Begin a run in the instance described by API.InstanceInfo().
local function Start(info)
    local now = time()
    TF.db.currentRun = {
        id = now, key = Key(info),
        instance = info.name or API.PlainString(GetRealZoneText and GetRealZoneText()) or "?",
        instanceID = info.id, difficultyID = info.difficultyID, difficulty = info.difficulty, size = info.size,
        start = now, lastSeen = now, pulls = {}, bosses = {},
    }
end

--- reason: "new", "timeout", "command" or "disabled".
----- End the current run: kept in runHistory (and toasted) when it had enough pulls.
local function Finish(reason)
    local run = TF.db.currentRun
    if not run then return end
    TF.db.currentRun = nil
    run.finish = run.leftAt or run.lastSeen or time()
    run.leftAt, run.lastSeen = nil, nil
    if #run.pulls < MIN_PULLS then
        if reason == "command" then
            TF:Print(string.format("run ended. It had %s, so it wasn't kept (runs need %d).",
                Plural(#run.pulls, "pull"), MIN_PULLS))
        end
        return
    end
    local list = TF.db.runHistory
    table.insert(list, 1, run)
    while #list > (TF.db.runs.keep or 25) do table.remove(list) end
    if reason == "command" then TF:Print("run ended and saved. /tf runs to see it.") end
    if reason ~= "disabled" and TF.db.runs.toast then
        TF:AfterCombat(function() Runs:Toast(run) end)
    end
end

local timeoutPending = false
local function ScheduleTimeout(seconds)
    if timeoutPending then return end
    timeoutPending = true
    C_Timer.After(math.max(seconds, 0) + 1, function()
        timeoutPending = false
        Runs:Check()
    end)
end

--- Start, continue or end the current run from where you are now.
--- isLogin: a fresh login (not a /reload), when a run left open too long ends.
--- Start, continue or end the current run from where you are now. A run ends
--- on entering a different instance, after TIMEOUT outside, or (on a fresh
--- login) when it was last seen more than TIMEOUT ago.
---@param isLogin boolean|nil
function Runs:Check(isLogin)
    if not TF.db then return end
    local run = TF.db.currentRun
    if not TF.db.runs.enabled then
        if run then Finish("disabled") end
        return
    end
    local now = time()
    if run and ((isLogin and now - (run.lastSeen or run.start) > TIMEOUT)
            or (run.leftAt and now - run.leftAt >= TIMEOUT)) then
        Finish("timeout")
        run = nil
    end
    local info = API.InstanceInfo()
    if InDungeon(info) then
        if run and run.key ~= Key(info) then
            Finish("new")
            run = nil
        end
        if run then run.leftAt = nil else Start(info) end
        TF.db.currentRun.lastSeen = now
    elseif run then
        run.leftAt = run.leftAt or now
        ScheduleTimeout(TIMEOUT - (now - run.leftAt))
    end
end

TF:On("PULL_END", function(p)
    local run = TF.db.currentRun
    if not run or not TF.db.runs.enabled then return end
    if not p.instance or p.duration < Report.MIN_SECONDS or p.hits < 3 then return end
    run.am = p.primaryName or run.am
    run.target = p.primaryTarget or run.target
    local deaths = {}
    for _, d in ipairs(p.deaths) do deaths[#deaths + 1] = Round(d.t) end
    run.pulls[#run.pulls + 1] = {
        t = p.time, d = Round(p.duration), boss = p.encounter,
        hits = p.hits, rel = p.hitsRelevant, unmit = p.hitsUnmitigated,
        ua = Round(p.underAttack), cov = Round(p.covered), gap = Round(p.longestGap),
        known = p.primaryKnown and true or nil,
        taunts = p.taunts, ints = p.interrupts, lost = p.aggroLost, heal = Round(p.healerAttacked),
        deaths = deaths,
        tl = Charts.EncodeTimeline(p.tl, p.duration),
    }
    run.lastSeen = time()
end)

TF:RegisterEvent("ENCOUNTER_END", function(_, _, name, _, _, success)
    local run = TF.db and TF.db.currentRun
    if not run then return end
    run.bosses[#run.bosses + 1] = { name = API.PlainString(name) or "?", ok = API.PlainNumber(success) == 1, t = time() }
end)

TF:On("ENTERING_WORLD", function(isLogin) Runs:Check(isLogin) end)
TF:RegisterEvent("ZONE_CHANGED_NEW_AREA", function() Runs:Check() end)
TF:RegisterEvent("PLAYER_LOGOUT", function()
    local run = TF.db and TF.db.currentRun
    if run and not run.leftAt then run.lastSeen = time() end
end)

-- Metrics --------------------------------------------------------------------

--- Totals and per-minute rates for a run. Rates are per minute of combat, so
--- a slow clear and a fast one compare fairly.
---@param run RunRecord
---@return table totals, rates and boss counts (coverage, unmitPM, ... nil when untracked)
function Runs.Metrics(run)
    local m = { pulls = #run.pulls, combat = 0, ua = 0, cov = 0, unmit = 0, lost = 0, heal = 0, ints = 0,
        deaths = 0, longest = 0 }
    local known = false
    for _, p in ipairs(run.pulls) do
        m.combat = m.combat + p.d
        if p.known then
            known = true
            m.ua = m.ua + p.ua
            m.cov = m.cov + p.cov
            if p.gap > m.longest then m.longest = p.gap end
        end
        m.unmit = m.unmit + p.unmit
        m.lost = m.lost + p.lost
        m.heal = m.heal + p.heal
        m.ints = m.ints + p.ints
        m.deaths = m.deaths + #p.deaths
    end
    local mins = m.combat / 60
    local function PerMin(v) return mins > 0 and v / mins or 0 end
    m.clear = (run.finish or time()) - run.start
    m.coverage = known and Report.Pct(m.cov, m.ua) or nil
    m.longest = known and m.longest or nil
    m.unmitPM = known and PerMin(m.unmit) or nil
    m.lostPM = PerMin(m.lost)
    m.healPM = PerMin(m.heal)
    m.intsPM = PerMin(m.ints)
    local killed, seen = {}, {}
    m.bosses, m.bossTotal, m.wipes = 0, 0, 0
    for _, b in ipairs(run.bosses or {}) do
        if not seen[b.name] then seen[b.name] = true m.bossTotal = m.bossTotal + 1 end
        if b.ok and not killed[b.name] then killed[b.name] = true m.bosses = m.bosses + 1 end
        if not b.ok then m.wipes = m.wipes + 1 end
    end
    return m
end

local CovColor = Report.CoverageColorFor

local function Hex(c) return "|cff" .. Style.Hex(c) end

local function RunTitle(run)
    return run.instance .. (run.difficulty and (MUTED .. "  " .. run.difficulty .. "|r") or "")
end

local function Headline(run, m)
    local parts = { API.FormatSeconds(m.clear) }
    if m.coverage then parts[#parts + 1] = Hex(CovColor(m.coverage, run.target)) .. m.coverage .. "%|r coverage" end
    parts[#parts + 1] = Plural(m.deaths, "death")
    if m.bossTotal > 0 then parts[#parts + 1] = m.bosses .. "/" .. m.bossTotal .. " bosses" end
    return table.concat(parts, MUTED .. "  ·  |r")
end

-- End-of-run summary ---------------------------------------------------------------

local toast = Style.Panel(UIParent, "TankForgeUIRunToast")
toast:SetSize(300, 84)
toast:SetFrameStrata("MEDIUM")
toast:EnableMouse(true)
toast:Hide()
toast.title = Style.Text(toast, 13)
toast.title:SetPoint("TOPLEFT", PAD, -PAD)
toast.title:SetPoint("RIGHT", toast, "RIGHT", -28, 0)
toast.title:SetJustifyH("LEFT")
toast.line = Style.Text(toast, 11)
toast.line:SetPoint("TOPLEFT", toast.title, "BOTTOMLEFT", 0, -4)
toast.close = CreateFrame("Button", nil, toast, "UIPanelCloseButton")
toast.close:SetSize(22, 22)
toast.close:SetPoint("TOPRIGHT", -2, -2)
toast.close:SetScript("OnClick", function() toast:Hide() end)
toast.latest = Style.Button(toast, "Latest run", 134, 24, function() toast:Hide() Runs:Open(1, "latest") end)
toast.latest:SetPoint("BOTTOMLEFT", PAD, 10)
toast.compare = Style.Button(toast, "Compare runs", 134, 24, function() toast:Hide() Runs:Open(1, "compare") end)
toast.compare:SetPoint("BOTTOMRIGHT", -PAD, 10)
toast:SetScript("OnUpdate", function(self)
    if self.hideAt and API.Now() >= self.hideAt and not self:IsMouseOver() then
        self.hideAt = nil
        self:Hide()
    end
end)
Style.Movable(toast, "runToast", "Run summary", { "TOP", "TOP", 0, -170 })

--- The small end-of-run summary with buttons to the run's report or a comparison.
---@param run RunRecord
function Runs:Toast(run)
    toast.title:SetText("Run complete: " .. RunTitle(run))
    toast.line:SetText(Headline(run, Runs.Metrics(run)))
    toast:SetScale(TF.db.scale or 1)
    Style.FitAnchor("runToast")
    toast.hideAt = API.Now() + 30
    toast:Show()
end

-- Window ---------------------------------------------------------------------

local win = Style.Panel(UIParent, "TankForgeUIRuns")
win:SetSize(WIDTH, 400)
win:SetFrameStrata("HIGH")
win:EnableMouse(true)
win:Hide()
Runs.frame = win

win.title = Style.Text(win, 14)
win.title:SetPoint("TOPLEFT", PAD, -PAD)
win.title:SetText("Runs")
win.close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
win.close:SetSize(24, 24)
win.close:SetPoint("TOPRIGHT", -2, -2)
win.close:SetScript("OnClick", function() win:Hide() end)

local view = "latest"
local latestIndex = 1
local VIEW_TOP = 66

local seg = Charts.Segment(win, { "Latest run", "Compare" }, 220, function(i)
    Runs:Show(i == 1 and "latest" or "compare")
end)
seg:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -36)

local function View()
    local v = CreateFrame("Frame", nil, win)
    v:SetPoint("TOPLEFT", 0, -VIEW_TOP)
    v:SetPoint("RIGHT")
    v:SetHeight(10)
    v:Hide()
    return v
end

local function Muted(parent, size)
    local fs = Style.Text(parent, size or 10)
    fs:SetTextColor(unpack(C.muted))
    fs:SetJustifyH("LEFT")
    return fs
end

local function Pager(parent)
    local p = {}
    p.prev = Style.Button(parent, "<", 28, 20, function() if p.onPrev then p.onPrev() end end)
    p.next = Style.Button(parent, ">", 28, 20, function() if p.onNext then p.onNext() end end)
    p.next:SetPoint("LEFT", p.prev, "RIGHT", 4, 0)
    p.text = Muted(parent, 10)
    p.text:SetPoint("LEFT", p.next, "RIGHT", 8, 0)
    function p:Set(text, canPrev, canNext)
        self.text:SetText(text)
        self.prev:SetEnabled(canPrev)
        self.next:SetEnabled(canNext)
        self.prev:SetAlpha(canPrev and 1 or 0.35)
        self.next:SetAlpha(canNext and 1 or 0.35)
    end
    return p
end

-- Latest run view ------------------------------------------------------------

local L = View()
L.title = Style.Text(L, 13)
L.title:SetPoint("TOPLEFT", PAD, 0)
L.title:SetPoint("RIGHT", L, "RIGHT", -PAD, 0)
L.title:SetJustifyH("LEFT")
L.sub = Muted(L, 10)
L.sub:SetPoint("TOPLEFT", L.title, "BOTTOMLEFT", 0, -3)

L.kpis = {}
local KPI_W = CW / 3
for i = 1, 6 do
    local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
    local k = {}
    k.label = Muted(L, 10)
    k.label:SetPoint("TOPLEFT", L, "TOPLEFT", PAD + col * KPI_W, -(36 + row * 36))
    k.label:SetWidth(KPI_W - 6)
    k.value = Style.Text(L, 15)
    k.value:SetPoint("TOPLEFT", k.label, "BOTTOMLEFT", 0, -2)
    L.kpis[i] = k
end
local y = 36 + 2 * 36 + 4
L.pullsHead = Muted(L, 10)
L.pullsHead:SetPoint("TOPLEFT", PAD, -y)
L.pullsHead:SetWidth(CW)
y = y + 15
L.bars = Charts.Bars(L, CW, 56)
L.bars:SetPoint("TOPLEFT", PAD, -y)
y = y + 56 + 12
L.tlHead = Style.Text(L, 11)
L.tlHead:SetPoint("TOPLEFT", PAD, -y)
L.tlHead:SetJustifyH("LEFT")
y = y + 16
L.timeline = Charts.Timeline(L, CW, 30, { legend = true })
L.timeline:SetPoint("TOPLEFT", PAD, -y)
y = y + L.timeline:GetHeight() + 12
L.pager = Pager(L)
L.pager.prev:SetPoint("TOPLEFT", PAD, -y)
L:SetHeight(y + 20)

local selectedPull

local function ShowPull(run, i)
    selectedPull = i
    local p = run.pulls[i]
    if not p then return end
    local parts = { "Pull " .. i }
    if p.boss then parts[#parts + 1] = Hex(C.accent) .. p.boss .. "|r" end
    parts[#parts + 1] = MUTED .. API.FormatSeconds(p.d) .. "|r"
    L.tlHead:SetText(table.concat(parts, "  "))
    L.timeline:SetShown(p.tl ~= nil)
    L.timeline:SetData(p.tl, p.deaths, run.am)
end

function Runs:RenderLatest()
    local list = TF.db.runHistory
    local run = list[latestIndex]
    if not run then return end
    local m = Runs.Metrics(run)
    L.title:SetText(RunTitle(run))
    L.sub:SetText(Report.When(run.start) .. "  ·  " .. Plural(m.pulls, "pull") .. "  ·  "
        .. API.FormatSeconds(m.combat) .. " in combat")
    local am = run.am or "Mitigation"
    local kpis = {
        { "Clear time", API.FormatSeconds(m.clear) },
        { am .. " coverage", m.coverage and (Hex(CovColor(m.coverage, run.target)) .. m.coverage .. "%|r") or "-" },
        { "Hits without it / min", m.unmitPM and string.format("%.1f", m.unmitPM) or "-" },
        { "Mobs lost / min", string.format("%.2f", m.lostPM) },
        { "Deaths", (m.deaths > 0 and Hex(C.bad) or "") .. m.deaths .. (m.deaths > 0 and "|r" or "") },
        { "Bosses killed", m.bossTotal > 0 and (m.bosses .. " of " .. m.bossTotal) or "-" },
    }
    for i, k in ipairs(L.kpis) do
        k.label:SetText(kpis[i][1])
        k.value:SetText(kpis[i][2])
    end

    L.pullsHead:SetText("Pulls: width is length, height is coverage, amber is a boss. Click one.")
    local items = {}
    if not run.pulls[selectedPull or 0] then selectedPull = 1 end
    for i, p in ipairs(run.pulls) do
        local cov = p.known and Report.Pct(p.cov, p.ua) or nil
        items[i] = {
            value = cov, weight = math.max(p.d, 4), color = CovColor(cov, run.target),
            outline = i == selectedPull and C.text or (p.boss and C.accent) or nil,
            onClick = function()
                selectedPull = i
                Runs:RenderLatest()
            end,
            tip = function(tt)
                tt:SetText("Pull " .. i .. (p.boss and (": " .. p.boss) or ""), 1, 1, 1)
                tt:AddLine(API.FormatSeconds(p.d) .. "  ·  " .. Plural(p.hits, "hit"), C.muted[1], C.muted[2], C.muted[3])
                tt:AddLine(am .. " coverage: " .. (cov and (cov .. "%") or "-"), 1, 1, 1)
                if p.known then tt:AddLine(string.format("Longest gap: %.1fs", p.gap), 1, 1, 1) end
                if p.lost > 0 then tt:AddLine("Mobs lost: " .. p.lost, 1, 1, 1) end
                if #p.deaths > 0 then tt:AddLine(Plural(#p.deaths, "death"), C.bad[1], C.bad[2], C.bad[3]) end
            end,
        }
    end
    L.bars:SetData(items, { max = 100, ref = (run.target or 0.75) * 100, gap = 2 })
    ShowPull(run, selectedPull)

    local n = #TF.db.runHistory
    L.pager:Set(string.format("Run %d of %d", n - latestIndex + 1, n), latestIndex < n, latestIndex > 1)
    return L:GetHeight()
end

L.pager.onPrev = function() latestIndex = latestIndex + 1 selectedPull = nil Runs:Show("latest") end
L.pager.onNext = function() latestIndex = latestIndex - 1 selectedPull = nil Runs:Show("latest") end

-- Compare view ---------------------------------------------------------------

local MAX_SELECTED = #Charts.series
local PICK_W = 196
local ROWS = 9
local RIGHT_X = PAD + PICK_W + 16
local RIGHT_W = WIDTH - RIGHT_X - PAD

local Cmp = View()
local sel = {}        -- slot (1..3) -> run id
local sameOnly = true
local pickPage = 1

local function RunById(id)
    for _, run in ipairs(TF.db.runHistory) do
        if run.id == id then return run end
    end
end

local function SlotOf(id)
    for slot = 1, MAX_SELECTED do
        if sel[slot] == id then return slot end
    end
end

-- Drop runs that no longer exist; pick defaults when nothing is chosen: the
-- latest run and the two before it in the same instance, oldest as A.
local function EnsureSelection()
    for slot = 1, MAX_SELECTED do
        if sel[slot] and not RunById(sel[slot]) then sel[slot] = nil end
    end
    if next(sel) then return end
    local list = TF.db.runHistory
    local latest = list[latestIndex] or list[1]
    if not latest then return end
    local picks = {}
    for _, run in ipairs(list) do
        if run.key == latest.key and #picks < MAX_SELECTED then picks[#picks + 1] = run end
    end
    for i = #picks, 1, -1 do sel[#picks - i + 1] = picks[i].id end
end

local function BaseKey()
    local base = sel[1] and RunById(sel[1])
    if base then return base.key end
    for slot = 2, MAX_SELECTED do
        local r = sel[slot] and RunById(sel[slot])
        if r then return r.key end
    end
    local latest = TF.db.runHistory[1]
    return latest and latest.key
end

local function Filtered()
    local out, key = {}, BaseKey()
    for _, run in ipairs(TF.db.runHistory) do
        if not sameOnly or run.key == key then out[#out + 1] = run end
    end
    return out
end

Cmp.filter = Style.Button(Cmp, "", PICK_W, 22, function()
    sameOnly = not sameOnly
    pickPage = 1
    Runs:Show("compare")
end)
Cmp.filter:SetPoint("TOPLEFT", PAD, 0)
Cmp.filter.title = "Which runs to list"
Cmp.filter.note = "Comparing runs of different instances isn't apples to apples; the same dungeon is the fair comparison."
Cmp.hint = Muted(Cmp, 10)
Cmp.hint:SetPoint("TOPLEFT", PAD, -27)
Cmp.hint:SetText("Click to pick up to " .. MAX_SELECTED .. " runs.")

Cmp.rows = {}
for i = 1, ROWS do
    local b = Style.Button(Cmp, "", PICK_W, 30, function() end)
    b:SetPoint("TOPLEFT", PAD, -(42 + (i - 1) * 33))
    b.label:ClearAllPoints()
    b.label:SetPoint("TOPLEFT", 10, -4)
    b.label:SetPoint("RIGHT", b, "RIGHT", -20, 0)
    b.label:SetJustifyH("LEFT")
    b.label:SetFont(b.label:GetFont(), 11, "")
    b.sub = Muted(b, 9)
    b.sub:SetPoint("BOTTOMLEFT", 10, 4)
    b.swatch = Style.Flat(b, "ARTWORK", C.muted)
    b.swatch:SetPoint("TOPLEFT", 1, -1)
    b.swatch:SetPoint("BOTTOMLEFT", 1, 1)
    b.swatch:SetWidth(4)
    b.letter = Style.Text(b, 12)
    b.letter:SetPoint("RIGHT", -8, 0)
    Cmp.rows[i] = b
end
Cmp.pager = Pager(Cmp)
Cmp.pager.prev:SetPoint("TOPLEFT", PAD, -(42 + ROWS * 33 + 2))
Cmp.pager.onPrev = function() pickPage = pickPage - 1 Runs:Show("compare") end
Cmp.pager.onNext = function() pickPage = pickPage + 1 Runs:Show("compare") end

local function Toggle(run)
    local slot = SlotOf(run.id)
    if slot then
        sel[slot] = nil
    else
        for s = 1, MAX_SELECTED do
            if not sel[s] then
                sel[s] = run.id
                slot = s
                break
            end
        end
        if not slot then
            Cmp.hint:SetText(Hex(C.warn) .. "Up to " .. MAX_SELECTED .. " runs. Unpick one first.|r")
            return
        end
    end
    Runs:Show("compare")
end

--- How a compared run differs from the base run on one metric.
---@param def {lower: boolean} lower is better when true
---@param v number
---@param base number
---@return number delta, boolean better, boolean same
function Runs.Delta(def, v, base)
    local d = v - base
    local better = (def.lower and d < 0) or (not def.lower and d > 0)
    return d, better, math.abs(d) < 1e-6
end

local METRICS = {
    { key = "clear", label = "Clear time", lower = true,
      fmt = function(v) return API.FormatSeconds(v) end,
      delta = function(d) return (d < 0 and "-" or "+") .. API.FormatSeconds(math.abs(d)) end },
    { key = "coverage", label = "Mitigation coverage", lower = false,
      fmt = function(v) return v .. "%" end,
      delta = function(d) return string.format("%+d pts", d) end },
    { key = "unmitPM", label = "Hits without it / min", lower = true,
      fmt = function(v) return string.format("%.1f", v) end,
      delta = function(d) return string.format("%+.1f", d) end },
    { key = "lostPM", label = "Mobs lost / min", lower = true,
      fmt = function(v) return string.format("%.2f", v) end,
      delta = function(d) return string.format("%+.2f", d) end },
    { key = "longest", label = "Longest gap", lower = true,
      fmt = function(v) return string.format("%.1fs", v) end,
      delta = function(d) return string.format("%+.1fs", d) end },
    { key = "deaths", label = "Deaths", lower = true,
      fmt = function(v) return tostring(v) end,
      delta = function(d) return string.format("%+d", d) end },
}
Runs.METRICS = METRICS
local METRIC_H = 42

Cmp.head = Muted(Cmp, 10)
Cmp.head:SetPoint("TOPLEFT", RIGHT_X, -4)
Cmp.head:SetWidth(RIGHT_W)
Cmp.metrics = {}
for i, def in ipairs(METRICS) do
    local row = {}
    local top = 22 + (i - 1) * METRIC_H
    row.label = Style.Text(Cmp, 11)
    row.label:SetPoint("TOPLEFT", RIGHT_X, -top)
    row.label:SetText(def.label)
    row.delta = Style.Text(Cmp, 10)
    row.delta:SetPoint("TOPRIGHT", Cmp, "TOPLEFT", RIGHT_X + RIGHT_W, -(top + 1))
    row.delta:SetJustifyH("RIGHT")
    row.dots = Charts.Dots(Cmp, RIGHT_W, 26)
    row.dots:SetPoint("TOPLEFT", RIGHT_X, -(top + 14))
    Cmp.metrics[i] = row
end
Cmp.warning = Muted(Cmp, 10)
Cmp.warning:SetPoint("TOPLEFT", RIGHT_X, -(22 + #METRICS * METRIC_H + 2))
Cmp.warning:SetWidth(RIGHT_W)
Cmp.warning:SetWordWrap(true)
Cmp:SetHeight(42 + ROWS * 33 + 30)

function Runs:RenderCompare()
    EnsureSelection()
    -- Picker
    Cmp.filter.label:SetText(sameOnly and "Showing: same instance" or "Showing: all instances")
    local list = Filtered()
    local pages = math.max(1, math.ceil(#list / ROWS))
    pickPage = math.min(math.max(pickPage, 1), pages)
    for i, b in ipairs(Cmp.rows) do
        local run = list[(pickPage - 1) * ROWS + i]
        b:SetShown(run ~= nil)
        if run then
            local slot = SlotOf(run.id)
            local m = Runs.Metrics(run)
            b.label:SetText(run.instance .. (run.difficulty and (MUTED .. " " .. run.difficulty .. "|r") or ""))
            b.sub:SetText(date("%b %d %H:%M", run.start) .. "  ·  " .. API.FormatSeconds(m.clear))
            local col = slot and Charts.series[slot] or C.muted
            b.swatch:SetVertexColor(col[1], col[2], col[3], slot and 1 or 0.25)
            b.letter:SetText(slot and Charts.letters[slot] or "")
            b.bg:SetVertexColor(slot and 0.17 or 0.13, slot and 0.17 or 0.14, slot and 0.19 or 0.17, 1)
            b:SetScript("OnClick", function() Toggle(run) end)
        end
    end
    Cmp.pager:Set(#list == 0 and "No runs" or string.format("%d-%d of %d", (pickPage - 1) * ROWS + 1,
        math.min(pickPage * ROWS, #list), #list), pickPage > 1, pickPage < pages)

    -- Small multiples
    local chosen, keys, count = {}, {}, 0
    for slot = 1, MAX_SELECTED do
        local run = sel[slot] and RunById(sel[slot])
        if run then
            chosen[slot] = { run = run, m = Runs.Metrics(run) }
            keys[run.key] = true
            count = count + 1
        end
    end
    local baseSlot
    for slot = 1, MAX_SELECTED do if chosen[slot] then baseSlot = slot break end end
    if count == 0 then
        Cmp.head:SetText("Pick runs on the left to compare them.")
    elseif count == 1 then
        Cmp.head:SetText("Pick another run to compare against " .. Charts.letters[baseSlot] .. ".")
    else
        Cmp.head:SetText("Differences from " .. Charts.letters[baseSlot] .. Hex(C.good) .. "  green is better|r"
            .. MUTED .. ". Hover a dot for its value.|r")
    end
    for i, def in ipairs(METRICS) do
        local row = Cmp.metrics[i]
        local points, deltas = {}, {}
        local base = baseSlot and chosen[baseSlot].m[def.key]
        for slot = 1, MAX_SELECTED do
            local c = chosen[slot]
            if c then
                local v = c.m[def.key]
                local letter = Charts.letters[slot]
                points[#points + 1] = {
                    value = v, color = Charts.series[slot], letter = letter,
                    tip = function(tt)
                        tt:SetText(letter .. ": " .. c.run.instance, 1, 1, 1)
                        tt:AddLine(date("%b %d %H:%M", c.run.start), C.muted[1], C.muted[2], C.muted[3])
                        tt:AddLine(def.label .. ": " .. (v and def.fmt(v) or "-"), 1, 1, 1)
                    end,
                }
                if slot ~= baseSlot then
                    if v and base then
                        local d, better, same = Runs.Delta(def, v, base)
                        local color = same and C.muted or (better and C.good or C.bad)
                        deltas[#deltas + 1] = letter .. " " .. Hex(color) .. def.delta(d) .. "|r"
                    else
                        deltas[#deltas + 1] = letter .. " " .. MUTED .. "-|r"
                    end
                end
            end
        end
        row.delta:SetText(table.concat(deltas, "   "))
        row.dots:SetData(points)
    end
    local mixed = 0
    for _ in pairs(keys) do mixed = mixed + 1 end
    Cmp.warning:SetText(mixed > 1 and (Hex(C.warn) .. "These runs are from different instances or difficulties, "
        .. "so the numbers aren't directly comparable.|r") or "")
    return Cmp:GetHeight()
end

-- Opening --------------------------------------------------------------------

---@param which "latest"|"compare"
function Runs:Show(which)
    view = which or view
    seg:Select(view == "latest" and 1 or 2)
    L:SetShown(view == "latest")
    Cmp:SetShown(view == "compare")
    local h = view == "latest" and Runs:RenderLatest() or Runs:RenderCompare()
    win:SetHeight(VIEW_TOP + (h or 200) + PAD)
    win:SetScale(TF.db.scale or 1)
    Style.FitAnchor("runs")
end

--- Open the runs window on runHistory[index].
---@param index integer
---@param which "latest"|"compare"|nil
function Runs:Open(index, which)
    if #TF.db.runHistory == 0 then
        if TF.db.runs.enabled then
            TF:Print("no runs saved yet. A run is saved when it ends (another instance, 15 minutes outside, or /tf run end).")
        else
            TF:Print("no runs saved yet. Turn on Options > Runs > Record dungeon and raid runs.")
        end
        return
    end
    latestIndex = math.min(index or 1, #TF.db.runHistory)
    selectedPull = nil
    if which == "compare" then wipe(sel) end
    Cmp.hint:SetText("Click to pick up to " .. MAX_SELECTED .. " runs.")
    Runs:Show(which or "latest")
    win:Show()
end

Style.Movable(win, "runs", "Runs", { "CENTER", "CENTER", 0, 60 })

TF:AddCommand("runs", function() Runs:Open(1) end, "- your saved dungeon and raid runs, and run comparisons",
    { group = "Tanking" })
TF:AddCommand("run", function(arg)
    arg = (arg or ""):lower()
    local run = TF.db.currentRun
    if arg == "end" then
        if run then Finish("command") else TF:Print("no run in progress.") end
        return
    end
    if not TF.db.runs.enabled then
        TF:Print("run recording is off (Options > Runs).")
    elseif run then
        TF:Print(string.format("recording %s: %s so far%s.", run.instance, Plural(#run.pulls, "pull"),
            run.leftAt and ", you're outside (it ends after 15 minutes)" or ""))
    else
        TF:Print("not in a run. One starts when you enter a dungeon or raid.")
    end
end, "[end] - show the run being recorded, or end it now", { group = "Tanking" })
