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
	for _, name in ipairs({ "Mine", "Buy", "Rebirth", "Teleport", "Sync", "Notify", "Effect", "OpenMenu", "EnterDimension", "GoSell", "Claim" }) do
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

local function setupTerrain()
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
		[Enum.Material.Sand] = Color3.fromRGB(205, 186, 145),
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
	for _, target in ipairs({ Vector3.new(-34, 0, 0), Vector3.new(33, 0, 0), Vector3.new(-34, 0, -34), Vector3.new(34, 0, -32), Vector3.new(-36, 0, 32), Vector3.new(34, 0, 32) }) do
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
	local bumpMaterials = { Enum.Material.Grass, Enum.Material.Slate, Enum.Material.Basalt, Enum.Material.Snow, Enum.Material.Salt }
	for i = 1, #Shared.Zones do
		local zs, ze = Shared.ZoneStart(i), Shared.ZoneEnd(i)
		for _ = 1, 14 do
			local radius = rng:NextNumber(14, 24)
			local x, bz = rng:NextNumber(-62, 62), rng:NextNumber(ze + 12, zs - 40)
			Terrain:FillBall(Vector3.new(x, -radius + rng:NextNumber(1.5, 4), bz), radius, bumpMaterials[i])
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
		local lake = Vector3.new(55, 0, (zs + ze) / 2 - 20)
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
			Terrain:FillBall(pos + Vector3.new(0, rng:NextNumber(-2, 0), 0), radius, Enum.Material.Slate)
			reserve(5, pos, radius + 2)
		end
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
	Color3.fromRGB(86, 116, 56),
}

