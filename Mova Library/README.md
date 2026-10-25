# Mova Library

A modern, single-file, MIT-licensed UI library for Roblox scripts — designed after reading the source of every library vendored in this repository (Rayfield 2022 & Gen 2, Obsidian, LinoriaLib, WindUI, Fluent, Kavo, Luna/Starlight, Maclib, Mercury, Bracket, Aetheris, Velvet, OasisUI, Eazy UI) and keeping what each does best while fixing what they get wrong.

```lua
local Mova = loadstring(game:HttpGet("https://raw.githubusercontent.com/Kira762/universal-library/main/Mova%20Library/source.lua"))()

local Window = Mova:CreateWindow({ Name = "My Hub", Theme = "Midnight", ConfigurationSaving = { Enabled = true } })
local Tab = Window:CreateTab({ Name = "Main" })

Tab:CreateToggle({ Name = "Auto farm", Flag = "AutoFarm", Callback = function(on) print(on) end })
Tab:CreateSlider({ Name = "Speed", Range = { 16, 100 }, Default = 16, Flag = "Speed" })
```

| | |
| --- | --- |
| **File** | [`source.lua`](source.lua) — one file, no dependencies, ~3.4k lines |
| **Example** | [`example.lua`](example.lua) — every element and option |
| **Tests** | [`tests/`](tests/) — headless Roblox mock + smoke suite (`python3 tests/run.py --all`) |
| **License** | MIT |

---

## Why another library?

The research in [`docs/roblox-ui-libraries-research.md`](../docs/roblox-ui-libraries-research.md) found that every popular library forces a trade-off. Mova is the version that doesn't:

| Problem seen in the wild | Where | What Mova does instead |
| --- | --- | --- |
| Loads a marketplace model / asset ids on start, which is fingerprintable and breaks when the asset is moderated | Rayfield 2022, Kavo, Mercury | Drawn 100 % in code. The only images are the icons *you* pass in; secure mode even blocks raw asset ids. |
| Phones home (analytics / "prompt" endpoints / remote settings) | Rayfield 2022 & Gen 2 | **Zero network calls.** The only optional request is the key-system `KeyURL` you configure yourself. |
| Multi-file loaders that fetch 10–30 modules via `HttpGet` | WindUI, Gen 2, Obsidian, Fluent | A single `loadstring`. Nothing else is fetched. |
| Configs that only store flat values (Color3 / keybinds lost or stored lossy) | Rayfield 2022, Kavo, Orion | Typed JSON: `Color3`, `KeyCode`, `UserInputType`, arrays and colour + alpha round-trip exactly. Named configs, autoload and debounced autosave built in. |
| Two incompatible API families (Rayfield-style `CreateToggle{}` vs Linoria-style `AddToggle(flag,{})`) | everywhere | **Both.** `Tab:CreateToggle{}` and `Groupbox:AddToggle("Flag", {})` return the same handle, so Rayfield *and* Linoria/Obsidian scripts port in minutes. |
| Theme = rebuild the UI, or only part of it recolours | Kavo, Orion, Fluent | Registry-based live themes: every themed property is tracked and tweened when `Mova:SetTheme()` is called. 8 built-in themes, custom tables accepted. |
| Keybinds are "press only", toggles need a separate keybind element | Rayfield, Kavo, Orion | Keybind modes **Press / Toggle / Hold / Always**, plus `Toggle:AddKeybind()` (Linoria-style) that flips the toggle. |
| Callback errors kill the whole UI thread | most | Every callback runs through `xpcall` with a traceback, a warning and an optional on-screen error notification. |
| No way to find an option in a 60-toggle hub | all except Obsidian | Top-bar search across **all tabs** — matching cards are gathered into a results page and put back afterwards. |
| Mobile is an afterthought (no touch drag, UI off-screen, no way to reopen) | many | Touch drag & resize, viewport-aware sizing, floating "open" pill when hidden, larger hit areas on touch. |
| Elements can't be disabled/hidden/renamed after creation | Kavo, Orion, Rayfield 2022 | Every handle has `.Value`, `:Set(v, silent)`, `:Lock(reason)`, `:Unlock()`, `:SetVisible()`, `:SetTitle()`, `:SetDescription()`, `:OnChanged()`, `:Destroy()`. |
| Leaked connections after unload | several | All connections are tracked; `Mova:Destroy()` disconnects everything and removes the ScreenGui. |

