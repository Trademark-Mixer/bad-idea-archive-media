--[[
	Main  (Script inside ServerScriptService)

	This script runs the whole game on the server:
	  1. builds the map (terrain, zones, gates, decorations, crystals)
	  2. sets up the lighting so everything looks nice
	  3. handles mining, selling, the shop, rebirths and teleports
	  4. saves player progress

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
	for _, name in ipairs({ "Mine", "Buy", "Rebirth", "Teleport", "Sync", "Notify", "Effect", "OpenMenu" }) do
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
	p.Parent = props.Parent or MapFolder
	return p
end

local function model(name: string, parent: Instance?): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent or MapFolder
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

--------------------------------------------------------------------------------
-- LIGHTING (makes everything look pretty)
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
	Lighting.GeographicLatitude = 35
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.25
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
	bloom.Intensity = 0.7
	bloom.Size = 28
	bloom.Threshold = 1.4
	bloom.Parent = Lighting

	local color = Instance.new("ColorCorrectionEffect")
	color.Name = "CrystalRushColor"
	color.TintColor = mood.Tint
	color.Saturation = mood.Saturation
	color.Contrast = mood.Contrast
	color.Brightness = 0.02
	color.Parent = Lighting

	local rays = Instance.new("SunRaysEffect")
	rays.Name = "CrystalRushSunRays"
	rays.Intensity = 0.06
	rays.Spread = 0.8
	rays.Parent = Lighting

	if not Lighting:FindFirstChildOfClass("Sky") then
		local sky = Instance.new("Sky")
		sky.Name = "CrystalRushSky"
		sky.StarCount = 3000
		sky.SunAngularSize = 14
		sky.MoonAngularSize = 11
		sky.Parent = Lighting
	end

	local terrain = Workspace.Terrain
	if not terrain:FindFirstChildOfClass("Clouds") then
		local clouds = Instance.new("Clouds")
		clouds.Cover = 0.55
		clouds.Density = 0.65
		clouds.Color = Color3.fromRGB(255, 255, 255)
		clouds.Parent = terrain
	end
end

--------------------------------------------------------------------------------
-- TERRAIN
--------------------------------------------------------------------------------
local Terrain = Workspace.Terrain
local MAP_END = Shared.ZoneEnd(#Shared.Zones)

local function fillBlock(x: number, y: number, z: number, sx: number, sy: number, sz: number, material: Enum.Material, rotY: number?)
	Terrain:FillBlock(CFrame.new(x, y, z) * CFrame.Angles(0, rotY or 0, 0), Vector3.new(sx, sy, sz), material)
end

local function setupTerrain()
	local colors = {
		[Enum.Material.Grass] = Color3.fromRGB(95, 178, 65),
		[Enum.Material.LeafyGrass] = Color3.fromRGB(80, 155, 60),
		[Enum.Material.Slate] = Color3.fromRGB(85, 75, 115),
		[Enum.Material.Rock] = Color3.fromRGB(105, 95, 130),
		[Enum.Material.Basalt] = Color3.fromRGB(55, 45, 45),
		[Enum.Material.CrackedLava] = Color3.fromRGB(255, 110, 30),
		[Enum.Material.Snow] = Color3.fromRGB(235, 245, 255),
		[Enum.Material.Glacier] = Color3.fromRGB(165, 210, 240),
		[Enum.Material.Asphalt] = Color3.fromRGB(45, 35, 75),
		[Enum.Material.Salt] = Color3.fromRGB(75, 60, 120),
		[Enum.Material.Pavement] = Color3.fromRGB(195, 180, 155),
		[Enum.Material.Sand] = Color3.fromRGB(235, 215, 155),
	}
	for material, color in pairs(colors) do
		Terrain:SetMaterialColor(material, color)
	end
	Terrain.WaterColor = Color3.fromRGB(40, 165, 205)
	Terrain.WaterTransparency = 0.6
	Terrain.WaterReflectance = 0.6
	Terrain.WaterWaveSize = 0.12
	Terrain.WaterWaveSpeed = 8

	-- Hub ground, path and pond
	fillBlock(0, -6, 15, 224, 12, 140, Enum.Material.Grass)
	fillBlock(0, -2, 0, 12, 4, 110, Enum.Material.Pavement)
	fillBlock(0, -2, 5, 30, 4, 30, Enum.Material.Pavement)
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
			if rng:NextNumber() < 0.25 then
				material = if zoneIndex == 1 then Enum.Material.Rock else zone.Ground
			end
			if zoneIndex == 1 and z > Layout.HubBack and rng:NextNumber() < 0.5 then
				material = Enum.Material.LeafyGrass
			end
			Terrain:FillBall(Vector3.new(side * rng:NextNumber(98, 106), rng:NextNumber(-5, 2), z + rng:NextNumber(-4, 4)), rng:NextNumber(20, 28), material)
		end
		z -= 16
	end
	-- Hills behind the spawn and at the very end
	for x = -110, 110, 18 do
		Terrain:FillBall(Vector3.new(x, -3, Layout.HubFront + 20 + rng:NextNumber(-3, 3)), rng:NextNumber(20, 26), Enum.Material.LeafyGrass)
		Terrain:FillBall(Vector3.new(x, -3, MAP_END - 22 + rng:NextNumber(-3, 3)), rng:NextNumber(20, 26), Shared.Zones[#Shared.Zones].Hills)
	end

	-- The Crystal Caves (zone 2) get walls and a ceiling so they feel like a cave
	do
		local zs, ze = Shared.ZoneStart(2), Shared.ZoneEnd(2)
		local mid = (zs + ze) / 2
		for _, side in ipairs({ -1, 1 }) do
			fillBlock(side * 96, 22, mid, 16, 60, Layout.ZoneLength, Enum.Material.Slate)
			-- entrance and exit walls, with an opening for the gates
			fillBlock(side * 69, 21, zs - 4, 82, 42, 8, Enum.Material.Rock)
			fillBlock(side * 69, 21, ze + 4, 82, 42, 8, Enum.Material.Rock)
		end
		fillBlock(0, 53, zs - 4, 220, 22, 8, Enum.Material.Rock)
		fillBlock(0, 53, ze + 4, 220, 22, 8, Enum.Material.Rock)
		fillBlock(0, 46, mid, 208, 12, Layout.ZoneLength, Enum.Material.Slate)
		-- holes in the ceiling let a little sunlight in
		for _, hole in ipairs({ Vector3.new(-30, 46, mid + 45), Vector3.new(35, 46, mid + 5), Vector3.new(-10, 46, mid - 50) }) do
			Terrain:FillBall(hole, 9, Enum.Material.Air)
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
		-- lava streams on the ground
		for _ = 1, 7 do
			local side = if rng:NextNumber() < 0.5 then -1 else 1
			fillBlock(side * rng:NextNumber(30, 70), -1, rng:NextNumber(ze + 15, zs - 30), 6, 2, rng:NextNumber(16, 34), Enum.Material.CrackedLava, rng:NextNumber(0, math.pi))
		end
	end

	-- A frozen lake in the Frozen Peaks
	do
		local zs, ze = Shared.ZoneStart(4), Shared.ZoneEnd(4)
		fillBlock(55, -2, (zs + ze) / 2 - 20, 30, 4, 40, Enum.Material.Glacier)
	end
end

--------------------------------------------------------------------------------
-- DECORATIONS
--------------------------------------------------------------------------------
local Decor = {}

function Decor.Tree(pos: Vector3, scale: number)
	local m = model("Tree")
	local trunkH = 7 * scale
	P({
		Name = "Trunk",
		Size = Vector3.new(1.4, trunkH, 1.4) * Vector3.new(scale, 1, scale),
		CFrame = CFrame.new(pos + Vector3.new(0, trunkH / 2, 0)),
		Color = Color3.fromRGB(115, 78, 48),
		Material = Enum.Material.Wood,
		Parent = m,
	})
	local leafColors = { Color3.fromRGB(85, 175, 70), Color3.fromRGB(110, 190, 75), Color3.fromRGB(70, 150, 60) }
	for i, offset in ipairs({ Vector3.new(0, 8.2, 0), Vector3.new(1.9, 7, 1), Vector3.new(-1.7, 7.3, -1), Vector3.new(0.3, 6.6, -1.9) }) do
		P({
			Name = "Leaves",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * (if i == 1 then 7 else 5) * scale,
			CFrame = CFrame.new(pos + offset * scale),
			Color = leafColors[rng:NextInteger(1, #leafColors)],
			Material = Enum.Material.Grass,
			CanCollide = false,
			Parent = m,
		})
	end
end

function Decor.Pine(pos: Vector3, scale: number)
	local m = model("PineTree")
	P({
		Name = "Trunk",
		Size = Vector3.new(1, 5, 1) * scale,
		CFrame = CFrame.new(pos + Vector3.new(0, 2.5 * scale, 0)),
		Color = Color3.fromRGB(95, 65, 45),
		Material = Enum.Material.Wood,
		Parent = m,
	})
	local layers = { { 7.5, 4.2 }, { 5.6, 7 }, { 3.6, 9.4 }, { 1.8, 11.2 } }
	for _, layer in ipairs(layers) do
		local w, y = layer[1] * scale, layer[2] * scale
		local cf = CFrame.new(pos + Vector3.new(0, y, 0)) * CFrame.Angles(0, rad(45), 0)
		P({ Name = "Needles", Size = Vector3.new(w, 2.4 * scale, w), CFrame = cf, Color = Color3.fromRGB(40, 105, 75), CanCollide = false, Parent = m })
		P({
			Name = "Snow",
			Size = Vector3.new(w * 0.8, 0.5 * scale, w * 0.8),
			CFrame = cf * CFrame.new(0, 1.3 * scale, 0),
			Color = Color3.fromRGB(245, 250, 255),
			Material = Enum.Material.Snow,
			CanCollide = false,
			Parent = m,
		})
	end
end

function Decor.Rock(pos: Vector3, scale: number, color: Color3, material: Enum.Material?)
	P({
		Name = "Rock",
		Size = Vector3.new(rng:NextNumber(3, 5), rng:NextNumber(2, 4), rng:NextNumber(3, 5)) * scale,
		CFrame = CFrame.new(pos + Vector3.new(0, 0.6 * scale, 0)) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, math.pi), rng:NextNumber(-0.3, 0.3)),
		Color = color,
		Material = material or Enum.Material.Slate,
	})
end

function Decor.Flowers(pos: Vector3)
	local colors = {
		Color3.fromRGB(255, 120, 170),
		Color3.fromRGB(255, 230, 90),
		Color3.fromRGB(255, 255, 255),
		Color3.fromRGB(180, 130, 255),
		Color3.fromRGB(255, 140, 70),
	}
	local color = colors[rng:NextInteger(1, #colors)]
	for _ = 1, rng:NextInteger(3, 6) do
		local offset = Vector3.new(rng:NextNumber(-2, 2), 0.25, rng:NextNumber(-2, 2))
		P({
			Name = "Flower",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * rng:NextNumber(0.6, 0.9),
			CFrame = CFrame.new(pos + offset),
			Color = color,
			CanCollide = false,
			CastShadow = false,
		})
	end
end

function Decor.Bush(pos: Vector3, scale: number)
	for i = 1, 3 do
		P({
			Name = "Bush",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * rng:NextNumber(2.5, 3.6) * scale,
			CFrame = CFrame.new(pos + Vector3.new((i - 2) * 1.6 * scale, 0.9 * scale, rng:NextNumber(-0.6, 0.6))),
			Color = Color3.fromRGB(70, 150, 60),
			Material = Enum.Material.Grass,
			CanCollide = false,
		})
	end
end

function Decor.Lamp(pos: Vector3)
	local m = model("Lamp")
	P({
		Name = "Pole",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(9, 0.6, 0.6),
		CFrame = CFrame.new(pos + Vector3.new(0, 4.5, 0)) * CFrame.Angles(0, 0, rad(90)),
		Color = Color3.fromRGB(45, 45, 55),
		Material = Enum.Material.Metal,
		Parent = m,
	})
	local bulb = P({
		Name = "Bulb",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 1.8,
		CFrame = CFrame.new(pos + Vector3.new(0, 9.4, 0)),
		Color = Color3.fromRGB(255, 225, 160),
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = m,
	})
	light(bulb, Color3.fromRGB(255, 210, 150), 18, 1.4)
end

function Decor.Spire(pos: Vector3, scale: number, color: Color3)
	local m = model("CrystalSpire")
	for i = 1, 3 do
		local h = rng:NextNumber(8, 16) * scale
		local tilt = CFrame.Angles(rng:NextNumber(-0.35, 0.35), rng:NextNumber(0, math.pi), rng:NextNumber(-0.35, 0.35))
		P({
			Name = "Spire",
			Size = Vector3.new(2.2, h, 2.2) * Vector3.new(scale, 1, scale),
			CFrame = CFrame.new(pos + Vector3.new((i - 2) * 2 * scale, h / 2 - 1, rng:NextNumber(-1.5, 1.5))) * tilt,
			Color = color,
			Material = if i == 2 then Enum.Material.Neon else Enum.Material.Glass,
			Transparency = if i == 2 then 0 else 0.2,
			Parent = m,
		})
	end
	light(m:FindFirstChild("Spire") :: Instance, color, 20, 2)
end

function Decor.Mushroom(pos: Vector3, scale: number, color: Color3)
	local m = model("Mushroom")
	P({
		Name = "Stem",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(3 * scale, 0.9 * scale, 0.9 * scale),
		CFrame = CFrame.new(pos + Vector3.new(0, 1.5 * scale, 0)) * CFrame.Angles(0, 0, rad(90)),
		Color = Color3.fromRGB(230, 225, 240),
		CanCollide = false,
		Parent = m,
	})
	local cap = P({
		Name = "Cap",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 3 * scale,
		CFrame = CFrame.new(pos + Vector3.new(0, 3 * scale, 0)),
		Color = color,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = m,
	})
	light(cap, color, 10 * scale, 1.5)
end

function Decor.IceSpike(pos: Vector3, scale: number)
	local h = rng:NextNumber(6, 12) * scale
	P({
		Name = "IceSpike",
		Size = Vector3.new(1.8 * scale, h, 1.8 * scale),
		CFrame = CFrame.new(pos + Vector3.new(0, h / 2 - 0.5, 0)) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, math.pi), rng:NextNumber(-0.3, 0.3)),
		Color = Color3.fromRGB(170, 225, 255),
		Material = Enum.Material.Ice,
		Transparency = 0.15,
	})
end

function Decor.Snowman(pos: Vector3, rotY: number)
	local m = model("Snowman")
	local base = CFrame.new(pos) * CFrame.Angles(0, rotY, 0)
	local snow = Color3.fromRGB(245, 250, 255)
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
		Color = Color3.fromRGB(255, 140, 40),
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
		Color = Color3.fromRGB(255, 110, 20),
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
	})
	light(pool, Color3.fromRGB(255, 120, 40), radius * 2.5, 2)
	particles(pool, {
		Color = Color3.fromRGB(255, 150, 50),
		Size = 0.3,
		Rate = 6,
		Lifetime = NumberRange.new(2, 4),
		Speed = NumberRange.new(2, 5),
		Direction = Enum.NormalId.Right,
		Acceleration = Vector3.new(0, 1, 0),
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
	spin(planet, 0.15, 2)
	if ringColor then
		local ring = P({
			Name = "Ring",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.4, size * 1.9, size * 1.9),
			CFrame = CFrame.new(pos) * CFrame.Angles(rad(20), 0, rad(90)),
			Color = ringColor,
			Material = Enum.Material.Neon,
			Transparency = 0.45,
			CanCollide = false,
			CastShadow = false,
		})
		spin(ring, 0, 2)
	end
end

function Decor.Rune(pos: Vector3, radius: number, color: Color3)
	for i, info in ipairs({ { radius, Enum.Material.Neon, color }, { radius - 1.2, Enum.Material.Asphalt, Color3.fromRGB(45, 35, 75) } }) do
		P({
			Name = "Rune",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.3 + i * 0.05, info[1] * 2, info[1] * 2),
			CFrame = CFrame.new(pos + Vector3.new(0, 0.05 + i * 0.02, 0)) * CFrame.Angles(0, 0, rad(90)),
			Color = info[3],
			Material = info[2],
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
		Color = Color3.fromRGB(50, 40, 80),
		Material = Enum.Material.Basalt,
		CanCollide = false,
	})
	local gem = P({
		Name = "Glow",
		Size = Vector3.new(1, 2.4, 1) * scale,
		CFrame = rock.CFrame * CFrame.new(0, rock.Size.Y / 2 + 0.6 * scale, 0),
		Color = glow,
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	spin(rock, 0.2, 1.5)
	spin(gem, 0.2, 1.5)
end

-- Big stone arch with a sign (used for zone entrances)
local function buildArch(z: number, zone, parent: Instance, title: string, subtitle: string?)
	local stone = zone.RockColor:Lerp(Color3.new(1, 1, 1), 0.25)
	local pillars = {}
	for _, side in ipairs({ -1, 1 }) do
		table.insert(
			pillars,
			P({
				Name = "Pillar",
				Size = Vector3.new(8, 36, 8),
				CFrame = CFrame.new(side * 24, 18, z),
				Color = stone,
				Material = Enum.Material.Cobblestone,
				Parent = parent,
			})
		)
		local orb = P({
			Name = "Orb",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 4,
			CFrame = CFrame.new(side * 24, 44.5, z),
			Color = zone.Accent,
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = parent,
		})
		light(orb, zone.Accent, 24, 2)
		spin(orb, 0, 1)
	end
	local beam = P({
		Name = "Beam",
		Size = Vector3.new(58, 6, 9),
		CFrame = CFrame.new(0, 39, z),
		Color = stone,
		Material = Enum.Material.Cobblestone,
		Parent = parent,
	})
	sign(beam, title, subtitle, zone.Accent:Lerp(Color3.new(1, 1, 1), 0.35), 34, 9, 9)
	return beam
end

--------------------------------------------------------------------------------
-- SELL PADS
--------------------------------------------------------------------------------
local sellAll -- defined later

local function buildSellPad(pos: Vector3, size: number)
	local m = model("SellPad", SellFolder)
	m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	P({
		Name = "Ring",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, size + 1.5, size + 1.5),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, rad(90)),
		Color = Color3.fromRGB(255, 200, 40),
		Material = Enum.Material.Neon,
		Parent = m,
	})
	local pad = P({
		Name = "Pad",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.8, size, size),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, 0, rad(90)),
		Color = Color3.fromRGB(255, 215, 90),
		Material = Enum.Material.Metal,
		Reflectance = 0.2,
		Parent = m,
	})
	local coin = P({
		Name = "Coin",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.8, 5, 5),
		CFrame = CFrame.new(pos + Vector3.new(0, 7, 0)),
		Color = Color3.fromRGB(255, 205, 50),
		Material = Enum.Material.Metal,
		Reflectance = 0.3,
		CanCollide = false,
		Parent = m,
	})
	spin(coin, 2, 0.8)
	light(coin, Color3.fromRGB(255, 210, 90), 16, 1.5)
	sign(coin, "💰 SELL", "Step here to sell gems", Color3.fromRGB(255, 220, 80), 12, 4.2, 4.5)
	particles(pad, {
		Color = Color3.fromRGB(255, 220, 90),
		Size = 0.5,
		Rate = 12,
		Lifetime = NumberRange.new(1, 2),
		Speed = NumberRange.new(3, 6),
		Direction = Enum.NormalId.Right,
	})
	local target = Instance.new("Attachment")
	target.Name = "GuideTarget"
	target.Parent = pad

	pad.Touched:Connect(function(hit)
		local player = Players:GetPlayerFromCharacter(hit.Parent)
		if player then
			sellAll(player)
		end
	end)
	return m
