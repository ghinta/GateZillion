--!strict
-- Builds the level geometry locally from the shared level definition. The track is purely
-- cosmetic: the server never looks at these parts, so each client can render its own copy.
-- World mapping: lateral x -> world X, distance z along the track -> world -Z.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage.Shared.config.GameConfig)
local GateMath = require(ReplicatedStorage.Shared.domain.GateMath)
local Types = require(ReplicatedStorage.Shared.domain.Types)

type Level = Types.Level

export type TrackRenderer = {
	build: (self: TrackRenderer, level: Level) -> (),
	markHit: (self: TrackRenderer, id: string, kind: Types.HitKind) -> (),
	clear: (self: TrackRenderer) -> (),
	levelId: (self: TrackRenderer) -> number?,
}

local COLORS = table.freeze({
	track = Color3.fromRGB(214, 222, 235),
	trackEdge = Color3.fromRGB(70, 82, 110),
	grass = Color3.fromRGB(120, 196, 128),
	startLine = Color3.fromRGB(255, 255, 255),
	goodGate = Color3.fromRGB(45, 140, 255),
	badGate = Color3.fromRGB(235, 70, 80),
	post = Color3.fromRGB(245, 245, 250),
	hazard = Color3.fromRGB(255, 150, 30),
	enemy = Color3.fromRGB(220, 50, 60),
	label = Color3.fromRGB(255, 255, 255),
	labelStroke = Color3.fromRGB(20, 24, 40),
	checkerDark = Color3.fromRGB(30, 30, 36),
})

local GATE_HEIGHT = 7
local FONT = Enum.Font.BuilderSansExtraBold
local ENEMY_SPACING = 1.6

local TrackRenderer = {}
TrackRenderer.__index = TrackRenderer

type Element = {
	parts: { BasePart },
	guis: { LayerCollector },
}

type Self = typeof(setmetatable(
	{} :: {
		parent: Instance,
		folder: Folder?,
		elements: { [string]: Element },
		currentLevelId: number?,
	},
	TrackRenderer
))

function TrackRenderer.worldPosition(x: number, z: number, y: number): Vector3
	return Vector3.new(x, y, -z)
end

