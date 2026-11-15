-- Modules/Setup.lua
-- /tf setup: installs the TankForgeUI Edit Mode layout and the game settings
-- that help a tank, then asks for a reload.
local _, ns = ...
local TF = ns.TF
local Style = ns.Style

-- Dialogs --------------------------------------------------------------------

local dialog
local function Button(parent, text, width)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 120, 24)
    b:SetText(text)
    return b
end

-- A small prompt with one or two buttons.
function TF:Prompt(text, okText, onOk, cancelText, onCancel)
    if not dialog then
        dialog = Style.Panel(UIParent, "TankForgeUIPrompt")
        dialog:SetSize(380, 140)
        dialog:SetPoint("CENTER", 0, 120)
        dialog:SetFrameStrata("DIALOG")
        dialog:EnableMouse(true)
        dialog.title = Style.Text(dialog, 14)
        dialog.title:SetPoint("TOP", 0, -12)
        dialog.title:SetText("|cff" .. TF.COLOR .. "TankForgeUI|r")
        dialog.text = Style.Text(dialog, 12)
        dialog.text:SetPoint("TOPLEFT", 16, -36)
        dialog.text:SetPoint("TOPRIGHT", -16, -36)
        dialog.text:SetWordWrap(true)
        dialog.text:SetJustifyH("CENTER")
        dialog.ok = Button(dialog, "OK")
        dialog.cancel = Button(dialog, "Cancel")
        dialog.ok:SetPoint("BOTTOMRIGHT", dialog, "BOTTOM", -6, 14)
        dialog.cancel:SetPoint("BOTTOMLEFT", dialog, "BOTTOM", 6, 14)
    end
    dialog.text:SetText(text)
    dialog.ok:SetText(okText or "OK")
    dialog.ok:SetScript("OnClick", function() dialog:Hide() if onOk then onOk() end end)
    if cancelText then
        dialog.cancel:SetText(cancelText)
        dialog.cancel:SetScript("OnClick", function() dialog:Hide() if onCancel then onCancel() end end)
        dialog.cancel:Show()
        dialog.ok:ClearAllPoints()
        dialog.ok:SetPoint("BOTTOMRIGHT", dialog, "BOTTOM", -6, 14)
    else
        dialog.cancel:Hide()
        dialog.ok:ClearAllPoints()
        dialog.ok:SetPoint("BOTTOM", dialog, "BOTTOM", 0, 14)
    end
    dialog:Show()
end

-- A box holding text to copy, for when the layout can't be installed directly.
local copyBox
local function ShowCopyBox(text)
    if not copyBox then
        copyBox = Style.Panel(UIParent, "TankForgeUICopy")
        copyBox:SetSize(460, 200)
        copyBox:SetPoint("CENTER", 0, 100)
        copyBox:SetFrameStrata("DIALOG")
        copyBox:EnableMouse(true)
        copyBox.text = Style.Text(copyBox, 12)
        copyBox.text:SetPoint("TOPLEFT", 14, -12)
        copyBox.text:SetPoint("TOPRIGHT", -14, -12)
        copyBox.text:SetWordWrap(true)
        copyBox.text:SetText("Press Ctrl+C to copy this layout. Then open Edit Mode, open the Layout dropdown, "
            .. "choose Import, paste it and name it TankForgeUI.")
        local scroll = CreateFrame("ScrollFrame", nil, copyBox, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 14, -52)
        scroll:SetPoint("BOTTOMRIGHT", -34, 44)
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetFontObject(ChatFontNormal)
        edit:SetWidth(400)
        edit:SetAutoFocus(false)
        edit:SetScript("OnEscapePressed", function() copyBox:Hide() end)
        scroll:SetScrollChild(edit)
        copyBox.edit = edit
        local close = Button(copyBox, "Close", 100)
        close:SetPoint("BOTTOM", 0, 12)
        close:SetScript("OnClick", function() copyBox:Hide() end)
    end
    copyBox.edit:SetText(text)
    copyBox:Show()
    copyBox.edit:SetFocus()
    copyBox.edit:HighlightText()
end

-- Layout ---------------------------------------------------------------------

local function FindLayout(name)
    local mgr = _G.EditModeManagerFrame
    local layouts = mgr and mgr.layoutInfo and mgr.layoutInfo.layouts
    if type(layouts) ~= "table" then return nil end
    for i, layout in ipairs(layouts) do
        if layout.layoutName == name then return i end
    end
    return nil
end

