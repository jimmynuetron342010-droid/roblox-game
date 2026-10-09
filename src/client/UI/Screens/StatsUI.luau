--[[
	StatsUI
	Every stat with its final value and where it came from, straight from the server's StatCalculator
	breakdown (the client never computes authoritative numbers):
	  final = base × (1 + capped additive bonus) × multiplicative bonuses, then clamped.
	Soft-capped stats are marked (only half of further bonuses count) and hard-capped ones show the
	ceiling, so players can see when stacking more of something stops paying off.
]]

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local CombatRoleConfig = require(Modules.Config.CombatRoleConfig)
local MagicConfig = require(Modules.Config.MagicConfig)
local MasteryConfig = require(Modules.Config.MasteryConfig)
local RaceConfig = require(Modules.Config.RaceConfig)
local StatDefinitions = require(Modules.Config.StatDefinitions)
local WeaponConfig = require(Modules.WeaponConfig)

local UI = script.Parent.Parent
local ClientState = require(UI.Parent.Controllers.ClientState)
local Components = require(UI.Components)
local Format = require(UI.Format)
local ScreenBase = require(UI.ScreenBase)
local Theme = require(UI.Theme)

local StatsUI = {}
StatsUI.__index = StatsUI

local CAP_TEXT = {
	Soft = { "◐ soft cap", Theme.Colors.Gold },
	Hard = { "● hard cap", Theme.Colors.Bad },
	Floor = { "▼ floor", Theme.Colors.Bad },
}

local function prettySource(source: string): string
	local kind, a, b = string.match(source, "^(%w+):?([^:]*):?(.*)$")
	if kind == "Race" and RaceConfig.ById[a] then
		return "Origin: " .. RaceConfig.ById[a].DisplayName
	elseif kind == "Mastery" and RaceConfig.ById[a] then
		return string.format("%s mastery %s", RaceConfig.ById[a].DisplayName, b)
	elseif kind == "Role" and CombatRoleConfig.ById[a] then
		return "Role: " .. CombatRoleConfig.ById[a].DisplayName
	elseif kind == "WeaponMastery" and WeaponConfig.Weapons[a] then
		return "Weapon mastery: " .. WeaponConfig.Weapons[a].DisplayName
	end
	return (string.gsub(source, ":", " · "))
end

function StatsUI.new(layer: Frame)
	local self = setmetatable({}, StatsUI)
	self.BlocksInput = true
	local root, content = ScreenBase.Modal("Stats", "STATS", layer)
	self.Root = root

	self.Header = Components.Label("", {
		Size = UDim2.new(1, 0, 0, 44),
		RichText = true,
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Colors.TextDim,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = content,
	})
	local body = Components.New("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 50),
		Size = UDim2.new(1, 0, 1, -50),
		Parent = content,
	})
	local left, right = ScreenBase.Columns(body, 0.56)
	self.List = Components.Scroll({ Size = UDim2.fromScale(1, 1), Parent = left })
	Components.List(Enum.FillDirection.Vertical, 4).Parent = self.List
	self.Detail =
		Components.Panel({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.Colors.InkLight, Parent = right })
	Components.Padding(14, 16).Parent = self.Detail
	self.DetailText = Components.Label("Select a stat to see where it comes from.", {
		Size = UDim2.fromScale(1, 1),
		RichText = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Colors.TextDim,
		Parent = self.Detail,
	})
	self.Selected = "MaxHealth"

	ClientState.StatsChanged:Connect(function()
		if root.Visible then
			self:Refresh()
		end
	end)
	ClientState.ProfileChanged:Connect(function()
		if root.Visible then
			self:RefreshHeader()
		end
	end)
	return self
end

function StatsUI:RefreshHeader()
	local profile = ClientState.Profile
	if not profile then
		return
	end
	local race = RaceConfig.ById[profile.Race.Active]
	local stage = race and profile.Race.Progress[race.Id] and profile.Race.Progress[race.Id].Stage or 1
	local role = CombatRoleConfig.ById[profile.Loadout.Role]
	local school = MagicConfig.ById[profile.Loadout.School]
	local weapon = WeaponConfig.Weapons[profile.Loadout.Weapon]
	self.Header.Text = string.format(
		'<b><font color="#F4C448">%s</font></b>  ·  Lv. %d  ·  Origin: <b>%s</b>%s  ·  Role: <b>%s</b>%s  ·  Weapon: <b>%s</b>\nKills %d  ·  Bosses %d  ·  Deaths %d',
		profile.Student.Name ~= "" and profile.Student.Name or "Student",
		profile.Level,
		race and race.DisplayName or "Unawakened",
		race and (" " .. MasteryConfig.StageNumerals[stage]) or "",
		role and role.DisplayName or "—",
		school and ("  ·  School: <b>" .. school.DisplayName .. "</b>") or "",
		weapon and weapon.DisplayName or "—",
		profile.Stats.Kills,
		profile.Stats.BossKills,
		profile.Stats.Deaths
	)
end