local function makePart(
	name: string,
	size: Vector3,
	position: Vector3,
	color: Color3,
	parent: Instance,
	transparency: number?,
	material: Enum.Material?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = size
	part.Position = position
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Transparency = transparency or 0
	part.Parent = parent
	return part
end

local function makeLabel(text: string, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = FONT
	label.TextColor3 = color
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = COLORS.labelStroke
	stroke.Parent = label
	return label
end

-- Label on the face that looks back towards the approaching group and camera.
local function surfaceLabel(part: BasePart, text: string): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	local label = makeLabel(text, COLORS.label)
	label.Size = UDim2.fromScale(0.9, 0.6)
	label.Position = UDim2.fromScale(0.05, 0.2)
	label.Parent = gui
	gui.Parent = part
	return gui
end

local function billboardLabel(part: BasePart, text: string, offsetY: number): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(6, 2.4)
	gui.StudsOffset = Vector3.new(0, offsetY, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 220
	makeLabel(text, COLORS.label).Parent = gui
	gui.Adornee = part
	gui.Parent = part
	return gui
end

function TrackRenderer.new(parent: Instance): TrackRenderer
	local self = setmetatable({
		parent = parent,
		folder = nil,
		elements = {},
		currentLevelId = nil,
	}, TrackRenderer)
	return (self :: any) :: TrackRenderer
end

function TrackRenderer.clear(self: Self)
	if self.folder then
		self.folder:Destroy()
		self.folder = nil
	end
	self.elements = {}
	self.currentLevelId = nil
end

function TrackRenderer.levelId(self: Self): number?
	return self.currentLevelId
end

local function buildGround(folder: Folder, level: Level)
	local width = GameConfig.TRACK_WIDTH
	local zFrom, zTo = -40, level.length + 80
	local length = zTo - zFrom
	local centerZ = (zFrom + zTo) / 2

	makePart(
		"Grass",
		Vector3.new(width + 300, 1, length + 300),
		TrackRenderer.worldPosition(0, centerZ, -1.6),
		COLORS.grass,
		folder,
		0,
		Enum.Material.Grass
	)
	makePart(
		"Track",
		Vector3.new(width, 1, length),
		TrackRenderer.worldPosition(0, centerZ, -0.5),
		COLORS.track,
		folder
	)
	for _, side in { -1, 1 } do
		makePart(
			"Edge",
			Vector3.new(0.8, 1.2, length),
			TrackRenderer.worldPosition(side * (width / 2 + 0.4), centerZ, 0.1),
			COLORS.trackEdge,
			folder
		)
	end
	makePart(
		"StartLine",
		Vector3.new(width, 0.05, 1),
		TrackRenderer.worldPosition(0, 0, 0.03),
		COLORS.startLine,
		folder
	)

	-- Checkered finish line and arch.
	local squares = 12
	local squareSize = width / squares
	for row = 0, 1 do
		for column = 0, squares - 1 do
			local dark = (row + column) % 2 == 0
			makePart(
				"Finish",
				Vector3.new(squareSize, 0.05, squareSize),
				TrackRenderer.worldPosition(
					-width / 2 + squareSize * (column + 0.5),
					level.length + squareSize * (row + 0.5),
					0.03
				),
				if dark then COLORS.checkerDark else COLORS.startLine,
				folder
			)
		end
	end
	local banner = makePart(
		"FinishBanner",
		Vector3.new(width + 2, 3, 0.6),
		TrackRenderer.worldPosition(0, level.length, 11),
		COLORS.trackEdge,
		folder
	)
	surfaceLabel(banner, "FINISH")
	for _, side in { -1, 1 } do
		makePart(
			"FinishPost",
			Vector3.new(0.8, 12.5, 0.8),
			TrackRenderer.worldPosition(side * (width / 2 + 0.6), level.length, 6),
			COLORS.trackEdge,
			folder
		)
	end
end

local function buildGate(folder: Folder, gate: Types.Gate): Element
	local width = gate.xMax - gate.xMin
	local centerX = (gate.xMin + gate.xMax) / 2
	local color = if GateMath.isBeneficial(gate.op) then COLORS.goodGate else COLORS.badGate
	local panel = makePart(
		`Gate_{gate.id}`,
		Vector3.new(width - 0.3, GATE_HEIGHT, 0.3),
		TrackRenderer.worldPosition(centerX, gate.z, GATE_HEIGHT / 2),
		color,
		folder,
		0.35,
		Enum.Material.Glass
	)
	local parts: { BasePart } = { panel }
	for _, x in { gate.xMin, gate.xMax } do
		table.insert(
			parts,
			makePart(
				"GatePost",
				Vector3.new(0.4, GATE_HEIGHT + 0.6, 0.4),
				TrackRenderer.worldPosition(x, gate.z, (GATE_HEIGHT + 0.6) / 2),
				COLORS.post,
				folder
			)
		)
	end
	local gui = surfaceLabel(panel, GateMath.label(gate.op, gate.value))
	return { parts = parts, guis = { gui } }
end

local function buildObstacle(folder: Folder, obstacle: Types.Obstacle): Element
	local width = obstacle.xMax - obstacle.xMin
	local block = makePart(
		`Hazard_{obstacle.id}`,
		Vector3.new(width - 0.4, 2.4, 1.6),
		TrackRenderer.worldPosition((obstacle.xMin + obstacle.xMax) / 2, obstacle.z, 1.2),
		COLORS.hazard,
		folder,
		0,
		Enum.Material.Neon
	)
	local gui = surfaceLabel(block, `-{obstacle.damage}`)
	return { parts = { block }, guis = { gui } }
end

local function buildEnemy(folder: Folder, enemy: Types.Enemy): Element
	local visible = math.min(enemy.count, GameConfig.MAX_VISIBLE_ENEMIES)
	local perRow = math.floor((GameConfig.TRACK_WIDTH - 2) / ENEMY_SPACING)
	local parts: { BasePart } = {}
	for index = 0, visible - 1 do
		local column = index % perRow
		local row = index // perRow
		local x = -((perRow - 1) * ENEMY_SPACING) / 2 + column * ENEMY_SPACING
		local unit = makePart(
			"Enemy",
			Vector3.new(1.3, 1.3, 1.3),
			TrackRenderer.worldPosition(x, enemy.z + row * ENEMY_SPACING, 0.65),
			COLORS.enemy,
			folder
		)
		unit.Shape = Enum.PartType.Ball
		table.insert(parts, unit)
	end
	local anchor = makePart(
		`EnemyAnchor_{enemy.id}`,
		Vector3.new(1, 1, 1),
		TrackRenderer.worldPosition(0, enemy.z, 1),
		COLORS.enemy,
		folder,
		1
	)
	table.insert(parts, anchor)
	local gui = billboardLabel(anchor, tostring(enemy.count), 3.5)
	return { parts = parts, guis = { gui } }
end

function TrackRenderer.build(self: Self, level: Level)
	self:clear()
	local folder = Instance.new("Folder")
	folder.Name = "GateZillionTrack"

	buildGround(folder, level)
	for _, gate in level.gates do
		self.elements[gate.id] = buildGate(folder, gate)
	end
	for _, obstacle in level.obstacles do
		self.elements[obstacle.id] = buildObstacle(folder, obstacle)
	end
	for _, enemy in level.enemies do
		self.elements[enemy.id] = buildEnemy(folder, enemy)
	end

	folder.Parent = self.parent
	self.folder = folder
	self.currentLevelId = level.id
end

-- Visual feedback when the server reports that the group hit an element.
function TrackRenderer.markHit(self: Self, id: string, kind: Types.HitKind)
	local element = self.elements[id]
	if element == nil then
		return
	end
	self.elements[id] = nil
	for _, gui in element.guis do
		gui.Enabled = false
	end
	local fade = TweenInfo.new(if kind == "enemy" then 0.35 else 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, part in element.parts do
		if kind == "gate" then
			part.Color = COLORS.post
		end
		TweenService:Create(part, fade, { Transparency = 1 }):Play()
	end
end

return TrackRenderer