Things borrowed deliberately (credit where due): the `New(class, props)` + theme-tag registry idea from WindUI's Creator, Obsidian's `SafeCallback` + keypicker modes, Rayfield's `Flag`/`ConfigurationSaving` shape and `Range/Increment` slider semantics, Linoria's global `Toggles`/`Options` tables, Gen 2's gradient-based HSV picker.

### Look & motion — and where each idea comes from

Every visual decision below was taken after reading the presentation code of the vendored libraries (`Rayfield Gen 2/`, `WindUI/`, `Fluent/`, `Aetheris/`, …). Nothing is loaded from the marketplace; glyphs (chevrons, ✕, −, search, check, resize grip) are drawn from rotated frames.

| What you see | Source of the idea |
| --- | --- |
| Real font weights (`Regular / Medium / SemiBold / Bold`) through `Font.new(family, weight)` instead of `Enum.Font` pairs; 14 px Medium titles, 12 px dim descriptions | WindUI `Creator.Font` + `FontWeight`, Gen 2 / Aetheris `Font.new(id, weight)` |
| Cards: surface + 1 px outline at 45 % transparency, hover = white wash (`BackgroundTransparency 0.95`) and the outline sharpens, 0.22 s Quint Out; press = card shrinks 8 px symmetrically and springs back with Exponential Out | Gen 2 `hover()` / `press()` (stroke + overlay tween, width bounce) |
| Toggle: 42×22 pill, knob squashes while travelling and lands with Back Out, accent glow (`UIShadow`) when on | WindUI/Fluent 0.25 s Quint toggles, Gen 2 `AccentGlow` + `UIShadow` |
| Slider: gradient fill, knob grows idle → hover → drag with a glow, value pill gets an accent outline while dragging | Gen 2 slider fill gradient + knob states |
| Dropdown / colour popups grow out of the field (0.3 s Exponential Out) and shrink back; chevron rotates with Back Out; selected rows show a drawn check | Fluent dropdown, Obsidian popup sizing |
| Sidebar: one accent indicator that glides to the selected tab (0.35 s Exponential InOut, stretches then settles) and tabs that slide in staggered during the intro | Fluent `SelectTab` selector spring, Gen 2 tab-selector stagger |
| Page switch: old page slides out, new page slides in from the direction of travel (0.4 s Exponential Out) | Fluent `SelectTab` container swap |
| Window intro: pops from 86 % with Exponential Out while a window-coloured veil lifts off the content; hide = veil + scale down; minimise = height tween 0.35 s Exponential InOut; drop shadow via `UIShadow` when the engine has it | Gen 2 `_firstShow` / `_fadeSurfaces` reveal (done without a `CanvasGroup`) |
| Notifications slide in from the right edge with a coloured type bar; dialogs dim the screen and the panel pops with Back Out | Gen 2 notification stack, Aetheris Back Out pops |
| Key-system card shakes the field on a wrong key | common pattern (WindUI / Starlight key UIs) |

All timings live in one `Motion` table (`fast 0.12`, `base 0.22`, `slow 0.4`, Quint / Exponential / Back) so the whole library feels consistent.

---

## Quick test

