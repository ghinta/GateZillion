local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local GameConfig = require(ReplicatedStorage.Shared.config.GameConfig)
local Levels = require(ReplicatedStorage.Shared.config.Levels)
local services = ServerScriptService.Server.services
local LevelService = require(services.LevelService)
local ProfileService = require(services.ProfileService)
local ProfileStore = require(services.ProfileStore)
local RunService = require(services.RunService)

local STEP = GameConfig.SIMULATION_STEP

local function fakeGateway()
	local gateway = { snapshots = {}, events = {}, ended = {}, profiles = {} }
	function gateway:sendSnapshot(_player, snapshot)
		table.insert(self.snapshots, snapshot)
	end
	function gateway:sendRunEvent(_player, event)
		table.insert(self.events, event)
	end
	function gateway:sendRunEnded(_player, payload)
		table.insert(self.ended, payload)
	end
	function gateway:sendProfile(_player, view)
		table.insert(self.profiles, view)
	end
	return gateway
end

local function setup()
	local now = 0
	local store = ProfileStore.memory()
	local profiles = ProfileService.new({
		store = store,
		jobId = "test-server",
		now = function()
			return 1000
		end,
		wait = function() end,
		spawn = function(fn)
			fn()
		end,
		warn = function() end,
	})
	local gateway = fakeGateway()
	local levels = LevelService.new(Levels.list, GameConfig)
	local runs = RunService.new({
		levels = levels,
		profiles = profiles,
		gateway = gateway,
		clock = function()
			return now
		end,
	})
	local player = { UserId = 101, Name = "Tester" }
	runs:addPlayer(player)
	assert(profiles:load(player.UserId))
	local env = {
		runs = runs,
		profiles = profiles,
		gateway = gateway,
		levels = levels,
		store = store,
		player = player,
	}
	function env.advanceClock(seconds)
		now += seconds
	end
	-- Simulates `seconds` of server time; `steer(run)` may return an axis each step.
	function env.simulate(seconds, steer)
		local steps = math.ceil(seconds / STEP)
		for _ = 1, steps do
			if steer then
				local run = runs:getRun(player)
				local axis = steer(run)
				if axis then
					runs:steer(player, axis)
				end
			end
			runs:tick(STEP)
			now += STEP
		end
	end
	return env
end

-- Steers towards the lane centre of the best gate in the next row (perfect play).
local function bestLaneSteer(levelId)
	local level = Levels.list[levelId]
	local limit = GameConfig.TRACK_WIDTH / 2 - GameConfig.EDGE_MARGIN
	local function choose(run)
		local nextZ = math.huge
		for _, list in { level.gates, level.obstacles } do
			for _, element in list do
				if element.z > run.progress and element.z < nextZ then
					nextZ = element.z
				end
			end
		end
		if nextZ == math.huge then
			return 0
		end
		-- Score every lateral position, then aim for the middle of the first best stretch so
		-- the group never sits on a lane boundary.
		local samples = {}
		local bestCount = -math.huge
		for x = -limit, limit + 1e-6, 0.25 do
			local count = run.groupCount
			for _, gate in level.gates do
				if gate.z == nextZ and x >= gate.xMin and x < gate.xMax then
					if gate.op == "add" then
						count += gate.value
					elseif gate.op == "subtract" then
						count -= gate.value
					else
						count *= gate.value
					end
				end
			end
			for _, obstacle in level.obstacles do
				if obstacle.z == nextZ and x >= obstacle.xMin and x < obstacle.xMax then
					count -= obstacle.damage
				end
			end
			count = math.max(count, 0)
			table.insert(samples, { x = x, count = count })
			bestCount = math.max(bestCount, count)
		end
		local first, last
		for _, sample in samples do
			if sample.count == bestCount then
				first = first or sample.x
				last = sample.x
			elseif first then
				break
			end
		end
		local bestX = (first + last) / 2
		local delta = bestX - run.laneX
		if math.abs(delta) < 0.3 then
			return 0
		end
		return math.clamp(delta, -1, 1)
	end
	return choose
end

