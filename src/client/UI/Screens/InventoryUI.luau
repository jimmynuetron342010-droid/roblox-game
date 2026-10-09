--[[
	InventoryUI — weapons
	A grid of all weapons (owned / locked by level) and a detail pane with a live 3D turntable of the
	actual in-game model, moveset, weapon mastery progress, canon/original lore note, and actions:
	Equip, Draw/Holster, and Tsubaki form switching. Opened from the HUD or the weapon rack prompts
	(which pass { WeaponId } to preselect that weapon).
]]

local Players = game:GetService("Players")

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local LoreCodex = require(Modules.Config.LoreCodex)
local Net = require(Modules.Core.Net)
local WeaponConfig = require(Modules.WeaponConfig)

local UI = script.Parent.Parent
local ClientState = require(UI.Parent.Controllers.ClientState)
local Components = require(UI.Components)
local Notifications = require(UI.Notifications)
local ScreenBase = require(UI.ScreenBase)
local Theme = require(UI.Theme)
local Viewport = require(UI.Viewport)

local InventoryUI = {}
InventoryUI.__index = InventoryUI

local player = Players.LocalPlayer

local REASONS = {
	NotOwned = "You haven't unlocked that weapon yet.",
	Cooldown = "Wait a moment before switching again.",
	BadWeapon = "Unknown weapon.",
	Loading = "Your character is still loading.",
	RateLimited = "Slow down a little.",
}

local function masteryProgress(xp: number): (number, number)
	local level = WeaponConfig.MasteryLevel(xp)
	local thresholds = WeaponConfig.MasteryThresholds
	local current = thresholds[level + 1] or 0
	local nextAt = thresholds[level + 2]
	if not nextAt then
		return level, 1
	end
	return level, (xp - current) / (nextAt - current)
end

local function prettyAttack(id: string): string
	local name = string.match(id, "_(.+)$") or id
	return (string.gsub(name, "(%l)(%u)", "%1 %2"))
end

function InventoryUI.new(layer: Frame)
	local self = setmetatable({}, InventoryUI)
	self.BlocksInput = true
	local root, content = ScreenBase.Modal("Inventory", "INVENTORY — WEAPONS", layer)
	self.Root = root
	local left, right = ScreenBase.Columns(content, 0.44)
	self.Grid = Components.Scroll({ Size = UDim2.fromScale(1, 1), Parent = left })
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(142, 118)
	grid.CellPadding = UDim2.fromOffset(10, 10)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = self.Grid
	Components.Padding(4).Parent = self.Grid
	self.Detail =
		Components.Panel({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.Colors.InkLight, Parent = right })
	self.Selected = nil :: string?
	ClientState.ProfileChanged:Connect(function()
		if root.Visible then
			self:Refresh(false)
		end
	end)
	return self
end

