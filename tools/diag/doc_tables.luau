-- Prints markdown tables straight from the game config (used to write docs/RACES.md, WEAPONS.md).
local Loader = require("../../tests/harness/Loader")
local loader = Loader.new({ IsServer = false })
local R = loader.RequirePath
local RaceConfig = R("ReplicatedStorage.Modules.Config.RaceConfig")
local AbilityConfig = R("ReplicatedStorage.Modules.Config.AbilityConfig")
local MasteryConfig = R("ReplicatedStorage.Modules.Config.MasteryConfig")
local StatDefinitions = R("ReplicatedStorage.Modules.Config.StatDefinitions")
local WeaponConfig = R("ReplicatedStorage.Modules.WeaponConfig")
local WeaponBuilder = R("ReplicatedStorage.Modules.WeaponBuilder")
local CombatRoleConfig = R("ReplicatedStorage.Modules.Config.CombatRoleConfig")
local MagicConfig = R("ReplicatedStorage.Modules.Config.MagicConfig")
local function pct(v)
	local s = string.format("%.1f", v * 100):gsub("%.0$", "")
	return (v > 0 and "+" or "") .. s .. "%"
end
local function mod(m)
	local def = StatDefinitions.ById[m.Stat]
	local name = def and def.DisplayName or m.Stat
	if m.Kind == "Multiplicative" then
		return string.format("x%.2f %s", 1 + m.Value, name)
	end
	return pct(m.Value) .. " " .. name
end
print("## RACES")
print("| Race | Rarity | Chance | Classification | Stat boosts | Passive | Ability [C] |")
print("|---|---|---|---|---|---|---|")
for _, race in RaceConfig.List do
	local mods = {}
	for _, m in race.Modifiers do
		table.insert(mods, mod(m))
	end
	local ability = race.AbilityId and AbilityConfig.Get(race.AbilityId)
	local abilityText = ability
			and (ability.Name .. (race.AbilityUnlockStage > 1 and (" (Mastery " .. MasteryConfig.StageNumerals[race.AbilityUnlockStage] .. ")") or ""))
		or "—"
	print(
		string.format(
			"| %s | %s | %s%% | %s | %s | **%s** — %s | %s |",
			race.DisplayName,
			race.Rarity,
			string.format("%g", race.Weight / 100),
			race.Classification.Label,
			table.concat(mods, ", "),
			race.Passive.Name,
			race.Passive.Description,
			abilityText
		)
	)
end
print("\n## ABILITIES")
for _, race in RaceConfig.List do
	if race.AbilityId then
		local a = AbilityConfig.Get(race.AbilityId)
		print(
			string.format(
				"- **%s — %s** (%d SE, %ds): %s%s",
				race.DisplayName,
				a.Name,
				a.Cost,
				a.Cooldown,
				a.Description,
				race.Drawback and (" _Drawback: " .. race.Drawback .. "_") or ""
			)
		)
	end
end
print("\n## MASTERY")
for _, race in RaceConfig.List do
	local tree = MasteryConfig.Tree(race.Id)
	local parts = {}
	for _, stage in tree do
		if stage.Stage > 1 then
			local objs = {}
			for _, o in stage.Objectives do
				table.insert(objs, o.Text)
			end
			local mods = {}
			for _, m in stage.Modifiers do
				table.insert(mods, mod(m))
			end
			table.insert(
				parts,
				string.format(
					"%s %s: %d XP + %s → %s%s",
					MasteryConfig.StageNumerals[stage.Stage],
					stage.Name,
					stage.XP,
					table.concat(objs, "; "),
					table.concat(mods, ", "),
					stage.Title and (" · title “" .. stage.Title .. "”") or ""
				)
			)
		end
	end
	print("- **" .. race.DisplayName .. "** — " .. table.concat(parts, " | "))
end
print("\n## ROLES")
for _, id in { "Meister", "Assassin", "Technician", "PartnerWeapon" } do
	local r = CombatRoleConfig.ById[id]
	local t = AbilityConfig.Get(r.TechniqueId)
	print(string.format("| %s | %s | %s (%d SE, %ds) |", r.DisplayName, r.Description, t.Name, t.Cost, t.Cooldown))
end
print("\n## SCHOOLS")
for _, s in MagicConfig.List do
	print(string.format("| %s | %s | Lv %d | %s |", s.DisplayName, s.Group, s.UnlockLevel, s.Description))
end
print("\n## WEAPONS")
print("| Weapon | Category | Hold style | Unlock | Parts | M1 combo | Z | X | Impact |")
print("|---|---|---|---|---|---|---|---|---|")
for _, id in WeaponConfig.Order do
	local w = WeaponConfig.Weapons[id]
	for _, form in w.FormOrder or { false } do
		local c = WeaponConfig.Resolve(id, form or nil)
		local model = WeaponBuilder.Build(id, { Form = form or nil, Anchored = true })
		local function vfx(a)
			local at = WeaponConfig.Attacks[a]
			return a .. " (" .. (at.VFX and at.VFX.Effect or "—") .. ")"
		end
		local m1 = {}
		for _, a in c.Moveset.M1 do
			table.insert(m1, a)
		end
		print(
			string.format(
				"| %s%s | %s | %s | Lv %d | %d | %s | %s | %s | %s |",
				w.DisplayName,
				form and (" — " .. w.Forms[form].DisplayName) or "",
				w.Category,
				c.HoldStyle,
				w.UnlockLevel or 1,
				WeaponBuilder.CountParts(model),
				table.concat(m1, " → "),
				vfx(c.Moveset.Z),
				vfx(c.Moveset.X),
				c.ImpactType
			)
		)
	end
end
print("\n## STATS")
for _, d in StatDefinitions.List do
	print(
		string.format(
			"| %s | %s | %s | %s | %s |",
			d.DisplayName,
			d.Category,
			d.Kind,
			d.SoftCap and pct(d.SoftCap):gsub("^%+", "") or "—",
			d.HardCap and pct(d.HardCap):gsub("^%+", "") or "—"
		)
	)
end
