--[[
	StudentCreator — "Create Your Student"
	Fixes the usual creator failure modes:
	  * cannot be dismissed (or skipped by respawning) until the student exists
	  * every field validated locally *and* on the server (name length/characters, server-side
	    TextService filtering); errors are shown inline next to the form, never silently ignored
	  * one in-flight request at a time (no double submits), retried safely on network errors
	  * works with mouse, touch (scrolling form) and gamepad (all options are selectable buttons)
	  * live 3D preview of skin, hair, uniform
	After creation it can be reopened from Settings to change appearance (name, role and starter
	weapon are locked; role can be changed in Skills).
]]

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local CombatRoleConfig = require(Modules.Config.CombatRoleConfig)
local Net = require(Modules.Core.Net)
local StudentConfig = require(Modules.Config.StudentConfig)
local WeaponConfig = require(Modules.WeaponConfig)

local UI = script.Parent.Parent
local ClientState = require(UI.Parent.Controllers.ClientState)
local Components = require(UI.Components)
local Theme = require(UI.Theme)
local UIController = require(UI.UIController)
local Viewport = require(UI.Viewport)

local StudentCreator = {}
StudentCreator.__index = StudentCreator

local REASON_TEXT = {
	NameLength = string.format(
		"Name must be %d–%d characters.",
		StudentConfig.NameMinLength,
		StudentConfig.NameMaxLength
	),
	NameCharacters = "Name must start with a letter and use letters, numbers, spaces, - or _.",
	NameNotAllowed = "That name isn't allowed. Please choose another.",
	FilterUnavailable = "Name check is unavailable right now. Try again in a moment.",
	BadName = "Please enter a name.",
	BadRole = "Choose a combat role.",
	BadWeapon = "Choose a starter weapon.",
	BadWavelength = "Choose a soul wavelength.",
	Loading = "Your profile is still loading…",
	RateLimited = "Slow down a little and try again.",
	ServerError = "Something went wrong. Please try again.",
}

