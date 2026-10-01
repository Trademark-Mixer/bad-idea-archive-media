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
	XPBase = 60, -- XP needed for the next level = XPBase x level x level
	LevelPowerBonus = 0.1, -- every level makes your pickaxe 10% stronger
	DimensionCrystals = 14, -- crystals on each dimension island
	DimensionHealth = 5, -- crystal health in dimension 1...
	DimensionHealthGrowth = 1.8, -- ...and x1.8 for every dimension after that
	DimensionGems = 4, -- gems per crystal in dimension 1...
	DimensionGemGrowth = 2, -- ...and x2 for every dimension after that
	MaxOpenDimensions = 8, -- how many dimension islands can exist at the same time
	DimensionCloseTime = 30, -- seconds an empty dimension stays before it disappears
	ShinyEvery = 5, -- every 5th dimension is a SHINY dimension (glowing, and 2x gems)

	-- Golden crystals (rare and worth a lot)
	GoldenChance = 0.02, -- 2% of crystals grow back golden
	GoldenGems = 10, -- golden crystals give 10x gems...
	GoldenXP = 5, -- ...and 5x XP

	-- Sky obby
	ObbyRewardCrystals = 80, -- the obby pays as much as mining this many crystals
	ObbyCooldown = 240, -- seconds before the obby pays out again

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
	return Shared.Settings.XPBase * level * level
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
		Price = 400,
		Color = RGB(255, 248, 225),
		Spots = RGB(120, 215, 100),
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
		Color = RGB(205, 160, 255),
		Spots = RGB(110, 230, 255),
		SpotMaterial = Enum.Material.Neon,
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
		Spots = RGB(110, 180, 255),
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
		Color = RGB(70, 40, 150),
		Spots = RGB(255, 130, 235),
		SpotMaterial = Enum.Material.Neon,
		Pets = {
			{ Name = "Star Slime", Chance = 59.9 },
			{ Name = "Nebula Cat", Chance = 30 },
			{ Name = "Cosmic Dragon", Chance = 9 },
			{ Name = "Galaxy Phoenix", Chance = 1 },
			{ Name = "Void Kitty", Chance = 0.1 },
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
		if Shared.Pets[index] and count > 0 then
			for _ = 1, math.min(count, Shared.Settings.MaxPets) do
				table.insert(list, index)
			end
		end
	end
	table.sort(list, function(a, b)
		if Shared.Pets[a].Bonus == Shared.Pets[b].Bonus then
			return a < b
		end
		return Shared.Pets[a].Bonus > Shared.Pets[b].Bonus
	end)
	while #list > Shared.Settings.MaxPets do
		table.remove(list)
	end
	return list
end

function Shared.GemMultiplier(owned: { [number]: number }): number
	local total = 1
	for _, index in ipairs(Shared.GetEquippedPets(owned)) do
		total += Shared.Pets[index].Bonus
	end
	return total
end

-- Picks a random pet from an egg, using the chances
function Shared.RollEgg(eggIndex: number, random: Random): number
	local egg = Shared.Eggs[eggIndex]
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
	local def = Shared.Pets[index]
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
function Shared.BuildEgg(index: number): Model
	local def = Shared.Eggs[index]
	local model = Instance.new("Model")
	model.Name = def.Name
	local shell = part(model, {
		Name = "Shell",
		Size = Vector3.new(4, 5.2, 4),
		Color = def.Color,
		Material = def.Material or Enum.Material.SmoothPlastic,
	})
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = shell
	model.PrimaryPart = shell
	-- spots on the shell (angles from the top, and around)
	local spots = { { 0.45, 0 }, { 0.9, 1.4 }, { 1.35, 2.7 }, { 0.85, 3.9 }, { 1.25, 5.1 }, { 1.9, 0.7 }, { 2.05, 2.1 }, { 1.85, 4.3 }, { 2.4, 5.6 } }
	for i, spot in ipairs(spots) do
		local theta, phi = spot[1], spot[2]
		local pos = Vector3.new(2 * math.sin(theta) * math.cos(phi), 2.6 * math.cos(theta), 2 * math.sin(theta) * math.sin(phi)) * 0.97
		part(model, {
			Name = "Spot",
			Shape = BALL,
			Size = Vector3.one * (0.95 - i * 0.04),
			CFrame = CFrame.new(pos),
			Color = def.Spots,
			Material = def.SpotMaterial or Enum.Material.SmoothPlastic,
		})
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
