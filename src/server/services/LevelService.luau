--!strict
-- Level lookup and validation. Every definition is validated on server start; an invalid level
-- stops the server from accepting runs instead of failing mid-game.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.config.GameConfig)
local GateMath = require(ReplicatedStorage.Shared.domain.GateMath)
local Hits = require(ReplicatedStorage.Shared.domain.Hits)
local RunState = require(ReplicatedStorage.Shared.domain.RunState)
local Types = require(ReplicatedStorage.Shared.domain.Types)
local EncounterService = require(script.Parent.EncounterService)
local GateService = require(script.Parent.GateService)

type Level = Types.Level
type Hit = Types.Hit
type Config = typeof(GameConfig)

export type LevelService = {
	get: (self: LevelService, levelId: number) -> Level?,
	count: (self: LevelService) -> number,
	bestFinishCount: (self: LevelService, levelId: number) -> number,
}

type Row = {
	z: number,
	ranges: { { xMin: number, xMax: number, id: string } },
	enemyCount: number,
}

local ROW_EPSILON = 1e-3

local LevelService = {}

local function isFinite(value: unknown): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function isIntegerIn(value: unknown, min: number, max: number): boolean
	return isFinite(value)
		and GateMath.isInteger(value :: number)
		and (value :: number) >= min
		and (value :: number) <= max
end

-- The steering speed must allow crossing the full playable width between two rows, otherwise
-- some lane choices would be unreachable.
function LevelService.validateConfig(config: Config): (boolean, { string })
	local errors = {}
	local travel = 2 * RunState.laneLimit(config)
	local zNeeded = config.FORWARD_SPEED * travel / config.STEER_SPEED
	if zNeeded > config.ROW_MIN_SPACING then
		table.insert(errors, `ROW_MIN_SPACING {config.ROW_MIN_SPACING} < {zNeeded} needed to cross the track`)
	end
	return #errors == 0, errors
end

local function collectRows(level: Level): { Row }
	local byZ: { [number]: Row } = {}
	local function rowAt(z: number): Row
		local row = byZ[z]
		if row == nil then
			row = { z = z, ranges = {}, enemyCount = 0 }
			byZ[z] = row
		end
		return row
	end
	for _, gate in level.gates do
		table.insert(rowAt(gate.z).ranges, { xMin = gate.xMin, xMax = gate.xMax, id = gate.id })
	end
	for _, obstacle in level.obstacles do
		table.insert(rowAt(obstacle.z).ranges, { xMin = obstacle.xMin, xMax = obstacle.xMax, id = obstacle.id })
	end
	for _, enemy in level.enemies do
		rowAt(enemy.z).enemyCount += 1
	end
	local rows = {}
	for _, row in byZ do
		table.insert(rows, row)
	end
	table.sort(rows, function(a, b)
		return a.z < b.z
	end)
	return rows
end

-- Best finish count reachable with perfect steering. Every outcome rule is monotonic in the
-- group size and every lane is reachable between rows, so the greedy per-row maximum is optimal.
function LevelService.bestFinishCount(level: Level, config: Config): number
	local limit = RunState.laneLimit(config)
	local count = level.startCount
	local noneConsumed = {}

	for _, row in collectRows(level) do
		local boundaries = { -limit, limit }
		for _, range in row.ranges do
			for _, x in { range.xMin, range.xMax } do
				if x > -limit and x < limit then
					table.insert(boundaries, x)
				end
			end
		end
		table.sort(boundaries)
		local candidates = table.clone(boundaries)
		for i = 1, #boundaries - 1 do
			table.insert(candidates, (boundaries[i] + boundaries[i + 1]) / 2)
		end

		local best = 0
		for _, x in candidates do
			local hits: { Hit } = {}
			GateService.collect(level, noneConsumed, row.z - ROW_EPSILON, row.z, x, x, hits)
			EncounterService.collect(level, noneConsumed, row.z - ROW_EPSILON, row.z, x, x, hits)
			Hits.sort(hits)
			local result = count
			for _, hit in hits do
				result = Hits.apply(hit, result, config.MAX_GROUP_SIZE)
				if result == 0 then
					break
				end
			end
			best = math.max(best, result)
		end

		count = best
		if count == 0 then
			return 0
		end
	end
	return count
end

