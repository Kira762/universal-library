-- Minimal headless Roblox environment so Mova can be executed outside Roblox.
-- It is NOT a renderer: it only models instances, properties, signals, services and datatypes
-- well enough to catch runtime errors (nil indexes, bad arguments, wrong call order).

local M = {}

---------------------------------------------------------------- polyfills (Luau -> Lua 5.4)
math.clamp = math.clamp or function(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end
math.round = math.round or function(v) return math.floor(v + 0.5) end
table.find = table.find or function(t, v) for i = 1, #t do if t[i] == v then return i end end return nil end
table.clear = table.clear or function(t) for k in pairs(t) do t[k] = nil end end
table.create = table.create or function(n, v) local t = {} for i = 1, n do t[i] = v end return t end
unpack = unpack or table.unpack
warn = warn or function(...) print("[warn]", ...) end
local loadstring = loadstring or load
table.unpack = table.unpack or unpack

---------------------------------------------------------------- typeof
local TYPE_KEY = setmetatable({}, { __mode = "k" })
function typeof(v)
	local t = type(v)
	if t == "table" and TYPE_KEY[v] then return TYPE_KEY[v] end
	if t == "table" and getmetatable(v) and getmetatable(v).__rbxtype then return getmetatable(v).__rbxtype end
	return t
end

local function tagged(t, name) TYPE_KEY[t] = name return t end

---------------------------------------------------------------- Signal
local Signal = {}
Signal.__index = Signal
Signal.__rbxtype = "RBXScriptSignal"
function Signal.new() return setmetatable({ _h = {} }, Signal) end
function Signal:Connect(fn)
	local conn = { Connected = true }
	TYPE_KEY[conn] = "RBXScriptConnection"
	function conn:Disconnect() self.Connected = false end
	self._h[#self._h + 1] = { fn = fn, conn = conn }
	return conn
end
Signal.connect = Signal.Connect
function Signal:Once(fn) local c c = self:Connect(function(...) c:Disconnect() fn(...) end) return c end
function Signal:Fire(...)
	for _, h in ipairs(self._h) do if h.conn.Connected then h.fn(...) end end
end
function Signal:Wait() return end
M.Signal = Signal

---------------------------------------------------------------- Datatypes
local function class(name, ctor, methods)
	local mt = { __rbxtype = name, __index = methods or {} }
	local C = {}
	C.new = function(...) return setmetatable(ctor(...), mt) end
	M[name] = C
	_G[name] = C
	return C, mt
end

local Vector2, V2mt = class("Vector2", function(x, y) return { X = x or 0, Y = y or 0 } end, {})
V2mt.__add = function(a, b) return Vector2.new(a.X + b.X, a.Y + b.Y) end
V2mt.__sub = function(a, b) return Vector2.new(a.X - b.X, a.Y - b.Y) end
V2mt.__mul = function(a, b) if type(b) == "number" then return Vector2.new(a.X * b, a.Y * b) end return Vector2.new(a.X * b.X, a.Y * b.Y) end
V2mt.__eq = function(a, b) return a.X == b.X and a.Y == b.Y end
V2mt.__tostring = function(a) return a.X .. ", " .. a.Y end
Vector2.zero = Vector2.new(0, 0)

local UDim = class("UDim", function(s, o) return { Scale = s or 0, Offset = o or 0 } end, {})
local UDim2, U2mt = class("UDim2", function(xs, xo, ys, yo) return { X = UDim.new(xs, xo), Y = UDim.new(ys, yo) } end, {})
UDim2.fromOffset = function(x, y) return UDim2.new(0, x, 0, y) end
UDim2.fromScale = function(x, y) return UDim2.new(x, 0, y, 0) end
U2mt.__eq = function(a, b) return a.X.Scale == b.X.Scale and a.X.Offset == b.X.Offset and a.Y.Scale == b.Y.Scale and a.Y.Offset == b.Y.Offset end

local Color3, C3mt = class("Color3", function(r, g, b) return { R = r or 0, G = g or 0, B = b or 0 } end, {
	ToHSV = function(c)
		local r, g, b = c.R, c.G, c.B
		local max, min = math.max(r, g, b), math.min(r, g, b)
		local h, s, v = 0, 0, max
		local d = max - min
		s = max == 0 and 0 or d / max
		if d ~= 0 then
			if max == r then h = (g - b) / d % 6 elseif max == g then h = (b - r) / d + 2 else h = (r - g) / d + 4 end
			h = h / 6
		end
		return h, s, v
	end,
	ToHex = function(c) return string.format("%02x%02x%02x", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5)) end,
	Lerp = function(a, b, t) return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t) end,
})
C3mt.__eq = function(a, b) return a.R == b.R and a.G == b.G and a.B == b.B end
Color3.fromRGB = function(r, g, b) return Color3.new(r / 255, g / 255, b / 255) end
Color3.fromHSV = function(h, s, v)
	local i = math.floor(h * 6)
	local f = h * 6 - i
	local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
	i = i % 6
	if i == 0 then return Color3.new(v, t, p) elseif i == 1 then return Color3.new(q, v, p) elseif i == 2 then return Color3.new(p, v, t)
	elseif i == 3 then return Color3.new(p, q, v) elseif i == 4 then return Color3.new(t, p, v) else return Color3.new(v, p, q) end
