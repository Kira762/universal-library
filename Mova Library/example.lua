--[[
	Mova Library - full example
	Every element and most options are shown here. Paste into an executor (or load source.lua in Studio).
]]

-- 1. Load. Replace with your own raw URL / fork; Mova never phones home, so pin whichever commit you trust.
local Mova = loadstring(game:HttpGet("https://raw.githubusercontent.com/Kira762/universal-library/main/Mova%20Library/source.lua"))()

-- 2. Window --------------------------------------------------------------------------------
local Window = Mova:CreateWindow({
	Name = "Mova Example",
	Subtitle = "v1.0 • every element",
	Theme = "Midnight",                 -- Dark | Light | Midnight | Ocean | Ember | Amethyst | Rose | Mocha | custom table
	ToggleUIKeybind = "RightShift",     -- desktop show/hide key (mobile gets a floating pill automatically)
	Size = Vector2.new(640, 440),       -- clamped to the viewport on small screens
	ConfigurationSaving = {
		Enabled = true,
		FolderName = "MovaExample",       -- workspace/MovaExample/<name>.mova.json
		FileName = "default",
		AutoSave = true,                  -- debounced save whenever a flagged value changes
		AutoLoad = true,                  -- loads the autoload config (or FileName) after the UI is built
	},
	-- KeySystem = {
	-- 	Title = "Mova Example", Note = "Grab a key from our Discord.",
	-- 	Keys = { "hello-world" },                               -- local keys
	-- 	KeyURL = "https://example.com/keys.txt",                -- optional remote list (one per line)
	-- 	Validate = function(key) return key == "callback" end,  -- optional custom check
	-- 	Link = "https://example.com/get-key", SaveKey = true, FileName = "example",
	-- },
	Translations = { es = { ["Main"] = "Principal", ["Auto farm"] = "Granja automática" } },
	SettingsTab = true,                 -- built-in Settings tab (theme, toggle key, configs, unload)
})

-- 3. Tabs ----------------------------------------------------------------------------------
local Main = Window:CreateTab({ Name = "Main", Icon = 0 })        -- Icon: rbxassetid number, "rbxassetid://…", or a Lucide name if you registered a resolver
local Combat = Window:CreateTab({ Name = "Combat" })
local Visuals = Window:CreateTab({ Name = "Visuals" })
local Misc = Window:CreateTab({ Name = "Misc" })

-- 4. Main tab ------------------------------------------------------------------------------
Main:CreateParagraph({
	Title = "Welcome",
	Content = "Mova is drawn entirely in code, never makes a network request on its own, and saves typed configs.\nUse the search box at the top to find any option across every tab.",
})

Main:CreateButton({
	Name = "Say hello",
	Description = "Shows a notification with actions.",
	Callback = function()
		Mova:Notify({
			Title = "Hello!",
			Content = "Notifications support a type, icon, duration and action buttons.",
			Type = "Success",            -- Info | Success | Warning | Error
			Duration = 6,
			Actions = {
				{ Text = "Nice", Callback = function() print("nice") end },
				{ Text = "Dismiss" },
			},
		})
	end,
})

local AutoFarm = Main:CreateToggle({
	Name = "Auto farm",
	Description = "Flags are saved to the config and readable from Mova.Flags.AutoFarm",
	Flag = "AutoFarm",
	Default = false,
	Callback = function(state)
		print("Auto farm:", state)
	end,
})
AutoFarm:AddKeybind({ Default = "F", Mode = "Toggle" })   -- Linoria/Obsidian-style attached keybind that flips the toggle

Main:CreateSlider({
	Name = "Walk speed",
	Range = { 16, 200 },
	Increment = 1,
	Default = 16,
	Suffix = " studs/s",
	Flag = "WalkSpeed",
	Callback = function(value)
		local hum = game.Players.LocalPlayer.Character and game.Players.LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
		if hum then hum.WalkSpeed = value end
	end,
})

Main:CreateInput({
	Name = "Target player",
	Placeholder = "username",
	Flag = "Target",
	Finished = true,            -- false = fire on every keystroke
	Callback = function(text) print("target:", text) end,
})

Main:CreateInput({ Name = "Amount", Numeric = true, Default = "10", Flag = "Amount" })

-- 5. Combat tab (sections, keybind modes, dropdowns) -------------------------------------------
local Aim = Combat:CreateSection({ Name = "Aimbot", Collapsed = false })

Aim:CreateToggle({ Name = "Enabled", Flag = "AimEnabled" })

Aim:CreateKeybind({
	Name = "Aim key",
	Default = "MouseButton2",
	Mode = "Hold",                      -- Press | Toggle | Hold | Always
	Flag = "AimKey",
	Callback = function(holding) print("aiming:", holding) end,
	ChangedCallback = function(newKey) print("aim key is now", Mova.KeyToString(newKey)) end,
})

Aim:CreateSlider({ Name = "FOV", Range = { 10, 360 }, Increment = 5, Default = 90, Suffix = "°", Flag = "FOV" })
Aim:CreateSlider({ Name = "Smoothing", Min = 0, Max = 1, Increment = 0.05, Default = 0.35, Flag = "Smooth" })

Aim:CreateDropdown({
	Name = "Target part",
	Options = { "Head", "HumanoidRootPart", "Torso", "Random" },
	Default = "Head",
	Flag = "AimPart",
	Callback = function(value) print("part:", value) end,
})

