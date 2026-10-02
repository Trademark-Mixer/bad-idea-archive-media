--[[
	Client  (LocalScript inside StarterPlayer > StarterPlayerScripts)

	Runs on each player's own computer:
	  * the screen UI (coins, backpack, shop, rebirth, teleport, quests, gifts, daily rewards)
	  * clicking crystals to mine them
	  * pets following you, spinning decorations, sparkles, sounds and music
	  * changing the sky and colors in every zone
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local StarterGui = game:GetService("StarterGui")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local Shared = require(ReplicatedStorage:WaitForChild("GameShared"))
local Settings = Shared.Settings
local Format = Shared.Format

local RemoteFolder = ReplicatedStorage:WaitForChild("Remotes")
local R: { [string]: RemoteEvent } = {}
for _, name in ipairs({ "Mine", "Buy", "Rebirth", "Teleport", "Sync", "Notify", "Effect", "OpenMenu", "EnterDimension", "GoSell", "Claim", "Dig", "Hatch", "GadgetToggle", "Swing", "Spin" }) do
	R[name] = RemoteFolder:WaitForChild(name) :: RemoteEvent
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = Workspace.CurrentCamera

Workspace:WaitForChild("Crystals")
local PetFolder = Workspace:WaitForChild("Pets")
local GateFolder = Workspace:WaitForChild("Gates")
local SellFolder = Workspace:WaitForChild("SellPads")
local WallFolder = Workspace:WaitForChild("Walls")
-- flying gems, rock chips and shards live here (only on this player's screen)
local FxFolder = Instance.new("Folder")
FxFolder.Name = "LocalEffects"
FxFolder.Parent = Workspace

-- The tool bar at the bottom: 1 = pickaxe, 2 = shovel (click again to put it away)
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, true)
end)

type State = {
	Coins: number,
	Gems: number,
	Capacity: number,
	Rebirths: number,
	Pickaxe: number,
	Backpack: number,
	Zone: number,
	Pets: { number }, -- Pets[n] = how many of pet n you own
	TotalGems: number,
	Hatched: number,
	Level: number,
	XP: number,
	FreeEggs: number,
	Quest: { Kind: string, Target: number, Progress: number },
	QuestsDone: number,
	Played: number, -- seconds you have played since you joined
	Gifts: { boolean }, -- which free gifts you already claimed
	DailyReady: boolean,
	DailyStreak: number,
	ObbyBest: number,
	ObbyWait: number, -- seconds until the obby pays out again
	DimObbyWaits: { [string]: number }?, -- ["3"] = seconds until dimension 3's obby pays again
	WheelWait: number, -- seconds until the next free spin of the lucky wheel
	BoostWait: number, -- seconds of 2x gems left
	ChestsFound: number,
	MeteorsBroken: number,
	DimPets: { { Index: number, Count: number } }, -- pets from dimension eggs
	Shards: number, -- 💠 Boss Shards
	BossesBeaten: number,
	DimPickaxe: number,
	DimBackpack: number,
	Gadgets: { number },
	GadgetsOff: { number },
}
local state: State? = nil
local syncedAt = 0 -- when the last state arrived (os.clock)
local ownedPets: { [number]: number } = {} -- [pet number] = how many you own
local equippedPets: { [number]: number } = {} -- [pet number] = how many are following you

--------------------------------------------------------------------------------
-- SOUNDS (built-in Roblox sounds, played at different pitches)
--------------------------------------------------------------------------------
local SOUND_IDS = {
	Click = "rbxasset://sounds/volume_slider.ogg",
	Hit = "rbxasset://sounds/action_jump_land.mp3",
	Boom = "rbxasset://sounds/impact_explosion_03.mp3",
	Splash = "rbxasset://sounds/impact_water.mp3",
}
local soundTemplates: { [string]: Sound } = {}

local function playSound(name: string, speed: number?, volume: number?)
	local template = soundTemplates[name]
	if not template then
		template = Instance.new("Sound")
		template.SoundId = SOUND_IDS[name]
		soundTemplates[name] = template
	end
	local sound = template:Clone()
	sound.PlaybackSpeed = speed or 1
	sound.Volume = volume or 0.5
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, 4)
end

-- A quick rising "ding-ding-ding" for coins and purchases
local function chime(notes: number?, baseSpeed: number?)
	for i = 0, (notes or 5) - 1 do
		task.delay(i * 0.06, function()
			playSound("Click", (baseSpeed or 1) + i * 0.22, 0.7)
		end)
	end
end

--------------------------------------------------------------------------------
-- UI HELPERS
--------------------------------------------------------------------------------
local FONT = Enum.Font.FredokaOne
local WHITE = Color3.new(1, 1, 1)
local DARK = Color3.fromRGB(30, 32, 52)
local OUTLINE = Color3.fromRGB(18, 18, 30)

local COLORS = {
	Green = { Color3.fromRGB(110, 235, 120), Color3.fromRGB(40, 165, 70) },
	Blue = { Color3.fromRGB(100, 190, 255), Color3.fromRGB(40, 110, 230) },
	Purple = { Color3.fromRGB(205, 130, 255), Color3.fromRGB(125, 55, 220) },
	Gold = { Color3.fromRGB(255, 220, 70), Color3.fromRGB(255, 150, 20) },
	Red = { Color3.fromRGB(255, 110, 110), Color3.fromRGB(205, 40, 60) },
	Gray = { Color3.fromRGB(150, 155, 170), Color3.fromRGB(90, 95, 115) },
	Cyan = { Color3.fromRGB(110, 240, 255), Color3.fromRGB(40, 140, 255) },
	Pink = { Color3.fromRGB(255, 140, 225), Color3.fromRGB(200, 60, 200) },
	Galaxy = { Color3.fromRGB(150, 110, 255), Color3.fromRGB(60, 40, 180) },
}

local function new(className: string, props: { [string]: any }): any
	local inst = Instance.new(className)
	local parent = nil
	for key, value in pairs(props) do
		if key == "Parent" then
			parent = value
		else
			(inst :: any)[key] = value
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function round(obj: Instance, radius: number?)
	new("UICorner", { CornerRadius = UDim.new(0, radius or 12), Parent = obj })
end

local function outline(obj: Instance, thickness: number?): UIStroke
	return new("UIStroke", {
		Thickness = thickness or 3,
		Color = OUTLINE,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = obj,
	})
end

local function gradient(obj: Instance, colors: { Color3 }): UIGradient
	return new("UIGradient", { Color = ColorSequence.new(colors[1], colors[2]), Rotation = 90, Parent = obj })
end

local function label(props: { [string]: any }): TextLabel
	local strokeSize = props.Stroke
	props.Stroke = nil
	if props.BackgroundTransparency == nil then
		props.BackgroundTransparency = 1
	end
	if props.TextScaled == nil then
		props.TextScaled = true
	end
	props.Font = props.Font or FONT
	props.TextColor3 = props.TextColor3 or WHITE
	local lbl = new("TextLabel", props)
	if strokeSize ~= 0 then
		new("UIStroke", { Thickness = strokeSize or 2.5, Color = OUTLINE, Parent = lbl })
	end
	return lbl
end

local function tween(obj: Instance, time: number, goal: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
	local t = TweenService:Create(obj, TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end

local function pop(scale: UIScale, amount: number?)
	scale.Scale = amount or 1.15
	tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
end

type ButtonProps = {
	Size: UDim2,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	LayoutOrder: number?,
	Text: string?,
	Colors: { Color3 },
	Radius: number?,
	OnClick: (() -> ())?,
	Parent: Instance,
}

local function button(props: ButtonProps): (TextButton, TextLabel, UIGradient)
	local btn: TextButton = new("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = WHITE,
		Size = props.Size,
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		Parent = props.Parent,
	})
	round(btn, props.Radius or 12)
	outline(btn, 3)
	local grad = gradient(btn, props.Colors)
	local lbl = label({
		Text = props.Text or "",
		Size = UDim2.fromScale(0.88, 0.72),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = btn,
	})
	local scale: UIScale = new("UIScale", { Parent = btn })
	btn.MouseEnter:Connect(function()
		tween(scale, 0.12, { Scale = 1.06 })
	end)
	btn.MouseLeave:Connect(function()
		tween(scale, 0.12, { Scale = 1 })
	end)
	btn.MouseButton1Down:Connect(function()
		tween(scale, 0.06, { Scale = 0.93 })
	end)
	btn.MouseButton1Up:Connect(function()
		tween(scale, 0.12, { Scale = 1 })
	end)
	local onClick = props.OnClick
	if onClick then
		btn.Activated:Connect(function()
			playSound("Click", 1.3, 0.6)
			onClick()
		end)
	end
	return btn, lbl, grad
end

local function setColors(grad: UIGradient, colors: { Color3 })
	grad.Color = ColorSequence.new(colors[1], colors[2])
end

-- Moves a whole model every frame. It remembers where each part sits compared
-- to the model's pivot, which is smoother and cheaper than PivotTo each frame.
local modelOffsets: { [Model]: { [BasePart]: CFrame } } = setmetatable({}, { __mode = "k" }) :: any
local function placeModel(m: Model, cframe: CFrame)
	local offsets = modelOffsets[m]
	if offsets then
		-- parts can be swapped out (for example by streaming); start fresh if so
		for p in pairs(offsets) do
			if p.Parent == nil then
				offsets = nil
				break
			end
		end
	end
	if not offsets then
		local newOffsets = {}
		local pivot = m:GetPivot()
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") then
				newOffsets[d] = pivot:ToObjectSpace(d.CFrame)
			end
		end
		modelOffsets[m] = newOffsets
		offsets = newOffsets
	end
	for p, offset in pairs(offsets) do
		p.CFrame = cframe * offset
	end
end

-- Turns a model around its MIDDLE (its pivot can be at one end, which makes it wobble).
-- base = where the model sits when it is not turned. lift moves it up, tilt leans it a bit.
local modelCenters: { [Model]: Vector3 } = setmetatable({}, { __mode = "k" }) :: any
local function turnModel(m: Model, base: CFrame, yaw: number, lift: number?, tiltX: number?, tiltZ: number?)
	local offset = modelCenters[m]
	if not offset then
		local box = m:GetBoundingBox()
		offset = m:GetPivot():PointToObjectSpace(box.Position)
		modelCenters[m] = offset
	end
	local center = base * offset
	local turn = CFrame.new(center + Vector3.new(0, lift or 0, 0)) * CFrame.Angles(tiltX or 0, yaw, tiltZ or 0) * CFrame.new(-center)
	placeModel(m, turn * base)
end

-- Everything scales with the screen size (so it fits phones too)
local scalers: { UIScale } = {}
local function autoScale(obj: Instance)
	table.insert(scalers, new("UIScale", { Parent = obj }))
end
local function updateScale()
	local size = camera.ViewportSize
	local s = math.clamp(math.min(size.X / 1280, size.Y / 760), 0.5, 1.25)
	for _, scaler in ipairs(scalers) do
		scaler.Scale = s
	end
end

--------------------------------------------------------------------------------
-- MUSIC (your songs from Settings.MusicIds, or a calm little music box)
--------------------------------------------------------------------------------
local music = { On = true }
local setMusic: (on: boolean) -> ()
do
	local musicGroup: SoundGroup = new("SoundGroup", { Name = "CrystalRushMusic", Volume = Settings.MusicVolume, Parent = SoundService })
	new("ReverbSoundEffect", { DecayTime = 2.4, Density = 0.9, Diffusion = 1, DryLevel = -3, WetLevel = -7, Parent = musicGroup })
	new("EqualizerSoundEffect", { HighGain = -9, MidGain = -2, LowGain = 2, Parent = musicGroup })
	setMusic = function(on: boolean)
		music.On = on
		tween(musicGroup, 0.6, { Volume = if on then Settings.MusicVolume else 0 })
	end

	-- The music box: chords C, Am, F, G as little arpeggios, with a slow tune on top.
	-- Numbers are notes (12 = one octave higher).
	local MUSIC_CHORDS = {
		{ 0, 4, 7, 12, 7, 4, 7, 4 },
		{ -3, 0, 4, 9, 4, 0, 4, 0 },
		{ -7, -3, 0, 5, 0, -3, 0, -3 },
		{ -5, -1, 2, 7, 2, -1, 2, -1 },
	}
	local MUSIC_TUNE: { { [number]: number } } = {
		{ [1] = 16, [5] = 14 },
		{ [1] = 12, [5] = 16 },
		{ [1] = 17, [5] = 16, [7] = 14 },
		{ [1] = 14, [5] = 11 },
	}

	local function musicNote(note: number, volume: number)
		local template = soundTemplates.Click
		if not template then
			playSound("Click", 1, 0)
			template = soundTemplates.Click
		end
		local sound = template:Clone()
		sound.PlaybackSpeed = 0.75 * 2 ^ (note / 12)
		sound.Volume = volume
		sound.SoundGroup = musicGroup
		sound.Parent = SoundService
		sound:Play()
		Debris:AddItem(sound, 3)
	end

	local function playMusicBox()
		local loops = 0
		while true do
			for bar, chord in ipairs(MUSIC_CHORDS) do
				for k, note in ipairs(chord) do
					if music.On then
						musicNote(note, 0.22)
						local tune = MUSIC_TUNE[bar][k]
						if tune then
							musicNote(tune, 0.34)
						end
					end
					task.wait(0.36)
				end
			end
			loops += 1
			if loops % 2 == 0 then
				task.wait(5) -- a little quiet time
			end
		end
	end

	local function playSongs(ids: { number })
		local i = 0
		while true do
			i = i % #ids + 1
			local song = new("Sound", {
				Name = "Song",
				SoundId = "rbxassetid://" .. tostring(ids[i]),
				Volume = 1,
				SoundGroup = musicGroup,
				Parent = SoundService,
			})
			song:Play()
			local started = os.clock()
			repeat
				task.wait(1)
				local elapsed = os.clock() - started
				local finished = song.TimeLength > 0 and not song.IsPlaying and elapsed > 2
				local broken = song.TimeLength == 0 and elapsed > 12 -- the song didn't load
			until finished or broken or elapsed > 900
			song:Destroy()
		end
	end

	task.spawn(function()
		task.wait(2)
		local ids = Settings.MusicIds
		if type(ids) == "table" and #ids > 0 then
			playSongs(ids)
		else
			playMusicBox()
		end
	end)
end

--------------------------------------------------------------------------------
-- SCREEN GUIS
--------------------------------------------------------------------------------
for _, oldName in ipairs({ "CrystalRushGui", "CrystalRushFX" }) do
	local oldGui = playerGui:FindFirstChild(oldName)
	if oldGui then
		oldGui:Destroy()
	end
end
local gui = new("ScreenGui", {
	Name = "CrystalRushGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = playerGui,
})
local fxGui = new("ScreenGui", {
	Name = "CrystalRushFX",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 5,
	Parent = playerGui,
})

--------------------------------------------------------------------------------
-- HUD (left side)
--------------------------------------------------------------------------------
local hud = new("Frame", {
	Name = "HUD",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 16, 0.5, 0),
	Size = UDim2.fromOffset(250, 450),
	BackgroundTransparency = 1,
	Parent = gui,
})
autoScale(hud)
new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = hud })

-- Coins
local coinsPill = new("Frame", { Size = UDim2.fromOffset(250, 60), BackgroundColor3 = WHITE, LayoutOrder = 1, Parent = hud })
round(coinsPill, 16)
outline(coinsPill, 3)
gradient(coinsPill, COLORS.Gold)
label({ Text = "💰", Size = UDim2.fromOffset(48, 48), Position = UDim2.new(0, 8, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Stroke = 0, Parent = coinsPill })
local coinsText = label({
	Text = "0",
	Size = UDim2.new(1, -74, 0.7, 0),
	Position = UDim2.new(0, 62, 0.5, 0),
	AnchorPoint = Vector2.new(0, 0.5),
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = coinsPill,
})
local coinsPop: UIScale = new("UIScale", { Parent = coinsPill })

-- Gems / backpack
local gemsPill = new("Frame", { Size = UDim2.fromOffset(250, 60), BackgroundColor3 = DARK, LayoutOrder = 2, Parent = hud })
round(gemsPill, 16)
outline(gemsPill, 3)
local gemsFill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = WHITE, Parent = gemsPill })
round(gemsFill, 16)
local gemsFillGrad = gradient(gemsFill, COLORS.Cyan)
label({ Text = "💎", Size = UDim2.fromOffset(46, 46), Position = UDim2.new(0, 9, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Stroke = 0, Parent = gemsPill })
local gemsText = label({
	Text = "0 / 25",
	Size = UDim2.new(1, -74, 0.62, 0),
	Position = UDim2.new(0, 62, 0.5, 0),
	AnchorPoint = Vector2.new(0, 0.5),
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = gemsPill,
})
local gemsPop: UIScale = new("UIScale", { Parent = gemsPill })

-- Level and XP bar
local levelPill = new("Frame", { Size = UDim2.fromOffset(250, 48), BackgroundColor3 = DARK, LayoutOrder = 3, Parent = hud })
round(levelPill, 14)
outline(levelPill, 3)
local levelFill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = WHITE, Parent = levelPill })
round(levelFill, 14)
gradient(levelFill, COLORS.Pink)
local levelText = label({
	Text = "⭐ Level 1",
	Size = UDim2.new(0.5, -10, 0.62, 0),
	Position = UDim2.new(0, 10, 0.5, 0),
	AnchorPoint = Vector2.new(0, 0.5),
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = levelPill,
})
local xpText = label({
	Text = "0 / 60 XP",
	Size = UDim2.new(0.5, -14, 0.5, 0),
	Position = UDim2.new(1, -10, 0.5, 0),
	AnchorPoint = Vector2.new(1, 0.5),
	TextXAlignment = Enum.TextXAlignment.Right,
	Parent = levelPill,
})
local levelPop: UIScale = new("UIScale", { Parent = levelPill })

-- Rebirths and boosts
local boostPill = new("Frame", { Size = UDim2.fromOffset(250, 44), BackgroundColor3 = WHITE, LayoutOrder = 4, Parent = hud })
round(boostPill, 14)
outline(boostPill, 3)
gradient(boostPill, COLORS.Purple)
local boostText = label({
	Text = "⭐ 0 Rebirths",
	Size = UDim2.new(1, -20, 0.62, 0),
	Position = UDim2.fromScale(0.5, 0.5),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Parent = boostPill,
})

-- Menu buttons (2 rows of 2)
local menuGrid = new("Frame", { Size = UDim2.fromOffset(250, 128), BackgroundTransparency = 1, LayoutOrder = 5, Parent = hud })
new("UIGridLayout", {
	CellSize = UDim2.fromOffset(119, 58),
	CellPadding = UDim2.fromOffset(12, 12),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = menuGrid,
})

local openWindow: (name: string, keepOpen: boolean?) -> ()
local openShop: (category: string?) -> ()
local refreshExtras: () -> ()

local function menuButton(order: number, emoji: string, caption: string, colors: { Color3 }, windowName: string)
	button({
		Size = UDim2.fromOffset(119, 58),
		Text = emoji .. " " .. caption,
		Colors = colors,
		Radius = 16,
		LayoutOrder = order,
		Parent = menuGrid,
		OnClick = function()
			if windowName == "Shop" then
				openShop(nil)
			else
				openWindow(windowName)
			end
		end,
	})
end
menuButton(1, "🛒", "Shop", COLORS.Green, "Shop")
menuButton(2, "🐾", "Pets", COLORS.Gold, "Pets")
menuButton(3, "🌀", "Teleport", COLORS.Blue, "Teleport")
menuButton(4, "♻️", "Rebirth", COLORS.Purple, "Rebirth")
button({
	Size = UDim2.fromOffset(250, 56),
	Text = "🌌 DIMENSIONS",
	Colors = COLORS.Galaxy,
	Radius = 16,
	LayoutOrder = 6,
	Parent = hud,
	OnClick = function()
		openWindow("Dimensions")
	end,
})

