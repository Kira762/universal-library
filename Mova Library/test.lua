--[[
	Mova Library - quick test script (no library code bundled)

	The library is fetched from the BRANCH url, not a commit url, so this file never needs
	to change when source.lua is updated: just re-run it and you get the latest push.

	Order of attempts:
	  1. raw.githubusercontent.com on the working branch  (works once the repo is public)
	  2. raw.githubusercontent.com on main                (after the branch is merged)
	  3. a local copy via readfile(LOCAL_FILE)            (works right now while the repo is private:
	                                                      save source.lua into your executor's workspace folder)
]]

local BRANCH_URL = "https://raw.githubusercontent.com/Kira762/universal-library/arena/98807242-universal-library/Mova%20Library/source.lua"
local MAIN_URL   = "https://raw.githubusercontent.com/Kira762/universal-library/main/Mova%20Library/source.lua"
local LOCAL_FILE = "mova.lua"

local function fetch(url)
	local ok, body = pcall(game.HttpGet, game, url)
	if ok and type(body) == "string" and body:find("Mova", 1, true) and not body:find("404: Not Found", 1, true) then
		return body
	end
	return nil
end

local source = fetch(BRANCH_URL) or fetch(MAIN_URL)
if not source and typeof(readfile) == "function" and typeof(isfile) == "function" and isfile(LOCAL_FILE) then
	source = readfile(LOCAL_FILE)
	print("[Mova test] loaded local copy: " .. LOCAL_FILE)
end
assert(source, "[Mova test] could not fetch source.lua (repo private?) and no local '" .. LOCAL_FILE .. "' found")

local chunk, err = loadstring(source)
assert(chunk, err)
local Mova = chunk()
print("[Mova test] Mova " .. tostring(Mova.Version) .. " loaded")

---------------------------------------------------------------------------------------------------
-- A compact window that touches every element, so you can eyeball visuals + animations fast.
---------------------------------------------------------------------------------------------------

local Window = Mova:CreateWindow({
	Name = "Mova Test",
	Subtitle = "visual check",
	Theme = "Midnight",
	ToggleUIKeybind = "RightShift",
	ConfigurationSaving = { Enabled = true, FolderName = "MovaTest" },
})

local Main = Window:CreateTab({ Name = "Main" })
local Controls = Window:CreateTab({ Name = "Controls" })
local Overlays = Window:CreateTab({ Name = "Overlays" })

Main:CreateParagraph({ Title = "What to look at", Content = "Hover a card (wash + outline), click a button (press bounce), flip the toggle (knob squash + glow), switch tabs (indicator glides, page slides)." })
Main:CreateButton({ Name = "Button", Description = "Chevron slides on hover, flashes on click.", Callback = function() print("clicked") end })
Main:CreateToggle({ Name = "Toggle", Flag = "TestToggle", Default = true, Callback = print })
	:AddKeybind({ Default = "Q", Mode = "Toggle" })
Main:CreateSlider({ Name = "Slider", Flag = "TestSlider", Range = { 0, 100 }, Increment = 1, Default = 40, Suffix = "%", Callback = print })
Main:CreateDivider("Grouped")
local section = Main:CreateSection({ Name = "Section (click header to collapse)" })
section:CreateToggle({ Name = "Inside a section", Flag = "Inner" })
section:CreateProgress({ Name = "Progress", Value = 65 })

Controls:CreateInput({ Name = "Input", Flag = "TestInput", Placeholder = "type and press enter", Callback = print })
Controls:CreateDropdown({ Name = "Dropdown", Flag = "TestDropdown", Options = { "Head", "Torso", "Legs" }, Default = "Head", Callback = print })
Controls:CreateDropdown({ Name = "Multi + search", Flag = "TestMulti", Options = { "Players", "NPCs", "Pets", "Vehicles", "Chests", "Ores", "Trees", "Quests" }, Multi = true, Default = { "Players" }, Searchable = true, Callback = function(v) print(table.concat(v, ", ")) end })
Controls:CreateKeybind({ Name = "Keybind (Hold)", Flag = "TestKey", Default = "E", Mode = "Hold", Callback = function(down) print("hold", down) end })
Controls:CreateColorPicker({ Name = "Colour", Flag = "TestColor", Default = Color3.fromRGB(99, 125, 255), Callback = print })
Controls:CreateColorPicker({ Name = "Colour + alpha", Flag = "TestColorA", Default = Color3.fromRGB(255, 80, 80), Transparency = 0.5, Callback = print })
Controls:CreateLabel({ Name = "A plain label" })
Controls:CreateToggle({ Name = "Locked toggle", Locked = true, LockReason = "Needs something enabled first." })

Overlays:CreateButton({ Name = "Notification (all 4 types)", Callback = function()
	for i, t in ipairs({ "Info", "Success", "Warning", "Error" }) do
		task.delay((i - 1) * 0.25, function()
			Mova:Notify({ Title = t, Content = "Slides in from the right, bar glows.", Type = t, Duration = 4, Actions = i == 1 and { { Text = "Action" }, { Text = "Close" } } or nil })
		end)
	end
end })
Overlays:CreateButton({ Name = "Dialog", Callback = function()
	Mova:Dialog({ Title = "Delete config?", Content = "Dim fades, panel pops with Back Out.", Buttons = { { Text = "Cancel" }, { Text = "Delete", Style = "Danger", Callback = function() print("deleted") end } } })
end })
Overlays:CreateButton({ Name = "Hide window (pill appears)", Callback = function() Window:Hide() end })
Overlays:CreateButton({ Name = "Minimise / restore", Callback = function() Window:ToggleMinimise() end })
Overlays:CreateDropdown({ Name = "Theme", Options = Mova:GetThemeNames(), Default = "Midnight", Save = false, Callback = function(t) Mova:SetTheme(t) end })
Overlays:CreateButton({ Name = "Unload", Callback = function() Mova:Destroy() end })

Mova:Notify({ Title = "Mova test ready", Content = "RightShift toggles the window. Settings tab has themes + configs.", Type = "Success", Duration = 5 })
