--!strict
-- Pure gate arithmetic and crossing geometry. No Roblox APIs; covered by tests/shared/GateMath.spec.luau.

local Types = require(script.Parent.Types)

type GateOp = Types.GateOp

local GateMath = {}

local OPS: { GateOp } = { "add", "subtract", "multiply" }
GateMath.OPS = table.freeze(OPS)

local SYMBOLS: { [GateOp]: string } = table.freeze({
	add = "+",
	subtract = "-",
	multiply = "×",
})

local function isInteger(value: number): boolean
	return value == value and value == math.floor(value) and math.abs(value) ~= math.huge
end

GateMath.isInteger = isInteger

function GateMath.isValidOp(op: unknown): boolean
	return op == "add" or op == "subtract" or op == "multiply"
end

-- Clamps a group size to the integer range 0..maxGroupSize.
function GateMath.clamp(count: number, maxGroupSize: number): number
	assert(count == count, "group count is NaN")
	if count <= 0 then
		return 0
	elseif count >= maxGroupSize then
		return maxGroupSize
	end
	return math.floor(count)
end

-- Applies a gate to the current group size and returns the clamped result.
function GateMath.apply(op: GateOp, operand: number, count: number, maxGroupSize: number): number
	assert(isInteger(operand), "gate operand must be an integer")
	assert(isInteger(count), "group count must be an integer")
	local result: number
	if op == "add" then
		result = count + operand
	elseif op == "subtract" then
		result = count - operand
	elseif op == "multiply" then
		result = count * operand
	else
		error(`unknown gate op {op}`)
	end
	return GateMath.clamp(result, maxGroupSize)
end

function GateMath.symbol(op: GateOp): string
	return SYMBOLS[op]
end

-- Player-facing label, e.g. "+10", "-5", "×3". The symbol carries the meaning, colour is secondary.
function GateMath.label(op: GateOp, value: number): string
	return `{SYMBOLS[op]}{value}`
end

function GateMath.isBeneficial(op: GateOp): boolean
	return op ~= "subtract"
end

-- True when a row at `z` lies inside the half-open travel segment (fromZ, toZ].
function GateMath.crossesZ(z: number, fromZ: number, toZ: number): boolean
	return z > fromZ and z <= toZ
end

-- Lateral position at `z`, linearly interpolated over the travel segment.
function GateMath.xAtZ(z: number, fromZ: number, toZ: number, fromX: number, toX: number): number
	if toZ <= fromZ then
		return toX
	end
	local alpha = math.clamp((z - fromZ) / (toZ - fromZ), 0, 1)
	return fromX + (toX - fromX) * alpha
end

-- Lanes are half-open ranges [xMin, xMax), so adjacent lanes never both contain a position.
function GateMath.containsX(xMin: number, xMax: number, x: number): boolean
	return x >= xMin and x < xMax
end

return GateMath