--------------------------------------------------------------------------------
-- RIGHT SIDE: QUEST, FREE GIFTS, DAILY REWARD, OBBY, MUSIC
--------------------------------------------------------------------------------
local clockText: (seconds: number) -> string
local playedSeconds: () -> number
local obbyWait: (d: number?) -> number
local obbyReward: (d: number?) -> number
local refreshSide: () -> ()
local questPop: UIScale
local obbyState = { Checkpoint = 0 }
do
	clockText = function(seconds: number): string
		local s = math.max(0, math.ceil(seconds))
		if s >= 3600 then
			return string.format("%d:%02d:%02d", s // 3600, (s // 60) % 60, s % 60)
		end
		return string.format("%d:%02d", s // 60, s % 60)
	end

	local side = new("Frame", {
		Name = "SidePanel",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.45, 0),
		Size = UDim2.fromOffset(240, 440),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	autoScale(side)
	new("UIListLayout", {
		Padding = UDim.new(0, 10),
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = side,
	})

	-- Quest tracker
	local questCard = new("Frame", { Name = "Quest", Size = UDim2.fromOffset(240, 114), BackgroundColor3 = DARK, LayoutOrder = 1, Parent = side })
	round(questCard, 16)
	outline(questCard, 3)
	label({
		Text = "📜 QUEST",
		Size = UDim2.new(1, -20, 0, 22),
		Position = UDim2.fromOffset(10, 8),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(255, 215, 110),
		Parent = questCard,
	})
	local questText = label({
		Text = "",
		Size = UDim2.new(1, -20, 0, 24),
		Position = UDim2.fromOffset(10, 32),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = questCard,
	})
	local questBar = new("Frame", { Size = UDim2.new(1, -20, 0, 22), Position = UDim2.fromOffset(10, 61), BackgroundColor3 = Color3.fromRGB(18, 18, 30), Parent = questCard })
	round(questBar, 11)
	local questFill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = WHITE, Parent = questBar })
	round(questFill, 11)
	gradient(questFill, COLORS.Green)
	local questCount = label({
		Text = "0 / 0",
		Size = UDim2.fromScale(1, 0.78),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = questBar,
	})
	local questReward = label({
		Text = "",
		Size = UDim2.new(1, -20, 0, 18),
		Position = UDim2.fromOffset(10, 89),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(205, 210, 230),
		Stroke = 0,
		Parent = questCard,
	})
	questPop = new("UIScale", { Parent = questCard })

	-- A little red "!" that wiggles when something is ready
	local function badge(parent: Instance): TextLabel
		local b = label({
			Name = "Badge",
			Text = "!",
			Size = UDim2.fromOffset(28, 28),
			Position = UDim2.new(1, 6, 0, -8),
			AnchorPoint = Vector2.new(1, 0),
			BackgroundTransparency = 0,
			BackgroundColor3 = Color3.fromRGB(235, 60, 70),
			Visible = false,
			ZIndex = 3,
			Parent = parent,
		})
		round(b, 14)
		return b
	end

	local giftButton, giftLabel, giftGrad = button({
		Size = UDim2.fromOffset(240, 54),
		Text = "🎁 Free gift",
		Colors = COLORS.Pink,
		Radius = 16,
		LayoutOrder = 2,
		Parent = side,
		OnClick = function()
			openWindow("Gifts")
		end,
	})
	local giftBadge = badge(giftButton)

	local dailyButton, dailyLabel, dailyGrad = button({
		Size = UDim2.fromOffset(240, 54),
		Text = "📅 Daily reward",
		Colors = COLORS.Blue,
		Radius = 16,
		LayoutOrder = 3,
		Parent = side,
		OnClick = function()
			openWindow("Daily")
		end,
	})
	local dailyBadge = badge(dailyButton)

	local obbyPill = new("Frame", { Name = "ObbyInfo", Size = UDim2.fromOffset(240, 44), BackgroundColor3 = DARK, LayoutOrder = 4, Parent = side })
	round(obbyPill, 14)
	outline(obbyPill, 3)
	local obbyInfo = label({
		Text = "🏃 Sky Obby",
		Size = UDim2.new(1, -20, 0.6, 0),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = obbyPill,
	})

	local eggsPill = new("Frame", { Name = "FreeEggs", Size = UDim2.fromOffset(240, 40), BackgroundColor3 = WHITE, LayoutOrder = 5, Visible = false, Parent = side })
	round(eggsPill, 14)
	outline(eggsPill, 3)
	gradient(eggsPill, COLORS.Gold)
	local eggsText = label({
		Text = "",
		Size = UDim2.new(1, -20, 0.62, 0),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = eggsPill,
	})

	local musicLabel: TextLabel
	_, musicLabel = button({
		Size = UDim2.fromOffset(240, 44),
		Text = "🔊 Music: ON",
		Colors = COLORS.Gray,
		Radius = 14,
		LayoutOrder = 6,
		Parent = side,
		OnClick = function()
			setMusic(not music.On)
			musicLabel.Text = if music.On then "🔊 Music: ON" else "🔇 Music: OFF"
		end,
	})

	-- How long you have played (the server tells us, and we keep counting)
	playedSeconds = function(): number
		local s = state
		if not s then
			return 0
		end
		return s.Played + (os.clock() - syncedAt)
	end

	local function giftsReady(): (number, number?)
		local s = state
		if not s then
			return 0, nil
		end
		local ready, nextIn = 0, nil
		local played = playedSeconds()
		for i, gift in ipairs(Shared.Gifts) do
			if not s.Gifts[i] then
				local left = gift.Minutes * 60 - played
				if left <= 0 then
					ready += 1
				elseif not nextIn or left < nextIn then
					nextIn = left
				end
			end
		end
		return ready, nextIn
	end

	-- seconds until an obby pays out again (d = nil is the one at the spawn)
	obbyWait = function(d: number?): number
		local s = state
		if not s then
			return 0
		end
		local wait = if d then (s.DimObbyWaits or {})[tostring(d)] or 0 else s.ObbyWait
		return math.max(0, wait - (os.clock() - syncedAt))
	end

	-- how many coins an obby pays you
	obbyReward = function(d: number?): number
		local s = state
		if not s then
			return 0
		end
		local view: any = table.clone(s)
		view.Pets = ownedPets -- dimension pets count too
		return if d then Shared.DimensionObbyReward(view, d) else Shared.ObbyReward(view)
	end

	refreshSide = function()
		local s = state
		if not s then
			return
		end
		-- quest
		local quest = s.Quest
		questText.Text = Shared.QuestText(quest)
		questCount.Text = Format(quest.Progress) .. " / " .. Format(quest.Target)
		tween(questFill, 0.3, { Size = UDim2.fromScale(math.clamp(quest.Progress / quest.Target, 0, 1), 1) })
		local coins, xp = Shared.QuestReward(s, s.QuestsDone)
		questReward.Text = "Reward: 💰 " .. Format(coins) .. "  ⭐ " .. Format(xp) .. " XP"
		-- gifts
		local ready, nextIn = giftsReady()
		giftBadge.Visible = ready > 0
		if ready > 0 then
			giftLabel.Text = if ready > 1 then "🎁 " .. ready .. " GIFTS READY!" else "🎁 GIFT READY!"
			setColors(giftGrad, COLORS.Gold)
		elseif nextIn then
			giftLabel.Text = "🎁 Gift in " .. clockText(nextIn)
			setColors(giftGrad, COLORS.Pink)
		else
			giftLabel.Text = "🎁 All gifts claimed!"
			setColors(giftGrad, COLORS.Gray)
		end
		-- daily
		dailyBadge.Visible = s.DailyReady
		dailyLabel.Text = if s.DailyReady then "📅 DAILY REWARD!" else "📅 Daily: day " .. s.DailyStreak .. " 🔥"
		setColors(dailyGrad, if s.DailyReady then COLORS.Gold else COLORS.Blue)
		-- obby
		local here = player:GetAttribute("Dimension")
		local d = if type(here) == "number" then here else nil
		local wait = obbyWait(d)
		local name = if d then "Dimension obby" else "Sky Obby"
		obbyInfo.Text = if wait > 0 then "🏃 " .. name .. " reward in " .. clockText(wait) else "🏃 " .. name .. ": win 💰 " .. Format(obbyReward(d))
		-- free eggs
		eggsPill.Visible = s.FreeEggs > 0
		eggsText.Text = "🥚 " .. s.FreeEggs .. " FREE " .. (if s.FreeEggs == 1 then "egg" else "eggs") .. "! Hatch 1 to use"
	end

	-- Obby timer (top of the screen while you do the sky obby)
	local obbyHud = new("Frame", {
		Name = "ObbyHud",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 64),
		Size = UDim2.fromOffset(380, 62),
		BackgroundColor3 = DARK,
		Visible = false,
		Parent = gui,
	})
	autoScale(obbyHud)
	round(obbyHud, 18)
	outline(obbyHud, 3)
	local obbyTime = label({
		Text = "🏃 0:00.0",
		Size = UDim2.new(0, 160, 0, 38),
		Position = UDim2.new(0, 14, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = obbyHud,
	})
	local obbyFlags = label({
		Text = "🚩 0/3",
		Size = UDim2.new(0, 84, 0, 30),
		Position = UDim2.new(0, 180, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		TextColor3 = Color3.fromRGB(255, 200, 190),
		Parent = obbyHud,
	})
	button({
		Size = UDim2.fromOffset(96, 44),
		Position = UDim2.new(1, -10, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Text = "✖ Quit",
		Colors = COLORS.Red,
		Radius = 12,
		Parent = obbyHud,
		OnClick = function()
			R.Teleport:FireServer(0)
		end,
	})

	-- every frame: wiggle the "!" badges and run the obby timer
	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		giftBadge.Rotation = math.sin(t * 7) * 12
		dailyBadge.Rotation = math.sin(t * 7 + 1) * 12
		local obbyStart = player:GetAttribute("ObbyStart")
		if type(obbyStart) == "number" then
			local elapsed = math.max(0, Workspace:GetServerTimeNow() - obbyStart)
			obbyHud.Visible = true
			obbyTime.Text = string.format("🏃 %d:%04.1f", elapsed // 60, elapsed % 60)
			obbyFlags.Text = "🚩 " .. obbyState.Checkpoint .. "/3"
		else
			obbyHud.Visible = false
		end
	end)
end

--------------------------------------------------------------------------------
-- TOASTS (little messages at the bottom), BANNERS AND WARNINGS
--------------------------------------------------------------------------------
local toastHolder = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -96),
	Size = UDim2.fromOffset(520, 230),
	BackgroundTransparency = 1,
	ZIndex = 3,
	Parent = gui,
})
autoScale(toastHolder)
new("UIListLayout", {
	VerticalAlignment = Enum.VerticalAlignment.Bottom,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	Padding = UDim.new(0, 8),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = toastHolder,
})

local TOAST_COLORS = { good = COLORS.Green, bad = COLORS.Red, info = COLORS.Blue, gold = COLORS.Gold }
local toastCount = 0

local function toast(message: string, kind: string?)
	toastCount += 1
	local frame = new("Frame", {
		Size = UDim2.fromOffset(500, 46),
		BackgroundColor3 = WHITE,
		LayoutOrder = toastCount,
		Parent = toastHolder,
	})
	round(frame, 14)
	local stroke = outline(frame, 3)
	gradient(frame, TOAST_COLORS[kind or "info"] or COLORS.Blue)
	local text = label({
		Text = message,
		Size = UDim2.new(1, -24, 0.68, 0),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = frame,
	})
	local scale: UIScale = new("UIScale", { Scale = 0.6, Parent = frame })
	tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)

	-- only keep the newest 4
	local frames = {}
	for _, child in ipairs(toastHolder:GetChildren()) do
		if child:IsA("Frame") then
			table.insert(frames, child)
		end
	end
	if #frames > 4 then
		table.sort(frames, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		frames[1]:Destroy()
	end

	task.delay(3, function()
		if not frame.Parent then
			return
		end
		tween(frame, 0.4, { BackgroundTransparency = 1 })
		tween(scale, 0.4, { Scale = 0.9 })
		tween(text, 0.4, { TextTransparency = 1 })
		tween(stroke, 0.4, { Transparency = 1 })
		local textStroke = text:FindFirstChildOfClass("UIStroke")
		if textStroke then
			tween(textStroke, 0.4, { Transparency = 1 })
		end
		task.wait(0.45)
		frame:Destroy()
	end)
end

-- Big text in the middle-top of the screen
local banner = label({
	Text = "",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.2),
	Size = UDim2.fromOffset(700, 70),
	TextTransparency = 1,
	Stroke = 4,
	ZIndex = 3,
	Parent = gui,
})
autoScale(banner)
local bannerStroke = banner:FindFirstChildOfClass("UIStroke") :: UIStroke
bannerStroke.Transparency = 1
local bannerId = 0

local function showBanner(text: string, color: Color3?)
	bannerId += 1
	local myId = bannerId
	banner.Text = text
	banner.TextColor3 = color or WHITE
	banner.TextTransparency = 1
	bannerStroke.Transparency = 1
	banner.Size = UDim2.fromOffset(520, 52)
	tween(banner, 0.45, { Size = UDim2.fromOffset(700, 70) }, Enum.EasingStyle.Back)
	tween(banner, 0.3, { TextTransparency = 0 })
	tween(bannerStroke, 0.4, { Transparency = 0 })
	task.delay(2.6, function()
		if bannerId == myId then
			tween(banner, 0.6, { TextTransparency = 1 })
			tween(bannerStroke, 0.6, { Transparency = 1 })
		end
	end)
end

-- "Backpack full!" warning
local fullWarning = new("Frame", {
	Name = "FullWarning",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.3),
	Size = UDim2.fromOffset(620, 104),
	BackgroundTransparency = 1,
	Visible = false,
	Parent = gui,
})
autoScale(fullWarning)
label({
	Text = "🎒 BACKPACK FULL! Go to a 💰 SELL pad",
	Size = UDim2.new(1, 0, 0, 44),
	TextColor3 = Color3.fromRGB(255, 225, 90),
	Stroke = 3,
	Parent = fullWarning,
})
button({
	Size = UDim2.fromOffset(270, 52),
	Position = UDim2.new(0.5, 0, 0, 50),
	AnchorPoint = Vector2.new(0.5, 0),
	Text = "🌀 Teleport to Sell",
	Colors = COLORS.Gold,
	Radius = 14,
	Parent = fullWarning,
	OnClick = function()
		R.GoSell:FireServer()
	end,
})

local lastFullToast = 0
local function backpackFull()
	if os.clock() - lastFullToast > 4 then
		lastFullToast = os.clock()
		toast("🎒 Your backpack is full! Sell your gems at a 💰 SELL pad", "gold")
		playSound("Hit", 0.6, 0.5)
	end
end

--------------------------------------------------------------------------------
-- WINDOWS (Shop, Teleport, Rebirth)
--------------------------------------------------------------------------------
type Window = { Holder: Frame, Pop: UIScale, Body: Frame, Title: TextLabel, OnOpen: (() -> ())? }
local windows: { [string]: Window } = {}
local openName: string? = nil

-- darkens the game behind an open window (click it to close the window)
local backdrop = new("TextButton", {
	Name = "Backdrop",
	Text = "",
	AutoButtonColor = false,
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(8, 8, 18),
	BackgroundTransparency = 1,
	Visible = false,
	ZIndex = 2,
	Parent = gui,
})
local backdropToken = 0

local function closeWindow()
	local name = openName
	if not name then
		return
	end
	openName = nil
	backdropToken += 1
	local token = backdropToken
	local window = windows[name]
	tween(window.Pop, 0.09, { Scale = 0.9 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	tween(backdrop, 0.15, { BackgroundTransparency = 1 })
	task.delay(0.09, function()
		if openName ~= name then
			window.Holder.Visible = false
		end
	end)
	task.delay(0.15, function()
		if token == backdropToken then
			backdrop.Visible = false
		end
	end)
end
backdrop.Activated:Connect(closeWindow)

openWindow = function(name: string, keepOpen: boolean?)
	if openName == name then
		if not keepOpen then
			closeWindow()
		end
		return
	end
	closeWindow()
	local window = windows[name]
	if not window then
		return
	end
	openName = name
	backdropToken += 1
	window.Holder.Visible = true
	window.Holder.Position = UDim2.new(0.5, 0, 0.5, 30)
	tween(window.Holder, 0.35, { Position = UDim2.fromScale(0.5, 0.5) }, Enum.EasingStyle.Quint)
	window.Pop.Scale = 0.85
	tween(window.Pop, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	backdrop.Visible = true
	tween(backdrop, 0.25, { BackgroundTransparency = 0.6 })
	if window.OnOpen then
		window.OnOpen()
	end
end

local function makeWindow(name: string, title: string, width: number, height: number, colors: { Color3 }): Window
	local holder = new("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(width, height),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 4,
		Parent = gui,
	})
	autoScale(holder)
	local panel = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = DARK, Parent = holder })
	round(panel, 22)
	outline(panel, 4)
	local popScale: UIScale = new("UIScale", { Parent = panel })

	local header = new("Frame", { Size = UDim2.new(1, 0, 0, 66), BackgroundColor3 = WHITE, Parent = panel })
	round(header, 22)
	outline(header, 3)
	gradient(header, colors)
	local titleLabel = label({
		Text = title,
		Size = UDim2.new(1, -150, 0, 46),
		Position = UDim2.new(0.5, 0, 0, 10),
		AnchorPoint = Vector2.new(0.5, 0),
		Stroke = 3,
		Parent = header,
	})
	button({
		Size = UDim2.fromOffset(52, 52),
		Position = UDim2.new(1, -8, 0, 7),
		AnchorPoint = Vector2.new(1, 0),
		Text = "✖",
		Colors = COLORS.Red,
		Radius = 14,
		Parent = header,
		OnClick = closeWindow,
	})

	local body = new("Frame", {
		Size = UDim2.new(1, -28, 1, -88),
		Position = UDim2.new(0, 14, 0, 76),
		BackgroundTransparency = 1,
		Parent = panel,
	})
	local window: Window = { Holder = holder, Pop = popScale, Body = body, Title = titleLabel }
	windows[name] = window
	return window
end

--------------------------------------------------------------------------------
-- SHOP
--------------------------------------------------------------------------------
local shop = makeWindow("Shop", "🛒 SHOP", 760, 540, COLORS.Green)

local shopTabs = new("Frame", { Size = UDim2.new(1, 0, 0, 50), BackgroundTransparency = 1, Parent = shop.Body })
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	Padding = UDim.new(0, 12),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = shopTabs,
})
local scroller = new("ScrollingFrame", {
	Size = UDim2.new(1, 0, 1, -62),
	Position = UDim2.new(0, 0, 0, 62),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 8,
	ScrollBarImageColor3 = WHITE,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	Parent = shop.Body,
})
new("UIGridLayout", {
	CellSize = UDim2.fromOffset(166, 222),
	CellPadding = UDim2.fromOffset(12, 12),
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = scroller,
})
new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 10), Parent = scroller })

type Card = {
	Category: string,
	Index: number,
	Price: number,
	Frame: Frame,
	Label: TextLabel,
	Grad: UIGradient,
	Model: Model,
	Base: CFrame,
}
local cards: { Card } = {}

local function fitCamera(cam: Camera, m: Model, direction: Vector3)
	local cf, size = m:GetBoundingBox()
	local radius = size.Magnitude / 2
	local distance = radius / math.tan(math.rad(cam.FieldOfView / 2)) * 1.05
	cam.CFrame = CFrame.lookAt(cf.Position + direction.Unit * distance, cf.Position)
end

local function makeCard(category: string, index: number, count: number, name: string, stat: string, price: number, m: Model, direction: Vector3, color: Color3?)
	local rarityColor = color or Shared.GetRarity(index, count).Color
	local frame = new("Frame", {
		Name = category .. index,
		BackgroundColor3 = WHITE,
		LayoutOrder = index,
		Visible = false,
		Parent = scroller,
	})
	round(frame, 16)
	outline(frame, 3)
	gradient(frame, { rarityColor:Lerp(WHITE, 0.15), rarityColor:Lerp(Color3.new(0, 0, 0), 0.45) })

	local viewport = new("ViewportFrame", {
		Size = UDim2.new(1, -16, 0, 104),
		Position = UDim2.fromOffset(8, 8),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.72,
		Ambient = Color3.fromRGB(190, 190, 200),
		LightColor = WHITE,
		LightDirection = Vector3.new(-1, -1, -1),
		Parent = frame,
	})
	round(viewport, 12)
	local cam = new("Camera", { FieldOfView = 34, Parent = viewport })
	viewport.CurrentCamera = cam
	m.Parent = viewport
	fitCamera(cam, m, direction)

	label({ Text = name, Size = UDim2.new(1, -12, 0, 28), Position = UDim2.fromOffset(6, 116), Parent = frame })
	label({
		Text = stat,
		Size = UDim2.new(1, -12, 0, 22),
		Position = UDim2.fromOffset(6, 145),
		TextColor3 = Color3.fromRGB(255, 240, 160),
		Parent = frame,
	})
	local _, buyLabel, buyGrad = button({
		Size = UDim2.new(1, -18, 0, 40),
		Position = UDim2.new(0.5, 0, 1, -8),
		AnchorPoint = Vector2.new(0.5, 1),
		Text = "",
		Colors = COLORS.Green,
		Parent = frame,
		OnClick = function()
			R.Buy:FireServer(category, index)
		end,
	})
	table.insert(cards, {
		Category = category,
		Index = index,
		Price = price,
		Frame = frame,
		Label = buyLabel,
		Grad = buyGrad,
		Model = m,
		Base = m:GetPivot(),
	})
