--!strict
-- The only entry point for client messages. Validates argument count, types, ranges, sequence
-- numbers and per-player rate limits before anything reaches game logic. Also owns the
-- server -> client remotes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.config.GameConfig)
local Protocol = require(ReplicatedStorage.Shared.net.Protocol)
local RateLimiter = require(ReplicatedStorage.Shared.util.RateLimiter)

type Config = typeof(GameConfig)

export type Handlers = {
	startRun: (player: Player, levelId: number) -> (),
	steer: (player: Player, axis: number) -> (),
	clientReady: (player: Player) -> (),
}

export type Options = {
	levelCount: number,
	clock: () -> number,
	config: Config?,
	warn: ((message: string) -> ())?,
}

export type RemoteGateway = {
	bind: (self: RemoteGateway, handlers: Handlers) -> (),
	dispatch: (self: RemoteGateway, player: Player, name: string, ...any) -> (boolean, string?),
	mount: (self: RemoteGateway, parent: Instance) -> Folder,
	removePlayer: (self: RemoteGateway, player: Player) -> (),
	sendSnapshot: (self: RemoteGateway, player: Player, snapshot: Protocol.Snapshot) -> (),
	sendRunEvent: (self: RemoteGateway, player: Player, event: Protocol.RunEvent) -> (),
	sendRunEnded: (self: RemoteGateway, player: Player, payload: Protocol.RunEnded) -> (),
	sendProfile: (self: RemoteGateway, player: Player, view: Protocol.ProfileView) -> (),
}

local EXPECTED_ARGS: { [string]: number } = {
	[Protocol.ClientToServer.StartRun] = 1,
	[Protocol.ClientToServer.Steer] = 2,
	[Protocol.ClientToServer.ClientReady] = 0,
}

-- Log every Nth rejected message per player to keep spam out of the server log.
local REJECTION_LOG_INTERVAL = 25

local RemoteGateway = {}
RemoteGateway.__index = RemoteGateway

type Self = typeof(setmetatable(
	{} :: {
		levelCount: number,
		limiters: { [string]: RateLimiter.RateLimiter },
		sequences: { [Player]: number },
		rejections: { [Player]: number },
		handlers: Handlers?,
		remotes: { [string]: RemoteEvent },
		warn: (message: string) -> (),
	},
	RemoteGateway
))

function RemoteGateway.new(options: Options): RemoteGateway
	local config = options.config or GameConfig
	local limiters = {}
	for name, limit in config.RATE_LIMITS do
		limiters[name] = RateLimiter.new(limit.capacity, limit.refillPerSecond, options.clock)
	end
	local self = setmetatable({
		levelCount = options.levelCount,
		limiters = limiters,
		sequences = {},
		rejections = {},
		handlers = nil,
		remotes = {},
		warn = options.warn or warn,
	}, RemoteGateway)
	return (self :: any) :: RemoteGateway
end

function RemoteGateway.bind(self: Self, handlers: Handlers)
	self.handlers = handlers
end

local function reject(self: Self, player: Player, name: string, reason: string): (boolean, string?)
	local count = (self.rejections[player] or 0) + 1
	self.rejections[player] = count
	if count % REJECTION_LOG_INTERVAL == 1 then
		self.warn(`[RemoteGateway] rejected {name} from {player.Name}: {reason} ({count} total)`)
	end
	return false, reason
end

-- Validates and routes one client message. Returns whether it was accepted and why not.
function RemoteGateway.dispatch(self: Self, player: Player, name: string, ...: any): (boolean, string?)
	local handlers = self.handlers
	local expectedArgs = EXPECTED_ARGS[name]
	if handlers == nil or expectedArgs == nil then
		return reject(self, player, tostring(name), "unknown remote")
	end
	if select("#", ...) ~= expectedArgs then
		return reject(self, player, name, "wrong argument count")
	end
	if not self.limiters[name]:allow(player) then
		return reject(self, player, name, "rate limited")
	end

	if name == Protocol.ClientToServer.StartRun then
		local levelId = Protocol.parseStartRun((...), self.levelCount)
		if levelId == nil then
			return reject(self, player, name, "invalid level id")
		end
		handlers.startRun(player, levelId)
	elseif name == Protocol.ClientToServer.Steer then
		local axis, sequence = Protocol.parseSteer(...)
		if axis == nil or sequence == nil then
			return reject(self, player, name, "invalid steer payload")
		end
		if sequence <= (self.sequences[player] or 0) then
			return reject(self, player, name, "stale sequence")
		end
		self.sequences[player] = sequence
		handlers.steer(player, axis)
	else
		handlers.clientReady(player)
	end
	return true, nil
end

function RemoteGateway.removePlayer(self: Self, player: Player)
	for _, limiter in self.limiters do
		limiter:remove(player)
	end
	self.sequences[player] = nil
	self.rejections[player] = nil
end

-- Creates the remotes under `parent` and wires client messages into dispatch.
function RemoteGateway.mount(self: Self, parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = Protocol.FOLDER_NAME
	for _, name in Protocol.CLIENT_TO_SERVER_NAMES do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.OnServerEvent:Connect(function(player: Player, ...: any)
			self:dispatch(player, name, ...)
		end)
		remote.Parent = folder
	end
	for _, name in Protocol.SERVER_TO_CLIENT_NAMES do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
		self.remotes[name] = remote
	end
	folder.Parent = parent
	return folder
end

local function fire(self: Self, name: string, player: Player, payload: any)
	local remote = self.remotes[name]
	if remote then
		remote:FireClient(player, payload)
	end
end

function RemoteGateway.sendSnapshot(self: Self, player: Player, snapshot: Protocol.Snapshot)
	fire(self, Protocol.ServerToClient.RunSnapshot, player, snapshot)
end

function RemoteGateway.sendRunEvent(self: Self, player: Player, event: Protocol.RunEvent)
	fire(self, Protocol.ServerToClient.RunEvent, player, event)
end

function RemoteGateway.sendRunEnded(self: Self, player: Player, payload: Protocol.RunEnded)
	fire(self, Protocol.ServerToClient.RunEnded, player, payload)
end

function RemoteGateway.sendProfile(self: Self, player: Player, view: Protocol.ProfileView)
	fire(self, Protocol.ServerToClient.ProfileUpdated, player, view)
end

return RemoteGateway
