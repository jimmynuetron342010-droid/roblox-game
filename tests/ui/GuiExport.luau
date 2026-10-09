--[[
	GuiExport (Lune)
	Serializes a MockInstance GUI tree to JSON for tests/ui/render_ui.mjs, which lays it out with
	CSS that mirrors Roblox's rules (scale+offset UDim2, AnchorPoint, UIListLayout/UIGridLayout,
	UIPadding, AutomaticSize, UIScale, UICorner, UIStroke, UIGradient, ClipsDescendants, ZIndex).
]]

local MockInstance = require("./MockInstance")

local GuiExport = {}

local PROPS = {
	GuiObject = {
		"Size",
		"Position",
		"AnchorPoint",
		"BackgroundColor3",
		"BackgroundTransparency",
		"BorderSizePixel",
		"BorderColor3",
		"Visible",
		"ZIndex",
		"LayoutOrder",
		"Rotation",
		"ClipsDescendants",
		"AutomaticSize",
		"SizeConstraint",
	},
	TextLabel = "Text",
	TextButton = "Text",
	TextBox = "Text",
	ImageLabel = "Image",
	ImageButton = "Image",
	ScrollingFrame = {
		"CanvasSize",
		"AutomaticCanvasSize",
		"ScrollBarThickness",
		"ScrollBarImageColor3",
		"ScrollingDirection",
	},
	UIListLayout = { "FillDirection", "Padding", "HorizontalAlignment", "VerticalAlignment", "SortOrder", "Wraps" },
	UIGridLayout = {
		"CellSize",
		"CellPadding",
		"FillDirection",
		"HorizontalAlignment",
		"VerticalAlignment",
		"SortOrder",
	},
	UIPadding = { "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight" },
	UICorner = { "CornerRadius" },
	UIStroke = { "Color", "Thickness", "Transparency", "ApplyStrokeMode", "Enabled" },
	UIScale = { "Scale" },
	UIGradient = { "Color", "Transparency", "Rotation", "Enabled", "Offset" },
	UISizeConstraint = { "MinSize", "MaxSize" },
	UIAspectRatioConstraint = { "AspectRatio" },
	ScreenGui = { "Enabled", "IgnoreGuiInset", "DisplayOrder" },
}

local TEXT_PROPS = {
	"Text",
	"TextColor3",
	"TextSize",
	"FontFace",
	"TextXAlignment",
	"TextYAlignment",
	"TextWrapped",
	"TextScaled",
	"RichText",
	"TextTransparency",
	"TextStrokeTransparency",
	"TextStrokeColor3",
	"TextTruncate",
	"LineHeight",
}
local IMAGE_PROPS = { "Image", "ImageColor3", "ImageTransparency" }

local function finite(n: number): number
	if n ~= n then
		return 0
	elseif n == math.huge then
		return 1e9
	elseif n == -math.huge then
		return -1e9
	end
	return n
end

local function serialize(value: any): any
	local kind = typeof(value)
	if kind == "number" then
		return finite(value)
	elseif kind == "boolean" or kind == "string" then
		return value
	elseif kind == "UDim2" then
		return { value.X.Scale, value.X.Offset, value.Y.Scale, value.Y.Offset }
	elseif kind == "UDim" then
		return { value.Scale, value.Offset }
	elseif kind == "Vector2" then
		return { finite(value.X), finite(value.Y) }
	elseif kind == "Color3" then
		return { value.R, value.G, value.B }
	elseif kind == "EnumItem" then
		return string.match(tostring(value), "([^%.]+)$")
	elseif kind == "Font" then
		return {
			value.Family,
			string.match(tostring(value.Weight), "([^%.]+)$"),
			string.match(tostring(value.Style), "([^%.]+)$"),
		}
	elseif kind == "ColorSequence" then
		local out = {}
		for _, keypoint in value.Keypoints do
			table.insert(out, { keypoint.Time, keypoint.Value.R, keypoint.Value.G, keypoint.Value.B })
		end
		return out
	elseif kind == "NumberSequence" then
		local out = {}
		for _, keypoint in value.Keypoints do
			table.insert(out, { keypoint.Time, keypoint.Value })
		end
		return out
	end
	return nil
end

local function propList(className: string): { string }
	local list = {}
	local function add(names)
		if type(names) == "table" then
			for _, name in names do
				table.insert(list, name)
			end
		end
	end
	if MockInstance.IsA(className, "GuiObject") then
		add(PROPS.GuiObject)
	end
	if className == "TextLabel" or className == "TextButton" or className == "TextBox" then
		add(TEXT_PROPS)
		if className == "TextBox" then
			add({ "PlaceholderText", "PlaceholderColor3" })
		end
	end
	if className == "ImageLabel" or className == "ImageButton" then
		add(IMAGE_PROPS)
	end
	add(PROPS[className])
	return list
end

function GuiExport.Node(instance)
	local className = MockInstance.Class(instance)
	local node = { c = className, n = instance.Name, p = {}, k = {} }
	for _, prop in propList(className) do
		node.p[prop] = serialize(MockInstance.Get(instance, prop))
	end
	local attributes = instance:GetAttributes()
	if next(attributes) then
		node.a = {}
		for key, value in attributes do
			node.a[key] = serialize(value)
		end
	end
	for _, child in MockInstance.Children(instance) do
		table.insert(node.k, GuiExport.Node(child))
	end
	return node
end

return GuiExport
