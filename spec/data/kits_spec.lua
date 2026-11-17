-- Data/Kits.lua: every class kit has what Tank.lua and the HUD expect.
local addon = require("support.addon")
local wow = require("support.wow")

local KINDS = { defensive = true, taunt = true, aoeTaunt = true, interrupt = true, stop = true, other = true }

describe("Kits", function()
    local ns
    before_each(function() ns = addon.load({ upto = "Data/Layout.lua", login = false }).ns end)
    after_each(function() wow.uninstall() end)

    local function ids(def)
        local list = { def.spell }
        for _, id in ipairs(def.alt or {}) do list[#list + 1] = id end
        return list
    end

    it("has a kit for each tanking class", function()
        for _, class in ipairs({ "WARRIOR", "DRUID", "PALADIN" }) do assert.is_table(ns.Kits[class], class) end
    end)

    for _, class in ipairs({ "WARRIOR", "DRUID", "PALADIN" }) do
        describe(class, function()
            local kit
            before_each(function() kit = ns.Kits[class] end)

            it("says what tanking posture is", function()
                local p = kit.posture
                assert.is_table(p)
                assert.is_true(#(p.forms or {}) + #(p.formSpells or {}) + #(p.auras or {}) > 0)
                assert.is_not_nil(ns.API.PowerType(kit.power))
            end)

            it("has exactly one primary mitigation, with a coverage target", function()
                local n = 0
                for _, def in ipairs(kit.am) do
                    if def.primary then
                        n = n + 1
                        assert.is_number(def.target)
                        assert.is_true(def.target > 0 and def.target <= 1)
                        assert.is_number(def.duration)
                    end
                end
                assert.are.equal(1, n)
            end)

            it("gives every mitigation a key and a duration", function()
                for _, def in ipairs(kit.am) do
                    assert.is_string(def.key)
                    assert.is_number(def.duration)
                    if def.maxDuration then assert.is_true(def.maxDuration >= def.duration) end
                    if def.blocks then assert.is_true(def.blocks > 0) end
                end
            end)

            it("says what the primary mitigation needs to be castable", function()
                for _, def in ipairs(kit.am) do
                    if def.primary then
                        assert.is_true(def.forms ~= nil or def.shield == true)
                        for _, id in ipairs(def.forms or {}) do assert.is_number(id) end
                    end
                end
            end)

            it("gives every icon a cooldown and a known kind", function()
                for _, def in ipairs(kit.icons) do
                    assert.is_number(def.cd)
                    assert.is_true(KINDS[def.kind] == true, tostring(def.kind))
                end
            end)

            it("uses numeric, distinct spell IDs across ranks", function()
                local seen = {}
                for _, list in ipairs({ kit.am, kit.icons }) do
                    for _, def in ipairs(list) do
                        for _, id in ipairs(ids(def)) do
                            assert.is_number(id)
                            assert.is_nil(seen[id], "spell " .. id .. " listed twice")
                            seen[id] = true
                        end
                    end
                end
            end)
        end)
    end

    it("weights healer classes with positive numbers", function()
        for class, w in pairs(ns.HEALER_CLASSES) do
            assert.is_string(class)
            assert.is_true(w > 0)
        end
    end)

    it("has an Edit Mode layout string", function()
        assert.are.equal("string", type(ns.LAYOUT_STRING))
        assert.is_true(#ns.LAYOUT_STRING > 100)
        assert.matches("TankForgeUI", ns.LAYOUT_NAME)
    end)
end)
