--[[
	GameShared  (ModuleScript inside ReplicatedStorage)

	Everything both the server and the players' computers need to know:
	  * game settings
	  * zones, pickaxes, backpacks and pets (names, prices, power)
	  * code that builds the 3D models for pets, pickaxes and backpacks

	Want to change a price, make a pickaxe stronger or add a new pet?
	This is the file to edit! Keep the same format and it will just work.
]]

local Shared = {}

Shared.GameName = "Crystal Rush"

--------------------------------------------------------------------------------
-- EASY SETTINGS
--------------------------------------------------------------------------------
Shared.Settings = {
	WalkSpeed = 22, -- how fast players walk (Roblox default is 16)
	MineRange = 24, -- how close (in studs) you must be to mine a crystal
	MineCooldown = 0.2, -- seconds between pickaxe swings
	CrystalsPerZone = 16, -- how many crystals each zone has
	CrystalRespawnTime = 7, -- seconds until a mined crystal grows back
	GiantChance = 0.15, -- chance that a crystal is a GIANT crystal
	GiantHealth = 5, -- giant crystals have 5x more health...
	GiantGems = 6, -- ...and give 6x more gems
	MaxPets = 3, -- how many pets can follow you at once (your best ones)
	RebirthBoost = 0.5, -- every rebirth gives +50% coins when selling
	RebirthBaseCost = 75000, -- coins needed for your first rebirth
	RebirthCostGrowth = 2.5, -- each rebirth costs this many times more
	SaveData = true, -- save progress (needs the game to be published)
	StudioStartCoins = 0, -- testing tip: set to 1000000 to get coins in Studio
}

--------------------------------------------------------------------------------
-- MAP LAYOUT (the hub is at the middle of the map, zones go in a line)
--------------------------------------------------------------------------------
Shared.Layout = {
	HubFront = 55, -- the hub goes from Z = 55 ...
	HubBack = -55, -- ... to Z = -55, then zone 1 starts
	ZoneLength = 170, -- how long each zone is
	HalfWidth = 84, -- the playable area goes from X = -84 to X = 84
}

