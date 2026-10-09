--[[
	WeaponService
	Server-side ownership, equipping, holstering, Tsubaki form switching and weapon mastery.
	Weapons are built and mounted on the server (WeaponBuilder) so every player sees the same model;
	clients only animate them.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage.Modules
local GameConfig = require(Modules.Config.GameConfig)
local WeaponBuilder = require(Modules.WeaponBuilder)
local WeaponConfig = require(Modules.WeaponConfig)

local Server = script.Parent.Parent
local GameEvents = require(Server.Core.GameEvents)
local Notifier = require(Server.Core.Notifier)
local RemoteGuard = require(Server.Core.RemoteGuard)

local WeaponService = {}

local DataService
local StatService

local lastEquip: { [Player]: number } = {}

local function owns(profile, weaponId: string): boolean
	if GameConfig.Debug.UnlockAllWeapons and RunService:IsStudio() then
		return true
	end
	return profile.Weapons.Owned[weaponId] == true
end

-- Returns (weaponId, resolvedConfig) of the player's equipped weapon.
function WeaponService:GetEquipped(player: Player)
	local character = player.Character
	local id = character and character:GetAttribute("EquippedWeapon")
	if not id then
		return nil, nil
	end
	return id, WeaponConfig.Resolve(id, character:GetAttribute("WeaponForm"))
end

function WeaponService:IsDrawn(player: Player): boolean
	local character = player.Character
	return character ~= nil and character:GetAttribute("WeaponDrawn") == true
end

function WeaponService:SetDrawn(player: Player, drawn: boolean)
	local character = player.Character
	if character and WeaponBuilder.GetEquipped(character) then
		WeaponBuilder.SetDrawn(character, drawn)
	end
end

function WeaponService:EquipFromProfile(player: Player)
	local profile = DataService:GetProfile(player)
	local character = player.Character
	if not profile or not character or not profile.Student.Created then
		return
	end
	local weaponId = profile.Loadout.Weapon
	if not WeaponConfig.IsValid(weaponId) or not owns(profile, weaponId) then
		weaponId = "MakaScythe"
		profile.Loadout.Weapon = weaponId
	end
	local form = weaponId == "TsubakiForms" and profile.Loadout.TsubakiForm or nil
	local model = WeaponBuilder.Equip(character, weaponId, { Form = form, Drawn = true })
	if model then
		local config = WeaponConfig.Resolve(weaponId, form)
		character:SetAttribute("HoldStyle", config.HoldStyle)
		character:SetAttribute("ImpactType", config.ImpactType)
	end
	StatService:Recompute(player)
end

local function weaponAction(player: Player, payload: any)
	if type(payload) ~= "table" then
		return { Ok = false, Reason = "BadRequest" }
	end
	local profile = DataService:GetProfile(player)
	if not profile or not profile.Student.Created then
		return { Ok = false, Reason = "Loading" }
	end
	local action = payload.Action
	if action == "Equip" then
		local weaponId = payload.WeaponId
		if not WeaponConfig.IsValid(weaponId) then
			return { Ok = false, Reason = "BadWeapon" }
		end
		if not owns(profile, weaponId) then
			return { Ok = false, Reason = "NotOwned" }
		end
		local now = os.clock()
		if lastEquip[player] and now - lastEquip[player] < 1 then
			return { Ok = false, Reason = "Cooldown" }
		end
		lastEquip[player] = now
		profile.Loadout.Weapon = weaponId
		WeaponService:EquipFromProfile(player)
		DataService:MarkDirty(player)
		return { Ok = true, Weapon = weaponId }
	elseif action == "Draw" then
		if type(payload.Drawn) ~= "boolean" then
			return { Ok = false, Reason = "BadRequest" }
		end
		WeaponService:SetDrawn(player, payload.Drawn)
		return { Ok = true }
	elseif action == "Form" then
		local weapon = WeaponConfig.Weapons.TsubakiForms
		local current = profile.Loadout.TsubakiForm
		local index = table.find(weapon.FormOrder, current) or 0
		local nextForm = weapon.FormOrder[index % #weapon.FormOrder + 1]
		if type(payload.Form) == "string" and weapon.Forms[payload.Form] then
			nextForm = payload.Form
		end
		profile.Loadout.TsubakiForm = nextForm
		if profile.Loadout.Weapon == "TsubakiForms" then
			WeaponService:EquipFromProfile(player)
		end
		DataService:MarkDirty(player)
		return { Ok = true, Form = nextForm }
	end
	return { Ok = false, Reason = "BadRequest" }
end

-- Unlocks weapons by level (players earn them by playing).
local function grantUnlocks(player: Player, profile)
	local granted = {}
	for _, id in WeaponConfig.Order do
		local weapon = WeaponConfig.Weapons[id]
		if profile.Level >= (weapon.UnlockLevel or 1) and not profile.Weapons.Owned[id] then
			profile.Weapons.Owned[id] = true
			table.insert(granted, weapon.DisplayName)
		end
	end
	if #granted > 0 then
		Notifier.Send(player, "New weapon unlocked: " .. table.concat(granted, ", "), "Reward")
		DataService:MarkDirty(player)
	end
end

function WeaponService:Init(registry)
	DataService = registry.DataService
	StatService = registry.StatService
end

function WeaponService:Start()
	RemoteGuard.OnInvoke("EquipWeapon", 4, 6, weaponAction)
	DataService.ProfileLoaded:Connect(function(player, profile)
		if profile.Student.Created then
			grantUnlocks(player, profile)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastEquip[player] = nil
	end)
	GameEvents.Fired:Connect(function(player, eventName, payload)
		local profile = DataService:GetProfile(player)
		if not profile then
			return
		end
		if eventName == "LevelUp" then
			grantUnlocks(player, profile)
		elseif eventName == "WeaponHit" and payload.WeaponId then
			local id = payload.WeaponId
			local gain = 1 + (StatService:GetValues(player).WeaponMasteryGain or 0)
			local before = WeaponConfig.MasteryLevel(profile.Weapons.Mastery[id] or 0)
			profile.Weapons.Mastery[id] = (profile.Weapons.Mastery[id] or 0) + gain
			local after = WeaponConfig.MasteryLevel(profile.Weapons.Mastery[id])
			if after > before then
				Notifier.Send(player, string.format("%s mastery %d (+%d%% weapon damage)", WeaponConfig.Weapons[id].DisplayName, after, after), "Reward")
				StatService:Recompute(player)
			end
			DataService:MarkDirty(player)
		end
	end)
end

return WeaponService
