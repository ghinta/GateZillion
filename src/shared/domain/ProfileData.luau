--!strict
-- Versioned player profile: defaults, migrations and repair of stored data. No Roblox APIs.
-- bestScores uses string keys ("1", "2", ...) so the table always serialises as a JSON object.

export type Settings = {
	soundEnabled: boolean,
}

export type Profile = {
	schemaVersion: number,
	highestUnlockedLevel: number,
	bestScores: { [string]: number },
	earnedPoints: number,
	unlockedCosmetics: { string },
	settings: Settings,
}

-- Migrations[n] upgrades a raw table from schema n to n + 1.
export type Migrations = { [number]: (raw: { [any]: any }) -> { [any]: any } }

local ProfileData = {}

ProfileData.CURRENT_VERSION = 1

ProfileData.MIGRATIONS = table.freeze({}) :: Migrations

local function isNonNegativeInteger(value: unknown): boolean
	return type(value) == "number"
		and value == value
		and value >= 0
		and value == math.floor(value)
		and value < math.huge
end

function ProfileData.default(): Profile
	return {
		schemaVersion = ProfileData.CURRENT_VERSION,
		highestUnlockedLevel = 1,
		bestScores = {},
		earnedPoints = 0,
		unlockedCosmetics = {},
		settings = { soundEnabled = true },
	}
end

function ProfileData.deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, child in value :: any do
		copy[ProfileData.deepCopy(key)] = ProfileData.deepCopy(child)
	end
	return (copy :: any) :: T
end

-- Repairs a table that claims to be the current schema: keeps valid fields, replaces invalid
-- ones with defaults and drops unknown keys.
function ProfileData.sanitize(raw: { [any]: any }): Profile
	local profile = ProfileData.default()

	if isNonNegativeInteger(raw.highestUnlockedLevel) and raw.highestUnlockedLevel >= 1 then
		profile.highestUnlockedLevel = raw.highestUnlockedLevel
	end
	if isNonNegativeInteger(raw.earnedPoints) then
		profile.earnedPoints = raw.earnedPoints
	end
	if type(raw.bestScores) == "table" then
		for key, score in raw.bestScores do
			local levelId = tonumber(key)
			if levelId and isNonNegativeInteger(levelId) and levelId >= 1 and isNonNegativeInteger(score) then
				profile.bestScores[tostring(levelId)] = score
			end
		end
	end
	if type(raw.unlockedCosmetics) == "table" then
		for _, cosmeticId in ipairs(raw.unlockedCosmetics) do
			if type(cosmeticId) == "string" then
				table.insert(profile.unlockedCosmetics, cosmeticId)
			end
		end
	end
	if type(raw.settings) == "table" and type(raw.settings.soundEnabled) == "boolean" then
		profile.settings.soundEnabled = raw.settings.soundEnabled
	end

	return profile
end

-- Converts stored data into a current-schema profile.
-- Returns nil and a reason when the data cannot be used safely (it must then not be overwritten).
function ProfileData.fromStored(raw: unknown, migrations: Migrations?, targetVersion: number?): (Profile?, string?)
	local steps = migrations or ProfileData.MIGRATIONS
	local target = targetVersion or ProfileData.CURRENT_VERSION

	if raw == nil then
		return ProfileData.default(), nil
	end
	if type(raw) ~= "table" then
		return nil, "corrupt profile"
	end

	local data = ProfileData.deepCopy(raw) :: { [any]: any }
	local version = data.schemaVersion
	if type(version) ~= "number" or not isNonNegativeInteger(version) then
		-- Unknown version: repair in place rather than lose progress.
		version = target
	end
	if version > target then
		return nil, `profile schema {version} is newer than supported schema {target}`
	end

	while version < target do
		local migrate = steps[version]
		if migrate == nil then
			return nil, `missing profile migration from schema {version}`
		end
		data = migrate(data)
		version += 1
	end

	return ProfileData.sanitize(data), nil
end

return ProfileData
