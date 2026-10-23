--!strict
-- Persistence and progression. Profiles are cached in memory while the player is in the server,
-- saved at checkpoints (run completion, autosave, departure, shutdown) and protected by a session
-- lock so two servers never write the same profile. Stored record:
--   { profile = ProfileData.Profile, session = { jobId = string, lockedAt = number }? }

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.config.GameConfig)
local ProfileData = require(ReplicatedStorage.Shared.domain.ProfileData)
local Rewards = require(ReplicatedStorage.Shared.domain.Rewards)
local Protocol = require(ReplicatedStorage.Shared.net.Protocol)
local ProfileStore = require(script.Parent.ProfileStore)

type Config = typeof(GameConfig)
type Profile = ProfileData.Profile

export type Options = {
	store: ProfileStore.Store,
	jobId: string,
	-- Wall-clock seconds (os.time) used for session lock timestamps.
	now: () -> number,
	wait: (seconds: number) -> (),
	spawn: (fn: () -> ()) -> (),
	config: Config?,
	warn: ((message: string) -> ())?,
}

export type ProfileService = {
	load: (self: ProfileService, userId: number) -> (boolean, string?),
	isLoaded: (self: ProfileService, userId: number) -> boolean,
	get: (self: ProfileService, userId: number) -> Profile?,
	highestUnlockedLevel: (self: ProfileService, userId: number) -> number?,
	view: (self: ProfileService, userId: number) -> Protocol.ProfileView?,
	commitRun: (
		self: ProfileService,
		userId: number,
		levelId: number,
		finalCount: number,
		levelCount: number
	) -> Rewards.RewardResult?,
	save: (self: ProfileService, userId: number) -> boolean,
	release: (self: ProfileService, userId: number) -> boolean,
	saveAll: (self: ProfileService) -> (),
	releaseAll: (self: ProfileService) -> (),
}

type Entry = {
	userId: number,
	key: string,
	profile: Profile,
	saving: boolean,
	-- Set when another server took over the session; this server must stop writing.
	lost: boolean,
}

type Loading = {
	cancelled: boolean,
}

local LOCK_WAIT_STEP = 0.1
local RELEASE_ALL_TIMEOUT_STEPS = 250

local ProfileService = {}
ProfileService.__index = ProfileService

type Self = typeof(setmetatable(
	{} :: {
		store: ProfileStore.Store,
		jobId: string,
		now: () -> number,
		wait: (seconds: number) -> (),
		spawn: (fn: () -> ()) -> (),
		config: Config,
		warn: (message: string) -> (),
		entries: { [number]: Entry },
		loading: { [number]: Loading },
		releasing: { [number]: boolean },
	},
	ProfileService
))

function ProfileService.new(options: Options): ProfileService
	local self = setmetatable({
		store = options.store,
		jobId = options.jobId,
		now = options.now,
		wait = options.wait,
		spawn = options.spawn,
		config = options.config or GameConfig,
		warn = options.warn or warn,
		entries = {},
		loading = {},
		releasing = {},
	}, ProfileService)
	return (self :: any) :: ProfileService
end

local function keyFor(self: Self, userId: number): string
	return `{self.config.PROFILE_KEY_PREFIX}{userId}`
end

local function backoff(self: Self, attempt: number)
	self.wait(self.config.DATASTORE_RETRY_BASE * 2 ^ (attempt - 1))
end

-- Loads and session-locks a profile. Retries DataStore errors and foreign locks with backoff;
-- the final attempt takes over a lock held by another server. Data that cannot be read safely
-- (corrupt or from a newer schema) is never overwritten.
function ProfileService.load(self: Self, userId: number): (boolean, string?)
	while self.releasing[userId] do
		self.wait(LOCK_WAIT_STEP)
	end
	if self.entries[userId] then
		return true, nil
	end
	if self.loading[userId] then
		return false, "already loading"
	end
	local loading: Loading = { cancelled = false }
	self.loading[userId] = loading

	local key = keyFor(self, userId)
	local maxAttempts = self.config.DATASTORE_MAX_RETRIES
	local lastError = "profile unavailable"

	for attempt = 1, maxAttempts do
		local force = attempt == maxAttempts
		local outcome: ("ok" | "locked" | "invalid")? = nil
		local loaded: Profile? = nil
		local invalidReason: string? = nil

		local ok, err = self.store:update(key, function(old: any): any
			-- UpdateAsync may run the transform more than once; reset all outputs each time.
			outcome, loaded, invalidReason = nil, nil, nil
			if old ~= nil and type(old) ~= "table" then
				outcome, invalidReason = "invalid", "corrupt profile record"
				return nil
			end
			local profile, reason = ProfileData.fromStored(if old then old.profile else nil)
			if profile == nil then
				outcome, invalidReason = "invalid", reason
				return nil
			end
			local now = self.now()
			local session = if old then old.session else nil
			if
				not force
				and type(session) == "table"
				and session.jobId ~= self.jobId
				and type(session.lockedAt) == "number"
				and now - session.lockedAt < self.config.SESSION_LOCK_TIMEOUT
			then
				outcome = "locked"
				return nil
			end
			outcome, loaded = "ok", profile
			return {
				profile = profile,
				session = { jobId = self.jobId, lockedAt = now },
			}
		end)

		if ok and outcome == "ok" and loaded then
			self.loading[userId] = nil
			self.entries[userId] = {
				userId = userId,
				key = key,
				profile = loaded,
				saving = false,
				lost = false,
			}
			if loading.cancelled then
				self:release(userId)
				return false, "player left during load"
			end
			return true, nil
		elseif ok and outcome == "invalid" then
			self.loading[userId] = nil
			self.warn(`[ProfileService] refusing to load {key}: {invalidReason}`)
			return false, invalidReason
		elseif not ok then
			lastError = tostring(err)
			self.warn(`[ProfileService] load {key} attempt {attempt} failed: {lastError}`)
		end

		if loading.cancelled then
			self.loading[userId] = nil
			return false, "player left during load"
		end
		if attempt < maxAttempts then
			backoff(self, attempt)
		end
	end

	self.loading[userId] = nil
	return false, lastError
