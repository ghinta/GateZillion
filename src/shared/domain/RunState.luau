--!strict
-- Canonical run record and state machine:
--   Lobby -> Loading -> Running -> Completed|Failed -> Results -> Lobby
-- Pure module: the server owns the authoritative instance, the client only mirrors snapshots.

local GateMath = require(script.Parent.GateMath)
local Types = require(script.Parent.Types)

type Phase = Types.Phase
type RunResult = Types.RunResult
type Level = Types.Level

export type Run = {
	runId: number,
	levelId: number,
	phase: Phase,
	-- Seconds spent in the current phase.
	phaseTime: number,
	progress: number,
	laneX: number,
	steerAxis: number,
	groupCount: number,
	-- Level element ids that already took effect (first validated crossing only).
	consumed: { [string]: boolean },
	result: RunResult?,
	failReason: string?,
	rewarded: boolean,
}

export type Snapshot = {
	runId: number,
	levelId: number,
	phase: Phase,
	phaseTime: number,
	progress: number,
	laneX: number,
	groupCount: number,
}

type MovementConfig = {
	FORWARD_SPEED: number,
	STEER_SPEED: number,
	TRACK_WIDTH: number,
	EDGE_MARGIN: number,
}

local RunState = {}

RunState.TRANSITIONS = table.freeze({
	Lobby = table.freeze({ Loading = true }),
	Loading = table.freeze({ Running = true, Lobby = true }),
	Running = table.freeze({ Completed = true, Failed = true }),
	Completed = table.freeze({ Results = true }),
	Failed = table.freeze({ Results = true }),
	Results = table.freeze({ Lobby = true }),
}) :: { [Phase]: { [Phase]: boolean } }

function RunState.new(): Run
	return {
		runId = 0,
		levelId = 0,
		phase = "Lobby",
		phaseTime = 0,
		progress = 0,
		laneX = 0,
		steerAxis = 0,
		groupCount = 0,
		consumed = {},
		result = nil,
		failReason = nil,
		rewarded = false,
	}
end

function RunState.canTransition(from: Phase, to: Phase): boolean
	local allowed = RunState.TRANSITIONS[from]
	return allowed ~= nil and allowed[to] == true
end

function RunState.transition(run: Run, to: Phase)
	if not RunState.canTransition(run.phase, to) then
		error(`invalid run transition {run.phase} -> {to}`)
	end
	run.phase = to
	run.phaseTime = 0
end

-- Resets the record for a new attempt and enters Loading. Only valid from Lobby.
function RunState.begin(run: Run, runId: number, level: Level)
	RunState.transition(run, "Loading")
	run.runId = runId
	run.levelId = level.id
	run.progress = 0
	run.laneX = 0
	run.steerAxis = 0
	run.groupCount = level.startCount
	run.consumed = {}
	run.result = nil
	run.failReason = nil
	run.rewarded = false
end

-- Ends a running attempt. Returns false when the run is not running (e.g. already ended).
function RunState.finish(run: Run, result: RunResult, reason: string?): boolean
	if run.phase ~= "Running" then
		return false
	end
	RunState.transition(run, result)
	run.result = result
	run.failReason = if result == "Failed" then reason else nil
	return true
end

function RunState.setSteer(run: Run, axis: number)
	if axis ~= axis then
		return
	end
	run.steerAxis = math.clamp(axis, -1, 1)
end

function RunState.laneLimit(config: MovementConfig): number
	return config.TRACK_WIDTH / 2 - config.EDGE_MARGIN
end

-- Integrates forward and lateral movement for one step. Returns the travelled segment
-- (fromZ, toZ, fromX, toX) for crossing detection.
function RunState.advance(
	run: Run,
	dt: number,
	config: MovementConfig,
	levelLength: number
): (number, number, number, number)
	assert(run.phase == "Running", "advance requires a running run")
	local fromZ, fromX = run.progress, run.laneX
	local limit = RunState.laneLimit(config)
	run.laneX = math.clamp(run.laneX + run.steerAxis * config.STEER_SPEED * dt, -limit, limit)
	run.progress = math.min(run.progress + config.FORWARD_SPEED * dt, levelLength)
	run.phaseTime += dt
	return fromZ, run.progress, fromX, run.laneX
end

function RunState.applyCount(run: Run, count: number, maxGroupSize: number)
	run.groupCount = GateMath.clamp(count, maxGroupSize)
end

function RunState.snapshot(run: Run): Snapshot
	return {
		runId = run.runId,
		levelId = run.levelId,
		phase = run.phase,
		phaseTime = run.phaseTime,
		progress = run.progress,
		laneX = run.laneX,
		groupCount = run.groupCount,
	}
end

return RunState
