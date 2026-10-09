--[[
	HUD — layout follows the reference sheet:
	  top-left     grinning-moon portrait, HP (red) + STAMINA (gold) bars, Soul Energy, race badge,
	               status chips, Madness / Resonance meters when relevant
	  under it     Z / X / C / V ability slots with icons, key labels and cooldown sweeps
	  bottom-left  level panel: portrait, "Lv. N", EXP bar "EXP: a / b"
	  top-right    Main Quest panel + currencies
	  right        menu buttons: Stats, Inventory, Skills, Settings (+ Race Index, Soul Altar)
	Everything is driven by replicated attributes and the profile snapshot.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local AbilitySlots = require(Modules.Core.AbilitySlots)
local GameConfig = require(Modules.Config.GameConfig)
local MasteryConfig = require(Modules.Config.MasteryConfig)
local QuestConfig = require(Modules.Config.QuestConfig)
local RaceConfig = require(Modules.Config.RaceConfig)
local Util = require(Modules.Core.Util)
local WeaponConfig = require(Modules.WeaponConfig)

local Controllers = script.Parent.Parent.Controllers
local ClientState = require(Controllers.ClientState)
local InputController = require(Controllers.InputController)
local PerceptionController = require(Controllers.PerceptionController)
local WeaponClient = require(Controllers.WeaponClient)

local Components = require(script.Parent.Components)
local Icons = require(script.Parent.Icons)
local Notifications = require(script.Parent.Notifications)
local Theme = require(script.Parent.Theme)
local UIController = require(script.Parent.UIController)

local HUD = {}
HUD.Root = nil :: Frame?
HUD.TouchLayout = false

local player = Players.LocalPlayer
local refs: { [string]: any } = {}

local function label(text: string, props)
	return Components.Label(text, props)
end

-- ── Vitals (top-left) ─────────────────────────────────────────────────────────
local function buildVitals(layer: Frame)
	local panel = Components.Panel({
		Name = "Vitals",
		Position = UDim2.fromOffset(16, 16),
		Size = UDim2.fromOffset(392, 118),
		Parent = layer,
	})
	local portraitRing = Components.New("Frame", {
		Name = "Portrait",
		BackgroundColor3 = Theme.Colors.InkLight,
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.fromOffset(98, 98),
		Parent = panel,
	})
	Components.Corner(UDim.new(1, 0)).Parent = portraitRing
	refs.PortraitStroke = Components.Stroke(Theme.Colors.Gold, 3, 0)
	refs.PortraitStroke.Parent = portraitRing
	local face = Icons.MoonFace(UDim2.fromScale(0.86, 0.86), Theme.Colors.InkLight)
	face.AnchorPoint = Vector2.new(0.5, 0.5)
	face.Position = UDim2.fromScale(0.5, 0.5)
	face.Parent = portraitRing

	local bars = Components.New("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(120, 12),
		Size = UDim2.new(1, -132, 1, -20),
		Parent = panel,
	})
	local hp, setHp, setHpText =
		Components.Bar(Theme.Colors.Red, { Size = UDim2.new(1, -64, 0, 22) }, Color3.fromRGB(255, 220, 220))
	hp.Parent = bars
	label("HP", {
		Position = UDim2.new(1, -58, 0, 0),
		Size = UDim2.fromOffset(58, 22),
		FontFace = Theme.Fonts.Display,
		TextSize = 22,
		Parent = bars,
	})
	local stamina, setStamina =
		Components.Bar(Theme.Colors.Stamina, { Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, -64, 0, 16) })
	stamina.Parent = bars
	label("STAMINA", {
		Position = UDim2.new(1, -58, 0, 28),
		Size = UDim2.fromOffset(58, 20),
		FontFace = Theme.Fonts.Display,
		TextSize = 16,
		Parent = bars,
	})
	local soul, setSoul, setSoulText =
		Components.Bar(Theme.Colors.Soul, { Position = UDim2.fromOffset(0, 54), Size = UDim2.new(1, -64, 0, 12) })
	soul.Parent = bars
	label("SOUL", {
		Position = UDim2.new(1, -58, 0, 50),
		Size = UDim2.fromOffset(58, 20),
		FontFace = Theme.Fonts.Display,
		TextSize = 15,
		TextColor3 = Theme.Colors.Soul,
		Parent = bars,
	})
	refs.RaceBadge = label("Unawakened", {
		Position = UDim2.fromOffset(0, 72),
		Size = UDim2.new(1, 0, 0, 22),
		FontFace = Theme.Fonts.BodyBold,
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Colors.TextDim,
		Parent = bars,
	})
	refs.SetHp, refs.SetHpText = setHp, setHpText
	refs.SetStamina, refs.SetSoul, refs.SetSoulText = setStamina, setSoul, setSoulText

	-- Extra meters (shown only when relevant).
	local extras = Components.New("Frame", {
		Name = "Extras",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 140),
		Size = UDim2.fromOffset(392, 22),
		Parent = layer,
	})
	Components.List(Enum.FillDirection.Horizontal, 8).Parent = extras
	local madness, setMadness =
		Components.Bar(Theme.Colors.Madness, { Size = UDim2.fromOffset(180, 14), Visible = false, LayoutOrder = 1 })
	madness.Parent = extras
	local resonance, setResonance =
		Components.Bar(Theme.Colors.Red, { Size = UDim2.fromOffset(180, 14), Visible = false, LayoutOrder = 2 })
	resonance.Parent = extras
	refs.Madness, refs.SetMadness = madness, setMadness
	refs.Resonance, refs.SetResonance = resonance, setResonance
	refs.Statuses = Components.New("Frame", {
		Name = "Statuses",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(200, 20),
		LayoutOrder = 3,
		Parent = extras,
	})
	Components.List(Enum.FillDirection.Horizontal, 4).Parent = refs.Statuses
