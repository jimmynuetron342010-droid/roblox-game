--[[
	Shared helpers for effect modules (not an effect itself; VFXController skips names starting
	with "_" when listing effects).
]]

local Shared = {}

function Shared.FindAttachment(model: Instance?, name: string): Attachment?
	if not model then
		return nil
	end
	local found = model:FindFirstChild(name, true)
	if found and found:IsA("Attachment") then
		return found
	end
	return nil
end

-- World position of the weapon tip (Impact attachment), falling back to the character's front.
function Shared.TipPosition(params): Vector3?
	local attachment = Shared.FindAttachment(params.Weapon, "Impact")
	if attachment then
		return attachment.WorldPosition
	end
	local root = params.Character and params.Character:FindFirstChild("HumanoidRootPart")
	if root then
		return (root :: BasePart).CFrame * Vector3.new(0, 0, -4)
	end
	return nil
end

function Shared.Root(params): BasePart?
	local character = params.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root and root:IsA("BasePart") and root or nil
end

-- Normalized strike time of an attack (first hit) for timing glints/flashes.
function Shared.HitTimes(params): { number }
	local times = {}
	local attack = params.Attack
	local duration = params.Duration or (attack and attack.Duration) or 0.5
	local scale = attack and attack.Duration and duration / attack.Duration or 1
	if attack and attack.Hits then
		for _, hit in attack.Hits do
			table.insert(times, hit.Time * scale)
		end
	end
	if #times == 0 then
		table.insert(times, duration * 0.4)
	end
	return times
end

-- Temporarily changes a Trail's width/lifetime and restores it.
function Shared.BoostTrail(vfx, weapon: Instance?, duration: number, widthScale: number?, lifetime: number?)
	if not weapon then
		return
	end
	for _, trail in weapon:GetDescendants() do
		if trail:IsA("Trail") then
			local oldWidth, oldLifetime = trail.WidthScale, trail.Lifetime
			if widthScale then
				trail.WidthScale = NumberSequence.new({
					NumberSequenceKeypoint.new(0, widthScale),
					NumberSequenceKeypoint.new(1, widthScale * 0.2),
				})
			end
			if lifetime then
				trail.Lifetime = lifetime
			end
			vfx.Delay(duration, function()
				if trail.Parent then
					trail.WidthScale = oldWidth
					trail.Lifetime = oldLifetime
				end
			end)
		end
	end
end

return Shared
