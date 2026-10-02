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
	HatchCooldown = 3, -- seconds between hatching eggs

	-- Levels and dimensions
	DimensionsPerLevel = 3, -- level 1 = 3 dimensions, level 2 = 6, level 3 = 9, ...
	XPBase = 100, -- XP needed for the next level = XPBase x level ^ XPPower
	XPPower = 2.5, -- bigger = levels get harder faster
	LevelsPerZone = 3, -- you can't level up past level 1 in the first zone; every zone you unlock lets you go 3 levels higher (the last zone has no limit)
	LevelPowerBonus = 0.1, -- every level makes your pickaxe 10% stronger
	DimensionCrystals = 14, -- crystals on each dimension island
	DimensionHealth = 5, -- crystal health in dimension 1...
	DimensionHealthGrowth = 1.8, -- ...and x1.8 for every dimension after that
	DimensionGems = 4, -- gems per crystal in dimension 1...
	DimensionGemGrowth = 2, -- ...and x2 for every dimension after that
	MaxOpenDimensions = 8, -- how many dimension islands can exist at the same time
	DimensionCloseTime = 30, -- seconds an empty dimension stays before it disappears
	ShinyEvery = 5, -- every 5th dimension is a SHINY dimension (glowing, and 2x gems)
	DimensionPetGrowth = 1.45, -- pets from dimension eggs get 45% stronger every dimension
	DimensionPickaxePower = 6, -- the special pickaxe in dimension 1 has power 6...
	DimensionPickaxeGrowth = 2.1, -- ...and x2.1 in every dimension after that
	DimensionPickaxeShards = 5, -- it costs 5 Boss Shards in dimension 1...
	DimensionPickaxeShardsGrowth = 3, -- ...and 3 more in every dimension after that

	-- Golden crystals (rare and worth a lot)
	GoldenChance = 0.02, -- 2% of crystals grow back golden
	GoldenGems = 10, -- golden crystals give 10x gems...
	GoldenXP = 5, -- ...and 5x XP

	-- Sky obby
	ObbyRewardCrystals = 80, -- the obby pays as much as mining this many crystals
	ObbyCooldown = 240, -- seconds before the obby pays out again (every dimension has its own obby too)
	DimensionSellBonus = 0.25, -- selling in dimension d gives (1 + 0.25 x d) times more coins

	-- Moving around
	SprintSpeed = 10, -- hold Shift (or press the Sprint button) to run this much faster
	JumpHeight = 7.2, -- how high you jump (Roblox default)

	-- Digging: equip your shovel and dig up buried gems (the little dirt piles)
	DigSpotsPerZone = 6, -- buried gems in every zone
	DigSpotsPerDimension = 5, -- and on every dimension island
	DigHealth = 3, -- a buried gem needs as much digging as 3 crystals...
	DigGems = 4, -- ...and gives the gems of 4 crystals
	DigRespawnTime = 15, -- seconds until a new buried gem appears

	-- Diamond bosses (one in every zone and every dimension)
	BossHealth = 80, -- a boss has as much health as 80 crystals
	BossRewardCrystals = 150, -- beating it gives as many coins as 150 crystals
	BossXP = 40, -- ...and this much XP (x the zone number)
	BossRespawnTime = 75, -- seconds until the boss comes back
	BossDamage = 8, -- how much a boss attack hurts (you have 100 health)
	BossAttackEvery = 2.6, -- seconds between boss attacks

	-- Background music. Paste song IDs from the Toolbox (Audio tab) here, like
	-- MusicIds = { 1234567890, 9876543210 }. With none, a little music box plays.
	MusicIds = {},
	MusicVolume = 0.35,
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
local function zoneMood(clockTime: number, brightness: number, outdoor: Color3, atmosphere: Color3, decay: Color3, density: number, haze: number, extra: { [string]: any }?)
	local m = {
		ClockTime = clockTime,
		Brightness = brightness,
		Ambient = Color3.fromRGB(70, 72, 80),
		OutdoorAmbient = outdoor,
		Exposure = 0,
		Density = density,
		Haze = haze,
		Glare = 0.15,
		AtmosphereColor = atmosphere,
		Decay = decay,
		Tint = Color3.fromRGB(255, 252, 246),
		Saturation = 0.04,
		Contrast = 0.08,
	}
	for key, value in pairs(extra or {}) do
		m[key] = value
	end
	return m
end

Shared.Zones = {
	{
		Name = "Sunny Meadow",
		Emoji = "🌻",
		Price = 0,
		Health = 4,
		Gems = 3,
		-- emerald, citrine, aquamarine
		CrystalColors = { Color3.fromRGB(30, 150, 80), Color3.fromRGB(215, 160, 40), Color3.fromRGB(70, 170, 195) },
		Ground = Enum.Material.Grass,
		Hills = Enum.Material.Grass,
		RockColor = Color3.fromRGB(110, 105, 100),
		Accent = Color3.fromRGB(150, 210, 120),
		Mood = zoneMood(14.2, 2.6, Color3.fromRGB(128, 128, 132), Color3.fromRGB(199, 215, 235), Color3.fromRGB(106, 112, 125), 0.3, 1.4),
	},
	{
		Name = "Crystal Caves",
		Emoji = "💜",
		Price = 2000,
		Health = 40,
		Gems = 30,
		-- amethyst, rose quartz, sapphire
		CrystalColors = { Color3.fromRGB(120, 60, 180), Color3.fromRGB(205, 120, 160), Color3.fromRGB(45, 80, 190) },
		Ground = Enum.Material.Slate,
		Hills = Enum.Material.Rock,
		RockColor = Color3.fromRGB(78, 74, 80),
		Accent = Color3.fromRGB(175, 135, 220),
		Mood = zoneMood(14.2, 2, Color3.fromRGB(90, 85, 100), Color3.fromRGB(150, 140, 170), Color3.fromRGB(60, 55, 75), 0.42, 2, {
			Ambient = Color3.fromRGB(62, 58, 72),
			Exposure = 0.2,
		}),
	},
	{
		Name = "Lava Volcano",
		Emoji = "🌋",
		Price = 40000,
		Health = 400,
		Gems = 300,
		-- ruby, fire opal, garnet
		CrystalColors = { Color3.fromRGB(175, 20, 40), Color3.fromRGB(220, 90, 30), Color3.fromRGB(120, 18, 35) },
		Ground = Enum.Material.Basalt,
		Hills = Enum.Material.Basalt,
		RockColor = Color3.fromRGB(52, 46, 44),
		Accent = Color3.fromRGB(235, 120, 60),
		Mood = zoneMood(17.4, 2.3, Color3.fromRGB(125, 105, 95), Color3.fromRGB(190, 150, 125), Color3.fromRGB(110, 70, 50), 0.45, 2.4, {
			Glare = 0.4,
			Tint = Color3.fromRGB(255, 244, 232),
		}),
	},
	{
		Name = "Frozen Peaks",
		Emoji = "❄️",
		Price = 750000,
		Health = 4000,
		Gems = 3000,
		-- diamond, ice, sapphire
		CrystalColors = { Color3.fromRGB(215, 232, 245), Color3.fromRGB(125, 185, 225), Color3.fromRGB(55, 100, 200) },
		Ground = Enum.Material.Snow,
		Hills = Enum.Material.Glacier,
		RockColor = Color3.fromRGB(120, 125, 135),
		Accent = Color3.fromRGB(170, 215, 245),
		Mood = zoneMood(11.8, 3, Color3.fromRGB(150, 158, 175), Color3.fromRGB(215, 228, 245), Color3.fromRGB(150, 170, 200), 0.38, 1.8, {
			Tint = Color3.fromRGB(244, 248, 255),
		}),
	},
	{
		Name = "Galaxy Isles",
		Emoji = "🌌",
		Price = 15000000,
		Health = 40000,
		Gems = 30000,
		-- alexandrite, tanzanite, opal
		CrystalColors = { Color3.fromRGB(105, 55, 160), Color3.fromRGB(70, 65, 190), Color3.fromRGB(185, 215, 230) },
		Ground = Enum.Material.Asphalt,
		Hills = Enum.Material.Salt,
		RockColor = Color3.fromRGB(48, 44, 58),
		Accent = Color3.fromRGB(170, 150, 235),
		Mood = zoneMood(23.6, 1.4, Color3.fromRGB(95, 92, 125), Color3.fromRGB(95, 90, 140), Color3.fromRGB(40, 35, 70), 0.3, 1, {
			Exposure = 0.4,
			Ambient = Color3.fromRGB(60, 58, 80),
		}),
	},
}

--------------------------------------------------------------------------------
-- DIMENSIONS
--   Dimensions are floating islands you can visit from the portal at the spawn.
--   There are 12 themes. After dimension 12 they repeat with new crystal colors
--   (Candy World II, Neon City II, ...) and keep getting stronger forever.
--   Decor picks the decorations: candy, pillars, coral, trees, cactus, mushrooms,
--   clouds, spires, rainbow, ice, lava, cyber
--------------------------------------------------------------------------------
local function mood(clockTime: number, atmosphere: Color3, decay: Color3, tint: Color3, extra: { [string]: any }?)
	local m = {
		ClockTime = clockTime,
		Brightness = 2.8,
		Ambient = Color3.fromRGB(85, 80, 100),
		OutdoorAmbient = Color3.fromRGB(150, 150, 165),
		Exposure = 0,
		Density = 0.32,
		Haze = 1.6,
		Glare = 0.2,
		AtmosphereColor = atmosphere,
		Decay = decay,
		Tint = tint,
		Saturation = 0.2,
		Contrast = 0.1,
	}
	for key, value in pairs(extra or {}) do
		m[key] = value
	end
	return m
end
local NIGHT = { Brightness = 1.5, OutdoorAmbient = Color3.fromRGB(120, 105, 170), Exposure = 0.35 }

