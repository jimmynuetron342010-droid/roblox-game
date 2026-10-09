--[[
	UISound
	Non-positional interface sounds (reveal stingers, clicks). Every id below is a clearly marked
	placeholder — replace "rbxassetid://0" with your own uploaded audio. Placeholders are skipped
	silently, so the UI works before audio exists.
]]

local SoundService = game:GetService("SoundService")

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local WeaponConfig = require(Modules.WeaponConfig)

local PH = WeaponConfig.PLACEHOLDER

local UISound = {}

UISound.Ids = {
	Click = PH,
	RollCharge = PH,
	RevealCommon = PH,
	RevealUncommon = PH,
	RevealRare = PH,
	RevealEpic = PH,
	RevealLegendary = PH,
	RevealMythic = PH,
	Confirm = PH,
	Error = PH,
}

local cache: { [string]: Sound } = {}

function UISound.Play(key: string, volume: number?)
	local id = UISound.Ids[key]
	if not id or WeaponConfig.IsPlaceholder(id) then
		return
	end
	local sound = cache[key]
	if not sound then
		sound = Instance.new("Sound")
		sound.Name = "UI_" .. key
		sound.SoundId = id
		sound.Parent = SoundService
		cache[key] = sound
	end
	sound.Volume = volume or 0.6
	SoundService:PlayLocalSound(sound)
end

return UISound
