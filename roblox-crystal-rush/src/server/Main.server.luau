--[[
	Main  (Script inside ServerScriptService)

	This script runs the whole game on the server:
	  1. builds the map (terrain, zones, gates, decorations, crystals, the obby)
	  2. sets up the lighting so everything looks natural
	  3. handles mining, selling, the shop, rebirths and teleports
	  4. runs the sky obby, quests, free gifts and daily rewards
	  5. saves player progress

	Prices and settings live in ReplicatedStorage > GameShared.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

-- Don't spawn anyone until the map exists
Players.CharacterAutoLoads = false

local Shared = require(ReplicatedStorage:WaitForChild("GameShared"))
local Settings = Shared.Settings
local Layout = Shared.Layout
local Format = Shared.Format

local rad = math.rad
local rng = Random.new(2026)

--------------------------------------------------------------------------------
-- REMOTES (how the server and the players' computers talk to each other)
--------------------------------------------------------------------------------
local Remotes: { [string]: RemoteEvent } = {}
do
	local old = ReplicatedStorage:FindFirstChild("Remotes")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "Remotes"
	for _, name in ipairs({ "Mine", "Buy", "Rebirth", "Teleport", "Sync", "Notify", "Effect", "OpenMenu", "EnterDimension", "GoSell", "Claim", "Dig", "Hatch", "GadgetToggle", "Swing", "Spin", "Trade" }) do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
		Remotes[name] = remote
	end
	folder.Parent = ReplicatedStorage
end

--------------------------------------------------------------------------------
-- FOLDERS IN THE WORKSPACE
--------------------------------------------------------------------------------
local function folder(name: string): Folder
	local existing = Workspace:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = Workspace
	return f
end

local MapFolder = folder("Map")
local CrystalFolder = folder("Crystals")
local GateFolder = folder("Gates")
local SellFolder = folder("SellPads")
local PetFolder = folder("Pets")
local WallFolder = folder("Walls")
local DimensionFolder = folder("Dimensions")
local DigFolder = folder("DigSpots")
local BossFolder = folder("Bosses")

-- New parts and models go here unless something else is given
-- (dimension islands switch this to their own folder while they are built)
local buildParent: Instance = MapFolder

-- Remove the default Baseplate / SpawnLocation if this started as a Baseplate place
do
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		baseplate:Destroy()
	end
	for _, child in ipairs(Workspace:GetChildren()) do
		if child:IsA("SpawnLocation") then
			child:Destroy()
		end
	end
end

--------------------------------------------------------------------------------
-- BUILDING HELPERS
--------------------------------------------------------------------------------
-- Makes a part. Example: P({ Size = Vector3.new(4, 1, 4), Color = ..., Parent = ... })
local function P(props): any
	local p: any = Instance.new(props.Class or "Part")
	if props.Shape then
		p.Shape = props.Shape
	end
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = props.Size or Vector3.new(4, 1, 4)
	p.CFrame = props.CFrame or CFrame.new()
	p.Color = props.Color or Color3.new(1, 1, 1)
	p.Material = props.Material or Enum.Material.SmoothPlastic
	p.Transparency = props.Transparency or 0
	p.Reflectance = props.Reflectance or 0
	p.CastShadow = props.CastShadow ~= false
	if props.CanCollide == false then
		p.CanCollide = false
		p.CanQuery = props.CanQuery == true
		p.CanTouch = props.CanTouch == true
	end
	p.Name = props.Name or "Part"
	p.Parent = props.Parent or buildParent
	return p
end

local function model(name: string, parent: Instance?): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent or buildParent
	return m
end

local function light(parent: Instance, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = parent
	return l
end

-- Parts tagged "Spin" are spun / bobbed by every player's computer (smooth!)
local function spin(inst: Instance, speed: number, bob: number?)
	inst:SetAttribute("SpinSpeed", speed)
	inst:SetAttribute("Bob", bob or 0)
	inst:AddTag("Spin")
end

-- A floating sign with big text (BillboardGui)
local function sign(parent: Instance, title: string, subtitle: string?, color: Color3, width: number, height: number, offsetY: number)
	local bb = Instance.new("BillboardGui")
	bb.Name = "Sign"
	bb.Size = UDim2.fromScale(width, height)
	bb.StudsOffset = Vector3.new(0, offsetY, 0)
	bb.LightInfluence = 0
	bb.MaxDistance = 300
	bb.ResetOnSpawn = false

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.BackgroundTransparency = 1
	titleLabel.Size = UDim2.fromScale(1, if subtitle then 0.62 else 1)
	titleLabel.Font = Enum.Font.FredokaOne
	titleLabel.TextScaled = true
	titleLabel.TextColor3 = color
	titleLabel.Text = title
	titleLabel.Parent = bb
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(20, 20, 32)
	stroke.Parent = titleLabel

	if subtitle then
		local sub = titleLabel:Clone()
		sub.Name = "Subtitle"
		sub.Position = UDim2.fromScale(0, 0.62)
		sub.Size = UDim2.fromScale(1, 0.38)
		sub.TextColor3 = Color3.new(1, 1, 1)
		sub.Text = subtitle
		sub.Parent = bb
	end
	bb.Parent = parent
	return bb
end

local function particles(parent: Instance, props)
	local pe: any = Instance.new("ParticleEmitter")
	pe.Texture = props.Texture or "rbxasset://textures/particles/sparkles_main.dds"
	pe.Color = ColorSequence.new(props.Color or Color3.new(1, 1, 1))
	pe.LightEmission = props.LightEmission or 1
	pe.Size = NumberSequence.new(props.Size or 0.4, props.EndSize or 0)
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.15, props.Transparency or 0),
		NumberSequenceKeypoint.new(0.8, props.Transparency or 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	pe.Lifetime = props.Lifetime or NumberRange.new(1, 2)
	pe.Speed = props.Speed or NumberRange.new(1, 2)
	pe.Rate = props.Rate or 10
	pe.SpreadAngle = props.Spread or Vector2.new(20, 20)
	pe.Acceleration = props.Acceleration or Vector3.zero
	pe.EmissionDirection = props.Direction or Enum.NormalId.Top
	pe.Drag = props.Drag or 0
	pe.Rotation = NumberRange.new(0, 360)
	pe.RotSpeed = NumberRange.new(-60, 60)
	pe.Parent = parent
	return pe
end

local function prompt(parent: Instance, action: string, object: string, hold: number)
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = action
	pp.ObjectText = object
	pp.HoldDuration = hold
	pp.MaxActivationDistance = 14
	pp.RequiresLineOfSight = false
	pp.Parent = parent
	return pp
end

-- A nicer floating sign: a dark panel with a colored border, an icon, a title and a subtitle
local function fancySign(parent: Instance, icon: string, title: string, subtitle: string?, accent: Color3, width: number, offsetY: number): BillboardGui
	local bb = Instance.new("BillboardGui")
	bb.Name = "Sign"
	bb.Size = UDim2.fromScale(width, width * 0.3)
	bb.StudsOffset = Vector3.new(0, offsetY, 0)
	bb.LightInfluence = 0
	bb.MaxDistance = 160
	bb.ResetOnSpawn = false
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundColor3 = Color3.new(1, 1, 1)
	panel.BackgroundTransparency = 0.08
	panel.Parent = bb
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.28, 0)
	corner.Parent = panel
	local border = Instance.new("UIStroke")
	border.Thickness = 3
	border.Color = accent
	border.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	border.Parent = panel
	local shade = Instance.new("UIGradient")
	shade.Color = ColorSequence.new(accent:Lerp(Color3.fromRGB(20, 22, 32), 0.55), Color3.fromRGB(20, 22, 32))
	shade.Rotation = 90
	shade.Parent = panel
	local function text(name: string, value: string, x: number, y: number, w: number, h: number, color: Color3, align: Enum.TextXAlignment)
		local lbl = Instance.new("TextLabel")
		lbl.Name = name
		lbl.BackgroundTransparency = 1
		lbl.Position = UDim2.fromScale(x, y)
		lbl.Size = UDim2.fromScale(w, h)
		lbl.Font = Enum.Font.FredokaOne
		lbl.TextScaled = true
		lbl.TextXAlignment = align
		lbl.TextColor3 = color
		lbl.Text = value
		lbl.Parent = panel
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Color = Color3.fromRGB(12, 12, 20)
		stroke.Parent = lbl
		return lbl
	end
	text("Icon", icon, 0.03, 0.12, 0.22, 0.76, Color3.new(1, 1, 1), Enum.TextXAlignment.Center)
	text("Title", title, 0.27, if subtitle then 0.1 else 0.2, 0.69, if subtitle then 0.5 else 0.6, accent:Lerp(Color3.new(1, 1, 1), 0.45), Enum.TextXAlignment.Left)
	if subtitle then
		text("Subtitle", subtitle, 0.27, 0.6, 0.69, 0.3, Color3.fromRGB(225, 228, 240), Enum.TextXAlignment.Left)
	end
	bb.Parent = parent
	return bb
end

-- Words carved into a stone (or painted on wood): a SurfaceGui on one face of a part
local function carvedText(parent: BasePart, face: Enum.NormalId, title: string, subtitle: string?, color: Color3)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0.4
	gui.MaxDistance = 250
	local function text(name: string, value: string, y: number, h: number, textColor: Color3)
		local lbl = Instance.new("TextLabel")
		lbl.Name = name
		lbl.BackgroundTransparency = 1
		lbl.Position = UDim2.fromScale(0.04, y)
		lbl.Size = UDim2.fromScale(0.92, h)
		lbl.Font = Enum.Font.FredokaOne
		lbl.TextScaled = true
		lbl.TextColor3 = textColor
		lbl.Text = value
		lbl.Parent = gui
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 3
		stroke.Color = Color3.fromRGB(30, 26, 22)
		stroke.Parent = lbl
	end
	text("Title", title, if subtitle then 0.06 else 0.15, if subtitle then 0.56 else 0.7, color)
	if subtitle then
		text("Subtitle", subtitle, 0.62, 0.3, Color3.fromRGB(245, 240, 230))
	end
	gui.Parent = parent
	return gui
end

-- A glowing circle on the ground. Step inside it to use it: the shop opens, you sell, ...
-- action tells the player's screen what to open (Shop, Backpacks, Pets, Gadgets, Egg, ...)
local function actionCircle(pos: Vector3, radius: number, color: Color3, action: string, arg: any?, parent: Instance?): BasePart
	local m = model("Circle", parent)
	local upright = CFrame.Angles(0, 0, rad(90))
	local floor = P({
		Name = "CircleFloor",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, radius * 2, radius * 2),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.18, 0)) * upright,
		Color = color,
		Transparency = 0.72,
		CanCollide = false,
		CastShadow = false,
		Parent = m,
	})
	local segments = math.max(24, math.floor(radius * 4))
	for k = 0, segments - 1 do
		local a = (k + 0.5) / segments * math.pi * 2
		P({
			Name = "Ring",
			Size = Vector3.new(0.55, 0.26, radius * 2 * math.pi / segments + 0.1),
			CFrame = CFrame.new(pos + Vector3.new(math.cos(a) * radius, 0.22, math.sin(a) * radius)) * CFrame.Angles(0, -a, 0),
			Color = color:Lerp(Color3.new(1, 1, 1), 0.25),
			Material = Enum.Material.Neon,
			Transparency = 0.2,
			CanCollide = false,
			CastShadow = false,
			Parent = m,
		})
	end
	particles(floor, {
		Color = color:Lerp(Color3.new(1, 1, 1), 0.4),
		Size = 0.22,
		Rate = 5,
		Lifetime = NumberRange.new(1.5, 2.5),
		Speed = NumberRange.new(1, 2),
		Spread = Vector2.new(5, 5),
		Direction = Enum.NormalId.Right,
		LightEmission = 0.5,
	})
	floor:SetAttribute("Action", action)
	if arg ~= nil then
		floor:SetAttribute("Arg", arg)
	end
	floor:SetAttribute("Radius", radius)
	floor:AddTag("ActionCircle")
	return floor
end

--------------------------------------------------------------------------------
-- LIGHTING (natural daylight; each zone changes the mood on the player's screen)
--------------------------------------------------------------------------------
local function setupLighting()
	local mood = Shared.Zones[1].Mood
	pcall(function()
		(Lighting :: any).Technology = Enum.Technology.Future
	end)
	Lighting.ClockTime = mood.ClockTime
	Lighting.Brightness = mood.Brightness
	Lighting.Ambient = mood.Ambient
	Lighting.OutdoorAmbient = mood.OutdoorAmbient
	Lighting.ExposureCompensation = mood.Exposure
	Lighting.GeographicLatitude = 41.7
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.15
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1

	-- Replace old effects with ours
	for _, child in ipairs(Lighting:GetChildren()) do
		if child:IsA("Atmosphere") or child:IsA("PostEffect") then
			child:Destroy()
		end
	end

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Name = "CrystalRushAtmosphere"
	atmosphere.Density = mood.Density
	atmosphere.Offset = 0.25
	atmosphere.Haze = mood.Haze
	atmosphere.Glare = mood.Glare
	atmosphere.Color = mood.AtmosphereColor
	atmosphere.Decay = mood.Decay
	atmosphere.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Name = "CrystalRushBloom"
	bloom.Intensity = 0.25
	bloom.Size = 18
	bloom.Threshold = 2.2
	bloom.Parent = Lighting

	local color = Instance.new("ColorCorrectionEffect")
	color.Name = "CrystalRushColor"
	color.TintColor = mood.Tint
	color.Saturation = mood.Saturation
	color.Contrast = mood.Contrast
	color.Parent = Lighting

	local rays = Instance.new("SunRaysEffect")
	rays.Name = "CrystalRushSunRays"
	rays.Intensity = 0.03
	rays.Spread = 0.6
	rays.Parent = Lighting

	local depth = Instance.new("DepthOfFieldEffect")
	depth.Name = "CrystalRushDepth"
	depth.FarIntensity = 0.12
	depth.FocusDistance = 80
	depth.InFocusRadius = 80
	depth.NearIntensity = 0
	depth.Parent = Lighting

	if not Lighting:FindFirstChildOfClass("Sky") then
		local sky = Instance.new("Sky")
		sky.Name = "CrystalRushSky"
		sky.StarCount = 3000
		sky.SunAngularSize = 11
		sky.MoonAngularSize = 11
		sky.Parent = Lighting
	end

	local terrain = Workspace.Terrain
	if not terrain:FindFirstChildOfClass("Clouds") then
		local clouds = Instance.new("Clouds")
		clouds.Cover = 0.6
		clouds.Density = 0.55
		clouds.Color = Color3.fromRGB(245, 245, 245)
		clouds.Parent = terrain
	end
end

--------------------------------------------------------------------------------
-- TERRAIN
--------------------------------------------------------------------------------
local Terrain = Workspace.Terrain
local MAP_END = Shared.ZoneEnd(#Shared.Zones)

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include
groundParams.FilterDescendantsInstances = { Terrain }

-- How high the ground is at (x, z). Starts below the cave ceiling.
local function groundY(x: number, z: number): number
	local hit = Workspace:Raycast(Vector3.new(x, 36, z), Vector3.new(0, -80, 0), groundParams)
	return if hit then hit.Position.Y else 0
end

local function onGround(pos: Vector3): Vector3
	return Vector3.new(pos.X, groundY(pos.X, pos.Z), pos.Z)
end

local function fillBlock(x: number, y: number, z: number, sx: number, sy: number, sz: number, material: Enum.Material, rotY: number?)
	Terrain:FillBlock(CFrame.new(x, y, z) * CFrame.Angles(0, rotY or 0, 0), Vector3.new(sx, sy, sz), material)
end

-- Spots where crystals should not grow (decorations, sell pads, lakes, ...)
local reserved: { [number]: { { pos: Vector3, radius: number } } } = {}

local function reserve(zoneIndex: number, pos: Vector3, radius: number)
	reserved[zoneIndex] = reserved[zoneIndex] or {}
	table.insert(reserved[zoneIndex], { pos = Vector3.new(pos.X, 0, pos.Z), radius = radius })
end

local function isReserved(zoneIndex: number, pos: Vector3, extra: number): boolean
	for _, r in ipairs(reserved[zoneIndex] or {}) do
		if (Vector3.new(pos.X, 0, pos.Z) - r.pos).Magnitude < r.radius + extra then
			return true
		end
	end
	return false
end

local function edgeSpot(zoneIndex: number): Vector3
	local side = if rng:NextNumber() < 0.5 then -1 else 1
	local zs, ze = Shared.ZoneStart(zoneIndex), Shared.ZoneEnd(zoneIndex)
	return Vector3.new(side * rng:NextNumber(64, 78), 0, rng:NextNumber(ze + 6, zs - 6))
end

local function anySpot(zoneIndex: number): Vector3
	local zs, ze = Shared.ZoneStart(zoneIndex), Shared.ZoneEnd(zoneIndex)
	return Vector3.new(rng:NextNumber(-60, 60), 0, rng:NextNumber(ze + 10, zs - 30))
end

-- A spot that isn't reserved (for big decorations inside a zone)
local function freeSpot(zoneIndex: number, radius: number): Vector3?
	for _ = 1, 25 do
		local pos = anySpot(zoneIndex)
		if not isReserved(zoneIndex, pos, radius) then
			return pos
		end
	end
	return nil
end

-- Where the boss arena of each zone is
local function bossArenaCenter(i: number): Vector3
	return Vector3.new(48, 0, (Shared.ZoneStart(i) + Shared.ZoneEnd(i)) / 2 - 20)
end
local BOSS_ARENA_RADIUS = 21

local function setupTerrain()
	for i = 1, #Shared.Zones do
		reserve(i, bossArenaCenter(i), BOSS_ARENA_RADIUS + 5)
	end
	local colors = {
		[Enum.Material.Grass] = Color3.fromRGB(86, 122, 58),
		[Enum.Material.LeafyGrass] = Color3.fromRGB(74, 106, 48),
		[Enum.Material.Ground] = Color3.fromRGB(104, 92, 70),
		[Enum.Material.Mud] = Color3.fromRGB(78, 66, 52),
		[Enum.Material.Rock] = Color3.fromRGB(104, 101, 96),
		[Enum.Material.Slate] = Color3.fromRGB(80, 78, 82),
		[Enum.Material.Basalt] = Color3.fromRGB(54, 50, 48),
		[Enum.Material.CrackedLava] = Color3.fromRGB(232, 92, 34),
		[Enum.Material.Snow] = Color3.fromRGB(236, 240, 246),
		[Enum.Material.Glacier] = Color3.fromRGB(165, 200, 225),
		[Enum.Material.Asphalt] = Color3.fromRGB(52, 50, 60),
		[Enum.Material.Salt] = Color3.fromRGB(80, 76, 92),
		[Enum.Material.Cobblestone] = Color3.fromRGB(128, 124, 118),
		[Enum.Material.Pavement] = Color3.fromRGB(150, 146, 140),
		[Enum.Material.Sand] = Color3.fromRGB(215, 190, 140),
		[Enum.Material.Sandstone] = Color3.fromRGB(196, 158, 112),
		[Enum.Material.Limestone] = Color3.fromRGB(228, 220, 198),
	}
	for material, color in pairs(colors) do
		Terrain:SetMaterialColor(material, color)
	end
	Terrain.WaterColor = Color3.fromRGB(28, 82, 96)
	Terrain.WaterTransparency = 0.45
	Terrain.WaterReflectance = 0.85
	Terrain.WaterWaveSize = 0.12
	Terrain.WaterWaveSpeed = 6

	-- Hub: grass, a cobblestone square around the fountain and dirt paths
	fillBlock(0, -6, 15, 224, 12, 140, Enum.Material.Grass)
	Terrain:FillCylinder(CFrame.new(0, -2, 4), 4, 22, Enum.Material.Cobblestone)
	fillBlock(0, -2, -30, 9, 4, 50, Enum.Material.Ground)
	fillBlock(0, -2, 33, 9, 4, 22, Enum.Material.Ground)
	for _, target in ipairs({
		Vector3.new(-24, 0, 4),
		Vector3.new(24, 0, 14),
		Vector3.new(24, 0, -10),
		Vector3.new(42, 0, 2),
		Vector3.new(-42, 0, -12),
		Vector3.new(-36, 0, -36),
		Vector3.new(-36, 0, 32),
		Vector3.new(34, 0, 32),
		Vector3.new(30, 0, -34),
		Vector3.new(48, 0, -34),
	}) do
		local from = Vector3.new(0, 0, 4)
		local mid = (from + target) / 2
		local length = (target - from).Magnitude
		local angle = math.atan2(target.X - from.X, target.Z - from.Z)
		fillBlock(mid.X, -2, mid.Z, 6, 4, length, Enum.Material.Ground, angle)
	end
	-- the pond
	fillBlock(60, -6, 38, 26, 12, 22, Enum.Material.Sand)
	fillBlock(60, -2, 38, 20, 4, 16, Enum.Material.Water)

	-- Zone grounds
	for i, zone in ipairs(Shared.Zones) do
		local mid = (Shared.ZoneStart(i) + Shared.ZoneEnd(i)) / 2
		fillBlock(0, -6, mid, 224, 12, Layout.ZoneLength, zone.Ground)
	end
	fillBlock(0, -6, MAP_END - 20, 224, 12, 40, Shared.Zones[#Shared.Zones].Ground)

	-- Hills along both sides (they make each zone feel like a valley)
	local z = Layout.HubFront + 10
	while z > MAP_END - 10 do
		local zoneIndex = math.max(Shared.ZoneAt(z), 1)
		local zone = Shared.Zones[zoneIndex]
		for _, side in ipairs({ -1, 1 }) do
			local material = zone.Hills
			if rng:NextNumber() < 0.3 then
				material = if zoneIndex == 1 then Enum.Material.Rock else zone.Ground
			end
			Terrain:FillBall(Vector3.new(side * rng:NextNumber(98, 106), rng:NextNumber(-5, 2), z + rng:NextNumber(-4, 4)), rng:NextNumber(20, 28), material)
		end
		z -= 16
	end
	for x = -110, 110, 18 do
		Terrain:FillBall(Vector3.new(x, -3, Layout.HubFront + 20 + rng:NextNumber(-3, 3)), rng:NextNumber(20, 26), Enum.Material.Grass)
		Terrain:FillBall(Vector3.new(x, -3, MAP_END - 22 + rng:NextNumber(-3, 3)), rng:NextNumber(20, 26), Shared.Zones[#Shared.Zones].Hills)
	end

	-- Bumpy, natural ground inside the zones (never right at the entrance)
	local bumpMaterials = { Enum.Material.Grass, Enum.Material.Slate, Enum.Material.Basalt, Enum.Material.Snow, Enum.Material.Salt, Enum.Material.LeafyGrass, Enum.Material.Sand, Enum.Material.Limestone }
	for i = 1, #Shared.Zones do
		local zs, ze = Shared.ZoneStart(i), Shared.ZoneEnd(i)
		for _ = 1, 14 do
			local radius = rng:NextNumber(14, 24)
			local x, bz = rng:NextNumber(-62, 62), rng:NextNumber(ze + 12, zs - 40)
			Terrain:FillBall(Vector3.new(x, -radius + rng:NextNumber(1.5, 4), bz), radius, bumpMaterials[i] or Shared.Zones[i].Ground)
		end
	end

	-- Sunny Meadow: dirt patches, boulders and a lake
	do
		local zs, ze = Shared.ZoneStart(1), Shared.ZoneEnd(1)
		for _ = 1, 10 do
			fillBlock(rng:NextNumber(-60, 60), -1, rng:NextNumber(ze + 10, zs - 30), rng:NextNumber(6, 12), 2, rng:NextNumber(6, 12), Enum.Material.Ground, rng:NextNumber(0, math.pi))
		end
		for _ = 1, 8 do
			local pos = Vector3.new(rng:NextNumber(-60, 60), 0, rng:NextNumber(ze + 10, zs - 35))
			local radius = rng:NextNumber(2.5, 5)
			Terrain:FillBall(pos + Vector3.new(0, rng:NextNumber(-2, 0), 0), radius, Enum.Material.Rock)
			reserve(1, pos, radius + 2)
		end
		local lake = Vector3.new(44, 0, (zs + ze) / 2 + 30)
		Terrain:FillCylinder(CFrame.new(lake + Vector3.new(0, -4, 0)), 8, 17, Enum.Material.Sand)
		Terrain:FillCylinder(CFrame.new(lake + Vector3.new(0, -3, 0)), 6, 13, Enum.Material.Water)
		reserve(1, lake, 19)
	end

	-- The Crystal Caves (zone 2) get rock walls, pillars and a ceiling
	do
		local zs, ze = Shared.ZoneStart(2), Shared.ZoneEnd(2)
		local mid = (zs + ze) / 2
		for _, side in ipairs({ -1, 1 }) do
			fillBlock(side * 96, 22, mid, 16, 60, Layout.ZoneLength, Enum.Material.Slate)
			fillBlock(side * 69, 21, zs - 4, 82, 42, 8, Enum.Material.Rock)
			fillBlock(side * 69, 21, ze + 4, 82, 42, 8, Enum.Material.Rock)
		end
		fillBlock(0, 53, zs - 4, 220, 22, 8, Enum.Material.Rock)
		fillBlock(0, 53, ze + 4, 220, 22, 8, Enum.Material.Rock)
		fillBlock(0, 46, mid, 208, 12, Layout.ZoneLength, Enum.Material.Slate)
		for _, hole in ipairs({ Vector3.new(-30, 46, mid + 45), Vector3.new(35, 46, mid + 5), Vector3.new(-10, 46, mid - 50) }) do
			Terrain:FillBall(hole, 9, Enum.Material.Air)
		end
		for _ = 1, 6 do
			local pos = freeSpot(2, 6)
			if pos then
				Terrain:FillCylinder(CFrame.new(pos.X, 20, pos.Z), 44, rng:NextNumber(3, 5), Enum.Material.Rock)
				reserve(2, pos, 7)
			end
		end
	end

	-- A volcano in the Lava zone
	do
		local zs, ze = Shared.ZoneStart(3), Shared.ZoneEnd(3)
		local cx, cz = -62, (zs + ze) / 2
		for k = 0, 9 do
			Terrain:FillCylinder(CFrame.new(cx, k * 4 + 2, cz), 4, 30 - k * 2.6, Enum.Material.Basalt)
		end
		Terrain:FillCylinder(CFrame.new(cx, 39, cz), 8, 5.5, Enum.Material.Air)
		Terrain:FillCylinder(CFrame.new(cx, 34, cz), 2, 5.5, Enum.Material.CrackedLava)
		for _ = 1, 7 do
			local side = if rng:NextNumber() < 0.5 then -1 else 1
			fillBlock(side * rng:NextNumber(30, 70), -1, rng:NextNumber(ze + 15, zs - 30), 6, 2, rng:NextNumber(16, 34), Enum.Material.CrackedLava, rng:NextNumber(0, math.pi))
		end
	end

	-- A frozen lake in the Frozen Peaks
	do
		local zs, ze = Shared.ZoneStart(4), Shared.ZoneEnd(4)
		local lake = Vector3.new(-50, 0, (zs + ze) / 2 + 25)
		Terrain:FillCylinder(CFrame.new(lake + Vector3.new(0, -3, 0)), 8, 18, Enum.Material.Glacier)
		reserve(4, lake, 20)
		for _ = 1, 8 do
			local pos = Vector3.new(rng:NextNumber(-60, 60), 0, rng:NextNumber(ze + 10, zs - 35))
			local radius = rng:NextNumber(2.5, 4.5)
			Terrain:FillBall(pos + Vector3.new(0, rng:NextNumber(-2, 0), 0), radius, Enum.Material.Rock)
			reserve(4, pos, radius + 2)
		end
	end

	-- Dark boulders in the Galaxy Isles
	do
		local zs, ze = Shared.ZoneStart(5), Shared.ZoneEnd(5)
		for _ = 1, 10 do
			local pos = Vector3.new(rng:NextNumber(-60, 60), 0, rng:NextNumber(ze + 10, zs - 35))
			local radius = rng:NextNumber(2.5, 5)
			if not isReserved(5, pos, radius) then
				Terrain:FillBall(pos + Vector3.new(0, rng:NextNumber(-2, 0), 0), radius, Enum.Material.Slate)
				reserve(5, pos, radius + 2)
			end
		end
	end

	-- Flat ground where the bosses live
	for i, zone in ipairs(Shared.Zones) do
		local c = bossArenaCenter(i)
		Terrain:FillCylinder(CFrame.new(c.X, 16, c.Z), 32, BOSS_ARENA_RADIUS + 3, Enum.Material.Air)
		Terrain:FillCylinder(CFrame.new(c.X, -3, c.Z), 6, BOSS_ARENA_RADIUS + 3, zone.Ground)
	end
end

--------------------------------------------------------------------------------
-- DECORATIONS
--------------------------------------------------------------------------------
local Decor = {}

-- Shiny dimensions switch this on so their decorations glow
local decorShiny = false

local function gemMaterial(): Enum.Material
	return if decorShiny then Enum.Material.Neon else Enum.Material.Glass
end

-- A cylinder between two points (used for trunks and branches)
local function rod(from: Vector3, to: Vector3, width: number, props)
	local length = (to - from).Magnitude
	local cf = CFrame.lookAt((from + to) / 2, to) * CFrame.Angles(0, rad(90), 0)
	props.Shape = Enum.PartType.Cylinder
	props.Size = Vector3.new(length, width, width)
	props.CFrame = cf
	return P(props)
end

local LEAF_COLORS = {
	Color3.fromRGB(62, 96, 44),
	Color3.fromRGB(74, 108, 50),
	Color3.fromRGB(56, 86, 40),
	Color3.fromRGB(88, 118, 56),
	Color3.fromRGB(48, 78, 38),
}

function Decor.Tree(pos: Vector3, scale: number)
	local m = model("Tree")
	local bark = Color3.fromRGB(88, 66, 50):Lerp(Color3.fromRGB(70, 58, 50), rng:NextNumber())
	local trunkH = rng:NextNumber(7, 10) * scale
	local top = pos + Vector3.new(rng:NextNumber(-0.6, 0.6), trunkH, rng:NextNumber(-0.6, 0.6))
	rod(pos + Vector3.new(0, -0.5, 0), top, 1.3 * scale, { Name = "Trunk", Color = bark, Material = Enum.Material.Wood, Parent = m })
	-- roots spreading into the ground
	for k = 1, 4 do
		local a = k / 4 * math.pi * 2 + rng:NextNumber(-0.4, 0.4)
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		rod(pos + Vector3.new(0, 1.1 * scale, 0), pos + out * 1.9 * scale + Vector3.new(0, -0.2, 0), 0.55 * scale, {
			Name = "Root",
			Color = bark,
			Material = Enum.Material.Wood,
			CanCollide = false,
			Parent = m,
		})
	end
	for k = 1, 4 do
		local yaw = rng:NextNumber(0, math.pi * 2)
		local tilt = rad(rng:NextNumber(35, 60))
		local from = pos + Vector3.new(0, trunkH * rng:NextNumber(0.55, 0.85), 0)
		local dir = Vector3.new(math.cos(yaw) * math.sin(tilt), math.cos(tilt), math.sin(yaw) * math.sin(tilt))
		rod(from, from + dir * 3.8 * scale, 0.5 * scale, { Name = "Branch" .. k, Color = bark, Material = Enum.Material.Wood, CanCollide = false, Parent = m })
	end
	-- a leafy crown made of many clumps of leaves (big ones inside, small ones on the edge)
	local crown = top + Vector3.new(0, 1.6 * scale, 0)
	for k = 1, rng:NextInteger(12, 16) do
		local outer = k > 8
		local dir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.5, 0.8), rng:NextNumber(-1, 1))
		if dir.Magnitude < 0.01 then
			dir = Vector3.yAxis
		end
		local offset = dir.Unit * (if outer then rng:NextNumber(3, 4) else rng:NextNumber(0.5, 2.5)) * scale
		P({
			Name = "Leaves",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * (if outer then rng:NextNumber(2.2, 3.4) else rng:NextNumber(4, 5.8)) * scale,
			CFrame = CFrame.new(crown + offset),
			Color = LEAF_COLORS[rng:NextInteger(1, #LEAF_COLORS)],
			Material = Enum.Material.LeafyGrass,
			CanCollide = false,
			Parent = m,
		})
	end
end

-- A pine tree: rings of sloped wedges make round, pointy layers of needles
function Decor.Pine(pos: Vector3, scale: number, snowy: boolean?)
	local m = model("PineTree")
	local height = rng:NextNumber(13, 17) * scale
	rod(pos + Vector3.new(0, -0.5, 0), pos + Vector3.new(0, height * 0.7, 0), 0.9 * scale, {
		Name = "Trunk",
		Color = Color3.fromRGB(80, 58, 44),
		Material = Enum.Material.Wood,
		Parent = m,
	})
	local layers = 5
	for k = 0, layers - 1 do
		local t = k / (layers - 1)
		local radius = (4.6 - t * 3.2) * scale
		local h = (3.4 - t * 0.6) * scale
		local baseY = (2.2 + t * (height - 5.5))
		local needles = Color3.fromRGB(38, 66, 44):Lerp(Color3.fromRGB(56, 88, 56), t * 0.6)
		local useSnow = snowy and k >= 1
		for j = 0, 7 do
			local a = j / 8 * math.pi * 2 + k * 0.4
			local out = Vector3.new(math.cos(a), 0, math.sin(a))
			local center = pos + Vector3.new(0, baseY + h / 2, 0) + out * radius / 2
			P({
				Class = "WedgePart",
				Name = "Needles",
				Size = Vector3.new(radius * 0.86, h, radius),
				CFrame = CFrame.lookAt(center, center + out),
				Color = if useSnow then needles:Lerp(Color3.fromRGB(240, 244, 250), 0.55) else needles,
				Material = if useSnow then Enum.Material.Snow else Enum.Material.LeafyGrass,
				CanCollide = false,
				Parent = m,
			})
		end
	end
	if snowy then
		P({
			Name = "SnowTop",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 1.4 * scale,
			CFrame = CFrame.new(pos + Vector3.new(0, height - 0.2, 0)),
			Color = Color3.fromRGB(240, 244, 250),
			Material = Enum.Material.Snow,
			CanCollide = false,
			Parent = m,
		})
	end
end

function Decor.DeadTree(pos: Vector3, scale: number)
	local m = model("DeadTree")
	local char = Color3.fromRGB(38, 32, 30)
	local h = rng:NextNumber(6, 9) * scale
	local top = pos + Vector3.new(rng:NextNumber(-1, 1), h, rng:NextNumber(-1, 1))
	rod(pos + Vector3.new(0, -0.5, 0), top, 0.9 * scale, { Name = "Trunk", Color = char, Material = Enum.Material.Wood, Parent = m })
	for k = 1, 3 do
		local from = pos + Vector3.new(0, h * rng:NextNumber(0.5, 0.9), 0)
		local yaw = rng:NextNumber(0, math.pi * 2)
		local dir = Vector3.new(math.cos(yaw), rng:NextNumber(0.4, 1), math.sin(yaw)).Unit
		rod(from, from + dir * 3 * scale, 0.35 * scale, { Name = "Branch" .. k, Color = char, Material = Enum.Material.Wood, CanCollide = false, Parent = m })
	end
end

function Decor.Rock(pos: Vector3, scale: number, color: Color3, material: Enum.Material?)
	for k = 1, 2 do
		P({
			Name = "Rock",
			Size = Vector3.new(rng:NextNumber(3, 5), rng:NextNumber(2, 3.5), rng:NextNumber(3, 5)) * scale * (if k == 1 then 1 else 0.6),
			CFrame = CFrame.new(pos + Vector3.new(k * 1.2 * scale - 1.2 * scale, 0.5 * scale, 0)) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, math.pi), rng:NextNumber(-0.4, 0.4)),
			Color = color,
			Material = material or Enum.Material.Slate,
		})
	end
end

function Decor.Flowers(pos: Vector3)
	local colors = {
		Color3.fromRGB(215, 95, 120),
		Color3.fromRGB(235, 200, 70),
		Color3.fromRGB(240, 240, 235),
		Color3.fromRGB(150, 110, 200),
	}
	local color = colors[rng:NextInteger(1, #colors)]
	for _ = 1, rng:NextInteger(3, 6) do
		local spot = pos + Vector3.new(rng:NextNumber(-2, 2), 0, rng:NextNumber(-2, 2))
		rod(spot, spot + Vector3.new(0, 0.9, 0), 0.08, { Name = "Stem", Color = Color3.fromRGB(70, 110, 50), CanCollide = false, CastShadow = false })
		P({
			Name = "Flower",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * rng:NextNumber(0.35, 0.5),
			CFrame = CFrame.new(spot + Vector3.new(0, 0.95, 0)),
			Color = color,
			CanCollide = false,
			CastShadow = false,
		})
	end
end

function Decor.Bush(pos: Vector3, scale: number)
	for i = 1, 4 do
		P({
			Name = "Bush",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * rng:NextNumber(2.2, 3.4) * scale,
			CFrame = CFrame.new(pos + Vector3.new((i - 2.5) * 1.3 * scale, 0.9 * scale, rng:NextNumber(-0.8, 0.8) * scale)),
			Color = LEAF_COLORS[rng:NextInteger(1, #LEAF_COLORS)],
			Material = Enum.Material.Grass,
			CanCollide = false,
		})
	end
end

function Decor.Log(pos: Vector3, scale: number)
	local yaw = rng:NextNumber(0, math.pi)
	local dir = Vector3.new(math.cos(yaw), 0, math.sin(yaw))
	rod(pos - dir * 3 * scale + Vector3.new(0, 0.6 * scale, 0), pos + dir * 3 * scale + Vector3.new(0, 0.6 * scale, 0), 1.2 * scale, {
		Name = "Log",
		Color = Color3.fromRGB(92, 70, 52),
		Material = Enum.Material.Wood,
	})
end

-- A park lamp: stone foot, iron pole and a round frosted glass globe
function Decor.Lamp(pos: Vector3)
	local m = model("Lamp")
	local iron = Color3.fromRGB(32, 34, 38)
	local upright = CFrame.Angles(0, 0, rad(90))
	P({ Name = "Base", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8, 1.7, 1.7), CFrame = CFrame.new(pos + Vector3.new(0, 0.4, 0)) * upright, Color = Color3.fromRGB(120, 116, 110), Material = Enum.Material.Slate, Parent = m })
	P({ Name = "Foot", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 0.95, 0.95), CFrame = CFrame.new(pos + Vector3.new(0, 1.3, 0)) * upright, Color = iron, Material = Enum.Material.Metal, Parent = m })
	rod(pos + Vector3.new(0, 1.3, 0), pos + Vector3.new(0, 8.7, 0), 0.34, { Name = "Pole", Color = iron, Material = Enum.Material.Metal, Parent = m })
	for _, y in ipairs({ 2.3, 7.9 }) do
		P({ Name = "PoleRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.25, 0.6, 0.6), CFrame = CFrame.new(pos + Vector3.new(0, y, 0)) * upright, Color = iron, Material = Enum.Material.Metal, Parent = m })
	end
	P({ Name = "Neck", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 0.8, 0.8), CFrame = CFrame.new(pos + Vector3.new(0, 8.95, 0)) * upright, Color = iron, Material = Enum.Material.Metal, Parent = m })
	P({
		Name = "Globe",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 1.9,
		CFrame = CFrame.new(pos + Vector3.new(0, 10.05, 0)),
		Color = Color3.fromRGB(255, 246, 228),
		Material = Enum.Material.Glass,
		Transparency = 0.3,
		CanCollide = false,
		Parent = m,
	})
	local bulb = P({
		Name = "Bulb",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 0.7,
		CFrame = CFrame.new(pos + Vector3.new(0, 10.05, 0)),
		Color = Color3.fromRGB(255, 222, 165),
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
		Parent = m,
	})
	P({ Name = "Cap", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 0.95, 0.95), CFrame = CFrame.new(pos + Vector3.new(0, 11.05, 0)) * upright, Color = iron, Material = Enum.Material.Metal, Parent = m })
	P({ Name = "Finial", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.38, CFrame = CFrame.new(pos + Vector3.new(0, 11.35, 0)), Color = iron, Material = Enum.Material.Metal, Parent = m })
	light(bulb, Color3.fromRGB(255, 210, 160), 18, 1.1)
end

-- A lantern on a wall. cf is on the wall surface, with -Z pointing out of the wall.
function Decor.Lantern(cf: CFrame, parent: Instance?)
	local m = model("Lantern", parent)
	local iron = Color3.fromRGB(32, 32, 36)
	P({ Name = "Bracket", Size = Vector3.new(0.25, 0.25, 1.6), CFrame = cf * CFrame.new(0, 1.2, -0.8), Color = iron, Material = Enum.Material.Metal, Parent = m })
	P({ Name = "WallPlate", Size = Vector3.new(0.9, 1.6, 0.15), CFrame = cf * CFrame.new(0, 0.9, -0.07), Color = iron, Material = Enum.Material.Metal, Parent = m })
	local body = cf * CFrame.new(0, 0, -1.6)
	P({ Name = "Hook", Size = Vector3.new(0.1, 0.45, 0.1), CFrame = body * CFrame.new(0, 1.05, 0), Color = iron, Material = Enum.Material.Metal, Parent = m })
	P({ Name = "Top", Size = Vector3.new(1.05, 0.16, 1.05), CFrame = body * CFrame.new(0, 0.72, 0), Color = iron, Material = Enum.Material.Metal, Parent = m })
	P({ Name = "Roof", Size = Vector3.new(0.75, 0.14, 0.75), CFrame = body * CFrame.new(0, 0.86, 0), Color = iron, Material = Enum.Material.Metal, Parent = m })
	P({ Name = "Bottom", Size = Vector3.new(0.95, 0.16, 0.95), CFrame = body * CFrame.new(0, -0.66, 0), Color = iron, Material = Enum.Material.Metal, Parent = m })
	for _, x in ipairs({ -0.42, 0.42 }) do
		for _, z in ipairs({ -0.42, 0.42 }) do
			P({ Name = "Post", Size = Vector3.new(0.1, 1.3, 0.1), CFrame = body * CFrame.new(x, 0.03, z), Color = iron, Material = Enum.Material.Metal, CanCollide = false, Parent = m })
		end
	end
	P({ Name = "Glass", Size = Vector3.new(0.82, 1.24, 0.82), CFrame = body, Color = Color3.fromRGB(255, 225, 170), Material = Enum.Material.Glass, Transparency = 0.35, CanCollide = false, Parent = m })
	local flame = P({ Name = "Flame", Shape = Enum.PartType.Ball, Size = Vector3.new(0.35, 0.35, 0.35), CFrame = body * CFrame.new(0, -0.1, 0), Color = Color3.fromRGB(255, 190, 110), Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = m })
	light(flame, Color3.fromRGB(255, 180, 110), 16, 1.1)
end

function Decor.Bench(pos: Vector3, yaw: number)
	local m = model("Bench")
	local wood = Color3.fromRGB(120, 88, 60)
	local base = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
	P({ Name = "Seat", Size = Vector3.new(6, 0.4, 1.8), CFrame = base * CFrame.new(0, 1.6, 0), Color = wood, Material = Enum.Material.WoodPlanks, Parent = m })
	P({ Name = "Back", Size = Vector3.new(6, 1.6, 0.3), CFrame = base * CFrame.new(0, 2.6, 0.85), Color = wood, Material = Enum.Material.WoodPlanks, Parent = m })
	for _, x in ipairs({ -2.6, 2.6 }) do
		P({ Name = "Leg", Size = Vector3.new(0.3, 1.6, 1.6), CFrame = base * CFrame.new(x, 0.8, 0), Color = Color3.fromRGB(40, 40, 44), Material = Enum.Material.Metal, Parent = m })
	end
end

function Decor.Fence(from: Vector3, to: Vector3)
	local m = model("Fence")
	local wood = Color3.fromRGB(110, 82, 58)
	local length = (to - from).Magnitude
	local posts = math.max(2, math.floor(length / 6) + 1)
	for k = 0, posts - 1 do
		local p = from:Lerp(to, k / (posts - 1))
		P({ Name = "Post", Size = Vector3.new(0.5, 3.4, 0.5), CFrame = CFrame.new(p + Vector3.new(0, 1.5, 0)), Color = wood, Material = Enum.Material.Wood, Parent = m })
	end
	for _, y in ipairs({ 1.2, 2.6 }) do
		local cf = CFrame.lookAt((from + to) / 2 + Vector3.new(0, y, 0), to + Vector3.new(0, y, 0))
		P({ Name = "Rail", Size = Vector3.new(0.25, 0.35, length), CFrame = cf, Color = wood, Material = Enum.Material.Wood, Parent = m })
	end
end

-- A cluster of gem crystals growing out of rock (used for decoration)
function Decor.Spire(pos: Vector3, scale: number, color: Color3)
	local m = model("CrystalFormation")
	P({
		Name = "Rock",
		Size = Vector3.new(4, 2, 4) * scale,
		CFrame = CFrame.new(pos + Vector3.new(0, 0.4 * scale, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
		Color = Color3.fromRGB(70, 66, 70),
		Material = Enum.Material.Slate,
		Parent = m,
	})
	local main
	for i = 1, 4 do
		local h = rng:NextNumber(5, 11) * scale * (if i == 1 then 1.3 else 0.8)
		local tilt = CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, math.pi), rng:NextNumber(-0.4, 0.4))
		local shard = P({
			Name = "Shard",
			Size = Vector3.new(1.6 * scale, h, 1.6 * scale),
			CFrame = CFrame.new(pos + Vector3.new(rng:NextNumber(-1.2, 1.2) * scale, 0, rng:NextNumber(-1.2, 1.2) * scale)) * tilt * CFrame.new(0, h / 2, 0),
			Color = color,
			Material = gemMaterial(),
			Transparency = if decorShiny then 0 else 0.1,
			Reflectance = if decorShiny then 0 else 0.25,
			Parent = m,
		})
		main = main or shard
	end
	light(main, color, if decorShiny then 22 else 12, if decorShiny then 2 else 0.6)
end

function Decor.Mushroom(pos: Vector3, scale: number, color: Color3)
	local m = model("Mushroom")
	rod(pos, pos + Vector3.new(0, 3 * scale, 0), 0.8 * scale, { Name = "Stem", Color = Color3.fromRGB(215, 205, 190), CanCollide = false, Parent = m })
	local cap = P({
		Name = "Cap",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 3 * scale,
		CFrame = CFrame.new(pos + Vector3.new(0, 3.1 * scale, 0)),
		Color = color,
		Material = if decorShiny then Enum.Material.Neon else Enum.Material.SmoothPlastic,
		CanCollide = false,
		Parent = m,
	})
	light(cap, color, 9 * scale, if decorShiny then 1.5 else 0.5)
end

function Decor.IceSpike(pos: Vector3, scale: number)
	local h = rng:NextNumber(6, 12) * scale
	P({
		Name = "IceSpike",
		Size = Vector3.new(1.8 * scale, h, 1.8 * scale),
		CFrame = CFrame.new(pos + Vector3.new(0, h / 2 - 0.5, 0)) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, math.pi), rng:NextNumber(-0.3, 0.3)),
		Color = Color3.fromRGB(175, 210, 235),
		Material = Enum.Material.Ice,
		Transparency = 0.1,
	})
end

function Decor.Snowman(pos: Vector3, rotY: number)
	local m = model("Snowman")
	local base = CFrame.new(pos) * CFrame.Angles(0, rotY, 0)
	local snow = Color3.fromRGB(240, 244, 250)
	for i, info in ipairs({ { 4.4, 2 }, { 3.3, 5.2 }, { 2.4, 7.7 } }) do
		P({
			Name = "Snowball" .. i,
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * info[1],
			CFrame = base * CFrame.new(0, info[2], 0),
			Color = snow,
			Material = Enum.Material.Snow,
			Parent = m,
		})
	end
	P({
		Name = "Nose",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.2, 0.35, 0.35),
		CFrame = base * CFrame.new(0, 7.7, -1.4) * CFrame.Angles(0, rad(90), 0),
		Color = Color3.fromRGB(230, 120, 40),
		CanCollide = false,
		Parent = m,
	})
	for _, side in ipairs({ -1, 1 }) do
		P({
			Name = "Eye",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 0.35,
			CFrame = base * CFrame.new(0.45 * side, 8.1, -1.05),
			Color = Color3.fromRGB(25, 25, 30),
			CanCollide = false,
			Parent = m,
		})
	end
	P({
		Name = "Hat",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.6, 1.7, 1.7),
		CFrame = base * CFrame.new(0, 9.4, 0) * CFrame.Angles(0, 0, rad(90)),
		Color = Color3.fromRGB(35, 35, 45),
		CanCollide = false,
		Parent = m,
	})
end

function Decor.LavaPool(pos: Vector3, radius: number)
	local pool = P({
		Name = "LavaPool",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, radius * 2, radius * 2),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, rad(90)),
		Color = Color3.fromRGB(230, 90, 25),
		Material = Enum.Material.CrackedLava,
		CanCollide = false,
		CastShadow = false,
	})
	light(pool, Color3.fromRGB(255, 120, 40), radius * 2.5, 1.5)
	particles(pool, {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Color = Color3.fromRGB(90, 80, 75),
		LightEmission = 0,
		Size = 2,
		EndSize = 5,
		Rate = 2,
		Lifetime = NumberRange.new(3, 5),
		Speed = NumberRange.new(1, 2),
		Direction = Enum.NormalId.Right,
		Transparency = 0.6,
	})
