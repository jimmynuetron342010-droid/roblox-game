--[[
	Icons
	Every icon is drawn from UI primitives (circles, bars, clipped rotated squares), so the HUD
	matches the art direction without uploading images: the grinning moon portrait, the Z/X/C/V
	ability glyphs (slashes, swirl, grin, skull) and one emblem per race.
	Swap any icon for an ImageLabel later if you upload artwork.
]]

local Theme = require(script.Parent.Theme)

local Icons = {}

local function frame(props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundTransparency = 1
	for key, value in props do
		(f :: any)[key] = value
	end
	return f
end

local function circle(parent: Instance, center: UDim2, size: UDim2, color: Color3, z: number?): Frame
	local f = frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = center,
		Size = size,
		BackgroundColor3 = color,
		BackgroundTransparency = 0,
		ZIndex = z or 2,
		Parent = parent,
	})
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = f
	return f
end

local function bar(
	parent: Instance,
	center: UDim2,
	size: UDim2,
	rotation: number,
	color: Color3,
	z: number?,
	round: boolean?
): Frame
	local f = frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = center,
		Size = size,
		Rotation = rotation,
		BackgroundColor3 = color,
		BackgroundTransparency = 0,
		ZIndex = z or 3,
		Parent = parent,
	})
	if round ~= false then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = f
	end
	return f
end

-- Upward triangle: a rotated square clipped by its parent's lower half.
local function triangle(
	parent: Instance,
	center: UDim2,
	size: UDim2,
	color: Color3,
	rotation: number?,
	z: number?
): Frame
	local clip = frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = center,
		Size = size,
		ClipsDescendants = true,
		Rotation = rotation or 0,
		ZIndex = z or 3,
		Parent = parent,
	})
	frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromScale(0.72, 0.72),
		SizeConstraint = Enum.SizeConstraint.RelativeXX,
		Rotation = 45,
		BackgroundColor3 = color,
		BackgroundTransparency = 0,
		ZIndex = z or 3,
		Parent = clip,
	})
	return clip
end

local function container(size: UDim2?): Frame
	local f = frame({ Size = size or UDim2.fromScale(1, 1), Name = "Icon" })
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = f
	return f
end

-- Grinning crescent moon (portrait, like the reference HUD).
function Icons.MoonFace(size: UDim2?, background: Color3?): Frame
	local root = container(size)
	local bg = background or Theme.Colors.Ink
	circle(root, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.92, 0.92), Theme.Colors.Moon, 2)
	-- Crescent bite.
	circle(root, UDim2.fromScale(0.78, 0.36), UDim2.fromScale(0.66, 0.66), bg, 3)
	-- Eye.
	local eye = circle(root, UDim2.fromScale(0.3, 0.36), UDim2.fromScale(0.2, 0.15), Theme.Colors.Ink, 4)
	circle(eye, UDim2.fromScale(0.6, 0.5), UDim2.fromScale(0.4, 0.6), Theme.Colors.Red, 5)
	-- Grin: dark mouth with teeth.
	local mouth = bar(root, UDim2.fromScale(0.44, 0.68), UDim2.fromScale(0.62, 0.17), -12, Theme.Colors.RedDark, 4)
	for i = 0, 5 do
		frame({
			Position = UDim2.fromScale(0.08 + i * 0.145, 0.08),
			Size = UDim2.fromScale(0.11, 0.84),
			BackgroundColor3 = Color3.fromRGB(245, 240, 230),
			BackgroundTransparency = 0,
			ZIndex = 5,
			Parent = mouth,
		})
	end
	return root
end

-- Z: triple claw slashes.
function Icons.Slashes(color: Color3?): Frame
	local root = container()
	for i = -1, 1 do
		bar(root, UDim2.fromScale(0.5 + i * 0.18, 0.5), UDim2.fromScale(0.09, 0.78), 25, color or Theme.Colors.Text, 3)
	end
	return root
end

