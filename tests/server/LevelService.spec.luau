local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local GameConfig = require(ReplicatedStorage.Shared.config.GameConfig)
local Levels = require(ReplicatedStorage.Shared.config.Levels)
local LevelService = require(ServerScriptService.Server.services.LevelService)

local function copyLevel(level)
	local copy = table.clone(level)
	copy.gates = {}
	for _, gate in level.gates do
		table.insert(copy.gates, table.clone(gate))
	end
	copy.obstacles = {}
	for _, obstacle in level.obstacles do
		table.insert(copy.obstacles, table.clone(obstacle))
	end
	copy.enemies = {}
	for _, enemy in level.enemies do
		table.insert(copy.enemies, table.clone(enemy))
	end
	return copy
end

local function hasError(errors, fragment)
	for _, message in errors do
		if string.find(message, fragment, 1, true) then
			return true
		end
	end
	return false
end

return function()
	describe("shipped levels", function()
		it("has ten levels with ids 1..10", function()
			expect(#Levels.list).to.equal(10)
			for index, level in Levels.list do
				expect(level.id).to.equal(index)
			end
		end)

		it("validates every level", function()
			local ok, errors = LevelService.validateAll(Levels.list, GameConfig)
			if not ok then
				error(table.concat(errors, "\n"))
			end
		end)

		it("makes every level completable with a meaningful best score", function()
			for _, level in Levels.list do
				local best = LevelService.bestFinishCount(level, GameConfig)
				expect(best >= level.minFinishCount).to.equal(true)
			end
		end)

		it("gets harder: later levels need bigger groups to survive", function()
			local function largestEnemy(level)
				local largest = 0
				for _, enemy in level.enemies do
					largest = math.max(largest, enemy.count)
				end
				return largest
			end
			expect(largestEnemy(Levels.list[10]) > largestEnemy(Levels.list[1])).to.equal(true)
		end)

		it("keeps the steering config consistent with row spacing", function()
			local ok = LevelService.validateConfig(GameConfig)
			expect(ok).to.equal(true)
		end)
	end)

	describe("LevelService.bestFinishCount", function()
		it("matches a hand-computed optimum for level 1", function()
			-- 5 -> +10 -> x2 -> +8 -> x2 -> enemy 10
			expect(LevelService.bestFinishCount(Levels.list[1], GameConfig)).to.equal(66)
		end)

		it("reports zero when no path survives", function()
			local level = copyLevel(Levels.list[1])
			level.enemies[1].count = 10000
			expect(LevelService.bestFinishCount(level, GameConfig)).to.equal(0)
			local ok, errors = LevelService.validate(level, GameConfig)
			expect(ok).to.equal(false)
			expect(hasError(errors, "not completable")).to.equal(true)
		end)
	end)

	describe("LevelService.validate", function()
		it("rejects rows that are too close together", function()
			local level = copyLevel(Levels.list[1])
			level.gates[3].z = level.gates[1].z + 10
			level.gates[4].z = level.gates[1].z + 10
			local ok, errors = LevelService.validate(level, GameConfig)
			expect(ok).to.equal(false)
			expect(hasError(errors, "too close")).to.equal(true)
		end)

		it("rejects overlapping lanes in a row", function()
			local level = copyLevel(Levels.list[1])
			level.gates[1].xMax = 2
			local ok, errors = LevelService.validate(level, GameConfig)
			expect(ok).to.equal(false)
			expect(hasError(errors, "overlaps")).to.equal(true)
		end)

		it("rejects invalid operands, ops and duplicate ids", function()
			local level = copyLevel(Levels.list[1])
			level.gates[1].value = 0
			level.gates[2].op = "divide"
			level.gates[3].id = level.gates[4].id
			level.gates[5].value = 2.5
			local ok, errors = LevelService.validate(level, GameConfig)
			expect(ok).to.equal(false)
			expect(hasError(errors, "operand out of range")).to.equal(true)
			expect(hasError(errors, "unknown op")).to.equal(true)
			expect(hasError(errors, "duplicate element id")).to.equal(true)
		end)

		it("rejects elements outside the track or the playable zone", function()
			local level = copyLevel(Levels.list[1])
			level.gates[1].xMin = -40
			level.enemies[1].z = level.length
			local ok, errors = LevelService.validate(level, GameConfig)
			expect(ok).to.equal(false)
			expect(hasError(errors, "outside the track")).to.equal(true)
			expect(hasError(errors, "playable zone")).to.equal(true)
		end)

		it("rejects enemies sharing a row with gates", function()
			local level = copyLevel(Levels.list[1])
			level.enemies[1].z = level.gates[1].z
			local ok, errors = LevelService.validate(level, GameConfig)
			expect(ok).to.equal(false)
			expect(hasError(errors, "only one enemy squad")).to.equal(true)
		end)

		it("rejects broken top-level fields", function()
			local level = copyLevel(Levels.list[1])
			level.startCount = 0
			level.name = ""
			local ok, errors = LevelService.validate(level, GameConfig)
			expect(ok).to.equal(false)
			expect(hasError(errors, "startCount")).to.equal(true)
			expect(hasError(errors, "name")).to.equal(true)
		end)

		it("requires sequential level ids", function()
			local ok, errors = LevelService.validateAll({ Levels.list[2] }, GameConfig)
			expect(ok).to.equal(false)
			expect(hasError(errors, "ids must be 1..n")).to.equal(true)
		end)

		it("refuses to construct a service from invalid levels", function()
			local level = copyLevel(Levels.list[1])
			level.length = 10
			expect(function()
				LevelService.new({ level }, GameConfig)
			end).to.throw("invalid level definitions")
		end)
	end)

	describe("Levels.parseGate", function()
		it("parses gate specs", function()
			local op, value = Levels.parseGate("x3")
			expect(op).to.equal("multiply")
			expect(value).to.equal(3)
			expect(function()
				Levels.parseGate("/2")
			end).to.throw("invalid gate spec")
		end)
	end)
end
