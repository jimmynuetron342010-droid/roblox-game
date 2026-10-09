--[[
	RaceRollUI — the Soul Altar
	  * The full probability table is always visible before rolling (exact server weights, total 100%).
	  * The server decides the result first; this screen only animates an outcome it was already told.
	  * Escalating soul-orb build-up that climbs through the rarity colors up to the result, a burst,
	    an optional (photosensitivity-safe) tinted flash for Epic+, then the reveal card.
	  * Fast reveal / Skip unlock after the player has watched one full reveal.
	  * Network retries reuse the same request id, so a retry can never charge twice.
	  * Replacing an invested origin shows a stat comparison and needs press-and-hold to confirm.
	  * Reduced motion: no pulsing, burst or flash — a short cross-fade instead.
]]

local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local AbilityConfig = require(Modules.Config.AbilityConfig)
local BuildModifiers = require(Modules.Core.BuildModifiers)
local BuildRules = require(Modules.Config.BuildRules)
local CombatRoleConfig = require(Modules.Config.CombatRoleConfig)
local GameConfig = require(Modules.Config.GameConfig)
local MasteryConfig = require(Modules.Config.MasteryConfig)
local Net = require(Modules.Core.Net)
local RaceConfig = require(Modules.Config.RaceConfig)
local RarityConfig = require(Modules.Config.RarityConfig)
local StatCalculator = require(Modules.Core.StatCalculator)
local Util = require(Modules.Core.Util)

local UI = script.Parent.Parent
local ClientState = require(UI.Parent.Controllers.ClientState)
local Components = require(UI.Components)
local Format = require(UI.Format)
local Icons = require(UI.Icons)
local Theme = require(UI.Theme)
local UIController = require(UI.UIController)
local UISound = require(UI.UISound)
local Viewport = require(UI.Viewport)

local RaceRollUI = {}
RaceRollUI.__index = RaceRollUI

local REASONS = {
	InsufficientFunds = "Not enough currency for that roll.",
	Cooldown = "The altar is still settling — try again in a moment.",
	PendingChoice = "Decide on your last roll first.",
	Busy = "Your previous request is still being processed.",
	RateLimited = "Slow down a little and try again.",
	NoStudent = "Create your student first.",
	Loading = "Your profile is still loading…",
	BadPayment = "Unknown payment type.",
	ServerError = "The altar faltered (server error). Nothing was charged — try again.",
	NoPending = "That decision was already made.",
}

local HOLD_TIME = 1.2
local COMPARE_HEIGHT = 236
local COMPARE_HEIGHT_COMPACT = 150

local function sortedRaces()
	local list = table.clone(RaceConfig.List)
	table.sort(list, function(a, b)
		if a.Weight ~= b.Weight then
			return a.Weight > b.Weight
		end
		return a.DisplayName < b.DisplayName
	end)
	return list
end

local function isInvested(profile, raceId: string): boolean
	local progress = profile.Race.Progress[raceId]
	return progress ~= nil and (progress.Stage > 1 or progress.XP > 0)
end

function RaceRollUI.new(layer: Frame)
	local self = setmetatable({}, RaceRollUI)
	self.State = "Idle"
	self.BlocksInput = true
	self.Closable = true
	self.Unconfirmed = nil :: { Id: string, Payment: string }?

	local root = Components.New("Frame", {
		Name = "RaceRoll",
		BackgroundColor3 = Theme.Colors.Overlay,
		BackgroundTransparency = 0.04,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = layer,
	})
	Components.Gradient(Color3.fromRGB(34, 18, 46), Color3.fromRGB(6, 4, 10)).Parent = root
	self.Root = root

	self.Title = Components.Title("SOUL ALTAR", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 14),
		Size = UDim2.fromOffset(500, 50),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = Theme.TextSize.Hero,
		Parent = root,
	})
	self.Subtitle = Components.Label("Awaken your soul's origin. Your role, weapon and magic stay your own choice.", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 62),
		Size = UDim2.fromOffset(640, 22),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Theme.Colors.TextDim,
		TextSize = Theme.TextSize.Small,
		Parent = root,
	})

	self:BuildOdds(root)
	self:BuildSide(root)
	self:BuildStage(root)

	-- Close (hidden while an animation is running).
	self.CloseButton = Components.Button("✕", function()
		UIController.CloseSelf("RaceRoll")
	end, {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -20, 0, 18),
		Size = UDim2.fromOffset(44, 44),
		Parent = root,
	}, "Ghost")

	-- Full-screen tint used for the Epic+ flash (never pure white, never strobing).
	self.Flash = Components.New("Frame", {
		Name = "Flash",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 50,
		Active = false,
		Parent = root,
	})

	ClientState.ProfileChanged:Connect(function()
		if root.Visible then
			self:RefreshSide()
		end
	end)
	return self
end

