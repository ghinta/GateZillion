--!strict
-- All 2D UI: level select (lobby), in-run HUD and results. Built in code so it stays in Git.
-- Scales with the viewport and respects device safe areas.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Types = require(ReplicatedStorage.Shared.domain.Types)
local Protocol = require(ReplicatedStorage.Shared.net.Protocol)

type Level = Types.Level

export type Callbacks = {
	onSelect: (levelId: number) -> (),
	onPlay: (levelId: number) -> (),
	onMenu: () -> (),
}

export type HudController = {
	setProfile: (self: HudController, view: Protocol.ProfileView) -> (),
	selectedLevel: (self: HudController) -> number,
	showLobby: (self: HudController) -> (),
	showRun: (self: HudController, level: Level) -> (),
	updateRun: (self: HudController, progress: number, groupCount: number, countdown: number?) -> (),
	showDelta: (self: HudController, before: number, after: number) -> (),
	showResults: (self: HudController, payload: Protocol.RunEnded, level: Level, hasNextLevel: boolean) -> (),
	setStatus: (self: HudController, text: string?) -> (),
}

local THEME = table.freeze({
	panel = Color3.fromRGB(22, 28, 52),
	panelLight = Color3.fromRGB(40, 50, 88),
	accent = Color3.fromRGB(45, 140, 255),
	good = Color3.fromRGB(80, 220, 120),
	bad = Color3.fromRGB(255, 90, 90),
	locked = Color3.fromRGB(70, 74, 90),
	text = Color3.fromRGB(255, 255, 255),
	muted = Color3.fromRGB(180, 188, 210),
	stroke = Color3.fromRGB(10, 14, 30),
})

local FONT = Enum.Font.BuilderSansExtraBold
local FONT_BODY = Enum.Font.BuilderSansBold
local DESIGN_HEIGHT = 720

local HudController = {}
HudController.__index = HudController

type LevelButton = {
	button: TextButton,
	detail: TextLabel,
	stroke: UIStroke,
}

type Self = typeof(setmetatable(
	{} :: {
		gui: ScreenGui,
		callbacks: Callbacks,
		levels: { Level },
		profile: Protocol.ProfileView?,
		selected: number,
		touch: boolean,
		lobby: Frame,
		pointsLabel: TextLabel,
		playButton: TextButton,
		levelButtons: { LevelButton },
		run: Frame,
		levelName: TextLabel,
		progressFill: Frame,
		countLabel: TextLabel,
		countdownLabel: TextLabel,
		deltaLabel: TextLabel,
		hintLabel: TextLabel,
		results: Frame,
		resultTitle: TextLabel,
		resultBody: TextLabel,
		nextButton: TextButton,
		retryButton: TextButton,
		status: TextLabel,
		lastResultLevel: number,
	},
	HudController
))

local function corner(parent: GuiObject, radius: number)
	local instance = Instance.new("UICorner")
	instance.CornerRadius = UDim.new(0, radius)
	instance.Parent = parent
end

local function textStroke(parent: TextLabel | TextButton, thickness: number)
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Color = THEME.stroke
	stroke.Thickness = thickness
	stroke.Parent = parent
end

local function makeLabel(parent: Instance, text: string, size: UDim2, position: UDim2, textSize: number): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = size
	label.Position = position
	label.Text = text
	label.TextSize = textSize
	label.Font = FONT
	label.TextColor3 = THEME.text
	label.TextWrapped = true
	label.Parent = parent
	return label
end

local function makeButton(parent: Instance, text: string, size: UDim2, position: UDim2, color: Color3): TextButton
	local button = Instance.new("TextButton")
	button.Size = size
	button.Position = position
	button.BackgroundColor3 = color
	button.Text = text
	button.TextSize = 26
	button.Font = FONT
	button.TextColor3 = THEME.text
	button.AutoButtonColor = true
	corner(button, 12)
	button.Parent = parent
	return button
end

local function makePanel(parent: Instance, name: string, size: UDim2): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = size
	frame.BackgroundColor3 = THEME.panel
	frame.BackgroundTransparency = 0.1
	frame.Visible = false
	corner(frame, 18)
	frame.Parent = parent
	return frame
