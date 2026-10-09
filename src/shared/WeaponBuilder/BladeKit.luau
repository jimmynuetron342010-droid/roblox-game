--[[
	BladeKit
	Curved, two-tone blades built from true triangles (GeometryKit:Strip).
	A blade is described by its spine curve (the back) and a width profile; the cutting edge is the
	spine offset sideways within the blade plane. An optional zigzag boundary between the two colors
	gives the serrated Soul Eater look without extra geometry.
]]

local GeometryKit = require(script.Parent.Parent.Core.GeometryKit)

local BladeKit = {}

export type CrescentOptions = {
	Spine: { Vector3 }, -- Bezier control points (model space)
	Segments: number,
	Width: number, -- width at the base
	Taper: number?, -- exponent of the width falloff toward the tip (default 0.85)
	BaseWidthScale: number?, -- width multiplier at t = 0 (default 1)
	PlaneNormal: Vector3?, -- blade plane normal (default X)
	EdgeSide: number?, -- +1 / -1 picks which side of the spine the edge is on (default -1)
	Split: number?, -- fraction of width that is "spine color" (default 0.45)
	ZigZag: number?, -- zigzag amplitude as a fraction of width (0 = straight split)
	SpineColor: Color3,
	EdgeColor: Color3,
	SpineThickness: number,
	EdgeThickness: number,
	SpineMaterial: Enum.Material?,
	EdgeMaterial: Enum.Material?,
}

-- Returns spine, split and edge polylines.
function BladeKit.Crescent(kit, group: Instance, o: CrescentOptions)
	local spine = GeometryKit.SampleBezier(o.Spine, o.Segments)
	local normal = o.PlaneNormal or Vector3.xAxis
	local side = o.EdgeSide or -1
	local taper = o.Taper or 0.85
	local split = o.Split or 0.45
	local zig = o.ZigZag or 0
	local baseScale = o.BaseWidthScale or 1
	local widths, splitWidths = {}, {}
	for i = 1, #spine do
		local t = (i - 1) / (#spine - 1)
		local base = baseScale + (1 - baseScale) * math.min(t * 4, 1)
		local w = o.Width * base * (1 - t) ^ taper
		widths[i] = w * side
		local fraction = split
		if zig > 0 and i > 1 and i < #spine then
			fraction += (i % 2 == 0) and zig or -zig * 0.6
		end
		splitWidths[i] = w * fraction * side
	end
	local edge = GeometryKit.Offset(spine, widths, normal)
	local mid = GeometryKit.Offset(spine, splitWidths, normal)
	kit:Strip("BladeSpine", spine, mid, o.SpineThickness, o.SpineColor, o.SpineMaterial or Enum.Material.Metal, group)
	kit:Strip("BladeEdge", mid, edge, o.EdgeThickness, o.EdgeColor, o.EdgeMaterial or Enum.Material.Metal, group)
	return spine, mid, edge
end

-- Straight/slightly curved two-tone blade between a back line and an edge line.
function BladeKit.Between(
	kit,
	group: Instance,
	back: { Vector3 },
	front: { Vector3 },
	split: number,
	coreColor: Color3,
	edgeColor: Color3,
	coreThickness: number,
	edgeThickness: number
)
	local mid = {}
	for i = 1, #back do
		mid[i] = back[i]:Lerp(front[i], split)
	end
	kit:Strip("BladeCore", back, mid, coreThickness, coreColor, Enum.Material.Metal, group)
	kit:Strip("BladeEdge", mid, front, edgeThickness, edgeColor, Enum.Material.Metal, group)
	return mid
end

-- Faceted diamond blade (kunai / spear head) pointing from `base` to `tip`, lying in the plane
-- spanned by `widthDir`; `ridge` raises the center line for a bevelled 3D look.
function BladeKit.Diamond(
	kit,
	group: Instance,
	base: Vector3,
	tip: Vector3,
	width: number,
	widthDir: Vector3,
	ridge: number,
	darkColor: Color3,
	lightColor: Color3
)
	local axis = (tip - base).Unit
	local w = (widthDir - axis * widthDir:Dot(axis)).Unit
	local up = axis:Cross(w).Unit
	local shoulder = base + axis * ((tip - base).Magnitude * 0.3)
	local left, right = shoulder + w * width / 2, shoulder - w * width / 2
	for _, face in { 1, -1 } do
		local ridgePoint = shoulder + up * ridge * face
		kit:Triangle(
			"Facet",
			left,
			tip,
			ridgePoint,
			0.04,
			face == 1 and lightColor or darkColor,
			Enum.Material.Metal,
			group
		)
		kit:Triangle(
			"Facet",
			ridgePoint,
			tip,
			right,
			0.04,
			face == 1 and darkColor or lightColor,
			Enum.Material.Metal,
			group
		)
		kit:Triangle("Facet", left, ridgePoint, base, 0.04, darkColor, Enum.Material.Metal, group)
		kit:Triangle("Facet", ridgePoint, right, base, 0.04, darkColor, Enum.Material.Metal, group)
	end
end

return BladeKit
