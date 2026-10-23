--!strict
-- Storage backends for ProfileService. Both expose `update(key, transform)`, mirroring
-- DataStore UpdateAsync: the transform returns the new value, or nil to cancel the write.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProfileData = require(ReplicatedStorage.Shared.domain.ProfileData)

export type Store = {
	update: (self: Store, key: string, transform: (old: any) -> any) -> (boolean, any),
}

export type MemoryStore = Store & {
	data: { [string]: any },
	-- Number of upcoming update calls that fail, for persistence failure tests.
	failures: number,
	calls: number,
}

local ProfileStore = {}

function ProfileStore.fromDataStore(dataStore: GlobalDataStore): Store
	local store = {}
	function store.update(_self: Store, key: string, transform: (old: any) -> any): (boolean, any)
		return pcall(function()
			return dataStore:UpdateAsync(key, function(old: any)
				return transform(old)
			end)
		end)
	end
	return store :: Store
end

-- In-memory store for Studio playtests and tests. Values are deep-copied on the way in and out
-- to behave like serialised DataStore entries.
function ProfileStore.memory(): MemoryStore
	local store = {
		data = {},
		failures = 0,
		calls = 0,
	}
	function store.update(self: MemoryStore, key: string, transform: (old: any) -> any): (boolean, any)
		self.calls += 1
		if self.failures > 0 then
			self.failures -= 1
			return false, "injected DataStore failure"
		end
		local ok, result = pcall(transform, ProfileData.deepCopy(self.data[key]))
		if not ok then
			return false, result
		end
		if result ~= nil then
			self.data[key] = ProfileData.deepCopy(result)
		end
		return true, ProfileData.deepCopy(result)
	end
	return (store :: any) :: MemoryStore
end

return ProfileStore
