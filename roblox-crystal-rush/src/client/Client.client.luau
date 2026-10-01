--[[
	Client  (LocalScript inside StarterPlayer > StarterPlayerScripts)

	Runs on each player's own computer:
	  * the screen UI (coins, backpack, shop, rebirth, teleport)
	  * clicking crystals to mine them
	  * pets following you, spinning decorations, sparkles and sounds
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
for _, name in ipairs({ "Mine", "Buy", "Rebirth", "Teleport", "Sync", "Notify", "Effect", "OpenMenu" }) do
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

-- Hide the default tool bar (your pickaxe is always in your hand)
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

type State = {
	Coins: number,
	Gems: number,
	Capacity: number,
	Rebirths: number,
	Pickaxe: number,
	Backpack: number,
	Zone: number,
	Pets: { number },
	TotalGems: number,
}
local state: State? = nil
local ownedPets: { [number]: boolean } = {}
local equippedPets: { [number]: boolean } = {}

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
	Size = UDim2.fromOffset(250, 330),
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

-- Rebirths and boosts
local boostPill = new("Frame", { Size = UDim2.fromOffset(250, 44), BackgroundColor3 = WHITE, LayoutOrder = 3, Parent = hud })
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

-- Menu buttons
local menuRow = new("Frame", { Size = UDim2.fromOffset(250, 94), BackgroundTransparency = 1, LayoutOrder = 4, Parent = hud })
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0, 12),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = menuRow,
})

local openWindow: (name: string, keepOpen: boolean?) -> ()

local function menuButton(order: number, emoji: string, caption: string, colors: { Color3 }, windowName: string)
	local holder = new("Frame", { Size = UDim2.fromOffset(75, 94), BackgroundTransparency = 1, LayoutOrder = order, Parent = menuRow })
	button({
		Size = UDim2.fromOffset(75, 75),
		Text = emoji,
		Colors = colors,
		Radius = 18,
		Parent = holder,
		OnClick = function()
			openWindow(windowName)
		end,
	})
	label({
		Text = caption,
		Size = UDim2.new(1, 10, 0, 26),
		Position = UDim2.new(0.5, 0, 1, 0),
		AnchorPoint = Vector2.new(0.5, 1),
		Parent = holder,
	})
end
menuButton(1, "🛒", "Shop", COLORS.Green, "Shop")
menuButton(2, "🌀", "Teleport", COLORS.Blue, "Teleport")
menuButton(3, "♻️", "Rebirth", COLORS.Purple, "Rebirth")

--------------------------------------------------------------------------------
-- TOASTS (little messages at the bottom), BANNERS AND WARNINGS
--------------------------------------------------------------------------------
local toastHolder = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -24),
	Size = UDim2.fromOffset(520, 230),
	BackgroundTransparency = 1,
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
	local scale: UIScale = new("UIScale", { Scale = 0.4, Parent = frame })
	tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)

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
	tween(banner, 0.4, { TextTransparency = 0 })
	tween(bannerStroke, 0.4, { Transparency = 0 })
	task.delay(2.6, function()
		if bannerId == myId then
			tween(banner, 0.6, { TextTransparency = 1 })
			tween(bannerStroke, 0.6, { Transparency = 1 })
		end
	end)
end

-- "Backpack full!" warning
local fullWarning = label({
	Text = "🎒 BACKPACK FULL! Go to a 💰 SELL pad",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.3),
	Size = UDim2.fromOffset(620, 44),
	TextColor3 = Color3.fromRGB(255, 225, 90),
	Visible = false,
	Stroke = 3,
	Parent = gui,
})
autoScale(fullWarning)

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
type Window = { Holder: Frame, Pop: UIScale, Body: Frame, OnOpen: (() -> ())? }
local windows: { [string]: Window } = {}
local openName: string? = nil

local function closeWindow()
	if openName then
		windows[openName].Holder.Visible = false
		openName = nil
	end
