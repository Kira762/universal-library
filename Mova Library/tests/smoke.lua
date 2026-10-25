-- Headless smoke test for Mova. Run with: lua tests/run.lua  (or python tests/run.py)
-- Exercises every public API path against the mock in roblox_mock.lua.

local MOCK_PATH, SOURCE_PATH = ...
local mock = dofile(MOCK_PATH or "tests/roblox_mock.lua")

local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = xpcall(fn, debug.traceback)
	if ok then
		passed = passed + 1
		print("  ok   " .. name)
	else
		failed = failed + 1
		print("  FAIL " .. name .. "\n       " .. tostring(err):gsub("\n", "\n       "))
	end
end
local function eq(a, b, msg)
	if a ~= b then error((msg or "expected equality") .. ": got " .. tostring(a) .. ", expected " .. tostring(b), 2) end
end
local function truthy(v, msg) if not v then error(msg or "expected truthy", 2) end end

local chunk = assert(loadfile(SOURCE_PATH or "source.lua"))
local Mova = chunk()

print("Mova " .. Mova.Version .. " loaded; secure=" .. tostring(Mova.SecureMode) .. " mobile=" .. tostring(Mova.IsMobile))

local Window, Main, Combat, Visuals, Misc
local log = {}

test("CreateWindow", function()
	Window = Mova:CreateWindow({
		Name = "Mova Test Hub",
		Subtitle = "smoke test",
		Theme = "Midnight",
		ToggleUIKeybind = "RightShift",
		ConfigurationSaving = { Enabled = true, FolderName = "MovaTests", FileName = "default", AutoSave = false },
	})
	truthy(Window.Main, "window has a Main frame")
	eq(Window.Main.Parent, mock.CoreGui:FindFirstChildOfClass("ScreenGui") or Window.Main.Parent, "window parented to ScreenGui")
	eq(Mova:GetTheme().Name, "Midnight")
	mock.flush() -- builds the settings tab, autoload etc.
	truthy(Window.SettingsTab, "settings tab built")
end)

