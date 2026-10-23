--!strict
-- Reward and progression rules applied by the server once per legitimately completed run.

local GateMath = require(script.Parent.GateMath)
local ProfileData = require(script.Parent.ProfileData)

type Profile = ProfileData.Profile

export type RewardConfig = {
	FIRST_CLEAR_BONUS: number,
	MAX_POINTS_PER_RUN: number,
	MAX_TOTAL_POINTS: number,
	STAR_THRESHOLDS: { number },
}

export type RewardResult = {
	earnedPoints: number,
	firstClear: boolean,
	newBest: boolean,
	bestScore: number,
	unlockedLevel: number?,
}

local Rewards = {}

function Rewards.pointsFor(finalCount: number, firstClear: boolean, config: RewardConfig): number
	local points = math.min(finalCount, config.MAX_POINTS_PER_RUN)
	if firstClear then
		points += config.FIRST_CLEAR_BONUS
	end
	return points
end

-- 1 to 3 stars, relative to the best finish count the level allows.
function Rewards.starsFor(finalCount: number, bestPossible: number, config: RewardConfig): number
	if finalCount <= 0 then
		return 0
	end
	if bestPossible <= 0 then
		return 1
	end
	local ratio = finalCount / bestPossible
	local stars = 1
	for _, threshold in config.STAR_THRESHOLDS do
		if ratio >= threshold then
			stars += 1
		end
	end
	return stars
end

-- Mutates the profile with the result of a completed run and reports what changed.
function Rewards.applyCompletion(
	profile: Profile,
	levelId: number,
	finalCount: number,
	levelCount: number,
	config: RewardConfig
): RewardResult
	assert(GateMath.isInteger(levelId) and levelId >= 1 and levelId <= levelCount, "invalid level id")
	assert(levelId <= profile.highestUnlockedLevel, "level is locked")
	assert(GateMath.isInteger(finalCount) and finalCount >= 1, "completed runs need a positive group")

	local key = tostring(levelId)
	local previousBest = profile.bestScores[key]
	local firstClear = previousBest == nil
	local newBest = previousBest == nil or finalCount > previousBest

	local earnedPoints = Rewards.pointsFor(finalCount, firstClear, config)
	profile.earnedPoints = math.min(profile.earnedPoints + earnedPoints, config.MAX_TOTAL_POINTS)
	if newBest then
		profile.bestScores[key] = finalCount
	end

	local unlockedLevel: number? = nil
	if levelId == profile.highestUnlockedLevel and levelId < levelCount then
		profile.highestUnlockedLevel = levelId + 1
		unlockedLevel = levelId + 1
	end

	return {
		earnedPoints = earnedPoints,
		firstClear = firstClear,
		newBest = newBest,
		bestScore = profile.bestScores[key],
		unlockedLevel = unlockedLevel,
	}
end

return Rewards