function InventoryUI:Refresh(rebuildDetail: boolean?)
	local profile = ClientState.Profile
	if not profile then
		return
	end
	ScreenBase.ClearChildren(self.Grid)
	for index, weaponId in WeaponConfig.Order do
		local weapon = WeaponConfig.Weapons[weaponId]
		local owned = profile.Weapons.Owned[weaponId] == true
		local equipped = profile.Loadout.Weapon == weaponId
		local card = Components.Button("", function()
			self:Select(weaponId)
		end, { LayoutOrder = index, Size = UDim2.fromOffset(142, 118), Parent = self.Grid }, "Ghost")
		local stroke = card:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = equipped and Theme.Colors.Gold
				or (self.Selected == weaponId and Theme.Colors.Text or Theme.Colors.Stroke)
			stroke.Thickness = equipped and 3 or 1.5
		end
		local holder = Components.New("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(6, 4),
			Size = UDim2.new(1, -12, 0, 70),
			Parent = card,
		})
		if owned then
			-- Static thumbnail (no spin) keeps 12 viewports cheap.
			Viewport.Weapon(holder, weaponId, weaponId == "TsubakiForms" and profile.Loadout.TsubakiForm or nil, false)
		else
			Components.Label("🔒", {
				Size = UDim2.fromScale(1, 1),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextSize = 30,
				Parent = holder,
			})
		end
		Components.Label(weapon.DisplayName, {
			Position = UDim2.fromOffset(6, 74),
			Size = UDim2.new(1, -12, 0, 22),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextSize = 13,
			FontFace = Theme.Fonts.BodyBold,
			TextColor3 = owned and Theme.Colors.Text or Theme.Colors.TextMuted,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = card,
		})
		Components.Label(
			equipped and "EQUIPPED" or (owned and weapon.Category or ("Unlocks at Lv. " .. (weapon.UnlockLevel or 1))),
			{
				Position = UDim2.fromOffset(6, 94),
				Size = UDim2.new(1, -12, 0, 18),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextSize = 12,
				TextColor3 = equipped and Theme.Colors.Gold or Theme.Colors.TextMuted,
				Parent = card,
			}
		)
	end
	if rebuildDetail then
		self.Preview = nil
	end
	self:Select(self.Selected or profile.Loadout.Weapon)
end

function InventoryUI:Action(payload)
	local ok, result = pcall(function()
		return Net.Function("EquipWeapon"):InvokeServer(payload)
	end)
	if not ok or type(result) ~= "table" then
		Notifications.Show("Connection problem — try again.", "Warning")
		return nil
	end
	if not result.Ok then
		Notifications.Show(REASONS[result.Reason] or ("Couldn't do that: " .. tostring(result.Reason)), "Warning")
	end
	return result
end

