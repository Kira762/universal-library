-- Runs example.lua against the mock to make sure the documented usage never drifts from the library.
local MOCK_PATH = ...
local mock = dofile(MOCK_PATH or "tests/roblox_mock.lua")
local Players = mock.Services.Players
Players.PlayerAdded = mock.Signal.new()
function Players:GetPlayers() return { { Name = "Tester" }, { Name = "Other" } } end
local MovaChunk = assert(loadfile("source.lua"))
local MovaRef
local realLoad = loadstring or load
_G.loadstring = function() return function() MovaRef = MovaChunk() return MovaRef end end -- example.lua's loadstring(game:HttpGet(...))
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
w:Destroy()
print(string.format("example ok: %d instances, config=%d bytes", mock.Created(), #mock.Files["MovaExample/default.mova.json"]))
print(mock.Files["MovaExample/default.mova.json"]:sub(1, 300) .. " ...")
