--[[
	Server bootstrap
	Requires every service, then runs Init (wire references, no yielding) followed by Start
	(connect events, begin loops) in a fixed order. Services find each other through the
	registry passed to Init, so there are no circular requires.
]]

local Services = script.Parent:WaitForChild("Services")

local ORDER = {
	"DataService",
	"StatusService",
	"StatService",
	"ProgressionService",
	"MapService",
	"CharacterService",
	"WeaponService",
	"RaceService",
	"MasteryService",
	"QuestService",
	"LoadoutService",
	"PartnerService",
	"MadnessService",
	"CombatService",
	"AbilityService",
	"EnemyService",
}

local registry = {}
for _, name in ORDER do
	local module = Services:FindFirstChild(name)
	assert(module, "Missing service " .. name)
	registry[name] = require(module) :: any
end

for _, name in ORDER do
	local service = registry[name]
	if service.Init then
		service:Init(registry)
	end
end

for _, name in ORDER do
	local service = registry[name]
	if service.Start then
		task.spawn(function()
			local ok, err = pcall(service.Start, service)
			if not ok then
				warn(string.format("[Server] %s failed to start: %s", name, tostring(err)))
			end
		end)
	end
end

print("[Server] Soul Eater RPG services started")
