-- Secure mode (getgenv().MOVA_SECURE = true): asset ids are never handed to the engine. Like Rayfield
-- Gen 2, the PNG is fetched from Roblox's asset delivery once, written to Mova/icons/<id>.png and shown
-- through getcustomasset; labels fill in when the download lands. Names from icon packs are refused
-- because that would need a GitHub request.
local MOCK_PATH = ...
local mock = dofile(MOCK_PATH or "tests/roblox_mock.lua")
_G.MOVA_SECURE = true

local PNG = "\137PNG\r\n\26\n" .. string.rep("\0", 32)
local requests = {}
_G.request = function(opts)
	requests[#requests + 1] = opts.Url
	local id = opts.Url:match("id=(%d+)")
	if id == "404" then return { StatusCode = 404, Body = "<html>missing</html>" } end
	if id == "555" then return { StatusCode = 200, Body = "<html>not a png</html>" } end
	return { StatusCode = 200, Body = PNG }
end

local Mova = dofile("source.lua")
assert(Mova.SecureMode == true, "secure mode on")

local function iconOf(card) return mock.find(card, function(x) return x.ClassName == "ImageLabel" end) end
local W = Mova:CreateWindow({ Name = "Secure", Icon = 4483362458 })
local T = W:CreateTab({ Name = "Tab", Icon = 4483362458 })
mock.flush()

local l1 = T:CreateLabel({ Name = "cached", Icon = 4483362458 })
local l2 = T:CreateLabel({ Name = "same id", Icon = "rbxassetid://4483362458" })
mock.flush()
local uri = "rbxasset://custom/Mova/icons/4483362458.png"
assert(mock.Files["Mova/icons/4483362458.png"] == PNG, "png written to the icon cache")
assert(#requests == 1, "one download per asset id, got " .. #requests)
assert(iconOf(l1.Card).Image == uri, "label filled in once the download landed: " .. tostring(iconOf(l1.Card).Image))
assert(iconOf(l2.Card).Image == uri, "second label shares the same download")
assert(mock.find(T.Button, function(x) return x.ClassName == "ImageLabel" and x.Image == uri end), "tab icon filled in")
assert(W._titleMark and W._titleMark.Image == uri, "window icon filled in")

local l3 = T:CreateLabel({ Name = "from disk", Icon = 4483362458 })
assert(iconOf(l3.Card).Image == uri and #requests == 1, "later labels resolve straight from the cache")

local bad = T:CreateLabel({ Name = "not png", Icon = 555 })
mock.flush()
assert(mock.Files["Mova/icons/555.png"] == nil, "non-png bodies are never written to disk")
assert(iconOf(bad.Card).Image == "", "non-png stays blank")
local missing = T:CreateLabel({ Name = "404", Icon = 404 })
mock.flush()
assert(iconOf(missing.Card).Image == "" and mock.Files["Mova/icons/404.png"] == nil, "404 stays blank")
local n = #requests
T:CreateLabel({ Name = "404 again", Icon = 404 })
assert(#requests == n, "a failed id is not re-requested")

assert(iconOf(T:CreateLabel({ Name = "named", Icon = "home" }).Card) == nil, "pack names need GitHub, refused in secure mode")
assert(iconOf(T:CreateLabel({ Name = "thumb", Icon = "rbxthumb://type=Asset&id=1&w=48&h=48" }).Card).Image:sub(1, 11) == "rbxthumb://", "thumbnails allowed")
assert(iconOf(T:CreateLabel({ Name = "builtin", Icon = "settings" }).Card), "built-in names go through the cache too")
mock.flush()
assert(mock.Files["Mova/icons/" .. Mova.Icons.settings .. ".png"] == PNG, "built-in icon cached")

Mova:Notify({ Title = "Secure toast", Content = "icon via cache", Icon = 4483362458, Duration = 1 })
local holder = mock.find(mock.CoreGui, function(x) return x.Name == "Notifications" end)
assert(mock.find(holder, function(x) return x.ClassName == "ImageLabel" and x.Image == uri end), "notification icon from cache")

W:Destroy() Mova:Destroy()
for _ = 1, 5 do mock.flush() end
print(string.format("secure ok: %d downloads, %d instances", #requests, mock.Created()))
