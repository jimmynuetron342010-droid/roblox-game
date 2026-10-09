--[[
	ChainKit
	Builds physically articulated chains: every link is a real ring of metal (two side bars + two
	end caps) joined to the previous link by a Motor6D at the link pivot. Links alternate 90° like a
	real chain. The client's ChainSimulator drives the Motor6D.Transform values with a verlet rope
	so the chain swings, sags and trails behind attacks — it is never replaced by an energy rope.
]]

local GeometryKit = require(script.Parent.Parent.Core.GeometryKit)

local ChainKit = {}

export type Chain = {
	Links: { BasePart },
	Motors: { Motor6D },
	EndPoint: Vector3,
	EndFrame: CFrame,
	Spacing: number,
}

-- `start` and `direction` are in model space. `anchor` is the part the first link hangs from.
function ChainKit.Build(
	kit,
	group: Instance,
	anchor: BasePart,
	start: Vector3,
	direction: Vector3,
	count: number,
	linkLength: number,
	linkWidth: number,
	colorA: Color3,
	colorB: Color3
): Chain
	local dir = direction.Unit
	local spacing = linkLength * 0.78 -- links overlap so they interlock visually
	local bar = math.max(linkWidth * 0.26, 0.05)
	local links, motors = {}, {}
	local previous = anchor
	for i = 1, count do
		local s = start + dir * ((i - 1) * spacing)
		local frame = GeometryKit.FrameAlong(s, dir, "Y") * CFrame.Angles(0, (i % 2 == 0) and math.pi / 2 or 0, 0)
		local color = (i % 2 == 0) and colorB or colorA
		local half = linkWidth / 2
		local y0, y1 = linkLength * 0.08, linkLength * 0.92
		local root = kit:Cylinder("Link", frame * Vector3.new(-half, y0, 0), frame * Vector3.new(-half, y1, 0), bar, color, Enum.Material.Metal, group)
		local side = kit:Cylinder("LinkSide", frame * Vector3.new(half, y0, 0), frame * Vector3.new(half, y1, 0), bar, color, Enum.Material.Metal, group)
		local capA = kit:Cylinder("LinkCap", frame * Vector3.new(-half - bar * 0.4, y0, 0), frame * Vector3.new(half + bar * 0.4, y0, 0), bar, color, Enum.Material.Metal, group)
		local capB = kit:Cylinder("LinkCap", frame * Vector3.new(-half - bar * 0.4, y1, 0), frame * Vector3.new(half + bar * 0.4, y1, 0), bar, color, Enum.Material.Metal, group)
		for _, part in { side, capA, capB } do
			kit:Reweld(part, root)
		end
		local motor = kit:Motor("ChainJoint", previous, root, GeometryKit.FrameAlong(s, dir, "Y"))
		motor:SetAttribute("ChainIndex", i)
		motor:SetAttribute("Spacing", spacing * kit.Scale)
		table.insert(links, root)
		table.insert(motors, motor)
		previous = root
	end
	local endPoint = start + dir * ((count - 1) * spacing + linkLength)
	if group:IsA("Model") or group:IsA("Folder") then
		group:SetAttribute("ChainLinks", count)
	end
	return {
		Links = links,
		Motors = motors,
		EndPoint = endPoint,
		EndFrame = GeometryKit.FrameAlong(endPoint, dir, "Y"),
		Spacing = spacing,
	}
end

return ChainKit