-- ── Probability table (left) ──────────────────────────────────────────────────
function RaceRollUI:BuildOdds(root: Frame)
	local panel = Components.Panel({
		Name = "Odds",
		Position = UDim2.fromOffset(24, 100),
		Size = UDim2.new(0, 330, 1, -124),
		Parent = root,
	})
	self.OddsPanel = panel
	Components.Label("Probability Table", {
		Position = UDim2.fromOffset(16, 10),
		Size = UDim2.new(1, -32, 0, 28),
		FontFace = Theme.Fonts.Hand,
		TextSize = 20,
		TextColor3 = Theme.Colors.Gold,
		Parent = panel,
	})
	local list =
		Components.Scroll({ Position = UDim2.fromOffset(12, 44), Size = UDim2.new(1, -20, 1, -128), Parent = panel })
	Components.List(Enum.FillDirection.Vertical, 6).Parent = list
	self.OddsRows = {}
	local total = 0
	for index, race in sortedRaces() do
		total += race.Weight
		local rarity = Theme.Rarity(race.Rarity)
		local row = Components.New("Frame", {
			BackgroundColor3 = Theme.Colors.InkLight,
			BackgroundTransparency = 0.2,
			Size = UDim2.new(1, -8, 0, 46),
			LayoutOrder = index,
			Parent = list,
		})
		Components.Corner(Theme.CornerSmall).Parent = row
		Components.New("Frame", {
			BackgroundColor3 = rarity.Color,
			BorderSizePixel = 0,
			Size = UDim2.new(0, 4, 1, -10),
			Position = UDim2.fromOffset(4, 5),
			Parent = row,
		})
		local emblem = Icons.Race(race.Id, rarity.Color)
		emblem.Position = UDim2.fromOffset(14, 7)
		emblem.Size = UDim2.fromOffset(32, 32)
		emblem.Parent = row
		Components.Label(race.DisplayName, {
			Position = UDim2.fromOffset(54, 3),
			Size = UDim2.new(1, -130, 0, 22),
			FontFace = Theme.Fonts.BodyBold,
			Parent = row,
		})
		Components.Label(rarity.DisplayName, {
			Position = UDim2.fromOffset(54, 23),
			Size = UDim2.new(1, -130, 0, 18),
			TextSize = Theme.TextSize.Small,
			TextColor3 = rarity.Color,
			Parent = row,
		})
		Components.Label(Format.Percent(race.Weight / GameConfig.RaceRoll.TotalWeight), {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 0),
			Size = UDim2.fromOffset(70, 46),
			TextXAlignment = Enum.TextXAlignment.Right,
			FontFace = Theme.Fonts.Display,
			TextSize = 24,
			TextColor3 = rarity.Color,
			Parent = row,
		})
		local seen = Components.Label("✓", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -84, 0, 0),
			Size = UDim2.fromOffset(18, 46),
			TextColor3 = Theme.Colors.Good,
			Visible = false,
			Parent = row,
		})
		self.OddsRows[race.Id] = { Row = row, Seen = seen }
	end
	self.OddsFooter = Components.Label(
		string.format(
			"Total: %s · Every roll uses these exact odds. The server decides the result before the animation starts. ✓ = discovered.",
			Format.Percent(total / GameConfig.RaceRoll.TotalWeight)
		),
		{
			Position = UDim2.new(0, 16, 1, -80),
			Size = UDim2.new(1, -32, 0, 70),
			TextSize = Theme.TextSize.Small,
			TextColor3 = Theme.Colors.TextMuted,
			TextYAlignment = Enum.TextYAlignment.Top,
			Parent = panel,
		}
	)
end