function Decor.Tree(pos: Vector3, scale: number)
	local m = model("Tree")
	local bark = Color3.fromRGB(88, 66, 50)
	local trunkH = rng:NextNumber(7, 10) * scale
	local top = pos + Vector3.new(rng:NextNumber(-0.6, 0.6), trunkH, rng:NextNumber(-0.6, 0.6))
	rod(pos + Vector3.new(0, -0.5, 0), top, 1.3 * scale, { Name = "Trunk", Color = bark, Material = Enum.Material.Wood, Parent = m })
	P({
		Name = "Roots",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, 2.4 * scale, 2.4 * scale),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, rad(90)),
		Color = bark,
		Material = Enum.Material.Wood,
		Parent = m,
	})
	for k = 1, 3 do
		local yaw = rng:NextNumber(0, math.pi * 2)
		local tilt = rad(rng:NextNumber(35, 55))
		local from = pos + Vector3.new(0, trunkH * rng:NextNumber(0.6, 0.8), 0)
		local dir = Vector3.new(math.cos(yaw) * math.sin(tilt), math.cos(tilt), math.sin(yaw) * math.sin(tilt))
		rod(from, from + dir * 3.6 * scale, 0.55 * scale, { Name = "Branch" .. k, Color = bark, Material = Enum.Material.Wood, CanCollide = false, Parent = m })
	end
	local crown = top + Vector3.new(0, 1.4 * scale, 0)
	for _ = 1, rng:NextInteger(7, 10) do
		local offset = Vector3.new(rng:NextNumber(-3, 3), rng:NextNumber(-1.6, 1.8), rng:NextNumber(-3, 3)) * scale
		P({
			Name = "Leaves",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * rng:NextNumber(3.6, 6) * scale,
			CFrame = CFrame.new(crown + offset),
			Color = LEAF_COLORS[rng:NextInteger(1, #LEAF_COLORS)],
			Material = Enum.Material.Grass,
			CanCollide = false,
			Parent = m,
		})
	end
end

function Decor.Pine(pos: Vector3, scale: number, snowy: boolean?)
	local m = model("PineTree")
	local height = rng:NextNumber(12, 16) * scale
	rod(pos + Vector3.new(0, -0.5, 0), pos + Vector3.new(0, height * 0.75, 0), 0.9 * scale, {
		Name = "Trunk",
		Color = Color3.fromRGB(80, 58, 44),
		Material = Enum.Material.Wood,
		Parent = m,
	})
	local layers = 7
	for k = 0, layers - 1 do
		local t = k / (layers - 1)
		local w = (7.5 - t * 6.3) * scale
		local y = (3 + t * (height - 4.5)) * 1
		local cf = CFrame.new(pos + Vector3.new(0, y, 0)) * CFrame.Angles(0, rad(45 + k * 23), 0)
		P({
			Name = "Needles",
			Size = Vector3.new(w, 1.8 * scale, w),
			CFrame = cf,
			Color = Color3.fromRGB(38, 66, 44),
			Material = Enum.Material.Grass,
			CanCollide = false,
			Parent = m,
		})
		if snowy then
			P({
				Name = "Snow",
				Size = Vector3.new(w * 0.85, 0.4 * scale, w * 0.85),
				CFrame = cf * CFrame.new(0, 1 * scale, 0),
				Color = Color3.fromRGB(240, 244, 250),
				Material = Enum.Material.Snow,
				CanCollide = false,
				Parent = m,
			})
		end
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

function Decor.Lamp(pos: Vector3)
	local m = model("Lamp")
	local iron = Color3.fromRGB(38, 38, 42)
	rod(pos, pos + Vector3.new(0, 9, 0), 0.45, { Name = "Pole", Color = iron, Material = Enum.Material.Metal, Parent = m })
	P({ Name = "Cap", Size = Vector3.new(1.8, 0.3, 1.8), CFrame = CFrame.new(pos + Vector3.new(0, 10.45, 0)), Color = iron, Material = Enum.Material.Metal, Parent = m })
	P({
		Name = "Glass",
		Size = Vector3.new(1.4, 1.5, 1.4),
		CFrame = CFrame.new(pos + Vector3.new(0, 9.6, 0)),
		Color = Color3.fromRGB(255, 236, 200),
		Material = Enum.Material.Glass,
		Transparency = 0.4,
		CanCollide = false,
		Parent = m,
	})
	local bulb = P({
		Name = "Bulb",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 0.6,
		CFrame = CFrame.new(pos + Vector3.new(0, 9.6, 0)),
		Color = Color3.fromRGB(255, 214, 150),
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
		Parent = m,
	})
	light(bulb, Color3.fromRGB(255, 205, 150), 16, 1.1)
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

-- Big stone arch with a sign (used for zone entrances)
local function buildArch(z: number, zone, parent: Instance, title: string, subtitle: string?)
	local stone = zone.RockColor:Lerp(Color3.fromRGB(150, 145, 138), 0.55)
	for _, side in ipairs({ -1, 1 }) do
		P({
			Name = "Pillar",
			Size = Vector3.new(8, 36, 8),
			CFrame = CFrame.new(side * 24, 18, z),
			Color = stone,
			Material = Enum.Material.Cobblestone,
			Parent = parent,
		})
		P({
			Name = "PillarCap",
			Size = Vector3.new(9.5, 2, 9.5),
			CFrame = CFrame.new(side * 24, 43, z),
			Color = stone:Lerp(Color3.new(0, 0, 0), 0.15),
			Material = Enum.Material.Slate,
			Parent = parent,
		})
		local torch = P({
			Name = "Torch",
			Size = Vector3.new(1, 1, 1),
			CFrame = CFrame.new(side * 24, 26, z + 4.6),
			Color = Color3.fromRGB(60, 45, 35),
			Material = Enum.Material.Wood,
			CanCollide = false,
			Parent = parent,
		})
		local fire = Instance.new("Fire")
		fire.Size = 3
		fire.Heat = 6
		fire.Parent = torch
		light(torch, Color3.fromRGB(255, 170, 90), 18, 1.2)
	end
	local beam = P({
		Name = "Beam",
		Size = Vector3.new(58, 6, 9),
		CFrame = CFrame.new(0, 39, z),
		Color = stone,
		Material = Enum.Material.Cobblestone,
		Parent = parent,
	})
	sign(beam, title, subtitle, zone.Accent:Lerp(Color3.new(1, 1, 1), 0.45), 34, 9, 9)
	return beam
end

--------------------------------------------------------------------------------
-- SELL PADS
--------------------------------------------------------------------------------
type SellPad = { Model: Model, Pad: BasePart, Radius: number, Zone: number, Dimension: number? }
local sellPads: { SellPad } = {}

-- zone = the zone you need to have unlocked; dimension = the island it is on (if any)
local function buildSellPad(pos: Vector3, size: number, zone: number, dimension: number?)
	local m = model("SellPad", SellFolder)
	m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	m:SetAttribute("Zone", zone)
	if dimension then
		m:SetAttribute("Dimension", dimension)
	end
	local upright = CFrame.Angles(0, 0, rad(90))
	local gold = Color3.fromRGB(205, 165, 70)
	P({
		Name = "Trim",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.5, size + 1.2, size + 1.2),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.25, 0)) * upright,
		Color = gold,
		Material = Enum.Material.Metal,
		Reflectance = 0.15,
		Parent = m,
	})
	local pad = P({
		Name = "Pad",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.7, size, size),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.35, 0)) * upright,
		Color = Color3.fromRGB(120, 86, 58),
		Material = Enum.Material.WoodPlanks,
		Parent = m,
	})
	-- piles of gold coins in the middle
	for k = 1, 7 do
		local a = k / 7 * math.pi * 2
		local r = if k == 1 then 0 else rng:NextNumber(1, 2.4)
		local h = rng:NextNumber(0.4, 1.4)
		P({
			Name = "Coins",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(h, 1.3, 1.3),
			CFrame = CFrame.new(pos + Vector3.new(math.cos(a) * r, 0.7 + h / 2, math.sin(a) * r)) * upright,
			Color = gold,
			Material = Enum.Material.Metal,
			Reflectance = 0.3,
			CanCollide = false,
			Parent = m,
		})
	end
	local post = P({
		Name = "SignPost",
		Size = Vector3.new(0.5, 6, 0.5),
		CFrame = CFrame.new(pos + Vector3.new(size / 2 + 0.8, 3, 0)),
		Color = Color3.fromRGB(95, 70, 50),
		Material = Enum.Material.Wood,
		Parent = m,
	})
	sign(post, "💰 SELL", "Stand on the pad to sell", Color3.fromRGB(255, 215, 110), 11, 3.8, 4.5)
	particles(pad, {
		Color = Color3.fromRGB(255, 215, 120),
		Size = 0.25,
		Rate = 4,
		Lifetime = NumberRange.new(1, 2),
		Speed = NumberRange.new(1, 2),
		Direction = Enum.NormalId.Right,
		LightEmission = 0.6,
	})
	local target = Instance.new("Attachment")
	target.Name = "GuideTarget"
	target.Parent = pad

	-- the selling itself happens in the SELLING loop further down
	table.insert(sellPads, { Model = m, Pad = pad, Radius = size / 2, Zone = zone, Dimension = dimension })
	return m