function StudentCreator.new(layer: Frame)
	local self = setmetatable({}, StudentCreator)
	self.Choice = {
		Name = "",
		SkinTone = 2,
		HairColor = 1,
		HairStyle = 2,
		Uniform = 2,
		Wavelength = "Calm",
		Role = "Meister",
		Weapon = "MakaScythe",
	}
	self.Submitting = false
	self.EditMode = false
	self.BlocksInput = true
	self.Closable = false

	local root = Components.New("Frame", {
		Name = "StudentCreator",
		BackgroundColor3 = Theme.Colors.Overlay,
		BackgroundTransparency = 0.05,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = layer,
	})
	Components.Gradient(Color3.fromRGB(40, 24, 54), Color3.fromRGB(10, 8, 14)).Parent = root
	self.Root = root

	Components.Title("CREATE YOUR STUDENT", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 18),
		Size = UDim2.fromOffset(600, 50),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = Theme.TextSize.Hero,
		Parent = root,
	})
	Components.Label("Death Weapon Meister Academy — enrollment form", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 66),
		Size = UDim2.fromOffset(600, 24),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Theme.Colors.TextDim,
		Parent = root,
	})

	-- Preview (left).
	local previewPanel = Components.Panel({
		Position = UDim2.fromOffset(32, 104),
		Size = UDim2.new(0.38, -40, 1, -136),
		Parent = root,
	})
	self.PreviewPanel = previewPanel

	-- Form (right, scrolls on small screens).
	local formPanel = Components.Panel({
		Position = UDim2.new(0.38, 8, 0, 104),
		Size = UDim2.new(0.62, -40, 1, -136),
		Parent = root,
	})
	local scroll =
		Components.Scroll({ Position = UDim2.fromOffset(16, 12), Size = UDim2.new(1, -24, 1, -92), Parent = formPanel })
	Components.List(Enum.FillDirection.Vertical, 14).Parent = scroll
	Components.Padding(4).Parent = scroll
	self.Form = scroll

	local order = 0
	local function section(title: string, hint: string?)
		order += 1
		local box = Components.New("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -10, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = order,
			Parent = scroll,
		})
		Components.List(Enum.FillDirection.Vertical, 6).Parent = box
		Components.Label(title, {
			Size = UDim2.new(1, 0, 0, 24),
			FontFace = Theme.Fonts.Hand,
			TextSize = 20,
			TextColor3 = Theme.Colors.Gold,
			LayoutOrder = 0,
			Parent = box,
		})
		if hint then
			Components.Label(hint, {
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				TextColor3 = Theme.Colors.TextMuted,
				TextSize = Theme.TextSize.Small,
				LayoutOrder = 1,
				Parent = box,
			})
		end
		local row = Components.New("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 2,
			Parent = box,
		})
		local grid = Instance.new("UIGridLayout")
		grid.CellPadding = UDim2.fromOffset(8, 8)
		grid.CellSize = UDim2.fromOffset(150, 44)
		grid.SortOrder = Enum.SortOrder.LayoutOrder
		grid.Parent = row
		return box, row, grid
	end

	-- Name.
	local nameBox, _, nameGrid = section(
		"Student Name",
		string.format(
			"%d–%d characters. Names are filtered for everyone's safety.",
			StudentConfig.NameMinLength,
			StudentConfig.NameMaxLength
		)
	)
	nameGrid:Destroy()
	local input = Components.New("TextBox", {
		Size = UDim2.new(1, 0, 0, 46),
		BackgroundColor3 = Theme.Colors.InkLight,
		Text = "",
		PlaceholderText = "Enter your student's name",
		PlaceholderColor3 = Theme.Colors.TextMuted,
		TextColor3 = Theme.Colors.Text,
		FontFace = Theme.Fonts.BodyBold,
		TextSize = Theme.TextSize.Large,
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 3,
		Parent = nameBox,
	})
	Components.Corner(Theme.CornerSmall).Parent = input
	Components.Stroke().Parent = input
	Components.Padding(8, 12).Parent = input
	input:GetPropertyChangedSignal("Text"):Connect(function()
		if #input.Text > StudentConfig.NameMaxLength then
			input.Text = string.sub(input.Text, 1, StudentConfig.NameMaxLength)
		end
		self.Choice.Name = input.Text
		self:Validate()
	end)
	self.NameInput = input

	-- Swatch helper: selectable buttons that highlight the current choice.
	self.Groups = {}
	local function options(
		key: string,
		row: Frame,
		entries: { { Value: any, Text: string, Color: Color3? } },
		onChange: (() -> ())?
	)
		local buttons = {}
		for index, entry in entries do
			local button = Components.Button(entry.Text, function()
				self.Choice[key] = entry.Value
				self:HighlightGroup(key)
				if onChange then
					onChange()
				end
				self:Validate()
			end, { LayoutOrder = index, TextSize = Theme.TextSize.Small, Parent = row }, "Ghost")
			if entry.Color then
				local swatch = Components.New("Frame", {
					BackgroundColor3 = entry.Color,
					Size = UDim2.fromOffset(18, 18),
					Position = UDim2.new(0, 10, 0.5, -9),
					Parent = button,
				})
				Components.Corner(UDim.new(1, 0)).Parent = swatch
				button.TextXAlignment = Enum.TextXAlignment.Left
				Components.Padding(0, 0).Parent = button
				local pad = button:FindFirstChildOfClass("UIPadding") :: UIPadding
				pad.PaddingLeft = UDim.new(0, 36)
			end
			buttons[entry.Value] = button
		end
		self.Groups[key] = buttons
		self:HighlightGroup(key)
	end
	local refresh = function()
		self:RefreshPreview()
	end

	local _, skinRow = section("Skin Tone")
	local skins = {}
	for i, color in StudentConfig.SkinTones do
		table.insert(skins, { Value = i, Text = "Tone " .. i, Color = color })
	end
	options("SkinTone", skinRow, skins, refresh)

	local _, hairColorRow = section("Hair Color")
	local hairColors = {}
	for i, hair in StudentConfig.HairColors do
		table.insert(hairColors, { Value = i, Text = hair.Name, Color = hair.Color })
	end
	options("HairColor", hairColorRow, hairColors, refresh)

	local _, hairRow = section("Hairstyle", '"Keep" uses your own avatar\'s hair.')
	local styles = {}
	for i, style in StudentConfig.HairStyles do
		table.insert(styles, { Value = i, Text = style })
	end
	options("HairStyle", hairRow, styles, refresh)

	local _, uniformRow = section("Uniform", '"My Avatar Outfit" keeps your Roblox clothing.')
	local uniforms = {}
	for i, uniform in StudentConfig.Uniforms do
		table.insert(uniforms, { Value = i, Text = uniform.Name, Color = uniform.Primary })
	end
	options("Uniform", uniformRow, uniforms, refresh)

	local _, waveRow, waveGrid =
		section("Soul Wavelength", "Affects how well you synchronize with a partner (Meister ⇄ Demon Weapon).")
	waveGrid.CellSize = UDim2.fromOffset(200, 44)
	local waves = {}
	for _, wave in StudentConfig.Wavelengths do
		table.insert(waves, { Value = wave.Id, Text = wave.Id .. " — " .. wave.Description })
	end
	options("Wavelength", waveRow, waves)

	local roleBox, roleRow, roleGrid = section(
		"Combat Role",
		"How you fight — not what you are. Your origin (race) is rolled later at the Soul Altar."
	)
	roleGrid.CellSize = UDim2.fromOffset(200, 44)
	local roles = {}
	for _, roleId in { "Meister", "Assassin", "Technician" } do
		table.insert(roles, { Value = roleId, Text = CombatRoleConfig.ById[roleId].DisplayName })
	end
	options("Role", roleRow, roles, function()
		self:RefreshRoleText()
	end)
	self.RoleText = Components.Label("", {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextColor3 = Theme.Colors.TextDim,
		TextSize = Theme.TextSize.Small,
		LayoutOrder = 4,
		Parent = roleBox,
	})
	self.RoleSection = roleBox

	local weaponBox, weaponRow, weaponGrid = section("Starter Weapon", "Other weapons unlock as you level up.")
	weaponGrid.CellSize = UDim2.fromOffset(220, 44)
	local weapons = {}
	for _, weaponId in StudentConfig.StarterWeapons do
		table.insert(weapons, { Value = weaponId, Text = WeaponConfig.Weapons[weaponId].DisplayName })
	end
	options("Weapon", weaponRow, weapons)
	self.WeaponSection = weaponBox

	-- Footer: error text + submit.
	self.Error = Components.Label("", {
		Position = UDim2.new(0, 16, 1, -74),
		Size = UDim2.new(1, -230, 0, 60),
		TextColor3 = Theme.Colors.Bad,
		FontFace = Theme.Fonts.BodyBold,
		TextSize = Theme.TextSize.Body,
		Parent = formPanel,
	})
	self.Submit = Components.Button("Enroll at the DWMA", function()
		self:SubmitForm()
	end, {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -16),
		Size = UDim2.fromOffset(200, 52),
		TextSize = Theme.TextSize.Large,
		Parent = formPanel,
	}, "Primary")
	self.Cancel = Components.Button("Close", function()
		UIController.CloseSelf("StudentCreator")
	end, {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -226, 1, -16),
		Size = UDim2.fromOffset(120, 52),
		Visible = false,
		Parent = formPanel,
	}, "Secondary")

	self:RefreshRoleText()
	return self