end

-- Writes the cached profile if this server still owns the session. Releasing clears the lock.
local function write(self: Self, entry: Entry, releasing: boolean): boolean
	if entry.lost then
		return false
	end
	while entry.saving do
		self.wait(LOCK_WAIT_STEP)
	end
	entry.saving = true

	local saved = false
	for attempt = 1, self.config.DATASTORE_MAX_RETRIES do
		local owned = false
		local ok, err = self.store:update(entry.key, function(old: any): any
			owned = type(old) == "table" and type(old.session) == "table" and old.session.jobId == self.jobId
			if not owned then
				return nil
			end
			return {
				profile = ProfileData.deepCopy(entry.profile),
				session = if releasing then nil else { jobId = self.jobId, lockedAt = self.now() },
			}
		end)
		if ok then
			if owned then
				saved = true
			else
				entry.lost = true
				self.warn(`[ProfileService] session for {entry.key} was taken over; not saving`)
			end
			break
		end
		self.warn(`[ProfileService] save {entry.key} attempt {attempt} failed: {tostring(err)}`)
		if attempt < self.config.DATASTORE_MAX_RETRIES then
			backoff(self, attempt)
		end
	end

	entry.saving = false
	return saved
end

function ProfileService.isLoaded(self: Self, userId: number): boolean
	return self.entries[userId] ~= nil
end

function ProfileService.get(self: Self, userId: number): Profile?
	local entry = self.entries[userId]
	return if entry then entry.profile else nil
end

function ProfileService.highestUnlockedLevel(self: Self, userId: number): number?
	local entry = self.entries[userId]
	return if entry then entry.profile.highestUnlockedLevel else nil
end

function ProfileService.view(self: Self, userId: number): Protocol.ProfileView?
	local entry = self.entries[userId]
	if entry == nil then
		return nil
	end
	local profile = entry.profile
	return {
		highestUnlockedLevel = profile.highestUnlockedLevel,
		earnedPoints = profile.earnedPoints,
		bestScores = table.clone(profile.bestScores),
		soundEnabled = profile.settings.soundEnabled,
	}
end

-- Applies the rewards of a completed run and saves in the background. RunService guarantees
-- this is called at most once per run.
function ProfileService.commitRun(
	self: Self,
	userId: number,
	levelId: number,
	finalCount: number,
	levelCount: number
): Rewards.RewardResult?
	local entry = self.entries[userId]
	if entry == nil or entry.lost then
		return nil
	end
	local result = Rewards.applyCompletion(entry.profile, levelId, finalCount, levelCount, self.config)
	self.spawn(function()
		write(self, entry, false)
	end)
	return result
end

function ProfileService.save(self: Self, userId: number): boolean
	local entry = self.entries[userId]
	return entry ~= nil and write(self, entry, false)
end

-- Saves, clears the session lock and drops the cached profile.
function ProfileService.release(self: Self, userId: number): boolean
	local loading = self.loading[userId]
	if loading then
		loading.cancelled = true
		return true
	end
	local entry = self.entries[userId]
	if entry == nil then
		return true
	end
	self.releasing[userId] = true
	local ok = write(self, entry, true)
	self.entries[userId] = nil
	self.releasing[userId] = nil
	return ok
end

function ProfileService.saveAll(self: Self)
	for userId in self.entries do
		self.spawn(function()
			self:save(userId)
		end)
	end
end

-- Used from BindToClose: releases every profile in parallel and waits (bounded) for completion.
function ProfileService.releaseAll(self: Self)
	local pending = 0
	for userId in self.entries do
		pending += 1
		self.spawn(function()
			self:release(userId)
			pending -= 1
		end)
	end
	local steps = 0
	while pending > 0 and steps < RELEASE_ALL_TIMEOUT_STEPS do
		self.wait(LOCK_WAIT_STEP)
		steps += 1
	end
end

return ProfileService