end

--------------------------------------------------------------------------------
-- EGG MACHINES
--------------------------------------------------------------------------------
local hatchEgg -- defined later

-- A floating board that shows the chance of every pet in an egg
local function oddsBoard(parent: Instance, egg)
	local rows = #egg.Pets
	local rowHeight = 1 / (rows + 1.4)
	local bb = Instance.new("BillboardGui")
	bb.Name = "Odds"
	bb.Size = UDim2.fromScale(8.5, (rows + 1.4) * 1.05)
	bb.StudsOffset = Vector3.new(8, 4.5, 0)
	bb.LightInfluence = 0
	bb.MaxDistance = 60
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(25, 25, 32)
	frame.BackgroundTransparency = 0.25
	frame.Parent = bb
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.08, 0)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = egg.Spots
	stroke.Parent = frame
	local function row(text: string, y: number, height: number, color: Color3)
		local lbl = Instance.new("TextLabel")
		lbl.BackgroundTransparency = 1
		lbl.Position = UDim2.fromScale(0.06, y)
		lbl.Size = UDim2.fromScale(0.88, height)
		lbl.Font = Enum.Font.FredokaOne
		lbl.TextScaled = true
		lbl.TextColor3 = color
		lbl.Text = text
		lbl.Parent = frame
		local textStroke = Instance.new("UIStroke")
		textStroke.Thickness = 2
		textStroke.Parent = lbl
	end
	row("🎲 Chances", rowHeight * 0.15, rowHeight * 1.05, Color3.new(1, 1, 1))
	for k, entry in ipairs(egg.Pets) do
		local def = Shared.Pets[entry.Index]
		row(def.Name .. "  " .. string.format("%g", entry.Chance) .. "%", rowHeight * (k + 0.3), rowHeight * 0.85, Shared.RarityColor(def.Rarity))
	end
	bb.Parent = parent
end

