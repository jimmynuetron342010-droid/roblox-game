--[[
	RaceIndexUI — the race collection index
	  Origins tab: every race with rarity and exact chance. Discovered races show a 3D portrait;
	               undiscovered ones show a silhouette, but their odds and boosts are never hidden.
	               The detail pane shows the three mastery stages (Awakening → Synchronization →
	               Transcendence) with XP and objective progress from the saved profile.
	  Lore tab:    canon vs. game interpretation for every origin and lore system (LoreCodex).
]]

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local AbilityConfig = require(Modules.Config.AbilityConfig)
local GameConfig = require(Modules.Config.GameConfig)
local LoreCodex = require(Modules.Config.LoreCodex)
local MasteryConfig = require(Modules.Config.MasteryConfig)
local RaceConfig = require(Modules.Config.RaceConfig)

local UI = script.Parent.Parent
local ClientState = require(UI.Parent.Controllers.ClientState)
local Components = require(UI.Components)
local Format = require(UI.Format)
local Icons = require(UI.Icons)
local ScreenBase = require(UI.ScreenBase)
local Theme = require(UI.Theme)
local Viewport = require(UI.Viewport)

local RaceIndexUI = {}
RaceIndexUI.__index = RaceIndexUI

function RaceIndexUI.new(layer: Frame)
	local self = setmetatable({}, RaceIndexUI)
	self.BlocksInput = true
	local root, content = ScreenBase.Modal("RaceIndex", "RACE INDEX", layer)
	self.Root = root

	local tabs, selectTab = Components.Tabs(
		{ { Id = "Origins", Text = "Origins" }, { Id = "Lore", Text = "Lore" } },
		function(id)
			self:ShowTab(id)
		end,
		{ Parent = content }
	)
	tabs.Name = "Tabs"
	self.Summary = Components.Label("", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(360, 36),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.Colors.TextDim,
		TextSize = Theme.TextSize.Small,
		Parent = content,
	})

	local body = Components.New("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 48),
		Size = UDim2.new(1, 0, 1, -48),
		Parent = content,
	})
	self.Origins = Components.New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = body })
	self.Lore = Components.Scroll({ Size = UDim2.fromScale(1, 1), Visible = false, Parent = body })
	Components.List(Enum.FillDirection.Vertical, 10).Parent = self.Lore

	local left, right = ScreenBase.Columns(self.Origins, 0.42)
	self.Grid = Components.Scroll({ Size = UDim2.fromScale(1, 1), Parent = left })
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(136, 150)
	grid.CellPadding = UDim2.fromOffset(10, 10)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = self.Grid
	Components.Padding(4).Parent = self.Grid
	self.Detail =
		Components.Panel({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.Colors.InkLight, Parent = right })

	self.SelectTab = selectTab
	self.Selected = nil :: string?
	self:BuildLore()
	selectTab("Origins")
	ClientState.ProfileChanged:Connect(function()
		if root.Visible then
			self:Refresh()
		end
	end)
	return self
end

function RaceIndexUI:ShowTab(id: string)
	self.Origins.Visible = id == "Origins"
	self.Lore.Visible = id == "Lore"
end

