--!strict
-- Renders the player's group as a pool of lightweight anchored parts moved with BulkMoveTo.
-- The logical group size can be far larger than the number of visible units; a billboard above
-- the group always shows the exact count. No Humanoids, no physics, nothing replicated.

export type FormationRenderer = {
	setCount: (self: FormationRenderer, count: number) -> (),
	reset: (self: FormationRenderer, count: number) -> (),
	update: (self: FormationRenderer, dt: number, lanePosition: Vector3, trackHalfWidth: number) -> (),
	setVisible: (self: FormationRenderer, visible: boolean) -> (),
	destroy: (self: FormationRenderer) -> (),
}

local GOLDEN_ANGLE = math.pi * (3 - math.sqrt(5))
local SPACING = 0.78
-- The formation is narrower than it is long so it reads clearly inside a single lane.
local X_SCALE = 0.55
local Z_SCALE = 1.25
local UNIT_SIZE = 1.25
local HIDDEN_CFRAME = CFrame.new(0, -1000, 0)
local FOLLOW_RATE = 12

local FormationRenderer = {}
FormationRenderer.__index = FormationRenderer

type Self = typeof(setmetatable(
	{} :: {
		folder: Folder,
		units: { BasePart },
		positions: { Vector3 },
		activeCount: number,
		maxUnits: number,
		anchor: Part,
		countLabel: TextLabel,
		visible: boolean,
		-- Place units directly on their slots on the next update instead of easing in.
		snapNext: boolean,
		clock: number,
	},
	FormationRenderer
))

local function makeUnit(color: Color3, parent: Instance): Part
	local unit = Instance.new("Part")
	unit.Name = "Unit"
	unit.Shape = Enum.PartType.Ball
	unit.Size = Vector3.new(UNIT_SIZE, UNIT_SIZE, UNIT_SIZE)
	unit.Color = color
	unit.Material = Enum.Material.SmoothPlastic
	unit.Anchored = true
	unit.CanCollide = false
	unit.CanQuery = false
	unit.CanTouch = false
	unit.CastShadow = false
	unit.CFrame = HIDDEN_CFRAME
	unit.Parent = parent
	return unit
end

function FormationRenderer.new(parent: Instance, maxUnits: number, color: Color3): FormationRenderer
	local folder = Instance.new("Folder")
	folder.Name = "GateZillionCrowd"

	local units = {}
	for _ = 1, maxUnits do
		table.insert(units, makeUnit(color, folder))
	end

	local anchor = Instance.new("Part")
	anchor.Name = "CountAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = HIDDEN_CFRAME
	anchor.Parent = folder

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(7, 2.6)
	billboard.StudsOffset = Vector3.new(0, 4.5, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Adornee = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.BuilderSansExtraBold
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = "0"
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(20, 40, 90)
	stroke.Parent = label
	label.Parent = billboard
	billboard.Parent = anchor

	folder.Parent = parent

	local self = setmetatable({
		folder = folder,
		units = units,
		positions = table.create(maxUnits, Vector3.zero),
		activeCount = 0,
		maxUnits = maxUnits,
		anchor = anchor,
		countLabel = label,
		visible = true,
		snapNext = true,
		clock = 0,
	}, FormationRenderer)
	return (self :: any) :: FormationRenderer
end

local function slotOffset(index: number): (number, number)
	local radius = SPACING * math.sqrt(index - 0.5)
	local theta = index * GOLDEN_ANGLE
	return math.cos(theta) * radius * X_SCALE, math.sin(theta) * radius * Z_SCALE
end

function FormationRenderer.setCount(self: Self, count: number)
	self.countLabel.Text = tostring(count)
	local visibleCount = math.min(count, self.maxUnits)
	if visibleCount < self.activeCount then
		local hidden: { BasePart } = {}
		local cframes: { CFrame } = {}
		for index = visibleCount + 1, self.activeCount do
			table.insert(hidden, self.units[index])
			table.insert(cframes, HIDDEN_CFRAME)
		end
		workspace:BulkMoveTo(hidden, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	elseif visibleCount > self.activeCount then
		-- New units spawn at the group centre and spread out to their slots.
		local centre = self.anchor.Position
		for index = self.activeCount + 1, visibleCount do
			self.positions[index] = centre
		end
	end
	self.activeCount = visibleCount
end

-- Sets the count and places every unit directly on its slot (used when a new run starts).
function FormationRenderer.reset(self: Self, count: number)
	self:setCount(count)
	self.snapNext = true
end

function FormationRenderer.update(self: Self, dt: number, lanePosition: Vector3, trackHalfWidth: number)
	if not self.visible then
		return
	end
	self.clock += dt
	self.anchor.CFrame = CFrame.new(lanePosition)

	local alpha = if self.snapNext then 1 else 1 - math.exp(-FOLLOW_RATE * dt)
	self.snapNext = false
	local parts: { BasePart } = table.create(self.activeCount)
	local cframes: { CFrame } = table.create(self.activeCount)
	local xLimit = trackHalfWidth - UNIT_SIZE / 2
	for index = 1, self.activeCount do
		local dx, dz = slotOffset(index)
		local x = math.clamp(lanePosition.X + dx, -xLimit, xLimit)
		local bob = math.abs(math.sin(self.clock * 11 + index * 0.7)) * 0.25
		local target = Vector3.new(x, lanePosition.Y + UNIT_SIZE / 2 + bob, lanePosition.Z + dz)
		local position = self.positions[index]:Lerp(target, alpha)
		self.positions[index] = position
		parts[index] = self.units[index]
		cframes[index] = CFrame.new(position)
	end
	if self.activeCount > 0 then
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function FormationRenderer.setVisible(self: Self, visible: boolean)
	if visible == self.visible then
		return
	end
	self.visible = visible
	if visible then
		self.snapNext = true
	else
		local cframes = table.create(#self.units, HIDDEN_CFRAME)
		workspace:BulkMoveTo(self.units, cframes, Enum.BulkMoveMode.FireCFrameChanged)
		self.anchor.CFrame = HIDDEN_CFRAME
	end
end

function FormationRenderer.destroy(self: Self)
	self.folder:Destroy()
end

return FormationRenderer
