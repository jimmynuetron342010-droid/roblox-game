--[[
	SettingsUI
	Accessibility and comfort options saved to the profile (validated server-side by
	LoadoutService.CleanSettings): reduced motion, camera shake, damage numbers, fast reveal (after
	the first full reveal), VFX quality, UI scale. Also: edit the student's appearance, and the full
	controls list for keyboard, gamepad and touch.
]]

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local Net = require(Modules.Core.Net)

local UI = script.Parent.Parent
local ClientState = require(UI.Parent.Controllers.ClientState)
local Components = require(UI.Components)
local Notifications = require(UI.Notifications)
local ScreenBase = require(UI.ScreenBase)
local Theme = require(UI.Theme)
local UIController = require(UI.UIController)

local SettingsUI = {}
SettingsUI.__index = SettingsUI

local QUALITY = { "Auto", "Low", "Medium", "High" }
local SCALE_MIN, SCALE_MAX, SCALE_STEP = 0.75, 1.4, 0.05

local CONTROLS = {
	{ "Attack / combo", "Left Mouse", "R2", "Attack button" },
	{ "Weapon techniques", "Z, X", "L1, R1", "Z, X buttons" },
	{ "Racial ability", "C", "Y", "C button" },
	{ "Role technique", "V", "B", "V button" },
	{ "Kishin Awakening", "B", "D-Pad Up", "B button" },
	{ "Dash", "Q", "L2", "Dash button" },
	{ "Sprint", "Shift (hold)", "L3 (toggle)", "Sprint button" },
	{ "Soul Perception", "G", "D-Pad Down", "Eye button" },
	{ "Draw / holster", "E", "D-Pad Left", "Draw button" },
	{ "Switch Tsubaki form", "T", "D-Pad Right", "Form button" },
	{ "Menu", "M", "Select / View", "Menu buttons" },
	{ "Close menu", "Esc", "B", "✕" },
}

function SettingsUI.new(layer: Frame)
	local self = setmetatable({}, SettingsUI)
	self.BlocksInput = true
	local root, content =
		ScreenBase.Modal("Settings", "SETTINGS", layer, UDim2.fromScale(0.8, 0.88), Vector2.new(980, 680))
	self.Root = root
	self.Body = Components.Scroll({ Size = UDim2.fromScale(1, 1), Parent = content })
	Components.List(Enum.FillDirection.Vertical, 8).Parent = self.Body
	Components.Padding(4).Parent = self.Body
	self.Pending = {}
	-- Values shown before the server echoes them back (the profile itself is never edited locally).
	self.Optimistic = {}
	ClientState.ProfileChanged:Connect(function()
		if next(self.Pending) == nil and not self.Saving then
			self.Optimistic = {}
			if root.Visible then
				self:Refresh()
			end
		end
	end)
	return self
end

-- Batches rapid changes into one validated request.
function SettingsUI:Get(key: string): any
	if self.Optimistic[key] ~= nil then
		return self.Optimistic[key]
	end
	return ClientState.Profile.Settings[key]
end

function SettingsUI:Save(key: string, value: any)
	self.Optimistic[key] = value
	self.Pending[key] = value
	if self.Saving then
		return
	end
	self.Saving = true
	task.delay(0.25, function()
		local batch = self.Pending
		self.Pending = {}
		local ok, result = pcall(function()
			return Net.Function("UpdateSettings"):InvokeServer(batch)
		end)
		self.Saving = false
		if not ok or type(result) ~= "table" or not result.Ok then
			Notifications.Show("Couldn't save settings — try again.", "Warning")
		end
		if next(self.Pending) ~= nil then
			local again = self.Pending
			self.Pending = {}
			for k, v in again do
				self:Save(k, v)
			end
		end
	end)
end

local order = 0
local function nextOrder()
	order += 1
	return order
end

function SettingsUI:Heading(text: string)
	Components.Label(text, {
		Size = UDim2.new(1, -12, 0, 30),
		FontFace = Theme.Fonts.Hand,
		TextSize = 21,
		TextColor3 = Theme.Colors.Gold,
		LayoutOrder = nextOrder(),
		Parent = self.Body,
	})
end

function SettingsUI:Row(title: string, description: string?)
	local row = Components.Panel({
		Size = UDim2.new(1, -12, 0, 62),
		BackgroundColor3 = Theme.Colors.InkLight,
		LayoutOrder = nextOrder(),
		Parent = self.Body,
	})
	Components.Label(title, {
		Position = UDim2.fromOffset(16, 8),
		Size = UDim2.new(1, -300, 0, 22),
		FontFace = Theme.Fonts.BodyBold,
		Parent = row,
	})
	if description then
		Components.Label(description, {
			Position = UDim2.fromOffset(16, 30),
			Size = UDim2.new(1, -300, 0, 26),
			TextSize = 13,
			TextColor3 = Theme.Colors.TextMuted,
			Parent = row,
		})
	end
	local controls = Components.New("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(280, 42),
		Parent = row,
	})
	local list = Components.List(Enum.FillDirection.Horizontal, 6)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Right
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Parent = controls
	return controls
end

