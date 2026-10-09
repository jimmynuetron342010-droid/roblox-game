--[[
	Components
	Small UI factory used by every screen so panels, buttons and bars look consistent:
	rounded ink panels with a soft gradient and stroke, buttons with hover/press feedback and
	gamepad selection, animated bars, modal windows with titles, tabs and scrolling lists.
]]

local Theme = require(script.Parent.Theme)

local Components = {}

export type Props = { [string]: any }

local function apply(instance: Instance, props: Props?)
	for key, value in (props or {}) :: Props do
		if key ~= "Children" then
			(instance :: any)[key] = value
		end
	end
	for _, child in (props and props.Children or {}) :: { Instance } do
		child.Parent = instance
	end
	return instance
end

function Components.New(className: string, props: Props?): any
	return apply(Instance.new(className), props)
end

function Components.Corner(radius: UDim?): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius or Theme.Corner
	return corner
end

function Components.Stroke(color: Color3?, thickness: number?, transparency: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Theme.Colors.Stroke
	stroke.Thickness = thickness or 1.5
	stroke.Transparency = transparency or 0.2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	return stroke
end

function Components.Padding(all: number, horizontal: number?): UIPadding
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, all)
	padding.PaddingBottom = UDim.new(0, all)
	padding.PaddingLeft = UDim.new(0, horizontal or all)
	padding.PaddingRight = UDim.new(0, horizontal or all)
	return padding
end

function Components.Gradient(top: Color3, bottom: Color3, rotation: number?): UIGradient
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(top, bottom)
	gradient.Rotation = rotation or 90
	return gradient
end

function Components.List(
	direction: Enum.FillDirection?,
	padding: number?,
	align: Enum.HorizontalAlignment?
): UIListLayout
	local list = Instance.new("UIListLayout")
	list.FillDirection = direction or Enum.FillDirection.Vertical
	list.Padding = UDim.new(0, padding or 8)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.HorizontalAlignment = align or Enum.HorizontalAlignment.Left
	return list
end

-- Rounded ink panel with gradient + stroke.
function Components.Panel(props: Props?): Frame
	local frame = Components.New("Frame", {
		BackgroundColor3 = Theme.Colors.Ink,
		BackgroundTransparency = 0.06,
		BorderSizePixel = 0,
	})
	Components.Corner().Parent = frame
	Components.Stroke().Parent = frame
	Components.Gradient(Color3.fromRGB(255, 255, 255), Color3.fromRGB(205, 198, 215)).Parent = frame
	return apply(frame, props) :: Frame
end

function Components.Label(text: string, props: Props?): TextLabel
	local label = Components.New("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = Theme.Colors.Text,
		FontFace = Theme.Fonts.Body,
		TextSize = Theme.TextSize.Body,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.None,
	})
	return apply(label, props) :: TextLabel
end

function Components.Title(text: string, props: Props?): TextLabel
	local label = Components.Label(text, {
		FontFace = Theme.Fonts.Display,
		TextSize = Theme.TextSize.Title,
		TextColor3 = Theme.Colors.Gold,
	})
	return apply(label, props) :: TextLabel
end

-- Button with hover/press feedback. `style`: "Primary" | "Secondary" | "Danger" | "Ghost"
function Components.Button(text: string, onClick: (() -> ())?, props: Props?, style: string?): TextButton
	local s = style or "Secondary"
	local base = ({
		Primary = Theme.Colors.Gold,
		Secondary = Theme.Colors.InkLighter,
		Danger = Theme.Colors.Red,
		Ghost = Theme.Colors.InkLight,
	})[s] or Theme.Colors.InkLighter
	local textColor = s == "Primary" and Theme.Colors.Ink or Theme.Colors.Text
	local button = Components.New("TextButton", {
		BackgroundColor3 = base,
		AutoButtonColor = false,
		Text = text,
		TextColor3 = textColor,
		FontFace = Theme.Fonts.BodyBold,
		TextSize = Theme.TextSize.Body,
		Size = UDim2.fromOffset(160, 44),
		BorderSizePixel = 0,
		Selectable = true,
	})
	Components.Corner(Theme.CornerSmall).Parent = button
	local stroke = Components.Stroke(s == "Primary" and Color3.fromRGB(255, 236, 170) or Theme.Colors.Stroke, 1.5, 0.15)
	stroke.Parent = button
	local scale = Instance.new("UIScale")
	scale.Parent = button
	local hoverColor = base:Lerp(Color3.new(1, 1, 1), 0.12)
	local function hover(on: boolean)
		Theme.Tween(button, 0.12, { BackgroundColor3 = on and hoverColor or base })
		Theme.Tween(stroke, 0.12, {
			Color = on and Theme.Colors.Gold
				or (s == "Primary" and Color3.fromRGB(255, 236, 170) or Theme.Colors.Stroke),
		})
	end
	button.MouseEnter:Connect(function()
		hover(true)
	end)
	button.MouseLeave:Connect(function()
		hover(false)
	end)
	button.SelectionGained:Connect(function()
		hover(true)
	end)
	button.SelectionLost:Connect(function()
		hover(false)
	end)
	button.MouseButton1Down:Connect(function()
		Theme.Tween(scale, 0.06, { Scale = 0.96 })
	end)
	button.MouseButton1Up:Connect(function()
		Theme.Tween(scale, 0.1, { Scale = 1 })
	end)
	if onClick then
		button.Activated:Connect(onClick)
	end
	return apply(button, props) :: TextButton