Shared.DimensionThemes = {
	{
		Name = "Candy World",
		Emoji = "🍭",
		Ground = Color3.fromRGB(255, 175, 215),
		GroundMaterial = Enum.Material.SmoothPlastic,
		Rock = Color3.fromRGB(255, 235, 245),
		Accent = Color3.fromRGB(255, 90, 170),
		Crystals = { Color3.fromRGB(255, 120, 200), Color3.fromRGB(120, 255, 210), Color3.fromRGB(255, 240, 120) },
		Decor = "candy",
		Mood = mood(13, Color3.fromRGB(255, 200, 230), Color3.fromRGB(200, 120, 170), Color3.fromRGB(255, 240, 248)),
	},
	{
		Name = "Neon City",
		Emoji = "🌃",
		Ground = Color3.fromRGB(25, 25, 40),
		GroundMaterial = Enum.Material.SmoothPlastic,
		Rock = Color3.fromRGB(45, 45, 70),
		Accent = Color3.fromRGB(0, 240, 255),
		Crystals = { Color3.fromRGB(0, 240, 255), Color3.fromRGB(255, 50, 220), Color3.fromRGB(150, 255, 60) },
		Decor = "pillars",
		Mood = mood(0.5, Color3.fromRGB(120, 80, 255), Color3.fromRGB(40, 20, 90), Color3.fromRGB(235, 225, 255), NIGHT),
	},
	{
		Name = "Ocean Reef",
		Emoji = "🐠",
		Ground = Color3.fromRGB(240, 220, 160),
		GroundMaterial = Enum.Material.Sand,
		Rock = Color3.fromRGB(200, 190, 170),
		Accent = Color3.fromRGB(60, 200, 255),
		Crystals = { Color3.fromRGB(70, 220, 255), Color3.fromRGB(255, 120, 110), Color3.fromRGB(80, 255, 200) },
		Decor = "coral",
		Mood = mood(12, Color3.fromRGB(120, 210, 255), Color3.fromRGB(40, 120, 200), Color3.fromRGB(225, 245, 255), { Density = 0.45 }),
	},
	{
		Name = "Jungle",
		Emoji = "🌴",
		Ground = Color3.fromRGB(70, 160, 60),
		GroundMaterial = Enum.Material.Grass,
		Rock = Color3.fromRGB(110, 115, 100),
		Accent = Color3.fromRGB(150, 255, 80),
		Crystals = { Color3.fromRGB(150, 255, 80), Color3.fromRGB(255, 200, 40), Color3.fromRGB(255, 120, 40) },
		Decor = "trees",
		Mood = mood(15, Color3.fromRGB(190, 230, 170), Color3.fromRGB(70, 120, 60), Color3.fromRGB(245, 255, 235), { Density = 0.4 }),
	},
	{
		Name = "Desert Dunes",
		Emoji = "🏜️",
		Ground = Color3.fromRGB(235, 195, 120),
		GroundMaterial = Enum.Material.Sand,
		Rock = Color3.fromRGB(190, 140, 90),
		Accent = Color3.fromRGB(255, 170, 40),
		Crystals = { Color3.fromRGB(255, 170, 40), Color3.fromRGB(255, 90, 60), Color3.fromRGB(255, 230, 120) },
		Decor = "cactus",
		Mood = mood(16.5, Color3.fromRGB(255, 210, 150), Color3.fromRGB(170, 110, 60), Color3.fromRGB(255, 245, 225), { Glare = 0.6 }),
	},
	{
		Name = "Toxic Swamp",
		Emoji = "☢️",
		Ground = Color3.fromRGB(70, 85, 45),
		GroundMaterial = Enum.Material.Mud,
		Rock = Color3.fromRGB(60, 60, 50),
		Accent = Color3.fromRGB(140, 255, 40),
		Crystals = { Color3.fromRGB(140, 255, 40), Color3.fromRGB(190, 80, 255), Color3.fromRGB(230, 255, 60) },
		Decor = "mushrooms",
		Mood = mood(18, Color3.fromRGB(160, 220, 90), Color3.fromRGB(60, 90, 30), Color3.fromRGB(240, 255, 225), { Density = 0.5, Haze = 2.6 }),
	},
	{
		Name = "Cloud Kingdom",
		Emoji = "☁️",
		Ground = Color3.fromRGB(245, 248, 255),
		GroundMaterial = Enum.Material.SmoothPlastic,
		Rock = Color3.fromRGB(220, 230, 250),
		Accent = Color3.fromRGB(255, 215, 90),
		Crystals = { Color3.fromRGB(255, 215, 90), Color3.fromRGB(140, 200, 255), Color3.fromRGB(255, 255, 255) },
		Decor = "clouds",
		Mood = mood(11.5, Color3.fromRGB(215, 235, 255), Color3.fromRGB(150, 190, 240), Color3.fromRGB(245, 250, 255), { Brightness = 3.4 }),
	},
	{
		Name = "Shadow Realm",
		Emoji = "🌑",
		Ground = Color3.fromRGB(30, 25, 40),
		GroundMaterial = Enum.Material.Slate,
		Rock = Color3.fromRGB(50, 40, 60),
		Accent = Color3.fromRGB(255, 40, 70),
		Crystals = { Color3.fromRGB(255, 40, 70), Color3.fromRGB(150, 40, 255), Color3.fromRGB(255, 255, 255) },
		Decor = "spires",
		Mood = mood(0, Color3.fromRGB(140, 40, 70), Color3.fromRGB(50, 10, 30), Color3.fromRGB(255, 225, 230), NIGHT),
	},
	{
		Name = "Rainbow Road",
		Emoji = "🌈",
		Ground = Color3.fromRGB(250, 250, 255),
		GroundMaterial = Enum.Material.Marble,
		Rock = Color3.fromRGB(230, 230, 240),
		Accent = Color3.fromRGB(255, 120, 200),
		Crystals = { Color3.fromRGB(255, 80, 80), Color3.fromRGB(80, 200, 255), Color3.fromRGB(255, 230, 60) },
		Decor = "rainbow",
		Mood = mood(13.5, Color3.fromRGB(230, 220, 255), Color3.fromRGB(170, 150, 230), Color3.fromRGB(255, 250, 255), { Saturation = 0.35 }),
	},
	{
		Name = "Crystal Glacier",
		Emoji = "🧊",
		Ground = Color3.fromRGB(190, 230, 255),
		GroundMaterial = Enum.Material.Glacier,
		Rock = Color3.fromRGB(170, 200, 230),
		Accent = Color3.fromRGB(120, 220, 255),
		Crystals = { Color3.fromRGB(120, 220, 255), Color3.fromRGB(220, 245, 255), Color3.fromRGB(100, 140, 255) },
		Decor = "ice",
		Mood = mood(10.5, Color3.fromRGB(220, 240, 255), Color3.fromRGB(150, 200, 240), Color3.fromRGB(238, 246, 255), { Brightness = 3.3 }),
	},
	{
		Name = "Magma Core",
		Emoji = "🔥",
		Ground = Color3.fromRGB(55, 40, 40),
		GroundMaterial = Enum.Material.Basalt,
		Rock = Color3.fromRGB(40, 30, 30),
		Accent = Color3.fromRGB(255, 110, 30),
		Crystals = { Color3.fromRGB(255, 110, 30), Color3.fromRGB(255, 50, 40), Color3.fromRGB(255, 220, 60) },
		Decor = "lava",
		Mood = mood(17.8, Color3.fromRGB(255, 130, 80), Color3.fromRGB(130, 40, 20), Color3.fromRGB(255, 235, 220), { Density = 0.48, Haze = 2.6 }),
	},
	{
		Name = "Cyber Grid",
		Emoji = "🤖",
		Ground = Color3.fromRGB(35, 45, 60),
		GroundMaterial = Enum.Material.DiamondPlate,
		Rock = Color3.fromRGB(60, 70, 90),
		Accent = Color3.fromRGB(60, 255, 180),
		Crystals = { Color3.fromRGB(60, 255, 180), Color3.fromRGB(60, 140, 255), Color3.fromRGB(255, 255, 255) },
		Decor = "cyber",
		Mood = mood(23.5, Color3.fromRGB(70, 140, 200), Color3.fromRGB(20, 40, 80), Color3.fromRGB(225, 240, 255), NIGHT),
	},
}

local ROMAN = { "", " II", " III", " IV", " V", " VI", " VII", " VIII", " IX", " X" }

local function shiftHue(color: Color3, amount: number): Color3
	if amount == 0 then
		return color
	end
	local h, sat, v = color:ToHSV()
	return Color3.fromHSV((h + amount) % 1, sat, v)
end

