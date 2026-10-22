--!strict
-- Scripted camera: a slow overview of the selected track in the lobby, a smooth chase camera
-- behind the group during runs. Portrait screens get a higher, wider view.

export type Mode = "overview" | "follow"

export type CameraController = {
	setMode: (self: CameraController, mode: Mode) -> (),
	update: (self: CameraController, dt: number, focus: Vector3) -> (),
}

local FOLLOW_OFFSET = Vector3.new(0, 17, 21)
local FOLLOW_OFFSET_PORTRAIT = Vector3.new(0, 26, 30)
local LOOK_AHEAD = 16
local OVERVIEW_OFFSET = Vector3.new(18, 34, 28)
local OVERVIEW_TARGET_AHEAD = 70
local SMOOTHING = 7

local CameraController = {}
CameraController.__index = CameraController

type Self = typeof(setmetatable(
	{} :: {
		camera: Camera,
		mode: Mode,
		current: CFrame?,
		clock: number,
	},
	CameraController
))

function CameraController.new(camera: Camera): CameraController
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 70
	local self = setmetatable({
		camera = camera,
		mode = "overview" :: Mode,
		current = nil,
		clock = 0,
	}, CameraController)
	return (self :: any) :: CameraController
end

function CameraController.setMode(self: Self, mode: Mode)
	if mode ~= self.mode then
		self.mode = mode
		-- Cut instead of flying across the map when switching modes.
		self.current = nil
	end
end

local function isPortrait(camera: Camera): boolean
	local size = camera.ViewportSize
	return size.Y > size.X
end

function CameraController.update(self: Self, dt: number, focus: Vector3)
	local camera = self.camera
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	self.clock += dt

	local target: CFrame
	if self.mode == "follow" then
		local offset = if isPortrait(camera) then FOLLOW_OFFSET_PORTRAIT else FOLLOW_OFFSET
		-- Follow the lane only partially so lateral steering stays readable on screen.
		local anchor = Vector3.new(focus.X * 0.5, focus.Y, focus.Z)
		target = CFrame.lookAt(anchor + offset, anchor + Vector3.new(0, 0, -LOOK_AHEAD))
	else
		local sway = math.sin(self.clock * 0.25) * 6
		local eye = focus + OVERVIEW_OFFSET + Vector3.new(sway, 0, 0)
		target = CFrame.lookAt(eye, focus + Vector3.new(0, 0, -OVERVIEW_TARGET_AHEAD))
	end

	local previous = self.current
	local current = if previous then previous:Lerp(target, 1 - math.exp(-SMOOTHING * dt)) else target
	self.current = current
	camera.CFrame = current
end

return CameraController
