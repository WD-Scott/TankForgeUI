-- Modules/Placement.lua
-- Keeps Blizzard's pop-ups off your action bars. Tooltips (units, items) and
-- the bag windows open from the bottom-right corner, and Blizzard only makes
-- room for action bars in their default places. With the bars moved to the
-- bottom right, both land on top of your abilities, so this moves them up to
-- just above the bars.
--
-- The clear area is worked out from where the bars actually are each time,
-- so moving bars in Edit Mode keeps working. Neither tooltips nor bag
-- windows are protected, so this works in combat too.
--
-- NPC windows (quest, gossip, vendor, trainer, flight, bank) open at a box
-- you place with /tf unlock instead of Blizzard's top-left panel slot.
local _, ns = ...
local TF = ns.TF

local GAP = 6

local function Enabled() return TF.db and TF.db.keepClear end

-- Converts a frame's own coordinates to UIParent's.
local function ToParent(frame, v)
    if not v then return nil end
    return v * frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
end

-- Converts a UIParent-sized offset to the frame's own scale (for SetPoint).
local function FromParent(frame, v)
    return v * UIParent:GetEffectiveScale() / frame:GetEffectiveScale()
end

-- The top of the highest visible bottom action bar, in UIParent coordinates.
local BARS = { "MainActionBar", "MainMenuBar", "MultiBarBottomLeft", "MultiBarBottomRight" }
local function BarTop()
    local top = 0
    for _, name in ipairs(BARS) do
        local bar = _G[name]
        if bar and bar:IsVisible() then
            local t = ToParent(bar, bar:GetTop())
            if t and t > top and t < UIParent:GetHeight() / 2 then top = t end
        end
    end
    return top
end

-- The left edge of the bag column when it's on the right side of the screen.
local function RightEdge()
    local w = UIParent:GetWidth()
    local bags = _G.BagsBar
    if bags and bags:IsVisible() then
        local x = ToParent(bags, bags:GetCenter())
        local left = ToParent(bags, bags:GetLeft())
        if x and left and x > w * 0.75 then return left end
    end
    return w
end

-- Tooltips -------------------------------------------------------------------

-- Only tooltips that use the default spot; ones attached to a frame stay put.
local function PlaceTooltip(tooltip)
    if not Enabled() or not tooltip then return end
    local x, y = RightEdge() - GAP, BarTop() + GAP
    tooltip:ClearAllPoints()
    tooltip:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", FromParent(tooltip, x), FromParent(tooltip, y))
end

if type(_G.GameTooltip_SetDefaultAnchor) == "function" then
    hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip) PlaceTooltip(tooltip) end)
end

-- Bags -----------------------------------------------------------------------

