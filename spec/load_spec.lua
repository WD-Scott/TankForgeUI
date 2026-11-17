-- The whole add-on loads in .toc order, logs in, and its commands run.
local addon = require("support.addon")

describe("TankForgeUI", function()
    after_each(function() require("support.wow").uninstall() end)

    it("lists every Lua file in the .toc, and only existing ones", function()
        local inToc = {}
        for _, path in ipairs(addon.files()) do
            inToc[path] = true
            assert.is_truthy(io.open(path), path .. " is in the .toc but missing")
        end
        local p = io.popen("find Core Data Modules -name '*.lua' | sort")
        for path in p:lines() do
            assert.is_true(inToc[path] == true, path .. " is not in the .toc")
        end
        p:close()
    end)

    it("loads, merges defaults and logs in without errors", function()
        local A = addon.load()
        assert.are.same({}, A.errors)
        assert.is_table(A.TF.db)
        assert.are.equal("auto", A.TF.db.tankMode)
        assert.are.equal(A.TF, _G.TankForgeUI)
    end)

    it("runs every command without errors", function()
        local A = addon.load()
        for _, name in ipairs(A.TF.commands) do
            if name ~= "taint" then A.slash(name) end
        end
        assert.are.same({}, A.errors)
    end)
end)
