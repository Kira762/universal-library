# Roblox UI libraries beyond Rayfield (Oct 2026)

Companion to `rayfield-research.md`. Repo stats were pulled from the GitHub API on 2026‑10‑25.

## At a glance

| Library | Repo | License | ★ / ⑂ | Created → last push | Status | Style / lineage |
| --- | --- | --- | --- | --- | --- | --- |
| **Orion** | `jensonhirst/Orion` (ex `shlexware/Orion`) | none | 128 / 270 | 2022‑04 → 2026‑04 | **Deprecated** ("Use Rayfield") | Sirius, Rayfield's predecessor |
| **Fluent** | `dawid-scripts/Fluent` | MIT | 122 / 212 | 2023‑07 → 2024‑05 | Unmaintained (last release 1.1.0, Aug 2023) | WinUI/acrylic look, Linoria element code |
| Fluent Renewed | `ActualMasterOogway/Fluent-Renewed` | MIT | 38 / 52 | 2024‑05 → 2025‑04 | **Archived** | Fluent fork |
| Fluent Modded | `StyearX/Fluent-modded` | MIT | 25 / 17 | 2026‑04 → 2026‑09 | **Archived** ("Dead project") | Fluent fork |
| **WindUI** | `Footagesus/WindUI` | MIT | 384 / 353 | 2024‑10 → 2026‑10 | Active (Beta; v1.6.66 Jul 2026) | Modern, modular |
| **LinoriaLib** (original) | `violin-suzutsuki/LinoriaLib` | MIT | 96 / 479 | 2021‑12 → 2024‑08 | Dormant | Splix/BBot "cheat menu" style |
| LinoriaLib (fork) | `mstudio45/LinoriaLib` | MIT | 40 / 66 | 2023‑04 → 2026‑08 | Somewhat maintained | adds resizing etc. |
| **Obsidian** | `deividcomsono/Obsidian` | MIT | 157 / 283 | 2025‑01 → 2026‑10 | **Active** (changelog Oct 7 2026) | Linoria API, mobile + PC |
| **Kavo** | `xHeptc/Kavo-UI-Library` | none | 21 / 51 | 2021‑02 → 2025‑09 | Legacy | Classic simple lib |
| **Luna Interface Suite** | `Nebula-Softworks/Luna-Interface-Suite` | BSD‑3 | 61 / 38 | 2024‑11 → 2025‑12 | Discontinued Apr 2025 (maintenance only) | Sirius/Rayfield-like |
| **Starlight Interface Suite** | `Nebula-Softworks/Starlight-Interface-Suite` | custom | 86 / 24 | 2025‑06 → 2026‑08 | Beta (Prerelease 5.01) | Luna successor, Linoria-inspired |
| **Maclib** | `biggaboy212/Maclib` | MIT | 25 / 12 | 2024‑09 → 2025‑01 | Dormant | macOS look, sidebar |
| **Mercury** | `deeeity/mercury-lib` | none | 53 / 56 | 2022‑01 → 2024‑09 | Dormant | Browser-like navigation |
| **Bracket** | `AlexR32/Bracket` | none | 11 / 12 | 2021‑11 → 2025‑01 | **Archived** | CS:GO cheat-menu style |
| **Vape V4** (UI inside) | `7GrandDadPGN/VapeV4ForRoblox` | CC0‑1.0 | 86 / 221 | 2025‑02 → 2026‑10 | Active | Full script; UI is Minecraft-client style |

