-- Runs example.lua against the mock to make sure the documented usage never drifts from the library.
local MOCK_PATH = ...
local mock = dofile(MOCK_PATH or "tests/roblox_mock.lua")
local Players = mock.Services.Players
Players.PlayerAdded = mock.Signal.new()
function Players:GetPlayers() return { { Name = "Tester" }, { Name = "Other" } } end
local MovaChunk = assert(loadfile("source.lua"))
local MovaRef
local realLoad = loadstring or load
-- example.lua's loadstring(game:HttpGet(...)) yields the library; the icon-pack fetch gets a tiny Lucide stand-in
mock.HttpGetResponse = function(url) if url:find("Footagesus/Icons", 1, true) then return 'return { house = "rbxassetid://1", eye = "rbxassetid://2" }' end return "" end
_G.loadstring = function(src)
	if src ~= "" then return realLoad(src) end
	return function() MovaRef = MovaChunk() return MovaRef end
end
local src = io.open("example.lua"):read("*a")
local fn = assert(realLoad(src, "example"))
fn()
for _ = 1, 25 do mock.flush() end -- progress bar loop + autoload
assert(MovaRef.Flags.AutoFarm == false and MovaRef.Flags.FOV == 90 and MovaRef.Flags.LegacyToggle == true, "flags populated")
assert(mock.Files["MovaExample/default.mova.json"] == nil, "nothing changed yet, so nothing autosaved")
MovaRef.Options.AutoFarm:Set(true)
mock.flush()
assert(mock.Files["MovaExample/default.mova.json"], "autosave produced a config after a change")
function Players:GetPlayers() return { { Name = "Tester" }, { Name = "Other" }, { Name = "New" } } end
Players.PlayerAdded:Fire()
assert(#MovaRef.Options.Player.Options == 3, "dropdown refreshed on PlayerAdded")
MovaRef:SetLocale("es")
assert(MovaRef.Options.AutoFarm.TitleLabel.Text == "Granja automática", MovaRef.Options.AutoFarm.TitleLabel.Text)
MovaRef:SetLocale("en")
local w = MovaRef.Windows[1]
assert(w.Main.Size.X.Offset == 640 and w.Main.Size.Y.Offset == 440, "Vector2 Size honoured")
assert(mock.find(w.Tabs[1].Button, function(x) return x.ClassName == "ImageLabel" and x.Image == "rbxassetid://1" end), "tab icon by Lucide name")
w:Destroy()
print(string.format("example ok: %d instances, config=%d bytes", mock.Created(), #mock.Files["MovaExample/default.mova.json"]))
print(mock.Files["MovaExample/default.mova.json"]:sub(1, 300) .. " ...")

-- test.lua (the no-bundle quick script) must also build cleanly; HttpGet is stubbed to "404" so it
-- falls through to readfile, which the mock serves from source.lua.
mock.Files["mova.lua"] = io.open("source.lua"):read("*a")
_G.loadstring = function(src) local f = assert(realLoad(src, "mova")) return function() MovaRef = f() return MovaRef end end
local game = _G.game
local oldHttpGet = game.HttpGet
game.HttpGet = function() return "404: Not Found" end
local tsrc = io.open("test.lua"):read("*a")
assert(realLoad(tsrc, "test"))()
for _ = 1, 10 do mock.flush() end
game.HttpGet = oldHttpGet
local tw = MovaRef.Windows[#MovaRef.Windows]
assert(tw.Name == "Mova Test" and #tw.Tabs >= 6, "test.lua window built")
-- every button in the quick script must run without throwing (the ones that hide / unload the UI
-- are skipped so the rest can still be pressed)
local pressed, errors = 0, {}
for _, el in ipairs(tw._allElements) do
	if el.Type == "Button" and not el.Destroyed and not (el.Name:find("Hide") or el.Name:find("Destroy everything")) then
		pressed = pressed + 1
		local ok, e = pcall(function() el:Press() for _ = 1, 3 do mock.flush() end end)
		if not ok then errors[#errors + 1] = el.Name .. ": " .. tostring(e) end
	end
end
assert(#errors == 0, "test.lua button callbacks threw:\n" .. table.concat(errors, "\n"))
for _, tab in ipairs(tw.Tabs) do tw:SelectTab(tab) end
MovaRef:SetLocale("es") MovaRef:SetLocale("en")
for _ = 1, 40 do mock.flush() end
tw:Destroy()
print(string.format("test.lua ok (%d buttons pressed)", pressed))
