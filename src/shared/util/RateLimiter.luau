--!strict
-- Token-bucket rate limiter keyed by caller (usually a Player). The clock is injected for tests.

export type RateLimiter = {
	allow: (self: RateLimiter, key: any) -> boolean,
	remove: (self: RateLimiter, key: any) -> (),
}

type Bucket = {
	tokens: number,
	updatedAt: number,
}

local RateLimiter = {}
RateLimiter.__index = RateLimiter

type Self = typeof(setmetatable(
	{} :: {
		capacity: number,
		refillPerSecond: number,
		clock: () -> number,
		buckets: { [any]: Bucket },
	},
	RateLimiter
))

function RateLimiter.new(capacity: number, refillPerSecond: number, clock: () -> number): RateLimiter
	assert(capacity >= 1, "capacity must be at least 1")
	assert(refillPerSecond > 0, "refill rate must be positive")
	local self = setmetatable({
		capacity = capacity,
		refillPerSecond = refillPerSecond,
		clock = clock,
		buckets = {},
	}, RateLimiter)
	return (self :: any) :: RateLimiter
end

function RateLimiter.allow(self: Self, key: any): boolean
	local now = self.clock()
	local bucket = self.buckets[key]
	if bucket == nil then
		bucket = { tokens = self.capacity, updatedAt = now }
		self.buckets[key] = bucket
	else
		local elapsed = math.max(now - bucket.updatedAt, 0)
		bucket.tokens = math.min(self.capacity, bucket.tokens + elapsed * self.refillPerSecond)
		bucket.updatedAt = now
	end
	if bucket.tokens >= 1 then
		bucket.tokens -= 1
		return true
	end
	return false
end

function RateLimiter.remove(self: Self, key: any)
	self.buckets[key] = nil
end

return RateLimiter
