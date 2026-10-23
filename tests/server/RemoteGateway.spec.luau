local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local GameConfig = require(ReplicatedStorage.Shared.config.GameConfig)
local RemoteGateway = require(ServerScriptService.Server.services.RemoteGateway)

local function setup()
	local now = 0
	local calls = { startRun = {}, steer = {}, clientReady = 0 }
	local warnings = {}
	local gateway = RemoteGateway.new({
		levelCount = 10,
		clock = function()
			return now
		end,
		warn = function(message)
			table.insert(warnings, message)
		end,
	})
	gateway:bind({
		startRun = function(_player, levelId)
			table.insert(calls.startRun, levelId)
		end,
		steer = function(_player, axis)
			table.insert(calls.steer, axis)
		end,
		clientReady = function()
			calls.clientReady += 1
		end,
	})
	return {
		gateway = gateway,
		calls = calls,
		warnings = warnings,
		player = { UserId = 1, Name = "Player1" },
		advance = function(seconds)
			now += seconds
		end,
	}
end

return function()
	describe("RemoteGateway.dispatch", function()
		it("routes valid messages", function()
			local env = setup()
			expect(env.gateway:dispatch(env.player, "StartRun", 2)).to.equal(true)
			expect(env.gateway:dispatch(env.player, "Steer", 0.5, 1)).to.equal(true)
			expect(env.gateway:dispatch(env.player, "ClientReady")).to.equal(true)
			expect(env.calls.startRun[1]).to.equal(2)
			expect(env.calls.steer[1]).to.equal(0.5)
			expect(env.calls.clientReady).to.equal(1)
		end)

		it("rejects unknown remotes and wrong argument counts", function()
			local env = setup()
			local ok, reason = env.gateway:dispatch(env.player, "AwardPoints", 1000)
			expect(ok).to.equal(false)
			expect(reason).to.equal("unknown remote")
			ok, reason = env.gateway:dispatch(env.player, "StartRun", 1, "extra")
			expect(ok).to.equal(false)
			expect(reason).to.equal("wrong argument count")
			ok, reason = env.gateway:dispatch(env.player, "StartRun")
			expect(ok).to.equal(false)
			expect(reason).to.equal("wrong argument count")
		end)

		it("rejects malformed payloads", function()
			local env = setup()
			local invalid = {
				{ "StartRun", "1" },
				{ "StartRun", 0 },
				{ "StartRun", 99 },
				{ "StartRun", 0 / 0 },
				{ "Steer", 2, 1 },
				{ "Steer", 0 / 0, 1 },
				{ "Steer", 0.5, -1 },
				{ "Steer", { 1 }, 1 },
			}
			for _, case in invalid do
				env.advance(10)
				local ok = env.gateway:dispatch(env.player, table.unpack(case))
				expect(ok).to.equal(false)
			end
			expect(#env.calls.startRun).to.equal(0)
			expect(#env.calls.steer).to.equal(0)
		end)

		it("rejects stale or replayed steer sequences", function()
			local env = setup()
			expect(env.gateway:dispatch(env.player, "Steer", 1, 5)).to.equal(true)
			local ok, reason = env.gateway:dispatch(env.player, "Steer", -1, 5)
			expect(ok).to.equal(false)
			expect(reason).to.equal("stale sequence")
			expect((env.gateway:dispatch(env.player, "Steer", -1, 4))).to.equal(false)
			expect((env.gateway:dispatch(env.player, "Steer", -1, 6))).to.equal(true)
		end)

		it("rate limits spam per player and remote", function()
			local env = setup()
			local limit = GameConfig.RATE_LIMITS.Steer.capacity
			local accepted = 0
			for sequence = 1, limit * 3 do
				if env.gateway:dispatch(env.player, "Steer", 0, sequence) then
					accepted += 1
				end
			end
			expect(accepted).to.equal(limit)

			local other = { UserId = 2, Name = "Player2" }
			expect(env.gateway:dispatch(other, "Steer", 0, 1)).to.equal(true)

			local starts = 0
			for _ = 1, 20 do
				if env.gateway:dispatch(env.player, "StartRun", 1) then
					starts += 1
				end
			end
			expect(starts).to.equal(GameConfig.RATE_LIMITS.StartRun.capacity)
		end)

		it("throttles rejection logging", function()
			local env = setup()
			for _ = 1, 60 do
				env.gateway:dispatch(env.player, "StartRun", "bad")
			end
			expect(#env.warnings < 5).to.equal(true)
		end)

		it("forgets players that leave", function()
			local env = setup()
			env.gateway:dispatch(env.player, "Steer", 0, 50)
			env.gateway:removePlayer(env.player)
			expect(env.gateway:dispatch(env.player, "Steer", 0, 1)).to.equal(true)
		end)
	end)
end
