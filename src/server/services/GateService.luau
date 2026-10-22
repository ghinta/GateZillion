--!strict
-- Gate crossing detection. A gate takes effect when the group passes its row while the
-- interpolated lateral position lies inside the gate's lane, and only on the first crossing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GateMath = require(ReplicatedStorage.Shared.domain.GateMath)
local Types = require(ReplicatedStorage.Shared.domain.Types)

type Hit = Types.Hit
type Level = Types.Level

local GateService = {}

-- Appends a hit for every unconsumed gate crossed in the travel segment (fromZ, toZ].
function GateService.collect(
	level: Level,
	consumed: { [string]: boolean },
	fromZ: number,
	toZ: number,
	fromX: number,
	toX: number,
	out: { Hit }
)
	for _, gate in level.gates do
		if consumed[gate.id] or not GateMath.crossesZ(gate.z, fromZ, toZ) then
			continue
		end
		local x = GateMath.xAtZ(gate.z, fromZ, toZ, fromX, toX)
		if GateMath.containsX(gate.xMin, gate.xMax, x) then
			table.insert(out, { kind = "gate", id = gate.id, z = gate.z, gate = gate })
		end
	end
end

return GateService