--------------------------------------------------------------------------------
-- ZONES
--   Price  = coins needed to unlock the zone
--   Health = how many hits (with power 1) a crystal needs
--   Gems   = how many gems a crystal gives
--   Mood   = how the sky and colors look while you are in the zone
--------------------------------------------------------------------------------
Shared.Zones = {
	{
		Name = "Sunny Meadow",
		Emoji = "🌻",
		Price = 0,
		Health = 4,
		Gems = 3,
		CrystalColors = {
			Color3.fromRGB(80, 255, 150),
			Color3.fromRGB(255, 225, 80),
			Color3.fromRGB(110, 200, 255),
		},
		Ground = Enum.Material.Grass,
		Hills = Enum.Material.LeafyGrass,
		RockColor = Color3.fromRGB(125, 125, 135),
		Accent = Color3.fromRGB(110, 230, 120),
		Mood = {
			ClockTime = 14.5,
			Brightness = 3,
			Ambient = Color3.fromRGB(70, 70, 80),
			OutdoorAmbient = Color3.fromRGB(150, 150, 160),
			Exposure = 0,
			Density = 0.28,
			Haze = 1.2,
			Glare = 0.25,
			AtmosphereColor = Color3.fromRGB(200, 220, 255),
			Decay = Color3.fromRGB(110, 130, 165),
			Tint = Color3.fromRGB(255, 251, 242),
			Saturation = 0.15,
			Contrast = 0.08,
		},
	},
	{
		Name = "Crystal Caves",
		Emoji = "💜",
		Price = 2000,
		Health = 40,
		Gems = 30,
		CrystalColors = {
			Color3.fromRGB(190, 100, 255),
			Color3.fromRGB(255, 110, 220),
			Color3.fromRGB(90, 230, 255),
		},
		Ground = Enum.Material.Slate,
		Hills = Enum.Material.Rock,
		RockColor = Color3.fromRGB(80, 70, 100),
		Accent = Color3.fromRGB(190, 110, 255),
		Mood = {
			ClockTime = 14.5,
			Brightness = 2.4,
			Ambient = Color3.fromRGB(80, 65, 115),
			OutdoorAmbient = Color3.fromRGB(110, 95, 150),
			Exposure = 0.15,
			Density = 0.42,
			Haze = 2.2,
			Glare = 0,
			AtmosphereColor = Color3.fromRGB(175, 130, 255),
			Decay = Color3.fromRGB(70, 40, 120),
			Tint = Color3.fromRGB(240, 230, 255),
			Saturation = 0.25,
			Contrast = 0.12,
		},
	},
	{
		Name = "Lava Volcano",
		Emoji = "🌋",
		Price = 40000,
		Health = 400,
		Gems = 300,
		CrystalColors = {
			Color3.fromRGB(255, 140, 40),
			Color3.fromRGB(255, 60, 50),
			Color3.fromRGB(255, 210, 60),
		},
		Ground = Enum.Material.Basalt,
		Hills = Enum.Material.Basalt,
		RockColor = Color3.fromRGB(50, 40, 40),
		Accent = Color3.fromRGB(255, 120, 40),
		Mood = {
			ClockTime = 17.6,
			Brightness = 2.6,
			Ambient = Color3.fromRGB(90, 60, 50),
			OutdoorAmbient = Color3.fromRGB(150, 105, 90),
			Exposure = 0.1,
			Density = 0.45,
			Haze = 2.6,
			Glare = 0.6,
			AtmosphereColor = Color3.fromRGB(255, 150, 90),
			Decay = Color3.fromRGB(130, 50, 25),
			Tint = Color3.fromRGB(255, 238, 225),
			Saturation = 0.2,
			Contrast = 0.12,
		},
	},
	{
		Name = "Frozen Peaks",
		Emoji = "❄️",
		Price = 750000,
		Health = 4000,
		Gems = 3000,
		CrystalColors = {
			Color3.fromRGB(150, 230, 255),
			Color3.fromRGB(215, 240, 255),
			Color3.fromRGB(80, 140, 255),
		},
		Ground = Enum.Material.Snow,
		Hills = Enum.Material.Glacier,
		RockColor = Color3.fromRGB(150, 170, 195),
		Accent = Color3.fromRGB(150, 220, 255),
		Mood = {
			ClockTime = 11.5,
			Brightness = 3.4,
			Ambient = Color3.fromRGB(85, 95, 115),
			OutdoorAmbient = Color3.fromRGB(170, 185, 210),
			Exposure = -0.1,
			Density = 0.36,
			Haze = 1.8,
			Glare = 0.2,
			AtmosphereColor = Color3.fromRGB(225, 240, 255),
			Decay = Color3.fromRGB(160, 195, 235),
			Tint = Color3.fromRGB(238, 246, 255),
			Saturation = 0.02,
			Contrast = 0.1,
		},
	},
	{
		Name = "Galaxy Isles",
		Emoji = "🌌",
		Price = 15000000,
		Health = 40000,
		Gems = 30000,
		CrystalColors = {
			Color3.fromRGB(170, 90, 255),
			Color3.fromRGB(255, 80, 230),
			Color3.fromRGB(120, 255, 240),
		},
		Ground = Enum.Material.Asphalt,
		Hills = Enum.Material.Salt,
		RockColor = Color3.fromRGB(45, 35, 75),
		Accent = Color3.fromRGB(200, 120, 255),
		Mood = {
			ClockTime = 23.8,
			Brightness = 1.5,
			Ambient = Color3.fromRGB(70, 55, 120),
			OutdoorAmbient = Color3.fromRGB(120, 95, 190),
			Exposure = 0.35,
			Density = 0.3,
			Haze = 1,
			Glare = 0,
			AtmosphereColor = Color3.fromRGB(130, 90, 220),
			Decay = Color3.fromRGB(45, 25, 100),
			Tint = Color3.fromRGB(235, 225, 255),
			Saturation = 0.3,
			Contrast = 0.15,
		},
	},
}