end
Color3.fromHex = function(hex)
	hex = tostring(hex):gsub("#", "")
	assert(#hex == 6 and hex:match("^%x+$"), "invalid hex")
	return Color3.fromRGB(tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16))
end

class("TweenInfo", function(t, s, d) return { Time = t or 1, EasingStyle = s, EasingDirection = d } end, {})
class("ColorSequenceKeypoint", function(t, v) return { Time = t, Value = v } end, {})
class("NumberSequenceKeypoint", function(t, v) return { Time = t, Value = v } end, {})
class("ColorSequence", function(a, b) if type(a) == "table" and a[1] then return { Keypoints = a } end return { Keypoints = { a, b or a } } end, {})
class("NumberSequence", function(a) return { Keypoints = type(a) == "table" and a or { a } } end, {})
class("Rect", function() return {} end, {})
class("Font", function(f, w) return { Family = f, Weight = w } end, {})

---------------------------------------------------------------- Enum
local EnumItem = {}
EnumItem.__index = EnumItem
EnumItem.__rbxtype = "EnumItem"
EnumItem.__tostring = function(e) return "Enum." .. e.EnumType .. "." .. e.Name end
local Enum = {}
local function makeEnum(name, items)
	local e = {}
	for i, item in ipairs(items) do
		e[item] = setmetatable({ Name = item, Value = i, EnumType = name }, EnumItem)
	end
	setmetatable(e, {
		__index = function(_, k) error("'" .. tostring(k) .. "' is not a valid member of Enum." .. name) end,
		__tostring = function() return name end,
	})
	Enum[name] = e