end

--------------------------------------------------------------------------------
-- THE HUB (spawn area)
--------------------------------------------------------------------------------
local function buildHub()
	local hub = model("Hub")

	-- Spawn pad
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(0, 0.5, 32)
	spawn.Color = Color3.fromRGB(70, 200, 255)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = hub
	P({
		Name = "SpawnRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 19, 19),
		CFrame = CFrame.new(0, 0.2, 32) * CFrame.Angles(0, 0, rad(90)),
		Color = Color3.fromRGB(110, 220, 255),
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = hub,
	})

	-- Fountain with a giant floating crystal
	local marble = Color3.fromRGB(235, 235, 240)
	P({
		Name = "Basin",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2.4, 20, 20),
		CFrame = CFrame.new(0, 1.2, 2) * CFrame.Angles(0, 0, rad(90)),
		Color = marble,
		Material = Enum.Material.Marble,
		Parent = hub,
	})
	P({
		Name = "Water",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 17.6, 17.6),
		CFrame = CFrame.new(0, 2.35, 2) * CFrame.Angles(0, 0, rad(90)),
		Color = Color3.fromRGB(70, 175, 255),
		Material = Enum.Material.Glass,
		Transparency = 0.3,
		CanCollide = false,
		Parent = hub,
	})
	P({
		Name = "Pillar",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(6, 2.4, 2.4),
		CFrame = CFrame.new(0, 4, 2) * CFrame.Angles(0, 0, rad(90)),
		Color = marble,
		Material = Enum.Material.Marble,
		Parent = hub,
	})
	local bowl = P({
		Name = "Bowl",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, 7, 7),
		CFrame = CFrame.new(0, 7.3, 2) * CFrame.Angles(0, 0, rad(90)),
		Color = marble,
		Material = Enum.Material.Marble,
		Parent = hub,
	})
	particles(bowl, {
		Color = Color3.fromRGB(170, 225, 255),
		Size = 0.45,
		Rate = 70,
		Lifetime = NumberRange.new(0.9, 1.2),
		Speed = NumberRange.new(9, 12),
		Spread = Vector2.new(12, 12),
		Direction = Enum.NormalId.Right,
		Acceleration = Vector3.new(0, -25, 0),
		LightEmission = 0.4,
		Transparency = 0.2,
	})
	local bigCrystal = P({
		Name = "HubCrystal",
		Size = Vector3.new(3.5, 7, 3.5),
		CFrame = CFrame.new(0, 15, 2) * CFrame.Angles(0, 0, rad(45)) * CFrame.Angles(rad(45), 0, 0),
		Color = Color3.fromRGB(110, 220, 255),
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = hub,
	})
	spin(bigCrystal, 0.8, 1.5)
	light(bigCrystal, Color3.fromRGB(110, 220, 255), 30, 2)
	sign(bigCrystal, "💎 CRYSTAL RUSH 💎", "Mine • Sell • Upgrade", Color3.fromRGB(130, 230, 255), 30, 8, 9)

	-- Sell pad
	buildSellPad(Vector3.new(-34, 0, 0), 16)

	-- Shop stall
	do
		local shop = model("Shop", hub)
		local wood = Color3.fromRGB(150, 100, 60)
		local counter = P({
			Name = "Counter",
			Size = Vector3.new(4, 3.5, 12),
			CFrame = CFrame.new(31, 1.75, 0),
			Color = wood,
			Material = Enum.Material.WoodPlanks,
			Parent = shop,
		})
		for _, corner in ipairs({ Vector3.new(29.5, 0, -6), Vector3.new(29.5, 0, 6), Vector3.new(36.5, 0, -6), Vector3.new(36.5, 0, 6) }) do
			P({
				Name = "Post",
				Size = Vector3.new(0.8, 10, 0.8),
				CFrame = CFrame.new(corner + Vector3.new(0, 5, 0)),
				Color = wood,
				Material = Enum.Material.Wood,
				Parent = shop,
			})
		end
		for i = -3, 3 do
			P({
				Name = "Awning",
				Size = Vector3.new(9, 0.4, 1.8),
				CFrame = CFrame.new(33, 10.4, i * 1.8) * CFrame.Angles(0, 0, rad(-12)),
				Color = if i % 2 == 0 then Color3.fromRGB(240, 60, 70) else Color3.fromRGB(255, 255, 255),
				Material = Enum.Material.Fabric,
				Parent = shop,
			})
		end
		local display = Shared.BuildPickaxe(5)
		display:PivotTo(CFrame.new(31, 5.8, 0) * CFrame.Angles(0, 0, rad(-20)))
		display.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		display.Parent = shop
		spin(display, 1.2, 0.4)
		sign(counter, "🛒 SHOP", "Pickaxes • Backpacks • Pets", Color3.fromRGB(120, 255, 140), 16, 5, 11)
		local pp = prompt(counter, "Open Shop", "Shop", 0)
		pp.Triggered:Connect(function(player)
			Remotes.OpenMenu:FireClient(player, "Shop")
		end)
	end

	-- Rebirth altar
	do
		local altar = model("RebirthAltar", hub)
		local purple = Color3.fromRGB(190, 90, 255)
		local platform = P({
			Name = "Platform",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.2, 14, 14),
			CFrame = CFrame.new(-34, 0.6, -34) * CFrame.Angles(0, 0, rad(90)),
			Color = Color3.fromRGB(60, 45, 90),
			Material = Enum.Material.Marble,
			Parent = altar,
		})
		local obelisk = P({
			Name = "Obelisk",
			Size = Vector3.new(3, 10, 3),
			CFrame = CFrame.new(-34, 6.2, -34) * CFrame.Angles(0, rad(45), 0),
			Color = purple,
			Material = Enum.Material.Neon,
			Parent = altar,
		})
		light(obelisk, purple, 24, 2)
		local ring = P({
			Name = "Ring",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.5, 8, 8),
			CFrame = CFrame.new(-34, 6, -34) * CFrame.Angles(rad(90), 0, 0),
			Color = Color3.fromRGB(240, 200, 255),
			Material = Enum.Material.ForceField,
			CanCollide = false,
			Parent = altar,
		})
		spin(ring, 1.5, 1)
		particles(platform, { Color = purple, Size = 0.6, Rate = 15, Lifetime = NumberRange.new(1.5, 2.5), Speed = NumberRange.new(2, 4), Direction = Enum.NormalId.Right })
		sign(obelisk, "♻️ REBIRTH", "Start over, earn MORE coins", Color3.fromRGB(220, 160, 255), 16, 5, 8)
		local pp = prompt(obelisk, "Rebirth", "Rebirth Altar", 0)
		pp.Triggered:Connect(function(player)
			Remotes.OpenMenu:FireClient(player, "Rebirth")
		end)
	end

	-- Lamps along the path
	for _, z in ipairs({ 44, 20, -20, -44 }) do
		Decor.Lamp(Vector3.new(-9, 0, z))
		Decor.Lamp(Vector3.new(9, 0, z))
	end

	-- Trees, bushes and flowers around the hub (but not on the paths, stalls or pond)
	local busy = {
		{ Vector3.new(0, 0, 2), 13 }, -- fountain
		{ Vector3.new(0, 0, 32), 11 }, -- spawn
		{ Vector3.new(-34, 0, 0), 12 }, -- sell pad
		{ Vector3.new(33, 0, 0), 10 }, -- shop
		{ Vector3.new(-34, 0, -34), 10 }, -- rebirth altar
		{ Vector3.new(60, 0, 38), 15 }, -- pond
	}
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
		local pos = hubSpot(52, 76, 4)
		if pos then
			Decor.Tree(pos, rng:NextNumber(0.9, 1.4))
		end
	end
	for _ = 1, 22 do
		local pos = hubSpot(12, 62, 2)
		if pos then
			Decor.Flowers(pos)
		end
	end
	for _ = 1, 8 do
		local pos = hubSpot(16, 50, 3)
		if pos then
			Decor.Bush(pos, rng:NextNumber(0.8, 1.2))
		end
	end

	-- Entrance arch to the first zone
	buildArch(Layout.HubBack, Shared.Zones[1], hub, Shared.Zones[1].Emoji .. " " .. string.upper(Shared.Zones[1].Name), "Click crystals to mine them!")