`test.lua` is a small script with **no library code inside it** — it loads `source.lua` from the branch URL (falls back to `main`, then to a local `readfile("mova.lua")`), builds one window that exercises every element, and never has to change when the library does. Run it from your executor to check the latest push:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Kira762/universal-library/arena/98807242-universal-library/Mova%20Library/test.lua"))()
```

While the repository is private, save `source.lua` as `mova.lua` in the executor workspace and paste `test.lua` directly.

---

## Feature overview

- **Window**: title/subtitle/icon, sidebar tabs with icons, player chip, top-bar search, minimise, hide (keybind or pill), resizable on desktop, draggable (mouse + touch), kept on screen.
- **Elements**: Button, Toggle (+ attached keybind), Slider, Input (numeric / live / on-enter), Dropdown (single, multi, type-to-filter, `Refresh`), Keybind (4 modes), ColorPicker (HSV square, hue, optional alpha, hex + RGB boxes), Label (with icon), Paragraph, Divider, Section (collapsible) / Groupbox.
- **Overlays**: Notifications (4 types, progress bar, action buttons), Dialogs (Primary/Neutral/Danger buttons, optional `Dismissable = true` to close on tap-outside), popups close on outside click and stay inside the viewport.
- **Themes**: Mono (default, monochrome), Dark, Light, Midnight, Ocean, Ember, Amethyst, Rose, Mocha; `Mova:RegisterTheme(name, table)`; partial tables fall back to Dark.
- **Configs**: `Window:SaveConfig / LoadConfig / ListConfigs / DeleteConfig / SetAutoload`, autosave, built-in Settings tab UI for all of it.
- **Key system**: drawn in code, local keys + remote list + custom `Validate` callback, saved keys, "Get key" copies the link.
- **Localisation**: `Mova:SetTranslations{ es = { ["Auto farm"] = "Granja automática" } }` + `Mova:SetLocale("es")` relabels live.
- **Secure mode**: `getgenv().MOVA_SECURE = true` before loading → no console output, raw asset ids rejected.
- **Compatibility**: pure Luau subset (no `continue`, `+=`, types) so it also runs on Lua 5.1 / LuaJIT / 5.4 — which is how the test-suite runs headless.

---

## API reference

All option tables accept several aliases (Rayfield, Linoria/Obsidian and lower-case spellings). The first name listed is the canonical one.

### `Mova:CreateWindow(options) → Window`

| Option | Type | Default | Notes |
| --- | --- | --- | --- |
| `Name` / `Title` | string | `"Mova"` | Title in the top bar, pill text, config folder name |
| `Subtitle` | string | — | |
| `Icon` | number \| string | — | `rbxassetid` number, `"rbxassetid://…"`, or a name handled by `Mova:SetIconResolver` |
| `Theme` | string \| table | `"Mono"` | Any built-in name, a registered name, or a partial theme table |
| `ToggleUIKeybind` / `ToggleKey` | string \| KeyCode | `"K"` | Show/hide key on desktop |
| `Size` | UDim2 \| Vector2 \| `{w, h}` | 640×440 (560×340 mobile) | Clamped to the viewport |
| `ConfigurationSaving` | table | — | `{ Enabled, FolderName, FileName = "default", AutoSave = true, AutoLoad = true }` |
| `KeySystem` / `KeySettings` | bool \| table | — | `{ Title, Subtitle, Note, Keys = {}, KeyURL, Validate = fn(key), Link, SaveKey = true, FileName }` |
| `Translations`, `Locale` | table, string | — | See localisation |
| `SettingsTab` | bool | `true` | Built-in Settings tab (theme, toggle key, configs, unload) |

**Window methods**: `CreateTab(opts | name, icon)`, `SelectTab(tab | name | index)`, `Show()`, `Hide()`, `Toggle()`, `SetVisible(bool)`, `IsVisible()`, `ToggleMinimise()`, `SetTitle()`, `SetSubtitle()`, `SetToggleKey(key)`, `ChangeTheme(name | table)`, `Notify(opts)`, `Dialog(opts)`, `Toast(text)`, `Get(flag)`, `Set(flag, value, silent)`, `SaveConfig(name)`, `LoadConfig(name)`, `ListConfigs()`, `DeleteConfig(name)`, `SetAutoload(name | nil)`, `Destroy()`.
Aliases: `AddTab`, `Navigate`, `ToggleHide`, `SetVisibility`, `ToggleMinimize`, `Minimize`, `ModifyTheme`, `SetTheme`, `Popup`, `Unload`, `Save`, `Load`.

### `Window:CreateTab({ Name, Icon, Order }) → Tab`

Tabs are containers. **Tab methods**: `Select()`, `SetVisible(bool)`, `SetName(text)`, `Destroy()` plus every element constructor below.

### Element constructors (on a Tab or Section)

Every constructor accepts a table; `Name`/`Title`/`Text` is the label, `Description`/`Tooltip`/`Desc` the sub-text, `Flag` registers the value in `Mova.Flags` and the config, `Save = false` excludes it from configs, `Locked = true` starts disabled, `Order` sets layout order.

| Constructor | Value | Key options | Extra methods |
| --- | --- | --- | --- |
| `CreateButton{ Callback }` or `CreateButton("Text", fn)` | — | | `Press()` |
| `CreateToggle{ Default, Callback(bool) }` | boolean | | `Toggle()`, `AddKeybind{ Default, Mode }` |
| `CreateSlider{ Range = {min,max}` or `Min/Max, Increment, Default, Suffix, Callback(n) }` | number | `Increment` controls snapping and decimals; the value box accepts typing | |
| `CreateInput{ Default, Placeholder, Numeric, Finished = true, ClearOnFocus, Callback(text) }` | string | `Finished = false` fires per keystroke | |
| `CreateDropdown{ Options, Default, MultipleOptions, Searchable, AllowNone = true, Callback(v) }` | string \| table | > 6 options get a filter box automatically | `Refresh(options, keepValue)`, `Open()`, `Close()` |
| `CreateKeybind{ Default, Mode = "Press", Callback, ChangedCallback, Blacklist }` | KeyCode \| UserInputType | Modes: `Press` (callback(key)), `Toggle` / `Hold` (callback(state)), `Always`. Click the box to record: Esc cancels, Backspace clears, clicking elsewhere cancels; keys fire unless a text box is focused (not blocked by WASD/Space-style game bindings) | `SetMode()`, `GetState()` |
| `CreateColorPicker{ Color, Alpha, Callback(color, alpha) }` | Color3 (+ alpha) | `Alpha` enables the transparency bar | `Set(color | "#hex", alpha)`, `GetHex()`, `Open()`, `Close()` |
| `CreateLabel{ Name, Icon, Transparent }` or `CreateLabel("text")` | — | | `Set(text)` |
| `CreateParagraph{ Title, Content }` | — | | `Set{ Title, Content }` |
| `CreateDivider("text")` | — | | |
| `CreateSection{ Name, Collapsed }` | — | Returns a container with all constructors | `SetCollapsed(bool)` |
| `CreateGroup{ Direction = "row"\|"column", Columns = 2, Gap = 6 }` | — | Rayfield Gen 2 layout container: a row packs children side by side (wrapping past `Columns`), a column stacks them; nest a row of columns for a grid. Aliases `CreateRow` / `CreateColumn` | `SetVisible(bool)`, `Destroy()` |

**Common handle API** (every element): `.Value`, `.Flag`, `.Type`, `.Card`, `Set(value, silent)`, `Get()`, `SetTitle(text)`, `SetDescription(text)`, `SetVisible(bool)`, `Lock(reason?)`, `Unlock()`, `IsLocked()`, `SetOrder(n)`, `OnChanged(fn)`, `Destroy()`.

**Linoria / Obsidian aliases** (same handles, same flags): `AddLeftGroupbox(name)`, `AddRightGroupbox(name)`, `AddToggle(flag, { Text, Default, Tooltip, Callback })`, `AddSlider(flag, { Text, Default, Min, Max, Rounding, Suffix })`, `AddDropdown(flag, { Values, Default, Multi, Searchable })`, `AddInput(flag, { Default, Placeholder, Numeric })`, `AddKeyPicker(flag, { Default, Mode })`, `AddColorPicker(flag, { Default, Transparency })`, `AddButton{ Text, Func }`, `AddLabel(text)`, `AddDivider()`, `Toggle:AddKeyPicker()`.

### Global registries

```lua
Mova.Flags.AutoFarm          -- current value of the element with Flag = "AutoFarm"
Mova.Options.AutoFarm:Set(true)   -- the element handle (any type)
Mova.Toggles.AutoFarm        -- toggles only (Linoria compatibility)
```

### `Mova:Notify(opts)` / `Mova:Dialog(opts)`

```lua
Mova:Notify({ Title = "Saved", Content = "Config written.", Type = "Success", Duration = 4, Icon = 123,
              Actions = { { Text = "Undo", Callback = fn }, { Text = "OK" } } })