end
makeEnum("FontWeight", { "Thin", "ExtraLight", "Light", "Regular", "Medium", "SemiBold", "Bold", "ExtraBold", "Heavy" })
makeEnum("FontStyle", { "Normal", "Italic" })
makeEnum("Font", { "Gotham", "GothamMedium", "GothamBold", "GothamBlack", "BuilderSans", "SourceSans", "Code" })
makeEnum("EasingStyle", { "Linear", "Quad", "Quint", "Back", "Sine", "Exponential" })
makeEnum("EasingDirection", { "In", "Out", "InOut" })
makeEnum("UserInputType", { "MouseButton1", "MouseButton2", "MouseButton3", "MouseMovement", "Touch", "Keyboard", "None" })
makeEnum("UserInputState", { "Begin", "Change", "End", "Cancel" })
makeEnum("KeyCode", { "Unknown", "A", "B", "C", "D", "E", "F", "K", "Q", "X", "Z", "LeftShift", "RightShift", "LeftControl", "Escape", "Backspace", "Delete", "Return", "Space", "One", "Two", "F1" })
makeEnum("Platform", { "Windows", "OSX", "IOS", "Android", "XBoxOne", "None" })
makeEnum("AutomaticSize", { "None", "X", "Y", "XY" })
makeEnum("TextXAlignment", { "Left", "Center", "Right" })
makeEnum("TextYAlignment", { "Top", "Center", "Bottom" })
makeEnum("TextTruncate", { "None", "AtEnd" })
makeEnum("FillDirection", { "Horizontal", "Vertical" })
makeEnum("HorizontalAlignment", { "Left", "Center", "Right" })
makeEnum("VerticalAlignment", { "Top", "Center", "Bottom" })
makeEnum("SortOrder", { "LayoutOrder", "Name" })
makeEnum("ScrollingDirection", { "X", "Y", "XY" })
makeEnum("ElasticBehavior", { "Never", "Always", "WhenScrollable" })
makeEnum("ZIndexBehavior", { "Global", "Sibling" })
makeEnum("ApplyStrokeMode", { "Border", "Contextual" })
makeEnum("SafeAreaCompatibility", { "None", "FullscreenExtension" })
makeEnum("ScreenInsets", { "None", "DeviceSafeInsets", "CoreUISafeInsets" })
_G.Enum = Enum
M.Enum = Enum

---------------------------------------------------------------- Instance
local EVENT_NAMES = {
	MouseButton1Click = 1, MouseButton1Down = 1, MouseButton1Up = 1, MouseButton2Click = 1, MouseEnter = 1, MouseLeave = 1,
	InputBegan = 1, InputChanged = 1, InputEnded = 1, Focused = 1, FocusLost = 1, Changed = 1, Activated = 1,
	ChildAdded = 1, ChildRemoved = 1, Destroying = 1, Completed = 1, RenderStepped = 1, Heartbeat = 1,
	TouchTap = 1, SelectionGained = 1, SelectionLost = 1,
}
local DEFAULTS = {
	GroupTransparency = 0, Scale = 1, BlurRadius = nil,
	Name = "Instance", Parent = nil, Visible = true, Text = "", Image = "", ZIndex = 1, LayoutOrder = 0,
	BackgroundTransparency = 0, TextTransparency = 0, ImageTransparency = 0, Transparency = 0, Rotation = 0,
	ClipsDescendants = false, Active = false, AutoButtonColor = true, ClearTextOnFocus = true, TextWrapped = false,
	Enabled = true, ResetOnSpawn = true, IgnoreGuiInset = false, DisplayOrder = 0, PlaceholderText = "", TextSize = 14,
	ScrollBarThickness = 12, ScrollBarImageTransparency = 0, BorderSizePixel = 1, Thickness = 1, TextScaled = false,
	RichText = false, Selectable = true, TextEditable = true, MultiLine = false, Interactable = true,
	ElasticBehavior = nil, TopImage = "", BottomImage = "", MidImage = "", CornerRadius = nil, Padding = nil,
}

local Instance = {}
local InstanceMT = {}
InstanceMT.__rbxtype = "Instance"
local created = 0
M.Created = function() return created end