end

local function formatCount(count: number): string
	local text = tostring(count)
	local formatted = string.reverse((string.gsub(string.reverse(text), "(%d%d%d)", "%1,")))
	return (string.gsub(formatted, "^,", ""))
end

HudController.formatCount = formatCount

local function buildLobby(self: Self)
	local lobby = makePanel(self.gui, "Lobby", UDim2.fromOffset(640, 520))
	self.lobby = lobby

	local title = makeLabel(lobby, "GateZillion", UDim2.new(1, 0, 0, 64), UDim2.fromOffset(0, 16), 54)
	textStroke(title, 3)
	self.pointsLabel = makeLabel(lobby, "Points: 0", UDim2.new(1, 0, 0, 28), UDim2.fromOffset(0, 80), 24)
	self.pointsLabel.TextColor3 = THEME.muted

	local grid = Instance.new("Frame")
	grid.BackgroundTransparency = 1
	grid.Size = UDim2.fromOffset(590, 230)
	grid.Position = UDim2.new(0.5, -295, 0, 124)
	grid.Parent = lobby
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(110, 106)
	layout.CellPadding = UDim2.fromOffset(10, 12)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	for index, level in self.levels do
		local button = Instance.new("TextButton")
		button.LayoutOrder = index
		button.BackgroundColor3 = THEME.panelLight
		button.Text = ""
		button.AutoButtonColor = true
		corner(button, 12)
		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Color = THEME.accent
		stroke.Thickness = 0
		stroke.Parent = button
		local number = makeLabel(button, tostring(level.id), UDim2.new(1, 0, 0, 44), UDim2.fromOffset(0, 6), 40)
		textStroke(number, 2)
		local name = makeLabel(button, level.name, UDim2.new(1, -8, 0, 34), UDim2.fromOffset(4, 48), 16)
		name.Font = FONT_BODY
		local detail = makeLabel(button, "Locked", UDim2.new(1, 0, 0, 20), UDim2.fromOffset(0, 82), 15)
		detail.Font = FONT_BODY
		detail.TextColor3 = THEME.muted
		button.Parent = grid
		button.Activated:Connect(function()
			local profile = self.profile
			if profile and level.id <= profile.highestUnlockedLevel then
				self.selected = level.id
				HudController.refreshLobby(self)
				self.callbacks.onSelect(level.id)
			end
		end)
		self.levelButtons[index] = { button = button, detail = detail, stroke = stroke }
	end

	self.playButton = makeButton(lobby, "Play", UDim2.fromOffset(260, 62), UDim2.new(0.5, -130, 1, -132), THEME.accent)
	self.playButton.TextSize = 30
	self.playButton.Activated:Connect(function()
		if self.profile then
			self.callbacks.onPlay(self.selected)
		end
	end)

	local hint = makeLabel(
		lobby,
		if self.touch then "Drag left or right to steer" else "Steer with A / D or the arrow keys",
		UDim2.new(1, 0, 0, 24),
		UDim2.new(0, 0, 1, -56),
		18
	)
	hint.Font = FONT_BODY
	hint.TextColor3 = THEME.muted
end

