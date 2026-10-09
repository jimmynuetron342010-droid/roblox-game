--[[
	Effect 8 — Drill Attack
	The bit spins (AnimatorCore drives the "BitSpin" motor while this effect marks the character as
	drilling). While the tip touches a surface it throws scraping sparks, dust in the surface color
	and small chips. Everything stops the instant the attack ends.
]]

local Shared = require(script.Parent._Shared)

return function(vfx, p, cfg)
	local character = p.Character
	if not character then
		return
	end
	local duration = (p.Params and p.Params.Duration) or p.Duration or 0.5
	local contact = Shared.FindAttachment(p.Weapon, "DrillContact")
	local token = {}
	character:SetAttribute("Drilling", true)
	character:SetAttribute("DrillToken", tostring(token))
	local t, sparkAcc, dustAcc, chipTimer = 0, 0, 0, 0
	vfx.AddTask(function(dt)
		t += dt
		if t >= duration or not character.Parent or character:GetAttribute("DrillToken") ~= tostring(token) then
			if character:GetAttribute("DrillToken") == tostring(token) then
				character:SetAttribute("Drilling", false)
			end
			return false
		end
		if not contact or not contact.Parent then
			return true
		end
		local cf = contact.WorldCFrame
		-- The drill axis is the bit's -Z (model space).
		local axis = -cf.ZVector
		local result = vfx.Raycast(cf.Position, axis * cfg.ContactDistance * 1.6, { character })
		if result then
			sparkAcc += cfg.SparkRate * dt
			dustAcc += cfg.DustRate * dt
			local spray = CFrame.lookAt(result.Position, result.Position + (result.Normal - axis * 0.3).Unit)
			if sparkAcc >= 1 then
				vfx.Emit("Spark", spray, math.floor(sparkAcc))
				sparkAcc -= math.floor(sparkAcc)
			end
			local hitsCharacter = result.Instance and result.Instance.Parent and result.Instance.Parent:FindFirstChildOfClass("Humanoid")
			if dustAcc >= 1 and not hitsCharacter then
				vfx.Emit("Dust", spray, math.floor(dustAcc), { Color = ColorSequence.new(vfx.SurfaceColor(result)) })
				dustAcc -= math.floor(dustAcc)
			end
			chipTimer += dt
			if chipTimer > 0.25 and not hitsCharacter then
				chipTimer = 0
				vfx.Debris(result.Position, result.Normal, vfx.SurfaceColor(result), 1, 14, 0.25)
			end
		end
		return true
	end)
	vfx.Sound(cfg.Sound, contact and contact.WorldPosition or nil, 0.6)
end