end

-- ── Ability slots ─────────────────────────────────────────────────────────────
local SLOT_KEYS = { Z = "Z", X = "X", C = "C", V = "V" }

local function buildSlots(layer: Frame)
	local row = Components.New("Frame", {
		Name = "Abilities",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 168),
		Size = UDim2.fromOffset(392, 104),
		Parent = layer,
	})
	Components.List(Enum.FillDirection.Horizontal, 14).Parent = row
	refs.Slots = {}
	for index, slot in { "Z", "X", "C", "V" } do
		local holder = Components.New(
			"Frame",
			{ BackgroundTransparency = 1, Size = UDim2.fromOffset(84, 104), LayoutOrder = index, Parent = row }
		)
		local box = Components.Panel({ Name = "Box", Size = UDim2.fromOffset(84, 76), Parent = holder })
		local icon = Icons.ForSlot(slot)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.Size = UDim2.fromScale(0.72, 0.72)
		icon.Parent = box
		local cooldown = Components.New("Frame", {
			Name = "Cooldown",
			BackgroundColor3 = Color3.fromRGB(0, 0, 0),
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.fromScale(1, 0),
			ZIndex = 8,
			Parent = box,
		})
		Components.Corner().Parent = cooldown
		local timer = label("", {
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			FontFace = Theme.Fonts.Display,
			TextSize = 26,
			ZIndex = 9,
			Parent = box,
		})
		local lock = label("🔒", {
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextSize = 22,
			ZIndex = 9,
			Visible = false,
			Parent = box,
		})
		local keyBox =
			Components.Panel({ Position = UDim2.fromOffset(22, 80), Size = UDim2.fromOffset(40, 24), Parent = holder })
		local key = label(SLOT_KEYS[slot], {
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			FontFace = Theme.Fonts.BodyBold,
			TextSize = Theme.TextSize.Small,
			Parent = keyBox,
		})
		local hit = Components.New("TextButton", {
			BackgroundTransparency = 1,
			Text = "",
			Size = UDim2.fromScale(1, 1),
			ZIndex = 10,
			Parent = box,
			Selectable = false,
		})
		hit.Activated:Connect(function()
			InputController.Trigger("Skill" .. slot, true)
			InputController.Trigger("Skill" .. slot, false)
		end)
		refs.Slots[slot] = { Box = box, Cooldown = cooldown, Timer = timer, Lock = lock, Key = key, Total = 1 }
	end