-- X: swirl (concentric arcs).
function Icons.Swirl(color: Color3?): Frame
	local root = container()
	for i, scale in { 0.86, 0.6, 0.34 } do
		local ring = circle(root, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(scale, scale), Theme.Colors.Ink, 2 + i)
		ring.BackgroundTransparency = 1
		local stroke = Instance.new("UIStroke")
		stroke.Color = color or Theme.Colors.Text
		stroke.Thickness = 3
		stroke.Parent = ring
		local gradient = Instance.new("UIGradient")
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.55, 0.1),
			NumberSequenceKeypoint.new(0.75, 1),
			NumberSequenceKeypoint.new(1, 1),
		})
		gradient.Rotation = i * 70
		gradient.Parent = stroke
	end
	return root
end

-- C: soul grin.
function Icons.Grin(color: Color3?): Frame
	local root = container()
	local c = color or Theme.Colors.Text
	circle(root, UDim2.fromScale(0.5, 0.55), UDim2.fromScale(0.88, 0.62), c, 2)
	circle(root, UDim2.fromScale(0.5, 0.38), UDim2.fromScale(0.95, 0.55), Theme.Colors.Ink, 3)
	for i = 0, 4 do
		bar(root, UDim2.fromScale(0.26 + i * 0.12, 0.72), UDim2.fromScale(0.035, 0.18), 0, Theme.Colors.Ink, 4, false)
	end
	circle(root, UDim2.fromScale(0.3, 0.3), UDim2.fromScale(0.16, 0.16), c, 4)
	circle(root, UDim2.fromScale(0.7, 0.3), UDim2.fromScale(0.16, 0.16), c, 4)
	return root
end

-- V: skull.
function Icons.Skull(color: Color3?): Frame
	local root = container()
	local c = color or Theme.Colors.Text
	circle(root, UDim2.fromScale(0.5, 0.42), UDim2.fromScale(0.74, 0.68), c, 2)
	local jaw = bar(root, UDim2.fromScale(0.5, 0.78), UDim2.fromScale(0.44, 0.22), 0, c, 2, false)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.25, 0)
	corner.Parent = jaw
	circle(root, UDim2.fromScale(0.36, 0.44), UDim2.fromScale(0.2, 0.22), Theme.Colors.Ink, 3)
	circle(root, UDim2.fromScale(0.64, 0.44), UDim2.fromScale(0.2, 0.22), Theme.Colors.Ink, 3)
	for i = -1, 1 do
		bar(root, UDim2.fromScale(0.5 + i * 0.1, 0.8), UDim2.fromScale(0.03, 0.16), 0, Theme.Colors.Ink, 3, false)
	end
	return root
end

-- B: Kishin eye.
function Icons.KishinEye(): Frame
	local root = container()
	circle(root, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.9, 0.5), Theme.Colors.RedDark, 2)
	circle(root, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.36, 0.36), Theme.Colors.Red, 3)
	circle(root, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.14, 0.3), Theme.Colors.Ink, 4)
	return root
end

-- Race emblems ----------------------------------------------------------------
local emblems = {}

emblems.Human = function(root, c)
	circle(root, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.62, 0.62), c, 2)
	circle(root, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.3, 0.3), Theme.Colors.Ink, 3)
end
emblems.DemonWeapon = function(root, c)
	triangle(root, UDim2.fromScale(0.5, 0.36), UDim2.fromScale(0.5, 0.52), c, 0)
	bar(root, UDim2.fromScale(0.5, 0.68), UDim2.fromScale(0.62, 0.08), 0, c)
	bar(root, UDim2.fromScale(0.5, 0.82), UDim2.fromScale(0.12, 0.22), 0, c)
end
emblems.Werewolf = function(root, c)
	triangle(root, UDim2.fromScale(0.3, 0.32), UDim2.fromScale(0.34, 0.4), c, -12)
	triangle(root, UDim2.fromScale(0.7, 0.32), UDim2.fromScale(0.34, 0.4), c, 12)
	circle(root, UDim2.fromScale(0.5, 0.62), UDim2.fromScale(0.62, 0.48), c, 2)
	circle(root, UDim2.fromScale(0.38, 0.6), UDim2.fromScale(0.1, 0.1), Theme.Colors.Gold, 3)
	circle(root, UDim2.fromScale(0.62, 0.6), UDim2.fromScale(0.1, 0.1), Theme.Colors.Gold, 3)
