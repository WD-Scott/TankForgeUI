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

--- A small prompt with one or two buttons. With reload set, the OK slot holds a
--- secure button that runs /reload: ReloadUI() is protected on this client, so
--- calling it from addon code is blocked.
---@param reload boolean|nil OK runs /reload through a secure button
function TF:Prompt(text, okText, onOk, cancelText, onCancel, reload)
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
    if reload and not dialog.reload and not InCombatLockdown() then
        local b = CreateFrame("Button", "TankForgeUIReloadButton", dialog,
            "SecureActionButtonTemplate, UIPanelButtonTemplate")
        b:SetSize(120, 24)
        b:SetText("Reload")
        b:RegisterForClicks("AnyUp", "AnyDown")
        b:SetAttribute("type", "macro")
        b:SetAttribute("macrotext", "/reload")
        -- Runs after the secure click handler, so the macro has already fired.
        b:HookScript("OnClick", function() dialog:Hide() end)
        b:Hide()
        dialog.reload = b
    end
    local useReload = reload and dialog.reload ~= nil
    local ok = useReload and dialog.reload or dialog.ok
    if dialog.reload and not InCombatLockdown() then dialog.reload:SetShown(useReload) end
    dialog.ok:SetShown(not useReload)
    dialog.text:SetText(text)
    dialog.ok:SetText(okText or "OK")
    dialog.ok:SetScript("OnClick", function() dialog:Hide() if onOk then onOk() end end)
    if cancelText then
        dialog.cancel:SetText(cancelText)
        dialog.cancel:SetScript("OnClick", function() dialog:Hide() if onCancel then onCancel() end end)
        dialog.cancel:Show()
        ok:ClearAllPoints()
        ok:SetPoint("BOTTOMRIGHT", dialog, "BOTTOM", -6, 14)
    else
        dialog.cancel:Hide()
        ok:ClearAllPoints()
        ok:SetPoint("BOTTOM", dialog, "BOTTOM", 0, 14)
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

-- Layouts are read and written only through the C_EditMode API. Calling
-- EditModeManagerFrame's methods (ImportLayout, SelectLayout) from addon code
-- taints Edit Mode, and the game then blocks Blizzard's own bar and frame
-- updates. Edit Mode picks up the saved layouts after a reload.

local function NumPresets()
    local meta = _G.Enum and _G.Enum.EditModePresetLayoutsMeta
    return (meta and (meta.NumValues or meta.NumLayouts)) or 2
end

-- Blizzard's own layout list (presets first), the one activeLayout counts in. Read
-- only: calling the manager's methods from addon code would taint Edit Mode.
local function ManagerLayouts()
    local mgr = _G.EditModeManagerFrame
    local li = type(mgr) == "table" and mgr.layoutInfo
    if type(li) == "table" and type(li.layouts) == "table" then return li.layouts, li.activeLayout end
    return nil
end

--- The game may store the name in a different case, so compare case-insensitively.
---@param layouts {layoutName: string?}[]
---@param name string
---@return integer|nil index
local function FindLayout(layouts, name)
    local want = strupper(name)
    for i, layout in ipairs(layouts) do
        if type(layout.layoutName) == "string" and strupper(layout.layoutName) == want then return i end
    end
    return nil
end

--- The activeLayout number for the layout called `name`. Edit Mode counts entries the
--- C_EditMode list doesn't show (presets, and on Forever at least one more), so the
--- number comes from Blizzard's own list when it can be read: the layout's place
--- there, or the end of it for a new one. Without it: presets + place in `layouts`.
---@param mgrLayouts table|nil EditModeManagerFrame.layoutInfo.layouts
---@param layouts {layoutName: string?}[] C_EditMode.GetLayouts().layouts
---@param name string
---@return integer|nil
local function ActiveIndexFor(mgrLayouts, layouts, name)
    if type(mgrLayouts) == "table" then
        local i = FindLayout(mgrLayouts, name)
        if i then return i end
    end
    local index = FindLayout(layouts, name)
    -- Just added at the end of `layouts`: it goes at the end of Blizzard's list too.
    if type(mgrLayouts) == "table" and index and index == #layouts then return #mgrLayouts + 1 end
    return index and NumPresets() + index or nil
end