local function newInstance(className)
	created = created + 1
	local self = {
		_class = className,
		_props = {},
		_children = {},
		_signals = {},
		_propSignals = {},
		_attributes = {},
		_destroyed = false,
	}
	self._props.Name = className
	self._props.Size = UDim2.new(0, 100, 0, 100)
	self._props.Position = UDim2.new(0, 0, 0, 0)
	self._props.AnchorPoint = Vector2.new(0, 0)
	self._props.AbsoluteSize = Vector2.new(100, 40)
	self._props.AbsolutePosition = Vector2.new(0, 0)
	if className == "ScrollingFrame" then self._props.CanvasPosition = Vector2.new(0, 0) end
	self._props.BackgroundColor3 = Color3.new(1, 1, 1)
	self._props.TextColor3 = Color3.new(0, 0, 0)
	self._props.ImageColor3 = Color3.new(1, 1, 1)
	self._props.Color = Color3.new(0, 0, 0)
	self._props.CanvasSize = UDim2.new(0, 0, 0, 0)
	self._props.ViewportSize = Vector2.new(1280, 720)
	if className == "ScreenGui" then self._props.AbsoluteSize = Vector2.new(1280, 720) end
	return setmetatable(self, InstanceMT)
end

local methods = {}
function methods:IsA(cls)
	if self._class == cls then return true end
	if cls == "GuiObject" then return self._class ~= "ScreenGui" and self._class ~= "Folder" and not self._class:match("^UI") end
	if cls == "GuiButton" then return self._class == "TextButton" or self._class == "ImageButton" end
	if cls == "Instance" then return true end
	return false
end
function methods:FindFirstChild(name)
	for _, c in ipairs(self._children) do if c._props.Name == name then return c end end
	return nil
end
function methods:FindFirstChildOfClass(cls)
	for _, c in ipairs(self._children) do if c._class == cls then return c end end
	return nil
end
function methods:FindFirstChildWhichIsA(cls)
	for _, c in ipairs(self._children) do if c:IsA(cls) then return c end end
	return nil
end
function methods:WaitForChild(name) return self:FindFirstChild(name) end
function methods:GetChildren()
	local out = {}
	for i, c in ipairs(self._children) do out[i] = c end
	return out