-- ── Current origin + actions (right) ──────────────────────────────────────────
function RaceRollUI:BuildSide(root: Frame)
	local panel = Components.Panel({
		Name = "Side",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -24, 0, 100),
		Size = UDim2.new(0, 320, 1, -124),
		Parent = root,
	})
	self.SidePanel = panel
	Components.Label("Current Origin", {
		Position = UDim2.fromOffset(16, 10),
		Size = UDim2.new(1, -32, 0, 28),
		FontFace = Theme.Fonts.Hand,
		TextSize = 20,
		TextColor3 = Theme.Colors.Gold,
		Parent = panel,
	})
	self.PortraitHolder = Components.New("Frame", {
		BackgroundColor3 = Theme.Colors.InkLight,
		Position = UDim2.fromOffset(16, 44),
		Size = UDim2.new(1, -32, 0, 150),
		Parent = panel,
	})
	Components.Corner().Parent = self.PortraitHolder
	self.CurrentName = Components.Label("", {
		Position = UDim2.fromOffset(16, 200),
		Size = UDim2.new(1, -32, 0, 30),
		FontFace = Theme.Fonts.Display,
		TextSize = 28,
		Parent = panel,
	})
	self.CurrentInfo = Components.Label("", {
		Position = UDim2.fromOffset(16, 230),
		Size = UDim2.new(1, -32, 0, 40),
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Colors.TextDim,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = panel,
	})
	self.Wallet = Components.Label("", {
		Position = UDim2.fromOffset(16, 274),
		Size = UDim2.new(1, -32, 0, 24),
		FontFace = Theme.Fonts.BodyBold,
		Parent = panel,
	})

	local actions = Components.New("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -12),
		Size = UDim2.new(1, -32, 0, 196),
		Parent = panel,
	})
	Components.List(Enum.FillDirection.Vertical, 8).Parent = actions
	self.RollToken = Components.Button(
		"",
		function()
			self:Roll("Token")
		end,
		{ Size = UDim2.new(1, 0, 0, 50), LayoutOrder = 1, TextSize = Theme.TextSize.Large, Parent = actions },
		"Primary"
	)
	self.RollSouls = Components.Button("", function()
		self:Roll("Souls")
	end, { Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 2, Parent = actions }, "Secondary")
	self.FastToggle = Components.Button("", function()
		self:ToggleFast()
	end, {
		Size = UDim2.new(1, 0, 0, 40),
		LayoutOrder = 3,
		TextSize = Theme.TextSize.Small,
		TextWrapped = true,
		Parent = actions,
	}, "Ghost")
	self.Status = Components.Label("", {
		Size = UDim2.new(1, 0, 0, 40),
		LayoutOrder = 4,
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Colors.Bad,
		FontFace = Theme.Fonts.BodyBold,
		Parent = actions,
	})
end

function RaceRollUI:RefreshSide()
	local profile = ClientState.Profile
	if not profile then
		return
	end
	local raceId = profile.Race.Active
	local race = RaceConfig.ById[raceId]
	if self.Portrait then
		self.Portrait:Destroy()
	end
	local stage = BuildModifiers.RaceStage(profile, raceId)
	self.Portrait = Viewport.Character(
		self.PortraitHolder,
		{ Student = profile.Student, RaceId = raceId, Stage = stage, Framing = "Portrait", Spin = true }
	)
	if race then
		local rarity = Theme.Rarity(race.Rarity)
		self.CurrentName.Text = race.DisplayName
		self.CurrentName.TextColor3 = rarity.Color
		self.CurrentInfo.Text = string.format(
			"%s · Mastery %s (%s)\n%s",
			rarity.DisplayName,
			MasteryConfig.StageNumerals[stage],
			MasteryConfig.StageNames[stage],
			race.Classification.Label
		)
	else
		self.CurrentName.Text = "Unawakened"
		self.CurrentName.TextColor3 = Theme.Colors.TextDim
		self.CurrentInfo.Text = "Your first roll is applied immediately."
	end
	local currency = profile.Currency
	self.Wallet.Text =
		string.format("Race Rolls: %d     Souls: %s", currency.RaceRolls, Util.FormatNumber(currency.Souls))
	local cfg = GameConfig.RaceRoll
	self.RollToken.Text = string.format("Roll — %d Race Roll", cfg.TokenCost)
	self.RollSouls.Text = string.format("Roll — %s Souls", Util.FormatNumber(cfg.SoulsCost))
	local canToken = currency.RaceRolls >= cfg.TokenCost
	local canSouls = currency.Souls >= cfg.SoulsCost
	self.RollToken.BackgroundTransparency = canToken and 0 or 0.55
	self.RollSouls.BackgroundTransparency = canSouls and 0 or 0.55
	local seen = profile.Settings.SeenRollAnimation == true
	if seen then
		self.FastToggle.Text = "Fast reveal: " .. (profile.Settings.FastReveal and "ON" or "OFF")
	else
		self.FastToggle.Text = "Fast reveal unlocks after one full reveal"
	end
	self.FastToggle.TextColor3 = seen and Theme.Colors.Text or Theme.Colors.TextMuted
	for id, row in self.OddsRows do
		row.Seen.Visible = profile.Race.Discovered[id] ~= nil
	end
end

function RaceRollUI:ToggleFast()
	local profile = ClientState.Profile
	if not profile or not profile.Settings.SeenRollAnimation or self.State ~= "Idle" then
		return
	end
	local value = not profile.Settings.FastReveal
	self.FastToggle.Text = "Fast reveal: " .. (value and "ON" or "OFF")
	task.spawn(function()
		pcall(function()
			Net.Function("UpdateSettings"):InvokeServer({ FastReveal = value })
		end)
	end)
end

