--[[
	MockInstance (Lune)
	A strict, pure-Lua stand-in for Roblox Instances so the real client UI code can run headless.

	Strict on purpose — it reproduces the errors Roblox would throw:
	  * Instance.new of an unknown / non-creatable class
	  * reading or writing a member that does not exist ("X is not a valid member of Y")
	  * writing a read-only property, or a value of the wrong type (incl. wrong Enum type)
	  * GetPropertyChangedSignal on a non-existent property
	Member and type information comes from the Roblox API dump (tests/ui/api-dump.min.json.gz).

	Events are real signals (Activated, InputBegan, GetPropertyChangedSignal, ...), so tests can
	click buttons and type into TextBoxes. Handler errors are collected in MockInstance.Errors.
]]

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local task = require("@lune/task")

local MockInstance = {}
MockInstance.Errors = {} :: { string }

local api = serde.decode("json", serde.decompress("gzip", fs.readFile("tests/ui/api-dump.min.json.gz")))
MockInstance.Api = api

local Color3, UDim2, UDim, Vector2, Font = roblox.Color3, roblox.UDim2, roblox.UDim, roblox.Vector2, roblox.Font
local Enum = roblox.Enum

-- ── Signals ───────────────────────────────────────────────────────────────────
local Signal = {}
Signal.__index = Signal

function Signal.new(name: string?)
	return setmetatable({ _handlers = {}, _waiting = {}, _name = name or "Signal" }, Signal)
end

function Signal:Connect(fn)
	assert(type(fn) == "function", "Connect expects a function")
	local connection = { Connected = true }
	local entry = { Fn = fn, Connection = connection }
	table.insert(self._handlers, entry)
	function connection.Disconnect()
		connection.Connected = false
		local index = table.find(self._handlers, entry)
		if index then
			table.remove(self._handlers, index)
		end
	end
	connection.disconnect = connection.Disconnect
	return setmetatable(connection, {
		__index = function(_, key)
			if key == "Disconnect" then
				return connection.Disconnect
			end
			return nil
		end,
	})
end

function Signal:Once(fn)
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		fn(...)
	end)
	return connection
end

function Signal:Wait()
	local thread = coroutine.running()
	table.insert(self._waiting, thread)
	return coroutine.yield()
end

function Signal:Fire(...)
	for _, entry in table.clone(self._handlers) do
		if entry.Connection.Connected then
			local args = table.pack(...)
			task.spawn(function()
				local ok, err = xpcall(entry.Fn, debug.traceback, table.unpack(args, 1, args.n))
				if not ok then
					table.insert(MockInstance.Errors, string.format("[%s handler] %s", self._name, tostring(err)))
				end
			end)
		end
	end
	local waiting = self._waiting
	self._waiting = {}
	for _, thread in waiting do
		task.spawn(thread, ...)
	end
end

MockInstance.Signal = Signal

-- ── API helpers ───────────────────────────────────────────────────────────────
local memberCache: { [string]: any } = {}

local function classInfo(className: string)
	return api.Classes[className]
end

local function lookup(className: string)
	local cached = memberCache[className]
	if cached then
		return cached
	end
	local props, events, funcs = {}, {}, {}
	local chain = {}
	local name = className
	while name and name ~= "<<<ROOT>>>" do
		local info = classInfo(name)
		if not info then
			break
		end
		table.insert(chain, name)
		for prop, def in info.P do
			if props[prop] == nil then
				props[prop] = def
			end
		end
		for _, event in info.E do
			events[event] = true
		end
		for _, fn in info.F do
			funcs[fn] = true
		end
		name = info.S
	end
	cached = { Props = props, Events = events, Funcs = funcs, Chain = chain }
	memberCache[className] = cached
	return cached
end

function MockInstance.IsA(className: string, target: string): boolean
	return table.find(lookup(className).Chain, target) ~= nil
end

