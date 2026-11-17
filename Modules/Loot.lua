-- Modules/Loot.lua
-- Holds Blizzard's Need / Greed / Pass roll windows back until combat ends.
--
-- The roll windows live in GroupLootContainer. In combat it's reparented to
-- the hidden frame and goes back to its own parent when combat ends. The roll
-- frames aren't secure, so this works in combat too, and nothing else on them
-- is touched (no Show/Hide/SetAlpha calls, hooks or field writes).
--
-- The server's roll timer keeps running while the window is hidden, and an
-- unanswered roll passes when it runs out. A roll with less than
-- `loot.revealAt` seconds left brings the windows back early.
local _, ns = ...
local TF = ns.TF
local API = ns.API
local Style = ns.Style

local Loot = { pending = {} }
ns.Loot = Loot

local TICK = 0.5
local MAX_FRAMES = 4

--- The earliest expiry time among pending rolls, or nil when there are none.
---@param pending table<integer, number> rollID -> GetTime() when the roll ends
---@return number|nil
function Loot.SoonestExpiry(pending)
    local soonest
    for _, expires in pairs(pending) do
        if not soonest or expires < soonest then soonest = expires end
    end
    return soonest
end

--- True when the roll windows should be held back: in combat, the setting is
--- on and no pending roll is within revealAt seconds of running out.
---@param inCombat boolean
---@param enabled boolean
---@param pending table<integer, number> rollID -> GetTime() when the roll ends
---@param now number
---@param revealAt number seconds
---@return boolean
function Loot.ShouldHide(inCombat, enabled, pending, now, revealAt)
    if not (inCombat and enabled) then return false end
    local soonest = Loot.SoonestExpiry(pending)
    if soonest and soonest - now <= revealAt then return false end
    return true
end

-- Frames ---------------------------------------------------------------------

--- Blizzard's roll windows: the container, or the single frames on clients without one.
---@return table[]
function Loot.Frames()
    if _G.GroupLootContainer then return { _G.GroupLootContainer } end
    local list = {}
    for i = 1, MAX_FRAMES do
        local f = _G["GroupLootFrame" .. i]
        if f then list[#list + 1] = f end
    end
    return list
end

local homes = {} -- frame -> its parent before it was hidden
local ticker

local function SetHidden(hide)
    for _, frame in ipairs(Loot.Frames()) do
        if hide and not homes[frame] then
            homes[frame] = frame:GetParent() or UIParent
            pcall(frame.SetParent, frame, Style.hiddenParent)
        elseif not hide and homes[frame] then
            pcall(frame.SetParent, frame, homes[frame])
            homes[frame] = nil
        end
    end
    Loot.hidden = hide
end

local function Update()
    local now = API.Now()
    for id, expires in pairs(Loot.pending) do
        if expires <= now then Loot.pending[id] = nil end
    end
    local cfg = TF.db.loot
    SetHidden(Loot.ShouldHide(TF.inCombat, cfg.delay, Loot.pending, now, cfg.revealAt))
    -- Only tick while a held-back roll could reach its reveal time.
    local needTick = Loot.hidden and next(Loot.pending) ~= nil
    if needTick and not ticker then
        ticker = C_Timer.NewTicker(TICK, Update)
    elseif not needTick and ticker then
        ticker:Cancel()
        ticker = nil
    end
end
Loot.Update = Update

--- Apply the "Delay loot rolls" setting now.
function TF:ApplyLoot()
    Update()
end

-- Events ---------------------------------------------------------------------

TF:RegisterEvent("START_LOOT_ROLL", function(_, rollID, rollTime)
    rollID, rollTime = API.PlainNumber(rollID), API.PlainNumber(rollTime)
    if not rollID or not rollTime then return end
    Loot.pending[rollID] = API.Now() + rollTime / 1000
    Update()
    if Loot.hidden then
        local link = API.LootRollItemLink(rollID) or "an item"
        TF:Print("loot roll waiting until combat ends: " .. link)
    end
end)

TF:RegisterEvent("CANCEL_LOOT_ROLL", function(_, rollID)
    rollID = API.PlainNumber(rollID)
    if rollID then Loot.pending[rollID] = nil end
    Update()
end)

TF:On("COMBAT", Update)
