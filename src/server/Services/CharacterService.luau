--[[
	CharacterService
	* Spawning (CharacterAutoLoads is off so characters only appear once the profile is loaded and
	  the map exists) and respawning.
	* "Create Your Student": validates every field server-side, filters the student name with
	  TextService, grants starter weapons and stores the choices.
	* Applies student appearance + race features/aura + a nameplate to the live character.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local Modules = ReplicatedStorage.Modules
local BuildRules = require(Modules.Config.BuildRules)
local RaceAppearance = require(Modules.Race.RaceAppearance)
local RaceConfig = require(Modules.Config.RaceConfig)
local RarityConfig = require(Modules.Config.RarityConfig)
local StudentAppearance = require(Modules.Race.StudentAppearance)
local StudentConfig = require(Modules.Config.StudentConfig)
local Validate = require(Modules.Core.Validate)

local Server = script.Parent.Parent
local Notifier = require(Server.Core.Notifier)
local RemoteGuard = require(Server.Core.RemoteGuard)

local CharacterService = {}

local DataService
local StatService
local WeaponService

local RESPAWN_TIME = 4

-- Prefers the newer async API when the engine provides it.
local function spawnCharacter(player: Player)
	local ok = pcall(function()
		(player :: any):LoadCharacterAsync()
	end)
	if not ok and player.Parent then
		(player :: any):LoadCharacter()
	end
end
CharacterService.SpawnCharacter = spawnCharacter

-- ── Name filtering ────────────────────────────────────────────────────────────
local function filterName(player: Player, name: string): (boolean, string)
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(name, player.UserId, Enum.TextFilterContext.PublicChat)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	if not ok then
		if RunService:IsStudio() then
			return true, name -- filtering is unavailable offline; allow in Studio only
		end
		return false, "FilterUnavailable"
	end
	if result ~= name then
		return false, "NameNotAllowed"
	end
	return true, result
end

-- Pure validation, exposed for tests. Returns (ok, reasonOrCleanPayload).
function CharacterService.ValidateStudent(payload: any, isFirstCreation: boolean)
	if not Validate.Table(payload, 12) then
		return false, "BadRequest"
	end
	local clean = {}
	if isFirstCreation then
		local name = payload.Name
		if type(name) ~= "string" then
			return false, "BadName"
		end
		name = string.gsub(name, "^%s+", "")
		name = string.gsub(name, "%s+$", "")
		name = string.gsub(name, "%s+", " ")
		if #name < StudentConfig.NameMinLength or #name > StudentConfig.NameMaxLength then
			return false, "NameLength"
		end
		if not string.match(name, StudentConfig.NamePattern) then
			return false, "NameCharacters"
		end
		clean.Name = name
	end
	local function index(key, list)
		local value = payload[key]
		if not Validate.Integer(value, 1, #list) then
			return nil
		end
		return value
	end
	clean.SkinTone = index("SkinTone", StudentConfig.SkinTones)
	clean.HairColor = index("HairColor", StudentConfig.HairColors)
	clean.HairStyle = index("HairStyle", StudentConfig.HairStyles)
	clean.Uniform = index("Uniform", StudentConfig.Uniforms)
	for _, key in { "SkinTone", "HairColor", "HairStyle", "Uniform" } do
		if clean[key] == nil then
			return false, "Bad" .. key
		end
	end
	if not StudentConfig.IsWavelength(payload.Wavelength) then
		return false, "BadWavelength"
	end
	clean.Wavelength = payload.Wavelength
	if isFirstCreation then
		if not BuildRules.IsRoleAllowed(nil, payload.Role) then
			return false, "BadRole"
		end
		clean.Role = payload.Role
		if type(payload.Weapon) ~= "string" or not table.find(StudentConfig.StarterWeapons, payload.Weapon) then
			return false, "BadWeapon"
		end
		clean.Weapon = payload.Weapon
	end
	return true, clean
end

local function createStudent(player: Player, payload: any)
	local profile = DataService:GetProfile(player)
	if not profile then
		return { Ok = false, Reason = "Loading" }
	end
	local first = not profile.Student.Created
	local ok, clean = CharacterService.ValidateStudent(payload, first)
	if not ok then
		return { Ok = false, Reason = clean }
	end
	if first then
		local allowed, filtered = filterName(player, clean.Name)
		if not allowed then
			return { Ok = false, Reason = filtered }
		end
		profile.Student.Name = filtered
		profile.Loadout.Role = clean.Role
		profile.Loadout.Weapon = clean.Weapon
		player:SetAttribute("Role", clean.Role)
		for _, weaponId in StudentConfig.StarterWeapons do
			profile.Weapons.Owned[weaponId] = true
		end
	end
	profile.Student.SkinTone = clean.SkinTone
	profile.Student.HairColor = clean.HairColor
	profile.Student.HairStyle = clean.HairStyle
	profile.Student.Uniform = clean.Uniform
	profile.Student.Wavelength = clean.Wavelength
	profile.Student.Created = true

	player:SetAttribute("StudentName", profile.Student.Name)
	player:SetAttribute("Wavelength", profile.Student.Wavelength)
	DataService:MarkDirty(player)
	DataService:SaveNow(player)
	StatService:Recompute(player)

	if first then
		Notifier.Send(
			player,
			"Welcome to the DWMA, " .. profile.Student.Name .. "! Visit the Soul Altar to awaken your origin.",
			"Success"
		)
		if player.Character then
			WeaponService:EquipFromProfile(player)
		end
	end
	CharacterService:ApplyAppearance(player)
	return { Ok = true, Student = profile.Student }
end

-- ── Nameplate ─────────────────────────────────────────────────────────────────
local function buildNameplate(head: BasePart): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = "Nameplate"
	gui.Adornee = head
	gui.Size = UDim2.fromOffset(240, 70)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
	gui.MaxDistance = 110
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false

	local function label(name, y, height, font, color)
		local text = Instance.new("TextLabel")
		text.Name = name
		text.BackgroundTransparency = 1
		text.Position = UDim2.fromScale(0, y)
		text.Size = UDim2.fromScale(1, height)
		text.Font = font
		text.TextScaled = true
		text.TextColor3 = color
		text.TextStrokeTransparency = 0.35
		text.TextStrokeColor3 = Color3.fromRGB(10, 8, 14)
		text.Parent = gui
		return text
	end
	label("Title", 0, 0.24, Enum.Font.GothamBold, Color3.fromRGB(255, 210, 90))
	label("StudentName", 0.24, 0.44, Enum.Font.Bangers, Color3.fromRGB(245, 245, 250))
	label("Info", 0.68, 0.3, Enum.Font.GothamMedium, Color3.fromRGB(200, 200, 210))
	gui.Parent = head
	return gui
end

function CharacterService:UpdateNameplate(player: Player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	local gui = head:FindFirstChild("Nameplate") :: BillboardGui?
	if not gui then
		gui = buildNameplate(head)
	end
	local profile = DataService:GetProfile(player)
	local name = profile and profile.Student.Name ~= "" and profile.Student.Name or player.DisplayName
	local raceId = player:GetAttribute("Race") or ""
	local race = RaceConfig.ById[raceId]
	local level = player:GetAttribute("Level") or 1
	local guiNonNil = gui :: BillboardGui
	local title = guiNonNil:FindFirstChild("Title") :: TextLabel
	local studentName = guiNonNil:FindFirstChild("StudentName") :: TextLabel
	local info = guiNonNil:FindFirstChild("Info") :: TextLabel
	studentName.Text = name
	title.Text = player:GetAttribute("Title") or ""
	if race then
		local rarity = RarityConfig.Tiers[race.Rarity]
		title.TextColor3 = rarity.Color
		info.Text = string.format("Lv. %d · %s", level, race.DisplayName)
		info.TextColor3 = rarity.Color:Lerp(Color3.new(1, 1, 1), 0.35)
	else
		info.Text = string.format("Lv. %d · Unawakened", level)
		info.TextColor3 = Color3.fromRGB(200, 200, 210)
	end
end

function CharacterService:ApplyAppearance(player: Player)
	local character = player.Character
	local profile = DataService:GetProfile(player)
	if not character or not profile then
		return
	end
	local raceId = profile.Race.Active
	if profile.Student.Created then
		local ok, err =
			pcall(StudentAppearance.Apply, character, profile.Student, raceId ~= "" and raceId or nil, false)
		if not ok then
			warn("[CharacterService] student appearance: " .. tostring(err))
		end
	end
	if raceId ~= "" then
		local progress = profile.Race.Progress[raceId]
		local ok, err = pcall(RaceAppearance.Apply, character, raceId, progress and progress.Stage or 1, false)
		if not ok then
			warn("[CharacterService] race appearance: " .. tostring(err))
		end
	else
		RaceAppearance.Clear(character)
	end
	self:UpdateNameplate(player)
end

-- ── Spawning ──────────────────────────────────────────────────────────────────
local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		return
	end
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.BreakJointsOnDeath = false
	character:WaitForChild("HumanoidRootPart", 10)

	-- Wait (bounded) for avatar accessories so hair replacement sees them.
	if not player:HasAppearanceLoaded() then
		local loaded = false
		local connection = player.CharacterAppearanceLoaded:Connect(function()
			loaded = true
		end)
		local deadline = os.clock() + 6
		while not loaded and os.clock() < deadline and character.Parent do
			task.wait(0.1)
		end
		connection:Disconnect()
	end
	if not character.Parent then
		return
	end

	StatService:Recompute(player)
	humanoid.Health = humanoid.MaxHealth
	CharacterService:ApplyAppearance(player)
	WeaponService:EquipFromProfile(player)

	humanoid.Died:Connect(function()
		local profile = DataService:GetProfile(player)
		if profile then
			profile.Stats.Deaths += 1
			DataService:MarkDirty(player)
		end
		task.delay(RESPAWN_TIME, function()
			if player.Parent and player.Character == character then
				spawnCharacter(player)
			end
		end)
	end)
end

function CharacterService:Init(registry)
	DataService = registry.DataService
	StatService = registry.StatService
	WeaponService = registry.WeaponService
end

function CharacterService:Start()
	local function setup(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
		for _, attribute in { "Level", "Race", "Title" } do
			player:GetAttributeChangedSignal(attribute):Connect(function()
				CharacterService:UpdateNameplate(player)
			end)
		end
	end
	Players.PlayerAdded:Connect(setup)
	for _, player in Players:GetPlayers() do
		setup(player)
	end

	DataService.ProfileLoaded:Connect(function(player, profile)
		player:SetAttribute("StudentName", profile.Student.Name)
		player:SetAttribute("StudentCreated", profile.Student.Created)
		player:SetAttribute("Wavelength", profile.Student.Wavelength)
		-- Wait until the map has a spawn point.
		local deadline = os.clock() + 15
		while not workspace:GetAttribute("MapReady") and os.clock() < deadline do
			task.wait(0.1)
		end
		if player.Parent then
			spawnCharacter(player)
		end
	end)

	RemoteGuard.OnInvoke("CreateStudent", 1, 3, function(player, payload)
		local result = createStudent(player, payload)
		if result.Ok then
			player:SetAttribute("StudentCreated", true)
		end
		return result
	end)
end

return CharacterService