--------------------------------------------------------------------------------
-- PICKAXES  (Power = damage per hit)
--   Glow = optional glowing color for fancy pickaxes
--------------------------------------------------------------------------------
Shared.Pickaxes = {
	{ Name = "Wooden Pickaxe", Power = 1, Price = 0, Color = Color3.fromRGB(150, 105, 60), Material = Enum.Material.Wood },
	{ Name = "Stone Pickaxe", Power = 2, Price = 60, Color = Color3.fromRGB(140, 140, 150), Material = Enum.Material.Slate },
	{ Name = "Copper Pickaxe", Power = 4, Price = 250, Color = Color3.fromRGB(215, 125, 70), Material = Enum.Material.Metal, Shine = 0.1 },
	{ Name = "Iron Pickaxe", Power = 10, Price = 900, Color = Color3.fromRGB(200, 205, 215), Material = Enum.Material.Metal, Shine = 0.15 },
	{ Name = "Gold Pickaxe", Power = 25, Price = 4000, Color = Color3.fromRGB(255, 200, 50), Material = Enum.Material.Metal, Shine = 0.25 },
	{
		Name = "Diamond Pickaxe",
		Power = 60,
		Price = 15000,
		Color = Color3.fromRGB(120, 230, 255),
		Material = Enum.Material.Glass,
		Glow = Color3.fromRGB(150, 240, 255),
	},
	{
		Name = "Ruby Pickaxe",
		Power = 150,
		Price = 60000,
		Color = Color3.fromRGB(230, 40, 70),
		Material = Enum.Material.Glass,
		Glow = Color3.fromRGB(255, 80, 110),
	},
	{
		Name = "Lava Pickaxe",
		Power = 400,
		Price = 250000,
		Color = Color3.fromRGB(70, 45, 40),
		Material = Enum.Material.CrackedLava,
		Glow = Color3.fromRGB(255, 120, 30),
	},
	{
		Name = "Frost Pickaxe",
		Power = 1200,
		Price = 1000000,
		Color = Color3.fromRGB(170, 225, 255),
		Material = Enum.Material.Ice,
		Glow = Color3.fromRGB(190, 240, 255),
	},
	{
		Name = "Galaxy Pickaxe",
		Power = 4000,
		Price = 5000000,
		Color = Color3.fromRGB(120, 60, 220),
		Material = Enum.Material.Glass,
		Glow = Color3.fromRGB(220, 120, 255),
	},
	{
		Name = "Rainbow Pickaxe",
		Power = 12000,
		Price = 25000000,
		Color = Color3.fromRGB(255, 90, 200),
		Material = Enum.Material.ForceField,
		Glow = Color3.fromRGB(255, 255, 255),
	},
}

--------------------------------------------------------------------------------
-- BACKPACKS  (Capacity = how many gems you can carry before selling)
--------------------------------------------------------------------------------
Shared.Backpacks = {
	{ Name = "Pouch", Capacity = 25, Price = 0, Color = Color3.fromRGB(150, 110, 70), Accent = Color3.fromRGB(115, 80, 50) },
	{ Name = "Sack", Capacity = 75, Price = 40, Color = Color3.fromRGB(205, 175, 125), Accent = Color3.fromRGB(160, 130, 90) },
	{ Name = "Backpack", Capacity = 250, Price = 300, Color = Color3.fromRGB(60, 140, 230), Accent = Color3.fromRGB(40, 90, 170) },
	{ Name = "Big Backpack", Capacity = 800, Price = 1500, Color = Color3.fromRGB(230, 70, 70), Accent = Color3.fromRGB(160, 40, 40) },
	{ Name = "Explorer Pack", Capacity = 2500, Price = 7500, Color = Color3.fromRGB(95, 175, 80), Accent = Color3.fromRGB(60, 110, 50) },
	{ Name = "Crystal Pack", Capacity = 8000, Price = 30000, Color = Color3.fromRGB(150, 90, 230), Accent = Color3.fromRGB(100, 50, 170) },
	{ Name = "Lava Pack", Capacity = 30000, Price = 150000, Color = Color3.fromRGB(65, 45, 45), Accent = Color3.fromRGB(255, 120, 30) },
	{ Name = "Frost Pack", Capacity = 120000, Price = 700000, Color = Color3.fromRGB(215, 240, 255), Accent = Color3.fromRGB(110, 180, 240) },
	{ Name = "Galaxy Pack", Capacity = 500000, Price = 3500000, Color = Color3.fromRGB(45, 30, 90), Accent = Color3.fromRGB(180, 90, 255) },
	{ Name = "Infinity Pack", Capacity = 2500000, Price = 20000000, Color = Color3.fromRGB(255, 215, 80), Accent = Color3.fromRGB(255, 250, 235) },
}