end

function Decor.Planet(pos: Vector3, size: number, color: Color3, material: Enum.Material, ringColor: Color3?)
	local planet = P({
		Name = "Planet",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * size,
		CFrame = CFrame.new(pos),
		Color = color,
		Material = material,
		CanCollide = false,
		CastShadow = false,
	})
	spin(planet, 0.05, 2)
	if ringColor then
		P({
			Name = "Ring",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.3, size * 1.9, size * 1.9),
			CFrame = CFrame.new(pos) * CFrame.Angles(rad(20), 0, rad(90)),
			Color = ringColor,
			Material = Enum.Material.SmoothPlastic,
			Transparency = 0.55,
			CanCollide = false,
			CastShadow = false,
		})
	end
end

function Decor.FloatingRock(pos: Vector3, scale: number, glow: Color3)
	local rock = P({
		Name = "FloatingRock",
		Size = Vector3.new(rng:NextNumber(4, 7), rng:NextNumber(2, 4), rng:NextNumber(4, 7)) * scale,
		CFrame = CFrame.new(pos) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, math.pi), rng:NextNumber(-0.4, 0.4)),
		Color = Color3.fromRGB(64, 60, 70),
		Material = Enum.Material.Slate,
		CanCollide = false,
	})
	local gem = P({
		Name = "Gem",
		Size = Vector3.new(1, 2.4, 1) * scale,
		CFrame = rock.CFrame * CFrame.new(0, rock.Size.Y / 2 + 0.6 * scale, 0),
		Color = glow,
		Material = gemMaterial(),
		Transparency = if decorShiny then 0 else 0.1,
		CanCollide = false,
	})
	spin(rock, 0.15, 1.5)
	spin(gem, 0.15, 1.5)
end

function Decor.Lollipop(pos: Vector3, scale: number, color: Color3)
	local m = model("Lollipop")
	local h = 7 * scale
	rod(pos, pos + Vector3.new(0, h, 0), 0.6 * scale, { Name = "Stick", Color = Color3.fromRGB(245, 240, 230), Parent = m })
	local candy = P({
		Name = "Candy",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1 * scale, 5 * scale, 5 * scale),
		CFrame = CFrame.new(pos + Vector3.new(0, h + 1.8 * scale, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
		Color = color,
		Material = if decorShiny then Enum.Material.Neon else Enum.Material.SmoothPlastic,
		Reflectance = 0.15,
		CanCollide = false,
		Parent = m,
	})
	P({
		Name = "Swirl",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.1 * scale, 2.6 * scale, 2.6 * scale),
		CFrame = candy.CFrame,
		Color = Color3.fromRGB(250, 248, 245),
		CanCollide = false,
		Parent = m,
	})
end

function Decor.Cactus(pos: Vector3, scale: number)
	local m = model("Cactus")
	local green = Color3.fromRGB(70, 120, 66)
	local h = 8 * scale
	rod(pos, pos + Vector3.new(0, h, 0), 1.6 * scale, { Name = "Trunk", Color = green, Material = Enum.Material.Grass, Parent = m })
	for _, side in ipairs({ -1, 1 }) do
		local armY = h * rng:NextNumber(0.4, 0.65)
		local elbow = pos + Vector3.new(side * 2.2 * scale, armY, 0)
		rod(pos + Vector3.new(0, armY, 0), elbow, 1.1 * scale, { Name = "Arm", Color = green, Material = Enum.Material.Grass, Parent = m })
		rod(elbow, elbow + Vector3.new(0, 2.6 * scale, 0), 1.1 * scale, { Name = "ArmUp", Color = green, Material = Enum.Material.Grass, Parent = m })
	end
end

-- Broken sandstone columns (Ancient Desert)
function Decor.Ruin(pos: Vector3, scale: number)
	local m = model("Ruin")
	local stone = Color3.fromRGB(205, 175, 125)
	for _ = 1, rng:NextInteger(2, 3) do
		local h = rng:NextNumber(4, 12) * scale
		local spot = pos + Vector3.new(rng:NextNumber(-4, 4), 0, rng:NextNumber(-4, 4)) * scale
		P({ Name = "ColumnBase", Size = Vector3.new(3, 0.8, 3) * scale, CFrame = CFrame.new(spot + Vector3.new(0, 0.4 * scale, 0)), Color = stone:Lerp(Color3.fromRGB(120, 100, 75), 0.2), Material = Enum.Material.Sandstone, Parent = m })
		P({ Name = "Column", Shape = Enum.PartType.Cylinder, Size = Vector3.new(h, 2.2 * scale, 2.2 * scale), CFrame = CFrame.new(spot + Vector3.new(0, h / 2 + 0.8 * scale, 0)) * CFrame.Angles(0, 0, rad(90)), Color = stone, Material = Enum.Material.Sandstone, Parent = m })
	end
	P({
		Name = "Fallen",
		Size = Vector3.new(5, 2, 2.4) * scale,
		CFrame = CFrame.new(pos + Vector3.new(rng:NextNumber(-3, 3), 0.9 * scale, rng:NextNumber(-3, 3))) * CFrame.Angles(0, rng:NextNumber(0, math.pi), rng:NextNumber(-0.2, 0.2)),
		Color = stone,
		Material = Enum.Material.Sandstone,
		Parent = m,
	})
end

-- A big stepped pyramid with a golden tip (Ancient Desert)
function Decor.Pyramid(pos: Vector3, size: number)
	local m = model("Pyramid")
	local layers = 8
	local step = size / layers * 0.85
	for k = 0, layers - 1 do
		local w = size * (1 - k / layers)
		P({
			Name = "Layer",
			Size = Vector3.new(w, step, w),
			CFrame = CFrame.new(pos + Vector3.new(0, (k + 0.5) * step, 0)),
			Color = Color3.fromRGB(215, 180, 120):Lerp(Color3.fromRGB(185, 145, 92), k / layers),
			Material = Enum.Material.Sandstone,
			Parent = m,
		})
	end
	local tip = P({
		Name = "GoldTip",
		Size = Vector3.new(size / layers, step, size / layers) * 0.9,
		CFrame = CFrame.new(pos + Vector3.new(0, (layers + 0.45) * step, 0)),
		Color = Color3.fromRGB(240, 190, 60),
		Material = Enum.Material.Metal,
		Reflectance = 0.3,
		Parent = m,
	})
	light(tip, Color3.fromRGB(255, 210, 120), 20, 1)
	P({ Name = "Door", Size = Vector3.new(0.6, step * 1.6, size * 0.12), CFrame = CFrame.new(pos + Vector3.new(size / 2 + 0.1, step * 0.8, 0)), Color = Color3.fromRGB(40, 30, 25), Parent = m })
end

-- A castle tower with a golden roof and a flag (Golden Kingdom)
function Decor.Tower(pos: Vector3, scale: number)
	local m = model("Tower")
	local h = rng:NextNumber(18, 26) * scale
	local r = 3.2 * scale
	local stone = Color3.fromRGB(225, 215, 195)
	local gold = Color3.fromRGB(230, 180, 50)
	P({ Name = "Tower", Shape = Enum.PartType.Cylinder, Size = Vector3.new(h, r * 2, r * 2), CFrame = CFrame.new(pos + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, 0, rad(90)), Color = stone, Material = Enum.Material.Limestone, Parent = m })
	for k = 0, 7 do
		local a = k / 8 * math.pi * 2
		P({ Name = "Merlon", Size = Vector3.new(1.2, 1.4, 1.2) * scale, CFrame = CFrame.new(pos + Vector3.new(math.cos(a) * r * 0.85, h + 0.7 * scale, math.sin(a) * r * 0.85)), Color = stone, Material = Enum.Material.Limestone, Parent = m })
	end
	for k = 0, 4 do
		local ring = r * (1 - k / 5) * 0.9
		P({ Name = "Roof", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.1 * scale, ring * 2, ring * 2), CFrame = CFrame.new(pos + Vector3.new(0, h + (1.6 + k * 1.05) * scale, 0)) * CFrame.Angles(0, 0, rad(90)), Color = gold, Material = Enum.Material.Metal, Reflectance = 0.2, Parent = m })
	end
	for _, y in ipairs({ 0.45, 0.75 }) do
		P({ Name = "Window", Size = Vector3.new(0.4, 1.8, 1) * scale, CFrame = CFrame.new(pos + Vector3.new(r - 0.1, h * y, 0)), Color = Color3.fromRGB(60, 45, 35), Parent = m })
	end
	local top = pos + Vector3.new(0, h + 7 * scale, 0)
	rod(top - Vector3.new(0, 2 * scale, 0), top + Vector3.new(0, 3 * scale, 0), 0.18, { Name = "FlagPole", Color = Color3.fromRGB(70, 60, 50), Material = Enum.Material.Metal, Parent = m })
	P({ Name = "Flag", Size = Vector3.new(0.1, 1.5, 2.4) * scale, CFrame = CFrame.new(top + Vector3.new(0, 2.2 * scale, 1.25 * scale)), Color = Color3.fromRGB(200, 30, 60), Material = Enum.Material.Fabric, CanCollide = false, Parent = m })
end

function Decor.Cloud(pos: Vector3, scale: number)
	for i = 1, 5 do
		P({
			Name = "Cloud",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * rng:NextNumber(4, 7) * scale,
			CFrame = CFrame.new(pos + Vector3.new((i - 3) * 2.6 * scale, rng:NextNumber(1, 3) * scale, rng:NextNumber(-1.5, 1.5) * scale)),
			Color = Color3.fromRGB(248, 248, 250),
			Transparency = 0.1,
			CanCollide = false,
		})
	end
end

function Decor.Pillar(pos: Vector3, scale: number, color: Color3)
	local m = model("Pillar")
	local h = rng:NextNumber(10, 18) * scale
	P({
		Name = "Pillar",
		Size = Vector3.new(2.5, h, 2.5) * Vector3.new(scale, 1, scale),
		CFrame = CFrame.new(pos + Vector3.new(0, h / 2, 0)),
		Color = Color3.fromRGB(58, 58, 70),
		Material = Enum.Material.Metal,
		Parent = m,
	})
	for _, y in ipairs({ 0.3, 0.6, 0.9 }) do
		P({
			Name = "Stripe",
			Size = Vector3.new(2.7, 0.4, 2.7) * Vector3.new(scale, 1, scale),
			CFrame = CFrame.new(pos + Vector3.new(0, h * y, 0)),
			Color = if decorShiny then color else Color3.fromRGB(110, 110, 120),
			Material = if decorShiny then Enum.Material.Neon else Enum.Material.Metal,
			CanCollide = false,
			Parent = m,
		})
	end
	local lamp = P({
		Name = "Lamp",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 1.6 * scale,
		CFrame = CFrame.new(pos + Vector3.new(0, h + 1 * scale, 0)),
		Color = color,
		Material = if decorShiny then Enum.Material.Neon else Enum.Material.Glass,
		CanCollide = false,
		Parent = m,
	})
	light(lamp, color, 16, if decorShiny then 1.8 else 0.7)
end

-- Big stone arch (used for zone entrances): stone blocks, banners, lanterns,
-- a keystone and battlements, with the name carved into the stone
local function buildArch(z: number, zone, parent: Instance, title: string, subtitle: string?)
	local stone = zone.RockColor:Lerp(Color3.fromRGB(160, 155, 148), 0.55)
	local dark = stone:Lerp(Color3.new(0, 0, 0), 0.25)
	local gold = Color3.fromRGB(205, 170, 80)
	for _, side in ipairs({ -1, 1 }) do
		local x = side * 24
		P({ Name = "Plinth", Size = Vector3.new(10.5, 3, 10.5), CFrame = CFrame.new(x, 1.5, z), Color = dark, Material = Enum.Material.Slate, Parent = parent })
		P({ Name = "PillarCore", Size = Vector3.new(7.2, 34, 7.2), CFrame = CFrame.new(x, 19, z), Color = dark, Material = Enum.Material.Slate, Parent = parent })
		-- stone blocks with mortar lines between them
		for k = 0, 5 do
			P({
				Name = "Block",
				Size = Vector3.new(8, 5.1, 8),
				CFrame = CFrame.new(x + rng:NextNumber(-0.06, 0.06), 5.6 + k * 5.5, z + rng:NextNumber(-0.06, 0.06)),
				Color = stone:Lerp(dark, rng:NextNumber(0, 0.35)),
				Material = Enum.Material.Cobblestone,
				Parent = parent,
			})
		end
		P({ Name = "Capital", Size = Vector3.new(9.6, 1.4, 9.6), CFrame = CFrame.new(x, 37, z), Color = stone, Material = Enum.Material.Slate, Parent = parent })
		-- banners in the zone's color on both sides
		for _, face in ipairs({ -1, 1 }) do
			local bz = z + face * 4.12
			P({ Name = "BannerRod", Shape = Enum.PartType.Cylinder, Size = Vector3.new(4.2, 0.2, 0.2), CFrame = CFrame.new(x, 33.3, bz + face * 0.15), Color = gold, Material = Enum.Material.Metal, Parent = parent })
			P({ Name = "Banner", Size = Vector3.new(3.4, 11, 0.12), CFrame = CFrame.new(x, 27.6, bz + face * 0.1), Color = zone.Accent:Lerp(Color3.new(0, 0, 0), 0.3), Material = Enum.Material.Fabric, Parent = parent })
			P({ Name = "BannerTrim", Size = Vector3.new(3.5, 0.35, 0.14), CFrame = CFrame.new(x, 22.3, bz + face * 0.12), Color = gold, Material = Enum.Material.Fabric, Parent = parent })
			P({ Name = "BannerTip", Size = Vector3.new(1.7, 1.7, 0.12), CFrame = CFrame.new(x, 21.9, bz + face * 0.1) * CFrame.Angles(0, 0, rad(45)), Color = zone.Accent:Lerp(Color3.new(0, 0, 0), 0.3), Material = Enum.Material.Fabric, Parent = parent })
			Decor.Lantern(CFrame.lookAt(Vector3.new(x - side * 4, 13, bz), Vector3.new(x - side * 4, 13, bz) + Vector3.new(0, 0, face)), parent)
		end
	end
	local beam = P({ Name = "Beam", Size = Vector3.new(58, 6, 9), CFrame = CFrame.new(0, 40.5, z), Color = stone, Material = Enum.Material.Cobblestone, Parent = parent })
	P({ Name = "Cornice", Size = Vector3.new(60, 1, 10), CFrame = CFrame.new(0, 44, z), Color = dark, Material = Enum.Material.Slate, Parent = parent })
	P({ Name = "BeamBottom", Size = Vector3.new(41, 0.8, 9.4), CFrame = CFrame.new(0, 37.2, z), Color = dark, Material = Enum.Material.Slate, Parent = parent })
	-- battlements on top, with a gem crest in the middle
	for k = -4, 4 do
		if k ~= 0 then
			P({ Name = "Merlon", Size = Vector3.new(3.4, 2.6, 9.4), CFrame = CFrame.new(k * 6.5, 45.8, z), Color = stone:Lerp(dark, rng:NextNumber(0, 0.3)), Material = Enum.Material.Cobblestone, Parent = parent })
		end
	end
	P({ Name = "Crest", Size = Vector3.new(6, 5.5, 9.6), CFrame = CFrame.new(0, 47, z), Color = stone:Lerp(Color3.new(1, 1, 1), 0.1), Material = Enum.Material.Slate, Parent = parent })
	for _, face in ipairs({ -1, 1 }) do
		P({ Name = "CrestGem", Size = Vector3.new(2.2, 2.2, 0.7), CFrame = CFrame.new(0, 47.4, z + face * 4.9) * CFrame.Angles(0, 0, rad(45)), Color = zone.CrystalColors[1], Material = Enum.Material.Glass, Reflectance = 0.3, Parent = parent })
	end
	-- the name, carved into a stone plate on both sides of the arch
	local signColor = zone.Accent:Lerp(Color3.fromRGB(255, 230, 160), 0.5)
	for _, info in ipairs({ { -1, Enum.NormalId.Front }, { 1, Enum.NormalId.Back } }) do
		local plate = P({
			Name = "NamePlate",
			Size = Vector3.new(32, 4.6, 0.3),
			CFrame = CFrame.new(0, 40.5, z + info[1] * 4.62),
			Color = dark:Lerp(Color3.new(0, 0, 0), 0.2),
			Material = Enum.Material.Slate,
			Parent = parent,
		})
		carvedText(plate, info[2], title, subtitle, signColor)
	end
	return beam
