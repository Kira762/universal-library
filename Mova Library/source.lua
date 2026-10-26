--[[

	Mova Library
	A modern, open-source UI library for Roblox scripts.

	Design goals (learned from Rayfield 2022 / Gen2, Obsidian, Linoria, WindUI, Fluent, Aetheris):
	  * Drawn 100% in code. No marketplace model, no asset ids by default -> nothing to fingerprint.
	  * Zero telemetry. The only requests Mova ever makes are the ones you ask for: a key-system URL,
	    or the Lucide icon index the first time you pass an icon *name* (never in secure mode).
	  * One file, one loadstring, no dependencies.
	  * Live themes (registry based, tweened), 8 built-in, custom tables accepted.
	  * Typed JSON config saving (Color3 / KeyCode / tables round-trip), multiple named configs.
	  * Every element handle: .Value, :Set(v, silent), :Lock(reason), :Unlock(), :SetVisible(), :Destroy().
	  * Global Mova.Flags / Mova.Options registries + Linoria-style AddToggle/AddSlider aliases,
	    so scripts written for Rayfield OR Linoria/Obsidian can be ported with minimal edits.
	  * Search across every tab, keybind modes (Press / Toggle / Hold), toggles with attached keybinds,
	    dropdown with type-to-filter + multi select, HSV colour picker with alpha + hex.
	  * Mobile first: touch drag, floating open button, auto-fit to viewport, resizable on desktop.
	  * Built-in key system (drawn in code), notifications, dialogs, settings tab, localisation.
	  * Icons like Rayfield Gen 2: asset ids, rbxassetid:// strings, built-in names, Lucide names,
	    spritesheet cells, custom resolver. Secure mode (getgenv().MOVA_SECURE = true): silent console,
	    asset ids served through a local PNG cache instead of rbxassetid://.

	License: MIT. See LICENSE in the Mova Library folder.

]]

local Mova = {
	Version = "1.2.0",
	Build = "mova-1",
	Flags = {},      -- flag -> current value
	Options = {},    -- flag -> element handle
	Toggles = {},    -- flag -> toggle handle (Linoria compat)
	Windows = {},
	Themes = {},
	Unloaded = false,
	NotifyOnError = true,
	Debug = false,
}

---------------------------------------------------------------------------------------------------
-- Environment
---------------------------------------------------------------------------------------------------

local cloneref = (typeof(cloneref) == "function" and cloneref) or function(o) return o end

local function getService(name)
	local ok, service = pcall(function() return game:GetService(name) end)
	if ok and service then return cloneref(service) end
	return nil
end

local Players = getService("Players")
local UserInputService = getService("UserInputService")
local TweenService = getService("TweenService")
local RunService = getService("RunService")
local HttpService = getService("HttpService")
local GuiService = getService("GuiService")
local TextService = getService("TextService")
local CoreGui = getService("CoreGui")
local LocalPlayer = Players and Players.LocalPlayer

local function readGlobal(name)
	if typeof(getgenv) == "function" then
		local ok, v = pcall(function() return getgenv()[name] end)
		if ok then return v end
	end
	return nil
end

local SecureMode = readGlobal("MOVA_SECURE") == true
Mova.SecureMode = SecureMode

-- Console helpers. Never assigned as globals: in an executor those are shared with every script.
local print = print
local warn = warn or function(...) print("[Mova]", ...) end
if SecureMode then
	warn = function() end
	print = function() end
end

local function log(...)
	if Mova.Debug then
		print("[Mova]", ...)
	end
end

local IsStudio = RunService and RunService:IsStudio() or false

local IsMobile = false
do
	local ok, platform = pcall(function() return UserInputService:GetPlatform() end)
	if ok and platform then
		IsMobile = (platform == Enum.Platform.Android or platform == Enum.Platform.IOS)
	end
	if not IsMobile and UserInputService then
		IsMobile = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
	end
end
Mova.IsMobile = IsMobile

local function getGuiContainer()
	if IsStudio and LocalPlayer then
		local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
		if pg then return pg end
	end
	if typeof(gethui) == "function" then
		local ok, hui = pcall(gethui)
		if ok and hui then return hui end
	end
	if CoreGui then return CoreGui end
	return LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
end

-- File system shim. Wraps every call in pcall: several executors throw from isfile/isfolder.
local FS = {}
do
	local function wrap(fn, fallback)
		if typeof(fn) ~= "function" then
			return function() return fallback end
		end
		return function(...)
			local ok, res = pcall(fn, ...)
			if ok then return res end
			return fallback
		end
	end
	FS.available = typeof(writefile) == "function" and typeof(readfile) == "function" and typeof(isfile) == "function"
	FS.writefile = wrap(writefile, nil)
	FS.readfile = wrap(readfile, nil)
	FS.isfile = wrap(isfile, false)
	FS.isfolder = wrap(isfolder, false)
	FS.makefolder = wrap(makefolder, nil)
	FS.delfile = wrap(delfile, nil)
	FS.listfiles = wrap(listfiles, {})
	FS.getcustomasset = typeof(getcustomasset) == "function" and getcustomasset or nil
end
Mova.FileSystem = FS

---------------------------------------------------------------------------------------------------
-- Small utilities
---------------------------------------------------------------------------------------------------

local function prop(t, default, ...)
	if typeof(t) ~= "table" then return default end
	local names = { ... }
	for i = 1, #names do
		local v = t[names[i]]
		if v ~= nil then return v end
	end
	return default
end

local function clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

local function round(v, decimals)
	local m = 10 ^ (decimals or 0)
	return math.floor(v * m + 0.5) / m
end

local function formatNumber(v, decimals)
	v = round(v, decimals)
	if decimals and decimals > 0 then
		return string.format("%." .. decimals .. "f", v)
	end
	return tostring(math.floor(v + 0.5))
end