end

-- ── Level panel (bottom-left) ─────────────────────────────────────────────────
local function buildLevel(layer: Frame)
	local panel = Components.Panel({
		Name = "Level",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -16),
		Size = UDim2.fromOffset(340, 104),
		Parent = layer,
	})
	local face = Icons.MoonFace(UDim2.fromOffset(84, 84), Theme.Colors.Ink)
	face.Position = UDim2.fromOffset(10, 10)
	face.Parent = panel
	refs.Level = label("Lv. 1", {
		Position = UDim2.fromOffset(106, 10),
		Size = UDim2.new(1, -118, 0, 34),
		FontFace = Theme.Fonts.Display,
		TextSize = 32,
		TextColor3 = Theme.Colors.Text,
		Parent = panel,
	})
	local exp, setExp =
		Components.Bar(Theme.Colors.Gold, { Position = UDim2.fromOffset(106, 48), Size = UDim2.new(1, -120, 0, 14) })
	exp.Parent = panel
	refs.SetExp = setExp
	refs.LevelPanel = panel
	refs.ExpText = label("EXP: 0 / 0", {
		Position = UDim2.fromOffset(106, 66),
		Size = UDim2.new(1, -118, 0, 22),
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Colors.TextDim,
		Parent = panel,
	})
end

-- ── Quest + currencies + menu (right) ─────────────────────────────────────────
local function buildRight(layer: Frame)
	local quest = Components.Panel({
		Name = "Quest",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 16),
		Size = UDim2.fromOffset(300, 116),
		Parent = layer,
	})
	Components.Padding(12, 14).Parent = quest
	label("Main Quest", {
		Size = UDim2.new(1, 0, 0, 22),
		FontFace = Theme.Fonts.Hand,
		TextSize = 18,
		TextColor3 = Theme.Colors.Gold,
		Parent = quest,
	})
	refs.QuestTitle = label("—", {
		Position = UDim2.fromOffset(0, 26),
		Size = UDim2.new(1, 0, 0, 24),
		FontFace = Theme.Fonts.BodyBold,
		TextSize = Theme.TextSize.Body,
		Parent = quest,
	})
	refs.QuestProgress = label("", {
		Position = UDim2.fromOffset(0, 52),
		Size = UDim2.new(1, 0, 0, 36),
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Colors.TextDim,
		Parent = quest,
	})

	local wallet = Components.Panel({
		Name = "Wallet",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 140),
		Size = UDim2.fromOffset(300, 40),
		Parent = layer,
	})
	refs.Wallet = label("", {
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -28, 1, 0),
		FontFace = Theme.Fonts.BodyBold,
		TextSize = Theme.TextSize.Small,
		Parent = wallet,
	})

	local menu = Components.Panel({
		Name = "Menu",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 192),
		Size = UDim2.fromOffset(200, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = layer,
	})
	Components.Padding(10).Parent = menu
	Components.List(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center).Parent = menu
	refs.Menu = menu
	local items = {
		{ "Stats", "Stats" },
		{ "Inventory", "Inventory" },
		{ "Skills", "Skills" },
		{ "Race Index", "RaceIndex" },
		{ "Soul Altar", "RaceRoll" },
		{ "Settings", "Settings" },
	}
	for index, item in items do
		Components.Button(item[1], function()
			if HUD.TouchLayout then
				menu.Visible = false
			end
			UIController.Toggle(item[2])
		end, {
			Size = UDim2.new(1, 0, 0, 40),
			LayoutOrder = index,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = menu,
		}, "Secondary")
	end

	-- Weapon / perception indicator (bottom center).
	refs.WeaponLabel = label("", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.fromOffset(420, 26),
		TextXAlignment = Enum.TextXAlignment.Center,
		FontFace = Theme.Fonts.BodyBold,
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Colors.TextDim,
		TextStrokeTransparency = 0.5,
		Parent = layer,
	})