-- ── Stage: orb, burst and the reveal card (center) ────────────────────────────
function RaceRollUI:BuildStage(root: Frame)
	local stage = Components.New("Frame", {
		Name = "Stage",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(370, 96),
		Size = UDim2.new(1, -726, 1, -116),
		ClipsDescendants = false,
		Parent = root,
	})
	self.Stage = stage

	local orb = Components.New("Frame", {
		Name = "Orb",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(170, 170),
		BackgroundColor3 = Theme.Colors.Soul,
		Parent = stage,
	})
	Components.Corner(UDim.new(1, 0)).Parent = orb
	local glow = Instance.new("UIGradient")
	glow.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(180, 180, 200))
	glow.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.7, 0.1),
		NumberSequenceKeypoint.new(1, 0.6),
	})
	glow.Parent = orb
	self.OrbStroke = Components.Stroke(Theme.Colors.Soul, 6, 0.1)
	self.OrbStroke.Parent = orb
	self.OrbScale = Instance.new("UIScale")
	self.OrbScale.Parent = orb
	local face = Icons.Grin(Color3.fromRGB(20, 16, 28))
	face.AnchorPoint = Vector2.new(0.5, 0.5)
	face.Position = UDim2.fromScale(0.5, 0.55)
	face.Size = UDim2.fromScale(0.6, 0.45)
	face.Parent = orb
	self.Orb = orb
	self.OrbText = Components.Label("Place your soul upon the altar.", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.42, 110),
		Size = UDim2.new(1, -20, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Center,
		FontFace = Theme.Fonts.Hand,
		TextSize = 22,
		TextColor3 = Theme.Colors.TextDim,
		Parent = stage,
	})
	self.Skip = Components.Button("Skip ▸▸", function()
		self.SkipRequested = true
	end, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.fromOffset(140, 40),
		Visible = false,
		Parent = stage,
	}, "Ghost")

	self.Shards = Components.New(
		"Frame",
		{ Name = "Shards", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = stage }
	)
	self.Shards:SetAttribute("Decorative", true) -- burst particles are meant to fly off-screen
end

local function waitOrSkip(seconds: number, self)
	local deadline = os.clock() + seconds
	while os.clock() < deadline do
		if self.SkipRequested then
			return true
		end
		task.wait()
	end
	return false
end

-- Orb charge-up that escalates through the rarity colors up to (and stopping at) the result tier.
function RaceRollUI:PlayBuildUp(rarity, fast: boolean)
	local reduced = Theme.ReducedMotion()
	local profile = ClientState.Profile
	local canSkip = profile and profile.Settings.SeenRollAnimation == true
	self.SkipRequested = false
	self.Skip.Visible = canSkip and not fast
	local total = fast and 0.45 or rarity.RevealBuildUp
	local steps = {}
	for _, tier in RarityConfig.Ordered do
		if tier.Order <= rarity.Order then
			table.insert(steps, tier)
		end
	end
	UISound.Play("RollCharge")
	self.OrbText.Text = "The soul resonates…"
	local stepTime = total / #steps
	for index, tier in steps do
		if reduced then
			self.Orb.BackgroundColor3 = tier.Color
			self.OrbStroke.Color = tier.AccentColor
		else
			Theme.Tween(self.Orb, stepTime * 0.8, { BackgroundColor3 = tier.Color })
			Theme.Tween(self.OrbStroke, stepTime * 0.8, { Color = tier.AccentColor, Thickness = 6 + index * 2 })
			self.OrbScale.Scale = 1 + index * 0.05
			Theme.Tween(self.OrbScale, stepTime * 0.9, { Scale = 1 + index * 0.025 }, Enum.EasingStyle.Back)
		end
		if index == #steps then
			self.OrbText.Text = "…"
		end
		if waitOrSkip(stepTime, self) then
			break
		end
	end
	self.Skip.Visible = false
	self.Orb.BackgroundColor3 = rarity.Color
	self.OrbStroke.Color = rarity.AccentColor
end

function RaceRollUI:PlayBurst(rarity)
	if Theme.ReducedMotion() then
		return
	end
	local count = math.min(rarity.ParticleBurst, 48)
	local center = self.Orb.Position
	for i = 1, count do
		local angle = (i / count) * math.pi * 2 + math.random() * 0.3
		local distance = 160 + math.random() * 220
		local shard = Components.New("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = center,
			Size = UDim2.fromOffset(6 + math.random(0, 8), 22 + math.random(0, 26)),
			Rotation = math.deg(angle) + 90,
			BackgroundColor3 = (i % 3 == 0) and rarity.AccentColor or rarity.Color,
			BorderSizePixel = 0,
			Parent = self.Shards,
		})
		Components.Corner(UDim.new(1, 0)).Parent = shard
		Theme.Tween(shard, 0.7 + math.random() * 0.3, {
			Position = center + UDim2.fromOffset(math.cos(angle) * distance, math.sin(angle) * distance),
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(2, 6),
		})
		task.delay(1.1, function()
			shard:Destroy()
		end)
	end
	if rarity.ScreenFlash then
		-- Tinted, low-intensity single flash (no strobing; < 40% opacity).
		self.Flash.BackgroundColor3 = rarity.Color:Lerp(Color3.new(1, 1, 1), 0.5)
		self.Flash.BackgroundTransparency = 0.62
		Theme.Tween(self.Flash, 0.6, { BackgroundTransparency = 1 })
	end
	self.OrbScale.Scale = 1.35
	Theme.Tween(self.OrbScale, 0.35, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
end

-- ── Reveal card ───────────────────────────────────────────────────────────────
function RaceRollUI:ClearCard()
	if self.Card then
		self.Card:Destroy()
		self.Card = nil
	end
end

local function section(parent: Instance, order: number, title: string, body: string, color: Color3?)
	local box = Components.New("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order,
		Parent = parent,
	})
	Components.List(Enum.FillDirection.Vertical, 2).Parent = box
	Components.Label(title, {
		Size = UDim2.new(1, 0, 0, 20),
		FontFace = Theme.Fonts.BodyBold,
		TextSize = Theme.TextSize.Small,
		TextColor3 = color or Theme.Colors.Gold,
		LayoutOrder = 1,
		Parent = box,
	})
	Components.Label(body, {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Colors.TextDim,
		LayoutOrder = 2,
		Parent = box,
	})
	return box
