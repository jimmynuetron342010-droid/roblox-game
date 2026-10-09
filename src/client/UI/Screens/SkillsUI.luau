--[[
	SkillsUI
	  Abilities  — what every key does for the current build (weapon M1/Z/X, racial C, role V,
	               Kishin B) with cost, cooldown and why a slot is locked.
	  Build      — combat role (filtered by BuildRules so contradictory builds cannot be picked) and
	               magic school for Witch / Sorcerer origins.
	  Resonance  — Meister ⇄ Demon Weapon synchronization: compatibility with each player in the
	               server, invites, accept, leave.
	  Kishin     — Madness, Black Blood and the Kishin Awakening questline status (endgame; not a roll).
	All changes go through validated remotes; the server re-checks every rule.
]]

local Players = game:GetService("Players")

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local AbilityConfig = require(Modules.Config.AbilityConfig)
local AbilitySlots = require(Modules.Core.AbilitySlots)
local BuildRules = require(Modules.Config.BuildRules)
local CombatRoleConfig = require(Modules.Config.CombatRoleConfig)
local MagicConfig = require(Modules.Config.MagicConfig)
local MasteryConfig = require(Modules.Config.MasteryConfig)
local Net = require(Modules.Core.Net)
local QuestConfig = require(Modules.Config.QuestConfig)
local RaceConfig = require(Modules.Config.RaceConfig)
local StudentConfig = require(Modules.Config.StudentConfig)
local WeaponConfig = require(Modules.WeaponConfig)

local UI = script.Parent.Parent
local ClientState = require(UI.Parent.Controllers.ClientState)
local Components = require(UI.Components)
local Notifications = require(UI.Notifications)
local ScreenBase = require(UI.ScreenBase)
local Theme = require(UI.Theme)

local SkillsUI = {}
SkillsUI.__index = SkillsUI

local player = Players.LocalPlayer

local REASONS = {
	InCombat = "You can't change that during combat.",
	RoleNotAllowed = "Your origin can't use that role.",
	SchoolNotAllowed = "That school isn't available to you yet.",
	Incompatible = "Your builds can't synchronize (one Demon Weapon + one Meister required).",
	NoInvite = "That invite expired.",
	BadTarget = "That player is no longer here.",
	RateLimited = "Slow down a little.",
	NoStudent = "Create your student first.",
}

local LOCK_TEXT = {
	NoRace = "Roll an origin at the Soul Altar.",
	NoAbility = "This origin has no active ability.",
	Locked = "Locked",
}

local function prettyAttack(id: string): string
	local name = string.match(id, "_(.+)$") or id
	return (string.gsub(name, "(%l)(%u)", "%1 %2"))
end

local function invoke(name: string, ...)
	local args = table.pack(...)
	local ok, result = pcall(function()
		return Net.Function(name):InvokeServer(table.unpack(args, 1, args.n))
	end)
	if not ok or type(result) ~= "table" then
		return { Ok = false, Reason = "Network" }
	end
	return result
end

function SkillsUI.new(layer: Frame)
	local self = setmetatable({}, SkillsUI)
	self.BlocksInput = true
	local root, content = ScreenBase.Modal("Skills", "SKILLS", layer)
	self.Root = root
	self.Invites = {} :: { [number]: number } -- userId -> os.clock()

	local tabs = {
		{ Id = "Abilities", Text = "Abilities" },
		{ Id = "Build", Text = "Role & Magic" },
		{ Id = "Resonance", Text = "Resonance" },
		{ Id = "Kishin", Text = "Kishin Path" },
	}
	local _, selectTab = Components.Tabs(tabs, function(id)
		self.Tab = id
		self:Refresh()
	end, { Parent = content })
	self.Body =
		Components.Scroll({ Position = UDim2.fromOffset(0, 50), Size = UDim2.new(1, 0, 1, -50), Parent = content })
	Components.List(Enum.FillDirection.Vertical, 10).Parent = self.Body
	Components.Padding(4).Parent = self.Body
	self.SelectTab = selectTab
	self.Tab = "Abilities"

	ClientState.ProfileChanged:Connect(function()
		if root.Visible then
			self:Refresh()
		end
	end)
	-- Resonance invites arrive as notifications carrying the inviter's user id.
	Net.Event("Notify").OnClientEvent:Connect(function(payload)
		if type(payload) == "table" and type(payload.Invite) == "number" then
			self.Invites[payload.Invite] = os.clock()
			if root.Visible and self.Tab == "Resonance" then
				self:Refresh()
			end
		end
	end)
	return self
end

-- ── Helpers ───────────────────────────────────────────────────────────────────
local order = 0
local function nextOrder()
	order += 1
	return order