local Targets = Aim:CreateDropdown({
	Name = "Targets",
	Options = { "Players", "NPCs", "Friends", "Team" },
	MultipleOptions = true,
	Default = { "Players", "NPCs" },
	Flag = "Targets",
	Callback = function(values) print("targets:", table.concat(values, ", ")) end,
})

-- lists with more than 6 entries get a type-to-filter box automatically
local players = {}
for _, p in ipairs(game.Players:GetPlayers()) do players[#players + 1] = p.Name end
local PlayerList = Combat:CreateDropdown({ Name = "Player", Options = players, Searchable = true, Flag = "Player" })
game.Players.PlayerAdded:Connect(function()
	local names = {}
	for _, p in ipairs(game.Players:GetPlayers()) do names[#names + 1] = p.Name end
	PlayerList:Refresh(names, true)       -- keep the current value if it still exists
end)

-- 6. Visuals tab (colour pickers, dividers) ----------------------------------------
Visuals:CreateDivider("ESP")

Visuals:CreateColorPicker({
	Name = "Box colour",
	Color = Color3.fromRGB(255, 80, 80),
	Flag = "BoxColor",
	Callback = function(color) print("box colour:", color:ToHex()) end,
})

Visuals:CreateColorPicker({
	Name = "Fill",
	Color = Color3.fromRGB(80, 160, 255),
	Alpha = 0.5,                        -- enables the transparency bar; callback receives (color, alpha)
	Flag = "FillColor",
	Callback = function(color, alpha) print("fill:", color:ToHex(), alpha) end,
})


Visuals:CreateLabel({ Name = "Labels can show icons", Icon = 4483362458 })
Visuals:CreateLabel("Plain string works too")

-- 7. Misc tab (Linoria/Obsidian style API, locking, dialogs, themes) ---------------------------
local Legacy = Misc:AddLeftGroupbox("Linoria style")
Legacy:AddToggle("LegacyToggle", { Text = "AddToggle works", Default = true, Tooltip = "Tooltips become descriptions" })
Legacy:AddSlider("LegacySlider", { Text = "AddSlider", Default = 5, Min = 0, Max = 10, Rounding = 1 })
Legacy:AddDropdown("LegacyDropdown", { Text = "AddDropdown", Values = { "a", "b", "c" }, Default = "a" })
Legacy:AddInput("LegacyInput", { Text = "AddInput", Placeholder = "type" })
Legacy:AddKeyPicker("LegacyKey", { Text = "AddKeyPicker", Default = "Z", Mode = "Toggle" })
Legacy:AddColorPicker("LegacyColor", { Text = "AddColorPicker", Default = Color3.new(1, 1, 1) })
Legacy:AddButton({ Text = "AddButton", Func = function() print(Mova.Toggles.LegacyToggle.Value) end })

local Danger = Misc:CreateSection({ Name = "Danger zone" })
local Nuke = Danger:CreateButton({
	Name = "Reset character",
	Callback = function()
		Mova:Dialog({
			Title = "Reset character?",
			Content = "You will respawn at the last checkpoint.",
			Buttons = {
				{ Text = "Cancel" },
				{ Text = "Reset", Style = "Danger", Callback = function()
					local char = game.Players.LocalPlayer.Character
					if char then char:BreakJoints() end
				end },
			},
		})
	end,
})
Danger:CreateToggle({
	Name = "Unlock danger zone",
	Callback = function(on)
		if on then Nuke:Unlock() else Nuke:Lock("Enable the toggle above first") end
	end,
})
Nuke:Lock("Enable the toggle above first")

Misc:CreateDropdown({
	Name = "Theme",
	Options = Mova:GetThemeNames(),
	Default = Mova:GetTheme().Name,
	Save = false,
	Callback = function(name) Mova:SetTheme(name) end,
})

Misc:CreateButton({
	Name = "Register a custom theme",
	Callback = function()
		Mova:RegisterTheme("Neon", { Accent = Color3.fromRGB(0, 255, 170), AccentHover = Color3.fromRGB(80, 255, 200), Background = Color3.fromRGB(8, 10, 14) })
		Mova:SetTheme("Neon")
	end,
})

Misc:CreateButton({ Name = "Switch to Spanish", Callback = function() Mova:SetLocale("es") end })
Misc:CreateButton({ Name = "Back to English", Callback = function() Mova:SetLocale("en") end })

-- 8. Reading values anywhere ----------------------------------------------------------------
task.spawn(function()
	while task.wait(1) do
		if Mova.Unloaded then break end
		if Mova.Flags.AutoFarm then
			-- do farming using Mova.Flags.WalkSpeed, Mova.Flags.Targets, ...
		end
	end
end)

-- React to a single element without polling
AutoFarm:OnChanged(function(state) print("AutoFarm changed ->", state) end)

-- 9. Configs ------------------------------------------------------------------------------------
-- Window:SaveConfig("pvp") / Window:LoadConfig("pvp") / Window:ListConfigs() / Window:DeleteConfig("pvp") / Window:SetAutoload("pvp")
-- The Settings tab exposes all of these to the user already.

Mova:Notify({ Title = "Mova loaded", Content = "Press RightShift to hide the UI.", Type = "Info" })