end

--------------------------------------------------------------------------------
-- SELL CIRCLES (stand inside to sell your gems)
--------------------------------------------------------------------------------
type SellPad = { Model: Model, Pad: BasePart, Radius: number, Zone: number, Dimension: number? }
local sellPads: { SellPad } = {}

-- A big gold coin (floats over sell circles)
local function buildCoin(parent: Instance, cf: CFrame, size: number): BasePart
	local gold = Color3.fromRGB(230, 185, 70)
	local turn = CFrame.Angles(0, rad(90), 0)
	local coin = P({ Name = "Coin", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.45, size, size) * 1, CFrame = cf * turn, Color = gold, Material = Enum.Material.Metal, Reflectance = 0.25, CanCollide = false, Parent = parent })
	P({ Name = "CoinRim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.55, size * 0.8, size * 0.8), CFrame = cf * turn, Color = gold:Lerp(Color3.new(0, 0, 0), 0.2), Material = Enum.Material.Metal, Reflectance = 0.2, CanCollide = false, Parent = parent })
	P({ Name = "CoinStar", Size = Vector3.new(size * 0.32, size * 0.32, 0.62), CFrame = cf * CFrame.Angles(0, 0, rad(45)), Color = Color3.fromRGB(255, 225, 120), Material = Enum.Material.Metal, Reflectance = 0.3, CanCollide = false, Parent = parent })
	return coin
end

-- zone = the zone you need to have unlocked; dimension = the island it is on (if any)
local function buildSellPad(pos: Vector3, size: number, zone: number, dimension: number?)
	local m = model("SellPad", SellFolder)
	m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	m:SetAttribute("Zone", zone)
	if dimension then
		m:SetAttribute("Dimension", dimension)
	end
	local radius = size / 2
	local gold = Color3.fromRGB(240, 190, 60)
	local pad = P({
		Name = "Pad",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, size + 0.6, size + 0.6),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, rad(90)),
		Color = Color3.fromRGB(150, 142, 128),
		Material = Enum.Material.Pavement,
		Parent = m,
	})
	actionCircle(pos, radius, gold, "Sell", nil, m)
	-- piles of coins and a sack in the middle
	local sack = P({ Name = "Sack", Shape = Enum.PartType.Ball, Size = Vector3.new(2.6, 2.3, 2.6), CFrame = CFrame.new(pos + Vector3.new(0, 1.15, 0)), Color = Color3.fromRGB(190, 160, 110), Material = Enum.Material.Fabric, Parent = m })
	P({ Name = "SackNeck", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 1, 1), CFrame = CFrame.new(pos + Vector3.new(0, 2.45, 0)) * CFrame.Angles(0, 0, rad(90)), Color = Color3.fromRGB(175, 145, 98), Material = Enum.Material.Fabric, Parent = m })
	P({ Name = "SackRope", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 1.1, 1.1), CFrame = CFrame.new(pos + Vector3.new(0, 2.3, 0)) * CFrame.Angles(0, 0, rad(90)), Color = Color3.fromRGB(120, 60, 40), Material = Enum.Material.Fabric, Parent = m })
	for k = 1, 6 do
		local a = k / 6 * math.pi * 2
		local r = rng:NextNumber(1.8, 2.6)
		local h = rng:NextNumber(0.3, 1)
		P({
			Name = "Coins",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(h, 1.1, 1.1),
			CFrame = CFrame.new(pos + Vector3.new(math.cos(a) * r, 0.2 + h / 2, math.sin(a) * r)) * CFrame.Angles(0, 0, rad(90)),
			Color = Color3.fromRGB(230, 185, 70),
			Material = Enum.Material.Metal,
			Reflectance = 0.25,
			CanCollide = false,
			Parent = m,
		})
	end
	local holder = model("FloatingCoin", m)
	local coin = buildCoin(holder, CFrame.new(pos + Vector3.new(0, 6.5, 0)), 3)
	holder.PrimaryPart = coin
	spin(holder, 1.2, 0.4)
	light(sack, gold, 14, 0.6)
	local bonus = Shared.DimensionSellBonus(dimension)
	fancySign(coin, "💰", "SELL", if bonus > 1 then "Coins x" .. string.format("%g", bonus) .. " here!" else "Step in the circle to sell", gold, 10, 3.2)
	local target = Instance.new("Attachment")
	target.Name = "GuideTarget"
	target.Position = Vector3.new(0.5, 0, 0)
	target.Parent = pad
	-- the selling itself happens in the SELLING loop further down
	table.insert(sellPads, { Model = m, Pad = pad, Radius = radius, Zone = zone, Dimension = dimension })
	return m
end

--------------------------------------------------------------------------------
-- EGG MACHINES (stand in the circle to see the pets and hatch)
--------------------------------------------------------------------------------
local hatchEgg -- defined later
local eggMachines: { [number]: Vector3 } = {} -- where each egg machine stands

local function buildEggMachine(eggId: number, pos: Vector3, parent: Instance?)
	local egg = Shared.GetEgg(eggId)
	local m = model("EggMachine" .. eggId, parent)
	m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local stone = Color3.fromRGB(122, 116, 110)
	local gold = Color3.fromRGB(205, 165, 75)
	local upright = CFrame.Angles(0, 0, rad(90))
	local accent = egg.Cap or egg.Spots
	actionCircle(pos, 8, accent:Lerp(Color3.fromRGB(255, 240, 200), 0.3), "Egg", eggId, m)
	P({ Name = "Base", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8, 7, 7), CFrame = CFrame.new(pos + Vector3.new(0, 0.4, 0)) * upright, Color = stone, Material = Enum.Material.Cobblestone, Parent = m })
	P({ Name = "Trim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 7.5, 7.5), CFrame = CFrame.new(pos + Vector3.new(0, 0.85, 0)) * upright, Color = gold, Material = Enum.Material.Metal, Parent = m })
	P({ Name = "Column", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3.4, 3.6, 3.6), CFrame = CFrame.new(pos + Vector3.new(0, 2.6, 0)) * upright, Color = Color3.fromRGB(225, 220, 212), Material = Enum.Material.Marble, Parent = m })
	for k = 0, 7 do
		local a = k / 8 * math.pi * 2
		P({ Name = "Flute", Size = Vector3.new(0.35, 3.4, 0.35), CFrame = CFrame.new(pos + Vector3.new(math.cos(a) * 1.82, 2.6, math.sin(a) * 1.82)), Color = Color3.fromRGB(205, 200, 192), Material = Enum.Material.Marble, Parent = m })
	end
	local top = P({ Name = "Top", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 5, 5), CFrame = CFrame.new(pos + Vector3.new(0, 4.5, 0)) * upright, Color = gold, Material = Enum.Material.Metal, Reflectance = 0.15, Parent = m })
	-- little gems around the top plate
	for k = 0, 5 do
		local a = k / 6 * math.pi * 2
		P({ Name = "TopGem", Size = Vector3.new(0.5, 0.5, 0.5), CFrame = CFrame.new(pos + Vector3.new(math.cos(a) * 2.25, 4.85, math.sin(a) * 2.25)) * CFrame.Angles(rad(45), a, rad(45)), Color = egg.Spots, Material = Enum.Material.Glass, Reflectance = 0.3, Parent = m })
	end
	particles(top, { Color = accent, Size = 0.3, Rate = 4, Lifetime = NumberRange.new(1, 2), Speed = NumberRange.new(1.5, 3), Direction = Enum.NormalId.Right, LightEmission = 0.5 })

	-- the big egg floating on top
	local eggModel = Shared.BuildEgg(eggId)
	eggModel.Name = "Egg"
	eggModel:PivotTo(CFrame.new(pos + Vector3.new(0, 8.2, 0)))
	eggModel.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	eggModel.Parent = m
	spin(eggModel, 0.6, 0.5)
	light(eggModel.PrimaryPart :: Instance, accent, 14, 0.7)
	local price = if egg.Price then "💰 " .. Format(egg.Price) else ""
	fancySign(top, "🥚", string.upper(egg.Name), price .. "  •  Step in the circle", accent, 12, 9.5)
	eggMachines[eggId] = pos
	return m
end

-- Where each egg machine goes: zone 1 eggs at the spawn, the others at their zone's entrance
local function eggMachineSpots(zoneIndex: number): { [number]: Vector3 }
	local spots = {}
	local k = 0
	for eggIndex, egg in ipairs(Shared.Eggs) do
		if egg.Zone == zoneIndex then
			k += 1
			if zoneIndex == 1 then
				spots[eggIndex] = Vector3.new(30 + (k - 1) * 18, 0, -34)
			else
				spots[eggIndex] = Vector3.new(26 + (k - 1) * 18, 0, Shared.ZoneStart(zoneIndex) - 18)
			end
		end
	end
	return spots
end

--------------------------------------------------------------------------------
-- SKY OBBIES (one floats above the spawn, and every dimension has its own)
--------------------------------------------------------------------------------
type ObbyCheckpoint = { Part: BasePart, Spawn: CFrame }
type ObbyCourse = {
	Model: Model,
	Start: CFrame,
	Checkpoints: { ObbyCheckpoint },
	Lava: { BasePart },
	Finish: BasePart?,
	FallY: number, -- below this you fell off
	Circle: Vector3, -- step in this circle on the ground to start
	Dimension: number?, -- nil = the obby at the spawn
}
local obbyCourses: { ObbyCourse } = {}
local startObby -- defined later

-- Builds a whole obby course floating above origin (the ground in the middle below it)
local function buildObby(origin: Vector3, circle: Vector3, dimension: number?, parent: Instance): ObbyCourse
	local f = model(if dimension then "DimensionObby" else "SkyObby", parent)
	local course: ObbyCourse = {
		Model = f,
		Start = CFrame.new(),
		Checkpoints = {},
		Lava = {},
		Finish = nil,
		FallY = origin.Y + 100,
		Circle = circle,
		Dimension = dimension,
	}
	local previous = buildParent
	buildParent = f
	local wood = Color3.fromRGB(140, 104, 72)
	local stone = Color3.fromRGB(128, 124, 118)
	local function at(x: number, y: number, z: number): Vector3
		return origin + Vector3.new(x, y, z)
	end

	local function block(pos: Vector3, size: Vector3, material: Enum.Material?, color: Color3?, name: string?, yaw: number?)
		return P({
			Name = name or "Platform",
			Size = size,
			CFrame = CFrame.new(pos) * CFrame.Angles(0, yaw or 0, 0),
			Material = material or Enum.Material.WoodPlanks,
			Color = color or wood,
		})
	end
	local function checkpoint(pos: Vector3, facing: Vector3)
		local base = block(pos, Vector3.new(12, 2, 12), Enum.Material.Cobblestone, stone, "Checkpoint")
		rod(pos + Vector3.new(4.5, 1, 4.5), pos + Vector3.new(4.5, 9, 4.5), 0.3, { Name = "FlagPole", Color = Color3.fromRGB(60, 60, 65), Material = Enum.Material.Metal })
		P({
			Name = "Flag",
			Size = Vector3.new(0.15, 1.8, 2.6),
			CFrame = CFrame.new(pos + Vector3.new(4.5, 8.1, 5.9)),
			Color = Color3.fromRGB(200, 60, 55),
			Material = Enum.Material.Fabric,
			CanCollide = false,
		})
		local spawnPos = pos + Vector3.new(0, 4, 0)
		table.insert(course.Checkpoints, { Part = base, Spawn = CFrame.lookAt(spawnPos, spawnPos + facing) })
	end

	-- Start
	local startPos = at(20, 110, 40)
	local startPart = block(startPos, Vector3.new(14, 2, 14), Enum.Material.Cobblestone, stone, "Start")
	course.Start = CFrame.lookAt(startPos + Vector3.new(0, 4, 0), startPos + Vector3.new(-10, 4, 0))
	if dimension then
		sign(startPart, "🏃 DIMENSION " .. dimension .. " OBBY", "Pays more than the spawn obby!", Color3.fromRGB(255, 220, 140), 22, 6, 9)
	else
		sign(startPart, "🏃 SKY OBBY", "Reach the trophy for a big reward!", Color3.fromRGB(255, 220, 140), 22, 6, 9)
	end

	-- Stage 1: stepping stones
	for k, x in ipairs({ 8, -2, -12, -22 }) do
		block(at(x, 110.5 + k * 0.6, 40 + rng:NextNumber(-1.5, 1.5)), Vector3.new(5, 1, 5), Enum.Material.Slate, Color3.fromRGB(112, 110, 106), "Stone", rng:NextNumber(0, 1))
	end
	checkpoint(at(-36, 112, 40), Vector3.new(0, 0, -1))

	-- Stage 2: a long walkway with hot lava strips to jump over
	block(at(-36, 112.5, 16), Vector3.new(6, 1, 34))
	for _, z in ipairs({ 26, 17, 8 }) do
		local lava = P({
			Name = "Lava",
			Size = Vector3.new(6.2, 0.5, 3),
			CFrame = CFrame.new(at(-36, 113.2, z)),
			Color = Color3.fromRGB(230, 92, 30),
			Material = Enum.Material.CrackedLava,
		})
		light(lava, Color3.fromRGB(255, 120, 40), 10, 1)
		table.insert(course.Lava, lava)
	end
	block(at(-36, 112.5, -4), Vector3.new(8, 1, 8))

	-- Stage 3: climb the truss
	local truss = Instance.new("TrussPart")
	truss.Name = "Truss"
	truss.Anchored = true
	truss.Size = Vector3.new(2, 16, 2)
	truss.CFrame = CFrame.new(at(-36, 121, -9))
	truss.Color = Color3.fromRGB(70, 70, 76)
	truss.Material = Enum.Material.Metal
	truss.Parent = f
	checkpoint(at(-36, 128, -16), Vector3.new(1, 0, 0))

	-- Stage 4: narrow beams
	block(at(-21, 128.5, -16), Vector3.new(18, 1, 1.4), Enum.Material.Wood, Color3.fromRGB(120, 88, 60), "Beam")
	block(at(-9, 128.5, -16), Vector3.new(5, 1, 5))
	local a, b = at(-6.5, 128.5, -17.5), at(6.5, 128.5, -22.5)
	P({
		Name = "Beam",
		Size = Vector3.new(1.4, 1, (b - a).Magnitude + 1),
		CFrame = CFrame.lookAt((a + b) / 2, b),
		Color = Color3.fromRGB(120, 88, 60),
		Material = Enum.Material.Wood,
	})
	block(at(9, 128.5, -24), Vector3.new(5, 1, 5))

	-- Stage 5: shrinking pillars
	for k, info in ipairs({ { 16, 3.6 }, { 23, 3 }, { 30, 2.6 } }) do
		local topY = 129 + k * 0.5
		block(at(info[1], topY - 15, -24), Vector3.new(info[2], 30, info[2]), Enum.Material.Cobblestone, stone, "Pillar")
	end
	checkpoint(at(40, 130, -24), Vector3.new(0, 0, 1))

	-- Stage 6: floating steps up to the finish
	for k = 0, 3 do
		block(at(40, 132.5 + k * 2, -12 + k * 8), Vector3.new(4, 1, 4), Enum.Material.Slate, Color3.fromRGB(112, 110, 106), "Step")
	end
	local finishPos = at(40, 139, 24)
	block(finishPos, Vector3.new(14, 2, 14), Enum.Material.Marble, Color3.fromRGB(225, 220, 210), "FinishPlatform")
	local finish = P({
		Name = "FinishPad",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 9, 9),
		CFrame = CFrame.new(finishPos + Vector3.new(0, 1.2, 0)) * CFrame.Angles(0, 0, rad(90)),
		Color = Color3.fromRGB(210, 170, 70),
		Material = Enum.Material.Metal,
		Reflectance = 0.25,
	})
	course.Finish = finish
	-- a golden trophy
	local gold = Color3.fromRGB(220, 175, 60)
	local trophyBase = finishPos + Vector3.new(0, 2, 5)
	P({ Name = "TrophyBase", Size = Vector3.new(2, 1, 2), CFrame = CFrame.new(trophyBase + Vector3.new(0, 0.5, 0)), Color = Color3.fromRGB(60, 50, 45), Material = Enum.Material.Wood })
	rod(trophyBase + Vector3.new(0, 1, 0), trophyBase + Vector3.new(0, 2.6, 0), 0.5, { Name = "TrophyStem", Color = gold, Material = Enum.Material.Metal, Reflectance = 0.35 })
	local cup = P({
		Name = "TrophyCup",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 2.4,
		CFrame = CFrame.new(trophyBase + Vector3.new(0, 3.5, 0)),
		Color = gold,
		Material = Enum.Material.Metal,
		Reflectance = 0.35,
		CanCollide = false,
	})
	spin(cup, 0.8, 0.3)
	sign(finish, "🏆 FINISH", nil, Color3.fromRGB(255, 220, 120), 12, 3.5, 7)

	-- clouds drifting around the course
	for _ = 1, if dimension then 6 else 10 do
		Decor.Cloud(at(rng:NextNumber(-70, 70), rng:NextNumber(96, 120), rng:NextNumber(-45, 50)), rng:NextNumber(1.2, 2.2))
	end
	buildParent = previous
	table.insert(obbyCourses, course)
	return course
end

local function removeObby(course: ObbyCourse)
	local k = table.find(obbyCourses, course)
	if k then
		table.remove(obbyCourses, k)
	end
	course.Model:Destroy()
end

--------------------------------------------------------------------------------
-- SHOP CIRCLES: a round stone floor, a glowing circle and the item floating above it
--------------------------------------------------------------------------------
local function buildShopCircle(pos: Vector3, radius: number, color: Color3, action: string, arg: any?, display: Model?, icon: string, title: string, subtitle: string, parent: Instance?): Model
	local m = model("Shop_" .. action, parent)
	m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	P({
		Name = "Floor",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, radius * 2 + 0.8, radius * 2 + 0.8),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, rad(90)),
		Color = Color3.fromRGB(152, 146, 136),
		Material = Enum.Material.Pavement,
		Parent = m,
	})
	actionCircle(pos, radius, color, action, arg, m)
	local anchor = P({ Name = "SignAnchor", Size = Vector3.one, CFrame = CFrame.new(pos + Vector3.new(0, 5, 0)), Transparency = 1, CanCollide = false, Parent = m })
	if display then
		display:PivotTo(CFrame.new(pos + Vector3.new(0, 4.2, 0)) * CFrame.Angles(0, 0, rad(-18)))
		display.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		display.Parent = m
		spin(display, 0.9, 0.45)
	end
	light(anchor, color, 14, 0.6)
	fancySign(anchor, icon, title, subtitle, color, 11, 3.6)
	return m
end

-- A stone ring with a magic swirl. Step in the circle to pick a dimension.
local function buildPortal(pos: Vector3, parent: Instance)
	local portal = model("DimensionPortal", parent)
	P({
		Name = "Platform",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.8, 17, 17),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, 0, rad(90)),
		Color = Color3.fromRGB(96, 92, 100),
		Material = Enum.Material.Slate,
		Parent = portal,
	})
	local ringCenter = pos + Vector3.new(0, 8.5, 0)
	for k = 0, 19 do
		local a = k / 20 * math.pi * 2
		P({
			Name = "Ring",
			Size = Vector3.new(2.8, 1.6, 1.8),
			CFrame = CFrame.new(ringCenter + Vector3.new(math.cos(a) * 7, math.sin(a) * 7, 0)) * CFrame.Angles(0, 0, a + math.pi / 2),
			Color = if k % 5 == 0 then Color3.fromRGB(140, 90, 210) else Color3.fromRGB(105, 100, 108),
			Material = if k % 5 == 0 then Enum.Material.Glass else Enum.Material.Slate,
			Parent = portal,
		})
	end
	local swirl = P({
		Name = "Swirl",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 13, 13),
		CFrame = CFrame.new(ringCenter) * CFrame.Angles(0, rad(90), 0),
		Color = Color3.fromRGB(150, 110, 255),
		Material = Enum.Material.ForceField,
		CanCollide = false,
		Parent = portal,
	})
	light(swirl, Color3.fromRGB(160, 120, 255), 24, 1.2)
	particles(swirl, {
		Color = Color3.fromRGB(190, 160, 255),
		Size = 0.35,
		Rate = 15,
		Lifetime = NumberRange.new(1, 2),
		Speed = NumberRange.new(2, 4),
		Direction = Enum.NormalId.Right,
		Spread = Vector2.new(60, 60),
	})
	actionCircle(pos, 8, Color3.fromRGB(160, 120, 255), "Dimensions", nil, portal)
	fancySign(swirl, "🌌", "DIMENSIONS", "Step in to pick one!", Color3.fromRGB(175, 140, 255), 12, 10)
	return portal
end

-- The circle on the ground that starts an obby (the course itself floats high above)
local function buildObbyEntrance(pos: Vector3, title: string, dimension: number?, parent: Instance)
	local obby = model("ObbyEntrance", parent)
	P({
		Name = "Floor",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 13, 13),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, rad(90)),
		Color = Color3.fromRGB(152, 146, 136),
		Material = Enum.Material.Pavement,
		Parent = obby,
	})
	actionCircle(pos, 6, Color3.fromRGB(235, 95, 85), "Obby", dimension, obby)
	local post = P({
		Name = "SignPost",
		Size = Vector3.new(0.5, 7, 0.5),
		CFrame = CFrame.new(pos + Vector3.new(0, 3.5, -7)),
		Color = Color3.fromRGB(95, 70, 50),
		Material = Enum.Material.Wood,
		Parent = obby,
	})
	-- every player's screen writes their own reward on this sign
	local board = fancySign(post, "🏃", title, "Win 💰 coins!", Color3.fromRGB(240, 120, 100), 11, 5)
	board.Name = "ObbySign"
	board:AddTag("ObbySign")
	if dimension then
		board:SetAttribute("Dimension", dimension)
	end
	return obby
end

--------------------------------------------------------------------------------
-- FUN EXTRAS: 🎡 lucky wheel, 🦘 bounce pads, 🎁 treasure chests, 🌠 meteors
-- (their code is spread over the script; everything is kept in this table)
--------------------------------------------------------------------------------
local Fun: { [string]: any } = {}
Fun.ChestFolder = folder("Chests")
Fun.Chests = {} -- [chest model] = chest

-- A trampoline. Every player's computer makes it bounce them up high.
function Fun.BouncePad(pos: Vector3, parent: Instance?): Model
	local m = model("BouncePad", parent)
	local upright = CFrame.Angles(0, 0, rad(90))
	local metal = Color3.fromRGB(70, 75, 90)
	for k = 0, 5 do
		local a = k / 6 * math.pi * 2
		P({ Name = "Leg", Size = Vector3.new(0.45, 1.9, 0.45), CFrame = CFrame.new(pos + Vector3.new(math.cos(a) * 3.3, 0.95, math.sin(a) * 3.3)), Color = metal, Material = Enum.Material.Metal, Parent = m })
	end
	P({ Name = "Frame", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 7.8, 7.8), CFrame = CFrame.new(pos + Vector3.new(0, 1.9, 0)) * upright, Color = Color3.fromRGB(40, 140, 230), Parent = m })
	for k = 0, 11 do
		local a = (k + 0.5) / 12 * math.pi * 2
		P({ Name = "Spring", Size = Vector3.new(0.2, 0.2, 0.9), CFrame = CFrame.new(pos + Vector3.new(math.cos(a) * 3.45, 2.2, math.sin(a) * 3.45)) * CFrame.Angles(0, -a, 0), Color = Color3.fromRGB(200, 205, 215), Material = Enum.Material.Metal, Parent = m })
	end
	local mat = P({ Name = "Mat", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 6.4, 6.4), CFrame = CFrame.new(pos + Vector3.new(0, 2.05, 0)) * upright, Color = Color3.fromRGB(30, 32, 42), Material = Enum.Material.Fabric, Parent = m })
	mat:SetAttribute("Power", Settings.BouncePower)
	mat:AddTag("BouncePad")
	sign(mat, "🦘 BOUNCE!", nil, Color3.fromRGB(130, 215, 255), 7, 1.8, 3.5)
	return m
end