function InventoryUI:Select(weaponId: string)
	local profile = ClientState.Profile
	local weapon = WeaponConfig.Weapons[weaponId]
	if not profile or not weapon then
		return
	end
	local changed = self.Selected ~= weaponId or self.ShownForm ~= profile.Loadout.TsubakiForm
	self.Selected = weaponId
	local owned = profile.Weapons.Owned[weaponId] == true
	local equipped = profile.Loadout.Weapon == weaponId
	local form = weaponId == "TsubakiForms" and profile.Loadout.TsubakiForm or nil
	if changed or not self.Preview or not self.Preview.Parent then
		ScreenBase.ClearChildren(self.Detail)
		self.ShownForm = profile.Loadout.TsubakiForm
		local stage = Components.New("Frame", {
			BackgroundColor3 = Theme.Colors.Ink,
			Position = UDim2.fromOffset(12, 12),
			Size = UDim2.new(1, -24, 0.46, -12),
			Parent = self.Detail,
		})
		Components.Corner().Parent = stage
		self.Preview = Viewport.Weapon(stage, weaponId, form, true)
		self.Info = Components.Scroll({
			Position = UDim2.new(0, 14, 0.46, 8),
			Size = UDim2.new(1, -28, 0.54, -76),
			Parent = self.Detail,
		})
		Components.List(Enum.FillDirection.Vertical, 6).Parent = self.Info
		self.Actions = Components.New("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 14, 1, -12),
			Size = UDim2.new(1, -28, 0, 48),
			Parent = self.Detail,
		})
		Components.List(Enum.FillDirection.Horizontal, 8).Parent = self.Actions
	end
	ScreenBase.ClearChildren(self.Info)
	ScreenBase.ClearChildren(self.Actions)

	local resolved = WeaponConfig.Resolve(weaponId, form)
	Components.Label(weapon.DisplayName, {
		Size = UDim2.new(1, 0, 0, 34),
		FontFace = Theme.Fonts.Display,
		TextSize = 32,
		TextColor3 = Theme.Colors.Gold,
		LayoutOrder = 1,
		Parent = self.Info,
	})
	local moves = {}
	for _, attackId in resolved.Moveset.M1 do
		table.insert(moves, prettyAttack(attackId))
	end
	local lines = {
		string.format(
			"<b>%s</b>%s",
			weapon.Category,
			resolved.Form and (" · Form: " .. weapon.Forms[resolved.Form].DisplayName) or ""
		),
		"M1: " .. table.concat(moves, " → "),
	}
	if resolved.Moveset.Z then
		table.insert(lines, "Z: " .. prettyAttack(resolved.Moveset.Z))
	end
	if resolved.Moveset.X then
		table.insert(lines, "X: " .. prettyAttack(resolved.Moveset.X))
	end
	Components.Label(table.concat(lines, "\n"), {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		RichText = true,
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Colors.TextDim,
		LayoutOrder = 2,
		Parent = self.Info,
	})

	local xp = profile.Weapons.Mastery[weaponId] or 0
	local level, fraction = masteryProgress(xp)
	Components.Label(
		string.format(
			"Weapon Mastery %d  (+%d%% weapon damage)",
			level,
			math.floor(level * WeaponConfig.MasteryDamagePerLevel * 100 + 0.5)
		),
		{
			Size = UDim2.new(1, 0, 0, 20),
			FontFace = Theme.Fonts.BodyBold,
			TextSize = Theme.TextSize.Small,
			LayoutOrder = 3,
			Parent = self.Info,
		}
	)
	local bar, setFill = Components.Bar(Theme.Colors.Gold, { Size = UDim2.new(1, -8, 0, 10), LayoutOrder = 4 })
	bar.Parent = self.Info
	setFill(fraction)
	local note = LoreCodex.WeaponNotes[weaponId]
	if note then
		Components.Label(note, {
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextSize = 13,
			TextColor3 = Theme.Colors.TextMuted,
			LayoutOrder = 5,
			Parent = self.Info,
		})
	end

	if not owned then
		Components.Label(
			string.format("Reach level %d to unlock.", weapon.UnlockLevel or 1),
			{ Size = UDim2.fromScale(1, 1), TextColor3 = Theme.Colors.TextMuted, Parent = self.Actions }
		)
		return
	end
	if not equipped then
		Components.Button("Equip", function()
			self:Action({ Action = "Equip", WeaponId = weaponId })
		end, { Size = UDim2.fromOffset(150, 46), LayoutOrder = 1, Parent = self.Actions }, "Primary")
	else
		local character = player.Character
		local drawn = character and character:GetAttribute("WeaponDrawn")
		Components.Button(drawn and "Holster" or "Draw", function()
			self:Action({ Action = "Draw", Drawn = not drawn })
			task.delay(0.15, function()
				if self.Root.Visible then
					self:Select(weaponId)
				end
			end)
		end, { Size = UDim2.fromOffset(130, 46), LayoutOrder = 1, Parent = self.Actions }, "Secondary")
	end
	if weapon.Forms then
		for index, formId in weapon.FormOrder do
			local current = profile.Loadout.TsubakiForm == formId
			Components.Button(weapon.Forms[formId].DisplayName, function()
				if not current then
					self:Action({ Action = "Form", Form = formId })
				end
			end, {
				Size = UDim2.fromOffset(124, 46),
				LayoutOrder = 10 + index,
				TextSize = Theme.TextSize.Small,
				Parent = self.Actions,
			}, current and "Primary" or "Ghost")
		end
	end
end

function InventoryUI:Open(args)
	ScreenBase.Show(self.Root)
	local profile = ClientState.Profile
	if args and type(args.WeaponId) == "string" and WeaponConfig.Weapons[args.WeaponId] then
		self.Selected = args.WeaponId
	elseif profile then
		self.Selected = profile.Loadout.Weapon
	end
	self:Refresh(true)
end

function InventoryUI:Close()
	ScreenBase.Hide(self.Root)
	-- Free the viewports while closed.
	ScreenBase.ClearChildren(self.Grid)
	ScreenBase.ClearChildren(self.Detail)
	self.Preview = nil
end

return InventoryUI
