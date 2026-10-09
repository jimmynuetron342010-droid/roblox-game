--[[
	MockServer (Lune)
	Answers the client's remotes inside the UI harness using the game's *real* server logic:
	  ProfileCore (template/client view), RaceRollLogic (rolls, idempotency, pending choices),
	  CharacterService.ValidateStudent, LoadoutService.CleanSettings, BuildRules, StatCalculator.
	Pushes ProfileChanged / StatsChanged / Notify exactly like DataService and StatService do.
	`ForceRace` makes the next roll deterministic for screenshots.
]]

local MockServer = {}
MockServer.__index = MockServer

function MockServer.new(loader, env)
	local self = setmetatable({}, MockServer)
	self.Env = env
	self.Loader = loader
	local R = loader.RequirePath
	self.ProfileCore = R("ServerScriptService.Server.Data.ProfileCore")
	self.RaceRollLogic = R("ServerScriptService.Server.Race.RaceRollLogic")
	self.CharacterService = R("ServerScriptService.Server.Services.CharacterService")
	self.LoadoutService = R("ServerScriptService.Server.Services.LoadoutService")
	self.BuildRules = R("ReplicatedStorage.Modules.Config.BuildRules")
	self.BuildModifiers = R("ReplicatedStorage.Modules.Core.BuildModifiers")
	self.StatCalculator = R("ReplicatedStorage.Modules.Core.StatCalculator")
	self.RaceConfig = R("ReplicatedStorage.Modules.Config.RaceConfig")
	self.StudentConfig = R("ReplicatedStorage.Modules.Config.StudentConfig")
	self.WeaponConfig = R("ReplicatedStorage.Modules.WeaponConfig")
	self.CombatRoleConfig = R("ReplicatedStorage.Modules.Config.CombatRoleConfig")

	self.Profile = self.ProfileCore.Migrate(self.ProfileCore.Template())
	self.Profile.Currency.Souls = 600
	self.Calls = {}
	self.LastRollAt = nil
	self.ForceRace = nil :: string?
	self.Latency = 0
	return self
end

-- ── Push helpers ──────────────────────────────────────────────────────────────
function MockServer:ClientBreakdown()
	local profile = self.Profile
	local computed = self.StatCalculator.Compute(profile.Level, self.BuildModifiers.FromProfile(profile))
	local out = { Values = computed.Values, DamageReduction = computed.DamageReduction, Lines = {} }
	for id, b in computed.Breakdown do
		local sources = {}
		for _, entry in b.Additive do
			table.insert(sources, { entry.Source, entry.Value, "Add" })
		end
		for _, entry in b.Multiplicative do
			table.insert(sources, { entry.Source, entry.Value, "Mul" })
		end
		out.Lines[id] = { Cap = b.CapState, Sources = sources, Raw = b.RawBonus }
	end
	return out, computed
end

function MockServer:SyncAttributes()
	local player = self.Env.Player
	local profile = self.Profile
	local _, computed = self:ClientBreakdown()
	player:SetAttribute("Level", profile.Level)
	player:SetAttribute("Race", profile.Race.Active)
	player:SetAttribute("Role", profile.Loadout.Role)
	player:SetAttribute("School", profile.Loadout.School)
	player:SetAttribute("StudentCreated", profile.Student.Created)
	player:SetAttribute("StudentName", profile.Student.Name)
	player:SetAttribute("Wavelength", profile.Student.Wavelength)
	player:SetAttribute("StaminaMax", computed.Values.StaminaMax or 100)
	player:SetAttribute("Stamina", (computed.Values.StaminaMax or 100) * 0.8)
	player:SetAttribute("SoulEnergyMax", computed.Values.SoulEnergyMax or 100)
	player:SetAttribute("SoulEnergy", (computed.Values.SoulEnergyMax or 100) * 0.55)
end

function MockServer:Push()
	self:SyncAttributes()
	self.Env.FireClient("ProfileChanged", self.ProfileCore.ClientView(self.Profile))
	self.Env.FireClient("StatsChanged", (self:ClientBreakdown()))
end

function MockServer:Notify(text: string, kind: string?, extra)
	local payload = { Text = text, Kind = kind or "Info" }
	for k, v in extra or {} do
		payload[k] = v
	end
	self.Env.FireClient("Notify", payload)
end

-- An rng whose next NextInteger lands inside `raceId`'s weight band.
function MockServer:RngFor(raceId: string)
	local cumulative = 0
	for _, entry in self.RaceConfig.RollTable do
		if entry.Id == raceId then
			local value = cumulative + 1
			return {
				NextInteger = function()
					return value
				end,
			}
		end
		cumulative += entry.Weight
	end
	error("unknown race " .. raceId)
end

-- ── Remotes ───────────────────────────────────────────────────────────────────
local handlers = {}

function handlers.GetProfile(self)
	return { Ok = true, Profile = self.ProfileCore.ClientView(self.Profile) }
end