Mova:Notify("plain string")

Mova:Dialog({ Title = "Delete?", Content = "This cannot be undone.",
              Buttons = { { Text = "Cancel" }, { Text = "Delete", Style = "Danger", Callback = fn } } })
```

### Themes

```lua
Mova:GetThemeNames()                -- { "Mono", "Dark", "Light", "Midnight", ... }
Mova:SetTheme("Ocean")              -- tweens every bound property
Mova:RegisterTheme("Neon", { Accent = Color3.fromRGB(0, 255, 170) })  -- missing keys fall back to Dark
Mova:SetTheme({ Background = Color3.fromRGB(9, 9, 9) })               -- inline partial theme
```

Theme keys: `Background, Sidebar, Surface, SurfaceHover, Stroke, Accent, AccentHover, OnAccent, Text, TextDim, Placeholder, Divider, Shadow, Knob, Track, Field, Scrollbar, Overlay, Success, Warning, Error` (colours) plus:

| Key | Default | Meaning |
| --- | --- | --- |
| `FontFamily` | `rbxasset://fonts/families/GothamSSm.json` | Family used with `Font.new(family, weight)`. Any built-in family or an `rbxassetid://` font works (secure mode falls back to the built-in). |
| `Font` / `TitleFont` | `GothamMedium` / `GothamBold` | Fallback `Enum.Font`s for engines without `FontFace`. |
| `Radius` | `10` | Corner radius of cards, fields, popups. |
| `WindowRadius` | `14` | Corner radius of the window, dialogs and the key card. |
| `StrokeTransparency` | `0.45` | Resting transparency of element outlines (hover sharpens them). |