end

-- ── Refresh ───────────────────────────────────────────────────────────────────
local function refreshProfile(profile)
	if not profile then
		return
	end
	local raceId = profile.Race.Active
	local race = RaceConfig.ById[raceId]
	if race then
		local rarity = Theme.Rarity(race.Rarity)
		local stage = profile.Race.Progress[raceId] and profile.Race.Progress[raceId].Stage or 1
		refs.RaceBadge.Text = string.format(
			"%s · %s · Mastery %s",
			race.DisplayName,
			rarity.DisplayName,
			MasteryConfig.StageNumerals[stage]
		)
		refs.RaceBadge.TextColor3 = rarity.Color
		refs.PortraitStroke.Color = rarity.Color
	else
		refs.RaceBadge.Text = "Unawakened — visit the Soul Altar"
		refs.RaceBadge.TextColor3 = Theme.Colors.TextDim
		refs.PortraitStroke.Color = Theme.Colors.Gold
	end
	refs.Level.Text = "Lv. " .. profile.Level
	local need = GameConfig.Level.ExpToNext(profile.Level)
	refs.SetExp(profile.Exp / math.max(need, 1))
	refs.ExpText.Text = string.format("EXP: %s / %s", Util.FormatNumber(profile.Exp), Util.FormatNumber(need))
	local quest = QuestConfig.ById[profile.Quests.Active]
	if quest then
		refs.QuestTitle.Text = quest.Title
		local locked = quest.RequiresLevel and profile.Level < quest.RequiresLevel
		refs.QuestProgress.Text = locked and string.format("Requires level %d", quest.RequiresLevel)
			or string.format("(%d/%d)  %s", profile.Quests.Progress, quest.Count, quest.Description)
	else
		refs.QuestTitle.Text = "All quests complete"
		refs.QuestProgress.Text = "Keep mastering your origin."
	end
	refs.Wallet.Text = string.format(
		"Souls  %s     Race Rolls  %d",
		Util.FormatNumber(profile.Currency.Souls),
		profile.Currency.RaceRolls
	)
	-- Slot lock states.
	for slot, ref in refs.Slots do
		if slot == "C" or slot == "V" then
			local abilityId = AbilitySlots.Resolve(profile, slot)
			ref.Lock.Visible = abilityId == nil
			ref.Box.Icon.Visible = abilityId ~= nil
		end
	end
	refs.Resonance.Visible = raceId == "DemonWeapon"
end

