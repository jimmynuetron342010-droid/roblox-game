--[[
	DamageNumbers
	Pooled floating numbers above hit targets (server-confirmed DamageFeedback only).
	Can be disabled in Settings; capped for performance.
]]

local Players = game:GetService("Players")

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local Net = require(Modules.Core.Net)
local VFXConfig = require(Modules.VFXConfig)

local ClientState = require(script.Parent.Parent.Controllers.ClientState)
local Theme = require(script.Parent.Theme)

local DamageNumbers = {}

local pool: { BillboardGui } = {}
local active = 0
local holder: Folder

local function acquire(): BillboardGui
	local gui = table.remove(pool)
	if gui then
		return gui
	end
	local b = Instance.new("BillboardGui")
	b.Size = UDim2.fromOffset(120, 44)
	b.AlwaysOnTop = true
	b.LightInfluence = 0
	b.MaxDistance = 140
	local label = Instance.new("TextLabel")
	label.Name = "Value"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.FontFace = Theme.Fonts.Display
	label.TextScaled = true
	label.TextStrokeTransparency = 0.2
	label.Parent = b
	return b
end

local function release(gui: BillboardGui)
	gui.Adornee = nil :: any
	gui.Parent = nil :: any
	active -= 1
	table.insert(pool, gui)
end

function DamageNumbers.Show(position: Vector3, amount: number, kind: string)
	if active >= VFXConfig.DamageNumbers.MaxVisible then
		return
	end
	local profile = ClientState.Profile
	if profile and profile.Settings.DamageNumbers == false then
		return
	end
	active += 1
	local gui = acquire()
	local anchor = Instance.new("Attachment")
	local terrain = workspace.Terrain
	anchor.WorldPosition = position + Vector3.new((math.random() - 0.5) * 1.5, 0, (math.random() - 0.5) * 1.5)
	anchor.Parent = terrain
	gui.Adornee = anchor
	local label = gui:FindFirstChild("Value") :: TextLabel
	label.Text = tostring(math.floor(amount + 0.5))
	label.TextColor3 = kind == "Taken" and Theme.Colors.Bad
		or (kind == "Magic" and Color3.fromRGB(190, 150, 255) or Theme.Colors.Text)
	label.TextTransparency = 0
	gui.Parent = holder
	local rise = VFXConfig.DamageNumbers.Rise
	local lifetime = VFXConfig.DamageNumbers.Lifetime
	local start = os.clock()
	task.spawn(function()
		while os.clock() - start < lifetime do
			local alpha = (os.clock() - start) / lifetime
			gui.StudsOffsetWorldSpace = Vector3.new(0, rise * (1 - (1 - alpha) ^ 2), 0)
			label.TextTransparency = math.max(0, (alpha - 0.6) / 0.4)
			task.wait()
		end
		anchor:Destroy()
		release(gui)
	end)
end

function DamageNumbers.Mount()
	local folder = Instance.new("Folder")
	folder.Name = "DamageNumbers"
	folder.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	holder = folder
	Net.Event("DamageFeedback").OnClientEvent:Connect(function(payload)
		if type(payload) == "table" and typeof(payload.Position) == "Vector3" and type(payload.Amount) == "number" then
			DamageNumbers.Show(payload.Position, payload.Amount, payload.Kind)
		end
	end)
end

return DamageNumbers