-- ── Defaults (values Roblox gives a fresh Instance.new) ───────────────────────
local LEGACY_FONT = Font.new("rbxasset://fonts/families/LegacyArial.json")
local DEFAULTS = {
	GuiObject = {
		BackgroundColor3 = Color3.fromRGB(163, 162, 165),
		BackgroundTransparency = 0,
		BorderColor3 = Color3.fromRGB(27, 42, 53),
		BorderSizePixel = 1,
		Size = UDim2.fromOffset(100, 100),
		Visible = true,
		ZIndex = 1,
		AutomaticSize = Enum.AutomaticSize.None,
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.new(),
		Rotation = 0,
		ClipsDescendants = false,
		LayoutOrder = 0,
		Active = false,
		Selectable = false,
	},
	GuiButton = { AutoButtonColor = true, Active = true, Selectable = true },
	TextLabel = { Text = "Label", Size = UDim2.fromOffset(200, 50) },
	TextButton = { Text = "Button", Size = UDim2.fromOffset(200, 50) },
	TextBox = {
		Text = "TextBox",
		Size = UDim2.fromOffset(200, 50),
		TextEditable = true,
		ClearTextOnFocus = true,
		Active = true,
		Selectable = true,
	},
	TextCommon = {
		TextColor3 = Color3.fromRGB(27, 42, 53),
		TextSize = 14,
		FontFace = LEGACY_FONT,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = false,
		TextScaled = false,
		RichText = false,
		TextTransparency = 0,
		TextStrokeTransparency = 1,
		TextStrokeColor3 = Color3.new(0, 0, 0),
		TextTruncate = Enum.TextTruncate.None,
		LineHeight = 1,
	},
	ImageLabel = {
		Image = "",
		ImageColor3 = Color3.new(1, 1, 1),
		ImageTransparency = 0,
		ScaleType = Enum.ScaleType.Stretch,
	},
	ImageButton = {
		Image = "",
		ImageColor3 = Color3.new(1, 1, 1),
		ImageTransparency = 0,
		ScaleType = Enum.ScaleType.Stretch,
	},
	ScrollingFrame = {
		CanvasSize = UDim2.fromScale(0, 2),
		ScrollBarThickness = 12,
		AutomaticCanvasSize = Enum.AutomaticSize.None,
		ScrollingDirection = Enum.ScrollingDirection.XY,
		CanvasPosition = Vector2.new(0, 0),
		ScrollingEnabled = true,
	},
	ViewportFrame = { Ambient = Color3.fromRGB(200, 200, 200), LightColor = Color3.fromRGB(140, 140, 140) },
	UIListLayout = {
		FillDirection = Enum.FillDirection.Vertical,
		Padding = UDim.new(0, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		Wraps = false,
	},
	UIGridLayout = {
		CellSize = UDim2.fromOffset(100, 100),
		CellPadding = UDim2.fromOffset(5, 5),
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		FillDirectionMaxCells = 0,
	},
	UIPadding = {
		PaddingTop = UDim.new(),
		PaddingBottom = UDim.new(),
		PaddingLeft = UDim.new(),
		PaddingRight = UDim.new(),
	},
	UICorner = { CornerRadius = UDim.new(0, 8) },
	UIStroke = {
		Color = Color3.new(0, 0, 0),
		Thickness = 1,
		Transparency = 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		Enabled = true,
	},
	UIScale = { Scale = 1 },
	UIGradient = {
		Color = roblox.ColorSequence.new(Color3.new(1, 1, 1)),
		Rotation = 0,
		Transparency = roblox.NumberSequence.new(0),
		Offset = Vector2.new(0, 0),
		Enabled = true,
	},
	UISizeConstraint = { MinSize = Vector2.new(0, 0), MaxSize = Vector2.new(math.huge, math.huge) },
	UIAspectRatioConstraint = { AspectRatio = 1 },
	ScreenGui = { Enabled = true, ResetOnSpawn = true, IgnoreGuiInset = false, DisplayOrder = 0 },
	Sound = { Volume = 0.5, PlaybackSpeed = 1, SoundId = "" },
}

local function genericDefault(def)
	local category, typeName = def[1], def[2]
	if category == "Primitive" then
		if typeName == "bool" then
			return false
		elseif typeName == "string" then
			return ""
		end
		return 0
	elseif category == "DataType" then
		if typeName == "UDim2" then
			return UDim2.new()
		elseif typeName == "UDim" then
			return UDim.new()
		elseif typeName == "Vector2" then
			return Vector2.new(0, 0)
		elseif typeName == "Vector3" then
			return roblox.Vector3.new(0, 0, 0)
		elseif typeName == "Color3" then
			return Color3.new(0, 0, 0)
		elseif typeName == "CFrame" then
			return roblox.CFrame.new()
		elseif typeName == "Content" then
			return ""
		elseif typeName == "Font" then
			return LEGACY_FONT
		end
		return nil
	elseif category == "Enum" then
		local items = api.Enums[typeName]
		local enumType = (Enum :: any)[typeName]
		return items and enumType and enumType[items[1]] or nil
	end
	return nil
end

local function defaultFor(className: string, prop: string, def)
	for _, name in lookup(className).Chain do
		local defaults = DEFAULTS[name]
		if defaults and defaults[prop] ~= nil then
			return defaults[prop]
		end
	end
	if
		MockInstance.IsA(className, "TextLabel")
		or MockInstance.IsA(className, "TextButton")
		or MockInstance.IsA(className, "TextBox")
	then
		if DEFAULTS.TextCommon[prop] ~= nil then
			return DEFAULTS.TextCommon[prop]
		end
	end
	return genericDefault(def)
end

-- ── Instances ─────────────────────────────────────────────────────────────────
local instanceMeta = {}
local isMock = setmetatable({}, { __mode = "k" })

function MockInstance.Is(value: any): boolean
	return type(value) == "table" and isMock[value] == true
end

local function describe(self)
	return string.format('%s "%s"', rawget(self, "_class"), rawget(self, "_props").Name or "?")
end

local function typeError(self, prop: string, expected: string, value: any)
	error(
		string.format(
			"Unable to assign property %s. %s expected, got %s (%s)",
			prop,
			expected,
			MockInstance.TypeOf(value),
			describe(self)
		),
		3
	)
end

function MockInstance.TypeOf(value: any): string
	if MockInstance.Is(value) then
		return "Instance"
	end
	return typeof(value)
end

local function enumTypeName(value: any): string?
	if typeof(value) ~= "EnumItem" then
		return nil
	end
	return string.match(tostring(value), "^Enum%.([^%.]+)%.")
end

local function validate(self, prop: string, def, value: any)
	local category, typeName = def[1], def[2]
	if category == "Class" then
		if value ~= nil and not (MockInstance.Is(value) and MockInstance.IsA(rawget(value, "_class"), typeName)) then
			typeError(self, prop, typeName, value)
		end
		return
	end
	if value == nil then
		typeError(self, prop, typeName, value)
	end
	if category == "Primitive" then
		local expected = (typeName == "bool" and "boolean") or (typeName == "string" and "string") or "number"
		if type(value) ~= expected then
			typeError(self, prop, expected, value)
		end
		if expected == "number" and value ~= value then
			typeError(self, prop, "number (not NaN)", value)
		end
	elseif category == "DataType" then
		if typeName == "Content" then
			if type(value) ~= "string" then
				typeError(self, prop, "Content (string)", value)
			end
		elseif typeof(value) ~= typeName then
			typeError(self, prop, typeName, value)
		end
	elseif category == "Enum" then
		if enumTypeName(value) ~= typeName then
			typeError(self, prop, "Enum." .. typeName, value)
		end
	elseif category == "Callback" then
		if type(value) ~= "function" and value ~= nil then
			typeError(self, prop, "function", value)
		end
	end
end

local methods = {}

local function children(self)
	return rawget(self, "_children")
end

local function fireIf(self, eventName: string, ...)
	local events = rawget(self, "_events")
	local signal = events[eventName]
	if signal then
		signal:Fire(...)
	end
end

local function propertyChanged(self, prop: string)
	local propSignals = rawget(self, "_propSignals")
	if propSignals[prop] then
		propSignals[prop]:Fire()
	end
	fireIf(self, "Changed", prop)
end

local function setParent(self, parent)
	if parent ~= nil and not MockInstance.Is(parent) then
		error(
			string.format(
				"Unable to assign property Parent. Instance expected, got %s (%s)",
				typeof(parent),
				describe(self)
			),
			3
		)
	end
	if rawget(self, "_destroyed") then
		error("The Parent property of " .. describe(self) .. " is locked (destroyed)", 3)
	end
	local node = parent
	while node do
		if node == self then
			error("Attempt to set parent of " .. describe(self) .. " to itself or a descendant", 3)
		end
		node = rawget(node, "_parent")
	end
	local old = rawget(self, "_parent")
	if old == parent then
		return
	end
	if old then
		local list = children(old)
		local index = table.find(list, self)
		if index then
			table.remove(list, index)
		end
		fireIf(old, "ChildRemoved", self)
	end
	rawset(self, "_parent", parent)
	if parent then
		table.insert(children(parent), self)
		fireIf(parent, "ChildAdded", self)
	end
	propertyChanged(self, "Parent")
	fireIf(self, "AncestryChanged", self, parent)
end

function MockInstance.new(className: string, parent: any?, internal: boolean?)
	local info = classInfo(className)
	if not info then
		error(string.format('Unable to create an Instance of type "%s"', tostring(className)), 2)
	end
	if not internal then
		for _, tag in info.T do
			if tag == "NotCreatable" or tag == "Service" then
				error(string.format('Unable to create an Instance of type "%s"', className), 2)
			end
		end
	end
	local self = setmetatable({
		_class = className,
		_props = { Name = className },
		_children = {},
		_events = {},
		_propSignals = {},
		_attributes = {},
		_attrSignals = {},
		_methods = {},
		_parent = nil,
	}, instanceMeta)
	isMock[self] = true
	if parent ~= nil then
		setParent(self, parent)
	end
	return self
end

instanceMeta.__index = function(self, key)
	if key == "ClassName" then
		return rawget(self, "_class")
	elseif key == "Name" then
		return rawget(self, "_props").Name
	elseif key == "Parent" then
		return rawget(self, "_parent")
	end
	local override = rawget(self, "_methods")[key]
	if override ~= nil then
		return override
	end
	local method = methods[key]
	if method then
		return method
	end
	local members = lookup(rawget(self, "_class"))
	local def = members.Props[key]
	if def then
		local props = rawget(self, "_props")
		local value = props[key]
		if value == nil and def[1] ~= "Class" then
			value = defaultFor(rawget(self, "_class"), key, def)
		end
		return value
	end
	if members.Events[key] then
		local events = rawget(self, "_events")
		if not events[key] then
			events[key] = Signal.new(rawget(self, "_class") .. "." .. key)
		end
		return events[key]
	end
	if members.Funcs[key] then
		return function()
			error(
				string.format(
					"MockInstance: %s:%s() is not implemented in the test harness",
					rawget(self, "_class"),
					key
				),
				2
			)
		end
	end
	for _, child in children(self) do
		if rawget(child, "_props").Name == key then
			return child
		end
	end
	error(string.format("%s is not a valid member of %s", tostring(key), describe(self)), 2)
end

instanceMeta.__newindex = function(self, key, value)
	if key == "Parent" then
		setParent(self, value)
		return
	elseif key == "Name" then
		if type(value) ~= "string" then
			typeError(self, "Name", "string", value)
		end
		rawget(self, "_props").Name = value
		propertyChanged(self, "Name")
		return
	elseif key == "ClassName" then
		error("Unable to assign property ClassName. Property is read only", 2)
	end
	local members = lookup(rawget(self, "_class"))
	local def = members.Props[key]
	if not def then
		error(string.format("%s is not a valid member of %s", tostring(key), describe(self)), 2)
	end
	if def[3] == 1 and not MockInstance.AllowReadOnly then
		error(string.format("Unable to assign property %s. Property is read only (%s)", key, describe(self)), 2)
	end
	validate(self, key, def, value)
	local props = rawget(self, "_props")
	if props[key] == value and value ~= nil then
		return
	end
	props[key] = value
	propertyChanged(self, key)
end

instanceMeta.__tostring = function(self)
	return rawget(self, "_props").Name
end

-- Sets a read-only property from harness code (e.g. Camera.ViewportSize, Player.UserId).
function MockInstance.SetInternal(self, key: string, value: any)
	MockInstance.AllowReadOnly = true
	local ok, err = pcall(function()
		self[key] = value
	end)
	MockInstance.AllowReadOnly = false
	if not ok then
		error(err, 2)
	end
end

-- ── Methods ───────────────────────────────────────────────────────────────────
function methods.FindFirstChild(self, name: string, recursive: boolean?)
	for _, child in children(self) do
		if rawget(child, "_props").Name == name then
			return child
		end
	end
	if recursive then
		for _, child in children(self) do
			local found = methods.FindFirstChild(child, name, true)
			if found then
				return found
			end
		end
	end
	return nil
end

function methods.FindFirstChildOfClass(self, className: string)
	for _, child in children(self) do
		if rawget(child, "_class") == className then
			return child
		end
	end
	return nil
end

function methods.FindFirstChildWhichIsA(self, className: string, recursive: boolean?)
	for _, child in children(self) do
		if MockInstance.IsA(rawget(child, "_class"), className) then
			return child
		end
	end
	if recursive then
		for _, child in children(self) do
			local found = methods.FindFirstChildWhichIsA(child, className, true)
			if found then
				return found
			end
		end
	end
	return nil
end

function methods.FindFirstAncestorOfClass(self, className: string)
	local node = rawget(self, "_parent")
	while node do
		if rawget(node, "_class") == className then
			return node
		end
		node = rawget(node, "_parent")
	end
	return nil
end

function methods.FindFirstAncestorWhichIsA(self, className: string)
	local node = rawget(self, "_parent")
	while node do
		if MockInstance.IsA(rawget(node, "_class"), className) then
			return node
		end
		node = rawget(node, "_parent")
	end
	return nil
end

function methods.FindFirstAncestor(self, name: string)
	local node = rawget(self, "_parent")
	while node do
		if rawget(node, "_props").Name == name then
			return node
		end
		node = rawget(node, "_parent")
	end
	return nil
end

function methods.WaitForChild(self, name: string, timeout: number?)
	local deadline = os.clock() + (timeout or 2)
	repeat
		local child = methods.FindFirstChild(self, name)
		if child then
			return child
		end
		task.wait()
	until os.clock() > deadline
	if timeout then
		return nil
	end
	error(string.format("Infinite yield: %s:WaitForChild(%q) — child never appeared", describe(self), name), 2)
end

function methods.GetChildren(self)
	return table.clone(children(self))
end

function methods.GetDescendants(self)
	local out = {}
	local function walk(node)
		for _, child in children(node) do
			table.insert(out, child)
			walk(child)
		end
	end
	walk(self)
	return out
end

function methods.IsA(self, className: string): boolean
	return MockInstance.IsA(rawget(self, "_class"), className)
end

function methods.IsDescendantOf(self, ancestor): boolean
	local node = rawget(self, "_parent")
	while node do
		if node == ancestor then
			return true
		end
		node = rawget(node, "_parent")
	end
	return false
end

function methods.IsAncestorOf(self, descendant): boolean
	return methods.IsDescendantOf(descendant, self)
end

function methods.GetFullName(self): string
	local parts = {}
	local node = self
	while node do
		table.insert(parts, 1, rawget(node, "_props").Name)
		node = rawget(node, "_parent")
	end
	return table.concat(parts, ".")
end

function methods.Destroy(self)
	if rawget(self, "_destroyed") then
		return
	end
	fireIf(self, "Destroying")
	for _, child in table.clone(children(self)) do
		methods.Destroy(child)
	end
	setParent(self, nil)
	rawset(self, "_destroyed", true)
end

function methods.ClearAllChildren(self)
	for _, child in table.clone(children(self)) do
		methods.Destroy(child)
	end
end

function methods.Clone(self)
	local copy = MockInstance.new(rawget(self, "_class"), nil, true)
	for key, value in rawget(self, "_props") do
		rawget(copy, "_props")[key] = value
	end
	for key, value in rawget(self, "_attributes") do
		rawget(copy, "_attributes")[key] = value
	end
	for _, child in children(self) do
		setParent(methods.Clone(child), copy)
	end
	return copy
end

local ATTRIBUTE_TYPES = {
	boolean = true,
	number = true,
	string = true,
	UDim = true,
	UDim2 = true,
	Color3 = true,
	Vector2 = true,
	Vector3 = true,
	CFrame = true,
	NumberRange = true,
	NumberSequence = true,
	ColorSequence = true,
	Rect = true,
	BrickColor = true,
	Font = true,
	EnumItem = true,
}

function methods.SetAttribute(self, key: string, value: any)
	if type(key) ~= "string" or #key == 0 or #key > 100 or not string.match(key, "^[%w_]+$") then
		error("SetAttribute: invalid attribute name " .. tostring(key), 2)
	end
	if value ~= nil and not ATTRIBUTE_TYPES[typeof(value)] then
		error(string.format("SetAttribute: %s is not a supported attribute type (%s)", typeof(value), key), 2)
	end
	local attributes = rawget(self, "_attributes")
	if attributes[key] == value then
		return
	end
	attributes[key] = value
	local signal = rawget(self, "_attrSignals")[key]
	if signal then
		signal:Fire()
	end
	fireIf(self, "AttributeChanged", key)
end

function methods.GetAttribute(self, key: string)
	return rawget(self, "_attributes")[key]
end

function methods.GetAttributes(self)
	return table.clone(rawget(self, "_attributes"))
end

function methods.GetAttributeChangedSignal(self, key: string)
	local signals = rawget(self, "_attrSignals")
	if not signals[key] then
		signals[key] = Signal.new("Attribute:" .. key)
	end
	return signals[key]
end

function methods.GetPropertyChangedSignal(self, prop: string)
	local members = lookup(rawget(self, "_class"))
	if not members.Props[prop] and prop ~= "Parent" and prop ~= "Name" then
		error(string.format("%s is not a valid property name of %s", prop, describe(self)), 2)
	end
	local signals = rawget(self, "_propSignals")
	if not signals[prop] then
		signals[prop] = Signal.new("Property:" .. prop)
	end
	return signals[prop]
end

function methods.GetDebugId(self)
	return tostring(self)
end

function methods.GetTags(_self)
	return {}
end

function methods.HasTag(_self, _tag)
	return false
end

-- Models in UI previews are positioned with pivots; the harness only tracks them.
function methods.GetPivot(self)
	return rawget(self, "_pivot") or roblox.CFrame.new()
end

function methods.PivotTo(self, cframe)
	rawset(self, "_pivot", cframe)
end

-- Sound playback is a no-op headless.
function methods.Play(_self) end
function methods.Stop(_self) end

-- Lets a test override a method (e.g. Players:GetPlayers) on one instance.
function MockInstance.Override(self, name: string, fn)
	rawget(self, "_methods")[name] = fn
end

function MockInstance.Children(self)
	return children(self)
end

function MockInstance.Props(self)
	return rawget(self, "_props")
end

function MockInstance.Class(self)
	return rawget(self, "_class")
end

-- Effective property value (explicit or Roblox default) for exporters.
function MockInstance.Get(self, prop: string)
	local ok, value = pcall(function()
		return self[prop]
	end)
	if ok then
		return value
	end
	return nil
end

-- Global table that replaces `Instance` for code under test.
MockInstance.InstanceGlobal = {
	new = function(className: string, parent: any?)
		return MockInstance.new(className, parent)
	end,
}

return MockInstance