--------------------------------------------------------------------------------
-- PETS  (Bonus = extra gems. 0.25 means +25% gems)
--   Kind picks the look: dog, cat, bunny, fox, panda, dragon, unicorn, cosmic
--------------------------------------------------------------------------------
Shared.Pets = {
	{ Name = "Puppy", Kind = "dog", Bonus = 0.25, Price = 100, Color = Color3.fromRGB(235, 185, 125), Accent = Color3.fromRGB(150, 95, 60) },
	{ Name = "Kitty", Kind = "cat", Bonus = 0.5, Price = 750, Color = Color3.fromRGB(255, 165, 75), Accent = Color3.fromRGB(255, 240, 220) },
	{ Name = "Bunny", Kind = "bunny", Bonus = 1, Price = 4000, Color = Color3.fromRGB(245, 245, 250), Accent = Color3.fromRGB(255, 170, 200) },
	{ Name = "Fox", Kind = "fox", Bonus = 2, Price = 25000, Color = Color3.fromRGB(255, 120, 40), Accent = Color3.fromRGB(255, 250, 245) },
	{ Name = "Panda", Kind = "panda", Bonus = 3.5, Price = 120000, Color = Color3.fromRGB(250, 250, 250), Accent = Color3.fromRGB(35, 35, 40) },
	{ Name = "Dragon", Kind = "dragon", Bonus = 6, Price = 600000, Color = Color3.fromRGB(80, 200, 110), Accent = Color3.fromRGB(255, 200, 80) },
	{ Name = "Unicorn", Kind = "unicorn", Bonus = 10, Price = 3000000, Color = Color3.fromRGB(255, 240, 255), Accent = Color3.fromRGB(255, 140, 220) },
	{ Name = "Cosmic Cat", Kind = "cosmic", Bonus = 20, Price = 18000000, Color = Color3.fromRGB(110, 60, 230), Accent = Color3.fromRGB(90, 240, 255) },
}

--------------------------------------------------------------------------------
-- RARITY COLORS (used by the shop cards)
--------------------------------------------------------------------------------
Shared.Rarities = {
	{ Name = "Common", Color = Color3.fromRGB(165, 170, 185) },
	{ Name = "Uncommon", Color = Color3.fromRGB(90, 215, 105) },
	{ Name = "Rare", Color = Color3.fromRGB(70, 160, 255) },
	{ Name = "Epic", Color = Color3.fromRGB(180, 90, 255) },
	{ Name = "Legendary", Color = Color3.fromRGB(255, 185, 40) },
	{ Name = "Mythic", Color = Color3.fromRGB(255, 70, 140) },
}