Newer / small (2026): `Mold53/OasisUI` (MIT, module cards, columns, theme editor), `akiradv/eazyuilib` (MIT, single file), `Saint0-0/Aetheris` (MIT, WinUI3/maclib-inspired, drawn in code, WIP), `DexCodeSX/Velvet` (MIT, glassmorphism), `wqzz1/Mercury` (MIT, "liquid glass", unrelated to deeeity's Mercury), `Ryanabcraft/AxiomUI`.

Collections (handy for browsing dozens of older libs): `GhostDuckyy/UI-Libraries` (★222, archived 2025 – Kavo, Ligma, Linoria, Orion, Venyx, Pepsi, Splix, Cerberus, uwuware, Neverlose clone…), `x2Swiftz/UI-Library` (★72 – Orion, Linoria rewrite, uwuware, Wally V3, Obsidian, Maclib…), `ImInsane-1337/Roblox-UI` (updated fork of weakhoes' list – Fluent, Obsidian, Luna, Gamesense/Neverlose clones), `ro0ti/Roblox-Scripting-UI`.

---

## Details

### Orion (Sirius, 2022)
- `loadstring(game:HttpGet('https://raw.githubusercontent.com/jensonhirst/Orion/main/source'))()`
- API: `OrionLib:MakeWindow{Name, HidePremium, SaveConfig, ConfigFolder, IntroEnabled, IntroText, Icon, KeySystem, KeySettings}` → `Window:MakeTab{Name, Icon, PremiumOnly}` → `Tab:AddSection/AddButton/AddToggle/AddColorpicker/AddSlider/AddLabel/AddParagraph/AddTextbox/AddBind/AddDropdown`; `OrionLib:MakeNotification`, `OrionLib:Init()` (loads saved config), `OrionLib:Destroy()`.
- One file, no license, built-in key system + config saving. Analytics reporting was added in Apr 2026 commits.
- README now says **"Deprecated. Use Rayfield."**
- ⚠️ **Jan 2025 incident**: the author renamed `shlexware` → `jensonhirst`; someone registered the old `shlexware` name and hosted an **obfuscated, likely malicious** "Orion" at the old URL. Any script still loading `raw.githubusercontent.com/shlexware/Orion/...` is unsafe. Use `jensonhirst/Orion` only, or migrate (`VanPotent/Or2Field` converts Orion code to Rayfield).

### Fluent (dawid, 2023)
- `loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()`
- Rojo project (`src/Elements/{Button,Toggle,Slider,Dropdown,Input,Keybind,Colorpicker,Paragraph}`), bundled release; addons `SaveManager` and `InterfaceManager` (theme + config UI sections).
- API: `Fluent:CreateWindow{Title, SubTitle, TabWidth, Size, Acrylic, Theme, MinimizeKey}` → `Window:AddTab{Title, Icon}` → `Tab:AddToggle/AddSlider/...`; `Fluent.Options.<Flag>:SetValue()`, `Window:Dialog`, `Window:SelectTab`, `Fluent:Notify`.
- Themes: Dark, Darker, Light, Aqua, Amethyst, Rose, plus acrylic blur. Credits Linoria for element code and richie0866/remote-spy for assets.
- Original hasn't been pushed since May 2024; both big forks (Renewed, Modded) are archived. Very widely used in script hubs despite that.

### WindUI (Footagesus, 2024‑)
- `loadstring(game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"))()` — docs at footagesus-windui.mintlify.app.
- Most-starred currently active lib (384★). Modular `src/` (elements: Button, Toggle, Slider, Dropdown, Input, Keybind, Colorpicker, Paragraph, Code, Image, Video, Viewport, ProgressBar, Divider, Group, HStack/VStack, Space, Section). Components: KeySystem, Notification, Popup, Dialog, Tag, Tooltip, Search, Openbutton.
- 10+ themes (Dark, Light, Rose, Plant, Indigo, Sky, Violet, Amber…), runtime switching; acrylic blur; localization module; flag-based config manager; key system with external providers (Luarmor, Platoboost, Panda/Junkie Development hooks in `src/utils/services`); own multi-pack icon set (`Footagesus/Icons`: Lucide, Craft, Geist, Solar, SF Symbols).
- API: `WindUI:CreateWindow{Title, Icon, Author, Folder, Theme, Size, Transparent, SideBarWidth, KeySystem}` → `Window:Tab{Title, Icon}` → `Tab:Toggle{Title, Value, Callback, Flag}` etc. (methods are `Tab:Button/Toggle/Slider/Dropdown/Input/Keybind/Colorpicker/Paragraph/Code/Section/Divider/Image/Space`).
- Author notes it's Beta and "might rewrite from scratch later"; many forks (KazeUI, WindU, etc.).

### LinoriaLib (Inori / violin-suzutsuki, 2021‑)
- `Library.lua` + `addons/ThemeManager.lua` + `addons/SaveManager.lua`.
- Window → Tabs → **Left/Right Groupboxes and Tabboxes** → `AddToggle/AddSlider/AddDropdown/AddInput/AddLabel/AddButton/AddDivider`, `AddKeyPicker` and `AddColorPicker` chained off toggles/labels, **DependencyBox** (show/hide elements based on others), `Library.Toggles` / `Library.Options` global registries, auto-scroll, keybind list, watermark.
- The "cheat menu" aesthetic (Splix/BBot/gamesense lineage); many hubs still use it. Original repo dormant since Aug 2024; `mstudio45/LinoriaLib` fork (adds resizing, fixes) is the maintained-ish one but its author now focuses on Obsidian.

### Obsidian (deivid / mspaint, 2025‑)
- `Library.lua` + `addons/{SaveManager,ThemeManager}.lua`; docs at docs.mspaint.cc/obsidian. Typed (`Library.d.luau`), StyLua/selene, wally.toml; works in Studio, executors and even has a React replica.
- API is **Linoria-compatible** (same `AddLeftGroupbox`, `AddToggle`, `Toggles.X`, `Options.X`) — easiest migration path from Linoria. Adds: `AddCheckbox`, `AddImage`, `AddVideo`, `AddViewport`, `AddUIPassthrough`, `AddDependencyGroupbox`, `AddKeyBox`, context menus, draggable buttons/labels/menus, tooltips, collapsible keybind menu with settings panel (Oct 2026), Lucide icons via font.
- Full mobile + PC support, themes, maintained by the mspaint hub team with a frequent changelog. Probably the best "serious" alternative to Rayfield Gen2 right now.

### Kavo (xHeptc, 2021)
- Single `source.lua`, no license. `Library.CreateLib(title, theme)` → `Window:NewTab` → `Tab:NewSection` → `Section:NewButton/NewToggle/NewSlider/NewDropdown/NewKeybind/NewColorPicker/NewTextBox/NewLabel`.
- 9 built-in themes: DarkTheme, LightTheme, BloodTheme, GrapeTheme, Ocean, Midnight, Sentinel, Synapse, Serpent. Very simple API; classic 2021‑22 hub look. No config saving or key system. Legacy – fine for tiny scripts, not for new work.

### Luna → Starlight (Nebula Softworks)
- **Luna** (Nov 2024, BSD‑3): heavily Sirius/Rayfield-inspired; `Luna:CreateWindow` → `Window:CreateHomeTab/CreateTab` → `Tab:CreateSection/Button/Toggle/Slider/Dropdown/Input/Bind/Keybind/ColorPicker/Label/Paragraph/Divider`. Discontinued 22 Apr 2025, maintenance only.
- **Starlight** (Jun 2025‑, Beta 5.01): `Starlight:CreateWindow` → `TabSection:CreateTab/CreateCustomTab` → `Tab:CreateGroupbox/CreateTabbox/CreateDivider` → `Groupbox:CreateToggle/Switch/Checkbox/Slider/Dropdown/Input/Bind/Button/PrimaryButton/SecondaryButton/Label/Paragraph/Divider`. Design "based off Linoria and other drawing libs"; pairs with `Nebula-Icon-Library` (4000+ Lucide/Material icons). Key system "coming soon". Custom license (check before forking).

### Maclib (biggaboy212 / brady-xyz, 2024)
- `loadstring(game:HttpGet("https://raw.githubusercontent.com/biggaboy212/Maclib/main/maclib.lua"))()` (also mirrored in `biggaboy212/Public-Resources`); docs on GitBook. MIT.
- macOS Settings look: sidebar, globe settings icon, dialogs, tab dividers, element groups, acrylic blur. `MacLib:Window{Title, Subtitle, Size, DragStyle, AcrylicBlur}`. Popular for its look (lots of "what UI is this?" posts) but no pushes since Jan 2025; several glassmorphic re-skins (e.g. `Dommeeeee/MSUHub-UI`).

### Mercury (deeeity, 2022)
- `loadstring(game:HttpGet("https://raw.githubusercontent.com/deeeity/mercury-lib/master/src.lua"))()`; `Mercury:Create{Name, Size, Theme, Link}`. Browser-like tab navigation, themes, buttons/sliders/dropdowns/inputs/color picker/notifications/prompts. No license, dormant since 2024.

### Bracket (AlexR32, 2021)
- CS:GO-style menu; v2/v3 in `AlexR32/Roblox`, standalone `AlexR32/Bracket` (wiki docs). Archived Jan 2025.

### Others you'll see referenced
- **Vape V4** (`7GrandDadPGN/VapeV4ForRoblox`, CC0): a full combat script, not a library, but its Minecraft-client-style GUI module gets ripped out and reused ("Vape UI lib").
- **Venyx**, **Pepsi UI**, **Splix**, **uwuware/Wally**, **Cerberus**, **Ligma** (Synapse-only), **Elerium** (ImGui-style), **Material UI**, **Finity**, **Neverlose/Gamesense clones**: all 2020‑22 era, mostly only alive inside the collection repos above; no active upstream.

---

## Takeaways for a "universal library"

1. **Actively maintained, open-licensed options today**: Rayfield Gen2 (MPL‑2.0), Obsidian (MIT), WindUI (MIT), Starlight (custom license, beta). Everything else is dormant, archived, or deprecated.
2. **Two API families dominate**: the *Rayfield/Orion* family (`CreateWindow → CreateTab → CreateToggle{Name, Callback}`; Luna, Kavo-ish, WindUI loosely) and the *Linoria* family (`Window → Tab → Left/RightGroupbox → AddToggle`, global `Toggles`/`Options`; Obsidian, Fluent, Starlight). A universal adapter should target both shapes.
3. **Common feature set to normalise**: window/tab/section, toggle, slider, dropdown (single/multi), input, keybind, colour picker, button, label/paragraph, divider, notification; plus flags + config save/load, themes, optional key system, Lucide-style icons.
4. **Security hygiene**: never load from `shlexware/*` (Orion hijack); prefer release/commit-pinned URLs (Fluent releases, Rayfield's `RAYFIELD_COMMIT`), and check licenses — Orion, Kavo, Mercury, Bracket have **no** license file, so they are technically all-rights-reserved.