-- Returns "installed", "activated" or nil plus a reason.
local function InstallLayout()
    local mgr = _G.EditModeManagerFrame
    local CE = _G.C_EditMode
    if not (mgr and CE and type(CE.ConvertStringToLayoutInfo) == "function") then
        return nil, "Edit Mode isn't available"
    end
    if mgr:IsShown() then return nil, "close Edit Mode first" end

    local existing = FindLayout(ns.LAYOUT_NAME)
    if not existing and ns.LEGACY_LAYOUT_NAME then
        -- Installed before 1.10 under the old spelling: adopt it, and rename it
        -- if this client lets addons do that.
        existing = FindLayout(ns.LEGACY_LAYOUT_NAME)
        if existing and type(mgr.RenameLayout) == "function" then
            local ok = pcall(mgr.RenameLayout, mgr, existing, ns.LAYOUT_NAME)
            TF:Log("SETUP", "rename legacy layout: %s", tostring(ok))
            existing = FindLayout(ns.LAYOUT_NAME) or FindLayout(ns.LEGACY_LAYOUT_NAME)
        end
    end
    if existing then
        if type(mgr.SelectLayout) ~= "function" then return nil, "can't switch layouts" end
        local ok = pcall(mgr.SelectLayout, mgr, existing)
        if ok then return "activated" end
        return nil, "couldn't switch to it"
    end

    if type(mgr.ImportLayout) ~= "function" then return nil, "this client can't import layouts from addons" end
    local ok, info = pcall(CE.ConvertStringToLayoutInfo, ns.LAYOUT_STRING)
    if not ok or type(info) ~= "table" then return nil, "the client didn't accept the layout" end
    local accountType = (_G.Enum and _G.Enum.EditModeLayoutType and _G.Enum.EditModeLayoutType.Account) or 1
    ok = pcall(mgr.ImportLayout, mgr, info, accountType, ns.LAYOUT_NAME)
    if not ok then return nil, "the import failed" end
    -- ImportLayout normally selects the new layout; make sure.
    local index = FindLayout(ns.LAYOUT_NAME)
    if not index then return nil, "the import failed" end
    if type(mgr.SelectLayout) == "function" then pcall(mgr.SelectLayout, mgr, index) end
    return "installed"
end

-- Game settings --------------------------------------------------------------

ns.CVARS = {
    { "showTargetOfTarget", "1", "Target of Target" },
    { "nameplateShowEnemies", "1", "enemy nameplates" },
}

local function SetCVars()
    local set = (_G.C_CVar and _G.C_CVar.SetCVar) or _G.SetCVar
    local done = {}
    for _, c in ipairs(ns.CVARS) do
        local ok = pcall(set, c[1], c[2])
        if ok then done[#done + 1] = c[3] end
    end
    return done
end

-- Setup ----------------------------------------------------------------------

function TF:RunSetup()
    if InCombatLockdown() then
        TF:Print("setup has to wait until you're out of combat.")
        return
    end
    TF.db.welcomed = true
    local result, reason = InstallLayout()
    local done = SetCVars()
    TF:Log("SETUP", "layout %s (%s), settings turned on: %s", tostring(result), tostring(reason),
        table.concat(done, ", "))
    if #done > 0 then TF:Print("turned on " .. table.concat(done, " and ") .. ".") end

    if result == "activated" then
        TF:Print("the TankForgeUI layout was already installed, so I switched to it. To reinstall it, delete it "
            .. "in Edit Mode and run |cff" .. TF.COLOR .. "/tf setup|r again.")
    elseif result == "installed" then
        TF:Print("installed the TankForgeUI Edit Mode layout. Your other layouts are unchanged.")
    else
        TF:Print("couldn't install the layout automatically (" .. tostring(reason) .. ").")
        ShowCopyBox(ns.LAYOUT_STRING)
        return
    end
    -- Edit Mode changes made by an addon are cleanest after a reload.
    TF:Prompt("Setup is done. Reload now to finish?", "Reload", function() ReloadUI() end, "Later")
end

TF:AddCommand("setup", function() TF:RunSetup() end, "- install the TankForgeUI layout and tank settings")
TF:AddCommand("layout", function() ShowCopyBox(ns.LAYOUT_STRING) end, "- show the layout string to import by hand")

TF:On("ENTERING_WORLD", function(isLogin)
    if TF.db.welcomed or not isLogin then return end
    C_Timer.After(4, function()
        if TF.db.welcomed or InCombatLockdown() then return end
        TF:Prompt("Set up your UI for tanking? This installs the TankForgeUI Edit Mode layout and turns on "
            .. "Target of Target and enemy nameplates. You can run it later with /tf setup.",
            "Set up", function() TF:RunSetup() end,
            "Not now", function() TF.db.welcomed = true end)
    end)
end)
