-- Modules/Report.lua
-- After each pull: what happened and what to work on. No score.
-- Keeps the last 30 pulls per character; /tf report shows the latest.
local _, ns = ...
local TF = ns.TF
local API = ns.API
local Style = ns.Style
local Tank = ns.Tank

local Report = {}
ns.Report = Report

local KEEP = 30
local MIN_SECONDS = 6
local WIDTH = 310
local PAD = 10
local C = Style.colors

-- Building a record ------------------------------------------------------------

local function Pct(a, b)
    if not b or b <= 0 then return nil end
    return math.floor(a / b * 100 + 0.5)
end

local function Notes(r)
    local notes = {}
    local am = r.primaryName or "Your mitigation"
    if r.primaryKnown and r.underAttack >= 5 and r.coverage then
        local target = math.floor((r.primaryTarget or 0.75) * 100 + 0.5)
        if r.coverage < target then
            notes[#notes + 1] = string.format("%s covered %d%% of the time you were being hit. Aim for %d%%.",
                am, r.coverage, target)
        end
        if r.longestGap >= 4 then
            notes[#notes + 1] = string.format("Longest stretch being hit without %s: %.1fs.", am, r.longestGap)
        end
    end
    if r.aggroLost > 0 then
        local who = {}
        for name, n in pairs(r.aggroLostTo or {}) do
            who[#who + 1] = n > 1 and string.format("%s x%d", name, n) or name
        end
        table.sort(who)
        notes[#notes + 1] = string.format("Mobs went to someone else %d time%s: %s.%s", r.aggroLost,
            r.aggroLost == 1 and "" or "s", table.concat(who, ", "), r.taunts == 0 and " You didn't taunt." or "")
    end
    if r.healerAttacked >= 2 then
        notes[#notes + 1] = string.format("Mobs were on your healer for %.0fs.", r.healerAttacked)
    end
    for _, name in ipairs(r.unusedAM or {}) do
        notes[#notes + 1] = name .. " wasn't used."
    end
    for _, d in ipairs(r.deaths or {}) do
        if #d.ready > 0 then
            notes[#notes + 1] = string.format("Died at %s with %s still ready.", API.FormatSeconds(d.t),
                table.concat(d.ready, ", "))
        else
            notes[#notes + 1] = string.format("Died at %s.", API.FormatSeconds(d.t))
        end
    end
    return notes
end

local function MakeRecord(p)
    local r = {
        time = p.time, zone = p.zone, encounter = p.encounter, duration = p.duration,
        hits = p.hits, hitsRelevant = p.hitsRelevant, hitsUnmitigated = p.hitsUnmitigated,
        underAttack = p.underAttack, longestGap = p.longestGap,
        coverage = Pct(p.covered, p.underAttack),
        primaryName = p.primaryName, primaryTarget = p.primaryTarget, primaryKnown = p.primaryKnown,
        taunts = p.taunts, interrupts = p.interrupts, defensives = p.defensives,
        aggroLost = p.aggroLost, aggroLostTo = p.aggroLostTo,
        healerAttacked = p.healerAttacked, looseTime = p.looseTime, deaths = p.deaths,
        unusedAM = {},
    }
    -- A secondary mitigation (Demoralizing Shout) never pressed in a longer pull.
    if p.duration >= 20 then
        for _, e in ipairs(Tank.am) do
            if e ~= Tank.primary and e.known and not p.casts[e.def.key or e.def.spell] then
                r.unusedAM[#r.unusedAM + 1] = API.GetSpellName(e.spell) or "?"
            end
        end
    end
    r.notes = Notes(r)
    return r
end

-- Window ---------------------------------------------------------------------

local f = Style.Panel(UIParent, "TankForgeUIReport")
f:SetSize(WIDTH, 200)
f:SetFrameStrata("MEDIUM")
f:EnableMouse(true)
f:Hide()
Report.frame = f

f.title = Style.Text(f, 14)
f.title:SetPoint("TOPLEFT", PAD, -PAD)
f.title:SetPoint("RIGHT", f, "RIGHT", -30, 0)
f.title:SetJustifyH("LEFT")
f.when = Style.Text(f, 10)
f.when:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -3)
f.when:SetTextColor(unpack(C.muted))

f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
f.close:SetSize(24, 24)
f.close:SetPoint("TOPRIGHT", -2, -2)
f.close:SetScript("OnClick", function() f:Hide() end)

f.stats = {}
f.notes = {}
local function StatCell(i)
    local cell = f.stats[i]
    if cell then return cell end
    cell = {}
    cell.label = Style.Text(f, 10)
    cell.label:SetTextColor(unpack(C.muted))
    cell.value = Style.Text(f, 13)
    f.stats[i] = cell
    return cell
end

f.workOn = Style.Text(f, 11)
f.workOn:SetText("What to work on")
f.workOn:SetTextColor(unpack(C.accent))

local function NoteLine(i)
    local fs = f.notes[i]
    if fs then return fs end
    fs = Style.Text(f, 11)
    fs:SetWordWrap(true)
    fs:SetJustifyH("LEFT")
    fs:SetWidth(WIDTH - 2 * PAD - 10)
    f.notes[i] = fs
    return fs
end

f.prev = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
f.prev:SetSize(28, 20)
f.prev:SetText("<")
f.next = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
f.next:SetSize(28, 20)
f.next:SetText(">")
f.count = Style.Text(f, 10)
f.count:SetTextColor(unpack(C.muted))

Style.Movable(f, "report", "Pull report", { "RIGHT", "RIGHT", -40, -40 })

local shownIndex = 1   -- 1 = newest

local function When(t)
    if not t then return "" end
    local today = date("%Y%m%d")
    local day = date("%Y%m%d", t)
    return (day == today and "Today " or date("%b %d ", t)) .. date("%H:%M", t)
end

local function CoverageColor(r)
    if not r.coverage then return C.muted end
    local target = (r.primaryTarget or 0.75) * 100
    if r.coverage >= target then return C.good end
    if r.coverage >= target - 15 then return C.warn end
    return C.bad
end

function Report:Render(index)
    local history = TF.db.history
    local r = history[index]
    if not r then return false end
    shownIndex = index

    f.title:SetText((r.encounter or r.zone or "Pull") .. "  |cff" .. Style.Hex(C.muted)
        .. API.FormatSeconds(r.duration) .. "|r")
    f.when:SetText(When(r.time))

    local hex = function(c) return "|cff" .. Style.Hex(c) end
    local am = r.primaryName or "Mitigation"
    local cells = {
        { "Hits taken", tostring(r.hits) },
        { am .. " coverage", r.coverage and (hex(CoverageColor(r)) .. r.coverage .. "%|r") or "-" },
        { "Hits without " .. am, r.primaryKnown and string.format("%d of %d", r.hitsUnmitigated, r.hitsRelevant) or "-" },
        { "Longest gap", r.primaryKnown and string.format("%.1fs", r.longestGap) or "-" },
        { "Mobs lost", (r.aggroLost > 0 and hex(C.warn) or "") .. r.aggroLost .. (r.aggroLost > 0 and "|r" or "") },
        { "Taunts", tostring(r.taunts) },
        { "Healer attacked", r.healerAttacked >= 1 and (hex(C.bad) .. string.format("%.0fs", r.healerAttacked) .. "|r") or "0s" },
        { "Interrupts", tostring(r.interrupts) },
    }
    local colW = (WIDTH - 2 * PAD) / 2
    local y = PAD + 36
    for i, data in ipairs(cells) do
        local cell = StatCell(i)
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        cell.label:ClearAllPoints()
        cell.label:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + col * colW, -(y + row * 32))
        cell.label:SetWidth(colW - 6)
        cell.label:SetJustifyH("LEFT")
        cell.label:SetText(data[1])
        cell.value:ClearAllPoints()
        cell.value:SetPoint("TOPLEFT", cell.label, "BOTTOMLEFT", 0, -2)
        cell.value:SetText(data[2])
    end
    y = y + math.ceil(#cells / 2) * 32

    -- Defensives used
    local cell = StatCell(#cells + 1)
    cell.label:ClearAllPoints()
    cell.label:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -y)
    cell.label:SetWidth(WIDTH - 2 * PAD)
    cell.label:SetText("Defensives used")
    cell.value:ClearAllPoints()
    cell.value:SetPoint("TOPLEFT", cell.label, "BOTTOMLEFT", 0, -2)
    cell.value:SetWidth(WIDTH - 2 * PAD)
    cell.value:SetJustifyH("LEFT")
    cell.value:SetText(#(r.defensives or {}) > 0 and table.concat(r.defensives, ", ") or hex(C.muted) .. "none|r")
    y = y + 36

    f.workOn:ClearAllPoints()
    f.workOn:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -y)
    y = y + 16
    for _, fs in ipairs(f.notes) do fs:Hide() end
    local notes = r.notes or {}
    if #notes == 0 then notes = { hex(C.good) .. "Clean pull. Nothing to fix.|r" } end
    for i, text in ipairs(notes) do
        local fs = NoteLine(i)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + 4, -y)
        fs:SetText("- " .. text)
        fs:Show()
        y = y + math.max(fs:GetStringHeight() or 13, 13) + 4
    end

    y = y + 6
    f.prev:ClearAllPoints()
    f.prev:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -y)
    f.next:ClearAllPoints()
    f.next:SetPoint("LEFT", f.prev, "RIGHT", 4, 0)
    f.count:ClearAllPoints()
    f.count:SetPoint("LEFT", f.next, "RIGHT", 8, 0)
    f.count:SetText(string.format("Pull %d of %d", #history - index + 1, #history))
    f.prev:SetEnabled(index < #history)
    f.next:SetEnabled(index > 1)
    f:SetHeight(y + 20 + PAD)
    f:SetScale(TF.db.scale or 1)
    Style.FitAnchor("report")
    return true
end

f.prev:SetScript("OnClick", function() Report:Render(shownIndex + 1) end)
f.next:SetScript("OnClick", function() Report:Render(shownIndex - 1) end)

function Report:Open(index)
    if Report:Render(index or 1) then
        f.hideAt = nil
        f:Show()
    else
        TF:Print("no pulls recorded yet. Pulls are recorded while you tank in dungeons and raids.")
    end
end

f:SetScript("OnUpdate", function(self)
    if self.hideAt and API.Now() >= self.hideAt and not self:IsMouseOver() then
        self.hideAt = nil
        self:Hide()
    end
end)

-- Recording ------------------------------------------------------------------

TF:On("PULL_END", function(p)
    local cfg = TF.db.report
    if not cfg.enabled then return end
    if p.duration < MIN_SECONDS or p.hits < 3 then return end
    if not p.instance and not cfg.openWorld then return end
    local r = MakeRecord(p)
    local history = TF.db.history
    table.insert(history, 1, r)
    while #history > KEEP do table.remove(history) end
    if cfg.autoShow then
        Report:Render(1)
        f:Show()
        f.hideAt = (cfg.hideAfter or 0) > 0 and (API.Now() + cfg.hideAfter) or nil
    end
end)

TF:On("COMBAT", function(inCombat)
    -- Out of the way when the next pull starts.
    if inCombat and f:IsShown() and f.hideAt then f:Hide() end
end)

TF:AddCommand("report", function() Report:Open(1) end, "- show the last pull report")