end

-- Horizontal bar: returns (container, setFill(fraction), setText(text)).
function Components.Bar(color: Color3, props: Props?, trailColor: Color3?)
	local container = Components.New("Frame", {
		BackgroundColor3 = Color3.fromRGB(10, 8, 14),
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Size = UDim2.new(1, 0, 0, 18),
	})
	Components.Corner(UDim.new(0, 5)).Parent = container
	Components.Stroke(Color3.fromRGB(0, 0, 0), 1.5, 0.3).Parent = container
	local trail = Components.New("Frame", {
		Name = "Trail",
		BackgroundColor3 = trailColor or Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = container,
	})
	Components.Corner(UDim.new(0, 5)).Parent = trail
	local fill = Components.New("Frame", {
		Name = "Fill",
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = container,
	})
	Components.Corner(UDim.new(0, 5)).Parent = fill
	Components.Gradient(color:Lerp(Color3.new(1, 1, 1), 0.25), color:Lerp(Color3.new(0, 0, 0), 0.2)).Parent = fill
	local label = Components.Label("", {
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = Theme.TextSize.Small,
		FontFace = Theme.Fonts.BodyBold,
		TextStrokeTransparency = 0.4,
		ZIndex = 3,
		Parent = container,
	})
	local current = 1
	local function setFill(fraction: number)
		fraction = math.clamp(fraction, 0, 1)
		fill.Size = UDim2.fromScale(fraction, 1)
		if fraction < current then
			-- Delayed "damage trail" catches up after a moment.
			task.delay(0.25, function()
				Theme.Tween(trail, 0.35, { Size = UDim2.fromScale(fraction, 1) })
			end)
		else
			trail.Size = UDim2.fromScale(fraction, 1)
		end
		current = fraction
	end
	local function setText(text: string)
		label.Text = text
	end
	apply(container, props)
	return container, setFill, setText
end

-- Modal window with title bar and close button. Returns (root, content, close).
function Components.Modal(title: string, size: UDim2, onClose: (() -> ())?)
	local root = Components.Panel({
		Name = "Modal_" .. title,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = size,
		Visible = false,
	})
	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = Vector2.new(320, 260)
	constraint.Parent = root
	local header = Components.New("Frame", {
		Name = "Header",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 52),
		Parent = root,
	})
	Components.Title(title, {
		Position = UDim2.fromOffset(20, 6),
		Size = UDim2.new(1, -90, 1, -8),
		Parent = header,
	})
	local close = Components.Button("✕", onClose, {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 8),
		Size = UDim2.fromOffset(40, 40),
		Parent = header,
	}, "Ghost")
	close.AccessibilityDescription = "Close"
	Components.New("Frame", {
		Name = "Divider",
		BackgroundColor3 = Theme.Colors.Gold,
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(20, 52),
		Size = UDim2.new(1, -40, 0, 2),
		Parent = root,
	})
	local content = Components.New("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 64),
		Size = UDim2.new(1, -32, 1, -80),
		Parent = root,
	})
	return root, content, close
end

function Components.Scroll(props: Props?): ScrollingFrame
	local scroll = Components.New("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.Colors.Stroke,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Selectable = false,
	})
	return apply(scroll, props) :: ScrollingFrame
end

-- Tab strip. tabs = { {Id, Text} }. Returns (frame, select(id)).
function Components.Tabs(tabs: { { Id: string, Text: string } }, onSelect: (string) -> (), props: Props?)
	local frame = Components.New("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 40),
	})
	Components.List(Enum.FillDirection.Horizontal, 8).Parent = frame
	local buttons = {}
	local function selectTab(id: string)
		for tabId, button in buttons do
			local on = tabId == id
			button.BackgroundColor3 = on and Theme.Colors.Gold or Theme.Colors.InkLight
			button.TextColor3 = on and Theme.Colors.Ink or Theme.Colors.TextDim
		end
		onSelect(id)
	end
	for index, tab in tabs do
		local button = Components.Button(tab.Text, function()
			selectTab(tab.Id)
		end, {
			LayoutOrder = index,
			Size = UDim2.fromOffset(120, 36),
			TextSize = Theme.TextSize.Small,
		}, "Ghost")
		button.Parent = frame
		buttons[tab.Id] = button
	end
	apply(frame, props)
	return frame, selectTab
end

-- Animated rarity border (rotating gradient), static when reduced motion is on.
function Components.RarityBorder(parent: GuiObject, color: Color3, accent: Color3, animated: boolean)
	local stroke = Components.Stroke(color, 3, 0)
	stroke.Name = "RarityBorder"
	stroke.Parent = parent
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, color),
		ColorSequenceKeypoint.new(0.5, accent:Lerp(Color3.new(1, 1, 1), 0.3)),
		ColorSequenceKeypoint.new(1, color),
	})
	gradient.Parent = stroke
	if animated and not Theme.ReducedMotion() then
		task.spawn(function()
			while stroke.Parent do
				gradient.Rotation = (gradient.Rotation + 3) % 360
				task.wait(1 / 30)
			end
		end)
	end
	return stroke
end

return Components
