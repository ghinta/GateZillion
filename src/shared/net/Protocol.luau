--!strict
-- Remote names, payload types and payload validation. Every client payload is untrusted.
-- There is deliberately no client-callable SetGroupCount, AwardPoints or CompleteLevel.

local RunState = require(script.Parent.Parent.domain.RunState)
local Types = require(script.Parent.Parent.domain.Types)

export type Snapshot = RunState.Snapshot

export type RunEvent = {
	runId: number,
	kind: Types.HitKind,
	id: string,
	before: number,
	after: number,
}

export type RunEnded = {
	runId: number,
	levelId: number,
	result: Types.RunResult,
	reason: string?,
	finalCount: number,
	earnedPoints: number,
	stars: number,
	bestScore: number?,
	newBest: boolean,
	unlockedLevel: number?,
}

export type ProfileView = {
	highestUnlockedLevel: number,
	earnedPoints: number,
	bestScores: { [string]: number },
	soundEnabled: boolean,
}

local Protocol = {}

Protocol.FOLDER_NAME = "Remotes"

-- Client -> server. Payloads: StartRun(levelId), Steer(axis, sequence), ClientReady().
Protocol.ClientToServer = table.freeze({
	StartRun = "StartRun",
	Steer = "Steer",
	ClientReady = "ClientReady",
})

-- Server -> client. Payloads: RunSnapshot(Snapshot), RunEvent(RunEvent), RunEnded(RunEnded),
-- ProfileUpdated(ProfileView).
Protocol.ServerToClient = table.freeze({
	RunSnapshot = "RunSnapshot",
	RunEvent = "RunEvent",
	RunEnded = "RunEnded",
	ProfileUpdated = "ProfileUpdated",
})

-- Iterable name lists (the tables above are for typed field access).
Protocol.CLIENT_TO_SERVER_NAMES = table.freeze({ "StartRun", "Steer", "ClientReady" }) :: { string }
Protocol.SERVER_TO_CLIENT_NAMES =
	table.freeze({ "RunSnapshot", "RunEvent", "RunEnded", "ProfileUpdated" }) :: { string }

Protocol.MAX_SEQUENCE = 2 ^ 31 - 1

function Protocol.isFiniteNumber(value: unknown): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

function Protocol.isInteger(value: unknown): boolean
	return Protocol.isFiniteNumber(value) and value == math.floor(value :: number)
end

-- Returns the level id when the payload is a plausible level id, otherwise nil.
function Protocol.parseStartRun(levelId: unknown, levelCount: number): number?
	if not Protocol.isInteger(levelId) then
		return nil
	end
	local id = levelId :: number
	if id < 1 or id > levelCount then
		return nil
	end
	return id
end

-- Returns (axis, sequence) when both are valid, otherwise nil.
function Protocol.parseSteer(axis: unknown, sequence: unknown): (number?, number?)
	if not Protocol.isFiniteNumber(axis) or not Protocol.isInteger(sequence) then
		return nil, nil
	end
	local a, s = axis :: number, sequence :: number
	if a < -1 or a > 1 or s < 1 or s > Protocol.MAX_SEQUENCE then
		return nil, nil
	end
	return a, s
end

-- Rounds an input axis to a fixed step so tiny analog changes do not produce extra messages.
function Protocol.quantizeAxis(axis: number, step: number): number
	local clamped = math.clamp(axis, -1, 1)
	return math.clamp(math.round(clamped / step) * step, -1, 1)
end

return Protocol
