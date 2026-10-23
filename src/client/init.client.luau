--!strict
-- Client composition root: input -> Steer intents, server snapshots/events -> presentation.
-- Nothing here decides outcomes; the server is authoritative for progress, counts and rewards.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.config.GameConfig)
local Levels = require(Shared.config.Levels)
local Protocol = require(Shared.net.Protocol)

local controllers = script.controllers
local CameraController = require(controllers.CameraController)
local FormationRenderer = require(controllers.FormationRenderer)
local InputController = require(controllers.InputController)
local RunPresenter = require(controllers.RunPresenter)
local TrackRenderer = require(controllers.TrackRenderer)
local HudController = require(script.ui.HudController)

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild(Protocol.FOLDER_NAME)

local function remote(name: string): RemoteEvent
	return remotes:WaitForChild(name) :: RemoteEvent
end

local startRunRemote = remote(Protocol.ClientToServer.StartRun)
local steerRemote = remote(Protocol.ClientToServer.Steer)
local clientReadyRemote = remote(Protocol.ClientToServer.ClientReady)

task.spawn(function()
	-- There is no character to reset; retry because the core GUI may not be ready yet.
	for _ = 1, 10 do
		if pcall(StarterGui.SetCore, StarterGui, "ResetButtonCallback", false) then
			return
		end
		task.wait(0.5)
	end
end)

local camera = CameraController.new(workspace.CurrentCamera :: Camera)
local track = TrackRenderer.new(workspace)
local crowd = FormationRenderer.new(workspace, GameConfig.MAX_VISIBLE_UNITS, Color3.fromRGB(45, 140, 255))
local input = InputController.new()
local presenter = RunPresenter.new(GameConfig)

local steerSequence = 0
local lastSentAxis = 0
local lastSentAt = -math.huge
local pendingStart = false

local function previewLevel(levelId: number)
	local level = Levels.get(levelId)
	if level and track:levelId() ~= levelId then
		track:build(level)
	end
	camera:setMode("overview")
	crowd:setVisible(false)
end

local hud: HudController.HudController
hud = HudController.new(player:WaitForChild("PlayerGui") :: PlayerGui, Levels.list, {
	onSelect = previewLevel,
	onPlay = function(levelId: number)
		if pendingStart then
			return
		end
		pendingStart = true
		startRunRemote:FireServer(levelId)
		-- The server answers with a snapshot; allow another attempt if it rejected the request.
		task.delay(GameConfig.START_RUN_COOLDOWN + 0.5, function()
			pendingStart = false
		end)
	end,
	onMenu = function()
		presenter:reset()
		hud:showLobby()
		-- Rebuild so gates consumed during the last run are visible again.
		track:clear()
		previewLevel(hud:selectedLevel())
	end,
}, input:isTouch())

hud:setStatus("Loading profile...")
hud:showLobby()
previewLevel(1)

remote(Protocol.ServerToClient.ProfileUpdated).OnClientEvent:Connect(function(view: Protocol.ProfileView)
	hud:setStatus(nil)
	hud:setProfile(view)
end)

remote(Protocol.ServerToClient.RunSnapshot).OnClientEvent:Connect(function(snapshot: Protocol.Snapshot)
	local isNew = presenter:applySnapshot(snapshot, os.clock())
	if not isNew then
		return
	end
	local level = Levels.get(snapshot.levelId)
	if level == nil then
		return
	end
	pendingStart = false
	lastSentAxis = 0
	track:build(level)
	hud:showRun(level)
	camera:setMode("follow")
	crowd:setVisible(true)
	crowd:reset(snapshot.groupCount)
end)

remote(Protocol.ServerToClient.RunEvent).OnClientEvent:Connect(function(event: Protocol.RunEvent)
	if presenter:applyEvent(event) then
		track:markHit(event.id, event.kind)
		crowd:setCount(event.after)
		hud:showDelta(event.before, event.after)
	end
end)

remote(Protocol.ServerToClient.RunEnded).OnClientEvent:Connect(function(payload: Protocol.RunEnded)
	local level = Levels.get(payload.levelId)
	if level and payload.runId == presenter.runId then
		crowd:setCount(payload.finalCount)
		hud:showResults(payload, level, payload.levelId < #Levels.list)
	end
end)

local function sendSteer(axis: number, now: number)
	local phase = presenter.phase
	if phase ~= "Loading" and phase ~= "Running" then
		return
	end
	if axis == lastSentAxis or now - lastSentAt < GameConfig.CLIENT_STEER_MIN_INTERVAL then
		return
	end
	steerSequence += 1
	lastSentAxis = axis
	lastSentAt = now
	steerRemote:FireServer(axis, steerSequence)
end

RunService.RenderStepped:Connect(function(dt: number)
	local now = os.clock()
	local axis = Protocol.quantizeAxis(input:getAxis(), GameConfig.STEER_AXIS_STEP)
	sendSteer(axis, now)

	local level = Levels.get(presenter.levelId)
	local inRun = presenter.phase ~= "Lobby" and level ~= nil
	if inRun and level then
		presenter:update(dt, if presenter.phase == "Running" then axis else 0, now, level.length)
		local position = TrackRenderer.worldPosition(presenter.laneX, presenter.progress, 0)
		crowd:update(dt, position, GameConfig.TRACK_WIDTH / 2)
		camera:update(dt, position)
		if presenter.phase == "Loading" or presenter.phase == "Running" then
			hud:updateRun(presenter.progress / level.length, presenter.groupCount, presenter:countdown(now))
		end
	else
		camera:update(dt, TrackRenderer.worldPosition(0, 0, 0))
	end
end)

clientReadyRemote:FireServer()
