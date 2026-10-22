--!strict
-- Declarative level definitions. Each row sits at a distance `z` along the track and fills lanes
-- with gates ("+N", "-N", "xN") or hazards (hazard(N)); `enemy = N` makes a full-width enemy row.
-- Lanes are half-open x ranges [xMin, xMax) so neighbouring lanes never overlap.
-- All levels are validated (including completability) by LevelService on server start and in tests.

local GameConfig = require(script.Parent.GameConfig)
local Types = require(script.Parent.Parent.domain.Types)

type Level = Types.Level
type GateOp = Types.GateOp

type Hazard = { hazard: number }
type LaneSpec = string | Hazard

type RowSpec = {
	z: number,
	enemy: number?,
	left: LaneSpec?,
	right: LaneSpec?,
	full: LaneSpec?,
	left3: LaneSpec?,
	mid3: LaneSpec?,
	right3: LaneSpec?,
}

type LevelSpec = {
	id: number,
	name: string,
	length: number,
	startCount: number,
	minFinishCount: number?,
	rows: { RowSpec },
}

local HALF = GameConfig.TRACK_WIDTH / 2
local THIRD = GameConfig.TRACK_WIDTH / 6

local LANES: { [string]: { number } } = {
	left = { -HALF, 0 },
	right = { 0, HALF },
	full = { -HALF, HALF },
	left3 = { -HALF, -THIRD },
	mid3 = { -THIRD, THIRD },
	right3 = { THIRD, HALF },
}
local LANE_ORDER = { "left", "left3", "full", "mid3", "right", "right3" }

local OPS: { [string]: GateOp } = {
	["+"] = "add",
	["-"] = "subtract",
	["x"] = "multiply",
}

local function hazard(damage: number): Hazard
	return { hazard = damage }
end

local function parseGate(spec: string): (GateOp, number)
	local symbol, digits = string.match(spec, "^([%+%-x])(%d+)$")
	assert(symbol and digits, `invalid gate spec "{spec}"`)
	local op: GateOp? = OPS[symbol]
	return assert(op, `unknown gate symbol "{symbol}"`), assert(tonumber(digits))
end

local function build(spec: LevelSpec): Level
	local level: Level = {
		id = spec.id,
		name = spec.name,
		length = spec.length,
		startCount = spec.startCount,
		minFinishCount = spec.minFinishCount or 1,
		gates = {},
		obstacles = {},
		enemies = {},
	}
	for index, row in spec.rows do
		if row.enemy then
			table.insert(level.enemies, { id = `r{index}-enemy`, z = row.z, count = row.enemy })
		end
		for _, laneName in LANE_ORDER do
			local laneSpec = (row :: any)[laneName] :: LaneSpec?
			if laneSpec == nil then
				continue
			end
			local bounds = LANES[laneName]
			local id = `r{index}-{laneName}`
			if type(laneSpec) == "string" then
				local op, value = parseGate(laneSpec)
				local gate: Types.Gate = {
					id = id,
					z = row.z,
					xMin = bounds[1],
					xMax = bounds[2],
					op = op :: GateOp,
					value = value,
				}
				table.insert(level.gates, gate)
			else
				table.insert(level.obstacles, {
					id = id,
					z = row.z,
					xMin = bounds[1],
					xMax = bounds[2],
					damage = laneSpec.hazard,
				})
			end
		end
	end
	return level
end

