--[[
	Gevurah Spiked Chain
	Heavy wrapped handle with banded collars, nine thick links, two spiked collars along the chain
	and a spiked ball at the end. Spikes are crossed blade pairs so they read from every angle.

	Components: Handle, Chain, SpikedCollars, Ball
]]

local ChainKit = require(script.Parent.Parent.ChainKit)

local function crossSpike(kit, group, base: Vector3, tip: Vector3, width: number, color: Color3, anchor: BasePart?)
	local axis = (tip - base).Unit
	local side = math.abs(axis.Y) < 0.9 and Vector3.yAxis or Vector3.xAxis
	local s1 = axis:Cross(side).Unit
	local s2 = axis:Cross(s1).Unit
	for _, side in { s1, s2 } do
		local w1, w2 = kit:Spike("Spike", base, tip, width, 0.07, color, side, Enum.Material.Metal, group)
		if anchor then
			for _, wedge in { w1, w2 } do
				if wedge then
					kit:Reweld(wedge, anchor)
				end
			end
		end
	end
end

return function(api)
	local d, p = api.Dimensions, api.Palette
	local unit = api.Unit("Main", "RightHand")
	local kit, handle = unit.Kit, unit.Handle
	local gl = d.GripLength

	local handleGroup = kit:Group("Handle")
	kit:Cylinder("HandleCore", Vector3.new(0, -gl / 2, 0), Vector3.new(0, gl / 2, 0), 0.32, p.Grip, Enum.Material.Fabric, handleGroup)
	for _, y in { -gl / 2 + 0.05, 0.1, gl / 2 - 0.05 } do
		kit:Cylinder("Band", Vector3.new(0, y - 0.08, 0), Vector3.new(0, y + 0.08, 0), 0.42, p.Band, Enum.Material.Metal, handleGroup)
	end
	kit:Ball("Pommel", 0.44, Vector3.new(0, -gl / 2 - 0.12, 0), p.Band, Enum.Material.Metal, handleGroup)
	crossSpike(kit, handleGroup, Vector3.new(0, -gl / 2 - 0.25, 0), Vector3.new(0, -gl / 2 - 0.7, 0), 0.22, p.Spike)
	kit:Cylinder("HeadCap", Vector3.new(0, gl / 2, 0), Vector3.new(0, gl / 2 + 0.22, 0), 0.5, p.Band, Enum.Material.Metal, handleGroup)
	kit:Cylinder("Eyelet", Vector3.new(-0.12, gl / 2 + 0.32, 0), Vector3.new(0.12, gl / 2 + 0.32, 0), 0.22, p.Link, Enum.Material.Metal, handleGroup)

	-- The chain leaves the head of the handle, like a real flail, and is simulated on the client.
	local chainGroup = kit:Group("Chain")
	local chainStart = Vector3.new(0, gl / 2 + 0.32, 0)
	local chain = ChainKit.Build(kit, chainGroup, handle, chainStart, Vector3.new(0, 1, 0), d.Links, d.LinkLength, d.LinkWidth, p.Link, p.Link:Lerp(Color3.new(0, 0, 0), 0.2))

	-- Spiked collars on two links (centered on the chain axis).
	local collars = kit:Group("SpikedCollars")
	for _, index in { 2, 4 } do
		local link = chain.Links[index]
		local localCenter = chainStart + Vector3.new(0, 1, 0) * ((index - 1) * chain.Spacing + d.LinkLength * 0.5)
		local band = kit:Cylinder("CollarBand", localCenter + Vector3.new(0, 0.12, 0), localCenter - Vector3.new(0, 0.12, 0), 0.62, p.Band, Enum.Material.Metal, collars)
		kit:Reweld(band, link)
		for k = 0, 3 do
			local a = math.rad(k * 90 + 45)
			local out = Vector3.new(math.cos(a), 0, math.sin(a))
			crossSpike(kit, collars, localCenter + out * 0.28, localCenter + out * 0.62, 0.18, p.Spike, link)
		end
	end

	-- Spiked ball.
	local last = chain.Links[#chain.Links]
	local ballGroup = kit:Group("Ball")
	local e = chain.EndFrame
	local radius = d.BallRadius
	local center = e * Vector3.new(0, radius * 0.9, 0)
	local ball = kit:Ball("Ball", radius * 2, center, p.Ball, Enum.Material.Metal, ballGroup)
	kit:Reweld(ball, last)
	local band = kit:Cylinder("BallBand", center + e.UpVector * 0.08, center - e.UpVector * 0.08, radius * 2.08, p.Band, Enum.Material.Metal, ballGroup)
	kit:Reweld(band, last)
	-- Evenly distributed spikes (golden-angle spiral).
	local count = d.Spikes
	for i = 0, count - 1 do
		local y = 1 - (i + 0.5) / count * 2
		local r = math.sqrt(1 - y * y)
		local theta = i * 2.39996
		local dir = Vector3.new(math.cos(theta) * r, y, math.sin(theta) * r)
		crossSpike(kit, ballGroup, center + dir * radius * 0.75, center + dir * radius * 1.65, 0.3, p.Spike, last)
	end

	local trailA = Instance.new("Attachment")
	trailA.Name = "TrailA"
	trailA.CFrame = last.CFrame:Inverse() * kit:ToWorldCFrame(CFrame.new(center - e.UpVector * radius))
	trailA.Parent = last
	local trailB = Instance.new("Attachment")
	trailB.Name = "TrailB"
	trailB.CFrame = last.CFrame:Inverse() * kit:ToWorldCFrame(CFrame.new(center + e.UpVector * radius))
	trailB.Parent = last
	local impact = Instance.new("Attachment")
	impact.Name = "Impact"
	impact.CFrame = last.CFrame:Inverse() * kit:ToWorldCFrame(CFrame.new(center))
	impact.Parent = last
end
