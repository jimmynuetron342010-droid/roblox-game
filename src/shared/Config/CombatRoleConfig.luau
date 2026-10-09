--[[
	CombatRoleConfig
	Combat roles are *how you fight*, never *what you are*. A Meister is a trained wielder who
	synchronizes with a Demon Weapon partner — it is a role, not a biological race.

	Roles grant small additive modifiers and one technique (key V). BuildRules decides which roles
	each race may pick so that builds never contradict each other.
]]

export type Role = {
	Id: string,
	DisplayName: string,
	Description: string,
	Modifiers: { { Stat: string, Value: number } },
	TechniqueId: string,
	Lore: string,
	Canon: boolean,
}

local CombatRoleConfig = {}

local roles: { Role } = {
	{
		Id = "Meister",
		DisplayName = "Meister",
		Description = "Weapon handler. Improved weapon mastery and synchronization with a Demon Weapon partner.",
		Modifiers = {
			{ Stat = "WeaponMasteryGain", Value = 0.10 },
			{ Stat = "WeaponDamage", Value = 0.05 },
		},
		TechniqueId = "WavelengthStrike",
		Lore = "Canon: Meisters wield Demon Weapons and match soul wavelengths with them (Soul Resonance). Wavelength Strike is an original technique name.",
		Canon = true,
	},
	{
		Id = "Assassin",
		DisplayName = "Assassin",
		Description = "Mobility and burst. Closes gaps and punishes from behind.",
		Modifiers = {
			{ Stat = "DodgeDistance", Value = 0.10 },
			{ Stat = "MoveSpeed", Value = 0.05 },
		},
		TechniqueId = "ShadowStep",
		Lore = "Original role inspired by the canon Star Clan of assassins. Shadow Step is an original technique.",
		Canon = false,
	},
	{
		Id = "Technician",
		DisplayName = "Wavelength Technician",
		Description = "Soul wavelength specialist. Stronger abilities and faster Soul Energy recovery.",
		Modifiers = {
			{ Stat = "AbilityDamage", Value = 0.08 },
			{ Stat = "SoulEnergyRegen", Value = 0.10 },
		},
		TechniqueId = "SoulPulse",
		Lore = "Original role. Canon fighters (e.g. Franken Stein) attack with their soul wavelength; the role and Soul Pulse are game interpretations.",
		Canon = false,
	},
	{
		Id = "PartnerWeapon",
		DisplayName = "Partner Weapon",
		Description = "Demon Weapons only. Fights with partial transformations of their own body.",
		Modifiers = {
			{ Stat = "WeaponDamage", Value = 0.05 },
			{ Stat = "AttackSpeed", Value = 0.05 },
		},
		TechniqueId = "PartialTransformation",
		Lore = "Canon: Demon Weapons can partially transform (e.g. a blade from an arm). Making this a selectable role is a game interpretation.",
		Canon = true,
	},
}

CombatRoleConfig.List = roles
CombatRoleConfig.ById = {} :: { [string]: Role }
for _, role in roles do
	CombatRoleConfig.ById[role.Id] = role
end

function CombatRoleConfig.StatModifiers(id: string): { any }
	local role = CombatRoleConfig.ById[id]
	local out = {}
	if role then
		for _, modifier in role.Modifiers do
			table.insert(
				out,
				{ Stat = modifier.Stat, Kind = "Additive", Value = modifier.Value, Source = "Role:" .. id }
			)
		end
	end
	return out
end

return CombatRoleConfig
