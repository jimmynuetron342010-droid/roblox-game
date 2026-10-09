--[[
	SceneExport (Lune)
	Serializes every BasePart under the given roots into JSON for the three.js viewer.
	Part shapes follow Roblox conventions: Block, Ball, Cylinder (axis = X), WedgePart.
]]

local SceneExport = {}

local function components(cf)
	local p, x, y, z = cf.Position, cf.RightVector, cf.UpVector, -cf.LookVector
	-- Row-major rotation matrix whose columns are the X, Y, Z axes.
	return { p.X, p.Y, p.Z, x.X, y.X, z.X, x.Y, y.Y, z.Y, x.Z, y.Z, z.Z }
end

local function shapeOf(part)
	if part.ClassName == "WedgePart" then
		return "Wedge"
	elseif part.ClassName == "CornerWedgePart" then
		return "CornerWedge"
	end
	local ok, shape = pcall(function()
		return part.Shape
	end)
	if ok and shape then
		return shape.Name
	end
	return "Block"
end

function SceneExport.Collect(roots, out)
	out = out or {}
	for _, root in roots do
		local list = root:GetDescendants()
		if root:IsA("BasePart") then
			table.insert(list, root)
		end
		for _, part in list do
			if part:IsA("BasePart") and part.Transparency < 0.99 then
				local c = part.Color
				table.insert(out, {
					n = part.Name,
					s = shapeOf(part),
					sz = { part.Size.X, part.Size.Y, part.Size.Z },
					cf = components(part.CFrame),
					col = { c.R, c.G, c.B },
					m = part.Material.Name,
					t = part.Transparency,
					r = part.Reflectance,
				})
			end
		end
	end
	return out
end

return SceneExport