local function refreshVitals()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		refs.SetHp(humanoid.Health / math.max(humanoid.MaxHealth, 1))
		refs.SetHpText(
			string.format("%d / %d", math.floor(humanoid.Health + 0.5), math.floor(humanoid.MaxHealth + 0.5))
		)
	end
	refs.SetStamina((player:GetAttribute("Stamina") or 0) / math.max(player:GetAttribute("StaminaMax") or 100, 1))
	local se = player:GetAttribute("SoulEnergy") or 0
	local seMax = player:GetAttribute("SoulEnergyMax") or 100
	refs.SetSoul(se / math.max(seMax, 1))
	local madness = player:GetAttribute("Madness") or 0
	refs.Madness.Visible = madness > 0
	refs.SetMadness(madness / 100)
	refs.SetResonance((player:GetAttribute("Resonance") or 0) / 100)
	-- Cooldown sweeps.
	local now = workspace:GetServerTimeNow()
	for slot, ref in refs.Slots do
		local ready = player:GetAttribute("CD_" .. slot) or 0
		local remaining = ready - now
		if remaining > 0 then
			ref.Total = math.max(ref.Total, remaining)
			ref.Cooldown.Size = UDim2.fromScale(1, remaining / ref.Total)
			ref.Timer.Text = remaining >= 1 and tostring(math.ceil(remaining)) or string.format("%.1f", remaining)
		else
			ref.Total = 0.01
			ref.Cooldown.Size = UDim2.fromScale(1, 0)
			ref.Timer.Text = ""
		end
	end
	-- Status chips.
	local statuses = {}
	if character then
		for _, name in { "Root", "Slow", "Stagger", "Burn", "Judged", "Cursed", "Invulnerable" } do
			local expires = character:GetAttribute("Status_" .. name)
			if expires and expires > now then
				table.insert(statuses, name)
			end
		end
	end
	local key = table.concat(statuses, ",")
	if refs.StatusKey ~= key then
		refs.StatusKey = key
		for _, child in refs.Statuses:GetChildren() do
			if child:IsA("TextLabel") then
				child:Destroy()
			end
		end
		for _, name in statuses do
			local chip = label(name, {
				Size = UDim2.fromOffset(70, 20),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextSize = 13,
				FontFace = Theme.Fonts.BodyBold,
				BackgroundTransparency = 0.2,
				BackgroundColor3 = Theme.Colors.InkLighter,
				Parent = refs.Statuses,
			})
			Components.Corner(UDim.new(0, 6)).Parent = chip
		end
	end
	-- Weapon line.
	if character then
		local weaponId = character:GetAttribute("EquippedWeapon")
		local weapon = weaponId and WeaponConfig.Resolve(weaponId, character:GetAttribute("WeaponForm"))
		local parts = {}
		if weapon then
			table.insert(
				parts,
				weapon.DisplayName .. (weapon.Form and (" — " .. weapon.Forms[weapon.Form].DisplayName) or "")
			)
			table.insert(
				parts,
				character:GetAttribute("WeaponDrawn") and "Drawn (E to holster)" or "Holstered (E to draw)"
			)
		end
		if PerceptionController.IsActive() then
			table.insert(parts, "Soul Perception ON")
		end
		refs.WeaponLabel.Text = table.concat(parts, "   •   ")
	end
end

function HUD.Mount(layer: Frame)
	buildVitals(layer)
	buildSlots(layer)
	buildLevel(layer)
	buildRight(layer)
	ClientState.ProfileChanged:Connect(refreshProfile)
	if ClientState.Profile then
		refreshProfile(ClientState.Profile)
	end
	local accumulator = 0
	RunService.RenderStepped:Connect(function(dt)
		accumulator += dt
		if accumulator >= 1 / 20 then
			accumulator = 0
			refreshVitals()
		end
	end)
	WeaponClient.Feedback:Connect(function(text, kind)
		Notifications.Show(text, kind)
	end)
	HUD.Root = layer
end

-- Phones/tablets: the level panel moves out of the thumbstick area and the menu column collapses
-- behind a ☰ button (MobileControls) so it never overlaps the touch action buttons.
function HUD.UseTouchLayout(enabled: boolean)
	HUD.TouchLayout = enabled
	if refs.LevelPanel then
		refs.LevelPanel.AnchorPoint = enabled and Vector2.new(0, 0) or Vector2.new(0, 1)
		refs.LevelPanel.Position = enabled and UDim2.fromOffset(16, 280) or UDim2.new(0, 16, 1, -16)
	end
	if refs.Menu then
		refs.Menu.Position = enabled and UDim2.new(1, -16, 0, 246) or UDim2.new(1, -16, 0, 192)
		refs.Menu.Visible = not enabled
	end
end

function HUD.ToggleMenu()
	if refs.Menu then
		refs.Menu.Visible = not refs.Menu.Visible
	end
end

-- Hidden while full-screen experiences (creator, reveal) are showing.
function HUD.SetVisible(visible: boolean)
	if HUD.Root then
		HUD.Root.Visible = visible
	end
end

return HUD