-- Everything about dimension number d (works for any number!)
function Shared.GetDimension(d: number)
	local themes = Shared.DimensionThemes
	local theme = themes[(d - 1) % #themes + 1]
	local cycle = math.floor((d - 1) / #themes)
	local hue = (cycle * 0.17) % 1
	local settings = Shared.Settings
	local shiny = d % settings.ShinyEvery == 0
	local colors = {}
	for i, color in ipairs(theme.Crystals) do
		local c = shiftHue(color, hue)
		if not shiny then
			-- normal dimensions have deeper, more natural gem colors
			local h, sat, v = c:ToHSV()
			c = Color3.fromHSV(h, sat * 0.8, v * 0.78)
		end
		colors[i] = c
	end
	local name = theme.Name .. (ROMAN[cycle + 1] or (" " .. (cycle + 1)))

	-- normal dimensions get softer, more natural colors and light.
	-- shiny ones keep the bright colors and get extra glow.
	local function soften(c: Color3): Color3
		if shiny then
			return c
		end
		local h, sat, v = c:ToHSV()
		return Color3.fromHSV(h, sat * 0.6, v * 0.85)
	end
	local skyMood = table.clone(theme.Mood)
	if shiny then
		skyMood.Saturation = theme.Mood.Saturation + 0.15
		skyMood.Exposure = theme.Mood.Exposure + 0.15
		skyMood.Glare = 0.6
	else
		skyMood.Saturation = theme.Mood.Saturation * 0.35 - 0.04
		skyMood.Glare = theme.Mood.Glare * 0.5
		skyMood.AtmosphereColor = theme.Mood.AtmosphereColor:Lerp(Color3.fromRGB(200, 205, 215), 0.45)
		skyMood.Tint = theme.Mood.Tint:Lerp(Color3.fromRGB(255, 253, 248), 0.6)
	end
	return {
		Number = d,
		Shiny = shiny,
		Name = if shiny then "Shiny " .. name else name,
		Emoji = theme.Emoji,
		Theme = theme,
		Level = math.ceil(d / settings.DimensionsPerLevel), -- level you need
		Health = math.floor(settings.DimensionHealth * settings.DimensionHealthGrowth ^ (d - 1)),
		Gems = math.floor(settings.DimensionGems * settings.DimensionGemGrowth ^ (d - 1)) * (if shiny then 2 else 1),
		XP = d,
		CrystalColors = colors,
		Accent = shiftHue(theme.Accent, hue),
		Ground = soften(theme.Ground),
		Rock = soften(theme.Rock),
		Mood = skyMood,
	}
end

-- How many dimensions you can visit at a level
function Shared.DimensionsUnlocked(level: number): number
	return level * Shared.Settings.DimensionsPerLevel
end

-- XP needed to go from this level to the next one
function Shared.XPNeeded(level: number): number
	return math.floor(Shared.Settings.XPBase * level ^ Shared.Settings.XPPower)
end

-- The highest level you can reach with this many zones unlocked
-- (zone 1: level 1, zone 2: level 4, zone 3: level 7, ... the last zone: no limit)
function Shared.MaxLevel(zone: number): number
	if zone >= #Shared.Zones then
		return math.huge
	end
	return 1 + (math.max(zone, 1) - 1) * Shared.Settings.LevelsPerZone
end

-- How much stronger your pickaxe is at this level (1.2 = 20% stronger)
function Shared.LevelPower(level: number): number
	return 1 + (level - 1) * Shared.Settings.LevelPowerBonus
end

--------------------------------------------------------------------------------
-- PICKAXES  (Power = damage per hit)
--   Glow = optional glowing color for fancy pickaxes
--------------------------------------------------------------------------------
Shared.Pickaxes = {
	{ Name = "Wooden Pickaxe", Power = 1, Price = 0, Color = Color3.fromRGB(150, 105, 60), Material = Enum.Material.Wood },
	{ Name = "Stone Pickaxe", Power = 2, Price = 60, Color = Color3.fromRGB(140, 140, 150), Material = Enum.Material.Slate },
	{ Name = "Copper Pickaxe", Power = 4, Price = 300, Color = Color3.fromRGB(215, 125, 70), Material = Enum.Material.Metal, Shine = 0.1 },
	{ Name = "Iron Pickaxe", Power = 10, Price = 1200, Color = Color3.fromRGB(200, 205, 215), Material = Enum.Material.Metal, Shine = 0.15 },
	{ Name = "Gold Pickaxe", Power = 25, Price = 6000, Color = Color3.fromRGB(255, 200, 50), Material = Enum.Material.Metal, Shine = 0.25 },
	{
		Name = "Diamond Pickaxe",
		Power = 60,
		Price = 25000,
		Color = Color3.fromRGB(120, 230, 255),
		Material = Enum.Material.Glass,
		Glow = Color3.fromRGB(150, 240, 255),
	},
	{
		Name = "Ruby Pickaxe",
		Power = 150,
		Price = 120000,
		Color = Color3.fromRGB(230, 40, 70),
		Material = Enum.Material.Glass,
		Glow = Color3.fromRGB(255, 80, 110),
	},
	{
		Name = "Lava Pickaxe",
		Power = 400,
		Price = 600000,
		Color = Color3.fromRGB(70, 45, 40),
		Material = Enum.Material.CrackedLava,
		Glow = Color3.fromRGB(255, 120, 30),
	},
	{
		Name = "Frost Pickaxe",
		Power = 1200,
		Price = 3000000,
		Color = Color3.fromRGB(170, 225, 255),
		Material = Enum.Material.Ice,
		Glow = Color3.fromRGB(190, 240, 255),
	},
	{
		Name = "Galaxy Pickaxe",
		Power = 4000,
		Price = 15000000,
		Color = Color3.fromRGB(120, 60, 220),
		Material = Enum.Material.Glass,
		Glow = Color3.fromRGB(220, 120, 255),
	},
	{
		Name = "Rainbow Pickaxe",
		Power = 12000,
		Price = 100000000,
		Color = Color3.fromRGB(255, 90, 200),
		Material = Enum.Material.ForceField,
		Glow = Color3.fromRGB(255, 255, 255),
	},
}

--------------------------------------------------------------------------------
-- BACKPACKS  (Capacity = how many gems you can carry before selling)
--------------------------------------------------------------------------------
Shared.Backpacks = {
	{ Name = "Pouch", Capacity = 30, Price = 0, Color = Color3.fromRGB(150, 110, 70), Accent = Color3.fromRGB(115, 80, 50) },
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
--   Kind picks the look: dog, cat, bunny, fox, panda, dragon, unicorn, cosmic,
--                        bee, slime, penguin, phoenix
--   Price  = pets with a price are sold in the Shop. The rest come from eggs!
--   Rarity = Common, Uncommon, Rare, Epic, Legendary, Mythic or Secret
--   Extra looks you can add: Material, Shine (0 to 1), Glow (a color),
--                            Aura (a color) and Size (1.3 = 30% bigger)
--------------------------------------------------------------------------------
local RGB = Color3.fromRGB
Shared.Pets = {
	-- Shop pets
	{ Name = "Puppy", Kind = "dog", Rarity = "Common", Bonus = 0.25, Price = 100, Color = RGB(235, 185, 125), Accent = RGB(150, 95, 60) },
	{ Name = "Kitty", Kind = "cat", Rarity = "Common", Bonus = 0.5, Price = 750, Color = RGB(255, 165, 75), Accent = RGB(255, 240, 220) },
	{ Name = "Bunny", Kind = "bunny", Rarity = "Uncommon", Bonus = 1, Price = 4000, Color = RGB(245, 245, 250), Accent = RGB(255, 170, 200) },
	{ Name = "Fox", Kind = "fox", Rarity = "Uncommon", Bonus = 2, Price = 25000, Color = RGB(255, 120, 40), Accent = RGB(255, 250, 245) },
	{ Name = "Panda", Kind = "panda", Rarity = "Rare", Bonus = 3.5, Price = 120000, Color = RGB(250, 250, 250), Accent = RGB(35, 35, 40) },
	{ Name = "Dragon", Kind = "dragon", Rarity = "Epic", Bonus = 6, Price = 600000, Color = RGB(80, 200, 110), Accent = RGB(255, 200, 80) },
	{ Name = "Unicorn", Kind = "unicorn", Rarity = "Legendary", Bonus = 10, Price = 3000000, Color = RGB(255, 240, 255), Accent = RGB(255, 140, 220) },
	{ Name = "Cosmic Cat", Kind = "cosmic", Rarity = "Mythic", Bonus = 20, Price = 18000000, Color = RGB(110, 60, 230), Accent = RGB(90, 240, 255) },

	-- Meadow Egg pets
	{ Name = "Bee", Kind = "bee", Rarity = "Common", Bonus = 0.3, Color = RGB(255, 210, 60), Accent = RGB(40, 35, 30) },
	{ Name = "Slime", Kind = "slime", Rarity = "Uncommon", Bonus = 0.6, Color = RGB(110, 240, 120), Accent = RGB(60, 180, 80) },
	{ Name = "Golden Puppy", Kind = "dog", Rarity = "Rare", Bonus = 1.5, Color = RGB(255, 200, 60), Accent = RGB(225, 150, 30), Material = Enum.Material.Metal, Shine = 0.3, Glow = RGB(255, 220, 110) },
	{ Name = "Rainbow Bunny", Kind = "bunny", Rarity = "Legendary", Bonus = 4, Color = RGB(255, 160, 225), Accent = RGB(150, 220, 255), Glow = RGB(255, 190, 240), Aura = RGB(255, 255, 255), Size = 1.2 },

	-- Crystal Egg pets
	{ Name = "Amethyst Slime", Kind = "slime", Rarity = "Common", Bonus = 1.2, Color = RGB(190, 110, 255), Accent = RGB(130, 60, 210) },
	{ Name = "Shadow Cat", Kind = "cat", Rarity = "Uncommon", Bonus = 2, Color = RGB(45, 40, 60), Accent = RGB(190, 110, 255) },
	{ Name = "Crystal Fox", Kind = "fox", Rarity = "Rare", Bonus = 5, Color = RGB(120, 220, 255), Accent = RGB(230, 250, 255), Material = Enum.Material.Glass, Glow = RGB(140, 230, 255) },
	{ Name = "Gem Dragon", Kind = "dragon", Rarity = "Legendary", Bonus = 15, Color = RGB(210, 90, 255), Accent = RGB(120, 240, 255), Material = Enum.Material.Glass, Glow = RGB(220, 120, 255), Aura = RGB(190, 110, 255), Size = 1.25 },

	-- Lava Egg pets
	{ Name = "Magma Slime", Kind = "slime", Rarity = "Common", Bonus = 3, Color = RGB(255, 100, 30), Accent = RGB(255, 200, 60), Glow = RGB(255, 120, 40) },
	{ Name = "Fire Fox", Kind = "fox", Rarity = "Uncommon", Bonus = 5, Color = RGB(255, 80, 30), Accent = RGB(255, 220, 80) },
	{ Name = "Phoenix", Kind = "phoenix", Rarity = "Rare", Bonus = 12, Color = RGB(255, 120, 30), Accent = RGB(255, 220, 60), Glow = RGB(255, 140, 40) },
	{ Name = "Inferno Dragon", Kind = "dragon", Rarity = "Legendary", Bonus = 40, Color = RGB(60, 30, 30), Accent = RGB(255, 100, 20), Material = Enum.Material.CrackedLava, Glow = RGB(255, 110, 30), Size = 1.25 },

	-- Frost Egg pets
	{ Name = "Penguin", Kind = "penguin", Rarity = "Common", Bonus = 8, Color = RGB(40, 45, 60), Accent = RGB(255, 160, 50) },
	{ Name = "Snow Bunny", Kind = "bunny", Rarity = "Uncommon", Bonus = 14, Color = RGB(240, 250, 255), Accent = RGB(160, 210, 255) },
	{ Name = "Ice Panda", Kind = "panda", Rarity = "Rare", Bonus = 30, Color = RGB(215, 240, 255), Accent = RGB(90, 150, 220), Material = Enum.Material.Ice, Glow = RGB(180, 230, 255) },
	{ Name = "Glacier Unicorn", Kind = "unicorn", Rarity = "Legendary", Bonus = 100, Color = RGB(200, 240, 255), Accent = RGB(120, 200, 255), Material = Enum.Material.Glass, Glow = RGB(180, 230, 255), Aura = RGB(180, 230, 255), Size = 1.25 },

	-- Galaxy Egg pets
	{ Name = "Star Slime", Kind = "slime", Rarity = "Common", Bonus = 22, Color = RGB(255, 230, 120), Accent = RGB(255, 170, 60), Glow = RGB(255, 235, 150) },
	{ Name = "Nebula Cat", Kind = "cat", Rarity = "Uncommon", Bonus = 40, Color = RGB(120, 60, 220), Accent = RGB(255, 120, 230), Aura = RGB(255, 120, 230) },
	{ Name = "Cosmic Dragon", Kind = "dragon", Rarity = "Rare", Bonus = 80, Color = RGB(40, 30, 90), Accent = RGB(120, 255, 240), Glow = RGB(120, 255, 240) },
	{ Name = "Galaxy Phoenix", Kind = "phoenix", Rarity = "Legendary", Bonus = 250, Color = RGB(170, 90, 255), Accent = RGB(120, 255, 240), Glow = RGB(200, 140, 255), Aura = RGB(120, 255, 240), Size = 1.3 },
	{ Name = "Void Kitty", Kind = "cosmic", Rarity = "Secret", Bonus = 1000, Color = RGB(15, 10, 25), Accent = RGB(255, 255, 255), Glow = RGB(255, 255, 255), Size = 1.35 },

	-- Sunny Egg pets (the better egg at the spawn)
	{ Name = "Honey Bee", Kind = "bee", Rarity = "Common", Bonus = 1, Color = RGB(255, 180, 40), Accent = RGB(70, 45, 25) },
	{ Name = "Meadow Fox", Kind = "fox", Rarity = "Uncommon", Bonus = 1.8, Color = RGB(215, 120, 60), Accent = RGB(250, 240, 225) },
	{ Name = "Flower Unicorn", Kind = "unicorn", Rarity = "Rare", Bonus = 3.5, Color = RGB(255, 245, 250), Accent = RGB(255, 150, 190), Glow = RGB(255, 200, 220) },
	{ Name = "Sun Phoenix", Kind = "phoenix", Rarity = "Legendary", Bonus = 9, Color = RGB(255, 200, 70), Accent = RGB(255, 240, 150), Glow = RGB(255, 220, 110), Aura = RGB(255, 230, 140), Size = 1.2 },

	-- Geode Egg pets
	{ Name = "Quartz Bunny", Kind = "bunny", Rarity = "Common", Bonus = 3, Color = RGB(235, 230, 240), Accent = RGB(200, 170, 230), Material = Enum.Material.Glass },
	{ Name = "Opal Cat", Kind = "cat", Rarity = "Uncommon", Bonus = 5, Color = RGB(200, 225, 235), Accent = RGB(255, 180, 210), Shine = 0.2 },
	{ Name = "Sapphire Panda", Kind = "panda", Rarity = "Rare", Bonus = 11, Color = RGB(235, 240, 255), Accent = RGB(45, 70, 190), Glow = RGB(110, 140, 255) },
	{ Name = "Diamond Unicorn", Kind = "unicorn", Rarity = "Legendary", Bonus = 35, Color = RGB(225, 245, 255), Accent = RGB(140, 220, 255), Material = Enum.Material.Glass, Glow = RGB(190, 240, 255), Aura = RGB(200, 240, 255), Size = 1.25 },

	-- Volcano Egg pets
	{ Name = "Ember Bee", Kind = "bee", Rarity = "Common", Bonus = 9, Color = RGB(255, 120, 40), Accent = RGB(40, 25, 20) },
	{ Name = "Lava Penguin", Kind = "penguin", Rarity = "Uncommon", Bonus = 15, Color = RGB(55, 35, 30), Accent = RGB(255, 140, 40) },
	{ Name = "Obsidian Dragon", Kind = "dragon", Rarity = "Rare", Bonus = 32, Color = RGB(35, 30, 40), Accent = RGB(255, 90, 40), Shine = 0.25, Glow = RGB(255, 110, 50) },
	{ Name = "Volcano Phoenix", Kind = "phoenix", Rarity = "Legendary", Bonus = 100, Color = RGB(200, 40, 25), Accent = RGB(255, 170, 40), Glow = RGB(255, 120, 40), Aura = RGB(255, 140, 60), Size = 1.25 },

	-- Blizzard Egg pets
	{ Name = "Frost Fox", Kind = "fox", Rarity = "Common", Bonus = 25, Color = RGB(225, 240, 255), Accent = RGB(120, 180, 240) },
	{ Name = "Yeti Panda", Kind = "panda", Rarity = "Uncommon", Bonus = 45, Color = RGB(245, 250, 255), Accent = RGB(110, 150, 200) },
	{ Name = "Aurora Cat", Kind = "cat", Rarity = "Rare", Bonus = 90, Color = RGB(120, 230, 200), Accent = RGB(190, 120, 255), Glow = RGB(150, 255, 220) },
	{ Name = "Blizzard Dragon", Kind = "dragon", Rarity = "Legendary", Bonus = 300, Color = RGB(200, 230, 255), Accent = RGB(70, 140, 230), Material = Enum.Material.Ice, Glow = RGB(180, 230, 255), Aura = RGB(200, 235, 255), Size = 1.3 },

	-- Nebula Egg pets
	{ Name = "Comet Bunny", Kind = "bunny", Rarity = "Common", Bonus = 70, Color = RGB(80, 70, 160), Accent = RGB(120, 240, 255) },
	{ Name = "Astro Penguin", Kind = "penguin", Rarity = "Uncommon", Bonus = 130, Color = RGB(30, 30, 70), Accent = RGB(255, 210, 90) },
	{ Name = "Supernova Unicorn", Kind = "unicorn", Rarity = "Rare", Bonus = 280, Color = RGB(255, 225, 180), Accent = RGB(255, 110, 200), Glow = RGB(255, 200, 150) },
	{ Name = "Black Hole Dragon", Kind = "dragon", Rarity = "Legendary", Bonus = 900, Color = RGB(15, 10, 25), Accent = RGB(190, 110, 255), Glow = RGB(190, 120, 255), Aura = RGB(160, 90, 255), Size = 1.35 },
}

--------------------------------------------------------------------------------
-- EGGS  (hatch them at the egg machines!)
--   Zone   = the zone you need to unlock first (the Meadow Egg is at the spawn)
--   Pets   = which pets can come out, and the chance of each one (in %)
--------------------------------------------------------------------------------
Shared.Eggs = {
	{
		Name = "Meadow Egg",
		Zone = 1,
		Price = 150,
		Color = RGB(250, 244, 222),
		Cap = RGB(150, 210, 120),
		Spots = RGB(95, 175, 80),
		Pets = {
			{ Name = "Bee", Chance = 60 },
			{ Name = "Slime", Chance = 30 },
			{ Name = "Golden Puppy", Chance = 9 },
			{ Name = "Rainbow Bunny", Chance = 1 },
		},
	},
	{
		Name = "Crystal Egg",
		Zone = 2,
		Price = 8000,
		Color = RGB(200, 165, 240),
		Cap = RGB(150, 110, 210),
		Spots = RGB(110, 200, 235),
		SpotMaterial = Enum.Material.Glass,
		Pets = {
			{ Name = "Amethyst Slime", Chance = 60 },
			{ Name = "Shadow Cat", Chance = 30 },
			{ Name = "Crystal Fox", Chance = 9 },
			{ Name = "Gem Dragon", Chance = 1 },
		},
	},
	{
		Name = "Lava Egg",
		Zone = 3,
		Price = 120000,
		Color = RGB(70, 40, 35),
		Material = Enum.Material.CrackedLava,
		Cap = RGB(45, 30, 28),
		Spots = RGB(255, 140, 40),
		SpotMaterial = Enum.Material.Neon,
		Pets = {
			{ Name = "Magma Slime", Chance = 60 },
			{ Name = "Fire Fox", Chance = 30 },
			{ Name = "Phoenix", Chance = 9 },
			{ Name = "Inferno Dragon", Chance = 1 },
		},
	},
	{
		Name = "Frost Egg",
		Zone = 4,
		Price = 2000000,
		Color = RGB(215, 240, 255),
		Material = Enum.Material.Glacier,
		Cap = RGB(240, 248, 255),
		Spots = RGB(110, 180, 255),
		Pattern = "stripes",
		Pets = {
			{ Name = "Penguin", Chance = 60 },
			{ Name = "Snow Bunny", Chance = 30 },
			{ Name = "Ice Panda", Chance = 9 },
			{ Name = "Glacier Unicorn", Chance = 1 },
		},
	},
	{
		Name = "Galaxy Egg",
		Zone = 5,
		Price = 30000000,
		Color = RGB(60, 40, 130),
		Cap = RGB(25, 20, 60),
		Spots = RGB(255, 130, 235),
		SpotMaterial = Enum.Material.Neon,
		Stars = true,
		Pets = {
			{ Name = "Star Slime", Chance = 59.9 },
			{ Name = "Nebula Cat", Chance = 30 },
			{ Name = "Cosmic Dragon", Chance = 9 },
			{ Name = "Galaxy Phoenix", Chance = 1 },
			{ Name = "Void Kitty", Chance = 0.1 },
		},
	},

	-- The better (and more expensive) egg in every zone
	{
		Name = "Sunny Egg",
		Zone = 1,
		Price = 2500,
		Color = RGB(255, 222, 120),
		Cap = RGB(255, 170, 60),
		Spots = RGB(255, 250, 235),
		Pattern = "stripes",
		Shine = 0.15,
		Pets = {
			{ Name = "Honey Bee", Chance = 60 },
			{ Name = "Meadow Fox", Chance = 30 },
			{ Name = "Flower Unicorn", Chance = 9 },
			{ Name = "Sun Phoenix", Chance = 1 },
		},
	},
	{
		Name = "Geode Egg",
		Zone = 2,
		Price = 45000,
		Color = RGB(120, 115, 125),
		Material = Enum.Material.Slate,
		Cap = RGB(90, 85, 95),
		Spots = RGB(175, 120, 235),
		SpotMaterial = Enum.Material.Glass,
		Pattern = "gems",
		Pets = {
			{ Name = "Quartz Bunny", Chance = 60 },
			{ Name = "Opal Cat", Chance = 30 },
			{ Name = "Sapphire Panda", Chance = 9 },
			{ Name = "Diamond Unicorn", Chance = 1 },
		},
	},
	{
		Name = "Volcano Egg",
		Zone = 3,
		Price = 650000,
		Color = RGB(40, 32, 34),
		Material = Enum.Material.Basalt,
		Cap = RGB(230, 90, 30),
		Spots = RGB(255, 170, 50),
		SpotMaterial = Enum.Material.Neon,
		Pattern = "stripes",
		Pets = {
			{ Name = "Ember Bee", Chance = 60 },
			{ Name = "Lava Penguin", Chance = 30 },
			{ Name = "Obsidian Dragon", Chance = 9 },
			{ Name = "Volcano Phoenix", Chance = 1 },
		},
	},
	{
		Name = "Blizzard Egg",
		Zone = 4,
		Price = 10000000,
		Color = RGB(235, 245, 255),
		Material = Enum.Material.Ice,
		Cap = RGB(130, 190, 245),
		Spots = RGB(255, 255, 255),
		Pattern = "gems",
		Pets = {
			{ Name = "Frost Fox", Chance = 60 },
			{ Name = "Yeti Panda", Chance = 30 },
			{ Name = "Aurora Cat", Chance = 9 },
			{ Name = "Blizzard Dragon", Chance = 1 },
		},
	},
	{
		Name = "Nebula Egg",
		Zone = 5,
		Price = 160000000,
		Color = RGB(150, 70, 190),
		Cap = RGB(40, 30, 90),
		Spots = RGB(120, 240, 255),
		SpotMaterial = Enum.Material.Neon,
		Pattern = "stripes",
		Stars = true,
		Pets = {
			{ Name = "Comet Bunny", Chance = 60 },
			{ Name = "Astro Penguin", Chance = 30 },
			{ Name = "Supernova Unicorn", Chance = 9 },
			{ Name = "Black Hole Dragon", Chance = 1 },
		},
	},
}

-- Look up pets by name, and check the eggs only use pets that exist
Shared.PetIndex = {}
for i, pet in ipairs(Shared.Pets) do
	Shared.PetIndex[pet.Name] = i
end
for _, egg in ipairs(Shared.Eggs) do
	for _, entry in ipairs(egg.Pets) do
		local index = Shared.PetIndex[entry.Name]
		if not index then
			error('[Crystal Rush] The ' .. egg.Name .. ' has a pet called "' .. entry.Name .. '", but there is no pet with that name in Shared.Pets')
		end
		entry.Index = index
		Shared.Pets[index].From = Shared.Pets[index].From or egg.Name
	end
end
for i, egg in ipairs(Shared.Eggs) do
	egg.Id = i
end

--------------------------------------------------------------------------------
-- SPECIAL THINGS IN EVERY DIMENSION
--   Every dimension has its own shop and its own egg.
--   * a special pickaxe (you pay with 💠 Boss Shards, which you only get from bosses)
--   * a special backpack (you pay with coins)
--   * an egg with 4 pets you can only find there
--   The further you go, the better they get. Shiny dimensions have shiny versions!
--------------------------------------------------------------------------------
local METAL = Enum.Material.Metal
Shared.DimensionItems = {
	{ Pickaxe = "Candy Pickaxe", Pack = "Candy Pack", Egg = "Candy Egg", Material = Enum.Material.SmoothPlastic },
	{ Pickaxe = "Neon Pickaxe", Pack = "Neon Pack", Egg = "Neon Egg", Material = Enum.Material.Glass },
	{ Pickaxe = "Cyber Pickaxe", Pack = "Cyber Pack", Egg = "Cyber Egg", Material = METAL },
	{ Pickaxe = "Coral Pickaxe", Pack = "Reef Pack", Egg = "Reef Egg", Material = Enum.Material.Glass },
	{ Pickaxe = "Vine Pickaxe", Pack = "Jungle Pack", Egg = "Jungle Egg", Material = Enum.Material.Wood },
	{ Pickaxe = "Sandstone Pickaxe", Pack = "Desert Pack", Egg = "Desert Egg", Material = Enum.Material.Sandstone },
	{ Pickaxe = "Toxic Pickaxe", Pack = "Toxic Pack", Egg = "Toxic Egg", Material = Enum.Material.Glass },
	{ Pickaxe = "Cloud Pickaxe", Pack = "Cloud Pack", Egg = "Cloud Egg", Material = Enum.Material.Marble },
	{ Pickaxe = "Shadow Pickaxe", Pack = "Shadow Pack", Egg = "Shadow Egg", Material = Enum.Material.Glass },
	{ Pickaxe = "Prism Pickaxe", Pack = "Rainbow Pack", Egg = "Rainbow Egg", Material = Enum.Material.Glass },
	{ Pickaxe = "Glacier Pickaxe", Pack = "Glacier Pack", Egg = "Glacier Egg", Material = Enum.Material.Ice },
	{ Pickaxe = "Magma Pickaxe", Pack = "Magma Pack", Egg = "Magma Egg", Material = Enum.Material.CrackedLava },
}

-- The 4 pets in each dimension's egg (Common, Uncommon, Rare, Legendary)
Shared.DimensionPets = {
	{ -- Candy World
		{ Name = "Gummy Slime", Kind = "slime", Color = RGB(255, 120, 190), Accent = RGB(255, 230, 120) },
		{ Name = "Lollipop Bunny", Kind = "bunny", Color = RGB(255, 235, 245), Accent = RGB(255, 110, 180) },
		{ Name = "Candy Unicorn", Kind = "unicorn", Color = RGB(255, 210, 235), Accent = RGB(120, 230, 210) },
		{ Name = "Sugar Dragon", Kind = "dragon", Color = RGB(255, 150, 210), Accent = RGB(255, 245, 160) },
	},
	{ -- Neon City
		{ Name = "Neon Cat", Kind = "cat", Color = RGB(40, 40, 70), Accent = RGB(0, 235, 255) },
		{ Name = "Laser Fox", Kind = "fox", Color = RGB(255, 60, 200), Accent = RGB(40, 40, 70) },
		{ Name = "Pixel Panda", Kind = "panda", Color = RGB(230, 240, 255), Accent = RGB(150, 60, 255) },
		{ Name = "Neon Phoenix", Kind = "phoenix", Color = RGB(30, 30, 60), Accent = RGB(0, 240, 255) },
	},
	{ -- Cyber Grid
		{ Name = "Robo Dog", Kind = "dog", Color = RGB(170, 180, 195), Accent = RGB(60, 255, 180), Material = METAL },
		{ Name = "Cyber Bee", Kind = "bee", Color = RGB(60, 255, 180), Accent = RGB(35, 45, 60) },
		{ Name = "Glitch Cat", Kind = "cat", Color = RGB(60, 140, 255), Accent = RGB(255, 255, 255) },
		{ Name = "Mecha Dragon", Kind = "dragon", Color = RGB(120, 130, 150), Accent = RGB(60, 255, 180), Material = METAL },
	},
	{ -- Ocean Reef
		{ Name = "Bubble Slime", Kind = "slime", Color = RGB(80, 210, 255), Accent = RGB(255, 255, 255) },
		{ Name = "Reef Penguin", Kind = "penguin", Color = RGB(30, 70, 110), Accent = RGB(255, 130, 110) },
		{ Name = "Coral Bunny", Kind = "bunny", Color = RGB(255, 140, 130), Accent = RGB(255, 230, 220) },
		{ Name = "Tide Dragon", Kind = "dragon", Color = RGB(40, 150, 200), Accent = RGB(120, 255, 220) },
	},
	{ -- Jungle
		{ Name = "Jungle Bee", Kind = "bee", Color = RGB(180, 230, 60), Accent = RGB(40, 60, 30) },
		{ Name = "Leaf Fox", Kind = "fox", Color = RGB(90, 170, 60), Accent = RGB(240, 250, 220) },
		{ Name = "Jungle Panda", Kind = "panda", Color = RGB(240, 245, 225), Accent = RGB(60, 110, 40) },
		{ Name = "Parrot Phoenix", Kind = "phoenix", Color = RGB(40, 180, 70), Accent = RGB(255, 200, 40) },
	},
	{ -- Desert Dunes
		{ Name = "Sand Slime", Kind = "slime", Color = RGB(235, 195, 120), Accent = RGB(200, 140, 70) },
		{ Name = "Desert Fox", Kind = "fox", Color = RGB(225, 170, 100), Accent = RGB(255, 245, 225) },
		{ Name = "Pharaoh Cat", Kind = "cat", Color = RGB(60, 50, 45), Accent = RGB(255, 200, 60) },
		{ Name = "Sun Dragon", Kind = "dragon", Color = RGB(255, 170, 40), Accent = RGB(255, 90, 50) },
	},
	{ -- Toxic Swamp
		{ Name = "Toxic Slime", Kind = "slime", Color = RGB(140, 255, 40), Accent = RGB(190, 80, 255) },
		{ Name = "Swamp Bee", Kind = "bee", Color = RGB(150, 200, 60), Accent = RGB(50, 40, 60) },
		{ Name = "Bog Panda", Kind = "panda", Color = RGB(200, 220, 160), Accent = RGB(70, 85, 45) },
		{ Name = "Venom Dragon", Kind = "dragon", Color = RGB(110, 60, 160), Accent = RGB(140, 255, 40) },
	},
	{ -- Cloud Kingdom
		{ Name = "Cloud Bunny", Kind = "bunny", Color = RGB(250, 252, 255), Accent = RGB(170, 210, 255) },
		{ Name = "Sky Penguin", Kind = "penguin", Color = RGB(110, 160, 230), Accent = RGB(255, 215, 90) },
		{ Name = "Angel Cat", Kind = "cosmic", Color = RGB(255, 252, 245), Accent = RGB(255, 215, 90) },
		{ Name = "Heaven Unicorn", Kind = "unicorn", Color = RGB(255, 255, 255), Accent = RGB(255, 215, 90) },
	},
	{ -- Shadow Realm
		{ Name = "Shadow Slime", Kind = "slime", Color = RGB(60, 40, 80), Accent = RGB(255, 40, 70) },
		{ Name = "Night Fox", Kind = "fox", Color = RGB(45, 35, 60), Accent = RGB(255, 60, 90) },
		{ Name = "Ghost Cat", Kind = "cosmic", Color = RGB(200, 200, 225), Accent = RGB(150, 40, 255) },
		{ Name = "Shadow Dragon", Kind = "dragon", Color = RGB(30, 20, 40), Accent = RGB(255, 40, 70) },
	},
	{ -- Rainbow Road
		{ Name = "Rainbow Slime", Kind = "slime", Color = RGB(255, 120, 200), Accent = RGB(120, 220, 255) },
		{ Name = "Prism Bunny", Kind = "bunny", Color = RGB(250, 250, 255), Accent = RGB(255, 120, 200) },
		{ Name = "Rainbow Cat", Kind = "cat", Color = RGB(255, 200, 80), Accent = RGB(120, 140, 255) },
		{ Name = "Rainbow Unicorn", Kind = "unicorn", Color = RGB(255, 245, 255), Accent = RGB(255, 90, 140) },
	},
	{ -- Crystal Glacier
		{ Name = "Frost Penguin", Kind = "penguin", Color = RGB(60, 100, 150), Accent = RGB(160, 230, 255) },
		{ Name = "Glacier Fox", Kind = "fox", Color = RGB(200, 235, 255), Accent = RGB(100, 150, 255) },
		{ Name = "Crystal Panda", Kind = "panda", Color = RGB(235, 248, 255), Accent = RGB(110, 200, 255), Material = Enum.Material.Glass },
		{ Name = "Ice Phoenix", Kind = "phoenix", Color = RGB(160, 225, 255), Accent = RGB(230, 250, 255) },
	},
	{ -- Magma Core
		{ Name = "Ember Slime", Kind = "slime", Color = RGB(255, 110, 30), Accent = RGB(255, 220, 60) },
		{ Name = "Magma Dog", Kind = "dog", Color = RGB(70, 40, 35), Accent = RGB(255, 110, 30) },
		{ Name = "Lava Cat", Kind = "cat", Color = RGB(255, 80, 40), Accent = RGB(60, 35, 30) },
		{ Name = "Magma Phoenix", Kind = "phoenix", Color = RGB(255, 90, 30), Accent = RGB(255, 220, 60) },
	},
}

local DIM_PET = 100000 -- dimension pets have numbers like 100000 + dimension x 10 + slot
local DIM_EGG = 1000 -- dimension eggs have numbers like 1000 + dimension
local DIM_RARITY = { "Common", "Uncommon", "Rare", "Legendary" }
local DIM_BONUS = { 0.4, 0.8, 2, 5 } -- pet boosts in dimension 1 (they grow every dimension)
local DIM_CHANCE = { 60, 30, 9, 1 }

local function dimensionInfo(d: number)
	local themes = Shared.DimensionThemes
	local themeIndex = (d - 1) % #themes + 1
	local cycle = (d - 1) // #themes
	return themeIndex, (ROMAN[cycle + 1] or (" " .. (cycle + 1))), (cycle * 0.17) % 1
end

function Shared.DimensionPetIndex(d: number, slot: number): number
	return DIM_PET + d * 10 + slot
end

local petCache: { [number]: any } = {}
-- Any pet by its number (shop and egg pets, and the pets from dimension eggs)
function Shared.GetPet(index: number)
	local def = Shared.Pets[index]
	if def or type(index) ~= "number" then
		return def
	end
	if petCache[index] then
		return petCache[index]
	end
	local d, slot = (index - DIM_PET) // 10, (index - DIM_PET) % 10
	if index ~= math.floor(index) or d < 1 or d > 100000 or slot < 1 or slot > 4 then
		return nil
	end
	local dim = Shared.GetDimension(d)
	local themeIndex, roman, hue = dimensionInfo(d)
	local template = Shared.DimensionPets[themeIndex][slot]
	local color, accent = shiftHue(template.Color, hue), shiftHue(template.Accent, hue)
	def = {
		Name = (if dim.Shiny then "Shiny " else "") .. template.Name .. roman,
		Kind = template.Kind,
		Rarity = DIM_RARITY[slot],
		Bonus = DIM_BONUS[slot] * Shared.Settings.DimensionPetGrowth ^ (d - 1) * (if dim.Shiny then 1.5 else 1),
		Color = color,
		Accent = accent,
		Material = template.Material,
		Glow = if slot >= 3 or dim.Shiny then accent else nil,
		Aura = if slot == 4 then accent else nil,
		Size = if slot == 4 then 1.2 else nil,
		Dimension = d,
		From = (if dim.Shiny then "Shiny " else "") .. Shared.DimensionItems[themeIndex].Egg .. roman,
	}
	petCache[index] = def
	return def
end

local eggCache: { [number]: any } = {}
-- Any egg by its number (zone eggs are 1, 2, 3 ..., dimension eggs are 1000 + the dimension)
function Shared.GetEgg(id: number)
	local egg = Shared.Eggs[id]
	if egg or type(id) ~= "number" then
		return egg
	end
	if eggCache[id] then
		return eggCache[id]
	end
	local d = id - DIM_EGG
	if id ~= math.floor(id) or d < 1 or d > 100000 then
		return nil
	end
	local dim = Shared.GetDimension(d)
	local themeIndex, roman = dimensionInfo(d)
	local pets = {}
	for slot = 1, 4 do
		table.insert(pets, { Index = Shared.DimensionPetIndex(d, slot), Chance = DIM_CHANCE[slot] })
	end
	egg = {
		Id = id,
		Name = (if dim.Shiny then "Shiny " else "") .. Shared.DimensionItems[themeIndex].Egg .. roman,
		Dimension = d,
		Price = math.floor(dim.Gems * math.min(40 + 25 * (d - 1), 1000)),
		Color = dim.Accent:Lerp(Color3.new(1, 1, 1), 0.45),
		Cap = dim.CrystalColors[1],
		Spots = dim.CrystalColors[2],
		SpotMaterial = if dim.Shiny then Enum.Material.Neon else Enum.Material.Glass,
		Pattern = ({ "spots", "stripes", "gems" })[d % 3 + 1],
		Stars = dim.Shiny,
		Shine = 0.1,
		Pets = pets,
	}
	eggCache[id] = egg
	return egg
end

function Shared.DimensionEggId(d: number): number
	return DIM_EGG + d
end

-- The special pickaxe sold in dimension d (costs 💠 Boss Shards)
function Shared.DimensionPickaxe(d: number)
	local dim = Shared.GetDimension(d)
	local themeIndex, roman = dimensionInfo(d)
	local settings = Shared.Settings
	return {
		Name = (if dim.Shiny then "Shiny " else "") .. Shared.DimensionItems[themeIndex].Pickaxe .. roman,
		Power = math.floor(settings.DimensionPickaxePower * settings.DimensionPickaxeGrowth ^ (d - 1) * (if dim.Shiny then 1.5 else 1)),
		Shards = settings.DimensionPickaxeShards + settings.DimensionPickaxeShardsGrowth * (d - 1),
		Color = dim.CrystalColors[1],
		Material = Shared.DimensionItems[themeIndex].Material,
		Glow = dim.Accent,
		Dimension = d,
	}
end

-- The special backpack sold in dimension d (costs coins)
function Shared.DimensionBackpack(d: number)
	local dim = Shared.GetDimension(d)
	local themeIndex, roman = dimensionInfo(d)
	return {
		Name = (if dim.Shiny then "Shiny " else "") .. Shared.DimensionItems[themeIndex].Pack .. roman,
		Capacity = dim.Gems * 50,
		Price = dim.Gems * 40,
		Color = dim.Ground,
		Accent = dim.Accent,
		Dimension = d,
	}
end

-- The pickaxe and backpack you really use (the better one of your normal and special one)
-- state needs Pickaxe, Backpack, DimPickaxe and DimBackpack
function Shared.BestPickaxe(state)
	local normal = Shared.Pickaxes[state.Pickaxe] or Shared.Pickaxes[1]
	if (state.DimPickaxe or 0) > 0 then
		local special = Shared.DimensionPickaxe(state.DimPickaxe)
		if special.Power > normal.Power then
			return special
		end
	end
	return normal
end

function Shared.BestBackpack(state)
	local normal = Shared.Backpacks[state.Backpack] or Shared.Backpacks[1]
	if (state.DimBackpack or 0) > 0 then
		local special = Shared.DimensionBackpack(state.DimBackpack)
		if special.Capacity > normal.Capacity then
			return special
		end
	end
	return normal
end

-- 💠 Boss Shards you get for beating the boss of a zone, or of a dimension
function Shared.BossShards(zoneIndex: number, dimension: number?): number
	if dimension then
		return 2 + dimension
	end
	return zoneIndex
end

--------------------------------------------------------------------------------
-- GADGETS (the Gadget Shop at the spawn). You keep them forever and can turn
-- them on and off. Gadgets that make you faster cost the most!
--   Kind: jump (jump height), speed (extra walk speed), sprint (extra sprint speed),
--         lucky (chance to get 10x gems from a crystal), gems (more gems)
--------------------------------------------------------------------------------
Shared.Gadgets = {
	{ Name = "Spring Shoes", Kind = "jump", Value = 11, Price = 1500, Look = "shoe", Color = RGB(90, 200, 120) },
	{ Name = "Running Shoes", Kind = "speed", Value = 4, Price = 5000, Look = "shoe", Color = RGB(70, 140, 255) },
	{ Name = "Sprint Charm", Kind = "sprint", Value = 6, Price = 35000, Look = "bolt", Color = RGB(255, 205, 60) },
	{ Name = "Gravity Coil", Kind = "jump", Value = 18, Price = 90000, Look = "coil", Color = RGB(150, 90, 255) },
	{ Name = "Speed Coil", Kind = "speed", Value = 9, Price = 500000, Look = "coil", Color = RGB(235, 70, 70) },
	{ Name = "Lucky Clover", Kind = "lucky", Value = 0.03, Price = 1500000, Look = "clover", Color = RGB(70, 190, 80) },
	{ Name = "Rocket Boots", Kind = "jump", Value = 28, Price = 6000000, Look = "rocket", Color = RGB(200, 200, 210) },
	{ Name = "Gem Magnet", Kind = "gems", Value = 0.25, Price = 15000000, Look = "magnet", Color = RGB(220, 50, 50) },
	{ Name = "Turbo Boots", Kind = "speed", Value = 16, Price = 60000000, Look = "rocket", Color = RGB(255, 140, 40) },
}

function Shared.GadgetText(gadget): string
	local v = gadget.Value
	if gadget.Kind == "jump" then
		return "🦘 Jump " .. string.format("%.1f", v / Shared.Settings.JumpHeight) .. "x higher"
	elseif gadget.Kind == "speed" then
		return "👟 +" .. v .. " walk speed"
	elseif gadget.Kind == "sprint" then
		return "⚡ +" .. v .. " sprint speed"
	elseif gadget.Kind == "lucky" then
		return "🍀 " .. math.floor(v * 100 + 0.5) .. "% chance: 10x gems"
	elseif gadget.Kind == "gems" then
		return "🧲 +" .. math.floor(v * 100 + 0.5) .. "% gems"
	end
	return ""
end

-- What your gadgets do together. owned/off = { [gadget number] = true }
function Shared.GadgetStats(owned: { [number]: boolean }, off: { [number]: boolean }?)
	local settings = Shared.Settings
	local stats = { Speed = 0, Jump = settings.JumpHeight, Sprint = settings.SprintSpeed, Lucky = 0, Gems = 1 }
	for i, gadget in ipairs(Shared.Gadgets) do
		if owned[i] and not (off and off[i]) then
			if gadget.Kind == "speed" then
				stats.Speed = math.max(stats.Speed, gadget.Value)
			elseif gadget.Kind == "jump" then
				stats.Jump = math.max(stats.Jump, gadget.Value)
			elseif gadget.Kind == "sprint" then
				stats.Sprint += gadget.Value
			elseif gadget.Kind == "lucky" then
				stats.Lucky += gadget.Value
			elseif gadget.Kind == "gems" then
				stats.Gems += gadget.Value
			end
		end
	end
	return stats
end

--------------------------------------------------------------------------------
-- RARITY COLORS
--------------------------------------------------------------------------------
Shared.Rarities = {
	{ Name = "Common", Color = RGB(165, 170, 185) },
	{ Name = "Uncommon", Color = RGB(90, 215, 105) },
	{ Name = "Rare", Color = RGB(70, 160, 255) },
	{ Name = "Epic", Color = RGB(180, 90, 255) },
	{ Name = "Legendary", Color = RGB(255, 185, 40) },
	{ Name = "Mythic", Color = RGB(255, 70, 140) },
	{ Name = "Secret", Color = RGB(40, 245, 220) },
}

function Shared.RarityRank(name: string): number
	for i, rarity in ipairs(Shared.Rarities) do
		if rarity.Name == name then
			return i
		end
	end
	return 1
end

function Shared.RarityColor(name: string): Color3
	return Shared.Rarities[Shared.RarityRank(name)].Color
end

-- Rarity color for shop items (pickaxes and backpacks get rarer as they go)
function Shared.GetRarity(index: number, count: number)
	local r = math.clamp(math.ceil(index / count * 6), 1, 6)
	return Shared.Rarities[r]
end

--------------------------------------------------------------------------------
-- FREE GIFTS, DAILY REWARDS AND QUESTS
--   Rewards are counted in "crystals": 10 means as many coins as mining
--   10 crystals in the best place you can mine. So they are always worth it!
--------------------------------------------------------------------------------
-- Free gifts you get for playing (Minutes = how long you have to play)
Shared.Gifts = {
	{ Minutes = 1, Crystals = 10 },
	{ Minutes = 3, Crystals = 15 },
	{ Minutes = 5, Egg = true },
	{ Minutes = 8, Crystals = 25 },
	{ Minutes = 12, Crystals = 35 },
	{ Minutes = 16, Egg = true },
	{ Minutes = 20, Crystals = 50 },
	{ Minutes = 30, Crystals = 75 },
	{ Minutes = 45, Egg = true },
	{ Minutes = 60, Crystals = 150 },
}

-- Daily rewards: come back every day to keep your streak!
Shared.DailyRewards = {
	{ Crystals = 30 },
	{ Crystals = 50 },
	{ Crystals = 80 },
	{ Crystals = 120, Egg = true },
	{ Crystals = 170 },
	{ Crystals = 230 },
	{ Crystals = 400, Egg = true },
}

-- The kinds of quests. Target = how many, based on how many quests you finished.
Shared.QuestKinds = {
	mine = { Text = "Mine %s crystals", Emoji = "⛏️", Target = function(done: number)
		return 20 + math.min(done, 30) * 5
	end },
	sell = { Text = "Sell your gems %s times", Emoji = "💰", Target = function(done: number)
		return 2 + math.min(math.floor(done / 4), 6)
	end },
	hatch = { Text = "Hatch %s eggs", Emoji = "🥚", Target = function(done: number)
		return 2 + math.min(math.floor(done / 3), 10)
	end },
	golden = { Text = "Mine %s golden crystal", Emoji = "✨", Target = function()
		return 1
	end },
	obby = { Text = "Finish the sky obby", Emoji = "🏃", Target = function()
		return 1
	end },
	giant = { Text = "Mine %s giant crystals", Emoji = "💎", Target = function(done: number)
		return 3 + math.min(math.floor(done / 3), 7)
	end },
}
Shared.QuestOrder = { "mine", "sell", "hatch", "giant", "obby", "golden" }

-- Coins you get for mining one crystal in the best place you can mine.
-- state needs Zone, Level, Rebirths and Pets (how many of each pet you own)
function Shared.CoinsPerCrystal(state): number
	local best = Shared.Zones[math.clamp(state.Zone, 1, #Shared.Zones)].Gems
	local dims = Shared.DimensionsUnlocked(state.Level)
	if dims > 2 then
		best = math.max(best, Shared.GetDimension(dims - 2).Gems)
	end
	return best * Shared.GemMultiplier(state.Pets) * Shared.CoinMultiplier(state.Rebirths)
end

function Shared.RewardCoins(state, crystals: number): number
	return math.max(25, math.floor(Shared.CoinsPerCrystal(state) * crystals))
end

function Shared.ObbyReward(state): number
	return math.max(300, Shared.RewardCoins(state, Shared.Settings.ObbyRewardCrystals))
end

-- Selling in a dimension gives more coins (the further, the more)
function Shared.DimensionSellBonus(d: number?): number
	if not d then
		return 1
	end
	return 1 + Shared.Settings.DimensionSellBonus * d
end

-- The obby in dimension d pays more the further you go
function Shared.DimensionObbyReward(state, d: number): number
	local dim = Shared.GetDimension(d)
	local coins = dim.Gems * Shared.Settings.ObbyRewardCrystals * Shared.GemMultiplier(state.Pets) * Shared.CoinMultiplier(state.Rebirths) * Shared.DimensionSellBonus(d)
	return math.floor(math.max(Shared.ObbyReward(state) * (1 + d * 0.5), coins))
end

function Shared.QuestText(quest): string
	local kind = Shared.QuestKinds[quest.Kind]
	return kind.Emoji .. " " .. string.format(kind.Text, Shared.Format(quest.Target))
end

function Shared.QuestReward(state, done: number): (number, number)
	local coins = Shared.RewardCoins(state, 40 * (1 + math.min(done, 50) * 0.02))
	local xp = math.max(5, math.floor(Shared.XPNeeded(state.Level) * 0.15))
	return coins, xp
end

function Shared.Today(): number
	return math.floor(os.time() / 86400)
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

-- Your best pets (up to MaxPets), strongest first.
-- owned = { [pet number] = how many you have }
function Shared.GetEquippedPets(owned: { [number]: number }): { number }
	local list = {}
	for index, count in pairs(owned) do
		if Shared.GetPet(index) and count > 0 then
			for _ = 1, math.min(count, Shared.Settings.MaxPets) do
				table.insert(list, index)
			end
		end
	end
	table.sort(list, function(a, b)
		local bonusA, bonusB = Shared.GetPet(a).Bonus, Shared.GetPet(b).Bonus
		if bonusA == bonusB then
			return a < b
		end
		return bonusA > bonusB
	end)
	while #list > Shared.Settings.MaxPets do
		table.remove(list)
	end
	return list
end

function Shared.GemMultiplier(owned: { [number]: number }): number
	local total = 1
	for _, index in ipairs(Shared.GetEquippedPets(owned)) do
		total += Shared.GetPet(index).Bonus
	end
	return total
end

-- Picks a random pet from an egg, using the chances
function Shared.RollEgg(eggIndex: number, random: Random): number
	local egg = Shared.GetEgg(eggIndex)
	local total = 0
	for _, entry in ipairs(egg.Pets) do
		total += entry.Chance
	end
	local roll = random:NextNumber(0, total)
	for _, entry in ipairs(egg.Pets) do
		roll -= entry.Chance
		if roll <= 0 then
			return entry.Index
		end
	end
	return egg.Pets[#egg.Pets].Index
end

-- Turns 2.4000001 into "2.4" (for boosts like x2.4)
function Shared.MultiplierText(n: number): string
	if n >= 1000 then
		return Shared.Format(n)
	end
	local s = string.format("%.2f", n)
	s = string.gsub(s, "0+$", "")
	s = string.gsub(s, "%.$", "")
	return s
end

-- "+40%" style text for a pet bonus
function Shared.BonusText(bonus: number): string
	return "+" .. Shared.Format(math.floor(bonus * 100 + 0.5)) .. "%"
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
	local def = Shared.GetPet(index)
	local model = Instance.new("Model")
	model.Name = def.Name

	local kind = def.Kind
	local bodyMaterial = def.Material or Enum.Material.SmoothPlastic
	local body
	if kind == "slime" then
		-- a squishy see-through blob
		body = part(model, {
			Name = "Body",
			Size = Vector3.new(2.6, 2.1, 2.6),
			Color = def.Color,
			Material = def.Material or Enum.Material.Glass,
			Transparency = 0.2,
			Reflectance = def.Shine or 0.1,
		})
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = body
	else
		body = part(model, {
			Name = "Body",
			Shape = BALL,
			Size = Vector3.one * 2.2,
			Color = def.Color,
			Material = bodyMaterial,
			Reflectance = def.Shine or 0,
		})
	end
	model.PrimaryPart = body

	local dark = Color3.fromRGB(25, 25, 35)
	local pink = Color3.fromRGB(255, 140, 170)
	local face = if kind == "slime" then 0.2 else 0 -- slimes are a bit wider
	local hasFeet = kind ~= "slime" and kind ~= "bee"
	-- very dark pets get glowing eyes so you can still see their face
	local eyeColor, eyeMaterial = dark, Enum.Material.SmoothPlastic
	if def.Color.R + def.Color.G + def.Color.B < 0.65 and kind ~= "penguin" then
		eyeColor, eyeMaterial = def.Accent, Enum.Material.Neon
	end

	-- Face, cheeks and feet
	for _, side in ipairs({ -1, 1 }) do
		if kind == "panda" or kind == "penguin" then
			part(model, {
				Name = "Patch",
				Shape = BALL,
				Size = Vector3.one * 0.72,
				CFrame = CFrame.new(0.42 * side, 0.18, -0.8),
				Color = if kind == "penguin" then WHITE else def.Accent,
			})
		end
		part(model, {
			Name = "Eye",
			Shape = BALL,
			Size = Vector3.one * 0.5,
			CFrame = CFrame.new(0.42 * side, 0.22, -0.88 - face),
			Color = eyeColor,
			Material = eyeMaterial,
		})
		part(model, {
			Name = "Shine",
			Shape = BALL,
			Size = Vector3.one * 0.18,
			CFrame = CFrame.new(0.36 * side, 0.32, -1.1 - face),
			Color = WHITE,
			Material = Enum.Material.Neon,
		})
		part(model, {
			Name = "Cheek",
			Shape = BALL,
			Size = Vector3.one * 0.38,
			CFrame = CFrame.new(0.72 * side, -0.12, -0.72 - face),
			Color = pink,
			Transparency = 0.25,
		})
		if hasFeet then
			part(model, { Name = "Foot", Shape = BALL, Size = Vector3.one * 0.6, CFrame = CFrame.new(0.5 * side, -0.95, -0.25), Color = def.Accent })
		end
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
			Color = def.Aura or def.Accent,
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
	elseif kind == "bee" then
		for _, z in ipairs({ 0.15, 0.62 }) do
			local width = 2 * math.sqrt(1.21 - z * z) + 0.08 -- just a bit wider than the body there
			part(model, {
				Name = "Stripe",
				Shape = CYLINDER,
				Size = Vector3.new(0.28, width, width),
				CFrame = CFrame.new(0, 0, z) * CFrame.Angles(0, math.rad(90), 0),
				Color = def.Accent,
			})
		end
		for _, side in ipairs({ -1, 1 }) do
			part(model, {
				Name = "Wing",
				Size = Vector3.new(0.08, 1, 1.3),
				CFrame = CFrame.new(0.7 * side, 1.1, 0.3) * CFrame.Angles(0, 0, math.rad(-30 * side)),
				Color = WHITE,
				Material = Enum.Material.Glass,
				Transparency = 0.35,
			})
			part(model, {
				Name = "Antenna",
				Size = Vector3.new(0.08, 0.6, 0.08),
				CFrame = CFrame.new(0.3 * side, 1.25, -0.5) * CFrame.Angles(math.rad(-20), 0, math.rad(-20 * side)),
				Color = def.Accent,
			})
			part(model, { Name = "AntennaTip", Shape = BALL, Size = Vector3.one * 0.22, CFrame = CFrame.new(0.42 * side, 1.55, -0.62), Color = def.Accent })
		end
		part(model, {
			Name = "Stinger",
			Size = Vector3.new(0.22, 0.22, 0.5),
			CFrame = CFrame.new(0, -0.1, 1.2),
			Color = def.Accent,
		})
	elseif kind == "slime" then
		part(model, { Name = "Core", Shape = BALL, Size = Vector3.one * 1, CFrame = CFrame.new(0, -0.15, 0.2), Color = def.Accent, Material = Enum.Material.Neon })
		part(model, { Name = "Drop", Shape = BALL, Size = Vector3.one * 0.6, CFrame = CFrame.new(0.15, 1.05, 0.25), Color = def.Color, Material = Enum.Material.Glass, Transparency = 0.2 })
	elseif kind == "penguin" then
		part(model, { Name = "Belly", Shape = BALL, Size = Vector3.one * 1.6, CFrame = CFrame.new(0, -0.3, -0.5), Color = WHITE })
		part(model, {
			Name = "Beak",
			Size = Vector3.new(0.35, 0.22, 0.4),
			CFrame = CFrame.new(0, -0.02, -1.15),
			Color = def.Accent,
		})
		for _, side in ipairs({ -1, 1 }) do
			part(model, {
				Name = "Flipper",
				Size = Vector3.new(0.18, 1, 0.5),
				CFrame = CFrame.new(1.05 * side, -0.15, 0) * CFrame.Angles(0, 0, math.rad(20 * side)),
				Color = def.Color,
			})
		end
	elseif kind == "phoenix" then
		part(model, { Name = "Beak", Size = Vector3.new(0.3, 0.25, 0.4), CFrame = CFrame.new(0, -0.05, -1.15), Color = def.Accent })
		for i, tilt in ipairs({ -25, 0, 25 }) do
			part(model, {
				Name = "Crest" .. i,
				Size = Vector3.new(0.12, 0.75, 0.22),
				CFrame = CFrame.new(0, 1.2, -0.1 + i * 0.12) * CFrame.Angles(math.rad(tilt + 15), 0, 0),
				Color = def.Accent,
				Material = Enum.Material.Neon,
			})
			part(model, {
				Name = "TailFeather" .. i,
				Size = Vector3.new(0.14, 0.3, 1.5),
				CFrame = CFrame.new(0, 0.1, 1.45) * CFrame.Angles(math.rad(-15), math.rad(tilt), 0),
				Color = def.Accent,
				Material = Enum.Material.Neon,
			})
		end
		for _, side in ipairs({ -1, 1 }) do
			part(model, {
				Name = "Wing",
				Size = Vector3.new(0.12, 1.25, 1.6),
				CFrame = CFrame.new(1.3 * side, 0.45, 0.4) * CFrame.Angles(0, 0, math.rad(-40 * side)),
				Color = def.Accent,
				Material = Enum.Material.Neon,
			})
		end
		local flames = Instance.new("ParticleEmitter")
		flames.Texture = "rbxasset://textures/particles/fire_main.dds"
		flames.Color = ColorSequence.new(def.Accent, def.Color)
		flames.LightEmission = 1
		flames.Size = NumberSequence.new(0.9, 0)
		flames.Lifetime = NumberRange.new(0.4, 0.8)
		flames.Speed = NumberRange.new(1, 2)
		flames.Rate = 12
		flames.Parent = body
	end

	-- Extra looks for rare pets
	if def.Aura and kind ~= "cosmic" then
		part(model, {
			Name = "Aura",
			Shape = BALL,
			Size = Vector3.one * 2.7,
			Color = def.Aura,
			Material = Enum.Material.ForceField,
			CastShadow = false,
		})
	end
	if def.Glow then
		local glow = Instance.new("PointLight")
		glow.Color = def.Glow
		glow.Range = 9
		glow.Brightness = 1.5
		glow.Parent = body
		local sparkles = Instance.new("ParticleEmitter")
		sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkles.Color = ColorSequence.new(def.Glow)
		sparkles.LightEmission = 1
		sparkles.Size = NumberSequence.new(0.3, 0)
		sparkles.Lifetime = NumberRange.new(0.6, 1.2)
		sparkles.Speed = NumberRange.new(0.5, 1.5)
		sparkles.SpreadAngle = Vector2.new(180, 180)
		sparkles.Rate = 5
		sparkles.Parent = body
	end
	if def.Size and def.Size ~= 1 then
		model:ScaleTo(def.Size)
	end

	return model
end

-- EGGS ------------------------------------------------------------------------
-- An egg is 4 wide and 5.2 tall: x²/4 + y²/6.76 + z²/4 = 1
local EGG_W, EGG_H = 2, 2.6

local function ellipsoid(parent: Instance, props): BasePart
	local p = part(parent, props)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- A point on the egg's surface (theta = angle from the top, phi = around), and the way out
local function eggSurface(theta: number, phi: number): (Vector3, Vector3)
	local pos = Vector3.new(EGG_W * math.sin(theta) * math.cos(phi), EGG_H * math.cos(theta), EGG_W * math.sin(theta) * math.sin(phi))
	local normal = Vector3.new(pos.X / (EGG_W * EGG_W), pos.Y / (EGG_H * EGG_H), pos.Z / (EGG_W * EGG_W)).Unit
	return pos, normal
end

-- A thin flat piece lying on the egg's shell
local function onShell(theta: number, phi: number, lift: number): CFrame
	local pos, normal = eggSurface(theta, phi)
	return CFrame.lookAt(pos + normal * lift, pos + normal * (lift + 1))
end

function Shared.BuildEgg(index: number): Model
	local def = Shared.GetEgg(index)
	local model = Instance.new("Model")
	model.Name = def.Name
	local material = def.Material or Enum.Material.SmoothPlastic
	local shine = def.Shine or 0.08
	local shell = ellipsoid(model, {
		Name = "Shell",
		Size = Vector3.new(EGG_W * 2, EGG_H * 2, EGG_W * 2),
		Color = def.Color,
		Material = material,
		Reflectance = shine,
	})
	model.PrimaryPart = shell
	local capColor = def.Cap or def.Color:Lerp(def.Spots, 0.5)
	-- the top half has another color (a slightly bigger egg, pushed up a little)
	ellipsoid(model, {
		Name = "Cap",
		Size = Vector3.new(EGG_W * 2.02, EGG_H * 2, EGG_W * 2.02),
		CFrame = CFrame.new(0, 0.12, 0),
		Color = capColor,
		Material = material,
		Reflectance = shine,
	})
	-- a zigzag edge between the two colors
	local edgeTheta = math.acos(-0.5 / EGG_H)
	local teeth = 14
	for k = 0, teeth - 1 do
		local phi = k / teeth * math.pi * 2
		part(model, {
			Name = "Zigzag",
			Size = Vector3.new(0.62, 0.62, 0.06),
			CFrame = onShell(edgeTheta, phi, 0.01) * CFrame.Angles(0, 0, math.rad(45)),
			Color = capColor,
			Material = material,
			Reflectance = shine,
		})
	end

	local pattern = def.Pattern or "spots"
	if pattern == "spots" then
		local spots = { { 1.75, 0.3, 0.95 }, { 2.05, 1.5, 0.8 }, { 2.4, 2.7, 0.7 }, { 1.85, 3.6, 0.9 }, { 2.25, 4.7, 0.75 }, { 1.9, 5.6, 0.6 } }
		for _, spot in ipairs(spots) do
			ellipsoid(model, {
				Name = "Spot",
				Size = Vector3.new(spot[3], spot[3], 0.14),
				CFrame = onShell(spot[1], spot[2], 0.0),
				Color = def.Spots,
				Material = def.SpotMaterial or Enum.Material.SmoothPlastic,
			})
		end
		for i, spot in ipairs({ { 0.55, 1 }, { 0.95, 2.6 }, { 1.05, 4.4 }, { 0.75, 5.5 } }) do
			ellipsoid(model, {
				Name = "TopSpot",
				Size = Vector3.new(0.7 - i * 0.06, 0.7 - i * 0.06, 0.14),
				CFrame = onShell(spot[1], spot[2], 0.13),
				Color = def.Spots:Lerp(Color3.new(1, 1, 1), 0.35),
				Material = def.SpotMaterial or Enum.Material.SmoothPlastic,
			})
		end
	elseif pattern == "stripes" then
		for _, y in ipairs({ -1.45, 1.15 }) do
			local r = EGG_W * math.sqrt(1 - (y / EGG_H) ^ 2)
			ellipsoid(model, {
				Name = "Stripe",
				Size = Vector3.new(r * 2 + 0.16, 0.42, r * 2 + 0.16),
				CFrame = CFrame.new(0, y + (if y > 0 then 0.12 else 0), 0),
				Color = def.Spots,
				Material = def.SpotMaterial or material,
				Reflectance = shine,
			})
		end
	elseif pattern == "gems" then
		-- little crystals stuck in the shell, like a geode
		for k = 0, 9 do
			local theta = 0.5 + (k % 3) * 0.55 + (k % 2) * 0.2
			local phi = k * 2.4
			part(model, {
				Name = "ShellGem",
				Size = Vector3.new(0.38, 0.38, 0.7),
				CFrame = onShell(theta, phi, 0.1) * CFrame.Angles(math.rad(45), math.rad(45), 0),
				Color = def.Spots,
				Material = def.SpotMaterial or Enum.Material.Glass,
				Reflectance = 0.25,
			})
		end
	end
	if def.Stars then
		for k = 0, 11 do
			ellipsoid(model, {
				Name = "Star",
				Size = Vector3.new(0.18, 0.18, 0.08),
				CFrame = onShell(0.4 + (k * 0.71) % 2.3, k * 1.9, 0.14),
				Color = Color3.fromRGB(255, 250, 220),
				Material = Enum.Material.Neon,
			})
		end
	end
	-- a soft shiny spot, like light on a real egg
	ellipsoid(model, {
		Name = "Highlight",
		Size = Vector3.new(0.75, 1.2, 0.1),
		CFrame = onShell(0.75, -2.2, 0.14) * CFrame.Angles(0, 0, math.rad(25)),
		Color = Color3.new(1, 1, 1),
		Transparency = 0.55,
		CastShadow = false,
	})
	return model
end

-- PICKAXES --------------------------------------------------------------------
-- The handle points up (Y). The head is across the top (along Z).
-- index can be a pickaxe number or a pickaxe (like a dimension's special pickaxe)
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- turns a cylinder so it stands up

-- A textured material for the plates on the side of a pickaxe head
local PLATE_MATERIAL = {
	[Enum.Material.Metal] = Enum.Material.DiamondPlate,
	[Enum.Material.Wood] = Enum.Material.WoodPlanks,
	[Enum.Material.Slate] = Enum.Material.Rock,
	[Enum.Material.CrackedLava] = Enum.Material.Basalt,
	[Enum.Material.Ice] = Enum.Material.Glacier,
	[Enum.Material.Glass] = Enum.Material.Glass,
	[Enum.Material.ForceField] = Enum.Material.Glass,
	[Enum.Material.SmoothPlastic] = Enum.Material.SmoothPlastic,
	[Enum.Material.Sandstone] = Enum.Material.Limestone,
	[Enum.Material.Marble] = Enum.Material.Marble,
}

function Shared.BuildPickaxe(index: any): Model
	local def = if type(index) == "table" then index else Shared.Pickaxes[index]
	local model = Instance.new("Model")
	model.Name = def.Name
	local wood = Color3.fromRGB(122, 82, 50)
	local woodDark = Color3.fromRGB(92, 60, 36)
	local leather = Color3.fromRGB(70, 44, 30)
	local leatherDark = Color3.fromRGB(46, 30, 22)
	local rope = Color3.fromRGB(160, 130, 90)
	-- fancy pickaxes get gold fittings, the others steel
	local fancy = def.Glow ~= nil
	local metal = if fancy then Color3.fromRGB(205, 165, 75) else Color3.fromRGB(78, 78, 84)

	-- the Handle part is what your hand holds (it's invisible, the round shaft is what you see)
	local handle = part(model, { Name = "Handle", Size = Vector3.new(0.34, 4.4, 0.34), Transparency = 1 })
	model.PrimaryPart = handle
	part(model, { Name = "Shaft", Shape = CYLINDER, Size = Vector3.new(4.4, 0.36, 0.36), CFrame = UPRIGHT, Color = wood, Material = Enum.Material.Wood })
	-- wood grain lines along the handle
	for k = 0, 2 do
		local a = k * 2.1 + 0.4
		part(model, {
			Name = "Grain",
			Size = Vector3.new(0.035, 3.2, 0.06),
			CFrame = CFrame.new(math.cos(a) * 0.17, 0.4 + k * 0.15, math.sin(a) * 0.17) * CFrame.Angles(0, -a, 0),
			Color = woodDark,
			Material = Enum.Material.Wood,
		})
	end
	-- a leather grip, wound with straps
	part(model, { Name = "Grip", Shape = CYLINDER, Size = Vector3.new(1.5, 0.42, 0.42), CFrame = CFrame.new(0, -1.35, 0) * UPRIGHT, Color = leather, Material = Enum.Material.Fabric })
	for k = 0, 3 do
		part(model, {
			Name = "Wrap",
			Shape = CYLINDER,
			Size = Vector3.new(0.11, 0.46, 0.46),
			CFrame = CFrame.new(0, -0.72 - k * 0.38, 0) * UPRIGHT * CFrame.Angles(math.rad(if k % 2 == 0 then 12 else -12), 0, 0),
			Color = leatherDark,
			Material = Enum.Material.Fabric,
		})
	end
	part(model, { Name = "Pommel", Shape = CYLINDER, Size = Vector3.new(0.24, 0.5, 0.5), CFrame = CFrame.new(0, -2.2, 0) * UPRIGHT, Color = metal, Material = Enum.Material.Metal, Reflectance = 0.1 })
	part(model, { Name = "PommelKnob", Shape = BALL, Size = Vector3.one * 0.34, CFrame = CFrame.new(0, -2.36, 0), Color = metal, Material = Enum.Material.Metal, Reflectance = 0.1 })

	local headY = 2
	local headMaterial = def.Material or Enum.Material.Metal
	local plateMaterial = PLATE_MATERIAL[headMaterial] or headMaterial
	local light = def.Color:Lerp(Color3.new(1, 1, 1), 0.3)
	local dark = def.Color:Lerp(Color3.new(0, 0, 0), 0.35)
	local function headPart(name: string, size: Vector3, cf: CFrame, color: Color3?, material: Enum.Material?)
		return part(model, {
			Name = name,
			Size = size,
			CFrame = cf,
			Color = color or def.Color,
			Material = material or headMaterial,
			Reflectance = def.Shine or 0,
		})
	end
	-- the metal collar that holds the head on, tied with rope
	part(model, { Name = "Collar", Shape = CYLINDER, Size = Vector3.new(0.62, 0.5, 0.5), CFrame = CFrame.new(0, headY - 0.64, 0) * UPRIGHT, Color = metal, Material = Enum.Material.Metal })
	for k = 0, 1 do
		part(model, { Name = "Rope", Shape = CYLINDER, Size = Vector3.new(0.09, 0.55, 0.55), CFrame = CFrame.new(0, headY - 0.48 - k * 0.3, 0) * UPRIGHT, Color = rope, Material = Enum.Material.Fabric })
	end
	for k = 0, 3 do
		local a = k / 4 * math.pi * 2
		part(model, { Name = "CollarRivet", Shape = BALL, Size = Vector3.one * 0.12, CFrame = CFrame.new(math.cos(a) * 0.25, headY - 0.75, math.sin(a) * 0.25), Color = metal:Lerp(Color3.new(1, 1, 1), 0.3), Material = Enum.Material.Metal })
	end

	-- the head: a center block with textured plates, a ridge, and two curved picks
	headPart("HeadCenter", Vector3.new(0.62, 0.8, 1.0), CFrame.new(0, headY, 0))
	headPart("HeadTop", Vector3.new(0.5, 0.12, 0.92), CFrame.new(0, headY + 0.45, 0), light)
	for _, side in ipairs({ -1, 1 }) do
		headPart("Plate", Vector3.new(0.06, 0.6, 0.82), CFrame.new(0.33 * side, headY, 0), dark, plateMaterial)
		headPart("Pick", Vector3.new(0.52, 0.52, 0.9), CFrame.new(0, headY - 0.05, 0.85 * side) * CFrame.Angles(math.rad(8 * side), 0, 0))
		headPart("PickOuter", Vector3.new(0.42, 0.42, 0.8), CFrame.new(0, headY - 0.25, 1.55 * side) * CFrame.Angles(math.rad(22 * side), 0, 0))
		-- a shiny sharpened edge under the pick
		headPart("Edge", Vector3.new(0.3, 0.07, 0.78), CFrame.new(0, headY - 0.45, 1.5 * side) * CFrame.Angles(math.rad(22 * side), 0, 0), light, Enum.Material.Metal)
		-- engraved lines on both sides of the pick
		for _, face in ipairs({ -1, 1 }) do
			headPart("Engraving", Vector3.new(0.03, 0.07, 0.7), CFrame.new(0.27 * face, headY - 0.05, 0.85 * side) * CFrame.Angles(math.rad(8 * side), 0, 0), dark, Enum.Material.Metal)
		end
		headPart(
			"Tip",
			Vector3.new(0.28, 0.28, 0.5),
			CFrame.new(0, headY - 0.5, 2.05 * side) * CFrame.Angles(math.rad(38 * side), 0, 0),
			def.Glow or light,
			if def.Glow then Enum.Material.Neon else headMaterial
		)
		-- rivets on the head
		for _, z in ipairs({ -0.28, 0.28 }) do
			part(model, {
				Name = "Rivet",
				Shape = BALL,
				Size = Vector3.one * 0.14,
				CFrame = CFrame.new(0.37 * side, headY + 0.22, z),
				Color = metal,
				Material = Enum.Material.Metal,
			})
		end
		if def.Glow then
			-- a gem set into the head, with a gold frame
			part(model, { Name = "GemFrame", Size = Vector3.new(0.05, 0.5, 0.5), CFrame = CFrame.new(0.37 * side, headY - 0.05, 0) * CFrame.Angles(math.rad(45), 0, 0), Color = metal, Material = Enum.Material.Metal })
			part(model, {
				Name = "Gem",
				Size = Vector3.new(0.12, 0.36, 0.36),
				CFrame = CFrame.new(0.4 * side, headY - 0.05, 0) * CFrame.Angles(math.rad(45), 0, 0),
				Color = def.Glow,
				Material = Enum.Material.Glass,
				Reflectance = 0.35,
			})
		end
	end
	if def.Glow then
		local glow = Instance.new("PointLight")
		glow.Color = def.Glow
		glow.Range = 8
		glow.Brightness = 1
		glow.Parent = handle
	end
	return model
end

-- SHOVEL ----------------------------------------------------------------------
-- Like the pickaxe: the handle points up (Y) and the blade is at the top
function Shared.BuildShovel(): Model
	local model = Instance.new("Model")
	model.Name = "Shovel"
	local wood = Color3.fromRGB(150, 105, 62)
	local steel = Color3.fromRGB(150, 155, 162)
	local handle = part(model, { Name = "Handle", Size = Vector3.new(0.3, 4.2, 0.3), Transparency = 1 })
	model.PrimaryPart = handle
	part(model, { Name = "Shaft", Shape = CYLINDER, Size = Vector3.new(4.2, 0.3, 0.3), CFrame = UPRIGHT, Color = wood, Material = Enum.Material.Wood })
	-- D shaped grip at the bottom end
	for _, side in ipairs({ -1, 1 }) do
		part(model, {
			Name = "GripSide",
			Size = Vector3.new(0.14, 0.75, 0.14),
			CFrame = CFrame.new(0, -2.35, 0.26 * side) * CFrame.Angles(math.rad(-14 * side), 0, 0),
			Color = Color3.fromRGB(40, 40, 44),
		})
	end
	part(model, { Name = "GripBar", Shape = CYLINDER, Size = Vector3.new(0.66, 0.2, 0.2), CFrame = CFrame.new(0, -2.72, 0) * CFrame.Angles(0, math.rad(90), 0), Color = Color3.fromRGB(40, 40, 44) })
	-- the blade
	part(model, { Name = "Socket", Shape = CYLINDER, Size = Vector3.new(0.7, 0.38, 0.38), CFrame = CFrame.new(0, 2.25, 0) * UPRIGHT, Color = steel, Material = Enum.Material.Metal })
	part(model, { Name = "Blade", Size = Vector3.new(0.1, 1.2, 1.3), CFrame = CFrame.new(0, 3.1, 0), Color = steel, Material = Enum.Material.Metal, Reflectance = 0.1 })
	part(model, { Name = "BladeTip", Size = Vector3.new(0.1, 0.92, 0.92), CFrame = CFrame.new(0, 3.68, 0) * CFrame.Angles(math.rad(45), 0, 0), Color = steel, Material = Enum.Material.Metal, Reflectance = 0.1 })
	for _, side in ipairs({ -1, 1 }) do
		part(model, { Name = "Step", Size = Vector3.new(0.3, 0.08, 0.5), CFrame = CFrame.new(0.08, 2.52, 0.4 * side), Color = steel, Material = Enum.Material.Metal })
	end
	part(model, { Name = "Spine", Size = Vector3.new(0.16, 1.1, 0.16), CFrame = CFrame.new(0.06, 2.95, 0), Color = steel:Lerp(Color3.new(0, 0, 0), 0.2), Material = Enum.Material.Metal })
	return model
end

-- BACKPACKS -------------------------------------------------------------------
-- The outside of the backpack faces +Z (so it sits on a character's back).
-- index can be a backpack number or a backpack (like a dimension's special backpack)
function Shared.BuildBackpack(index: any): Model
	local def = if type(index) == "table" then index else Shared.Backpacks[index]
	local number = if type(index) == "number" then index else 8
	local model = Instance.new("Model")
	model.Name = def.Name
	local s = 0.85 + number * 0.05
	local fabric = Enum.Material.Fabric
	local dark = def.Accent:Lerp(Color3.new(0, 0, 0), 0.35)
	local metal = Color3.fromRGB(215, 185, 95)

	local body = part(model, { Name = "Body", Size = Vector3.new(1.7, 1.6, 0.9) * s, CFrame = CFrame.new(0, -0.15 * s, 0), Color = def.Color, Material = fabric })
	model.PrimaryPart = body
	-- rounded top
	part(model, {
		Name = "Top",
		Shape = CYLINDER,
		Size = Vector3.new(1.7, 0.9, 0.9) * s,
		CFrame = CFrame.new(0, 0.62 * s, 0),
		Color = def.Color,
		Material = fabric,
	})
	part(model, {
		Name = "Flap",
		Size = Vector3.new(1.5, 0.55, 0.12) * s,
		CFrame = CFrame.new(0, 0.55 * s, 0.48 * s) * CFrame.Angles(math.rad(-12), 0, 0),
		Color = def.Accent,
		Material = fabric,
	})
	-- front pocket with a zipper and a little badge
	part(model, { Name = "Pocket", Size = Vector3.new(1.2, 0.72, 0.28) * s, CFrame = CFrame.new(0, -0.48 * s, 0.56 * s), Color = def.Accent, Material = fabric })
	part(model, { Name = "Zipper", Size = Vector3.new(1.08, 0.05, 0.04) * s, CFrame = CFrame.new(0, -0.22 * s, 0.71 * s), Color = metal, Material = Enum.Material.Metal })
	part(model, { Name = "ZipperPull", Size = Vector3.new(0.08, 0.18, 0.04) * s, CFrame = CFrame.new(0.4 * s, -0.3 * s, 0.72 * s), Color = metal, Material = Enum.Material.Metal })
	part(model, {
		Name = "Badge",
		Shape = CYLINDER,
		Size = Vector3.new(0.04, 0.3, 0.3) * s,
		CFrame = CFrame.new(0, -0.52 * s, 0.71 * s) * CFrame.Angles(0, math.rad(90), 0),
		Color = def.Color:Lerp(Color3.new(1, 1, 1), 0.5),
	})
	-- straps with buckles
	for _, side in ipairs({ -1, 1 }) do
		part(model, { Name = "Strap", Size = Vector3.new(0.16, 1.15, 0.06) * s, CFrame = CFrame.new(0.42 * s * side, 0.12 * s, 0.53 * s), Color = dark, Material = fabric })
		part(model, { Name = "Buckle", Size = Vector3.new(0.24, 0.18, 0.08) * s, CFrame = CFrame.new(0.42 * s * side, 0.12 * s, 0.57 * s), Color = metal, Material = Enum.Material.Metal })
	end
	-- a water bottle on one side, a pouch on the other
	part(model, { Name = "Bottle", Shape = CYLINDER, Size = Vector3.new(0.75, 0.42, 0.42) * s, CFrame = CFrame.new(-1.02 * s, -0.4 * s, 0) * UPRIGHT, Color = Color3.fromRGB(90, 170, 210), Material = Enum.Material.Glass, Transparency = 0.15 })
	part(model, { Name = "BottleCap", Shape = CYLINDER, Size = Vector3.new(0.12, 0.3, 0.3) * s, CFrame = CFrame.new(-1.02 * s, 0.02 * s, 0) * UPRIGHT, Color = Color3.fromRGB(40, 40, 45) })
	part(model, { Name = "SidePouch", Size = Vector3.new(0.26, 0.7, 0.6) * s, CFrame = CFrame.new(0.97 * s, -0.35 * s, 0), Color = def.Accent, Material = fabric })
	if number >= 4 then
		-- bigger packs carry a rolled-up mat on top
		part(model, { Name = "Mat", Shape = CYLINDER, Size = Vector3.new(1.9, 0.5, 0.5) * s, CFrame = CFrame.new(0, 1.15 * s, 0.1 * s), Color = dark, Material = fabric })
	end
	-- gems peeking out of the top
	local gemColor = if def.Dimension then def.Accent else Shared.Zones[math.clamp(math.ceil(number / 2), 1, #Shared.Zones)].CrystalColors[1]
	for i, x in ipairs({ -0.45, 0, 0.45 }) do
		part(model, {
			Name = "Gem" .. i,
			Size = Vector3.new(0.3, 0.6 + (i % 2) * 0.25, 0.3) * s,
			CFrame = CFrame.new(x * s, 1.12 * s, -0.18 * s) * CFrame.Angles(0, math.rad(45), math.rad(x * -30)),
			Color = gemColor,
			Material = Enum.Material.Glass,
			Reflectance = 0.25,
		})
	end
	return model
end

-- GADGETS ---------------------------------------------------------------------
function Shared.BuildGadget(index: number): Model
	local def = Shared.Gadgets[index]
	local model = Instance.new("Model")
	model.Name = def.Name
	local look = def.Look
	local color = def.Color
	local white = Color3.fromRGB(240, 240, 240)
	local dark = Color3.fromRGB(40, 40, 46)
	local main
	if look == "shoe" or look == "rocket" then
		main = part(model, { Name = "Upper", Size = Vector3.new(1, 0.9, 1.9), CFrame = CFrame.new(0, 0.55, 0.15), Color = color })
		part(model, { Name = "Toe", Shape = BALL, Size = Vector3.new(1.02, 1.02, 1.02), CFrame = CFrame.new(0, 0.45, -0.75), Color = if look == "rocket" then color else white })
		part(model, { Name = "Sole", Size = Vector3.new(1.1, 0.28, 2.5), CFrame = CFrame.new(0, 0.05, -0.1), Color = dark })
		part(model, { Name = "Ankle", Size = Vector3.new(0.95, 0.75, 0.9), CFrame = CFrame.new(0, 1.2, 0.6), Color = color })
		for i = 1, 3 do
			part(model, { Name = "Lace", Size = Vector3.new(0.7, 0.07, 0.1), CFrame = CFrame.new(0, 1.0, -0.35 + i * 0.25) * CFrame.Angles(math.rad(-20), 0, 0), Color = white })
		end
		part(model, { Name = "Stripe", Size = Vector3.new(1.04, 0.12, 1.2), CFrame = CFrame.new(0, 0.45, 0.3) * CFrame.Angles(math.rad(-15), 0, 0), Color = white })
		if look == "rocket" then
			part(model, { Name = "Rocket", Shape = CYLINDER, Size = Vector3.new(1.1, 0.5, 0.5), CFrame = CFrame.new(0, 0.9, 1.25) * UPRIGHT, Color = Color3.fromRGB(200, 205, 215), Material = Enum.Material.Metal })
			part(model, { Name = "Flame", Shape = BALL, Size = Vector3.new(0.45, 0.45, 0.45), CFrame = CFrame.new(0, 0.2, 1.25), Color = Color3.fromRGB(255, 150, 40), Material = Enum.Material.Neon })
		elseif def.Kind == "jump" then
			for k = 0, 2 do
				part(model, { Name = "Spring", Shape = CYLINDER, Size = Vector3.new(0.1, 0.8, 0.8), CFrame = CFrame.new(0, -0.18 - k * 0.18, 0.5) * UPRIGHT, Color = Color3.fromRGB(190, 195, 205), Material = Enum.Material.Metal })
			end
		end
	elseif look == "coil" then
		-- a spring made of little beads going round and round
		main = part(model, { Name = "Grip", Size = Vector3.new(0.4, 0.8, 0.4), CFrame = CFrame.new(0, 2.1, 0), Color = dark })
		for k = 0, 40 do
			local a = k * 0.55
			part(model, {
				Name = "Coil",
				Shape = BALL,
				Size = Vector3.one * 0.32,
				CFrame = CFrame.new(math.cos(a) * 0.55, -0.4 + k * 0.055, math.sin(a) * 0.55),
				Color = color,
				Material = Enum.Material.Metal,
				Reflectance = 0.2,
			})
		end
	elseif look == "bolt" then
		main = part(model, { Name = "Bolt1", Size = Vector3.new(0.3, 1.2, 0.55), CFrame = CFrame.new(0.2, 0.9, 0) * CFrame.Angles(0, 0, math.rad(-25)), Color = color, Material = Enum.Material.Metal, Reflectance = 0.25 })
		part(model, { Name = "Bolt2", Size = Vector3.new(0.3, 0.3, 0.9), CFrame = CFrame.new(0, 0.3, 0) * CFrame.Angles(0, math.rad(90), 0), Color = color, Material = Enum.Material.Metal, Reflectance = 0.25 })
		part(model, { Name = "Bolt3", Size = Vector3.new(0.3, 1.2, 0.55), CFrame = CFrame.new(-0.2, -0.3, 0) * CFrame.Angles(0, 0, math.rad(-25)), Color = color, Material = Enum.Material.Metal, Reflectance = 0.25 })
		part(model, { Name = "Ring", Shape = CYLINDER, Size = Vector3.new(0.12, 0.45, 0.45), CFrame = CFrame.new(0.45, 1.6, 0) * CFrame.Angles(0, math.rad(90), 0), Color = Color3.fromRGB(200, 200, 205), Material = Enum.Material.Metal })
	elseif look == "clover" then
		main = part(model, { Name = "Stem", Size = Vector3.new(0.14, 1.3, 0.14), CFrame = CFrame.new(0, -0.6, 0) * CFrame.Angles(0, 0, math.rad(10)), Color = color:Lerp(Color3.new(0, 0, 0), 0.3) })
		for k = 0, 3 do
			local a = k * math.pi / 2 + math.pi / 4
			for _, offset in ipairs({ -0.18, 0.18 }) do
				local b = a + offset * 1.4
				part(model, { Name = "Leaf", Shape = BALL, Size = Vector3.new(0.55, 0.55, 0.2), CFrame = CFrame.new(math.cos(b) * 0.42, 0.25 + math.sin(b) * 0.42, 0), Color = color })
			end
		end
	elseif look == "magnet" then
		main = part(model, { Name = "Bottom", Size = Vector3.new(1.4, 0.45, 0.45), CFrame = CFrame.new(0, -0.5, 0), Color = color })
		for _, side in ipairs({ -1, 1 }) do
			part(model, { Name = "Arm", Size = Vector3.new(0.45, 1.3, 0.45), CFrame = CFrame.new(0.475 * side, 0.15, 0), Color = color })
			part(model, { Name = "Tip", Size = Vector3.new(0.47, 0.35, 0.47), CFrame = CFrame.new(0.475 * side, 0.95, 0), Color = Color3.fromRGB(215, 220, 228), Material = Enum.Material.Metal })
		end
	end
	model.PrimaryPart = main
	return model
end

return Shared
