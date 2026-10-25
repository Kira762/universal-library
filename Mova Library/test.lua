--[[
	Mova Library — quick test script

	No library code is bundled here. source.lua is fetched from the BRANCH url (not a commit url),
	so this file never has to change when the library is updated: re-run it and you get the latest
	push. Fallbacks: main branch → local readfile("mova.lua") (handy while the repo is private).

	Layout of the test window
	  Elements  — one of every element, each in a few variants
	  Layout    — sections, rows, columns, grids, responsive narrowing
	  States    — lock / unlock, hide / show, live retitle, destroy, programmatic Set
	  Overlays  — notifications, dialogs, toasts
	  Window    — show / hide / minimise, title, toggle key, themes, configs, locale, icons
	  Stress    — many elements + bulk Set, to check scrolling, search and performance
	  Settings  — built in by the library (themes, configs, toggle key)

	Everything that fires a callback prints a line prefixed with [Mova test].
]]

---------------------------------------------------------------------------------------------------
-- 1. Loader
---------------------------------------------------------------------------------------------------

local BRANCH_URL = "https://raw.githubusercontent.com/Kira762/universal-library/arena/98807242-universal-library/Mova%20Library/source.lua"
local MAIN_URL   = "https://raw.githubusercontent.com/Kira762/universal-library/main/Mova%20Library/source.lua"
local LOCAL_FILE = "mova.lua"