local function trim(s)
	return (tostring(s):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function splitLines(s)
	local out = {}
	for line in (tostring(s) .. "\n"):gmatch("(.-)\r?\n") do
		out[#out + 1] = line
	end
	return out
end

local function indexOf(t, v)
	for i = 1, #t do
		if t[i] == v then return i end
	end
	return nil
end

local function shallowCopy(t)
	local n = {}
	for k, v in pairs(t) do n[k] = v end
	return n
end

local function safeCallback(fn, ...)
	if typeof(fn) ~= "function" then return end
	local args = { ... }
	local ok, err = xpcall(function()
		return fn(table.unpack(args))
	end, function(e)
		return debug and debug.traceback and debug.traceback(tostring(e), 2) or tostring(e)
	end)
	if not ok then
		warn("[Mova] callback error: " .. tostring(err))
		if Mova.NotifyOnError and Mova.Notify and not SecureMode then
			pcall(function()
				Mova:Notify({ Title = "Callback error", Content = tostring(err):match("^[^\n]*") or "error", Duration = 6, Type = "Error" })
			end)
		end
	end
	return ok
end

local Connections = {}
local function connect(signal, fn)
	if not signal then return nil end
	local c = signal:Connect(fn)
	Connections[#Connections + 1] = c
	-- rebuilt UI (dropdown rows, popups) leaves disconnected entries behind; compact now and then
	if #Connections > 1500 then
		local live = {}
		for _, conn in ipairs(Connections) do
			local ok, connected = pcall(function() return conn.Connected end)
			if not ok or connected ~= false then live[#live + 1] = conn end
		end
		Connections = live
	end
	return c
end

local function disconnectAll(list)
	for i = #list, 1, -1 do
		local c = list[i]
		if c and c.Connected ~= false then
			pcall(function() c:Disconnect() end)
		end
		list[i] = nil
	end
end

---------------------------------------------------------------------------------------------------
-- Icons
-- Every Icon / Image property in the library (window, tabs, elements, notifications) accepts:
--   * 4483362458, "4483362458", "rbxassetid://4483362458"           asset ids
--   * "rbxasset://..." (getcustomasset results, engine content), "rbxthumb://..."
--   * "home", "lucide:home", "solar:home"                             icon-pack names. The pack index
--     (Footagesus/Icons, MIT) is fetched once on first use, only when you pass a name, never in
--     secure mode. Change the default pack with Mova:SetIconPack("solar") or warm it with
--     Mova:PreloadIcons().
--   * "settings", "search", "check", "chevron", "close", "dot" ...   built-in names (Mova.Icons,
--     the same assets Rayfield Gen 2 ships), resolved without any download
--   * { Image = ..., ImageRectSize = Vector2, ImageRectOffset = Vector2 }  spritesheet cells
--   * whatever your Mova:SetIconResolver(fn) returns for a name
-- Secure mode never hands an asset id to the engine. Like Rayfield Gen 2 the PNG is downloaded from
-- Roblox's own asset delivery once into <Mova.Folder>/icons/ and shown through getcustomasset; the label
-- fills in when the download lands. getgenv().MOVA_NO_ICON_CACHE = true disables that too.
---------------------------------------------------------------------------------------------------

local NoIconCache = readGlobal("MOVA_NO_ICON_CACHE") == true

---------------------------------------------------------------------------------------------------
-- Storage. Everything Mova ever writes lives under ONE root folder with a fixed layout:
--
--   Mova/
--   ├─ icons/                     shared secure-mode asset cache (<id>.png)
--   └─ <Script>/                  one folder per window (ConfigurationSaving.FolderName renames it)
--      ├─ settings.json           theme, autoload config, saved key, dismissed prompts
--      └─ configs/
--         └─ <name>.json          saved configs ({ library, version, data })
--
-- getgenv().MOVA_FOLDER moves the root. The old scattered layout (<Folder>/<name>.mova.json,
-- theme.txt, autoload.txt, Mova/keys/*.txt) is migrated the first time a window with that name
-- is created.
---------------------------------------------------------------------------------------------------

Mova.Folder = type(readGlobal("MOVA_FOLDER")) == "string" and readGlobal("MOVA_FOLDER") or "Mova"

local Storage = { _stores = {} }
Mova.Storage = Storage

local function safeName(name, fallback)
	name = trim((tostring(name or "")):gsub("[^%w%s%-_%.]", ""):gsub("^%.+", ""))
	if name == "" then name = fallback or "default" end
	return name
end
Storage.safeName = safeName

-- makefolder is not recursive on most executors: create every missing parent in turn
function Storage.ensure(path)
	if not FS.available then return false end
	local sofar
	for part in tostring(path):gmatch("[^/\\]+") do
		sofar = sofar and (sofar .. "/" .. part) or part
		if not FS.isfolder(sofar) then FS.makefolder(sofar) end
	end
	return FS.isfolder(path)
end

function Storage.readJSON(path)
	if not FS.isfile(path) then return nil end
	local raw = FS.readfile(path)
	if type(raw) ~= "string" or raw == "" then return nil end
	local ok, decoded = pcall(function() return HttpService:JSONDecode(raw) end)
	if ok and type(decoded) == "table" then return decoded end
	return nil
end

function Storage.writeJSON(path, value)
	local ok, json = pcall(function() return HttpService:JSONEncode(value) end)
	if not ok then return false, json end
	local folder = tostring(path):match("^(.*)[/\\][^/\\]+$")
	if folder and not Storage.ensure(folder) then return false, "could not create " .. folder end
	FS.writefile(path, json)
	return true
end

function Storage.iconFolder() return Mova.Folder .. "/icons" end
function Storage.scriptFolder(name)
	name = tostring(name or ""):gsub("^" .. Mova.Folder:gsub("%p", "%%%0") .. "[/\\]", "")
	return Mova.Folder .. "/" .. safeName(name, "Script")
end

-- One store per script folder: settings.json (small key/value file) + configs/<name>.json
local ScriptStore = {}
ScriptStore.__index = ScriptStore

function Storage.forScript(name)
	local folder = Storage.scriptFolder(name)
	local store = Storage._stores[folder]
	if store then return store end
	store = setmetatable({
		Folder = folder,
		ConfigFolder = folder .. "/configs",
		SettingsPath = folder .. "/settings.json",
	}, ScriptStore)
	Storage._stores[folder] = store
	return store
end

function ScriptStore:Settings()
	if not self._settings then self._settings = Storage.readJSON(self.SettingsPath) or {} end
	return self._settings
end
function ScriptStore:Get(key) return self:Settings()[key] end
function ScriptStore:Set(key, value)
	local settings = self:Settings()
	if settings[key] == value then return true end
	settings[key] = value
	return Storage.writeJSON(self.SettingsPath, settings)
end

function ScriptStore:ConfigPath(name) return self.ConfigFolder .. "/" .. safeName(name) .. ".json" end
function ScriptStore:ListConfigs()
	local out = {}
	for _, file in ipairs(FS.listfiles(self.ConfigFolder) or {}) do
		local name = tostring(file):match("([^/\\]+)%.json$")
		if name then out[#out + 1] = name end
	end
	table.sort(out)
	return out
end
function ScriptStore:HasConfig(name) return FS.isfile(self:ConfigPath(name)) end
function ScriptStore:ReadConfig(name) return Storage.readJSON(self:ConfigPath(name)) end
function ScriptStore:WriteConfig(name, value) return Storage.writeJSON(self:ConfigPath(name), value) end
function ScriptStore:DeleteConfig(name)
	local path = self:ConfigPath(name)
	if FS.isfile(path) then FS.delfile(path) return true end
	return false
end

-- Moves files from the pre-1.1 layout into this store (existing configs are never overwritten).
function ScriptStore:Migrate(legacyFolders, legacyKeyPath)
	if not FS.available then return end
	for _, old in ipairs(legacyFolders or {}) do
		if old ~= self.ConfigFolder then
			for _, file in ipairs(FS.listfiles(old) or {}) do
				local f = tostring(file)
				local leaf = f:match("([^/\\]+)$") or ""
				local cfgName = leaf:match("^(.+)%.mova%.json$")
				if cfgName then
					local raw = FS.readfile(f)
					if raw and not self:HasConfig(cfgName) and Storage.ensure(self.ConfigFolder) then
						FS.writefile(self:ConfigPath(cfgName), raw)
					end
					FS.delfile(f)
				elseif leaf == "theme.txt" or leaf == "autoload.txt" then
					local v = trim(FS.readfile(f) or "")
					local key = leaf == "theme.txt" and "theme" or "autoload"
					if v ~= "" and self:Get(key) == nil then self:Set(key, v) end
					FS.delfile(f)
				end
			end
		end
	end
	if legacyKeyPath and FS.isfile(legacyKeyPath) then
		local v = trim(FS.readfile(legacyKeyPath) or "")
		if v ~= "" and self:Get("key") == nil then self:Set("key", v) end
		FS.delfile(legacyKeyPath)
	end
end

local IconResolver = nil
function Mova:SetIconResolver(fn)
	IconResolver = fn
end

Mova.IconPack = "lucide"
Mova.IconPackURL = "https://raw.githubusercontent.com/Footagesus/Icons/refs/heads/main/%s/dist/Icons.lua"
Mova.Icons = {
	settings = 129180860773723, search = 100604009889706, check = 125626312718314, chevron = 88479147175134,
	close = 83277910885129, minimise = 108115485663409, minimize = 108115485663409,
	maximise = 88738500661569, maximize = 88738500661569, dot = 91452555903853, circle = 91452555903853,
	banner = 111263549366178, config = 125823673784681, rayfield = 80387863064905,
}

function Mova:SetIconPack(name)
	assert(type(name) == "string" and name ~= "", "SetIconPack expects a pack name")
	Mova.IconPack = name:lower()
end

local IconPacks = {} -- pack -> table | false (load failed, do not retry)
local function loadIconPack(pack)
	local cached = IconPacks[pack]
	if cached ~= nil then return cached or nil end
	IconPacks[pack] = false
	if SecureMode or type(Mova.IconPackURL) ~= "string" then return nil end
	local ok, tbl = pcall(function()
		local src = game:HttpGet(string.format(Mova.IconPackURL, pack))
		local chunk = assert((loadstring or load)(src))
		return chunk()
	end)
	if ok and type(tbl) == "table" then
		IconPacks[pack] = tbl
		return tbl
	end
	warn("[Mova] icon pack '" .. pack .. "' could not be loaded" .. (ok and "" or (": " .. tostring(tbl))))
	return nil
end

function Mova:PreloadIcons(pack)
	return loadIconPack((pack or Mova.IconPack):lower()) ~= nil
end

local function iconSpec(image, rectSize, rectOffset)
	return { Image = image, RectSize = rectSize, RectOffset = rectOffset }
end

local function toVector2(v)
	if typeof(v) == "Vector2" then return v end
	if type(v) == "table" then
		local x, y = v[1] or v.X or v.x, v[2] or v.Y or v.y
		if type(x) == "number" and type(y) == "number" then return Vector2.new(x, y) end
	end
	return nil
end

-- Secure-mode asset cache: Mova/icons/<id>.png shown through getcustomasset.
local IconCache = { uris = {}, waiting = {}, failed = {} }
local PNG_MAGIC = "\137PNG\r\n\26\n"
Mova.IconCacheURLs = { -- tried in order; same endpoints Rayfield Gen 2 uses
	"https://assetdelivery.roblox.com/v1/asset/?id=%s",
	"https://assetdelivery.roproxy.com/v1/asset/?id=%s",
}

local function httpRequest(url)
	local fn = (typeof(request) == "function" and request)
		or (typeof(http_request) == "function" and http_request)
		or (typeof(syn) == "table" and typeof(syn.request) == "function" and syn.request)
		or (typeof(fluxus) == "table" and typeof(fluxus.request) == "function" and fluxus.request)
		or (typeof(http) == "table" and typeof(http.request) == "function" and http.request)
	if fn then
		local ok, res = pcall(fn, { Url = url, Method = "GET" })
		if ok and type(res) == "table" and type(res.Body) == "string" and (res.StatusCode == 200 or res.Success == true) then
			return res.Body
		end
		return nil
	end
	local ok, body = pcall(function() return game:HttpGet(url) end)
	if ok and type(body) == "string" and body ~= "" then return body end
	return nil
end

local function customAsset(path)
	local ok, res = pcall(FS.getcustomasset, path)
	if ok and type(res) == "string" and res ~= "" then return res end
	return nil
end

local function cachedAsset(id)
	local uri = IconCache.uris[id]
	if uri then return iconSpec(uri) end
	if NoIconCache or not FS.available or not FS.getcustomasset or IconCache.failed[id] then return nil end
	local path = Storage.iconFolder() .. "/" .. tostring(id) .. ".png"
	if FS.isfile(path) then
		uri = customAsset(path)
		if uri then
			IconCache.uris[id] = uri
			return iconSpec(uri)
		end
	end
	if not IconCache.waiting[id] then
		IconCache.waiting[id] = {}
		task.spawn(function()
			local body
			for _, base in ipairs(Mova.IconCacheURLs) do
				body = httpRequest(string.format(base, tostring(id)))
				if body and body:sub(1, 8) == PNG_MAGIC then break end
				body = nil
			end
			local out
			-- only ever write a real PNG: an error page cached to disk would shadow the asset forever
			if body and Storage.ensure(Storage.iconFolder()) then
				FS.writefile(path, body)
				out = customAsset(path)
			end
			local waiters = IconCache.waiting[id] or {}
			IconCache.waiting[id] = nil
			if out then
				IconCache.uris[id] = out
				for _, label in ipairs(waiters) do
					if label.Parent then label.Image = out end
				end
			else
				IconCache.failed[id] = true
			end
		end)
	end
	return { Image = "", Pending = id }
end

local resolveIcon
local function iconFromEntry(entry, depth)
	-- pack / resolver results: "rbxassetid://..", 123, { Image = .., ImageRectSize = .., ImageRectOffset = .. },
	-- WindUI's { Image, ImageRectSize, ImageRectPosition } or Rayfield 2022's { id, {w, h}, {x, y} }
	if entry.Pending then return entry end -- an already-resolved spec waiting on the secure-mode cache
	local image = entry.Image or entry.image or entry.Id or entry.id or entry[1]
	local spec = resolveIcon(image, depth)
	if not spec then return nil end
	spec.RectSize = toVector2(entry.ImageRectSize or entry.imageRectSize or entry.RectSize or entry[2]) or spec.RectSize
	spec.RectOffset = toVector2(entry.ImageRectOffset or entry.imageRectOffset or entry.ImageRectPosition or entry.RectOffset or entry[3]) or spec.RectOffset
	return spec
end

local function iconFromName(name, depth)
	if IconResolver then
		local ok, res = pcall(IconResolver, name)
		if ok and res ~= nil and res ~= name then
			return resolveIcon(res, depth)
		end
	end
	local key = name:lower()
	local pack, short = key:match("^([%w%-_]+):(.+)$")
	if not pack then pack, short = Mova.IconPack, key end
	short = trim(short)
	local builtin = (pack == Mova.IconPack or pack == "mova") and Mova.Icons[short] or nil
	if builtin ~= nil then return resolveIcon(builtin, depth) end
	if pack == "mova" then return nil end
	local tbl = loadIconPack(pack)
	if not tbl then return nil end
	local entry = tbl[short] or tbl[(short:gsub("[_%s]", "-"))] or tbl[(short:gsub("[%-%s]", "_"))]
	if entry == nil then return nil end
	return resolveIcon(entry, depth)
end

resolveIcon = function(icon, depth)
	depth = (depth or 0) + 1
	if depth > 4 or icon == nil or icon == 0 or icon == "" or icon == false then return nil end
	local kind = typeof(icon)
	if kind == "table" then return iconFromEntry(icon, depth) end
	local id, uri
	if kind == "number" then
		id = math.floor(icon)
	elseif kind == "string" then
		local s = trim(icon)
		if s == "" then return nil end
		if s:match("^%d+$") then
			id = tonumber(s)
		elseif s:match("^rbxassetid://%d+$") then
			id = tonumber(s:match("%d+"))
		elseif s:match("^rbx%a+://") then
			uri = s
		else
			return iconFromName(s, depth)
		end
	else
		return nil
	end
	if uri then
		-- only per-machine custom assets and player thumbnails are allowed in secure mode
		if SecureMode and not (uri:match("^rbxasset://") or uri:match("^rbxthumb://")) then return nil end
		return iconSpec(uri)
	end
	if not id or id <= 0 then return nil end
	if SecureMode then return cachedAsset(id) end
	return iconSpec("rbxassetid://" .. tostring(id))
end

-- Writes a resolved spec onto an ImageLabel / ImageButton (rect fields included, pending cache hooked up).
local function applyIcon(obj, spec)
	if not spec then
		obj.Image = ""
		return false
	end
	obj.Image = spec.Image or ""
	if spec.RectSize then obj.ImageRectSize = spec.RectSize end
	if spec.RectOffset then obj.ImageRectOffset = spec.RectOffset end
	if spec.Pending then
		local ready = IconCache.uris[spec.Pending]
		if ready then
			obj.Image = ready -- the download finished before the label existed
		else
			local waiters = IconCache.waiting[spec.Pending]
			if waiters then table.insert(waiters, obj) end
		end
	end
	return true
end
Mova.ResolveIcon = function(_, icon) return resolveIcon(icon) end

---------------------------------------------------------------------------------------------------
-- Themes
---------------------------------------------------------------------------------------------------

local function C(r, g, b) return Color3.fromRGB(r, g, b) end

Mova.Themes.Dark = {
	Name = "Dark",
	Background = C(26, 26, 31),
	Sidebar = C(20, 20, 24),
	Surface = C(44, 44, 52),
	SurfaceHover = C(54, 54, 63),
	Stroke = C(70, 70, 82),
	Accent = C(99, 125, 255),
	AccentHover = C(122, 144, 255),
	OnAccent = C(255, 255, 255),
	Highlight = C(99, 125, 255),            -- section header line, left end
	HighlightEnd = C(168, 120, 255),        -- ... fading into this towards the right
	Text = C(240, 240, 245),
	TextDim = C(160, 162, 176),
	Placeholder = C(160, 162, 176),
	Divider = C(48, 48, 56),
	Shadow = C(0, 0, 0),
	Knob = C(228, 228, 235),
	Track = C(64, 64, 75),
	Field = C(56, 56, 66),
	Scrollbar = C(92, 92, 104),
	Overlay = C(0, 0, 0),
	Success = C(72, 199, 142),
	Warning = C(255, 184, 77),
	Error = C(240, 84, 84),
	Font = Enum.Font.GothamMedium,          -- fallback only (environments without Font.new)
	TitleFont = Enum.Font.GothamBold,       -- fallback only
	FontFamily = "rbxasset://fonts/families/GothamSSm.json", -- built-in family, weights via FontFace
	Radius = 10,                            -- element corner radius
	WindowRadius = 14,
	StrokeTransparency = 0.55,              -- resting element outline
}

local function derive(base, overrides)
	local t = shallowCopy(base)
	for k, v in pairs(overrides) do t[k] = v end
	-- placeholder text must stay readable on that theme's fields: follow TextDim unless set explicitly
	if overrides.TextDim and not overrides.Placeholder then t.Placeholder = overrides.TextDim end
	-- a theme that recolours the accent but says nothing about the section highlight follows it
	if overrides.Accent and not overrides.Highlight then
		t.Highlight = overrides.Accent
		t.HighlightEnd = overrides.HighlightEnd or overrides.AccentHover or overrides.Accent
	end
	return t
end

-- Default. Monochrome in the Obsidian / Linoria spirit: near-black panels, a single off-white accent,
-- hairline white outlines at ~10% so every edge is drawn but nothing shouts.
Mova.Themes.Mono = derive(Mova.Themes.Dark, {
	Name = "Mono",
	Highlight = C(255, 255, 255),
	HighlightEnd = C(150, 150, 160),
	Background = C(20, 20, 23),
	Sidebar = C(14, 14, 16),
	Surface = C(38, 38, 44),
	SurfaceHover = C(48, 48, 55),
	Stroke = C(255, 255, 255),
	StrokeTransparency = 0.86,
	Divider = C(46, 46, 52),
	Accent = C(228, 228, 232),
	AccentHover = C(255, 255, 255),
	OnAccent = C(18, 18, 20),
	Text = C(240, 240, 243),
	TextDim = C(158, 158, 168),
	Placeholder = C(158, 158, 168),
	Knob = C(236, 236, 240),
	Track = C(60, 60, 68),
	Field = C(50, 50, 57),
	Scrollbar = C(84, 84, 92),
	Success = C(128, 204, 164),
	Warning = C(232, 190, 110),
	Error = C(232, 110, 110),
	Radius = 12,
	WindowRadius = 18,
})

Mova.Themes.Light = derive(Mova.Themes.Dark, {
	Name = "Light",
	Highlight = C(70, 100, 240),
	HighlightEnd = C(150, 110, 255),
	Background = C(244, 244, 247),
	Sidebar = C(236, 236, 241),
	Surface = C(255, 255, 255),
	SurfaceHover = C(246, 246, 250),
	Stroke = C(218, 218, 226),
	Accent = C(70, 100, 240),
	AccentHover = C(90, 118, 250),
	Text = C(25, 25, 30),
	TextDim = C(90, 93, 106),
	Placeholder = C(90, 93, 106),
	Divider = C(218, 218, 226),
	Shadow = C(120, 120, 140),
	Knob = C(255, 255, 255),
	Track = C(205, 205, 215),
	Field = C(246, 246, 250),
	Scrollbar = C(180, 180, 190),
	Overlay = C(40, 40, 50),
})

Mova.Themes.Midnight = derive(Mova.Themes.Dark, {
	Name = "Midnight",
	Highlight = C(84, 160, 255),
	HighlightEnd = C(150, 205, 255),
	Background = C(19, 23, 35),
	Sidebar = C(14, 17, 27),
	Surface = C(35, 42, 62),
	SurfaceHover = C(44, 52, 76),
	Stroke = C(60, 71, 102),
	Divider = C(40, 48, 68),
	Accent = C(84, 160, 255),
	AccentHover = C(110, 178, 255),
	Field = C(47, 56, 82),
	Track = C(56, 66, 94),
})

Mova.Themes.Ocean = derive(Mova.Themes.Dark, {
	Name = "Ocean",
	Highlight = C(0, 190, 170),
	HighlightEnd = C(90, 220, 120),
	Background = C(19, 36, 43),
	Sidebar = C(14, 28, 34),
	Surface = C(33, 60, 70),
	SurfaceHover = C(41, 72, 84),
	Stroke = C(56, 94, 108),
	Divider = C(38, 68, 80),
	Accent = C(0, 190, 170),
	AccentHover = C(30, 210, 190),
	OnAccent = C(5, 25, 25),
	Field = C(44, 76, 88),
	TextDim = C(178, 196, 206),
	Track = C(52, 88, 102),
})

Mova.Themes.Ember = derive(Mova.Themes.Dark, {
	Name = "Ember",
	Highlight = C(255, 112, 67),
	HighlightEnd = C(255, 190, 80),
	Background = C(34, 24, 22),
	Sidebar = C(27, 19, 17),
	Surface = C(55, 40, 36),
	SurfaceHover = C(66, 48, 44),
	Stroke = C(86, 64, 58),
	Divider = C(62, 46, 42),
	Accent = C(255, 112, 67),
	AccentHover = C(255, 136, 96),
	Field = C(70, 52, 47),
	Track = C(80, 60, 54),
})

Mova.Themes.Amethyst = derive(Mova.Themes.Dark, {
	Name = "Amethyst",
	Highlight = C(170, 110, 255),
	HighlightEnd = C(255, 110, 200),
	Background = C(28, 22, 40),
	Sidebar = C(22, 17, 31),
	Surface = C(47, 38, 66),
	SurfaceHover = C(57, 46, 80),
	Stroke = C(76, 62, 104),
	Divider = C(54, 44, 74),
	Accent = C(170, 110, 255),
	AccentHover = C(188, 138, 255),
	Field = C(60, 50, 84),
	Track = C(72, 58, 98),
})

Mova.Themes.Rose = derive(Mova.Themes.Dark, {
	Name = "Rose",
	Highlight = C(255, 92, 140),
	HighlightEnd = C(255, 165, 100),
	Background = C(36, 23, 29),
	Sidebar = C(29, 18, 23),
	Surface = C(58, 39, 48),
	SurfaceHover = C(70, 47, 58),
	Stroke = C(92, 64, 78),
	Divider = C(66, 46, 56),
	Accent = C(255, 92, 140),
	AccentHover = C(255, 120, 160),
	Field = C(74, 50, 62),
	Track = C(86, 60, 72),
})

Mova.Themes.Mocha = derive(Mova.Themes.Dark, {
	Name = "Mocha",
	Highlight = C(203, 166, 247),
	HighlightEnd = C(245, 194, 231),
	Background = C(36, 36, 55),
	Sidebar = C(30, 30, 46),
	Surface = C(57, 58, 82),
	SurfaceHover = C(67, 68, 96),
	Stroke = C(86, 88, 118),
	Divider = C(64, 66, 92),
	Accent = C(203, 166, 247),
	AccentHover = C(216, 185, 252),
	OnAccent = C(30, 30, 46),
	Text = C(205, 214, 244),
	TextDim = C(180, 186, 212),
	Field = C(70, 72, 100),
	Track = C(80, 82, 110),
})

local ThemeOrder = { "Mono", "Dark", "Light", "Midnight", "Ocean", "Ember", "Amethyst", "Rose", "Mocha" }

local CurrentTheme = shallowCopy(Mova.Themes.Mono)
-- NOT weak-keyed on purpose: in Roblox an Instance held only as a weak key is collected as soon as
-- no strong Lua reference remains, even though the Instance is still in the tree. With weak tables
-- every binding that wasn't also kept in a local (corner fillers, fields, the title dot...) silently
-- dropped out and stayed in the old colours after SetTheme. Entries are pruned instead when the
-- instance has left the tree (Destroy() sets Parent = nil).
local ThemeRegistry = {}
local ThemeHooks = {} -- instance -> function() run after a theme change
local function pruneRegistry(t)
	for obj in pairs(t) do
		local ok, parent = pcall(function() return obj.Parent end)
		if not ok or parent == nil then t[obj] = nil end
	end
end

local function onTheme(instance, fn)
	ThemeHooks[instance] = fn
	fn()
end

local THEMED_PROPS = {
	BackgroundColor3 = true, TextColor3 = true, ImageColor3 = true, Color = true,
	ScrollBarImageColor3 = true, PlaceholderColor3 = true, Font = true, TextStrokeColor3 = true,
	BorderColor3 = true,
}

function Mova:RegisterTheme(name, theme)
	assert(typeof(name) == "string", "theme name must be a string")
	local t = derive(Mova.Themes.Dark, theme or {})
	t.Name = name
	Mova.Themes[name] = t
	if not indexOf(ThemeOrder, name) then
		ThemeOrder[#ThemeOrder + 1] = name
	end
	return t
end

function Mova:GetThemeNames()
	local names = {}
	for i = 1, #ThemeOrder do names[i] = ThemeOrder[i] end
	return names
end

function Mova:GetTheme()
	return CurrentTheme
end

local function themeValue(key)
	return CurrentTheme[key]
end

local function tween(obj, props, time, style, dir)
	if not obj or not TweenService then return nil end
	local ok, tw = pcall(function()
		return TweenService:Create(obj, TweenInfo.new(time or 0.2, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out), props)
	end)
	if ok and tw then
		tw:Play()
		return tw
	end
	return nil
end

local setFont -- defined with the font helpers below

local function applyThemeToObject(obj, map, animate)
	local colorProps = {}
	for property, key in pairs(map) do
		if property == "FontFace" and typeof(key) == "string" and key:sub(1, 1) == "@" then
			setFont(obj, key:sub(2))
			key = nil
		end
		local value = key and CurrentTheme[key]
		if value ~= nil then
			if typeof(value) == "Color3" and animate then
				colorProps[property] = value
			else
				pcall(function() obj[property] = value end)
			end
		end
	end
	if animate and next(colorProps) then
		if not tween(obj, colorProps, 0.25) then
			for property, value in pairs(colorProps) do
				pcall(function() obj[property] = value end)
			end
		end
	end
end

local function bindTheme(obj, map)
	local existing = ThemeRegistry[obj]
	if existing then
		for k, v in pairs(map) do existing[k] = v end
	else
		ThemeRegistry[obj] = shallowCopy(map)
	end
	applyThemeToObject(obj, map, false)
end

function Mova:SetTheme(theme, animate)
	local resolved
	if typeof(theme) == "string" then
		resolved = Mova.Themes[theme]
		if not resolved then
			for name, t in pairs(Mova.Themes) do
				if name:lower() == theme:lower() then resolved = t end
			end
		end
		if not resolved then
			warn("[Mova] unknown theme '" .. theme .. "', keeping current")
			return false
		end
	elseif typeof(theme) == "table" then
		resolved = derive(Mova.Themes.Dark, theme)
		resolved.Name = theme.Name or "Custom"
	else
		return false
	end
	CurrentTheme = shallowCopy(resolved)
	if animate == nil then animate = true end
	pruneRegistry(ThemeRegistry)
	pruneRegistry(ThemeHooks)
	for obj, map in pairs(ThemeRegistry) do
		applyThemeToObject(obj, map, animate)
	end
	for _, hook in pairs(ThemeHooks) do pcall(hook) end
	for _, win in ipairs(Mova.Windows) do
		if win._onThemeChanged then pcall(win._onThemeChanged, win) end
	end
	return true
end

---------------------------------------------------------------------------------------------------
-- Instance factory
-- New("Frame", { BackgroundColor3 = "Surface", Size = ... }, { children })
-- A string value on a themed property (see THEMED_PROPS) binds it to that theme key.
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Fonts: one built-in family (theme.FontFamily) rendered through FontFace weights.
-- Falls back to Enum.Font on environments without Font.new.
---------------------------------------------------------------------------------------------------

local FontFaceSupported = (function()
	local ok = pcall(function()
		local f = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
		local l = Instance.new("TextLabel")
		l.FontFace = f
		l:Destroy()
	end)
	return ok
end)()

local FontCache = {}
local function fontFor(weight)
	local family = CurrentTheme.FontFamily or "rbxasset://fonts/families/GothamSSm.json"
	local key = family .. "|" .. weight
	local f = FontCache[key]
	if not f then
		local ok, built = pcall(function() return Font.new(family, Enum.FontWeight[weight] or Enum.FontWeight.Medium) end)
		f = ok and built or nil
		FontCache[key] = f
	end
	return f
end

setFont = function(obj, weight)
	weight = weight or "Medium"
	if FontFaceSupported then
		local f = fontFor(weight)
		if f then
			pcall(function() obj.FontFace = f end)
			return
		end
	end
	local heavy = weight == "SemiBold" or weight == "Bold"
	pcall(function() obj.Font = heavy and CurrentTheme.TitleFont or CurrentTheme.Font end)
end

local function New(className, props, children)
	local obj = Instance.new(className)
	local themeMap = nil
	props = props or {}
	-- defaults that every library ends up repeating
	if className == "Frame" or className == "ScrollingFrame" or className == "TextButton" or className == "TextLabel"
		or className == "TextBox" or className == "ImageLabel" or className == "ImageButton" or className == "CanvasGroup" then
		obj.BorderSizePixel = 0
	end
	local isText = className == "TextLabel" or className == "TextButton" or className == "TextBox"
	if isText then
		obj.TextSize = 14
		obj.BackgroundTransparency = 1
		obj.TextColor3 = CurrentTheme.Text
		if className == "TextButton" then obj.AutoButtonColor = false end
		if className == "TextBox" then obj.ClearTextOnFocus = false end
	end
	if className == "ImageLabel" or className == "ImageButton" then
		obj.BackgroundTransparency = 1
		if className == "ImageButton" then obj.AutoButtonColor = false end
	end
	if className == "ScrollingFrame" then
		obj.BackgroundTransparency = 1
		obj.ScrollBarThickness = 3
		obj.ScrollBarImageColor3 = CurrentTheme.Scrollbar
		obj.ScrollBarImageTransparency = 0.2
		obj.AutomaticCanvasSize = Enum.AutomaticSize.Y
		obj.CanvasSize = UDim2.new(0, 0, 0, 0)
		obj.ScrollingDirection = Enum.ScrollingDirection.Y
		obj.ElasticBehavior = Enum.ElasticBehavior.Never
		obj.TopImage = ""
		obj.BottomImage = ""
		obj.MidImage = ""
	end
	local parent = nil
	local weight = nil
	for key, value in pairs(props) do
		if key == "Parent" then
			parent = value
		elseif key == "Weight" then
			weight = value
		elseif key == "Font" and typeof(value) == "string" then
			weight = (value == "TitleFont") and "SemiBold" or "Medium"
		elseif key == "ThemeTag" then
			themeMap = themeMap or {}
			for p, k in pairs(value) do themeMap[p] = k end
		elseif THEMED_PROPS[key] and typeof(value) == "string" and CurrentTheme[value] ~= nil then
			themeMap = themeMap or {}
			themeMap[key] = value
		elseif key == "Image" and className:match("^Image") then
			applyIcon(obj, resolveIcon(value))
		else
			obj[key] = value
		end
	end
	if isText then
		themeMap = themeMap or {}
		if typeof(props.Font) ~= "EnumItem" and themeMap.Font == nil then
			themeMap.FontFace = "@" .. (weight or "Medium")
		end
		if props.TextColor3 == nil and themeMap.TextColor3 == nil then themeMap.TextColor3 = "Text" end
	end
	if themeMap then bindTheme(obj, themeMap) end
	if children then
		for _, child in ipairs(children) do
			if child then child.Parent = obj end
		end
	end
	if parent then obj.Parent = parent end
	return obj
end

local function Corner(radius, parent)
	return New("UICorner", { CornerRadius = UDim.new(0, radius or CurrentTheme.Radius or 10), Parent = parent })
end

local function Stroke(parent, colorKey, thickness, transparency)
	return New("UIStroke", {
		Color = colorKey or "Stroke",
		Thickness = thickness or 1,
		Transparency = transparency or CurrentTheme.StrokeTransparency or 0.45,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

local function Padding(parent, top, right, bottom, left)
	return New("UIPadding", {
		PaddingTop = UDim.new(0, top or 0),
		PaddingRight = UDim.new(0, right or top or 0),
		PaddingBottom = UDim.new(0, bottom or top or 0),
		PaddingLeft = UDim.new(0, left or right or top or 0),
		Parent = parent,
	})
end

local function List(parent, spacing, direction, hAlign, vAlign)
	return New("UIListLayout", {
		Padding = UDim.new(0, spacing or 6),
		FillDirection = direction or Enum.FillDirection.Vertical,
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Left,
		VerticalAlignment = vAlign or Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = parent,
	})
end

local function textWidth(text, size, font)
	if TextService then
		local ok, v = pcall(function()
			return TextService:GetTextSize(tostring(text), size or 14, font or CurrentTheme.Font, Vector2.new(10000, 100))
		end)
		if ok and v then return v.X end
	end
	return #tostring(text) * (size or 14) * 0.55
end

local function hoverable(button, target, baseKey, hoverKey)
	target = target or button
	connect(button.MouseEnter, function()
		tween(target, { BackgroundColor3 = themeValue(hoverKey or "SurfaceHover") }, 0.15)
	end)
	connect(button.MouseLeave, function()
		tween(target, { BackgroundColor3 = themeValue(baseKey or "Surface") }, 0.15)
	end)
end

---------------------------------------------------------------------------------------------------
-- Motion + visual primitives
-- Easing vocabulary (borrowed from Gen 2 / Fluent): Quint-out for state changes, Exponential-out
-- for reveals, Back-out for things that should "land" (knobs, popups), Quint-in for exits.
---------------------------------------------------------------------------------------------------

local Motion = {
	fast = 0.12,
	base = 0.22,
	slow = 0.4,
	Quint = Enum.EasingStyle.Quint,
	Expo = Enum.EasingStyle.Exponential,
	Back = Enum.EasingStyle.Back,
	Out = Enum.EasingDirection.Out,
	In = Enum.EasingDirection.In,
	InOut = Enum.EasingDirection.InOut,
}

-- Focus / open state for fields: a soft accent ring (45% transparent) rather than a solid
-- outline, so focused inputs read as "active" without adding a hard border to the design.
local function focusRing(stroke, on, time)
	if not stroke then return end
	if on then
		tween(stroke, { Color = themeValue("Accent"), Transparency = 0.45 }, time or Motion.fast)
	else
		tween(stroke, { Color = themeValue("Stroke"), Transparency = CurrentTheme.StrokeTransparency }, time or Motion.base)
	end
end


-- UIShadow (2025+ engine) gives real soft shadows/glows without any image asset. Optional.
local HasUIShadow = pcall(function()
	local s = Instance.new("UIShadow")
	s:Destroy()
end)

local function Shadow(parent, colorKey, blur, transparency)
	if not HasUIShadow then return nil end
	local ok, shadow = pcall(New, "UIShadow", {
		Color = colorKey or "Shadow",
		BlurRadius = UDim.new(0, blur or 24),
		Transparency = transparency or 0.5,
		ZIndex = -1,
		Parent = parent,
	})
	return ok and shadow or nil
end

local function brighten(color, amount)
	return Color3.new(
		clamp(color.R + (1 - color.R) * amount, 0, 1),
		clamp(color.G + (1 - color.G) * amount, 0, 1),
		clamp(color.B + (1 - color.B) * amount, 0, 1)
	)
end

-- Gen 2 draws every surface as a white frame tinted by a vertical UIGradient (slightly lighter at
-- the top). Same trick here, kept theme-aware through a hook.
-- A UIGradient MULTIPLIES the frame's BackgroundColor3, so the frame underneath must be pure white
-- or the surface comes out as Surface x Surface (near black - which is exactly how the cards used to
-- render, darker than the page behind them).
local WHITE = Color3.new(1, 1, 1)
local function SurfaceGradient(parent, colorKey, amount, rotation)
	local g = New("UIGradient", { Rotation = rotation or 90, Parent = parent })
	onTheme(g, function()
		local base = themeValue(colorKey or "Surface")
		parent.BackgroundColor3 = WHITE
		g.Color = ColorSequence.new(brighten(base, amount or 0.035), base)
	end)
	return g
end

-- Icons drawn from rotated frames so nothing depends on fonts having a glyph or on asset ids.
local GLYPHS = {}
local function Glyph(kind, parent, colorKey, size, thickness)
	size = size or 16
	thickness = thickness or 1.6
	colorKey = colorKey or "TextDim"
	local holder = New("Frame", {
		Name = "Glyph", BackgroundTransparency = 1, Size = UDim2.fromOffset(size, size),
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Parent = parent,
	})
	local parts = {}
	local function line(len, rot, cx, cy)
		local f = New("Frame", {
			BackgroundColor3 = colorKey, Size = UDim2.fromOffset(len, thickness), Rotation = rot,
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, cx or 0, 0.5, cy or 0), Parent = holder,
		})
		Corner(math.ceil(thickness), f)
		parts[#parts + 1] = f
		return f
	end
	if kind == "close" then
		line(size * 0.72, 45)
		line(size * 0.72, -45)
	elseif kind == "minus" then
		line(size * 0.6, 0)
	elseif kind == "plus" then
		line(size * 0.6, 0)
		line(size * 0.6, 90)
	elseif kind == "chevron-down" or kind == "chevron-up" or kind == "chevron-right" or kind == "chevron-left" then
		local len = size * 0.42
		local off = len * 0.33
		if kind == "chevron-down" then
			line(len, 45, -off, -off * 0.5)
			line(len, -45, off, -off * 0.5)
		elseif kind == "chevron-up" then
			line(len, -45, -off, off * 0.5)
			line(len, 45, off, off * 0.5)
		elseif kind == "chevron-right" then
			line(len, 45, off * 0.5, -off)   -- "\" on top, "/" below -> ">"
			line(len, -45, off * 0.5, off)
		else
			line(len, -45, -off * 0.5, -off) -- "/" on top, "\" below -> "<"
			line(len, 45, -off * 0.5, off)
		end
	elseif kind == "check" then
		line(size * 0.3, 45, -size * 0.2, size * 0.08)
		line(size * 0.55, -45, size * 0.08, -size * 0.02)
	elseif kind == "search" then
		local ring = New("Frame", {
			BackgroundTransparency = 1, Size = UDim2.fromOffset(size * 0.55, size * 0.55),
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, -size * 0.08, 0.5, -size * 0.08), Parent = holder,
		})
		Corner(size, ring)
		parts[#parts + 1] = New("UIStroke", { Color = colorKey, Thickness = thickness, Parent = ring })
		line(size * 0.3, 45, size * 0.22, size * 0.22)
	elseif kind == "resize" then
		line(size * 0.8, -45, size * 0.1, size * 0.1)
		line(size * 0.4, -45, size * 0.26, size * 0.26)
	elseif kind == "dot" then
		local d = New("Frame", { BackgroundColor3 = colorKey, Size = UDim2.fromOffset(size * 0.4, size * 0.4), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Parent = holder })
		Corner(size, d)
		parts[#parts + 1] = d
	elseif kind == "grip" then
		for i = -1, 1 do
			local d = New("Frame", { BackgroundColor3 = colorKey, Size = UDim2.fromOffset(3, 3), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, i * 5), Parent = holder })
			Corner(3, d)
			parts[#parts + 1] = d
		end
	end
	GLYPHS[holder] = parts
	return holder
end

local function tintGlyph(holder, color, time)
	local parts = GLYPHS[holder]
	if not parts then return end
	for _, part in ipairs(parts) do
		if part:IsA("UIStroke") then
			tween(part, { Color = color }, time or Motion.fast)
		else
			tween(part, { BackgroundColor3 = color }, time or Motion.fast)
		end
	end
end

local function rebindGlyph(holder, colorKey)
	local parts = GLYPHS[holder]
	if not parts then return end
	for _, part in ipairs(parts) do
		bindTheme(part, { [part:IsA("UIStroke") and "Color" or "BackgroundColor3"] = colorKey })
	end
end

-- Hover: a text-coloured wash (so it reads on light and dark themes) + a brighter outline.
local function hoverOverlay(parent)
	local overlay = New("Frame", {
		Name = "Hover", BackgroundColor3 = "Text", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 1, Parent = parent,
	})
	Corner(nil, overlay)
	return overlay
end

local function hoverFx(trigger, overlay, stroke, opts)
	if IsMobile then return end
	opts = opts or {}
	local strength = opts.strength or 0.95
	connect(trigger.MouseEnter, function()
		if opts.enabled and not opts.enabled() then return end
		if overlay then tween(overlay, { BackgroundTransparency = strength }, Motion.base) end
		if stroke then tween(stroke, { Transparency = math.max(0, (CurrentTheme.StrokeTransparency or 0.45) - 0.2) }, Motion.base) end
	end)
	connect(trigger.MouseLeave, function()
		if overlay then tween(overlay, { BackgroundTransparency = 1 }, Motion.slow) end
		if stroke then tween(stroke, { Transparency = CurrentTheme.StrokeTransparency or 0.45 }, Motion.slow) end
	end)
end

-- Press: cards shrink 8px symmetrically (pages centre their children) and spring back.
local Pressing = {} -- card -> resting size while a press animation runs
local Compact = {}  -- cards that share a row: no width bounce (it would shove the neighbours)
local function pressFx(card)
	if Compact[card] then return end
	local size = Pressing[card] or card.Size
	Pressing[card] = size
	tween(card, { Size = UDim2.new(size.X.Scale, size.X.Offset - 8, size.Y.Scale, size.Y.Offset) }, 0.08, Motion.Quint, Motion.Out)
	task.delay(0.09, function()
		if card.Parent then
			tween(card, { Size = size }, 0.45, Motion.Expo, Motion.Out)
		end
		task.delay(0.45, function() if Pressing[card] == size then Pressing[card] = nil end end)
	end)
end

-- Touch-dragging a control inside a ScrollingFrame also scrolls the page; freeze every ancestor
-- ScrollingFrame for the duration of the gesture and hand back an unlock.
local function lockScroll(obj)
	local locked = {}
	local p = obj and obj.Parent
	while p do
		if p:IsA("ScrollingFrame") and p.ScrollingEnabled then
			p.ScrollingEnabled = false
			locked[#locked + 1] = p
		end
		p = p.Parent
	end
	return function()
		for _, sf in ipairs(locked) do pcall(function() sf.ScrollingEnabled = true end) end
	end
end

-- Quick white flash used for button taps.
local function flash(overlay)
	tween(overlay, { BackgroundTransparency = 0.86 }, 0.05)
	task.delay(0.06, function() tween(overlay, { BackgroundTransparency = 1 }, 0.35, Motion.Quint, Motion.Out) end)
end

---------------------------------------------------------------------------------------------------
-- Localisation
---------------------------------------------------------------------------------------------------

local Translations = {}
local CurrentLocale = "en"
local LangRegistry = {} -- strong for the same reason as ThemeRegistry; pruned on SetLocale

local function translate(text)
	if typeof(text) ~= "string" then return text end
	local table_ = Translations[CurrentLocale]
	if table_ and table_[text] then return table_[text] end
	return text
end

local function bindText(obj, source)
	LangRegistry[obj] = source
	obj.Text = translate(source)
end

function Mova:SetTranslations(t)
	Translations = t or {}
end

function Mova:SetLocale(locale)
	CurrentLocale = locale or "en"
	pruneRegistry(LangRegistry)
	for obj, source in pairs(LangRegistry) do
		pcall(function() obj.Text = translate(source) end)
	end
end

function Mova:Translate(text)
	return translate(text)
end

---------------------------------------------------------------------------------------------------
-- Value serialisation (configs)
---------------------------------------------------------------------------------------------------

local function encodeValue(v)
	local t = typeof(v)
	if t == "Color3" then
		return { __type = "Color3", r = v.R, g = v.G, b = v.B }
	elseif t == "EnumItem" then
		return { __type = "Enum", enum = tostring(v.EnumType), name = v.Name }
	elseif t == "Vector2" then
		return { __type = "Vector2", x = v.X, y = v.Y }
	elseif t == "table" then
		local out = {}
		for k, val in pairs(v) do out[k] = encodeValue(val) end
		return out
	end
	return v
end

local function decodeValue(v)
	if typeof(v) ~= "table" then return v end
	if v.__type == "Color3" then
		return Color3.new(v.r or 0, v.g or 0, v.b or 0)
	elseif v.__type == "Enum" then
		local ok, item = pcall(function() return Enum[v.enum][v.name] end)
		if ok then return item end
		return nil
	elseif v.__type == "Vector2" then
		return Vector2.new(v.x or 0, v.y or 0)
	end
	local out = {}
	for k, val in pairs(v) do out[k] = decodeValue(val) end
	return out
end

---------------------------------------------------------------------------------------------------
-- Key names
---------------------------------------------------------------------------------------------------

local KeyNames = {
	LeftControl = "LCtrl", RightControl = "RCtrl", LeftShift = "LShift", RightShift = "RShift",
	LeftAlt = "LAlt", RightAlt = "RAlt", Return = "Enter", BackSpace = "Backspace",
	MouseButton1 = "MB1", MouseButton2 = "MB2", MouseButton3 = "MB3", Escape = "Esc",
	Zero = "0", One = "1", Two = "2", Three = "3", Four = "4", Five = "5", Six = "6", Seven = "7", Eight = "8", Nine = "9",
}

local function keyToString(key)
	if key == nil then return "None" end
	local name = typeof(key) == "EnumItem" and key.Name or tostring(key)
	return KeyNames[name] or name
end

local function keyFromName(name)
	if typeof(name) == "EnumItem" then return name end
	if typeof(name) ~= "string" or name == "" or name == "None" then return nil end
	local ok, k = pcall(function() return Enum.KeyCode[name] end)
	if ok and k then return k end
	ok, k = pcall(function() return Enum.UserInputType[name] end)
	if ok and k then return k end
	return nil
end

local KeybindListening = false
local ActiveKeybindListener = nil -- stop() of the field currently waiting for a key

local function inputToKey(input)
	if input.UserInputType == Enum.UserInputType.Keyboard then
		return input.KeyCode
	elseif input.UserInputType == Enum.UserInputType.MouseButton2
		or input.UserInputType == Enum.UserInputType.MouseButton3 then
		return input.UserInputType
	end
	return nil
end

-- Obsidian's rule for "should a hotkey fire": not while any TextBox has focus. Roblox's
-- gameProcessedEvent is wrong for this - it is also true for keys the game's own control
-- scripts consume (WASD, Space, Shift, E near a prompt...), which made keybinds on those keys
-- silently dead.
local function isTyping()
	if not UserInputService then return false end
	local ok, box = pcall(UserInputService.GetFocusedTextBox, UserInputService)
	return ok and box ~= nil
end
local function hasKeyboard()
	if not UserInputService then return true end
	local ok, v = pcall(function() return UserInputService.KeyboardEnabled end)
	if ok and v == false then return false end
	return true
end

---------------------------------------------------------------------------------------------------
-- Root ScreenGui + overlay layers (shared by every window)
---------------------------------------------------------------------------------------------------

local Root = nil
local Layers = {}
local function getRoot()
	if Root and Root.Parent then return Root end
	local container = getGuiContainer()
	Root = New("ScreenGui", {
		Name = HttpService and HttpService:GenerateGUID(false) or "Mova",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 999,
	})
	pcall(function() Root.ClipToDeviceSafeArea = false end)
	Root.Parent = container
	-- overlay layers: popups (dropdown lists, colour pickers) < dialogs < notifications
	Layers.popup = New("Frame", {
		Name = "Popups", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 50, Parent = Root,
	})
	Layers.dialog = New("Frame", {
		Name = "Dialogs", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 100, Parent = Root,
	})
	Layers.notify = New("Frame", {
		Name = "Notifications", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 150, Parent = Root,
	})
	return Root
end

-- Height of Roblox's own top bar. Our ScreenGui ignores the inset so the window can use the whole
-- screen, which means anything we park at the very top must be pushed below the inset or Roblox's
-- top bar will swallow the taps (this is what made the reopen pill unclickable).
local function topInset()
	if GuiService and Root and Root.IgnoreGuiInset then
		local ok, v = pcall(function() return GuiService:GetGuiInset() end)
		if ok and v then return v.Y end
	end
	return 0
end

local function viewportSize()
	local ok, cam = pcall(function() return workspace.CurrentCamera end)
	if ok and cam and cam.ViewportSize and cam.ViewportSize.X > 0 then
		return cam.ViewportSize
	end
	if Root and Root.AbsoluteSize and Root.AbsoluteSize.X > 0 then
		return Root.AbsoluteSize
	end
	return Vector2.new(1280, 720)
end

---------------------------------------------------------------------------------------------------
-- Popups (anything that floats above the window and closes on outside click)
---------------------------------------------------------------------------------------------------

local OpenPopup = nil

local function closePopup()
	if OpenPopup then
		local p = OpenPopup
		OpenPopup = nil
		if p.onClose then pcall(p.onClose) end
	end
end

local function openPopup(frame, anchorObject, onClose)
	closePopup()
	OpenPopup = { frame = frame, anchor = anchorObject, onClose = onClose }
end

local function pointInside(obj, pos)
	if not obj or not obj.AbsolutePosition then return false end
	local p, s = obj.AbsolutePosition, obj.AbsoluteSize
	return pos.X >= p.X and pos.X <= p.X + s.X and pos.Y >= p.Y and pos.Y <= p.Y + s.Y
end

local function positionPopup(frame, anchor, width, height)
	local vp = viewportSize()
	local ap, as = anchor.AbsolutePosition, anchor.AbsoluteSize
	local inset = 0
	if GuiService then
		local ok, v = pcall(function() return GuiService:GetGuiInset() end)
		if ok and v and Root and not Root.IgnoreGuiInset then inset = v.Y end
	end
	local base = Layers.popup and Layers.popup.AbsolutePosition or Vector2.new(0, 0)
	ap = ap - base
	local x = ap.X + as.X - width
	local y = ap.Y + as.Y + 6 + inset
	if y + height > vp.Y - 8 then
		y = ap.Y - height - 6 + inset
	end
	local top = topInset() + 8
	x = clamp(x, 8, math.max(8, vp.X - width - 8))
	y = clamp(y, top, math.max(top, vp.Y - height - 8))
	frame.Position = UDim2.fromOffset(x, y)
	frame.Size = UDim2.fromOffset(width, height)
end

if UserInputService then
	connect(UserInputService.InputBegan, function(input, processed)
		if not OpenPopup then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			local pos = input.Position
			local inside = pointInside(OpenPopup.frame, pos) or pointInside(OpenPopup.anchor, pos)
			if not inside then
				closePopup()
			end
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- Dragging (mouse + touch), keeps the frame on screen
---------------------------------------------------------------------------------------------------

local function makeDraggable(frame, handle, options)
	options = options or {}
	local dragging, dragInput, startPos, startFrame
	local conns = {}
	local function update(input)
		local delta = input.Position - startPos
		local x = startFrame.X.Offset + delta.X
		local y = startFrame.Y.Offset + delta.Y
		if options.keepOnScreen ~= false then
			local vp = viewportSize()
			local size = frame.AbsoluteSize
			local ax, ay = frame.AnchorPoint.X, frame.AnchorPoint.Y
			local top = topInset()
			x = clamp(x, size.X * ax, math.max(size.X * ax, vp.X - size.X * (1 - ax)))
			y = clamp(y, size.Y * ay + top, math.max(size.Y * ay + top, vp.Y - size.Y * (1 - ay)))
		end
		frame.Position = UDim2.fromOffset(x, y)
		if options.onDrag then options.onDrag(frame.Position, delta) end
	end
	conns[#conns + 1] = connect(handle.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if options.canDrag and not options.canDrag() then return end
			dragging = true
			startPos = input.Position
			-- normalise to offset-only positioning so deltas are simple
			local ap = frame.AbsolutePosition
			local size = frame.AbsoluteSize
			local anchor = frame.AnchorPoint
			-- AbsolutePosition is measured below Roblox's top bar even when the ScreenGui ignores the
			-- inset, while Position offsets start at the real top of the screen: add the inset back or
			-- the frame jumps up by one top-bar height on the first move (verified by Gen 2 in play).
			local inset = topInset()
			startFrame = UDim2.fromOffset(ap.X + size.X * anchor.X, ap.Y + inset + size.Y * anchor.Y)
			frame.Position = startFrame
			if options.onDragStart then options.onDragStart() end
			local changed
			changed = input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
					if changed then changed:Disconnect() changed = nil end
					if options.onDragEnd then options.onDragEnd(frame.Position) end
				end
			end)
		end
	end)
	conns[#conns + 1] = connect(handle.InputChanged, function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			dragInput = input
		end
	end)
	conns[#conns + 1] = connect(UserInputService and UserInputService.InputChanged, function(input)
		if dragging and input == dragInput then
			update(input)
		end
	end)
	return conns
end

local function makeResizable(frame, handle, minSize, maxSize, onResize)
	local resizing, startPos, startSize
	connect(handle.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			resizing = true
			startPos = input.Position
			startSize = frame.AbsoluteSize
			connect(input.Changed, function()
				if input.UserInputState == Enum.UserInputState.End then resizing = false end
			end)
		end
	end)
	connect(UserInputService and UserInputService.InputChanged, function(input)
		if not resizing then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			local delta = input.Position - startPos
			local vp = viewportSize()
			local w = clamp(startSize.X + delta.X, minSize.X, math.min(maxSize.X, vp.X - 16))
			local h = clamp(startSize.Y + delta.Y, minSize.Y, math.min(maxSize.Y, vp.Y - 16))
			frame.Size = UDim2.fromOffset(w, h)
			if onResize then onResize(w, h) end
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- Notifications
---------------------------------------------------------------------------------------------------

local NotifyHolder = nil
local function getNotifyHolder()
	if NotifyHolder and NotifyHolder.Parent then return NotifyHolder end
	local root = getRoot()
	NotifyHolder = New("Frame", {
		Name = "NotifyHolder",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -16),
		Size = UDim2.fromOffset(IsMobile and 248 or 272, 600), -- Gen 2 keeps these around 260; a wide toast reads as a panel
		Parent = Layers.notify,
	})
	List(NotifyHolder, 8, Enum.FillDirection.Vertical, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Bottom)
	return NotifyHolder
end

function Mova:Notify(props)
	if typeof(props) == "string" then props = { Content = props } end
	props = props or {}
	local title = prop(props, nil, "Title", "title")
	local content = prop(props, "", "Content", "content", "Description", "Text")
	local duration = prop(props, nil, "Duration", "duration")
	local icon = prop(props, nil, "Icon", "icon", "Image")
	local kind = prop(props, "Info", "Type", "type")
	local actions = prop(props, nil, "Actions", "actions", "Buttons")
	if duration == nil then
		-- read time from the content length (Gen 2's autoDuration), clamped to 3-9s
		duration = clamp(#tostring(content) * 0.06 + 3, 3, 9)
	end

	local holder = getNotifyHolder()
	local accentKey = (kind == "Error" and "Error") or (kind == "Success" and "Success") or (kind == "Warning" and "Warning") or "Accent"

	-- slot sits in the list layout; the card inside it is what slides so the layout never fights the tween
	local slot = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = holder })
	local card = New("Frame", {
		BackgroundColor3 = "Surface",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.fromOffset(320, 0),
		ClipsDescendants = true,
		BackgroundTransparency = 1,
		Parent = slot,
	})
	Corner(12, card)
	local cardStroke = Stroke(card)
	cardStroke.Transparency = 1
	Shadow(card, "Shadow", 32, 0.4)
	Padding(card, 11, 14, 11, 14)
	-- Time left is shown as a quiet wash of the type colour behind the text that drains from
	-- right to left (WindUI's duration fill) instead of a hairline under the card. It is a child
	-- of the card, so the padding offsets it: counter the padding to cover the whole card.
	local wash = nil
	if duration and duration > 0 then
		wash = New("Frame", {
			BackgroundColor3 = accentKey, BackgroundTransparency = 0.9,
			Position = UDim2.fromOffset(-14, -11), Size = UDim2.new(1, 28, 1, 22), ZIndex = 0, Parent = card,
		})
		Corner(12, wash)
		-- the trailing edge dissolves instead of ending in a second rounded "card" edge
		New("UIGradient", {
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(0.7, 0), NumberSequenceKeypoint.new(1, 1) }),
			Parent = wash,
		})
	end

	local iconImage = resolveIcon(icon)
	local textLeft = iconImage and 28 or 0
	if iconImage then
		New("ImageLabel", {
			Image = iconImage, ImageColor3 = accentKey, Size = UDim2.fromOffset(18, 18), Position = UDim2.fromOffset(0, 1), Parent = card,
		})
	end

	local body = New("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -textLeft, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.fromOffset(textLeft, 0),
		Parent = card,
	})
	List(body, 3)
	if title then
		local titleRow = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 1, Parent = body })
		local dotLeft = 0
		if not iconImage then
			-- type is shown by a small dot next to the title (no coloured bars or outlines)
			local dot = New("Frame", { BackgroundColor3 = accentKey, Size = UDim2.fromOffset(6, 6), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Parent = titleRow })
			Corner(3, dot)
			dotLeft = 12
		end
		New("TextLabel", {
			Text = tostring(title), Weight = "SemiBold", TextSize = 14, TextColor3 = "Text",
			Size = UDim2.new(1, -dotLeft, 1, 0), Position = UDim2.fromOffset(dotLeft, 0), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = titleRow,
		})
	end
	if content and content ~= "" then
		New("TextLabel", {
			Text = tostring(content), TextSize = 13, TextColor3 = "TextDim", TextWrapped = true, LineHeight = 1.1,
			Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
			LayoutOrder = 2, Parent = body,
		})
	end

	local closed = false
	local function close()
		if closed then return end
		closed = true
		tween(card, { BackgroundTransparency = 1, Position = UDim2.fromOffset(320, 0) }, 0.3, Motion.Quint, Motion.In)
		tween(cardStroke, { Transparency = 1 }, 0.15)
		if wash then tween(wash, { BackgroundTransparency = 1 }, 0.15) end
		for _, d in ipairs(card:GetDescendants()) do
			pcall(function()
				if d:IsA("TextLabel") or d:IsA("TextButton") then tween(d, { TextTransparency = 1 }, 0.15) end
				if d:IsA("ImageLabel") then tween(d, { ImageTransparency = 1 }, 0.15) end
			end)
		end
		task.delay(0.32, function() slot:Destroy() end)
	end

	if typeof(actions) == "table" and #actions > 0 then
		-- compact action row: 22px chips with a 4px gap above the text, so a toast with buttons is
		-- only ~26px taller than one without
		local row = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 3, Parent = body })
		List(row, 6, Enum.FillDirection.Horizontal)
		Padding(row, 4, 0, 0, 0)
		for i, action in ipairs(actions) do
			local label = prop(action, "OK", "Text", "Name", "text", "name")
			local btn = New("TextButton", {
				Text = label, TextSize = 12, Weight = "SemiBold",
				BackgroundColor3 = i == 1 and "Accent" or "SurfaceHover",
				TextColor3 = i == 1 and "OnAccent" or "Text",
				BackgroundTransparency = 0,
				Size = UDim2.fromOffset(math.max(52, textWidth(label, 12) + 20), 22),
				LayoutOrder = i, Parent = row,
			})
			Corner(7, btn)
			local btnHover = hoverOverlay(btn)
			hoverFx(btn, btnHover, nil, { strength = 0.88 })
			connect(btn.MouseButton1Click, function()
				flash(btnHover)
				safeCallback(prop(action, nil, "Callback", "callback", "Func"))
				close()
			end)
		end
	end

	-- No close button: a tap anywhere on the card dismisses it (Gen 2), and hovering it pauses the
	-- timer so a long message can be read. The tap target sits under the action buttons.
	local hovered = false
	local tapZone = New("TextButton", {
		Text = "", BackgroundTransparency = 1, AutoButtonColor = false,
		Position = UDim2.fromOffset(-14, -11), Size = UDim2.new(1, 28, 1, 22), ZIndex = 0, Parent = card,
	})
	local tapConns = {}
	tapConns[1] = tapZone.MouseEnter:Connect(function() hovered = true end)
	tapConns[2] = tapZone.MouseLeave:Connect(function() hovered = false end)
	tapConns[3] = tapZone.MouseButton1Click:Connect(close)

	if duration and duration > 0 then
		-- dwell: advance only while not hovered; the wash follows the remaining fraction
		task.spawn(function()
			local elapsed = 0
			while not closed and card.Parent do
				local dt = task.wait()
				if type(dt) ~= "number" or dt <= 0 then dt = 1 / 60 end
				if not hovered then elapsed = elapsed + dt end
				local left = clamp(1 - elapsed / duration, 0, 1)
				if wash then wash.Size = UDim2.new(left, 28 * left, 1, 22) end
				if elapsed >= duration then break end
			end
			if not closed then close() end
		end)
	end

	-- slide in from the right edge
	tween(card, { BackgroundTransparency = 0, Position = UDim2.fromOffset(0, 0) }, 0.45, Motion.Expo, Motion.Out)
	tween(cardStroke, { Transparency = CurrentTheme.StrokeTransparency }, 0.45)
	return { Close = close, Dismiss = close, Instance = card }
end

---------------------------------------------------------------------------------------------------
-- Dialog (modal)
---------------------------------------------------------------------------------------------------

function Mova:Dialog(props)
	props = props or {}
	local root = getRoot()
	local title = prop(props, "Dialog", "Title", "title")
	local content = prop(props, "", "Content", "content", "Text")
	local buttons = prop(props, { { Text = "OK" } }, "Buttons", "buttons", "Options", "Actions")
	local dismissable = prop(props, false, "Dismissable", "dismissable", "CloseOnClickOutside")

	local dim = New("TextButton", {
		Text = "", BackgroundColor3 = "Overlay", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), AutoButtonColor = false,
		Parent = Layers.dialog,
	})
	tween(dim, { BackgroundTransparency = 0.4 }, 0.3, Motion.Quint, Motion.Out)

	local vp = viewportSize()
	local width = math.min(380, vp.X - 32)
	local card = New("Frame", {
		BackgroundColor3 = "Surface",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 24),
		Size = UDim2.fromOffset(width, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = dim,
	})
	local cardCorner = Corner(CurrentTheme.WindowRadius or 14, card)
	local cardStroke = Stroke(card)
	cardStroke.Transparency = 1
	Shadow(card, "Shadow", 48, 0.35)
	local cardScale = New("UIScale", { Scale = 0.92, Parent = card })
	Padding(card, 18, 18, 18, 18)
	List(card, 10)
	-- pop in: Back Out scale, slide up, fade
	tween(card, { BackgroundTransparency = 0, Position = UDim2.fromScale(0.5, 0.5) }, 0.4, Motion.Expo, Motion.Out)
	tween(cardScale, { Scale = 1 }, 0.45, Motion.Back, Motion.Out)
	tween(cardStroke, { Transparency = CurrentTheme.StrokeTransparency }, 0.4)
	New("TextLabel", {
		Text = tostring(title), Weight = "SemiBold", TextSize = 16, Size = UDim2.new(1, 0, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 1, Parent = card,
	})
	New("TextLabel", {
		Text = tostring(content), TextSize = 13, TextColor3 = "TextDim", TextWrapped = true, LineHeight = 1.15,
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
		LayoutOrder = 2, Parent = card,
	})
	local row = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = 3, Parent = card })
	List(row, 8, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Right)
	Padding(row, 4, 0, 0, 0)

	local handle = {}
	local closed = false
	function handle:Close()
		if closed then return end
		closed = true
		tween(dim, { BackgroundTransparency = 1 }, 0.25, Motion.Quint, Motion.In)
		tween(card, { BackgroundTransparency = 1, Position = UDim2.new(0.5, 0, 0.5, 16) }, 0.2, Motion.Quint, Motion.In)
		tween(cardScale, { Scale = 0.94 }, 0.2, Motion.Quint, Motion.In)
		tween(cardStroke, { Transparency = 1 }, 0.15)
		for _, d in ipairs(card:GetDescendants()) do
			pcall(function()
				if d:IsA("TextLabel") or d:IsA("TextButton") then tween(d, { TextTransparency = 1 }, 0.15) end
				if d:IsA("Frame") then tween(d, { BackgroundTransparency = 1 }, 0.15) end
			end)
		end
		task.delay(0.26, function() dim:Destroy() end)
	end

	for i, b in ipairs(buttons) do
		local label = prop(b, "OK", "Text", "Name", "text", "name")
		local style = prop(b, (i == #buttons) and "Primary" or "Neutral", "Style", "style")
		local bg = (style == "Primary" or style == "primary") and "Accent" or ((style == "Danger" or style == "danger") and "Error" or "SurfaceHover")
		local fg = (bg == "SurfaceHover") and "Text" or "OnAccent"
		local btn = New("TextButton", {
			Text = label, TextSize = 13, Weight = "SemiBold", BackgroundColor3 = bg, TextColor3 = fg, BackgroundTransparency = 0,
			Size = UDim2.fromOffset(math.max(76, textWidth(label, 13) + 28), 30), LayoutOrder = i, Parent = row,
		})
		Corner(9, btn)
		if bg == "SurfaceHover" then Stroke(btn) end
		local btnHover = hoverOverlay(btn)
		hoverFx(btn, btnHover, nil, { strength = 0.88 })
		connect(btn.MouseButton1Click, function()
			flash(btnHover)
			handle:Close()
			safeCallback(prop(b, nil, "Callback", "callback", "Func"))
		end)
	end
	if dismissable then
		connect(dim.MouseButton1Click, function() handle:Close() end)
		-- clicks on the card itself must not bubble to the scrim
		local shield = New("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 0, AutoButtonColor = false, Parent = card })
		shield.Position = UDim2.fromOffset(-18, -18)
		shield.Size = UDim2.new(1, 36, 1, 36)
	end
	handle.Instance = card
	return handle
end

---------------------------------------------------------------------------------------------------
-- Elements
---------------------------------------------------------------------------------------------------

local Element = {}
Element.__index = Element

local function registerFlag(element)
	element._ready = true -- from now on value changes count as user changes (autosave)
	if not element.Flag then return end
	if Mova.Options[element.Flag] and Mova.Options[element.Flag] ~= element then
		warn("[Mova] duplicate flag '" .. tostring(element.Flag) .. "' - the previous element is overwritten in Mova.Options")
	end
	Mova.Options[element.Flag] = element
	if element.Type == "Toggle" then Mova.Toggles[element.Flag] = element end
	Mova.Flags[element.Flag] = element.Value
end

local function syncFlag(element)
	if element.Flag then
		Mova.Flags[element.Flag] = element.Value
	end
	if element._ready and element.Flag and element.Save ~= false and element.Window and element.Window._autoSave then
		element.Window:_queueAutoSave()
	end
end

function Element:SetTitle(text)
	self.Name = text
	if self.TitleLabel then bindText(self.TitleLabel, tostring(text)) end
	return self
end
Element.SetName = Element.SetTitle
Element.SetText = Element.SetTitle

function Element:SetDescription(text)
	self.Description = text
	if self.DescLabel then
		if text and text ~= "" then
			bindText(self.DescLabel, tostring(text))
			self.DescLabel.Visible = true
		else
			self.DescLabel.Visible = false
		end
	end
	return self
end
Element.SetDesc = Element.SetDescription

function Element:SetVisible(state)
	self.Visible = state and true or false
	if self.Card then self.Card.Visible = self.Visible and not self._searchHidden end
	return self
end

function Element:Lock(reason)
	self.Locked = true
	self._lockReason = reason
	if self.Card then
		tween(self.Card, { BackgroundTransparency = 0.4 }, Motion.base)
		if self.Stroke then tween(self.Stroke, { Transparency = 0.85 }, Motion.base) end
		if self.Hover then tween(self.Hover, { BackgroundTransparency = 1 }, Motion.base) end
		if self.TitleLabel then tween(self.TitleLabel, { TextTransparency = 0.5 }, Motion.base) end
		if self.DescLabel then
			if reason and reason ~= "" then
				self.DescLabel.Text = tostring(reason)
				self.DescLabel.Visible = true
			end
			tween(self.DescLabel, { TextTransparency = 0.4 }, 0.15)
		end
		if self.Blocker then self.Blocker.Visible = true end
	end
	return self
end

function Element:Unlock()
	self.Locked = false
	self._lockReason = nil
	if self.Card then
		tween(self.Card, { BackgroundTransparency = 0 }, Motion.base)
		if self.Stroke then tween(self.Stroke, { Transparency = CurrentTheme.StrokeTransparency }, Motion.base) end
		if self.TitleLabel then tween(self.TitleLabel, { TextTransparency = 0 }, Motion.base) end
		if self.DescLabel then
			if self.Description and self.Description ~= "" then
				self.DescLabel.Text = translate(tostring(self.Description))
				self.DescLabel.Visible = true
			else
				self.DescLabel.Visible = false
			end
			tween(self.DescLabel, { TextTransparency = 0 }, 0.15)
		end
		if self.Blocker then self.Blocker.Visible = false end
	end
	return self
end

function Element:IsLocked()
	return self.Locked == true
end

function Element:SetOrder(order)
	if self.Card then self.Card.LayoutOrder = order end
	return self
end

function Element:Destroy()
	if self.Flag then
		if Mova.Options[self.Flag] == self then Mova.Options[self.Flag] = nil end
		if Mova.Toggles[self.Flag] == self then Mova.Toggles[self.Flag] = nil end
	end
	if self._cleanup then
		for _, fn in ipairs(self._cleanup) do pcall(fn) end
	end
	if self.Card then self.Card:Destroy() end
	if self.Container then
		local list = self.Container.Elements
		local i = indexOf(list, self)
		if i then table.remove(list, i) end
	end
	self.Destroyed = true
end

function Element:OnChanged(fn)
	self._onChanged = self._onChanged or {}
	self._onChanged[#self._onChanged + 1] = fn
	return self
end

function Element:_fireChanged()
	if self._onChanged then
		for _, fn in ipairs(self._onChanged) do safeCallback(fn, self.Value) end
	end
end

-- Builds the standard card (title + description on the left, control on the right).
-- Card metrics. Roomier than Gen 2's 43px rows: 50px minimum, 16px side / 15px vertical padding,
-- 15px titles over 13px descriptions, 32px fields. Everything below reads from these.
local CARD_MIN, CARD_PAD_X, CARD_PAD_Y, FIELD_H = 50, 16, 15, 32

local function buildCard(container, props, kind, controlWidth, noStack, minControlWidth)
	local name = prop(props, kind, "Name", "name", "Title", "title", "Text")
	local desc = prop(props, nil, "Description", "description", "Desc", "Info")
	local icon = prop(props, nil, "Icon", "icon")

	local card = New("Frame", {
		Name = kind,
		BackgroundColor3 = WHITE, -- tinted by SurfaceGradient below
		Size = UDim2.new(1, 0, 0, CARD_MIN),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = container:_nextOrder(),
		Parent = container.Holder,
	})
	Corner(nil, card)
	SurfaceGradient(card, "Surface", 0.03)
	local stroke = Stroke(card)
	local overlay = hoverOverlay(card)
	local sizeConstraint = New("UISizeConstraint", { MinSize = Vector2.new(0, CARD_MIN), Parent = card })

	local iconImage = resolveIcon(icon)
	local leftPad = CARD_PAD_X
	if iconImage then
		New("ImageLabel", {
			Image = iconImage, ImageColor3 = "TextDim", Size = UDim2.fromOffset(20, 20), Position = UDim2.fromOffset(CARD_PAD_X, CARD_PAD_Y), Parent = card,
		})
		leftPad = CARD_PAD_X + 20 + 10
	end

	local textHolder = New("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(leftPad, 0),
		Size = UDim2.new(1, -leftPad - (controlWidth or 0) - CARD_PAD_X - ((controlWidth or 0) > 0 and 10 or 0), 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = card,
	})
	local textPad = Padding(textHolder, CARD_PAD_Y, 0, CARD_PAD_Y, 0)
	List(textHolder, 3)

	local title = New("TextLabel", {
		TextSize = 15, Weight = "Medium", TextColor3 = "Text", Size = UDim2.new(1, 0, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = 1, Parent = textHolder,
	})
	bindText(title, tostring(name))

	local descLabel = New("TextLabel", {
		TextSize = 13, Weight = "Regular", TextColor3 = "TextDim", TextWrapped = true, LineHeight = 1.15,
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
		LayoutOrder = 2, Visible = false, Parent = textHolder,
	})
	if desc and desc ~= "" then
		bindText(descLabel, tostring(desc))
		descLabel.Visible = true
	end

	local control = New("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -CARD_PAD_X, 0, 0),
		Size = UDim2.new(0, controlWidth or 0, 1, 0),
		ZIndex = 2,
		Parent = card,
	})

	-- blocks input while locked
	local blocker = New("TextButton", {
		Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 5, Visible = false, Parent = card,
	})

	local element = setmetatable({
		Type = kind,
		Name = name,
		Description = desc,
		Flag = prop(props, nil, "Flag", "flag", "Idx"),
		Save = prop(props, true, "Save", "save"),
		Callback = prop(props, nil, "Callback", "callback", "Func"),
		Container = container,
		Tab = container.Tab or container,
		Window = container.Window,
		Card = card,
		TitleLabel = title,
		TextPadding = textPad,
		DescLabel = descLabel,
		Control = control,
		Stacked = false,
		NoStack = noStack and true or false,
		MinControlWidth = minControlWidth, -- a control that can give up width before it has to stack
		Blocker = blocker,
		Stroke = stroke,
		Hover = overlay,
		SizeConstraint = sizeConstraint,
		Visible = true,
		Locked = false,
		_cleanup = {},
	}, Element)

	-- Responsive layout (Gen 2's narrow mode): when the card is too tight for the title and the
	-- control to share a row - a phone, a resized window, a two-column group - the control drops
	-- under the text and spans the card instead of being drawn over the title. The decision uses
	-- the title's real width (a short "Left" keeps its toggle beside it; a long name stacks) and
	-- the window's unscaled width, so the open/close scale animation can't change the answer.
	local cw = controlWidth or 0
	if cw > 0 then
		local restingText = textHolder.Size
		local function applyLayout()
			if element.NoStack then return end
			local w = card.AbsoluteSize.X
			if w <= 0 then return end
			local win = element.Window
			local scale = win and win.MainScale and win.MainScale.Scale or 1
			if scale > 0 then w = w / scale end
			local room = w - leftPad - CARD_PAD_X - 10 - cw
			local bounds = title.TextBounds
			local need = clamp((bounds and bounds.X or 60) + 10, 56, 110)
			local want = room < need
			-- fields and tracks shrink towards their minimum before the card gives up and stacks,
			-- so the cards of a two-column group keep one height for as long as possible
			local shrunk = nil
			if want and element.MinControlWidth then
				local avail = math.floor(w - leftPad - CARD_PAD_X - 10 - need)
				if avail >= element.MinControlWidth then
					want = false
					shrunk = math.min(avail, cw)
				end
			end
			if want == element.Stacked and shrunk == element._shrunk then return end
			element.Stacked, element._shrunk = want, shrunk
			if element._onStack then element._onStack(want) end
			if want then
				textHolder.Size = UDim2.new(1, -leftPad - CARD_PAD_X, 0, 0)
				textPad.PaddingBottom = UDim.new(0, CARD_PAD_Y + FIELD_H + 10)
				control.AnchorPoint = Vector2.new(1, 1)
				control.Position = UDim2.new(1, -CARD_PAD_X, 1, -(CARD_PAD_Y - 1))
				control.Size = UDim2.new(1, -leftPad - CARD_PAD_X, 0, FIELD_H)
			else
				local width = shrunk or cw
				textHolder.Size = shrunk and UDim2.new(1, -leftPad - width - CARD_PAD_X - 10, 0, 0) or restingText
				textPad.PaddingBottom = UDim.new(0, CARD_PAD_Y)
				control.AnchorPoint = Vector2.new(1, 0)
				control.Position = UDim2.new(1, -CARD_PAD_X, 0, 0)
				control.Size = UDim2.new(0, width, 1, 0)
			end
		end
		connect(card:GetPropertyChangedSignal("AbsoluteSize"), applyLayout)
		connect(title:GetPropertyChangedSignal("TextBounds"), applyLayout)
		applyLayout()
	end

	container.Elements[#container.Elements + 1] = element
	element.Window._allElements[#element.Window._allElements + 1] = element
	hoverFx(card, overlay, stroke, { enabled = function() return not element.Locked end })

	if prop(props, false, "Locked", "locked", "Disabled") then
		element:Lock(prop(props, nil, "LockReason", "lockReason"))
	end
	if prop(props, true, "Visible", "visible") == false then
		element:SetVisible(false)
	end
	return element
end

---------------------------------------------------------------------------------------------------
-- Container: shared element constructors for Tab and Section
---------------------------------------------------------------------------------------------------

local Container = {}
Container.__index = Container

function Container:_nextOrder()
	self._order = (self._order or 0) + 1
	return self._order
end

-- Button --------------------------------------------------------------------------------------

function Container:CreateButton(props, callback)
	if typeof(props) == "string" then props = { Name = props, Callback = callback } end
	-- Rayfield Gen 2 button: the whole card is the control and nothing decorates its right side.
	-- Pressing ghosts the outline and squeezes the card in from both sides around the callback,
	-- then both spring back - that motion is the feedback, not an arrow.
	local el = buildCard(self, props, "Button", 0, true)
	local interact = New("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = el.Card })
	local function press()
		flash(el.Hover)
		pressFx(el.Card)
		tween(el.Stroke, { Transparency = 1 }, 0.25, Motion.Quint, Motion.Out)
		task.delay(0.11, function()
			if el.Card.Parent and not el.Locked then
				tween(el.Stroke, { Transparency = CurrentTheme.StrokeTransparency or 0.45 }, 0.25, Motion.Quint, Motion.Out)
			end
		end)
	end
	connect(interact.MouseButton1Click, function()
		if el.Locked then return end
		press()
		safeCallback(el.Callback, el)
	end)
	function el:Press() if not self.Locked then safeCallback(self.Callback, self) end end
	function el:SetCallback(fn) self.Callback = fn return self end
	return el
end

-- Toggle --------------------------------------------------------------------------------------

local TOGGLE_W, TOGGLE_H, KNOB_W, KNOB_H, KNOB_INSET = 48, 22, 22, 16, 3

function Container:CreateToggle(props)
	props = props or {}
	local el = buildCard(self, props, "Toggle", TOGGLE_W)
	el.Value = prop(props, false, "CurrentValue", "Default", "Value", "default", "value", "Enabled") and true or false

	-- Rayfield Gen 2 switch: the track is a quiet inset that never changes colour; the knob is a wide
	-- pill that is translucent when off and becomes the accent (with a lighter accent rim) when on.
	-- Gen 2 draws it at 50x21 with a 25x17 knob; Mova keeps the proportions but trims it to 44x20
	-- with a 20x14 knob (between Fluent's 36x18/14 and Gen 2) so the knob reads as a handle, not a
	-- slab, on a 50px card. 3px inset at either end, both full pills.
	local track = New("Frame", {
		BackgroundColor3 = "Track", BackgroundTransparency = 0.35, Size = UDim2.fromOffset(TOGGLE_W, TOGGLE_H), AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0), Parent = el.Control,
	})
	New("UICorner", { CornerRadius = UDim.new(1, 0), Parent = track })
	local trackStroke = Stroke(track)
	local knob = New("Frame", {
		BackgroundColor3 = "Knob", BackgroundTransparency = 0.5, Size = UDim2.fromOffset(KNOB_W, KNOB_H), AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, KNOB_INSET, 0.5, 0), ZIndex = 2, Parent = track,
	})
	New("UICorner", { CornerRadius = UDim.new(1, 0), Parent = knob })
	local knobStroke = Stroke(knob, "Text", 1, 0.7)
	local interact = New("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = el.Card })

	local KNOB_ON, KNOB_OFF = UDim2.new(1, -(KNOB_W + KNOB_INSET), 0.5, 0), UDim2.new(0, KNOB_INSET, 0.5, 0)
	local function render(animate)
		-- one 0.6s Expo tween, like Gen 2: no stretch/overshoot, so the knob never leaves the track
		local t = animate and 0.6 or 0
		if el.Value then
			tween(knob, { Position = KNOB_ON, BackgroundColor3 = themeValue("Accent"), BackgroundTransparency = 0 }, t, Motion.Expo, Motion.Out)
			tween(knobStroke, { Color = themeValue("AccentHover"), Transparency = 0 }, t, Motion.Expo, Motion.Out)
		else
			tween(knob, { Position = KNOB_OFF, BackgroundColor3 = themeValue("Knob"), BackgroundTransparency = 0.5 }, t, Motion.Expo, Motion.Out)
			tween(knobStroke, { Color = themeValue("Text"), Transparency = 0.7 }, t, Motion.Expo, Motion.Out)
		end
		-- keep registry in sync so theme swaps land on the right colour
		ThemeRegistry[knob] = { BackgroundColor3 = el.Value and "Accent" or "Knob" }
		ThemeRegistry[knobStroke] = { Color = el.Value and "AccentHover" or "Text" }
	end

	function el:Set(value, silent)
		value = value and true or false
		local changed = value ~= self.Value
		self.Value = value
		render(true)
		syncFlag(self)
		if not silent then
			safeCallback(self.Callback, value, self)
		end
		if changed then self:_fireChanged() end
		if self._keybind then self._keybind:_syncFromToggle() end
		return self
	end
	el.SetValue = el.Set
	function el:Toggle() return self:Set(not self.Value) end
	function el:Get() return self.Value end

	connect(interact.MouseButton1Click, function()
		if el.Locked then return end
		pressFx(el.Card)
		el:Set(not el.Value)
	end)

	-- Linoria/Obsidian style attached keybind that flips this toggle
	function el:AddKeybind(kprops)
		kprops = kprops or {}
		kprops.Name = kprops.Name or kprops.Text or (tostring(self.Name) .. " key")
		kprops.Mode = kprops.Mode or "Toggle"
		kprops._attachedToggle = self
		local kb = self.Container:_createKeybind(kprops, self)
		self._keybind = kb
		return kb
	end
	el.AddKeyPicker = el.AddKeybind

	render(false)
	registerFlag(el)
	if prop(props, false, "CallOnCreate", "callOnCreate") then
		safeCallback(el.Callback, el.Value, el)
	end
	return el
end

-- Slider --------------------------------------------------------------------------------------

function Container:CreateSlider(props)
	props = props or {}
	local range = prop(props, nil, "Range", "range")
	local min = range and range[1] or prop(props, 0, "Min", "min")
	local max = range and range[2] or prop(props, 100, "Max", "max")
	local increment = prop(props, 1, "Increment", "increment", "Rounding", "Step")
	if prop(props, nil, "Rounding") then
		increment = 10 ^ (-prop(props, 0, "Rounding"))
	end
	local suffix = prop(props, "", "Suffix", "suffix")
	local prefix = prop(props, "", "Prefix", "prefix")
	local decimals = 0
	do
		local s = tostring(increment)
		local dot = s:find("%.")
		if dot then decimals = #s - dot end
		if increment < 1 and decimals == 0 then decimals = 2 end
	end

	-- Gen 2's wide slider: title stacked over a dim value readout on the left, a fixed-width track
	-- on the right, all on one 58px card. On a narrow card (phone, grouped column) buildCard drops
	-- the track under the text and the readout jumps up beside the title so the card stays short.
	local trackWidth = IsMobile and 160 or 220
	local el = buildCard(self, props, "Slider", trackWidth, false, 110)
	el.Min, el.Max, el.Increment, el.Decimals = min, max, increment, decimals
	el.Suffix, el.Prefix = suffix, prefix
	el.Value = clamp(prop(props, min, "CurrentValue", "Default", "Value", "default", "value"), min, max)
	el.SizeConstraint.MinSize = Vector2.new(0, 56)
	el.TextPadding.PaddingTop = UDim.new(0, 11)
	el.TextPadding.PaddingBottom = UDim.new(0, 11)

	-- value readout: looks like a dim second line, becomes a small field when clicked to type
	local textHolder = el.TitleLabel.Parent
	-- (a list layout owns the positions of its children, so the box sits in a host row and is
	-- pulled 6px left inside it: its text lines up with the title, its field padding does not)
	local valueHost = New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 3, Parent = textHolder })
	local valueBox = New("TextBox", {
		Text = "", TextSize = 13, TextColor3 = "TextDim", Weight = "SemiBold",
		BackgroundColor3 = "Field", BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, Position = UDim2.fromOffset(-6, 0),
		TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false, ZIndex = 3, Parent = valueHost,
	})
	Corner(5, valueBox)
	Padding(valueBox, 0, 6, 0, 6)
	local valueStroke = Stroke(valueBox)
	valueStroke.Transparency = 1
	connect(valueBox.Focused, function()
		tween(valueBox, { BackgroundTransparency = 0, TextColor3 = themeValue("Text") }, Motion.fast)
		focusRing(valueStroke, true)
	end)
	connect(valueBox.FocusLost, function()
		tween(valueBox, { BackgroundTransparency = 1, TextColor3 = themeValue("TextDim") }, Motion.base)
		tween(valueStroke, { Transparency = 1 }, Motion.base)
	end)
	el.ValueBox = valueBox
	-- narrow card: the readout sits at the right end of the title row instead of under it, so the
	-- card is title row + track row and nothing more
	el._onStack = function(stacked)
		if stacked then
			valueHost.Visible = false
			valueBox.Parent = el.Card
			valueBox.AnchorPoint = Vector2.new(1, 0)
			valueBox.Position = UDim2.new(1, -14 + 6, 0, 11)
			el.TitleLabel.Size = UDim2.new(1, -70, 0, 18)
		else
			valueBox.AnchorPoint = Vector2.new(0, 0)
			valueBox.Position = UDim2.fromOffset(-6, 0)
			valueBox.Parent = valueHost
			valueHost.Visible = true
			el.TitleLabel.Size = UDim2.new(1, 0, 0, 18)
		end
	end

	-- Rayfield Gen 2 track: 14px rounded, gradient fill, a pill handle riding the fill's leading
	-- edge (it lives inside the fill, so the fill carries it). While held the pill grows a touch,
	-- ghosts to 70% and shows a thin ring. Sized a step under Gen 2's 35x20 so it reads as a
	-- handle on a 14px track rather than a block.
	local HANDLE_REST, HANDLE_HELD = Vector2.new(32, 20), Vector2.new(36, 22)
	-- the pill is centred on the track's ends, so the track is inset by half a pill: at 0% / 100%
	-- the pill stays inside the control instead of hanging over the card edge
	local trackHolder = New("Frame", {
		BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22), AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0), ZIndex = 2, Parent = el.Control,
	})
	local track = New("Frame", {
		BackgroundColor3 = "Track", Size = UDim2.new(1, -HANDLE_HELD.X, 0, 16), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Parent = trackHolder,
	})
	Corner(7, track)
	local fill = New("Frame", { BackgroundColor3 = WHITE, Size = UDim2.new(0, 0, 1, 0), ZIndex = 2, Parent = track }) -- colour comes from the gradient
	Corner(7, fill)
	local fillGradient = New("UIGradient", {
		Rotation = 2, Offset = Vector2.new(0, 0.5),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.85), NumberSequenceKeypoint.new(1, 0) }),
		Parent = fill,
	})
	onTheme(fillGradient, function() fillGradient.Color = ColorSequence.new(themeValue("AccentHover"), themeValue("Accent")) end)
	local knob = New("Frame", {
		BackgroundColor3 = "Knob", Size = UDim2.fromOffset(HANDLE_REST.X, HANDLE_REST.Y), AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0), ZIndex = 5, Parent = fill,
	})
	New("UICorner", { CornerRadius = UDim.new(1, 0), Parent = knob })
	local knobRing = Stroke(knob, "TextDim", 1, 0.7)
	local knobGlow = Shadow(knob, "Text", 10, 0.85)
	local interact = New("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 10, Parent = trackHolder })

	local function snap(v)
		v = clamp(v, min, max)
		v = min + math.floor((v - min) / increment + 0.5) * increment
		return clamp(round(v, decimals), min, max)
	end

	local dragging = false
	local function render(animate)
		local alpha = (max > min) and ((el.Value - min) / (max - min)) or 0
		-- the fill carries the pill, so one tween moves both: 0.3 Quint while following the pointer,
		-- 0.45 Expo when a value is set programmatically (Gen 2's followInfo / tweenInfo)
		local t = (not animate) and 0 or (dragging and 0.3 or 0.45)
		tween(fill, { Size = UDim2.new(alpha, 0, 1, 0) }, t, dragging and Motion.Quint or Motion.Expo, Motion.Out)
		valueBox.Text = prefix .. formatNumber(el.Value, decimals) .. suffix
	end
	local function setKnobState(state) -- "idle" | "hover" | "drag"
		local held = state == "drag"
		local size = held and HANDLE_HELD or HANDLE_REST
		tween(knob, { Size = UDim2.fromOffset(size.X, size.Y), BackgroundTransparency = held and 0.7 or 0 }, 0.3, Motion.Expo, Motion.Out)
		tween(knobRing, { Color = held and themeValue("Text") or themeValue("TextDim"), Transparency = held and 0.5 or 0.7 }, 0.3, Motion.Expo, Motion.Out)
		ThemeRegistry[knobRing] = { Color = held and "Text" or "TextDim" }
		tween(track, { BackgroundColor3 = state == "idle" and themeValue("Track") or brighten(themeValue("Track"), 0.08) }, 0.45, Motion.Expo, Motion.Out)
		if knobGlow then tween(knobGlow, { Transparency = held and 0.7 or 0.85 }, 0.3, Motion.Expo, Motion.Out) end
	end
	connect(interact.MouseEnter, function() if not dragging and not el.Locked then setKnobState("hover") end end)
	connect(interact.MouseLeave, function() if not dragging then setKnobState("idle") end end)

	function el:Set(value, silent)
		value = tonumber(value)
		if value == nil then return self end
		value = snap(value)
		local changed = value ~= self.Value
		self.Value = value
		render(true)
		syncFlag(self)
		if not silent then safeCallback(self.Callback, value, self) end
		if changed then self:_fireChanged() end
		return self
	end
	el.SetValue = el.Set
	function el:Get() return self.Value end
	function el:SetRange(newMin, newMax)
		min, max = newMin, newMax
		self.Min, self.Max = newMin, newMax
		self:Set(self.Value, true)
		return self
	end
	el.SetMax = function(self, m) return self:SetRange(min, m) end
	el.SetMin = function(self, m) return self:SetRange(m, max) end

	local function fromInput(pos)
		local p, s = track.AbsolutePosition, track.AbsoluteSize
		if s.X <= 0 then return end
		local alpha = clamp((pos.X - p.X) / s.X, 0, 1)
		el:Set(min + (max - min) * alpha)
	end
	connect(interact.InputBegan, function(input)
		if el.Locked then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			setKnobState("drag")
			local unlock = input.UserInputType == Enum.UserInputType.Touch and lockScroll(interact) or nil
			fromInput(input.Position)
			local changed
			changed = input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
					setKnobState("idle")
					if unlock then unlock() end
					if changed then changed:Disconnect() changed = nil end
				end
			end)
		end
	end)
	connect(UserInputService and UserInputService.InputChanged, function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			fromInput(input.Position)
		end
	end)
	connect(valueBox.FocusLost, function()
		if el.Locked then render(false) return end
		local txt = valueBox.Text:gsub("[^%d%.%-]", "")
		local n = tonumber(txt)
		if n then el:Set(n) else render(false) end
	end)

	render(false)
	registerFlag(el)
	return el
end

-- Input ---------------------------------------------------------------------------------------

function Container:CreateInput(props)
	props = props or {}
	local el = buildCard(self, props, "Input", IsMobile and 130 or 180, false, 96)
	el.Value = tostring(prop(props, "", "CurrentValue", "Default", "Value", "default", "value", "Text") or "")
	local placeholder = prop(props, "Type here...", "PlaceholderText", "Placeholder", "placeholder")
	local numeric = prop(props, false, "Numeric", "numeric", "NumbersOnly")
	local finished = prop(props, true, "Finished", "finished", "OnEnter")   -- callback on enter / focus lost (true) or every keystroke (false)
	local clearOnFocus = prop(props, false, "RemoveTextAfterFocusLost", "ClearOnFocus", "clearOnFocus")
	local maxLength = prop(props, nil, "MaxLength", "maxLength")

	local field = New("Frame", {
		BackgroundColor3 = "Field", Size = UDim2.new(1, 0, 0, FIELD_H), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Parent = el.Control,
	})
	Corner(8, field)
	local stroke = Stroke(field)
	local box = New("TextBox", {
		Text = el.Value, PlaceholderText = placeholder, PlaceholderColor3 = "Placeholder", TextSize = 14,
		Size = UDim2.new(1, -24, 1, 0), Position = UDim2.fromOffset(12, 0), ClipsDescendants = true,
		TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false, Parent = field,
	})

	local function sanitise(text)
		if numeric then text = text:gsub("[^%d%.%-]", "") end
		if maxLength and #text > maxLength then text = text:sub(1, maxLength) end
		return text
	end

	function el:Set(value, silent)
		value = tostring(value == nil and "" or value)
		value = sanitise(value)
		local changed = value ~= self.Value
		self.Value = value
		if box.Text ~= value then box.Text = value end
		syncFlag(self)
		if not silent then safeCallback(self.Callback, value, self) end
		if changed then self:_fireChanged() end
		return self
	end
	el.SetValue = el.Set
	function el:Get() return self.Value end
	function el:SetPlaceholder(t) box.PlaceholderText = t return self end

	connect(box.Focused, function() focusRing(stroke, true) end)
	connect(box.FocusLost, function(enterPressed)
		focusRing(stroke, false)
		if el.Locked then box.Text = el.Value return end
		el:Set(box.Text, not finished)
		if clearOnFocus then
			box.Text = ""
			el.Value = ""
		end
	end)
	connect(box:GetPropertyChangedSignal("Text"), function()
		local clean = sanitise(box.Text)
		if clean ~= box.Text then box.Text = clean return end
		if not finished and not el.Locked then
			el:Set(clean)
		end
	end)
	registerFlag(el)
	return el
end

-- Dropdown ------------------------------------------------------------------------------------

function Container:CreateDropdown(props)
	props = props or {}
	local el = buildCard(self, props, "Dropdown", IsMobile and 146 or 200, false, 110)
	el.Options = {}
	local raw = prop(props, {}, "Options", "options", "Values", "values", "List")
	for i, v in ipairs(raw) do el.Options[i] = v end
	el.Multi = prop(props, false, "MultipleOptions", "Multi", "multi", "MultiSelect", "multiSelect") and true or false
	el.AllowNone = prop(props, true, "AllowNull", "AllowNone", "allowNone")
	local placeholder = prop(props, el.Multi and "None selected" or "Select...", "Placeholder", "placeholder")
	local searchable = prop(props, nil, "Searchable", "searchable")
	local maxVisible = prop(props, 6, "MaxVisible", "maxVisible")

	local default = prop(props, nil, "CurrentOption", "Default", "Value", "default", "value")
	if el.Multi then
		el.Value = {}
		if typeof(default) == "table" then
			for _, v in ipairs(default) do el.Value[#el.Value + 1] = v end
		elseif default ~= nil then
			el.Value[1] = default
		end
	else
		if typeof(default) == "table" then default = default[1] end
		el.Value = default
	end

	local field = New("TextButton", {
		Text = "", BackgroundColor3 = "Field", BackgroundTransparency = 0, Size = UDim2.new(1, 0, 0, FIELD_H),
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Parent = el.Control,
	})
	Corner(8, field)
	local stroke = Stroke(field)
	local fieldHover = hoverOverlay(field)
	hoverFx(field, fieldHover, nil, { strength = 0.96, enabled = function() return not el.Locked end })
	local valueLabel = New("TextLabel", {
		Text = "", TextSize = 14, TextColor3 = "Text", Size = UDim2.new(1, -38, 1, 0), Position = UDim2.fromOffset(12, 0),
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = field,
	})
	local chevronHolder = New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(22, FIELD_H), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 0), Parent = field })
	local chevron = Glyph("chevron-down", chevronHolder, "TextDim", 14, 1.6)

	local function display()
		local empty = el.Multi and (#el.Value == 0) or (not el.Multi and el.Value == nil)
		if empty then
			valueLabel.Text = placeholder
		elseif el.Multi then
			-- "A, B" or "A, B +3": the field is narrow, a long comma list just truncates to nothing useful
			if #el.Value <= 2 then
				valueLabel.Text = table.concat(el.Value, ", ")
			else
				valueLabel.Text = tostring(el.Value[1]) .. ", " .. tostring(el.Value[2]) .. " +" .. (#el.Value - 2)
			end
		else
			valueLabel.Text = tostring(el.Value)
		end
		bindTheme(valueLabel, { TextColor3 = empty and "Placeholder" or "Text" })
	end

	local open = false
	local listFrame = nil
	local listScroll = nil
	local listSearch = nil
	local rows = {}

	local function rebuildRows(filter)
		for _, r in ipairs(rows) do r:Destroy() end
		rows = {}
		if not listFrame or not listScroll then return end
		local scroll = listScroll
		filter = filter and filter:lower() or ""
		local count = 0
		for i, option in ipairs(el.Options) do
			local text = tostring(option)
			if filter == "" or text:lower():find(filter, 1, true) then
				count = count + 1
				local selected
				if el.Multi then selected = indexOf(el.Value, option) ~= nil else selected = el.Value == option end
				local row = New("TextButton", {
					Text = "", BackgroundColor3 = "Accent", BackgroundTransparency = selected and 0.86 or 1,
					Size = UDim2.new(1, 0, 0, 30), LayoutOrder = i, Parent = scroll,
				})
				Corner(7, row)
				New("TextLabel", {
					Text = text, TextSize = 13, Weight = selected and "SemiBold" or "Medium", TextColor3 = selected and "Accent" or "Text", Size = UDim2.new(1, -40, 1, 0),
					Position = UDim2.fromOffset(10, 0), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = row,
				})
				if selected then
					local tick = New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(20, 30), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 0), Parent = row })
					Glyph("check", tick, "Accent", 14, 1.8)
				end
				local rowHover = hoverOverlay(row)
				hoverFx(row, rowHover, nil, { strength = 0.94 })
				connect(row.MouseButton1Click, function()
					if el.Multi then
						local idx = indexOf(el.Value, option)
						local newValue = {}
						for _, v in ipairs(el.Value) do newValue[#newValue + 1] = v end
						if idx then
							if #newValue > 1 or el.AllowNone then table.remove(newValue, idx) end
						else
							newValue[#newValue + 1] = option
						end
						el:Set(newValue)
						rebuildRows(listSearch and listSearch.Text or "")
					else
						if el.Value == option and el.AllowNone then
							el:Set(nil)
						else
							el:Set(option)
						end
						closePopup()
					end
				end)
				rows[#rows + 1] = row
			end
		end
		local showSearch = listSearch ~= nil
		local visible = math.min(count, maxVisible)
		local height = visible * 30 + math.max(0, visible - 1) * 3 + 12 + (showSearch and 36 or 0)
		if count == 0 then height = 40 + (showSearch and 36 or 0) end
		positionPopup(listFrame, field, math.max(field.AbsoluteSize.X, IsMobile and 136 or 180), height) -- flush with the field unless it was shrunk
	end

	local function close()
		if not open then return end
		open = false
		tween(chevron, { Rotation = 0 }, Motion.base, Motion.Back, Motion.Out)
		focusRing(stroke, false)
		if listFrame then
			local f = listFrame
			listFrame, listScroll, listSearch = nil, nil, nil
			rows = {}
			tween(f, { Size = UDim2.fromOffset(f.Size.X.Offset, 0), BackgroundTransparency = 1 }, Motion.fast, Motion.Quint, Motion.In)
			task.delay(Motion.fast + 0.02, function() f:Destroy() end)
		end
	end

	local function openList()
		if el.Locked or open then return end
		open = true
		tween(chevron, { Rotation = 180 }, Motion.base, Motion.Back, Motion.Out)
		focusRing(stroke, true)
		local root = getRoot()
		listFrame = New("Frame", {
			BackgroundColor3 = "Surface", Size = UDim2.fromOffset(160, 40), ZIndex = 60, ClipsDescendants = true, Parent = Layers.popup,
		})
		Corner(nil, listFrame)
		Stroke(listFrame)
		Shadow(listFrame, "Shadow", 28, 0.4)
		Padding(listFrame, 6, 6, 6, 6)
		local useSearch = searchable
		if useSearch == nil then useSearch = #el.Options > maxVisible end
		if useSearch then
			local sf = New("Frame", { BackgroundColor3 = "Field", Size = UDim2.new(1, 0, 0, 30), ZIndex = 61, Parent = listFrame })
			Corner(8, sf)
			local sfStroke = Stroke(sf)
			local sb = New("TextBox", {
				Text = "", PlaceholderText = "Search...", PlaceholderColor3 = "Placeholder", TextSize = 13, ZIndex = 62,
				Size = UDim2.new(1, -20, 1, 0), Position = UDim2.fromOffset(10, 0), TextXAlignment = Enum.TextXAlignment.Left, Parent = sf,
			})
			connect(sb.Focused, function() focusRing(sfStroke, true) end)
			connect(sb.FocusLost, function() focusRing(sfStroke, false) end)
			listSearch = sb
			connect(sb:GetPropertyChangedSignal("Text"), function() rebuildRows(sb.Text) end)
		end
		local scroll = New("ScrollingFrame", {
			Size = UDim2.new(1, 0, 1, useSearch and -36 or 0), Position = UDim2.fromOffset(0, useSearch and 36 or 0), ZIndex = 61, Parent = listFrame,
		})
		List(scroll, 3)
		listScroll = scroll
		rebuildRows("")
		-- grow in from the field
		local target = listFrame.Size
		listFrame.Size = UDim2.fromOffset(target.X.Offset, 0)
		listFrame.BackgroundTransparency = 1
		tween(listFrame, { Size = target, BackgroundTransparency = 0 }, 0.3, Motion.Expo, Motion.Out)
		openPopup(listFrame, field, close)
	end

	connect(field.MouseButton1Click, function()
		if open then closePopup() else openList() end
	end)

	local function sameValue(a, b)
		if typeof(a) == "table" and typeof(b) == "table" then
			if #a ~= #b then return false end
			for i = 1, #a do if a[i] ~= b[i] then return false end end
			return true
		end
		return a == b
	end
	function el:Set(value, silent)
		local before = self.Value
		if self.Multi then
			local newValue = {}
			if typeof(value) == "table" then
				for _, v in ipairs(value) do
					if indexOf(self.Options, v) then newValue[#newValue + 1] = v end
				end
			elseif value ~= nil and indexOf(self.Options, value) then
				newValue[1] = value
			end
			self.Value = newValue
		else
			if typeof(value) == "table" then value = value[1] end
			if value ~= nil and not indexOf(self.Options, value) then
				-- allow numeric index as a convenience
				if typeof(value) == "number" and self.Options[value] ~= nil then value = self.Options[value] else value = nil end
			end
			self.Value = value
		end
		display()
		syncFlag(self)
		if not silent then safeCallback(self.Callback, self.Value, self) end
		if not sameValue(before, self.Value) then self:_fireChanged() end
		return self
	end
	el.SetValue = el.Set
	function el:Get() return self.Value end
	function el:Refresh(options, keep)
		self.Options = {}
		for i, v in ipairs(options or {}) do self.Options[i] = v end
		if keep then self:Set(self.Value, true) else self:Set(self.Multi and {} or nil, true) end
		if open then rebuildRows(listSearch and listSearch.Text or "") end
		return self
	end
	el.SetOptions = el.Refresh
	el.SetValues = el.Refresh
	function el:AddOption(option)
		if not indexOf(self.Options, option) then self.Options[#self.Options + 1] = option end
		return self
	end
	function el:RemoveOption(option)
		local i = indexOf(self.Options, option)
		if i then table.remove(self.Options, i) end
		self:Set(self.Value, true)
		return self
	end
	function el:Open() openList() end
	function el:Close() closePopup() end
	el._cleanup[#el._cleanup + 1] = close

	el:Set(el.Value, true)
	registerFlag(el)
	return el
end

-- Keybind -------------------------------------------------------------------------------------

function Container:_createKeybind(props, attachedToggle)
	props = props or {}
	local el = buildCard(self, props, "Keybind", 110)
	el.Mode = prop(props, "Press", "Mode", "mode")       -- Press | Toggle | Hold | Always
	if prop(props, false, "HoldToInteract", "Hold", "hold") then el.Mode = "Hold" end
	el.Value = keyFromName(prop(props, nil, "CurrentKeybind", "Default", "Value", "default", "value", "Key"))
	el.ChangedCallback = prop(props, nil, "ChangedCallback", "OnChanged", "onChanged")
	el.CallOnChange = prop(props, false, "CallOnChange", "callOnChange")
	el.Blacklist = prop(props, { "Unknown" }, "Blacklist", "blacklist")
	el.State = false      -- toggle/hold state
	el._attached = attachedToggle

	-- Gen 2 style key box: sized to its label, "Recording" while it listens, Esc cancels,
	-- Backspace clears, a click anywhere else cancels.
	local field = New("TextButton", {
		Text = "", BackgroundColor3 = "Field", BackgroundTransparency = 0, Size = UDim2.fromOffset(60, FIELD_H),
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Parent = el.Control,
	})
	Corner(8, field)
	local stroke = Stroke(field)
	local fieldHover = hoverOverlay(field)
	hoverFx(field, fieldHover, nil, { strength = 0.96, enabled = function() return not el.Locked end })
	local label = New("TextLabel", {
		Text = keyToString(el.Value), TextSize = 13, Weight = "SemiBold", TextColor3 = "Text", Size = UDim2.new(1, -16, 1, 0), Position = UDim2.fromOffset(8, 0),
		TextTruncate = Enum.TextTruncate.AtEnd, Parent = field,
	})

	local listening = false
	local function sizeBox(animate)
		local w = clamp(#label.Text * 7 + 24, 44, 110)
		if animate then
			tween(field, { Size = UDim2.fromOffset(w, FIELD_H) }, 0.3, Motion.Expo, Motion.Out)
		else
			field.Size = UDim2.fromOffset(w, FIELD_H)
		end
	end
	local function render(animate)
		if listening then
			label.Text = "Recording"
			bindTheme(label, { TextColor3 = "Accent" })
		else
			label.Text = keyToString(el.Value)
			bindTheme(label, { TextColor3 = el.Value and "Text" or "Placeholder" })
		end
		sizeBox(animate)
	end

	local function fire(state)
		if el._attached then
			el._attached:Set(state)
		else
			safeCallback(el.Callback, state, el)
		end
	end
	local function releaseHold()
		if el.Mode == "Hold" and el.State then
			el.State = false
			fire(false)
		end
	end

	function el:Set(key, silent)
		key = keyFromName(key)
		local changed = key ~= self.Value
		if changed then releaseHold() end
		self.Value = key
		render(true)
		syncFlag(self)
		if changed and not silent then
			safeCallback(self.ChangedCallback, key, self)
			if self.CallOnChange then safeCallback(self.Callback, key, self) end
			if self.Mode == "Always" then
				self.State = key ~= nil
				safeCallback(self.Callback, self.State, self)
			end
		end
		if changed then self:_fireChanged() end
		return self
	end
	el.SetValue = el.Set
	function el:Get() return self.Value end
	function el:GetState() return self.State end
	function el:SetMode(mode)
		releaseHold()
		self.Mode = mode
		return self
	end
	function el:_syncFromToggle()
		if self._attached then self.State = self._attached.Value end
	end

	local function setListening(state)
		if state == listening then return end
		listening = state
		if state then
			if ActiveKeybindListener and ActiveKeybindListener ~= setListening then ActiveKeybindListener(false) end
			ActiveKeybindListener = setListening
			KeybindListening = true
		elseif ActiveKeybindListener == setListening then
			ActiveKeybindListener = nil
			-- clear next frame: the key that ended recording is still being dispatched and the
			-- window's toggle-key listener may run after us on the same press (Gen 2 does this too)
			task.defer(function() if ActiveKeybindListener == nil then KeybindListening = false end end)
		end
		focusRing(stroke, state, Motion.fast)
		render(true)
	end
	el._cleanup[#el._cleanup + 1] = function() if listening then setListening(false) end end
	connect(field.MouseButton1Click, function()
		if el.Locked then return end
		if not listening and not hasKeyboard() then
			if el.Window and el.Window.Notify then el.Window:Notify({ Title = "No keyboard", Content = "Connect a keyboard to bind keys.", Type = "Warning", Duration = 3 }) end
			return
		end
		setListening(not listening)
	end)

	local function insideField(pos)
		local p, sz = field.AbsolutePosition, field.AbsoluteSize
		return pos.X >= p.X and pos.X <= p.X + sz.X and pos.Y >= p.Y and pos.Y <= p.Y + sz.Y
	end

	connect(UserInputService and UserInputService.InputBegan, function(input)
		if el.Destroyed then return end
		if listening then
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				-- the click that opened us lands inside the box; anything outside cancels
				if not insideField(input.Position) then setListening(false) end
				return
			end
			local key = inputToKey(input)
			if not key then return end
			if key == Enum.KeyCode.Escape then
				setListening(false)                        -- cancel, keep the old key
			elseif key == Enum.KeyCode.Backspace or key == Enum.KeyCode.Delete then
				setListening(false)
				el:Set(nil)                                -- clear
			elseif indexOf(el.Blacklist, key.Name) then
				return                                     -- keep recording
			elseif el.Window and el.Window.ToggleKey == key and not el._isToggleKeybind then
				setListening(false)
				if el.Window.Notify then el.Window:Notify({ Title = "Key in use", Content = keyToString(key) .. " already opens and closes the menu.", Type = "Warning", Duration = 3 }) end
			else
				setListening(false)
				el:Set(key)
			end
			return
		end
		if KeybindListening or el.Locked or not el.Value then return end
		if input.UserInputType == Enum.UserInputType.Keyboard and isTyping() then return end
		if inputToKey(input) ~= el.Value then return end
		if el.Mode == "Toggle" then
			if el._attached then el.State = not el._attached.Value else el.State = not el.State end
			fire(el.State)
		elseif el.Mode == "Hold" then
			if not el.State then
				el.State = true
				fire(true)
			end
		elseif el.Mode == "Always" then
			-- always: callback(true) fired once on bind, nothing on press
		else
			safeCallback(el.Callback, el.Value, el)
		end
	end)
	connect(UserInputService and UserInputService.InputEnded, function(input)
		if el.Destroyed or el.Mode ~= "Hold" or not el.Value then return end
		if inputToKey(input) == el.Value and el.State then
			el.State = false
			fire(false)
		end
	end)

	render(false)
	registerFlag(el)
	return el
end

function Container:CreateKeybind(props)
	return self:_createKeybind(props, nil)
end

-- Colour picker -------------------------------------------------------------------------------

function Container:CreateColorPicker(props)
	props = props or {}
	local el = buildCard(self, props, "ColorPicker", 64)
	el.Value = prop(props, Color3.fromRGB(255, 255, 255), "Color", "Default", "Value", "color", "default", "value")
	el.Alpha = prop(props, nil, "Transparency", "Alpha", "alpha")
	local useAlpha = el.Alpha ~= nil
	if useAlpha then el.Alpha = clamp(el.Alpha, 0, 1) end

	local swatchHolder = New("Frame", {
		BackgroundColor3 = "Field", Size = UDim2.fromOffset(56, FIELD_H), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Parent = el.Control,
	})
	Corner(8, swatchHolder)
	local swatchStroke = Stroke(swatchHolder)
	local swatch = New("TextButton", {
		Text = "", BackgroundColor3 = el.Value, BackgroundTransparency = 0, Size = UDim2.new(1, -8, 1, -8),
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Parent = swatchHolder,
	})
	Corner(5, swatch)
	local swatchHover = hoverOverlay(swatchHolder)
	hoverFx(swatch, swatchHover, swatchStroke, { strength = 0.96, enabled = function() return not el.Locked end })

	local h, s, v = el.Value:ToHSV()
	local open = false
	local panel = nil
	local panelRefresh = nil
	local dragTarget = nil

	local function render()
		el.Value = Color3.fromHSV(h, s, v)
		swatch.BackgroundColor3 = el.Value
		if useAlpha then swatch.BackgroundTransparency = el.Alpha end
	end

	local function commit(silent)
		render()
		syncFlag(el)
		if not silent then
			if useAlpha then safeCallback(el.Callback, el.Value, el.Alpha, el) else safeCallback(el.Callback, el.Value, el) end
		end
		el:_fireChanged()
	end

	function el:Set(color, alpha, silent)
		if typeof(alpha) == "boolean" then silent = alpha alpha = nil end
		if typeof(color) == "string" then
			local ok, c = pcall(Color3.fromHex, color)
			if ok then color = c else color = nil end
		end
		if typeof(color) == "Color3" then
			h, s, v = color:ToHSV()
		end
		if useAlpha and typeof(alpha) == "number" then self.Alpha = clamp(alpha, 0, 1) end
		commit(silent)
		if panelRefresh then panelRefresh() end
		return self
	end
	el.SetValue = el.Set
	function el:Get() return self.Value, self.Alpha end
	function el:GetHex() return "#" .. self.Value:ToHex():upper() end

	local function closePanel()
		if not open then return end
		open = false
		tween(swatchStroke, { Color = themeValue("Stroke"), Transparency = CurrentTheme.StrokeTransparency }, Motion.base)
		if el._panelConn then pcall(function() el._panelConn:Disconnect() end) el._panelConn = nil end
		dragTarget = nil
		if panel then
			local p = panel
			panel = nil
			panelRefresh = nil
			tween(p, { Size = UDim2.fromOffset(p.Size.X.Offset, 0), BackgroundTransparency = 1 }, Motion.fast, Motion.Quint, Motion.In)
			task.delay(Motion.fast + 0.02, function() p:Destroy() end)
		end
	end

	local function openPanel()
		if el.Locked or open then return end
		open = true
		local root = getRoot()
		local width, height = 230, useAlpha and 258 or 232
		focusRing(swatchStroke, true)
		panel = New("Frame", { BackgroundColor3 = "Surface", ZIndex = 60, ClipsDescendants = true, Parent = Layers.popup })
		Corner(nil, panel)
		Stroke(panel)
		Shadow(panel, "Shadow", 28, 0.4)
		Padding(panel, 10, 10, 10, 10)
		positionPopup(panel, swatchHolder, width, height)
		panel.Size = UDim2.fromOffset(width, 0)
		panel.BackgroundTransparency = 1
		tween(panel, { Size = UDim2.fromOffset(width, height), BackgroundTransparency = 0 }, 0.3, Motion.Expo, Motion.Out)

		-- saturation / value square
		-- a UIGradient multiplies its frame's colour, so the square is white, the hue fades in over it
		-- from left to right, and black fades in over both from top to bottom
		local sv = New("TextButton", {
			Text = "", BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0, Size = UDim2.new(1, 0, 0, 140), ZIndex = 61, Parent = panel,
		})
		Corner(6, sv)
		local hueLayer = New("Frame", { BackgroundColor3 = Color3.fromHSV(h, 1, 1), Size = UDim2.fromScale(1, 1), ZIndex = 62, Parent = sv })
		Corner(6, hueLayer)
		New("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) }), Parent = hueLayer })
		local dark = New("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), Size = UDim2.fromScale(1, 1), ZIndex = 63, Parent = sv })
		Corner(6, dark)
		New("UIGradient", { Color = ColorSequence.new(Color3.new(0, 0, 0), Color3.new(0, 0, 0)), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) }), Rotation = 90, Parent = dark })
		local svCursor = New("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.fromOffset(10, 10), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 64, Parent = sv,
		})
		Corner(5, svCursor)
		New("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1, Parent = svCursor })

		-- hue bar
		local hue = New("TextButton", { Text = "", BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0, Size = UDim2.new(1, 0, 0, 14), Position = UDim2.fromOffset(0, 150), ZIndex = 61, Parent = panel })
		Corner(7, hue)
		local keypoints = {}
		for i = 0, 6 do
			keypoints[#keypoints + 1] = ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6 == 1 and 0.9999 or i / 6, 1, 1))
		end
		New("UIGradient", { Color = ColorSequence.new(keypoints), Parent = hue })
		local hueCursor = New("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.fromOffset(6, 18), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(h, 0, 0.5, 0), ZIndex = 62, Parent = hue })
		Corner(3, hueCursor)

		-- alpha bar
		local alphaBar, alphaCursor, alphaGrad
		local y = 172
		if useAlpha then
			alphaBar = New("TextButton", { Text = "", BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0, Size = UDim2.new(1, 0, 0, 14), Position = UDim2.fromOffset(0, y), ZIndex = 61, Parent = panel })
			Corner(7, alphaBar)
			alphaGrad = New("UIGradient", { Color = ColorSequence.new(el.Value, el.Value), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }), Parent = alphaBar })
			alphaCursor = New("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.fromOffset(6, 18), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(el.Alpha, 0, 0.5, 0), ZIndex = 62, Parent = alphaBar })
			Corner(3, alphaCursor)
			y = y + 22
		end

		-- hex + rgb inputs
		local hexField = New("Frame", { BackgroundColor3 = "Field", Size = UDim2.new(0.5, -4, 0, 26), Position = UDim2.fromOffset(0, y + 4), ZIndex = 61, Parent = panel })
		Corner(6, hexField)
		Stroke(hexField)
		local hexBox = New("TextBox", { Text = "", TextSize = 13, Size = UDim2.new(1, -12, 1, 0), Position = UDim2.fromOffset(6, 0), ZIndex = 62, TextXAlignment = Enum.TextXAlignment.Left, Parent = hexField })
		local rgbField = New("Frame", { BackgroundColor3 = "Field", Size = UDim2.new(0.5, -4, 0, 26), Position = UDim2.new(0.5, 4, 0, y + 4), ZIndex = 61, Parent = panel })
		Corner(6, rgbField)
		Stroke(rgbField)
		local rgbBox = New("TextBox", { Text = "", TextSize = 13, Size = UDim2.new(1, -12, 1, 0), Position = UDim2.fromOffset(6, 0), ZIndex = 62, TextXAlignment = Enum.TextXAlignment.Left, Parent = rgbField })

		local function refresh()
			hueLayer.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
			svCursor.Position = UDim2.new(s, 0, 1 - v, 0)
			hueCursor.Position = UDim2.new(h, 0, 0.5, 0)
			hexBox.Text = "#" .. el.Value:ToHex():upper()
			rgbBox.Text = string.format("%d, %d, %d", math.floor(el.Value.R * 255 + 0.5), math.floor(el.Value.G * 255 + 0.5), math.floor(el.Value.B * 255 + 0.5))
			if alphaBar then
				alphaGrad.Color = ColorSequence.new(el.Value, el.Value)
				alphaCursor.Position = UDim2.new(el.Alpha, 0, 0.5, 0)
			end
		end
		panelRefresh = refresh

		local function applyDrag(pos)
			if dragTarget == "sv" then
				local p, sz = sv.AbsolutePosition, sv.AbsoluteSize
				s = clamp((pos.X - p.X) / sz.X, 0, 1)
				v = 1 - clamp((pos.Y - p.Y) / sz.Y, 0, 1)
			elseif dragTarget == "hue" then
				local p, sz = hue.AbsolutePosition, hue.AbsoluteSize
				h = clamp((pos.X - p.X) / sz.X, 0, 0.9999)
			elseif dragTarget == "alpha" and alphaBar then
				local p, sz = alphaBar.AbsolutePosition, alphaBar.AbsoluteSize
				el.Alpha = clamp((pos.X - p.X) / sz.X, 0, 1)
			end
			commit(false)
			refresh()
		end
		local function beginDrag(which)
			return function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					dragTarget = which
					applyDrag(input.Position)
					local changed
					changed = input.Changed:Connect(function()
						if input.UserInputState == Enum.UserInputState.End then
							dragTarget = nil
							if changed then changed:Disconnect() changed = nil end
						end
					end)
				end
			end
		end
		connect(sv.InputBegan, beginDrag("sv"))
		connect(hue.InputBegan, beginDrag("hue"))
		if alphaBar then connect(alphaBar.InputBegan, beginDrag("alpha")) end
		local moveConn = UserInputService and UserInputService.InputChanged:Connect(function(input)
			if dragTarget and panel and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
				applyDrag(input.Position)
			end
		end)
		el._panelConn = moveConn
		connect(hexBox.FocusLost, function()
			local ok, c = pcall(Color3.fromHex, hexBox.Text)
			if ok then el:Set(c) else refresh() end
		end)
		connect(rgbBox.FocusLost, function()
			local r, g, b = rgbBox.Text:match("(%d+)%D+(%d+)%D+(%d+)")
			if r then el:Set(Color3.fromRGB(clamp(tonumber(r), 0, 255), clamp(tonumber(g), 0, 255), clamp(tonumber(b), 0, 255))) else refresh() end
		end)
		refresh()
		openPopup(panel, swatch, closePanel)
	end

	connect(swatch.MouseButton1Click, function()
		if open then closePopup() else openPanel() end
	end)
	el._cleanup[#el._cleanup + 1] = closePanel
	function el:Open() openPanel() end
	function el:Close() closePanel() end

	render()
	registerFlag(el)
	return el
end
Container.CreateColorpicker = Container.CreateColorPicker

-- Text elements -------------------------------------------------------------------------------

function Container:CreateLabel(props)
	if typeof(props) == "string" then props = { Name = props } end
	props = props or {}
	local el = buildCard(self, props, "Label", 0)
	if prop(props, false, "Transparent", "transparent") then el.Card.BackgroundTransparency = 1 end
	local color = prop(props, nil, "Color", "color")
	if color then
		el.TitleLabel.TextColor3 = color
		ThemeRegistry[el.TitleLabel] = nil
	end
	function el:Set(text) return self:SetTitle(text) end
	return el
end

function Container:CreateParagraph(props)
	props = props or {}
	local el = buildCard(self, { Name = prop(props, "Paragraph", "Title", "Name", "title", "name"), Description = prop(props, "", "Content", "Description", "content", "Text") }, "Paragraph", 0)
	setFont(el.TitleLabel, "SemiBold")
	bindTheme(el.TitleLabel, { FontFace = "@SemiBold" })
	el.DescLabel.TextSize = 13
	function el:Set(newProps)
		if typeof(newProps) == "string" then return self:SetDescription(newProps) end
		if newProps.Title or newProps.Name then self:SetTitle(newProps.Title or newProps.Name) end
		if newProps.Content or newProps.Description then self:SetDescription(newProps.Content or newProps.Description) end
		return self
	end
	el.SetContent = el.SetDescription
	return el
end

function Container:CreateDivider(props)
	if typeof(props) == "string" then props = { Name = props } end
	props = props or {}
	local text = prop(props, nil, "Name", "Text", "name", "text")
	local holder = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, text and 22 or 12), LayoutOrder = self:_nextOrder(), Parent = self.Holder })
	local el = setmetatable({ Type = "Divider", Card = holder, Container = self, Window = self.Window, Visible = true, _cleanup = {} }, Element)
	if text then
		local label = New("TextLabel", {
			Text = "", TextSize = 11, Weight = "SemiBold", TextColor3 = "TextDim", Position = UDim2.fromOffset(4, 0),
			Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 2, Parent = holder,
		})
		bindText(label, tostring(text):upper())
		el.TitleLabel = label
		local line = New("Frame", { BackgroundColor3 = "Divider", Size = UDim2.new(1, -textWidth(tostring(text):upper(), 11) - 20, 0, 1), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Parent = holder })
	else
		New("Frame", { BackgroundColor3 = "Divider", Size = UDim2.new(1, 0, 0, 1), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Parent = holder })
	end
	self.Elements[#self.Elements + 1] = el
	return el
end

-- Section (groupbox) --------------------------------------------------------------------------

local Section = setmetatable({}, { __index = Container })
Section.__index = Section

local SECTION_PAD = 8 -- inset of the cards inside a section panel

-- A section is a boxed panel (WindUI's Box sections / Obsidian groupboxes): a soft surface with a
-- hairline outline, a 44px header row (icon, title, optional description, chevron) that folds the
-- content underneath, a divider between the two, and the cards inset 8px inside the panel so they
-- read as nested. The whole header is the button; the chevron points right while folded.
function Container:CreateSection(props)
	if typeof(props) == "string" then props = { Name = props } end
	props = props or {}
	local name = prop(props, "Section", "Name", "name", "Title", "title")
	local desc = prop(props, nil, "Description", "description", "Desc")
	local icon = prop(props, nil, "Icon", "icon")
	local collapsible = prop(props, true, "Collapsible", "collapsible")
	local collapsed = prop(props, false, "Collapsed", "collapsed", "Opened")
	if props.Opened ~= nil then collapsed = not props.Opened end

	local HEADER = desc and 52 or 44
	local panel = New("Frame", {
		Name = "Section", BackgroundColor3 = "Surface", BackgroundTransparency = 0.6, Size = UDim2.new(1, 0, 0, HEADER),
		AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = self:_nextOrder(), Parent = self.Holder,
	})
	Corner(nil, panel)
	local panelStroke = Stroke(panel)
	local header = New("TextButton", { Name = "Header", Text = "", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, HEADER), ZIndex = 2, Parent = panel })
	local wash = hoverOverlay(header)
	local iconImage = resolveIcon(icon)
	local textX = 14
	if iconImage then
		New("ImageLabel", { Image = iconImage, ImageColor3 = "TextDim", Size = UDim2.fromOffset(16, 16), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, 0), ZIndex = 3, Parent = header })
		textX = 38
	end
	local title = New("TextLabel", {
		TextSize = 13, TextColor3 = "Text", Weight = "SemiBold", Size = UDim2.new(1, -textX - 40, 0, 18), Position = UDim2.new(0, textX, 0.5, desc and -9 or 0),
		AnchorPoint = Vector2.new(0, 0.5), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 3, Parent = header,
	})
	bindText(title, tostring(name))
	local descLabel
	if desc then
		descLabel = New("TextLabel", {
			TextSize = 11, TextColor3 = "TextDim", Size = UDim2.new(1, -textX - 40, 0, 14), Position = UDim2.new(0, textX, 0.5, 9), AnchorPoint = Vector2.new(0, 0.5),
			TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 3, Parent = header,
		})
		bindText(descLabel, tostring(desc))
	end
	local chevronHolder = New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(22, 22), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -11, 0.5, 0), Visible = collapsible, ZIndex = 3, Parent = header })
	local chevron = Glyph("chevron-down", chevronHolder, "TextDim", 12, 1.5)
	-- Highlight under the header while the section is open: a 2px line that runs from the left edge
	-- in the theme's Highlight colour, shifts towards HighlightEnd and fades out across the panel,
	-- with a soft glow bleeding a few pixels down into the content. Both frames are white so the
	-- gradients own the colour; onTheme rebuilds them when the theme changes.
	local function fade(a, b, c)
		return NumberSequence.new({
			NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(0.5, b), NumberSequenceKeypoint.new(0.85, c), NumberSequenceKeypoint.new(1, 1),
		})
	end
	local rule = New("Frame", {
		Name = "Highlight", BackgroundColor3 = WHITE, BackgroundTransparency = 0, Size = UDim2.new(1, 0, 0, 2), Position = UDim2.fromOffset(0, HEADER),
		BorderSizePixel = 0, ZIndex = 2, Parent = panel,
	})
	local ruleGrad = New("UIGradient", { Transparency = fade(0, 0.3, 1), Parent = rule })
	-- two stacked glow strips (denser near the line, fainter below) approximate a vertical fall-off,
	-- since one UIGradient can only fade along one axis and the horizontal fade matters more
	local GLOW_T, GLOW2_T = 0.86, 0.94
	local glow = New("Frame", {
		Name = "HighlightGlow", BackgroundColor3 = WHITE, BackgroundTransparency = GLOW_T, Size = UDim2.new(1, 0, 0, 4), Position = UDim2.fromOffset(0, HEADER + 2),
		BorderSizePixel = 0, ZIndex = 1, Parent = panel,
	})
	local glowGrad = New("UIGradient", { Transparency = fade(0, 0.55, 1), Parent = glow })
	local glow2 = New("Frame", {
		Name = "HighlightGlow2", BackgroundColor3 = WHITE, BackgroundTransparency = GLOW2_T, Size = UDim2.new(1, 0, 0, 6), Position = UDim2.fromOffset(0, HEADER + 6),
		BorderSizePixel = 0, ZIndex = 1, Parent = panel,
	})
	local glow2Grad = New("UIGradient", { Transparency = fade(0, 0.6, 1), Parent = glow2 })
	onTheme(rule, function()
		local c1 = themeValue("Highlight") or themeValue("Accent")
		local c2 = themeValue("HighlightEnd") or themeValue("AccentHover") or c1
		local seq = ColorSequence.new(c1, c2)
		ruleGrad.Color = seq
		glowGrad.Color = seq
		glow2Grad.Color = seq
	end)
	local holder = New("Frame", {
		Name = "Content", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Position = UDim2.fromOffset(0, HEADER + 1),
		Parent = panel,
	})
	Padding(holder, SECTION_PAD, SECTION_PAD, SECTION_PAD, SECTION_PAD)
	local holderLayout = List(holder, 8, nil, Enum.HorizontalAlignment.Center)
	if collapsible then
		hoverFx(header, wash, panelStroke, { strength = 0.96 })
		connect(header.MouseEnter, function() tintGlyph(chevron, themeValue("Text")) end)
		connect(header.MouseLeave, function() tintGlyph(chevron, themeValue("TextDim"), Motion.slow) end)
	end

	local section = setmetatable({
		Type = "Section", Name = name, Frame = panel, Panel = panel, Holder = holder, Header = header, TitleLabel = title, DescLabel = descLabel,
		Stroke = panelStroke, Rule = rule, Highlight = rule, HighlightGlow = glow, Chevron = chevron,
		Window = self.Window, Tab = self.Tab or self, Elements = {}, Collapsed = false, Collapsible = collapsible, _order = 0,
	}, Section)
	self.Elements[#self.Elements + 1] = section
	self.Window._allSections[#self.Window._allSections + 1] = section

	local collapseToken = 0
	local openHeight = 0 -- last height measured while the content was fully open
	-- Height of the open content. holder.AbsoluteSize is right whenever the holder is open and
	-- auto-sized; otherwise fall back to the list's content size plus the padding.
	local function contentHeight()
		local h = holder.AutomaticSize == Enum.AutomaticSize.Y and holder.Visible and holder.AbsoluteSize.Y or 0
		if h <= 0 then
			local ok, inner = pcall(function() return holderLayout.AbsoluteContentSize.Y end)
			if ok and inner and inner > 0 then h = inner + 2 * SECTION_PAD end
		end
		if h <= 0 then h = openHeight end
		return h
	end
	local function settleOpen()
		holder.AutomaticSize = Enum.AutomaticSize.Y
		holder.Size = UDim2.new(1, 0, 0, 0)
		holder.ClipsDescendants = false
	end
	function section:SetCollapsed(state, instant)
		state = state and true or false
		if state == self.Collapsed then return self end
		self.Collapsed = state
		collapseToken = collapseToken + 1
		local token = collapseToken
		if instant then
			chevron.Rotation = state and -90 or 0
			rule.BackgroundTransparency = state and 1 or 0
			glow.BackgroundTransparency = state and 1 or GLOW_T
			glow2.BackgroundTransparency = state and 1 or GLOW2_T
		else
			tween(chevron, { Rotation = state and -90 or 0 }, 0.3, Motion.Back, Motion.Out)
			tween(rule, { BackgroundTransparency = state and 1 or 0 }, state and Motion.fast or Motion.slow)
			tween(glow, { BackgroundTransparency = state and 1 or GLOW_T }, state and Motion.fast or Motion.slow)
			tween(glow2, { BackgroundTransparency = state and 1 or GLOW2_T }, state and Motion.fast or Motion.slow)
		end
		if state then
			local height = contentHeight()
			if height > 0 then openHeight = height end
			-- freeze the current height, then run it down; clip only while the height animates
			-- (clipping for good would eat the card outlines at the padding edge)
			holder.ClipsDescendants = true
			holder.AutomaticSize = Enum.AutomaticSize.None
			if instant then
				holder.Size = UDim2.new(1, 0, 0, 0)
				holder.Visible = false
			else
				holder.Size = UDim2.new(1, 0, 0, height)
				tween(holder, { Size = UDim2.new(1, 0, 0, 0) }, 0.3, Motion.Expo, Motion.Out)
				task.delay(0.3, function() if token == collapseToken and self.Collapsed then holder.Visible = false end end)
			end
		else
			holder.Visible = true
			if instant then
				settleOpen()
				return self
			end
			-- the holder was hidden, so its layout may be stale: show it at zero height (clipped,
			-- so nothing flashes), let one frame lay the cards out, then measure and grow
			holder.ClipsDescendants = true
			holder.AutomaticSize = Enum.AutomaticSize.None
			local from = holder.Size.Y.Offset
			if from < 0 then from = 0 end
			holder.Size = UDim2.new(1, 0, 0, from)
			task.spawn(function()
				task.wait()
				if token ~= collapseToken or self.Collapsed or not holder.Parent then return end
				local height = contentHeight()
				if height <= 0 then settleOpen() return end
				openHeight = height
				tween(holder, { Size = UDim2.new(1, 0, 0, height) }, 0.35, Motion.Expo, Motion.Out)
				task.delay(0.35, function() if token == collapseToken and not self.Collapsed then settleOpen() end end)
			end)
		end
		return self
	end
	function section:Collapse(instant) return self:SetCollapsed(true, instant) end
	function section:Expand(instant) return self:SetCollapsed(false, instant) end
	function section:Toggle() return self:SetCollapsed(not self.Collapsed) end
	function section:IsCollapsed() return self.Collapsed end
	function section:Set(newName) self.Name = newName bindText(title, tostring(newName)) return self end
	section.SetTitle = section.Set
	section.SetName = section.Set
	function section:SetDescription(text)
		if not descLabel then return self end
		bindText(descLabel, tostring(text or ""))
		return self
	end
	function section:SetVisible(state) panel.Visible = state and true or false return self end
	function section:Destroy()
		for i = #self.Elements, 1, -1 do pcall(function() self.Elements[i]:Destroy() end) end
		ThemeHooks[rule] = nil
		panel:Destroy()
	end
	if collapsible then
		connect(header.MouseButton1Click, function()
			flash(wash)
			section:SetCollapsed(not section.Collapsed)
		end)
	end
	if collapsed then section:SetCollapsed(true, true) end
	return section
end
Container.CreateGroupbox = Container.CreateSection

-- Group: Rayfield Gen 2's layout container. A row packs its children side by side (Columns per
-- row, wrapping when there are more), a column stacks them. Nest a row of columns for a grid.
-- Every Create*/Add* method of a container works on a group, so the same element code builds
-- inside it and flags still register on the window.
local Group = setmetatable({}, { __index = function(_, k)
	local v = Container[k]
	if typeof(v) == "function" and (k:match("^Create") or k:match("^Add")) then
		return function(self, ...)
			local el = v(self, ...)
			self:_fit(el)
			return el
		end
	end
	return v
end })
Group.__index = Group

-- Rows are built from explicit line frames (one horizontal list per Columns children) instead of
-- UIListLayout.Wraps + HorizontalFlex: wrapping/flex inside an AutomaticSize parent re-measures
-- itself every time a child's size animates, which made the whole group blink in and out when a
-- toggle inside it was tapped. Plain nested lists have no feedback loop.
function Group:_newLine()
	self._lines = (self._lines or 0) + 1
	local line = New("Frame", {
		Name = "GroupLine", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = self._lines, Parent = self.Frame,
	})
	List(line, self.Gap, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top)
	self._lineCount = 0
	self.Holder = line
	return line
end

function Group:_fit(el)
	if typeof(el) ~= "table" or el._fitted then return end -- alias wrappers (CreateRow -> CreateGroup) fit twice
	el._fitted = true
	local f = el.Card or el.Frame
	if not f then return end
	if self.Direction == Enum.FillDirection.Horizontal then
		local cols = math.max(1, self.Columns)
		local gap = self.Gap
		local size = UDim2.new(1 / cols, -math.ceil(gap * (cols - 1) / cols), f.Size.Y.Scale, f.Size.Y.Offset)
		f.Size = size
		el._compactSize = size
		Compact[f] = true
		self._lineCount = (self._lineCount or 0) + 1
		if self._lineCount >= cols then self:_newLine() end
	end
end

function Group:SetVisible(state) self.Frame.Visible = state and true or false return self end
function Group:Destroy()
	for i = #self.Elements, 1, -1 do pcall(function() self.Elements[i]:Destroy() end) end
	self.Frame:Destroy()
end

function Container:CreateGroup(props)
	if typeof(props) == "string" then props = { Direction = props } end
	props = props or {}
	local dir = tostring(prop(props, "row", "Direction", "direction")):lower()
	local horizontal = not (dir == "column" or dir == "vertical")
	local columns = tonumber(prop(props, 2, "Columns", "columns")) or 2
	local gap = tonumber(prop(props, 6, "Gap", "gap", "Padding")) or 6

	local frame = New("Frame", {
		Name = "Group", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = self:_nextOrder(), Parent = self.Holder,
	})
	local layout = List(frame, gap, Enum.FillDirection.Vertical, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top)

	local group = setmetatable({
		Type = "Group", Frame = frame, Holder = frame, Layout = layout,
		Direction = horizontal and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical,
		Columns = columns, Gap = gap,
		Window = self.Window, Tab = self.Tab or self, Elements = {}, _order = 0,
	}, Group)
	if horizontal then group:_newLine() end
	self.Elements[#self.Elements + 1] = group
	return group
end
Container.CreateRow = function(self, props) props = props or {} props.Direction = "row" return self:CreateGroup(props) end
Container.CreateColumn = function(self, props) props = props or {} props.Direction = "column" return self:CreateGroup(props) end

-- Linoria / Obsidian compatibility aliases -----------------------------------------------------

local function linoriaInfo(idx, info)
	if typeof(idx) == "table" then info = idx idx = info.Flag or info.Idx end
	info = shallowCopy(info or {})
	info.Flag = info.Flag or idx
	info.Name = info.Name or info.Text or info.Title or idx
	info.Text = nil -- Linoria's Text is the label; Mova's Text alias is an Input value
	info.Description = info.Description or info.Tooltip
	if info.Disabled ~= nil then info.Locked = info.Disabled end
	return info
end

function Container:AddToggle(idx, info)
	return self:CreateToggle(linoriaInfo(idx, info))
end
function Container:AddCheckbox(idx, info)
	return self:CreateToggle(linoriaInfo(idx, info))
end
function Container:AddSlider(idx, info)
	info = linoriaInfo(idx, info)
	if info.Rounding and not info.Increment then info.Increment = 10 ^ (-(info.Rounding)) end
	info.Rounding = nil
	return self:CreateSlider(info)
end
function Container:AddDropdown(idx, info)
	info = linoriaInfo(idx, info)
	info.Options = info.Options or info.Values
	info.Multi = info.Multi
	info.AllowNone = info.AllowNull
	return self:CreateDropdown(info)
end
function Container:AddInput(idx, info)
	info = linoriaInfo(idx, info)
	info.Value = info.Value or info.Default
	return self:CreateInput(info)
end
function Container:AddButton(a, b)
	if typeof(a) == "table" then
		local info = a
		return self:CreateButton({ Name = info.Text or info.Name, Description = info.Tooltip, Callback = info.Func or info.Callback, Locked = info.Disabled })
	end
	return self:CreateButton({ Name = a, Callback = b })
end
function Container:AddLabel(text, wrap)
	if typeof(text) == "table" then return self:CreateLabel({ Name = text.Text or text.Name }) end
	return self:CreateLabel({ Name = text })
end
function Container:AddDivider() return self:CreateDivider() end
function Container:AddKeyPicker(idx, info)
	info = linoriaInfo(idx, info)
	info.Callback = info.Callback
	return self:CreateKeybind(info)
end
function Container:AddColorPicker(idx, info)
	info = linoriaInfo(idx, info)
	info.Color = info.Color or info.Default
	return self:CreateColorPicker(info)
end
function Container:AddLeftGroupbox(name) return self:CreateSection({ Name = name }) end
function Container:AddRightGroupbox(name) return self:CreateSection({ Name = name }) end
function Container:AddGroupbox(name) return self:CreateSection({ Name = name }) end

---------------------------------------------------------------------------------------------------
-- Tab
---------------------------------------------------------------------------------------------------

local Tab = setmetatable({}, { __index = Container })
Tab.__index = Tab

function Tab:Select()
	self.Window:SelectTab(self)
	return self
end

function Tab:SetVisible(state)
	self.Button.Visible = state and true or false
	return self
end

function Tab:SetName(name)
	self.Name = name
	bindText(self.Label, tostring(name))
	return self
end

function Tab:Destroy()
	for i = #self.Elements, 1, -1 do pcall(function() self.Elements[i]:Destroy() end) end
	self.Button:Destroy()
	self.Page:Destroy()
	local i = indexOf(self.Window.Tabs, self)
	if i then table.remove(self.Window.Tabs, i) end
	if self.Window.CurrentTab == self then
		self.Window.CurrentTab = nil
		if self.Window.Tabs[1] then self.Window:SelectTab(self.Window.Tabs[1]) end
	end
end

---------------------------------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------------------------------

local Window = {}
Window.__index = Window

-- bottom fade over the content area (Gen 2): height, and the extra page padding that keeps the
-- last row readable when a page is scrolled to its end
local BOTTOM_FADE_H, BOTTOM_FADE_PAD = 52, 12
local TAG_H, TAG_GAP = 22, 6 -- topbar tag height / spacing

function Mova:CreateWindow(props)
	props = props or {}
	local root = getRoot()

	local self = setmetatable({
		Name = prop(props, "Mova", "Name", "name", "Title", "title"),
		Subtitle = prop(props, nil, "Subtitle", "subtitle", "LoadingSubtitle"),
		Icon = prop(props, nil, "Icon", "icon"),
		Tabs = {},
		CurrentTab = nil,
		Hidden = false,
		Minimised = false,
		Destroyed = false,
		_allElements = {},
		_allSections = {},
		_order = 0,
	}, Window)

	-- configuration
	local cfg = prop(props, nil, "ConfigurationSaving", "Configuration", "configuration", "Config")
	local folderName = typeof(cfg) == "table" and prop(cfg, nil, "FolderName", "Folder", "folder", "customFolder") or nil
	self.Store = Storage.forScript(folderName or self.Name)   -- <Mova.Folder>/<Script>/ (settings.json + configs/)
	self.Folder = self.Store.Folder
	self.ConfigFolder = self.Store.ConfigFolder
	self._legacyFolders = { Mova.Folder .. "/" .. self.Name:gsub("[^%w%s%-_]", ""), self.Folder }
	if folderName then self._legacyFolders[#self._legacyFolders + 1] = tostring(folderName) end
	if typeof(cfg) == "table" then
		self.ConfigEnabled = prop(cfg, true, "Enabled", "enabled")
		self.ConfigFile = safeName(prop(cfg, "default", "FileName", "fileName", "file"))
		self._autoSave = prop(cfg, true, "AutoSave", "autoSave")
		self._autoLoad = prop(cfg, true, "AutoLoad", "autoLoad")
	else
		self.ConfigEnabled = false
		self.ConfigFile = "default"
	end
	if self.ConfigEnabled and not FS.available then
		self.ConfigEnabled = false
		warn("[Mova] configuration saving disabled: executor has no file system access")
	end

	-- theme
	local theme = prop(props, nil, "Theme", "theme")
	if theme then Mova:SetTheme(theme, false) end

	-- localisation
	local translations = prop(props, nil, "Translations", "translations")
	if translations then Mova:SetTranslations(translations) end
	local locale = prop(props, nil, "Locale", "locale")
	if locale then Mova:SetLocale(locale) end

	-- toggle key
	self.ToggleKey = keyFromName(prop(props, IsMobile and nil or "K", "ToggleUIKeybind", "ToggleKey", "toggleKey", "MinimizeKey", "Keybind")) or (not IsMobile and Enum.KeyCode.K or nil)

	-- sizing
	local vp = viewportSize()
	local requested = prop(props, nil, "Size", "size")
	local width, height = IsMobile and 560 or 640, IsMobile and 340 or 440
	if typeof(requested) == "UDim2" then
		width, height = requested.X.Offset, requested.Y.Offset
	elseif typeof(requested) == "Vector2" then
		width, height = requested.X, requested.Y
	elseif typeof(requested) == "table" then
		width, height = tonumber(requested[1] or requested.Width or requested.X) or width, tonumber(requested[2] or requested.Height or requested.Y) or height
	end
	width = math.min(width, vp.X - 24)
	height = math.min(height, vp.Y - 24)
	self.MinSize = Vector2.new(420, 260)
	self.Size = Vector2.new(width, height)
	local sidebarWidth = IsMobile and 118 or 146
	self.SidebarWidth = sidebarWidth

	-- main frame ----------------------------------------------------------------------------
	-- The frame itself is sidebar-coloured; the content panel paints the lighter area with its own
	-- rounded corners, so nothing square ever pokes out of the window's corners.
	local main = New("Frame", {
		Name = "Window", BackgroundColor3 = "Sidebar", Size = UDim2.fromOffset(width, height),
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ClipsDescendants = true, Parent = root,
	})
	local mainCorner = Corner(CurrentTheme.WindowRadius or 14, main)
	onTheme(mainCorner, function() mainCorner.CornerRadius = UDim.new(0, CurrentTheme.WindowRadius or 14) end)
	local mainStroke = Stroke(main)
	Shadow(main, "Shadow", 48, 0.35)
	local mainScale = New("UIScale", { Scale = 1, Parent = main })
	self.Main, self.MainStroke, self.MainScale = main, mainStroke, mainScale
	local TOPBAR = 48

	-- topbar
	local topbar = New("Frame", { Name = "Topbar", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, TOPBAR), Parent = main })
	New("Frame", { BackgroundColor3 = "Divider", Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, -1), Parent = topbar })
	self.Topbar = topbar

	local titleX = 18
	local iconImage = resolveIcon(self.Icon)
	if iconImage then
		self._titleMark = New("ImageLabel", { Image = iconImage, Size = UDim2.fromOffset(22, 22), Position = UDim2.fromOffset(16, 13), Parent = topbar })
		titleX = 48
	else
		-- accent mark when there is no icon
		local mark = New("Frame", { BackgroundColor3 = "Accent", Size = UDim2.fromOffset(8, 8), Position = UDim2.fromOffset(16, 20), Parent = topbar })
		Corner(4, mark)
		self._titleMark = mark
		titleX = 32
	end
	local titleLabel = New("TextLabel", {
		Weight = "SemiBold", TextSize = 15, Size = UDim2.fromOffset(120, 18), Position = UDim2.fromOffset(titleX, self.Subtitle and 8 or 15),
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = topbar,
	})
	bindText(titleLabel, tostring(self.Name))
	self.TitleLabel = titleLabel
	-- measuring twin: same text and font, never truncated, invisible. A truncating label's
	-- TextBounds describes the truncated text, so sizing from it would ratchet the title down.
	local titleMeasure = New("TextLabel", {
		Name = "TitleMeasure", Weight = "SemiBold", TextSize = 15, TextTransparency = 1, Size = UDim2.fromOffset(4000, 18), Position = UDim2.fromOffset(titleX, 8),
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 0, Parent = topbar,
	})
	pcall(function() titleMeasure.Interactable = false end)
	bindText(titleMeasure, tostring(self.Name))
	self._titleMeasure = titleMeasure
	local sub, subMeasure
	if self.Subtitle then
		sub = New("TextLabel", {
			TextSize = 12, TextColor3 = "TextDim", Size = UDim2.fromOffset(120, 14), Position = UDim2.fromOffset(titleX, 26),
			TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = topbar,
		})
		bindText(sub, tostring(self.Subtitle))
		self.SubtitleLabel = sub
		subMeasure = New("TextLabel", {
			Name = "SubtitleMeasure", TextSize = 12, TextTransparency = 1, Size = UDim2.fromOffset(4000, 14), Position = UDim2.fromOffset(titleX, 26),
			TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 0, Parent = topbar,
		})
		pcall(function() subMeasure.Interactable = false end)
		bindText(subMeasure, tostring(self.Subtitle))
		self._subMeasure = subMeasure
	end
	self._titleX = titleX

	-- tags (Rayfield Gen 2 `tagContainer`): small pills in a row right after the title block.
	-- The topbar layout below places them, hides the ones that don't fit and gives their room to
	-- the search field when it opens.
	local tagBar = New("Frame", { Name = "Tags", BackgroundTransparency = 1, Size = UDim2.fromOffset(0, TAG_H), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, titleX, 0.5, 0), Visible = false, Parent = topbar })
	self.TagBar = tagBar
	self.Tags = {}

	-- topbar buttons (code-drawn glyphs, hover wash; close tints red)
	local buttons = New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, TOPBAR), AutomaticSize = Enum.AutomaticSize.X, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 0), Parent = topbar })
	List(buttons, 2, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)

	local function topButton(kind, order, hoverColorKey)
		local b = New("TextButton", {
			Text = "", Size = UDim2.fromOffset(30, 30), BackgroundColor3 = "Text", BackgroundTransparency = 1, LayoutOrder = order, Parent = buttons,
		})
		Corner(8, b)
		local glyph = Glyph(kind, b, "TextDim", 14, 1.6)
		connect(b.MouseEnter, function()
			tween(b, { BackgroundTransparency = 0.93 }, Motion.base)
			tintGlyph(glyph, themeValue(hoverColorKey or "Text"))
		end)
		connect(b.MouseLeave, function()
			tween(b, { BackgroundTransparency = 1 }, Motion.slow)
			tintGlyph(glyph, themeValue("TextDim"), Motion.slow)
		end)
		connect(b.MouseButton1Down, function() tween(glyph, { Size = UDim2.fromOffset(12, 12) }, Motion.fast, Motion.Quint, Motion.Out) end)
		connect(b.MouseButton1Up, function() tween(glyph, { Size = UDim2.fromOffset(14, 14) }, Motion.slow, Motion.Back, Motion.Out) end)
		return b, glyph
	end
	local closeBtn = topButton("close", 3, "Error")
	local minBtn, minGlyph = topButton("minus", 2)
	local searchBtn, searchGlyph = topButton("search", 1)

	-- Search field: lives INSIDE the topbar, in whatever room is free between the title / tags
	-- and the buttons. The topbar layout sizes it: tags give way first, then the title truncates,
	-- so nothing ever overlaps. It grows out of the search button (right-anchored) when opened.
	local SEARCH_H = 32
	local searchHolder = New("Frame", {
		Name = "Search", BackgroundColor3 = "Field", BackgroundTransparency = 1, Size = UDim2.fromOffset(SEARCH_H, SEARCH_H),
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -120, 0.5, 0), ClipsDescendants = true, Visible = false, ZIndex = 15, Parent = topbar,
	})
	New("UICorner", { CornerRadius = UDim.new(1, 0), Parent = searchHolder })
	local searchStroke = Stroke(searchHolder)
	searchStroke.Transparency = 1
	local searchIconHolder = New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(16, 16), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 11, 0.5, 0), ZIndex = 16, Parent = searchHolder })
	local searchFieldGlyph = Glyph("search", searchIconHolder, "TextDim", 13, 1.6)
	local searchBox = New("TextBox", {
		Text = "", PlaceholderText = "Search all tabs", PlaceholderColor3 = "Placeholder", TextSize = 13, ClearTextOnFocus = false, TextTransparency = 1,
		Size = UDim2.new(1, -34 - 32, 1, 0), Position = UDim2.fromOffset(34, 0), TextXAlignment = Enum.TextXAlignment.Left, ClipsDescendants = true, ZIndex = 16, Parent = searchHolder,
	})
	local clearBtn = New("TextButton", {
		Text = "", BackgroundColor3 = "Text", BackgroundTransparency = 1, Size = UDim2.fromOffset(24, 24), AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -4, 0.5, 0), ZIndex = 17, Parent = searchHolder,
	})
	New("UICorner", { CornerRadius = UDim.new(1, 0), Parent = clearBtn })
	local clearGlyph = Glyph("close", clearBtn, "TextDim", 12, 1.6)
	connect(clearBtn.MouseEnter, function() tween(clearBtn, { BackgroundTransparency = 0.92 }, Motion.fast) tintGlyph(clearGlyph, themeValue("Text")) end)
	connect(clearBtn.MouseLeave, function() tween(clearBtn, { BackgroundTransparency = 1 }, Motion.base) tintGlyph(clearGlyph, themeValue("TextDim"), Motion.base) end)
	connect(searchBox.Focused, function() focusRing(searchStroke, true) end)
	connect(searchBox.FocusLost, function() if searchHolder.Visible then focusRing(searchStroke, false) end end)
	self.SearchBox, self.SearchBar = searchBox, searchHolder

	-- sidebar
	local body = New("Frame", { Name = "Body", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -TOPBAR), Position = UDim2.fromOffset(0, TOPBAR), Parent = main })
	self.Body = body
	local sidebar = New("Frame", { Name = "Sidebar", BackgroundTransparency = 1, Size = UDim2.new(0, sidebarWidth, 1, 0), Parent = body })
	New("Frame", { BackgroundColor3 = "Divider", Size = UDim2.new(0, 1, 1, 0), Position = UDim2.new(1, -1, 0, 0), Parent = sidebar })
	self.Sidebar = sidebar
	-- profile footer (Gen 2: 60px footer, 34px avatar, no divider, not a control). Ours: 56px,
	-- a 30px avatar plate and display name over @username, laid straight on the rail - nothing to
	-- hover or click. Profile = false hides it and the tab list takes the height back;
	-- Window:SetProfile{ Name, Subtitle, Image } changes the lines.
	local PROFILE_H = 42
	local profileProps = prop(props, nil, "Profile", "profile", "User", "user")
	local showProfile = prop(props, true, "ShowProfile", "showProfile")
	if profileProps == false then showProfile = false end
	if typeof(profileProps) ~= "table" then profileProps = {} end
	local tabList = New("ScrollingFrame", { Size = UDim2.new(1, 0, 1, showProfile and -PROFILE_H or 0), Parent = sidebar })
	Padding(tabList, 8, 8, 8, 8)
	List(tabList, 2)
	self.TabList = tabList

	local displayName = (LocalPlayer and (LocalPlayer.DisplayName or LocalPlayer.Name)) or "Player"
	local userName = (LocalPlayer and LocalPlayer.Name) or "guest"
	local userId = LocalPlayer and tonumber(LocalPlayer.UserId) or 0
	local footer = New("Frame", { Name = "Profile", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, PROFILE_H), AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Visible = showProfile, Parent = sidebar })
	pcall(function() footer.Interactable = false end)
	-- Quiet footer, one line by default: a small round avatar and the display name. A second,
	-- dimmer line only appears when a Subtitle is asked for (Profile = { Subtitle = ... } or
	-- SetProfile), so the corner never reads as a block of text.
	local AV = 24
	local avatar = New("Frame", { BackgroundColor3 = "SurfaceHover", Size = UDim2.fromOffset(AV, AV), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, 0), Parent = footer })
	New("UICorner", { CornerRadius = UDim.new(1, 0), Parent = avatar })
	Stroke(avatar, "Stroke", 1, 0.8)
	-- initial only shows while there is no picture: headshots are PNGs with a transparent
	-- background, so a letter underneath would bleed through the face
	local initial = New("TextLabel", { Text = displayName:sub(1, 1):upper(), TextSize = 11, Weight = "Bold", TextColor3 = "Text", Size = UDim2.fromScale(1, 1), Parent = avatar })
	local head = New("ImageLabel", { Image = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = avatar })
	New("UICorner", { CornerRadius = UDim.new(1, 0), Parent = head })
	local function setAvatar(image)
		local spec = image and resolveIcon(image) or nil
		if spec then applyIcon(head, spec) head.Visible = true else head.Image = "" head.Visible = false end
		initial.Visible = not head.Visible
	end
	self._setAvatar = setAvatar
	self.ProfileAvatar, self.ProfileInitial, self.ProfileImage = avatar, initial, head
	setAvatar(profileProps.Image or profileProps.Avatar or (userId > 0 and ("rbxthumb://type=AvatarHeadShot&id=" .. userId .. "&w=60&h=60") or nil))
	local textX = 14 + AV + 8
	local chipLabel = New("TextLabel", {
		Text = profileProps.Name or displayName, TextSize = 12, TextColor3 = "Text", Weight = "Medium",
		Size = UDim2.new(1, -textX - 10, 0, 14), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, textX, 0.5, 0),
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = footer,
	})
	local subText = profileProps.Subtitle
	if subText == true then subText = "@" .. userName end
	local chipSub = New("TextLabel", {
		Text = (subText and subText ~= false) and tostring(subText) or "", TextSize = 10, TextColor3 = "TextDim", Visible = false,
		Size = UDim2.new(1, -textX - 10, 0, 12), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, textX, 0.5, 7),
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = footer,
	})
	local function layoutProfile()
		local two = chipSub.Text ~= ""
		chipSub.Visible = two
		chipLabel.Position = two and UDim2.new(0, textX, 0.5, -7) or UDim2.new(0, textX, 0.5, 0)
	end
	layoutProfile()
	self._layoutProfile = layoutProfile
	self.Profile, self.ChipLabel, self.ChipSub, self.ProfileAvatar = footer, chipLabel, chipSub, head
	self._profileTextX = textX
	self._profileShown = showProfile

	-- content
	local content = New("Frame", { Name = "Content", BackgroundColor3 = "Background", Size = UDim2.new(1, -sidebarWidth, 1, 0), Position = UDim2.fromOffset(sidebarWidth, 0), ClipsDescendants = true, Parent = body })
	local contentCorner = Corner(CurrentTheme.WindowRadius or 14, content)
	onTheme(contentCorner, function() contentCorner.CornerRadius = UDim.new(0, CurrentTheme.WindowRadius or 14) end)
	-- square off the three inner corners (they sit against the sidebar / topbar, not the window edge)
	New("Frame", { BackgroundColor3 = "Background", Size = UDim2.fromOffset(20, 20), Parent = content })
	New("Frame", { BackgroundColor3 = "Background", Size = UDim2.fromOffset(20, 20), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Parent = content })
	New("Frame", { BackgroundColor3 = "Background", Size = UDim2.fromOffset(20, 20), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Parent = content })

	-- body veil: two window-coloured sheets (sidebar + page) that cover the contents while the
	-- window folds up / unfolds on minimise, so the elements are never seen being squashed.
	local bodyVeil = New("Frame", { Name = "BodyVeil", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -TOPBAR), Position = UDim2.fromOffset(0, TOPBAR), ZIndex = 80, Visible = false, Parent = main })
	pcall(function() bodyVeil.Interactable = false end)
	self.BodyVeil = bodyVeil
	self._veilParts = {}
	local function veilSheet(color, size, position, squareCorners)
		local sheet = New("Frame", { BackgroundColor3 = color, BackgroundTransparency = 1, Size = size, Position = position, ZIndex = 80, Parent = bodyVeil })
		local corner = Corner(CurrentTheme.WindowRadius or 14, sheet)
		onTheme(corner, function() corner.CornerRadius = UDim.new(0, CurrentTheme.WindowRadius or 14) end)
		self._veilParts[#self._veilParts + 1] = sheet
		for _, anchor in ipairs(squareCorners) do -- inner corners sit against the topbar / sidebar, keep them square
			self._veilParts[#self._veilParts + 1] = New("Frame", { BackgroundColor3 = color, BackgroundTransparency = 1, Size = UDim2.fromOffset(20, 20), AnchorPoint = anchor, Position = UDim2.fromScale(anchor.X, anchor.Y), ZIndex = 80, Parent = sheet })
		end
	end
	veilSheet("Sidebar", UDim2.new(0, sidebarWidth, 1, 0), UDim2.fromOffset(0, 0), { Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(1, 1) })
	veilSheet("Background", UDim2.new(1, -sidebarWidth, 1, 0), UDim2.fromOffset(sidebarWidth, 0), { Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(0, 1) })
	self.Content = content

	-- bottom fade (Gen 2): elements dissolve into the page colour as they scroll out at the base of
	-- the content instead of being cut by a hard edge. Interactable = false so it never eats input.
	local fade = New("Frame", {
		Name = "BottomFade", BackgroundColor3 = WHITE, Size = UDim2.new(1, 0, 0, BOTTOM_FADE_H), AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1), ZIndex = 4, Parent = content,
	})
	pcall(function() fade.Interactable = false end)
	local fadeCorner = Corner(CurrentTheme.WindowRadius or 14, fade)
	onTheme(fadeCorner, function() fadeCorner.CornerRadius = UDim.new(0, CurrentTheme.WindowRadius or 14) end)
	local fadeGradient = New("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.7), NumberSequenceKeypoint.new(1, 0) }),
		Parent = fade,
	})
	onTheme(fadeGradient, function() fadeGradient.Color = ColorSequence.new(themeValue("Background")) end)
	self.BottomFade = fade

	-- search results page
	local searchPage = New("ScrollingFrame", { Name = "SearchPage", Size = UDim2.fromScale(1, 1), Visible = false, Parent = content })
	Padding(searchPage, 14, 14, 14 + BOTTOM_FADE_PAD, 14)
	List(searchPage, 6, nil, Enum.HorizontalAlignment.Center)
	self.SearchPage = searchPage
	self.SearchEmpty = New("TextLabel", { Text = "No results", TextSize = 13, TextColor3 = "TextDim", Size = UDim2.new(1, 0, 0, 30), Visible = false, LayoutOrder = -1, Parent = searchPage })

	-- resize handle (desktop)
	local resizeHandle = New("TextButton", {
		Text = "", BackgroundTransparency = 1, Size = UDim2.fromOffset(18, 18), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, 0), ZIndex = 10, Visible = not IsMobile, Parent = main,
	})
	local resizeGlyph = Glyph("resize", resizeHandle, "TextDim", 12, 1.4)
	resizeGlyph.Position = UDim2.new(0.5, -3, 0.5, -3)
	connect(resizeHandle.MouseEnter, function() tintGlyph(resizeGlyph, themeValue("Text")) end)
	connect(resizeHandle.MouseLeave, function() tintGlyph(resizeGlyph, themeValue("TextDim"), Motion.slow) end)
	self.ResizeHandle = resizeHandle
	makeResizable(main, resizeHandle, self.MinSize, Vector2.new(1400, 1000), function(w, h)
		self.Size = Vector2.new(w, h)
	end)

	-- floating "open" pill (shown while hidden; essential on mobile)
	local pill = New("TextButton", {
		Text = "", BackgroundColor3 = "Surface", BackgroundTransparency = 0, Size = UDim2.fromOffset(0, 36), AutomaticSize = Enum.AutomaticSize.X,
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, topInset() + 12), ZIndex = 200, Active = true, Visible = false, Parent = root,
	})
	Corner(17, pill)
	Stroke(pill)
	Shadow(pill, "Shadow", 24, 0.4)
	Padding(pill, 0, 16, 0, 14)
	local pillDot = New("Frame", { BackgroundColor3 = "Accent", Size = UDim2.fromOffset(8, 8), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Parent = pill })
	Corner(4, pillDot)
	local pillLabel = New("TextLabel", { Text = prop(props, self.Name, "ShowText", "showName"), Weight = "SemiBold", TextSize = 13, Size = UDim2.fromOffset(0, 36), Position = UDim2.fromOffset(16, 0), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 201, Parent = pill })
	local pillHover = hoverOverlay(pill)
	hoverFx(pill, pillHover, nil, { strength = 0.95 })
	self.Pill = pill
	local pillMoved = false
	makeDraggable(pill, pill, { onDrag = function(_, delta) if delta.Magnitude > 8 then pillMoved = true end end })
	connect(pill.InputBegan, function() pillMoved = false end)
	local function pillTapped()
		if not pillMoved and self.Hidden then self:Show() end
	end
	connect(pill.MouseButton1Click, pillTapped)
	-- Activated also covers touch taps and gamepad; Show() is idempotent so firing twice is harmless
	pcall(function() connect(pill.Activated, pillTapped) end)

	-- drag the window by its topbar (open dropdowns / pickers would be left floating, so they close)
	makeDraggable(main, topbar, { onDragStart = closePopup })

	-- drag bar (Gen 2): a slim pill hanging under the window's bottom edge that also moves it. Lives
	-- in the root (the window clips its children) and is re-parked whenever the window moves or
	-- resizes, so a centred window keeps a centred bar and a dragged one keeps it underneath.
	local dragZone = New("Frame", { Name = "DragBar", BackgroundTransparency = 1, Size = UDim2.fromOffset(150, 22), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 5, Visible = false, Parent = root })
	local dragPill = New("Frame", {
		BackgroundColor3 = "Text", BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 4), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 9), ZIndex = 6, Parent = dragZone,
	})
	New("UICorner", { CornerRadius = UDim.new(1, 0), Parent = dragPill })
	Shadow(dragPill, "Text", 10, 0.88)
	local dragInteract = New("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 7, Parent = dragZone })
	self.DragBar, self.DragPill = dragZone, dragPill
	local DRAG_REST, DRAG_HOT = 0.7, 0.45
	local function syncDragBar()
		local pos = main.Position
		dragZone.Position = UDim2.new(pos.X.Scale, pos.X.Offset, pos.Y.Scale, pos.Y.Offset + main.Size.Y.Offset / 2 + 5)
	end
	self._syncDragBar = syncDragBar
	connect(main:GetPropertyChangedSignal("Position"), syncDragBar)
	connect(main:GetPropertyChangedSignal("Size"), syncDragBar)
	syncDragBar()
	local dragHeld = false
	connect(dragZone.MouseEnter, function()
		if not dragHeld and not self.Hidden then tween(dragPill, { Size = UDim2.fromOffset(120, 4), BackgroundTransparency = DRAG_HOT }, 0.25, Motion.Back, Motion.Out) end
	end)
	connect(dragZone.MouseLeave, function()
		if not dragHeld and not self.Hidden then tween(dragPill, { Size = UDim2.fromOffset(100, 4), BackgroundTransparency = DRAG_REST }, 0.25, Motion.Back, Motion.Out) end
	end)
	makeDraggable(main, dragInteract, {
		onDragStart = function()
			dragHeld = true
			closePopup()
			tween(dragPill, { Size = UDim2.fromOffset(120, 4), BackgroundTransparency = DRAG_HOT }, Motion.fast)
		end,
		onDragEnd = function()
			dragHeld = false
			tween(dragPill, { Size = UDim2.fromOffset(100, 4), BackgroundTransparency = DRAG_REST }, 0.25, Motion.Back, Motion.Out)
		end,
	})
	function self:_showDragBar(delay)
		task.delay(delay or 0, function()
			if self.Destroyed or self.Hidden then return end
			syncDragBar()
			dragZone.Visible = true
			dragPill.Size = UDim2.fromOffset(0, 4)
			dragPill.BackgroundTransparency = 1
			tween(dragPill, { Size = UDim2.fromOffset(100, 4), BackgroundTransparency = DRAG_REST }, 0.45, Motion.Expo, Motion.Out)
		end)
	end
	function self:_hideDragBar()
		tween(dragPill, { Size = UDim2.fromOffset(0, 4), BackgroundTransparency = 1 }, 0.18, Motion.Quint, Motion.Out)
		task.delay(0.19, function() if self.Hidden or self.Destroyed then dragZone.Visible = false end end)
	end

	-- wire topbar
	connect(closeBtn.MouseButton1Click, function() self:Hide() end)
	connect(minBtn.MouseButton1Click, function() self:ToggleMinimise() end)
	local searchOpen = false
	-- Topbar layout: [mark][title block][tags][search when open][buttons]. Everything to the left
	-- of the buttons is measured and placed by hand so the pieces never overlap:
	--   * the title block is its natural width, truncating only when it has to;
	--   * tags follow it and hide from the end when they stop fitting;
	--   * the open search field takes the rest - tags give way first, then the title shrinks
	--     to TITLE_MIN so the field always gets at least SEARCH_MIN.
	local TITLE_MIN, SEARCH_MIN, GAP = 64, 150, 12
	local BUTTONS_W = 3 * 30 + 2 * 2 + 10
	local function textWidth(label)
		if not label then return 0 end
		local w = label.TextBounds.X
		if w <= 0 then w = #tostring(label.Text) * 7 end
		return w
	end
	local function layoutTopbar(animateSearch)
		if self.Destroyed then return end
		local left, right = titleX, main.Size.X.Offset - BUTTONS_W - 10
		local span = math.max(right - left, 0)
		local titleW = math.ceil(math.max(textWidth(titleMeasure), textWidth(subMeasure))) + 4
		local tags, tagsW = {}, 0
		for _, tag in ipairs(self.Tags) do
			if tag.Enabled and not tag.Destroyed then
				tags[#tags + 1] = tag
				tagsW = tagsW + tag.Width + (#tags > 1 and TAG_GAP or 0)
			end
		end
		local tagsOn = #tags > 0
		local searchNeed = searchOpen and (SEARCH_MIN + GAP) or 0
		if searchOpen then
			local free = span - titleW - (tagsOn and (GAP + tagsW) or 0)
			if free < searchNeed and tagsOn then tagsOn = false free = span - titleW end
			if free < searchNeed then titleW = math.max(TITLE_MIN, span - searchNeed) end
		elseif tagsOn and titleW + GAP + tagsW > span then
			-- the title keeps its natural width (up to half the row); tags that don't fit hide instead
			titleW = math.max(TITLE_MIN, math.min(titleW, math.floor(span * 0.5)))
		end
		titleW = clamp(titleW, 0, span)
		titleLabel.Size = UDim2.fromOffset(titleW, 18)
		if sub then sub.Size = UDim2.fromOffset(titleW, 14) end
		local cursor = left + titleW
		tagBar.Visible = tagsOn
		if tagsOn then
			cursor = cursor + GAP
			tagBar.Position = UDim2.new(0, cursor, 0.5, 0)
			local limit, x, shown = right - searchNeed, 0, 0
			for _, tag in ipairs(self.Tags) do
				local fits = false
				if tag.Enabled and not tag.Destroyed then
					local w = tag.Width + (shown > 0 and TAG_GAP or 0)
					fits = cursor + x + w <= limit
					if fits then
						tag.Frame.Position = UDim2.new(0, x + (shown > 0 and TAG_GAP or 0), 0.5, 0)
						x = x + w
						shown = shown + 1
					end
				end
				tag.Frame.Visible = fits
			end
			tagBar.Size = UDim2.fromOffset(x, TAG_H)
			cursor = cursor + x
		end
		if searchOpen or searchHolder.Visible then
			local width = math.max(right - (cursor + GAP), SEARCH_H)
			searchHolder.Position = UDim2.new(0, right, 0.5, 0)
			if animateSearch then
				tween(searchHolder, { Size = UDim2.fromOffset(width, SEARCH_H) }, 0.35, Motion.Expo, Motion.Out)
			elseif searchOpen then
				searchHolder.Size = UDim2.fromOffset(width, SEARCH_H)
			end
		end
	end
	self._layoutTopbar = layoutTopbar
	connect(main:GetPropertyChangedSignal("Size"), function() layoutTopbar() end)
	connect(titleMeasure:GetPropertyChangedSignal("TextBounds"), function() layoutTopbar() end)
	if subMeasure then connect(subMeasure:GetPropertyChangedSignal("TextBounds"), function() layoutTopbar() end) end
	layoutTopbar()

	local function setSearch(state)
		if state == searchOpen then return end
		searchOpen = state
		if state then
			searchHolder.Visible = true
			searchHolder.Size = UDim2.fromOffset(SEARCH_H, SEARCH_H)
			tintGlyph(searchGlyph, themeValue("Accent"))
			layoutTopbar(true) -- grows out of the button into the free room
			tween(searchHolder, { BackgroundTransparency = 0 }, Motion.base)
			tween(searchStroke, { Transparency = CurrentTheme.StrokeTransparency }, 0.35)
			tween(searchBox, { TextTransparency = 0 }, 0.35)
			task.defer(function() pcall(function() searchBox:CaptureFocus() end) end)
		else
			searchBox.Text = ""
			pcall(function() searchBox:ReleaseFocus() end)
			tintGlyph(searchGlyph, themeValue("TextDim"), Motion.slow)
			tween(searchHolder, { Size = UDim2.fromOffset(SEARCH_H, SEARCH_H), BackgroundTransparency = 1 }, Motion.base, Motion.Quint, Motion.In)
			tween(searchStroke, { Transparency = 1 }, Motion.base)
			tween(searchBox, { TextTransparency = 1 }, Motion.base)
			task.delay(Motion.base + 0.01, function()
				if not searchOpen then
					searchHolder.Visible = false
					layoutTopbar() -- title and tags take their room back
				end
			end)
		end
	end
	self._setSearch = setSearch
	connect(searchBtn.MouseButton1Click, function() setSearch(not searchOpen) end)
	connect(clearBtn.MouseButton1Click, function()
		if searchBox.Text ~= "" then
			searchBox.Text = ""
			pcall(function() searchBox:CaptureFocus() end)
		else
			setSearch(false)
		end
	end)
	connect(searchBox:GetPropertyChangedSignal("Text"), function()
		clearBtn.Visible = true -- always reachable: clears text, or closes when empty
		self:_applySearch(searchBox.Text)
	end)
	connect(searchBox.FocusLost, function(enter)
		-- tapping away with nothing typed closes the pill; an empty Enter does too
		if searchBox.Text == "" then setSearch(false) end
	end)

	-- toggle key
	connect(UserInputService and UserInputService.InputBegan, function(input, processed)
		if self.Destroyed or KeybindListening then return end
		if self.ToggleKey and input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == self.ToggleKey and not isTyping() then
			self:Toggle()
		end
	end)

	-- keep inside the viewport when it changes (rotation, resize)
	connect(root:GetPropertyChangedSignal("AbsoluteSize"), function()
		if self.Minimised or self.Destroyed then return end
		local v = viewportSize()
		local w = math.min(self.Size.X, v.X - 24)
		local h = math.min(self.Size.Y, v.Y - 24)
		main.Size = UDim2.fromOffset(w, h)
		-- a dragged window keeps an offset position; pull it back inside the new viewport
		local pos = main.Position
		if pos.X.Scale == 0 and pos.Y.Scale == 0 then
			local x = clamp(pos.X.Offset, w * 0.5, math.max(w * 0.5, v.X - w * 0.5))
			local y = clamp(pos.Y.Offset, h * 0.5 + topInset(), math.max(h * 0.5 + topInset(), v.Y - h * 0.5))
			main.Position = UDim2.fromOffset(x, y)
		end
	end)

	-- veil: a window-coloured sheet above the content; fading it reveals the UI without a CanvasGroup
	local veil = New("Frame", { Name = "Veil", BackgroundColor3 = "Sidebar", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 90, Visible = false, Parent = main })
	local veilCorner = Corner(CurrentTheme.WindowRadius or 14, veil)
	onTheme(veilCorner, function() veilCorner.CornerRadius = UDim.new(0, CurrentTheme.WindowRadius or 14) end)
	self.Veil = veil
	self._introAt = os.clock()
	local keySystemRequested = prop(props, nil, "KeySystem", "keySystem")

	-- intro: pop from 0.86 with Expo Out while the veil lifts
	veil.Visible = true
	veil.BackgroundTransparency = 0
	mainScale.Scale = 0.86
	main.BackgroundTransparency = 1
	mainStroke.Transparency = 1
	tween(mainScale, { Scale = 1 }, 0.55, Motion.Expo, Motion.Out)
	tween(main, { BackgroundTransparency = 0 }, 0.3, Motion.Quint, Motion.Out)
	tween(mainStroke, { Transparency = CurrentTheme.StrokeTransparency }, 0.5, Motion.Quint, Motion.Out)
	task.delay(0.12, function()
		if self.Destroyed then return end
		tween(veil, { BackgroundTransparency = 1 }, 0.45, Motion.Quint, Motion.Out)
		task.delay(0.46, function() if not self.Destroyed and not self.Hidden then veil.Visible = false end end)
	end)
	if not keySystemRequested then self:_showDragBar(0.3) end

	Mova.Windows[#Mova.Windows + 1] = self

	-- key system ------------------------------------------------------------------------------
	local keySystem = keySystemRequested
	local keySettings = prop(props, nil, "KeySettings", "keySettings")
	if keySystem == true and typeof(keySettings) == "table" then keySystem = keySettings end
	if typeof(keySystem) == "table" then
		main.Visible = false
		self._keyGate = true
		self:_showKeySystem(keySystem, function()
			self._keyGate = false
			self.Hidden = true
			self:Show()
			self:_finishSetup(props)
		end)
	else
		self:_finishSetup(props)
	end

	return self
end

function Window:_finishSetup(props)
	-- settings tab is built lazily on first SelectTab so user tabs come first in the sidebar
	self._buildSettings = prop(props, true, "SettingsTab", "settingsTab", "ShowSettings")
	local tagList = prop(props, nil, "Tags", "tags")
	if typeof(tagList) == "table" then
		for _, t in ipairs(tagList) do self:CreateTag(t) end
	end
	local discord = prop(props, nil, "Discord", "discord")
	if typeof(discord) == "table" and discord.Enabled and discord.Invite and discord.Invite ~= "" then
		self._discordInvite = discord.Invite
	end
	task.defer(function()
		if self.Destroyed then return end
		if self.ConfigEnabled then
			self.Store:Migrate(self._legacyFolders)
			local saved = self.Store:Get("theme")
			if type(saved) == "string" and Mova.Themes[saved] then Mova:SetTheme(saved, false) end
		end
		if self._buildSettings then self:_createSettingsTab() end
		if self.ConfigEnabled and self._autoLoad then
			local auto = self:_readAutoload()
			if auto then self:LoadConfig(auto) end
		end
		if self._discordInvite and typeof(setclipboard) == "function" then
			local remembered = self.Store:Get("discordPrompted") == tostring(self._discordInvite)
				or FS.isfile(Mova.Folder .. "/discord_" .. tostring(self._discordInvite))
			if not remembered then
				Mova:Notify({
					Title = "Join the Discord", Content = "The developer of " .. tostring(self.Name) .. " has a Discord server.", Duration = 10,
					Actions = { { Text = "Copy invite", Callback = function()
						pcall(setclipboard, "https://discord.gg/" .. tostring(self._discordInvite))
						self.Store:Set("discordPrompted", tostring(self._discordInvite))
					end }, { Text = "Dismiss" } },
				})
			end
		end
	end)
end

-- Tabs ------------------------------------------------------------------------------------------

function Window:CreateTab(props, icon)
	if typeof(props) == "string" then props = { Name = props, Icon = icon } end
	props = props or {}
	local name = prop(props, "Tab", "Name", "name", "Title", "title")
	local iconValue = prop(props, nil, "Icon", "icon", "Image")
	local tab = setmetatable({
		Type = "Tab", Name = name, Window = self, Elements = {}, _order = 0,
	}, Tab)
	tab.Tab = tab

	local button = New("TextButton", {
		Text = "", BackgroundColor3 = "Surface", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 32), LayoutOrder = prop(props, self:_nextOrderTab(), "Order", "order"), Parent = self.TabList,
	})
	Corner(nil, button)
	local buttonStroke = Stroke(button)
	buttonStroke.Transparency = 1
	local hover = hoverOverlay(button)
	local iconImage = resolveIcon(iconValue)
	local labelX = 11
	if iconImage then
		New("ImageLabel", { Image = iconImage, ImageColor3 = "TextDim", Size = UDim2.fromOffset(16, 16), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), Name = "Icon", Parent = button })
		labelX = 32
	end
	local label = New("TextLabel", {
		TextSize = 13, Weight = "Medium", TextColor3 = "TextDim", Size = UDim2.new(1, -labelX - 6, 1, 0), Position = UDim2.fromOffset(labelX, 0),
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = button,
	})
	bindText(label, tostring(name))

	local page = New("ScrollingFrame", { Name = "Page", Size = UDim2.fromScale(1, 1), Visible = false, Parent = self.Content })
	Padding(page, 14, 14, 14 + BOTTOM_FADE_PAD, 14) -- extra room at the end so the last row clears the bottom fade
	List(page, 8, nil, Enum.HorizontalAlignment.Center)

	tab.Button, tab.Label, tab.Stroke, tab.Hover, tab.Page, tab.Holder, tab.Icon = button, label, buttonStroke, hover, page, page, button:FindFirstChild("Icon")
	tab._labelX = labelX

	connect(button.MouseEnter, function()
		if self.CurrentTab ~= tab then
			tween(hover, { BackgroundTransparency = 0.95 }, Motion.base)
			tween(label, { TextColor3 = themeValue("Text") }, Motion.base)
			if tab.Icon then tween(tab.Icon, { ImageColor3 = themeValue("Text") }, Motion.base) end
		end
	end)
	connect(button.MouseLeave, function()
		if self.CurrentTab ~= tab then
			tween(hover, { BackgroundTransparency = 1 }, Motion.slow)
			tween(label, { TextColor3 = themeValue("TextDim") }, Motion.slow)
			if tab.Icon then tween(tab.Icon, { ImageColor3 = themeValue("TextDim") }, Motion.slow) end
		end
	end)
	connect(button.MouseButton1Click, function() self:SelectTab(tab) end)

	-- staggered reveal while the window intro is still running
	if self._introAt and os.clock() - self._introAt < 1.2 then
		local idx = #self.Tabs
		label.TextTransparency = 1
		if tab.Icon then tab.Icon.ImageTransparency = 1 end
		label.Position = UDim2.fromOffset(labelX - 12, 0)
		task.delay(0.2 + math.min(idx, 8) * 0.045, function()
			if self.Destroyed then return end
			tween(label, { TextTransparency = 0, Position = UDim2.fromOffset(labelX, 0) }, 0.45, Motion.Expo, Motion.Out)
			if tab.Icon then tween(tab.Icon, { ImageTransparency = 0 }, 0.35, Motion.Quint, Motion.Out) end
		end)
	end

	self.Tabs[#self.Tabs + 1] = tab
	if not self.CurrentTab and not prop(props, false, "_internal") then
		self:SelectTab(tab)
	end
	return tab
end
Window.AddTab = Window.CreateTab

function Window:_nextOrderTab()
	self._order = self._order + 1
	return self._order
end

function Window:SelectTab(target)
	if typeof(target) == "string" then
		for _, t in ipairs(self.Tabs) do
			if t.Name == target then target = t break end
		end
	elseif typeof(target) == "number" then
		target = self.Tabs[target]
	end
	if typeof(target) ~= "table" or target.Page == nil then return end
	local previous = self.CurrentTab
	if previous == target then return end
	self.CurrentTab = target
	self._tabToken = (self._tabToken or 0) + 1
	local token = self._tabToken
	local downwards = true
	if previous then
		downwards = (target.Button.LayoutOrder or 0) >= (previous.Button.LayoutOrder or 0)
		tween(previous.Button, { BackgroundTransparency = 1 }, Motion.base)
		tween(previous.Label, { TextColor3 = themeValue("TextDim") }, Motion.base)
		setFont(previous.Label, "Medium")
		if previous.Icon then
			tween(previous.Icon, { ImageColor3 = themeValue("TextDim") }, Motion.base)
			ThemeRegistry[previous.Icon] = { ImageColor3 = "TextDim" }
		end
		ThemeRegistry[previous.Label] = { TextColor3 = "TextDim", FontFace = "@Medium" }
	end
	-- sidebar: selected pill + gliding indicator
	tween(target.Hover, { BackgroundTransparency = 1 }, Motion.fast)
	tween(target.Button, { BackgroundTransparency = 0 }, Motion.base)
	tween(target.Label, { TextColor3 = themeValue("Text") }, Motion.base)
	setFont(target.Label, "SemiBold")
	if target.Icon then
		tween(target.Icon, { ImageColor3 = themeValue("Accent") }, Motion.base)
		ThemeRegistry[target.Icon] = { ImageColor3 = "Accent" }
	end
	ThemeRegistry[target.Label] = { TextColor3 = "Text", FontFace = "@SemiBold" }
	-- the label nudges right a touch so the change is felt, not just seen (the list layout owns the
	-- button's Position). Always relative to the label's resting x, never to wherever a running
	-- tween left it, so rapid tab switching can't make it drift.
	local lx = target._labelX or target.Label.Position.X.Offset
	if not (self._introAt and os.clock() - self._introAt < 1.2) then
		target.Label.Position = UDim2.fromOffset(lx - 4, 0)
		tween(target.Label, { Position = UDim2.fromOffset(lx, 0) }, 0.35, Motion.Expo, Motion.Out)
	end
	-- content: previous page slides away and fades, new one slides in (Fluent-style)
	local offset = downwards and 18 or -18
	if previous then
		local prevPage = previous.Page
		tween(prevPage, { Position = UDim2.fromOffset(0, -offset) }, 0.12, Motion.Quint, Motion.In)
		task.delay(0.1, function()
			if token ~= self._tabToken then return end
			prevPage.Visible = false
			prevPage.Position = UDim2.fromOffset(0, 0)
		end)
	end
	local function reveal()
		if token ~= self._tabToken or self.Destroyed then return end
		if self._searching then return end
		target.Page.Position = UDim2.fromOffset(0, offset)
		target.Page.Visible = true
		tween(target.Page, { Position = UDim2.fromOffset(0, 0) }, 0.4, Motion.Expo, Motion.Out)
	end
	if previous then task.delay(0.1, reveal) else reveal() end
	closePopup()
	if self.SearchBox and self.SearchBox.Text ~= "" then self.SearchBox.Text = "" end
end
Window.Navigate = Window.SelectTab

-- Search ------------------------------------------------------------------------------------------

-- Obsidian-style forgiving match: every character of the query appears in order ("esp box" finds
-- "ESP: show boxes"), used as a fallback when the plain substring search finds nothing.
local function fuzzyMatch(text, query)
	query = query:gsub("%s+", "")
	if #query < 2 then return false end
	local pos = 1
	for i = 1, #query do
		local found = text:find(query:sub(i, i), pos, true)
		if not found then return false end
		pos = found + 1
	end
	return true
end

function Window:_applySearch(query)
	query = trim(query or ""):lower()
	local page = self.SearchPage
	if query == "" then
		-- restore every element to its original holder
		if self._searching then
			for _, el in ipairs(self._allElements) do
				if el._searchHome then
					el.Card.Parent = el._searchHome
					el.Card.LayoutOrder = el._searchOrder or el.Card.LayoutOrder
					if el._compactSize then el.Card.Size = el._compactSize end
					el._searchHome = nil
					el._searchHidden = nil
					el.Card.Visible = el.Visible ~= false
				end
			end
			page.Visible = false
			if self.CurrentTab then self.CurrentTab.Page.Visible = true end
			self._searching = false
		end
		return
	end
	self._searching = true
	if self.CurrentTab then self.CurrentTab.Page.Visible = false end
	page.Visible = true
	local count = 0
	for i, el in ipairs(self._allElements) do
		if not el.Destroyed and el.Card and el.Type ~= "Divider" then
			local haystack = (tostring(el.Name or "") .. " " .. tostring(el.Description or "")):lower()
			local match = haystack:find(query, 1, true) ~= nil or fuzzyMatch(haystack, query)
			if match and el.Visible ~= false then
				if not el._searchHome then
					el._searchHome = el.Card.Parent
					el._searchOrder = el.Card.LayoutOrder
				end
				el.Card.Parent = page
				el.Card.LayoutOrder = i
				if el._compactSize then el.Card.Size = UDim2.new(1, 0, el._compactSize.Y.Scale, el._compactSize.Y.Offset) end
				el.Card.Visible = true
				count = count + 1
			elseif el._searchHome then
				el.Card.Parent = el._searchHome
				el.Card.LayoutOrder = el._searchOrder or el.Card.LayoutOrder
				if el._compactSize then el.Card.Size = el._compactSize end
				el._searchHome = nil
			end
		end
	end
	self.SearchEmpty.Visible = count == 0
end

-- Visibility --------------------------------------------------------------------------------------

function Window:Show()
	if self.Destroyed then return end
	self.Hidden = false
	closePopup()
	self._visToken = (self._visToken or 0) + 1
	local token = self._visToken
	tween(self.Pill, { Position = UDim2.new(0.5, 0, 0, -40), BackgroundTransparency = 1 }, Motion.base, Motion.Quint, Motion.In)
	task.delay(Motion.base, function() if token == self._visToken and not self.Hidden then self.Pill.Visible = false end end)
	self.Main.Visible = true
	self.Veil.Visible = true
	self.Veil.BackgroundTransparency = 0
	self.MainScale.Scale = 0.92
	self.Main.BackgroundTransparency = 1
	tween(self.MainScale, { Scale = 1 }, 0.45, Motion.Expo, Motion.Out)
	tween(self.Main, { BackgroundTransparency = 0 }, Motion.base, Motion.Quint, Motion.Out)
	tween(self.MainStroke, { Transparency = CurrentTheme.StrokeTransparency }, Motion.slow)
	tween(self.Veil, { BackgroundTransparency = 1 }, 0.3, Motion.Quint, Motion.Out)
	task.delay(0.31, function() if token == self._visToken and not self.Hidden then self.Veil.Visible = false end end)
	self:_showDragBar(0.2)
end

function Window:Hide()
	if self.Destroyed then return end
	self.Hidden = true
	closePopup()
	if self._setSearch then self._setSearch(false) end
	self._visToken = (self._visToken or 0) + 1
	local token = self._visToken
	self.Veil.Visible = true
	self:_hideDragBar()
	tween(self.Veil, { BackgroundTransparency = 0 }, 0.12, Motion.Quint, Motion.Out)
	tween(self.MainScale, { Scale = 0.92 }, 0.25, Motion.Quint, Motion.In)
	tween(self.MainStroke, { Transparency = 1 }, 0.15)
	task.delay(0.08, function()
		if token ~= self._visToken then return end
		tween(self.Main, { BackgroundTransparency = 1 }, 0.17, Motion.Quint, Motion.In)
	end)
	task.delay(0.26, function()
		if token ~= self._visToken or not self.Hidden then return end
		self.Main.Visible = false
		self.Pill.Visible = true
		self.Pill.BackgroundTransparency = 1
		self.Pill.Position = UDim2.new(0.5, 0, 0, -40)
		tween(self.Pill, { Position = UDim2.new(0.5, 0, 0, topInset() + 12), BackgroundTransparency = 0 }, 0.45, Motion.Expo, Motion.Out)
	end)
end

function Window:Toggle()
	if self.Hidden then self:Show() else self:Hide() end
end
Window.ToggleHide = Window.Toggle

function Window:SetVisible(state)
	if state then self:Show() else self:Hide() end
end
Window.SetVisibility = Window.SetVisible

function Window:IsVisible() return not self.Hidden end

-- Covers / uncovers the body with the window-coloured veil.
function Window:_setBodyVeil(on, duration)
	local veil = self.BodyVeil
	if not veil then return end
	self._veilToken = (self._veilToken or 0) + 1
	local token = self._veilToken
	veil.Visible = true
	for _, part in ipairs(self._veilParts) do
		if duration and duration > 0 then
			tween(part, { BackgroundTransparency = on and 0 or 1 }, duration, Motion.Quint, Motion.Out)
		else
			part.BackgroundTransparency = on and 0 or 1
		end
	end
	if not on then
		task.delay((duration or 0) + 0.02, function() if token == self._veilToken and veil.Parent then veil.Visible = false end end)
	end
end

-- Minimise = contents first, frame second. The veil (window-coloured sheets above the whole body,
-- profile footer included) fades in, the body is then hidden outright, and only the empty frame
-- folds up to its topbar. Restoring unfolds the empty frame behind the veil and reveals the body
-- once it has landed. Nothing inside is ever seen squashed, clipped or peeking out.
local MIN_FOLD = 0.3
local VEIL_IN = 0.14
function Window:ToggleMinimise()
	self.Minimised = not self.Minimised
	self._minToken = (self._minToken or 0) + 1
	local token = self._minToken
	closePopup()
	if self._setSearch then self._setSearch(false) end
	local topbarHeight = self.Topbar.Size.Y.Offset
	if self.Minimised then
		self.ResizeHandle.Visible = false
		self:_setBodyVeil(true, VEIL_IN)
		task.delay(VEIL_IN, function()
			if token ~= self._minToken then return end
			self.Body.Visible = false
			tween(self.Main, { Size = UDim2.fromOffset(self.Size.X, topbarHeight) }, MIN_FOLD, Motion.Expo, Motion.Out)
			task.delay(MIN_FOLD + 0.02, function() if token == self._minToken and self.Minimised then self.BodyVeil.Visible = false end end)
		end)
	else
		self.Body.Visible = false
		self:_setBodyVeil(true, 0)
		tween(self.Main, { Size = UDim2.fromOffset(self.Size.X, self.Size.Y) }, MIN_FOLD, Motion.Expo, Motion.Out)
		task.delay(MIN_FOLD * 0.75, function()
			if token ~= self._minToken then return end
			self.Body.Visible = true
			self:_setBodyVeil(false, 0.2)
			task.delay(0.2, function() if token == self._minToken and not self.Minimised then self.ResizeHandle.Visible = not IsMobile end end)
		end)
	end
end
Window.ToggleMinimize = Window.ToggleMinimise
Window.Minimize = Window.ToggleMinimise

function Window:SetTitle(text) self.Name = text bindText(self.TitleLabel, tostring(text)) if self._titleMeasure then bindText(self._titleMeasure, tostring(text)) end if self._layoutTopbar then self._layoutTopbar() end return self end

-- Profile card: SetProfile{ Name = , Subtitle = , Image = } changes any of the lines (nil keeps,
-- false clears the subtitle line); SetProfileVisible(false) removes the card and gives the tab
-- list its height back.
function Window:SetProfile(info)
	info = info or {}
	if info.Name ~= nil then bindText(self.ChipLabel, tostring(info.Name)) end
	if info.Subtitle ~= nil then
		local text = info.Subtitle
		if text == true then text = "@" .. ((LocalPlayer and LocalPlayer.Name) or "guest") end
		text = text ~= false and tostring(text) or ""
		bindText(self.ChipSub, text)
		if self._layoutProfile then self._layoutProfile() end
	end
	if info.Image ~= nil and self._setAvatar then self._setAvatar(info.Image or nil) end
	return self
end

function Window:SetProfileVisible(state)
	state = state and true or false
	if state == self._profileShown then return self end
	self._profileShown = state
	self.Profile.Visible = state
	self.TabList.Size = UDim2.new(1, 0, 1, state and -self.Profile.Size.Y.Offset or 0)
	return self
end
function Window:IsProfileVisible() return self._profileShown end
function Window:SetSubtitle(text) if self.SubtitleLabel then bindText(self.SubtitleLabel, tostring(text)) end if self._subMeasure then bindText(self._subMeasure, tostring(text)) end if self._layoutTopbar then self._layoutTopbar() end return self end

-- Tags -------------------------------------------------------------------------------------------
-- Rayfield Gen 2's topbar tags (24px filled pills next to the title) with a few more options:
--   Style = "Soft" (default: tinted pill, coloured text and hairline - sits well on any theme)
--         | "Filled" (Gen 2: solid colour, contrast text)
--   Color = Color3 or a theme key ("Accent", "Success", "Warning", "Error" ...) that follows the theme
--   Icon / Dot = true (status dot instead of an icon), Callback (makes the tag clickable), Order
-- Tags that don't fit the topbar hide from the end; they also step aside for the search field.

local function luminance(c)
	return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B
end

function Window:CreateTag(props)
	if typeof(props) == "string" then props = { Text = props } end
	props = props or {}
	local tag = {
		Window = self, Type = "Tag", Enabled = true, Destroyed = false, Width = 0,
		Text = prop(props, nil, "Text", "text", "Title", "title", "Name"),
		Icon = prop(props, nil, "Icon", "icon", "Image"),
		Dot = prop(props, false, "Dot", "dot"),
		Color = prop(props, "Accent", "Color", "color", "Colour"),
		Style = prop(props, "Soft", "Style", "style"),
		Callback = prop(props, nil, "Callback", "callback", "OnClick"),
		Order = prop(props, #self.Tags + 1, "Order", "order"),
	}
	assert(tag.Text or tag.Icon or tag.Dot, "a tag needs Text, an Icon or Dot = true")
	local frame = New("TextButton", {
		Name = "Tag", Text = "", AutoButtonColor = false, BackgroundColor3 = WHITE, BackgroundTransparency = 1,
		Size = UDim2.fromOffset(20, TAG_H), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Parent = self.TagBar,
	})
	Corner(6, frame)
	local stroke = New("UIStroke", { Color = WHITE, Thickness = 1, Transparency = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = frame })
	local icon = New("ImageLabel", { Image = "", BackgroundTransparency = 1, Size = UDim2.fromOffset(13, 13), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 8, 0.5, 0), ImageTransparency = 1, Visible = false, Parent = frame })
	local dot = New("Frame", { BackgroundColor3 = WHITE, BackgroundTransparency = 1, Size = UDim2.fromOffset(6, 6), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 9, 0.5, 0), Visible = false, Parent = frame })
	New("UICorner", { CornerRadius = UDim.new(1, 0), Parent = dot })
	local label = New("TextLabel", { Text = "", TextSize = 12, Weight = "Medium", TextColor3 = WHITE, TextTransparency = 1, Size = UDim2.fromOffset(0, TAG_H), Position = UDim2.fromOffset(9, 0), TextXAlignment = Enum.TextXAlignment.Left, Parent = frame })
	tag.Frame, tag.Label, tag.IconLabel, tag.DotFrame, tag.Stroke = frame, label, icon, dot, stroke
	ThemeRegistry[label] = { FontFace = "@Medium" }

	local shown = false
	local function colour()
		if typeof(tag.Color) == "Color3" then return tag.Color end
		return themeValue(tag.Color) or themeValue("Accent")
	end
	local function paint(time)
		local c = colour()
		local filled = tag.Style == "Filled"
		local fg
		if filled then
			fg = luminance(c) > 0.55 and Color3.fromRGB(20, 20, 24) or Color3.fromRGB(250, 250, 252)
		else
			-- soft text is the tag colour pushed towards the theme's text so it stays legible on
			-- light pages (a pastel on white) as well as dark ones
			local lightPage = luminance(themeValue("Background") or Color3.new()) > 0.5
			fg = lightPage and c:Lerp(Color3.new(0, 0, 0), 0.52) or c:Lerp(Color3.new(1, 1, 1), 0.15)
		end
		local props = {
			bg = filled and 0 or 0.84, stroke = filled and 1 or 0.55,
		}
		local t = time or 0
		tween(frame, { BackgroundColor3 = c, BackgroundTransparency = shown and props.bg or 1 }, t)
		tween(stroke, { Color = c, Transparency = shown and props.stroke or 1 }, t)
		tween(label, { TextColor3 = fg, TextTransparency = shown and 0 or 1 }, t)
		tween(icon, { ImageColor3 = fg, ImageTransparency = shown and 0 or 1 }, t)
		tween(dot, { BackgroundColor3 = fg, BackgroundTransparency = shown and 0 or 1 }, t)
	end
	local function measure()
		local x = 9
		local hasText = tag.Text ~= nil and tag.Text ~= ""
		icon.Visible = tag.Icon ~= nil
		dot.Visible = not icon.Visible and tag.Dot and true or false
		if icon.Visible then
			icon.Position = UDim2.new(0, hasText and 8 or math.floor((TAG_H - 13) / 2), 0.5, 0)
			x = 8 + 13 + 5
		elseif dot.Visible then
			x = 9 + 6 + 6
		end
		label.Visible = hasText
		local w = x
		if hasText then
			label.Text = translate(tostring(tag.Text))
			local tw = label.TextBounds.X
			if tw <= 0 then tw = #label.Text * 6 end
			label.Position = UDim2.fromOffset(x, 0)
			label.Size = UDim2.fromOffset(tw + 1, TAG_H)
			w = x + tw + 1 + 9
		else
			w = TAG_H -- icon-only tag is square
		end
		tag.Width = math.ceil(w)
		frame.Size = UDim2.fromOffset(tag.Width, TAG_H)
	end
	if tag.Icon then applyIcon(icon, resolveIcon(tag.Icon)) end
	measure()
	onTheme(frame, function() if not tag.Destroyed then paint(0) end end)

	function tag:SetText(text) self.Text = text measure() if self.Window._layoutTopbar then self.Window._layoutTopbar() end return self end
	function tag:SetIcon(image)
		self.Icon = image
		if image then applyIcon(icon, resolveIcon(image)) else icon.Image = "" end
		measure()
		if self.Window._layoutTopbar then self.Window._layoutTopbar() end
		return self
	end
	function tag:SetColor(c) self.Color = c paint(Motion.base) return self end
	function tag:SetStyle(style) self.Style = style paint(Motion.base) return self end
	function tag:Set(info)
		if typeof(info) == "string" then return self:SetText(info) end
		info = info or {}
		local text = prop(info, nil, "Text", "text", "Title", "title")
		if text ~= nil then self.Text = text end
		if info.Icon ~= nil or info.icon ~= nil then self.Icon = info.Icon or info.icon if self.Icon then applyIcon(icon, resolveIcon(self.Icon)) else icon.Image = "" end end
		if info.Dot ~= nil then self.Dot = info.Dot end
		if info.Style or info.style then self.Style = info.Style or info.style end
		local c = prop(info, nil, "Color", "color", "Colour")
		if c ~= nil then self.Color = c end
		measure()
		paint(Motion.base)
		if self.Window._layoutTopbar then self.Window._layoutTopbar() end
		return self
	end
	function tag:SetVisible(state)
		self.Enabled = state and true or false
		if self.Window._layoutTopbar then self.Window._layoutTopbar() end
		return self
	end
	function tag:Destroy()
		if self.Destroyed then return end
		self.Destroyed = true
		shown = false
		paint(Motion.base)
		for i, t in ipairs(self.Window.Tags) do if t == self then table.remove(self.Window.Tags, i) break end end
		if self.Window._layoutTopbar then self.Window._layoutTopbar() end
		task.delay(Motion.base + 0.02, function() ThemeHooks[frame] = nil frame:Destroy() end)
	end
	tag.Remove = tag.Destroy

	if tag.Callback then
		connect(frame.MouseEnter, function() tween(frame, { BackgroundTransparency = tag.Style == "Filled" and 0.15 or 0.72 }, Motion.fast) end)
		connect(frame.MouseLeave, function() paint(Motion.base) end)
		connect(frame.MouseButton1Click, function() safeCallback(tag.Callback, tag) end)
	end

	self.Tags[#self.Tags + 1] = tag
	table.sort(self.Tags, function(a, b) return (a.Order or 0) < (b.Order or 0) end)
	if self._layoutTopbar then self._layoutTopbar() end
	-- settle in like Gen 2: a 0.25 Quint fade once placed
	shown = true
	paint(0.25)
	return tag
end
Window.AddTag = Window.CreateTag
Window.Tag = Window.CreateTag

function Window:SetToggleKey(key)
	self.ToggleKey = keyFromName(key)
	if self._toggleKeybind then self._toggleKeybind:Set(self.ToggleKey, true) end
	return self
end

function Window:ChangeTheme(theme) return Mova:SetTheme(theme) end
Window.ModifyTheme = Window.ChangeTheme
Window.SetTheme = Window.ChangeTheme

function Window:Notify(props) return Mova:Notify(props) end
function Window:Dialog(props) return Mova:Dialog(props) end
Window.Popup = Window.Dialog
function Window:Toast(props)
	props = typeof(props) == "string" and { Content = props } or (props or {})
	props.Duration = props.Duration or 2.5
	return Mova:Notify(props)
end

function Window:Get(flag) return Mova.Flags[flag] end
function Window:Set(flag, value, silent)
	local el = Mova.Options[flag]
	if el and el.Set then el:Set(value, silent) end
end

function Window:Destroy()
	if self.Destroyed then return end
	self.Destroyed = true
	closePopup()
	if self._autoSaveThread then pcall(task.cancel, self._autoSaveThread) end
	for _, el in ipairs(self._allElements) do
		el.Destroyed = true
		if el._cleanup then for _, fn in ipairs(el._cleanup) do pcall(fn) end end
		if el.Flag then
			if Mova.Options[el.Flag] == el then Mova.Options[el.Flag] = nil end
			if Mova.Toggles[el.Flag] == el then Mova.Toggles[el.Flag] = nil end
		end
	end
	KeybindListening = false
	self.Main:Destroy()
	self.Pill:Destroy()
	if self.DragBar then self.DragBar:Destroy() end
	local i = indexOf(Mova.Windows, self)
	if i then table.remove(Mova.Windows, i) end
end
Window.Unload = Window.Destroy

-- Configs -----------------------------------------------------------------------------------------

function Window:_configPath(name)
	return self.Store:ConfigPath(name or self.ConfigFile)
end

function Window:_collect()
	local data = {}
	for _, el in ipairs(self._allElements) do
		if el.Flag and el.Save ~= false and not el.Destroyed and el.Type ~= "Button" and el.Type ~= "Label" and el.Type ~= "Paragraph" then
			local v = el.Value
			if el.Type == "ColorPicker" and el.Alpha ~= nil then
				v = { __type = "ColorAlpha", color = encodeValue(el.Value), alpha = el.Alpha }
			else
				v = encodeValue(v)
			end
			data[el.Flag] = v
		end
	end
	return data
end

function Window:SaveConfig(name)
	if not self.ConfigEnabled then return false, "configuration saving is disabled" end
	name = safeName(name or self.ConfigFile)
	local ok, err = self.Store:WriteConfig(name, { version = 1, library = "Mova", data = self:_collect() })
	if not ok then return false, err end
	log("saved config", name)
	return true
end
Window.Save = Window.SaveConfig

function Window:LoadConfig(name, silent)
	if not self.ConfigEnabled then return false, "configuration saving is disabled" end
	name = safeName(name or self.ConfigFile)
	if not self.Store:HasConfig(name) then return false, "no such config" end
	local decoded = self.Store:ReadConfig(name)
	if not decoded then return false, "config file is corrupt" end
	local data = decoded.data or decoded
	local previousAuto = self._autoSave
	self._autoSave = false   -- don't re-save while applying
	for flag, value in pairs(data) do
		local el = Mova.Options[flag]
		if el and el.Set and el.Window == self then
			pcall(function()
				if typeof(value) == "table" and value.__type == "ColorAlpha" then
					el:Set(decodeValue(value.color), value.alpha, silent)
				else
					el:Set(decodeValue(value), silent)
				end
			end)
		end
	end
	self._autoSave = previousAuto
	log("loaded config", name)
	return true
end
Window.Load = Window.LoadConfig

function Window:ListConfigs()
	if not self.ConfigEnabled then return {} end
	return self.Store:ListConfigs()
end

function Window:DeleteConfig(name)
	if not self.ConfigEnabled then return false end
	if self.Store:DeleteConfig(name) then
		if self._activeConfig == safeName(name) then self._activeConfig = nil end
		return true
	end
	return false
end

function Window:_readAutoload()
	local v = self.Store:Get("autoload")
	if type(v) == "string" and v ~= "" then return v end
	return nil
end
Window.GetAutoload = Window._readAutoload
function Window:SetAutoload(name)
	if not self.ConfigEnabled then return false end
	self.Store:Set("autoload", name and safeName(name) or nil)
	return true
end

function Window:_queueAutoSave()
	if not self.ConfigEnabled or not self._autoSave or self.Destroyed then return end
	if self._autoSaveThread then pcall(task.cancel, self._autoSaveThread) end
	self._autoSaveThread = task.delay(0.6, function()
		self._autoSaveThread = nil
		self:SaveConfig(self._activeConfig or self.ConfigFile)
	end)
end

-- Settings tab ------------------------------------------------------------------------------------

function Window:_createSettingsTab()
	if self.SettingsTab then return self.SettingsTab end
	local tab = self:CreateTab({ Name = "Settings", Icon = "settings", _internal = true, Order = 10000 })
	tab._isSettings = true
	self.SettingsTab = tab

	local appearance = tab:CreateSection({ Name = "Appearance" })
	local names = Mova:GetThemeNames()
	appearance:CreateDropdown({
		Name = "Theme", Description = "Applies instantly to every window and is remembered.", Options = names, Default = CurrentTheme.Name, Save = false, AllowNone = false,
		Callback = function(v)
			if not v then return end
			Mova:SetTheme(v)
			if self.ConfigEnabled then self.Store:Set("theme", tostring(v)) end
		end,
	})
	if not IsMobile then
		self._toggleKeybind = appearance:CreateKeybind({
			Name = "Toggle UI key", Description = "Press to show or hide the window.", Default = self.ToggleKey, Save = false, Mode = "None",
			ChangedCallback = function(key) self.ToggleKey = key end,
		})
	end
	appearance:CreateButton({ Name = "Reset window position", Callback = function()
		tween(self.Main, { Position = UDim2.fromScale(0.5, 0.5) }, 0.45, Motion.Expo, Motion.Out)
	end })

	if self.ConfigEnabled then
		local configs = tab:CreateSection({ Name = "Configuration" })
		local list, autoloadToggle
		local function syncAutoload()
			if autoloadToggle then autoloadToggle:Set(list.Value ~= nil and self:_readAutoload() == list.Value, true) end
		end
		local function refresh(select)
			local names = self:ListConfigs()
			list:Refresh(names, true)
			if select then list:Set(select, true) end
			local auto = self:_readAutoload()
			list:SetDescription(#names == 0 and "Nothing saved yet — type a name below and press Enter."
				or ("Active: " .. (self._activeConfig or self.ConfigFile) .. (auto and ("  ·  Autoload: " .. auto) or "")))
			syncAutoload()
		end
		local function report(ok, title, content, err)
			Mova:Notify({ Title = ok and title or (title .. " failed"), Content = ok and content or tostring(err), Type = ok and "Success" or "Error", Duration = 3 })
		end

		-- pick a config, then act on it with the row below
		list = configs:CreateDropdown({
			Name = "Config", Options = self:ListConfigs(), Default = self._activeConfig, Save = false, Placeholder = "Select a config",
			Callback = syncAutoload,
		})
		local actions = configs:CreateRow({ Columns = 3 })
		actions:CreateButton({ Name = "Load", Callback = function()
			local name = list.Value
			if not name then Mova:Notify({ Title = "Pick a config", Content = "Select a saved config first.", Type = "Warning", Duration = 3 }) return end
			local ok, err = self:LoadConfig(name)
			if ok then self._activeConfig = name end
			refresh()
			report(ok, "Loaded", "'" .. name .. "' applied.", err)
		end })
		actions:CreateButton({ Name = "Save", Callback = function()
			local name = list.Value or self._activeConfig or self.ConfigFile
			local ok, err = self:SaveConfig(name)
			if ok then self._activeConfig = name end
			refresh(name)
			report(ok, "Saved", "'" .. name .. "' now holds the current values.", err)
		end })
		actions:CreateButton({ Name = "Delete", Callback = function()
			local name = list.Value
			if not name then return end
			Mova:Dialog({ Title = "Delete '" .. name .. "'?", Content = "The file is removed permanently.", Buttons = {
				{ Text = "Cancel" },
				{ Text = "Delete", Style = "Danger", Callback = function()
					self:DeleteConfig(name)
					if self:_readAutoload() == name then self:SetAutoload(nil) end
					refresh()
				end },
			} })
		end })

		-- create a new one: name + Enter
		local newInput
		newInput = configs:CreateInput({
			Name = "New config", Description = "Saves the current values under a new name.", Placeholder = "Name, then press Enter", Save = false, ClearOnFocus = true,
			Callback = function(text)
				local name = trim(text or "")
				if name == "" then return end
				name = safeName(name)
				local ok, err = self:SaveConfig(name)
				if ok then self._activeConfig = name end
				newInput:Set("", true)
				refresh(name)
				report(ok, "Created", "'" .. name .. "' saved and selected.", err)
			end,
		})

		autoloadToggle = configs:CreateToggle({ Name = "Autoload selected config", Description = "Applies it automatically when the script starts.", Default = false, Save = false, Callback = function(state)
			if state then
				if list.Value then self:SetAutoload(list.Value) else autoloadToggle:Set(false, true) end
			elseif self:_readAutoload() == list.Value then
				self:SetAutoload(nil)
			end
			refresh()
		end })
		configs:CreateToggle({ Name = "Auto save", Description = "Writes every change to the active config.", Default = self._autoSave, Save = false, Callback = function(state)
			self._autoSave = state
		end })
		configs:CreateLabel({ Name = "Stored in " .. self.Store.ConfigFolder .. "/", Icon = "config", Transparent = true })
		refresh(self._activeConfig)
	end

	local about = tab:CreateSection({ Name = "About" })
	about:CreateParagraph({ Title = "Mova Library " .. Mova.Version, Content = "Open source, MIT licensed, zero telemetry. Drawn entirely in code." .. (SecureMode and " Secure mode is on." or "") })
	about:CreateButton({ Name = "Unload interface", Description = "Destroys the UI. Your script keeps running.", Callback = function()
		Mova:Dialog({ Title = "Unload " .. tostring(self.Name) .. "?", Content = "The interface will be removed.", Buttons = {
			{ Text = "Cancel" }, { Text = "Unload", Style = "Danger", Callback = function() self:Destroy() end },
		} })
	end })
	return tab
end

-- Key system --------------------------------------------------------------------------------------

function Window:_showKeySystem(settings, onSuccess)
	local root = getRoot()
	local title = prop(settings, self.Name, "Title", "title")
	local subtitle = prop(settings, "Key System", "Subtitle", "subtitle")
	local note = prop(settings, "Enter your key to continue.", "Note", "note")
	local keys = prop(settings, {}, "Key", "Keys", "keys")
	if typeof(keys) == "string" then keys = { keys } end
	local validate = prop(settings, nil, "Validate", "validate", "Callback")
	local keyUrl = prop(settings, nil, "KeyURL", "keyUrl")
	if prop(settings, false, "GrabKeyFromSite") and not keyUrl then keyUrl = keys[1] keys = {} end
	local link = prop(settings, nil, "Link", "GetKeyLink", "link")
	local saveKey = prop(settings, true, "SaveKey", "saveKey")
	local keyFile = prop(settings, nil, "FileName", "fileName")
	local store = keyFile and Storage.forScript(keyFile) or self.Store   -- FileName shares one key between scripts
	store:Migrate(nil, Mova.Folder .. "/keys/" .. safeName(keyFile or (self.Name .. "_key")) .. ".txt")

	local remoteKeys = nil
	local function fetchRemote()
		if remoteKeys or not keyUrl then return end
		local ok, body = pcall(function() return game:HttpGet(keyUrl) end)
		if ok and body then
			remoteKeys = {}
			for _, line in ipairs(splitLines(body)) do
				line = trim(line)
				if line ~= "" then remoteKeys[#remoteKeys + 1] = line end
			end
		end
	end

	local function check(key)
		key = trim(key)
		if key == "" then return false end
		for _, k in ipairs(keys) do
			if trim(tostring(k)) == key then return true end
		end
		fetchRemote()
		if remoteKeys then
			for _, k in ipairs(remoteKeys) do if k == key then return true end end
		end
		if typeof(validate) == "function" then
			local ok, res = pcall(validate, key)
			if ok and res == true then return true end
		end
		return false
	end

	-- saved key
	if saveKey and type(store:Get("key")) == "string" then
		local saved = store:Get("key")
		if check(saved) then
			onSuccess()
			return
		end
	end

	local dim = New("Frame", { BackgroundColor3 = "Overlay", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = Layers.dialog })
	tween(dim, { BackgroundTransparency = 0.4 }, 0.3, Motion.Quint, Motion.Out)
	local vp = viewportSize()
	local card = New("Frame", {
		BackgroundColor3 = "Background", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 24), Size = UDim2.fromOffset(math.min(380, vp.X - 32), 0),
		AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = dim,
	})
	Corner(CurrentTheme.WindowRadius or 14, card)
	local cardStroke = Stroke(card)
	cardStroke.Transparency = 1
	Shadow(card, "Shadow", 48, 0.35)
	local cardScale = New("UIScale", { Scale = 0.92, Parent = card })
	Padding(card, 20, 20, 20, 20)
	List(card, 10)
	tween(card, { BackgroundTransparency = 0, Position = UDim2.fromScale(0.5, 0.5) }, 0.45, Motion.Expo, Motion.Out)
	tween(cardScale, { Scale = 1 }, 0.5, Motion.Back, Motion.Out)
	tween(cardStroke, { Transparency = CurrentTheme.StrokeTransparency }, 0.45)
	local head = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 1, Parent = card })
	local mark = New("Frame", { BackgroundColor3 = "Accent", Size = UDim2.fromOffset(10, 10), Position = UDim2.fromOffset(0, 7), Parent = head })
	Corner(5, mark)
	New("TextLabel", { Text = tostring(title), Weight = "SemiBold", TextSize = 17, Size = UDim2.new(1, -20, 0, 22), Position = UDim2.fromOffset(20, 0), TextXAlignment = Enum.TextXAlignment.Left, Parent = head })
	New("TextLabel", { Text = tostring(subtitle), TextSize = 12, TextColor3 = "TextDim", Size = UDim2.new(1, -20, 0, 14), Position = UDim2.fromOffset(20, 24), TextXAlignment = Enum.TextXAlignment.Left, Parent = head })
	New("TextLabel", { Text = tostring(note), TextSize = 13, TextColor3 = "TextDim", TextWrapped = true, LineHeight = 1.15, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, LayoutOrder = 3, Parent = card })
	local field = New("Frame", { BackgroundColor3 = "Field", Size = UDim2.new(1, 0, 0, 36), LayoutOrder = 4, Parent = card })
	Corner(nil, field)
	local fieldStroke = Stroke(field)
	local box = New("TextBox", { Text = "", PlaceholderText = "Paste your key", PlaceholderColor3 = "Placeholder", TextSize = 14, Size = UDim2.new(1, -24, 1, 0), Position = UDim2.fromOffset(12, 0), TextXAlignment = Enum.TextXAlignment.Left, Parent = field })
	connect(box.Focused, function() focusRing(fieldStroke, true) end)
	connect(box.FocusLost, function() tween(fieldStroke, { Color = themeValue("Stroke"), Transparency = CurrentTheme.StrokeTransparency }, Motion.base) end)
	local status = New("TextLabel", { Text = "", TextSize = 12, TextColor3 = "Error", Size = UDim2.new(1, 0, 0, 14), TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 5, Visible = false, Parent = card })
	local row = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36), LayoutOrder = 6, Parent = card })
	List(row, 8, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Right)
	Padding(row, 4, 0, 0, 0)

	local function button(text, primary, order)
		local b = New("TextButton", {
			Text = text, TextSize = 13, Weight = "SemiBold", BackgroundColor3 = primary and "Accent" or "Surface", TextColor3 = primary and "OnAccent" or "Text", BackgroundTransparency = 0,
			Size = UDim2.fromOffset(math.max(96, textWidth(text, 13) + 32), 32), LayoutOrder = order, Parent = row,
		})
		Corner(nil, b)
		if not primary then Stroke(b) end
		local h = hoverOverlay(b)
		hoverFx(b, h, nil, { strength = 0.88 })
		connect(b.MouseButton1Click, function() flash(h) end)
		return b
	end
	if link then
		local getKey = button("Get key", false, 1)
		connect(getKey.MouseButton1Click, function()
			if typeof(setclipboard) == "function" then
				pcall(setclipboard, link)
				status.Text = "Link copied to clipboard."
				status.TextColor3 = themeValue("Success")
				status.Visible = true
			else
				status.Text = tostring(link)
				status.TextColor3 = themeValue("TextDim")
				status.Visible = true
			end
		end)
	end
	local verify = button("Verify", true, 2)
	local busy = false
	local function attempt()
		if busy then return end
		busy = true
		verify.Text = "Checking..."
		task.spawn(function()
			local ok = check(box.Text)
			busy = false
			verify.Text = "Verify"
			if ok then
				if saveKey then store:Set("key", trim(box.Text)) end
				tween(dim, { BackgroundTransparency = 1 }, 0.25, Motion.Quint, Motion.In)
				tween(card, { BackgroundTransparency = 1 }, 0.2, Motion.Quint, Motion.In)
				tween(cardScale, { Scale = 1.04 }, 0.25, Motion.Quint, Motion.In)
				task.delay(0.26, function() dim:Destroy() end)
				onSuccess()
			else
				status.Text = "Invalid key."
				status.TextColor3 = themeValue("Error")
				status.Visible = true
				tween(fieldStroke, { Color = themeValue("Error"), Transparency = 0 }, 0.1)
				-- shake
				local base = field.Position
				for i, dx in ipairs({ -6, 6, -4, 4, 0 }) do
					task.delay((i - 1) * 0.05, function() tween(field, { Position = UDim2.new(base.X.Scale, base.X.Offset + dx, base.Y.Scale, base.Y.Offset) }, 0.05, Motion.Quint, Motion.Out) end)
				end
				task.delay(0.8, function() tween(fieldStroke, { Color = themeValue("Stroke"), Transparency = CurrentTheme.StrokeTransparency }, 0.3) end)
			end
		end)
	end
	connect(verify.MouseButton1Click, attempt)
	connect(box.FocusLost, function(enter) if enter then attempt() end end)
	self._keyCard = card
