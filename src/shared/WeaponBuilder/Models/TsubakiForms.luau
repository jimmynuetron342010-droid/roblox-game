--[[
	Tsubaki's Forms — modular weapon with three forms (switch with T):
	  Blade       ninja sword: wrapped red handle, square tsuba, black blade with a steel edge
	  Kusarigama  sickle + articulated chain + weighted end
	  ChainSickle sickle + chain + second sickle at the end
	Components: Handle, Guard, Blade/Sickle, Chain, ChainEnd
]]

local BladeKit = require(script.Parent.Parent.BladeKit)
local ChainKit = require(script.Parent.Parent.ChainKit)

local function handleGroup(kit, p, length)
	local group = kit:Group("Handle")
	kit:Cylinder("HandleCore", Vector3.new(0, -length / 2, 0), Vector3.new(0, length / 2, 0), 0.25, p.Handle, Enum.Material.Fabric, group)
	for i = 0, 4 do
		local y = -length / 2 + 0.12 + i * (length - 0.24) / 4
		kit:Block("WrapDiamond", Vector3.new(0.22, 0.12, 0.22), CFrame.new(0, y, 0) * CFrame.Angles(0, math.rad(45), 0), p.Wrap, Enum.Material.Fabric, group)
	end
	kit:Cylinder("Pommel", Vector3.new(0, -length / 2 - 0.12, 0), Vector3.new(0, -length / 2, 0), 0.3, p.Metal, Enum.Material.Metal, group)
	return group
end

local function sickle(kit, group, p, origin: Vector3, radius: number, thickness: number)
	-- Crescent sickle blade sprouting from `origin` toward -Z and curving down.
	return BladeKit.Crescent(kit, group, {
		Spine = {
			origin + Vector3.new(0, 0.05, -0.05),
			origin + Vector3.new(0, radius * 0.55, -radius * 0.8),
			origin + Vector3.new(0, radius * 0.15, -radius * 1.55),
			origin + Vector3.new(0, -radius * 0.55, -radius * 1.75),
		},
		Segments = 6,
		Width = radius * 0.42,
		Taper = 0.9,
		EdgeSide = -1,
		Split = 0.55,
		SpineColor = p.Blade,
		EdgeColor = p.Edge,
		SpineThickness = thickness,
		EdgeThickness = thickness * 0.7,
	})
end

return function(api)
	local d, p = api.Dimensions, api.Palette
	local form = api.Form or "Blade"
	local unit = api.Unit("Main", "RightHand")
	local kit, handle = unit.Kit, unit.Handle

	if form == "Blade" then
		local gl = d.GripLength
		handleGroup(kit, p, gl)
		local guard = kit:Group("Guard")
		kit:Block("Tsuba", Vector3.new(0.72, 0.08, 0.72), CFrame.new(0, gl / 2 + 0.06, 0), p.Metal, Enum.Material.Metal, guard)
		kit:Block("Habaki", Vector3.new(0.18, 0.18, 0.5), CFrame.new(0, gl / 2 + 0.18, 0.02), p.Accent, Enum.Material.Metal, guard)
		-- Red tassel from the pommel.
		kit:Cylinder("Tassel", Vector3.new(0, -gl / 2 - 0.12, 0), Vector3.new(0.05, -gl / 2 - 0.65, 0.08), 0.06, p.Accent, Enum.Material.Fabric, guard)
		kit:Ball("TasselKnot", 0.14, Vector3.new(0.05, -gl / 2 - 0.68, 0.08), p.Accent, Enum.Material.Fabric, guard)

		local blade = kit:Group("Blade")
		local base = gl / 2 + 0.26
		local back, front = {}, {}
		local steps = 7
		for i = 0, steps do
			local t = i / steps
			local y = base + d.BladeLength * t
			local curve = 0.18 * t * t -- gentle sori (curve toward the back)
			table.insert(back, Vector3.new(0, y, 0.21 + curve))
			table.insert(front, Vector3.new(0, y - 0.04 * t, 0.21 + curve - d.BladeWidth * (1 - 0.15 * t)))
		end
		-- Kissaki (angled tip).
		local tip = back[#back] + Vector3.new(0, 0.32, -0.2)
		kit:Triangle("Kissaki", back[#back], front[#front], tip, d.Thickness, p.Edge, Enum.Material.Metal, blade)
		local mid = BladeKit.Between(kit, blade, back, front, 0.55, p.Blade, p.Edge, d.Thickness, d.Thickness * 0.7)
		kit:Attachment("TrailA", handle, CFrame.new(mid[2]))
		kit:Attachment("TrailB", handle, CFrame.new(mid[#mid]))
		kit:Attachment("Impact", handle, CFrame.new(tip))
		return
	end

	-- Sickle forms -----------------------------------------------------------------------
	local hl = 1.5
	handleGroup(kit, p, hl)
	local head = kit:Group("Sickle")
	kit:Block("Socket", Vector3.new(0.3, 0.36, 0.34), CFrame.new(0, hl / 2 + 0.12, -0.05), p.Metal, Enum.Material.Metal, head)
	local spine, _, edge = sickle(kit, head, p, Vector3.new(0, hl / 2 + 0.2, -0.1), d.SickleRadius, d.Thickness)
	kit:Attachment("SupportGrip", handle, CFrame.new(0, -0.2, 0))

	-- Chain from the pommel, hanging down (-Y). Simulated on the client.
	local chainGroup = kit:Group("Chain")
	local chain = ChainKit.Build(kit, chainGroup, handle, Vector3.new(0, -hl / 2 - 0.15, 0), Vector3.new(0, -1, 0), d.ChainLinks, d.LinkLength, 0.22, p.Metal, p.Blade)
	local last = chain.Links[#chain.Links]
	local endGroup = kit:Group("ChainEnd")
	local e = chain.EndFrame
	if form == "Kusarigama" then
		local weight = kit:Ball("Weight", 0.5, e * Vector3.new(0, 0.28, 0), p.Metal, Enum.Material.Metal, endGroup)
		kit:Reweld(weight, last)
		local band = kit:Cylinder("WeightBand", e * Vector3.new(0, 0.1, 0), e * Vector3.new(0, 0.2, 0), 0.36, p.Accent, Enum.Material.Metal, endGroup)
		kit:Reweld(band, last)
	else
		-- Second, smaller sickle on the chain end.
		sickle(kit, endGroup, p, e * Vector3.new(0, 0.15, 0), d.SickleRadius * 0.75, d.Thickness)
		for _, part in endGroup:GetChildren() do
			if part:IsA("BasePart") then
				kit:Reweld(part, last)
			end
		end
	end
	-- Trail on the chain end so swings leave a motion streak.
	local endA = Instance.new("Attachment")
	endA.Name = "ChainTrailA"
	endA.CFrame = last.CFrame:Inverse() * kit:ToWorldCFrame(chain.EndFrame * CFrame.new(0, -0.3, 0))
	endA.Parent = last
	local endB = Instance.new("Attachment")
	endB.Name = "ChainTrailB"
	endB.CFrame = last.CFrame:Inverse() * kit:ToWorldCFrame(chain.EndFrame * CFrame.new(0, 0.4, 0))
	endB.Parent = last
	kit:Attachment("TrailA", handle, CFrame.new(spine[2]:Lerp(edge[2], 0.5)))
	kit:Attachment("TrailB", handle, CFrame.new(spine[#spine - 1]:Lerp(edge[#edge - 1], 0.4)))
	kit:Attachment("Impact", handle, CFrame.new(edge[#edge]))
end