local function buildRun(self: Self)
	local run = Instance.new("Frame")
	run.Name = "Run"
	run.BackgroundTransparency = 1
	run.Size = UDim2.fromScale(1, 1)
	run.Visible = false
	run.Parent = self.gui
	self.run = run

	self.levelName = makeLabel(run, "", UDim2.new(0, 360, 0, 32), UDim2.fromOffset(16, 12), 26)
	self.levelName.TextXAlignment = Enum.TextXAlignment.Left
	textStroke(self.levelName, 2)

	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.new(0.5, 0, 0, 56)
	bar.Size = UDim2.new(0.5, 0, 0, 14)
	bar.BackgroundColor3 = THEME.panel
	bar.BackgroundTransparency = 0.2
	corner(bar, 7)
	bar.Parent = run
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = THEME.accent
	corner(fill, 7)
	fill.Parent = bar
	self.progressFill = fill

	self.countLabel = makeLabel(run, "0", UDim2.new(0, 260, 0, 56), UDim2.new(1, -276, 0, 6), 48)
	self.countLabel.TextXAlignment = Enum.TextXAlignment.Right
	textStroke(self.countLabel, 3)

	self.deltaLabel = makeLabel(run, "", UDim2.new(0, 260, 0, 40), UDim2.new(1, -276, 0, 62), 34)
	self.deltaLabel.TextXAlignment = Enum.TextXAlignment.Right
	self.deltaLabel.TextTransparency = 1
	textStroke(self.deltaLabel, 2)

	self.countdownLabel = makeLabel(run, "", UDim2.fromOffset(300, 140), UDim2.new(0.5, -150, 0.35, -70), 120)
	textStroke(self.countdownLabel, 4)

	self.hintLabel = makeLabel(
		run,
		if self.touch then "Drag left or right to steer" else "A / D or arrow keys to steer",
		UDim2.new(1, 0, 0, 32),
		UDim2.new(0, 0, 1, -64),
		26
	)
	textStroke(self.hintLabel, 2)
end

local function buildResults(self: Self)
	local results = makePanel(self.gui, "Results", UDim2.fromOffset(460, 380))
	self.results = results

	self.resultTitle = makeLabel(results, "", UDim2.new(1, 0, 0, 56), UDim2.fromOffset(0, 18), 44)
	textStroke(self.resultTitle, 3)
	self.resultBody = makeLabel(results, "", UDim2.new(1, -40, 0, 150), UDim2.fromOffset(20, 80), 24)
	self.resultBody.Font = FONT_BODY
	self.resultBody.TextYAlignment = Enum.TextYAlignment.Top

	self.nextButton =
		makeButton(results, "Next level", UDim2.fromOffset(200, 56), UDim2.new(0.5, -210, 1, -150), THEME.accent)
	self.retryButton =
		makeButton(results, "Retry", UDim2.fromOffset(200, 56), UDim2.new(0.5, 10, 1, -150), THEME.panelLight)
	local menuButton =
		makeButton(results, "Menu", UDim2.fromOffset(200, 50), UDim2.new(0.5, -100, 1, -80), THEME.panelLight)

	self.nextButton.Activated:Connect(function()
		self.callbacks.onPlay(self.lastResultLevel + 1)
	end)
	self.retryButton.Activated:Connect(function()
		self.callbacks.onPlay(self.lastResultLevel)
	end)
	menuButton.Activated:Connect(function()
		self.callbacks.onMenu()
	end)
end

function HudController.new(playerGui: PlayerGui, levels: { Level }, callbacks: Callbacks, touch: boolean): HudController
	local gui = Instance.new("ScreenGui")
	gui.Name = "GateZillionHud"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets

	local self = setmetatable(
		{
			gui = gui,
			callbacks = callbacks,
			levels = levels,
			profile = nil,
			selected = 1,
			touch = touch,
			levelButtons = {},
			lastResultLevel = 1,
		} :: any,
		HudController
	) :: Self

	local scale = Instance.new("UIScale")
	scale.Parent = gui
	local function rescale()
		local camera = workspace.CurrentCamera
		if camera then
			local size = camera.ViewportSize
			scale.Scale = math.clamp(math.min(size.Y / DESIGN_HEIGHT, size.X / 680), 0.45, 1.5)
		end
	end
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	end
	rescale()

	buildLobby(self)
	buildRun(self)
	buildResults(self)

	self.status = makeLabel(gui, "", UDim2.new(1, 0, 0, 30), UDim2.new(0, 0, 1, -40), 22)
	textStroke(self.status, 2)

	gui.Parent = playerGui
	return (self :: any) :: HudController
end

function HudController.refreshLobby(self: Self)
	local profile = self.profile
	for index, entry in self.levelButtons do
		local level = self.levels[index]
		local unlocked = profile ~= nil and level.id <= profile.highestUnlockedLevel
		local best = if profile then profile.bestScores[tostring(level.id)] else nil
		entry.button.BackgroundColor3 = if unlocked then THEME.panelLight else THEME.locked
		entry.button.AutoButtonColor = unlocked
		entry.detail.Text = if not unlocked then "Locked" elseif best then `Best {formatCount(best)}` else "New"
		entry.stroke.Thickness = if level.id == self.selected then 3 else 0
	end
	self.pointsLabel.Text = if profile then `Points: {formatCount(profile.earnedPoints)}` else "Loading profile..."
	self.playButton.Text = `Play level {self.selected}`