end

function RaceRollUI:ShowCard(result, decision: boolean)
	-- Height kept free below the portrait/details: footer buttons, plus the comparison when deciding.
	local compareHeight = self.Compact and COMPARE_HEIGHT_COMPACT or COMPARE_HEIGHT
	local reserved = decision and (80 + compareHeight + 10) or 120
	self:ClearCard()
	local profile = ClientState.Profile
	local race = RaceConfig.ById[result.RaceId]
	local rarity = Theme.Rarity(race.Rarity)
	local card = Components.Panel({
		Name = "RevealCard",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Parent = self.Stage,
	})
	self.Card = card
	Components.RarityBorder(card, rarity.Color, rarity.AccentColor, rarity.Order >= 4)
	local cardScale = Instance.new("UIScale")
	cardScale.Parent = card
	if not Theme.ReducedMotion() then
		cardScale.Scale = 0.85
		Theme.Tween(cardScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	end

	-- Banner.
	local banner =
		Components.New("Frame", { BackgroundColor3 = rarity.Color, Size = UDim2.new(1, 0, 0, 34), Parent = card })
	Components.Corner().Parent = banner
	Components.Gradient(rarity.Color, rarity.AccentColor, 0).Parent = banner
	Components.Label(string.upper(rarity.DisplayName) .. (result.IsNew and "   ·   NEW DISCOVERY!" or ""), {
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		FontFace = Theme.Fonts.Display,
		TextSize = 24,
		TextColor3 = Theme.Colors.Ink,
		Parent = banner,
	})

	-- Portrait (left) and details (right).
	local split = self.Compact and 0 or 0.36
	if not self.Compact then
		local portrait = Components.New("Frame", {
			BackgroundColor3 = Theme.Colors.InkLight,
			Position = UDim2.fromOffset(14, 46),
			Size = UDim2.new(split, -14, 1, -reserved),
			Parent = card,
		})
		Components.Corner().Parent = portrait
		local stage = BuildModifiers.RaceStage(profile, race.Id)
		Viewport.Character(
			portrait,
			{ Student = profile.Student, RaceId = race.Id, Stage = stage, Framing = "Full", Spin = true }
		)
	end

	local details = Components.Scroll({
		Position = UDim2.new(split, self.Compact and 14 or 10, 0, 46),
		Size = UDim2.new(1 - split, -24, 1, -reserved),
		Parent = card,
	})
	Components.List(Enum.FillDirection.Vertical, 8).Parent = details
	Components.Label(race.DisplayName, {
		Size = UDim2.new(1, 0, 0, 40),
		FontFace = Theme.Fonts.Display,
		TextSize = 38,
		TextColor3 = rarity.Color,
		LayoutOrder = 1,
		Parent = details,
	})
	Components.Label(
		string.format(
			"“%s”  ·  %s  ·  %s",
			race.Tagline,
			race.Classification.Label,
			Format.Percent(race.Weight / GameConfig.RaceRoll.TotalWeight) .. " chance"
		),
		{
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextSize = Theme.TextSize.Small,
			TextColor3 = Theme.Colors.TextDim,
			LayoutOrder = 2,
			Parent = details,
		}
	)
	local mods = {}
	for _, modifier in race.Modifiers do
		table.insert(mods, Format.Modifier(modifier))
	end
	section(details, 3, "Stat Boosts", table.concat(mods, "   ·   "))
	section(details, 4, "Passive — " .. race.Passive.Name, race.Passive.Description)
	if race.AbilityId then
		local _, _, name, description = AbilityConfig.Resolve(race.AbilityId, 1)
		local unlock = race.AbilityUnlockStage > 1
				and string.format(" (unlocks at Mastery %s)", MasteryConfig.StageNumerals[race.AbilityUnlockStage])
			or ""
		section(details, 5, "Ability [C] — " .. name .. unlock, description)
	end
	if race.Drawback then
		section(details, 6, "Drawback", race.Drawback, Theme.Colors.Bad)
	end
	if result.SameRace then
		section(
			details,
			7,
			"Soul Echo",
			string.format(
				"You already carry this soul. Your mastery is untouched and you gain +%d mastery XP.",
				result.SoulEchoXP or 0
			),
			Theme.Colors.Good
		)
	elseif result.Applied then
		section(
			details,
			7,
			"Origin Awakened",
			"This is now your origin. Mastery stages, passives and your racial ability are unlocked through play.",
			Theme.Colors.Good
		)
	end

	local footer = Components.New("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 14, 1, -12),
		Size = UDim2.new(1, -28, 0, 60),
		Parent = card,
	})
	if decision then
		self:BuildDecision(card, footer, result)
	else
		local continue = Components.Button("Continue", function()
			self:EndReveal()
		end, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(1, 0.5),
			Size = UDim2.fromOffset(180, 50),
			TextSize = Theme.TextSize.Large,
			Parent = footer,
		}, "Primary")
		if UserInputService.GamepadEnabled then
			GuiService.SelectedObject = continue
		end
	end