local function ContainerFrames()
    local list, set = {}, {}
    local function Add(f)
        if f and not set[f] then
            set[f] = true
            list[#list + 1] = f
        end
    end
    Add(_G.ContainerFrameCombinedBags)
    for i = 1, (_G.NUM_CONTAINER_FRAMES or 13) do Add(_G["ContainerFrame" .. i]) end
    return list, set
end

-- 0 backpack, 1-4 bags, 5 reagent bag; anything else is a bank bag.
local LAST_BAG = 5
local function BagID(f)
    if f == _G.ContainerFrameCombinedBags then return 0 end
    if f.GetBagID then
        local ok, id = pcall(f.GetBagID, f)
        if ok and type(id) == "number" then return id end
    end
    return f.GetID and f:GetID() or nil
end

-- Frames along the top of the screen that bags must stay under.
local TOP_FRAMES = { "MinimapCluster", "BuffFrame", "DebuffFrame" }

-- The highest a column spanning left..right can reach, in UIParent coordinates.
local function TopLimit(left, right)
    local limit = UIParent:GetHeight()
    for _, name in ipairs(TOP_FRAMES) do
        local f = _G[name]
        if f and f:IsVisible() then
            local l, r, b = ToParent(f, f:GetLeft()), ToParent(f, f:GetRight()), ToParent(f, f:GetBottom())
            if l and r and b and l < right and r > left and b > UIParent:GetHeight() / 2 then
                limit = math.min(limit, b)
            end
        end
    end
    return limit - GAP
end

-- Lays your bag windows out in columns, growing up from just above the
-- action bars and left of the bag column, wrapping left before they reach
-- the minimap or buffs. Bank bags are left where Blizzard puts them.
local placing = false
local LayOut
local function PlaceBags()
    if placing or not Enabled() then return end
    local bags = {}
    for _, f in ipairs((ContainerFrames())) do
        local id = BagID(f)
        if f:IsShown() and id and id >= 0 and id <= LAST_BAG and f:GetHeight() and f:GetWidth() then
            bags[#bags + 1] = { frame = f, id = id }
        end
    end
    if #bags == 0 then return end
    table.sort(bags, function(a, b) return a.id < b.id end)

    -- The guard stops our own moves re-entering through the anchor hook; reset it
    -- even when the layout fails, or bags would never be placed again.
    placing = true
    local ok, err = pcall(LayOut, bags)
    placing = false
    if not ok then TF:Error(err) end
end

-- Stack `bags` ({ frame, id }, sorted) in columns from the bottom right.
function LayOut(bags)
    local bottom = BarTop() + GAP
    local right = RightEdge() - GAP
    local y, colWidth, limit = bottom, 0, nil
    for _, bag in ipairs(bags) do
        local f = bag.frame
        local w, h = ToParent(f, f:GetWidth()), ToParent(f, f:GetHeight())
        limit = limit or TopLimit(right - w, right)
        -- Wrap into a new column to the left when this one is full.
        if y > bottom and y + h > limit then
            right = right - colWidth - GAP
            y, colWidth = bottom, 0
            limit = TopLimit(right - w, right)
        end
        f:ClearAllPoints()
        f:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", FromParent(f, right), FromParent(f, y))
        y = y + h + GAP
        colWidth = math.max(colWidth, w)
    end
end

if type(_G.UpdateContainerFrameAnchors) == "function" then
    hooksecurefunc("UpdateContainerFrameAnchors", PlaceBags)
end

-- Some ways of opening bags place them after the window shows; catch those a
-- frame later.
local function Deferred() C_Timer.After(0, PlaceBags) end
TF:On("LOGIN", function()
    for _, f in ipairs((ContainerFrames())) do f:HookScript("OnShow", Deferred) end
end)

-- NPC windows ----------------------------------------------------------------
--
-- Gossip, quest text, vendor, trainer, flight map and bank windows open in
-- Blizzard's left panel slot, top left, on top of whatever you put there.
-- They follow the "NPC dialogs" box instead (/tf unlock). Only the window in
-- the left slot moves, so a second panel opened next to it still lines up.
-- None of these windows are protected, so this works in combat too. Nothing is
-- written to the Blizzard frames but their anchor.

local Style = ns.Style
local Placement = {}
ns.Placement = Placement

--- Blizzard's NPC interaction windows, by global name. Trainer and flight map
--- load on demand, so names are looked up again when an add-on loads.
Placement.NPC_FRAMES = { "GossipFrame", "QuestFrame", "MerchantFrame", "ClassTrainerFrame", "TaxiFrame", "BankFrame" }

local dialog = CreateFrame("Frame", "TankForgeUINpcDialog", UIParent)
dialog:SetSize(340, 500)
Placement.dialog = dialog
Style.Movable(dialog, "npcDialog", "NPC dialogs", { "TOPLEFT", "TOPLEFT", 16, -200 })

--- True when `frame` should be moved to the NPC dialogs box: the setting is on,
--- the window is shown, and it's the panel in Blizzard's left slot (when the
--- client says which panel that is).
---@param frame table|nil
---@return boolean
function Placement.ShouldPlaceDialog(frame)
    local cfg = TF.db and TF.db.npcDialogs
    if not (cfg and cfg.enabled) or not frame or not frame:IsShown() then return false end
    local GetUIPanel = _G.GetUIPanel
    if type(GetUIPanel) == "function" then
        local ok, left = pcall(GetUIPanel, "left")
        if ok and left ~= nil and left ~= frame then return false end
    end
    return true
end

local function PlaceDialog(frame)
    if not Placement.ShouldPlaceDialog(frame) then return end
    local p = frame:GetNumPoints() == 1 and { frame:GetPoint(1) }
    if p and p[1] == "TOPLEFT" and p[2] == dialog and p[3] == "TOPLEFT" then return end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", dialog, "TOPLEFT", 0, 0)
end

--- Move every shown NPC window that belongs at the NPC dialogs box.
function Placement.PlaceDialogs()
    for _, name in ipairs(Placement.NPC_FRAMES) do PlaceDialog(_G[name]) end
end

-- Blizzard places a panel as it shows, sometimes a frame later; place it after both.
local hooked = {}
local function HookDialogs()
    for _, name in ipairs(Placement.NPC_FRAMES) do
        local f = _G[name]
        if f and not hooked[f] and f.HookScript then
            hooked[f] = true
            f:HookScript("OnShow", function(self)
                PlaceDialog(self)
                C_Timer.After(0, function() PlaceDialog(self) end)
            end)
        end
    end
end

if type(_G.UpdateUIPanelPositions) == "function" then
    hooksecurefunc("UpdateUIPanelPositions", function() Placement.PlaceDialogs() end)
end
TF:On("LOGIN", HookDialogs)
TF:RegisterEvent("ADDON_LOADED", function() if TF.db then HookDialogs() end end)

--- Apply the "Move NPC windows" setting to windows already open. Turned off,
--- windows go back to Blizzard's spot the next time they open.
function TF:ApplyNpcDialogs()
    Placement.PlaceDialogs()
end