end
emblems.Witch = function(root, c)
	triangle(root, UDim2.fromScale(0.52, 0.36), UDim2.fromScale(0.5, 0.56), c, 8)
	bar(root, UDim2.fromScale(0.5, 0.66), UDim2.fromScale(0.82, 0.1), 0, c)
	bar(root, UDim2.fromScale(0.5, 0.6), UDim2.fromScale(0.36, 0.06), 0, Theme.Colors.Gold, 4, false)
end
emblems.Zombie = function(root, c)
	circle(root, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.7, 0.7), c, 2)
	bar(root, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.06, 0.6), 45, Theme.Colors.Ink, 3, false)
	for i = -1, 1 do
		bar(
			root,
			UDim2.fromScale(0.5 + i * 0.12, 0.5 - i * 0.12),
			UDim2.fromScale(0.2, 0.04),
			-45,
			Theme.Colors.Ink,
			4,
			false
		)
	end
end
emblems.Mummy = function(root, c)
	circle(root, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.7, 0.7), c, 2)
	for i = -1, 1 do
		bar(root, UDim2.fromScale(0.5, 0.5 + i * 0.16), UDim2.fromScale(0.74, 0.07), i * 8, Theme.Colors.Ink, 3, false)
	end
	circle(root, UDim2.fromScale(0.6, 0.42), UDim2.fromScale(0.12, 0.12), Theme.Colors.Gold, 4)
end
emblems.Sorcerer = function(root, c)
	circle(root, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.42, 0.42), c, 3)
	local ring = circle(root, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.82, 0.82), c, 2)
	ring.BackgroundTransparency = 1
	local stroke = Instance.new("UIStroke")
	stroke.Color = c
	stroke.Thickness = 3
	stroke.Parent = ring
end
emblems.Shinigami = function(root, c)
	circle(root, UDim2.fromScale(0.5, 0.48), UDim2.fromScale(0.74, 0.78), c, 2)
	for i = -1, 1 do
		circle(
			root,
			UDim2.fromScale(0.5 + i * 0.2, 0.42 + (i == 0 and 0.18 or 0)),
			UDim2.fromScale(0.16, 0.18),
			Theme.Colors.Ink,
			3
		)
	end
end
emblems.Golem = function(root, c)
	bar(root, UDim2.fromScale(0.5, 0.75), UDim2.fromScale(0.74, 0.24), 0, c, 2, false)
	bar(root, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.56, 0.22), 0, c:Lerp(Color3.new(0, 0, 0), 0.15), 2, false)
	bar(root, UDim2.fromScale(0.5, 0.27), UDim2.fromScale(0.36, 0.2), 0, c, 2, false)
	circle(root, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.12, 0.12), Color3.fromRGB(255, 170, 70), 4)
end

function Icons.Race(raceId: string, color: Color3): Frame
	local root = container()
	local builder = emblems[raceId] or emblems.Human
	builder(root, color)
	return root
end

-- Unknown race silhouette for the collection index.
function Icons.Unknown(color: Color3): Frame
	local root = container()
	circle(root, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.7, 0.7), Theme.Colors.InkLighter, 2)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = "?"
	label.FontFace = Theme.Fonts.Display
	label.TextScaled = true
	label.TextColor3 = color
	label.ZIndex = 3
	label.Parent = root
	return root
end

-- Icon for an ability slot.
function Icons.ForSlot(slot: string, color: Color3?): Frame
	if slot == "Z" then
		return Icons.Slashes(color)
	elseif slot == "X" then
		return Icons.Swirl(color)
	elseif slot == "C" then
		return Icons.Grin(color)
	elseif slot == "V" then
		return Icons.Skull(color)
	end
	return Icons.KishinEye()
end

return Icons
