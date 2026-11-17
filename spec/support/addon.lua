-- spec/support/addon.lua
-- Loads TankForgeUI into a fresh stub client, the way the game does: every file
-- in .toc order, called with ("TankForgeUI", ns). Each call gives a clean add-on
-- (file-local state such as listeners and timers can't be reset any other way).
--
--   local addon = require("support.addon")
--   local A = addon.load({ db = { tankMode = "always" }, world = { ... } })
--   A.ns.Tank, A.TF, A.fire("PLAYER_REGEN_DISABLED"), A.messages("CAST")
--
-- Errors inside event handlers and message listeners are re-raised (the add-on
-- normally catches them and prints them), so a broken handler fails the test.

local wow = require("support.wow")

local addon = {}

local ADDON = "TankForgeUI"

--- File paths from the .toc, in load order.
---@return string[]
function addon.files()
    local list = {}
    for line in io.lines(ADDON .. ".toc") do
        line = line:gsub("\r", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and not line:match("^#") then
            list[#list + 1] = (line:gsub("\\", "/"))
        end
    end
    return list
end

---@class LoadOptions
---@field world table|nil      overrides for wow's default world (see spec/support/wow.lua)
---@field db table|nil         saved settings (TankForgeUIDB) before defaults are merged in
---@field log table|nil        TankForgeUILog before login
---@field upto string|nil      stop after this file, e.g. "Core/Core.lua"
---@field login boolean|nil    fire PLAYER_LOGIN (default true; needs a full load)
---@field reload boolean|nil   enter the world as after a /reload rather than a fresh login
---@field catchErrors boolean|nil  keep the add-on's own error handling (errors are printed, not raised)
---@field setup fun(wow: table)|nil  runs after the client is installed, before any file loads
---   (for Blizzard frames and functions the add-on looks for at load)

--- Load the add-on into a fresh client.
---@param opts LoadOptions|nil
function addon.load(opts)
    opts = opts or {}
    wow.install(opts.world)
    if opts.setup then opts.setup(wow) end
    local ns = {}
    local A = { ns = ns, wow = wow, errors = {}, fired = {} }

    for _, path in ipairs(addon.files()) do
        local chunk = assert(loadfile(path))
        chunk(ADDON, ns)
        if path == "Core/Core.lua" then addon.instrument(A, opts) end
        if opts.upto and path == opts.upto then break end
    end
    A.TF = ns.TF

    _G.TankForgeUIDB = opts.db
    _G.TankForgeUILog = opts.log
    wow.fire("ADDON_LOADED", ADDON)
    if opts.login ~= false then
        wow.fire("PLAYER_LOGIN")
        wow.fire("PLAYER_ENTERING_WORLD", not opts.reload, opts.reload and true or false)
    end

    --- Fire a game event.
    function A.fire(event, ...) wow.fire(event, ...) end
    --- Recorded internal messages: every TF:Fire call, or only `name`'s, as arg lists.
    function A.messages(name)
        local out = {}
        for _, m in ipairs(A.fired) do
            if not name or m.name == name then out[#out + 1] = m.args end
        end
        return out
    end
    function A.clearMessages() A.fired = {} end
    --- Enter or leave combat the way the client signals it.
    function A.combat(on)
        wow.world.inCombat = on
        wow.fire(on and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
    end
    --- Run a slash command: A.slash("status").
    function A.slash(text) _G.SlashCmdList.TANKFORGEUI(text) end
    return A
end

-- Wrap TF:Fire to record messages and TF:Error to raise.
function addon.instrument(A, opts)
    local TF = A.ns.TF
    local fire = TF.Fire
    TF.Fire = function(self, name, ...)
        A.fired[#A.fired + 1] = { name = name, args = { n = select("#", ...), ... } }
        return fire(self, name, ...)
    end
    if not opts.catchErrors then
        TF.Error = function(_, err)
            A.errors[#A.errors + 1] = err
            error(err, 0)
        end
    end
end

return addon