local list: { Level } = {
	build({
		id = 1,
		name = "First Steps",
		length = 400,
		startCount = 5,
		rows = {
			{ z = 60, left = "+5", right = "+10" },
			{ z = 120, left = "x2", right = "+3" },
			{ z = 180, left = "-5", right = "+8" },
			{ z = 240, left = "+10", right = "x2" },
			{ z = 320, enemy = 10 },
		},
	}),
	build({
		id = 2,
		name = "Choices",
		length = 460,
		startCount = 8,
		rows = {
			{ z = 60, left = "x2", right = "+5" },
			{ z = 120, left = "-4", right = "-10" },
			{ z = 180, left = "+6", right = "x2" },
			{ z = 240, left = hazard(6), right = "-2" },
			{ z = 300, left = "x3", right = "+20" },
			{ z = 380, enemy = 20 },
		},
	}),
	build({
		id = 3,
		name = "Narrow Path",
		length = 520,
		startCount = 10,
		rows = {
			{ z = 60, left3 = "+5", mid3 = "x2", right3 = "+15" },
			{ z = 120, left3 = hazard(8), mid3 = "+10", right3 = hazard(8) },
			{ z = 180, left = "x2", right = "-10" },
			{ z = 240, enemy = 25 },
			{ z = 300, left3 = "+10", mid3 = "-20", right3 = "x2" },
			{ z = 360, left = hazard(15), right = "+5" },
			{ z = 440, enemy = 40 },
		},
	}),
	build({
		id = 4,
		name = "Multiplier Mayhem",
		length = 600,
		startCount = 6,
		rows = {
			{ z = 60, left = "x3", right = "+10" },
			{ z = 120, left = "-8", right = "x2" },
			{ z = 180, left3 = "x2", mid3 = hazard(10), right3 = "+30" },
			{ z = 240, enemy = 30 },
			{ z = 300, left = "x2", right = "x3" },
			{ z = 360, left3 = hazard(20), mid3 = "+15", right3 = hazard(20) },
			{ z = 420, left = "-50", right = "-30" },
			{ z = 500, enemy = 60 },
		},
	}),
	build({
		id = 5,
		name = "Gauntlet",
		length = 680,
		startCount = 12,
		rows = {
			{ z = 60, left = "+8", right = "x2" },
			{ z = 120, left3 = hazard(10), mid3 = hazard(10), right3 = "+4" },
			{ z = 180, left = "x2", right = "+20" },
			{ z = 240, left3 = "+10", mid3 = hazard(30), right3 = "+10" },
			{ z = 300, enemy = 40 },
			{ z = 360, left = "x3", right = "+40" },
			{ z = 420, left = hazard(25), right = "-10" },
			{ z = 480, left3 = "x2", mid3 = "-30", right3 = "+50" },
			{ z = 550, left = "+20", right = "-20" },
			{ z = 620, enemy = 100 },
		},
	}),
	build({
		id = 6,
		name = "Split Decision",
		length = 760,
		startCount = 10,
		rows = {
			{ z = 60, left = "x2", right = "x3" },
			{ z = 120, left = "-15", right = "+5" },
			{ z = 180, enemy = 20 },
			{ z = 240, left3 = "x4", mid3 = "+20", right3 = "-5" },
			{ z = 300, left = hazard(20), right = "+10" },
			{ z = 360, left = "x2", right = "+60" },
			{ z = 420, left3 = "-40", mid3 = "-25", right3 = "-40" },
			{ z = 480, enemy = 60 },
			{ z = 540, left = "x3", right = "+80" },
			{ z = 600, left3 = hazard(40), mid3 = "+30", right3 = hazard(40) },
			{ z = 680, enemy = 120 },
		},
	}),
	build({
		id = 7,
		name = "Swarm",
		length = 840,
		startCount = 15,
		rows = {
			{ z = 60, left = "+15", right = "x2" },
			{ z = 120, left3 = "x3", mid3 = hazard(15), right3 = "+40" },
			{ z = 180, enemy = 50 },
			{ z = 240, left = "x2", right = "+30" },
			{ z = 300, left3 = "+25", mid3 = "x2", right3 = "-20" },
			{ z = 360, left = hazard(50), right = hazard(30) },
			{ z = 420, enemy = 70 },
			{ z = 480, left = "x4", right = "+150" },
			{ z = 540, left3 = "-60", mid3 = "+20", right3 = "-60" },
			{ z = 600, left = "x2", right = "-100" },
			{ z = 660, enemy = 200 },
			{ z = 740, enemy = 150 },
		},
	}),
	build({
		id = 8,
		name = "Tight Squeeze",
		length = 900,
		startCount = 20,
		rows = {
			{ z = 60, left3 = hazard(10), mid3 = "x2", right3 = hazard(10) },
			{ z = 110, left = "+20", right = "x2" },
			{ z = 160, left3 = "x2", mid3 = hazard(40), right3 = "x3" },
			{ z = 210, enemy = 100 },
			{ z = 270, left = "-50", right = "x2" },
			{ z = 330, left3 = hazard(60), mid3 = hazard(60), right3 = "+10" },
			{ z = 390, left = "x3", right = "+400" },
			{ z = 450, enemy = 300 },
			{ z = 510, left3 = "+100", mid3 = "-200", right3 = "x2" },
			{ z = 570, left = hazard(200), right = "-150" },
			{ z = 640, enemy = 500 },
			{ z = 720, left = "x2", right = "+300" },
			{ z = 800, enemy = 600 },
		},
	}),
	build({
		id = 9,
		name = "Zillion Rush",
		length = 980,
		startCount = 25,
		rows = {
			{ z = 60, left = "x2", right = "+30" },
			{ z = 110, left3 = "x3", mid3 = "x2", right3 = "+100" },
			{ z = 160, enemy = 80 },
			{ z = 220, left = "x4", right = "+250" },
			{ z = 280, left3 = hazard(100), mid3 = "+50", right3 = hazard(100) },
			{ z = 340, left = "x3", right = "x2" },
			{ z = 400, enemy = 600 },
			{ z = 460, left3 = "-200", mid3 = "x2", right3 = "-100" },
			{ z = 520, left = "+500", right = "x2" },
			{ z = 580, left3 = hazard(500), mid3 = hazard(800), right3 = hazard(500) },
			{ z = 640, enemy = 1000 },
			{ z = 700, left = "x3", right = "+1000" },
			{ z = 770, enemy = 1500 },
			{ z = 850, left = "x2", right = "+500" },
			{ z = 920, enemy = 1200 },
		},
	}),
	build({
		id = 10,
		name = "GateZillion",
		length = 1100,
		startCount = 30,
		rows = {
			{ z = 60, left = "x2", right = "x3" },
			{ z = 110, left3 = "+60", mid3 = hazard(20), right3 = "x2" },
			{ z = 160, enemy = 100 },
			{ z = 220, left = "x5", right = "+300" },
			{ z = 280, left3 = hazard(150), mid3 = "x2", right3 = hazard(150) },
			{ z = 340, enemy = 500 },
			{ z = 400, left = "x4", right = "+1000" },
			{ z = 460, left3 = "-400", mid3 = "-200", right3 = "-600" },
			{ z = 520, left = "x3", right = "x2" },
			{ z = 580, enemy = 2000 },
			{ z = 640, left3 = "x2", mid3 = hazard(1000), right3 = "+1000" },
			{ z = 700, left = "x4", right = "+1000" },
			{ z = 760, enemy = 6000 },
			{ z = 820, left = hazard(1000), right = "-1000" },
			{ z = 880, left3 = "x5", mid3 = "x2", right3 = "x3" },
			{ z = 940, enemy = 12000 },
			{ z = 1020, enemy = 3000 },
		},
	}),
}

local function deepFreeze<T>(value: T): T
	if type(value) == "table" and not table.isfrozen(value :: any) then
		for _, child in value :: any do
			deepFreeze(child)
		end
		table.freeze(value :: any)
	end
	return value
end

local Levels = {
	list = deepFreeze(list),
	-- Exposed for tests and future tooling.
	hazard = hazard,
	parseGate = parseGate,
	build = build,
}

function Levels.get(levelId: number): Level?
	return Levels.list[levelId]
end

return Levels
