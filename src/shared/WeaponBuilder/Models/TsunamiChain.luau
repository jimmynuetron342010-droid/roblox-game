--[[
	Tsunami Chain
	Wrapped handle with a short faceted blade on top; a long articulated chain hangs from the pommel
	and ends in a heavy faceted blade with a hook. Every link is real geometry.

	Components: Handle, TopBlade, Chain, EndBlade
]]

local BladeKit = require(script.Parent.Parent.BladeKit)
local ChainKit = require(script.Parent.Parent.ChainKit)

return function(api)
	local d, p = api.Dimensions, api.Palette
	local unit = api.Unit("Main", "RightHand")
	local kit, handle = unit.Kit, unit.Handle
	local gl = d.GripLength

	local handleGroup = kit:Group("Handle")
	kit:Cylinder("HandleCore", Vector3.new(0, -gl / 2, 0), Vector3.new(0, gl / 2, 0), 0.27, p.Grip, Enum.Material.Fabric, handleGroup)
	for _, y in { -gl / 2, gl / 2 } do
		kit:Cylinder("Ferrule", Vector3.new(0, y - 0.07, 0), Vector3.new(0, y + 0.07, 0), 0.36, p.Link, Enum.Material.Metal, handleGroup)
	end
	kit:Cylinder("Ring", Vector3.new(0, -gl / 2 - 0.2, 0), Vector3.new(0, -gl / 2 - 0.07, 0), 0.3, p.LinkDark, Enum.Material.Metal, handleGroup)

	local top = kit:Group("TopBlade")
	BladeKit.Diamond(kit, top, Vector3.new(0, gl / 2 + 0.05, 0), Vector3.new(0, gl / 2 + 1.05, 0), 0.42, Vector3.zAxis, 0.07, p.Blade, p.Edge)

	local chainGroup = kit:Group("Chain")
	local chain = ChainKit.Build(kit, chainGroup, handle, Vector3.new(0, -gl / 2 - 0.2, 0), Vector3.new(0, -1, 0), d.Links, d.LinkLength, d.LinkWidth, p.Link, p.LinkDark)
	local last = chain.Links[#chain.Links]
	local e = chain.EndFrame

	local endGroup = kit:Group("EndBlade")
	kit:Cylinder("EndCollar", e * Vector3.new(0, 0.0, 0), e * Vector3.new(0, 0.18, 0), 0.3, p.LinkDark, Enum.Material.Metal, endGroup)
	BladeKit.Diamond(kit, endGroup, e * Vector3.new(0, 0.15, 0), e * Vector3.new(0, d.BladeLength + 0.15, 0), 0.62, e.LookVector, 0.1, p.Blade, p.Edge)
	kit:Spike("Hook", e * Vector3.new(0, 0.55, 0), e * Vector3.new(0, 0.3, 0) + e.RightVector * 0.7, 0.32, 0.1, p.Edge, e.UpVector, Enum.Material.Metal, endGroup)
	for _, part in endGroup:GetChildren() do
		if part:IsA("BasePart") then
			kit:Reweld(part, last)
		end
	end

	local trailA = Instance.new("Attachment")
	trailA.Name = "TrailA"
	trailA.CFrame = last.CFrame:Inverse() * kit:ToWorldCFrame(e * CFrame.new(0, 0.2, 0))
	trailA.Parent = last
	local trailB = Instance.new("Attachment")
	trailB.Name = "TrailB"
	trailB.CFrame = last.CFrame:Inverse() * kit:ToWorldCFrame(e * CFrame.new(0, d.BladeLength, 0))
	trailB.Parent = last
	local impact = Instance.new("Attachment")
	impact.Name = "Impact"
	impact.CFrame = trailB.CFrame
	impact.Parent = last
end
