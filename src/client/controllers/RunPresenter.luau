--!strict
-- Client-side mirror of the authoritative run used for presentation only. Lateral movement is
-- predicted from local input so steering feels immediate; forward progress is extrapolated from
-- snapshots. The group count and all outcomes always come from the server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.config.GameConfig)
local RunState = require(ReplicatedStorage.Shared.domain.RunState)
local Types = require(ReplicatedStorage.Shared.domain.Types)
local Protocol = require(ReplicatedStorage.Shared.net.Protocol)

type Config = typeof(GameConfig)

export type RunPresenter = {
	runId: number,
	levelId: number,
	phase: Types.Phase,
	progress: number,
	laneX: number,
	groupCount: number,
	applySnapshot: (self: RunPresenter, snapshot: Protocol.Snapshot, now: number) -> boolean,
	applyEvent: (self: RunPresenter, event: Protocol.RunEvent) -> boolean,
	update: (self: RunPresenter, dt: number, axis: number, now: number, levelLength: number) -> (),
	countdown: (self: RunPresenter, now: number) -> number?,
	reset: (self: RunPresenter) -> (),
}

-- After the input has been idle this long the server position has caught up and the prediction
-- is pulled towards it.
local SETTLE_TIME = 0.3
local CORRECTION_RATE = 4
local HARD_CORRECTION = 6
local PROGRESS_CORRECTION_RATE = 5

local RunPresenter = {}
RunPresenter.__index = RunPresenter

type Self = typeof(setmetatable(
	{} :: {
		config: Config,
		runId: number,
		levelId: number,
		phase: Types.Phase,
		progress: number,
		laneX: number,
		groupCount: number,
		serverProgress: number,
		serverLaneX: number,
		serverPhaseTime: number,
		snapshotAt: number,
		idleTime: number,
	},
	RunPresenter
))

function RunPresenter.new(config: Config?): RunPresenter
	local self = setmetatable({
		config = config or GameConfig,
		runId = 0,
		levelId = 0,
		phase = "Lobby" :: Types.Phase,
		progress = 0,
		laneX = 0,
		groupCount = 0,
		serverProgress = 0,
		serverLaneX = 0,
		serverPhaseTime = 0,
		snapshotAt = 0,
		idleTime = 0,
	}, RunPresenter)
	return (self :: any) :: RunPresenter
end

function RunPresenter.reset(self: Self)
	self.phase = "Lobby"
end

-- Returns true when the snapshot starts a new run.
function RunPresenter.applySnapshot(self: Self, snapshot: Protocol.Snapshot, now: number): boolean
	if snapshot.runId < self.runId then
		return false
	end
	local isNew = snapshot.runId ~= self.runId
	self.runId = snapshot.runId
	self.levelId = snapshot.levelId
	self.phase = snapshot.phase
	self.groupCount = snapshot.groupCount
	self.serverProgress = snapshot.progress
	self.serverLaneX = snapshot.laneX
	self.serverPhaseTime = snapshot.phaseTime
	self.snapshotAt = now
	if isNew or snapshot.phase ~= "Running" then
		self.progress = snapshot.progress
		self.laneX = snapshot.laneX
	end
	return isNew
end

-- Returns true when the event belongs to the current run.
function RunPresenter.applyEvent(self: Self, event: Protocol.RunEvent): boolean
	if event.runId ~= self.runId then
		return false
	end
	self.groupCount = event.after
	return true
end

function RunPresenter.update(self: Self, dt: number, axis: number, now: number, levelLength: number)
	if self.phase ~= "Running" then
		return
	end
	local config = self.config

	local limit = RunState.laneLimit(config)
	self.laneX = math.clamp(self.laneX + axis * config.STEER_SPEED * dt, -limit, limit)
	if axis == 0 then
		self.idleTime += dt
	else
		self.idleTime = 0
	end
	-- While steering, the server lags behind by the network latency; only reconcile once idle.
	if self.idleTime >= SETTLE_TIME then
		local laneError = self.serverLaneX - self.laneX
		if math.abs(laneError) > HARD_CORRECTION then
			self.laneX = self.serverLaneX
		else
			self.laneX += laneError * math.min(1, CORRECTION_RATE * dt)
		end
	end

	local expected = math.min(self.serverProgress + config.FORWARD_SPEED * (now - self.snapshotAt), levelLength)
	self.progress = math.min(self.progress + config.FORWARD_SPEED * dt, levelLength)
	self.progress += (expected - self.progress) * math.min(1, PROGRESS_CORRECTION_RATE * dt)
end

-- Seconds left in the pre-run countdown, or nil outside Loading.
function RunPresenter.countdown(self: Self, now: number): number?
	if self.phase ~= "Loading" then
		return nil
	end
	local elapsed = self.serverPhaseTime + (now - self.snapshotAt)
	return math.max(self.config.COUNTDOWN_SECONDS - elapsed, 0)
end

return RunPresenter
