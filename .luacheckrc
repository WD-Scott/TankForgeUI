-- luacheck config. Run through scripts/test.sh. WoW runs Lua 5.1.
std = "lua51"
max_line_length = 150
codes = true
exclude_files = { ".lua/", ".luarocks/" }

-- Methods declared with `:` often ignore self (TF:On, Style hooks).
ignore = { "212/self" }

-- Globals the add-on writes.
globals = {
    "TankForgeUI", "TankForgeUIDB", "TankForgeUILog",
    "SLASH_TANKFORGEUI1", "SLASH_TANKFORGEUI2", "SlashCmdList",
}

-- WoW API the add-on reads. Most calls go through _G.X (API.lua) and aren't listed;
-- these are the ones referenced bare. Add new names here, alphabetically.
read_globals = {
    "C_AddOns", "C_CVar", "C_Spell", "C_Timer", "C_UnitAuras",
    "ChatFontNormal", "CreateFrame", "CurveConstants",
    "DEFAULT_CHAT_FRAME", "EditModeManagerFrame",
    "GameTooltip", "GameTooltip_SetDefaultAnchor", "GetAddOnMetadata", "GetBuildInfo",
    "GetCursorPosition", "GetCVar", "GetMouseFoci", "GetMouseFocus", "GetRealZoneText",
    "GetShapeshiftFormID", "HideUIPanel", "hooksecurefunc",
    "InCombatLockdown", "IsInGroup", "IsInInstance", "IsInRaid", "IsMouseButtonDown",
    "issecretvalue", "issecurevariable", "IsShiftKeyDown",
    "Minimap", "RegisterStateDriver", "RegisterUnitWatch",
    "SetPortraitTexture", "strlower", "strtrim", "strupper",
    "UIParent", "UISpecialFrames",
    "UnitAffectingCombat", "UnitCanAttack", "UnitCastingInfo", "UnitChannelInfo",
    "UnitDetailedThreatSituation", "UnitGroupRolesAssigned", "UnitGUID",
    "UnitHealth", "UnitHealthMax", "UnitHealthPercent", "UnitInParty", "UnitInRaid",
    "UnitInRange", "UnitIsGroupLeader", "UnitIsUnit", "UnitName",
    "UnitPower", "UnitPowerMax", "UnitPowerPercent", "UnitThreatSituation",
    "UnregisterUnitWatch", "wipe",
    -- os.time / os.date under their WoW names
    "date", "time",
}

files["Data/Layout.lua"] = { max_line_length = false }

files["spec/"] = {
    std = "+busted",
    globals = { "_G" },
    -- Specs install WoW stubs into _G and read add-on globals freely.
    allow_defined_top = true,
    ignore = { "111", "112", "113", "122", "142", "143" },
}