end

---------------------------------------------------------------------------------------------------
-- Library level helpers
---------------------------------------------------------------------------------------------------

function Mova:SetVisibility(state)
	for _, w in ipairs(Mova.Windows) do w:SetVisible(state) end
end

function Mova:IsVisible()
	for _, w in ipairs(Mova.Windows) do if not w.Hidden then return true end end
	return false
end

function Mova:Destroy()
	Mova.Unloaded = true
	closePopup()
	for i = #Mova.Windows, 1, -1 do pcall(function() Mova.Windows[i]:Destroy() end) end
	disconnectAll(Connections)
	if Root then pcall(function() Root:Destroy() end) end
	Root = nil
	NotifyHolder = nil
	Mova.Flags, Mova.Options, Mova.Toggles = {}, {}, {}
end
Mova.Unload = Mova.Destroy

function Mova:LoadConfiguration()
	for _, w in ipairs(Mova.Windows) do
		if w.ConfigEnabled then
			local auto = w:_readAutoload()
			w:LoadConfig(auto or w.ConfigFile)
		end
	end
end

function Mova:SaveConfiguration()
	for _, w in ipairs(Mova.Windows) do
		if w.ConfigEnabled then w:SaveConfig(w._activeConfig or w.ConfigFile) end
	end
end

Mova.New = New
Mova.Tween = tween
Mova.SafeCallback = safeCallback
Mova.KeyToString = keyToString

return Mova