local function buildEggMachine(eggIndex: number, pos: Vector3)
	local egg = Shared.Eggs[eggIndex]
	local m = model("EggMachine" .. eggIndex)
	m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local stone = Color3.fromRGB(118, 112, 108)
	local upright = CFrame.Angles(0, 0, rad(90))
	P({
		Name = "Ring",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 15, 15),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.2, 0)) * upright,
		Color = Color3.fromRGB(190, 155, 75),
		Material = Enum.Material.Metal,
		Parent = m,
	})
	P({
		Name = "Base",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.8, 13, 13),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.4, 0)) * upright,
		Color = stone,
		Material = Enum.Material.Cobblestone,
		Parent = m,
	})
	local pillar = P({
		Name = "Pillar",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(4, 5, 5),
		CFrame = CFrame.new(pos + Vector3.new(0, 2.8, 0)) * upright,
		Color = stone,
		Material = Enum.Material.Marble,
		Parent = m,
	})
	local top = P({
		Name = "Top",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 6, 6),
		CFrame = CFrame.new(pos + Vector3.new(0, 4.95, 0)) * upright,
		Color = Color3.fromRGB(190, 155, 75),
		Material = Enum.Material.Metal,
		Parent = m,
	})
	particles(top, {
		Color = egg.Spots,
		Size = 0.3,
		Rate = 5,
		Lifetime = NumberRange.new(1, 2),
		Speed = NumberRange.new(1.5, 3),
		Direction = Enum.NormalId.Right,
		LightEmission = 0.6,
	})

	-- the big egg floating on top
	local eggModel = Shared.BuildEgg(eggIndex)
	eggModel.Name = "Egg"
	eggModel:PivotTo(CFrame.new(pos + Vector3.new(0, 8.6, 0)))
	eggModel.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	eggModel.Parent = m
	spin(eggModel, 0.6, 0.5)
	light(eggModel.PrimaryPart :: Instance, egg.Spots, 14, 0.8)

	sign(pillar, "🥚 " .. string.upper(egg.Name), "💰 " .. Format(egg.Price) .. " per egg", egg.Spots:Lerp(Color3.new(1, 1, 1), 0.5), 16, 5, 12)
	oddsBoard(top, egg)

	-- two buttons: hatch 1 egg (E) or 3 eggs (R)
	local spotOne = P({ Name = "HatchOne", Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(pos + Vector3.new(0, 4.5, 0)), Transparency = 1, CanCollide = false, Parent = m })
	local spotThree = P({ Name = "HatchThree", Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(pos + Vector3.new(0, 1.8, 0)), Transparency = 1, CanCollide = false, Parent = m })
	local one = prompt(spotOne, "Hatch 1  (💰 " .. Format(egg.Price) .. ")", egg.Name, 0.3)
	local three = prompt(spotThree, "Hatch 3  (💰 " .. Format(egg.Price * 3) .. ")", egg.Name, 0.3)
	three.KeyboardKeyCode = Enum.KeyCode.R
	three.GamepadKeyCode = Enum.KeyCode.ButtonY
	for _, pp in ipairs({ one, three }) do
		pp.MaxActivationDistance = 13
	end
	one:AddTag("HatchOnePrompt")
	one:SetAttribute("Price", egg.Price)
	one.Triggered:Connect(function(player)
		hatchEgg(player, eggIndex, 1)
	end)
	three.Triggered:Connect(function(player)
		hatchEgg(player, eggIndex, 3)
	end)
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
				spots[eggIndex] = Vector3.new(34 + (k - 1) * 16, 0, -32)
			else
				spots[eggIndex] = Vector3.new(26 + (k - 1) * 16, 0, Shared.ZoneStart(zoneIndex) - 16)
			end
		end
	end
	return spots
end

--------------------------------------------------------------------------------
-- SKY OBBY (floats above the spawn)
--------------------------------------------------------------------------------
type ObbyCheckpoint = { Part: BasePart, Spawn: CFrame }
local Obby = {
	Start = CFrame.new(),
	Checkpoints = {} :: { ObbyCheckpoint },
	Lava = {} :: { BasePart },
	Finish = nil :: BasePart?,
	FallY = 100,
}
local startObby -- defined later

local function buildObby()
	local f = model("SkyObby")
	local previous = buildParent
	buildParent = f
	local wood = Color3.fromRGB(140, 104, 72)
	local stone = Color3.fromRGB(128, 124, 118)

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
		table.insert(Obby.Checkpoints, { Part = base, Spawn = CFrame.lookAt(spawnPos, spawnPos + facing) })
	end

	-- Start
	local startPos = Vector3.new(20, 110, 40)
	local startPart = block(startPos, Vector3.new(14, 2, 14), Enum.Material.Cobblestone, stone, "Start")
	Obby.Start = CFrame.lookAt(startPos + Vector3.new(0, 4, 0), startPos + Vector3.new(-10, 4, 0))
	sign(startPart, "🏃 SKY OBBY", "Reach the trophy for a big reward!", Color3.fromRGB(255, 220, 140), 22, 6, 9)

	-- Stage 1: stepping stones
	for k, x in ipairs({ 8, -2, -12, -22 }) do
		block(Vector3.new(x, 110.5 + k * 0.6, 40 + rng:NextNumber(-1.5, 1.5)), Vector3.new(5, 1, 5), Enum.Material.Slate, Color3.fromRGB(112, 110, 106), "Stone", rng:NextNumber(0, 1))
	end
	checkpoint(Vector3.new(-36, 112, 40), Vector3.new(0, 0, -1))

	-- Stage 2: a long walkway with hot lava strips to jump over
	block(Vector3.new(-36, 112.5, 16), Vector3.new(6, 1, 34))
	for _, z in ipairs({ 26, 17, 8 }) do
		local lava = P({
			Name = "Lava",
			Size = Vector3.new(6.2, 0.5, 3),
			CFrame = CFrame.new(-36, 113.2, z),
			Color = Color3.fromRGB(230, 92, 30),
			Material = Enum.Material.CrackedLava,
		})
		light(lava, Color3.fromRGB(255, 120, 40), 10, 1)
		table.insert(Obby.Lava, lava)
	end
	block(Vector3.new(-36, 112.5, -4), Vector3.new(8, 1, 8))

	-- Stage 3: climb the truss
	local truss = Instance.new("TrussPart")
	truss.Name = "Truss"
	truss.Anchored = true
	truss.Size = Vector3.new(2, 16, 2)
	truss.CFrame = CFrame.new(-36, 121, -9)
	truss.Color = Color3.fromRGB(70, 70, 76)
	truss.Material = Enum.Material.Metal
	truss.Parent = f
	checkpoint(Vector3.new(-36, 128, -16), Vector3.new(1, 0, 0))

	-- Stage 4: narrow beams
	block(Vector3.new(-21, 128.5, -16), Vector3.new(18, 1, 1.4), Enum.Material.Wood, Color3.fromRGB(120, 88, 60), "Beam")
	block(Vector3.new(-9, 128.5, -16), Vector3.new(5, 1, 5))
	local a, b = Vector3.new(-6.5, 128.5, -17.5), Vector3.new(6.5, 128.5, -22.5)
	P({
		Name = "Beam",
		Size = Vector3.new(1.4, 1, (b - a).Magnitude + 1),
		CFrame = CFrame.lookAt((a + b) / 2, b),
		Color = Color3.fromRGB(120, 88, 60),
		Material = Enum.Material.Wood,
	})
	block(Vector3.new(9, 128.5, -24), Vector3.new(5, 1, 5))

	-- Stage 5: shrinking pillars
	for k, info in ipairs({ { 16, 3.6 }, { 23, 3 }, { 30, 2.6 } }) do
		local topY = 129 + k * 0.5
		block(Vector3.new(info[1], topY - 15, -24), Vector3.new(info[2], 30, info[2]), Enum.Material.Cobblestone, stone, "Pillar")
	end
	checkpoint(Vector3.new(40, 130, -24), Vector3.new(0, 0, 1))

	-- Stage 6: floating steps up to the finish
	for k = 0, 3 do
		block(Vector3.new(40, 132.5 + k * 2, -12 + k * 8), Vector3.new(4, 1, 4), Enum.Material.Slate, Color3.fromRGB(112, 110, 106), "Step")
	end
	local finishPos = Vector3.new(40, 139, 24)
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
	Obby.Finish = finish
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
	for _ = 1, 10 do
		Decor.Cloud(Vector3.new(rng:NextNumber(-70, 70), rng:NextNumber(96, 120), rng:NextNumber(-45, 50)), rng:NextNumber(1.2, 2.2))
	end
	buildParent = previous
