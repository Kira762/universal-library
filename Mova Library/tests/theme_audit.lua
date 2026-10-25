-- Theme audit: builds the test.lua window, switches through EVERY theme and fails on
--  (a) an opaque frame whose colour is not in the theme palette (hard-coded or stale binding)
--  (b) text drawn on a backdrop with a luminance contrast below 4.5:1 (WCAG AA)
-- The only allowed off-palette backgrounds are the colour-picker swatches (they show the picked colour).
local MOCK_PATH = ...
local mock = dofile(MOCK_PATH or "tests/roblox_mock.lua")
local realLoad = loadstring or load
local MovaChunk = assert(loadfile("source.lua"))
local MovaRef
mock.Files["mova.lua"] = io.open("source.lua"):read("*a")
_G.loadstring = function(src) local f = assert(realLoad(src, "mova")) return function() MovaRef = f() return MovaRef end end
_G.game.HttpGet = function() return "404: Not Found" end
assert(realLoad(io.open("test.lua"):read("*a"), "test"))()
for _ = 1, 10 do mock.flush() end
local Mova = MovaRef
local win = Mova.Windows[#Mova.Windows]

local function lum(c)
	local function ch(v) v = v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4 return v end
	return 0.2126 * ch(c.R) + 0.7152 * ch(c.G) + 0.0722 * ch(c.B)
end
local function contrast(a, b) local la, lb = lum(a), lum(b) if la < lb then la, lb = lb, la end return (la + 0.05) / (lb + 0.05) end
local function key(c) return string.format("%d,%d,%d", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5)) end

local total = 0
for _, name in ipairs(Mova:GetThemeNames()) do
	Mova:SetTheme(name, false)
	for _ = 1, 3 do mock.flush() end
	local theme = Mova.Themes[name]
	local palette = { ["255,255,255"] = "white-base", ["0,0,0"] = "black" }
	for k, v in pairs(theme) do if typeof(v) == "Color3" then palette[key(v)] = k end end
	local issues = {}
	local function backdrop(o)
		local p = o.Parent
		while p do
			if (p.ClassName == "Frame" or p.ClassName == "TextButton" or p.ClassName == "TextBox" or p.ClassName == "ScrollingFrame") and p.BackgroundTransparency < 0.5 then
				local c = p.BackgroundColor3
				if key(c) == "255,255,255" then -- gradient-tinted: read the gradient
					for _, ch in ipairs(p:GetChildren()) do if ch.ClassName == "UIGradient" and ch.Color then return ch.Color.Keypoints[#ch.Color.Keypoints].Value end end
				end
				return c
			end
			p = p.Parent
		end
		return theme.Background
	end
	local function walk(o, depth)
		for _, ch in ipairs(o:GetChildren()) do
			local cls = ch.ClassName
			if (cls == "Frame" or cls == "TextButton" or cls == "TextBox" or cls == "ImageLabel" or cls == "ScrollingFrame") and ch.BackgroundTransparency < 1 then
				local k = key(ch.BackgroundColor3 or theme.Background)
				local isSwatch = ch.Parent and ch.Parent.ClassName == "Frame" and ch.Size.X.Offset == -8 and ch.Size.Y.Offset == -8
				if not palette[k] and ch.Name ~= "Glyph" and not isSwatch then
					-- allow brighten()/derived tints: skip if close to a palette colour
					issues[#issues + 1] = string.format("off-palette bg %s on %s '%s'", k, cls, ch.Name)
				end
			end
			if (cls == "TextLabel" or cls == "TextButton" or cls == "TextBox") and ch.Text ~= "" and ch.TextTransparency < 0.5 and ch.Visible ~= false then
				local bg = backdrop(ch) or theme.Background
				local tc = ch.TextColor3 or theme.Text
				local cr = contrast(tc, bg)
				if cr < 4.5 then issues[#issues + 1] = string.format("low contrast %.1f: '%s' text %s on %s", cr, tostring(ch.Text):sub(1, 24), key(tc), key(bg)) end
			end
			walk(ch, depth + 1)
		end
	end
	walk(win.Main, 0)
	-- dedupe
	local seen, out = {}, {}
	for _, i in ipairs(issues) do if not seen[i] then seen[i] = true out[#out + 1] = i end end
	print(string.format("== %s: %d issue(s)", name, #out))
	for _, i in ipairs(out) do print("   " .. i) end
	total = total + #out
end
print("theme audit: " .. total .. " issue(s)")
assert(total == 0, "theme audit found issues")