end

function SkillsUI:Heading(text: string, sub: string?)
	Components.Label(text, {
		Size = UDim2.new(1, -12, 0, 28),
		FontFace = Theme.Fonts.Hand,
		TextSize = 21,
		TextColor3 = Theme.Colors.Gold,
		LayoutOrder = nextOrder(),
		Parent = self.Body,
	})
	if sub then
		Components.Label(sub, {
			Size = UDim2.new(1, -12, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextSize = Theme.TextSize.Small,
			TextColor3 = Theme.Colors.TextMuted,
			LayoutOrder = nextOrder(),
			Parent = self.Body,
		})
	end
end

function SkillsUI:Card(
	title: string,
	body: string,
	opts: {
		Key: string?,
		Color: Color3?,
		Dim: boolean?,
		Button: string?,
		OnClick: (() -> ())?,
		Selected: boolean?,
	}?
)
	local o = opts or {}
	local card = Components.Panel({
		Size = UDim2.new(1, -12, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = o.Selected and Theme.Colors.InkLighter or Theme.Colors.InkLight,
		LayoutOrder = nextOrder(),
		Parent = self.Body,
	})
	Components.Padding(10, 14).Parent = card
	local stroke = card:FindFirstChildOfClass("UIStroke")
	if stroke and o.Selected then
		stroke.Color = Theme.Colors.Gold
		stroke.Thickness = 2.5
	end
	local textLeft = 0
	if o.Key then
		local key =
			Components.Panel({ Size = UDim2.fromOffset(46, 46), BackgroundColor3 = Theme.Colors.Ink, Parent = card })
		Components.Label(o.Key, {
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			FontFace = Theme.Fonts.Display,
			TextSize = 24,
			TextColor3 = o.Color or Theme.Colors.Gold,
			Parent = key,
		})
		textLeft = 58
	end
	local buttonWidth = o.Button and 150 or 0
	local text = Components.New("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(textLeft, 0),
		Size = UDim2.new(1, -textLeft - buttonWidth - 8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = card,
	})
	Components.List(Enum.FillDirection.Vertical, 2).Parent = text
	Components.Label(title, {
		Size = UDim2.new(1, 0, 0, 22),
		FontFace = Theme.Fonts.BodyBold,
		TextColor3 = o.Dim and Theme.Colors.TextMuted or (o.Color or Theme.Colors.Text),
		LayoutOrder = 1,
		Parent = text,
	})
	Components.Label(body, {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		RichText = true,
		TextSize = Theme.TextSize.Small,
		TextColor3 = o.Dim and Theme.Colors.TextMuted or Theme.Colors.TextDim,
		LayoutOrder = 2,
		Parent = text,
	})
	if o.Button then
		Components.Button(o.Button, o.OnClick, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromOffset(140, 40),
			TextSize = Theme.TextSize.Small,
			Parent = card,
		}, o.Selected and "Ghost" or "Primary")
	end
	return card
end

function SkillsUI:Do(remote: string, ...)
	local result = invoke(remote, ...)
	if not result.Ok then
		Notifications.Show(REASONS[result.Reason] or ("Couldn't do that: " .. tostring(result.Reason)), "Warning")
	end
	return result
end

-- ── Tabs ──────────────────────────────────────────────────────────────────────
function SkillsUI:Abilities(profile)
	local weapon = WeaponConfig.Resolve(profile.Loadout.Weapon, profile.Loadout.TsubakiForm)
	self:Heading("Weapon", weapon and weapon.DisplayName or "")
	if weapon then
		local combo = {}
		for _, attackId in weapon.Moveset.M1 do
			table.insert(combo, prettyAttack(attackId))
		end
		self:Card(
			"Combo",
			table.concat(combo, " → ") .. "\nTap or hold attack. The combo resets if you pause too long.",
			{ Key = "M1" }
		)
		for _, key in { "Z", "X" } do
			local attackId = weapon.Moveset[key]
			local attack = attackId and WeaponConfig.Attacks[attackId]
			if attack then
				self:Card(
					prettyAttack(attackId),
					string.format("Stamina %d · Weapon technique", attack.Stamina or 0),
					{ Key = key }
				)
			end
		end
	end
	self:Heading("Soul Abilities", "Costs are Soul Energy; cooldowns are reduced by Cooldown Reduction (capped).")
	for _, slot in AbilitySlots.Slots do
		local abilityId, stage, reason = AbilitySlots.Resolve(profile, slot)
		if abilityId then
			local ability, _, name, description = AbilityConfig.Resolve(abilityId, stage)
			if ability then
				self:Card(
					name,
					string.format(
						"%s\n<b>%d</b> Soul Energy · <b>%d s</b> cooldown",
						description,
						AbilityConfig.CostFor(abilityId, stage),
						ability.Cooldown
					),
					{
						Key = slot,
						Color = AbilityConfig.Colors[abilityId],
					}
				)
			end
		else
			local why = LOCK_TEXT[reason or ""] or "Locked"
			if slot == "C" and reason == "Locked" then
				local race = RaceConfig.ById[profile.Race.Active]
				why = race
						and string.format(
							"%s's ability unlocks at Mastery %s.",
							race.DisplayName,
							MasteryConfig.StageNumerals[race.AbilityUnlockStage]
						)
					or why
			elseif slot == "B" then
				why = "Kishin Awakening — complete the Kishin Path questline (endgame)."
			end
			self:Card(
				slot == "C" and "Racial ability" or (slot == "B" and "Kishin Awakening" or "Technique"),
				why,
				{ Key = slot, Dim = true }
			)
		end
	end
	self:Heading("Movement")
	self:Card("Dash", "Q / L2 — quick dodge with brief invulnerability. Costs stamina.", { Key = "Q" })
	self:Card("Sprint", "Shift (hold) / L3 (toggle). Drains stamina.", { Key = "⇧" })
	self:Card(
		"Soul Perception",
		"G / D-Pad Down — see souls through walls, reveal hidden Kishin Eggs.",
		{ Key = "G" }
	)
end

function SkillsUI:Build(profile)
	local raceId = profile.Race.Active ~= "" and profile.Race.Active or nil
	local race = raceId and RaceConfig.ById[raceId]
	self:Heading(
		"Combat Role",
		"How you fight. Independent from your origin, weapon and magic — but some origins limit the choice."
	)
	for _, roleId in { "Meister", "Assassin", "Technician", "PartnerWeapon" } do
		local role = CombatRoleConfig.ById[roleId]
		local allowed = BuildRules.IsRoleAllowed(raceId, roleId)
		local current = profile.Loadout.Role == roleId
		local body = role.Description
		if not allowed then
			body ..= "\n" .. (roleId == "PartnerWeapon" and "Requires the Demon Weapon origin." or ((race and race.DisplayName or "Your origin") .. " can't take this role."))
		end
		local _, _, techName = AbilityConfig.Resolve(role.TechniqueId, 1)
		body ..= "\nTechnique [V]: " .. techName
		self:Card(role.DisplayName, body, {
			Dim = not allowed,
			Selected = current,
			Button = allowed and (current and "Current" or "Choose") or nil,
			OnClick = function()
				if not current then
					self:Do("SetLoadout", "Role", roleId)
				end
			end,
		})
	end
	if BuildRules.CanUseMagic(raceId) then
		self:Heading("Magic School", "Decides what your racial magic ability casts.")
		for _, school in MagicConfig.SchoolsForRace(raceId) do
			local unlocked = profile.Level >= school.UnlockLevel
			local current = profile.Loadout.School == school.Id
			self:Card(
				school.DisplayName,
				school.Description
					.. (unlocked and "" or string.format("\nUnlocks at level %d.", school.UnlockLevel))
					.. "\n<i>"
					.. school.Lore
					.. "</i>",
				{
					Color = school.Color,
					Dim = not unlocked,
					Selected = current,
					Button = unlocked and (current and "Current" or "Choose") or nil,
					OnClick = function()
						if not current then
							self:Do("SetLoadout", "School", school.Id)
						end
					end,
				}
			)
		end
	else
		self:Heading("Magic School", "Only Witch and Sorcerer origins can learn a school of magic.")
	end
end

function SkillsUI:Resonance(profile)
	local myRace = profile.Race.Active
	local myRole = profile.Loadout.Role
	local myWave = profile.Student.Wavelength
	self:Heading(
		"Soul Resonance",
		"A Demon Weapon origin synchronizes with a Meister-role partner. Bonuses scale with wavelength compatibility while you stay close together."
	)
	local partnerId = player:GetAttribute("PartnerId")
	if partnerId then
		local partner = Players:GetPlayerByUserId(partnerId)
		local sync = player:GetAttribute("SyncLevel")
		self:Card(
			"Partner: " .. (partner and partner.DisplayName or "—"),
			sync and string.format("Synchronized · compatibility %d%%", math.floor(sync * 100))
				or "Out of range — move closer to synchronize.",
			{
				Selected = true,
				Button = "Leave",
				OnClick = function()
					self:Do("PartnerAction", "Leave")
					self:Refresh()
				end,
			}
		)
	end
	local any = false
	for _, other in Players:GetPlayers() do
		if other ~= player and other:GetAttribute("StudentCreated") then
			any = true
			local theirWave = other:GetAttribute("Wavelength")
			local compat = StudentConfig.Compatibility(myWave, theirWave)
			local theirRace = other:GetAttribute("Race")
			local theirRole = other:GetAttribute("Role")
			local can = BuildRules.CanSynchronize(myRace, myRole, theirRace, theirRole)
			local invited = self.Invites[other.UserId] and os.clock() - self.Invites[other.UserId] < 60
			local race = RaceConfig.ById[theirRace or ""]
			local body = string.format(
				"%s · %s · %s wavelength · compatibility <b>%d%%</b>",
				race and race.DisplayName or "Unawakened",
				theirRole or "—",
				theirWave or "?",
				math.floor(compat * 100)
			)
			if not can then
				body ..= "\nCan't synchronize with your current build."
			end
			self:Card(other.DisplayName, body, {
				Dim = not can,
				Button = can and (invited and "Accept" or "Invite") or nil,
				OnClick = function()
					if invited then
						if self:Do("PartnerAction", "Accept", other.UserId).Ok then
							self.Invites[other.UserId] = nil
						end
					else
						local result = self:Do("PartnerAction", "Invite", other.UserId)
						if result.Ok then
							Notifications.Show("Invite sent to " .. other.DisplayName .. ".", "Info")
						end
					end
					self:Refresh()
				end,
			})
		end
	end
	if not any then
		self:Card("No other students here", "Invite a friend to the server to try Soul Resonance.", { Dim = true })
	end
end

function SkillsUI:Kishin(profile)
	local madness = player:GetAttribute("Madness") or 0
	self:Heading(
		"Madness",
		"Madness rises inside a Madness Wraith's wavelength and decays once you leave it. At 50+ you deal 8% more damage but take 10% more; at 80+ it is 12% / 15%."
	)
	self:Card(
		string.format("Madness: %d / 100", madness),
		madness >= 80 and "Your wavelength is breaking apart."
			or (madness >= 50 and "Your wavelength is unstable." or "Your soul is steady."),
		{ Color = Theme.Colors.Madness }
	)
	self:Heading("Black Blood", "A status and progression system — not a race. Earned through the Kishin Path.")
	self:Card(
		profile.Unlocks.BlackBlood and "Black Blood: awakened" or "Black Blood: sealed",
		profile.Unlocks.BlackBlood
				and "Below 40% health your blood hardens: +30% Defense for 5 s (30 s cooldown), at the cost of +10 Madness."
			or "Complete “Whispers of Madness” to awaken it.",
		{
			Color = Theme.Colors.Red,
			Dim = not profile.Unlocks.BlackBlood,
		}
	)
	self:Heading(
		"The Kishin Path",
		"Kishin are beings who devoured human souls and lost themselves to madness. This endgame questline lets you borrow that power for a moment — you never become one."
	)
	for _, quest in QuestConfig.List do
		if quest.Chain == "Kishin" then
			local done = profile.Quests.Completed[quest.Id] ~= nil
			local active = profile.Quests.Active == quest.Id
			local status = done and "✓ Complete"
				or (
					active and string.format("In progress (%d/%d)", profile.Quests.Progress, quest.Count)
					or "Not started"
				)
			if quest.RequiresLevel and profile.Level < quest.RequiresLevel and not done then
				status ..= string.format(" · requires level %d", quest.RequiresLevel)
			end
			self:Card(
				quest.Title,
				quest.Description .. "\n<b>" .. status .. "</b>",
				{ Dim = not (done or active), Selected = active }
			)
		end
	end
	local _, _, name, description = AbilityConfig.Resolve("KishinAwakening", 1)
	self:Card(
		name .. " [B]",
		description,
		{ Key = "B", Color = Theme.Colors.Red, Dim = not profile.Unlocks.KishinAwakening }
	)
end

function SkillsUI:Refresh()
	local profile = ClientState.Profile
	if not profile then
		return
	end
	ScreenBase.ClearChildren(self.Body)
	order = 0
	if self.Tab == "Abilities" then
		self:Abilities(profile)
	elseif self.Tab == "Build" then
		self:Build(profile)
	elseif self.Tab == "Resonance" then
		self:Resonance(profile)
	else
		self:Kishin(profile)
	end
end

function SkillsUI:Open(args)
	ScreenBase.Show(self.Root)
	self.SelectTab(args and args.Tab or self.Tab)
end

function SkillsUI:Close()
	ScreenBase.Hide(self.Root)
end

return SkillsUI
