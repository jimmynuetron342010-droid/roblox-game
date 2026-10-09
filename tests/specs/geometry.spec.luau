local Loader = require("../harness/Loader")
local Test = require("../harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local loader = Loader.new()
local roblox = Loader.roblox
local Vector3, CFrame, Instance = roblox.Vector3, roblox.CFrame, roblox.Instance
local GeometryKit = loader.RequirePath("ReplicatedStorage.Modules.Core.GeometryKit")

-- Roblox WedgePart: right-triangle prism. In local space (YZ cross-section) the vertices are
-- bottom-front (-h/2, -d/2), bottom-back (-h/2, +d/2), top-back (+h/2, +d/2).
local function wedgeTriangle(part)
	local s = part.Size
	local cf = part.CFrame
	return {
		cf * Vector3.new(0, -s.Y / 2, -s.Z / 2),
		cf * Vector3.new(0, -s.Y / 2, s.Z / 2),
		cf * Vector3.new(0, s.Y / 2, s.Z / 2),
	}
end

local function area(a, b, c)
	return (b - a):Cross(c - a).Magnitude / 2
end

local function near(p, q)
	return (p - q).Magnitude < 1e-3
end

local function newKit(origin, scale)
	local model = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Parent = model
	return GeometryKit.new({ Model = model, Root = root, Origin = origin, Scale = scale }), model
end

describe("GeometryKit triangles", function()
	local cases = {
		{ Vector3.new(0, 0, 0), Vector3.new(2, 0, 0), Vector3.new(0.5, 1.5, 0) },
		{ Vector3.new(0, 0, 0), Vector3.new(0, 3, 0), Vector3.new(0, 1, -2) },
		{ Vector3.new(1, 2, 3), Vector3.new(-2, 0.5, 1), Vector3.new(0.3, -1, 2.2) },
		{ Vector3.new(0, 0, 0), Vector3.new(4, 0.1, 0), Vector3.new(2, 0.05, 0.3) }, -- sliver
	}
	for index, case in cases do
		it("reconstructs triangle #" .. index .. " exactly from two wedges", function()
			local origin = CFrame.new(5, -3, 2) * CFrame.Angles(0.3, 1.1, -0.4)
			local kit = newKit(origin, 1.5)
			local w1, w2 = kit:Triangle("T", case[1], case[2], case[3], 0.1, roblox.Color3.new(1, 1, 1))
			local expected = {
				kit:ToWorldPoint(case[1]),
				kit:ToWorldPoint(case[2]),
				kit:ToWorldPoint(case[3]),
			}
			local total = 0
			for _, w in { w1, w2 } do
				if w then
					local tri = wedgeTriangle(w)
					total += area(tri[1], tri[2], tri[3])
					-- Every wedge corner lies on the triangle's edges/vertices.
					for _, p in tri do
						local onTriangle = false
						for i = 1, 3 do
							local a, b = expected[i], expected[i % 3 + 1]
							local ab = b - a
							local t = math.clamp((p - a):Dot(ab) / ab:Dot(ab), 0, 1)
							if near(a + ab * t, p) then
								onTriangle = true
							end
						end
						expect(onTriangle).toBe(true)
					end
				end
			end
			expect(total).toBeNear(area(expected[1], expected[2], expected[3]), 1e-3)
			-- Each original vertex is a corner of at least one wedge.
			for _, v in expected do
				local found = false
				for _, w in { w1, w2 } do
					if w then
						for _, p in wedgeTriangle(w) do
							if near(p, v) then
								found = true
							end
						end
					end
				end
				expect(found).toBe(true)
			end
		end)
	end

	it("welds every generated part to the root with matching offsets", function()
		local kit, model = newKit(CFrame.new(1, 2, 3), 1)
		kit:Triangle("T", Vector3.new(0, 0, 0), Vector3.new(1, 0, 0), Vector3.new(0, 1, 0), 0.1, roblox.Color3.new(1, 0, 0))
		kit:Cylinder("C", Vector3.new(0, 0, 0), Vector3.new(0, 5, 0), 0.3, roblox.Color3.new(0, 1, 0))
		local count = 0
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") and part.Name ~= "Root" then
				count += 1
				local weld = part:FindFirstChild("Weld")
				expect(weld ~= nil).toBe(true)
				local root = model:FindFirstChild("Root")
				local rebuilt = root.CFrame * weld.C0 * weld.C1:Inverse()
				expect((rebuilt.Position - part.CFrame.Position).Magnitude).toBeAtMost(1e-4)
				expect(part.CanCollide).toBe(false)
				expect(part.Massless).toBe(true)
				expect(part.Anchored).toBe(false)
			end
		end
		expect(count).toBe(3)
	end)

	it("places cylinders exactly between two points", function()
		local kit = newKit(CFrame.new(), 1)
		local c = kit:Cylinder("C", Vector3.new(1, 1, 1), Vector3.new(1, 6, 1), 0.4, roblox.Color3.new(1, 1, 1))
		expect(c.Size.X).toBeNear(5, 1e-4)
		expect((c.CFrame.Position - Vector3.new(1, 3.5, 1)).Magnitude).toBeAtMost(1e-4)
		expect(math.abs(c.CFrame.RightVector:Dot(Vector3.yAxis))).toBeNear(1, 1e-4)
	end)
end)