end

-- Keep / Replace with a stat comparison.
function RaceRollUI:BuildDecision(card: Frame, footer: Frame, result)
	local profile = ClientState.Profile
	local currentId = profile.Race.Active
	local current = RaceConfig.ById[currentId]
	local newRace = RaceConfig.ById[result.RaceId]

	local role = profile.Loadout.Role
	local school = profile.Loadout.School ~= "" and profile.Loadout.School or nil
	local newRole, _, changes = BuildRules.Sanitize(newRace.Id, role, school, profile.Level)
	local before = StatCalculator.Compute(profile.Level, BuildModifiers.FromProfile(profile))
	local after = StatCalculator.Compute(
		profile.Level,
		BuildModifiers.FromProfile(profile, { RaceId = newRace.Id, Role = newRole })
	)
	local diff = StatCalculator.Diff(before, after)
	table.sort(diff, function(a, b)
		return math.abs(a.Delta / math.max(math.abs(a.Before), 0.01))
			> math.abs(b.Delta / math.max(math.abs(b.Before), 0.01))
	end)

	local compare = Components.Panel({
		Name = "Compare",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -80),
		Size = UDim2.new(1, -28, 0, self.Compact and COMPARE_HEIGHT_COMPACT or COMPARE_HEIGHT),
		ClipsDescendants = true,
		BackgroundColor3 = Theme.Colors.InkLight,
		ZIndex = 5,
		Parent = card,
	})
	Components.Padding(10, 14).Parent = compare
	Components.List(Enum.FillDirection.Vertical, 4).Parent = compare
	Components.Label(
		string.format("Replace %s with %s?", current and current.DisplayName or "—", newRace.DisplayName),
		{
			Size = UDim2.new(1, 0, 0, 24),
			FontFace = Theme.Fonts.BodyBold,
			TextColor3 = Theme.Colors.Gold,
			LayoutOrder = 1,
			Parent = compare,
		}
	)
	local lines = {}
	for i = 1, math.min(#diff, self.Compact and 4 or 6) do
		local d = diff[i]
		local arrow = d.Delta >= 0 and "▲" or "▼"
		table.insert(
			lines,
			string.format(
				'<font color="#%s">%s %s %s → %s</font>',
				d.Delta >= 0 and "6CE08C" or "FF6C6C",
				arrow,
				Format.StatName(d.Stat),
				Format.StatValue(d.Stat, d.Before),
				Format.StatValue(d.Stat, d.After)
			)
		)
	end
	if #lines == 0 then
		table.insert(lines, "No change to your base stats.")
	end
	Components.Label(table.concat(lines, "\n"), {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		RichText = true,
		TextSize = Theme.TextSize.Small,
		LayoutOrder = 2,
		Parent = compare,
	})
	local notes = {}
	if current then
		local stage = BuildModifiers.RaceStage(profile, currentId)
		table.insert(
			notes,
			string.format(
				"Your %s mastery (Stage %s) is saved — roll it again later and it returns.",
				current.DisplayName,
				MasteryConfig.StageNumerals[stage]
			)
		)
	end
	for _, change in changes do
		table.insert(notes, change)
	end
	if newRole ~= role then
		table.insert(notes, "Combat role will become " .. CombatRoleConfig.ById[newRole].DisplayName .. ".")
	end
	Components.Label(table.concat(notes, "\n"), {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Colors.TextMuted,
		LayoutOrder = 3,
		Parent = compare,
	})

	local keep = Components.Button("Keep " .. (current and current.DisplayName or "current"), function()
		self:Resolve(result.RequestId, false)
	end, {
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.new(0.5, -6, 1, 0),
		TextWrapped = true,
		Parent = footer,
	}, "Secondary")
	Components.Padding(4, 10).Parent = keep
	local invested = current ~= nil and isInvested(profile, currentId)
	local replace = Components.Button("", nil, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.5, -6, 1, 0),
		ClipsDescendants = true,
		TextWrapped = true,
		Parent = footer,
	}, "Primary")
	Components.Padding(4, 10).Parent = replace
	if not invested then
		replace.Text = "Replace with " .. newRace.DisplayName
		replace.Activated:Connect(function()
			self:Resolve(result.RequestId, true)
		end)
	else
		replace.Text = "Hold to replace with " .. newRace.DisplayName
		self:MakeHold(replace, function()
			self:Resolve(result.RequestId, true)
		end)
	end
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = keep
	end
