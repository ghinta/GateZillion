--!strict
-- Deterministic outcome rules for obstacles and enemy squads. No Roblox APIs.

local GateMath = require(script.Parent.GateMath)

local EncounterRules = {}

-- An obstacle removes a fixed number of units from the group.
function EncounterRules.applyObstacle(count: number, damage: number, maxGroupSize: number): number
	assert(GateMath.isInteger(damage) and damage >= 0, "obstacle damage must be a non-negative integer")
	return GateMath.clamp(count - damage, maxGroupSize)
end

-- Units trade one-for-one with an enemy squad. Returns the surviving group size and the number
-- of enemies defeated.
function EncounterRules.applyEnemy(count: number, enemyCount: number, maxGroupSize: number): (number, number)
	assert(GateMath.isInteger(enemyCount) and enemyCount >= 0, "enemy count must be a non-negative integer")
	local survivors = GateMath.clamp(count - enemyCount, maxGroupSize)
	local defeated = math.min(count, enemyCount)
	return survivors, defeated
end

return EncounterRules