function Shared.GetRarity(index: number, count: number)
	local r = math.clamp(math.ceil(index / count * #Shared.Rarities), 1, #Shared.Rarities)
	return Shared.Rarities[r]
end

--------------------------------------------------------------------------------
-- HELPER MATH
--------------------------------------------------------------------------------
local SUFFIXES = { "", "K", "M", "B", "T", "Qd", "Qn", "Sx", "Sp", "Oc", "No", "Dc" }

-- Turns 1234567 into "1.23M"
function Shared.Format(n: number?): string
	local value = math.floor(n or 0)
	if value < 1000 then
		return tostring(value)
	end
	local i = 1
	local v = value
	while v >= 1000 and i < #SUFFIXES do
		v /= 1000
		i += 1
	end
	local s
	if v >= 100 then
		s = tostring(math.floor(v))
	elseif v >= 10 then
		s = string.format("%.1f", math.floor(v * 10) / 10)
	else
		s = string.format("%.2f", math.floor(v * 100) / 100)
	end
	if string.find(s, ".", 1, true) then
		s = string.gsub(s, "0+$", "")
		s = string.gsub(s, "%.$", "")
	end
	return s .. SUFFIXES[i]
end

function Shared.ZoneStart(i: number): number
	return Shared.Layout.HubBack - (i - 1) * Shared.Layout.ZoneLength
end

function Shared.ZoneEnd(i: number): number
	return Shared.ZoneStart(i) - Shared.Layout.ZoneLength
end

-- Which zone is this Z position in? (0 = the hub)
function Shared.ZoneAt(z: number): number
	if z > Shared.Layout.HubBack then
		return 0
	end
	local i = math.floor((Shared.Layout.HubBack - z) / Shared.Layout.ZoneLength) + 1
	return math.clamp(i, 1, #Shared.Zones)
end

-- Where players appear when they teleport to a zone (0 = the hub)
function Shared.ZoneSpawn(i: number): Vector3
	if i == 0 then
		return Vector3.new(0, 4, 30)
	end
	return Vector3.new(0, 4, Shared.ZoneStart(i) - 16)
end

-- Your best pets (up to MaxPets), strongest first
function Shared.GetEquippedPets(owned: { [number]: boolean }): { number }
	local list = {}
	for index in pairs(owned) do
		if Shared.Pets[index] then
			table.insert(list, index)
		end
	end
	table.sort(list, function(a, b)
		return Shared.Pets[a].Bonus > Shared.Pets[b].Bonus
	end)
	while #list > Shared.Settings.MaxPets do
		table.remove(list)
	end
	return list
end

function Shared.GemMultiplier(owned: { [number]: boolean }): number
	local total = 1
	for _, index in ipairs(Shared.GetEquippedPets(owned)) do
		total += Shared.Pets[index].Bonus
	end
	return total
end

function Shared.CoinMultiplier(rebirths: number): number
	return 1 + rebirths * Shared.Settings.RebirthBoost
end

function Shared.RebirthCost(rebirths: number): number
	return math.floor(Shared.Settings.RebirthBaseCost * Shared.Settings.RebirthCostGrowth ^ rebirths)
end

--------------------------------------------------------------------------------
-- 3D MODEL BUILDERS
-- Every model is built around (0, 0, 0) and faces -Z (forward).
--------------------------------------------------------------------------------
local WHITE = Color3.new(1, 1, 1)
local BALL = Enum.PartType.Ball
local CYLINDER = Enum.PartType.Cylinder

local function part(parent: Instance, props): BasePart
	local p: any = Instance.new(props.Class or "Part")
	if props.Shape then
		p.Shape = props.Shape
	end
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.CastShadow = props.CastShadow ~= false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = props.Size
	p.CFrame = props.CFrame or CFrame.new()
	p.Color = props.Color or WHITE
	p.Material = props.Material or Enum.Material.SmoothPlastic
	p.Transparency = props.Transparency or 0
	p.Reflectance = props.Reflectance or 0
	p.Name = props.Name or "Part"
	p.Parent = parent
	return p
end
Shared.MakePart = part

-- PETS ------------------------------------------------------------------------
function Shared.BuildPet(index: number): Model
	local def = Shared.Pets[index]
	local model = Instance.new("Model")
	model.Name = def.Name

	local kind = def.Kind
	local bodyMaterial = Enum.Material.SmoothPlastic
	local body = part(model, { Name = "Body", Shape = BALL, Size = Vector3.one * 2.2, Color = def.Color, Material = bodyMaterial })
	model.PrimaryPart = body

	local dark = Color3.fromRGB(25, 25, 35)
	local pink = Color3.fromRGB(255, 140, 170)

	-- Face, cheeks and feet (every pet has these)
	for _, side in ipairs({ -1, 1 }) do
		if kind == "panda" then
			part(model, { Name = "Patch", Shape = BALL, Size = Vector3.one * 0.72, CFrame = CFrame.new(0.42 * side, 0.18, -0.8), Color = def.Accent })
		end
		part(model, { Name = "Eye", Shape = BALL, Size = Vector3.one * 0.5, CFrame = CFrame.new(0.42 * side, 0.22, -0.88), Color = dark })
		part(model, {
			Name = "Shine",
			Shape = BALL,
			Size = Vector3.one * 0.18,
			CFrame = CFrame.new(0.36 * side, 0.32, -1.1),
			Color = WHITE,
			Material = Enum.Material.Neon,
		})
		part(model, {
			Name = "Cheek",
			Shape = BALL,
			Size = Vector3.one * 0.38,
			CFrame = CFrame.new(0.72 * side, -0.12, -0.72),
			Color = pink,
			Transparency = 0.25,
		})
		part(model, { Name = "Foot", Shape = BALL, Size = Vector3.one * 0.6, CFrame = CFrame.new(0.5 * side, -0.95, -0.25), Color = def.Accent })
	end

	-- Pointy ears (diamond shape)
	local function pointyEars(color: Color3, inner: Color3?)
		for _, side in ipairs({ -1, 1 }) do
			local cf = CFrame.new(0.55 * side, 0.95, -0.05) * CFrame.Angles(0, 0, math.rad(45))
			part(model, { Name = "Ear", Size = Vector3.new(0.6, 0.6, 0.28), CFrame = cf, Color = color })
			if inner then
				part(model, { Name = "InnerEar", Size = Vector3.new(0.34, 0.34, 0.3), CFrame = cf * CFrame.new(0, 0, -0.02), Color = inner })
			end
		end
	end

	if kind == "dog" then
		for _, side in ipairs({ -1, 1 }) do
			part(model, {
				Name = "Ear",
				Size = Vector3.new(0.3, 0.9, 0.6),
				CFrame = CFrame.new(1.05 * side, 0.25, 0) * CFrame.Angles(0, 0, math.rad(15 * side)),
				Color = def.Accent,
			})
		end
		part(model, { Name = "Nose", Shape = BALL, Size = Vector3.one * 0.28, CFrame = CFrame.new(0, 0, -1.12), Color = dark })
		part(model, { Name = "Tail", Shape = BALL, Size = Vector3.one * 0.5, CFrame = CFrame.new(0, 0.15, 1.12), Color = def.Accent })
	elseif kind == "cat" then
		pointyEars(def.Color, pink)
		part(model, { Name = "Nose", Shape = BALL, Size = Vector3.one * 0.2, CFrame = CFrame.new(0, 0.02, -1.1), Color = pink })
		part(model, {
			Name = "Tail",
			Size = Vector3.new(0.28, 1.3, 0.28),
			CFrame = CFrame.new(0, 0.35, 1.15) * CFrame.Angles(math.rad(35), 0, 0),
			Color = def.Color,
		})
	elseif kind == "bunny" then
		for _, side in ipairs({ -1, 1 }) do
			local cf = CFrame.new(0.38 * side, 1.45, 0) * CFrame.Angles(0, 0, math.rad(-8 * side))
			part(model, { Name = "Ear", Size = Vector3.new(0.34, 1.3, 0.24), CFrame = cf, Color = def.Color })
			part(model, { Name = "InnerEar", Size = Vector3.new(0.18, 1, 0.26), CFrame = cf * CFrame.new(0, 0, -0.01), Color = def.Accent })
		end
		part(model, { Name = "Tail", Shape = BALL, Size = Vector3.one * 0.6, CFrame = CFrame.new(0, -0.3, 1.1), Color = WHITE })
		part(model, { Name = "Nose", Shape = BALL, Size = Vector3.one * 0.2, CFrame = CFrame.new(0, 0.02, -1.1), Color = def.Accent })
	elseif kind == "fox" then
		pointyEars(def.Color, Color3.fromRGB(60, 40, 35))
		part(model, { Name = "Snout", Shape = BALL, Size = Vector3.one * 0.9, CFrame = CFrame.new(0, -0.32, -0.75), Color = def.Accent })
		part(model, { Name = "Nose", Shape = BALL, Size = Vector3.one * 0.25, CFrame = CFrame.new(0, -0.2, -1.2), Color = dark })
		part(model, { Name = "Tail", Shape = BALL, Size = Vector3.one * 1.05, CFrame = CFrame.new(0, 0, 1.25), Color = def.Color })
		part(model, { Name = "TailTip", Shape = BALL, Size = Vector3.one * 0.6, CFrame = CFrame.new(0, 0.2, 1.72), Color = def.Accent })
	elseif kind == "panda" then
		for _, side in ipairs({ -1, 1 }) do
			part(model, { Name = "Ear", Shape = BALL, Size = Vector3.one * 0.65, CFrame = CFrame.new(0.72 * side, 0.88, 0), Color = def.Accent })
		end
		part(model, { Name = "Nose", Shape = BALL, Size = Vector3.one * 0.25, CFrame = CFrame.new(0, -0.05, -1.1), Color = def.Accent })
	elseif kind == "dragon" then
		for _, side in ipairs({ -1, 1 }) do
			part(model, {
				Name = "Horn",
				Size = Vector3.new(0.25, 0.65, 0.25),
				CFrame = CFrame.new(0.45 * side, 1.05, 0.1) * CFrame.Angles(math.rad(-20), 0, math.rad(-15 * side)),
				Color = def.Accent,
			})
			part(model, {
				Name = "Wing",
				Size = Vector3.new(0.12, 1.1, 1.5),
				CFrame = CFrame.new(1.3 * side, 0.4, 0.5) * CFrame.Angles(0, 0, math.rad(-35 * side)),
				Color = def.Accent,
			})
		end
		for i, pos in ipairs({ Vector3.new(0, 1.05, 0.35), Vector3.new(0, 0.8, 0.85), Vector3.new(0, 0.35, 1.1) }) do
			part(model, {
				Name = "Spike" .. i,
				Size = Vector3.new(0.12, 0.38, 0.38),
				CFrame = CFrame.new(pos) * CFrame.Angles(math.rad(45), 0, 0),
				Color = def.Accent,
			})
		end
		part(model, { Name = "Belly", Shape = BALL, Size = Vector3.one * 1.3, CFrame = CFrame.new(0, -0.45, -0.5), Color = Color3.fromRGB(190, 240, 170) })
	elseif kind == "unicorn" then
		part(model, {
			Name = "Horn",
			Shape = CYLINDER,
			Size = Vector3.new(1.1, 0.3, 0.3),
			CFrame = CFrame.new(0, 1.35, -0.45) * CFrame.Angles(math.rad(-25), 0, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(255, 215, 90),
			Material = Enum.Material.Neon,
		})
		local maneColors = { def.Accent, Color3.fromRGB(170, 130, 255), Color3.fromRGB(120, 210, 255) }
		for i, pos in ipairs({ Vector3.new(0, 1.0, 0.3), Vector3.new(0, 0.75, 0.78), Vector3.new(0, 0.3, 1.05) }) do
			part(model, { Name = "Mane" .. i, Shape = BALL, Size = Vector3.one * 0.62, CFrame = CFrame.new(pos), Color = maneColors[i] })
		end
		pointyEars(def.Color, def.Accent)
	elseif kind == "cosmic" then
		pointyEars(def.Color, def.Accent)
		part(model, {
			Name = "Aura",
			Shape = BALL,
			Size = Vector3.one * 2.5,
			Color = def.Accent,
			Material = Enum.Material.ForceField,
			CastShadow = false,
		})
		part(model, {
			Name = "Halo",
			Shape = CYLINDER,
			Size = Vector3.new(0.12, 1.5, 1.5),
			CFrame = CFrame.new(0, 1.6, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(255, 230, 120),
			Material = Enum.Material.Neon,
			CastShadow = false,
		})
		local sparkles = Instance.new("ParticleEmitter")
		sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkles.Color = ColorSequence.new(def.Accent)
		sparkles.LightEmission = 1
		sparkles.Size = NumberSequence.new(0.35, 0)
		sparkles.Lifetime = NumberRange.new(0.8, 1.4)
		sparkles.Speed = NumberRange.new(1, 2)
		sparkles.SpreadAngle = Vector2.new(180, 180)
		sparkles.Rate = 8
		sparkles.Parent = body
	end

	return model
end

-- PICKAXES --------------------------------------------------------------------
-- The handle points up (Y). The head is across the top (along Z).
function Shared.BuildPickaxe(index: number): Model
	local def = Shared.Pickaxes[index]
	local model = Instance.new("Model")
	model.Name = def.Name

	local handle = part(model, {
		Name = "Handle",
		Size = Vector3.new(0.38, 4.4, 0.38),
		Color = Color3.fromRGB(120, 78, 45),
		Material = Enum.Material.Wood,
	})
	model.PrimaryPart = handle
	part(model, {
		Name = "Wrap",
		Size = Vector3.new(0.48, 1, 0.48),
		CFrame = CFrame.new(0, -1.4, 0),
		Color = Color3.fromRGB(60, 40, 30),
		Material = Enum.Material.Fabric,
	})

	local headY = 2
	local head = {
		Color = def.Color,
		Material = def.Material,
		Reflectance = def.Shine or 0,
	}
	part(model, {
		Name = "HeadCenter",
		Size = Vector3.new(0.6, 0.72, 0.95),
		CFrame = CFrame.new(0, headY, 0),
		Color = head.Color,
		Material = head.Material,
		Reflectance = head.Reflectance,
	})
	for _, side in ipairs({ -1, 1 }) do
		part(model, {
			Name = "Pick",
			Size = Vector3.new(0.46, 0.5, 1.5),
			CFrame = CFrame.new(0, headY - 0.18, 0.95 * side) * CFrame.Angles(math.rad(14 * side), 0, 0),
			Color = head.Color,
			Material = head.Material,
			Reflectance = head.Reflectance,
		})
		part(model, {
			Name = "Tip",
			Size = Vector3.new(0.3, 0.32, 0.62),
			CFrame = CFrame.new(0, headY - 0.48, 1.75 * side) * CFrame.Angles(math.rad(30 * side), 0, 0),
			Color = def.Glow or head.Color,
			Material = if def.Glow then Enum.Material.Neon else head.Material,
		})
		if def.Glow then
			part(model, {
				Name = "Gem",
				Size = Vector3.new(0.12, 0.4, 0.4),
				CFrame = CFrame.new(0.3 * side, headY, 0) * CFrame.Angles(math.rad(45), 0, 0),
				Color = def.Glow,
				Material = Enum.Material.Neon,
			})
		end
	end
	if def.Glow then
		local light = Instance.new("PointLight")
		light.Color = def.Glow
		light.Range = 8
		light.Brightness = 1.2
		light.Parent = handle
	end
	return model
end

-- BACKPACKS -------------------------------------------------------------------
-- The outside of the backpack faces +Z (so it sits on a character's back).
function Shared.BuildBackpack(index: number): Model
	local def = Shared.Backpacks[index]
	local model = Instance.new("Model")
	model.Name = def.Name
	local s = 0.85 + index * 0.05
	local fabric = Enum.Material.Fabric

	local body = part(model, { Name = "Body", Size = Vector3.new(1.7, 1.9, 0.9) * s, Color = def.Color, Material = fabric })
	model.PrimaryPart = body
	part(model, {
		Name = "Flap",
		Size = Vector3.new(1.78, 0.5, 0.98) * s,
		CFrame = CFrame.new(0, 0.78 * s, 0),
		Color = def.Accent,
		Material = fabric,
	})
	part(model, {
		Name = "Pocket",
		Size = Vector3.new(1.2, 0.75, 0.3) * s,
		CFrame = CFrame.new(0, -0.4 * s, 0.55 * s),
		Color = def.Accent,
		Material = fabric,
	})
	part(model, {
		Name = "Buckle",
		Size = Vector3.new(0.3, 0.3, 0.12) * s,
		CFrame = CFrame.new(0, 0.5 * s, 0.5 * s),
		Color = Color3.fromRGB(255, 205, 70),
		Material = Enum.Material.Metal,
	})
	for _, side in ipairs({ -1, 1 }) do
		part(model, {
			Name = "SidePouch",
			Size = Vector3.new(0.26, 0.8, 0.6) * s,
			CFrame = CFrame.new(0.97 * s * side, -0.3 * s, 0),
			Color = def.Accent,
			Material = fabric,
		})
	end
	-- Shiny gems peeking out of the top
	local gemColor = Shared.Zones[math.clamp(math.ceil(index / 2), 1, #Shared.Zones)].CrystalColors[1]
	for i, x in ipairs({ -0.45, 0, 0.45 }) do
		part(model, {
			Name = "Gem" .. i,
			Size = Vector3.new(0.3, 0.6 + (i % 2) * 0.25, 0.3) * s,
			CFrame = CFrame.new(x * s, 1.1 * s, -0.1 * s) * CFrame.Angles(0, math.rad(45), math.rad(x * -30)),
			Color = gemColor,
			Material = Enum.Material.Neon,
		})
	end
	return model
end

return Shared