end

for i, def in ipairs(Shared.Pickaxes) do
	makeCard("Pickaxe", i, #Shared.Pickaxes, def.Name, "⛏️ Power " .. Format(def.Power), def.Price, Shared.BuildPickaxe(i), Vector3.new(1, 0.2, 0.25))
end
for i, def in ipairs(Shared.Backpacks) do
	makeCard("Backpack", i, #Shared.Backpacks, def.Name, "🎒 Holds " .. Format(def.Capacity), def.Price, Shared.BuildBackpack(i), Vector3.new(0.45, 0.3, 1))
end
for i, def in ipairs(Shared.Pets) do
	if def.Price then -- egg pets are not sold in the shop
		local stat = "✨ " .. Shared.BonusText(def.Bonus) .. " Gems"
		makeCard("Pet", i, #Shared.Pets, def.Name, stat, def.Price, Shared.BuildPet(i), Vector3.new(0.35, 0.3, -1), Shared.RarityColor(def.Rarity))
	end
end

local currentTab = "Pickaxe"
local tabButtons: { [string]: UIGradient } = {}

local function refreshShop()
	local s = state
	if not s then
		return
	end
	for _, card in ipairs(cards) do
		card.Frame.Visible = card.Category == currentTab
		local owned, equipped = false, false
		if card.Category == "Pickaxe" then
			equipped = card.Index == s.Pickaxe
			owned = card.Index < s.Pickaxe
		elseif card.Category == "Backpack" then
			equipped = card.Index == s.Backpack
			owned = card.Index < s.Backpack
		else
			owned = (ownedPets[card.Index] or 0) > 0
			equipped = (equippedPets[card.Index] or 0) > 0
		end
		if equipped then
			card.Label.Text = "EQUIPPED"
			setColors(card.Grad, COLORS.Blue)
		elseif owned then
			card.Label.Text = "OWNED"
			setColors(card.Grad, COLORS.Gray)
		else
			card.Label.Text = "💰 " .. Format(card.Price)
			setColors(card.Grad, if s.Coins >= card.Price then COLORS.Green else COLORS.Red)
		end
	end
	for name, grad in pairs(tabButtons) do
		setColors(grad, if name == currentTab then COLORS.Gold else COLORS.Gray)
	end
end

for order, info in ipairs({ { "Pickaxe", "⛏️ Pickaxes" }, { "Backpack", "🎒 Backpacks" }, { "Pet", "🐾 Pets" } }) do
	local _, _, grad = button({
		Size = UDim2.fromOffset(200, 48),
		Text = info[2],
		Colors = COLORS.Gray,
		LayoutOrder = order,
		Parent = shopTabs,
		OnClick = function()
			currentTab = info[1]
			scroller.CanvasPosition = Vector2.zero
			refreshShop()
		end,
	})
	tabButtons[info[1]] = grad
end
shop.OnOpen = refreshShop

-- The shop circles open the shop on one kind of item (the HUD button shows all of them)
local SHOP_TITLES = { Pickaxe = "⛏️ PICKAXES", Backpack = "🎒 BACKPACKS", Pet = "🐾 PET SHOP" }
openShop = function(category: string?)
	shopTabs.Visible = category == nil
	scroller.Position = if category then UDim2.new() else UDim2.new(0, 0, 0, 62)
	scroller.Size = if category then UDim2.fromScale(1, 1) else UDim2.new(1, 0, 1, -62)
	shop.Title.Text = if category then SHOP_TITLES[category] else "🛒 SHOP"
	if category then
		currentTab = category
	end
	scroller.CanvasPosition = Vector2.zero
	openWindow("Shop", true)
	refreshShop()
end

--------------------------------------------------------------------------------
-- TELEPORT
--------------------------------------------------------------------------------
local teleport = makeWindow("Teleport", "🌀 TELEPORT", 460, 590, COLORS.Blue)
new("UIListLayout", {
	Padding = UDim.new(0, 10),
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = teleport.Body,
})
type TeleportButton = { Zone: number, Label: TextLabel, Grad: UIGradient }
local teleportButtons: { TeleportButton } = {}
for i = 1, #Shared.Zones + 1 do
	local zoneIndex = i - 1 -- 0 is the spawn
	local _, lbl, grad = button({
		Size = UDim2.new(1, -10, 0, 60),
		Text = "",
		Colors = COLORS.Blue,
		LayoutOrder = zoneIndex,
		Parent = teleport.Body,
		OnClick = function()
			local s = state
			if zoneIndex == 0 or (s and zoneIndex <= s.Zone) then
				R.Teleport:FireServer(zoneIndex)
				closeWindow()
			else
				toast("🔒 Unlock " .. Shared.Zones[zoneIndex].Name .. " at its gate first!", "bad")
			end
		end,
	})
	table.insert(teleportButtons, { Zone = zoneIndex, Label = lbl, Grad = grad })
end

local function refreshTeleport()
	local s = state
	for _, b in ipairs(teleportButtons) do
		if b.Zone == 0 then
			b.Label.Text = "🏠 Spawn"
			setColors(b.Grad, COLORS.Green)
		else
			local zone = Shared.Zones[b.Zone]
			local unlocked = s ~= nil and b.Zone <= s.Zone
			b.Label.Text = if unlocked then zone.Emoji .. " " .. zone.Name else "🔒 " .. zone.Name .. "  (💰 " .. Format(zone.Price) .. ")"
			setColors(b.Grad, if unlocked then COLORS.Blue else COLORS.Gray)
		end
	end
end
teleport.OnOpen = refreshTeleport
button({
	Size = UDim2.new(1, -10, 0, 60),
	Text = "🌌 Dimensions...",
	Colors = COLORS.Galaxy,
	LayoutOrder = 100,
	Parent = teleport.Body,
	OnClick = function()
		openWindow("Dimensions")
	end,
})

--------------------------------------------------------------------------------
-- REBIRTH
--------------------------------------------------------------------------------
local rebirth = makeWindow("Rebirth", "♻️ REBIRTH", 520, 400, COLORS.Purple)
local rebirthInfo = label({
	Text = "",
	Size = UDim2.new(1, 0, 0, 120),
	TextYAlignment = Enum.TextYAlignment.Top,
	Parent = rebirth.Body,
})
label({
	Text = "Rebirthing resets your coins, gems, pickaxes, backpacks and zones.\nYou KEEP your pets, gadgets and Boss Shards, and earn more coins forever!",
	Size = UDim2.new(1, 0, 0, 56),
	Position = UDim2.fromOffset(0, 128),
	TextColor3 = Color3.fromRGB(210, 200, 235),
	Stroke = 0,
	Parent = rebirth.Body,
})
local confirmUntil = 0
local rebirthLabel: TextLabel, rebirthGrad: UIGradient

local function refreshRebirth()
	local s = state
	if not s then
		return
	end
	local cost = Shared.RebirthCost(s.Rebirths)
	rebirthInfo.Text = string.format(
		"♻️ Rebirths: %d  →  %d\n💰 Coin boost: x%s  →  x%s\nCost: 💰 %s",
		s.Rebirths,
		s.Rebirths + 1,
		Shared.MultiplierText(Shared.CoinMultiplier(s.Rebirths)),
		Shared.MultiplierText(Shared.CoinMultiplier(s.Rebirths + 1)),
		Format(cost)
	)
	if os.clock() < confirmUntil then
		rebirthLabel.Text = "Are you sure? Click again!"
		setColors(rebirthGrad, COLORS.Gold)
	elseif s.Coins >= cost then
		rebirthLabel.Text = "♻️ REBIRTH!"
		setColors(rebirthGrad, COLORS.Green)
	else
		rebirthLabel.Text = "Need 💰 " .. Format(cost - s.Coins) .. " more"
		setColors(rebirthGrad, COLORS.Gray)
	end
end

_, rebirthLabel, rebirthGrad = button({
	Size = UDim2.new(1, -40, 0, 70),
	Position = UDim2.new(0.5, 0, 1, -6),
	AnchorPoint = Vector2.new(0.5, 1),
	Text = "",
	Colors = COLORS.Green,
	Radius = 18,
	Parent = rebirth.Body,
	OnClick = function()
		local s = state
		if not s then
			return
		end
		if s.Coins < Shared.RebirthCost(s.Rebirths) then
			toast("You need 💰 " .. Format(Shared.RebirthCost(s.Rebirths)) .. " to rebirth!", "bad")
			return
		end
		if os.clock() < confirmUntil then
			confirmUntil = 0
			R.Rebirth:FireServer()
			closeWindow()
		else
			confirmUntil = os.clock() + 3
			refreshRebirth()
			task.delay(3.1, refreshRebirth)
		end
	end,
})
rebirth.OnOpen = refreshRebirth

--------------------------------------------------------------------------------
-- MY PETS (your pet collection)
--------------------------------------------------------------------------------
local petsWindow = makeWindow("Pets", "🐾 MY PETS", 760, 580, COLORS.Gold)
local petsInfo = label({ Text = "", Size = UDim2.new(1, 0, 0, 30), Parent = petsWindow.Body })
label({
	Text = "Pets give you more gems. A +30% pet makes every crystal give 30% more gems. Your best 3 pets are equipped by themselves!",
	Size = UDim2.new(1, 0, 0, 22),
	Position = UDim2.fromOffset(0, 32),
	TextColor3 = Color3.fromRGB(215, 215, 235),
	Stroke = 0,
	Parent = petsWindow.Body,
})
local petScroller = new("ScrollingFrame", {
	Size = UDim2.new(1, 0, 1, -62),
	Position = UDim2.new(0, 0, 0, 62),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 8,
	ScrollBarImageColor3 = WHITE,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	Parent = petsWindow.Body,
})
new("UIGridLayout", {
	CellSize = UDim2.fromOffset(166, 222),
	CellPadding = UDim2.fromOffset(12, 12),
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = petScroller,
})
new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 10), Parent = petScroller })

type PetCard = {
	Index: number,
	Viewport: ViewportFrame,
	Model: Model,
	Base: CFrame,
	NameLabel: TextLabel,
	Status: TextLabel,
	StatusGrad: UIGradient,
}
local petCards: { PetCard } = {}

local function makePetCard(i: number)
	local def = Shared.GetPet(i)
	local color = Shared.RarityColor(def.Rarity)
	local frame = new("Frame", { Name = "Pet" .. i, BackgroundColor3 = WHITE, LayoutOrder = if Shared.Pets[i] then i else 1000 + i % 100000, Parent = petScroller })
	round(frame, 16)
	outline(frame, 3)
	gradient(frame, { color:Lerp(WHITE, 0.15), color:Lerp(Color3.new(0, 0, 0), 0.45) })
	local viewport = new("ViewportFrame", {
		Size = UDim2.new(1, -16, 0, 104),
		Position = UDim2.fromOffset(8, 8),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.72,
		Ambient = Color3.fromRGB(190, 190, 200),
		LightColor = WHITE,
		LightDirection = Vector3.new(-1, -1, -1),
		Parent = frame,
	})
	round(viewport, 12)
	local cam = new("Camera", { FieldOfView = 34, Parent = viewport })
	viewport.CurrentCamera = cam
	local m = Shared.BuildPet(i)
	m.Parent = viewport
	fitCamera(cam, m, Vector3.new(0.35, 0.3, -1))
	local nameLabel = label({ Text = def.Name, Size = UDim2.new(1, -12, 0, 26), Position = UDim2.fromOffset(6, 115), Parent = frame })
	label({
		Text = def.Rarity .. "  •  " .. Shared.BonusText(def.Bonus),
		Size = UDim2.new(1, -12, 0, 22),
		Position = UDim2.fromOffset(6, 143),
		TextColor3 = Color3.fromRGB(255, 240, 160),
		Parent = frame,
	})
	local statusBox = new("Frame", {
		Size = UDim2.new(1, -18, 0, 40),
		Position = UDim2.new(0.5, 0, 1, -8),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = WHITE,
		Parent = frame,
	})
	round(statusBox, 12)
	outline(statusBox, 3)
	local statusGrad = gradient(statusBox, COLORS.Gray)
	local status = label({
		Text = "",
		Size = UDim2.fromScale(0.9, 0.7),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = statusBox,
	})
	table.insert(petCards, {
		Index = i,
		Viewport = viewport,
		Model = m,
		Base = m:GetPivot(),
		NameLabel = nameLabel,
		Status = status,
		StatusGrad = statusGrad,
	})
end
for i in ipairs(Shared.Pets) do
	makePetCard(i)
end

local function refreshPetsWindow()
	local s = state
	if not s then
		return
	end
	-- pets from dimension eggs get a card when you find them
	for index in pairs(ownedPets) do
		if not Shared.Pets[index] then
			local known = false
			for _, card in ipairs(petCards) do
				known = known or card.Index == index
			end
			if not known and Shared.GetPet(index) then
				makePetCard(index)
			end
		end
	end
	local found = 0
	for _, card in ipairs(petCards) do
		local def = Shared.GetPet(card.Index)
		local count = ownedPets[card.Index] or 0
		local following = equippedPets[card.Index] or 0
		if count > 0 then
			found += 1
		end
		-- pets you haven't found yet are a black shadow
		card.Viewport.ImageColor3 = if count > 0 then WHITE else Color3.new(0, 0, 0)
		card.NameLabel.Text = if count > 0 then def.Name else "???"
		if following > 0 then
			card.Status.Text = "⭐ EQUIPPED" .. (if following > 1 then " x" .. following else "")
			setColors(card.StatusGrad, COLORS.Blue)
		elseif count > 0 then
			card.Status.Text = "OWNED x" .. count
			setColors(card.StatusGrad, COLORS.Gray)
		else
			card.Status.Text = if def.Price then "🛒 Shop" else "🥚 " .. (def.From or "Egg")
			setColors(card.StatusGrad, COLORS.Purple)
		end
	end
	petsInfo.Text = string.format(
		"Your best %d follow you  •  Boost x%s 💎  •  Found %d/%d  •  Hatched %s",
		Settings.MaxPets,
		Shared.MultiplierText(Shared.GemMultiplier(ownedPets)),
		found,
		#Shared.Pets,
		Format(s.Hatched or 0)
	)
end
petsWindow.OnOpen = refreshPetsWindow

--------------------------------------------------------------------------------
-- DIMENSIONS (3 more every level!)
--------------------------------------------------------------------------------
local dimWindow = makeWindow("Dimensions", "🌌 DIMENSIONS", 760, 560, COLORS.Galaxy)
local dimInfo = label({ Text = "", Size = UDim2.new(1, 0, 0, 30), Parent = dimWindow.Body })
local dimScroller = new("ScrollingFrame", {
	Size = UDim2.new(1, 0, 1, -42),
	Position = UDim2.new(0, 0, 0, 42),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 8,
	ScrollBarImageColor3 = WHITE,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	Parent = dimWindow.Body,
})
new("UIGridLayout", {
	CellSize = UDim2.fromOffset(166, 170),
	CellPadding = UDim2.fromOffset(12, 12),
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = dimScroller,
})
new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 10), Parent = dimScroller })

type DimCard = { Number: number, Label: TextLabel, Grad: UIGradient }
local dimCards: { DimCard } = {}

local function makeDimCard(d: number): DimCard
	local dim = Shared.GetDimension(d)
	local frame = new("Frame", { Name = "Dimension" .. d, BackgroundColor3 = WHITE, LayoutOrder = d, Parent = dimScroller })
	round(frame, 16)
	outline(frame, 3)
	if dim.Shiny then
		gradient(frame, { Color3.fromRGB(255, 225, 120), dim.Accent:Lerp(Color3.new(0, 0, 0), 0.3) })
	else
		gradient(frame, { dim.Accent:Lerp(Color3.fromRGB(120, 120, 130), 0.45), dim.Ground:Lerp(Color3.new(0, 0, 0), 0.5) })
	end
	label({ Text = (if dim.Shiny then "✨ #" else dim.Emoji .. " #") .. d, Size = UDim2.new(1, -12, 0, 40), Position = UDim2.fromOffset(6, 6), Stroke = 3, Parent = frame })
	label({ Text = dim.Name, Size = UDim2.new(1, -12, 0, 26), Position = UDim2.fromOffset(6, 48), Parent = frame })
	label({
		Text = "❤️ " .. Format(dim.Health) .. "   💎 " .. Format(dim.Gems),
		Size = UDim2.new(1, -12, 0, 22),
		Position = UDim2.fromOffset(6, 78),
		TextColor3 = Color3.fromRGB(255, 240, 160),
		Parent = frame,
	})
	local _, enterLabel, enterGrad = button({
		Size = UDim2.new(1, -18, 0, 42),
		Position = UDim2.new(0.5, 0, 1, -8),
		AnchorPoint = Vector2.new(0.5, 1),
		Text = "",
		Colors = COLORS.Green,
		Parent = frame,
		OnClick = function()
			local s = state
			if s and d <= Shared.DimensionsUnlocked(s.Level) then
				R.EnterDimension:FireServer(d)
				closeWindow()
			else
				toast("🔒 Reach level " .. dim.Level .. " to visit dimension " .. d .. "!", "bad")
			end
		end,
	})
	return { Number = d, Label = enterLabel, Grad = enterGrad }
end

