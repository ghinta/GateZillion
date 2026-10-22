--!strict
-- Server composition root: wires services to Roblox events. Game rules live in the services.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RbxRunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.config.GameConfig)
local Levels = require(ReplicatedStorage.Shared.config.Levels)
local services = script.services
local LevelService = require(services.LevelService)
local ProfileService = require(services.ProfileService)
local ProfileStore = require(services.ProfileStore)
local RemoteGateway = require(services.RemoteGateway)
local RunService = require(services.RunService)

Players.CharacterAutoLoads = false

local levels = LevelService.new(Levels.list, GameConfig)

local useMemoryStore = RbxRunService:IsStudio() and not GameConfig.USE_DATASTORE_IN_STUDIO
local store = if useMemoryStore
	then ProfileStore.memory()
	else ProfileStore.fromDataStore(DataStoreService:GetDataStore(GameConfig.DATASTORE_NAME))
if useMemoryStore then
	print("[GateZillion] Studio session: using in-memory profile store")
end

local profiles = ProfileService.new({
	store = store,
	jobId = if game.JobId ~= "" then game.JobId else "studio",
	now = os.time,
	wait = function(seconds: number)
		task.wait(seconds)
	end,
	spawn = function(fn: () -> ())
		task.spawn(fn)
	end,
})

local gateway = RemoteGateway.new({
	levelCount = levels:count(),
	clock = os.clock,
})

local runs = RunService.new({
	levels = levels,
	profiles = profiles,
	gateway = gateway,
	clock = os.clock,
})

gateway:bind({
	startRun = function(player: Player, levelId: number)
		runs:startRun(player, levelId)
	end,
	steer = function(player: Player, axis: number)
		runs:steer(player, axis)
	end,
	clientReady = function(player: Player)
		runs:clientReady(player)
	end,
})
gateway:mount(ReplicatedStorage)

local function onPlayerAdded(player: Player)
	runs:addPlayer(player)
	local ok, err = profiles:load(player.UserId)
	if player.Parent == nil then
		-- Left while loading; ProfileService releases the lock itself.
		return
	end
	if not ok then
		warn(`[GateZillion] could not load profile for {player.UserId}: {err}`)
		player:Kick("Your progress could not be loaded right now. Please rejoin in a moment.")
		return
	end
	runs:profileLoaded(player)
end

local function onPlayerRemoving(player: Player)
	runs:removePlayer(player)
	gateway:removePlayer(player)
	profiles:release(player.UserId)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

RbxRunService.Heartbeat:Connect(function(dt: number)
	runs:tick(dt)
end)

task.spawn(function()
	while true do
		task.wait(GameConfig.AUTOSAVE_INTERVAL)
		profiles:saveAll()
	end
end)

game:BindToClose(function()
	profiles:releaseAll()
end)