end

function StudentCreator:HighlightGroup(key: string)
	for value, button in self.Groups[key] or {} do
		local selected = self.Choice[key] == value
		button.BackgroundColor3 = selected and Theme.Colors.Gold or Theme.Colors.InkLight
		button.TextColor3 = selected and Theme.Colors.Ink or Theme.Colors.Text
	end
end

function StudentCreator:RefreshRoleText()
	local role = CombatRoleConfig.ById[self.Choice.Role]
	if role and self.RoleText then
		self.RoleText.Text = role.Description .. "\n" .. role.Lore
	end
end

function StudentCreator:RefreshPreview()
	if self.Preview then
		self.Preview:Destroy()
	end
	self.Preview = Viewport.Character(self.PreviewPanel, { Student = self.Choice, Spin = true, Framing = "Full" })
end

-- Local validation mirrors the server rules (server still re-checks everything).
function StudentCreator:Validate(): boolean
	local message = ""
	if not self.EditMode then
		local name = string.gsub(string.gsub(self.Choice.Name, "^%s+", ""), "%s+$", "")
		if #name < StudentConfig.NameMinLength or #name > StudentConfig.NameMaxLength then
			message = #name == 0 and "" or REASON_TEXT.NameLength
		elseif not string.match(name, StudentConfig.NamePattern) then
			message = REASON_TEXT.NameCharacters
		end
	end
	self.Error.Text = message
	local valid = message == "" and (self.EditMode or #self.Choice.Name >= StudentConfig.NameMinLength)
	self.Submit.AutoButtonColor = false
	self.Submit.BackgroundTransparency = valid and 0 or 0.5
	return valid
end

function StudentCreator:SubmitForm()
	if self.Submitting or not self:Validate() then
		return
	end
	self.Submitting = true
	self.Submit.Text = "Enrolling…"
	local remote = Net.Function("CreateStudent")
	local result
	for attempt = 1, 3 do
		local ok, response = pcall(function()
			return remote:InvokeServer(self.Choice)
		end)
		if ok then
			result = response
			break
		end
		task.wait(0.5 * attempt)
	end
	self.Submitting = false
	self.Submit.Text = self.EditMode and "Save Appearance" or "Enroll at the DWMA"
	if type(result) ~= "table" then
		self.Error.Text = REASON_TEXT.ServerError
		return
	end
	if not result.Ok then
		self.Error.Text = REASON_TEXT[result.Reason] or ("Couldn't save: " .. tostring(result.Reason))
		return
	end
	-- The replicated profile can arrive a moment later; the server already confirmed creation.
	self.Enrolled = true
	self.Closable = true
	UIController.CloseSelf("StudentCreator")
end

function StudentCreator:Open(_args)
	local profile = ClientState.Profile
	self.EditMode = profile ~= nil and (profile.Student.Created == true or self.Enrolled == true)
	self.Closable = self.EditMode
	if self.EditMode then
		for key in self.Choice do
			if profile.Student[key] ~= nil then
				self.Choice[key] = profile.Student[key]
			end
		end
		self.Choice.Role = profile.Loadout.Role
		self.Choice.Weapon = profile.Loadout.Weapon
		self.NameInput.Text = profile.Student.Name
	end
	self.NameInput.TextEditable = not self.EditMode
	self.RoleSection.Visible = not self.EditMode
	self.WeaponSection.Visible = not self.EditMode
	self.Cancel.Visible = self.EditMode
	self.Submit.Text = self.EditMode and "Save Appearance" or "Enroll at the DWMA"
	for key in self.Groups do
		self:HighlightGroup(key)
	end
	self:RefreshRoleText()
	self:RefreshPreview()
	self:Validate()
	self.Root.Visible = true
	if self.OnVisibility then
		self.OnVisibility(true)
	end
end

function StudentCreator:Close()
	local profile = ClientState.Profile
	if not (self.Enrolled or (profile and profile.Student.Created)) then
		return -- cannot leave before enrolling
	end
	self.Root.Visible = false
	if self.Preview then
		self.Preview:Destroy()
		self.Preview = nil
	end
	if self.OnVisibility then
		self.OnVisibility(false)
	end
	if self.OnClosed then
		self.OnClosed()
	end
end

return StudentCreator