function RaceIndexUI:Refresh()
	local profile = ClientState.Profile
	if not profile then
		return
	end
	ScreenBase.ClearChildren(self.Grid)
	local discovered = 0
	local list = table.clone(RaceConfig.List)
	table.sort(list, function(a, b)
		return a.Weight > b.Weight
	end)
	for index, race in list do
		local found = profile.Race.Discovered[race.Id] ~= nil
		if found then
			discovered += 1
		end
		local rarity = Theme.Rarity(race.Rarity)
		local active = profile.Race.Active == race.Id
		local card = Components.Button("", function()
			self:Select(race.Id)
		end, { LayoutOrder = index, Size = UDim2.fromOffset(136, 150), Parent = self.Grid }, "Ghost")
		card.AccessibilityDescription = found and race.DisplayName
			or ("Undiscovered " .. rarity.DisplayName .. " origin")
		local stroke = card:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = found and rarity.Color or Theme.Colors.Stroke
			stroke.Thickness = active and 3 or 1.5
		end
		local icon = found and Icons.Race(race.Id, rarity.Color) or Icons.Unknown(Theme.Colors.TextMuted)
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Position = UDim2.new(0.5, 0, 0, 12)
		icon.Size = UDim2.fromOffset(64, 64)
		icon.Parent = card
		Components.Label(found and race.DisplayName or "???", {
			Position = UDim2.fromOffset(6, 82),
			Size = UDim2.new(1, -12, 0, 22),
			TextXAlignment = Enum.TextXAlignment.Center,
			FontFace = Theme.Fonts.BodyBold,
			Parent = card,
		})
		Components.Label(
			string.format("%s · %s", rarity.DisplayName, Format.Percent(race.Weight / GameConfig.RaceRoll.TotalWeight)),
			{
				Position = UDim2.fromOffset(6, 104),
				Size = UDim2.new(1, -12, 0, 18),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextSize = Theme.TextSize.Small,
				TextColor3 = rarity.Color,
				Parent = card,
			}
		)
		local progress = profile.Race.Progress[race.Id]
		local stageText = active and "ACTIVE"
			or (progress and ("Mastery " .. MasteryConfig.StageNumerals[progress.Stage]) or "")
		Components.Label(stageText, {
			Position = UDim2.fromOffset(6, 124),
			Size = UDim2.new(1, -12, 0, 18),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextSize = 13,
			FontFace = Theme.Fonts.BodyBold,
			TextColor3 = active and Theme.Colors.Gold or Theme.Colors.TextMuted,
			Parent = card,
		})
	end
	self.Summary.Text =
		string.format("Discovered %d / %d   ·   Total rolls %d", discovered, #RaceConfig.List, profile.Race.TotalRolls)
	self:Select(self.Selected or (profile.Race.Active ~= "" and profile.Race.Active) or list[1].Id)
end

local function block(parent: Instance, order: number, title: string, body: string, color: Color3?)
	local frame = Components.New("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order,
		Parent = parent,
	})
	Components.List(Enum.FillDirection.Vertical, 2).Parent = frame
	Components.Label(title, {
		Size = UDim2.new(1, 0, 0, 20),
		FontFace = Theme.Fonts.BodyBold,
		TextSize = Theme.TextSize.Small,
		TextColor3 = color or Theme.Colors.Gold,
		LayoutOrder = 1,
		Parent = frame,
	})
	Components.Label(body, {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		RichText = true,
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Colors.TextDim,
		LayoutOrder = 2,
		Parent = frame,
	})
	return frame
end

