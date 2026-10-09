--[[
	Test (Lune)
	A tiny BDD-style test framework: describe / it / expect. Collects results for the runner.
]]

local Test = {}

local results = { passed = 0, failed = 0, failures = {} }
local stack = {}

function Test.describe(name: string, body: () -> ())
	table.insert(stack, name)
	body()
	table.remove(stack)
end

function Test.it(name: string, body: () -> ())
	local fullName = table.concat(stack, " > ") .. " > " .. name
	local ok, err = xpcall(body, debug.traceback)
	if ok then
		results.passed += 1
		print("  \27[32m✓\27[0m " .. fullName)
	else
		results.failed += 1
		table.insert(results.failures, { name = fullName, err = err })
		print("  \27[31m✗ " .. fullName .. "\27[0m\n" .. tostring(err))
	end
end

local function fmt(v)
	if type(v) == "string" then
		return string.format("%q", v)
	end
	return tostring(v)
end

function Test.expect(actual: any)
	local e = {}
	function e.toBe(expected)
		if actual ~= expected then
			error(string.format("expected %s to be %s", fmt(actual), fmt(expected)), 2)
		end
	end
	function e.toBeNear(expected, tolerance)
		local tol = tolerance or 1e-6
		if type(actual) ~= "number" or math.abs(actual - expected) > tol then
			error(string.format("expected %s to be within %s of %s", fmt(actual), fmt(tol), fmt(expected)), 2)
		end
	end
	function e.toBeTruthy()
		if not actual then
			error("expected value to be truthy, got " .. fmt(actual), 2)
		end
	end
	function e.toBeFalsy()
		if actual then
			error("expected value to be falsy, got " .. fmt(actual), 2)
		end
	end
	function e.toBeAtMost(limit)
		if not (actual <= limit) then
			error(string.format("expected %s <= %s", fmt(actual), fmt(limit)), 2)
		end
	end
	function e.toBeAtLeast(limit)
		if not (actual >= limit) then
			error(string.format("expected %s >= %s", fmt(actual), fmt(limit)), 2)
		end
	end
	function e.toContain(item)
		if type(actual) == "string" then
			if not string.find(actual, item, 1, true) then
				error(string.format("expected %s to contain %s", fmt(actual), fmt(item)), 2)
			end
			return
		end
		if not table.find(actual, item) then
			error("expected table to contain " .. fmt(item), 2)
		end
	end
	return e
end

function Test.results()
	return results
end

return Test