end

function HudController.setProfile(self: Self, view: Protocol.ProfileView)
	local first = self.profile == nil
	self.profile = view
	if first or self.selected > view.highestUnlockedLevel then
		self.selected = math.clamp(view.highestUnlockedLevel, 1, #self.levels)
		self.callbacks.onSelect(self.selected)
	end
	HudController.refreshLobby(self)
end

function HudController.selectedLevel(self: Self): number
	return self.selected
end

function HudController.showLobby(self: Self)
	self.run.Visible = false
	self.results.Visible = false
	self.lobby.Visible = true
	HudController.refreshLobby(self)
end

function HudController.showRun(self: Self, level: Level)
	self.lobby.Visible = false
	self.results.Visible = false
	self.run.Visible = true
	self.levelName.Text = `{level.id}. {level.name}`
	self.progressFill.Size = UDim2.fromScale(0, 1)
	self.deltaLabel.TextTransparency = 1
	self.hintLabel.Visible = true
end

function HudController.updateRun(self: Self, progress: number, groupCount: number, countdown: number?)
	self.progressFill.Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1)
	self.countLabel.Text = formatCount(groupCount)
	if countdown and countdown > 0 then
		self.countdownLabel.Text = tostring(math.ceil(countdown))
		self.countdownLabel.Visible = true
	elseif countdown or progress < 0.03 then
		self.countdownLabel.Text = "GO!"
		self.countdownLabel.Visible = true
	else
		self.countdownLabel.Visible = false
	end
	self.hintLabel.Visible = progress < 0.08
end

function HudController.showDelta(self: Self, before: number, after: number)
	local delta = after - before
	if delta == 0 then
		return
	end
	local label = self.deltaLabel
	label.Text = if delta > 0 then `+{formatCount(delta)}` else `-{formatCount(-delta)}`
	label.TextColor3 = if delta > 0 then THEME.good else THEME.bad
	label.TextTransparency = 0
	TweenService:Create(label, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextTransparency = 1,
	}):Play()
end

local FAIL_TITLES: { [string]: string } = {
	groupLost = "Group lost!",
	tooFew = "Not enough made it!",
}

function HudController.showResults(self: Self, payload: Protocol.RunEnded, level: Level, hasNextLevel: boolean)
	self.lastResultLevel = level.id
	self.run.Visible = false
	self.results.Visible = true

	local completed = payload.result == "Completed"
	self.resultTitle.Text = if completed then "Level complete!" else FAIL_TITLES[payload.reason or ""] or "Run failed"
	self.resultTitle.TextColor3 = if completed then THEME.good else THEME.bad

	local lines = { `{level.id}. {level.name}`, `Final group: {formatCount(payload.finalCount)}` }
	if completed then
		table.insert(lines, `Stars: {payload.stars} / 3`)
		table.insert(lines, `+{formatCount(payload.earnedPoints)} points`)
		if payload.newBest then
			table.insert(lines, "New best!")
		end
		if payload.unlockedLevel then
			table.insert(lines, `Level {payload.unlockedLevel} unlocked!`)
		end
	else
		table.insert(lines, "Pick better gates and try again.")
	end
	self.resultBody.Text = table.concat(lines, "\n")

	local profile = self.profile
	local nextUnlocked = profile ~= nil and level.id + 1 <= profile.highestUnlockedLevel
	self.nextButton.Visible = hasNextLevel and (nextUnlocked or payload.unlockedLevel ~= nil)
	self.retryButton.Position = if self.nextButton.Visible
		then UDim2.new(0.5, 10, 1, -150)
		else UDim2.new(0.5, -100, 1, -150)
end

function HudController.setStatus(self: Self, text: string?)
	self.status.Text = text or ""
	self.status.Visible = text ~= nil
end

return HudController