end

--------------------------------------------------------------------------------
-- THE HUB (spawn area)
--------------------------------------------------------------------------------
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

	-- Fountain with a big gem statue
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
	local statue = P({
		Name = "HubCrystal",
		Size = Vector3.new(3, 7, 3),
		CFrame = CFrame.new(0, 13, 2) * CFrame.Angles(0, 0, rad(45)) * CFrame.Angles(rad(45), 0, 0),
		Color = Color3.fromRGB(70, 160, 190),
		Material = Enum.Material.Glass,
		Transparency = 0.05,
		Reflectance = 0.3,
		CanCollide = false,
		Parent = hub,
	})
	spin(statue, 0.5, 1)
	light(statue, Color3.fromRGB(120, 200, 230), 18, 0.8)
	sign(statue, "💎 CRYSTAL RUSH 💎", "Mine • Sell • Upgrade", Color3.fromRGB(190, 230, 245), 30, 8, 8)
	for k = 0, 3 do
		local a = k / 4 * math.pi * 2 + math.pi / 4
		Decor.Bench(Vector3.new(math.cos(a) * 15, 0, 2 + math.sin(a) * 15), -a - math.pi / 2)
	end

	-- Sell pad
	buildSellPad(Vector3.new(-34, 0, 0), 16, 1)

	-- Shop stall
	do
		local shop = model("Shop", hub)
		local wood = Color3.fromRGB(128, 92, 62)
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
				Size = Vector3.new(9, 0.3, 1.8),
				CFrame = CFrame.new(33, 10.4, i * 1.8) * CFrame.Angles(0, 0, rad(-12)),
				Color = if i % 2 == 0 then Color3.fromRGB(165, 55, 50) else Color3.fromRGB(225, 215, 195),
				Material = Enum.Material.Fabric,
				Parent = shop,
			})
		end
		for k = 1, 3 do
			P({
				Name = "Crate",
				Size = Vector3.new(2.2, 2.2, 2.2),
				CFrame = CFrame.new(35, 1.1, -4 + k * 2.4) * CFrame.Angles(0, rng:NextNumber(-0.3, 0.3), 0),
				Color = Color3.fromRGB(150, 115, 75),
				Material = Enum.Material.WoodPlanks,
				Parent = shop,
			})
		end
		local display = Shared.BuildPickaxe(5)
		display:PivotTo(CFrame.new(31, 5.8, 0) * CFrame.Angles(0, 0, rad(-20)))
		display.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		display.Parent = shop
		spin(display, 0.8, 0.3)
		sign(counter, "🛒 SHOP", "Pickaxes • Backpacks • Pets", Color3.fromRGB(170, 235, 160), 16, 5, 11)
		local pp = prompt(counter, "Open Shop", "Shop", 0)
		pp.Triggered:Connect(function(player)
			Remotes.OpenMenu:FireClient(player, "Shop")
		end)
	end

	-- Rebirth altar
	do
		local altar = model("RebirthAltar", hub)
		P({
			Name = "Platform",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.2, 14, 14),
			CFrame = CFrame.new(-34, 0.6, -34) * CFrame.Angles(0, 0, rad(90)),
			Color = Color3.fromRGB(96, 92, 100),
			Material = Enum.Material.Slate,
			Parent = altar,
		})
		local obelisk = P({
			Name = "Obelisk",
			Size = Vector3.new(3, 9, 3),
			CFrame = CFrame.new(-34, 5.7, -34) * CFrame.Angles(0, rad(45), 0),
			Color = Color3.fromRGB(70, 66, 76),
			Material = Enum.Material.Marble,
			Parent = altar,
		})
		local gem = P({
			Name = "Gem",
			Size = Vector3.new(2, 3, 2),
			CFrame = CFrame.new(-34, 12.5, -34) * CFrame.Angles(rad(45), 0, rad(45)),
			Color = Color3.fromRGB(130, 70, 190),
			Material = Enum.Material.Glass,
			Reflectance = 0.25,
			CanCollide = false,
			Parent = altar,
		})
		spin(gem, 1, 0.6)
		light(gem, Color3.fromRGB(170, 110, 230), 16, 0.9)
		sign(obelisk, "♻️ REBIRTH", "Start over, earn MORE coins", Color3.fromRGB(215, 185, 245), 16, 5, 9)
		local pp = prompt(obelisk, "Rebirth", "Rebirth Altar", 0)
		pp.Triggered:Connect(function(player)
			Remotes.OpenMenu:FireClient(player, "Rebirth")
		end)
	end

	-- Lamps along the path
	for _, z in ipairs({ 44, 22, -18, -44 }) do
		Decor.Lamp(Vector3.new(-6.5, 0, z))
		Decor.Lamp(Vector3.new(6.5, 0, z))
	end

	local busy = {
		{ Vector3.new(0, 0, 2), 24 }, -- fountain square
		{ Vector3.new(0, 0, 32), 11 }, -- spawn
		{ Vector3.new(-34, 0, 0), 12 }, -- sell pad
		{ Vector3.new(33, 0, 0), 10 }, -- shop
		{ Vector3.new(-34, 0, -34), 10 }, -- rebirth altar
		{ Vector3.new(60, 0, 38), 15 }, -- pond
		{ Vector3.new(34, 0, 32), 10 }, -- obby entrance
	}
	for eggIndex, pos in pairs(eggMachineSpots(1)) do
		buildEggMachine(eggIndex, pos)
		table.insert(busy, { pos, 11 })
	end

	-- Dimension portal (stone ring with a magic swirl)
	do
		local portalPos = Vector3.new(-36, 0, 32)
		table.insert(busy, { portalPos, 12 })
		local portal = model("DimensionPortal", hub)
		P({
			Name = "Platform",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.8, 16, 16),
			CFrame = CFrame.new(portalPos + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, 0, rad(90)),
			Color = Color3.fromRGB(96, 92, 100),
			Material = Enum.Material.Slate,
			Parent = portal,
		})
		local ringCenter = portalPos + Vector3.new(0, 8.5, 0)
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
		light(swirl, Color3.fromRGB(160, 120, 255), 24, 1.4)
		particles(swirl, {
			Color = Color3.fromRGB(190, 160, 255),
			Size = 0.35,
			Rate = 15,
			Lifetime = NumberRange.new(1, 2),
			Speed = NumberRange.new(2, 4),
			Direction = Enum.NormalId.Right,
			Spread = Vector2.new(60, 60),
		})
		sign(swirl, "🌌 DIMENSIONS", "Level up to unlock more!", Color3.fromRGB(205, 185, 250), 18, 5.5, 10)
		local pp = prompt(swirl, "Choose a Dimension", "Dimension Portal", 0)
		pp.MaxActivationDistance = 16
		pp.Triggered:Connect(function(player)
			Remotes.OpenMenu:FireClient(player, "Dimensions")
		end)
	end

	-- Sky obby entrance
	do
		local obbyPos = Vector3.new(34, 0, 32)
		local entrance = model("ObbyEntrance", hub)
		local pad = P({
			Name = "Pad",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.8, 12, 12),
			CFrame = CFrame.new(obbyPos + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, 0, rad(90)),
			Color = stone,
			Material = Enum.Material.Cobblestone,
			Parent = entrance,
		})
		local post = P({
			Name = "SignPost",
			Size = Vector3.new(0.6, 8, 0.6),
			CFrame = CFrame.new(obbyPos + Vector3.new(0, 4, -5)),
			Color = Color3.fromRGB(95, 70, 50),
			Material = Enum.Material.Wood,
			Parent = entrance,
		})
		local board = sign(post, "🏃 SKY OBBY", "Win 💰 coins!", Color3.fromRGB(255, 220, 140), 14, 4.6, 5.5)
		board.Name = "ObbySign"
		local pp = prompt(pad, "Start Obby", "Sky Obby", 0)
		pp.MaxActivationDistance = 12
		pp.Triggered:Connect(function(player)
			startObby(player)
		end)
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
		local pos = hubSpot(52, 76, 4)
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
	end

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