function StatsUI:Refresh()
	self:RefreshHeader()
	ScreenBase.ClearChildren(self.List)
	local stats = ClientState.Stats
	if not stats then
		Components.Label(
			"Waiting for stats from the server…",
			{ Size = UDim2.new(1, 0, 0, 30), TextColor3 = Theme.Colors.TextMuted, Parent = self.List }
		)
		return
	end
	local order = 0
	for _, category in StatDefinitions.Categories do
		order += 1
		Components.Label(category, {
			Size = UDim2.new(1, -10, 0, 28),
			FontFace = Theme.Fonts.Hand,
			TextSize = 20,
			TextColor3 = Theme.Colors.Gold,
			LayoutOrder = order,
			Parent = self.List,
		})
		for _, def in StatDefinitions.List do
			if def.Category == category then
				order += 1
				self:Row(def.Id, stats, order)
				if def.Id == "Defense" then
					order += 1
					self:Row("DamageReduction", stats, order)
				end
			end
		end
	end
	self:ShowDetail(self.Selected)
end

function StatsUI:Row(statId: string, stats, order: number)
	local value = statId == "DamageReduction" and stats.DamageReduction or stats.Values[statId]
	if value == nil then
		return
	end
	local line = stats.Lines[statId]
	local row = Components.Button("", function()
		self:ShowDetail(statId)
	end, { Size = UDim2.new(1, -10, 0, 34), LayoutOrder = order, Parent = self.List }, "Ghost")
	Components.Label(Format.StatName(statId), {
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(0.55, -12, 1, 0),
		TextSize = Theme.TextSize.Small,
		Parent = row,
	})
	local cap = line and CAP_TEXT[line.Cap]
	if cap then
		Components.Label(cap[1], {
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.fromScale(0.25, 1),
			TextSize = 13,
			TextColor3 = cap[2],
			Parent = row,
		})
	end
	Components.Label(Format.StatValue(statId, value), {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 0),
		Size = UDim2.fromScale(0.3, 1),
		TextXAlignment = Enum.TextXAlignment.Right,
		FontFace = Theme.Fonts.BodyBold,
		Parent = row,
	})
end

function StatsUI:ShowDetail(statId: string)
	self.Selected = statId
	local stats = ClientState.Stats
	local profile = ClientState.Profile
	if not stats or not profile then
		return
	end
	if statId == "DamageReduction" then
		self.DetailText.Text = string.format(
			'<font size="22"><b>Damage Reduction: %s</b></font>\n\nDerived from Defense: reduction = Defense / (Defense + %d). The constant grows with level, so Defense stays meaningful all game. Capped at %s.\n\nRanged-only and poison-only reductions (e.g. Mummy wrappings, Zombie resistance) are applied separately to matching hits.',
			Format.StatValue("DamageReduction", stats.DamageReduction),
			StatDefinitions.DamageReduction.K(profile.Level),
			Format.Percent(StatDefinitions.DamageReduction.Cap)
		)
		return
	end
	local def = StatDefinitions.ById[statId]
	local line = stats.Lines[statId] or { Sources = {}, Raw = 0 }
	local parts = {
		string.format(
			'<font size="22"><b>%s: %s</b></font>',
			def.DisplayName,
			Format.StatValue(statId, stats.Values[statId])
		),
		def.Description,
		"",
	}
	if def.Kind == "Scalar" then
		table.insert(
			parts,
			string.format(
				"Base at Lv. %d: %s",
				profile.Level,
				Format.StatValue(statId, StatDefinitions.BaseValue(statId, profile.Level))
			)
		)
		table.insert(parts, string.format("Total bonus before caps: %s", Format.Percent(line.Raw or 0, true)))
	end
	local capOf = def.Kind == "Scalar" and "Bonus " or ""
	if def.SoftCap then
		table.insert(
			parts,
			string.format(
				"%ssoft cap %s (only %s of anything above counts)",
				capOf,
				Format.Percent(def.SoftCap),
				Format.Percent(def.DiminishFactor or 0.5)
			)
		)
	end
	if def.HardCap then
		table.insert(parts, capOf .. "hard cap " .. Format.Percent(def.HardCap))
	end
	table.insert(parts, "")
	table.insert(parts, "<b>Sources</b>")
	if #line.Sources == 0 then
		table.insert(parts, "None — this is the base value.")
	end
	for _, source in line.Sources do
		local label, value, kind = source[1], source[2], source[3]
		local text = kind == "Mul" and ("x" .. Format.Trim(1 + value, 2)) or Format.Percent(value, true)
		table.insert(
			parts,
			string.format(
				'<font color="#%s">%s</font>  %s',
				value >= 0 and "6CE08C" or "FF6C6C",
				text,
				prettySource(tostring(label))
			)
		)
	end
	self.DetailText.Text = table.concat(parts, "\n")
end

function StatsUI:Open(_args)
	ScreenBase.Show(self.Root)
	self:Refresh()
end

function StatsUI:Close()
	ScreenBase.Hide(self.Root)
end

return StatsUI
