-- Modules/Hide.lua
-- Hides Blizzard's player frame pieces, the action bar tooltips and the main
-- bar's end caps and border art.
--
-- The player frame itself stays shown and only Blizzard's own pieces are
-- hidden, so anything another addon attaches to it keeps working.
local _, ns = ...
local TF = ns.TF
local Style = ns.Style

-- Player frame ---------------------------------------------------------------

local frame = _G.PlayerFrame
local pieces = {}
local updating = {}
local hooked = false

-- Captured now, before addons that load later add anything to the frame.
if frame then
    for _, child in ipairs({ frame:GetChildren() }) do pieces[#pieces + 1] = child end
    for _, region in ipairs({ frame:GetRegions() }) do pieces[#pieces + 1] = region end
end

local function HidePlayer()
    return TF.db and TF.db.hidePlayerFrame
end

local function UpdatePiece(piece)
    updating[piece] = true
    -- Alpha is never blocked in combat.
    piece:SetAlpha(HidePlayer() and 0 or 1)
    if not (piece.IsProtected and piece:IsProtected() and InCombatLockdown()) then
        if HidePlayer() then
            piece:Hide()
        elseif piece.tfWasShown then
            piece:Show()
        end
    end
    updating[piece] = nil
end

local function ApplyPlayerFrame()
    if not frame then return end
    if not hooked then
        for _, piece in ipairs(pieces) do
            piece.tfWasShown = piece:IsShown()
            hooksecurefunc(piece, "Show", function(self)
                if HidePlayer() and not updating[self] then UpdatePiece(self) end
            end)
            hooksecurefunc(piece, "SetAlpha", function(self)
                if HidePlayer() and not updating[self] then UpdatePiece(self) end
            end)
        end
        hooked = true
    end
    for _, piece in ipairs(pieces) do UpdatePiece(piece) end
    if InCombatLockdown() then TF:AfterCombat(ApplyPlayerFrame) end
end

-- Action bar art -------------------------------------------------------------

local artUpdating = {}
local artHooked = {}

local function ArtRegions()
    local list = {}
    local bar = _G.MainActionBar or _G.MainMenuBar
    if bar then
        if bar.EndCaps then list[#list + 1] = bar.EndCaps end
        if bar.BorderArt then list[#list + 1] = bar.BorderArt end
    end
    for _, name in ipairs({ "MainMenuBarLeftEndCap", "MainMenuBarRightEndCap" }) do
        if _G[name] then list[#list + 1] = _G[name] end
    end
    return list
end

local function ApplyBarArt()
    local hide = TF.db.hideBarArt
    for _, region in ipairs(ArtRegions()) do
        artUpdating[region] = true
        region:SetAlpha(hide and 0 or 1)
        artUpdating[region] = nil
        if not artHooked[region] then
            hooksecurefunc(region, "SetAlpha", function(self)
                if TF.db.hideBarArt and not artUpdating[self] then
                    artUpdating[self] = true
                    self:SetAlpha(0)
                    artUpdating[self] = nil
                end
            end)
            artHooked[region] = true
        end
    end
end

-- Action bar tooltips --------------------------------------------------------

local function SuppressTooltip()
    if not TF.db or not TF.db.hideActionTooltips then return false end
    if TF.db.shiftShowsTooltips and IsShiftKeyDown() then return false end
    return true
end

local tooltipsHooked = false
local function HookTooltips()
    if tooltipsHooked or not GameTooltip then return end
    tooltipsHooked = true
    -- Blizzard's bars and bar addons all build action tooltips with SetAction.
    if GameTooltip.SetAction then
        hooksecurefunc(GameTooltip, "SetAction", function(self)
            if SuppressTooltip() then self:Hide() end
        end)
    end
    -- Backup for anything that shows the tooltip after SetAction.
    GameTooltip:HookScript("OnShow", function(self)
        if not SuppressTooltip() then return end
        local owner = self:GetOwner()
        if owner and owner.action ~= nil then self:Hide() end
    end)
    -- Shift pressed or released while already hovering a button. Blizzard only
    -- refreshes an action tooltip while the button still owns GameTooltip, and
    -- hiding it ended that, so it's rebuilt here. Only GameTooltip is touched,
    -- never the button's own OnEnter (running that from add-on code would
    -- taint the button).
    TF:RegisterEvent("MODIFIER_STATE_CHANGED", function(_, key)
        if key ~= "LSHIFT" and key ~= "RSHIFT" then return end
        if not (TF.db and TF.db.hideActionTooltips and TF.db.shiftShowsTooltips) then return end
        if SuppressTooltip() then
            -- Released: hide it again, as if hovered without Shift.
            local owner = GameTooltip:IsShown() and GameTooltip:GetOwner()
            if owner and owner.action ~= nil then GameTooltip:Hide() end
            return
        end
        local focus
        if GetMouseFoci then
            local foci = GetMouseFoci()
            focus = foci and foci[1]
        elseif GetMouseFocus then
            focus = GetMouseFocus()
        end
        if not focus then return end
        pcall(function()
            if focus.action == nil or not focus:IsVisible() then return end
            GameTooltip:SetOwner(focus, "ANCHOR_NONE")
            if GameTooltip_SetDefaultAnchor then GameTooltip_SetDefaultAnchor(GameTooltip, focus) end
            GameTooltip:SetAction(focus.action)
            GameTooltip:Show()
        end)
    end)
end

-- Quest objective tracker ----------------------------------------------------
--
-- Hidden always, in dungeons and raids, or in combat. Hidden by moving it under
-- a hidden frame, out of combat. The tracker holds clickable quest-item buttons,
-- so that can't happen in combat: then it's only made transparent, and moved
-- once the fight ends. It's never shown, hidden or hooked directly, and no
-- field is written on it: that tainted Blizzard's UI, and the game then blocked
-- the action bars in combat. It always shows while Edit Mode is open, so it
-- can be moved.

ns.OBJECTIVE_MODES = { "never", "always", "instance", "combat" }
local objParent             -- the tracker's parent before it was moved
local objFaded = false      -- made transparent in combat by us
local objQueued = false

local function Tracker()
    return _G.ObjectiveTrackerFrame or _G.WatchFrame or _G.QuestWatchFrame
end

local function InDungeon()
    local inInstance, kind = IsInInstance()
    return inInstance and (kind == "party" or kind == "raid" or kind == "scenario") or false
end

local function HideObjectives()
    local mode = TF.db and TF.db.hideObjectives or "never"
    local em = _G.EditModeManagerFrame
    if em and em:IsShown() then return false end
    if mode == "always" then return true end
    if mode == "instance" then return InDungeon() end
    if mode == "combat" then return TF.inCombat end
    return false
end

local ApplyObjectives
local function QueueAfterCombat()
    if objQueued then return end
    objQueued = true
    TF:AfterCombat(function()
        objQueued = false
        ApplyObjectives()
    end)
end

local editHooked = false
ApplyObjectives = function()
    local tracker = Tracker()
    if not tracker then return end
    local hide = HideObjectives()
    local moved = tracker:GetParent() == Style.hiddenParent

    if InCombatLockdown() then
        if hide and not moved and not objFaded then
            objFaded = true
            tracker:SetAlpha(0)
        elseif not hide and objFaded then
            objFaded = false
            tracker:SetAlpha(1)
        end
        if hide ~= moved then QueueAfterCombat() end
    else
        if hide and not moved then
            objParent = tracker:GetParent() or UIParent
            tracker:SetParent(Style.hiddenParent)
        elseif not hide and moved then
            tracker:SetParent(objParent or UIParent)
            objParent = nil
        end
        if objFaded then
            objFaded = false
            tracker:SetAlpha(1)
        end
    end

    if editHooked then return end
    editHooked = true
    local em = _G.EditModeManagerFrame
    if em then
        em:HookScript("OnShow", ApplyObjectives)
        em:HookScript("OnHide", ApplyObjectives)
    end
end

-- Wiring ---------------------------------------------------------------------

--- Apply every hiding setting (player frame, bar art, action tooltips, quest tracker).
function TF:ApplyHiding()
    ApplyPlayerFrame()
    ApplyBarArt()
    HookTooltips()
    ApplyObjectives()
end

TF:On("ENTERING_WORLD", function() TF:ApplyHiding() end)
TF:On("COMBAT", function() ApplyObjectives() end)
TF:RegisterEvent("ZONE_CHANGED_NEW_AREA", function() ApplyObjectives() end)

local MODE_NAMES = { never = "never hidden", always = "always hidden", instance = "hidden in dungeons and raids",
    combat = "hidden in combat" }
TF:AddCommand("quests", function(arg)
    arg = strlower(strtrim(arg or ""))
    if arg == "dungeons" or arg == "raids" then arg = "instance" end
    if not MODE_NAMES[arg] then
        -- No argument: step to the next mode.
        local cur = TF.db.hideObjectives
        for i, m in ipairs(ns.OBJECTIVE_MODES) do
            if m == cur then arg = ns.OBJECTIVE_MODES[i % #ns.OBJECTIVE_MODES + 1] break end
        end
        arg = arg ~= "" and MODE_NAMES[arg] and arg or "always"
    end
    TF.db.hideObjectives = arg
    ApplyObjectives()
    TF:Print("quest tracker: " .. MODE_NAMES[arg] .. ".")
end, "[never|always|dungeons|combat] - when to hide the quest tracker", { group = "Hiding", details = {
    "never - always show it",
    "always - always hide it (it still shows in Edit Mode)",
    "dungeons - hide it in dungeons and raids",
    "combat - hide it during fights",
    "(no argument) - step to the next mode",
} })

local function Toggle(key, label)
    TF.db[key] = not TF.db[key]
    TF:ApplyHiding()
    TF:Print(label .. ": " .. (TF.db[key] and "|cff40ff40on|r" or "|cffff4040off|r"))
end

TF:AddCommand("frame", function() Toggle("hidePlayerFrame", "hide player frame") end,
    "- toggle hiding the player frame", { group = "Hiding" })
TF:AddCommand("tooltips", function() Toggle("hideActionTooltips", "hide action bar tooltips") end,
    "- toggle hiding action bar tooltips", { group = "Hiding" })
TF:AddCommand("shift", function() Toggle("shiftShowsTooltips", "Shift shows tooltips") end,
    "- toggle showing action bar tooltips while Shift is held", { group = "Hiding" })