local function refreshDimensions()
	local s = state
	if not s then
		return
	end
	local unlocked = Shared.DimensionsUnlocked(s.Level)
	-- show every dimension you can visit, plus the ones the next level unlocks
	local shown = Shared.DimensionsUnlocked(s.Level + 1)
	while #dimCards < shown do
		table.insert(dimCards, makeDimCard(#dimCards + 1))
	end
	local here = player:GetAttribute("Dimension")
	for _, card in ipairs(dimCards) do
		if card.Number == here then
			card.Label.Text = "YOU ARE HERE"
			setColors(card.Grad, COLORS.Blue)
		elseif card.Number <= unlocked then
			card.Label.Text = "ENTER"
			setColors(card.Grad, COLORS.Green)
		else
			card.Label.Text = "🔒 Level " .. Shared.GetDimension(card.Number).Level
			setColors(card.Grad, COLORS.Gray)
		end
	end
	dimInfo.Text = string.format("⭐ Level %d: you can visit %d dimensions. Level up to unlock %d more!", s.Level, unlocked, Settings.DimensionsPerLevel)
end
dimWindow.OnOpen = refreshDimensions

--------------------------------------------------------------------------------
-- FREE GIFTS (for playing)
--------------------------------------------------------------------------------
local refreshGifts: () -> ()
local refreshDaily: () -> ()
do
	local giftsWindow = makeWindow("Gifts", "🎁 FREE GIFTS", 680, 480, COLORS.Pink)
	label({
		Text = "Keep playing to unlock more gifts! (They start again when you rejoin.)",
		Size = UDim2.new(1, 0, 0, 26),
		TextColor3 = Color3.fromRGB(220, 215, 240),
		Stroke = 0,
		Parent = giftsWindow.Body,
	})
	local giftGrid = new("Frame", {
		Size = UDim2.new(1, 0, 1, -38),
		Position = UDim2.fromOffset(0, 38),
		BackgroundTransparency = 1,
		Parent = giftsWindow.Body,
	})
	new("UIGridLayout", {
		CellSize = UDim2.fromOffset(114, 160),
		CellPadding = UDim2.fromOffset(10, 12),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = giftGrid,
	})
	type GiftCard = { Index: number, Icon: TextLabel, Reward: TextLabel, ButtonLabel: TextLabel, ButtonGrad: UIGradient }
	local giftCards: { GiftCard } = {}
	for i, gift in ipairs(Shared.Gifts) do
		local frame = new("Frame", { Name = "Gift" .. i, BackgroundColor3 = WHITE, LayoutOrder = i, Parent = giftGrid })
		round(frame, 14)
		outline(frame, 3)
		gradient(frame, { Color3.fromRGB(78, 66, 120), Color3.fromRGB(42, 38, 72) })
		local icon = label({ Text = if gift.Egg then "🥚" else "🎁", Size = UDim2.new(1, 0, 0, 54), Position = UDim2.fromOffset(0, 8), Stroke = 0, Parent = frame })
		local reward = label({
			Text = "",
			Size = UDim2.new(1, -10, 0, 24),
			Position = UDim2.fromOffset(5, 66),
			TextColor3 = Color3.fromRGB(255, 235, 150),
			Parent = frame,
		})
		local _, buttonLabel, buttonGrad = button({
			Size = UDim2.new(1, -14, 0, 42),
			Position = UDim2.new(0.5, 0, 1, -8),
			AnchorPoint = Vector2.new(0.5, 1),
			Text = "",
			Colors = COLORS.Gray,
			Parent = frame,
			OnClick = function()
				local s = state
				if s and not s.Gifts[i] and playedSeconds() >= gift.Minutes * 60 then
					R.Claim:FireServer("gift", i)
				elseif s and not s.Gifts[i] then
					toast("⏳ Keep playing to unlock this gift!", "info")
				end
			end,
		})
		table.insert(giftCards, { Index = i, Icon = icon, Reward = reward, ButtonLabel = buttonLabel, ButtonGrad = buttonGrad })
	end

	refreshGifts = function()
		local s = state
		if not s then
			return
		end
		local played = playedSeconds()
		for _, card in ipairs(giftCards) do
			local gift = Shared.Gifts[card.Index]
			card.Reward.Text = if gift.Egg then "FREE egg!" else "💰 " .. Format(Shared.RewardCoins(s, gift.Crystals or 0))
			local left = gift.Minutes * 60 - played
			if s.Gifts[card.Index] then
				card.ButtonLabel.Text = "✔ Claimed"
				card.Icon.TextTransparency = 0.6
				setColors(card.ButtonGrad, COLORS.Gray)
			elseif left <= 0 then
				card.ButtonLabel.Text = "CLAIM!"
				card.Icon.TextTransparency = 0
				setColors(card.ButtonGrad, COLORS.Green)
			else
				card.ButtonLabel.Text = "⏳ " .. clockText(left)
				card.Icon.TextTransparency = 0
				setColors(card.ButtonGrad, COLORS.Blue)
			end
		end
	end
	giftsWindow.OnOpen = refreshGifts

	-- Daily rewards (come back every day!)
	local dailyWindow = makeWindow("Daily", "📅 DAILY REWARDS", 740, 400, COLORS.Blue)
	local dailyInfo = label({ Text = "", Size = UDim2.new(1, 0, 0, 30), Parent = dailyWindow.Body })
	local dayRow = new("Frame", { Size = UDim2.new(1, 0, 0, 160), Position = UDim2.fromOffset(0, 42), BackgroundTransparency = 1, Parent = dailyWindow.Body })
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = dayRow,
	})
	type DayCard = { Grad: UIGradient, Reward: TextLabel, Check: TextLabel, Stroke: UIStroke, Pop: UIScale }
	local dayCards: { DayCard } = {}
	for i, reward in ipairs(Shared.DailyRewards) do
		local frame = new("Frame", { Name = "Day" .. i, Size = UDim2.fromOffset(92, 156), BackgroundColor3 = WHITE, LayoutOrder = i, Parent = dayRow })
		round(frame, 14)
		local stroke = outline(frame, 3)
		local grad = gradient(frame, COLORS.Gray)
		label({ Text = "Day " .. i, Size = UDim2.new(1, -8, 0, 26), Position = UDim2.fromOffset(4, 6), Parent = frame })
		label({ Text = if reward.Egg then "🥚" else "💰", Size = UDim2.new(1, 0, 0, 48), Position = UDim2.fromOffset(0, 36), Stroke = 0, Parent = frame })
		local rewardLabel = label({ Text = "", Size = UDim2.new(1, -8, 0, 40), Position = UDim2.fromOffset(4, 90), TextWrapped = true, Parent = frame })
		local check = label({
			Text = "✔",
			Size = UDim2.fromOffset(40, 40),
			Position = UDim2.new(1, -2, 0, 2),
			AnchorPoint = Vector2.new(1, 0),
			TextColor3 = Color3.fromRGB(130, 255, 140),
			Visible = false,
			Parent = frame,
		})
		table.insert(dayCards, { Grad = grad, Reward = rewardLabel, Check = check, Stroke = stroke, Pop = new("UIScale", { Parent = frame }) })
	end
	local dailyClaimLabel: TextLabel, dailyClaimGrad: UIGradient
	_, dailyClaimLabel, dailyClaimGrad = button({
		Size = UDim2.fromOffset(380, 62),
		Position = UDim2.new(0.5, 0, 1, -4),
		AnchorPoint = Vector2.new(0.5, 1),
		Text = "",
		Colors = COLORS.Green,
		Radius = 18,
		Parent = dailyWindow.Body,
		OnClick = function()
			local s = state
			if s and s.DailyReady then
				R.Claim:FireServer("daily")
			else
				toast("📅 Come back tomorrow for your next reward!", "info")
			end
		end,
	})

	refreshDaily = function()
		local s = state
		if not s then
			return
		end
		local today = (s.DailyStreak - 1) % #Shared.DailyRewards + 1
		for i, card in ipairs(dayCards) do
			local reward = Shared.DailyRewards[i]
			card.Reward.Text = "💰 " .. Format(Shared.RewardCoins(s, reward.Crystals or 0)) .. (if reward.Egg then "\n+ FREE egg" else "")
			if i == today then
				setColors(card.Grad, COLORS.Gold)
				card.Stroke.Thickness = 4
				card.Check.Visible = not s.DailyReady
			elseif i < today then
				setColors(card.Grad, COLORS.Green)
				card.Stroke.Thickness = 3
				card.Check.Visible = true
			else
				setColors(card.Grad, COLORS.Gray)
				card.Stroke.Thickness = 3
				card.Check.Visible = false
			end
		end
		dailyInfo.Text = "🔥 Streak: " .. s.DailyStreak .. (if s.DailyStreak == 1 then " day" else " days") .. "  •  Come back every day for bigger rewards!"
		if s.DailyReady then
			dailyClaimLabel.Text = "🎁 CLAIM DAY " .. today .. "!"
			setColors(dailyClaimGrad, COLORS.Green)
		else
			dailyClaimLabel.Text = "⏳ Next reward in " .. clockText(86400 - os.time() % 86400)
			setColors(dailyClaimGrad, COLORS.Gray)
		end
	end
	dailyWindow.OnOpen = function()
		refreshDaily()
		local s = state
		if s then
			local card = dayCards[(s.DailyStreak - 1) % #Shared.DailyRewards + 1]
			pop(card.Pop, 1.15)
		end
	end
end

R.OpenMenu.OnClientEvent:Connect(function(name)
	openWindow(name, true)
end)

--------------------------------------------------------------------------------
-- WORLD EFFECTS
--------------------------------------------------------------------------------
local function attachmentAt(position: Vector3, lifetime: number): Attachment
	local att = Instance.new("Attachment")
	att.Parent = Workspace.Terrain
	att.Position = position
	Debris:AddItem(att, lifetime)
	return att
end

local function burst(position: Vector3, color: Color3, count: number, speed: number, size: number)
	local att = attachmentAt(position, 3)
	local emitter = new("ParticleEmitter", {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new(color),
		LightEmission = 1,
		Size = NumberSequence.new(size, 0),
		Lifetime = NumberRange.new(0.5, 1),
		Speed = NumberRange.new(speed * 0.4, speed),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 3,
		Acceleration = Vector3.new(0, -12, 0),
		Rate = 0,
		Rotation = NumberRange.new(0, 360),
		Parent = att,
	})
	emitter:Emit(count)
end

-- Floating text in the world, like "+30 💎"
local function worldText(position: Vector3, text: string, color: Color3, height: number)
	local att = attachmentAt(position, 1.4)
	local bb = new("BillboardGui", {
		Adornee = att,
		Size = UDim2.fromOffset(height * 5, height),
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = 150,
		Parent = att,
	})
	local lbl = label({ Text = text, Size = UDim2.fromScale(1, 1), TextColor3 = color, Stroke = 3, Parent = bb })
	local stroke = lbl:FindFirstChildOfClass("UIStroke") :: UIStroke
	tween(bb, 1.2, { StudsOffset = Vector3.new(math.random(-10, 10) / 10, 4, 0) })
	task.delay(0.6, function()
		tween(lbl, 0.6, { TextTransparency = 1 })
		tween(stroke, 0.6, { Transparency = 1 })
	end)
end

-- Little icons that fly from the world into your HUD
local function flyIcons(fromWorld: Vector3, emoji: string, target: GuiObject, targetPop: UIScale, count: number)
	local screen, onScreen = camera:WorldToViewportPoint(fromWorld)
	if not onScreen then
		pop(targetPop)
		return
	end
	local goal = target.AbsolutePosition + target.AbsoluteSize / 2
	for i = 1, count do
		local icon = label({
			Text = emoji,
			Size = UDim2.fromOffset(36, 36),
			Position = UDim2.fromOffset(screen.X + math.random(-40, 40), screen.Y + math.random(-40, 40)),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Stroke = 0,
			Parent = fxGui,
		})
		local t = TweenService:Create(
			icon,
			TweenInfo.new(0.45 + i * 0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = UDim2.fromOffset(goal.X, goal.Y), Size = UDim2.fromOffset(22, 22) }
		)
		t.Completed:Connect(function()
			icon:Destroy()
			pop(targetPop, 1.1)
		end)
		t:Play()
	end
end

-- Crystal pieces that fly off when a crystal breaks
local function shards(position: Vector3, color: Color3, count: number, shiny: boolean)
	for _ = 1, count do
		local shard = new("Part", {
			Size = Vector3.new(0.5, 0.9, 0.5) * (0.6 + math.random() * 0.7),
			CFrame = CFrame.new(position + Vector3.new(math.random() - 0.5, math.random() * 2, math.random() - 0.5))
				* CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6),
			Color = color,
			Material = if shiny then Enum.Material.Neon else Enum.Material.Glass,
			Transparency = if shiny then 0 else 0.1,
			Reflectance = if shiny then 0 else 0.3,
			CanTouch = false,
			CastShadow = false,
			Parent = FxFolder,
		})
		shard.AssemblyLinearVelocity = Vector3.new(math.random(-20, 20), math.random(15, 32), math.random(-20, 20))
		shard.AssemblyAngularVelocity = Vector3.new(math.random(-10, 10), math.random(-10, 10), math.random(-10, 10))
		tween(shard, 1.3, { Transparency = 1, Size = shard.Size * 0.3 })
		Debris:AddItem(shard, 1.4)
	end
end

-- Makes a crystal wiggle when you hit it
local shaking: { [Model]: boolean } = {}
local function shake(m: Model)
	if shaking[m] then
		return
	end
	shaking[m] = true
	local origin = m:GetPivot()
	task.spawn(function()
		for i = 1, 4 do
			if not m.Parent then
				break
			end
			local amount = (5 - i) * 0.06
			m:PivotTo(origin * CFrame.new(math.random(-10, 10) / 10 * amount, 0, math.random(-10, 10) / 10 * amount))
			task.wait(0.03)
		end
		if m.Parent then
			m:PivotTo(origin)
		end
		shaking[m] = nil
	end)
end

local function confetti(position: Vector3)
	for _, color in ipairs({ Color3.fromRGB(255, 90, 120), Color3.fromRGB(255, 220, 80), Color3.fromRGB(90, 220, 255), Color3.fromRGB(140, 255, 120) }) do
		burst(position, color, 12, 30, 0.8)
	end
end

local function myRoot(): BasePart?
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- Are we in a shiny dimension right now?
local function inShinyDimension(): boolean
	local d = player:GetAttribute("Dimension")
	return type(d) == "number" and Shared.GetDimension(d).Shiny
end

-- A puff of dust
local function dust(position: Vector3, color: Color3, count: number, size: number)
	local att = attachmentAt(position, 3)
	local emitter = new("ParticleEmitter", {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Color = ColorSequence.new(color),
		LightEmission = 0,
		LightInfluence = 1,
		Size = NumberSequence.new(size, size * 2.4),
		Transparency = NumberSequence.new(0.45, 1),
		Lifetime = NumberRange.new(0.9, 1.5),
		Speed = NumberRange.new(3, 7),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 4,
		Acceleration = Vector3.new(0, 1.5, 0),
		Rate = 0,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-40, 40),
		Parent = att,
	})
	emitter:Emit(count)
end

-- Little pieces of rock that bounce away
local function chips(position: Vector3, color: Color3, count: number)
	for _ = 1, count do
		local chip = new("Part", {
			Size = Vector3.new(0.35 + math.random() * 0.4, 0.3 + math.random() * 0.3, 0.35 + math.random() * 0.4),
			CFrame = CFrame.new(position + Vector3.new(math.random() - 0.5, 0.3, math.random() - 0.5))
				* CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6),
			Color = color:Lerp(Color3.new(0, 0, 0), math.random() * 0.25),
			Material = Enum.Material.Slate,
			CanTouch = false,
			CastShadow = false,
			Parent = FxFolder,
		})
		chip.AssemblyLinearVelocity = Vector3.new(math.random(-14, 14), math.random(10, 20), math.random(-14, 14))
		chip.AssemblyAngularVelocity = Vector3.new(math.random(-12, 12), math.random(-12, 12), math.random(-12, 12))
		task.delay(1.1, function()
			if chip.Parent then
				tween(chip, 0.5, { Transparency = 1 })
			end
		end)
		Debris:AddItem(chip, 1.7)
	end
end

-- Gems fly out of a broken crystal into you
type FlyingGem = { Part: BasePart, Start: Vector3, Side: Vector3, Delay: number }
local GEM_SIZE = Vector3.new(0.45, 0.7, 0.45)
local function gemsToPlayer(from: Vector3, color: Color3, count: number, onArrive: () -> ())
	local root = myRoot()
	if not root then
		return
	end
	local material = if inShinyDimension() then Enum.Material.Neon else Enum.Material.Glass
	local gems: { FlyingGem } = {}
	for i = 1, count do
		local gem = new("Part", {
			Size = GEM_SIZE,
			CFrame = CFrame.new(from),
			Anchored = true,
			CanCollide = false,
			CanTouch = false,
			CastShadow = false,
			Color = color,
			Material = material,
			Reflectance = 0.3,
			Parent = FxFolder,
		})
		Debris:AddItem(gem, 3)
		table.insert(gems, {
			Part = gem,
			Start = from + Vector3.new(math.random() * 2 - 1, math.random() * 1.5, math.random() * 2 - 1),
			Side = Vector3.new(math.random() * 8 - 4, 0, math.random() * 8 - 4),
			Delay = (i - 1) * 0.05,
		})
	end
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local now = os.clock() - started
		local target = if root.Parent then root.Position + Vector3.new(0, 0.5, 0) else from
		local flying = 0
		for _, g in ipairs(gems) do
			if g.Part.Parent then
				local a = math.clamp((now - g.Delay) / 0.6, 0, 1)
				local e = a * a -- speeds up as it gets closer
				local mid = g.Start + g.Side + Vector3.new(0, 5, 0)
				local pos = g.Start:Lerp(mid, e):Lerp(mid:Lerp(target, e), e)
				g.Part.CFrame = CFrame.new(pos) * CFrame.Angles(a * 9, a * 7, 0)
				g.Part.Size = GEM_SIZE * (1 - a * 0.6)
				if a >= 1 then
					g.Part:Destroy()
					onArrive()
				else
					flying += 1
				end
			end
		end
		if flying == 0 then
			connection:Disconnect()
		end
	end)
end

-- New crystals grow up out of the ground
local function backOut(t: number): number
	local c1 = 1.70158
	return 1 + (c1 + 1) * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end
local function grow(m: Model)
	local final = m:GetPivot()
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local t = math.clamp((os.clock() - started) / 0.55, 0, 1)
		if not m.Parent then
			connection:Disconnect()
			return
		end
		placeModel(m, final * CFrame.new(0, -3.5 * (1 - backOut(t)), 0))
		if t >= 1 then
			connection:Disconnect()
		end
	end)
end

--------------------------------------------------------------------------------
-- EGG HATCHING ANIMATION
--------------------------------------------------------------------------------
local hatchOverlay = new("TextButton", {
	Name = "HatchOverlay",
	Text = "",
	AutoButtonColor = false,
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(12, 8, 24),
	BackgroundTransparency = 1,
	Visible = false,
	ZIndex = 20,
	Parent = gui,
})
local hatchRow = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.46),
	Size = UDim2.fromOffset(820, 380),
	BackgroundTransparency = 1,
	Parent = hatchOverlay,
})
autoScale(hatchRow)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0, 24),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = hatchRow,
})
local hatchHint = label({
	Text = "Click anywhere to continue",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -40),
	Size = UDim2.fromOffset(500, 34),
	TextColor3 = Color3.fromRGB(220, 220, 240),
	Visible = false,
	Parent = hatchOverlay,
})
autoScale(hatchHint)
local hatchFlash = new("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = WHITE,
	BackgroundTransparency = 1,
	ZIndex = 5,
	Parent = hatchOverlay,
})

type HatchSlot = {
	Frame: Frame,
	Rays: Frame,
	Viewport: ViewportFrame,
	Camera: Camera,
	Model: Model?,
	Base: CFrame,
	Info: Frame,
	Pop: UIScale,
}

local function makeHatchSlot(order: number): HatchSlot
	local frame = new("Frame", { Size = UDim2.fromOffset(250, 370), BackgroundTransparency = 1, LayoutOrder = order, Parent = hatchRow })
	-- glowing light rays behind the pet
	local rays = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(125, 130),
		Size = UDim2.fromOffset(10, 10),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = frame,
	})
	for i = 0, 7 do
		local ray = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(30, 320),
			Rotation = i * 22.5,
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			Parent = rays,
		})
		new("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0.2),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = ray,
		})
	end
	local viewport = new("ViewportFrame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(125, 130),
		Size = UDim2.fromOffset(240, 240),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(200, 200, 210),
		LightColor = WHITE,
		LightDirection = Vector3.new(-1, -1, -1),
		Parent = frame,
	})
	local cam = new("Camera", { FieldOfView = 30, Parent = viewport })
	viewport.CurrentCamera = cam
	local info = new("Frame", { Position = UDim2.fromOffset(0, 255), Size = UDim2.fromOffset(250, 110), BackgroundTransparency = 1, Visible = false, Parent = frame })
	local popScale: UIScale = new("UIScale", { Parent = info })
	return { Frame = frame, Rays = rays, Viewport = viewport, Camera = cam, Base = CFrame.new(), Info = info, Pop = popScale }
end