end

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
	window.Holder.Visible = true
	window.Pop.Scale = 0.6
	tween(window.Pop, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
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
	label({
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
	local window: Window = { Holder = holder, Pop = popScale, Body = body }
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

local function makeCard(category: string, index: number, count: number, name: string, stat: string, price: number, m: Model, direction: Vector3)
	local rarity = Shared.GetRarity(index, count)
	local frame = new("Frame", {
		Name = category .. index,
		BackgroundColor3 = WHITE,
		LayoutOrder = index,
		Visible = false,
		Parent = scroller,
	})
	round(frame, 16)
	outline(frame, 3)
	gradient(frame, { rarity.Color:Lerp(WHITE, 0.15), rarity.Color:Lerp(Color3.new(0, 0, 0), 0.45) })

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
	makeCard("Pet", i, #Shared.Pets, def.Name, "✨ +" .. tostring(math.floor(def.Bonus * 100)) .. "% Gems", def.Price, Shared.BuildPet(i), Vector3.new(0.35, 0.3, -1))
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
			owned = ownedPets[card.Index] == true
			equipped = equippedPets[card.Index] == true
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

--------------------------------------------------------------------------------
-- TELEPORT
--------------------------------------------------------------------------------
local teleport = makeWindow("Teleport", "🌀 TELEPORT", 460, 520, COLORS.Blue)
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
	Text = "Rebirthing resets your coins, gems, pickaxe, backpack and zones.\nYou KEEP your pets and earn more coins forever!",
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
		"⭐ Rebirths: %d  →  %d\n💰 Coin boost: x%s  →  x%s\nCost: 💰 %s",
		s.Rebirths,
		s.Rebirths + 1,
		tostring(Shared.CoinMultiplier(s.Rebirths)),
		tostring(Shared.CoinMultiplier(s.Rebirths + 1)),
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
local function shards(position: Vector3, color: Color3, count: number)
	for _ = 1, count do
		local shard = new("Part", {
			Size = Vector3.new(0.5, 0.9, 0.5) * (0.6 + math.random() * 0.7),
			CFrame = CFrame.new(position + Vector3.new(math.random() - 0.5, math.random() * 2, math.random() - 0.5))
				* CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6),
			Color = color,
			Material = Enum.Material.Neon,
			CanTouch = false,
			CastShadow = false,
			Parent = Workspace,
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

--------------------------------------------------------------------------------
-- EVENTS FROM THE SERVER
--------------------------------------------------------------------------------
R.Effect.OnClientEvent:Connect(function(kind, a, b, c)
	if kind == "hit" then
		local position: Vector3, damage: number, m: Model? = a, b, c
		burst(position, Color3.new(1, 1, 1), 6, 14, 0.5)
		worldText(position + Vector3.new(0, 1, 0), "-" .. Format(damage), Color3.fromRGB(255, 255, 255), 26)
		playSound("Hit", 1.5 + math.random() * 0.4, 0.45)
		if m and m.Parent then
			shake(m)
		end
	elseif kind == "break" then
		local position: Vector3, color: Color3, giant: boolean = a, b, c
		burst(position, color, if giant then 45 else 25, if giant then 40 else 26, if giant then 1.4 else 0.9)
		shards(position, color, if giant then 14 else 8)
		local root = myRoot()
		if root and (root.Position - position).Magnitude < 80 then
			playSound("Boom", if giant then 1.2 else 1.8, if giant then 0.35 else 0.18)
		end
	elseif kind == "reward" then
		local position: Vector3, gems: number = a, b
		worldText(position + Vector3.new(0, 2.5, 0), "+" .. Format(gems) .. " 💎", Color3.fromRGB(120, 240, 255), 38)
		flyIcons(position, "💎", gemsPill, gemsPop, math.clamp(math.floor(gems / 5) + 2, 2, 7))
		playSound("Click", 2, 0.6)
	elseif kind == "sold" then
		local coins: number = a
		local root = myRoot()
		if root then
			flyIcons(root.Position, "💰", coinsPill, coinsPop, 8)
			confetti(root.Position + Vector3.new(0, 2, 0))
		end
		showBanner("💰 +" .. Format(coins) .. " COINS!", Color3.fromRGB(255, 220, 80))
		chime(6, 1)
	elseif kind == "full" then
		backpackFull()
	elseif kind == "bought" then
		local root = myRoot()
		if root then
			confetti(root.Position + Vector3.new(0, 3, 0))
		end
		chime(4, 1.4)
	elseif kind == "unlock" then
		local zone = Shared.Zones[a]
		if zone then
			showBanner("🔓 " .. string.upper(zone.Name) .. " UNLOCKED!", zone.Accent:Lerp(WHITE, 0.3))
		end
		playSound("Boom", 1.1, 0.4)
		chime(6, 1.2)
		local root = myRoot()
		if root then
			confetti(root.Position + Vector3.new(0, 3, 0))
		end
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
	elseif kind == "spawn" then
		local position: Vector3, color: Color3 = a, b
		burst(position, color, 14, 10, 0.7)
	end
end)

R.Notify.OnClientEvent:Connect(function(message, kind)
	toast(message, kind)
	if kind == "bad" then
		playSound("Hit", 0.6, 0.5)
	end
end)

--------------------------------------------------------------------------------
-- MINING (click / tap / hold on crystals)
--------------------------------------------------------------------------------
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function crystalAt(point: Vector2, isViewportPoint: boolean): Model?
	local ray = if isViewportPoint then camera:ViewportPointToRay(point.X, point.Y) else camera:ScreenPointToRay(point.X, point.Y)
	local ignore: { Instance } = { PetFolder, WallFolder }
	if player.Character then
		table.insert(ignore, player.Character)
	end
	rayParams.FilterDescendantsInstances = ignore
	local result = Workspace:Raycast(ray.Origin, ray.Direction * 400, rayParams)
	if result then
		local m = result.Instance.Parent
		if m and m:IsA("Model") and m:GetAttribute("IsCrystal") then
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
local swings = 0

local function swing()
	local char = player.Character
	local tool = char and char:FindFirstChildOfClass("Tool")
	if tool then
		local anim = Instance.new("StringValue")
		anim.Name = "toolanim"
		anim.Value = "Slash"
		anim.Parent = tool
		Debris:AddItem(anim, 1)
	end
end

local function tryMine(point: Vector2, isViewportPoint: boolean)
	local now = os.clock()
	if now - lastSwing < Settings.MineCooldown then
		return
	end
	local m = crystalAt(point, isViewportPoint)
	if not m then
		return
	end
	if not inRange(m) then
		if now - lastFarHint > 2.5 then
			lastFarHint = now
			toast("🏃 Walk closer to mine that crystal!", "info")
		end
		return
	end
	local s = state
	if s and s.Gems >= s.Capacity then
		backpackFull()
		return
	end
	local zone = m:GetAttribute("Zone")
	if s and type(zone) == "number" and zone > s.Zone then
		return
	end
	lastSwing = now
	R.Mine:FireServer(m)
	swing()
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

--------------------------------------------------------------------------------
-- PETS FOLLOW THEIR OWNERS, DECORATIONS SPIN
--------------------------------------------------------------------------------
local PET_OFFSETS = { Vector3.new(-3.4, 0, 3.2), Vector3.new(3.4, 0, 3.2), Vector3.new(0, 0, 5.6) }

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
local petCFrames: { [Model]: CFrame } = setmetatable({}, { __mode = "k" }) :: any

type Spinner = { Base: CFrame, Speed: number, Bob: number, Phase: number }
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
	spinners[inst] = {
		Base = base,
		Speed = inst:GetAttribute("SpinSpeed") or 1,
		Bob = inst:GetAttribute("Bob") or 0,
		Phase = math.random() * 6,
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
				local offset = PET_OFFSETS[slot] or PET_OFFSETS[1]
				local moving = root.AssemblyLinearVelocity.Magnitude > 2
				local hop = if moving then math.abs(math.sin(t * 9 + slot)) * 1.1 else math.sin(t * 3 + slot) * 0.3 + 0.3
				local spot = (root.CFrame * CFrame.new(offset)).Position
				local look = root.CFrame.LookVector
				local position = Vector3.new(spot.X, root.Position.Y - 1.6 + hop, spot.Z)
				local target = CFrame.lookAt(position, position + Vector3.new(look.X, 0, look.Z) + Vector3.new(0, 0, 0.001))
				local current = petCFrames[pet] or target
				current = current:Lerp(target, math.min(1, dt * 9))
				petCFrames[pet] = current
				placeModel(pet, current)
			end
		end
	end

	-- spinning things
	for inst, info in pairs(spinners) do
		if inst.Parent then
			local cf = CFrame.new(info.Base.Position + Vector3.new(0, math.sin(t * 1.6 + info.Phase) * info.Bob, 0))
				* CFrame.Angles(0, t * info.Speed + info.Phase, 0)
				* info.Base.Rotation
			if inst:IsA("BasePart") then
				inst.CFrame = cf
			elseif inst:IsA("Model") then
				placeModel(inst, cf)
			end
		end
	end

	-- spin the models in the shop while it is open
	if openName == "Shop" then
		for _, card in ipairs(cards) do
			if card.Frame.Visible then
				placeModel(card.Model, CFrame.Angles(0, t * 0.9, 0) * card.Base)
			end
		end
	end
end)

--------------------------------------------------------------------------------
-- ZONE MOODS (the sky changes in each zone) AND GATES
--------------------------------------------------------------------------------
local atmosphere = Lighting:WaitForChild("CrystalRushAtmosphere", 10) :: Atmosphere?
local colorFx = Lighting:WaitForChild("CrystalRushColor", 10) :: ColorCorrectionEffect?
local currentZone = -1

local function applyMood(zoneIndex: number, instant: boolean?)
	local mood = Shared.Zones[math.max(zoneIndex, 1)].Mood
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

local function updateGate(gate: Instance)
	local s = state
	local zoneIndex = gate:GetAttribute("Zone")
	if not s or type(zoneIndex) ~= "number" then
		return
	end
	local zone = Shared.Zones[zoneIndex]
	local unlocked = s.Zone >= zoneIndex
	local barrier = gate:FindFirstChild("Barrier")
	if barrier and barrier:IsA("BasePart") then
		if unlocked then
			barrier.CanCollide = false
			barrier.CanQuery = false
			barrier.Transparency = 1
		else
			barrier.CanQuery = true
			barrier.CanCollide = true
			barrier.Transparency = 0.3
		end
	end
	local beam = gate:FindFirstChild("Beam")
	local signGui = beam and beam:FindFirstChild("Sign")
	if signGui then
		local title = signGui:FindFirstChild("Title")
		local subtitle = signGui:FindFirstChild("Subtitle")
		if title and title:IsA("TextLabel") then
			title.Text = (if unlocked then zone.Emoji .. " " else "🔒 ") .. string.upper(zone.Name)
		end
		if subtitle and subtitle:IsA("TextLabel") then
			subtitle.Text = if unlocked then "Unlocked!" else "💰 " .. Format(zone.Price) .. " to unlock"
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
	local full = s ~= nil and s.Gems >= s.Capacity
	fullWarning.Visible = full
	if not full or not root then
		if guideBeam then
			guideBeam.Enabled = false
		end
		return
	end
	local best: Attachment? = nil
	local bestDistance = math.huge
	for _, pad in ipairs(SellFolder:GetChildren()) do
		local target = pad:FindFirstChild("GuideTarget", true)
		if target and target:IsA("Attachment") then
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
	boostText.Text = string.format("⭐ %d Rebirths  •  x%s 💰  •  x%s 💎", rebirths, tostring(Shared.CoinMultiplier(rebirths)), tostring(petBoost))
	local fill = math.clamp(s.Gems / s.Capacity, 0, 1)
	tween(gemsFill, 0.25, { Size = UDim2.fromScale(fill, 1) })
	setColors(gemsFillGrad, if fill >= 1 then COLORS.Gold else COLORS.Cyan)
	refreshShop()
	refreshTeleport()
	refreshRebirth()
	updateGates()
end

R.Sync.OnClientEvent:Connect(function(newState: State)
	state = newState
	ownedPets = {}
	for _, index in ipairs(newState.Pets) do
		ownedPets[index] = true
	end
	equippedPets = {}
	for _, index in ipairs(Shared.GetEquippedPets(ownedPets)) do
		equippedPets[index] = true
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
				toast("🛒 Spend coins in the Shop on pickaxes, backpacks and pets!", "good")
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
			local zoneIndex = Shared.ZoneAt(root.Position.Z)
			if zoneIndex ~= currentZone then
				local first = currentZone == -1
				currentZone = zoneIndex
				applyMood(zoneIndex, first)
				if zoneIndex > 0 and not first then
					local zone = Shared.Zones[zoneIndex]
					showBanner(zone.Emoji .. " " .. string.upper(zone.Name), zone.Accent:Lerp(WHITE, 0.3))
				end
			end
			-- keep the pickaxe in your hand
			local char = player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local backpack = player:FindFirstChildOfClass("Backpack")
			if char and hum and hum.Health > 0 and backpack and not char:FindFirstChildOfClass("Tool") then
				local tool = backpack:FindFirstChild("Pickaxe")
				if tool and tool:IsA("Tool") then
					hum:EquipTool(tool)
				end
			end
		end
		updateGuide()
		task.wait(0.3)
	end
end)

camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
updateScale()

-- Ask the server for our data
R.Sync:FireServer()
