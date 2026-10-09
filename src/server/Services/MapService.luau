--[[
	MapService
	Builds the playable Death City test map at server start so the place works out of the box:
	  * central plaza + spawn, gothic city blocks with warm windows, street lamps
	  * the Academy (skull facade, candle spires)
	  * Soul Altar (race rolling) and the Race Index lectern (ProximityPrompts open the UI)
	  * training yard with dummies and a weapon display rack (all 12 weapons on stands)
	  * graveyard district (Kishin Eggs, Shrouded Eggs), madness fields (Madness Wraiths),
	    the Pharaoh's Tomb (boss arena), and a PvP arena (the only PvP zone)
	  * hidden soul fragments only Shinigami can perceive
	  * night lighting with a grinning crescent moon built from geometry
	If your own place already has a map, set MapService.Enabled = false and add parts named like
	the markers below (Map.EnemySpawns, PvPZone, prompts with the "OpensUI" attribute).
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage.Modules
local GeometryKit = require(Modules.Core.GeometryKit)
local WeaponBuilder = require(Modules.WeaponBuilder)
local WeaponConfig = require(Modules.WeaponConfig)

local Server = script.Parent.Parent
local GameEvents = require(Server.Core.GameEvents)
local Notifier = require(Server.Core.Notifier)

local MapService = {}

MapService.Enabled = true

local ProgressionService
local mapFolder: Folder
local pvpZones: { BasePart } = {}
local rng = Random.new(1337)

local PALETTE = {
	Ground = Color3.fromRGB(46, 40, 54),
	Cobble = Color3.fromRGB(78, 72, 84),
	WallA = Color3.fromRGB(70, 60, 76),
	WallB = Color3.fromRGB(88, 70, 64),
	WallC = Color3.fromRGB(58, 56, 70),
	Roof = Color3.fromRGB(36, 30, 42),
	Window = Color3.fromRGB(255, 196, 110),
	Bone = Color3.fromRGB(232, 226, 210),
	Dark = Color3.fromRGB(22, 20, 26),
	Stone = Color3.fromRGB(110, 106, 112),
	Sand = Color3.fromRGB(196, 170, 120),
	Gold = Color3.fromRGB(214, 170, 60),
	Moon = Color3.fromRGB(255, 222, 90),
}

local function part(
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?,
	parent: Instance,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Name = name
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function wedge(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): WedgePart
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Size = size
	w.CFrame = cframe
	w.Color = color
	w.Material = Enum.Material.Slate
	w.Anchored = true
	w.Parent = parent
	return w
end

local function group(name: string, parent: Instance?): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent or mapFolder
	return model
end

local function prompt(parentPart: BasePart, action: string, object: string, opensUI: string)
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = 0
	p.MaxActivationDistance = 12
	p.RequiresLineOfSight = false
	p.KeyboardKeyCode = Enum.KeyCode.F
	p.GamepadKeyCode = Enum.KeyCode.ButtonX
	p:SetAttribute("OpensUI", opensUI)
	p.Parent = parentPart
	return p
end

local function sign(parentPart: BasePart, face: Enum.NormalId, text: string, color: Color3?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.LightInfluence = 0
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Bangers
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = color or Color3.fromRGB(255, 230, 160)
	label.TextStrokeTransparency = 0.3
	label.Parent = gui
	gui.Parent = parentPart
end

-- ── Lighting & sky ────────────────────────────────────────────────────────────
local function buildLighting()
	Lighting.ClockTime = 0.2
	Lighting.Brightness = 1.6
	Lighting.Ambient = Color3.fromRGB(41, 31, 56)
	Lighting.OutdoorAmbient = Color3.fromRGB(82, 66, 107)
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Density = 0.32
	atmosphere.Offset = 0.15
	atmosphere.Color = Color3.fromRGB(120, 90, 150)
	atmosphere.Decay = Color3.fromRGB(70, 40, 90)
	atmosphere.Glare = 0
	atmosphere.Haze = 1.6
	atmosphere.Parent = Lighting
	local sky = Lighting:FindFirstChildOfClass("Sky") or Instance.new("Sky")
	sky.CelestialBodiesShown = false -- the stylized moon below replaces the default one
	sky.StarCount = 3000
	sky.Parent = Lighting
	local grade = Lighting:FindFirstChild("SoulEaterGrade") or Instance.new("ColorCorrectionEffect")
	grade.Name = "SoulEaterGrade"
	(grade :: ColorCorrectionEffect).Contrast = 0.08
	(grade :: ColorCorrectionEffect).Saturation = 0.12
	(grade :: ColorCorrectionEffect).TintColor = Color3.fromRGB(245, 236, 255)
	grade.Parent = Lighting
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect")
	bloom.Intensity = 0.35
	bloom.Size = 18
	bloom.Threshold = 1.6
	bloom.Parent = Lighting
end

-- Grinning crescent moon built from real geometry, far in the sky.
local function buildMoon()
	local moon = group("Moon")
	pcall(function()
		(moon :: any).ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	end)
	local origin = CFrame.lookAt(Vector3.new(-380, 520, -900), Vector3.new(0, 60, 0))
	local kit = GeometryKit.new({ Model = moon, Origin = origin, Anchored = true, CastShadow = false })
	local radius, inner = 140, 112
	local outerArc, innerArc = {}, {}
	local steps = 16
	for i = 0, steps do
		local a = math.rad(-125 + 250 * i / steps)
		table.insert(outerArc, Vector3.new(-math.cos(a) * radius, math.sin(a) * radius, 0))
		local b = math.rad(-110 + 220 * i / steps)
		table.insert(innerArc, Vector3.new(-math.cos(b) * inner + 52, math.sin(b) * inner, 0))
	end
	kit:Strip("Crescent", outerArc, innerArc, 10, PALETTE.Moon, Enum.Material.Neon, moon)
	-- Face: eye, grin and teeth on the crescent's body.
	kit:Ball("Eye", 22, Vector3.new(-95, 40, -4), PALETTE.Dark, Enum.Material.SmoothPlastic, moon)
	kit:Ball("Pupil", 9, Vector3.new(-99, 42, -10), Color3.fromRGB(200, 30, 30), Enum.Material.Neon, moon)
	local mouth = {}
	local mouthInner = {}
	for i = 0, 6 do
		local a = math.rad(-70 + 50 * i / 6)
		table.insert(mouth, Vector3.new(-math.cos(a) * 118, math.sin(a) * 118 + 6, -5))
		table.insert(mouthInner, Vector3.new(-math.cos(a) * 92 + 10, math.sin(a) * 92 + 6, -5))
	end
	kit:Strip("Grin", mouth, mouthInner, 4, Color3.fromRGB(40, 10, 16), Enum.Material.SmoothPlastic, moon)
	for i = 1, 5 do
		local a = math.rad(-68 + 46 * i / 6)
		local p = Vector3.new(-math.cos(a) * 108, math.sin(a) * 108 + 6, -8)
		kit:Block(
			"Tooth",
			Vector3.new(7, 11, 3),
			CFrame.new(p) * CFrame.Angles(0, 0, -a),
			PALETTE.Bone,
			Enum.Material.SmoothPlastic,
			moon
		)
	end
	kit:Block(
		"Drip",
		Vector3.new(3, 26, 3),
		CFrame.new(-70, -80, -6),
		Color3.fromRGB(150, 10, 20),
		Enum.Material.Neon,
		moon
	)
	local glow = Instance.new("PointLight")
	glow.Color = PALETTE.Moon
	glow.Range = 60
	glow.Brightness = 1
	glow.Parent = moon:FindFirstChild("Crescent") or moon:FindFirstChildWhichIsA("BasePart", true)
end

-- ── City ──────────────────────────────────────────────────────────────────────
local function house(parent: Instance, cf: CFrame, width: number, depth: number, height: number)
	local model = group("House", parent)
	local wall = ({ PALETTE.WallA, PALETTE.WallB, PALETTE.WallC })[rng:NextInteger(1, 3)]
	part("Wall", Vector3.new(width, height, depth), cf * CFrame.new(0, height / 2, 0), wall, Enum.Material.Brick, model)
	-- Gable roof from two wedges + chimney.
	local roofHeight = rng:NextNumber(5, 9)
	wedge(
		"Roof",
		Vector3.new(width + 1, roofHeight, depth / 2 + 0.5),
		cf * CFrame.new(0, height + roofHeight / 2, -depth / 4) * CFrame.Angles(0, math.pi, 0),
		PALETTE.Roof,
		model
	)
	wedge(
		"Roof",
		Vector3.new(width + 1, roofHeight, depth / 2 + 0.5),
		cf * CFrame.new(0, height + roofHeight / 2, depth / 4),
		PALETTE.Roof,
		model
	)
	if rng:NextNumber() < 0.5 then
		part(
			"Chimney",
			Vector3.new(1.6, roofHeight + 2, 1.6),
			cf * CFrame.new(width * 0.3, height + roofHeight / 2 + 1, depth * 0.15),
			PALETTE.WallB,
			Enum.Material.Brick,
			model
		)
	end
	-- Lit windows on the street side (-Z face) and a door.
	local floors = math.max(1, math.floor(height / 8))
	for f = 1, floors do
		for w = -1, 1, 2 do
			if rng:NextNumber() < 0.75 then
				local lit = rng:NextNumber() < 0.7
				part(
					"Window",
					Vector3.new(2, 3, 0.4),
					cf * CFrame.new(w * width * 0.25, f * 7 - 1.5, -depth / 2 - 0.1),
					lit and PALETTE.Window or PALETTE.Dark,
					lit and Enum.Material.Neon or Enum.Material.Glass,
					model
				)
			end
		end
	end
	part(
		"Door",
		Vector3.new(3, 6, 0.5),
		cf * CFrame.new(0, 3, -depth / 2 - 0.15),
		Color3.fromRGB(60, 40, 30),
		Enum.Material.Wood,
		model
	)
	return model
end

local function lamp(parent: Instance, position: Vector3)
	local model = group("Lamp", parent)
	part(
		"Post",
		Vector3.new(0.5, 12, 0.5),
		CFrame.new(position + Vector3.new(0, 6, 0)),
		PALETTE.Dark,
		Enum.Material.Metal,
		model
	)
	local head = part(
		"Light",
		Vector3.new(1.3, 1.6, 1.3),
		CFrame.new(position + Vector3.new(0, 12.5, 0)),
		PALETTE.Window,
		Enum.Material.Neon,
		model
	)
	local light = Instance.new("PointLight")
	light.Color = PALETTE.Window
	light.Range = 26
	light.Brightness = 1.2
	light.Shadows = false
	light.Parent = head
end

local function buildCity()
	local city = group("DeathCity")
	part("Ground", Vector3.new(620, 2, 620), CFrame.new(0, -1, 0), PALETTE.Ground, Enum.Material.Slate, city)
	part(
		"Plaza",
		Vector3.new(1, 90, 90),
		CFrame.new(0, 0.05, 0) * CFrame.Angles(0, 0, math.rad(90)),
		PALETTE.Cobble,
		Enum.Material.Cobblestone,
		city,
		Enum.PartType.Cylinder
	)
	-- Main streets.
	part("StreetNS", Vector3.new(22, 0.2, 400), CFrame.new(0, 0.1, 0), PALETTE.Cobble, Enum.Material.Cobblestone, city)
	part("StreetEW", Vector3.new(400, 0.2, 22), CFrame.new(0, 0.1, 0), PALETTE.Cobble, Enum.Material.Cobblestone, city)
	-- Houses ring around the plaza, skipping the zone corridors.
	for i = 0, 27 do
		local angle = i / 28 * math.pi * 2
		local axisGap = math.min(math.abs(math.sin(angle)), math.abs(math.cos(angle)))
		if axisGap > 0.32 then
			local r = rng:NextNumber(62, 92)
			local position = Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
			local cf = CFrame.lookAt(position, Vector3.new(0, 0, 0))
			house(city, cf, rng:NextNumber(12, 18), rng:NextNumber(10, 14), rng:NextNumber(14, 30))
		end
	end
	for i = 0, 11 do
		local angle = i / 12 * math.pi * 2 + 0.26
		lamp(city, Vector3.new(math.cos(angle) * 47, 0, math.sin(angle) * 47))
	end
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.CFrame = CFrame.new(0, 0.5, 22)
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Color = PALETTE.Bone
	spawn.Material = Enum.Material.Marble
	spawn.Parent = city
	-- Invisible boundary walls.
	for _, wall in { { 0, -300, 620, 4 }, { 0, 300, 620, 4 }, { -300, 0, 4, 620 }, { 300, 0, 4, 620 } } do
		local w = part(
			"Boundary",
			Vector3.new(wall[3], 120, wall[4]),
			CFrame.new(wall[1], 60, wall[2]),
			PALETTE.Dark,
			Enum.Material.SmoothPlastic,
			city
		)
		w.Transparency = 1
	end
end

local function buildAcademy()
	local academy = group("Academy")
	local base = CFrame.new(0, 0, -150)
	part("Steps", Vector3.new(50, 4, 16), base * CFrame.new(0, 2, 28), PALETTE.Stone, Enum.Material.Marble, academy)
	part(
		"Hall",
		Vector3.new(70, 34, 40),
		base * CFrame.new(0, 17, 0),
		Color3.fromRGB(196, 170, 120),
		Enum.Material.Sandstone,
		academy
	)
	part(
		"Tower",
		Vector3.new(24, 70, 24),
		base * CFrame.new(0, 35, -4),
		Color3.fromRGB(206, 182, 130),
		Enum.Material.Sandstone,
		academy
	)
	-- Skull facade.
	part(
		"Skull",
		Vector3.new(22, 22, 22),
		base * CFrame.new(0, 52, -14),
		PALETTE.Bone,
		Enum.Material.SmoothPlastic,
		academy,
		Enum.PartType.Ball
	)
	for _, x in { -5, 5 } do
		part(
			"Socket",
			Vector3.new(7, 7, 7),
			base * CFrame.new(x, 55, -23),
			PALETTE.Dark,
			Enum.Material.SmoothPlastic,
			academy,
			Enum.PartType.Ball
		)
	end
	part(
		"Nose",
		Vector3.new(3, 4, 3),
		base * CFrame.new(0, 49, -24.5),
		PALETTE.Dark,
		Enum.Material.SmoothPlastic,
		academy
	)
	for i = -2, 2 do
		part(
			"Tooth",
			Vector3.new(2.6, 4, 2),
			base * CFrame.new(i * 3, 43.5, -23.5),
			PALETTE.Bone,
			Enum.Material.SmoothPlastic,
			academy
		)
	end
	-- Candle spires (with flames) like the Academy's silhouette.
	for _, x in { -30, -18, 18, 30 } do
		local h = (math.abs(x) == 18) and 58 or 46
		part(
			"Spire",
			Vector3.new(h, 3, 3),
			base * CFrame.new(x, h / 2, -18) * CFrame.Angles(0, 0, math.rad(90)),
			Color3.fromRGB(150, 120, 90),
			Enum.Material.Sandstone,
			academy,
			Enum.PartType.Cylinder
		)
		local flame = part(
			"Flame",
			Vector3.new(2, 3, 2),
			base * CFrame.new(x, h + 1.6, -18),
			Color3.fromRGB(255, 160, 60),
			Enum.Material.Neon,
			academy,
			Enum.PartType.Ball
		)
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 160, 60)
		light.Range = 30
		light.Parent = flame
	end
	local banner = part(
		"Banner",
		Vector3.new(30, 6, 1),
		base * CFrame.new(0, 30, -20.6),
		PALETTE.Dark,
		Enum.Material.Fabric,
		academy
	)
	sign(banner, Enum.NormalId.Front, "DEATH WEAPON MEISTER ACADEMY")
end

local function buildAltar()
	local altar = group("SoulAltar")
	local base = CFrame.new(28, 0, -38)
	part(
		"Dais",
		Vector3.new(2, 20, 20),
		base * CFrame.new(0, 1, 0) * CFrame.Angles(0, 0, math.rad(90)),
		PALETTE.Stone,
		Enum.Material.Marble,
		altar,
		Enum.PartType.Cylinder
	)
	for i = 0, 3 do
		local a = i / 4 * math.pi * 2 + math.pi / 4
		part(
			"Pillar",
			Vector3.new(1.6, 10, 1.6),
			base * CFrame.new(math.cos(a) * 8, 7, math.sin(a) * 8),
			PALETTE.Bone,
			Enum.Material.Marble,
			altar
		)
	end
	local soul = part(
		"Soul",
		Vector3.new(3, 3, 3),
		base * CFrame.new(0, 7, 0),
		Color3.fromRGB(170, 220, 255),
		Enum.Material.Neon,
		altar,
		Enum.PartType.Ball
	)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(170, 220, 255)
	light.Range = 24
	light.Brightness = 2
	light.Parent = soul
	prompt(soul, "Roll Origin", "Soul Altar", "RaceRoll")
	local lectern = part(
		"Lectern",
		Vector3.new(3, 4, 2),
		base * CFrame.new(-12, 3, 6),
		Color3.fromRGB(90, 60, 40),
		Enum.Material.Wood,
		altar
	)
	prompt(lectern, "Open Race Index", "Lectern", "RaceIndex")
	local plate = part(
		"AltarSign",
		Vector3.new(10, 3, 0.5),
		base * CFrame.new(0, 3.5, -10.5),
		PALETTE.Dark,
		Enum.Material.Slate,
		altar
	)
	sign(plate, Enum.NormalId.Front, "SOUL ALTAR")
end

local function buildTraining()
	local yard = group("TrainingYard")
	local base = CFrame.new(-46, 0, -34)
	part(
		"Floor",
		Vector3.new(36, 0.4, 26),
		base * CFrame.new(0, 0.2, 0),
		Color3.fromRGB(90, 76, 60),
		Enum.Material.WoodPlanks,
		yard
	)
	-- Weapon display rack: every weapon on its own stand (a quick in-world visual check).
	local rack = group("WeaponRack", mapFolder)
	for i, id in WeaponConfig.Order do
		local x = -70 + (i - 1) * 6.5
		local standCF = CFrame.new(x, 0, -62)
		part("Stand", Vector3.new(4, 1, 4), standCF * CFrame.new(0, 0.5, 0), PALETTE.Stone, Enum.Material.Marble, rack)
		local placard = part(
			"Placard",
			Vector3.new(4, 1.2, 0.3),
			standCF * CFrame.new(0, 1.2, -2.2),
			PALETTE.Dark,
			Enum.Material.Slate,
			rack
		)
		sign(placard, Enum.NormalId.Front, WeaponConfig.Weapons[id].DisplayName, Color3.fromRGB(240, 240, 240))
		local mount = WeaponConfig.Weapons[id].Mount
		local display = CFrame.new(x, 4.5, -62) * CFrame.Angles(0, math.rad(90), 0)
		if mount == "Back" then
			display = CFrame.new(x, 4, -62) * CFrame.Angles(0, math.rad(180), 0)
		elseif WeaponConfig.Weapons[id].Category == "Guns" or WeaponConfig.Weapons[id].Category == "Drill" then
			display = CFrame.new(x, 3.5, -62) * CFrame.Angles(0, math.rad(90), 0)
		end
		local ok, err = pcall(WeaponBuilder.Spawn, id, display, rack)
		if not ok then
			warn("[MapService] display " .. id .. ": " .. tostring(err))
		end
		local promptPart = part(
			"EquipPrompt",
			Vector3.new(1, 1, 1),
			standCF * CFrame.new(0, 2, 0),
			PALETTE.Dark,
			Enum.Material.SmoothPlastic,
			rack
		)
		promptPart.Transparency = 1
		promptPart.CanCollide = false
		local p = prompt(promptPart, "Inspect", WeaponConfig.Weapons[id].DisplayName, "Inventory")
		p:SetAttribute("WeaponId", id)
	end
end

local function enemyMarker(parent: Instance, enemyType: string, position: Vector3, minLevel: number, maxLevel: number)
	local marker = part(
		"Spawn_" .. enemyType,
		Vector3.new(2, 1, 2),
		CFrame.new(position + Vector3.new(0, 4, 0)),
		PALETTE.Dark,
		Enum.Material.SmoothPlastic,
		parent
	)
	marker.Transparency = 1
	marker.CanCollide = false
	marker.CanQuery = false
	marker:SetAttribute("EnemyType", enemyType)
	marker:SetAttribute("MinLevel", minLevel)
	marker:SetAttribute("MaxLevel", maxLevel)
end

local function secret(parent: Instance, position: Vector3)
	local fragment = part(
		"SoulFragment",
		Vector3.new(1.4, 1.4, 1.4),
		CFrame.new(position + Vector3.new(0, 2.5, 0)),
		Color3.fromRGB(235, 240, 255),
		Enum.Material.Neon,
		parent,
		Enum.PartType.Ball
	)
	fragment.Transparency = 1
	fragment.CanCollide = false
	fragment:SetAttribute("Secret", true)
	local p = prompt(fragment, "Gather Soul Fragment", "Hidden Soul", "")
	p.Enabled = true
	local claimed: { [Player]: boolean } = {}
	p.Triggered:Connect(function(player)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if
			claimed[player]
			or player:GetAttribute("Race") ~= "Shinigami"
			or not root
			or (root.Position - fragment.Position).Magnitude > 14
		then
			return
		end
		claimed[player] = true
		ProgressionService:AddSouls(player, 75)
		GameEvents.Fire(player, "HiddenRevealed", { Secret = true })
		Notifier.Send(player, "You gathered a hidden soul fragment (+75 Souls).", "Reward")
	end)
end

local function buildGraveyard(spawns: Instance)
	local yard = group("Graveyard")
	local center = Vector3.new(130, 0, 10)
	part(
		"Soil",
		Vector3.new(120, 0.3, 120),
		CFrame.new(center + Vector3.new(0, 0.15, 0)),
		Color3.fromRGB(52, 44, 46),
		Enum.Material.Ground,
		yard
	)
	for _ = 1, 40 do
		local p = center + Vector3.new(rng:NextNumber(-52, 52), 0, rng:NextNumber(-52, 52))
		if rng:NextNumber() < 0.5 then
			part(
				"Tombstone",
				Vector3.new(3, 4, 0.8),
				CFrame.new(p + Vector3.new(0, 2, 0))
					* CFrame.Angles(rng:NextNumber(-0.1, 0.1), rng:NextNumber(0, 6.28), 0),
				PALETTE.Stone,
				Enum.Material.Slate,
				yard
			)
		else
			local rot = CFrame.Angles(0, rng:NextNumber(0, 6.28), rng:NextNumber(-0.15, 0.15))
			part(
				"CrossV",
				Vector3.new(0.7, 5, 0.7),
				CFrame.new(p + Vector3.new(0, 2.5, 0)) * rot,
				PALETTE.Dark,
				Enum.Material.Wood,
				yard
			)
			part(
				"CrossH",
				Vector3.new(3, 0.7, 0.7),
				CFrame.new(p + Vector3.new(0, 3.6, 0)) * rot,
				PALETTE.Dark,
				Enum.Material.Wood,
				yard
			)
		end
	end
	for _ = 1, 6 do
		local p = center + Vector3.new(rng:NextNumber(-55, 55), 0, rng:NextNumber(-55, 55))
		local tilt = CFrame.Angles(rng:NextNumber(-0.2, 0.2), 0, rng:NextNumber(-0.2, 0.2))
		part(
			"DeadTree",
			Vector3.new(1.4, 16, 1.4),
			CFrame.new(p + Vector3.new(0, 8, 0)) * tilt,
			Color3.fromRGB(40, 32, 30),
			Enum.Material.Wood,
			yard
		)
		part(
			"Branch",
			Vector3.new(0.7, 7, 0.7),
			CFrame.new(p + Vector3.new(1.5, 13, 0)) * tilt * CFrame.Angles(0, 0, -0.9),
			Color3.fromRGB(40, 32, 30),
			Enum.Material.Wood,
			yard
		)
	end
	for i = 1, 5 do
		local a = i / 5 * math.pi * 2
		enemyMarker(spawns, "KishinEgg", center + Vector3.new(math.cos(a) * 28, 0, math.sin(a) * 28), 1, 22)
	end
	for i = 1, 3 do
		local a = i / 3 * math.pi * 2 + 0.6
		enemyMarker(spawns, "ShroudedKishinEgg", center + Vector3.new(math.cos(a) * 45, 0, math.sin(a) * 45), 3, 24)
	end
	secret(yard, center + Vector3.new(48, 0, -48))
	local gate = part(
		"GateSign",
		Vector3.new(14, 3, 0.6),
		CFrame.new(center + Vector3.new(-60, 9, 0)) * CFrame.Angles(0, math.rad(90), 0),
		PALETTE.Dark,
		Enum.Material.Slate,
		yard
	)
	sign(gate, Enum.NormalId.Front, "GRAVEYARD DISTRICT")
end

local function buildMadnessFields(spawns: Instance)
	local fields = group("MadnessFields")
	local center = Vector3.new(120, 0, -160)
	part(
		"Ground",
		Vector3.new(90, 0.3, 80),
		CFrame.new(center + Vector3.new(0, 0.15, 0)),
		Color3.fromRGB(40, 26, 50),
		Enum.Material.Basalt,
		fields
	)
	local fog = part(
		"MadnessFog",
		Vector3.new(80, 2, 70),
		CFrame.new(center + Vector3.new(0, 1.5, 0)),
		Color3.fromRGB(0, 0, 0),
		Enum.Material.SmoothPlastic,
		fields
	)
	fog.Transparency = 1
	fog.CanCollide = false
	fog.CanQuery = false
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(150, 80, 190))
	emitter.Size = NumberSequence.new(6, 12)
	emitter.Transparency = NumberSequence.new(0.8, 1)
	emitter.Lifetime = NumberRange.new(6, 9)
	emitter.Rate = 6
	emitter.Speed = NumberRange.new(0.5, 1.5)
	emitter.LightInfluence = 0.4
	emitter.Parent = fog
	for i = 1, 8 do
		local a = i / 8 * math.pi * 2
		part(
			"Monolith",
			Vector3.new(3, rng:NextNumber(8, 16), 3),
			CFrame.new(center + Vector3.new(math.cos(a) * 36, 5, math.sin(a) * 30)) * CFrame.Angles(0.1, a, 0.08),
			Color3.fromRGB(60, 40, 76),
			Enum.Material.Basalt,
			fields
		)
	end
	for i = 1, 3 do
		local a = i / 3 * math.pi * 2
		enemyMarker(spawns, "MadnessWraith", center + Vector3.new(math.cos(a) * 18, 0, math.sin(a) * 15), 18, 40)
	end
end

local function buildTomb(spawns: Instance)
	local tomb = group("PharaohsTomb")
	local center = Vector3.new(-170, 0, 10)
	for i = 0, 4 do
		local size = 90 - i * 14
		local ring = part(
			"Step",
			Vector3.new(size, 4, size),
			CFrame.new(center + Vector3.new(0, 2 + i * 4, 0)),
			PALETTE.Sand,
			Enum.Material.Sandstone,
			tomb
		)
		if i == 0 then
			ring.Name = "TombBase"
		end
	end
	-- Hollow the arena: an open-top sanctum on the top tier.
	part(
		"ArenaFloor",
		Vector3.new(30, 1, 30),
		CFrame.new(center + Vector3.new(0, 20.5, 0)),
		Color3.fromRGB(176, 150, 100),
		Enum.Material.Sandstone,
		tomb
	)
	for i = 0, 3 do
		local a = i / 4 * math.pi * 2 + math.pi / 4
		part(
			"Obelisk",
			Vector3.new(2.5, 14, 2.5),
			CFrame.new(center + Vector3.new(math.cos(a) * 13, 28, math.sin(a) * 13)),
			PALETTE.Gold,
			Enum.Material.Metal,
			tomb
		)
	end
	-- Ramp up the east face.
	local ramp = wedge(
		"Ramp",
		Vector3.new(14, 20, 40),
		CFrame.new(center + Vector3.new(58, 10, 0)) * CFrame.Angles(0, math.rad(-90), 0),
		PALETTE.Sand,
		tomb
	)
	ramp.Material = Enum.Material.Sandstone
	enemyMarker(spawns, "Pharaoh", center + Vector3.new(0, 21, 0), 22, 50)
	secret(tomb, center + Vector3.new(-40, 4, 40))
	local plate = part(
		"TombSign",
		Vector3.new(16, 3, 0.6),
		CFrame.new(center + Vector3.new(66, 6, 0)) * CFrame.Angles(0, math.rad(-90), 0),
		PALETTE.Dark,
		Enum.Material.Slate,
		tomb
	)
	sign(plate, Enum.NormalId.Front, "PHARAOH'S TOMB")
end

local function buildArena()
	local arena = group("PvPArena")
	local center = Vector3.new(0, 0, 150)
	part(
		"Floor",
		Vector3.new(1, 70, 70),
		CFrame.new(center + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(70, 60, 66),
		Enum.Material.Concrete,
		arena,
		Enum.PartType.Cylinder
	)
	for i = 0, 23 do
		local a = i / 24 * math.pi * 2
		if not (math.abs(a - math.pi * 1.5) < 0.2) then
			part(
				"Wall",
				Vector3.new(9.5, 6, 2),
				CFrame.new(center + Vector3.new(math.cos(a) * 35, 3, math.sin(a) * 35))
					* CFrame.Angles(0, -a + math.pi / 2, 0),
				Color3.fromRGB(110, 30, 40),
				Enum.Material.Brick,
				arena
			)
		end
	end
	local zone = part(
		"PvPZone",
		Vector3.new(68, 30, 68),
		CFrame.new(center + Vector3.new(0, 15, 0)),
		Color3.fromRGB(255, 0, 0),
		Enum.Material.SmoothPlastic,
		arena
	)
	zone.Transparency = 1
	zone.CanCollide = false
	zone.CanQuery = false
	zone.CanTouch = false
	table.insert(pvpZones, zone)
	local plate = part(
		"ArenaSign",
		Vector3.new(14, 3, 0.6),
		CFrame.new(center + Vector3.new(0, 8, -36)),
		PALETTE.Dark,
		Enum.Material.Slate,
		arena
	)
	sign(plate, Enum.NormalId.Front, "PVP ARENA", Color3.fromRGB(255, 120, 120))
end

function MapService:IsPvPZone(position: Vector3): boolean
	for _, zone in pvpZones do
		local localPos = zone.CFrame:PointToObjectSpace(position)
		local half = zone.Size / 2
		if math.abs(localPos.X) <= half.X and math.abs(localPos.Y) <= half.Y and math.abs(localPos.Z) <= half.Z then
			return true
		end
	end
	return false
end

function MapService:Init(registry)
	ProgressionService = registry.ProgressionService
end

function MapService:Start()
	if not MapService.Enabled then
		-- Use the existing place: collect any PvPZone parts and mark ready.
		for _, descendant in workspace:GetDescendants() do
			if descendant:IsA("BasePart") and descendant.Name == "PvPZone" then
				table.insert(pvpZones, descendant)
			end
		end
		workspace:SetAttribute("MapReady", true)
		return
	end
	local existing = workspace:FindFirstChild("Map")
	if existing then
		existing:Destroy()
	end
	mapFolder = Instance.new("Folder")
	mapFolder.Name = "Map"
	mapFolder.Parent = workspace
	local spawns = Instance.new("Folder")
	spawns.Name = "EnemySpawns"
	spawns.Parent = mapFolder

	local steps = {
		buildLighting,
		buildCity,
		buildAcademy,
		buildAltar,
		buildTraining,
		function()
			buildGraveyard(spawns)
		end,
		function()
			buildMadnessFields(spawns)
		end,
		function()
			buildTomb(spawns)
		end,
		buildArena,
		buildMoon,
	}
	for index, step in steps do
		local ok, err = pcall(step)
		if not ok then
			warn("[MapService] build step " .. index .. " failed: " .. tostring(err))
		end
	end
	-- Training dummies.
	for i = -1, 1 do
		enemyMarker(spawns, "TrainingDummy", Vector3.new(-46 + i * 9, 0, -38), 1, 1)
	end
	workspace:SetAttribute("MapReady", true)
end

return MapService