end

-- Press-and-hold (mouse, touch, or gamepad A / Enter while selected).
function RaceRollUI:MakeHold(button: TextButton, onConfirm: () -> ())
	-- The button has UIPadding (4, 10); the fill sits in the padding gutter so it spans edge to edge.
	local function fillSize(t: number): UDim2
		return UDim2.new(t, 20 * t, 1, 8)
	end
	local fill = Components.New("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.6,
		Position = UDim2.fromOffset(-10, -4),
		Size = fillSize(0),
		ZIndex = button.ZIndex + 1,
		Parent = button,
	})
	local holding = false
	local token = 0
	local function begin()
		if holding then
			return
		end
		holding = true
		token += 1
		local mine = token
		local started = os.clock()
		task.spawn(function()
			while holding and mine == token and button.Parent do
				local t = (os.clock() - started) / HOLD_TIME
				fill.Size = fillSize(math.clamp(t, 0, 1))
				if t >= 1 then
					holding = false
					UISound.Play("Confirm")
					onConfirm()
					return
				end
				task.wait()
			end
			fill.Size = fillSize(0)
		end)
	end
	local function stop()
		holding = false
	end
	button.MouseButton1Down:Connect(begin)
	button.MouseButton1Up:Connect(stop)
	button.MouseLeave:Connect(stop)
	local began = UserInputService.InputBegan:Connect(function(input)
		if
			(input.KeyCode == Enum.KeyCode.ButtonA or input.KeyCode == Enum.KeyCode.Return)
			and GuiService.SelectedObject == button
		then
			begin()
		end
	end)
	local ended = UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.ButtonA or input.KeyCode == Enum.KeyCode.Return then
			stop()
		end
	end)
	button.Destroying:Connect(function()
		began:Disconnect()
		ended:Disconnect()
	end)
end

-- ── Responsive layout ─────────────────────────────────────────────────────────
-- Short screens (phones in landscape) drop the side portrait and tighten the header so the roll
-- buttons never cover the current-origin details.
function RaceRollUI:ApplyLayout(compact: boolean)
	self.Compact = compact
	local top = compact and 74 or 100
	self.Title.TextSize = compact and 34 or Theme.TextSize.Hero
	self.Title.Position = UDim2.new(0.5, 0, 0, compact and 6 or 14)
	self.Subtitle.Position = UDim2.new(0.5, 0, 0, compact and 44 or 62)
	self.OddsPanel.Position = UDim2.fromOffset(24, top)
	self.OddsPanel.Size = UDim2.new(0, 330, 1, -(top + 24))
	self.SidePanel.Position = UDim2.new(1, -24, 0, top)
	self.SidePanel.Size = UDim2.new(0, 320, 1, -(top + 24))
	self.Stage.Position = UDim2.fromOffset(370, top - 4)
	self.Stage.Size = UDim2.new(1, -726, 1, -(top + 16))
	self.PortraitHolder.Visible = not compact
	local infoTop = compact and 44 or 200
	self.CurrentName.Position = UDim2.fromOffset(16, infoTop)
	self.CurrentInfo.Position = UDim2.fromOffset(16, infoTop + 30)
	self.Wallet.Position = UDim2.fromOffset(16, infoTop + 74)
end

-- ── Flow ──────────────────────────────────────────────────────────────────────
function RaceRollUI:SetBusy(busy: boolean)
	self.Closable = not busy
	self.CloseButton.Visible = not busy
	self.RollToken.Active = not busy
	self.RollSouls.Active = not busy
	self.RollToken.AutoButtonColor = false
end

local function invoke(remoteName: string, ...)
	local remote = Net.Function(remoteName)
	local args = table.pack(...)
	for attempt = 1, 3 do
		local ok, response = pcall(function()
			return remote:InvokeServer(table.unpack(args, 1, args.n))
		end)
		if ok and type(response) == "table" then
			return response
		end
		task.wait(0.4 * attempt)
	end
	return nil
end

function RaceRollUI:ShowError(reason: string?)
	self.Status.Text = REASONS[reason or ""] or ("Roll failed: " .. tostring(reason))
	UISound.Play("Error")