local function clearHatchSlots()
	for _, child in ipairs(hatchRow:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
end

type HatchResult = { Pet: number, New: boolean }
local hatchToken = 0

local function playHatch(eggIndex: number, results: { HatchResult })
	hatchToken += 1
	local token = hatchToken
	closeWindow()
	clearHatchSlots()
	hatchOverlay.Visible = true
	hatchHint.Visible = false
	hatchOverlay.BackgroundTransparency = 1
	tween(hatchOverlay, 0.3, { BackgroundTransparency = 0.3 })

	local slots: { HatchSlot } = {}
	for i = 1, #results do
		local slot = makeHatchSlot(i)
		local egg = Shared.BuildEgg(eggIndex)
		egg.Parent = slot.Viewport
		fitCamera(slot.Camera, egg, Vector3.new(0, 0.1, -1))
		slot.Model = egg
		slot.Base = egg:GetPivot()
		table.insert(slots, slot)
	end

	-- the eggs wobble more and more...
	local started = os.clock()
	local wobble = RunService.RenderStepped:Connect(function()
		local t = os.clock() - started
		local amount = math.min(t / 1.6, 1) * 0.5
		for i, slot in ipairs(slots) do
			local m = slot.Model
			if m then
				placeModel(m, slot.Base * CFrame.Angles(0, 0, math.sin(t * (12 + t * 12) + i) * amount))
			end
		end
	end)
	-- click (or tap) to make it go faster
	local hurry = false
	local hurryClick = hatchOverlay.Activated:Connect(function()
		hurry = true
	end)
	for k = 1, 6 do
		task.wait(if hurry then 0.05 else 0.27)
		if token ~= hatchToken then
			wobble:Disconnect()
			hurryClick:Disconnect()
			return
		end
		playSound("Click", 0.7 + k * 0.15, 0.8)
	end
	hurryClick:Disconnect()
	wobble:Disconnect()

	-- ...and POP!
	hatchFlash.BackgroundTransparency = 0
	tween(hatchFlash, 0.7, { BackgroundTransparency = 1 })
	playSound("Boom", 1.4, 0.35)
	local bestRank = 1
	for i, slot in ipairs(slots) do
		local result = results[i]
		local def = Shared.GetPet(result.Pet)
		local color = Shared.RarityColor(def.Rarity)
		bestRank = math.max(bestRank, Shared.RarityRank(def.Rarity))
		local egg = slot.Model
		if egg then
			egg:Destroy()
		end
		local pet = Shared.BuildPet(result.Pet)
		pet.Parent = slot.Viewport
		fitCamera(slot.Camera, pet, Vector3.new(0.3, 0.25, -1))
		slot.Model = pet
		slot.Base = pet:GetPivot()
		for _, ray in ipairs(slot.Rays:GetChildren()) do
			if ray:IsA("Frame") then
				ray.BackgroundColor3 = color
			end
		end
		slot.Rays.Visible = true
		label({ Text = def.Name, Size = UDim2.new(1, 0, 0, 40), Parent = slot.Info })
		label({ Text = string.upper(def.Rarity), Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 42), TextColor3 = color, Parent = slot.Info })
		label({
			Text = Shared.BonusText(def.Bonus) .. " Gems 💎",
			Size = UDim2.new(1, 0, 0, 26),
			Position = UDim2.fromOffset(0, 76),
			TextColor3 = Color3.fromRGB(255, 240, 160),
			Parent = slot.Info,
		})
		if result.New then
			label({
				Text = "NEW!",
				Size = UDim2.fromOffset(90, 36),
				Position = UDim2.new(1, -6, 0, 6),
				AnchorPoint = Vector2.new(1, 0),
				Rotation = 12,
				TextColor3 = Color3.fromRGB(255, 225, 60),
				Parent = slot.Frame,
			})
		end
		slot.Info.Visible = true
		pop(slot.Pop, 1.4)
	end
	if bestRank >= Shared.RarityRank("Legendary") then
		chime(9, 0.9)
		local root = myRoot()
		if root then
			confetti(root.Position + Vector3.new(0, 3, 0))
		end
	elseif bestRank >= Shared.RarityRank("Rare") then
		chime(6, 1.1)
	else
		chime(4, 1.3)
	end

	-- show the pets until the player clicks (or a few seconds pass)
	local shownAt = os.clock()
	local spinner = RunService.RenderStepped:Connect(function(dt)
		local t = os.clock() - shownAt
		for _, slot in ipairs(slots) do
			slot.Rays.Rotation += dt * 25
			local m = slot.Model
			if m then
				turnModel(m, slot.Base, math.sin(t * 1.5) * 0.6)
			end
		end
	end)
	task.wait(0.35)
	hatchHint.Visible = true
	local clicked = false
	local click = hatchOverlay.Activated:Connect(function()
		clicked = true
	end)
	while not clicked and os.clock() - shownAt < 5 and token == hatchToken do
		task.wait(0.05)
	end
	click:Disconnect()
	spinner:Disconnect()
	if token == hatchToken then
		hatchOverlay.Visible = false
		clearHatchSlots()
	end
end

--------------------------------------------------------------------------------
-- EVENTS FROM THE SERVER
--------------------------------------------------------------------------------
local function rootPosition(): Vector3?
	local root = myRoot()
	return if root then root.Position else nil
end

local function celebrate(notes: number, speed: number)
	local position = rootPosition()
	if position then
		confetti(position + Vector3.new(0, 3, 0))
	end
	chime(notes, speed)
end

local updateGate: (gate: Instance, animate: boolean?) -> ()

R.Effect.OnClientEvent:Connect(function(kind, a, b, c, d, e)
	if kind == "hit" then
		local position: Vector3, damage: number, m: Model? = a, b, c
		burst(position, Color3.new(1, 1, 1), 4, 12, 0.35)
		local rock = m and m.PrimaryPart
		dust(position - Vector3.new(0, 2, 0), if rock then rock.Color:Lerp(WHITE, 0.35) else Color3.fromRGB(170, 165, 158), 2, 0.8)
		worldText(position + Vector3.new(0, 1, 0), "-" .. Format(damage), Color3.fromRGB(255, 255, 255), 24)
		playSound("Hit", 1.5 + math.random() * 0.4, 0.45)
		if m and m.Parent then
			shake(m)
		end
	elseif kind == "break" then
		local position: Vector3, color: Color3, giant: boolean, golden: boolean? = a, b, c, d
		burst(position, color, if giant then 30 else 14, if giant then 34 else 22, if giant then 1 else 0.6)
		shards(position, color, if giant then 12 else 7, inShinyDimension())
		chips(position - Vector3.new(0, 1.5, 0), Color3.fromRGB(110, 104, 98), if giant then 10 else 5)
		dust(position - Vector3.new(0, 2, 0), Color3.fromRGB(175, 170, 162), if giant then 14 else 7, if giant then 2.2 else 1.3)
		if golden then
			burst(position, Color3.fromRGB(255, 215, 90), 40, 30, 1)
		end
		local position2 = rootPosition()
		if position2 and (position2 - position).Magnitude < 80 then
			playSound("Boom", if giant then 1.2 else 1.8, if giant then 0.35 else 0.18)
		end
	elseif kind == "reward" then
		local position: Vector3, gems: number, xp: number?, golden: boolean?, color: Color3? = a, b, c, d, e
		worldText(position + Vector3.new(0, 2.5, 0), "+" .. Format(gems) .. " 💎", Color3.fromRGB(120, 240, 255), 34)
		if xp then
			worldText(position + Vector3.new(0, 0.5, 0), "+" .. Format(xp) .. " XP", Color3.fromRGB(255, 150, 230), 24)
		end
		local arrived = 0
		gemsToPlayer(position, color or Color3.fromRGB(120, 200, 230), math.clamp(math.floor(gems / 5) + 3, 3, 8), function()
			arrived += 1
			pop(gemsPop, 1.08)
			playSound("Click", 1.6 + arrived * 0.08, 0.35)
		end)
		if golden then
			showBanner("✨ GOLDEN CRYSTAL! ✨", Color3.fromRGB(255, 215, 90))
			celebrate(7, 1.1)
		end
	elseif kind == "sold" then
		local coins: number = a
		local bonus: number = if type(b) == "number" then b else 1
		local position = rootPosition()
		if position then
			flyIcons(position, "💰", coinsPill, coinsPop, 8)
			confetti(position + Vector3.new(0, 2, 0))
		end
		showBanner("💰 +" .. Format(coins) .. " COINS!" .. (if bonus > 1 then "  (x" .. string.format("%g", bonus) .. " dimension bonus)" else ""), Color3.fromRGB(255, 220, 80))
		chime(6, 1)
	elseif kind == "full" then
		backpackFull()
	elseif kind == "bought" then
		celebrate(4, 1.4)
	elseif kind == "unlock" then
		local zone = Shared.Zones[a]
		if zone then
			showBanner("🔓 " .. string.upper(zone.Name) .. " UNLOCKED!", zone.Accent:Lerp(WHITE, 0.3))
		end
		local gate = GateFolder:FindFirstChild("Gate" .. tostring(a))
		if gate then
			updateGate(gate, true)
		end
		playSound("Boom", 1.1, 0.4)
		celebrate(6, 1.2)
	elseif kind == "rebirth" then
		local who = Players:GetPlayerByUserId(a)
		local char = who and who.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			burst(root.Position, Color3.fromRGB(200, 120, 255), 60, 45, 1.6)
			burst(root.Position, Color3.fromRGB(255, 255, 255), 30, 30, 1)
		end
		if who == player then
			showBanner("♻️ REBIRTH! ♻️", Color3.fromRGB(220, 160, 255))
			playSound("Boom", 0.8, 0.5)
			chime(8, 0.9)
		end
	elseif kind == "levelup" then
		local who = Players:GetPlayerByUserId(a)
		local char = who and who.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			burst(root.Position, Color3.fromRGB(255, 150, 230), 40, 35, 1.2)
			burst(root.Position, Color3.fromRGB(255, 230, 90), 25, 25, 1)
		end
		if who == player then
			showBanner("⭐ LEVEL UP! LEVEL " .. tostring(b) .. " ⭐", Color3.fromRGB(255, 170, 235))
			toast("🌌 " .. Settings.DimensionsPerLevel .. " new dimensions unlocked! Open DIMENSIONS to visit them.", "gold")
			pop(levelPop, 1.25)
			celebrate(8, 1)
		end
	elseif kind == "hatch" then
		task.spawn(playHatch, a, b)
	elseif kind == "spawn" then
		local position: Vector3, color: Color3, golden: boolean?, m: Model? = a, b, c, d
		local near = rootPosition()
		local close = near ~= nil and (near - position).Magnitude < 150
		if close then
			dust(position - Vector3.new(0, 2.5, 0), Color3.fromRGB(175, 170, 162), 5, 1)
			burst(position, color, 8, 8, 0.5)
			if m and m.Parent then
				grow(m)
			end
		end
		if golden and close then
			burst(position, Color3.fromRGB(255, 215, 90), 25, 14, 0.8)
			toast("✨ A GOLDEN crystal appeared nearby! It gives 10x gems!", "gold")
		end
	elseif kind == "quest" then
		local text: string, coins: number, xp: number = a, b, c
		showBanner("📜 QUEST COMPLETE!", Color3.fromRGB(255, 215, 110))
		toast(text .. "  ✔  +💰 " .. Format(coins) .. "  +" .. Format(xp) .. " XP", "gold")
		pop(questPop, 1.2)
		local position = rootPosition()
		if position then
			flyIcons(position, "💰", coinsPill, coinsPop, 6)
		end
		celebrate(7, 1.05)
	elseif kind == "gift" then
		showBanner("🎁 FREE GIFT!", Color3.fromRGB(255, 160, 230))
		toast("🎁 You got " .. tostring(a) .. "!", "gold")
		celebrate(6, 1.2)
	elseif kind == "daily" then
		showBanner("📅 DAY " .. tostring(b) .. " REWARD!", Color3.fromRGB(140, 210, 255))
		toast("📅 You got " .. tostring(a) .. "! Come back tomorrow for more.", "gold")
		celebrate(8, 1)
	elseif kind == "obbystart" then
		closeWindow()
		obbyState.Checkpoint = 0
		local title = if type(a) == "number" then "🏃 DIMENSION " .. a .. " OBBY!" else "🏃 SKY OBBY!"
		showBanner(title .. " Reach the 🏆 trophy!", Color3.fromRGB(255, 220, 140))
		chime(3, 1.2)
	elseif kind == "checkpoint" then
		obbyState.Checkpoint = a
		showBanner("🚩 CHECKPOINT " .. tostring(a) .. " / " .. tostring(b), Color3.fromRGB(255, 150, 140))
		local position = rootPosition()
		if position then
			burst(position, Color3.fromRGB(255, 120, 110), 20, 18, 0.7)
		end
		chime(4, 1.3)
	elseif kind == "obbyfall" then
		toast("💨 Whoops! Back to your last checkpoint.", "info")
		playSound("Hit", 0.7, 0.5)
	elseif kind == "obbylava" then
		toast("🔥 Ouch, hot lava! Back to your last checkpoint.", "bad")
		local position = rootPosition()
		if position then
			burst(position, Color3.fromRGB(255, 120, 40), 25, 16, 0.8)
		end
		playSound("Splash", 1.4, 0.4)
	elseif kind == "obby" then
		local time: number, coins: number, record: boolean, wait: number = a, b, c, d
		showBanner("🏆 FINISHED IN " .. string.format("%.1f", time) .. "s!", Color3.fromRGB(255, 220, 120))
		if coins > 0 then
			toast("🏆 +💰 " .. Format(coins) .. " for finishing the obby!", "gold")
			local position = rootPosition()
			if position then
				flyIcons(position, "💰", coinsPill, coinsPop, 10)
			end
		else
			toast("⏳ You finished! The obby pays again in " .. clockText(wait) .. ".", "info")
		end
		if record then
			task.delay(0.8, function()
				toast("⭐ NEW BEST TIME: " .. string.format("%.1f", time) .. " seconds!", "good")
			end)
		end
		celebrate(9, 0.95)
	elseif kind == "teleported" then
		local position = rootPosition()
		if position then
			burst(position, Color3.fromRGB(150, 220, 255), 25, 16, 0.7)
		end
		playSound("Click", 0.8, 0.6)
	end
end)

R.Notify.OnClientEvent:Connect(function(message, kind)
	toast(message, kind)
	if kind == "bad" then
		playSound("Hit", 0.6, 0.5)
	end
end)

--------------------------------------------------------------------------------
-- TOOL ANIMATIONS (a swing with the pickaxe, a scoop with the shovel)
--------------------------------------------------------------------------------
local playSwing: (kind: string, who: Model?) -> ()
do
	local shoulderHome: { [Motor6D]: CFrame } = setmetatable({}, { __mode = "k" }) :: any
	local swingTokens: { [Motor6D]: number } = setmetatable({}, { __mode = "k" }) :: any
	-- who = someone else's character (you see other players swing too)
	playSwing = function(kind: string, who: Model?)
		local char = who or player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not (char and hum) then
			return
		end
		local r15 = hum.RigType == Enum.HumanoidRigType.R15
		local holder = if r15 then char:FindFirstChild("RightUpperArm") else char:FindFirstChild("Torso")
		local shoulder = holder and holder:FindFirstChild(if r15 then "RightShoulder" else "Right Shoulder")
		if not (shoulder and shoulder:IsA("Motor6D")) then
			return
		end
		local home = shoulderHome[shoulder] or shoulder.C0
		shoulderHome[shoulder] = home
		local token = (swingTokens[shoulder] or 0) + 1
		swingTokens[shoulder] = token
		local started = os.clock()
		local duration = if kind == "dig" then 0.3 else 0.22
		local connection: RBXScriptConnection
		connection = RunService.RenderStepped:Connect(function()
			if swingTokens[shoulder] ~= token or not shoulder.Parent then
				connection:Disconnect()
				return
			end
			local t = math.clamp((os.clock() - started) / duration, 0, 1)
			-- smooth start and stop for every part of the move
			local function ease(x: number): number
				return x * x * (3 - 2 * x)
			end
			local angle
			if kind == "dig" then
				-- push down into the ground, then scoop up
				angle = if t < 0.4 then -0.9 * ease(t / 0.4) elseif t < 0.75 then -0.9 + 1.3 * ease((t - 0.4) / 0.35) else 0.4 * (1 - ease((t - 0.75) / 0.25))
			else
				-- lift up, hit down hard, then come back
				angle = if t < 0.35 then 0.95 * ease(t / 0.35) elseif t < 0.6 then 0.95 - 1.6 * ((t - 0.35) / 0.25) else -0.65 * (1 - ease((t - 0.6) / 0.4))
			end
			shoulder.C0 = home * (if r15 then CFrame.Angles(angle, 0, 0) else CFrame.Angles(0, 0, angle))
			if t >= 1 then
				shoulder.C0 = home
				connection:Disconnect()
			end
		end)
	end

	-- other players swinging near you
	R.Effect.OnClientEvent:Connect(function(kind, userId, swingKind)
		if kind ~= "swing" or type(userId) ~= "number" or type(swingKind) ~= "string" then
			return
		end
		local other = Players:GetPlayerByUserId(userId)
		if other and other ~= player and other.Character then
			playSwing(swingKind, other.Character)
		end
	end)
end

--------------------------------------------------------------------------------
-- SPRINTING, GADGETS AND 💠 BOSS SHARDS ON THE SCREEN
--------------------------------------------------------------------------------
do
	hud.Size = UDim2.fromOffset(250, 510)
	local shardsPill = new("Frame", { Name = "Shards", Size = UDim2.fromOffset(250, 44), BackgroundColor3 = WHITE, LayoutOrder = 4, Parent = hud })
	round(shardsPill, 14)
	outline(shardsPill, 3)
	gradient(shardsPill, COLORS.Cyan)
	local shardsText = label({
		Text = "💠 0 Boss Shards",
		Size = UDim2.new(1, -20, 0.62, 0),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = shardsPill,
	})
	local shardsPop: UIScale = new("UIScale", { Parent = shardsPill })
	local lastShards = -1

	-- Sprint: hold Shift, or tap the button (phones and tablets)
	local sprintHeld = false
	local sprintToggle = false
	local sprintButton, sprintLabel, sprintGrad = button({
		Size = UDim2.fromOffset(96, 96),
		Position = UDim2.new(1, -24, 1, -200),
		AnchorPoint = Vector2.new(1, 1),
		Text = "🏃\nSprint",
		Colors = COLORS.Gray,
		Radius = 48,
		Parent = gui,
		OnClick = function()
			sprintToggle = not sprintToggle
		end,
	})
	sprintButton.Visible = UserInputService.TouchEnabled
	autoScale(sprintButton)
	UserInputService.InputBegan:Connect(function(input, processed)
		if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
			sprintHeld = true
		elseif input.KeyCode == Enum.KeyCode.ButtonL3 and not processed then
			sprintToggle = not sprintToggle
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
			sprintHeld = false
		end
	end)

	local function toSet(list: { number }?): { [number]: boolean }
		local set = {}
		for _, n in ipairs(list or {}) do
			set[n] = true
		end
		return set
	end
	local stats = Shared.GadgetStats({})
	local statsFrom: any = nil
	local fov = camera.FieldOfView
	RunService.RenderStepped:Connect(function(dt)
		local s = state
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not (s and hum) then
			return
		end
		if statsFrom ~= s then
			statsFrom = s
			stats = Shared.GadgetStats(toSet(s.Gadgets), toSet(s.GadgetsOff))
		end
		local inObby = player:GetAttribute("ObbyStart") ~= nil
		local sprinting = (sprintHeld or sprintToggle) and hum.MoveDirection.Magnitude > 0.1
		local walk = Settings.WalkSpeed + (if inObby then 0 else stats.Speed) + (if sprintHeld or sprintToggle then stats.Sprint else 0)
		local jump = if inObby then Settings.JumpHeight else stats.Jump
		if hum.WalkSpeed ~= walk then
			hum.WalkSpeed = walk
		end
		if hum.JumpHeight ~= jump or hum.UseJumpPower then
			hum.UseJumpPower = false
			hum.JumpHeight = jump
		end
		-- the view gets a bit wider when you run fast
		local wantFov = if sprinting then 78 else 70
		fov += (wantFov - fov) * math.min(1, dt * 8)
		if math.abs(camera.FieldOfView - fov) > 0.05 then
			camera.FieldOfView = fov
		end
		sprintLabel.Text = if sprintToggle then "🏃\nON" else "🏃\nSprint"
	end)

	refreshExtras = function()
		local s = state
		if not s then
			return
		end
		shardsText.Text = "💠 " .. Format(s.Shards or 0) .. " Boss Shards"
		if lastShards >= 0 and (s.Shards or 0) > lastShards then
			pop(shardsPop, 1.25)
		end
		lastShards = s.Shards or 0
		setColors(sprintGrad, if sprintToggle then COLORS.Green else COLORS.Gray)
		local window = openName and windows[openName]
		if window and (openName == "Egg" or openName == "Gadgets" or openName == "DimShop") and window.OnOpen then
			window.OnOpen()
		end
	end
end