return function()
	describe("RunService start validation", function()
		it("starts an unlocked level and enters Loading", function()
			local env = setup()
			local ok = env.runs:startRun(env.player, 1)
			expect(ok).to.equal(true)
			local run = env.runs:getRun(env.player)
			expect(run.phase).to.equal("Loading")
			expect(run.groupCount).to.equal(Levels.list[1].startCount)
			expect(#env.gateway.snapshots).to.equal(1)
		end)

		it("rejects locked levels", function()
			local env = setup()
			local ok, reason = env.runs:startRun(env.player, 2)
			expect(ok).to.equal(false)
			expect(reason).to.equal("level locked")
		end)

		it("rejects starts while a run is in progress", function()
			local env = setup()
			env.runs:startRun(env.player, 1)
			env.advanceClock(5)
			local ok, reason = env.runs:startRun(env.player, 1)
			expect(ok).to.equal(false)
			expect(reason).to.equal("run in progress")
		end)

		it("rejects players without a loaded profile", function()
			local env = setup()
			local stranger = { UserId = 202, Name = "Stranger" }
			env.runs:addPlayer(stranger)
			local ok, reason = env.runs:startRun(stranger, 1)
			expect(ok).to.equal(false)
			expect(reason).to.equal("profile not loaded")
			ok, reason = env.runs:startRun({ UserId = 303, Name = "Unknown" }, 1)
			expect(ok).to.equal(false)
			expect(reason).to.equal("unknown player")
		end)
	end)

	describe("RunService simulation", function()
		it("counts down, then runs", function()
			local env = setup()
			env.runs:startRun(env.player, 1)
			env.simulate(GameConfig.COUNTDOWN_SECONDS - 0.5)
			expect(env.runs:getRun(env.player).phase).to.equal("Loading")
			env.simulate(1)
			local run = env.runs:getRun(env.player)
			expect(run.phase).to.equal("Running")
			expect(run.progress > 0).to.equal(true)
		end)

		it("applies the gate in the group's lane exactly once", function()
			local env = setup()
			env.runs:startRun(env.player, 1)
			-- Hold right: level 1 row 1 is left "+5" / right "+10".
			env.simulate(GameConfig.COUNTDOWN_SECONDS + 70 / GameConfig.FORWARD_SPEED, function()
				return 1
			end)
			local first = env.gateway.events[1]
			expect(first.kind).to.equal("gate")
			expect(first.id).to.equal("r1-right")
			expect(first.before).to.equal(5)
			expect(first.after).to.equal(15)
			local count = 0
			for _, event in env.gateway.events do
				if event.id == "r1-right" then
					count += 1
				end
			end
			expect(count).to.equal(1)
		end)

		it("completes level 1 with perfect play, awards once and unlocks level 2", function()
			local env = setup()
			env.runs:startRun(env.player, 1)
			env.simulate(
				GameConfig.COUNTDOWN_SECONDS + Levels.list[1].length / GameConfig.FORWARD_SPEED + 1,
				bestLaneSteer(1)
			)
			local run = env.runs:getRun(env.player)
			expect(run.phase).to.equal("Results")
			expect(run.result).to.equal("Completed")
			expect(#env.gateway.ended).to.equal(1)
			local ended = env.gateway.ended[1]
			expect(ended.result).to.equal("Completed")
			expect(ended.finalCount).to.equal(env.levels:bestFinishCount(1))
			expect(ended.stars).to.equal(3)
			expect(ended.unlockedLevel).to.equal(2)
			expect(ended.earnedPoints).to.equal(ended.finalCount + GameConfig.FIRST_CLEAR_BONUS)
			local profile = env.profiles:get(env.player.UserId)
			expect(profile.highestUnlockedLevel).to.equal(2)
			expect(profile.earnedPoints).to.equal(ended.earnedPoints)

			-- Further ticks in Results never award again.
			env.simulate(5)
			expect(#env.gateway.ended).to.equal(1)
			expect(env.profiles:get(env.player.UserId).earnedPoints).to.equal(ended.earnedPoints)

			-- The reward was persisted.
			local stored = env.store.data["User_101"]
			expect(stored.profile.highestUnlockedLevel).to.equal(2)
		end)

		it("reaches the computed best finish count on every level", function()
			for levelId = 1, #Levels.list do
				local env = setup()
				env.profiles:get(env.player.UserId).highestUnlockedLevel = levelId
				env.runs:startRun(env.player, levelId)
				local level = Levels.list[levelId]
				env.simulate(
					GameConfig.COUNTDOWN_SECONDS + level.length / GameConfig.FORWARD_SPEED + 1,
					bestLaneSteer(levelId)
				)
				local ended = env.gateway.ended[1]
				expect(ended).to.be.ok()
				if ended.finalCount ~= env.levels:bestFinishCount(levelId) then
					error(
						`level {levelId}: finished with {ended.finalCount}, best is {env.levels:bestFinishCount(levelId)}`
					)
				end
				expect(ended.result).to.equal("Completed")
			end
		end)

		it("fails the run when the group is wiped out", function()
			local env = setup()
			env.runs:startRun(env.player, 1)
			-- Play until just before level 1's enemy row (z = 320, 10 enemies) with a tiny group.
			env.simulate(GameConfig.COUNTDOWN_SECONDS + 260 / GameConfig.FORWARD_SPEED)
			local run = env.runs:getRun(env.player)
			expect(run.phase).to.equal("Running")
			run.groupCount = 3
			env.simulate(100 / GameConfig.FORWARD_SPEED)
			expect(run.phase).to.equal("Results")
			expect(run.result).to.equal("Failed")
			local ended = env.gateway.ended[1]
			expect(ended.reason).to.equal("groupLost")
			expect(ended.finalCount).to.equal(0)
			expect(ended.earnedPoints).to.equal(0)
			expect(env.profiles:get(env.player.UserId).highestUnlockedLevel).to.equal(1)
			local last = env.gateway.events[#env.gateway.events]
			expect(last.kind).to.equal("enemy")
			expect(last.after).to.equal(0)
		end)

		it("allows a retry from Results after the cooldown", function()
			local env = setup()
			env.runs:startRun(env.player, 1)
			env.simulate(GameConfig.COUNTDOWN_SECONDS + Levels.list[1].length / GameConfig.FORWARD_SPEED + 1)
			expect(env.runs:getRun(env.player).phase).to.equal("Results")
			local ok = env.runs:startRun(env.player, 1)
			expect(ok).to.equal(true)
			expect(env.runs:getRun(env.player).runId).to.equal(2)
		end)

		it("enforces the start cooldown", function()
			local env = setup()
			env.runs:startRun(env.player, 1)
			local run = env.runs:getRun(env.player)
			-- Force the run to end immediately.
			env.simulate(GameConfig.COUNTDOWN_SECONDS + 0.1)
			run.groupCount = 0
			run.progress = Levels.list[1].length
			env.simulate(STEP)
			expect(run.phase).to.equal("Results")
			local ok, reason = env.runs:startRun(env.player, 1)
			if GameConfig.COUNTDOWN_SECONDS + 0.2 < GameConfig.START_RUN_COOLDOWN then
				expect(ok).to.equal(false)
				expect(reason).to.equal("cooldown")
			else
				expect(ok).to.equal(true)
			end
		end)

		it("sends periodic snapshots only for active runs", function()
			local env = setup()
			env.simulate(1)
			expect(#env.gateway.snapshots).to.equal(0)
			env.runs:startRun(env.player, 1)
			env.simulate(1)
			local count = #env.gateway.snapshots
			expect(count >= GameConfig.SNAPSHOT_RATE - 1 and count <= GameConfig.SNAPSHOT_RATE + 2).to.equal(true)
		end)

		it("discards the run when the player leaves", function()
			local env = setup()
			env.runs:startRun(env.player, 1)
			env.runs:removePlayer(env.player)
			expect(env.runs:getRun(env.player)).to.equal(nil)
			env.simulate(30)
			expect(#env.gateway.ended).to.equal(0)
		end)

		it("sends the profile once the client is ready", function()
			local env = setup()
			env.runs:profileLoaded(env.player)
			expect(#env.gateway.profiles).to.equal(0)
			env.runs:clientReady(env.player)
			expect(#env.gateway.profiles).to.equal(1)
			expect(env.gateway.profiles[1].highestUnlockedLevel).to.equal(1)
		end)
	end)
end