end
function methods:GetDescendants()
	local out = {}
	local function walk(o)
		for _, c in ipairs(o._children) do out[#out + 1] = c walk(c) end
	end
	walk(self)
	return out
end
function methods:ClearAllChildren()
	for i = #self._children, 1, -1 do self._children[i]:Destroy() end
end
function methods:Destroy()
	if self._destroyed then return end
	self._destroyed = true
	self:ClearAllChildren()
	if self._props.Parent then
		local p = self._props.Parent
		for i, c in ipairs(p._children) do if c == self then table.remove(p._children, i) break end end
		self._props.Parent = nil
	end
end
function methods:Clone()
	local c = newInstance(self._class)
	for k, v in pairs(self._props) do if k ~= "Parent" then c._props[k] = v end end
	for _, child in ipairs(self._children) do child:Clone().Parent = c end
	return c
end
function methods:GetPropertyChangedSignal(prop)
	self._propSignals[prop] = self._propSignals[prop] or Signal.new()
	return self._propSignals[prop]
end
function methods:GetAttribute(k) return self._attributes[k] end
function methods:SetAttribute(k, v) self._attributes[k] = v end
function methods:GetFullName() return self._props.Name end
function methods:CaptureFocus() M.FocusedBox = self end
function methods:ReleaseFocus(enter) if M.FocusedBox == self then M.FocusedBox = nil end if self._signals.FocusLost then self._signals.FocusLost:Fire(enter or false) end end
function methods:IsFocused() return M.FocusedBox == self end
function methods:TweenSize() return true end
function methods:TweenPosition() return true end
function methods:GetService(name) return M.Services[name] or error("unknown service " .. tostring(name)) end
function methods:HttpGet() return "" end

InstanceMT.__index = function(self, key)
	if methods[key] then return methods[key] end
	local props = rawget(self, "_props")
	if props == nil then return nil end
	local v = props[key]
	if v ~= nil then return v end
	if EVENT_NAMES[key] then
		local sigs = rawget(self, "_signals")
		sigs[key] = sigs[key] or Signal.new()
		return sigs[key]
	end
	if DEFAULTS[key] ~= nil then return DEFAULTS[key] end
	-- children by name
	local child = methods.FindFirstChild(self, key)
	if child then return child end
	if key == "ClassName" then return rawget(self, "_class") end
	if key == "Parent" then return nil end
	if key == "TextBounds" then return Vector2.new(#tostring(props.Text or "") * 7, 14) end
	if key == "CurrentCamera" then return nil end
	error(tostring(key) .. " is not a valid member of " .. tostring(rawget(self, "_class")) .. " \"" .. tostring(props.Name) .. "\"", 2)
end

InstanceMT.__newindex = function(self, key, value)
	if key:sub(1, 1) == "_" then
		error("attempt to set custom field '" .. key .. "' on Instance " .. self._class .. " (not allowed in Roblox)", 2)
	end
	if key == "Parent" then
		local old = self._props.Parent
		if old then
			for i, c in ipairs(old._children) do if c == self then table.remove(old._children, i) break end end
		end
		self._props.Parent = value
		if value then
			if typeof(value) ~= "Instance" then error("Parent must be an Instance", 2) end
			value._children[#value._children + 1] = self
			if value._signals.ChildAdded then value._signals.ChildAdded:Fire(self) end
		end
		return
	end
	if key == "AbsoluteSize" or key == "AbsolutePosition" then
		-- allowed in the mock so tests can simulate layout
	end
	if key == "Image" and typeof(value) ~= "string" then error("Image must be a string", 2) end
	if key == "Text" and typeof(value) ~= "string" then error("Text must be a string, got " .. typeof(value), 2) end
	if (key == "Size" or key == "Position") and typeof(value) ~= "UDim2" then error(key .. " must be UDim2, got " .. typeof(value), 2) end
	if (key == "BackgroundColor3" or key == "TextColor3" or key == "ImageColor3") and typeof(value) ~= "Color3" then
		error(key .. " must be Color3, got " .. typeof(value) .. " (" .. tostring(value) .. ")", 2)
	end
	if key == "Font" and typeof(value) ~= "EnumItem" then error("Font must be an EnumItem, got " .. typeof(value), 2) end
	if key == "FontFace" and typeof(value) ~= "Font" then error("FontFace must be a Font, got " .. typeof(value), 2) end
	if key == "Rotation" and type(value) ~= "number" then error("Rotation must be a number", 2) end
	if key == "Visible" and typeof(value) ~= "boolean" then error("Visible must be boolean", 2) end
	local old = self._props[key]
	self._props[key] = value
	if old ~= value and self._propSignals[key] then self._propSignals[key]:Fire() end
end
InstanceMT.__tostring = function(self) return self._props.Name end

function Instance.new(className, parent)
	local inst = newInstance(className)
	if parent then inst.Parent = parent end
	return inst
end
_G.Instance = Instance
M.Instance = Instance

---------------------------------------------------------------- Services
local Services = {}
M.Services = Services
local function service(name, t)
	t = t or {}
	t.ClassName = name
	t.Name = name
	TYPE_KEY[t] = "Instance"
	Services[name] = t
	return t
end

local PlayerGui = Instance.new("Folder")
PlayerGui._class = "PlayerGui"
PlayerGui.Name = "PlayerGui"
local LocalPlayer = { Name = "Tester", DisplayName = "Tester", UserId = 1 }
TYPE_KEY[LocalPlayer] = "Instance"
function LocalPlayer:FindFirstChildOfClass(cls) if cls == "PlayerGui" then return PlayerGui end return nil end
function LocalPlayer:WaitForChild() return PlayerGui end
service("Players", { LocalPlayer = LocalPlayer })

local UIS = service("UserInputService", {
	TouchEnabled = false, MouseEnabled = true, KeyboardEnabled = true, MouseIconEnabled = true,
	InputBegan = Signal.new(), InputChanged = Signal.new(), InputEnded = Signal.new(),
})
function UIS:GetPlatform() return Enum.Platform.Windows end
function UIS:GetMouseLocation() return Vector2.new(640, 360) end
function UIS:GetStringForKeyCode(k) return k.Name end
function UIS:IsKeyDown() return false end
function UIS:GetFocusedTextBox() return M.FocusedBox end

local tweensPlayed = 0
M.TweensPlayed = function() return tweensPlayed end
local TS = service("TweenService")
function TS:Create(obj, info, props)
	assert(typeof(obj) == "Instance", "TweenService:Create expects an Instance, got " .. typeof(obj))
	assert(typeof(info) == "TweenInfo", "expected TweenInfo")
	local tw = { Completed = Signal.new(), PlaybackState = "Begin" }
	function tw:Play()
		tweensPlayed = tweensPlayed + 1
		-- apply instantly (headless)
		for k, v in pairs(props) do obj[k] = v end
		self.Completed:Fire()
	end
	function tw:Cancel() end
	function tw:Pause() end
	return tw
end

local RS = service("RunService", { RenderStepped = Signal.new(), Heartbeat = Signal.new(), Stepped = Signal.new() })
function RS:IsStudio() return M.StudioMode == true end
function RS:IsClient() return true end

local HS = service("HttpService")
local guid = 0
function HS:GenerateGUID() guid = guid + 1 return "GUID-" .. guid end
-- tiny JSON codec sufficient for config round trips
local function encode(v, out)
	local t = type(v)
	if t == "table" then
		local isArray = #v > 0 or next(v) == nil
		if isArray then
			out[#out + 1] = "["
			for i, item in ipairs(v) do if i > 1 then out[#out + 1] = "," end encode(item, out) end
			out[#out + 1] = "]"
		else
			out[#out + 1] = "{"
			local first = true
			for k, item in pairs(v) do
				if not first then out[#out + 1] = "," end
				first = false
				out[#out + 1] = string.format("%q", tostring(k)) .. ":"
				encode(item, out)
			end
			out[#out + 1] = "}"
		end
	elseif t == "string" then out[#out + 1] = string.format("%q", v)
	elseif t == "number" then out[#out + 1] = tostring(v)
	elseif t == "boolean" then out[#out + 1] = tostring(v)
	else out[#out + 1] = "null" end
end
function HS:JSONEncode(v) local out = {} encode(v, out) return table.concat(out) end
function HS:JSONDecode(s)
	-- the mock encodes with %q which is Lua-loadable; translate JSON tokens back to Lua
	local lua = s:gsub("%[", "{"):gsub("%]", "}"):gsub('("[^"]-")%s*:', "[%1]="):gsub("null", "nil")
	local fn = assert(loadstring("return " .. lua))
	return fn()
end

service("GuiService", { GetGuiInset = function() return Vector2.new(0, 36), Vector2.new(0, 0) end })
service("TextService", { GetTextSize = function(_, text, size) return Vector2.new(#tostring(text) * size * 0.55, size) end })
local CoreGui = Instance.new("Folder") CoreGui.Name = "CoreGui"
Services.CoreGui = CoreGui
TYPE_KEY[CoreGui] = "Instance"
M.CoreGui = CoreGui
M.PlayerGui = PlayerGui

local Camera = { ViewportSize = Vector2.new(1280, 720) }
_G.workspace = { CurrentCamera = Camera }

_G.game = setmetatable({}, { __index = function(_, k)
	if k == "GetService" then return function(_, name) return Services[name] or error("unknown service " .. tostring(name)) end end
	if k == "HttpGet" then return function(_, url) return M.HttpGetResponse or "" end end
	if k == "Players" then return Services.Players end
	if k == "CoreGui" then return CoreGui end
	return nil
end })
TYPE_KEY[_G.game] = "Instance"

---------------------------------------------------------------- task
-- Coroutine based: task.wait() yields when called inside a task.spawn thread, and every mock.flush()
-- resumes each pending thread exactly once (one "tick"), so `while task.wait() do` loops cannot hang tests.
local scheduled = {}
local function schedule(co, at, args) local item = { co = co, at = at or 0, args = args or {} } scheduled[#scheduled + 1] = item return item end
local function resume(item)
	local ok, err = coroutine.resume(item.co, table.unpack(item.args))
	if not ok then error("scheduled callback failed: " .. tostring(err), 0) end
	if coroutine.status(item.co) == "suspended" then schedule(item.co, 0) end
end
_G.task = {
	spawn = function(fn, ...)
		local co = type(fn) == "thread" and fn or coroutine.create(fn)
		resume({ co = co, args = { ... } })
		return co
	end,
	defer = function(fn, ...) return schedule(coroutine.create(fn), 0, { ... }) end,
	delay = function(t, fn, ...) return schedule(coroutine.create(fn), t, { ... }) end,
	wait = function(t)
		local co, isMain = coroutine.running()
		if co and not isMain then coroutine.yield() end
		return t or 0
	end,
	cancel = function(th) if type(th) == "table" then th.cancelled = true end end,
}
function M.flush()
	local batch = scheduled
	scheduled = {}
	table.sort(batch, function(a, b) return a.at < b.at end)
	local n = 0
	for _, item in ipairs(batch) do
		if not item.cancelled then n = n + 1 resume(item) end
	end
	return n
end

---------------------------------------------------------------- virtual file system
local files, folders = {}, {}
M.Files = files
_G.writefile = function(p, c) files[p] = c end
_G.readfile = function(p) return files[p] or error("no file " .. p) end
_G.isfile = function(p) return files[p] ~= nil end
_G.isfolder = function(p) return folders[p] == true end
_G.makefolder = function(p) folders[p] = true end
_G.delfile = function(p) files[p] = nil end
_G.listfiles = function(folder)
	local out = {}
	for p in pairs(files) do if p:sub(1, #folder + 1) == folder .. "/" then out[#out + 1] = p end end
	return out
end
_G.getcustomasset = function(p) return "rbxasset://custom/" .. p end
_G.setclipboard = function(s) M.Clipboard = s end
_G.gethui = function() return CoreGui end
_G.getgenv = function() return _G end
_G.cloneref = function(o) return o end

---------------------------------------------------------------- input simulation helpers
function M.input(userInputType, keyCode, position, state)
	local obj = {
		UserInputType = userInputType, KeyCode = keyCode or Enum.KeyCode.Unknown,
		Position = position or Vector2.new(0, 0), UserInputState = state or Enum.UserInputState.Begin,
		Changed = Signal.new(), Delta = Vector2.new(0, 0),
	}
	TYPE_KEY[obj] = "InputObject"
	return obj
end
function M.pressKey(keyCode, processed)
	local i = M.input(Enum.UserInputType.Keyboard, keyCode)
	UIS.InputBegan:Fire(i, processed or false)
	i.UserInputState = Enum.UserInputState.End
	UIS.InputEnded:Fire(i, processed or false)
	return i
end
function M.click(button)
	assert(typeof(button) == "Instance", "click expects an Instance")
	local i = M.input(Enum.UserInputType.MouseButton1, nil, button.AbsolutePosition)
	button.InputBegan:Fire(i, false)
	UIS.InputBegan:Fire(i, false)
	button.MouseButton1Click:Fire()
	i.UserInputState = Enum.UserInputState.End
	i.Changed:Fire()
	button.InputEnded:Fire(i, false)
	UIS.InputEnded:Fire(i, false)
end
function M.setText(box, text, enter)
	box.Text = text
	box.FocusLost:Fire(enter ~= false)
end
function M.find(root, predicate)
	for _, d in ipairs(root:GetDescendants()) do if predicate(d) then return d end end
	return nil
end
function M.findAll(root, predicate)
	local out = {}
	for _, d in ipairs(root:GetDescendants()) do if predicate(d) then out[#out + 1] = d end end
	return out
end

return M