local addXP -- defined later
local endObby -- defined later

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
			Color = color,
			Material = Enum.Material.Glass,
			Transparency = 0.12,
			Reflectance = 0.2,
			Parent = m,
		})
		table.insert(gemParts, body)
		table.insert(gemParts, tip)
		return body
	end

	local main = prism("Main", CFrame.new(0, 0.6 * s, 0) * CFrame.Angles(rad(rng:NextNumber(-6, 6)), rad(45), rad(rng:NextNumber(-6, 6))), 1.7 * s, 5.2 * s)
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
	}
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
						if index and Shared.Pets[index] and type(count) == "number" and count >= 1 then
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
	data.Gems = math.clamp(math.floor(data.Gems), 0, Shared.Backpacks[data.Backpack].Capacity)
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
	for index, count in pairs(data.Pets) do
		pets[index] = count
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
addXP = function(player: Player, data: PlayerData, amount: number)
	data.XP += amount
	local leveledUp = false
	while data.XP >= Shared.XPNeeded(data.Level) do
		data.XP -= Shared.XPNeeded(data.Level)
		data.Level += 1
		leveledUp = true
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
		pet:SetAttribute("Scale", Shared.Pets[index].Size or 1)
		pet.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
		if root and root:IsA("BasePart") then
			pet:PivotTo(root.CFrame * CFrame.new(0, 0, 5))
		end
		pet.Parent = PetFolder
	end