end

function RaceRollUI:Roll(payment: string)
	local profile = ClientState.Profile
	if self.State ~= "Idle" or not profile then
		return
	end
	self.Status.Text = ""
	-- Retry an unconfirmed request with the same id (never double-charges).
	local requestId
	if self.Unconfirmed and self.Unconfirmed.Payment == payment then
		requestId = self.Unconfirmed.Id
	else
		requestId = HttpService:GenerateGUID(false)
	end
	self.Unconfirmed = { Id = requestId, Payment = payment }
	self.State = "Requesting"
	self:SetBusy(true)
	self:ClearCard()
	self.Orb.Visible = true
	self.OrbScale.Scale = 1
	self.OrbText.Text = "Contacting the altar…"

	local result = invoke("RollRace", requestId, payment)
	if not result then
		self.State = "Idle"
		self:SetBusy(false)
		self.Status.Text =
			"Connection problem. Press roll again — the same request is retried and never charged twice."
		return
	end
	self.Unconfirmed = nil
	if not result.Ok then
		self.State = "Idle"
		self:SetBusy(false)
		self.OrbText.Text = "Place your soul upon the altar."
		if result.Reason == "PendingChoice" and result.Pending and result.Pending.RaceId then
			self:ShowPending(result.Pending)
			return
		end
		self:ShowError(result.Reason)
		return
	end
	if result.Currency then
		self.Wallet.Text = string.format(
			"Race Rolls: %d     Souls: %s",
			result.Currency.RaceRolls,
			Util.FormatNumber(result.Currency.Souls)
		)
	end
	self:Reveal(result)
end

function RaceRollUI:Reveal(result)
	local profile = ClientState.Profile
	local race = RaceConfig.ById[result.RaceId]
	local rarity = Theme.Rarity(race.Rarity)
	local seen = profile and profile.Settings.SeenRollAnimation == true
	local fast = seen and profile.Settings.FastReveal == true
	self.State = "Animating"
	self:PlayBuildUp(rarity, fast)
	UISound.Play(rarity.SoundKey, 0.8)
	self:PlayBurst(rarity)
	task.wait(Theme.ReducedMotion() and 0 or 0.3)
	self.Orb.Visible = false
	self.OrbText.Text = ""
	self.State = result.NeedsConfirm and "Deciding" or "Revealed"
	self:SetBusy(false)
	self:ShowCard(result, result.NeedsConfirm == true)
	if not seen then
		task.spawn(invoke, "UpdateSettings", { SeenRollAnimation = true })
	end
end

-- A decision that is still open (e.g. the player disconnected mid-choice).
function RaceRollUI:ShowPending(pending)
	self.Orb.Visible = false
	self.OrbText.Text = ""
	self.State = "Deciding"
	self:ShowCard({ RaceId = pending.RaceId, RequestId = pending.RequestId, NeedsConfirm = true }, true)
	self.Status.Text = "You still have an undecided roll."
end

function RaceRollUI:Resolve(requestId: string, accept: boolean)
	if self.State ~= "Deciding" then
		return
	end
	self.State = "Resolving"
	self:SetBusy(true)
	local result = invoke("ResolveRaceRoll", requestId, accept)
	self:SetBusy(false)
	if not result then
		self.State = "Deciding"
		self.Status.Text = "Connection problem — your choice was not lost. Try again."
		return
	end
	if not result.Ok and result.Reason ~= "NoPending" then
		self.State = "Deciding"
		self:ShowError(result.Reason)
		return
	end
	self:EndReveal()
end

function RaceRollUI:EndReveal()
	self.State = "Idle"
	self:ClearCard()
	self.Orb.Visible = true
	self.Orb.BackgroundColor3 = Theme.Colors.Soul
	self.OrbStroke.Color = Theme.Colors.Soul
	self.OrbStroke.Thickness = 6
	self.OrbScale.Scale = 1
	self.OrbText.Text = "Place your soul upon the altar."
	self:RefreshSide()
end

function RaceRollUI:Open(_args)
	self:ApplyLayout(UIController.IsCompact())
	self.Root.Visible = true
	self.Status.Text = ""
	if self.State == "Idle" then
		self:EndReveal()
	end
	local profile = ClientState.Profile
	if profile and self.State == "Idle" and profile.Race.Pending and profile.Race.Pending.RaceId then
		self:ShowPending(profile.Race.Pending)
	end
	if self.OnVisibility then
		self.OnVisibility(true)
	end
end

function RaceRollUI:Close()
	if self.State == "Requesting" or self.State == "Animating" or self.State == "Resolving" then
		return
	end
	if self.State == "Revealed" then
		self:EndReveal()
	end
	self.Root.Visible = false
	if self.OnVisibility then
		self.OnVisibility(false)
	end
end

return RaceRollUI
