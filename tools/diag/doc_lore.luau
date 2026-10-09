-- Prints the in-game LoreCodex as markdown (used for docs/LORE.md).
local Loader = require("../../tests/harness/Loader")
local loader = Loader.new({ IsServer = false })
local LoreCodex = loader.RequirePath("ReplicatedStorage.Modules.Config.LoreCodex")
local WeaponConfig = loader.RequirePath("ReplicatedStorage.Modules.WeaponConfig")
for _, entry in LoreCodex.List do
	print("### " .. entry.Title)
	print("*" .. entry.System .. "*\n")
	print("| Canon (Soul Eater) | This game (original interpretation) |")
	print("|---|---|")
	local rows = math.max(#entry.Canon, #entry.Game)
	for i = 1, rows do
		print(string.format("| %s | %s |", entry.Canon[i] or "", entry.Game[i] or ""))
	end
	print("")
end
print("### Weapon notes\n")
print("| Weapon | Note |")
print("|---|---|")
for _, id in WeaponConfig.Order do
	print(string.format("| %s | %s |", WeaponConfig.Weapons[id].DisplayName, LoreCodex.WeaponNotes[id] or ""))
end