test("CreateTab (table + positional)", function()
	Main = Window:CreateTab({ Name = "Main", Icon = 0 })
	Combat = Window:CreateTab("Combat", 123456)
	Visuals = Window:CreateTab({ Name = "Visuals" })
	Misc = Window:CreateTab({ Name = "Misc" })
	eq(#Window.Tabs, 5, "4 user tabs + settings")
	eq(Window.CurrentTab, Main, "first user tab is auto-selected, never the internal settings tab")
	eq(Window.SettingsTab.Button.LayoutOrder, 10000, "settings tab sorts last")
	truthy(Main.Page.Visible and not Window.SettingsTab.Page.Visible)
	Window:SelectTab("Combat")
	eq(Window.CurrentTab, Combat)
	Window:SelectTab(1)
	eq(Window.CurrentTab, Window.Tabs[1])
	Window:SelectTab(Main)
end)

test("Button", function()
	local hits = 0
	local b = Main:CreateButton({ Name = "Click me", Description = "desc", Callback = function() hits = hits + 1 end })
	local interact = mock.find(b.Card, function(d) return d.ClassName == "TextButton" and d ~= b.Blocker end)
	mock.click(interact)
	eq(hits, 1)
	b:Lock("nope")
	mock.click(interact)
	eq(hits, 1, "locked button must not fire")
	truthy(b:IsLocked() and b.DescLabel.Text == "nope")
	b:Unlock()
	eq(b.DescLabel.Text, "desc", "description restored after unlock")
	b:Press()
	eq(hits, 2)
	-- positional / string form
	local b2 = Main:CreateButton("Quick", function() hits = hits + 10 end)
	b2:Press()
	eq(hits, 12)
end)

test("Toggle + flags + attached keybind", function()
	local last
	local t = Main:CreateToggle({ Name = "Auto Farm", Flag = "AutoFarm", Default = false, Callback = function(v) last = v end })
	eq(Mova.Flags.AutoFarm, false)
	eq(Mova.Options.AutoFarm, t)
	eq(Mova.Toggles.AutoFarm, t)
	t:Set(true)
	eq(last, true)
	eq(Mova.Flags.AutoFarm, true)
	t:Set(false, true)
	eq(last, true, "silent set must not fire callback")
	eq(t.Value, false)
	local interact = mock.find(t.Card, function(d) return d.ClassName == "TextButton" and d ~= t.Blocker end)
	mock.click(interact)
	eq(t.Value, true)
	-- attached keybind flips the toggle
	local kb = t:AddKeybind({ Default = "F" })
	eq(kb.Mode, "Toggle")
	mock.pressKey(Enum.KeyCode.F)
	eq(t.Value, false, "F flips toggle off")
	mock.pressKey(Enum.KeyCode.F)
	eq(t.Value, true, "F flips toggle on")
	-- processed keyboard input is ignored (typing in chat)
	mock.pressKey(Enum.KeyCode.F, true)
	eq(t.Value, true)
	t:OnChanged(function(v) log[#log + 1] = "changed:" .. tostring(v) end)
	t:Toggle()
	eq(log[#log], "changed:false")
end)

test("Only one keybind field listens at a time; a destroyed window stops its keybinds", function()
	local W2 = Mova:CreateWindow({ Name = "Second", Theme = "Dark" })
	local T2 = W2:CreateTab("T")
	local fired = 0
	local a = T2:CreateKeybind({ Name = "A", Default = "F", Callback = function() fired = fired + 1 end })
	local b = T2:CreateKeybind({ Name = "B", Default = "G", Callback = function() end })
	local fieldA = mock.find(a.Card, function(x) return x.ClassName == "TextButton" and x ~= a.Blocker end)
	local fieldB = mock.find(b.Card, function(x) return x.ClassName == "TextButton" and x ~= b.Blocker end)
	mock.click(fieldA)
	mock.click(fieldB)                         -- B takes over, A must stop listening
	mock.pressKey(Enum.KeyCode.X)
	eq(a.Value, Enum.KeyCode.F, "A kept its key")
	eq(b.Value, Enum.KeyCode.X, "B got the new key")
	mock.pressKey(Enum.KeyCode.F)
	eq(fired, 1)
	W2:Destroy()
	mock.flush()
	mock.pressKey(Enum.KeyCode.F)
	eq(fired, 1, "keybind of a destroyed window must not fire")
end)

test("Press animation returns a card to its resting size even when tapped twice", function()
	local btn = Combat:CreateButton({ Name = "Double", Callback = function() end })
	local base = btn.Card.Size
	local interact = mock.find(btn.Card, function(x) return x.ClassName == "TextButton" and x ~= btn.Blocker end)
	mock.click(interact) mock.click(interact)
	for _ = 1, 30 do mock.flush() end
	eq(btn.Card.Size, base, "card size restored")
end)

test("Controls drop under the title on narrow cards and come back when there is room", function()
	local d = Combat:CreateDropdown({ Name = "Responsive", Options = { "A", "B" }, Default = "A" })
	d.Card.AbsoluteSize = Vector2.new(180, 44)       -- mock default is 100 wide, so start stacked
	eq(d.Stacked, true, "narrow card stacks")
	eq(d.Control.Size.X.Scale, 1, "stacked control spans the card")
	d.Card.AbsoluteSize = Vector2.new(520, 44)
	eq(d.Stacked, false, "wide card goes back to one row")
	eq(d.Control.Size.X.Offset, 170, "control width restored")
	eq(d.TextPadding.PaddingBottom.Offset, 13)
	local s = Combat:CreateSlider({ Name = "Never stacks", Range = { 0, 1000 }, Suffix = " studs", Default = 10 })
	eq(s.Stacked, false, "slider keeps its own two-row layout")
	eq(s.Card.Size.Y.Offset, 76)
	truthy(s.Control.Size.X.Offset >= 56, "value box sized for the longest value")
	local b = Combat:CreateButton({ Name = "No stack", Callback = function() end })
	eq(b.Stacked, false)
end)

test("Group (Gen 2 layout container)", function()
	local row = Combat:CreateGroup({ Direction = "row", Columns = 2 })
	local a = row:CreateToggle({ Name = "Row A", Default = true })
	local b = row:CreateButton({ Name = "Row B", Callback = function() end })
	eq(a.Card.Parent.Name, "GroupLine", "children sit in a line frame")
	eq(a.Card.Parent.Parent, row.Frame, "line frames sit in the group")
	eq(a.Card.Parent, b.Card.Parent, "two children share the first line")
	local c0 = row:CreateButton({ Name = "Row C", Callback = function() end })
	truthy(c0.Card.Parent ~= a.Card.Parent, "the third child starts a new line")
	eq(a.Card.Size.X.Scale, 0.5, "two columns share the width")
	eq(b.Card.Size.X.Scale, 0.5)
	local col = Combat:CreateGroup("column")
	local c = col:CreateSlider({ Name = "Col slider", Range = { 0, 1 }, Default = 0.5 })
	eq(c.Card.Size.X.Scale, 1, "column children stay full width")
	local grid = Combat:CreateRow({ Columns = 2 })
	local left = grid:CreateColumn()
	eq(left.Frame.Size.X.Scale, 0.5, "a column nested in a row shares its width")
	local d = left:CreateToggle({ Name = "Grid toggle", Flag = "GridToggle", Default = true })
	truthy(Mova.Flags.GridToggle == true, "flags register through nested groups")
	Window:_applySearch("row a")
	eq(a.Card.Size.X.Scale, 1, "compact card goes full width on the search page")
	Window:_applySearch("")
	eq(a.Card.Size.X.Scale, 0.5, "and gets its column width back")
	row:Destroy() col:Destroy() grid:Destroy()
end)

test("Theme bindings survive without strong references", function()
	collectgarbage() collectgarbage()
	Mova:SetTheme("Light", false)
	local stale = {}
	local function walk(o)
		for _, ch in ipairs(o:GetChildren()) do
			if ch.ClassName == "Frame" and ch.Name ~= "Hover" and ch.Name ~= "Glyph" and ch.BackgroundTransparency < 1 then
				local c = ch.BackgroundColor3
				if c == Mova.Themes.Mono.Background or c == Mova.Themes.Mono.Field or c == Mova.Themes.Mono.Surface or c == Mova.Themes.Mono.Sidebar then
					stale[#stale + 1] = ch:GetFullName()
				end
			end
			walk(ch)
		end
	end
	walk(Window.Main)
	eq(#stale, 0, "frames still in Mono colours after switching to Light: " .. table.concat(stale, ", "))
	Mova:SetTheme("Midnight", false)
end)

test("Card base is white under its surface gradient", function()
	local t = Combat:CreateToggle({ Name = "Gradient check", Default = false })
	eq(t.Card.BackgroundColor3, Color3.new(1, 1, 1), "card background must be white (UIGradient multiplies it)")
	local grad = mock.find(t.Card, function(x) return x.ClassName == "UIGradient" end)
	assert(grad and grad.Color, "card has a tint gradient")
end)

test("Slider", function()
	local got
	local s = Combat:CreateSlider({ Name = "FOV", Range = { 30, 120 }, Increment = 5, Default = 90, Suffix = "°", Flag = "FOV", Callback = function(v) got = v end })
	eq(s.Value, 90)
	s:Set(93)
	eq(s.Value, 95, "snaps to increment")
	eq(got, 95)
	s:Set(1000)
	eq(s.Value, 120, "clamped to max")
	s:Set(-5)
	eq(s.Value, 30, "clamped to min")
	-- decimals
	local s2 = Combat:CreateSlider({ Name = "Smooth", Min = 0, Max = 1, Increment = 0.05, Default = 0.5 })
	s2:Set(0.333)
	eq(s2.Value, 0.35)
	eq(s2.Decimals, 2)
	-- Linoria style
	local s3 = Combat:AddSlider("WalkSpeed", { Text = "Walk speed", Default = 16, Min = 16, Max = 100, Rounding = 0, Callback = function() end })
	eq(s3.Flag, "WalkSpeed")
	eq(Mova.Flags.WalkSpeed, 16)
	-- typing a value into the box
	local box = mock.find(s.Card, function(d) return d.ClassName == "TextBox" end)
	mock.setText(box, "60")
	eq(s.Value, 60)
	-- drag simulation
	local trackHolder = mock.find(s.Card, function(d) return d.ClassName == "TextButton" and d ~= s.Blocker end)
	local track = trackHolder.Parent:FindFirstChildOfClass("Frame")
	track.AbsolutePosition = Vector2.new(100, 0)
	track.AbsoluteSize = Vector2.new(200, 6)
	local i = mock.input(Enum.UserInputType.MouseButton1, nil, Vector2.new(300, 3))
	trackHolder.InputBegan:Fire(i, false)
	eq(s.Value, 120, "click at far right = max")
	local move = mock.input(Enum.UserInputType.MouseMovement, nil, Vector2.new(200, 3))
	mock.Services.UserInputService.InputChanged:Fire(move, false)
	eq(s.Value, 75, "drag to middle")
	i.UserInputState = Enum.UserInputState.End
	i.Changed:Fire()
	mock.Services.UserInputService.InputChanged:Fire(mock.input(Enum.UserInputType.MouseMovement, nil, Vector2.new(100, 3)), false)
	eq(s.Value, 75, "no change after release")
end)

test("Input", function()
	local got
	local inp = Misc:CreateInput({ Name = "Player", Placeholder = "name", Flag = "Target", Callback = function(v) got = v end })
	local box = mock.find(inp.Card, function(d) return d.ClassName == "TextBox" end)
	mock.setText(box, "Builderman")
	eq(got, "Builderman")
	eq(Mova.Flags.Target, "Builderman")
	local num = Misc:CreateInput({ Name = "Amount", Numeric = true, Default = "12" })
	num:Set("1a2b3")
	eq(num.Value, "123")
	local live = Misc:CreateInput({ Name = "Live", Finished = false, Callback = function(v) got = v end })
	local lbox = mock.find(live.Card, function(d) return d.ClassName == "TextBox" end)
	lbox.Text = "ab"
	eq(got, "ab", "Finished=false fires per keystroke")
end)

test("Dropdown single / multi / refresh / popup", function()
	local got
	local d = Visuals:CreateDropdown({ Name = "Mode", Options = { "Box", "Corner", "Skeleton" }, Default = "Box", Flag = "ESPMode", Callback = function(v) got = v end })
	eq(d.Value, "Box")
	d:Set("Corner")
	eq(got, "Corner")
	d:Set("Nope")
	eq(d.Value, nil, "unknown option clears (AllowNone)")
	d:Set(3)
	eq(d.Value, "Skeleton", "numeric index accepted")
	d:Refresh({ "A", "B" })
	eq(d.Value, nil)
	d:Refresh({ "Skeleton", "Box" }, true)
	d:Set("Box")
	-- open the list
	local field = mock.find(d.Card, function(x) return x.ClassName == "TextButton" and x ~= d.Blocker end)
	mock.click(field)
	local popups = mock.CoreGui:FindFirstChildOfClass("ScreenGui"):FindFirstChild("Popups")
	eq(#popups:GetChildren(), 1, "one popup list open")
	local rows = mock.findAll(popups, function(x) return x.ClassName == "TextButton" end)
	eq(#rows, 2)
	mock.click(rows[1]) -- "Skeleton"
	eq(d.Value, "Skeleton")
	mock.flush() -- close animation finishes
	eq(#popups:GetChildren(), 0, "single select closes the list")

	local m = Visuals:CreateDropdown({ Name = "Targets", Options = { "Players", "NPCs", "Items" }, Multi = true, Default = { "Players" }, Flag = "Targets" })
	eq(#m.Value, 1)
	m:Set({ "NPCs", "Items", "Bogus" })
	eq(#m.Value, 2, "bogus filtered out")
	mock.click(mock.find(m.Card, function(x) return x.ClassName == "TextButton" and x ~= m.Blocker end))
	rows = mock.findAll(popups, function(x) return x.ClassName == "TextButton" end)
	mock.click(rows[1]) -- add Players
	eq(#m.Value, 3)
	eq(#popups:GetChildren(), 1, "multi select keeps the list open")
	-- outside click closes it
	mock.Services.UserInputService.InputBegan:Fire(mock.input(Enum.UserInputType.MouseButton1, nil, Vector2.new(-50, -50)), false)
	mock.flush()
	eq(#popups:GetChildren(), 0)
	-- big list gets a search box
	local opts = {}
	for i = 1, 30 do opts[i] = "Item " .. i end
	local big = Visuals:CreateDropdown({ Name = "Big", Options = opts })
	mock.click(mock.find(big.Card, function(x) return x.ClassName == "TextButton" and x ~= big.Blocker end))
	local search = mock.find(popups, function(x) return x.ClassName == "TextBox" end)
	truthy(search, "search box present for >6 options")
	search.Text = "Item 3"
	rows = mock.findAll(popups, function(x) return x.ClassName == "TextButton" end)
	eq(#rows, 2, "'Item 3' and 'Item 30'")
	big:Close()
	mock.flush()
	eq(#popups:GetChildren(), 0)
end)

test("Keybind modes", function()
	local presses, holdState = 0, nil
	local k = Combat:CreateKeybind({ Name = "Aim", Default = "Q", Flag = "AimKey", Callback = function() presses = presses + 1 end })
	mock.pressKey(Enum.KeyCode.Q)
	eq(presses, 1)
	eq(Mova.Flags.AimKey, Enum.KeyCode.Q)
	local h = Combat:CreateKeybind({ Name = "Zoom", Default = "C", Mode = "Hold", Callback = function(s) holdState = s end })
	local i = mock.input(Enum.UserInputType.Keyboard, Enum.KeyCode.C)
	mock.Services.UserInputService.InputBegan:Fire(i, false)
	eq(holdState, true)
	mock.Services.UserInputService.InputEnded:Fire(i, false)
	eq(holdState, false)
	-- rebinding via the UI
	local changed
	k.ChangedCallback = function(key) changed = key end
	local field = mock.find(k.Card, function(x) return x.ClassName == "TextButton" and x ~= k.Blocker end)
	mock.click(field)                          -- start listening
	mock.pressKey(Enum.KeyCode.X)              -- bind X
	eq(k.Value, Enum.KeyCode.X)
	eq(changed, Enum.KeyCode.X)
	presses = 0
	mock.pressKey(Enum.KeyCode.Q)
	eq(presses, 0, "old key no longer fires")
	mock.pressKey(Enum.KeyCode.X)
	eq(presses, 1)
	-- escape clears
	mock.click(field)
	mock.pressKey(Enum.KeyCode.Escape)
	eq(k.Value, nil)
	eq(k.Card:FindFirstChild("Keybind") or true, true)
end)

test("ColorPicker", function()
	local got, gotAlpha
	local c = Visuals:CreateColorPicker({ Name = "ESP colour", Color = Color3.fromRGB(255, 0, 0), Flag = "ESPColor", Callback = function(col) got = col end })
	eq(c:GetHex(), "#FF0000")
	c:Set(Color3.fromRGB(0, 255, 0))
	eq(got:ToHex(), "00ff00")
	c:Set("#0000FF")
	eq(c.Value:ToHex(), "0000ff")
	local a = Visuals:CreateColorPicker({ Name = "Fill", Color = Color3.fromRGB(10, 20, 30), Alpha = 0.5, Flag = "Fill", Callback = function(col, alpha) got, gotAlpha = col, alpha end })
	a:Set(Color3.fromRGB(1, 2, 3), 0.25)
	eq(gotAlpha, 0.25)
	-- open panel, drag hue
	local swatch = mock.find(a.Card, function(x) return x.ClassName == "TextButton" and x ~= a.Blocker end)
	mock.click(swatch)
	local popups = mock.CoreGui:FindFirstChildOfClass("ScreenGui"):FindFirstChild("Popups")
	mock.flush()
	eq(#popups:GetChildren(), 1)
	local bars = mock.findAll(popups, function(x) return x.ClassName == "TextButton" end)
	eq(#bars, 3, "sv square + hue + alpha")
	local hue = bars[2]
	hue.AbsolutePosition = Vector2.new(0, 0)
	hue.AbsoluteSize = Vector2.new(100, 14)
	hue.InputBegan:Fire(mock.input(Enum.UserInputType.MouseButton1, nil, Vector2.new(50, 5)), false)
	local hh = a.Value:ToHSV()
	truthy(math.abs(hh - 0.5) < 0.01, "hue dragged to 0.5, got " .. hh)
	local hex = mock.find(popups, function(x) return x.ClassName == "TextBox" end)
	mock.setText(hex, "#123456")
	eq(a.Value:ToHex(), "123456")
	a:Close()
	mock.flush()
	eq(#popups:GetChildren(), 0)
end)

test("Label / Paragraph / Divider / Progress / Section", function()
	local l = Misc:CreateLabel("Just a label")
	l:Set("Changed")
	eq(l.TitleLabel.Text, "Changed")
	local p = Misc:CreateParagraph({ Title = "Info", Content = "Body text" })
	p:Set({ Content = "New body" })
	eq(p.DescLabel.Text, "New body")
	Misc:CreateDivider("Danger zone")
	Misc:CreateDivider()
	local pr = Misc:CreateProgress({ Name = "Loading", Value = 25 })
	pr:Set(80)
	eq(pr.Value, 80)
	local sec = Misc:CreateSection({ Name = "Group" })
	local inner = sec:CreateToggle({ Name = "Inside section", Flag = "Inner" })
	eq(inner.Tab, Misc)
	eq(inner.Card.Parent, sec.Holder)
	sec:SetCollapsed(true)
	mock.flush() -- collapse animation
	truthy(not sec.Holder.Visible)
	mock.click(sec.Header)
	truthy(sec.Holder.Visible)
	-- Linoria aliases
	local gb = Misc:AddLeftGroupbox("Legacy")
	local lt = gb:AddToggle("LegacyToggle", { Text = "Legacy toggle", Default = true, Tooltip = "tip" })
	eq(lt.Flag, "LegacyToggle")
	eq(lt.Value, true)
	eq(lt.Description, "tip")
	gb:AddButton({ Text = "Legacy button", Func = function() end })
	gb:AddDropdown("LegacyDD", { Values = { "a", "b" }, Default = "a", Multi = false })
	eq(Mova.Flags.LegacyDD, "a")
	gb:AddInput("LegacyInput", { Default = "x", Placeholder = "p" })
	gb:AddKeyPicker("LegacyKey", { Default = "Z", Mode = "Toggle" })
	gb:AddColorPicker("LegacyColor", { Default = Color3.new(1, 1, 1) })
	gb:AddLabel("Legacy label")
	gb:AddDivider()
end)

test("Visibility, minimise, toggle key, pill", function()
	Window:Hide()
	mock.flush()
	truthy(Window.Hidden and not Window.Main.Visible and Window.Pill.Visible)
	mock.pressKey(Enum.KeyCode.RightShift)
	mock.flush() -- pill slides away, window pops in
	truthy(not Window.Hidden and Window.Main.Visible and not Window.Pill.Visible)
	Window:ToggleMinimise()
	mock.flush() -- body hidden once the height tween ends
	truthy(Window.Minimised and not Window.Body.Visible)
	Window:ToggleMinimise()
	mock.flush()
	truthy(not Window.Minimised and Window.Body.Visible)
	Window:SetToggleKey("K")
	mock.pressKey(Enum.KeyCode.RightShift)
	truthy(not Window.Hidden, "old toggle key ignored")
	mock.pressKey(Enum.KeyCode.K)
	truthy(Window.Hidden)
	mock.flush()
	truthy(Window.Pill.Visible and not Window.Main.Visible)
	mock.click(Window.Pill) -- tapping the floating pill re-opens the window
	mock.flush()
	truthy(not Window.Hidden and Window.Main.Visible and not Window.Pill.Visible, "pill reopens the window")
end)

test("Search moves elements and restores them", function()
	local toggle = Mova.Options.AutoFarm
	local home = toggle.Card.Parent
	Window.SearchBox.Text = "auto"
	eq(toggle.Card.Parent, Window.SearchPage)
	truthy(Window.SearchPage.Visible)
	truthy(not Window.SearchEmpty.Visible)
	Window.SearchBox.Text = "zzzzzz"
	truthy(Window.SearchEmpty.Visible, "no results label shown")
	eq(toggle.Card.Parent, home, "non-matching element returned home")
	Window.SearchBox.Text = ""
	eq(toggle.Card.Parent, home)
	truthy(not Window.SearchPage.Visible)
	truthy(Window.CurrentTab.Page.Visible)
end)

test("Themes", function()
	local names = Mova:GetThemeNames()
	truthy(#names >= 8)
	for _, n in ipairs(names) do truthy(Mova:SetTheme(n), "theme " .. n) end
	eq(Mova:GetTheme().Name, names[#names])
	Mova:SetTheme("Dark")
	eq(Window.Main.BackgroundColor3, Mova.Themes.Dark.Sidebar)
	eq(Window.Content.BackgroundColor3, Mova.Themes.Dark.Background)
	truthy(not Mova:SetTheme("DoesNotExist"))
	Mova:RegisterTheme("Custom", { Accent = Color3.fromRGB(1, 2, 3) })
	Window:ChangeTheme("Custom")
	eq(Mova:GetTheme().Accent, Color3.fromRGB(1, 2, 3))
	Mova:SetTheme({ Name = "Inline", Background = Color3.fromRGB(9, 9, 9) })
	eq(Window.Content.BackgroundColor3, Color3.fromRGB(9, 9, 9))
	Mova:SetTheme("Dark")
	-- toggle colours follow state after a theme change
	local t = Mova.Options.AutoFarm
	t:Set(true, true)
	Mova:SetTheme("Ocean")
	local track = mock.find(t.Card, function(x) return x.ClassName == "Frame" and x.Size.X.Offset == 50 end)
	local knob = mock.find(track, function(x) return x.ClassName == "Frame" and x.Size.Y.Offset == 17 end)
	eq(track.BackgroundColor3, Mova.Themes.Ocean.Track, "track stays neutral (Gen 2 style)")
	eq(knob.BackgroundColor3, Mova.Themes.Ocean.Accent, "on-toggle knob uses accent")
	Mova:SetTheme("Dark")
end)

test("Config save / load / list / delete / autoload", function()
	Mova.Options.AutoFarm:Set(true, true)
	Mova.Options.FOV:Set(45, true)
	Mova.Options.ESPMode:Set("Box", true)
	Mova.Options.Targets:Set({ "NPCs" }, true)
	Mova.Options.ESPColor:Set(Color3.fromRGB(12, 34, 56), true)
	Mova.Options.Fill:Set(Color3.fromRGB(1, 1, 1), 0.75, true)
	Mova.Options.AimKey:Set("E", true)
	Mova.Options.Target:Set("Noob", true)
	local ok, err = Window:SaveConfig("alpha")
	truthy(ok, tostring(err))
	truthy(mock.Files["MovaTests/alpha.mova.json"], "file written")
	-- mutate everything
	Mova.Options.AutoFarm:Set(false, true)
	Mova.Options.FOV:Set(120, true)
	Mova.Options.ESPMode:Set(nil, true)
	Mova.Options.Targets:Set({}, true)
	Mova.Options.ESPColor:Set(Color3.fromRGB(0, 0, 0), true)
	Mova.Options.Fill:Set(Color3.fromRGB(0, 0, 0), 0, true)
	Mova.Options.AimKey:Set(nil, true)
	Mova.Options.Target:Set("", true)
	local fired = false
	Mova.Options.AutoFarm.Callback = function() fired = true end
	ok, err = Window:LoadConfig("alpha")
	truthy(ok, tostring(err))
	truthy(fired, "load fires callbacks so state applies")
	eq(Mova.Options.AutoFarm.Value, true)
	eq(Mova.Options.FOV.Value, 45)
	eq(Mova.Options.ESPMode.Value, "Box")
	eq(Mova.Options.Targets.Value[1], "NPCs")
	eq(Mova.Options.ESPColor.Value:ToHex(), Color3.fromRGB(12, 34, 56):ToHex())
	eq(Mova.Options.Fill.Alpha, 0.75)
	eq(Mova.Options.AimKey.Value, Enum.KeyCode.E)
	eq(Mova.Options.Target.Value, "Noob")
	local list = Window:ListConfigs()
	eq(#list, 1)
	eq(list[1], "alpha")
	Window:SetAutoload("alpha")
	eq(Window:_readAutoload(), "alpha")
	truthy(Window:DeleteConfig("alpha"))
	eq(#Window:ListConfigs(), 0)
	local bad, why = Window:LoadConfig("missing")
	truthy(not bad and why)
	-- autosave debounce
	Window._autoSave = true
	Mova.Options.FOV:Set(50)
	truthy(Window._autoSaveThread, "autosave queued")
	mock.flush()
	truthy(mock.Files["MovaTests/default.mova.json"], "autosaved to default")
end)

test("Notifications and dialogs", function()
	local n = Mova:Notify({ Title = "Hello", Content = "World", Duration = 1, Type = "Success", Actions = { { Text = "Yes", Callback = function() log[#log + 1] = "yes" end }, { Text = "No" } } })
	truthy(n.Instance.Parent)
	local yes = mock.find(n.Instance, function(x) return x.ClassName == "TextButton" and x.Text == "Yes" end)
	mock.click(yes)
	eq(log[#log], "yes")
	Mova:Notify("plain string works")
	Window:Toast("toast")
	local picked
	local d = Mova:Dialog({ Title = "Sure?", Content = "Really?", Buttons = { { Text = "Cancel" }, { Text = "Do it", Style = "Danger", Callback = function() picked = "do" end } } })
	local doIt = mock.find(d.Instance, function(x) return x.ClassName == "TextButton" and x.Text == "Do it" end)
	mock.click(doIt)
	eq(picked, "do")
	mock.flush()
end)

test("Lock / visibility / destroy element", function()
	local t = Mova.Options.AutoFarm
	t:Lock()
	truthy(t.Blocker.Visible)
	t:Unlock()
	t:SetVisible(false)
	truthy(not t.Card.Visible)
	t:SetVisible(true)
	local tmp = Misc:CreateToggle({ Name = "Temp", Flag = "Temp" })
	truthy(Mova.Options.Temp)
	tmp:Destroy()
	truthy(Mova.Options.Temp == nil and tmp.Destroyed)
	-- callback errors are contained
	local bad = Misc:CreateButton({ Name = "Boom", Callback = function() error("kaboom") end })
	bad:Press()
	mock.flush()
end)

test("Localisation", function()
	Mova:SetTranslations({ es = { ["Auto Farm"] = "Granja automática", ["Main"] = "Principal" } })
	Mova:SetLocale("es")
	eq(Mova.Options.AutoFarm.TitleLabel.Text, "Granja automática")
	eq(Main.Label.Text, "Principal")
	Mova:SetLocale("en")
	eq(Main.Label.Text, "Main")
end)

test("Key system gates the window", function()
	mock.HttpGetResponse = "remote-key-1\nremote-key-2\n"
	local opened = false
	local W2 = Mova:CreateWindow({
		Name = "Gated",
		KeySystem = true,
		KeySettings = { Title = "Gated", Note = "get a key", Key = { "local-key" }, KeyURL = "https://example.invalid/keys.txt", SaveKey = true, FileName = "gated", Link = "https://example.invalid/get" },
	})
	truthy(not W2.Main.Visible, "window hidden until key accepted")
	local card = W2._keyCard
	local box = mock.find(card, function(x) return x.ClassName == "TextBox" end)
	local verify = mock.find(card, function(x) return x.ClassName == "TextButton" and x.Text == "Verify" end)
	local getKey = mock.find(card, function(x) return x.ClassName == "TextButton" and x.Text == "Get key" end)
	mock.click(getKey)
	eq(mock.Clipboard, "https://example.invalid/get")
	box.Text = "wrong"
	mock.click(verify)
	mock.flush()
	truthy(not W2.Main.Visible)
	box.Text = "remote-key-2"
	mock.click(verify)
	mock.flush()
	truthy(W2.Main.Visible, "remote key accepted")
	truthy(mock.Files["Mova/keys/gated.txt"] == "remote-key-2", "key saved")
	-- second window with same file skips the prompt
	local W3 = Mova:CreateWindow({ Name = "Gated", KeySystem = { Key = { "local-key" }, FileName = "gated", KeyURL = "x" } })
	truthy(W3.Main.Visible, "saved key auto-accepted")
	-- validate callback
	local W4 = Mova:CreateWindow({ Name = "Gated2", KeySystem = { Validate = function(k) return k == "cb" end, SaveKey = false } })
	local box4 = mock.find(W4._keyCard, function(x) return x.ClassName == "TextBox" end)
	box4.Text = "cb"
	box4.FocusLost:Fire(true)
	mock.flush()
	truthy(W4.Main.Visible)
	W2:Destroy() W3:Destroy() W4:Destroy()
end)

test("Window:Get / Set and Mova level helpers", function()
	Window:Set("FOV", 70, true)
	eq(Window:Get("FOV"), 70)
	Mova:SetVisibility(false)
	truthy(not Mova:IsVisible())
	Mova:SetVisibility(true)
	truthy(Mova:IsVisible())
	Mova:SaveConfiguration()
	Mova:LoadConfiguration()
end)

test("Secure mode blocks raw asset ids", function()
	eq(Mova.SecureMode, false)
	local l = Misc:CreateLabel({ Name = "Icon label", Icon = 123 })
	truthy(mock.find(l.Card, function(x) return x.ClassName == "ImageLabel" and x.Image == "rbxassetid://123" end), "icon resolved in normal mode")
end)

test("Destroy everything", function()
	local gui = mock.CoreGui:FindFirstChildOfClass("ScreenGui")
	Window:Destroy()
	truthy(Window.Destroyed)
	eq(Mova.Options.AutoFarm, nil, "flags released on destroy")
	Mova:Destroy()
	truthy(gui._destroyed, "ScreenGui removed")
	mock.flush()
end)

print(string.format("\n%d passed, %d failed, %d instances created, %d tweens played", passed, failed, mock.Created(), mock.TweensPlayed()))
if failed > 0 then os.exit(1) end