function LevelService.validate(level: Level, config: Config): (boolean, { string })
	local errors: { string } = {}
	local function check(condition: boolean, message: string)
		if not condition then
			table.insert(errors, `level {tostring(level.id)}: {message}`)
		end
	end

	check(isIntegerIn(level.id, 1, math.huge), "id must be a positive integer")
	check(type(level.name) == "string" and #level.name > 0 and #level.name <= 40, "name must be 1-40 characters")
	check(
		isFinite(level.length) and level.length >= config.MIN_LEVEL_LENGTH and level.length <= config.MAX_LEVEL_LENGTH,
		"length out of range"
	)
	check(isIntegerIn(level.startCount, 1, config.MAX_GROUP_SIZE), "startCount out of range")
	check(isIntegerIn(level.minFinishCount, 1, config.MAX_GROUP_SIZE), "minFinishCount out of range")
	check(type(level.gates) == "table", "gates must be a list")
	check(type(level.obstacles) == "table", "obstacles must be a list")
	check(type(level.enemies) == "table", "enemies must be a list")
	if #errors > 0 then
		return false, errors
	end

	local half = config.TRACK_WIDTH / 2
	local limit = RunState.laneLimit(config)
	local seenIds: { [string]: boolean } = {}

	local function checkElement(element: { id: string, z: number })
		check(type(element.id) == "string" and #element.id > 0, "element id must be a non-empty string")
		check(not seenIds[element.id], `duplicate element id {tostring(element.id)}`)
		seenIds[element.id] = true
		check(
			isFinite(element.z) and element.z >= config.START_ZONE and element.z <= level.length - config.FINISH_ZONE,
			`{element.id}: z outside the playable zone`
		)
	end

	local function checkRange(element: { id: string, xMin: number, xMax: number })
		local valid = isFinite(element.xMin) and isFinite(element.xMax) and element.xMin < element.xMax
		check(valid, `{element.id}: invalid lane range`)
		if valid then
			check(element.xMin >= -half and element.xMax <= half, `{element.id}: lane outside the track`)
			check(element.xMax > -limit and element.xMin < limit, `{element.id}: lane unreachable`)
		end
	end

	for _, gate in level.gates do
		checkElement(gate)
		checkRange(gate)
		check(GateMath.isValidOp(gate.op), `{gate.id}: unknown op {tostring(gate.op)}`)
		if gate.op == "multiply" then
			check(isIntegerIn(gate.value, 2, config.MAX_MULTIPLY_OPERAND), `{gate.id}: multiplier out of range`)
		else
			check(isIntegerIn(gate.value, 1, config.MAX_ADD_OPERAND), `{gate.id}: operand out of range`)
		end
	end
	for _, obstacle in level.obstacles do
		checkElement(obstacle)
		checkRange(obstacle)
		check(isIntegerIn(obstacle.damage, 1, config.MAX_ADD_OPERAND), `{obstacle.id}: damage out of range`)
	end
	for _, enemy in level.enemies do
		checkElement(enemy)
		check(isIntegerIn(enemy.count, 1, config.MAX_GROUP_SIZE), `{enemy.id}: count out of range`)
	end
	if #errors > 0 then
		return false, errors
	end

	local rows = collectRows(level)
	for index, row in rows do
		if index > 1 then
			local gap = row.z - rows[index - 1].z
			check(gap >= config.ROW_MIN_SPACING, `rows at z={rows[index - 1].z} and z={row.z} are too close`)
		end
		if row.enemyCount > 0 then
			check(row.enemyCount == 1 and #row.ranges == 0, `row at z={row.z} must contain only one enemy squad`)
		end
		for i = 1, #row.ranges do
			for j = i + 1, #row.ranges do
				local a, b = row.ranges[i], row.ranges[j]
				check(not (a.xMin < b.xMax and b.xMin < a.xMax), `{a.id} overlaps {b.id}`)
			end
		end
	end

	if #errors == 0 then
		local best = LevelService.bestFinishCount(level, config)
		check(best >= level.minFinishCount, `not completable (best finish count {best})`)
	end

	return #errors == 0, errors
end

function LevelService.validateAll(levels: { Level }, config: Config): (boolean, { string })
	local errors: { string } = {}
	local _, configErrors = LevelService.validateConfig(config)
	table.move(configErrors, 1, #configErrors, #errors + 1, errors)
	if #levels == 0 then
		table.insert(errors, "no levels defined")
	end
	for index, level in levels do
		if level.id ~= index then
			table.insert(errors, `level at position {index} has id {tostring(level.id)}; ids must be 1..n`)
		end
		local _, levelErrors = LevelService.validate(level, config)
		table.move(levelErrors, 1, #levelErrors, #errors + 1, errors)
	end
	return #errors == 0, errors
end

local LevelServiceClass = {}
LevelServiceClass.__index = LevelServiceClass

type Self = typeof(setmetatable(
	{} :: {
		levels: { Level },
		best: { [number]: number },
	},
	LevelServiceClass
))

-- Validates all levels and errors with every problem listed when any is invalid.
function LevelService.new(levels: { Level }, options: Config?): LevelService
	local config = options or GameConfig
	local ok, errors = LevelService.validateAll(levels, config)
	if not ok then
		error("invalid level definitions:\n" .. table.concat(errors, "\n"), 2)
	end
	local best = {}
	for _, level in levels do
		best[level.id] = LevelService.bestFinishCount(level, config)
	end
	local self = setmetatable({ levels = levels, best = best }, LevelServiceClass)
	return (self :: any) :: LevelService
end

function LevelServiceClass.get(self: Self, levelId: number): Level?
	return self.levels[levelId]
end

function LevelServiceClass.count(self: Self): number
	return #self.levels
end

function LevelServiceClass.bestFinishCount(self: Self, levelId: number): number
	return self.best[levelId] or 0
end

return LevelService