function SettingsUI:Toggle(key: string, title: string, description: string?, enabled: boolean?)
	local controls = self:Row(title, description)
	local value = self:Get(key) == true
	local button = Components.Button(
		"",
		nil,
		{ Size = UDim2.fromOffset(110, 40), Parent = controls },
		value and "Primary" or "Ghost"
	)
	local function paint()
		button.Text = value and "ON" or "OFF"
		button.BackgroundColor3 = value and Theme.Colors.Gold or Theme.Colors.InkLighter
		button.TextColor3 = value and Theme.Colors.Ink or Theme.Colors.Text
	end
	paint()
	if enabled == false then
		button.Text = "Locked"
		button.BackgroundTransparency = 0.5
		button.Active = false
		return
	end
	button.Activated:Connect(function()
		value = not value
		paint()
		self:Save(key, value)
	end)
end

function SettingsUI:Refresh()
	local profile = ClientState.Profile
	if not profile then
		return
	end
	local settings = profile.Settings
	ScreenBase.ClearChildren(self.Body)
	order = 0

	self:Heading("Accessibility & comfort")
	local systemReduced = ClientState.SystemReducedMotion()
	self:Toggle(
		"ReducedMotion",
		"Reduced motion",
		systemReduced and "Also on because your device asks for reduced motion."
			or "Removes screen shake, flashes, UI pulsing and turntables."
	)
	self:Toggle("CameraShake", "Camera shake", "Impact shake on heavy hits.")
	self:Toggle("DamageNumbers", "Damage numbers", "Floating numbers on hits.")
	self:Toggle(
		"FastReveal",
		"Fast race reveal",
		settings.SeenRollAnimation and "Shortens the Soul Altar reveal." or "Unlocks after you watch one full reveal.",
		settings.SeenRollAnimation == true
	)

	self:Heading("Graphics & interface")
	local qualityRow = self:Row("Effects quality", "Auto adapts to your device. Low is best for older phones.")
	for _, quality in QUALITY do
		local current = (self:Get("VFXQuality") or "Auto") == quality
		Components.Button(quality, function()
			self:Save("VFXQuality", quality)
			self:Refresh()
		end, { Size = UDim2.fromOffset(64, 40), TextSize = 13, Parent = qualityRow }, current and "Primary" or "Ghost")
	end
	local scaleRow = self:Row("Interface size", "Scales every menu and the HUD.")
	local scaleValue = self:Get("UIScale") or 1
	local label
	local function setScale(delta: number)
		scaleValue = math.clamp(math.floor((scaleValue + delta) / SCALE_STEP + 0.5) * SCALE_STEP, SCALE_MIN, SCALE_MAX)
		label.Text = string.format("%d%%", math.floor(scaleValue * 100 + 0.5))
		self:Save("UIScale", scaleValue)
	end
	Components.Button("−", function()
		setScale(-SCALE_STEP)
	end, { Size = UDim2.fromOffset(44, 40), TextSize = 22, LayoutOrder = 1, Parent = scaleRow }, "Ghost")
	label = Components.Label(string.format("%d%%", math.floor(scaleValue * 100 + 0.5)), {
		Size = UDim2.fromOffset(70, 40),
		TextXAlignment = Enum.TextXAlignment.Center,
		FontFace = Theme.Fonts.BodyBold,
		LayoutOrder = 2,
		Parent = scaleRow,
	})
	Components.Button("+", function()
		setScale(SCALE_STEP)
	end, { Size = UDim2.fromOffset(44, 40), TextSize = 22, LayoutOrder = 3, Parent = scaleRow }, "Ghost")

	self:Heading("Student")
	local studentRow =
		self:Row("Appearance", string.format("%s — change skin, hair, uniform and wavelength.", profile.Student.Name))
	Components.Button("Edit student", function()
		UIController.Open("StudentCreator")
	end, { Size = UDim2.fromOffset(150, 40), Parent = studentRow }, "Secondary")

	self:Heading("Controls")
	local header = Components.Panel({
		Size = UDim2.new(1, -12, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Colors.InkLight,
		LayoutOrder = nextOrder(),
		Parent = self.Body,
	})
	Components.Padding(10, 16).Parent = header
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0.25, -6, 0, 26)
	grid.CellPadding = UDim2.fromOffset(6, 2)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = header
	local index = 0
	local function cell(text: string, bold: boolean?, color: Color3?)
		index += 1
		Components.Label(text, {
			LayoutOrder = index,
			TextSize = 13,
			FontFace = bold and Theme.Fonts.BodyBold or Theme.Fonts.Body,
			TextColor3 = color or Theme.Colors.TextDim,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = header,
		})
	end
	for _, title in { "Action", "Keyboard & mouse", "Gamepad", "Touch" } do
		cell(title, true, Theme.Colors.Gold)
	end
	for _, row in CONTROLS do
		cell(row[1], true, Theme.Colors.Text)
		cell(row[2])
		cell(row[3])
		cell(row[4])
	end
end

function SettingsUI:Open(_args)
	ScreenBase.Show(self.Root)
	self:Refresh()
end

function SettingsUI:Close()
	ScreenBase.Hide(self.Root)
end

return SettingsUI
