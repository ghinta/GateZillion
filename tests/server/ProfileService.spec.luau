local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local GameConfig = require(ReplicatedStorage.Shared.config.GameConfig)
local ProfileData = require(ReplicatedStorage.Shared.domain.ProfileData)
local services = ServerScriptService.Server.services
local ProfileService = require(services.ProfileService)
local ProfileStore = require(services.ProfileStore)

local USER = 42
local KEY = "User_42"

local function newService(store, jobId, clock)
	local waits = {}
	local service = ProfileService.new({
		store = store,
		jobId = jobId,
		now = function()
			return clock.now
		end,
		wait = function(seconds)
			table.insert(waits, seconds)
			clock.now += seconds
		end,
		spawn = function(fn)
			fn()
		end,
		warn = function() end,
	})
	return service, waits
end

return function()
	describe("ProfileService", function()
		it("creates, locks and saves a new profile", function()
			local clock = { now = 1000 }
			local store = ProfileStore.memory()
			local service = newService(store, "server-a", clock)
			expect(service:load(USER)).to.equal(true)
			expect(service:isLoaded(USER)).to.equal(true)
			local record = store.data[KEY]
			expect(record.session.jobId).to.equal("server-a")
			expect(record.profile.highestUnlockedLevel).to.equal(1)

			service:commitRun(USER, 1, 25, 10)
			expect(store.data[KEY].profile.highestUnlockedLevel).to.equal(2)
			expect(store.data[KEY].profile.bestScores["1"]).to.equal(25)
		end)

		it("releases the session lock and keeps the data on leave", function()
			local clock = { now = 1000 }
			local store = ProfileStore.memory()
			local service = newService(store, "server-a", clock)
			service:load(USER)
			service:commitRun(USER, 1, 25, 10)
			expect(service:release(USER)).to.equal(true)
			expect(service:isLoaded(USER)).to.equal(false)
			expect(store.data[KEY].session).to.equal(nil)
			expect(store.data[KEY].profile.earnedPoints).to.equal(25 + GameConfig.FIRST_CLEAR_BONUS)
		end)

		it("waits for a foreign lock and finally takes it over", function()
			local clock = { now = 1000 }
			local store = ProfileStore.memory()
			local serverA = newService(store, "server-a", clock)
			serverA:load(USER)
			serverA:commitRun(USER, 1, 10, 10)

			local serverB, waits = newService(store, "server-b", clock)
			expect(serverB:load(USER)).to.equal(true)
			expect(#waits).to.equal(GameConfig.DATASTORE_MAX_RETRIES - 1)
			expect(store.data[KEY].session.jobId).to.equal("server-b")
			-- B sees A's last saved progress.
			expect(serverB:get(USER).highestUnlockedLevel).to.equal(2)

			-- A lost the session: its later writes are refused and do not clobber B.
			serverA:get(USER).earnedPoints = 999999
			expect(serverA:save(USER)).to.equal(false)
			expect(store.data[KEY].profile.earnedPoints).to.equal(10 + GameConfig.FIRST_CLEAR_BONUS)
			expect(serverA:commitRun(USER, 2, 10, 10)).to.equal(nil)
		end)

		it("takes over a stale lock immediately", function()
			local clock = { now = 1000 }
			local store = ProfileStore.memory()
			store.data[KEY] = {
				profile = ProfileData.default(),
				session = { jobId = "crashed-server", lockedAt = 1000 - GameConfig.SESSION_LOCK_TIMEOUT - 1 },
			}
			local service, waits = newService(store, "server-b", clock)
			expect(service:load(USER)).to.equal(true)
			expect(#waits).to.equal(0)
		end)

		it("retries DataStore failures with exponential backoff", function()
			local clock = { now = 1000 }
			local store = ProfileStore.memory()
			store.failures = 2
			local service, waits = newService(store, "server-a", clock)
			expect(service:load(USER)).to.equal(true)
			expect(#waits).to.equal(2)
			expect(waits[1]).to.equal(GameConfig.DATASTORE_RETRY_BASE)
			expect(waits[2]).to.equal(GameConfig.DATASTORE_RETRY_BASE * 2)
		end)

		it("gives up after the retry budget", function()
			local clock = { now = 1000 }
			local store = ProfileStore.memory()
			store.failures = 100
			local service = newService(store, "server-a", clock)
			local ok, reason = service:load(USER)
			expect(ok).to.equal(false)
			expect(reason).to.be.ok()
			expect(store.calls).to.equal(GameConfig.DATASTORE_MAX_RETRIES)
			expect(service:isLoaded(USER)).to.equal(false)
		end)

		it("keeps the cached profile when a save fails and retries", function()
			local clock = { now = 1000 }
			local store = ProfileStore.memory()
			local service = newService(store, "server-a", clock)
			service:load(USER)
			service:get(USER).earnedPoints = 77
			store.failures = 1
			expect(service:save(USER)).to.equal(true)
			expect(store.data[KEY].profile.earnedPoints).to.equal(77)
		end)

		it("refuses to load or overwrite data from a newer schema", function()
			local clock = { now = 1000 }
			local store = ProfileStore.memory()
			local future = { schemaVersion = ProfileData.CURRENT_VERSION + 1, highestUnlockedLevel = 9 }
			store.data[KEY] = { profile = future }
			local service = newService(store, "server-a", clock)
			local ok = service:load(USER)
			expect(ok).to.equal(false)
			expect(store.data[KEY].profile.schemaVersion).to.equal(ProfileData.CURRENT_VERSION + 1)
			expect(store.data[KEY].session).to.equal(nil)
		end)

		it("releases a profile whose player left during loading", function()
			local clock = { now = 1000 }
			local store = ProfileStore.memory()
			local service
			local originalUpdate = store.update
			store.update = function(self, key, transform)
				-- The player leaves while the DataStore request is in flight.
				service:release(USER)
				store.update = originalUpdate
				return originalUpdate(self, key, transform)
			end
			service = newService(store, "server-a", clock)
			local ok = service:load(USER)
			expect(ok).to.equal(false)
			expect(service:isLoaded(USER)).to.equal(false)
			expect(store.data[KEY].session).to.equal(nil)
		end)

		it("exposes a client-safe view", function()
			local clock = { now = 1000 }
			local store = ProfileStore.memory()
			local service = newService(store, "server-a", clock)
			service:load(USER)
			service:commitRun(USER, 1, 12, 10)
			local view = service:view(USER)
			expect(view.highestUnlockedLevel).to.equal(2)
			expect(view.bestScores["1"]).to.equal(12)
			view.bestScores["1"] = 1
			expect(service:get(USER).bestScores["1"]).to.equal(12)
		end)

		it("releases every profile on shutdown", function()
			local clock = { now = 1000 }
			local store = ProfileStore.memory()
			local service = newService(store, "server-a", clock)
			service:load(1)
			service:load(2)
			service:releaseAll()
			expect(service:isLoaded(1)).to.equal(false)
			expect(service:isLoaded(2)).to.equal(false)
			expect(store.data["User_1"].session).to.equal(nil)
			expect(store.data["User_2"].session).to.equal(nil)
		end)
	end)
end
