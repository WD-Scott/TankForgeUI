-- spec/support/fixtures.lua
-- Builders for the data shapes modules pass around, with sensible defaults.
local fixtures = {}

local function merge(t, over)
    for k, v in pairs(over or {}) do t[k] = v end
    return t
end

--- A finished pull as Tank.lua hands it to PULL_END: 30s in a dungeon, hit for 20s,
--- Shield Block up for 15 of them.
function fixtures.pull(over)
    return merge({
        start = 1000, time = 1767226600, zone = "Deadmines", instance = true, duration = 30,
        hits = 20, hitsRelevant = 18, hitsUnmitigated = 6,
        underAttack = 20, covered = 15, longestGap = 2, gap = nil,
        casts = { shieldBlock = 4 }, taunts = 1, interrupts = 2, defensives = {},
        aggroLost = 0, aggroLostTo = {}, healerAttacked = 0, looseTime = 0, deaths = {},
        tl = { n = 3, att = { true, true }, cov = { 1, -1 }, hit = { 2, 1 } },
        primaryName = "Shield Block", primaryTarget = 0.75, primaryKnown = true,
    }, over)
end

--- A compact pull as Runs.lua stores it.
function fixtures.runPull(over)
    return merge({ t = 0, d = 60, hits = 30, rel = 28, unmit = 6, ua = 40, cov = 30, gap = 3, known = true,
        taunts = 1, ints = 1, lost = 0, heal = 0, deaths = {} }, over)
end

--- A finished run with `n` default pulls.
function fixtures.run(n, over)
    local pulls = {}
    for i = 1, n or 3 do pulls[i] = fixtures.runPull() end
    return merge({ id = 1, key = "36:1", instance = "Deadmines", start = 0, finish = 1800, pulls = pulls,
        bosses = {}, target = 0.75 }, over)
end

return fixtures
