--!strict
-- Authoritative runs. One run record per player; the server simulates movement with a fixed
-- step, resolves gates and encounters, ends runs and commits rewards exactly once.
-- (Not to be confused with Roblox's RunService, which init.server.luau uses for Heartbeat.)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.config.GameConfig)
local Hits = require(ReplicatedStorage.Shared.domain.Hits)
local Rewards = require(ReplicatedStorage.Shared.domain.Rewards)
local RunState = require(ReplicatedStorage.Shared.domain.RunState)
local Types = require(ReplicatedStorage.Shared.domain.Types)
local Protocol = require(ReplicatedStorage.Shared.net.Protocol)
local EncounterService = require(script.Parent.EncounterService)
local GateService = require(script.Parent.GateService)
local LevelService = require(script.Parent.LevelService)

type Config = typeof(GameConfig)
type Level = Types.Level
type Hit = Types.Hit
type Run = RunState.Run

-- The parts of RemoteGateway and ProfileService that runs depend on (fakes in tests).
export type Gateway = {
	sendSnapshot: (self: Gateway, player: Player, snapshot: Protocol.Snapshot) -> (),
	sendRunEvent: (self: Gateway, player: Player, event: Protocol.RunEvent) -> (),
	sendRunEnded: (self: Gateway, player: Player, payload: Protocol.RunEnded) -> (),
	sendProfile: (self: Gateway, player: Player, view: Protocol.ProfileView) -> (),
}

export type Profiles = {
	isLoaded: (self: Profiles, userId: number) -> boolean,
	highestUnlockedLevel: (self: Profiles, userId: number) -> number?,
	view: (self: Profiles, userId: number) -> Protocol.ProfileView?,
	commitRun: (
		self: Profiles,
		userId: number,
		levelId: number,
		finalCount: number,
		levelCount: number
	) -> Rewards.RewardResult?,
}

export type Options = {
	levels: LevelService.LevelService,
	profiles: Profiles,
	gateway: Gateway,
	-- Monotonic seconds (os.clock) for cooldowns.
	clock: () -> number,
	config: Config?,
}

export type RunService = {
	addPlayer: (self: RunService, player: Player) -> (),
	removePlayer: (self: RunService, player: Player) -> (),
	getRun: (self: RunService, player: Player) -> Run?,
	startRun: (self: RunService, player: Player, levelId: number) -> (boolean, string?),
	steer: (self: RunService, player: Player, axis: number) -> (),
	clientReady: (self: RunService, player: Player) -> (),
	profileLoaded: (self: RunService, player: Player) -> (),
	tick: (self: RunService, dt: number) -> (),
}

type Session = {
	player: Player,
	run: Run,
	lastStartAt: number,
	clientReady: boolean,
}

local RunService = {}
RunService.__index = RunService

type Self = typeof(setmetatable(
	{} :: {
		levels: LevelService.LevelService,
		profiles: Profiles,
		gateway: Gateway,
		clock: () -> number,
		config: Config,
		sessions: { [Player]: Session },
		nextRunId: number,
		accumulator: number,
		snapshotTimer: number,
	},
	RunService
))

function RunService.new(options: Options): RunService
	local self = setmetatable({
		levels = options.levels,
		profiles = options.profiles,
		gateway = options.gateway,
		clock = options.clock,
		config = options.config or GameConfig,
		sessions = {},
		nextRunId = 0,
		accumulator = 0,
		snapshotTimer = 0,
	}, RunService)
	return (self :: any) :: RunService
end

function RunService.addPlayer(self: Self, player: Player)
	if self.sessions[player] == nil then
		self.sessions[player] = {
			player = player,
			run = RunState.new(),
			lastStartAt = -math.huge,
			clientReady = false,
		}
	end
end

-- Leaving discards any unfinished run; nothing is awarded.
function RunService.removePlayer(self: Self, player: Player)
	self.sessions[player] = nil
end

function RunService.getRun(self: Self, player: Player): Run?
	local session = self.sessions[player]
	return if session then session.run else nil
end

local function sendProfile(self: Self, session: Session)
	if not session.clientReady then
		return
	end
	local view = self.profiles:view(session.player.UserId)
	if view then
		self.gateway:sendProfile(session.player, view)
	end
end

function RunService.clientReady(self: Self, player: Player)
	local session = self.sessions[player]
	if session then
		session.clientReady = true
		sendProfile(self, session)
	end
end

function RunService.profileLoaded(self: Self, player: Player)
	local session = self.sessions[player]
	if session then
		sendProfile(self, session)
	end
end

-- Validates game state for a StartRun request (payload shape is checked by RemoteGateway).
function RunService.startRun(self: Self, player: Player, levelId: number): (boolean, string?)
	local session = self.sessions[player]
	if session == nil then
		return false, "unknown player"
	end
	local userId = player.UserId
	if not self.profiles:isLoaded(userId) then
		return false, "profile not loaded"
	end
	local level = self.levels:get(levelId)
	if level == nil then
		return false, "unknown level"
	end
	local highest = self.profiles:highestUnlockedLevel(userId) or 1
	if levelId > highest then
		return false, "level locked"
	end
	local run = session.run
	if run.phase ~= "Lobby" and run.phase ~= "Results" then
		return false, "run in progress"
	end
	local now = self.clock()
	if now - session.lastStartAt < self.config.START_RUN_COOLDOWN then
		return false, "cooldown"
	end

	if run.phase == "Results" then
		RunState.transition(run, "Lobby")
	end
	self.nextRunId += 1
	RunState.begin(run, self.nextRunId, level)
	session.lastStartAt = now
	self.gateway:sendSnapshot(player, RunState.snapshot(run))
	return true, nil
end

function RunService.steer(self: Self, player: Player, axis: number)
	local session = self.sessions[player]
	if session and (session.run.phase == "Loading" or session.run.phase == "Running") then
		RunState.setSteer(session.run, axis)
	end
end

local function finish(self: Self, session: Session, level: Level, result: Types.RunResult, reason: string?)
	local run = session.run
	if not RunState.finish(run, result, reason) then
		return
	end

	local payload: Protocol.RunEnded = {
		runId = run.runId,
		levelId = level.id,
		result = result,
		reason = run.failReason,
		finalCount = run.groupCount,
		earnedPoints = 0,
		stars = 0,
		bestScore = nil,
		newBest = false,
		unlockedLevel = nil,
	}
	if result == "Completed" and not run.rewarded then
		run.rewarded = true
		local reward = self.profiles:commitRun(session.player.UserId, level.id, run.groupCount, self.levels:count())
		if reward then
			payload.earnedPoints = reward.earnedPoints
			payload.bestScore = reward.bestScore
			payload.newBest = reward.newBest
			payload.unlockedLevel = reward.unlockedLevel
		end
		payload.stars = Rewards.starsFor(run.groupCount, self.levels:bestFinishCount(level.id), self.config)
	end

	RunState.transition(run, "Results")
	self.gateway:sendSnapshot(session.player, RunState.snapshot(run))
	self.gateway:sendRunEnded(session.player, payload)
	sendProfile(self, session)
end

local function step(self: Self, session: Session, dt: number)
	local run = session.run
	if run.phase == "Loading" then
		run.phaseTime += dt
		if run.phaseTime >= self.config.COUNTDOWN_SECONDS then
			RunState.transition(run, "Running")
			self.gateway:sendSnapshot(session.player, RunState.snapshot(run))
		end
		return
	elseif run.phase ~= "Running" then
		return
	end

	local level = assert(self.levels:get(run.levelId), "running level disappeared")
	local fromZ, toZ, fromX, toX = RunState.advance(run, dt, self.config, level.length)

	local hits: { Hit } = {}
	GateService.collect(level, run.consumed, fromZ, toZ, fromX, toX, hits)
	EncounterService.collect(level, run.consumed, fromZ, toZ, fromX, toX, hits)
	if #hits > 1 then
		Hits.sort(hits)
	end
	for _, hit in hits do
		local before = run.groupCount
		run.consumed[hit.id] = true
		RunState.applyCount(run, Hits.apply(hit, before, self.config.MAX_GROUP_SIZE), self.config.MAX_GROUP_SIZE)
		self.gateway:sendRunEvent(session.player, {
			runId = run.runId,
			kind = hit.kind,
			id = hit.id,
			before = before,
			after = run.groupCount,
		})
		if run.groupCount == 0 then
			finish(self, session, level, "Failed", "groupLost")
			return
		end
	end

	if run.progress >= level.length then
		if run.groupCount >= level.minFinishCount then
			finish(self, session, level, "Completed", nil)
		else
			finish(self, session, level, "Failed", "tooFew")
		end
	end
end

-- Advances all runs with a fixed simulation step and sends periodic snapshots.
function RunService.tick(self: Self, dt: number)
	local stepSize = self.config.SIMULATION_STEP
	self.accumulator = math.min(self.accumulator + dt, stepSize * self.config.MAX_STEPS_PER_FRAME)
	while self.accumulator >= stepSize do
		self.accumulator -= stepSize
		for _, session in self.sessions do
			step(self, session, stepSize)
		end
	end

	self.snapshotTimer += dt
	local interval = 1 / self.config.SNAPSHOT_RATE
	if self.snapshotTimer >= interval then
		self.snapshotTimer %= interval
		for player, session in self.sessions do
			if session.run.phase == "Loading" or session.run.phase == "Running" then
				self.gateway:sendSnapshot(player, RunState.snapshot(session.run))
			end
		end
	end
end

return RunService
