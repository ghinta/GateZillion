local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProfileData = require(ReplicatedStorage.Shared.domain.ProfileData)

return function()
	describe("ProfileData.fromStored", function()
		it("creates the default profile for new players", function()
			local profile = ProfileData.fromStored(nil)
			expect(profile).to.be.ok()
			expect(profile.schemaVersion).to.equal(ProfileData.CURRENT_VERSION)
			expect(profile.highestUnlockedLevel).to.equal(1)
			expect(profile.earnedPoints).to.equal(0)
			expect(profile.settings.soundEnabled).to.equal(true)
		end)

		it("keeps valid data and repairs invalid fields", function()
			local profile = ProfileData.fromStored({
				schemaVersion = 1,
				highestUnlockedLevel = 4,
				earnedPoints = -20,
				bestScores = { ["1"] = 30, ["2"] = "lots", ["x"] = 5, [3] = 12 },
				unlockedCosmetics = { "hat", 42 },
				settings = { soundEnabled = false },
				injected = "ignored",
			})
			expect(profile.highestUnlockedLevel).to.equal(4)
			expect(profile.earnedPoints).to.equal(0)
			expect(profile.bestScores["1"]).to.equal(30)
			expect(profile.bestScores["2"]).to.equal(nil)
			expect(profile.bestScores["x"]).to.equal(nil)
			expect(profile.bestScores["3"]).to.equal(12)
			expect(#profile.unlockedCosmetics).to.equal(1)
			expect(profile.settings.soundEnabled).to.equal(false)
			expect((profile :: any).injected).to.equal(nil)
		end)

		it("refuses corrupt records and newer schemas", function()
			local profile, reason = ProfileData.fromStored("garbage")
			expect(profile).to.equal(nil)
			expect(reason).to.be.ok()
			profile, reason = ProfileData.fromStored({ schemaVersion = ProfileData.CURRENT_VERSION + 1 })
			expect(profile).to.equal(nil)
			expect(string.find(reason, "newer", 1, true)).to.be.ok()
		end)

		it("runs migrations in order", function()
			local migrations = {
				[1] = function(raw)
					raw.highestUnlockedLevel = raw.level
					raw.level = nil
					raw.schemaVersion = 2
					return raw
				end,
				[2] = function(raw)
					raw.earnedPoints = (raw.coins or 0) * 2
					raw.schemaVersion = 3
					return raw
				end,
			}
			local profile = ProfileData.fromStored({ schemaVersion = 1, level = 5, coins = 21 }, migrations, 3)
			expect(profile).to.be.ok()
			expect(profile.highestUnlockedLevel).to.equal(5)
			expect(profile.earnedPoints).to.equal(42)
		end)

		it("reports a missing migration step", function()
			local profile, reason = ProfileData.fromStored({ schemaVersion = 1 }, {}, 2)
			expect(profile).to.equal(nil)
			expect(string.find(reason, "missing profile migration", 1, true)).to.be.ok()
		end)

		it("does not mutate the stored input", function()
			local raw = { schemaVersion = 1, highestUnlockedLevel = 2, bestScores = { ["1"] = 3 } }
			local profile = ProfileData.fromStored(raw)
			profile.bestScores["1"] = 99
			expect(raw.bestScores["1"]).to.equal(3)
		end)
	end)
end