function handlers.CreateStudent(self, payload)
	local profile = self.Profile
	local first = not profile.Student.Created
	local ok, clean = self.CharacterService.ValidateStudent(payload, first)
	if not ok then
		return { Ok = false, Reason = clean }
	end
	if first then
		if string.find(string.lower(clean.Name), "badword", 1, true) then
			return { Ok = false, Reason = "NameNotAllowed" }
		end
		profile.Student.Name = clean.Name
		profile.Loadout.Role = clean.Role
		profile.Loadout.Weapon = clean.Weapon
		for _, weaponId in self.StudentConfig.StarterWeapons do
			profile.Weapons.Owned[weaponId] = true
		end
	end
	for _, key in { "SkinTone", "HairColor", "HairStyle", "Uniform", "Wavelength" } do
		profile.Student[key] = clean[key]
	end
	profile.Student.Created = true
	self:Push()
	if first then
		self:Notify(
			"Welcome to the DWMA, " .. profile.Student.Name .. "! Visit the Soul Altar to awaken your origin.",
			"Success"
		)
	end
	return { Ok = true, Student = profile.Student }
end

function handlers.RollRace(self, requestId, payment)
	local profile = self.Profile
	local rng = self.ForceRace and self:RngFor(self.ForceRace) or self.Loader.Globals().Random.new(42)
	local result = self.RaceRollLogic.Roll(profile, requestId, payment, {
		Now = os.clock(),
		UnixTime = os.time(),
		Rng = rng,
		LastRollAt = self.LastRollAt,
	})
	if result.Ok and not result.Replayed then
		self.LastRollAt = os.clock()
		if result.Applied then
			self:SanitizeBuild()
		end
		self:Push()
	end
	return result
end

function handlers.ResolveRaceRoll(self, requestId, accept)
	local result = self.RaceRollLogic.Resolve(self.Profile, requestId, accept)
	if result.Ok and not result.Replayed then
		if result.Accepted then
			self:SanitizeBuild()
			self:Notify(
				"Your soul now resonates as a " .. self.RaceConfig.ById[result.Active].DisplayName .. ".",
				"Success"
			)
		else
			self:Notify("You kept your current origin.", "Info")
		end
		self:Push()
	end
	return result
end

function MockServer:SanitizeBuild()
	local profile = self.Profile
	local raceId = profile.Race.Active
	local role, school, changes = self.BuildRules.Sanitize(
		raceId,
		profile.Loadout.Role,
		profile.Loadout.School ~= "" and profile.Loadout.School or nil,
		profile.Level
	)
	profile.Loadout.Role = role
	profile.Loadout.School = school or ""
	for _, change in changes do
		self:Notify(change, "Info")
	end
end

function handlers.UpdateSettings(self, input)
	local accepted = self.LoadoutService.CleanSettings(input)
	for key, value in accepted do
		self.Profile.Settings[key] = value
	end
	self:Push()
	return { Ok = true, Settings = self.Profile.Settings }
end

function handlers.SetLoadout(self, kind, value)
	local profile = self.Profile
	local raceId = profile.Race.Active ~= "" and profile.Race.Active or nil
	if kind == "Role" then
		if not self.BuildRules.IsRoleAllowed(raceId, value) then
			return { Ok = false, Reason = "RoleNotAllowed" }
		end
		profile.Loadout.Role = value
	elseif kind == "School" then
		if not self.BuildRules.IsSchoolAllowed(raceId, value, profile.Level) then
			return { Ok = false, Reason = "SchoolNotAllowed" }
		end
		profile.Loadout.School = value
	else
		return { Ok = false, Reason = "BadRequest" }
	end
	self:Push()
	return { Ok = true, Loadout = profile.Loadout }
end

function handlers.EquipWeapon(self, payload)
	local profile = self.Profile
	if type(payload) ~= "table" then
		return { Ok = false, Reason = "BadRequest" }
	end
	if payload.Action == "Equip" then
		if not self.WeaponConfig.IsValid(payload.WeaponId) then
			return { Ok = false, Reason = "BadWeapon" }
		end
		if not profile.Weapons.Owned[payload.WeaponId] then
			return { Ok = false, Reason = "NotOwned" }
		end
		profile.Loadout.Weapon = payload.WeaponId
	elseif payload.Action == "Draw" then
		local character = self.Env.Player.Character
		if character then
			character:SetAttribute("WeaponDrawn", payload.Drawn == true)
		end
		return { Ok = true }
	elseif payload.Action == "Form" then
		local weapon = self.WeaponConfig.Weapons.TsubakiForms
		if type(payload.Form) == "string" and weapon.Forms[payload.Form] then
			profile.Loadout.TsubakiForm = payload.Form
		end
	else
		return { Ok = false, Reason = "BadRequest" }
	end
	self:Push()
	return { Ok = true }
end

function handlers.PartnerAction(self, kind, targetUserId)
	if kind == "Leave" then
		self.Env.Player:SetAttribute("PartnerId", nil)
		return { Ok = true }
	end
	if type(targetUserId) ~= "number" then
		return { Ok = false, Reason = "BadTarget" }
	end
	return { Ok = true, Compatibility = 0.9 }
end

function MockServer:Invoke(name: string, ...)
	table.insert(self.Calls, { Name = name, Args = table.pack(...) })
	local handler = handlers[name]
	if not handler then
		return { Ok = false, Reason = "NoMockHandler:" .. name }
	end
	return handler(self, ...)
end

function MockServer:OnEvent(name: string, ...)
	table.insert(self.Calls, { Name = name, Args = table.pack(...), Event = true })
end

return MockServer
