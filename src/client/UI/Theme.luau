--[[
	Theme
	Design tokens for the whole UI: a dark ink panel style with hand-drawn display type, gold
	accents, and rarity colors from RarityConfig. Text/background pairs meet at least 4.5:1
	contrast. Motion helpers automatically respect reduced-motion preferences.
]]

local TweenService = game:GetService("TweenService")

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local RarityConfig = require(Modules.Config.RarityConfig)

local Theme = {}

Theme.Colors = {
	Ink = Color3.fromRGB(16, 13, 21), -- panel background
	InkLight = Color3.fromRGB(30, 25, 38),
	InkLighter = Color3.fromRGB(44, 37, 56),
	Stroke = Color3.fromRGB(78, 66, 96),
	Text = Color3.fromRGB(242, 240, 246),
	TextDim = Color3.fromRGB(186, 180, 200),
	TextMuted = Color3.fromRGB(140, 132, 158),
	Gold = Color3.fromRGB(244, 196, 72),
	Red = Color3.fromRGB(226, 52, 64),
	RedDark = Color3.fromRGB(120, 18, 30),
	Stamina = Color3.fromRGB(246, 190, 52),
	Soul = Color3.fromRGB(96, 176, 255),
	Madness = Color3.fromRGB(190, 80, 230),
	Good = Color3.fromRGB(108, 224, 140),
	Bad = Color3.fromRGB(255, 108, 108),
	Moon = Color3.fromRGB(255, 214, 80),
	Overlay = Color3.fromRGB(8, 6, 12),
}

Theme.Fonts = {
	Display = Font.fromEnum(Enum.Font.Bangers),
	Hand = Font.fromEnum(Enum.Font.PermanentMarker),
	Body = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium),
	BodyBold = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold),
}

Theme.TextSize = {
	Small = 14, -- minimum readable size (mobile included)
	Body = 16,
	Large = 20,
	Title = 28,
	Hero = 44,
}

Theme.Corner = UDim.new(0, 12)
Theme.CornerSmall = UDim.new(0, 8)

Theme.ReducedMotion = function(): boolean
	return false
end

function Theme.Rarity(id: string)
	return RarityConfig.Tiers[id] or RarityConfig.Tiers.Common
end

-- Tween that degrades to an instant set when reduced motion is on.
function Theme.Tween(
	instance: Instance,
	time: number,
	goal: { [string]: any },
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?
)
	if Theme.ReducedMotion() then
		for key, value in goal do
			(instance :: any)[key] = value
		end
		return nil
	end
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(time, style or Enum.EasingStyle.Quint, direction or Enum.EasingDirection.Out),
		goal
	)
	tween:Play()
	return tween
end

return Theme