Any `TextLabel/TextButton/TextBox` created through `Mova.New` accepts `Weight = "Regular" | "Medium" | "SemiBold" | "Bold"`; the weight re-resolves automatically when the theme's `FontFamily` changes.

### Configs

Files are written to `<FolderName>/<name>.mova.json` (default folder `Mova/<WindowName>`). The autoload name is stored in `<FolderName>/autoload.txt`. Format:

```json
{ "library": "Mova", "version": 1, "data": {
  "AutoFarm": true,
  "AimKey": { "__type": "Enum", "enum": "KeyCode", "name": "Q" },
  "BoxColor": { "__type": "Color3", "r": 1, "g": 0.31, "b": 0.31 },
  "Fill": { "__type": "ColorAlpha", "color": { "...": "..." }, "alpha": 0.5 },
  "Targets": ["Players", "NPCs"]
} }
```

Loading calls each element's callback (so game state follows the config); pass `silent` yourself through `Window:Set(flag, value, true)` when you don't want that.

### Other

```lua
Mova:SetIconResolver(function(nameOrId) return "rbxassetid://…" end)  -- plug in Lucide or your own icon pack
Mova:SetTranslations({ es = { ["Main"] = "Principal" } }); Mova:SetLocale("es")
Mova:SetVisibility(false); Mova:IsVisible()
Mova:SaveConfiguration(); Mova:LoadConfiguration()   -- all windows
Mova:Destroy()                                       -- disconnects everything, removes the GUI
Mova.Version, Mova.IsMobile, Mova.SecureMode, Mova.Unloaded
Mova.New(class, props)  Mova.Tween(obj, props, time)  Mova.SafeCallback(fn, ...)  Mova.KeyToString(key)
```

---

## Porting

**From Rayfield** — mostly rename the loader. `CreateWindow`, `CreateTab`, `CreateSection`, `CreateButton/Toggle/Slider/Input/Dropdown/Keybind/ColorPicker/Label/Paragraph/Divider`, `Flag`, `CurrentValue/CurrentOption/CurrentKeybind`, `Range/Increment/Suffix`, `ConfigurationSaving`, `KeySystem/KeySettings`, `Rayfield:Notify` → `Mova:Notify` all work. `Window:ModifyTheme` → `ChangeTheme` (alias provided). `Rayfield.Flags.X.CurrentValue` → `Mova.Flags.X`.

**From Linoria / Obsidian** — `Library:CreateWindow` → `Mova:CreateWindow`, `Window:AddTab("Name")` → `Window:CreateTab("Name")` (alias `AddTab` exists), then `Tab:AddLeftGroupbox`, `Groupbox:AddToggle(...)`, `Toggles.X.Value`, `Options.X:SetValue()` are all there (`Mova.Toggles`, `Mova.Options`). SaveManager/ThemeManager are built in: use `Window:SaveConfig` and `Mova:SetTheme`.

---

## Development

```bash
pip install lupa
cd "Mova Library"
python3 tests/run.py          # Lua 5.4
python3 tests/run.py --all    # Lua 5.1, LuaJIT and 5.4
```

`tests/roblox_mock.lua` is a small headless model of Roblox (instances, signals, services, datatypes, a virtual file system, `task`) that is strict about things real Roblox rejects — e.g. custom fields on Instances or wrong property types. `tests/smoke.lua` drives every public API, and `tests/example_check.lua` runs `example.lua` so the docs can't drift from the code. It is not a renderer; always do a final check in an executor or Studio.