local function log(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
	print("[Mova test] " .. table.concat(parts, " "))
end

-- raw.githubusercontent.com caches a URL for ~5 minutes; a changing query string skips that cache
local function fetch(url)
	url = url .. "?t=" .. tostring(os.time())
	local ok, body = pcall(game.HttpGet, game, url)
	if ok and type(body) == "string" and body:find("Mova", 1, true) and not body:find("404: Not Found", 1, true) then
		return body
	end
	return nil
end

local source = fetch(BRANCH_URL) or fetch(MAIN_URL)
if not source and typeof(readfile) == "function" and typeof(isfile) == "function" and isfile(LOCAL_FILE) then
	source = readfile(LOCAL_FILE)
	log("loaded local copy: " .. LOCAL_FILE)
end
assert(source, "[Mova test] could not fetch source.lua (repo private?) and no local '" .. LOCAL_FILE .. "' found")

local chunk, err = loadstring(source)
assert(chunk, err)
local Mova = chunk()
log("Mova " .. tostring(Mova.Version) .. " loaded  (mobile=" .. tostring(Mova.IsMobile) .. ", secure=" .. tostring(Mova.SecureMode) .. ")")

---------------------------------------------------------------------------------------------------
-- 2. Window + tabs
---------------------------------------------------------------------------------------------------

local Window = Mova:CreateWindow({
	Name = "Mova Test",
	Subtitle = "v" .. tostring(Mova.Version),
	Icon = "flask-conical",            -- Lucide name; a number / "rbxassetid://…" works too
	Theme = "Mono",
	ToggleUIKeybind = "RightShift",
	ConfigurationSaving = { Enabled = true, FolderName = "MovaTest" },
	Tags = {                           -- topbar pills next to the title (Rayfield Gen 2 style)
		{ Text = "Beta", Style = "Filled", Color = Color3.fromRGB(255, 175, 15) },
		{ Text = "Online", Dot = true, Color = "Success" },
	},
})

local Tabs = {
	Elements = Window:CreateTab({ Name = "Elements", Icon = "layout-grid" }),
	Layout   = Window:CreateTab({ Name = "Layout",   Icon = "columns-3" }),
	States   = Window:CreateTab({ Name = "States",   Icon = "toggle-left" }),
	Overlays = Window:CreateTab({ Name = "Overlays", Icon = "bell" }),
	Window   = Window:CreateTab({ Name = "Window",   Icon = "app-window" }),
	Stress   = Window:CreateTab({ Name = "Stress",   Icon = "gauge" }),
}

---------------------------------------------------------------------------------------------------
-- 3. Elements — one of everything, in variants
---------------------------------------------------------------------------------------------------
do
	local T = Tabs.Elements

	T:CreateParagraph({
		Title = "What to look at",
		Content = "Hover a card (wash + outline sharpens), press a button (card dips and springs back), flip a toggle (one smooth slide), drag a slider (pill grows and ghosts), open a dropdown (grows out of the field).",
	})

	-- Buttons -------------------------------------------------------------------------------
	T:CreateDivider("Buttons")
	T:CreateButton({ Name = "Button", Callback = function() log("button pressed") end })
	T:CreateButton({ Name = "Button with description", Description = "Chevron slides on hover, flashes accent on click.", Callback = function() log("described button pressed") end })
	T:CreateButton({ Name = "Button with icon", Icon = "rocket", Callback = function() log("icon button pressed") end })

	-- Toggles -------------------------------------------------------------------------------
	T:CreateDivider("Toggles")
	T:CreateToggle({ Name = "Toggle (on)", Flag = "ToggleOn", Default = true, Callback = function(v) log("ToggleOn =", v) end })
	T:CreateToggle({ Name = "Toggle (off)", Flag = "ToggleOff", Callback = function(v) log("ToggleOff =", v) end })
	T:CreateToggle({ Name = "Toggle with description", Description = "Descriptions wrap onto as many lines as they need without pushing the switch around.", Flag = "ToggleDesc" })
	T:CreateToggle({ Name = "Toggle + keybind", Description = "Press Q to flip it. Click the key chip to rebind; Esc cancels, Backspace clears.", Flag = "ToggleKey", Callback = function(v) log("ToggleKey =", v) end })
		:AddKeybind({ Default = "Q", Mode = "Toggle" })

	-- Sliders -------------------------------------------------------------------------------
	T:CreateDivider("Sliders")
	T:CreateSlider({ Name = "Percent", Flag = "SliderPercent", Range = { 0, 100 }, Increment = 1, Default = 40, Suffix = "%", Callback = function(v) log("SliderPercent =", v) end })
	T:CreateSlider({ Name = "Walk speed", Description = "Large range, step 2. Click the value under the title to type one.", Flag = "SliderSpeed", Range = { 16, 500 }, Increment = 2, Default = 16, Suffix = " studs", Callback = function(v) log("SliderSpeed =", v) end })
	T:CreateSlider({ Name = "Decimals", Flag = "SliderDecimal", Min = 0, Max = 1, Increment = 0.05, Default = 0.25, Callback = function(v) log("SliderDecimal =", v) end })
	T:CreateSlider({ Name = "Negative range", Flag = "SliderNeg", Range = { -50, 50 }, Default = 0, Prefix = "x", Callback = function(v) log("SliderNeg =", v) end })

	-- Inputs --------------------------------------------------------------------------------
	T:CreateDivider("Inputs")
	T:CreateInput({ Name = "Input (on enter)", Flag = "InputEnter", Placeholder = "type, then press Enter", Callback = function(v) log("InputEnter =", v) end })
	T:CreateInput({ Name = "Input (live)", Description = "Fires on every keystroke.", Flag = "InputLive", Placeholder = "type…", Finished = false, Callback = function(v) log("InputLive =", v) end })
	T:CreateInput({ Name = "Numeric input", Flag = "InputNumber", Placeholder = "numbers only", Numeric = true, Default = "10", Callback = function(v) log("InputNumber =", v) end })
	T:CreateInput({ Name = "Clears after enter", Flag = "InputClear", Placeholder = "say something", ClearOnFocus = true, Save = false, Callback = function(v) log("InputClear =", v) end })

	-- Dropdowns -----------------------------------------------------------------------------
	T:CreateDivider("Dropdowns")
	T:CreateDropdown({ Name = "Single", Flag = "DropSingle", Options = { "Head", "Torso", "Legs" }, Default = "Head", Callback = function(v) log("DropSingle =", v) end })
	T:CreateDropdown({ Name = "Multi + search", Description = "More than 6 options gets a filter box; the field summarises with +N.", Flag = "DropMulti", Options = { "Players", "NPCs", "Pets", "Vehicles", "Chests", "Ores", "Trees", "Quests", "Bosses" }, Multi = true, Default = { "Players", "NPCs" }, Callback = function(v) log("DropMulti =", table.concat(v, ", ")) end })
	local players = T:CreateDropdown({ Name = "Refreshable (players)", Flag = "DropPlayers", Options = {}, AllowNone = true, Save = false, Callback = function(v) log("DropPlayers =", v) end })
	local function refreshPlayers()
		local names = {}
		local ok, list = pcall(function() return game:GetService("Players"):GetPlayers() end)
		for _, p in ipairs(ok and list or {}) do names[#names + 1] = p.Name end
		players:Refresh(names, true)
	end
	refreshPlayers()
	T:CreateButton({ Name = "Refresh player list", Callback = refreshPlayers })

	-- Keybinds ------------------------------------------------------------------------------
	T:CreateDivider("Keybinds")
	T:CreateKeybind({ Name = "Press", Description = "Fires once per press.", Flag = "KeyPress", Default = "F", Mode = "Press", Callback = function() log("KeyPress fired") end })
	T:CreateKeybind({ Name = "Toggle", Description = "Each press flips a state.", Flag = "KeyToggle", Default = "G", Mode = "Toggle", Callback = function(state) log("KeyToggle =", state) end })
	T:CreateKeybind({ Name = "Hold", Description = "True while held, false on release.", Flag = "KeyHold", Default = "H", Mode = "Hold", Callback = function(state) log("KeyHold =", state) end })
	T:CreateKeybind({ Name = "Mouse button", Flag = "KeyMouse", Default = "MouseButton2", Mode = "Hold", Callback = function(state) log("KeyMouse =", state) end })

	-- Colour pickers ------------------------------------------------------------------------
	T:CreateDivider("Colour pickers")
	T:CreateColorPicker({ Name = "Colour", Flag = "ColorPlain", Default = Color3.fromRGB(99, 125, 255), Callback = function(c) log("ColorPlain = #" .. c:ToHex()) end })
	T:CreateColorPicker({ Name = "Colour + alpha", Description = "Hex and RGB boxes accept typing.", Flag = "ColorAlpha", Default = Color3.fromRGB(255, 80, 80), Transparency = 0.5, Callback = function(c, a) log("ColorAlpha = #" .. c:ToHex(), "alpha", a) end })

	-- Text ----------------------------------------------------------------------------------
	T:CreateDivider("Text")
	T:CreateLabel({ Name = "A plain label" })
	T:CreateLabel({ Name = "Label with a Lucide icon", Icon = "eye" })
	T:CreateLabel({ Name = "Label with a built-in icon", Icon = "settings" })
	T:CreateParagraph({ Title = "Paragraph", Content = "Paragraphs hold longer explanatory text. This one is long enough to wrap onto a second line so you can check the line height and the card growing to fit." })
	T:CreateDivider()
	T:CreateLabel({ Name = "(a bare divider sits above this label)" })
end

---------------------------------------------------------------------------------------------------
-- 4. Layout — containers and responsive behaviour
---------------------------------------------------------------------------------------------------
do
	local T = Tabs.Layout

	local section = T:CreateSection({ Name = "Section (click the header to collapse)" })
	section:CreateToggle({ Name = "Inside a section", Flag = "SectionToggle" })
	section:CreateSlider({ Name = "Section slider", Flag = "SectionSlider", Range = { 0, 10 }, Default = 3 })
	section:CreateLabel({ Name = "Any element works inside a section" })

	local collapsed = T:CreateSection({ Name = "Starts collapsed", Collapsed = true })
	collapsed:CreateLabel({ Name = "You found me" })

	T:CreateDivider("Row — two columns, wraps")
	local row = T:CreateRow({ Columns = 2 })
	row:CreateToggle({ Name = "Left", Flag = "RowLeft", Default = true })
	row:CreateToggle({ Name = "Right", Flag = "RowRight" })
	row:CreateButton({ Name = "Third wraps", Callback = function() log("third") end })
	row:CreateSlider({ Name = "Compact slider", Flag = "RowSlider", Range = { 0, 10 }, Default = 3 })
	row:CreateInput({ Name = "Field", Flag = "RowInput", Placeholder = "shrinks first" })
	row:CreateDropdown({ Name = "Pick", Flag = "RowDrop", Options = { "A", "B", "C" }, Default = "A" })

	T:CreateDivider("Row — three columns")
	local three = T:CreateRow({ Columns = 3, Gap = 6 })
	three:CreateButton({ Name = "Save", Callback = function() log("save") end })
	three:CreateButton({ Name = "Load", Callback = function() log("load") end })
	three:CreateButton({ Name = "Reset", Callback = function() log("reset") end })

	T:CreateDivider("Grid — a row of two columns")
	local grid = T:CreateRow({ Columns = 2 })
	local left, right = grid:CreateColumn(), grid:CreateColumn()
	left:CreateLabel({ Name = "Left column" })
	left:CreateToggle({ Name = "Aim", Flag = "GridAim" })
	left:CreateToggle({ Name = "Silent", Flag = "GridSilent" })
	right:CreateLabel({ Name = "Right column" })
	right:CreateSlider({ Name = "FOV", Flag = "GridFov", Range = { 10, 180 }, Default = 90 })
	right:CreateKeybind({ Name = "Key", Flag = "GridKey", Default = "X" })

	T:CreateDivider("Responsive")
	T:CreateParagraph({ Title = "Resize the window", Content = "Drag the corner handle to make the window narrow: fields and tracks shrink towards a minimum first, then drop under their titles. Grow it again and everything comes back to one row." })
	T:CreateToggle({ Name = "This toggle has a deliberately long title so it stacks early on narrow windows", Flag = "LongTitle" })
end

---------------------------------------------------------------------------------------------------
-- 5. States — things you do to elements after creating them
---------------------------------------------------------------------------------------------------
do
	local T = Tabs.States

	T:CreateDivider("Lock / unlock")
	local locked = T:CreateToggle({ Name = "Locked toggle", Flag = "LockedToggle", Locked = true, LockReason = "Unlock it with the button below." })
	T:CreateButton({ Name = "Toggle lock", Callback = function()
		if locked:IsLocked() then locked:Unlock() else locked:Lock("Locked again from the button.") end
		log("locked =", locked:IsLocked())
	end })

	T:CreateDivider("Visibility")
	local hideMe = T:CreateLabel({ Name = "Hide me with the button below" })
	T:CreateButton({ Name = "Show / hide the label", Callback = function() hideMe:SetVisible(not hideMe.Visible) end })

	T:CreateDivider("Live retitle")
	local counter, clicks = nil, 0
	counter = T:CreateButton({ Name = "Clicked 0 times", Description = "Title and description update in place.", Callback = function()
		clicks = clicks + 1
		counter:SetTitle("Clicked " .. clicks .. " times")
		counter:SetDescription(clicks % 2 == 0 and "Even." or "Odd.")
	end })
	local para = T:CreateParagraph({ Title = "Live paragraph", Content = "Press the button to replace this text." })
	T:CreateButton({ Name = "Rewrite the paragraph", Callback = function() para:Set({ Title = "Rewritten at " .. os.date("%X"), Content = "Paragraph:Set replaces title and content together." }) end })

	T:CreateDivider("Programmatic Set (silent = no callback)")
	local tg = T:CreateToggle({ Name = "Target toggle", Flag = "SetToggle", Callback = function(v) log("SetToggle callback", v) end })
	local sl = T:CreateSlider({ Name = "Target slider", Flag = "SetSlider", Range = { 0, 100 }, Default = 10, Callback = function(v) log("SetSlider callback", v) end })
	local dd = T:CreateDropdown({ Name = "Target dropdown", Flag = "SetDrop", Options = { "One", "Two", "Three" }, Default = "One", Callback = function(v) log("SetDrop callback", v) end })
	local cp = T:CreateColorPicker({ Name = "Target colour", Flag = "SetColor", Default = Color3.fromRGB(255, 255, 255), Callback = function(c) log("SetColor callback #" .. c:ToHex()) end })
	T:CreateButton({ Name = "Set all (with callbacks)", Callback = function()
		tg:Set(not tg.Value)
		sl:Set(math.random(0, 100))
		dd:Set(({ "One", "Two", "Three" })[math.random(3)])
		cp:Set(Color3.fromHSV(math.random(), 0.7, 1))
	end })
	T:CreateButton({ Name = "Set all silently", Callback = function()
		tg:Set(not tg.Value, true)
		sl:Set(math.random(0, 100), true)
		dd:Set(({ "One", "Two", "Three" })[math.random(3)], true)
		cp:Set(Color3.fromHSV(math.random(), 0.7, 1), nil, true)
		log("silent set done; flags:", Mova.Flags.SetToggle, Mova.Flags.SetSlider, Mova.Flags.SetDrop)
	end })
	T:CreateButton({ Name = "Window:Set / Window:Get by flag", Callback = function()
		Window:Set("SetSlider", 50)
		log("Window:Get('SetSlider') =", Window:Get("SetSlider"))
	end })

	T:CreateDivider("OnChanged")
	local watched = T:CreateToggle({ Name = "Watched toggle", Flag = "Watched" })
	watched:OnChanged(function(v) log("OnChanged ->", v) end)

	T:CreateDivider("Destroy")
	local victim = T:CreateLabel({ Name = "This label can be destroyed" })
	T:CreateButton({ Name = "Destroy the label", Callback = function() if not victim.Destroyed then victim:Destroy() log("label destroyed") end end })
end

---------------------------------------------------------------------------------------------------
-- 6. Overlays — notifications, dialogs, toasts
---------------------------------------------------------------------------------------------------
do
	local T = Tabs.Overlays

	T:CreateDivider("Notifications")
	T:CreateButton({ Name = "One of each type", Description = "Tap to dismiss, hover to pause the timer.", Callback = function()
		local icons = { Info = "info", Success = "circle-check", Warning = "triangle-alert", Error = "circle-x" }
		for i, t in ipairs({ "Info", "Success", "Warning", "Error" }) do
			task.delay((i - 1) * 0.25, function()
				Mova:Notify({ Title = t, Content = "A " .. t:lower() .. " notification.", Type = t, Icon = icons[t] })
			end)
		end
	end })
	T:CreateButton({ Name = "With action buttons", Callback = function()
		Mova:Notify({ Title = "Update available", Content = "Version 1.1 is out.", Type = "Info", Icon = "download", Duration = 8,
			Actions = { { Text = "Update", Callback = function() log("update chosen") end }, { Text = "Later" } } })
	end })
	T:CreateButton({ Name = "Long content (auto duration)", Callback = function()
		Mova:Notify({ Title = "Long one", Content = "Duration is derived from the length of the text when you do not pass one, so a longer message stays up for longer — up to nine seconds." })
	end })
	T:CreateButton({ Name = "No icon, short, 2 seconds", Callback = function() Mova:Notify({ Title = "Quick", Content = "Gone in two.", Duration = 2 }) end })
	T:CreateButton({ Name = "Asset-id icon", Callback = function() Mova:Notify({ Title = "Asset icon", Content = "Icon = 4483362458", Icon = 4483362458 }) end })
	T:CreateButton({ Name = "Five at once (stacking)", Callback = function()
		for i = 1, 5 do Mova:Notify({ Title = "Stacked " .. i, Content = "Toasts stack and slide up as they go.", Duration = 3 + i }) end
	end })
	T:CreateButton({ Name = "Toast (plain string)", Callback = function() Window:Toast("Saved.") end })

	T:CreateDivider("Dialogs")
	T:CreateButton({ Name = "Confirm dialog", Callback = function()
		Mova:Dialog({ Title = "Delete config?", Content = "This cannot be undone.", Buttons = {
			{ Text = "Cancel", Callback = function() log("cancel") end },
			{ Text = "Delete", Style = "Danger", Callback = function() log("deleted") end },
		} })
	end })
	T:CreateButton({ Name = "Dismissable dialog (click outside)", Callback = function()
		Mova:Dialog({ Title = "Heads up", Content = "Clicking the dim backdrop closes this one.", Dismissable = true, Buttons = { { Text = "OK" } } })
	end })
	T:CreateButton({ Name = "Three buttons", Callback = function()
		Mova:Dialog({ Title = "Save changes?", Content = "You have unsaved changes.", Buttons = { { Text = "Discard", Style = "Danger" }, { Text = "Cancel" }, { Text = "Save", Callback = function() log("saved") end } } })
	end })
end

---------------------------------------------------------------------------------------------------
-- 7. Window — chrome, themes, configs, locale, icons
---------------------------------------------------------------------------------------------------
do
	local T = Tabs.Window

	T:CreateDivider("Visibility")
	T:CreateButton({ Name = "Hide (pill appears; click it or press RightShift)", Callback = function() Window:Hide() end })
	T:CreateButton({ Name = "Hide for 2 seconds, then show", Callback = function() Window:Hide() task.delay(2, function() Window:Show() end) end })
	T:CreateButton({ Name = "Minimise / restore", Callback = function() Window:ToggleMinimise() end })
	T:CreateButton({ Name = "Reset position (centre)", Callback = function() Window.Main.Position = UDim2.fromScale(0.5, 0.5) end })

	T:CreateDivider("Title bar")
	local titles = { "Mova Test", "Renamed", "Third title" }
	local ti = 1
	T:CreateButton({ Name = "Cycle the window title", Callback = function() ti = ti % #titles + 1 Window:SetTitle(titles[ti]) end })
	T:CreateButton({ Name = "Set the subtitle to the time", Callback = function() Window:SetSubtitle(os.date("%X")) end })
	T:CreateDivider("Tags (topbar pills) — resize the window or open the search to watch them make room")
	local extraTag
	local tagRow = T:CreateRow({ Columns = 2 })
	tagRow:CreateButton({ Name = "Add a clickable tag", Callback = function()
		if extraTag then return end
		extraTag = Window:CreateTag({ Text = "Discord", Icon = "message-circle", Callback = function() Window:Toast("Tag clicked") end })
		log("tag added")
	end })
	tagRow:CreateButton({ Name = "Recolour 'Online'", Callback = function()
		local t = Window.Tags[2]
		if t then t:Set({ Text = t.Text == "Online" and "Away" or "Online", Color = t.Text == "Online" and "Warning" or "Success" }) end
	end })
	tagRow:CreateButton({ Name = "Hide / show 'Beta'", Callback = function() local t = Window.Tags[1] if t then t:SetVisible(not t.Enabled) end end })
	tagRow:CreateButton({ Name = "Remove the added tag", Callback = function() if extraTag then extraTag:Destroy() extraTag = nil log("tag removed") end end })
	T:CreateDivider("Profile card (bottom of the sidebar)")
	local profileRow = T:CreateRow({ Columns = 2 })
	profileRow:CreateButton({ Name = "Subtitle → Premium", Callback = function() Window:SetProfile({ Subtitle = "Premium" }) log("profile subtitle set") end })
	profileRow:CreateButton({ Name = "Subtitle → none", Callback = function() Window:SetProfile({ Subtitle = false }) log("profile subtitle cleared") end })
	profileRow:CreateButton({ Name = "Rename → Guest", Callback = function() Window:SetProfile({ Name = "Guest", Image = "user" }) log("profile renamed") end })
	profileRow:CreateButton({ Name = "Show / hide card", Callback = function() Window:SetProfileVisible(not Window:IsProfileVisible()) log("profile visible =", Window:IsProfileVisible()) end })
	T:CreateKeybind({ Name = "Window toggle key", Description = "Rebinding here changes the key that shows / hides the window.", Default = "RightShift", Mode = "Press", Save = false, ChangedCallback = function(key) Window:SetToggleKey(key) log("toggle key =", key) end })

	T:CreateDivider("Themes")
	T:CreateDropdown({ Name = "Theme", Options = Mova:GetThemeNames(), Default = "Mono", Save = false, Callback = function(t) Mova:SetTheme(t) end })
	T:CreateButton({ Name = "Register + apply a custom theme", Callback = function()
		Mova:RegisterTheme("Test Teal", { Accent = Color3.fromRGB(70, 200, 180), AccentHover = Color3.fromRGB(110, 225, 205) })
		Mova:SetTheme("Test Teal")
	end })

	T:CreateDivider("Configs")
	local configName = T:CreateInput({ Name = "Config name", Default = "quick", Save = false })
	local row = T:CreateRow({ Columns = 3 })
	row:CreateButton({ Name = "Save", Callback = function() Window:SaveConfig(configName.Value) log("saved", configName.Value) end })
	row:CreateButton({ Name = "Load", Callback = function() Window:LoadConfig(configName.Value) log("loaded", configName.Value) end })
	row:CreateButton({ Name = "List", Callback = function() log("configs:", table.concat(Window:ListConfigs(), ", ")) end })
	T:CreateButton({ Name = "Autoload this config on start", Callback = function() Window:SetAutoload(configName.Value) log("autoload =", configName.Value) end })

	T:CreateDivider("Localisation")
	Mova:SetTranslations({ es = { ["Elements"] = "Elementos", ["Layout"] = "Diseño", ["States"] = "Estados", ["Overlays"] = "Capas", ["Window"] = "Ventana", ["Stress"] = "Carga", ["Theme"] = "Tema", ["Config name"] = "Nombre de configuración" } })
	T:CreateDropdown({ Name = "Locale", Options = { "en", "es" }, Default = "en", Save = false, Callback = function(l) Mova:SetLocale(l) end })

	T:CreateDivider("Icons")
	T:CreateParagraph({ Title = "Every Icon option accepts", Content = "Lucide names (\"house\", \"lucide:sword\"), built-in names (\"settings\", \"search\", \"check\"), asset ids (4483362458) or \"rbxassetid://…\" strings, spritesheet cells and anything your SetIconResolver returns." })
	local icons = T:CreateRow({ Columns = 3 })
	icons:CreateLabel({ Name = "house", Icon = "house" })
	icons:CreateLabel({ Name = "sword", Icon = "sword" })
	icons:CreateLabel({ Name = "settings", Icon = "settings" })
	icons:CreateLabel({ Name = "zap", Icon = "zap" })
	icons:CreateLabel({ Name = "asset id", Icon = 4483362458 })
	icons:CreateLabel({ Name = "unknown → none", Icon = "definitely-not-an-icon" })

	T:CreateDivider("Search")
	T:CreateParagraph({ Title = "Search every tab", Content = "Click the magnifier in the top bar and type part of any element's name — results from all tabs collect on one page and go back when you clear the box." })

	T:CreateDivider("Unload")
	T:CreateButton({ Name = "Destroy everything", Description = "Mova:Destroy() removes the GUI and disconnects every connection.", Callback = function() Mova:Destroy() end })
end

---------------------------------------------------------------------------------------------------
-- 8. Stress — lots of elements, bulk operations
---------------------------------------------------------------------------------------------------
do
	local T = Tabs.Stress
	local made = {}

	T:CreateParagraph({ Title = "Volume", Content = "Thirty toggles and ten sliders follow, to check scrolling, the bottom fade, search speed and config size." })
	T:CreateButton({ Name = "Flip every stress toggle", Callback = function()
		local t0 = os.clock()
		for _, el in ipairs(made) do if el.Type == "Toggle" then el:Set(not el.Value, true) end end
		log(string.format("flipped %d toggles in %.1f ms", #made, (os.clock() - t0) * 1000))
	end })
	T:CreateButton({ Name = "Randomise every stress slider", Callback = function()
		for _, el in ipairs(made) do if el.Type == "Slider" then el:Set(math.random(0, 100), true) end end
	end })
	T:CreateButton({ Name = "Dump Mova.Flags to the console", Callback = function()
		local n = 0
		for k, v in pairs(Mova.Flags) do n = n + 1 print("  " .. tostring(k) .. " = " .. tostring(v)) end
		log(n .. " flags")
	end })

	T:CreateDivider("Toggles")
	for i = 1, 30 do
		made[#made + 1] = T:CreateToggle({ Name = "Stress toggle " .. i, Flag = "Stress_T" .. i, Default = i % 3 == 0 })
	end
	T:CreateDivider("Sliders")
	for i = 1, 10 do
		made[#made + 1] = T:CreateSlider({ Name = "Stress slider " .. i, Flag = "Stress_S" .. i, Range = { 0, 100 }, Default = i * 10 })
	end
end

---------------------------------------------------------------------------------------------------
-- 9. Done
---------------------------------------------------------------------------------------------------

Window:SelectTab(Tabs.Elements)
Mova:Notify({
	Title = "Mova test ready",
	Content = "RightShift toggles the window. Callbacks print to the console with a [Mova test] prefix.",
	Type = "Success", Icon = "flask-conical", Duration = 5,
})