--------------------------------------------------------------------------------
-- EGG WINDOW (see the pets in an egg, and hatch it)
--------------------------------------------------------------------------------
local openEgg: (eggId: number) -> ()
do
	local eggWindow = makeWindow("Egg", "🥚 EGG", 800, 560, COLORS.Gold)
	local eggInfo = label({ Text = "", Size = UDim2.new(1, 0, 0, 28), Parent = eggWindow.Body })
	local petRow = new("Frame", { Size = UDim2.new(1, 0, 0, 286), Position = UDim2.fromOffset(0, 36), BackgroundTransparency = 1, Parent = eggWindow.Body })
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = petRow,
	})
	label({
		Text = "Pets give you more gems: a +30% pet makes every crystal give 30% more gems!\nYour best 3 pets are equipped by themselves.   ✅ Green = you have it",
		Size = UDim2.new(1, 0, 0, 44),
		Position = UDim2.fromOffset(0, 330),
		TextColor3 = Color3.fromRGB(215, 215, 235),
		Stroke = 0,
		Parent = eggWindow.Body,
	})
	local currentEgg: number? = nil
	type EggCard = { Index: number, Model: Model, Base: CFrame, Grad: UIGradient, Shine: UIGradient, Status: TextLabel, Stroke: UIStroke }
	local eggCards: { EggCard } = {}

	local function hatch(amount: number)
		if currentEgg then
			R.Hatch:FireServer(currentEgg, amount)
		end
	end
	local _, oneLabel, oneGrad = button({
		Size = UDim2.fromOffset(300, 64),
		Position = UDim2.new(0.5, -10, 1, -4),
		AnchorPoint = Vector2.new(1, 1),
		Text = "",
		Colors = COLORS.Green,
		Radius = 18,
		Parent = eggWindow.Body,
		OnClick = function()
			hatch(1)
		end,
	})
	local _, threeLabel, threeGrad = button({
		Size = UDim2.fromOffset(300, 64),
		Position = UDim2.new(0.5, 10, 1, -4),
		AnchorPoint = Vector2.new(0, 1),
		Text = "",
		Colors = COLORS.Green,
		Radius = 18,
		Parent = eggWindow.Body,
		OnClick = function()
			hatch(3)
		end,
	})

	local function buildCards(egg)
		for _, child in ipairs(petRow:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		table.clear(eggCards)
		for k, entry in ipairs(egg.Pets) do
			local def = Shared.GetPet(entry.Index)
			local frame = new("Frame", { Name = "EggPet" .. k, Size = UDim2.fromOffset(142, 282), BackgroundColor3 = WHITE, LayoutOrder = k, Parent = petRow })
			round(frame, 16)
			local stroke = outline(frame, 4)
			local grad = gradient(frame, COLORS.Gray)
			-- a shiny stripe that slides over the card
			local shineFrame = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 0, ZIndex = 2, Parent = frame })
			round(shineFrame, 16)
			local shine = new("UIGradient", {
				Rotation = 25,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.42, 1),
					NumberSequenceKeypoint.new(0.5, 0.65),
					NumberSequenceKeypoint.new(0.58, 1),
					NumberSequenceKeypoint.new(1, 1),
				}),
				Parent = shineFrame,
			})
			local viewport = new("ViewportFrame", {
				Size = UDim2.new(1, -14, 0, 112),
				Position = UDim2.fromOffset(7, 7),
				BackgroundColor3 = Color3.new(0, 0, 0),
				BackgroundTransparency = 0.7,
				Ambient = Color3.fromRGB(200, 200, 210),
				LightColor = WHITE,
				LightDirection = Vector3.new(-1, -1, -1),
				ZIndex = 3,
				Parent = frame,
			})
			round(viewport, 12)
			local cam = new("Camera", { FieldOfView = 32, Parent = viewport })
			viewport.CurrentCamera = cam
			local m = Shared.BuildPet(entry.Index)
			m.Parent = viewport
			fitCamera(cam, m, Vector3.new(0.35, 0.25, -1))
			local function line(text: string, y: number, h: number, color: Color3)
				return label({ Text = text, Size = UDim2.new(1, -12, 0, h), Position = UDim2.fromOffset(6, y), TextColor3 = color, ZIndex = 3, Parent = frame })
			end
			line(def.Name, 124, 26, WHITE)
			line(string.upper(def.Rarity), 152, 20, Shared.RarityColor(def.Rarity))
			line("🎲 " .. string.format("%g", entry.Chance) .. "%", 176, 24, Color3.fromRGB(255, 240, 170))
			line("💎 " .. Shared.BonusText(def.Bonus) .. " gems", 204, 22, Color3.fromRGB(150, 235, 255))
			local status = line("", 240, 26, WHITE)
			table.insert(eggCards, { Index = entry.Index, Model = m, Base = m:GetPivot(), Grad = grad, Shine = shine, Status = status, Stroke = stroke })
		end
	end

	local function refresh()
		local s = state
		local egg = currentEgg and Shared.GetEgg(currentEgg)
		if not (s and egg) then
			return
		end
		eggWindow.Title.Text = "🥚 " .. string.upper(egg.Name)
		eggInfo.Text = "💰 " .. Format(egg.Price) .. " per egg" .. (if s.FreeEggs > 0 then "   •   🎁 You have " .. s.FreeEggs .. " free " .. (if s.FreeEggs == 1 then "egg" else "eggs") .. "!" else "")
		for _, card in ipairs(eggCards) do
			local count = ownedPets[card.Index] or 0
			if count > 0 then
				setColors(card.Grad, COLORS.Green)
				card.Stroke.Color = Color3.fromRGB(120, 255, 140)
				card.Status.Text = "✅ You have " .. count
			else
				setColors(card.Grad, COLORS.Gray)
				card.Stroke.Color = OUTLINE
				card.Status.Text = "❔ Not found yet"
			end
		end
		local free = s.FreeEggs > 0
		oneLabel.Text = if free then "🥚 Hatch 1  (🎁 FREE)  [E]" else "🥚 Hatch 1  💰 " .. Format(egg.Price) .. "  [E]"
		threeLabel.Text = "🥚🥚🥚 Hatch 3  💰 " .. Format(egg.Price * 3) .. "  [R]"
		setColors(oneGrad, if free or s.Coins >= egg.Price then COLORS.Green else COLORS.Red)
		setColors(threeGrad, if s.Coins >= egg.Price * 3 then COLORS.Green else COLORS.Red)
	end
	eggWindow.OnOpen = refresh

	openEgg = function(eggId: number)
		local egg = Shared.GetEgg(eggId)
		if not egg then
			return
		end
		if currentEgg ~= eggId then
			currentEgg = eggId
			buildCards(egg)
		end
		openWindow("Egg", true)
		refresh()
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or openName ~= "Egg" then
			return
		end
		if input.KeyCode == Enum.KeyCode.E then
			hatch(1)
		elseif input.KeyCode == Enum.KeyCode.R then
			hatch(3)
		end
	end)

	RunService.RenderStepped:Connect(function()
		if openName ~= "Egg" then
			return
		end
		local t = os.clock()
		for k, card in ipairs(eggCards) do
			turnModel(card.Model, card.Base, math.sin(t * 1.4 + k) * 0.5)
			card.Shine.Offset = Vector2.new(((t * 0.5 + k * 0.2) % 2) - 1, 0)
		end
	end)
end

--------------------------------------------------------------------------------
-- GADGET SHOP
--------------------------------------------------------------------------------
do
	local gadgetWindow = makeWindow("Gadgets", "⚡ GADGET SHOP", 780, 560, COLORS.Purple)
	label({
		Text = "Gadgets are yours forever. Click an owned gadget to turn it ON or OFF. (They turn off in the obby.)",
		Size = UDim2.new(1, 0, 0, 24),
		TextColor3 = Color3.fromRGB(220, 215, 240),
		Stroke = 0,
		Parent = gadgetWindow.Body,
	})
	local grid = new("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, -34),
		Position = UDim2.fromOffset(0, 34),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = WHITE,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = gadgetWindow.Body,
	})
	new("UIGridLayout", { CellSize = UDim2.fromOffset(166, 228), CellPadding = UDim2.fromOffset(12, 12), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
	new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 10), Parent = grid })
	type GadgetCard = { Index: number, Label: TextLabel, Grad: UIGradient, Model: Model, Base: CFrame }
	local gadgetCards: { GadgetCard } = {}
	for i, def in ipairs(Shared.Gadgets) do
		local frame = new("Frame", { Name = "Gadget" .. i, BackgroundColor3 = WHITE, LayoutOrder = i, Parent = grid })
		round(frame, 16)
		outline(frame, 3)
		gradient(frame, { def.Color:Lerp(WHITE, 0.1), def.Color:Lerp(Color3.new(0, 0, 0), 0.55) })
		local viewport = new("ViewportFrame", {
			Size = UDim2.new(1, -16, 0, 100),
			Position = UDim2.fromOffset(8, 8),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.72,
			Ambient = Color3.fromRGB(190, 190, 200),
			LightColor = WHITE,
			LightDirection = Vector3.new(-1, -1, -1),
			Parent = frame,
		})
		round(viewport, 12)
		local cam = new("Camera", { FieldOfView = 34, Parent = viewport })
		viewport.CurrentCamera = cam
		local m = Shared.BuildGadget(i)
		m.Parent = viewport
		fitCamera(cam, m, Vector3.new(0.8, 0.35, -0.6))
		label({ Text = def.Name, Size = UDim2.new(1, -12, 0, 26), Position = UDim2.fromOffset(6, 112), Parent = frame })
		label({ Text = Shared.GadgetText(def), Size = UDim2.new(1, -12, 0, 22), Position = UDim2.fromOffset(6, 140), TextColor3 = Color3.fromRGB(255, 240, 160), Parent = frame })
		local _, buyLabel, buyGrad = button({
			Size = UDim2.new(1, -18, 0, 42),
			Position = UDim2.new(0.5, 0, 1, -8),
			AnchorPoint = Vector2.new(0.5, 1),
			Text = "",
			Colors = COLORS.Green,
			Parent = frame,
			OnClick = function()
				local s = state
				if s and table.find(s.Gadgets or {}, i) then
					R.GadgetToggle:FireServer(i)
				else
					R.Buy:FireServer("Gadget", i)
				end
			end,
		})
		table.insert(gadgetCards, { Index = i, Label = buyLabel, Grad = buyGrad, Model = m, Base = m:GetPivot() })
	end
	gadgetWindow.OnOpen = function()
		local s = state
		if not s then
			return
		end
		for _, card in ipairs(gadgetCards) do
			local def = Shared.Gadgets[card.Index]
			if table.find(s.Gadgets or {}, card.Index) then
				local off = table.find(s.GadgetsOff or {}, card.Index) ~= nil
				card.Label.Text = if off then "⭕ OFF" else "✅ ON"
				setColors(card.Grad, if off then COLORS.Gray else COLORS.Blue)
			else
				card.Label.Text = "💰 " .. Format(def.Price)
				setColors(card.Grad, if s.Coins >= def.Price then COLORS.Green else COLORS.Red)
			end
		end
	end
	RunService.RenderStepped:Connect(function()
		if openName ~= "Gadgets" then
			return
		end
		local t = os.clock()
		for _, card in ipairs(gadgetCards) do
			turnModel(card.Model, card.Base, t * 0.9)
		end
	end)
end

