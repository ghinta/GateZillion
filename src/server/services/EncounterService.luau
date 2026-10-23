--!strict
-- Obstacle and enemy detection. Obstacles only hit groups inside their lane; enemy squads span
-- the whole track. Outcomes are applied through the shared Hits/EncounterRules modules.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GateMath = require(ReplicatedStorage.Shared.domain.GateMath)
local Types = require(ReplicatedStorage.Shared.domain.Types)

type Hit = Types.Hit
type Level = Types.Level

local EncounterService = {}

-- Appends a hit for every unresolved obstacle or enemy crossed in the travel segment (fromZ, toZ].
function EncounterService.collect(
	level: Level,
	consumed: { [string]: boolean },
	fromZ: number,
	toZ: number,
	fromX: number,
	toX: number,
	out: { Hit }
)
	for _, obstacle in level.obstacles do
		if consumed[obstacle.id] or not GateMath.crossesZ(obstacle.z, fromZ, toZ) then
			continue
		end
		local x = GateMath.xAtZ(obstacle.z, fromZ, toZ, fromX, toX)
		if GateMath.containsX(obstacle.xMin, obstacle.xMax, x) then
			table.insert(out, { kind = "obstacle", id = obstacle.id, z = obstacle.z, obstacle = obstacle })
		end
	end
	for _, enemy in level.enemies do
		if not consumed[enemy.id] and GateMath.crossesZ(enemy.z, fromZ, toZ) then
			table.insert(out, { kind = "enemy", id = enemy.id, z = enemy.z, enemy = enemy })
		end
	end
end

return EncounterService
