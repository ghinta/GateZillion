local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local GameConfig = require(ReplicatedStorage.Shared.config.GameConfig)
local RunPresenter = require(StarterPlayer.StarterPlayerScripts.Client.controllers.RunPresenter)

local function snapshot(fields)
	local base = {
		runId = 1,
		levelId = 1,
		phase = "Running",
		phaseTime = 0,
		progress = 0,
		laneX = 0,
		groupCount = 5,
	}
	for key, value in fields do
		base[key] = value
	end
	return base
end

return function()
	describe("RunPresenter", function()
		it("detects new runs and ignores stale ones", function()
			local presenter = RunPresenter.new(GameConfig)
			expect(presenter:applySnapshot(snapshot({ runId = 2, phase = "Loading" }), 0)).to.equal(true)
			expect(presenter:applySnapshot(snapshot({ runId = 2, phase = "Running" }), 0.1)).to.equal(false)
			expect(presenter:applySnapshot(snapshot({ runId = 1, groupCount = 999 }), 0.2)).to.equal(false)
			expect(presenter.groupCount).to.equal(5)
		end)

		it("only takes group counts from the server", function()
			local presenter = RunPresenter.new(GameConfig)
			presenter:applySnapshot(snapshot({}), 0)
			expect(presenter:applyEvent({ runId = 1, kind = "gate", id = "a", before = 5, after = 15 })).to.equal(true)
			expect(presenter.groupCount).to.equal(15)
			expect(presenter:applyEvent({ runId = 9, kind = "gate", id = "b", before = 15, after = 1 })).to.equal(false)
			expect(presenter.groupCount).to.equal(15)
		end)

		it("predicts steering immediately and converges to the server once idle", function()
			local presenter = RunPresenter.new(GameConfig)
			presenter:applySnapshot(snapshot({}), 0)
			local now = 0
			for _ = 1, 15 do
				now += 1 / 60
				presenter:update(1 / 60, 1, now, 400)
			end
			expect(presenter.laneX).to.be.near(GameConfig.STEER_SPEED * 0.25, 0.01)

			-- The server reports where the group really is; prediction converges after settling.
			presenter:applySnapshot(snapshot({ laneX = 4, progress = presenter.progress }), now)
			for _ = 1, 120 do
				now += 1 / 60
				presenter:update(1 / 60, 0, now, 400)
			end
			expect(presenter.laneX).to.be.near(4, 0.05)
		end)

		it("extrapolates progress between snapshots and never passes the finish", function()
			local presenter = RunPresenter.new(GameConfig)
			presenter:applySnapshot(snapshot({ progress = 100 }), 0)
			local now = 0
			for _ = 1, 30 do
				now += 1 / 60
				presenter:update(1 / 60, 0, now, 400)
			end
			expect(presenter.progress).to.be.near(100 + GameConfig.FORWARD_SPEED * 0.5, 0.5)
			for _ = 1, 2000 do
				now += 1 / 60
				presenter:update(1 / 60, 0, now, 400)
			end
			expect(presenter.progress).to.be.near(400, 1e-6)
		end)

		it("reports the countdown during Loading", function()
			local presenter = RunPresenter.new(GameConfig)
			presenter:applySnapshot(snapshot({ phase = "Loading", phaseTime = 1 }), 10)
			expect(presenter:countdown(10.5)).to.be.near(GameConfig.COUNTDOWN_SECONDS - 1.5)
			presenter:applySnapshot(snapshot({ phase = "Running" }), 11)
			expect(presenter:countdown(11)).to.equal(nil)
		end)
	end)
end
