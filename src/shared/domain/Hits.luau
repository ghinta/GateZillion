--!strict
-- Ordering and application of level elements crossed by the group. Server simulation and level
-- validation both go through this module so they cannot disagree about outcomes.

local EncounterRules = require(script.Parent.EncounterRules)
local GateMath = require(script.Parent.GateMath)
local Types = require(script.Parent.Types)

type Hit = Types.Hit
type HitKind = Types.HitKind

local Hits = {}

local KIND_ORDER: { [HitKind]: number } = table.freeze({
	gate = 1,
	obstacle = 2,
	enemy = 3,
})

-- Sort key: distance along the track, then gates before obstacles before enemies, then id.
function Hits.compare(a: Hit, b: Hit): boolean
	if a.z ~= b.z then
		return a.z < b.z
	end
	if a.kind ~= b.kind then
		return KIND_ORDER[a.kind] < KIND_ORDER[b.kind]
	end
	return a.id < b.id
end

function Hits.sort(hits: { Hit })
	table.sort(hits, Hits.compare)
end

-- Returns the group size after the hit.
function Hits.apply(hit: Hit, count: number, maxGroupSize: number): number
	if hit.kind == "gate" then
		local gate = assert(hit.gate, "gate hit without gate")
		return GateMath.apply(gate.op, gate.value, count, maxGroupSize)
	elseif hit.kind == "obstacle" then
		local obstacle = assert(hit.obstacle, "obstacle hit without obstacle")
		return EncounterRules.applyObstacle(count, obstacle.damage, maxGroupSize)
	else
		local enemy = assert(hit.enemy, "enemy hit without enemy")
		local survivors = EncounterRules.applyEnemy(count, enemy.count, maxGroupSize)
		return survivors
	end
end

return Hits
