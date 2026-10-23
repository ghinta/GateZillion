local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Protocol = require(ReplicatedStorage.Shared.net.Protocol)
local RateLimiter = require(ReplicatedStorage.Shared.util.RateLimiter)

return function()
	describe("Protocol validation", function()
		it("accepts valid level ids only", function()
			expect(Protocol.parseStartRun(3, 10)).to.equal(3)
			expect(Protocol.parseStartRun(0, 10)).to.equal(nil)
			expect(Protocol.parseStartRun(11, 10)).to.equal(nil)
			expect(Protocol.parseStartRun(2.5, 10)).to.equal(nil)
			expect(Protocol.parseStartRun("3", 10)).to.equal(nil)
			expect(Protocol.parseStartRun(0 / 0, 10)).to.equal(nil)
			expect(Protocol.parseStartRun(math.huge, 10)).to.equal(nil)
			expect(Protocol.parseStartRun({}, 10)).to.equal(nil)
		end)

		it("accepts finite steering axes in -1..1 with a positive integer sequence", function()
			local axis, sequence = Protocol.parseSteer(-0.5, 4)
			expect(axis).to.equal(-0.5)
			expect(sequence).to.equal(4)
			expect((Protocol.parseSteer(1.01, 1))).to.equal(nil)
			expect((Protocol.parseSteer(0 / 0, 1))).to.equal(nil)
			expect((Protocol.parseSteer(-math.huge, 1))).to.equal(nil)
			expect((Protocol.parseSteer(0.5, 0))).to.equal(nil)
			expect((Protocol.parseSteer(0.5, 1.5))).to.equal(nil)
			expect((Protocol.parseSteer(0.5, Protocol.MAX_SEQUENCE + 1))).to.equal(nil)
			expect((Protocol.parseSteer("1", 1))).to.equal(nil)
		end)

		it("quantizes axes", function()
			expect(Protocol.quantizeAxis(0.512, 0.05)).to.be.near(0.5)
			expect(Protocol.quantizeAxis(2, 0.05)).to.equal(1)
			expect(Protocol.quantizeAxis(-0.01, 0.05)).to.be.near(0)
		end)
	end)

	describe("RateLimiter", function()
		it("allows bursts up to capacity and refills over time", function()
			local now = 0
			local limiter = RateLimiter.new(3, 2, function()
				return now
			end)
			local key = {}
			expect(limiter:allow(key)).to.equal(true)
			expect(limiter:allow(key)).to.equal(true)
			expect(limiter:allow(key)).to.equal(true)
			expect(limiter:allow(key)).to.equal(false)
			now = 0.5
			expect(limiter:allow(key)).to.equal(true)
			expect(limiter:allow(key)).to.equal(false)
			now = 100
			for _ = 1, 3 do
				expect(limiter:allow(key)).to.equal(true)
			end
			expect(limiter:allow(key)).to.equal(false)
		end)

		it("tracks keys independently and forgets removed keys", function()
			local limiter = RateLimiter.new(1, 0.001, function()
				return 0
			end)
			local a, b = {}, {}
			expect(limiter:allow(a)).to.equal(true)
			expect(limiter:allow(a)).to.equal(false)
			expect(limiter:allow(b)).to.equal(true)
			limiter:remove(a)
			expect(limiter:allow(a)).to.equal(true)
		end)
	end)
end
