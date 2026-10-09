-- Verifies the harness lookAt matches Roblox conventions (LookVector points at the target).
local roblox = require("@lune/roblox")
local Polyfills = require("../../tests/harness/Polyfills")
local CFrame, Vector3 = Polyfills.CFrame, roblox.Vector3
for _, d in { { 0, 0, 1 }, { 0, 0, -1 }, { 1, 0, 1 }, { 0.3, 0.2, 1 }, { 0, 1, 0 }, { 0, -1, 0.0001 } } do
	local dir = Vector3.new(d[1], d[2], d[3])
	local cf = CFrame.lookAt(Vector3.new(1, 2, 3), Vector3.new(1, 2, 3) + dir)
	local legacy = CFrame.new(Vector3.new(1, 2, 3), Vector3.new(1, 2, 3) + dir)
	print(
		string.format(
			"dir (%g,%g,%g): dot %.4f legacy %.4f up.y %.3f",
			d[1],
			d[2],
			d[3],
			cf.LookVector:Dot(dir.Unit),
			legacy.LookVector:Dot(dir.Unit),
			cf.UpVector.Y
		)
	)
end
print("identity still ok:", CFrame.new(1, 2, 3).Position, CFrame.Angles(0, 1, 0).LookVector)