function RaceIndexUI:Select(raceId: string)
	local profile = ClientState.Profile
	local race = RaceConfig.ById[raceId]
	if not profile or not race then
		return
	end
	self.Selected = raceId
	ScreenBase.ClearChildren(self.Detail)
	local rarity = Theme.Rarity(race.Rarity)
	local found = profile.Race.Discovered[raceId] ~= nil
	local progress = profile.Race.Progress[raceId] or { XP = 0, Stage = 1, Objectives = {} }

	local portrait = Components.New("Frame", {
		BackgroundColor3 = Theme.Colors.Ink,
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.new(0.38, -12, 0, 230),
		Parent = self.Detail,
	})
	Components.Corner().Parent = portrait
	if found then
		Viewport.Character(
			portrait,
			{ Student = profile.Student, RaceId = raceId, Stage = progress.Stage, Framing = "Full", Spin = true }
		)
	else
		local unknown = Icons.Unknown(Theme.Colors.TextMuted)
		unknown.AnchorPoint = Vector2.new(0.5, 0.5)
		unknown.Position = UDim2.fromScale(0.5, 0.45)
		unknown.Size = UDim2.fromOffset(90, 90)
		unknown.Parent = portrait
		Components.Label("Undiscovered", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -10),
			Size = UDim2.new(1, 0, 0, 22),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = Theme.Colors.TextMuted,
			Parent = portrait,
		})
	end

	local head = Components.New("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0.38, 10, 0, 12),
		Size = UDim2.new(0.62, -22, 0, 230),
		Parent = self.Detail,
	})
	Components.List(Enum.FillDirection.Vertical, 6).Parent = head
	Components.Label(race.DisplayName, {
		Size = UDim2.new(1, 0, 0, 38),
		FontFace = Theme.Fonts.Display,
		TextSize = 36,
		TextColor3 = rarity.Color,
		LayoutOrder = 1,
		Parent = head,
	})
	Components.Label(
		string.format(
			"%s · %s chance · %s",
			rarity.DisplayName,
			Format.Percent(race.Weight / GameConfig.RaceRoll.TotalWeight),
			race.Classification.Label
		),
		{
			Size = UDim2.new(1, 0, 0, 20),
			TextSize = Theme.TextSize.Small,
			TextColor3 = Theme.Colors.TextDim,
			LayoutOrder = 2,
			Parent = head,
		}
	)
	Components.Label(race.Purpose, {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = Theme.TextSize.Small,
		LayoutOrder = 3,
		Parent = head,
	})
	local mods = {}
	for _, modifier in race.Modifiers do
		table.insert(mods, Format.Modifier(modifier))
	end
	block(head, 4, "Stat Boosts", table.concat(mods, "  ·  "))
	block(head, 5, "Passive — " .. race.Passive.Name, race.Passive.Description)

	-- Mastery tree + ability (scrolls).
	local scroll = Components.Scroll({
		Position = UDim2.fromOffset(12, 254),
		Size = UDim2.new(1, -24, 1, -266),
		Parent = self.Detail,
	})
	Components.List(Enum.FillDirection.Vertical, 10).Parent = scroll
	if race.AbilityId then
		local _, _, name, description = AbilityConfig.Resolve(race.AbilityId, progress.Stage)
		local note = race.AbilityUnlockStage > 1
				and string.format(" — unlocks at Mastery %s", MasteryConfig.StageNumerals[race.AbilityUnlockStage])
			or ""
		block(scroll, 1, string.format("Racial Ability [C]: %s%s", name, note), description)
	end
	if race.Drawback then
		block(scroll, 2, "Drawback", race.Drawback, Theme.Colors.Bad)
	end
	local tree = MasteryConfig.Tree(raceId) or {}
	for _, stageDef in tree do
		local reached = progress.Stage >= stageDef.Stage
		local isNext = progress.Stage + 1 == stageDef.Stage
		local lines = {}
		if stageDef.XP > 0 then
			local xp = math.min(progress.XP, stageDef.XP)
			table.insert(
				lines,
				string.format(
					"%s Mastery XP %d / %d",
					(reached or xp >= stageDef.XP) and "✓" or "•",
					reached and stageDef.XP or xp,
					stageDef.XP
				)
			)
		end
		for _, objective in stageDef.Objectives do
			local count = reached and objective.Count or (isNext and (progress.Objectives[objective.Id] or 0) or 0)
			table.insert(
				lines,
				string.format(
					"%s %s (%d/%d)",
					count >= objective.Count and "✓" or "•",
					objective.Text,
					count,
					objective.Count
				)
			)
		end
		local mods2 = {}
		for _, modifier in stageDef.Modifiers do
			table.insert(mods2, Format.Modifier(modifier))
		end
		if #mods2 > 0 then
			table.insert(lines, "Bonuses: " .. table.concat(mods2, ", "))
		end
		if #stageDef.Unlocks > 0 then
			table.insert(lines, "Unlocks: " .. table.concat(stageDef.Unlocks, ", "))
		end
		if stageDef.Title then
			table.insert(lines, "Title: “" .. stageDef.Title .. "”")
		end
		local color = reached and Theme.Colors.Good or (isNext and Theme.Colors.Gold or Theme.Colors.TextMuted)
		block(
			scroll,
			10 + stageDef.Stage,
			string.format(
				"Stage %s — %s%s",
				MasteryConfig.StageNumerals[stageDef.Stage],
				stageDef.Name,
				reached and "  (reached)" or ""
			),
			table.concat(lines, "\n"),
			color
		)
	end
	block(
		scroll,
		20,
		"How mastery works",
		"Mastery is earned by playing this origin — never bought. Progress is saved per race, so if you replace it and roll it again later, everything returns.",
		Theme.Colors.TextMuted
	)
end

function RaceIndexUI:BuildLore()
	for index, entry in LoreCodex.List do
		local panel = Components.Panel({
			Size = UDim2.new(1, -12, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = Theme.Colors.InkLight,
			LayoutOrder = index,
			Parent = self.Lore,
		})
		Components.Padding(12, 16).Parent = panel
		Components.List(Enum.FillDirection.Vertical, 4).Parent = panel
		Components.Label(entry.Title, {
			Size = UDim2.new(1, 0, 0, 26),
			FontFace = Theme.Fonts.Display,
			TextSize = 24,
			TextColor3 = Theme.Colors.Gold,
			LayoutOrder = 1,
			Parent = panel,
		})
		Components.Label(entry.System, {
			Size = UDim2.new(1, 0, 0, 18),
			TextSize = Theme.TextSize.Small,
			TextColor3 = Theme.Colors.TextMuted,
			LayoutOrder = 2,
			Parent = panel,
		})
		local canon = {}
		for _, line in entry.Canon do
			table.insert(canon, "• " .. line)
		end
		local game_ = {}
		for _, line in entry.Game do
			table.insert(game_, "• " .. line)
		end
		block(panel, 3, "Canon (Soul Eater)", table.concat(canon, "\n"), Theme.Colors.Soul)
		block(panel, 4, "Game interpretation (original)", table.concat(game_, "\n"), Theme.Colors.Madness)
	end
end

function RaceIndexUI:Open(args)
	ScreenBase.Show(self.Root)
	self.SelectTab(args and args.Tab or "Origins")
	self:Refresh()
end

function RaceIndexUI:Close()
	ScreenBase.Hide(self.Root)
	ScreenBase.ClearChildren(self.Detail)
end

return RaceIndexUI