end

--------------------------------------------------------------------------------
-- DIMENSIONS (floating islands that are built when someone visits them)
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
	-- little floating rocks under and around the island
	for _ = 1, 8 do
		local pos = edge(90, 120) + Vector3.new(0, rng:NextNumber(-40, 10), 0)
		Decor.FloatingRock(pos, rng:NextNumber(1, 2), colors[rng:NextInteger(1, #colors)])
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

	-- the floating island
	P({
		Name = "Ground",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(8, 170, 170),
		CFrame = CFrame.new(center - Vector3.new(0, 4, 0)) * upright,
		Color = dim.Ground,
		Material = theme.GroundMaterial,
	})
	local y = center.Y - 8
	for _, layer in ipairs({ { 10, 150 }, { 12, 112 }, { 14, 74 }, { 16, 36 } }) do
		P({
			Name = "Underside",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(layer[1], layer[2], layer[2]),
			CFrame = CFrame.new(center.X, y - layer[1] / 2, center.Z) * upright,
			Color = dim.Rock:Lerp(Color3.new(0, 0, 0), 0.35),
			Material = Enum.Material.Slate,
		})
		y -= layer[1]
	end
	-- invisible walls so nobody falls off
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

	-- title floating above the island
	local titlePart = P({
		Name = "Title",
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(center + Vector3.new(0, 34, 0)),
		Transparency = 1,
		CanCollide = false,
	})
	if dim.Shiny then
		sign(titlePart, "✨ SHINY DIMENSION " .. d .. " ✨", dim.Emoji .. " " .. dim.Name .. "  •  2x gems!", Color3.fromRGB(255, 230, 140), 48, 11, 0)
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
	else
		sign(titlePart, "🌌 DIMENSION " .. d, dim.Emoji .. " " .. dim.Name, dim.Accent:Lerp(Color3.new(1, 1, 1), 0.5), 44, 11, 0)
	end

	-- stone portal back home
	local homePos = center + Vector3.new(24, 0, 42)
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
	P({
		Name = "Base",
		Size = Vector3.new(12, 1, 4),
		CFrame = CFrame.new(homePos + Vector3.new(0, 0.5, 0)),
		Color = Color3.fromRGB(112, 108, 104),
		Material = Enum.Material.Cobblestone,
		Parent = home,
	})
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
	sign(homeSwirl, "🏠 HOME", "Back to the spawn", Color3.fromRGB(170, 225, 245), 12, 4, 8)
	local homePrompt = prompt(homeSwirl, "Go Home", "Home Portal", 0)
	homePrompt.Triggered:Connect(function(player)
		teleport(player, 0)
	end)

	local sellPos = center + Vector3.new(-24, 0, 38)
	local sellPad = buildSellPad(sellPos, 14, 1, d)

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
			{ pos = sellPos, radius = 11 },
			{ pos = homePos, radius = 9 },
		},
		Alive = true,
	}
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
	for k, pad in ipairs(sellPads) do
		if pad.Model == arena.SellPad then
			table.remove(sellPads, k)
			break
		end
	end
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

Remotes.Mine.OnServerEvent:Connect(function(player, crystal)
	local data = Data[player]
	if not data or typeof(crystal) ~= "Instance" or not crystal:IsA("Model") then
		return
	end
	local info = crystals[crystal]
	if not info or not info.Alive or crystal.Parent ~= info.Folder then
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
	if info.Dimension and info.Dimension > Shared.DimensionsUnlocked(data.Level) then
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

	local power = math.max(1, math.floor(Shared.Pickaxes[data.Pickaxe].Power * Shared.LevelPower(data.Level)))
	info.Health -= power
	Remotes.Effect:FireClient(player, "hit", info.Main.Position, power, crystal)

	if info.Health <= 0 then
		local gems = math.floor(info.Gems * Shared.GemMultiplier(data.Pets))
		local added = math.min(gems, capacity - data.Gems)
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
		sync(player)
	else
		updateBar(info)
	end
end)

--------------------------------------------------------------------------------
-- SKY OBBY
--------------------------------------------------------------------------------
type ObbyRun = { Started: number, Checkpoint: number }
local obbyRuns: { [Player]: ObbyRun } = {}

local function obbySpawn(run: ObbyRun): CFrame
	local checkpoint = Obby.Checkpoints[run.Checkpoint]
	return if checkpoint then checkpoint.Spawn else Obby.Start
end

startObby = function(player: Player)
	local char = player.Character
	if not Data[player] or not char then
		return
	end
	endObby(player, false)
	leaveDimension(player)
	obbyRuns[player] = { Started = os.clock(), Checkpoint = 0 }
	player:SetAttribute("ObbyStart", Workspace:GetServerTimeNow())
	char:PivotTo(Obby.Start)
	Remotes.Effect:FireClient(player, "obbystart")
end

endObby = function(player: Player, finished: boolean)
	local run = obbyRuns[player]
	if not run then
		return
	end
	obbyRuns[player] = nil
	player:SetAttribute("ObbyStart", nil)
	local data = Data[player]
	if not finished or not data then
		return
	end
	local time = math.floor((os.clock() - run.Started) * 10) / 10
	local record = data.ObbyBest == 0 or time < data.ObbyBest
	if record then
		data.ObbyBest = time
	end
	local wait = data.ObbyLast + Settings.ObbyCooldown - os.time()
	local coins = 0
	if wait <= 0 then
		coins = Shared.ObbyReward(data)
		data.Coins += coins
		data.ObbyLast = os.time()
	end
	Remotes.Effect:FireClient(player, "obby", time, coins, record, math.max(wait, 0))
	questProgress(player, data, "obby", 1)
	sync(player)
	-- after a little party at the finish, back to the spawn
	local char = player.Character
	task.delay(3, function()
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if player.Parent and player.Character == char and not obbyRuns[player] and root and root:IsA("BasePart") and root.Position.Y > Obby.FallY then
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
		local pos = root.Position
		if pos.Y < Obby.FallY then
			char:PivotTo(obbySpawn(run))
			Remotes.Effect:FireClient(player, "obbyfall")
			continue
		end
		local burned = false
		for _, lava in ipairs(Obby.Lava) do
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
		for k, checkpoint in ipairs(Obby.Checkpoints) do
			if k > run.Checkpoint then
				local rel = checkpoint.Part.CFrame:PointToObjectSpace(pos)
				if math.abs(rel.X) < 6.5 and math.abs(rel.Z) < 6.5 and rel.Y > 0 and rel.Y < 7 then
					run.Checkpoint = k
					Remotes.Effect:FireClient(player, "checkpoint", k, #Obby.Checkpoints)
				end
			end
		end
		local finish = Obby.Finish
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

local function sellAll(player: Player)
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
			if data.Gems > 0 and root and root:IsA("BasePart") then
				local pad = padUnder(root.Position)
				if pad then
					if canUsePad(player, data, pad) then
						sellAll(player)
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
-- HATCHING EGGS
--------------------------------------------------------------------------------
local hatchRandom = Random.new()
local lastHatch: { [Player]: number } = {}

hatchEgg = function(player: Player, eggIndex: number, amount: number)
	local data = Data[player]
	local egg = Shared.Eggs[eggIndex]
	if not data or not egg then
		return
	end
	if data.Zone < egg.Zone then
		notify(player, "🔒 Unlock " .. Shared.Zones[egg.Zone].Name .. " first!", "bad")
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
		local def = Shared.Pets[result.Pet]
		if Shared.RarityRank(def.Rarity) >= Shared.RarityRank("Legendary") then
			for _, other in ipairs(Players:GetPlayers()) do
				notify(other, "🎉 " .. player.DisplayName .. " hatched a " .. string.upper(def.Rarity) .. " " .. def.Name .. "!", "gold")
			end
		end
	end
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

--------------------------------------------------------------------------------
-- BUILD EVERYTHING, THEN LET PLAYERS IN
--------------------------------------------------------------------------------
setupLighting()
setupTerrain()
buildHub()
for i = 1, #Shared.Zones do
	buildZone(i)
end
buildObby()
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