-- The 🎡 Lucky Wheel: step in its circle and spin it for a prize
function Fun.LuckyWheel(pos: Vector3, parent: Instance): Model
	local m = model("LuckyWheel", parent)
	m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local gold = Color3.fromRGB(230, 185, 70)
	local wood = Color3.fromRGB(110, 78, 52)
	P({ Name = "Floor", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 13, 13), CFrame = CFrame.new(pos + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, rad(90)), Color = Color3.fromRGB(152, 146, 136), Material = Enum.Material.Pavement, Parent = m })
	actionCircle(pos, 6, Color3.fromRGB(255, 200, 80), "Wheel", nil, m)
	local center = pos + Vector3.new(-9, 8, 0)
	P({ Name = "Base", Size = Vector3.new(3, 1, 9), CFrame = CFrame.new(pos + Vector3.new(-9.6, 0.5, 0)), Color = Color3.fromRGB(120, 116, 110), Material = Enum.Material.Cobblestone, Parent = m })
	for _, side in ipairs({ -1, 1 }) do
		rod(pos + Vector3.new(-9.6, 1, side * 3.6), center + Vector3.new(-0.7, 0, side * 0.5), 0.55, { Name = "Stand", Color = wood, Material = Enum.Material.Wood, Parent = m })
	end
	local wheel = model("Wheel", m)
	local disc = P({ Name = "Disc", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 11.6, 11.6), CFrame = CFrame.new(center), Color = Color3.fromRGB(245, 240, 230), Parent = wheel })
	wheel.PrimaryPart = disc
	P({ Name = "Rim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 12.4, 12.4), CFrame = CFrame.new(center - Vector3.new(0.1, 0, 0)), Color = gold, Material = Enum.Material.Metal, Parent = wheel })
	for k, prize in ipairs(Shared.WheelPrizes) do
		local a = (k - 1) / #Shared.WheelPrizes * math.pi * 2
		P({ Name = "Slice", Size = Vector3.new(0.7, 4.7, 2.2), CFrame = CFrame.new(center) * CFrame.Angles(a, 0, 0) * CFrame.new(0.05, 3, 0), Color = prize.Color, Parent = wheel })
		P({ Name = "Peg", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 0.45, 0.45), CFrame = CFrame.new(center) * CFrame.Angles(a + math.pi / #Shared.WheelPrizes, 0, 0) * CFrame.new(0.3, 5.5, 0), Color = gold, Material = Enum.Material.Metal, Parent = wheel })
	end
	P({ Name = "Hub", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.1, 2.2, 2.2), CFrame = CFrame.new(center + Vector3.new(0.2, 0, 0)), Color = gold, Material = Enum.Material.Metal, Reflectance = 0.2, Parent = wheel })
	P({ Name = "Pointer", Size = Vector3.new(0.6, 1.6, 0.9), CFrame = CFrame.new(center + Vector3.new(0.5, 6.6, 0)), Color = Color3.fromRGB(225, 60, 60), Parent = m })
	local anchor = P({ Name = "SignAnchor", Size = Vector3.one, CFrame = CFrame.new(center + Vector3.new(0, 7, 0)), Transparency = 1, CanCollide = false, Parent = m })
	light(anchor, Color3.fromRGB(255, 210, 120), 16, 0.7)
	fancySign(anchor, "🎡", "LUCKY WHEEL", "A free spin every " .. math.floor(Settings.WheelCooldown / 60) .. " minutes!", Color3.fromRGB(255, 200, 80), 11, 3)
	return m
end

--------------------------------------------------------------------------------
-- LEADERBOARDS (big boards behind the spawn with the best players of ALL servers, worldwide)
--------------------------------------------------------------------------------
type BoardRow = { PlayerName: TextLabel, Score: TextLabel }
type LeaderboardInfo = { Stat: string, Icon: string, Title: string, Color: Color3, Fastest: boolean? }
type Leaderboard = { Info: LeaderboardInfo, Rows: { BoardRow } }
local leaderboards: { Leaderboard } = {}
-- Fastest = smaller is better (obby times)
local LEADERBOARD_STATS: { LeaderboardInfo } = {
	{ Stat = "Level", Icon = "🌍", Title = "TOP PLAYERS", Color = Color3.fromRGB(255, 215, 90) },
	{ Stat = "TotalGems", Icon = "💎", Title = "MOST GEMS MINED", Color = Color3.fromRGB(120, 220, 255) },
	{ Stat = "Rebirths", Icon = "♻️", Title = "MOST REBIRTHS", Color = Color3.fromRGB(205, 145, 255) },
	{ Stat = "ObbyBest", Icon = "🏃", Title = "FASTEST OBBY", Color = Color3.fromRGB(255, 150, 120), Fastest = true },
}

-- The number a player has on a board (nil = not on it). Obby times are saved in tenths of a second.
local function boardValue(info: LeaderboardInfo, data): number?
	local value = tonumber(data[info.Stat])
	if not value then
		return nil
	end
	if info.Fastest then
		return if value > 0 then math.floor(value * 10 + 0.5) else nil
	end
	return math.floor(value)
end

local function boardText(info: LeaderboardInfo, value: number): string
	if info.Fastest then
		return string.format("%.1fs", value / 10)
	elseif info.Stat == "Level" then
		return "⭐ " .. Format(value)
	end
	return Format(value)
end

-- One board on two stone posts. It faces -Z (towards the spawn).
local function buildLeaderboard(pos: Vector3, info: LeaderboardInfo, parent: Instance)
	local m = model("Leaderboard_" .. info.Stat, parent)
	local stone = Color3.fromRGB(124, 120, 114)
	local wood = Color3.fromRGB(96, 68, 46)
	P({ Name = "Base", Size = Vector3.new(14.5, 0.6, 3.4), CFrame = CFrame.new(pos + Vector3.new(0, 0.3, 0.4)), Color = stone, Material = Enum.Material.Cobblestone, Parent = m })
	for _, side in ipairs({ -1, 1 }) do
		P({ Name = "Post", Size = Vector3.new(1.3, 15, 1.3), CFrame = CFrame.new(pos + Vector3.new(side * 6.4, 7.8, 0.4)), Color = stone, Material = Enum.Material.Cobblestone, Parent = m })
		P({ Name = "PostCap", Size = Vector3.new(1.8, 0.6, 1.8), CFrame = CFrame.new(pos + Vector3.new(side * 6.4, 15.6, 0.4)), Color = stone:Lerp(Color3.new(1, 1, 1), 0.15), Material = Enum.Material.Slate, Parent = m })
	end
	local board = P({ Name = "Board", Size = Vector3.new(11.2, 13, 0.4), CFrame = CFrame.new(pos + Vector3.new(0, 8.6, 0)), Color = Color3.fromRGB(32, 34, 48), Parent = m })
	P({ Name = "Frame", Size = Vector3.new(11.8, 13.6, 0.4), CFrame = CFrame.new(pos + Vector3.new(0, 8.6, 0.35)), Color = wood, Material = Enum.Material.Wood, Parent = m })
	P({ Name = "Roof", Size = Vector3.new(14.6, 0.7, 2.8), CFrame = CFrame.new(pos + Vector3.new(0, 16.2, 0.4)), Color = wood, Material = Enum.Material.WoodPlanks, Parent = m })
	local lamp = P({ Name = "Lamp", Size = Vector3.new(8, 0.3, 0.5), CFrame = CFrame.new(pos + Vector3.new(0, 15.6, -0.6)), Color = Color3.fromRGB(255, 236, 190), Material = Enum.Material.Neon, CanCollide = false, Parent = m })
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Bottom
	spot.Angle = 70
	spot.Range = 16
	spot.Brightness = 1.2
	spot.Color = Color3.fromRGB(255, 236, 200)
	spot.Parent = lamp

	local gui = Instance.new("SurfaceGui")
	gui.Name = "Board"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.MaxDistance = 220
	local function text(name: string, value: string, x: number, y: number, w: number, h: number, color: Color3, align: Enum.TextXAlignment, frameParent: Instance): TextLabel
		local lbl = Instance.new("TextLabel")
		lbl.Name = name
		lbl.BackgroundTransparency = 1
		lbl.Position = UDim2.fromScale(x, y)
		lbl.Size = UDim2.fromScale(w, h)
		lbl.Font = Enum.Font.FredokaOne
		lbl.TextScaled = true
		lbl.TextXAlignment = align
		lbl.TextColor3 = color
		lbl.Text = value
		lbl.Parent = frameParent
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Color = Color3.fromRGB(12, 12, 20)
		stroke.Parent = lbl
		return lbl
	end
	text("Title", info.Icon .. " " .. info.Title, 0.04, 0.015, 0.92, 0.11, info.Color, Enum.TextXAlignment.Center, gui)
	local rows: { BoardRow } = {}
	local medals = { Color3.fromRGB(255, 210, 80), Color3.fromRGB(215, 222, 235), Color3.fromRGB(225, 150, 95) }
	for k = 1, 10 do
		local row = Instance.new("Frame")
		row.Name = "Row" .. k
		row.Position = UDim2.fromScale(0.04, 0.14 + (k - 1) * 0.085)
		row.Size = UDim2.fromScale(0.92, 0.075)
		row.BackgroundColor3 = if k % 2 == 1 then Color3.fromRGB(52, 56, 78) else Color3.fromRGB(42, 45, 64)
		row.BorderSizePixel = 0
		row.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.3, 0)
		corner.Parent = row
		local color = medals[k] or Color3.fromRGB(235, 238, 248)
		text("Rank", "#" .. k, 0.02, 0.1, 0.14, 0.8, color, Enum.TextXAlignment.Left, row)
		local nameLabel = text("PlayerName", "---", 0.17, 0.1, 0.5, 0.8, color, Enum.TextXAlignment.Left, row)
		local scoreLabel = text("Score", "", 0.67, 0.1, 0.31, 0.8, info.Color, Enum.TextXAlignment.Right, row)
		table.insert(rows, { PlayerName = nameLabel, Score = scoreLabel })
	end
	gui.Parent = board
	table.insert(leaderboards, { Info = info, Rows = rows })
	return m
end

--------------------------------------------------------------------------------
-- THE HUB (spawn area)
--------------------------------------------------------------------------------
-- Where everything at the spawn is
local HUB = {
	Sell = Vector3.new(-24, 0, 4),
	Pickaxes = Vector3.new(24, 0, 14),
	Backpacks = Vector3.new(24, 0, -10),
	Pets = Vector3.new(42, 0, 2),
	Gadgets = Vector3.new(-42, 0, -12),
	Rebirth = Vector3.new(-36, 0, -36),
	Portal = Vector3.new(-36, 0, 32),
	Obby = Vector3.new(34, 0, 32),
	Wheel = Vector3.new(-46, 0, 10),
}

local function buildHub()
	local hub = model("Hub")
	local stone = Color3.fromRGB(132, 128, 122)

	-- Spawn: a round stone platform
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(0, 0.5, 32)
	spawn.Color = stone
	spawn.Material = Enum.Material.Slate
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Parent = hub
	P({
		Name = "SpawnPlatform",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, 16, 16),
		CFrame = CFrame.new(0, 0.3, 32) * CFrame.Angles(0, 0, rad(90)),
		Color = stone,
		Material = Enum.Material.Slate,
		Parent = hub,
	})

	-- Fountain with a crystal statue on top
	local marble = Color3.fromRGB(205, 202, 196)
	for k = 0, 17 do
		local a = k / 18 * math.pi * 2
		P({
			Name = "BasinWall",
			Size = Vector3.new(3.4, 2.2, 1.2),
			CFrame = CFrame.new(math.cos(a) * 9.4, 1.1, 2 + math.sin(a) * 9.4) * CFrame.Angles(0, -a + math.pi / 2, 0),
			Color = marble,
			Material = Enum.Material.Marble,
			Parent = hub,
		})
		P({
			Name = "BasinTop",
			Size = Vector3.new(3.5, 0.3, 1.5),
			CFrame = CFrame.new(math.cos(a) * 9.4, 2.35, 2 + math.sin(a) * 9.4) * CFrame.Angles(0, -a + math.pi / 2, 0),
			Color = marble:Lerp(Color3.new(1, 1, 1), 0.2),
			Material = Enum.Material.Marble,
			Parent = hub,
		})
	end
	P({
		Name = "Water",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.6, 18, 18),
		CFrame = CFrame.new(0, 0.9, 2) * CFrame.Angles(0, 0, rad(90)),
		Color = Color3.fromRGB(40, 95, 110),
		Material = Enum.Material.Glass,
		Transparency = 0.25,
		Reflectance = 0.25,
		CanCollide = false,
		Parent = hub,
	})
	rod(Vector3.new(0, 0, 2), Vector3.new(0, 6, 2), 2.4, { Name = "Pillar", Color = marble, Material = Enum.Material.Marble, Parent = hub })
	local bowl = P({
		Name = "Bowl",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, 7, 7),
		CFrame = CFrame.new(0, 6.3, 2) * CFrame.Angles(0, 0, rad(90)),
		Color = marble,
		Material = Enum.Material.Marble,
		Parent = hub,
	})
	particles(bowl, {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = Color3.fromRGB(200, 225, 235),
		Size = 0.35,
		Rate = 60,
		Lifetime = NumberRange.new(0.8, 1.1),
		Speed = NumberRange.new(7, 9),
		Spread = Vector2.new(14, 14),
		Direction = Enum.NormalId.Right,
		Acceleration = Vector3.new(0, -25, 0),
		LightEmission = 0.1,
		Transparency = 0.35,
	})
	local previous = buildParent
	buildParent = hub
	Decor.Spire(Vector3.new(0, 6.6, 2), 1.15, Color3.fromRGB(80, 170, 200))
	buildParent = previous
	-- a stone plate with the name of the game, facing the spawn
	local plaque = P({
		Name = "Plaque",
		Size = Vector3.new(12, 2.8, 0.4),
		CFrame = CFrame.new(0, 1.5, 12.15),
		Color = Color3.fromRGB(70, 66, 64),
		Material = Enum.Material.Slate,
		Parent = hub,
	})
	carvedText(plaque, Enum.NormalId.Back, "💎 CRYSTAL RUSH 💎", "Mine  •  Sell  •  Upgrade", Color3.fromRGB(255, 215, 120))
	for k = 0, 3 do
		local a = k / 4 * math.pi * 2 + math.pi / 4
		Decor.Bench(Vector3.new(math.cos(a) * 15, 0, 2 + math.sin(a) * 15), -a - math.pi / 2)
	end

	-- Selling, shops, rebirth, the portal and the obby: all circles you step into
	buildSellPad(HUB.Sell, 14, 1)
	buildShopCircle(HUB.Pickaxes, 6.5, Color3.fromRGB(225, 165, 70), "Pickaxes", nil, Shared.BuildPickaxe(5), "⛏️", "PICKAXES", "Mine faster", hub)
	buildShopCircle(HUB.Backpacks, 6.5, Color3.fromRGB(80, 150, 235), "Backpacks", nil, Shared.BuildBackpack(5), "🎒", "BACKPACKS", "Carry more gems", hub)
	local puppy = Shared.BuildPet(1)
	puppy:ScaleTo(1.5)
	buildShopCircle(HUB.Pets, 6.5, Color3.fromRGB(240, 130, 190), "Pets", nil, puppy, "🐾", "PET SHOP", "Pets give more gems", hub)
	local coil = Shared.BuildGadget(5)
	coil:ScaleTo(1.4)
	buildShopCircle(HUB.Gadgets, 6.5, Color3.fromRGB(165, 110, 240), "Gadgets", nil, coil, "⚡", "GADGETS", "Run faster, jump higher", hub)
	do
		local gem = model("RebirthGem")
		local crystal = P({
			Name = "Gem",
			Size = Vector3.new(2.2, 3.4, 2.2),
			CFrame = CFrame.new(0, 0, 0) * CFrame.Angles(rad(45), 0, rad(45)),
			Color = Color3.fromRGB(130, 70, 190),
			Material = Enum.Material.Glass,
			Reflectance = 0.25,
			CanCollide = false,
			Parent = gem,
		})
		gem.PrimaryPart = crystal
		light(crystal, Color3.fromRGB(170, 110, 230), 14, 0.8)
		buildShopCircle(HUB.Rebirth, 6.5, Color3.fromRGB(185, 115, 235), "Rebirth", nil, gem, "♻️", "REBIRTH", "Start over, earn MORE coins", hub)
	end
	buildPortal(HUB.Portal, hub)
	buildObbyEntrance(HUB.Obby, "SKY OBBY", nil, hub)
	Fun.LuckyWheel(HUB.Wheel, hub)

	-- Eggs at the spawn
	local busy = {
		{ Vector3.new(0, 0, 2), 24 }, -- fountain square
		{ Vector3.new(0, 0, 32), 11 }, -- spawn
		{ Vector3.new(60, 0, 38), 15 }, -- pond
	}
	-- Bounce pads to play on
	for _, pos in ipairs({ Vector3.new(-14, 0, -28), Vector3.new(14, 0, -28) }) do
		Fun.BouncePad(pos, hub)
		table.insert(busy, { pos, 6 })
	end
	-- Leaderboards behind the spawn, with a big sign above them
	for k, info in ipairs(LEADERBOARD_STATS) do
		local pos = Vector3.new((k - (#LEADERBOARD_STATS + 1) / 2) * 17, 0, 51)
		buildLeaderboard(pos, info, hub)
		table.insert(busy, { pos, 9 })
	end
	local boardSign = P({ Name = "LeaderboardSign", Size = Vector3.one, CFrame = CFrame.new(0, 19.5, 51), Transparency = 1, CanCollide = false, Parent = hub })
	sign(boardSign, "🌍 WORLDWIDE LEADERBOARDS", "The best players of every server", Color3.fromRGB(255, 220, 120), 34, 6, 0)
	for _, pos in pairs(HUB) do
		table.insert(busy, { pos, 11 })
	end
	for eggIndex, pos in pairs(eggMachineSpots(1)) do
		buildEggMachine(eggIndex, pos)
		table.insert(busy, { pos, 11 })
	end

	-- Lamps along the path, flower boxes around the fountain
	for _, z in ipairs({ 44, 22, -18, -44 }) do
		Decor.Lamp(Vector3.new(-6.5, 0, z))
		Decor.Lamp(Vector3.new(6.5, 0, z))
	end
	for _, pos in ipairs({ Vector3.new(-12, 0, 38), Vector3.new(12, 0, 38), Vector3.new(-12, 0, 25), Vector3.new(12, 0, 25) }) do
		do
			P({ Name = "Planter", Size = Vector3.new(4, 1.4, 4), CFrame = CFrame.new(pos + Vector3.new(0, 0.7, 0)), Color = Color3.fromRGB(140, 134, 126), Material = Enum.Material.Cobblestone, Parent = hub })
			P({ Name = "Soil", Size = Vector3.new(3.4, 0.2, 3.4), CFrame = CFrame.new(pos + Vector3.new(0, 1.42, 0)), Color = Color3.fromRGB(80, 60, 45), Material = Enum.Material.Ground, Parent = hub })
			Decor.Flowers(pos + Vector3.new(0, 1.4, 0))
		end
	end

	local function hubSpot(minX: number, maxX: number, radius: number): Vector3?
		for _ = 1, 20 do
			local side = if rng:NextNumber() < 0.5 then -1 else 1
			local pos = Vector3.new(side * rng:NextNumber(minX, maxX), 0, rng:NextNumber(-48, 50))
			local free = math.abs(pos.X) > 8 + radius
			for _, spot in ipairs(busy) do
				if (pos - spot[1]).Magnitude < spot[2] + radius then
					free = false
				end
			end
			if free then
				return pos
			end
		end
		return nil
	end
	for _ = 1, 16 do
		local pos = hubSpot(54, 76, 4)
		if pos then
			Decor.Tree(pos, rng:NextNumber(0.9, 1.3))
		end
	end
	for _ = 1, 12 do
		local pos = hubSpot(14, 62, 2)
		if pos then
			Decor.Flowers(pos)
		end
	end
	for _ = 1, 10 do
		local pos = hubSpot(16, 56, 3)
		if pos then
			Decor.Bush(pos, rng:NextNumber(0.8, 1.2))
		end
	end
	Decor.Fence(Vector3.new(46, 0, 27), Vector3.new(74, 0, 27))
	Decor.Fence(Vector3.new(46, 0, 49), Vector3.new(74, 0, 49))

	-- Entrance arch to the first zone
	buildArch(Layout.HubBack, Shared.Zones[1], hub, Shared.Zones[1].Emoji .. " " .. string.upper(Shared.Zones[1].Name), "Click crystals to mine them!")
end

--------------------------------------------------------------------------------
-- GATES (locked zone entrances)
--------------------------------------------------------------------------------
local unlockZone -- defined later
local buildBossArena -- defined later

local function buildGate(i: number)
	local zone = Shared.Zones[i]
	local z = Shared.ZoneStart(i)
	local gate = model("Gate" .. i, GateFolder)
	gate:SetAttribute("Zone", i)
	gate.ModelStreamingMode = Enum.ModelStreamingMode.Persistent

	buildArch(z, zone, gate, "🔒 " .. string.upper(zone.Name), "💰 " .. Format(zone.Price) .. " to unlock")

	-- iron bars in the arch (they disappear for you once you unlock the zone)
	local bars = model("Bars", gate)
	local iron = Color3.fromRGB(46, 46, 50)
	for x = -18, 18, 3 do
		rod(Vector3.new(x, 0, z), Vector3.new(x, 36, z), 0.55, { Name = "Bar", Color = iron, Material = Enum.Material.Metal, CanCollide = false, Parent = bars })
	end
	for _, y in ipairs({ 6, 16, 26 }) do
		P({ Name = "Rail", Size = Vector3.new(40, 0.8, 0.8), CFrame = CFrame.new(0, y, z), Color = iron, Material = Enum.Material.Metal, CanCollide = false, Parent = bars })
	end
	-- stone walls from the arch out to the hills (the caves have rock walls already)
	if i ~= 2 then
		local stone = zone.RockColor:Lerp(Color3.fromRGB(150, 145, 138), 0.55)
		for _, side in ipairs({ -1, 1 }) do
			P({
				Name = "Wall",
				Size = Vector3.new(58, 14, 4),
				CFrame = CFrame.new(side * 57, 7, z),
				Color = stone,
				Material = Enum.Material.Cobblestone,
				Parent = gate,
			})
		end
	end
	-- an invisible wall that blocks the way until you unlock the zone
	P({
		Name = "Barrier",
		Size = Vector3.new(Layout.HalfWidth * 2, 60, 2),
		CFrame = CFrame.new(0, 30, z),
		Transparency = 1,
		CastShadow = false,
		Parent = gate,
	})
	local promptPart = P({
		Name = "PromptPart",
		Size = Vector3.new(4, 4, 1),
		CFrame = CFrame.new(0, 3, z + 4),
		Transparency = 1,
		CanCollide = false,
		Parent = gate,
	})
	local pp = prompt(promptPart, "Unlock for 💰 " .. Format(zone.Price), zone.Emoji .. " " .. zone.Name, 0.4)
	pp.MaxActivationDistance = 16
	pp.Triggered:Connect(function(player)
		unlockZone(player, i)
	end)
end

--------------------------------------------------------------------------------
-- ZONES
--------------------------------------------------------------------------------
local function buildZone(i: number)
	local zone = Shared.Zones[i]
	local zs, ze = Shared.ZoneStart(i), Shared.ZoneEnd(i)
	local mid = (zs + ze) / 2
	if i >= 2 then
		buildGate(i)
	end

	-- Sell pad and egg machines near the entrance of every zone
	local padPos = Vector3.new(-26, 0, zs - 16)
	buildSellPad(padPos, 14, i)
	reserve(i, padPos, 14)
	reserve(i, Shared.ZoneSpawn(i), 8)
	if i >= 2 then
		for eggIndex, pos in pairs(eggMachineSpots(i)) do
			buildEggMachine(eggIndex, pos)
			reserve(i, pos, 12)
		end
		-- a shop, so you don't have to walk back to the spawn
		local shopPos = Vector3.new(-46, 0, zs - 18)
		local display = Shared.BuildPickaxe(math.min(i * 2 + 1, #Shared.Pickaxes))
		buildShopCircle(shopPos, 6, zone.Accent, "Shop", nil, display, "🛒", "SHOP", "Pickaxes • Backpacks • Pets", MapFolder)
		reserve(i, shopPos, 10)
	end
	buildBossArena(i)

	local function decorAt(minRadius: number): Vector3?
		local pos = freeSpot(i, minRadius)
		if pos then
			reserve(i, pos, minRadius)
			return onGround(pos)
		end
		return nil
	end

	if i == 1 then -- Sunny Meadow
		for _ = 1, 18 do
			Decor.Tree(onGround(edgeSpot(i)), rng:NextNumber(0.9, 1.4))
		end
		for _ = 1, 4 do
			Decor.Pine(onGround(edgeSpot(i)), rng:NextNumber(0.8, 1.1))
		end
		for _ = 1, 12 do
			Decor.Bush(onGround(edgeSpot(i)), rng:NextNumber(0.8, 1.3))
		end
		for _ = 1, 16 do
			local pos = freeSpot(i, 2)
			if pos then
				Decor.Flowers(onGround(pos))
			end
		end
		for _ = 1, 4 do
			local pos = decorAt(5)
			if pos then
				Decor.Log(pos, rng:NextNumber(0.8, 1.2))
			end
		end
	elseif i == 2 then -- Crystal Caves
		for _ = 1, 14 do
			Decor.Spire(onGround(edgeSpot(i)), rng:NextNumber(0.8, 1.4), zone.CrystalColors[rng:NextInteger(1, #zone.CrystalColors)])
		end
		for _ = 1, 14 do
			Decor.Mushroom(onGround(edgeSpot(i)), rng:NextNumber(0.7, 1.2), Color3.fromRGB(150, 120, 190))
		end
		for _ = 1, 5 do
			local pos = decorAt(5)
			if pos then
				Decor.Mushroom(pos, rng:NextNumber(0.5, 0.8), Color3.fromRGB(110, 170, 190))
			end
		end
		-- stalactites hanging from the ceiling
		for _ = 1, 26 do
			local h = rng:NextNumber(4, 10)
			P({
				Name = "Stalactite",
				Size = Vector3.new(2, h, 2),
				CFrame = CFrame.new(rng:NextNumber(-80, 80), 40 - h / 2 + 1, rng:NextNumber(ze + 8, zs - 8)) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
				Color = zone.RockColor,
				Material = Enum.Material.Slate,
				CanCollide = false,
			})
		end
		local dust = P({
			Name = "CaveDust",
			Size = Vector3.new(160, 1, Layout.ZoneLength - 10),
			CFrame = CFrame.new(0, 20, mid),
			Transparency = 1,
			CanCollide = false,
		})
		particles(dust, {
			Color = Color3.fromRGB(190, 180, 200),
			LightEmission = 0.2,
			Size = 0.15,
			Rate = 20,
			Lifetime = NumberRange.new(4, 7),
			Speed = NumberRange.new(0.1, 0.4),
			Spread = Vector2.new(180, 180),
			Transparency = 0.4,
		})
	elseif i == 3 then -- Lava Volcano
		local volcanoPos = Vector3.new(-62, 40, mid)
		reserve(i, Vector3.new(-62, 0, mid), 34)
		local glow = P({
			Name = "VolcanoGlow",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 9,
			CFrame = CFrame.new(volcanoPos - Vector3.new(0, 4, 0)),
			Color = Color3.fromRGB(230, 95, 25),
			Material = Enum.Material.CrackedLava,
			CanCollide = false,
		})
		light(glow, Color3.fromRGB(255, 120, 40), 60, 2.5)
		particles(glow, {
			Texture = "rbxasset://textures/particles/smoke_main.dds",
			Color = Color3.fromRGB(70, 65, 62),
			LightEmission = 0,
			Size = 8,
			EndSize = 24,
			Rate = 6,
			Lifetime = NumberRange.new(6, 9),
			Speed = NumberRange.new(6, 9),
			Spread = Vector2.new(15, 15),
			Transparency = 0.35,
		})
		particles(glow, {
			Texture = "rbxasset://textures/particles/fire_main.dds",
			Color = Color3.fromRGB(255, 130, 40),
			Size = 4,
			EndSize = 1,
			Rate = 18,
			Lifetime = NumberRange.new(1, 2),
			Speed = NumberRange.new(8, 14),
			Spread = Vector2.new(15, 15),
		})
		for _ = 1, 6 do
			local pos = freeSpot(i, 8)
			if pos and pos.X > -25 then
				local r = rng:NextNumber(4, 7)
				reserve(i, pos, r + 4)
				Decor.LavaPool(onGround(pos), r)
			end
		end
		for _ = 1, 18 do
			Decor.Rock(onGround(edgeSpot(i)), rng:NextNumber(1, 2.2), zone.RockColor, Enum.Material.Basalt)
		end
		for _ = 1, 10 do
			Decor.DeadTree(onGround(edgeSpot(i)), rng:NextNumber(0.9, 1.4))
		end
		local ash = P({
			Name = "Ash",
			Size = Vector3.new(160, 1, Layout.ZoneLength - 10),
			CFrame = CFrame.new(0, 40, mid),
			Transparency = 1,
			CanCollide = false,
		})
		particles(ash, {
			Color = Color3.fromRGB(110, 105, 100),
			LightEmission = 0,
			Size = 0.25,
			EndSize = 0.25,
			Rate = 40,
			Lifetime = NumberRange.new(8, 12),
			Speed = NumberRange.new(3, 5),
			Spread = Vector2.new(25, 25),
			Direction = Enum.NormalId.Bottom,
			Transparency = 0.3,
		})
	elseif i == 4 then -- Frozen Peaks
		for _ = 1, 22 do
			Decor.Pine(onGround(edgeSpot(i)), rng:NextNumber(0.9, 1.5), true)
		end
		for _ = 1, 10 do
			Decor.IceSpike(onGround(edgeSpot(i)), rng:NextNumber(0.8, 1.5))
		end
		for _ = 1, 2 do
			local pos = decorAt(6)
			if pos then
				Decor.Snowman(pos, rng:NextNumber(0, math.pi * 2))
			end
		end
		local snow = P({
			Name = "Snowfall",
			Size = Vector3.new(170, 1, Layout.ZoneLength),
			CFrame = CFrame.new(0, 60, mid),
			Transparency = 1,
			CanCollide = false,
		})
		particles(snow, {
			Color = Color3.fromRGB(255, 255, 255),
			LightEmission = 0.2,
			Size = 0.3,
			EndSize = 0.3,
			Rate = 120,
			Lifetime = NumberRange.new(9, 12),
			Speed = NumberRange.new(5, 7),
			Spread = Vector2.new(15, 15),
			Direction = Enum.NormalId.Bottom,
		})
	elseif i == 5 then -- Galaxy Isles
		Decor.Planet(Vector3.new(-90, 95, mid + 30), 40, Color3.fromRGB(95, 70, 140), Enum.Material.Slate, Color3.fromRGB(180, 150, 200))
		Decor.Planet(Vector3.new(85, 75, mid - 35), 26, Color3.fromRGB(70, 120, 150), Enum.Material.Glacier, nil)
		Decor.Planet(Vector3.new(30, 120, mid + 70), 16, Color3.fromRGB(190, 120, 70), Enum.Material.Sandstone, Color3.fromRGB(220, 200, 160))
		for _ = 1, 12 do
			Decor.FloatingRock(onGround(edgeSpot(i)) + Vector3.new(0, rng:NextNumber(14, 34), 0), rng:NextNumber(0.8, 1.6), zone.CrystalColors[rng:NextInteger(1, 3)])
		end
		for _ = 1, 12 do
			Decor.Spire(onGround(edgeSpot(i)), rng:NextNumber(0.8, 1.3), zone.CrystalColors[rng:NextInteger(1, 3)])
		end
		local stars = P({
			Name = "Stars",
			Size = Vector3.new(180, 1, Layout.ZoneLength),
			CFrame = CFrame.new(0, 45, mid),
			Transparency = 1,
			CanCollide = false,
		})
		particles(stars, {
			Color = Color3.fromRGB(230, 230, 255),
			Size = 0.3,
			Rate = 25,
			Lifetime = NumberRange.new(2, 4),
			Speed = NumberRange.new(0, 0.3),
			Spread = Vector2.new(180, 180),
		})
	elseif i == 6 then -- Mushroom Forest
		local caps = { Color3.fromRGB(200, 60, 70), Color3.fromRGB(190, 80, 200), Color3.fromRGB(60, 170, 170), Color3.fromRGB(235, 150, 60) }
		for _ = 1, 18 do
			Decor.Mushroom(onGround(edgeSpot(i)), rng:NextNumber(1.6, 2.8), caps[rng:NextInteger(1, #caps)])
		end
		for _ = 1, 8 do
			local pos = decorAt(4)
			if pos then
				Decor.Mushroom(pos, rng:NextNumber(0.6, 1), caps[rng:NextInteger(1, #caps)])
			end
		end
		for _ = 1, 6 do
			Decor.Tree(onGround(edgeSpot(i)), rng:NextNumber(1, 1.4))
		end
		-- glowing spores floating around
		local spores = P({ Name = "Spores", Size = Vector3.new(160, 1, Layout.ZoneLength - 10), CFrame = CFrame.new(0, 12, mid), Transparency = 1, CanCollide = false })
		particles(spores, {
			Color = Color3.fromRGB(190, 255, 150),
			Size = 0.25,
			Rate = 35,
			Lifetime = NumberRange.new(5, 8),
			Speed = NumberRange.new(0.2, 0.8),
			Spread = Vector2.new(180, 180),
		})
	elseif i == 7 then -- Ancient Desert
		Decor.Pyramid(Vector3.new(-64, 0, mid + 10), 34)
		reserve(i, Vector3.new(-64, 0, mid + 10), 24)
		Decor.Pyramid(Vector3.new(-60, 0, mid - 55), 22) -- (the boss arena is on the other side)
		reserve(i, Vector3.new(-60, 0, mid - 55), 16)
		for _ = 1, 16 do
			Decor.Cactus(onGround(edgeSpot(i)), rng:NextNumber(0.9, 1.4))
		end
		for _ = 1, 5 do
			local pos = decorAt(8)
			if pos then
				Decor.Ruin(pos, rng:NextNumber(0.8, 1.2))
			end
		end
		for _ = 1, 10 do
			Decor.Rock(onGround(edgeSpot(i)), rng:NextNumber(1, 2), zone.RockColor, Enum.Material.Sandstone)
		end
		-- blowing sand
		local sand = P({ Name = "BlowingSand", Size = Vector3.new(170, 1, Layout.ZoneLength), CFrame = CFrame.new(0, 6, mid), Transparency = 1, CanCollide = false })
		particles(sand, {
			Color = Color3.fromRGB(230, 205, 160),
			LightEmission = 0,
			Size = 0.35,
			Rate = 45,
			Lifetime = NumberRange.new(3, 5),
			Speed = NumberRange.new(8, 12),
			Spread = Vector2.new(10, 10),
			Direction = Enum.NormalId.Right,
			Transparency = 0.4,
		})
	elseif i == 8 then -- Golden Kingdom
		for _ = 1, 10 do
			Decor.Tower(onGround(edgeSpot(i)), rng:NextNumber(0.9, 1.3))
		end
		for _ = 1, 10 do
			Decor.Spire(onGround(edgeSpot(i)), rng:NextNumber(0.8, 1.3), zone.CrystalColors[rng:NextInteger(1, 3)])
		end
		for _ = 1, 10 do
			local pos = freeSpot(i, 2)
			if pos then
				Decor.Flowers(onGround(pos))
			end
		end
		local glitter = P({ Name = "GoldGlitter", Size = Vector3.new(160, 1, Layout.ZoneLength - 10), CFrame = CFrame.new(0, 18, mid), Transparency = 1, CanCollide = false })
		particles(glitter, {
			Color = Color3.fromRGB(255, 215, 110),
			Size = 0.25,
			Rate = 30,
			Lifetime = NumberRange.new(3, 6),
			Speed = NumberRange.new(0.2, 0.6),
			Spread = Vector2.new(180, 180),
		})
	end

	-- The end of the world, with a portal to the dimensions
	if i == #Shared.Zones then
		local finale = buildArch(ze + 8, zone, MapFolder, "🏆 YOU MADE IT!", "Step in the portal to visit the dimensions")
		finale.Name = "FinalArch"
		reserve(i, Vector3.new(-24, 0, ze + 8), 6)
		reserve(i, Vector3.new(24, 0, ze + 8), 6)
		local portalPos = Vector3.new(0, 0, ze + 30)
		buildPortal(portalPos, MapFolder)
		reserve(i, portalPos, 14)
	end
end

--------------------------------------------------------------------------------
-- INVISIBLE WALLS (so nobody walks off the map or around the gates)
--------------------------------------------------------------------------------
local function buildWalls()
	local length = Layout.HubFront - MAP_END + 20
	local midZ = (Layout.HubFront + MAP_END) / 2
	for _, side in ipairs({ -1, 1 }) do
		P({
			Name = "Wall",
			Size = Vector3.new(2, 300, length),
			CFrame = CFrame.new(side * (Layout.HalfWidth + 1), 150, midZ),
			Transparency = 1,
			Parent = WallFolder,
		})
	end
	for _, z in ipairs({ Layout.HubFront + 4, MAP_END + 2 }) do
		P({
			Name = "Wall",
			Size = Vector3.new(Layout.HalfWidth * 2, 300, 2),
			CFrame = CFrame.new(0, 150, z),
			Transparency = 1,
			Parent = WallFolder,
		})
	end
end

local addXP -- defined later
local endObby -- defined later
-- every dimension's obby pays out on its own timer: dimObbyLast[player][d] = os.time()
local dimObbyLast: { [Player]: { [number]: number } } = {}
type ObbyRun = { Course: ObbyCourse, Started: number, Checkpoint: number }
local obbyRuns: { [Player]: ObbyRun } = {} -- who is doing an obby right now
local lastObbyEnd: { [Player]: number } = {}

local digSpots: { [Instance]: any } = {} -- buried gems (see DIGGING)

--------------------------------------------------------------------------------
-- CRYSTALS
--------------------------------------------------------------------------------
type CrystalInfo = {
	Model: Model,
	Zone: number, -- 0 for dimension crystals
	Dimension: number?,
	XP: number,
	BaseXP: number,
	Folder: Instance, -- where the crystal lives while it is not broken
	Respawn: (CrystalInfo) -> CFrame?, -- where it grows back (nil = don't grow back)
	Giant: boolean,
	Golden: boolean,
	Health: number,
	MaxHealth: number,
	Gems: number,
	BaseGems: number,
	Color: Color3,
	BaseColor: Color3,
	GemParts: { BasePart },
	Glow: PointLight,
	GlowBrightness: number,
	Sparkles: ParticleEmitter,
	Main: BasePart,
	Radius: number,
	Alive: boolean,
	Billboard: BillboardGui,
	Fill: Frame,
	Label: TextLabel,
	Meteor: boolean?, -- a 🌠 meteor (pays coins, doesn't grow back)
}
local crystals: { [Model]: CrystalInfo } = {}

local GOLD = Color3.fromRGB(255, 194, 60)
-- turns a cube so one corner points straight up (that makes a crystal's pointy tip)
local CORNER_UP = CFrame.Angles(0, 0, math.atan(math.sqrt(2))) * CFrame.Angles(0, rad(45), 0)

local function updateBar(info: CrystalInfo)
	local frac = math.clamp(info.Health / info.MaxHealth, 0, 1)
	info.Fill.Size = UDim2.fromScale(frac, 1)
	info.Fill.BackgroundColor3 = Color3.fromRGB(235, 80, 70):Lerp(Color3.fromRGB(110, 220, 120), frac)
	info.Label.Text = Format(math.max(info.Health, 0)) .. " / " .. Format(info.MaxHealth)
	info.Billboard.Enabled = info.Health < info.MaxHealth
end

-- Golden crystals look like gold and give a lot more gems and XP
local function setGolden(info: CrystalInfo, golden: boolean)
	info.Golden = golden
	info.Color = if golden then GOLD else info.BaseColor
	info.Gems = info.BaseGems * (if golden then Settings.GoldenGems else 1)
	info.XP = info.BaseXP * (if golden then Settings.GoldenXP else 1)
	for _, part in ipairs(info.GemParts) do
		part.Color = info.Color
		if part.Material ~= Enum.Material.Neon then
			part.Reflectance = if golden then 0.4 else 0.2
		end
	end
	info.Glow.Color = info.Color
	info.Glow.Brightness = if golden then 1.5 else info.GlowBrightness
	info.Sparkles.Enabled = golden
	info.Model:SetAttribute("Golden", if golden then true else nil)
end

local function findSpot(zoneIndex: number, ignore: Model?): CFrame
	local best = anySpot(zoneIndex)
	for _ = 1, 40 do
		local pos = anySpot(zoneIndex)
		local ok = not isReserved(zoneIndex, pos, 4)
		for _, spot in pairs(digSpots) do
			if ok and spot.Alive and (spot.Pos - Vector3.new(pos.X, spot.Pos.Y, pos.Z)).Magnitude < 7 then
				ok = false
			end
		end
		for _, chest in pairs(Fun.Chests) do
			if ok and chest.Alive and (chest.Pos - Vector3.new(pos.X, chest.Pos.Y, pos.Z)).Magnitude < 7 then
				ok = false
			end
		end
		if ok then
			for m, info in pairs(crystals) do
				if m ~= ignore and info.Zone == zoneIndex and info.Alive then
					local other = info.Model:GetPivot().Position
					if (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(other.X, 0, other.Z)).Magnitude < 11 then
						ok = false
						break
					end
				end
			end
		end
		if ok then
			best = pos
			break
		end
	end
	-- sit a little bit in the ground, so it looks like it grew there
	return CFrame.new(onGround(best) - Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
end

type CrystalSpec = {
	Colors: { Color3 },
	RockColor: Color3,
	Health: number,
	Gems: number,
	XP: number,
	Zone: number,
	Dimension: number?,
	Shiny: boolean?,
}

local function zoneSpec(zoneIndex: number): CrystalSpec
	local zone = Shared.Zones[zoneIndex]
	return {
		Colors = zone.CrystalColors,
		RockColor = zone.RockColor,
		Health = zone.Health,
		Gems = zone.Gems,
		XP = zoneIndex,
		Zone = zoneIndex,
	}
end

local function buildCrystal(spec: CrystalSpec, giant: boolean, folder: Instance, respawn: (CrystalInfo) -> CFrame?): CrystalInfo
	local color = spec.Colors[rng:NextInteger(1, #spec.Colors)]
	local s = if giant then 1.9 else 1
	local m = Instance.new("Model")
	m.Name = if giant then "GiantCrystal" else "Crystal"
	m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local gemParts: { BasePart } = {}

	-- the rock it grows out of
	local base = P({
		Name = "Rock",
		Size = Vector3.new(4.4, 1.3, 4) * s,
		CFrame = CFrame.new(0, 0.45 * s, 0) * CFrame.Angles(rng:NextNumber(-0.08, 0.08), rng:NextNumber(0, math.pi), rng:NextNumber(-0.08, 0.08)),
		Color = spec.RockColor,
		Material = Enum.Material.Slate,
		Parent = m,
	})
	for k = 1, 3 do
		local a = k / 3 * math.pi * 2 + rng:NextNumber(-0.4, 0.4)
		P({
			Name = "Stone",
			Size = Vector3.new(rng:NextNumber(1.4, 2.2), rng:NextNumber(0.8, 1.2), rng:NextNumber(1.4, 2.2)) * s,
			CFrame = CFrame.new(math.cos(a) * 2 * s, 0.35 * s, math.sin(a) * 2 * s) * CFrame.Angles(rng:NextNumber(-0.5, 0.5), rng:NextNumber(0, math.pi), rng:NextNumber(-0.5, 0.5)),
			Color = spec.RockColor:Lerp(Color3.new(0, 0, 0), rng:NextNumber(0, 0.2)),
			Material = Enum.Material.Rock,
			Parent = m,
		})
	end

	-- a gem crystal: a long see-through prism with a pointy tip
	local function prism(name: string, root: CFrame, width: number, height: number): BasePart
		local body = P({
			Name = name,
			Size = Vector3.new(width, height, width),
			CFrame = root * CFrame.new(0, height / 2, 0),
			Color = color,
			Material = Enum.Material.Glass,
			Transparency = 0.12,
			Reflectance = 0.2,
			Parent = m,
		})
		local tip = P({
			Name = name .. "Tip",
			Size = Vector3.one * width * 0.82,
			CFrame = root * CFrame.new(0, height, 0) * CORNER_UP,
			Color = color:Lerp(Color3.new(1, 1, 1), 0.12),
			Material = Enum.Material.Glass,
			Transparency = 0.1,
			Reflectance = 0.25,
			Parent = m,
		})
		table.insert(gemParts, body)
		table.insert(gemParts, tip)
		return body
	end

	local main = prism("Main", CFrame.new(0, 0.6 * s, 0) * CFrame.Angles(rad(rng:NextNumber(-6, 6)), rad(45), rad(rng:NextNumber(-6, 6))), 1.7 * s, 5.2 * s)
	-- a lighter crystal inside the big one, so it looks deep and see-through
	local inner = P({
		Name = "Inner",
		Size = Vector3.new(0.9 * s, 4.4 * s, 0.9 * s),
		CFrame = main.CFrame * CFrame.Angles(0, rad(45), 0),
		Color = color:Lerp(Color3.new(1, 1, 1), 0.45),
		Material = Enum.Material.Glass,
		Transparency = 0.45,
		CanCollide = false,
		CanQuery = true,
		Parent = m,
	})
	table.insert(gemParts, inner)
	-- tiny crystals and pebbles around the bottom
	for k = 1, 2 do
		local a = rng:NextNumber(0, math.pi * 2)
		prism("Small", CFrame.new(math.cos(a) * 2.1 * s, 0.25 * s, math.sin(a) * 2.1 * s) * CFrame.Angles(rng:NextNumber(-0.5, 0.5), a, rng:NextNumber(-0.5, 0.5)), 0.45 * s, rng:NextNumber(0.8, 1.3) * s)
	end
	for _ = 1, 3 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(2.4, 3) * s
		P({
			Name = "Pebble",
			Size = Vector3.new(rng:NextNumber(0.4, 0.8), rng:NextNumber(0.3, 0.5), rng:NextNumber(0.4, 0.8)) * s,
			CFrame = CFrame.new(math.cos(a) * r, 0.15, math.sin(a) * r) * CFrame.Angles(0, rng:NextNumber(0, math.pi), rng:NextNumber(-0.3, 0.3)),
			Color = spec.RockColor:Lerp(Color3.new(1, 1, 1), rng:NextNumber(0, 0.15)),
			Material = Enum.Material.Rock,
			CanCollide = false,
			CanQuery = true,
			Parent = m,
		})
	end
	local sides = rng:NextInteger(3, 4)
	for k = 1, sides do
		local a = k / sides * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
		local lean = rad(rng:NextNumber(22, 38))
		local root = CFrame.new(math.cos(a) * 0.9 * s, 0.5 * s, math.sin(a) * 0.9 * s)
			* CFrame.Angles(0, -a, 0)
			* CFrame.Angles(0, 0, -lean)
		prism("Shard", root, rng:NextNumber(0.8, 1.1) * s, rng:NextNumber(2.2, 3.6) * s)
	end
	if spec.Shiny then
		-- shiny dimensions: crystals glow from the inside
		local core = P({
			Name = "Core",
			Size = Vector3.new(0.7 * s, 4.2 * s, 0.7 * s),
			CFrame = main.CFrame,
			Color = color,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CanQuery = true,
			Parent = m,
		})
		table.insert(gemParts, core)
	end
	local glowBrightness = if spec.Shiny then 1.6 else 0.45
	local glow = light(main, color, (if spec.Shiny then 13 else 8) * s, glowBrightness)
	local sparkles = particles(main, {
		Color = Color3.fromRGB(255, 225, 120),
		Size = 0.35 * s,
		Rate = 8,
		Lifetime = NumberRange.new(0.8, 1.4),
		Speed = NumberRange.new(0.5, 1.5),
		Spread = Vector2.new(180, 180),
	})
	sparkles.Enabled = false
	m.PrimaryPart = base

	-- health bar
	local bb = Instance.new("BillboardGui")
	bb.Name = "HealthBar"
	bb.Size = UDim2.fromOffset(120, 22)
	bb.StudsOffset = Vector3.new(0, 4.4 * s, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 70
	bb.Enabled = false
	bb.Adornee = main
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(25, 25, 32)
	back.BackgroundTransparency = 0.15
	back.Parent = bb
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = back
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1.5
	stroke.Color = Color3.fromRGB(10, 10, 16)
	stroke.Parent = back
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(110, 220, 120)
	fill.Parent = back
	corner:Clone().Parent = fill
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 0.9)
	label.Position = UDim2.fromScale(0, 0.05)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Parent = back
	local labelStroke = Instance.new("UIStroke")
	labelStroke.Thickness = 1.5
	labelStroke.Parent = label
	bb.Parent = m

	local health = spec.Health * (if giant then Settings.GiantHealth else 1)
	local gems = spec.Gems * (if giant then Settings.GiantGems else 1)
	local xp = spec.XP * (if giant then 3 else 1)
	local info: CrystalInfo = {
		Model = m,
		Zone = spec.Zone,
		Dimension = spec.Dimension,
		XP = xp,
		BaseXP = xp,
		Folder = folder,
		Respawn = respawn,
		Giant = giant,
		Golden = false,
		Health = health,
		MaxHealth = health,
		Gems = gems,
		BaseGems = gems,
		Color = color,
		BaseColor = color,
		GemParts = gemParts,
		Glow = glow,
		GlowBrightness = glowBrightness,
		Sparkles = sparkles,
		Main = main,
		Radius = 2 * s,
		Alive = true,
		Billboard = bb,
		Fill = fill,
		Label = label,
	}
	m:SetAttribute("IsCrystal", true)
	m:SetAttribute("Zone", spec.Zone)
	m:SetAttribute("Radius", info.Radius)
	crystals[m] = info
	setGolden(info, rng:NextNumber() < Settings.GoldenChance)
	updateBar(info)
	return info
end

local function zoneRespawn(info: CrystalInfo): CFrame?
	return findSpot(info.Zone, info.Model)
end

local function spawnCrystals()
	for zoneIndex = 1, #Shared.Zones do
		local spec = zoneSpec(zoneIndex)
		for _ = 1, Settings.CrystalsPerZone do
			local info = buildCrystal(spec, rng:NextNumber() < Settings.GiantChance, CrystalFolder, zoneRespawn)
			info.Model:PivotTo(findSpot(zoneIndex, info.Model))
			info.Model.Parent = CrystalFolder
		end
	end
end

--------------------------------------------------------------------------------
-- PLAYER DATA (saving and loading)
--------------------------------------------------------------------------------
type PlayerData = {
	Coins: number,
	Gems: number,
	Rebirths: number,
	Pickaxe: number,
	Backpack: number,
	Zone: number,
	Pets: { [number]: number }, -- [pet number] = how many you own
	TotalGems: number,
	Hatched: number,
	Level: number,
	XP: number,
	GoldenMined: number,
	ObbyBest: number, -- best obby time in seconds (0 = never finished)
	ObbyLast: number, -- when the obby last paid you (os.time)
	DailyStreak: number, -- how many days in a row you came back
	DailyLast: number, -- the day you last claimed your daily reward
	FreeEggs: number,
	QuestKind: string,
	QuestTarget: number,
	QuestProgress: number,
	QuestsDone: number,
	Shards: number, -- 💠 Boss Shards (only from bosses)
	BossesBeaten: number,
	DimPickaxe: number, -- the dimension of your special pickaxe (0 = none)
	DimBackpack: number, -- the dimension of your special backpack (0 = none)
	Gadgets: { number }, -- the gadgets you own
	GadgetsOff: { number }, -- the gadgets you turned off
	WheelLast: number, -- when you last spun the lucky wheel (os.time)
	GemBoostUntil: number, -- 2x gems until this time (os.time)
	ChestsFound: number,
	MeteorsBroken: number,
	Trades: number, -- how many trades you finished
}

local store: DataStore? = nil
if Settings.SaveData then
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore("CrystalRush_v1")
	end)
	if ok then
		store = result
	else
		warn("[Crystal Rush] Saving is off: " .. tostring(result))
	end
end
-- The leaderboards remember the best players of ALL servers in OrderedDataStores
local orderedStores: { [string]: OrderedDataStore } = {}
local boardSaved: { [Player]: { [string]: number } } = {} -- what we last wrote, so we only write changes
if store then
	for _, info in ipairs(LEADERBOARD_STATS) do
		local ok, result = pcall(function()
			return DataStoreService:GetOrderedDataStore("CrystalRush_Top_" .. info.Stat)
		end)
		if ok then
			orderedStores[info.Stat] = result
		end
	end
end

local Data: { [Player]: PlayerData } = {}
local CanSave: { [Player]: boolean } = {}

local function defaultData(): PlayerData
	return {
		Coins = 0,
		Gems = 0,
		Rebirths = 0,
		Pickaxe = 1,
		Backpack = 1,
		Zone = 1,
		Pets = {},
		TotalGems = 0,
		Hatched = 0,
		Level = 1,
		XP = 0,
		GoldenMined = 0,
		ObbyBest = 0,
		ObbyLast = 0,
		DailyStreak = 0,
		DailyLast = 0,
		FreeEggs = 0,
		QuestKind = Shared.QuestOrder[1],
		QuestTarget = Shared.QuestKinds[Shared.QuestOrder[1]].Target(0),
		QuestProgress = 0,
		QuestsDone = 0,
		Shards = 0,
		BossesBeaten = 0,
		DimPickaxe = 0,
		DimBackpack = 0,
		Gadgets = {},
		GadgetsOff = {},
		WheelLast = 0,
		GemBoostUntil = 0,
		ChestsFound = 0,
		MeteorsBroken = 0,
		Trades = 0,
	}
end

-- Turns a list like { 1, 4 } into { [1] = true, [4] = true }
local function toSet(list: { number }): { [number]: boolean }
	local set = {}
	for _, n in ipairs(list) do
		set[n] = true
	end
	return set
end

local function gadgetStats(data: PlayerData)
	return Shared.GadgetStats(toSet(data.Gadgets), toSet(data.GadgetsOff))
end

-- Gives you the next quest
local function newQuest(data: PlayerData)
	local kind = Shared.QuestOrder[data.QuestsDone % #Shared.QuestOrder + 1]
	data.QuestKind = kind
	data.QuestTarget = Shared.QuestKinds[kind].Target(data.QuestsDone)
	data.QuestProgress = 0
end

local function loadData(player: Player): (PlayerData, boolean)
	local data = defaultData()
	local loaded = false
	if store then
		local ok, saved = pcall(function()
			return (store :: DataStore):GetAsync("Player_" .. player.UserId)
		end)
		if ok then
			loaded = true
			if type(saved) == "table" then
				for key, default in pairs(data :: any) do
					if key ~= "Pets" and type(saved[key]) == type(default) then
						(data :: any)[key] = saved[key]
					end
				end
				if type(saved.PetCounts) == "table" then
					for key, count in pairs(saved.PetCounts) do
						local index = tonumber(key)
						if index and Shared.GetPet(index) and type(count) == "number" and count >= 1 then
							data.Pets[index] = math.floor(count)
						end
					end
				elseif type(saved.Pets) == "table" then -- saves from the first version of the game
					for _, index in ipairs(saved.Pets) do
						if type(index) == "number" and Shared.Pets[index] then
							data.Pets[index] = (data.Pets[index] or 0) + 1
						end
					end
				end
			end
		else
			warn("[Crystal Rush] Could not load data, progress won't be saved this time: " .. tostring(saved))
		end
	end
	data.Pickaxe = math.clamp(math.floor(data.Pickaxe), 1, #Shared.Pickaxes)
	data.Backpack = math.clamp(math.floor(data.Backpack), 1, #Shared.Backpacks)
	data.Zone = math.clamp(math.floor(data.Zone), 1, #Shared.Zones)
	data.Coins = math.max(0, math.floor(data.Coins))
	data.Level = math.max(1, math.floor(data.Level))
	data.XP = math.max(0, data.XP)
	data.Shards = math.max(0, math.floor(data.Shards))
	data.DimPickaxe = math.max(0, math.floor(data.DimPickaxe))
	data.DimBackpack = math.max(0, math.floor(data.DimBackpack))
	for _, key in ipairs({ "Gadgets", "GadgetsOff" }) do
		local clean = {}
		for _, n in ipairs((data :: any)[key]) do
			if type(n) == "number" and Shared.Gadgets[n] and not table.find(clean, n) then
				table.insert(clean, n)
			end
		end
		(data :: any)[key] = clean
	end
	data.Gems = math.clamp(math.floor(data.Gems), 0, Shared.BestBackpack(data).Capacity)
	data.FreeEggs = math.max(0, math.floor(data.FreeEggs))
	data.QuestsDone = math.max(0, math.floor(data.QuestsDone))
	if not Shared.QuestKinds[data.QuestKind] or data.QuestTarget < 1 then
		newQuest(data)
	end
	if RunService:IsStudio() and Settings.StudioStartCoins > 0 then
		data.Coins = math.max(data.Coins, Settings.StudioStartCoins)
	end
	return data, loaded
end

local function saveData(player: Player)
	local data = Data[player]
	if not (data and CanSave[player] and store) then
		return
	end
	local petCounts = {}
	for index, count in pairs(data.Pets) do
		petCounts[tostring(index)] = count
	end
	local payload: { [string]: any } = { PetCounts = petCounts }
	for key, value in pairs(data :: any) do
		if key ~= "Pets" then
			payload[key] = value
		end
	end
	local ok, err = pcall(function()
		(store :: DataStore):SetAsync("Player_" .. player.UserId, payload)
	end)
	if not ok then
		warn("[Crystal Rush] Could not save " .. player.Name .. ": " .. tostring(err))
		return
	end
	-- the leaderboards (only numbers that changed, and never Studio test players)
	if player.UserId <= 0 then
		return
	end
	local saved = boardSaved[player] or {}
	boardSaved[player] = saved
	for _, info in ipairs(LEADERBOARD_STATS) do
		local ordered = orderedStores[info.Stat]
		local value = boardValue(info, data)
		if ordered and value and saved[info.Stat] ~= value then
			local done = pcall(function()
				ordered:SetAsync(tostring(player.UserId), value)
			end)
			if done then
				saved[info.Stat] = value
			end
		end
	end
end

--------------------------------------------------------------------------------
-- TELLING PLAYERS WHAT CHANGED
--------------------------------------------------------------------------------
local function notify(player: Player, text: string, kind: string?)
	Remotes.Notify:FireClient(player, text, kind or "info")
end

-- Things that only last while you are in the server (free gifts for playing)
local sessionStart: { [Player]: number } = {}
local giftsClaimed: { [Player]: { [number]: boolean } } = {}

-- Which day of the daily streak you are on (counting today)
local function dailyStreak(data: PlayerData): number
	local today = Shared.Today()
	if data.DailyLast == today then
		return data.DailyStreak
	elseif data.DailyLast == today - 1 then
		return data.DailyStreak + 1
	end
	return 1
end

local function sync(player: Player)
	local data = Data[player]
	if not data then
		return
	end
	local claimed = giftsClaimed[player] or {}
	local gifts = table.create(#Shared.Gifts, false)
	for i in ipairs(Shared.Gifts) do
		gifts[i] = claimed[i] == true
	end
	-- Pets[n] = how many of pet n you own
	local pets = table.create(#Shared.Pets, 0)
	local dimPets = {}
	local dimWaits = {} -- ["3"] = seconds until dimension 3's obby pays again
	for d, last in pairs(dimObbyLast[player] or {}) do
		local wait = last + Settings.ObbyCooldown - os.time()
		if wait > 0 then
			dimWaits[tostring(d)] = wait
		end
	end
	for index, count in pairs(data.Pets) do
		if Shared.Pets[index] then
			pets[index] = count
		else
			table.insert(dimPets, { Index = index, Count = count })
		end
	end
	Remotes.Sync:FireClient(player, {
		Coins = data.Coins,
		Gems = data.Gems,
		Capacity = Shared.BestBackpack(data).Capacity,
		Rebirths = data.Rebirths,
		Pickaxe = data.Pickaxe,
		Backpack = data.Backpack,
		Zone = data.Zone,
		Pets = pets,
		TotalGems = data.TotalGems,
		Hatched = data.Hatched,
		Level = data.Level,
		XP = data.XP,
		FreeEggs = data.FreeEggs,
		Quest = { Kind = data.QuestKind, Target = data.QuestTarget, Progress = data.QuestProgress },
		QuestsDone = data.QuestsDone,
		Played = os.clock() - (sessionStart[player] or os.clock()),
		Gifts = gifts,
		DailyReady = data.DailyLast ~= Shared.Today(),
		DailyStreak = dailyStreak(data),
		ObbyBest = data.ObbyBest,
		ObbyWait = math.max(0, data.ObbyLast + Settings.ObbyCooldown - os.time()),
		DimObbyWaits = dimWaits,
		DimPets = dimPets,
		Shards = data.Shards,
		BossesBeaten = data.BossesBeaten,
		DimPickaxe = data.DimPickaxe,
		DimBackpack = data.DimBackpack,
		Gadgets = data.Gadgets,
		GadgetsOff = data.GadgetsOff,
		WheelWait = math.max(0, data.WheelLast + Settings.WheelCooldown - os.time()),
		BoostWait = math.max(0, data.GemBoostUntil - os.time()),
		ChestsFound = data.ChestsFound,
		MeteorsBroken = data.MeteorsBroken,
	})
	local stats = player:FindFirstChild("leaderstats")
	if stats then
		local coins = stats:FindFirstChild("Coins") :: IntValue?
		local rebirths = stats:FindFirstChild("Rebirths") :: IntValue?
		local level = stats:FindFirstChild("Level") :: IntValue?
		if coins then
			coins.Value = data.Coins
		end
		if level then
			level.Value = data.Level
		end
		if rebirths then
			rebirths.Value = data.Rebirths
		end
	end
end

--------------------------------------------------------------------------------
-- LEVELS
--------------------------------------------------------------------------------
local lastLevelLockNotice: { [Player]: number } = {}
addXP = function(player: Player, data: PlayerData, amount: number)
	data.XP += amount
	local leveledUp = false
	local maxLevel = Shared.MaxLevel(data.Zone)
	while data.Level < maxLevel and data.XP >= Shared.XPNeeded(data.Level) do
		data.XP -= Shared.XPNeeded(data.Level)
		data.Level += 1
		leveledUp = true
	end
	if data.Level >= maxLevel and data.XP >= Shared.XPNeeded(data.Level) then
		-- the XP bar is full: unlock the next zone to level up
		data.XP = Shared.XPNeeded(data.Level)
		local nextZone = Shared.Zones[data.Zone + 1]
		if nextZone and amount > 0 and os.clock() - (lastLevelLockNotice[player] or -math.huge) > 30 then
			lastLevelLockNotice[player] = os.clock()
			notify(player, "🔒 Your XP bar is full! Unlock " .. nextZone.Name .. " to level up.", "info")
		end
	end
	if leveledUp then
		Remotes.Effect:FireAllClients("levelup", player.UserId, data.Level)
		notify(player, "⭐ LEVEL " .. data.Level .. "! You can now visit " .. Shared.DimensionsUnlocked(data.Level) .. " dimensions!", "gold")
	end
end

--------------------------------------------------------------------------------
-- QUESTS, FREE GIFTS AND DAILY REWARDS
--------------------------------------------------------------------------------
-- Counts towards your quest. When it's done you get coins and XP, and a new quest.
local function questProgress(player: Player, data: PlayerData, kind: string, amount: number)
	if data.QuestKind ~= kind then
		return
	end
	data.QuestProgress = math.min(data.QuestProgress + amount, data.QuestTarget)
	if data.QuestProgress < data.QuestTarget then
		return
	end
	local coins, xp = Shared.QuestReward(data, data.QuestsDone)
	local text = Shared.QuestText({ Kind = kind, Target = data.QuestTarget })
	data.Coins += coins
	data.QuestsDone += 1
	newQuest(data)
	Remotes.Effect:FireClient(player, "quest", text, coins, xp)
	addXP(player, data, xp)
end

-- Gives a reward like { Crystals = 10 } or { Egg = true }. Returns what you got as text.
local function giveReward(data: PlayerData, reward: { Crystals: number?, Egg: boolean? }): string
	local parts = {}
	if reward.Crystals then
		local coins = Shared.RewardCoins(data, reward.Crystals)
		data.Coins += coins
		table.insert(parts, "💰 " .. Format(coins) .. " coins")
	end
	if reward.Egg then
		data.FreeEggs += 1
		table.insert(parts, "🥚 a FREE egg")
	end
	return table.concat(parts, " + ")
end

Remotes.Claim.OnServerEvent:Connect(function(player, what, index)
	local data = Data[player]
	if not data or type(what) ~= "string" then
		return
	end
	if what == "gift" then
		local gift = if type(index) == "number" then Shared.Gifts[index] else nil
		local claimed = giftsClaimed[player]
		if not gift or not claimed or claimed[index] then
			return
		end
		if os.clock() - sessionStart[player] < gift.Minutes * 60 - 2 then
			return -- not ready yet
		end
		claimed[index] = true
		Remotes.Effect:FireClient(player, "gift", giveReward(data, gift))
		sync(player)
	elseif what == "daily" then
		local today = Shared.Today()
		if data.DailyLast == today then
			return
		end
		local streak = dailyStreak(data)
		data.DailyStreak = streak
		data.DailyLast = today
		local reward = Shared.DailyRewards[(streak - 1) % #Shared.DailyRewards + 1]
		Remotes.Effect:FireClient(player, "daily", giveReward(data, reward), streak)
		sync(player)
		task.spawn(saveData, player)
	end
end)

--------------------------------------------------------------------------------
-- PICKAXE TOOL, BACKPACK ON YOUR BACK, PETS
--------------------------------------------------------------------------------
local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = a
end

-- Turns a model (pickaxe, shovel) into a tool you hold in your hand
local function makeTool(built: Model, name: string, tooltip: string, grip: CFrame): Tool
	local tool = Instance.new("Tool")
	tool.Name = name
	tool.ToolTip = tooltip
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.Grip = grip
	local handle = built.PrimaryPart :: BasePart
	for _, child in ipairs(built:GetChildren()) do
		if child:IsA("BasePart") then
			child.Anchored = false
			child.CanCollide = false
			child.CanQuery = false
			child.CanTouch = false
			child.Massless = true
			if child ~= handle then
				weld(handle, child)
			end
			child.Parent = tool
		end
	end
	for _, child in ipairs(built:GetDescendants()) do
		if child:IsA("Light") then
			child.Parent = handle
		end
	end
	built:Destroy()
	return tool
end

local function removeTool(player: Player, name: string): boolean
	local wasEquipped = false
	for _, container in ipairs({ player:FindFirstChildOfClass("Backpack"), player.Character } :: { Instance? }) do
		if container then
			for _, child in ipairs(container:GetChildren()) do
				if child:IsA("Tool") and child.Name == name then
					wasEquipped = wasEquipped or container == player.Character
					child:Destroy()
				end
			end
		end
	end
	return wasEquipped
end

-- Gives you your best pickaxe (your normal one or a dimension's special one)
local function givePickaxe(player: Player, equip: boolean?)
	local data = Data[player]
	local char = player.Character
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not (data and char and backpack) then
		return
	end
	local wasEquipped = removeTool(player, "Pickaxe")
	local def = Shared.BestPickaxe(data)
	local tool = makeTool(Shared.BuildPickaxe(def), "Pickaxe", def.Name, CFrame.new(0, -1.4, 0))
	tool.Parent = backpack
	local hum = char:FindFirstChildOfClass("Humanoid")
	if (equip or wasEquipped) and hum and hum.Health > 0 then
		hum:EquipTool(tool)
	end
end

local function giveShovel(player: Player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end
	removeTool(player, "Shovel")
	local tool = makeTool(Shared.BuildShovel(), "Shovel", "Shovel: dig up buried gems", CFrame.new(0, -1.2, 0))
	tool.Parent = backpack
end

-- Walk speed and jump height from your gadgets (gadgets are off in the obby)
local function applyMovement(player: Player, plain: boolean?)
	local data = Data[player]
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (data and hum) then
		return
	end
	local stats = gadgetStats(data)
	hum.UseJumpPower = false
	hum.WalkSpeed = Settings.WalkSpeed + (if plain then 0 else stats.Speed)
	hum.JumpHeight = if plain then Settings.JumpHeight else stats.Jump
end

local function updateBackpack(player: Player)
	local data = Data[player]
	local char = player.Character
	if not (data and char) then
		return
	end
	local old = char:FindFirstChild("GemBackpack")
	if old then
		old:Destroy()
	end
	local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
	if not (torso and torso:IsA("BasePart")) then
		return
	end
	local best = Shared.BestBackpack(data)
	local bag = Shared.BuildBackpack(if best.Dimension then best else data.Backpack)
	bag.Name = "GemBackpack"
	local body = bag.PrimaryPart :: BasePart
	bag:PivotTo(torso.CFrame * CFrame.new(0, 0, torso.Size.Z / 2 + body.Size.Z / 2))
	for _, child in ipairs(bag:GetChildren()) do
		if child:IsA("BasePart") then
			child.Anchored = false
			child.CanCollide = false
			child.CanQuery = false
			child.CanTouch = false
			child.Massless = true
			if child ~= body then
				weld(body, child)
			end
		end
	end
	weld(body, torso)
	bag.Parent = char
end

local function refreshPets(player: Player)
	for _, pet in ipairs(PetFolder:GetChildren()) do
		if pet:GetAttribute("Owner") == player.UserId then
			pet:Destroy()
		end
	end
	local data = Data[player]
	if not data then
		return
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	for slot, index in ipairs(Shared.GetEquippedPets(data.Pets)) do
		local pet = Shared.BuildPet(index)
		pet.Name = player.Name .. "_" .. pet.Name
		pet:SetAttribute("Owner", player.UserId)
		pet:SetAttribute("Slot", slot)
		pet:SetAttribute("Scale", Shared.GetPet(index).Size or 1)
		pet.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
		if root and root:IsA("BasePart") then
			pet:PivotTo(root.CFrame * CFrame.new(0, 0, 5))
		end
		pet.Parent = PetFolder
	end
end

--------------------------------------------------------------------------------
-- DIGGING (buried gems: dig them up with your shovel!)
--------------------------------------------------------------------------------
type DigSpot = {
	Model: Model,
	Mound: { BasePart },
	MoundSizes: { Vector3 },
	Zone: number,
	Dimension: number?,
	Health: number,
	MaxHealth: number,
	Gems: number,
	XP: number,
	Color: Color3,
	Pos: Vector3,
	Alive: boolean,
	Removed: boolean,
	OnTerrain: boolean,
	Place: () -> Vector3?,
	Fill: Frame,
	Label: TextLabel,
	Billboard: BillboardGui,
}

local function updateDigBar(spot: DigSpot)
	local frac = math.clamp(spot.Health / spot.MaxHealth, 0, 1)
	spot.Fill.Size = UDim2.fromScale(frac, 1)
	spot.Label.Text = "⛏️ " .. Format(math.max(spot.Health, 0)) .. " / " .. Format(spot.MaxHealth)
	spot.Billboard.Enabled = spot.Health < spot.MaxHealth
	-- the dirt pile gets smaller while you dig
	for k, part in ipairs(spot.Mound) do
		local size = spot.MoundSizes[k]
		part.Size = Vector3.new(size.X, size.Y * (0.35 + 0.65 * frac), size.Z)
	end
end

local function buildDigSpot(zoneIndex: number, dimension: number?, health: number, gems: number, xp: number, color: Color3, place: () -> Vector3?, onTerrain: boolean): DigSpot?
	local pos = place()
	if not pos then
		return nil
	end
	local m = Instance.new("Model")
	m.Name = "BuriedGem"
	m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local dirt = Color3.fromRGB(110, 84, 60)
	local mound, sizes = {}, {}
	for k = 1, 3 do
		local size = Vector3.new(rng:NextNumber(2.6, 3.4), rng:NextNumber(1.1, 1.6), rng:NextNumber(2.6, 3.4)) * (if k == 1 then 1.2 else 0.85)
		local piece = P({
			Name = "Dirt",
			Shape = Enum.PartType.Ball,
			Size = size,
			CFrame = CFrame.new(rng:NextNumber(-0.8, 0.8), 0, rng:NextNumber(-0.8, 0.8)),
			Color = dirt:Lerp(Color3.new(0, 0, 0), rng:NextNumber(0, 0.2)),
			Material = Enum.Material.Ground,
			CanCollide = false,
			CanQuery = true,
			Parent = m,
		})
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = piece
		table.insert(mound, piece)
		table.insert(sizes, size)
	end
	-- the tip of a gem sticking out, with a little glint
	local gem = P({
		Name = "GemTip",
		Size = Vector3.new(0.6, 1.3, 0.6),
		CFrame = CFrame.new(0.3, 0.6, -0.2) * CFrame.Angles(rad(15), rad(45), rad(-12)),
		Color = color,
		Material = Enum.Material.Glass,
		Reflectance = 0.3,
		CanCollide = false,
		CanQuery = true,
		Parent = m,
	})
	particles(gem, { Color = Color3.fromRGB(255, 245, 210), Size = 0.4, Rate = 2, Lifetime = NumberRange.new(0.4, 0.8), Speed = NumberRange.new(0, 0.2), Spread = Vector2.new(180, 180) })
	for k = 1, 3 do
		local a = k * 2.1
		P({
			Name = "Pebble",
			Size = Vector3.new(0.5, 0.35, 0.45),
			CFrame = CFrame.new(math.cos(a) * 1.9, -0.1, math.sin(a) * 1.9) * CFrame.Angles(0, a, 0.2),
			Color = Color3.fromRGB(120, 115, 108),
			Material = Enum.Material.Rock,
			CanCollide = false,
			CanQuery = true,
			Parent = m,
		})
	end
	m.PrimaryPart = mound[1]
	local bb = Instance.new("BillboardGui")
	bb.Name = "DigBar"
	bb.Size = UDim2.fromOffset(120, 22)
	bb.StudsOffset = Vector3.new(0, 3, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 60
	bb.Enabled = false
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(30, 24, 20)
	back.BackgroundTransparency = 0.15
	back.Parent = bb
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = back
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(205, 150, 80)
	fill.Parent = back
	corner:Clone().Parent = fill
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 0.9)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Parent = back
	bb.Parent = mound[1]
	m:SetAttribute("IsDigSpot", true)
	m:SetAttribute("Zone", zoneIndex)
	m:SetAttribute("Radius", 2)
	m:PivotTo(CFrame.new(pos))
	m.Parent = DigFolder
	local spot: DigSpot = {
		Model = m,
		Mound = mound,
		MoundSizes = sizes,
		Zone = zoneIndex,
		Dimension = dimension,
		Health = health,
		MaxHealth = health,
		Gems = gems,
		XP = xp,
		Color = color,
		Pos = pos,
		Alive = true,
		Removed = false,
		OnTerrain = onTerrain,
		Place = place,
		Fill = fill,
		Label = label,
		Billboard = bb,
	}
	digSpots[m] = spot
	updateDigBar(spot)
	return spot
end

-- A free spot for a buried gem: away from crystals and other buried gems
local function digSpotFree(pos: Vector3): boolean
	for _, other in pairs(digSpots) do
		if other.Alive and (other.Pos - pos).Magnitude < 14 then
			return false
		end
	end
	for _, info in pairs(crystals) do
		if info.Alive and (info.Model:GetPivot().Position - pos).Magnitude < 7 then
			return false
		end
	end
	return true
end

local function spawnZoneDigSpots(i: number)
	local zone = Shared.Zones[i]
	local function place(): Vector3?
		for _ = 1, 30 do
			local pos = freeSpot(i, 4)
			if pos and digSpotFree(pos) then
				return onGround(pos)
			end
		end
		return nil
	end
	for _ = 1, Settings.DigSpotsPerZone do
		buildDigSpot(i, nil, zone.Health * Settings.DigHealth, zone.Gems * Settings.DigGems, i * 2, zone.CrystalColors[rng:NextInteger(1, #zone.CrystalColors)], place, true)
	end
end

local function removeDigSpot(spot: DigSpot)
	spot.Removed = true
	spot.Alive = false
	digSpots[spot.Model] = nil
	spot.Model:Destroy()
end

local function digOut(spot: DigSpot, player: Player, data: PlayerData)
	spot.Alive = false
	local pos = spot.Pos
	local capacity = Shared.BestBackpack(data).Capacity
	local gems = math.floor(spot.Gems * Shared.GemMultiplier(data.Pets) * gadgetStats(data).Gems * (if data.GemBoostUntil > os.time() then 2 else 1))
	local added = math.min(gems, capacity - data.Gems)
	data.Gems += added
	data.TotalGems += added
	Remotes.Effect:FireAllClients("dugout", pos, spot.Color)
	Remotes.Effect:FireClient(player, "reward", pos + Vector3.new(0, 1, 0), added, spot.XP, false, spot.Color)
	addXP(player, data, spot.XP)
	questProgress(player, data, "mine", 1)
	sync(player)
	-- a real hole in the ground (it fills up again later)
	local restore: (() -> ())? = nil
	if spot.OnTerrain and Fun.HoleFree(pos) then
		local region = Region3.new(pos - Vector3.new(4, 5, 4), pos + Vector3.new(4, 3, 4)):ExpandToGrid(4)
		local ok, materials, occupancies = pcall(function()
			return Terrain:ReadVoxels(region, 4)
		end)
		if ok then
			Terrain:FillBall(pos - Vector3.new(0, 0.8, 0), 2.6, Enum.Material.Air)
			Fun.Holes[pos] = true
			restore = function()
				pcall(function()
					Terrain:WriteVoxels(region, 4, materials, occupancies)
				end)
				Fun.Holes[pos] = nil
			end
		end
	end
	spot.Model.Parent = ServerStorage
	task.delay(Settings.DigRespawnTime, function()
		if restore then
			restore()
		end
		if spot.Removed then
			return
		end
		local newPos = spot.Place()
		if not newPos then
			removeDigSpot(spot)
			return
		end
		spot.Pos = newPos
		spot.Health = spot.MaxHealth
		updateDigBar(spot)
		spot.Model:PivotTo(CFrame.new(newPos))
		spot.Alive = true
		spot.Model.Parent = DigFolder
	end)
end

-- Holes in the terrain that are still open (they can't overlap, or they would fill up wrong)
Fun.Holes = {} :: { [Vector3]: boolean }
function Fun.HoleFree(pos: Vector3): boolean
	local count = 0
	for other in pairs(Fun.Holes) do
		count += 1
		if (other - pos).Magnitude < 10 then
			return false
		end
	end
	return count < 40
end

-- Digging anywhere with the shovel: a few gems every time, and sometimes a lucky find
local lastGroundDig: { [Player]: number } = {}
function Fun.DigGround(player: Player, data: PlayerData, pos: Vector3)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (char and root and root:IsA("BasePart") and hum and hum.Health > 0) or not char:FindFirstChild("Shovel") then
		return
	end
	if pos ~= pos or (root.Position - pos).Magnitude > Settings.GroundDigRange then
		return -- too far away (or not a real position)
	end
	local now = os.clock()
	if now - (lastGroundDig[player] or 0) < Settings.GroundDigCooldown * 0.8 then
		return
	end
	local here = player:GetAttribute("Dimension")
	local gemsHere
	if type(here) == "number" then
		gemsHere = Shared.GetDimension(here).Gems
	else
		local zone = math.max(1, Shared.ZoneAt(pos.Z))
		if zone > data.Zone then
			return
		end
		gemsHere = Shared.Zones[zone].Gems
	end
	local capacity = Shared.BestBackpack(data).Capacity
	if data.Gems >= capacity then
		Remotes.Effect:FireClient(player, "full")
		return
	end
	lastGroundDig[player] = now
	local boost = if data.GemBoostUntil > os.time() then 2 else 1
	local gems = math.max(1, math.floor(gemsHere * Settings.GroundDigGems * Shared.GemMultiplier(data.Pets) * gadgetStats(data).Gems * boost))
	local added = math.min(gems, capacity - data.Gems)
	data.Gems += added
	data.TotalGems += added
	-- sometimes you find something special
	local found: string? = nil
	local roll = rng:NextNumber()
	if roll < Settings.DigFindEgg then
		data.FreeEggs += 1
		found = "🥚 a FREE EGG"
	elseif roll < Settings.DigFindEgg + Settings.DigFindShard then
		data.Shards += 1
		found = "💠 a Boss Shard"
	elseif roll < Settings.DigFindEgg + Settings.DigFindShard + Settings.DigFindCoins then
		local coins = Shared.RewardCoins(data, 8)
		data.Coins += coins
		found = "a bag of 💰 " .. Format(coins) .. " coins"
	end
	Remotes.Effect:FireClient(player, "digground", pos, added, found)
	if found then
		notify(player, "🪣 You dug up " .. found .. "!", "gold")
	end
	addXP(player, data, 1)
	-- a little hole in the ground that fills up again
	if type(here) ~= "number" and Fun.HoleFree(pos) then
		local region = Region3.new(pos - Vector3.new(4, 4, 4), pos + Vector3.new(4, 4, 4)):ExpandToGrid(4)
		local ok, materials, occupancies = pcall(function()
			return Terrain:ReadVoxels(region, 4)
		end)
		if ok then
			Fun.Holes[pos] = true
			Terrain:FillBall(pos - Vector3.new(0, 0.5, 0), 1.6, Enum.Material.Air)
			task.delay(Settings.GroundHoleTime, function()
				pcall(function()
					Terrain:WriteVoxels(region, 4, materials, occupancies)
				end)
				Fun.Holes[pos] = nil
			end)
		end
	end
	sync(player)
end
Players.PlayerRemoving:Connect(function(player)
	lastGroundDig[player] = nil
end)

local lastDig: { [Player]: number } = {}
Remotes.Dig.OnServerEvent:Connect(function(player, target)
	local data = Data[player]
	if data and typeof(target) == "Vector3" then
		Fun.DigGround(player, data, target)
		return
	end
	if not data or typeof(target) ~= "Instance" then
		return
	end
	local spot = digSpots[target]
	if not spot or not spot.Alive then
		return
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (char and root and root:IsA("BasePart") and hum and hum.Health > 0) or not char:FindFirstChild("Shovel") then
		return
	end
	local now = os.clock()
	if now - (lastDig[player] or 0) < Settings.MineCooldown * 0.8 then
		return
	end
	if (root.Position - spot.Pos).Magnitude > Settings.MineRange + 6 then
		return
	end
	if spot.Dimension and spot.Dimension > Shared.DimensionsUnlocked(data.Level) then
		return
	end
	if data.Gems >= Shared.BestBackpack(data).Capacity then
		Remotes.Effect:FireClient(player, "full")
		return
	end
	lastDig[player] = now
	local power = math.max(1, math.floor(Shared.BestPickaxe(data).Power * Shared.LevelPower(data.Level)))
	spot.Health -= power
	Remotes.Effect:FireClient(player, "dig", spot.Pos, power)
	if spot.Health <= 0 then
		digOut(spot, player, data)
	else
		updateDigBar(spot)
	end
end)

--------------------------------------------------------------------------------
-- DIAMOND BOSSES (one in every zone and every dimension)
--   They float around their arena and shoot crystal shards at you (jump away!).
--   Hit them with your pickaxe. Beating one gives lots of coins, XP and
--   💠 Boss Shards, the money for the special pickaxes in the dimensions.
--------------------------------------------------------------------------------
type Boss = {
	Model: Model,
	Name: string,
	Color: Color3,
	Center: Vector3,
	Radius: number,
	Zone: number,
	Dimension: number?,
	Pos: Vector3,
	Target: Vector3,
	Health: number,
	MaxHealth: number,
	Alive: boolean,
	Removed: boolean,
	Hitters: { [Player]: number },
	NextAttack: number,
	Fill: Frame,
	Label: TextLabel,
}
local bosses: { [Model]: Boss } = {}
local BOSS_NAMES = { "Emerald Guardian", "Amethyst Titan", "Ruby Overlord", "Sapphire Giant", "Void Diamond" }
local BOSS_HOVER = 7 -- how high bosses float

local function updateBossBar(boss: Boss)
	local frac = math.clamp(boss.Health / boss.MaxHealth, 0, 1)
	boss.Fill.Size = UDim2.fromScale(frac, 1)
	boss.Label.Text = "❤️ " .. Format(math.max(boss.Health, 0)) .. " / " .. Format(boss.MaxHealth)
end

-- A giant gem with an angry face, a crown of crystals and shards flying around it
local function buildBossModel(name: string, color: Color3, accent: Color3, shiny: boolean): (Model, Frame, TextLabel)
	local m = Instance.new("Model")
	m.Name = "DiamondBoss"
	local function gemPart(props)
		props.CanCollide = false
		props.CanQuery = true
		props.Parent = m
		return P(props)
	end
	local body = gemPart({ Name = "Body", Size = Vector3.new(5, 5.4, 5), Color = color, Material = Enum.Material.Glass, Transparency = 0.05, Reflectance = 0.3 })
	gemPart({ Name = "Top", Size = Vector3.one * 4.3, CFrame = CFrame.new(0, 2.7, 0) * CORNER_UP, Color = color:Lerp(Color3.new(1, 1, 1), 0.15), Material = Enum.Material.Glass, Transparency = 0.05, Reflectance = 0.3 })
	gemPart({ Name = "Bottom", Size = Vector3.one * 4.3, CFrame = CFrame.new(0, -2.7, 0) * CORNER_UP, Color = color:Lerp(Color3.new(0, 0, 0), 0.2), Material = Enum.Material.Glass, Transparency = 0.05, Reflectance = 0.3 })
	gemPart({ Name = "Core", Size = Vector3.new(2.6, 3.4, 2.6), Color = color:Lerp(Color3.new(1, 1, 1), 0.5), Material = if shiny then Enum.Material.Neon else Enum.Material.Glass, Transparency = if shiny then 0.2 else 0.4 })
	for k = 0, 4 do
		local a = k / 5 * math.pi * 2
		gemPart({
			Name = "Crown",
			Size = Vector3.new(0.8, 2.4, 0.8),
			CFrame = CFrame.new(math.cos(a) * 1.4, 5.4, math.sin(a) * 1.4) * CFrame.Angles(0, -a, 0) * CFrame.Angles(0, 0, rad(-18)),
			Color = accent,
			Material = Enum.Material.Glass,
			Reflectance = 0.3,
		})
	end
	-- the angry face (on the -Z side, the front)
	for _, side in ipairs({ -1, 1 }) do
		gemPart({ Name = "Eye", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.15, CFrame = CFrame.new(1.05 * side, 0.7, -2.45), Color = Color3.fromRGB(255, 250, 235), Material = Enum.Material.Neon })
		gemPart({ Name = "Pupil", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.5, CFrame = CFrame.new(0.95 * side, 0.6, -2.95), Color = Color3.fromRGB(25, 20, 30) })
		gemPart({ Name = "Brow", Size = Vector3.new(1.5, 0.32, 0.4), CFrame = CFrame.new(1.05 * side, 1.55, -2.6) * CFrame.Angles(0, 0, rad(-20 * side)), Color = color:Lerp(Color3.new(0, 0, 0), 0.55) })
	end
	gemPart({ Name = "Mouth", Size = Vector3.new(1.8, 0.35, 0.3), CFrame = CFrame.new(0, -0.95, -2.55), Color = Color3.fromRGB(30, 22, 34) })
	-- little shards that fly around it
	for k = 0, 3 do
		local a = k / 4 * math.pi * 2
		gemPart({
			Name = "Shard",
			Size = Vector3.new(0.9, 1.8, 0.9),
			CFrame = CFrame.new(math.cos(a) * 5.2, math.sin(a * 2) * 0.8, math.sin(a) * 5.2) * CFrame.Angles(rad(30), a, rad(20)),
			Color = accent,
			Material = Enum.Material.Glass,
			Reflectance = 0.3,
		})
	end
	light(body, color, 22, if shiny then 2 else 1)
	m.PrimaryPart = body
	-- a big health bar with the boss's name
	local bb = Instance.new("BillboardGui")
	bb.Name = "BossBar"
	bb.Size = UDim2.fromOffset(260, 56)
	bb.StudsOffset = Vector3.new(0, 8, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 120
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(1, 0.45)
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = accent:Lerp(Color3.new(1, 1, 1), 0.5)
	title.Text = "👑 " .. name
	title.Parent = bb
	local titleStroke = Instance.new("UIStroke")
	titleStroke.Thickness = 2
	titleStroke.Parent = title
	local back = Instance.new("Frame")
	back.Position = UDim2.fromScale(0, 0.5)
	back.Size = UDim2.fromScale(1, 0.5)
	back.BackgroundColor3 = Color3.fromRGB(28, 20, 26)
	back.BackgroundTransparency = 0.1
	back.Parent = bb
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = back
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(235, 70, 80)
	fill.Parent = back
	corner:Clone().Parent = fill
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 0.9)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Parent = back
	local labelStroke = Instance.new("UIStroke")
	labelStroke.Thickness = 1.5
	labelStroke.Parent = label
	bb.Parent = body
	return m, fill, label
end

-- The arena: a stone floor and a low wall with an opening, braziers and a sign
local function buildArenaRing(center: Vector3, radius: number, entrance: Vector3, name: string, accent: Color3, parent: Instance)
	local arena = model("BossArena", parent)
	arena.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local upright = CFrame.Angles(0, 0, rad(90))
	local stone = Color3.fromRGB(116, 110, 104)
	P({ Name = "Floor", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, radius * 2, radius * 2), CFrame = CFrame.new(center + Vector3.new(0, 0.1, 0)) * upright, Color = stone, Material = Enum.Material.Slate, Parent = arena })
	P({ Name = "FloorRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.66, radius * 1.3, radius * 1.3), CFrame = CFrame.new(center + Vector3.new(0, 0.12, 0)) * upright, Color = stone:Lerp(Color3.new(0, 0, 0), 0.2), Material = Enum.Material.Cobblestone, Parent = arena })
	P({ Name = "FloorCenter", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.7, radius * 0.6, radius * 0.6), CFrame = CFrame.new(center + Vector3.new(0, 0.14, 0)) * upright, Color = accent:Lerp(stone, 0.6), Material = Enum.Material.Slate, Parent = arena })
	local segments = 22
	local openAngle = math.atan2(entrance.Z - center.Z, entrance.X - center.X)
	for k = 0, segments - 1 do
		local a = (k + 0.5) / segments * math.pi * 2
		local diff = math.abs((a - openAngle + math.pi) % (math.pi * 2) - math.pi)
		if diff > 0.3 then
			local pos = center + Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius)
			P({
				Name = "Wall",
				Size = Vector3.new(1.6, 3.2, radius * 2 * math.pi / segments + 0.3),
				CFrame = CFrame.new(pos + Vector3.new(0, 1.6, 0)) * CFrame.Angles(0, -a, 0),
				Color = stone:Lerp(Color3.new(0, 0, 0), rng:NextNumber(0, 0.2)),
				Material = Enum.Material.Cobblestone,
				Parent = arena,
			})
			if k % 4 == 0 then
				P({ Name = "Pillar", Size = Vector3.new(2.4, 6, 2.4), CFrame = CFrame.new(pos + Vector3.new(0, 3, 0)) * CFrame.Angles(0, -a, 0), Color = stone, Material = Enum.Material.Slate, Parent = arena })
				local bowl = P({ Name = "Brazier", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8, 2.2, 2.2), CFrame = CFrame.new(pos + Vector3.new(0, 6.4, 0)) * upright, Color = Color3.fromRGB(40, 38, 40), Material = Enum.Material.Metal, Parent = arena })
				local fire = Instance.new("Fire")
				fire.Size = 3
				fire.Heat = 7
				fire.Color = Color3.fromRGB(255, 150, 60)
				fire.SecondaryColor = Color3.fromRGB(255, 220, 120)
				fire.Parent = bowl
				light(bowl, Color3.fromRGB(255, 170, 90), 18, 1)
			end
		end
	end
	-- sign over the entrance
	local signPos = center + Vector3.new(math.cos(openAngle), 0, math.sin(openAngle)) * (radius + 1)
	for _, offset in ipairs({ -3.5, 3.5 }) do
		local side = Vector3.new(-math.sin(openAngle), 0, math.cos(openAngle)) * offset
		P({ Name = "GatePost", Size = Vector3.new(1.4, 9, 1.4), CFrame = CFrame.new(signPos + side + Vector3.new(0, 4.5, 0)), Color = Color3.fromRGB(80, 64, 50), Material = Enum.Material.Wood, Parent = arena })
	end
	local anchor = P({ Name = "SignAnchor", Size = Vector3.one, CFrame = CFrame.new(signPos + Vector3.new(0, 9, 0)), Transparency = 1, CanCollide = false, Parent = arena })
	fancySign(anchor, "⚔️", "BOSS: " .. string.upper(name), "Beat it for 💠 Boss Shards!", Color3.fromRGB(235, 90, 90), 13, 2.5)
	return arena
end

local function randomArenaPoint(boss: Boss): Vector3
	local a = rng:NextNumber(0, math.pi * 2)
	local r = rng:NextNumber(0, boss.Radius - 7)
	return boss.Center + Vector3.new(math.cos(a) * r, BOSS_HOVER, math.sin(a) * r)
end

local function createBoss(center: Vector3, radius: number, zoneIndex: number, d: number?, entrance: Vector3, parent: Instance): Boss
	local name, color, accent, health, shiny
	if d then
		local dim = Shared.GetDimension(d)
		name = dim.Name .. " Diamond"
		color, accent = dim.CrystalColors[1], dim.Accent
		health = dim.Health * Settings.BossHealth
		shiny = dim.Shiny
	else
		local zone = Shared.Zones[zoneIndex]
		name = BOSS_NAMES[zoneIndex] or (zone.Name .. " Boss")
		color, accent = zone.CrystalColors[1], zone.Accent
		health = zone.Health * Settings.BossHealth
		shiny = false
	end
	buildArenaRing(center, radius, entrance, name, accent, parent)
	local m, fill, label = buildBossModel(name, color, accent, shiny)
	local start = center + Vector3.new(0, BOSS_HOVER, 0)
	m:PivotTo(CFrame.new(start))
	m:SetAttribute("IsBoss", true)
	m:SetAttribute("Radius", 4)
	m:SetAttribute("BossPos", start)
	m:SetAttribute("ArenaCenter", center)
	m:SetAttribute("ArenaRadius", radius)
	m:AddTag("Boss")
	m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	m.Parent = BossFolder
	local boss: Boss = {
		Model = m,
		Name = name,
		Color = color,
		Center = center,
		Radius = radius,
		Zone = zoneIndex,
		Dimension = d,
		Pos = start,
		Target = start,
		Health = health,
		MaxHealth = health,
		Alive = true,
		Removed = false,
		Hitters = {},
		NextAttack = 0,
		Fill = fill,
		Label = label,
	}
	bosses[m] = boss
	updateBossBar(boss)
	return boss
end

buildBossArena = function(i: number)
	local center = bossArenaCenter(i)
	createBoss(center, BOSS_ARENA_RADIUS, i, nil, Vector3.new(0, 0, center.Z), MapFolder)
end

local function removeBoss(boss: Boss)
	boss.Removed = true
	boss.Alive = false
	bosses[boss.Model] = nil
	boss.Model:Destroy()
end

local function defeatBoss(boss: Boss)
	boss.Alive = false
	Remotes.Effect:FireAllClients("bossdefeat", boss.Pos, boss.Color)
	local level = boss.Dimension or boss.Zone
	for player, damage in pairs(boss.Hitters) do
		local data = Data[player]
		-- you need to have helped a bit to get the reward
		if data and player.Parent and damage >= boss.MaxHealth * 0.05 then
			local coins = Shared.RewardCoins(data, Settings.BossRewardCrystals)
			local shards = Shared.BossShards(boss.Zone, boss.Dimension)
			local xp = Settings.BossXP * level
			data.Coins += coins
			data.Shards += shards
			data.BossesBeaten += 1
			Remotes.Effect:FireClient(player, "bossreward", boss.Name, coins, shards, xp)
			addXP(player, data, xp)
			sync(player)
		end
	end
	boss.Hitters = {}
	boss.Model.Parent = ServerStorage
	task.delay(Settings.BossRespawnTime, function()
		if boss.Removed then
			return
		end
		boss.Health = boss.MaxHealth
		updateBossBar(boss)
		boss.Pos = boss.Center + Vector3.new(0, BOSS_HOVER, 0)
		boss.Target = boss.Pos
		boss.Model:SetAttribute("BossPos", boss.Pos)
		boss.Alive = true
		boss.Model.Parent = BossFolder
		Remotes.Effect:FireAllClients("bossspawn", boss.Pos, boss.Color)
	end)
end

local function hitBoss(player: Player, boss: Boss, power: number)
	boss.Health -= power
	boss.Hitters[player] = (boss.Hitters[player] or 0) + power
	Remotes.Effect:FireClient(player, "bosshit", boss.Pos, power, boss.Model)
	if boss.Health <= 0 then
		defeatBoss(boss)
	else
		updateBossBar(boss)
	end
end

-- Bosses float around and attack whoever is in their arena
local function playersInArena(boss: Boss): { Player }
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if root and root:IsA("BasePart") and hum and hum.Health > 0 then
			local flat = Vector3.new(root.Position.X - boss.Center.X, 0, root.Position.Z - boss.Center.Z)
			if flat.Magnitude < boss.Radius + 1 and math.abs(root.Position.Y - boss.Center.Y) < 25 then
				table.insert(list, player)
			end
		end
	end
	return list
end

task.spawn(function()
	while true do
		local dt = task.wait(0.1)
		for _, boss in pairs(bosses) do
			if boss.Alive then
				local fighters = playersInArena(boss)
				local to = boss.Target - boss.Pos
				if to.Magnitude < 1 then
					boss.Target = randomArenaPoint(boss)
				else
					local speed = if #fighters > 0 then 9 else 4
					boss.Pos += to.Unit * math.min(to.Magnitude, speed * dt)
				end
				boss.Model:SetAttribute("BossPos", boss.Pos)
				local now = os.clock()
				if now >= boss.NextAttack then
					if #fighters > 0 then
						boss.NextAttack = now + Settings.BossAttackEvery
						local victim = fighters[rng:NextInteger(1, #fighters)]
						local root = (victim.Character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart
						local spot = root.Position - Vector3.new(0, 2.6, 0)
						Remotes.Effect:FireAllClients("bossattack", boss.Model, boss.Pos, spot)
						task.delay(0.8, function()
							if not boss.Alive then
								return
							end
							for _, player in ipairs(fighters) do
								local char = player.Character
								local r = char and char:FindFirstChild("HumanoidRootPart")
								local hum = char and char:FindFirstChildOfClass("Humanoid")
								if r and r:IsA("BasePart") and hum and (r.Position - Vector3.new(0, 2.6, 0) - spot).Magnitude < 5 then
									hum:TakeDamage(Settings.BossDamage)
									Remotes.Effect:FireClient(player, "bossouch")
								end
							end
						end)
					else
						boss.NextAttack = now + 1
					end
				end
			end
		end
	end
end)

--------------------------------------------------------------------------------
-- DIMENSIONS (valleys between mountains, built when someone visits them)
--------------------------------------------------------------------------------
type Arena = {
	Number: number,
	Slot: number,
	Center: Vector3,
	Folder: Folder,
	CrystalFolder: Folder,
	Walls: Folder,
	SellPad: Model,
	Infos: { CrystalInfo },
	Reserved: { { pos: Vector3, radius: number } },
	DigSpots: { DigSpot },
	Boss: Boss?,
	Obby: ObbyCourse,
	Chests: { any },
	EmptySince: number?,
	Alive: boolean,
}
local arenas: { [number]: Arena } = {}
local usedSlots: { [number]: boolean } = {}
local dimensionOf: { [Player]: number } = {}

local function leaveDimension(player: Player)
	dimensionOf[player] = nil
	player:SetAttribute("Dimension", nil)
end

local function teleport(player: Player, zoneIndex: number)
	endObby(player, false)
	leaveDimension(player)
	local char = player.Character
	if char then
		char:PivotTo(CFrame.new(Shared.ZoneSpawn(zoneIndex)))
	end
end

local function arenaCenter(slot: number): Vector3
	return Vector3.new(5000 + slot * 700, 300, 0)
end

local function arenaSpawn(arena: Arena): CFrame
	return CFrame.new(arena.Center + Vector3.new(0, 4, 45))
end

local function arenaSpot(arena: Arena, ignore: Model?): CFrame?
	if not arena.Alive then
		return nil
	end
	local best = arena.Center
	for _ = 1, 40 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local radius = rng:NextNumber(6, 50)
		local pos = arena.Center + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		local ok = true
		for _, r in ipairs(arena.Reserved) do
			if (pos - r.pos).Magnitude < r.radius + 4 then
				ok = false
				break
			end
		end
		if ok then
			for _, other in ipairs(arena.Infos) do
				if other.Model ~= ignore and other.Alive and (other.Model:GetPivot().Position - pos).Magnitude < 10 then
					ok = false
					break
				end
			end
		end
		if ok then
			best = pos
			break
		end
	end
	return CFrame.new(best) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
end

local function decorateArena(dim, center: Vector3)
	local theme = dim.Theme
	local function edge(minR: number, maxR: number): Vector3
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(minR, maxR)
		return center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
	end
	local colors = dim.CrystalColors
	local rock = dim.Rock
	for _ = 1, 16 do
		local pos = edge(58, 74)
		local color = colors[rng:NextInteger(1, #colors)]
		local scale = rng:NextNumber(0.9, 1.5)
		local decor = theme.Decor
		if decor == "candy" then
			Decor.Lollipop(pos, scale, color)
		elseif decor == "pillars" or decor == "cyber" then
			Decor.Pillar(pos, scale, color)
		elseif decor == "coral" or decor == "spires" or decor == "rainbow" then
			Decor.Spire(pos, scale, color)
		elseif decor == "trees" then
			Decor.Tree(pos, scale)
		elseif decor == "cactus" then
			Decor.Cactus(pos, scale)
		elseif decor == "mushrooms" then
			Decor.Mushroom(pos, scale * 1.4, color)
		elseif decor == "clouds" then
			Decor.Cloud(pos, scale)
		elseif decor == "ice" then
			Decor.IceSpike(pos, scale)
		elseif decor == "lava" then
			Decor.Rock(pos, scale * 1.5, rock, Enum.Material.Basalt)
		end
	end
	if theme.Decor == "lava" then
		for _ = 1, 5 do
			Decor.LavaPool(edge(52, 70), rng:NextNumber(3, 5))
		end
	end
	-- rocks around the edge of the island
	for k = 0, 23 do
		local a = k / 24 * math.pi * 2 + rng:NextNumber(-0.1, 0.1)
		local r = rng:NextNumber(78, 83)
		Decor.Rock(center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r), rng:NextNumber(1.4, 2.4), rock, Enum.Material.Slate)
	end
end

-- What the mountains around each kind of dimension are made of (and if they have snow on top)
local MOUNTAINS = {
	candy = { Enum.Material.Limestone, false },
	pillars = { Enum.Material.Basalt, false },
	cyber = { Enum.Material.Slate, false },
	coral = { Enum.Material.Sandstone, false },
	trees = { Enum.Material.Rock, true },
	cactus = { Enum.Material.Sandstone, false },
	mushrooms = { Enum.Material.Mud, false },
	clouds = { Enum.Material.Snow, true },
	spires = { Enum.Material.Basalt, false },
	rainbow = { Enum.Material.Limestone, true },
	ice = { Enum.Material.Glacier, true },
	lava = { Enum.Material.Basalt, false },
}

-- A mountain made of terrain: big round rock at the bottom, getting thinner to the top
local function mountain(base: Vector3, radius: number, height: number, material: Enum.Material, snow: boolean)
	local steps = 6
	for k = 0, steps - 1 do
		local t = k / (steps - 1)
		local r = radius * (1 - t * 0.78)
		Terrain:FillBall(base + Vector3.new(rng:NextNumber(-2, 2), t * height - r * 0.35, rng:NextNumber(-2, 2)), r, material)
	end
	if snow then
		Terrain:FillBall(base + Vector3.new(0, height * 0.97, 0), radius * 0.3, Enum.Material.Snow)
	end
end

local function buildMountains(center: Vector3, theme)
	local info = MOUNTAINS[theme.Decor] or { Enum.Material.Rock, true }
	for ring, settings in ipairs({ { 12, 135, 165, 30, 46, 55, 95 }, { 10, 205, 235, 50, 70, 100, 150 } }) do
		local count = settings[1]
		for k = 0, count - 1 do
			local a = (k + rng:NextNumber(-0.3, 0.3)) / count * math.pi * 2 + ring * 0.3
			local dist = rng:NextNumber(settings[2], settings[3])
			local base = center + Vector3.new(math.cos(a) * dist, -2, math.sin(a) * dist)
			mountain(base, rng:NextNumber(settings[4], settings[5]), rng:NextNumber(settings[6], settings[7]), info[1], info[2])
		end
	end
end

local function clearMountains(center: Vector3)
	-- in four pieces, so no single terrain change is too big
	for _, x in ipairs({ -140, 140 }) do
		for _, z in ipairs({ -140, 140 }) do
			Terrain:FillBlock(CFrame.new(center + Vector3.new(x, 70, z)), Vector3.new(280, 240, 280), Enum.Material.Air)
		end
	end
end

local function buildArena(d: number): Arena?
	local slot = nil
	for i = 0, Settings.MaxOpenDimensions - 1 do
		if not usedSlots[i] then
			slot = i
			break
		end
	end
	if not slot then
		return nil
	end
	usedSlots[slot] = true
	local dim = Shared.GetDimension(d)
	local theme = dim.Theme
	local center = arenaCenter(slot)

	local f = Instance.new("Folder")
	f.Name = "Dimension" .. d
	f.Parent = DimensionFolder
	local crystalFolder = Instance.new("Folder")
	crystalFolder.Name = "Crystals"
	crystalFolder.Parent = f
	local walls = Instance.new("Folder")
	walls.Name = "Dimension" .. d
	walls.Parent = WallFolder

	local previous = buildParent
	buildParent = f
	decorShiny = dim.Shiny
	local upright = CFrame.Angles(0, 0, rad(90))

	-- a big valley with mountains all around
	P({
		Name = "Ground",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(8, 540, 540),
		CFrame = CFrame.new(center - Vector3.new(0, 4, 0)) * upright,
		Color = dim.Ground,
		Material = theme.GroundMaterial,
	})
	buildMountains(center, theme)
	-- invisible walls so nobody walks off
	for k = 0, 23 do
		local a = k / 24 * math.pi * 2
		P({
			Name = "Wall",
			Size = Vector3.new(2, 120, 24.5),
			CFrame = CFrame.new(center + Vector3.new(math.cos(a) * 86, 60, math.sin(a) * 86)) * CFrame.Angles(0, -a, 0),
			Transparency = 1,
			Parent = walls,
		})
	end

	-- a stone sign with the dimension's name, in front of the spawn
	do
		local signPos = center + Vector3.new(0, 0, 30)
		P({ Name = "SignBase", Size = Vector3.new(15, 1.2, 3), CFrame = CFrame.new(signPos + Vector3.new(0, 0.6, 0)), Color = dim.Rock:Lerp(Color3.fromRGB(120, 115, 110), 0.5), Material = Enum.Material.Cobblestone })
		local plate = P({ Name = "SignStone", Size = Vector3.new(13, 5, 1.2), CFrame = CFrame.new(signPos + Vector3.new(0, 3.7, 0)), Color = dim.Rock:Lerp(Color3.fromRGB(70, 66, 64), 0.6), Material = Enum.Material.Slate })
		if dim.Shiny then
			carvedText(plate, Enum.NormalId.Back, "✨ SHINY DIMENSION " .. d .. " ✨", dim.Emoji .. " " .. dim.Name .. "  •  2x gems!", Color3.fromRGB(255, 225, 130))
		else
			carvedText(plate, Enum.NormalId.Back, "🌌 DIMENSION " .. d, dim.Emoji .. " " .. dim.Name, dim.Accent:Lerp(Color3.new(1, 1, 1), 0.5))
		end
	end
	if dim.Shiny then
		-- sparkles in the air (only shiny dimensions sparkle)
		local air = P({
			Name = "Sparkles",
			Size = Vector3.new(150, 1, 150),
			CFrame = CFrame.new(center + Vector3.new(0, 25, 0)),
			Transparency = 1,
			CanCollide = false,
		})
		particles(air, {
			Color = dim.Accent,
			Size = 0.45,
			Rate = 30,
			Lifetime = NumberRange.new(3, 6),
			Speed = NumberRange.new(0.3, 1),
			Spread = Vector2.new(180, 180),
		})
	end

	-- stone portal back home (step in its circle)
	local homePos = center + Vector3.new(24, 0, 44)
	local home = model("HomePortal")
	local ringCenter = homePos + Vector3.new(0, 6.5, 0)
	for k = 0, 15 do
		local a = k / 16 * math.pi * 2
		P({
			Name = "Ring",
			Size = Vector3.new(2.4, 1.3, 1.4),
			CFrame = CFrame.new(ringCenter + Vector3.new(math.cos(a) * 5, math.sin(a) * 5, 0)) * CFrame.Angles(0, 0, a + math.pi / 2),
			Color = if k % 4 == 0 then Color3.fromRGB(90, 150, 175) else Color3.fromRGB(112, 108, 104),
			Material = if k % 4 == 0 then Enum.Material.Glass else Enum.Material.Slate,
			Parent = home,
		})
	end
	local homeSwirl = P({
		Name = "Swirl",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 9, 9),
		CFrame = CFrame.new(ringCenter) * CFrame.Angles(0, rad(90), 0),
		Color = Color3.fromRGB(120, 200, 230),
		Material = Enum.Material.ForceField,
		CanCollide = false,
		Parent = home,
	})
	light(homeSwirl, Color3.fromRGB(140, 210, 240), 14, 0.8)
	actionCircle(homePos, 5.5, Color3.fromRGB(120, 200, 235), "Home", nil, home)
	fancySign(homeSwirl, "🏠", "HOME", "Step in to go back", Color3.fromRGB(130, 205, 240), 10, 8)

	-- selling, the shops, this dimension's egg and its obby
	local sellPos = center + Vector3.new(-24, 0, 40)
	local sellPad = buildSellPad(sellPos, 14, 1, d)
	local shopPos = center + Vector3.new(-38, 0, 16)
	local special = Shared.DimensionPickaxe(d)
	buildShopCircle(shopPos, 6.5, dim.Accent, "DimShop", d, Shared.BuildPickaxe(special), "💠", "SPECIAL SHOP", "Only in this dimension!", f)
	local regularShopPos = center + Vector3.new(-40, 0, -2)
	local display = Shared.BuildPickaxe(math.min(#Shared.Pickaxes, 4 + d))
	buildShopCircle(regularShopPos, 6, Color3.fromRGB(225, 165, 70), "Shop", nil, display, "🛒", "SHOP", "Pickaxes • Backpacks • Pets", f)
	local eggId = Shared.DimensionEggId(d)
	local eggPos = center + Vector3.new(40, 0, 10)
	buildEggMachine(eggId, eggPos, f)
	local mythicPos = center + Vector3.new(46, 0, -9)
	buildEggMachine(Shared.DimensionEggId(d, true), mythicPos, f)
	local obbyPos = center + Vector3.new(38, 0, -28)
	buildObbyEntrance(obbyPos, "DIMENSION OBBY", d, f)
	local obby = buildObby(center, obbyPos, d, f)
	local bossCenter = center + Vector3.new(-24, 0, -32)
	local padPos = center + Vector3.new(8, 0, 12)
	Fun.BouncePad(padPos, f)

	decorateArena(dim, center)
	decorShiny = false
	buildParent = previous

	local arena: Arena = {
		Number = d,
		Slot = slot,
		Center = center,
		Folder = f,
		CrystalFolder = crystalFolder,
		Walls = walls,
		SellPad = sellPad,
		Infos = {},
		Reserved = {
			{ pos = center + Vector3.new(0, 0, 45), radius = 8 },
			{ pos = center + Vector3.new(0, 0, 30), radius = 9 },
			{ pos = sellPos, radius = 11 },
			{ pos = homePos, radius = 9 },
			{ pos = shopPos, radius = 10 },
			{ pos = regularShopPos, radius = 10 },
			{ pos = eggPos, radius = 11 },
			{ pos = mythicPos, radius = 11 },
			{ pos = obbyPos, radius = 10 },
			{ pos = padPos, radius = 7 },
			{ pos = bossCenter, radius = 19 },
		},
		DigSpots = {},
		Obby = obby,
		Chests = {},
		Alive = true,
	}
	arena.Boss = createBoss(bossCenter, 15, 0, d, center, f)
	local spec: CrystalSpec = {
		Colors = dim.CrystalColors,
		RockColor = dim.Rock,
		Health = dim.Health,
		Gems = dim.Gems,
		XP = dim.XP,
		Zone = 0,
		Dimension = d,
		Shiny = dim.Shiny,
	}
	local function respawn(info: CrystalInfo): CFrame?
		return arenaSpot(arena, info.Model)
	end
	for _ = 1, Settings.DimensionCrystals do
		local info = buildCrystal(spec, rng:NextNumber() < Settings.GiantChance, crystalFolder, respawn)
		info.Model:PivotTo(arenaSpot(arena, info.Model) :: CFrame)
		info.Model.Parent = crystalFolder
		table.insert(arena.Infos, info)
	end
	-- buried gems on the island
	local function place(): Vector3?
		if not arena.Alive then
			return nil
		end
		for _ = 1, 30 do
			local spot = arenaSpot(arena, nil)
			if spot and digSpotFree(spot.Position) then
				return spot.Position
			end
		end
		return nil
	end
	for _ = 1, Settings.DigSpotsPerDimension do
		local spot = buildDigSpot(0, d, dim.Health * Settings.DigHealth, dim.Gems * Settings.DigGems, dim.XP * 2, dim.CrystalColors[rng:NextInteger(1, #dim.CrystalColors)], place, false)
		if spot then
			table.insert(arena.DigSpots, spot)
		end
	end
	-- a hidden treasure chest
	local chest = Fun.SpawnChest(0, d, Fun.ArenaChestPlace(arena))
	if chest then
		table.insert(arena.Chests, chest)
	end
	arenas[d] = arena
	return arena
end

local function destroyArena(arena: Arena)
	arena.Alive = false
	for _, info in ipairs(arena.Infos) do
		info.Alive = false
		if info.Model.Parent ~= ServerStorage then -- broken ones clean themselves up
			crystals[info.Model] = nil
			info.Model:Destroy()
		end
	end
	for _, spot in ipairs(arena.DigSpots) do
		removeDigSpot(spot)
	end
	if arena.Boss then
		removeBoss(arena.Boss)
	end
	for player, run in pairs(obbyRuns) do
		if run.Course == arena.Obby then
			endObby(player, false)
		end
	end
	removeObby(arena.Obby)
	for _, chest in ipairs(arena.Chests) do
		Fun.RemoveChest(chest)
	end
	eggMachines[Shared.DimensionEggId(arena.Number)] = nil
	eggMachines[Shared.DimensionEggId(arena.Number, true)] = nil
	for k, pad in ipairs(sellPads) do
		if pad.Model == arena.SellPad then
			table.remove(sellPads, k)
			break
		end
	end
	clearMountains(arena.Center)
	arena.SellPad:Destroy()
	arena.Walls:Destroy()
	arena.Folder:Destroy()
	usedSlots[arena.Slot] = nil
	arenas[arena.Number] = nil
end

local lastDimensionTrip: { [Player]: number } = {}

local function enterDimension(player: Player, d: number)
	local data = Data[player]
	local char = player.Character
	if not data or not char then
		return
	end
	if d > Shared.DimensionsUnlocked(data.Level) then
		notify(player, "🔒 Reach level " .. Shared.GetDimension(d).Level .. " to visit dimension " .. d .. "!", "bad")
		return
	end
	local now = os.clock()
	if now - (lastDimensionTrip[player] or -math.huge) < 1 then
		return
	end
	lastDimensionTrip[player] = now
	local arena = arenas[d] or buildArena(d)
	if not arena then
		notify(player, "Too many dimensions are open right now. Try again in a minute!", "bad")
		return
	end
	arena.EmptySince = nil
	endObby(player, false)
	dimensionOf[player] = d
	player:SetAttribute("Dimension", d)
	char:PivotTo(arenaSpawn(arena))
end

Remotes.EnterDimension.OnServerEvent:Connect(function(player, d)
	if type(d) ~= "number" or d ~= math.floor(d) or d < 1 or d > 100000 then
		return
	end
	enterDimension(player, d)
end)

-- Every couple of seconds: close empty islands and catch anyone who fell off
task.spawn(function()
	while true do
		task.wait(2)
		for d, arena in pairs(arenas) do
			local visitors = 0
			for player, playerDimension in pairs(dimensionOf) do
				if playerDimension == d and player.Parent then
					visitors += 1
					local char = player.Character
					local root = char and char:FindFirstChild("HumanoidRootPart")
					if char and root and root:IsA("BasePart") and root.Position.Y < arena.Center.Y - 60 then
						char:PivotTo(arenaSpawn(arena))
					end
				end
			end
			if visitors > 0 then
				arena.EmptySince = nil
			else
				arena.EmptySince = arena.EmptySince or os.clock()
				if os.clock() - (arena.EmptySince :: number) > Settings.DimensionCloseTime then
					destroyArena(arena)
				end
			end
		end
	end
end)

--------------------------------------------------------------------------------
-- SWINGING (you can swing your pickaxe or shovel any time, and everyone near you sees it)
--------------------------------------------------------------------------------
local lastSwingRelay: { [Player]: number } = {}
Remotes.Swing.OnServerEvent:Connect(function(player, kind)
	if kind ~= "swing" and kind ~= "dig" then
		return
	end
	local now = os.clock()
	if now - (lastSwingRelay[player] or 0) < 0.15 then
		return
	end
	lastSwingRelay[player] = now
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) or not char:FindFirstChild(if kind == "dig" then "Shovel" else "Pickaxe") then
		return
	end
	for _, other in ipairs(Players:GetPlayers()) do
		local otherChar = other.Character
		local otherRoot = otherChar and otherChar:FindFirstChild("HumanoidRootPart")
		if other ~= player and otherRoot and otherRoot:IsA("BasePart") and (otherRoot.Position - root.Position).Magnitude < 200 then
			Remotes.Effect:FireClient(other, "swing", player.UserId, kind)
		end
	end
end)
Players.PlayerRemoving:Connect(function(player)
	lastSwingRelay[player] = nil
end)

--------------------------------------------------------------------------------
-- MINING
--------------------------------------------------------------------------------
local lastMine: { [Player]: number } = {}
local lastFullWarning: { [Player]: number } = {}

local function breakCrystal(info: CrystalInfo)
	info.Alive = false
	Remotes.Effect:FireAllClients("break", info.Main.Position, info.Color, info.Giant, info.Golden)
	info.Model.Parent = ServerStorage
	task.delay(Settings.CrystalRespawnTime, function()
		local spot = info.Respawn(info)
		if not spot then -- its dimension island is gone
			crystals[info.Model] = nil
			info.Model:Destroy()
			return
		end
		info.Model:PivotTo(spot)
		info.Health = info.MaxHealth
		setGolden(info, rng:NextNumber() < Settings.GoldenChance)
		updateBar(info)
		info.Alive = true
		info.Model.Parent = info.Folder
		Remotes.Effect:FireAllClients("spawn", info.Main.Position, info.Color, info.Golden, info.Model)
	end)
end

local function minePower(data: PlayerData): number
	return math.max(1, math.floor(Shared.BestPickaxe(data).Power * Shared.LevelPower(data.Level)))
end

--------------------------------------------------------------------------------
-- 🎁 TREASURE CHESTS (hidden in every zone and dimension, press E to open)
--------------------------------------------------------------------------------
do
	type Chest = { Model: Model, Lid: BasePart, LidHome: CFrame, Zone: number, Dimension: number?, Place: () -> Vector3?, Pos: Vector3, Alive: boolean, Removed: boolean }
	local chests: { [Model]: Chest } = Fun.Chests

	local function buildChestModel(): (Model, BasePart, ProximityPrompt)
		local m = Instance.new("Model")
		m.Name = "TreasureChest"
		m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		local wood = Color3.fromRGB(125, 82, 48)
		local gold = Color3.fromRGB(235, 190, 70)
		local base = P({ Name = "Box", Size = Vector3.new(3.4, 1.8, 2.3), CFrame = CFrame.new(0, 0.9, 0), Color = wood, Material = Enum.Material.WoodPlanks, Parent = m })
		m.PrimaryPart = base
		for _, x in ipairs({ -1.25, 1.25 }) do
			P({ Name = "Band", Size = Vector3.new(0.3, 1.86, 2.36), CFrame = CFrame.new(x, 0.9, 0), Color = gold, Material = Enum.Material.Metal, Reflectance = 0.2, Parent = m })
		end
		local lid = P({ Name = "Lid", Size = Vector3.new(3.5, 0.8, 2.4), CFrame = CFrame.new(0, 2.2, 0), Color = wood:Lerp(Color3.new(0, 0, 0), 0.1), Material = Enum.Material.WoodPlanks, Parent = m })
		P({ Name = "Lock", Size = Vector3.new(0.6, 0.7, 0.3), CFrame = CFrame.new(0, 1.65, -1.25), Color = gold, Material = Enum.Material.Metal, Reflectance = 0.3, Parent = m })
		local glow = P({ Name = "Gold", Size = Vector3.new(3, 0.3, 1.9), CFrame = CFrame.new(0, 1.75, 0), Color = gold, Material = Enum.Material.Metal, Reflectance = 0.4, Parent = m })
		light(glow, Color3.fromRGB(255, 215, 120), 10, 0.8)
		particles(glow, { Color = Color3.fromRGB(255, 225, 120), Size = 0.25, Rate = 4, Lifetime = NumberRange.new(1, 2), Speed = NumberRange.new(0.5, 1.5), Spread = Vector2.new(40, 40) })
		local pp = prompt(base, "Open", "🎁 Treasure Chest", 0.6)
		return m, lid, pp
	end

	local function chestFree(pos: Vector3): boolean
		if not digSpotFree(pos) then
			return false
		end
		for _, other in pairs(chests) do
			if other.Alive and (other.Pos - pos).Magnitude < 20 then
				return false
			end
		end
		return true
	end

	local function placeChest(chest: Chest): boolean
		local pos = chest.Place()
		if not pos then
			return false
		end
		chest.Pos = pos
		chest.Lid.CFrame = chest.LidHome
		chest.Model:PivotTo(CFrame.new(pos + Vector3.new(0, 0.9, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
		chest.LidHome = chest.Lid.CFrame
		chest.Alive = true
		chest.Model.Parent = Fun.ChestFolder
		return true
	end

	function Fun.RemoveChest(chest: Chest)
		chest.Removed = true
		chest.Alive = false
		chests[chest.Model] = nil
		chest.Model:Destroy()
	end

	local function openChest(player: Player, chest: Chest)
		local data = Data[player]
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if not (data and chest.Alive and root and root:IsA("BasePart")) or (root.Position - chest.Pos).Magnitude > 18 then
			return
		end
		if chest.Dimension then
			if dimensionOf[player] ~= chest.Dimension then
				return
			end
		elseif chest.Zone > data.Zone then
			notify(player, "🔒 Unlock " .. Shared.Zones[chest.Zone].Name .. " to open this chest!", "bad")
			return
		end
		chest.Alive = false
		local coins = Shared.RewardCoins(data, rng:NextInteger(math.floor(Settings.ChestCrystals / 2), Settings.ChestCrystals))
		data.Coins += coins
		data.ChestsFound += 1
		local text = "🎁 TREASURE! +💰 " .. Format(coins)
		if rng:NextNumber() < 0.35 then
			local shards = rng:NextInteger(1, 3)
			data.Shards += shards
			text ..= "  +💠 " .. shards
		end
		if rng:NextNumber() < 0.12 then
			data.FreeEggs += 1
			text ..= "  +🥚 a free egg"
		end
		notify(player, text, "gold")
		Remotes.Effect:FireClient(player, "chest", chest.Pos, coins)
		sync(player)
		-- the lid swings open...
		local hinge = chest.LidHome * CFrame.new(0, -0.4, 1.2)
		task.spawn(function()
			for k = 1, 8 do
				chest.Lid.CFrame = hinge * CFrame.Angles(rad(9 * k), 0, 0) * CFrame.new(0, 0.4, -1.2)
				task.wait(0.03)
			end
		end)
		-- ...then it vanishes and hides somewhere else later
		task.delay(2.5, function()
			if chest.Removed then
				return
			end
			chest.Model.Parent = ServerStorage
			task.delay(Settings.ChestRespawnTime, function()
				if not chest.Removed and not placeChest(chest) then
					Fun.RemoveChest(chest)
				end
			end)
		end)
	end

	-- place() finds a spot for it (nil = there is no room, or its dimension is gone)
	function Fun.SpawnChest(zone: number, dimension: number?, place: () -> Vector3?): Chest?
		local m, lid, pp = buildChestModel()
		local chest: Chest = { Model = m, Lid = lid, LidHome = lid.CFrame, Zone = zone, Dimension = dimension, Place = place, Pos = Vector3.zero, Alive = false, Removed = false }
		if not placeChest(chest) then
			m:Destroy()
			return nil
		end
		chests[m] = chest
		pp.Triggered:Connect(function(player)
			openChest(player, chest)
		end)
		return chest
	end

	function Fun.SpawnZoneChests()
		for i = 1, #Shared.Zones do
			local function place(): Vector3?
				for _ = 1, 30 do
					local pos = freeSpot(i, 4)
					if pos and chestFree(pos) then
						return onGround(pos)
					end
				end
				return nil
			end
			for _ = 1, Settings.ChestsPerZone do
				Fun.SpawnChest(i, nil, place)
			end
		end
	end

	function Fun.ArenaChestPlace(arena): () -> Vector3?
		return function(): Vector3?
			if not arena.Alive then
				return nil
			end
			for _ = 1, 30 do
				local spot = arenaSpot(arena, nil)
				if spot and chestFree(spot.Position) then
					return spot.Position
				end
			end
			return nil
		end
	end
end

--------------------------------------------------------------------------------
-- 🌠 METEOR SHOWERS (every few minutes a giant meteor crashes down near a player)
--------------------------------------------------------------------------------
do
	local meteorRandom = Random.new()

	-- Where the next meteor lands: near a random player, in a place they can mine
	local function meteorTarget(): (CrystalSpec?, Instance?, CFrame?, string?)
		local list = {}
		for player in pairs(Data) do
			local char = player.Character
			if player.Parent and char and char:FindFirstChild("HumanoidRootPart") then
				table.insert(list, player)
			end
		end
		if #list == 0 then
			return nil
		end
		local player = list[meteorRandom:NextInteger(1, #list)]
		local d = dimensionOf[player]
		local arena = d and arenas[d]
		if d and arena then
			local dim = Shared.GetDimension(d)
			local spec: CrystalSpec = { Colors = dim.CrystalColors, RockColor = dim.Rock, Health = dim.Health, Gems = dim.Gems, XP = dim.XP, Zone = 0, Dimension = d, Shiny = dim.Shiny }
			return spec, arena.CrystalFolder, arenaSpot(arena, nil), dim.Emoji .. " " .. dim.Name
		end
		local root = (player.Character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart
		local zone = math.clamp(Shared.ZoneAt(root.Position.Z), 1, Data[player].Zone)
		return zoneSpec(zone), CrystalFolder, findSpot(zone, nil), Shared.Zones[zone].Emoji .. " " .. Shared.Zones[zone].Name
	end

	function Fun.DropMeteor(): CrystalInfo?
		local spec, crystalFolder, spot, where = meteorTarget()
		if not (spec and crystalFolder and spot) then
			return nil
		end
		local info = buildCrystal(spec, true, crystalFolder, function()
			return nil -- meteors don't grow back
		end)
		local health = spec.Health * Settings.MeteorHealth
		info.Health, info.MaxHealth = health, health
		info.Meteor = true
		setGolden(info, true)
		info.Model.Name = "Meteor"
		info.Model:SetAttribute("Meteor", true)
		-- a burnt crater around it
		for k = 0, 9 do
			local a = k / 10 * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
			P({
				Name = "CraterRock",
				Size = Vector3.new(rng:NextNumber(2, 3.4), rng:NextNumber(0.8, 1.6), rng:NextNumber(1.6, 2.6)),
				CFrame = CFrame.new(math.cos(a) * 6.2, 0.3, math.sin(a) * 6.2) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), -a, rng:NextNumber(-0.3, 0.3)),
				Color = Color3.fromRGB(45, 38, 36),
				Material = Enum.Material.Basalt,
				Parent = info.Model,
			})
		end
		local scorch = P({ Name = "Scorch", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 14, 14), CFrame = CFrame.new(0, 0.08, 0) * CFrame.Angles(0, 0, rad(90)), Color = Color3.fromRGB(35, 30, 30), Material = Enum.Material.Basalt, CanCollide = false, Parent = info.Model })
		particles(scorch, { Texture = "rbxasset://textures/particles/fire_main.dds", Color = Color3.fromRGB(255, 140, 50), Size = 1.2, Rate = 8, Lifetime = NumberRange.new(0.6, 1.2), Speed = NumberRange.new(2, 4), Spread = Vector2.new(15, 15), Direction = Enum.NormalId.Right })
		info.Model:PivotTo(spot)
		updateBar(info)
		Remotes.Effect:FireAllClients("meteor", spot.Position, where, spec.Dimension)
		-- it lands after a short fall...
		task.delay(1.6, function()
			if crystals[info.Model] == info then
				info.Model.Parent = crystalFolder
			end
		end)
		-- ...and fades away if nobody mines it
		task.delay(Settings.MeteorLifetime, function()
			if crystals[info.Model] == info and info.Alive then
				info.Alive = false
				crystals[info.Model] = nil
				Remotes.Effect:FireAllClients("meteorgone", spot.Position)
				info.Model:Destroy()
			end
		end)
		return info
	end

	-- Breaking a meteor pays coins right away (so a full backpack doesn't matter)
	function Fun.MeteorBroken(player: Player, data: PlayerData, info: CrystalInfo)
		local coins = Shared.RewardCoins(data, Settings.MeteorRewardCrystals)
		data.Coins += coins
		data.Shards += Settings.MeteorShards
		data.MeteorsBroken += 1
		local pos = info.Main.Position
		breakCrystal(info)
		Remotes.Effect:FireClient(player, "meteorwin", pos, coins)
		addXP(player, data, info.XP * 10)
		questProgress(player, data, "mine", 1)
		for _, other in ipairs(Players:GetPlayers()) do
			notify(other, "🌠 " .. player.DisplayName .. " smashed the meteor! +💰 " .. Format(coins) .. " +💠 " .. Settings.MeteorShards, "gold")
		end
		sync(player)
	end

	task.spawn(function()
		task.wait(Settings.MeteorEvery / 2)
		while true do
			Fun.DropMeteor()
			task.wait(math.max(5, Settings.MeteorEvery * meteorRandom:NextNumber(0.75, 1.25)))
		end
	end)
end

Remotes.Mine.OnServerEvent:Connect(function(player, crystal)
	local data = Data[player]
	if not data or typeof(crystal) ~= "Instance" or not crystal:IsA("Model") then
		return
	end
	local now = os.clock()
	if now - (lastMine[player] or 0) < Settings.MineCooldown * 0.8 then
		return
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (char and root and root:IsA("BasePart") and hum and hum.Health > 0) then
		return
	end
	-- you need your pickaxe in your hand
	if not char:FindFirstChild("Pickaxe") then
		return
	end
	-- hitting a boss
	local boss = bosses[crystal]
	if boss then
		local allowed = if boss.Dimension then boss.Dimension <= Shared.DimensionsUnlocked(data.Level) else boss.Zone <= data.Zone
		if boss.Alive and allowed and (root.Position - boss.Pos).Magnitude <= Settings.MineRange + 10 then
			lastMine[player] = now
			hitBoss(player, boss, minePower(data))
		end
		return
	end
	local info = crystals[crystal]
	if not info or not info.Alive or crystal.Parent ~= info.Folder then
		return
	end
	if (root.Position - crystal:GetPivot().Position).Magnitude > Settings.MineRange + info.Radius + 6 then
		return
	end
	if info.Zone > data.Zone then
		return
	end
	if info.Dimension and info.Dimension > Shared.DimensionsUnlocked(data.Level) then
		return
	end
	-- a meteor: everyone hits the same one, and it pays coins (so your backpack can be full)
	if info.Meteor then
		lastMine[player] = now
		local power = minePower(data)
		info.Health -= power
		Remotes.Effect:FireClient(player, "hit", info.Main.Position, power, crystal)
		if info.Health <= 0 then
			Fun.MeteorBroken(player, data, info)
		else
			updateBar(info)
		end
		return
	end
	local capacity = Shared.BestBackpack(data).Capacity
	if data.Gems >= capacity then
		if now - (lastFullWarning[player] or 0) > 1 then
			lastFullWarning[player] = now
			Remotes.Effect:FireClient(player, "full")
		end
		return
	end
	lastMine[player] = now

	local power = minePower(data)
	info.Health -= power
	Remotes.Effect:FireClient(player, "hit", info.Main.Position, power, crystal)

	if info.Health <= 0 then
		local stats = gadgetStats(data)
		local gems = info.Gems * Shared.GemMultiplier(data.Pets) * stats.Gems * (if data.GemBoostUntil > os.time() then 2 else 1)
		local lucky = stats.Lucky > 0 and rng:NextNumber() < stats.Lucky
		if lucky then
			gems *= 10
		end
		local added = math.min(math.floor(gems), capacity - data.Gems)
		local xp = info.XP
		local golden = info.Golden
		local color = info.Color
		data.Gems += added
		data.TotalGems += added
		breakCrystal(info)
		Remotes.Effect:FireClient(player, "reward", info.Main.Position, added, xp, golden, color)
		addXP(player, data, xp)
		questProgress(player, data, "mine", 1)
		if info.Giant then
			questProgress(player, data, "giant", 1)
		end
		if golden then
			data.GoldenMined += 1
			questProgress(player, data, "golden", 1)
			notify(player, "✨ GOLDEN CRYSTAL! +" .. Format(added) .. " gems!", "gold")
		end
		if lucky then
			notify(player, "🍀 LUCKY! 10x gems: +" .. Format(added) .. "!", "good")
		end
		sync(player)
	else
		updateBar(info)
	end
end)

--------------------------------------------------------------------------------
-- SKY OBBIES (running them)
--------------------------------------------------------------------------------
local function obbySpawn(run: ObbyRun): CFrame
	local checkpoint = run.Course.Checkpoints[run.Checkpoint]
	return if checkpoint then checkpoint.Spawn else run.Course.Start
end

-- Seconds until an obby pays out again (d = nil is the obby at the spawn)
local function obbyWaitFor(player: Player, data: PlayerData, d: number?): number
	local last = if d then (dimObbyLast[player] or {})[d] or 0 else data.ObbyLast
	return math.max(0, last + Settings.ObbyCooldown - os.time())
end

startObby = function(player: Player, course: ObbyCourse)
	local char = player.Character
	if not Data[player] or not char then
		return
	end
	endObby(player, false)
	if not course.Dimension then
		leaveDimension(player)
	end
	obbyRuns[player] = { Course = course, Started = os.clock(), Checkpoint = 0 }
	player:SetAttribute("ObbyStart", Workspace:GetServerTimeNow())
	applyMovement(player, true) -- no gadgets in the obby, that would be cheating!
	char:PivotTo(course.Start)
	Remotes.Effect:FireClient(player, "obbystart", course.Dimension)
end

endObby = function(player: Player, finished: boolean)
	local run = obbyRuns[player]
	if not run then
		return
	end
	obbyRuns[player] = nil
	lastObbyEnd[player] = os.clock()
	player:SetAttribute("ObbyStart", nil)
	applyMovement(player)
	local data = Data[player]
	if not finished or not data then
		return
	end
	local course = run.Course
	local d = course.Dimension
	local time = math.floor((os.clock() - run.Started) * 10) / 10
	local record = data.ObbyBest == 0 or time < data.ObbyBest
	if record then
		data.ObbyBest = time
	end
	local wait = obbyWaitFor(player, data, d)
	local coins = 0
	if wait <= 0 then
		if d then
			-- dimension obbies pay more, and more the further the dimension is
			coins = Shared.DimensionObbyReward(data, d)
			local timers = dimObbyLast[player] or {}
			dimObbyLast[player] = timers
			timers[d] = os.time()
		else
			coins = Shared.ObbyReward(data)
			data.ObbyLast = os.time()
		end
		data.Coins += coins
	end
	Remotes.Effect:FireClient(player, "obby", time, coins, record, wait)
	questProgress(player, data, "obby", 1)
	sync(player)
	-- after a little party at the finish, back down to the ground
	local char = player.Character
	task.delay(3, function()
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if not (player.Parent and player.Character == char and not obbyRuns[player] and root and root:IsA("BasePart") and root.Position.Y > course.FallY) then
			return
		end
		local arena = d and arenas[d]
		if arena and dimensionOf[player] == d then
			char:PivotTo(arenaSpawn(arena))
			Remotes.Effect:FireClient(player, "teleported")
		else
			teleport(player, 0)
		end
	end)
end

-- Checks every frame where obby players are (falling, lava, checkpoints, finish)
RunService.Heartbeat:Connect(function()
	for player, run in pairs(obbyRuns) do
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if not (char and root and root:IsA("BasePart")) then
			continue
		end
		local course = run.Course
		local pos = root.Position
		if pos.Y < course.FallY then
			char:PivotTo(obbySpawn(run))
			Remotes.Effect:FireClient(player, "obbyfall")
			continue
		end
		local burned = false
		for _, lava in ipairs(course.Lava) do
			local rel = lava.CFrame:PointToObjectSpace(pos)
			if math.abs(rel.X) < lava.Size.X / 2 + 0.6 and math.abs(rel.Z) < lava.Size.Z / 2 + 0.6 and rel.Y > 0 and rel.Y < lava.Size.Y / 2 + 3.4 then
				burned = true
				break
			end
		end
		if burned then
			char:PivotTo(obbySpawn(run))
			Remotes.Effect:FireClient(player, "obbylava")
			continue
		end
		for k, checkpoint in ipairs(course.Checkpoints) do
			if k > run.Checkpoint then
				local rel = checkpoint.Part.CFrame:PointToObjectSpace(pos)
				if math.abs(rel.X) < 6.5 and math.abs(rel.Z) < 6.5 and rel.Y > 0 and rel.Y < 7 then
					run.Checkpoint = k
					Remotes.Effect:FireClient(player, "checkpoint", k, #course.Checkpoints)
				end
			end
		end
		local finish = course.Finish
		if finish then
			local flat = Vector3.new(pos.X - finish.Position.X, 0, pos.Z - finish.Position.Z)
			local up = pos.Y - finish.Position.Y
			if flat.Magnitude < 5 and up > 0 and up < 7 then
				endObby(player, true)
			end
		end
	end
end)

--------------------------------------------------------------------------------
-- SELLING (stand on a sell pad)
--------------------------------------------------------------------------------
local lastSell: { [Player]: number } = {}
local lastGoSell: { [Player]: number } = {}
local lastLockedPad: { [Player]: number } = {}

local function sellAll(player: Player, pad: SellPad)
	local data = Data[player]
	if not data or data.Gems <= 0 then
		return
	end
	local now = os.clock()
	if now - (lastSell[player] or 0) < 0.6 then
		return
	end
	lastSell[player] = now
	-- the further the dimension, the more every gem is worth
	local bonus = Shared.DimensionSellBonus(pad.Dimension)
	local coins = math.floor(data.Gems * Shared.CoinMultiplier(data.Rebirths) * bonus)
	data.Coins += coins
	data.Gems = 0
	Remotes.Effect:FireClient(player, "sold", coins, bonus)
	questProgress(player, data, "sell", 1)
	sync(player)
end

-- You can only sell where you are allowed to be
local function canUsePad(player: Player, data: PlayerData, pad: SellPad): boolean
	if pad.Dimension then
		return dimensionOf[player] == pad.Dimension
	end
	return data.Zone >= pad.Zone
end

local function padUnder(pos: Vector3): SellPad?
	for _, pad in ipairs(sellPads) do
		if pad.Pad.Parent then
			local center = pad.Pad.Position
			local flat = Vector3.new(pos.X - center.X, 0, pos.Z - center.Z)
			if flat.Magnitude <= pad.Radius + 1.5 and pos.Y > center.Y - 2 and pos.Y < center.Y + 9 then
				return pad
			end
		end
	end
	return nil
end

-- Every moment: anyone standing on a sell pad sells their gems
task.spawn(function()
	while true do
		task.wait(0.15)
		for player, data in pairs(Data) do
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			-- an obby circle (at the spawn or in a dimension) starts that obby
			if root and root:IsA("BasePart") and not obbyRuns[player] and os.clock() - (lastObbyEnd[player] or -math.huge) > 3 then
				for _, course in ipairs(obbyCourses) do
					local flat = Vector3.new(root.Position.X - course.Circle.X, 0, root.Position.Z - course.Circle.Z)
					if flat.Magnitude < 6 and math.abs(root.Position.Y - course.Circle.Y) < 8 and (course.Dimension == nil or dimensionOf[player] == course.Dimension) then
						startObby(player, course)
						break
					end
				end
			end
			if data.Gems > 0 and root and root:IsA("BasePart") then
				local pad = padUnder(root.Position)
				if pad then
					if canUsePad(player, data, pad) then
						sellAll(player, pad)
					elseif os.clock() - (lastLockedPad[player] or 0) > 4 then
						lastLockedPad[player] = os.clock()
						notify(player, "🔒 Unlock this zone first to sell here!", "bad")
					end
				end
			end
		end
	end
end)

-- The "Teleport to sell" button takes you to the closest sell pad you can use
Remotes.GoSell.OnServerEvent:Connect(function(player)
	local data = Data[player]
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not (data and char and root and root:IsA("BasePart")) then
		return
	end
	if os.clock() - (lastGoSell[player] or -math.huge) < 2 then
		return
	end
	lastGoSell[player] = os.clock()
	local best: SellPad? = nil
	local bestDistance = math.huge
	for _, pad in ipairs(sellPads) do
		if pad.Pad.Parent and canUsePad(player, data, pad) then
			local distance = (pad.Pad.Position - root.Position).Magnitude
			if distance < bestDistance then
				best, bestDistance = pad, distance
			end
		end
	end
	if best then
		endObby(player, false)
		char:PivotTo(CFrame.new(best.Pad.Position + Vector3.new(0, 3.5, 0)))
		Remotes.Effect:FireClient(player, "teleported")
	end
end)

--------------------------------------------------------------------------------
-- SHOP
--------------------------------------------------------------------------------
local function spend(player: Player, data: PlayerData, price: number): boolean
	if data.Coins < price then
		notify(player, "Not enough coins! You need 💰 " .. Format(price - data.Coins) .. " more.", "bad")
		return false
	end
	data.Coins -= price
	return true
end

unlockZone = function(player: Player, i: number)
	local data = Data[player]
	local zone = Shared.Zones[i]
	if not data or not zone or i < 2 then
		return
	end
	if data.Zone >= i then
		notify(player, zone.Name .. " is already unlocked!", "info")
		return
	end
	if data.Zone < i - 1 then
		notify(player, "Unlock " .. Shared.Zones[i - 1].Name .. " first!", "bad")
		return
	end
	if not spend(player, data, zone.Price) then
		return
	end
	data.Zone = i
	notify(player, "🔓 " .. zone.Name .. " unlocked!", "good")
	Remotes.Effect:FireClient(player, "unlock", i)
	addXP(player, data, 0) -- a full XP bar levels up now
	sync(player)
end

Remotes.Buy.OnServerEvent:Connect(function(player, category, index)
	local data = Data[player]
	if not data or type(category) ~= "string" or type(index) ~= "number" or index ~= math.floor(index) then
		return
	end
	if category == "Pickaxe" then
		local def = Shared.Pickaxes[index]
		if not def then
			return
		end
		if index <= data.Pickaxe then
			notify(player, "You already have a pickaxe this good!", "info")
			return
		end
		if not spend(player, data, def.Price) then
			return
		end
		data.Pickaxe = index
		givePickaxe(player)
		notify(player, "⛏️ You got the " .. def.Name .. "!", "good")
	elseif category == "Backpack" then
		local def = Shared.Backpacks[index]
		if not def then
			return
		end
		if index <= data.Backpack then
			notify(player, "You already have a backpack this big!", "info")
			return
		end
		if not spend(player, data, def.Price) then
			return
		end
		data.Backpack = index
		updateBackpack(player)
		notify(player, "🎒 You got the " .. def.Name .. "!", "good")
	elseif category == "Pet" then
		local def = Shared.Pets[index]
		if not def or not def.Price then -- egg pets can't be bought
			return
		end
		if (data.Pets[index] or 0) > 0 then
			notify(player, "You already own " .. def.Name .. "!", "info")
			return
		end
		if not spend(player, data, def.Price) then
			return
		end
		data.Pets[index] = 1
		refreshPets(player)
		notify(player, "🐾 " .. def.Name .. " joined your team!", "good")
	elseif category == "Gadget" then
		local def = Shared.Gadgets[index]
		if not def then
			return
		end
		if table.find(data.Gadgets, index) then
			notify(player, "You already have the " .. def.Name .. "!", "info")
			return
		end
		if not spend(player, data, def.Price) then
			return
		end
		table.insert(data.Gadgets, index)
		applyMovement(player, obbyRuns[player] ~= nil)
		notify(player, "⚡ You got the " .. def.Name .. "! " .. Shared.GadgetText(def), "good")
	elseif category == "DimPickaxe" or category == "DimBackpack" then
		-- special things can only be bought in their own dimension
		if dimensionOf[player] ~= index or index > Shared.DimensionsUnlocked(data.Level) then
			notify(player, "You can only buy this in dimension " .. index .. "!", "bad")
			return
		end
		if category == "DimPickaxe" then
			local def = Shared.DimensionPickaxe(index)
			if def.Power <= Shared.BestPickaxe(data).Power then
				notify(player, "You already have a pickaxe this good!", "info")
				return
			end
			if data.Shards < def.Shards then
				notify(player, "You need 💠 " .. (def.Shards - data.Shards) .. " more Boss Shards! Beat bosses to get them.", "bad")
				return
			end
			data.Shards -= def.Shards
			data.DimPickaxe = index
			givePickaxe(player)
			notify(player, "⛏️ You got the " .. def.Name .. "!", "gold")
		else
			local def = Shared.DimensionBackpack(index)
			if def.Capacity <= Shared.BestBackpack(data).Capacity then
				notify(player, "You already have a backpack this big!", "info")
				return
			end
			if not spend(player, data, def.Price) then
				return
			end
			data.DimBackpack = index
			updateBackpack(player)
			notify(player, "🎒 You got the " .. def.Name .. "!", "gold")
		end
	elseif category == "Zone" then
		unlockZone(player, index)
		return
	else
		return
	end
	Remotes.Effect:FireClient(player, "bought", category, index)
	sync(player)
end)

-- Turn a gadget on or off
Remotes.GadgetToggle.OnServerEvent:Connect(function(player, index)
	local data = Data[player]
	if not data or type(index) ~= "number" or not table.find(data.Gadgets, index) then
		return
	end
	local k = table.find(data.GadgetsOff, index)
	if k then
		table.remove(data.GadgetsOff, k)
	else
		table.insert(data.GadgetsOff, index)
	end
	applyMovement(player, obbyRuns[player] ~= nil)
	sync(player)
end)

--------------------------------------------------------------------------------
-- HATCHING EGGS
--------------------------------------------------------------------------------
local hatchRandom = Random.new()
local lastHatch: { [Player]: number } = {}

hatchEgg = function(player: Player, eggIndex: number, amount: number)
	local data = Data[player]
	local egg = Shared.GetEgg(eggIndex)
	if not data or not egg then
		return
	end
	if egg.Zone and data.Zone < egg.Zone then
		notify(player, "🔒 Unlock " .. Shared.Zones[egg.Zone].Name .. " first!", "bad")
		return
	end
	if egg.Dimension and egg.Dimension > Shared.DimensionsUnlocked(data.Level) then
		return
	end
	local now = os.clock()
	if now - (lastHatch[player] or -math.huge) < Settings.HatchCooldown then
		return -- still hatching the last egg
	end
	local free = amount == 1 and data.FreeEggs > 0
	if free then
		data.FreeEggs -= 1
	elseif not spend(player, data, egg.Price * amount) then
		return
	end
	lastHatch[player] = now
	if free then
		notify(player, "🎁 You used a FREE egg!", "good")
	end

	local results = {}
	for _ = 1, amount do
		local index = Shared.RollEgg(eggIndex, hatchRandom)
		local isNew = (data.Pets[index] or 0) == 0
		data.Pets[index] = (data.Pets[index] or 0) + 1
		table.insert(results, { Pet = index, New = isNew })
	end
	data.Hatched += amount
	questProgress(player, data, "hatch", amount)
	sync(player)
	Remotes.Effect:FireClient(player, "hatch", eggIndex, results)

	-- new pets start following you after the hatch animation
	task.delay(2.2, function()
		if Data[player] == data then
			refreshPets(player)
		end
	end)

	-- tell everyone in the server about super rare pets
	for _, result in ipairs(results) do
		local def = Shared.GetPet(result.Pet)
		if Shared.RarityRank(def.Rarity) >= Shared.RarityRank("Legendary") then
			for _, other in ipairs(Players:GetPlayers()) do
				notify(other, "🎉 " .. player.DisplayName .. " hatched a " .. string.upper(def.Rarity) .. " " .. def.Name .. "!", "gold")
			end
		end
	end
end

-- The egg window asks to hatch (you have to stand at the egg machine)
Remotes.Hatch.OnServerEvent:Connect(function(player, eggId, amount)
	if type(eggId) ~= "number" or (amount ~= 1 and amount ~= 3) then
		return
	end
	local pos = eggMachines[eggId]
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not pos or not (root and root:IsA("BasePart")) or (root.Position - pos).Magnitude > 18 then
		return
	end
	hatchEgg(player, eggId, amount)
end)

--------------------------------------------------------------------------------
-- 🎡 LUCKY WHEEL (a free spin every few minutes)
--------------------------------------------------------------------------------
do
	local wheelRandom = Random.new()
	Remotes.Spin.OnServerEvent:Connect(function(player)
		local data = Data[player]
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if not (data and root and root:IsA("BasePart")) or (root.Position - HUB.Wheel).Magnitude > 16 then
			return
		end
		local wait = data.WheelLast + Settings.WheelCooldown - os.time()
		if wait > 0 then
			notify(player, "🎡 The wheel is ready again in " .. math.ceil(wait / 60) .. " min.", "info")
			return
		end
		data.WheelLast = os.time()
		-- pick a prize (Chance = how likely)
		local total = 0
		for _, prize in ipairs(Shared.WheelPrizes) do
			total += prize.Chance
		end
		local roll = wheelRandom:NextNumber(0, total)
		local index = #Shared.WheelPrizes
		for k, prize in ipairs(Shared.WheelPrizes) do
			roll -= prize.Chance
			if roll <= 0 then
				index = k
				break
			end
		end
		local prize = Shared.WheelPrizes[index]
		local text = prize.Text
		if prize.Crystals then
			local coins = Shared.RewardCoins(data, prize.Crystals)
			data.Coins += coins
			text = "💰 +" .. Format(coins) .. " coins"
		elseif prize.Eggs then
			data.FreeEggs += prize.Eggs
			text = "🥚 +" .. prize.Eggs .. " free " .. (if prize.Eggs == 1 then "egg" else "eggs")
		elseif prize.Shards then
			local shards = prize.Shards + data.Zone - 1
			data.Shards += shards
			text = "💠 +" .. shards .. " Boss Shards"
		elseif prize.XP then
			local xp = math.max(1, math.floor(Shared.XPNeeded(data.Level) * prize.XP))
			addXP(player, data, xp)
			text = "⭐ +" .. Format(xp) .. " XP"
		elseif prize.Boost then
			data.GemBoostUntil = math.max(data.GemBoostUntil, os.time()) + prize.Boost
			text = "⚡ 2x gems for " .. math.floor(prize.Boost / 60) .. " minutes"
		end
		Remotes.Effect:FireClient(player, "wheel", index, text)
		sync(player)
	end)
end

--------------------------------------------------------------------------------
-- 🤝 TRADING (swap pets and coins with your friends)
--   1. ask someone to trade   2. they say yes   3. both put pets and coins in
--   4. both press READY       5. after a short countdown everything swaps
--------------------------------------------------------------------------------
do
	type Offer = { Pets: { [number]: number }, Coins: number, Ready: boolean }
	type Trade = { A: Player, B: Player, Offers: { [Player]: Offer }, Token: number, Counting: boolean, Done: boolean }
	local trades: { [Player]: Trade } = {}
	local requests: { [Player]: { [Player]: number } } = {} -- requests[to][from] = when it was sent
	local lastRequest: { [Player]: number } = {}

	local function partnerOf(trade: Trade, player: Player): Player
		return if trade.A == player then trade.B else trade.A
	end

	-- What a player's screen needs to show about one side of the trade
	local function offerInfo(offer: Offer)
		local pets = {}
		for index, count in pairs(offer.Pets) do
			if count > 0 then
				table.insert(pets, { Index = index, Count = count })
			end
		end
		table.sort(pets, function(a, b)
			return a.Index < b.Index
		end)
		return { Pets = pets, Coins = offer.Coins, Ready = offer.Ready }
	end

	local function sendTrade(trade: Trade)
		for _, p in ipairs({ trade.A, trade.B }) do
			local partner = partnerOf(trade, p)
			Remotes.Trade:FireClient(p, "update", {
				Partner = partner.UserId,
				PartnerName = partner.DisplayName,
				Mine = offerInfo(trade.Offers[p]),
				Theirs = offerInfo(trade.Offers[partner]),
				Counting = trade.Counting,
				Countdown = Settings.TradeCountdown,
			})
		end
	end

	local function closeTrade(trade: Trade, reason: string)
		trade.Done = true
		trade.Token += 1
		for _, p in ipairs({ trade.A, trade.B }) do
			if trades[p] == trade then
				trades[p] = nil
			end
			if p.Parent then
				Remotes.Trade:FireClient(p, "closed", reason)
			end
		end
	end

	-- Something changed: nobody is ready anymore
	local function unready(trade: Trade)
		trade.Token += 1
		trade.Counting = false
		for _, offer in pairs(trade.Offers) do
			offer.Ready = false
		end
	end

	-- Swap everything (checked again first, in case something changed)
	local function finishTrade(trade: Trade)
		local a, b = trade.A, trade.B
		if not (Data[a] and Data[b] and a.Parent and b.Parent) then
			closeTrade(trade, "Someone left, so the trade stopped.")
			return
		end
		for _, p in ipairs({ a, b }) do
			local data, offer = Data[p], trade.Offers[p]
			if offer.Coins > data.Coins then
				closeTrade(trade, p.DisplayName .. " doesn't have enough coins anymore.")
				return
			end
			for index, count in pairs(offer.Pets) do
				if (data.Pets[index] or 0) < count then
					closeTrade(trade, p.DisplayName .. " doesn't have all those pets anymore.")
					return
				end
			end
		end
		local function give(from: Player, to: Player)
			local fromData, toData, offer = Data[from], Data[to], trade.Offers[from]
			fromData.Coins -= offer.Coins
			toData.Coins += offer.Coins
			for index, count in pairs(offer.Pets) do
				local left = (fromData.Pets[index] or 0) - count
				fromData.Pets[index] = if left > 0 then left else nil
				toData.Pets[index] = (toData.Pets[index] or 0) + count
			end
		end
		give(a, b)
		give(b, a)
		closeTrade(trade, "done")
		for _, p in ipairs({ a, b }) do
			Data[p].Trades += 1
			refreshPets(p)
			sync(p)
			notify(p, "🤝 Trade with " .. partnerOf(trade, p).DisplayName .. " is done!", "good")
			task.spawn(saveData, p) -- save right away
		end
	end

	local function newOffer(): Offer
		return { Pets = {}, Coins = 0, Ready = false }
	end

	Remotes.Trade.OnServerEvent:Connect(function(player, action, a, b)
		local data = Data[player]
		if not data or type(action) ~= "string" then
			return
		end
		local trade = trades[player]
		if action == "request" then
			local target = if type(a) == "number" then Players:GetPlayerByUserId(a) else nil
			if not target or target == player or not Data[target] then
				return
			end
			if os.clock() - (lastRequest[player] or -math.huge) < 2 then
				return
			end
			lastRequest[player] = os.clock()
			if trade or trades[target] then
				notify(player, "🤝 " .. target.DisplayName .. " is busy trading right now.", "info")
				return
			end
			if Settings.TradeFriendsOnly then
				local ok, friends = pcall(function()
					return player:IsFriendsWith(target.UserId)
				end)
				if not (ok and friends) then
					notify(player, "🤝 You can only trade with your friends.", "bad")
					return
				end
			end
			requests[target] = requests[target] or {}
			requests[target][player] = os.clock()
			Remotes.Trade:FireClient(target, "request", player.UserId, player.DisplayName)
			notify(player, "🤝 Trade request sent to " .. target.DisplayName .. "!", "info")
		elseif action == "respond" then
			local from = if type(a) == "number" then Players:GetPlayerByUserId(a) else nil
			local pending = requests[player]
			local sentAt = if from and pending then pending[from] else nil
			if not (from and pending and sentAt) then
				return
			end
			pending[from] = nil
			if os.clock() - sentAt > Settings.TradeRequestTime then
				notify(player, "🤝 That trade request ran out. Ask again!", "info")
				return
			end
			if b ~= true then
				notify(from, "🤝 " .. player.DisplayName .. " said no thanks.", "info")
				return
			end
			if trade or trades[from] or not Data[from] then
				notify(player, "🤝 " .. from.DisplayName .. " is busy right now.", "info")
				return
			end
			local started: Trade = { A = from, B = player, Offers = { [from] = newOffer(), [player] = newOffer() }, Token = 0, Counting = false, Done = false }
			trades[from] = started
			trades[player] = started
			sendTrade(started)
		elseif trade and not trade.Done then
			local offer = trade.Offers[player]
			if action == "pet" then
				if type(a) ~= "number" or (b ~= 1 and b ~= -1) then
					return
				end
				local current = offer.Pets[a] or 0
				local count = math.clamp(current + b, 0, data.Pets[a] or 0)
				if count == current then
					return
				end
				offer.Pets[a] = if count > 0 then count else nil
				unready(trade)
				sendTrade(trade)
			elseif action == "coins" then
				if type(a) ~= "number" or a ~= a then
					return
				end
				offer.Coins = math.clamp(math.floor(a), 0, data.Coins)
				unready(trade)
				sendTrade(trade)
			elseif action == "ready" then
				offer.Ready = a == true
				local partner = trade.Offers[partnerOf(trade, player)]
				trade.Token += 1
				trade.Counting = offer.Ready and partner.Ready
				sendTrade(trade)
				if trade.Counting then
					local token = trade.Token
					task.delay(Settings.TradeCountdown, function()
						if trade.Token == token and not trade.Done then
							finishTrade(trade)
						end
					end)
				end
			elseif action == "cancel" then
				closeTrade(trade, player.DisplayName .. " stopped the trade.")
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local trade = trades[player]
		if trade then
			closeTrade(trade, player.DisplayName .. " left the game.")
		end
		requests[player] = nil
		lastRequest[player] = nil
		for _, list in pairs(requests) do
			list[player] = nil
		end
	end)
end

--------------------------------------------------------------------------------
-- REBIRTH
--------------------------------------------------------------------------------
Remotes.Rebirth.OnServerEvent:Connect(function(player)
	local data = Data[player]
	if not data then
		return
	end
	local cost = Shared.RebirthCost(data.Rebirths)
	if data.Coins < cost then
		notify(player, "You need 💰 " .. Format(cost) .. " coins to rebirth!", "bad")
		return
	end
	data.Rebirths += 1
	data.Coins = 0
	data.Gems = 0
	data.Pickaxe = 1
	data.Backpack = 1
	data.Zone = 1
	data.DimPickaxe = 0
	data.DimBackpack = 0
	givePickaxe(player)
	updateBackpack(player)
	teleport(player, 0)
	notify(player, "♻️ REBIRTH! You now earn x" .. Shared.CoinMultiplier(data.Rebirths) .. " coins!", "gold")
	Remotes.Effect:FireAllClients("rebirth", player.UserId)
	sync(player)
	task.spawn(saveData, player)
end)

--------------------------------------------------------------------------------
-- TELEPORT
--------------------------------------------------------------------------------
local lastTeleport: { [Player]: number } = {}

Remotes.Teleport.OnServerEvent:Connect(function(player, zoneIndex)
	local data = Data[player]
	if not data or type(zoneIndex) ~= "number" then
		return
	end
	if zoneIndex ~= 0 and (zoneIndex < 1 or zoneIndex > data.Zone or not Shared.Zones[zoneIndex]) then
		return
	end
	if os.clock() - (lastTeleport[player] or 0) < 1 then
		return
	end
	lastTeleport[player] = os.clock()
	teleport(player, zoneIndex)
end)

-- The client asks for its data when it is ready
Remotes.Sync.OnServerEvent:Connect(function(player)
	sync(player)
end)

--------------------------------------------------------------------------------
-- PLAYERS JOINING AND LEAVING
--------------------------------------------------------------------------------
local setUpCharacters: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function onCharacter(player: Player, char: Model)
	if setUpCharacters[char] then
		return
	end
	setUpCharacters[char] = true
	endObby(player, false)
	leaveDimension(player) -- respawning always puts you back at the spawn
	local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
	if not hum then
		return
	end
	hum.WalkSpeed = Settings.WalkSpeed
	hum.UseJumpPower = false
	hum.JumpHeight = Settings.JumpHeight
	local started = os.clock()
	while (not Data[player] or not char:IsDescendantOf(Workspace)) and player.Parent and os.clock() - started < 20 do
		task.wait(0.1)
	end
	if not Data[player] or player.Character ~= char then
		return
	end
	if hum.RigType == Enum.HumanoidRigType.R15 then
		char:WaitForChild("UpperTorso", 5)
	else
		char:WaitForChild("Torso", 5)
	end
	givePickaxe(player, true)
	giveShovel(player)
	applyMovement(player)
	updateBackpack(player)
	refreshPets(player)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(char)
		onCharacter(player, char)
	end)

	local data, loaded = loadData(player)
	if not player.Parent then
		return
	end
	Data[player] = data
	CanSave[player] = loaded
	sessionStart[player] = os.clock()
	giftsClaimed[player] = {}

	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Parent = stats
	local level = Instance.new("IntValue")
	level.Name = "Level"
	level.Parent = stats
	local rebirths = Instance.new("IntValue")
	rebirths.Name = "Rebirths"
	rebirths.Parent = stats
	stats.Parent = player

	sync(player)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
end

Players.PlayerRemoving:Connect(function(player)
	obbyRuns[player] = nil
	saveData(player)
	for _, pet in ipairs(PetFolder:GetChildren()) do
		if pet:GetAttribute("Owner") == player.UserId then
			pet:Destroy()
		end
	end
	Data[player] = nil
	CanSave[player] = nil
	lastMine[player] = nil
	lastSell[player] = nil
	lastTeleport[player] = nil
	lastFullWarning[player] = nil
	lastHatch[player] = nil
	lastDimensionTrip[player] = nil
	dimensionOf[player] = nil
	lastGoSell[player] = nil
	lastLockedPad[player] = nil
	lastDig[player] = nil
	lastObbyEnd[player] = nil
	dimObbyLast[player] = nil
	lastLevelLockNotice[player] = nil
	boardSaved[player] = nil
	for _, boss in pairs(bosses) do
		boss.Hitters[player] = nil
	end
	sessionStart[player] = nil
	giftsClaimed[player] = nil
end)

game:BindToClose(function()
	local running = 0
	for _, player in ipairs(Players:GetPlayers()) do
		running += 1
		task.spawn(function()
			saveData(player)
			running -= 1
		end)
	end
	local started = os.clock()
	while running > 0 and os.clock() - started < 25 do
		task.wait(0.2)
	end
end)

-- Autosave every minute
task.spawn(function()
	while true do
		task.wait(60)
		for _, player in ipairs(Players:GetPlayers()) do
			task.spawn(saveData, player)
		end
	end
end)

-- Leaderboards: the best of all servers (every minute) mixed with everyone here right now
do
	local nameCache: { [number]: string } = {}
	local function nameOf(userId: number): string
		local online = Players:GetPlayerByUserId(userId)
		if online then
			return online.Name
		end
		local cached = nameCache[userId]
		if cached then
			return cached
		end
		local ok, result = pcall(function()
			return Players:GetNameFromUserIdAsync(userId)
		end)
		local name = if ok and type(result) == "string" then result else "Player"
		nameCache[userId] = name
		return name
	end

	local stored: { [string]: { [number]: number } } = {} -- best scores from the OrderedDataStores
	local function loadStored()
		for _, info in ipairs(LEADERBOARD_STATS) do
			local ordered = orderedStores[info.Stat]
			if not ordered then
				continue
			end
			local ok, page = pcall(function()
				-- fastest times are the smallest numbers, so they go up instead of down
				return ordered:GetSortedAsync(info.Fastest == true, 10):GetCurrentPage()
			end)
			if ok and type(page) == "table" then
				local scores = {}
				for _, entry in ipairs(page) do
					local id = tonumber(entry.key)
					if id and type(entry.value) == "number" and (entry.value > 0 or not info.Fastest) then
						scores[id] = entry.value
					end
				end
				stored[info.Stat] = scores
			end
		end
	end

	local function refreshBoards()
		for _, board in ipairs(leaderboards) do
			local info = board.Info
			local fastest = info.Fastest == true
			local scores: { [number]: number } = table.clone(stored[info.Stat] or {})
			for player, data in pairs(Data) do
				local value = boardValue(info, data)
				if value and player.Parent then
					local old = scores[player.UserId]
					scores[player.UserId] = if old == nil then value elseif fastest then math.min(old, value) else math.max(old, value)
				end
			end
			local list = {}
			for id, value in pairs(scores) do
				table.insert(list, { Id = id, Value = value })
			end
			table.sort(list, function(a, b)
				if a.Value ~= b.Value then
					return if fastest then a.Value < b.Value else a.Value > b.Value
				end
				return a.Id < b.Id
			end)
			for k, row in ipairs(board.Rows) do
				local entry = list[k]
				row.PlayerName.Text = if entry then nameOf(entry.Id) else "---"
				row.Score.Text = if entry then boardText(info, entry.Value) else ""
			end
		end
	end

	task.spawn(function()
		local lastLoad = -math.huge
		while true do
			if os.clock() - lastLoad >= 60 then
				lastLoad = os.clock()
				loadStored()
			end
			refreshBoards()
			task.wait(5)
		end
	end)
end

--------------------------------------------------------------------------------
-- BUILD EVERYTHING, THEN LET PLAYERS IN
--------------------------------------------------------------------------------
setupLighting()
setupTerrain()
buildHub()
for i = 1, #Shared.Zones do
	buildZone(i)
end
buildObby(Vector3.zero, HUB.Obby, nil, MapFolder)
buildWalls()
for i = 1, #Shared.Zones do
	-- a bounce pad somewhere in every zone
	local padPos = freeSpot(i, 6)
	if padPos then
		reserve(i, padPos, 6)
		Fun.BouncePad(onGround(padPos), MapFolder)
	end
end
spawnCrystals()
for i = 1, #Shared.Zones do
	spawnZoneDigSpots(i)
end
Fun.SpawnZoneChests()

Players.CharacterAutoLoads = true
Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	-- these players joined while the map was being built, so spawn them now
	task.spawn(onPlayerAdded, player)
	task.spawn(function()
		task.wait(0.5)
		if player.Parent and not player.Character then
			player:LoadCharacter()
		end
	end)
end

print("[Crystal Rush] World built! Have fun mining 💎")