end

--------------------------------------------------------------------------------
-- GATES (locked zone entrances)
--------------------------------------------------------------------------------
local unlockZone -- defined later

local function buildGate(i: number)
	local zone = Shared.Zones[i]
	local z = Shared.ZoneStart(i)
	local gate = model("Gate" .. i, GateFolder)
	gate:SetAttribute("Zone", i)
	gate.ModelStreamingMode = Enum.ModelStreamingMode.Persistent

	buildArch(z, zone, gate, "🔒 " .. string.upper(zone.Name), "💰 " .. Format(zone.Price) .. " to unlock")

	P({
		Name = "Barrier",
		Size = Vector3.new(Layout.HalfWidth * 2, 60, 2),
		CFrame = CFrame.new(0, 30, z),
		Color = zone.Accent,
		Material = Enum.Material.ForceField,
		Transparency = 0.3,
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
-- Spots where crystals should not grow (decorations, sell pads, ...)
local reserved: { [number]: { { pos: Vector3, radius: number } } } = {}

local function reserve(zoneIndex: number, pos: Vector3, radius: number)
	reserved[zoneIndex] = reserved[zoneIndex] or {}
	table.insert(reserved[zoneIndex], { pos = pos, radius = radius })
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

local function buildZone(i: number)
	local zone = Shared.Zones[i]
	local zs, ze = Shared.ZoneStart(i), Shared.ZoneEnd(i)
	local mid = (zs + ze) / 2
	if i >= 2 then
		buildGate(i)
	end

	-- Sell pad near the entrance of every zone
	local padPos = Vector3.new(-26, 0, zs - 16)
	buildSellPad(padPos, 14)
	reserve(i, padPos, 14)
	reserve(i, Shared.ZoneSpawn(i), 8)

	if i == 1 then -- Sunny Meadow
		for _ = 1, 18 do
			Decor.Tree(edgeSpot(i), rng:NextNumber(0.9, 1.5))
		end
		for _ = 1, 30 do
			Decor.Flowers(anySpot(i))
		end
		for _ = 1, 10 do
			Decor.Bush(edgeSpot(i), rng:NextNumber(0.8, 1.3))
			Decor.Rock(edgeSpot(i), rng:NextNumber(0.8, 1.6), zone.RockColor)
		end
	elseif i == 2 then -- Crystal Caves
		for _ = 1, 14 do
			Decor.Spire(edgeSpot(i), rng:NextNumber(0.8, 1.4), zone.CrystalColors[rng:NextInteger(1, #zone.CrystalColors)])
		end
		for _ = 1, 16 do
			Decor.Mushroom(edgeSpot(i), rng:NextNumber(0.7, 1.3), zone.CrystalColors[rng:NextInteger(1, #zone.CrystalColors)])
		end
		for _ = 1, 6 do
			local pos = anySpot(i)
			reserve(i, pos, 5)
			Decor.Mushroom(pos, rng:NextNumber(0.5, 0.8), Color3.fromRGB(90, 230, 255))
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
		local sparkle = P({
			Name = "CaveSparkles",
			Size = Vector3.new(160, 1, Layout.ZoneLength - 10),
			CFrame = CFrame.new(0, 20, mid),
			Transparency = 1,
			CanCollide = false,
		})
		particles(sparkle, {
			Color = Color3.fromRGB(210, 160, 255),
			Size = 0.35,
			Rate = 25,
			Lifetime = NumberRange.new(3, 6),
			Speed = NumberRange.new(0.2, 0.8),
			Spread = Vector2.new(180, 180),
		})
	elseif i == 3 then -- Lava Volcano
		local volcanoPos = Vector3.new(-62, 40, mid)
		reserve(i, Vector3.new(-62, 0, mid), 34)
		local glow = P({
			Name = "VolcanoGlow",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 9,
			CFrame = CFrame.new(volcanoPos - Vector3.new(0, 4, 0)),
			Color = Color3.fromRGB(255, 110, 20),
			Material = Enum.Material.Neon,
			CanCollide = false,
		})
		light(glow, Color3.fromRGB(255, 120, 40), 60, 3)
		particles(glow, {
			Texture = "rbxasset://textures/particles/smoke_main.dds",
			Color = Color3.fromRGB(80, 70, 70),
			LightEmission = 0,
			Size = 8,
			EndSize = 22,
			Rate = 6,
			Lifetime = NumberRange.new(6, 9),
			Speed = NumberRange.new(6, 9),
			Spread = Vector2.new(15, 15),
			Transparency = 0.4,
		})
		particles(glow, {
			Texture = "rbxasset://textures/particles/fire_main.dds",
			Color = Color3.fromRGB(255, 140, 40),
			Size = 4,
			EndSize = 1,
			Rate = 25,
			Lifetime = NumberRange.new(1, 2),
			Speed = NumberRange.new(8, 14),
			Spread = Vector2.new(15, 15),
		})
		for _ = 1, 8 do
			local pos = anySpot(i)
			if pos.X > -25 then
				local r = rng:NextNumber(4, 7)
				reserve(i, pos, r + 4)
				Decor.LavaPool(pos, r)
			end
		end
		for _ = 1, 22 do
			Decor.Rock(edgeSpot(i), rng:NextNumber(1, 2.4), zone.RockColor, Enum.Material.Basalt)
		end
		local embers = P({
			Name = "Embers",
			Size = Vector3.new(160, 1, Layout.ZoneLength - 10),
			CFrame = CFrame.new(0, 1, mid),
			Transparency = 1,
			CanCollide = false,
		})
		particles(embers, {
			Color = Color3.fromRGB(255, 150, 50),
			Size = 0.3,
			Rate = 40,
			Lifetime = NumberRange.new(3, 6),
			Speed = NumberRange.new(2, 5),
			Spread = Vector2.new(30, 30),
		})
	elseif i == 4 then -- Frozen Peaks
		for _ = 1, 22 do
			Decor.Pine(edgeSpot(i), rng:NextNumber(0.9, 1.6))
		end
		for _ = 1, 14 do
			Decor.IceSpike(edgeSpot(i), rng:NextNumber(0.8, 1.6))
		end
		for _, pos in ipairs({ Vector3.new(-40, 0, mid + 30), Vector3.new(30, 0, mid - 45) }) do
			reserve(i, pos, 6)
			Decor.Snowman(pos, rng:NextNumber(0, math.pi * 2))
		end
		reserve(i, Vector3.new(55, 0, mid - 20), 22)
		local snow = P({
			Name = "Snowfall",
			Size = Vector3.new(170, 1, Layout.ZoneLength),
			CFrame = CFrame.new(0, 60, mid),
			Transparency = 1,
			CanCollide = false,
		})
		particles(snow, {
			Color = Color3.fromRGB(255, 255, 255),
			LightEmission = 0.3,
			Size = 0.35,
			EndSize = 0.35,
			Rate = 120,
			Lifetime = NumberRange.new(9, 12),
			Speed = NumberRange.new(5, 7),
			Spread = Vector2.new(15, 15),
			Direction = Enum.NormalId.Bottom,
		})
	elseif i == 5 then -- Galaxy Isles
		Decor.Planet(Vector3.new(-90, 95, mid + 30), 40, Color3.fromRGB(120, 70, 220), Enum.Material.Glass, Color3.fromRGB(255, 120, 230))
		Decor.Planet(Vector3.new(85, 75, mid - 35), 26, Color3.fromRGB(80, 230, 255), Enum.Material.ForceField, nil)
		Decor.Planet(Vector3.new(30, 120, mid + 70), 16, Color3.fromRGB(255, 160, 80), Enum.Material.SmoothPlastic, Color3.fromRGB(255, 230, 150))
		for _ = 1, 14 do
			local pos = edgeSpot(i)
			Decor.FloatingRock(pos + Vector3.new(0, rng:NextNumber(14, 34), 0), rng:NextNumber(0.8, 1.6), zone.CrystalColors[rng:NextInteger(1, 3)])
		end
		for _ = 1, 6 do
			local pos = anySpot(i)
			reserve(i, pos, 8)
			Decor.Rune(pos, rng:NextNumber(4, 6), zone.CrystalColors[rng:NextInteger(1, 3)])
		end
		for _ = 1, 10 do
			Decor.Spire(edgeSpot(i), rng:NextNumber(0.8, 1.3), zone.CrystalColors[rng:NextInteger(1, 3)])
		end
		local stars = P({
			Name = "Stars",
			Size = Vector3.new(180, 1, Layout.ZoneLength),
			CFrame = CFrame.new(0, 45, mid),
			Transparency = 1,
			CanCollide = false,
		})
		particles(stars, {
			Color = Color3.fromRGB(255, 255, 255),
			Size = 0.6,
			Rate = 40,
			Lifetime = NumberRange.new(2, 4),
			Speed = NumberRange.new(0, 0.5),
			Spread = Vector2.new(180, 180),
		})
		-- The end of the world
		local finale = buildArch(ze + 8, zone, MapFolder, "🏆 YOU MADE IT!", "Rebirth to go even further")
		finale.Name = "FinalArch"
		reserve(i, Vector3.new(-24, 0, ze + 8), 6)
		reserve(i, Vector3.new(24, 0, ze + 8), 6)
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

--------------------------------------------------------------------------------
-- CRYSTALS
--------------------------------------------------------------------------------
type CrystalInfo = {
	Model: Model,
	Zone: number,
	Giant: boolean,
	Health: number,
	MaxHealth: number,
	Gems: number,
	Color: Color3,
	Main: BasePart,
	Radius: number,
	Alive: boolean,
	Billboard: BillboardGui,
	Fill: Frame,
	Label: TextLabel,
}
local crystals: { [Model]: CrystalInfo } = {}

local function updateBar(info: CrystalInfo)
	local frac = math.clamp(info.Health / info.MaxHealth, 0, 1)
	info.Fill.Size = UDim2.fromScale(frac, 1)
	info.Fill.BackgroundColor3 = Color3.fromRGB(255, 80, 80):Lerp(Color3.fromRGB(90, 255, 120), frac)
	info.Label.Text = Format(math.max(info.Health, 0)) .. " / " .. Format(info.MaxHealth)
	info.Billboard.Enabled = info.Health < info.MaxHealth
end

local function findSpot(zoneIndex: number, ignore: Model?): CFrame
	local best = anySpot(zoneIndex)
	for _ = 1, 40 do
		local pos = anySpot(zoneIndex)
		local ok = true
		for _, r in ipairs(reserved[zoneIndex] or {}) do
			if (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(r.pos.X, 0, r.pos.Z)).Magnitude < r.radius + 4 then
				ok = false
				break
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
	return CFrame.new(best) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
end

local function buildCrystal(zoneIndex: number, giant: boolean): CrystalInfo
	local zone = Shared.Zones[zoneIndex]
	local color = zone.CrystalColors[rng:NextInteger(1, #zone.CrystalColors)]
	local s = if giant then 1.9 else 1
	local m = Instance.new("Model")
	m.Name = if giant then "GiantCrystal" else "Crystal"
	m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	local base = P({
		Name = "Rock",
		Size = Vector3.new(5, 1.6, 5) * s,
		CFrame = CFrame.new(0, 0.5 * s, 0) * CFrame.Angles(0, rad(45), 0),
		Color = zone.RockColor,
		Material = Enum.Material.Slate,
		Parent = m,
	})
	local main = P({
		Name = "Main",
		Size = Vector3.new(1.7, 6, 1.7) * s,
		CFrame = CFrame.new(0, 3.2 * s, 0) * CFrame.Angles(0, rad(45), rad(4)),
		Color = color,
		Material = Enum.Material.Glass,
		Transparency = 0.15,
		Reflectance = 0.15,
		Parent = m,
	})
	P({
		Name = "Core",
		Size = Vector3.new(0.7, 5, 0.7) * s,
		CFrame = main.CFrame,
		Color = color,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanQuery = true,
		Parent = m,
	})
	local shards = {
		{ Vector3.new(1.4, 2, 0.3), Vector3.new(0, 20, -28), Vector3.new(1.1, 3.6, 1.1) },
		{ Vector3.new(-1.3, 1.8, 0.6), Vector3.new(0, -30, 26), Vector3.new(1, 3.2, 1) },
		{ Vector3.new(0.3, 1.6, 1.4), Vector3.new(30, 60, 0), Vector3.new(0.9, 2.8, 0.9) },
		{ Vector3.new(-0.2, 1.5, -1.4), Vector3.new(-28, 10, 0), Vector3.new(0.9, 2.6, 0.9) },
	}
	for _, shard in ipairs(shards) do
		local r = shard[2]
		P({
			Name = "Shard",
			Size = shard[3] * s,
			CFrame = CFrame.new(shard[1] * s) * CFrame.fromEulerAnglesXYZ(rad(r.X), rad(r.Y), rad(r.Z)),
			Color = color,
			Material = Enum.Material.Glass,
			Transparency = 0.15,
			Reflectance = 0.15,
			Parent = m,
		})
	end
	light(main, color, 12 * s, 1.6)
	m.PrimaryPart = base

	-- health bar
	local bb = Instance.new("BillboardGui")
	bb.Name = "HealthBar"
	bb.Size = UDim2.fromOffset(130, 30)
	bb.StudsOffset = Vector3.new(0, 4 * s, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 70
	bb.Enabled = false
	bb.Adornee = main
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(25, 25, 40)
	back.Parent = bb
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = back
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(15, 15, 25)
	stroke.Parent = back
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(90, 255, 120)
	fill.Parent = back
	corner:Clone().Parent = fill
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Parent = back
	local labelStroke = Instance.new("UIStroke")
	labelStroke.Thickness = 2
	labelStroke.Parent = label
	bb.Parent = m

	local health = zone.Health * (if giant then Settings.GiantHealth else 1)
	local info: CrystalInfo = {
		Model = m,
		Zone = zoneIndex,
		Giant = giant,
		Health = health,
		MaxHealth = health,
		Gems = zone.Gems * (if giant then Settings.GiantGems else 1),
		Color = color,
		Main = main,
		Radius = 2 * s,
		Alive = true,
		Billboard = bb,
		Fill = fill,
		Label = label,
	}
	m:SetAttribute("IsCrystal", true)
	m:SetAttribute("Zone", zoneIndex)
	m:SetAttribute("Radius", info.Radius)
	crystals[m] = info
	updateBar(info)
	return info
end

local function spawnCrystals()
	for zoneIndex = 1, #Shared.Zones do
		for _ = 1, Settings.CrystalsPerZone do
			local info = buildCrystal(zoneIndex, rng:NextNumber() < Settings.GiantChance)
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
	Pets: { [number]: boolean },
	TotalGems: number,
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

local Data: { [Player]: PlayerData } = {}
local CanSave: { [Player]: boolean } = {}

local function defaultData(): PlayerData
	return { Coins = 0, Gems = 0, Rebirths = 0, Pickaxe = 1, Backpack = 1, Zone = 1, Pets = {}, TotalGems = 0 }
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
				if type(saved.Pets) == "table" then
					for _, index in ipairs(saved.Pets) do
						if type(index) == "number" and Shared.Pets[index] then
							data.Pets[index] = true
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
	data.Gems = math.clamp(math.floor(data.Gems), 0, Shared.Backpacks[data.Backpack].Capacity)
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
	local pets = {}
	for index in pairs(data.Pets) do
		table.insert(pets, index)
	end
	local payload = {
		Coins = data.Coins,
		Gems = data.Gems,
		Rebirths = data.Rebirths,
		Pickaxe = data.Pickaxe,
		Backpack = data.Backpack,
		Zone = data.Zone,
		Pets = pets,
		TotalGems = data.TotalGems,
	}
	local ok, err = pcall(function()
		(store :: DataStore):SetAsync("Player_" .. player.UserId, payload)
	end)
	if not ok then
		warn("[Crystal Rush] Could not save " .. player.Name .. ": " .. tostring(err))
	end
end

--------------------------------------------------------------------------------
-- TELLING PLAYERS WHAT CHANGED
--------------------------------------------------------------------------------
local function notify(player: Player, text: string, kind: string?)
	Remotes.Notify:FireClient(player, text, kind or "info")
end

local function sync(player: Player)
	local data = Data[player]
	if not data then
		return
	end
	local pets = {}
	for index in pairs(data.Pets) do
		table.insert(pets, index)
	end
	Remotes.Sync:FireClient(player, {
		Coins = data.Coins,
		Gems = data.Gems,
		Capacity = Shared.Backpacks[data.Backpack].Capacity,
		Rebirths = data.Rebirths,
		Pickaxe = data.Pickaxe,
		Backpack = data.Backpack,
		Zone = data.Zone,
		Pets = pets,
		TotalGems = data.TotalGems,
	})
	local stats = player:FindFirstChild("leaderstats")
	if stats then
		local coins = stats:FindFirstChild("Coins") :: IntValue?
		local rebirths = stats:FindFirstChild("Rebirths") :: IntValue?
		if coins then
			coins.Value = data.Coins
		end
		if rebirths then
			rebirths.Value = data.Rebirths
		end
	end
end

--------------------------------------------------------------------------------
-- PICKAXE TOOL, BACKPACK ON YOUR BACK, PETS
--------------------------------------------------------------------------------
local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = a
end

local function makePickaxeTool(index: number): Tool
	local def = Shared.Pickaxes[index]
	local tool = Instance.new("Tool")
	tool.Name = "Pickaxe"
	tool.ToolTip = def.Name
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.Grip = CFrame.new(0, -1.4, 0)
	local built = Shared.BuildPickaxe(index)
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
	built:Destroy()
	return tool
end

local function givePickaxe(player: Player)
	local data = Data[player]
	local char = player.Character
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not (data and char and backpack) then
		return
	end
	for _, container in ipairs({ backpack, char } :: { Instance }) do
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") and child.Name == "Pickaxe" then
				child:Destroy()
			end
		end
	end
	local tool = makePickaxeTool(data.Pickaxe)
	tool.Parent = backpack
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		hum:EquipTool(tool)
	end
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
	local bag = Shared.BuildBackpack(data.Backpack)
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
		pet.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
		if root and root:IsA("BasePart") then
			pet:PivotTo(root.CFrame * CFrame.new(0, 0, 5))
		end
		pet.Parent = PetFolder
	end
end

local function teleport(player: Player, zoneIndex: number)
	local char = player.Character
	if char then
		char:PivotTo(CFrame.new(Shared.ZoneSpawn(zoneIndex)))
	end
end

--------------------------------------------------------------------------------
-- MINING
--------------------------------------------------------------------------------
local lastMine: { [Player]: number } = {}
local lastFullWarning: { [Player]: number } = {}

local function breakCrystal(info: CrystalInfo)
	info.Alive = false
	Remotes.Effect:FireAllClients("break", info.Main.Position, info.Color, info.Giant)
	info.Model.Parent = ServerStorage
	task.delay(Settings.CrystalRespawnTime, function()
		info.Model:PivotTo(findSpot(info.Zone, info.Model))
		info.Health = info.MaxHealth
		updateBar(info)
		info.Alive = true
		info.Model.Parent = CrystalFolder
		Remotes.Effect:FireAllClients("spawn", info.Main.Position, info.Color)
	end)
end

Remotes.Mine.OnServerEvent:Connect(function(player, crystal)
	local data = Data[player]
	if not data or typeof(crystal) ~= "Instance" or not crystal:IsA("Model") then
		return
	end
	local info = crystals[crystal]
	if not info or not info.Alive or crystal.Parent ~= CrystalFolder then
		return
	end
	local now = os.clock()
	if now - (lastMine[player] or 0) < Settings.MineCooldown * 0.8 then
		return
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (root and root:IsA("BasePart") and hum and hum.Health > 0) then
		return
	end
	if (root.Position - crystal:GetPivot().Position).Magnitude > Settings.MineRange + info.Radius + 6 then
		return
	end
	if info.Zone > data.Zone then
		return
	end
	local capacity = Shared.Backpacks[data.Backpack].Capacity
	if data.Gems >= capacity then
		if now - (lastFullWarning[player] or 0) > 1 then
			lastFullWarning[player] = now
			Remotes.Effect:FireClient(player, "full")
		end
		return
	end
	lastMine[player] = now

	local power = Shared.Pickaxes[data.Pickaxe].Power
	info.Health -= power
	Remotes.Effect:FireClient(player, "hit", info.Main.Position, power, crystal)

	if info.Health <= 0 then
		local gems = math.floor(info.Gems * Shared.GemMultiplier(data.Pets))
		local added = math.min(gems, capacity - data.Gems)
		data.Gems += added
		data.TotalGems += added
		breakCrystal(info)
		Remotes.Effect:FireClient(player, "reward", info.Main.Position, added)
		sync(player)
	else
		updateBar(info)
	end
end)

--------------------------------------------------------------------------------
-- SELLING
--------------------------------------------------------------------------------
local lastSell: { [Player]: number } = {}

sellAll = function(player: Player)
	local data = Data[player]
	if not data or data.Gems <= 0 then
		return
	end
	local now = os.clock()
	if now - (lastSell[player] or 0) < 0.6 then
		return
	end
	lastSell[player] = now
	local coins = math.floor(data.Gems * Shared.CoinMultiplier(data.Rebirths))
	data.Coins += coins
	data.Gems = 0
	Remotes.Effect:FireClient(player, "sold", coins)
	sync(player)
end

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
		if not def then
			return
		end
		if data.Pets[index] then
			notify(player, "You already own " .. def.Name .. "!", "info")
			return
		end
		if not spend(player, data, def.Price) then
			return
		end
		data.Pets[index] = true
		refreshPets(player)
		notify(player, "🐾 " .. def.Name .. " joined your team!", "good")
	elseif category == "Zone" then
		unlockZone(player, index)
		return
	else
		return
	end
	Remotes.Effect:FireClient(player, "bought", category, index)
	sync(player)
end)

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
	local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
	if not hum then
		return
	end
	hum.WalkSpeed = Settings.WalkSpeed
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
	givePickaxe(player)
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

	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Parent = stats
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

--------------------------------------------------------------------------------
-- BUILD EVERYTHING, THEN LET PLAYERS IN
--------------------------------------------------------------------------------
setupLighting()
setupTerrain()
buildHub()
for i = 1, #Shared.Zones do
	buildZone(i)
end
buildWalls()
spawnCrystals()

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
