--!strict
-- Converts keyboard, gamepad and touch input into a steering axis in -1..1.
-- Touch works like a virtual joystick anywhere on the screen: drag left or right to steer.

local UserInputService = game:GetService("UserInputService")

export type InputController = {
	getAxis: (self: InputController) -> number,
	isTouch: (self: InputController) -> boolean,
	destroy: (self: InputController) -> (),
}

local GAMEPAD_DEADZONE = 0.2
-- Horizontal drag, as a fraction of the screen width, that gives full steering.
local TOUCH_FULL_DRAG = 0.12

local InputController = {}
InputController.__index = InputController

type Self = typeof(setmetatable(
	{} :: {
		touchStart: Vector3?,
		touchCurrent: Vector3?,
		activeTouch: InputObject?,
		connections: { RBXScriptConnection },
	},
	InputController
))

function InputController.new(): InputController
	local self = setmetatable({
		touchStart = nil :: Vector3?,
		touchCurrent = nil :: Vector3?,
		activeTouch = nil :: InputObject?,
		connections = {} :: { RBXScriptConnection },
	}, InputController)

	table.insert(
		self.connections,
		UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
			if processed or input.UserInputType ~= Enum.UserInputType.Touch or self.activeTouch then
				return
			end
			self.activeTouch = input
			self.touchStart = input.Position
			self.touchCurrent = input.Position
		end)
	)
	table.insert(
		self.connections,
		UserInputService.InputChanged:Connect(function(input: InputObject)
			if input == self.activeTouch then
				self.touchCurrent = input.Position
			end
		end)
	)
	table.insert(
		self.connections,
		UserInputService.InputEnded:Connect(function(input: InputObject)
			if input == self.activeTouch then
				self.activeTouch = nil
				self.touchStart = nil
				self.touchCurrent = nil
			end
		end)
	)

	return (self :: any) :: InputController
end

local function keyboardAxis(): number
	if UserInputService:GetFocusedTextBox() then
		return 0
	end
	local axis = 0
	if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then
		axis -= 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then
		axis += 1
	end
	return axis
end

local function gamepadAxis(): number
	if not UserInputService:GetGamepadConnected(Enum.UserInputType.Gamepad1) then
		return 0
	end
	for _, state in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
		if state.KeyCode == Enum.KeyCode.Thumbstick1 then
			local x = state.Position.X
			if math.abs(x) >= GAMEPAD_DEADZONE then
				return x
			end
		elseif state.KeyCode == Enum.KeyCode.DPadLeft and state.UserInputState == Enum.UserInputState.Begin then
			return -1
		elseif state.KeyCode == Enum.KeyCode.DPadRight and state.UserInputState == Enum.UserInputState.Begin then
			return 1
		end
	end
	return 0
end

function InputController.touchAxis(self: Self): number
	local start, current = self.touchStart, self.touchCurrent
	if start == nil or current == nil then
		return 0
	end
	local camera = workspace.CurrentCamera
	local width = if camera then camera.ViewportSize.X else 1000
	return math.clamp((current.X - start.X) / (width * TOUCH_FULL_DRAG), -1, 1)
end

function InputController.getAxis(self: Self): number
	local axis = keyboardAxis() + gamepadAxis() + InputController.touchAxis(self)
	return math.clamp(axis, -1, 1)
end

function InputController.isTouch(_self: Self): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

function InputController.destroy(self: Self)
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
end

return InputController