----- The saved Edit Mode layouts, or nil and a reason the player can act on.
local function ReadLayouts()
    local CE = _G.C_EditMode
    if not (CE and type(CE.GetLayouts) == "function" and type(CE.SaveLayouts) == "function"
        and type(CE.ConvertStringToLayoutInfo) == "function") then
        return nil, "Edit Mode isn't available"
    end
    local mgr = _G.EditModeManagerFrame
    if mgr and mgr:IsShown() then return nil, "close Edit Mode first" end
    local ok, info = pcall(CE.GetLayouts)
    if not ok or type(info) ~= "table" or type(info.layouts) ~= "table" then
        return nil, "couldn't read your layouts"
    end
    return info
end

-- Adds the TankForgeUI layout, or replaces the systems of the existing one,
-- and makes it active. Returns "installed" / "updated" or nil plus a reason.
local function WriteLayout(info)
    local CE = _G.C_EditMode
    local ok, new = pcall(CE.ConvertStringToLayoutInfo, ns.LAYOUT_STRING)
    if not ok or type(new) ~= "table" or type(new.systems) ~= "table" then
        return nil, "the client didn't accept the layout"
    end
    local mgrLayouts = ManagerLayouts()
    local before = info.activeLayout
    local index = FindLayout(info.layouts, ns.LAYOUT_NAME)
    local result
    if index then
        info.layouts[index].systems = new.systems
        result = "updated"
    else
        local types = _G.Enum and _G.Enum.EditModeLayoutType
        new.layoutName = ns.LAYOUT_NAME
        new.layoutType = (types and types.Character) or 1
        table.insert(info.layouts, new)
        index = #info.layouts
        result = "installed"
    end
    local active = ActiveIndexFor(mgrLayouts, info.layouts, ns.LAYOUT_NAME) or (NumPresets() + index)
    TF:Log("SETUP", "layout index %d of %d, manager list %s, presets %d, active %s -> %d", index, #info.layouts,
        mgrLayouts and tostring(#mgrLayouts) or "unreadable", NumPresets(), tostring(before), active)
    info.activeLayout = active
    ok = pcall(CE.SaveLayouts, info)
    if not ok then return nil, "saving the layout failed" end
    if type(CE.SetActiveLayout) == "function" then pcall(CE.SetActiveLayout, active) end
    return result
end

--- A short fingerprint of a layout string (djb2, kept under 2^32 so it stays exact in
--- Lua 5.1's doubles). Stored when /tf setup writes the layout, so a newer shipped
--- layout can be noticed at login.
---@param s string
---@return string hash 8 hex digits
local function LayoutHash(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
    return string.format("%08x", h)
end

--- Whether to say at login that a newer layout ships: you've been through setup, have a
--- TankForgeUI layout, it's from an older version, and you haven't been told about this one.
---@param db TankForgeUISettings
---@param hasLayout boolean
---@param hash string LayoutHash(ns.LAYOUT_STRING)
---@return boolean
local function LayoutNotice(db, hasLayout, hash)
    return (db.welcomed and hasLayout and db.layoutHash ~= hash and db.layoutNoticed ~= hash) and true or false
end

--- After the reload that follows /tf setup: the name of the active layout when it
--- isn't TankForgeUI, or nil when it is (or can't be read).
---@return string|nil
local function WrongActiveLayout()
    local list, active = ManagerLayouts()
    local layout = list and type(active) == "number" and list[active]
    if type(layout) ~= "table" or type(layout.layoutName) ~= "string" then return nil end
    if strupper(layout.layoutName) == strupper(ns.LAYOUT_NAME) then return nil end
    return layout.layoutName
end

ns.Setup = { FindLayout = FindLayout, ReadLayouts = ReadLayouts, WriteLayout = WriteLayout,
    LayoutHash = LayoutHash, LayoutNotice = LayoutNotice, ActiveIndexFor = ActiveIndexFor,
    WrongActiveLayout = WrongActiveLayout }

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

local function FinishLayout()
    if InCombatLockdown() then
        TF:Print("setup has to wait until you're out of combat.")
        return
    end
    -- Read again: the prompt may have been open for a while.
    local info, reason = ReadLayouts()
    local result
    if info then result, reason = WriteLayout(info) end
    TF:Log("SETUP", "layout %s (%s)", tostring(result), tostring(reason))
    if result then
        TF.db.layoutHash = LayoutHash(ns.LAYOUT_STRING)
        TF.db.layoutCheck = true
    end
    if not result then
        TF:Print("couldn't install the layout automatically (" .. tostring(reason) .. ").")
        local ok = pcall(ShowCopyBox, ns.LAYOUT_STRING)
        if not ok then TF:Print("type |cff" .. TF.COLOR .. "/tf layout|r to copy it by hand.") end
        return
    end
    if result == "updated" then
        TF:Print("updated the TankForgeUI Edit Mode layout.")
    else
        TF:Print("installed the TankForgeUI Edit Mode layout. Your other layouts are unchanged.")
    end
    -- Edit Mode loads the saved layout on reload.
    TF:Print("reload to switch to it (type |cff" .. TF.COLOR .. "/reload|r if the button doesn't work).")
    TF:Prompt("Reload now to switch to the TankForgeUI layout?", "OK", nil, "Later", nil, true)
end

--- /tf setup: turn on the tank CVars, then install or update the layout (asking
--- before overwriting an existing TankForgeUI layout). Not in combat.
function TF:RunSetup()
    if InCombatLockdown() then
        TF:Print("setup has to wait until you're out of combat.")
        return
    end
    TF.db.welcomed = true
    local done = SetCVars()
    TF:Log("SETUP", "settings turned on: %s", table.concat(done, ", "))
    if #done > 0 then TF:Print("turned on " .. table.concat(done, " and ") .. ".") end

    local info, reason = ReadLayouts()
    if not info then
        TF:Print("couldn't install the layout automatically (" .. tostring(reason) .. ").")
        if reason ~= "close Edit Mode first" then
            local ok = pcall(ShowCopyBox, ns.LAYOUT_STRING)
            if not ok then TF:Print("type |cff" .. TF.COLOR .. "/tf layout|r to copy it by hand.") end
        end
        return
    end
    if FindLayout(info.layouts, ns.LAYOUT_NAME) then
        TF:Prompt("Update your TankForgeUI layout to the latest version? Changes you made to it in Edit Mode "
            .. "will be lost.", "Update", FinishLayout, "Cancel")
    else
        FinishLayout()
    end
end

TF:AddCommand("setup", function() TF:RunSetup() end, "- install the TankForgeUI layout and tank settings", { group = "Setup" })
TF:AddCommand("layout", function() ShowCopyBox(ns.LAYOUT_STRING) end, "- show the Edit Mode layout string to import by hand", { group = "Setup" })

-- Edit Mode layouts don't change when the add-on does; say once per shipped version
-- that /tf setup would bring yours up to date.
local function CheckLayoutVersion()
    if InCombatLockdown() then return end
    local info = ReadLayouts()
    if not info then return end
    local hash = LayoutHash(ns.LAYOUT_STRING)
    if not LayoutNotice(TF.db, FindLayout(info.layouts, ns.LAYOUT_NAME) ~= nil, hash) then return end
    TF.db.layoutNoticed = hash
    TF:Print("a newer TankForgeUI layout is available (moves the cast bar clear of the HUD). |cff" .. TF.COLOR
        .. "/tf setup|r to update it.")
end

-- Once, after the reload that follows /tf setup: is Edit Mode on the TankForgeUI layout?
local function CheckActiveLayout()
    TF.db.layoutCheck = nil
    local name = WrongActiveLayout()
    if not name then return end
    local list, active = ManagerLayouts()
    TF:Log("SETUP", "after reload Edit Mode is on %q (active %s of %d)", name, tostring(active), #list)
    TF:Print(string.format("Edit Mode is using \"%s\", not TankForgeUI. Pick TankForgeUI in Edit Mode's Layout "
        .. "dropdown.", name))
end

TF:On("ENTERING_WORLD", function(isLogin)
    if TF.db.layoutCheck then C_Timer.After(2, CheckActiveLayout) end
    if not isLogin then return end
    if TF.db.welcomed then
        C_Timer.After(4, CheckLayoutVersion)
        return
    end
    C_Timer.After(4, function()
        if TF.db.welcomed or InCombatLockdown() then return end
        TF:Prompt("Set up your UI for tanking? This installs the TankForgeUI Edit Mode layout and turns on "
            .. "Target of Target and enemy nameplates. You can run it later with /tf setup.",
            "Set up", function() TF:RunSetup() end,
            "Not now", function() TF.db.welcomed = true end)
    end)
end)
