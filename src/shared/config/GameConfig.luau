--!strict
-- Central tuning values. The server uses them authoritatively; the client only for presentation
-- and prediction. Distances are in studs, durations in seconds.

export type RateLimit = {
	capacity: number,
	refillPerSecond: number,
}

-- Per-player token buckets for client -> server remotes.
local RATE_LIMITS: { [string]: RateLimit } = table.freeze({
	StartRun = table.freeze({ capacity = 3, refillPerSecond = 0.5 }),
	Steer = table.freeze({ capacity = 30, refillPerSecond = 20 }),
	ClientReady = table.freeze({ capacity = 3, refillPerSecond = 0.2 }),
})

local GameConfig = table.freeze({
	-- Group size is always an integer in 0..MAX_GROUP_SIZE. Zero ends the run.
	MAX_GROUP_SIZE = 99999,

	-- Movement
	FORWARD_SPEED = 26,
	STEER_SPEED = 20,
	TRACK_WIDTH = 24,
	-- Distance between the group centre and the track edge.
	EDGE_MARGIN = 1.5,

	-- Level layout rules (enforced by LevelService.validate)
	MIN_LEVEL_LENGTH = 150,
	MAX_LEVEL_LENGTH = 3000,
	START_ZONE = 40,
	FINISH_ZONE = 20,
	-- Minimum distance between two rows of gates/obstacles/enemies. Must leave enough time to
	-- steer across the full track (see LevelService.validateConfig).
	ROW_MIN_SPACING = 32,
	MAX_ADD_OPERAND = 1000,
	MAX_MULTIPLY_OPERAND = 10,

	-- Run timing
	COUNTDOWN_SECONDS = 3,
	SIMULATION_STEP = 1 / 30,
	MAX_STEPS_PER_FRAME = 8,
	SNAPSHOT_RATE = 10,

	-- Networking
	START_RUN_COOLDOWN = 1,
	RATE_LIMITS = RATE_LIMITS,
	-- Client-side throttle for Steer messages (stays well below the server rate limit).
	CLIENT_STEER_MIN_INTERVAL = 0.08,
	STEER_AXIS_STEP = 0.05,

	-- Rewards
	FIRST_CLEAR_BONUS = 50,
	MAX_POINTS_PER_RUN = 1000,
	MAX_TOTAL_POINTS = 2 ^ 31 - 1,
	-- Fraction of the best possible finish count needed for 2 and 3 stars.
	STAR_THRESHOLDS = table.freeze({ 0.5, 0.9 }),

	-- Persistence
	DATASTORE_NAME = "GateZillionProfiles_v1",
	PROFILE_KEY_PREFIX = "User_",
	AUTOSAVE_INTERVAL = 120,
	SESSION_LOCK_TIMEOUT = 1800,
	DATASTORE_MAX_RETRIES = 5,
	DATASTORE_RETRY_BASE = 1,
	-- Studio playtests use an in-memory store unless explicitly enabled; never point
	-- development sessions at production data.
	USE_DATASTORE_IN_STUDIO = false,

	-- Presentation
	MAX_VISIBLE_UNITS = 150,
	MAX_VISIBLE_ENEMIES = 60,
})

return GameConfig
