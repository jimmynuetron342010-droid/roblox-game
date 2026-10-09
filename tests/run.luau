--[[
	Test runner: `lune run tests/run.luau` from the repository root
	(after `rojo sourcemap default.project.json --output sourcemap.json`).
	Optional argument filters spec files by substring.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local Test = require("./harness/Test")

local filter = process.args[1]

local specs = {}
for _, name in fs.readDir("tests/specs") do
	if string.match(name, "%.spec%.luau$") and (not filter or string.find(name, filter, 1, true)) then
		table.insert(specs, name)
	end
end
table.sort(specs)

for _, name in specs do
	print("\n\27[1m" .. name .. "\27[0m")
	local ok, err = pcall(function()
		require("./specs/" .. string.gsub(name, "%.luau$", ""))
	end)
	if not ok then
		print("\27[31mspec failed to load: " .. tostring(err) .. "\27[0m")
		Test.results().failed += 1
	end
end

local results = Test.results()
print(string.format("\n%d passed, %d failed", results.passed, results.failed))
if results.failed > 0 then
	process.exit(1)
end