--------------------------------------------------------------------------------
-- SPECIAL SHOP IN EVERY DIMENSION
--------------------------------------------------------------------------------
local openDimShop: (d: number) -> ()
do
	local window = makeWindow("DimShop", "💠 SPECIAL SHOP", 700, 520, COLORS.Cyan)
	local info = label({ Text = "", Size = UDim2.new(1, 0, 0, 28), Parent = window.Body })
	label({
		Text = "These are only sold in this dimension! Beat the 👑 diamond bosses to get 💠 Boss Shards.",
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.fromOffset(0, 30),
		TextColor3 = Color3.fromRGB(215, 230, 240),
		Stroke = 0,
		Parent = window.Body,
	})
	local row = new("Frame", { Size = UDim2.new(1, 0, 1, -64), Position = UDim2.fromOffset(0, 64), BackgroundTransparency = 1, Parent = window.Body })
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 20), Parent = row })
	local shopDim: number? = nil
	type DimCard = { Frame: Frame, Viewport: ViewportFrame, Camera: Camera, Model: Model?, Name: TextLabel, Stat: TextLabel, Label: TextLabel, Grad: UIGradient }
	local function makeDimCard(kind: string): DimCard
		local frame = new("Frame", { Size = UDim2.fromOffset(300, 370), BackgroundColor3 = WHITE, Parent = row })
		round(frame, 18)
		outline(frame, 3)
		gradient(frame, COLORS.Galaxy)
		local viewport = new("ViewportFrame", {
			Size = UDim2.new(1, -20, 0, 170),
			Position = UDim2.fromOffset(10, 10),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.7,
			Ambient = Color3.fromRGB(190, 190, 200),
			LightColor = WHITE,
			LightDirection = Vector3.new(-1, -1, -1),
			Parent = frame,
		})
		round(viewport, 14)
		local cam = new("Camera", { FieldOfView = 34, Parent = viewport })
		viewport.CurrentCamera = cam
		local nameLabel = label({ Text = "", Size = UDim2.new(1, -16, 0, 32), Position = UDim2.fromOffset(8, 188), Parent = frame })
		local stat = label({ Text = "", Size = UDim2.new(1, -16, 0, 26), Position = UDim2.fromOffset(8, 224), TextColor3 = Color3.fromRGB(255, 240, 160), Parent = frame })
		local _, buyLabel, buyGrad = button({
			Size = UDim2.new(1, -24, 0, 56),
			Position = UDim2.new(0.5, 0, 1, -10),
			AnchorPoint = Vector2.new(0.5, 1),
			Text = "",
			Colors = COLORS.Green,
			Radius = 16,
			Parent = frame,
			OnClick = function()
				if shopDim then
					R.Buy:FireServer(kind, shopDim)
				end
			end,
		})
		return { Frame = frame, Viewport = viewport, Camera = cam, Name = nameLabel, Stat = stat, Label = buyLabel, Grad = buyGrad }
	end
	local pickCard = makeDimCard("DimPickaxe")
	local packCard = makeDimCard("DimBackpack")
	local function setModel(card: DimCard, m: Model, direction: Vector3)
		if card.Model then
			card.Model:Destroy()
		end
		card.Model = m
		m.Parent = card.Viewport
		fitCamera(card.Camera, m, direction)
	end
	local function refresh()
		local s = state
		local d = shopDim
		if not (s and d) then
			return
		end
		local pick = Shared.DimensionPickaxe(d)
		local pack = Shared.DimensionBackpack(d)
		window.Title.Text = "💠 SPECIAL SHOP  •  DIMENSION " .. d
		info.Text = "💠 You have " .. Format(s.Shards or 0) .. " Boss Shards    💰 " .. Format(s.Coins) .. " coins"
		pickCard.Name.Text = pick.Name
		pickCard.Stat.Text = "⛏️ Power " .. Format(pick.Power)
		packCard.Name.Text = pack.Name
		packCard.Stat.Text = "🎒 Holds " .. Format(pack.Capacity)
		local bestPick = Shared.BestPickaxe(s)
		local bestPack = Shared.BestBackpack(s)
		if pick.Power <= bestPick.Power then
			pickCard.Label.Text = if s.DimPickaxe == d then "EQUIPPED" else "You have a better one"
			setColors(pickCard.Grad, COLORS.Gray)
		else
			pickCard.Label.Text = "💠 " .. pick.Shards .. " Boss Shards"
			setColors(pickCard.Grad, if (s.Shards or 0) >= pick.Shards then COLORS.Green else COLORS.Red)
		end
		if pack.Capacity <= bestPack.Capacity then
			packCard.Label.Text = if s.DimBackpack == d then "EQUIPPED" else "You have a bigger one"
			setColors(packCard.Grad, COLORS.Gray)
		else
			packCard.Label.Text = "💰 " .. Format(pack.Price)
			setColors(packCard.Grad, if s.Coins >= pack.Price then COLORS.Green else COLORS.Red)
		end
	end
	window.OnOpen = refresh
	openDimShop = function(d: number)
		if shopDim ~= d then
			shopDim = d
			setModel(pickCard, Shared.BuildPickaxe(Shared.DimensionPickaxe(d)), Vector3.new(1, 0.2, 0.25))
			setModel(packCard, Shared.BuildBackpack(Shared.DimensionBackpack(d)), Vector3.new(0.45, 0.3, 1))
		end
		openWindow("DimShop", true)
		refresh()
	end
	RunService.RenderStepped:Connect(function()
		if openName ~= "DimShop" then
			return
		end
		local t = os.clock()
		for _, card in ipairs({ pickCard, packCard }) do
			local m = card.Model
			if m then
				turnModel(m, CFrame.new(), t * 0.9)
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- CIRCLES ON THE GROUND (step in one and its window opens)
--------------------------------------------------------------------------------
do
	local inside: BasePart? = nil
	local openedWindow: string? = nil
	local function enter(circle: BasePart)
		local action = circle:GetAttribute("Action")
		local arg = circle:GetAttribute("Arg")
		local window: string? = nil
		if action == "Pickaxes" then
			openShop("Pickaxe")
			window = "Shop"
		elseif action == "Backpacks" then
			openShop("Backpack")
			window = "Shop"
		elseif action == "Pets" then
			openShop("Pet")
			window = "Shop"
		elseif action == "Shop" then
			openShop(nil)
			window = "Shop"
		elseif action == "Gadgets" or action == "Rebirth" or action == "Dimensions" then
			openWindow(action, true)
			window = action
		elseif action == "Egg" and type(arg) == "number" then
			openEgg(arg)
			window = "Egg"
		elseif action == "DimShop" and type(arg) == "number" then
			openDimShop(arg)
			window = "DimShop"
		elseif action == "Wheel" then
			openWindow("Wheel", true)
			window = "Wheel"
		elseif action == "Home" then
			R.Teleport:FireServer(0)
		end
		if window then
			playSound("Click", 1.2, 0.5)
		end
		openedWindow = window
	end
	task.spawn(function()
		while true do
			task.wait(0.1)
			local root = myRoot()
			local found: BasePart? = nil
			if root then
				for _, circle in ipairs(CollectionService:GetTagged("ActionCircle")) do
					if circle:IsA("BasePart") and circle.Parent then
						local radius = circle:GetAttribute("Radius")
						local flat = Vector3.new(root.Position.X - circle.Position.X, 0, root.Position.Z - circle.Position.Z)
						if type(radius) == "number" and flat.Magnitude < radius and math.abs(root.Position.Y - circle.Position.Y) < 7 then
							found = circle
							break
						end
					end
				end
			end
			if found ~= inside then
				-- walking out of a circle closes the window it opened
				if openedWindow and openName == openedWindow then
					closeWindow()
				end
				openedWindow = nil
				inside = found
				if found then
					enter(found)
				end
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- BOSSES (they float around smoothly and look at you) AND THEIR ATTACKS
--------------------------------------------------------------------------------
do
	type BossView = { Pos: Vector3, Yaw: number }
	local views: { [Model]: BossView } = setmetatable({}, { __mode = "k" }) :: any
	local bossModels: { [Model]: boolean } = {}
	local function track(inst: Instance)
		if inst:IsA("Model") then
			bossModels[inst] = true
		end
	end
	for _, inst in ipairs(CollectionService:GetTagged("Boss")) do
		track(inst)
	end
	CollectionService:GetInstanceAddedSignal("Boss"):Connect(track)
	CollectionService:GetInstanceRemovedSignal("Boss"):Connect(function(inst)
		bossModels[inst :: Model] = nil
	end)
	RunService.RenderStepped:Connect(function(dt)
		local root = myRoot()
		local t = os.clock()
		for m in pairs(bossModels) do
			local target = m:GetAttribute("BossPos")
			if m.Parent and typeof(target) == "Vector3" then
				local view = views[m]
				if not view then
					view = { Pos = target, Yaw = 0 }
					views[m] = view
				end
				view.Pos = view.Pos:Lerp(target, math.min(1, dt * 5))
				local pos = view.Pos + Vector3.new(0, math.sin(t * 2) * 0.6, 0)
				if root and (root.Position - pos).Magnitude < 70 then
					local want = math.atan2(-(root.Position.X - pos.X), -(root.Position.Z - pos.Z))
					local diff = (want - view.Yaw + math.pi) % (math.pi * 2) - math.pi
					view.Yaw += diff * math.min(1, dt * 4)
				else
					view.Yaw += dt * 0.5
				end
				placeModel(m, CFrame.new(pos) * CFrame.Angles(0, view.Yaw, 0))
			end
		end
	end)

	-- a red circle shows where the attack will land (jump away!)
	local function warningCircle(spot: Vector3, time: number)
		local ring = new("Part", {
			Name = "BossWarning",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.2, 1, 1),
			CFrame = CFrame.new(spot + Vector3.new(0, 0.25, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(255, 60, 60),
			Material = Enum.Material.Neon,
			Transparency = 0.4,
			Anchored = true,
			CanCollide = false,
			CanTouch = false,
			CastShadow = false,
			Parent = FxFolder,
		})
		tween(ring, time, { Size = Vector3.new(0.2, 10, 10), Transparency = 0.6 })
		Debris:AddItem(ring, time + 0.05)
	end

	R.Effect.OnClientEvent:Connect(function(kind, a, b, c, d)
		if kind == "bossattack" then
			local m: Model?, from: Vector3, spot: Vector3 = a, b, c
			local view = m and views[m]
			local start = if view then view.Pos else from
			warningCircle(spot, 0.8)
			local shard = new("Part", {
				Name = "BossShard",
				Size = Vector3.new(1, 2.2, 1),
				CFrame = CFrame.new(start),
				Color = if m and m.PrimaryPart then m.PrimaryPart.Color else Color3.fromRGB(150, 220, 255),
				Material = Enum.Material.Glass,
				Reflectance = 0.3,
				Anchored = true,
				CanCollide = false,
				CanTouch = false,
				Parent = FxFolder,
			})
			local began = os.clock()
			local connection: RBXScriptConnection
			connection = RunService.RenderStepped:Connect(function()
				local k = math.clamp((os.clock() - began) / 0.8, 0, 1)
				local function along(x: number): Vector3
					return start:Lerp(spot, x) + Vector3.new(0, math.sin(x * math.pi) * 6, 0)
				end
				local pos = along(k)
				local ahead = along(math.min(k + 0.05, 1)) - pos
				-- point the shard the way it flies
				shard.CFrame = if ahead.Magnitude > 0.01 then CFrame.lookAt(pos, pos + ahead) * CFrame.Angles(math.rad(90), 0, 0) else CFrame.new(pos)
				if k >= 1 then
					connection:Disconnect()
					shard:Destroy()
					burst(spot, Color3.fromRGB(255, 120, 120), 18, 22, 0.7)
					chips(spot, Color3.fromRGB(120, 110, 100), 4)
					local position = rootPosition()
					if position and (position - spot).Magnitude < 40 then
						playSound("Boom", 2, 0.25)
					end
				end
			end)
		elseif kind == "bossouch" then
			local flash = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(255, 40, 40), BackgroundTransparency = 0.6, ZIndex = 30, Parent = fxGui })
			tween(flash, 0.4, { BackgroundTransparency = 1 })
			Debris:AddItem(flash, 0.5)
			playSound("Hit", 0.8, 0.6)
		elseif kind == "bosshit" then
			local position: Vector3, damage: number = a, b
			local m: Model? = c
			local view = m and views[m]
			local at = if view then view.Pos else position
			burst(at, Color3.new(1, 1, 1), 8, 18, 0.5)
			worldText(at + Vector3.new(0, 3, 0), "-" .. Format(damage), Color3.fromRGB(255, 120, 120), 34)
			playSound("Hit", 1.2 + math.random() * 0.3, 0.5)
		elseif kind == "bossdefeat" then
			local position: Vector3, color: Color3 = a, b
			burst(position, color, 60, 50, 1.6)
			burst(position, Color3.new(1, 1, 1), 30, 35, 1)
			shards(position, color, 20, false)
			dust(position - Vector3.new(0, 4, 0), Color3.fromRGB(175, 170, 162), 16, 2.5)
			local near = rootPosition()
			if near and (near - position).Magnitude < 120 then
				playSound("Boom", 0.8, 0.6)
			end
		elseif kind == "bossreward" then
			local name: string, coins: number, gotShards: number, xp: number = a, b, c, d
			showBanner("👑 YOU BEAT THE " .. string.upper(name) .. "!", Color3.fromRGB(255, 215, 110))
			toast("💠 +" .. gotShards .. " Boss Shards   💰 +" .. Format(coins) .. "   ⭐ +" .. Format(xp) .. " XP", "gold")
			local position = rootPosition()
			if position then
				flyIcons(position, "💰", coinsPill, coinsPop, 10)
			end
			celebrate(10, 0.9)
		elseif kind == "bossspawn" then
			local position: Vector3, color: Color3 = a, b
			local near = rootPosition()
			if near and (near - position).Magnitude < 90 then
				burst(position, color, 30, 25, 1)
				toast("👑 The diamond boss is back!", "info")
			end
		elseif kind == "dig" then
			local position: Vector3, damage: number = a, b
			dust(position, Color3.fromRGB(140, 110, 80), 4, 1.1)
			chips(position + Vector3.new(0, 0.5, 0), Color3.fromRGB(110, 84, 60), 3)
			worldText(position + Vector3.new(0, 2, 0), "-" .. Format(damage), WHITE, 22)
			playSound("Hit", 0.9 + math.random() * 0.2, 0.4)
		elseif kind == "dugout" then
			local position: Vector3, color: Color3 = a, b
			dust(position, Color3.fromRGB(140, 110, 80), 14, 2)
			chips(position + Vector3.new(0, 0.5, 0), Color3.fromRGB(110, 84, 60), 8)
			burst(position + Vector3.new(0, 1, 0), color, 20, 20, 0.8)
			local near = rootPosition()
			if near and (near - position).Magnitude < 60 then
				playSound("Splash", 0.6, 0.3)
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- MINING (click / tap / hold on crystals)
--------------------------------------------------------------------------------
do
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	local function crystalAt(point: Vector2, isViewportPoint: boolean): Model?
		local ray = if isViewportPoint then camera:ViewportPointToRay(point.X, point.Y) else camera:ScreenPointToRay(point.X, point.Y)
		local ignore: { Instance } = { PetFolder, WallFolder, FxFolder }
		if player.Character then
			table.insert(ignore, player.Character)
		end
		rayParams.FilterDescendantsInstances = ignore
		local result = Workspace:Raycast(ray.Origin, ray.Direction * 400, rayParams)
		if result then
			local m = result.Instance.Parent
			if m and m:IsA("Model") and (m:GetAttribute("IsCrystal") or m:GetAttribute("IsBoss") or m:GetAttribute("IsDigSpot")) then
				return m
			end
		end
		return nil
	end

	local function inRange(m: Model): boolean
		local root = myRoot()
		if not root then
			return false
		end
		local radius = m:GetAttribute("Radius") or 2
		return (root.Position - m:GetPivot().Position).Magnitude <= Settings.MineRange + radius
	end

	local lastSwing = 0
	local lastFarHint = 0
	local lastToolHint = 0
	local swings = 0

	local function heldTool(): string?
		local char = player.Character
		local tool = char and char:FindFirstChildOfClass("Tool")
		return if tool then tool.Name else nil
	end

	-- Swinging at nothing (or something you can't mine): just a swing, everyone sees it
	local FREE_SWING_TIME = 0.32
	local function freeSwing(tool: string?, now: number)
		if tool ~= "Pickaxe" and tool ~= "Shovel" then
			return
		end
		if now - lastSwing < FREE_SWING_TIME then
			return
		end
		lastSwing = now
		local kind = if tool == "Shovel" then "dig" else "swing"
		playSwing(kind)
		R.Swing:FireServer(kind)
		playSound("Click", 0.45, 0.15)
	end

	local function tryMine(point: Vector2, isViewportPoint: boolean)
		local now = os.clock()
		if now - lastSwing < Settings.MineCooldown then
			return
		end
		local tool = heldTool()
		local m = crystalAt(point, isViewportPoint)
		if not m then
			freeSwing(tool, now)
			return
		end
		local digSpot = m:GetAttribute("IsDigSpot") == true
		local needed = if digSpot then "Shovel" else "Pickaxe"
		if tool ~= needed then
			if now - lastToolHint > 2.5 then
				lastToolHint = now
				if digSpot then
					toast("🪣 Hold your SHOVEL (press 2) to dig up buried gems!", "info")
				else
					toast("⛏️ Hold your PICKAXE (press 1) to mine!", "info")
				end
			end
			freeSwing(tool, now)
			return
		end
		if not inRange(m) then
			if now - lastFarHint > 2.5 then
				lastFarHint = now
				toast("🏃 Walk closer!", "info")
			end
			freeSwing(tool, now)
			return
		end
		local s = state
		-- bosses and meteors pay coins, so a full backpack doesn't stop you
		local isBoss = m:GetAttribute("IsBoss") == true or m:GetAttribute("Meteor") == true
		if s and s.Gems >= s.Capacity and not isBoss then
			backpackFull()
			freeSwing(tool, now)
			return
		end
		local zone = m:GetAttribute("Zone")
		if s and type(zone) == "number" and zone > s.Zone then
			freeSwing(tool, now)
			return
		end
		lastSwing = now
		if digSpot then
			R.Dig:FireServer(m)
			playSwing("dig")
			R.Swing:FireServer("dig")
		else
			R.Mine:FireServer(m)
			playSwing("swing")
			R.Swing:FireServer("swing")
		end
		swings += 1
		if swings == 6 then
			toast("💡 Tip: hold the mouse button down to keep mining!", "info")
		end
	end

	local holding = false
	local touchPoint: Vector2? = nil
	local gamepadHolding = false

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			holding = true
			touchPoint = nil
			tryMine(UserInputService:GetMouseLocation(), true)
		elseif input.UserInputType == Enum.UserInputType.Touch then
			local point = Vector2.new(input.Position.X, input.Position.Y)
			holding = true
			touchPoint = point
			tryMine(point, false)
		elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
			gamepadHolding = true
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch and touchPoint then
			touchPoint = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			holding = false
			touchPoint = nil
		elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
			gamepadHolding = false
		end
	end)

	-- Outline the crystal under your mouse
	local highlight = new("Highlight", {
		FillColor = WHITE,
		FillTransparency = 0.85,
		OutlineColor = WHITE,
		OutlineTransparency = 0,
		DepthMode = Enum.HighlightDepthMode.Occluded,
		Enabled = false,
		Parent = camera,
	})

	RunService.Heartbeat:Connect(function()
		if holding then
			if touchPoint then
				tryMine(touchPoint, false)
			else
				tryMine(UserInputService:GetMouseLocation(), true)
			end
		elseif gamepadHolding then
			tryMine(camera.ViewportSize / 2, true)
		end

		if UserInputService.MouseEnabled and not openName then
			local m = crystalAt(UserInputService:GetMouseLocation(), true)
			if m then
				highlight.Adornee = m
				highlight.OutlineColor = if inRange(m) then WHITE else Color3.fromRGB(255, 90, 90)
				highlight.Enabled = true
			else
				highlight.Enabled = false
			end
		else
			highlight.Enabled = false
		end
	end)
end

--------------------------------------------------------------------------------
-- PETS FOLLOW THEIR OWNERS, DECORATIONS SPIN
--------------------------------------------------------------------------------
do
	local PET_OFFSETS = { Vector3.new(-3.4, 0, 3.2), Vector3.new(3.4, 0, 3.2), Vector3.new(0, 0, 5.6) }


	local petCFrames: { [Model]: CFrame } = setmetatable({}, { __mode = "k" }) :: any

	-- Angle = how far it has turned. It speeds up smoothly when it first shows up.
	type Spinner = { Base: CFrame, Speed: number, Bob: number, Phase: number, Angle: number, Ease: number }
	local spinners: { [Instance]: Spinner } = {}

	local function addSpinner(inst: Instance)
		local base: CFrame
		if inst:IsA("BasePart") then
			base = inst.CFrame
		elseif inst:IsA("Model") then
			base = inst:GetPivot()
		else
			return
		end
		local phase = math.random() * 6
		spinners[inst] = {
			Base = base,
			Speed = inst:GetAttribute("SpinSpeed") or 1,
			Bob = inst:GetAttribute("Bob") or 0,
			Phase = phase,
			Angle = phase,
			Ease = 0,
		}
	end
	for _, inst in ipairs(CollectionService:GetTagged("Spin")) do
		addSpinner(inst)
	end
	CollectionService:GetInstanceAddedSignal("Spin"):Connect(addSpinner)
	CollectionService:GetInstanceRemovedSignal("Spin"):Connect(function(inst)
		spinners[inst] = nil
	end)

	RunService.RenderStepped:Connect(function(dt)
		local t = os.clock()

		-- pets
		for _, pet in ipairs(PetFolder:GetChildren()) do
			if pet:IsA("Model") and pet.PrimaryPart then
				local owner = Players:GetPlayerByUserId(pet:GetAttribute("Owner") or 0)
				local char = owner and owner.Character
				local root = char and char:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") then
					local slot = pet:GetAttribute("Slot") or 1
					local scale = pet:GetAttribute("Scale") or 1
					local offset = PET_OFFSETS[slot] or PET_OFFSETS[1]
					local moving = root.AssemblyLinearVelocity.Magnitude > 2
					local hop = if moving then math.abs(math.sin(t * 9 + slot)) * 1.1 else math.sin(t * 3 + slot) * 0.3 + 0.3
					local spot = (root.CFrame * CFrame.new(offset)).Position
					local look = root.CFrame.LookVector
					local position = Vector3.new(spot.X, root.Position.Y - 1.6 + (scale - 1) * 1.1 + hop, spot.Z)
					local target = CFrame.lookAt(position, position + Vector3.new(look.X, 0, look.Z) + Vector3.new(0, 0, 0.001))
					local current = petCFrames[pet] or target
					current = current:Lerp(target, math.min(1, dt * 9))
					petCFrames[pet] = current
					placeModel(pet, current)
				end
			end
		end

		-- spinning things: a calm turn, a soft float up and down and a little sway
		local step = math.min(dt, 0.1)
		for inst, info in pairs(spinners) do
			if inst.Parent then
				info.Ease = math.min(1, info.Ease + step * 0.8)
				info.Angle += step * info.Speed * 0.75 * info.Ease
				local wave = t * 1.2 + info.Phase
				local lift = math.sin(wave) * info.Bob
				local swayX = math.sin(wave * 0.7) * 0.05
				local swayZ = math.cos(wave * 0.55) * 0.05
				if inst:IsA("BasePart") then
					inst.CFrame = CFrame.new(info.Base.Position + Vector3.new(0, lift, 0)) * CFrame.Angles(swayX, info.Angle, swayZ) * info.Base.Rotation
				elseif inst:IsA("Model") then
					turnModel(inst, info.Base, info.Angle, lift, swayX, swayZ)
				end
			end
		end

		-- spin the models in the shop and pets window while they are open
		if openName == "Shop" then
			for _, card in ipairs(cards) do
				if card.Frame.Visible then
					turnModel(card.Model, card.Base, t * 0.9)
				end
			end
		elseif openName == "Pets" then
			for _, card in ipairs(petCards) do
				turnModel(card.Model, card.Base, t * 0.9)
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- ZONE MOODS (the sky changes in each zone) AND GATES
--------------------------------------------------------------------------------
local atmosphere = Lighting:WaitForChild("CrystalRushAtmosphere", 10) :: Atmosphere?
local colorFx = Lighting:WaitForChild("CrystalRushColor", 10) :: ColorCorrectionEffect?
local bloomFx = Lighting:WaitForChild("CrystalRushBloom", 10) :: BloomEffect?
local currentArea = ""

local function applyMood(mood, instant: boolean?)
	local time = if instant then 0 else 2.5
	local info = TweenInfo.new(time, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	TweenService:Create(Lighting, info, {
		ClockTime = mood.ClockTime,
		Brightness = mood.Brightness,
		Ambient = mood.Ambient,
		OutdoorAmbient = mood.OutdoorAmbient,
		ExposureCompensation = mood.Exposure,
	}):Play()
	if atmosphere then
		TweenService:Create(atmosphere, info, {
			Density = mood.Density,
			Haze = mood.Haze,
			Glare = mood.Glare,
			Color = mood.AtmosphereColor,
			Decay = mood.Decay,
		}):Play()
	end
	if colorFx then
		TweenService:Create(colorFx, info, {
			TintColor = mood.Tint,
			Saturation = mood.Saturation,
			Contrast = mood.Contrast,
		}):Play()
	end
end

local barsOpen: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local barHome: { [BasePart]: CFrame } = setmetatable({}, { __mode = "k" }) :: any

local function setBars(gate: Instance, open: boolean, animate: boolean)
	local bars = gate:FindFirstChild("Bars")
	if not bars or (barsOpen[gate] == true) == open then
		return
	end
	barsOpen[gate] = open
	for _, part in ipairs(bars:GetChildren()) do
		if part:IsA("BasePart") then
			local home = barHome[part] or part.CFrame
			barHome[part] = home
			if open and animate then
				tween(part, 1.8, { CFrame = home + Vector3.new(0, 34, 0), Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
			elseif open then
				part.Transparency = 1
			else
				part.CFrame = home
				part.Transparency = 0
			end
		end
	end
	if open and animate then
		playSound("Hit", 0.5, 0.6)
	end
end

updateGate = function(gate: Instance, animate: boolean?)
	local s = state
	local zoneIndex = gate:GetAttribute("Zone")
	if not s or type(zoneIndex) ~= "number" then
		return
	end
	local zone = Shared.Zones[zoneIndex]
	local unlocked = s.Zone >= zoneIndex
	local barrier = gate:FindFirstChild("Barrier")
	if barrier and barrier:IsA("BasePart") then
		barrier.CanCollide = not unlocked
		barrier.CanQuery = not unlocked
		barrier.Transparency = 1
	end
	setBars(gate, unlocked, animate == true)
	for _, d in ipairs(gate:GetDescendants()) do
		if d:IsA("TextLabel") and d.Name == "Title" then
			d.Text = (if unlocked then zone.Emoji .. " " else "🔒 ") .. string.upper(zone.Name)
		elseif d:IsA("TextLabel") and d.Name == "Subtitle" then
			d.Text = if unlocked then "Unlocked!" else "💰 " .. Format(zone.Price) .. " to unlock"
		end
	end
	local pp = gate:FindFirstChildWhichIsA("ProximityPrompt", true)
	if pp then
		pp.Enabled = not unlocked
	end
end

local function updateGates()
	for _, gate in ipairs(GateFolder:GetChildren()) do
		updateGate(gate)
	end
end
GateFolder.ChildAdded:Connect(function(gate)
	task.wait()
	updateGate(gate)
end)

--------------------------------------------------------------------------------
-- SELL GUIDE (a sparkly line pointing to the nearest sell pad when you're full)
--------------------------------------------------------------------------------
local guideBeam: Beam? = nil
local guideStart: Attachment? = nil

local function updateGuide()
	local s = state
	local root = myRoot()
	local inObby = player:GetAttribute("ObbyStart") ~= nil
	local full = s ~= nil and s.Gems >= s.Capacity and not inObby
	fullWarning.Visible = full
	if not full or not root or not s then
		if guideBeam then
			guideBeam.Enabled = false
		end
		return
	end
	local best: Attachment? = nil
	local bestDistance = math.huge
	local here = player:GetAttribute("Dimension")
	for _, pad in ipairs(SellFolder:GetChildren()) do
		local target = pad:FindFirstChild("GuideTarget", true)
		local padDimension = pad:GetAttribute("Dimension")
		local padZone = pad:GetAttribute("Zone")
		local usable
		if padDimension ~= nil then
			usable = padDimension == here
		else
			usable = here == nil and (type(padZone) ~= "number" or s.Zone >= padZone)
		end
		if usable and target and target:IsA("Attachment") then
			local distance = (target.WorldPosition - root.Position).Magnitude
			if distance < bestDistance then
				best, bestDistance = target, distance
			end
		end
	end
	if not best then
		return
	end
	if not guideStart or guideStart.Parent ~= root then
		if guideBeam then
			guideBeam:Destroy()
		end
		guideStart = new("Attachment", { Name = "SellGuide", Parent = root })
		guideBeam = new("Beam", {
			Attachment0 = guideStart,
			Texture = "rbxasset://textures/particles/sparkles_main.dds",
			TextureMode = Enum.TextureMode.Wrap,
			TextureLength = 2,
			TextureSpeed = 2,
			Color = ColorSequence.new(Color3.fromRGB(255, 230, 90), Color3.fromRGB(255, 170, 40)),
			Transparency = NumberSequence.new(0.1),
			LightEmission = 1,
			FaceCamera = true,
			Width0 = 1.2,
			Width1 = 1.2,
			Segments = 20,
			Parent = root,
		})
	end
	local beam = guideBeam :: Beam
	beam.Attachment1 = best
	beam.Enabled = bestDistance > 8
end

--------------------------------------------------------------------------------
-- STATE FROM THE SERVER
--------------------------------------------------------------------------------
local shownCoins, shownGems = 0, 0
local firstSync = true

local function refreshAll()
	local s = state
	if not s then
		return
	end
	local rebirths = s.Rebirths
	local petBoost = Shared.GemMultiplier(ownedPets)
	boostText.Text = string.format(
		"♻️ %d Rebirths  •  x%s 💰  •  x%s 💎",
		rebirths,
		Shared.MultiplierText(Shared.CoinMultiplier(rebirths)),
		Shared.MultiplierText(petBoost)
	)
	local fill = math.clamp(s.Gems / s.Capacity, 0, 1)
	tween(gemsFill, 0.25, { Size = UDim2.fromScale(fill, 1) })
	setColors(gemsFillGrad, if fill >= 1 then COLORS.Gold else COLORS.Cyan)
	local needed = Shared.XPNeeded(s.Level)
	levelText.Text = "⭐ Level " .. s.Level
	local nextZone = Shared.Zones[s.Zone + 1]
	if s.Level >= Shared.MaxLevel(s.Zone) and s.XP >= needed and nextZone then
		xpText.Text = "🔒 Unlock " .. nextZone.Name .. " to level up!"
	else
		xpText.Text = Format(s.XP) .. " / " .. Format(needed) .. " XP"
	end
	tween(levelFill, 0.25, { Size = UDim2.fromScale(math.clamp(s.XP / needed, 0, 1), 1) })
	refreshShop()
	refreshTeleport()
	refreshRebirth()
	refreshPetsWindow()
	refreshDimensions()
	refreshSide()
	refreshGifts()
	refreshDaily()
	updateGates()
	refreshExtras()
end

R.Sync.OnClientEvent:Connect(function(newState: State)
	state = newState
	syncedAt = os.clock()
	ownedPets = {}
	for index, count in ipairs(newState.Pets) do
		if count > 0 then
			ownedPets[index] = count
		end
	end
	for _, entry in ipairs(newState.DimPets or {}) do
		ownedPets[entry.Index] = entry.Count
	end
	equippedPets = {}
	for _, index in ipairs(Shared.GetEquippedPets(ownedPets)) do
		equippedPets[index] = (equippedPets[index] or 0) + 1
	end
	refreshAll()
	if firstSync then
		firstSync = false
		shownCoins, shownGems = newState.Coins, newState.Gems
		if newState.TotalGems == 0 then
			task.delay(1, function()
				showBanner("💎 WELCOME TO CRYSTAL RUSH! 💎", Color3.fromRGB(130, 230, 255))
				toast("⛏️ Walk to the meadow and click crystals to mine them!", "info")
				task.wait(3.5)
				toast("💰 When your backpack is full, step on a SELL pad", "gold")
				task.wait(3.5)
				toast("🏃 Try the SKY OBBY at the spawn for a big coin reward!", "good")
				task.wait(3.5)
				toast("🥚 Hatch eggs at the egg machine to find RARE pets!", "gold")
				task.wait(3.5)
				toast("📜 Finish quests and claim 🎁 free gifts on the right!", "info")
			end)
		end
		if newState.DailyReady then
			task.delay(if newState.TotalGems == 0 then 20 else 2.5, function()
				local s = state
				if s and s.DailyReady and not openName then
					openWindow("Daily", true)
				end
			end)
		end
	end
end)

-- Numbers count up smoothly
RunService.RenderStepped:Connect(function(dt)
	local s = state
	if not s then
		return
	end
	local k = math.min(1, dt * 10)
	shownCoins += (s.Coins - shownCoins) * k
	shownGems += (s.Gems - shownGems) * k
	if math.abs(s.Coins - shownCoins) < 1 then
		shownCoins = s.Coins
	end
	if math.abs(s.Gems - shownGems) < 1 then
		shownGems = s.Gems
	end
	coinsText.Text = Format(shownCoins)
	gemsText.Text = Format(shownGems) .. " / " .. Format(s.Capacity)
end)

--------------------------------------------------------------------------------
-- A SLOW LOOP FOR THINGS THAT DON'T NEED TO RUN EVERY FRAME
--------------------------------------------------------------------------------
task.spawn(function()
	while true do
		local root = myRoot()
		if root then
			local dimension = player:GetAttribute("Dimension")
			local first = currentArea == ""
			if type(dimension) == "number" then
				-- in a dimension: use its sky
				local area = "D" .. dimension
				if area ~= currentArea then
					currentArea = area
					local dim = Shared.GetDimension(dimension)
					applyMood(dim.Mood, first)
					if bloomFx then
						tween(bloomFx, 2, { Intensity = if dim.Shiny then 0.9 else 0.25, Threshold = if dim.Shiny then 1.4 else 2.2 })
					end
					if dim.Shiny then
						showBanner("✨ SHINY DIMENSION " .. dimension .. "! 2x GEMS ✨", Color3.fromRGB(255, 225, 120))
					else
						showBanner("🌌 DIMENSION " .. dimension .. ": " .. string.upper(dim.Name), dim.Accent:Lerp(WHITE, 0.3))
					end
					refreshDimensions()
				end
			else
				local zoneIndex = Shared.ZoneAt(root.Position.Z)
				local area = "Z" .. zoneIndex
				if area ~= currentArea then
					local wasDimension = string.sub(currentArea, 1, 1) == "D"
					currentArea = area
					applyMood(Shared.Zones[math.max(zoneIndex, 1)].Mood, first)
					if bloomFx then
						tween(bloomFx, 2, { Intensity = 0.25, Threshold = 2.2 })
					end
					if zoneIndex > 0 and not first then
						local zone = Shared.Zones[zoneIndex]
						showBanner(zone.Emoji .. " " .. string.upper(zone.Name), zone.Accent:Lerp(WHITE, 0.3))
					elseif wasDimension then
						showBanner("🏠 BACK HOME", Color3.fromRGB(150, 235, 255))
					end
					refreshDimensions()
				end
			end
		end
		updateGuide()
		task.wait(0.3)
	end
end)

--------------------------------------------------------------------------------
-- FUN EXTRAS: 🎡 LUCKY WHEEL, 🦘 BOUNCE PADS, 🎁 TREASURE CHESTS, 🌠 METEORS
--------------------------------------------------------------------------------
do
	local prizes = Shared.WheelPrizes
	local wheelWindow = makeWindow("Wheel", "🎡 LUCKY WHEEL", 660, 470, COLORS.Gold)
	label({
		Text = "Spin for a free prize! You get a new spin every " .. math.floor(Settings.WheelCooldown / 60) .. " minutes.",
		Size = UDim2.new(1, 0, 0, 26),
		TextColor3 = Color3.fromRGB(235, 230, 215),
		Stroke = 0,
		Parent = wheelWindow.Body,
	})
	-- 8 prize tiles in a ring: the top row goes right, the bottom row comes back
	local tiles: { { Frame: Frame, Light: Frame } } = {}
	for k, prize in ipairs(prizes) do
		local row = if k <= 4 then 0 else 1
		local col = if k <= 4 then k - 1 else 8 - k
		local frame = new("Frame", {
			Name = "Prize" .. k,
			Size = UDim2.fromOffset(142, 118),
			Position = UDim2.fromOffset(8 + col * 156, 40 + row * 132),
			BackgroundColor3 = WHITE,
			Parent = wheelWindow.Body,
		})
		round(frame, 16)
		outline(frame, 3)
		gradient(frame, { prize.Color:Lerp(WHITE, 0.2), prize.Color:Lerp(Color3.new(0, 0, 0), 0.4) })
		label({ Text = prize.Text, Size = UDim2.new(1, -12, 0, 56), Position = UDim2.fromOffset(6, 12), TextWrapped = true, Parent = frame })
		label({ Text = "🎲 " .. string.format("%g", prize.Chance) .. "%", Size = UDim2.new(1, -12, 0, 24), Position = UDim2.fromOffset(6, 80), TextColor3 = Color3.fromRGB(255, 245, 200), Parent = frame })
		local glow = new("Frame", { Name = "Light", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 1, ZIndex = 3, Parent = frame })
		round(glow, 16)
		tiles[k] = { Frame = frame, Light = glow }
	end
	-- Spinning: is it turning right now? Angle: how far the big wheel at the spawn has turned
	local W: { Spinning: boolean, Angle: number, Model: Model?, Base: CFrame? } = { Spinning = false, Angle = 0, Model = nil, Base = nil }
	local _, spinLabel, spinGrad = button({
		Size = UDim2.fromOffset(360, 66),
		Position = UDim2.new(0.5, 0, 1, -4),
		AnchorPoint = Vector2.new(0.5, 1),
		Text = "🎡 SPIN!",
		Colors = COLORS.Green,
		Radius = 18,
		Parent = wheelWindow.Body,
		OnClick = function()
			local s = state
			if W.Spinning or not s then
				return
			end
			if s.WheelWait - (os.clock() - syncedAt) > 0 then
				toast("⏳ The wheel needs a little rest. Come back soon!", "info")
				return
			end
			W.Spinning = true
			R.Spin:FireServer()
			task.delay(4, function()
				W.Spinning = false -- just in case the server didn't answer
			end)
		end,
	})

	local function wheelWait(): number
		local s = state
		return if s then math.max(0, s.WheelWait - (os.clock() - syncedAt)) else 0
	end
	local function refreshWheel()
		if W.Spinning then
			spinLabel.Text = "🎡 Spinning..."
			setColors(spinGrad, COLORS.Gold)
			return
		end
		local wait = wheelWait()
		spinLabel.Text = if wait > 0 then "⏳ Next spin in " .. clockText(wait) else "🎡 SPIN! (FREE)"
		setColors(spinGrad, if wait > 0 then COLORS.Gray else COLORS.Green)
	end
	wheelWindow.OnOpen = refreshWheel

	-- the big wheel at the spawn turns too
	local function worldWheel(): (Model?, CFrame?)
		local current = W.Model
		if not (current and current.Parent) then
			local map = Workspace:FindFirstChild("Map")
			local found = map and map:FindFirstChild("LuckyWheel", true)
			local m = found and found:FindFirstChild("Wheel")
			if m and m:IsA("Model") then
				W.Model, W.Base = m, m:GetPivot()
			end
		end
		return W.Model, W.Base
	end

	local function playWheel(index: number, text: string)
		W.Spinning = true
		refreshWheel()
		-- turn the big wheel so the prize's slice ends up under the pointer
		local m, base = worldWheel()
		local sliceAngle = (index - 1) / #prizes * math.pi * 2
		local startAngle = W.Angle
		local finalAngle = startAngle - 4 * math.pi - ((startAngle + sliceAngle) % (math.pi * 2))
		W.Angle = finalAngle
		local steps = 2 * #prizes + index - 1
		local started = os.clock()
		local duration = 3.2
		local connection: RBXScriptConnection
		connection = RunService.RenderStepped:Connect(function()
			local t = math.clamp((os.clock() - started) / duration, 0, 1)
			local eased = 1 - (1 - t) ^ 3
			if m and base and m.Parent then
				placeModel(m, base * CFrame.Angles(startAngle + (finalAngle - startAngle) * eased, 0, 0))
			end
			-- the light runs around the tiles and slows down
			local at = math.floor(eased * steps + 0.5) % #prizes + 1
			for k, tile in ipairs(tiles) do
				tile.Light.BackgroundTransparency = if k == at then 0.45 else 1
			end
			if t >= 1 then
				connection:Disconnect()
			end
		end)
		task.spawn(function()
			local last = -1
			while os.clock() - started < duration do
				local eased = 1 - (1 - math.clamp((os.clock() - started) / duration, 0, 1)) ^ 3
				local at = math.floor(eased * steps + 0.5)
				if at ~= last then
					last = at
					playSound("Click", 1.4, 0.35)
				end
				task.wait()
			end
			W.Spinning = false
			refreshWheel()
			local prize = prizes[index]
			showBanner("🎡 YOU WON: " .. text .. "!", prize.Color:Lerp(WHITE, 0.3))
			toast("🎡 " .. text .. "!", "gold")
			local position = rootPosition()
			if prize.Crystals and position then
				flyIcons(position, "💰", coinsPill, coinsPop, if prize.Crystals >= 300 then 16 else 8)
			end
			celebrate(if prize.Chance <= 3 then 12 else 7, 1)
		end)
	end

	-- Side panel: wheel timer and the 2x gems boost
	do
		local side = gui:FindFirstChild("SidePanel")
		if side and side:IsA("Frame") then
			side.Size = UDim2.fromOffset(240, 560)
		end
		local wheelPill = new("Frame", { Name = "WheelInfo", Size = UDim2.fromOffset(240, 40), BackgroundColor3 = WHITE, LayoutOrder = 6, Parent = side })
		round(wheelPill, 14)
		outline(wheelPill, 3)
		local wheelGrad = gradient(wheelPill, COLORS.Gold)
		local wheelText = label({ Text = "", Size = UDim2.new(1, -20, 0.62, 0), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Parent = wheelPill })
		local gemBoostPill = new("Frame", { Name = "BoostInfo", Size = UDim2.fromOffset(240, 40), BackgroundColor3 = WHITE, LayoutOrder = 7, Visible = false, Parent = side })
		round(gemBoostPill, 14)
		outline(gemBoostPill, 3)
		gradient(gemBoostPill, COLORS.Purple)
		local gemBoostText = label({ Text = "", Size = UDim2.new(1, -20, 0.62, 0), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Parent = gemBoostPill })
		task.spawn(function()
			while true do
				if state then
					local wait = wheelWait()
					wheelText.Text = if wait > 0 then "🎡 Next spin in " .. clockText(wait) else "🎡 Lucky Wheel spin ready!"
					setColors(wheelGrad, if wait > 0 then COLORS.Gray else COLORS.Gold)
					local boost = math.max(0, ((state :: State).BoostWait or 0) - (os.clock() - syncedAt))
					gemBoostPill.Visible = boost > 0
					gemBoostText.Text = "⚡ 2x GEMS  " .. clockText(boost)
					if openName == "Wheel" then
						refreshWheel()
					end
				end
				task.wait(0.5)
			end
		end)
	end

	R.Effect.OnClientEvent:Connect(function(kind, a, b)
		if kind == "wheel" and type(a) == "number" and type(b) == "string" then
			playWheel(a, b)
		end
	end)
end

do
	-- 🦘 Bounce pads: land on one and it throws you up high
	local lastBounce = 0
	RunService.Heartbeat:Connect(function()
		local root = myRoot()
		if not root or os.clock() - lastBounce < 0.5 then
			return
		end
		for _, pad in ipairs(CollectionService:GetTagged("BouncePad")) do
			if pad:IsA("BasePart") and pad.Parent then
				local flat = Vector3.new(root.Position.X - pad.Position.X, 0, root.Position.Z - pad.Position.Z)
				local up = root.Position.Y - pad.Position.Y
				if flat.Magnitude < pad.Size.Y / 2 + 0.5 and up > 0 and up < 4.5 and root.AssemblyLinearVelocity.Y < 5 then
					lastBounce = os.clock()
					local hum = root.Parent and root.Parent:FindFirstChildOfClass("Humanoid")
					if hum then
						hum:ChangeState(Enum.HumanoidStateType.Jumping)
					end
					local v = root.AssemblyLinearVelocity
					local power = pad:GetAttribute("Power")
					root.AssemblyLinearVelocity = Vector3.new(v.X, if type(power) == "number" then power else 110, v.Z)
					playSound("Hit", 1.8, 0.5)
					burst(pad.Position + Vector3.new(0, 0.5, 0), Color3.fromRGB(130, 215, 255), 12, 14, 0.5)
					break
				end
			end
		end
	end)

end

do
	-- 🌠 a fireball falls from the sky, then BOOM
	local function meteorFall(position: Vector3)
		local root = myRoot()
		if root and (root.Position - position).Magnitude > 700 then
			return -- too far away to see
		end
		local ball = new("Part", {
			Name = "Fireball",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 7,
			Color = Color3.fromRGB(255, 140, 50),
			Material = Enum.Material.Neon,
			Anchored = true,
			CanCollide = false,
			CastShadow = false,
			CFrame = CFrame.new(position + Vector3.new(140, 300, 70)),
			Parent = FxFolder,
		})
		new("ParticleEmitter", {
			Texture = "rbxasset://textures/particles/fire_main.dds",
			Color = ColorSequence.new(Color3.fromRGB(255, 200, 80), Color3.fromRGB(255, 70, 30)),
			LightEmission = 1,
			Size = NumberSequence.new(6, 0),
			Lifetime = NumberRange.new(0.5, 1),
			Speed = NumberRange.new(2, 6),
			Rate = 60,
			Parent = ball,
		})
		new("PointLight", { Color = Color3.fromRGB(255, 150, 60), Range = 40, Brightness = 3, Parent = ball })
		tween(ball, 1.6, { CFrame = CFrame.new(position + Vector3.new(0, 2, 0)) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(1.6, function()
			ball:Destroy()
			playSound("Boom", 0.8, 0.8)
			for _, color in ipairs({ Color3.fromRGB(255, 160, 60), Color3.fromRGB(255, 230, 120), Color3.fromRGB(90, 80, 75) }) do
				burst(position + Vector3.new(0, 2, 0), color, 30, 45, 1.2)
			end
			-- a glowing pillar so you can find it
			local pillar = new("Part", {
				Name = "MeteorBeacon",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(120, 3, 3),
				CFrame = CFrame.new(position + Vector3.new(0, 60, 0)) * CFrame.Angles(0, 0, math.rad(90)),
				Color = Color3.fromRGB(255, 200, 90),
				Material = Enum.Material.Neon,
				Transparency = 0.6,
				Anchored = true,
				CanCollide = false,
				CastShadow = false,
				Parent = FxFolder,
			})
			tween(pillar, 25, { Transparency = 1 })
			Debris:AddItem(pillar, 25)
		end)
	end

	R.Effect.OnClientEvent:Connect(function(kind, a, b)
		if kind == "chest" then
			local position, coins = a :: Vector3, b :: number
			for _, color in ipairs({ Color3.fromRGB(255, 215, 90), Color3.fromRGB(255, 250, 220) }) do
				burst(position + Vector3.new(0, 2, 0), color, 20, 25, 0.7)
			end
			flyIcons(position, "💰", coinsPill, coinsPop, 10)
			showBanner("🎁 TREASURE CHEST! +💰 " .. Format(coins), Color3.fromRGB(255, 215, 110))
			chime(6, 1.2)
		elseif kind == "meteor" then
			local position, where = a :: Vector3, b :: string
			meteorFall(position)
			showBanner("🌠 A METEOR CRASHED IN " .. string.upper(where) .. "!", Color3.fromRGB(255, 170, 80))
			toast("🌠 Find the glowing meteor and mine it for a huge reward!", "gold")
			playSound("Boom", 0.5, 0.4)
		elseif kind == "meteorwin" then
			local position, coins = a :: Vector3, b :: number
			flyIcons(position, "💰", coinsPill, coinsPop, 16)
			showBanner("🌠 METEOR SMASHED! +💰 " .. Format(coins), Color3.fromRGB(255, 200, 90))
			celebrate(12, 0.9)
		elseif kind == "meteorgone" then
			toast("🌠 The meteor cooled down and crumbled away.", "info")
		end
	end)
end

-- Once a second: timers on the right side, the gifts window and the obby signs
task.spawn(function()
	while true do
		local s = state
		if s then
			refreshSide()
			if openName == "Gifts" then
				refreshGifts()
			elseif openName == "Daily" then
				refreshDaily()
			end
			-- every obby sign shows what that obby pays YOU
			for _, obbySign in ipairs(CollectionService:GetTagged("ObbySign")) do
				local subtitle = obbySign:FindFirstChild("Subtitle", true)
				if subtitle and subtitle:IsA("TextLabel") then
					local here = obbySign:GetAttribute("Dimension")
					local d = if type(here) == "number" then here else nil
					local wait = obbyWait(d)
					subtitle.Text = if wait > 0 then "Reward again in " .. clockText(wait) else "Win 💰 " .. Format(obbyReward(d)) .. "!"
				end
			end
		end
		task.wait(1)
	end
end)

camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
updateScale()

-- Ask the server for our data
R.Sync:FireServer()
