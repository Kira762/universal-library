# Rayfield research notes (Oct 2026)

Reference notes on the two open-source generations of Sirius's Rayfield UI library for Roblox.

## Repositories

| Repo | What it is | License | Language | Created | Last push | Stars / forks |
| --- | --- | --- | --- | --- | --- | --- |
| `jensonhirst/Rayfield` (was `shlexware/Rayfield`) | Original 2022 repo. **Archived 2024‑11‑19**, read-only. | Apache-2.0 | Lua | 2022‑08‑10 | 2024‑11‑19 | 82 / 129 |
| `SiriusSoftwareLtd/Rayfield` | Canonical **Rayfield (2022)** repo, still maintained. | Apache-2.0 | Lua | 2023‑09‑04 | 2026‑10‑20 | 80 / 119 |
| `SiriusSoftwareLtd/rayfield-gen2` | **Rayfield Gen2**, ground-up rewrite. | MPL-2.0 (© 2026 Corridon Capital) | Luau | 2025‑01‑11 | 2026‑10‑20 | 15 / 15 |
| `sirius-menu/rayfield` | Mirror of the 2022 source (Dec 2025), no license file. | – | Lua | 2025‑12‑16 | 2025‑12‑19 | 1 / 0 |
| `SiriusDevelopmentGroup/rayfield-docs` | Old docs, archived 2024‑04‑27. | – | – | – | – | – |

Docs: https://docs.sirius.menu/rayfield (2022) and https://docs.sirius.menu/rayfield-gen2 (Gen2). Machine-readable index at https://docs.sirius.menu/llms.txt. Docs source: `SiriusSoftwareLtd/docs` (MIT).

Main contributors: `jensonhirst` (shlex, lead on both), `maxtcodes`, `Damian-11` (2022 only).

## Rayfield (2022) – "Rayfield Interface Suite"

- Load: `loadstring(game:HttpGet('https://sirius.menu/rayfield'))()`
  (raw: `https://raw.githubusercontent.com/SiriusSoftwareLtd/Rayfield/refs/heads/main/source.lua`)
- Current build in `source.lua`: `Release = "Build 1.753"`, `InterfaceBuild = 'UU2NX'`. Single ~190 KB file plus `icons.lua` (Lucide icon map, ~148 KB) and `reporter.lua` (analytics). Remote modules are pinned to a commit via `RAYFIELD_COMMIT`.
- UI is a **Roblox marketplace model** loaded by asset ID (this is the detectability problem Gen2 fixes).
- API (PascalCase, positional or table args):
  - `Rayfield:CreateWindow{ Name, Icon, LoadingTitle, LoadingSubtitle, ShowText, Theme, ToggleUIKeybind, DisableRayfieldPrompts, DisableBuildWarnings, Heartbeat, ScriptID, ConfigurationSaving{Enabled,FolderName,FileName}, Discord{Enabled,Invite,RememberJoins}, KeySystem, KeySettings{Title,Subtitle,Note,FileName,SaveKey,GrabKeyFromSite,Key} }`
  - `Rayfield:Notify`, `Rayfield:Destroy`, `Rayfield:IsVisible`, `Rayfield:SetVisibility`, `Rayfield:LoadConfiguration`
  - `Window:CreateTab(name, icon)`, `Window.ModifyTheme(theme)`
  - `Tab:CreateSection`, `CreateDivider`, `CreateButton`, `CreateToggle`, `CreateColorPicker`, `CreateSlider`, `CreateInput`, `CreateDropdown`, `CreateKeybind`, `CreateLabel`, `CreateParagraph` (9 "elements" + section/divider)
- 9 built-in themes: Default, AmberGlow, Amethyst, Bloom, DarkBlue, Green, Light, Ocean, Serenity. Custom theme tables since 1.53.
- Icons: Roblox image ID or Lucide icon name (via latte-soft/lucide-roblox).
- Config saving to `Rayfield/Configurations/*.rfld`, settings in `Rayfield/settings.rfld`.
- Built-in **key system** (local list or `GrabKeyFromSite` raw URL) and **Discord auto-join** prompt.
- Global flags: `RAYFIELD_SECURE` (secure mode: silence console, block detectable asset refs), `RAYFIELD_ASSET_ID` (swap the model for your own uploaded copy – "anti-detection"), `RAYFIELD_ANALYTICS = false`, `DISABLE_RAYFIELD_REQUESTS = true` (dev-side kill switch for analytics + heartbeat).
- **Analytics**: one event per window open (hashed user id, place/universe, executor, platform, locale, script name/theme/features; kick/ban error codes). ~1/200 sessions ping a Sentivel uptime monitor. Opt-out via settings tab or the globals above.
- Sirius says it has run ~400 M+ times as of Jan 2026 (rayfield.gg claims 432 M executions). Still works but "new scripts should start on Gen2".

## Rayfield Gen2

- Load (stable): `loadstring(game:HttpGet("https://sirius.menu/gen2"))()`
  Preview (rolling build from `dev`): `https://sirius.menu/gen2-preview`
- Timeline: repo created Jan 2025; public preview announced on r/robloxhackers 2025‑01‑29; **1.0.0 released 2026‑07‑22**, 1.0.1–1.0.3 within days, 1.1.0 (2026‑07‑31), **1.2.0 (2026‑08‑31, current stable)**, preview heading to 1.2.1.
- **Built entirely in code** (no marketplace model, nothing for `GetAssetFetchStatus` to probe). Secure mode (`getgenv().RAYFIELD_SECURE = true`) caches built-in icons/brand font/avatars to local files via `getcustomasset`, blocks any raw asset IDs you pass, and silences all console output. Needs an executor with file access.
- Proper engineering setup: Rojo project, Luau strict types (`src/types.luau`), StyLua + Selene + luau-lsp in CI, TestEZ specs (38 test files, 70 % coverage gate + tracked baseline), Rokit-pinned toolchain, Wax bundle minified with Darklua for release, Cloudflare Worker (`worker/`) that serves the loadstring. GitHub Actions: `ci.yml`, `preview.yml`, `release.yml`. Branches: `main`, `dev`, `preview-channel`, plus feature branches.
- Source layout: `src/init.luau` (entry), `src/components/*` (window, tab, sidebar, button, toggle, slider, dropdown, input, keybind, colorpicker, stat, progress, console, text, divider, notification, toast, popup, tag, search, group, section…), `src/themes/*` (6 themes), `src/utility/*` (persistence, filesystem, imageCache, fontManager, locale, odometer, HapticEngine, windowSizing…).
- API (camelCase props, PascalCase also accepted; every element returns a handle):
  - `Rayfield:CreateWindow{ name, subtitle, theme, icon, sidebarLayout, profile, showName, showIcon, showIconOnly, configuration{autoSave,autoLoad,fileName,customFolder}, locale, translations, translator, fallbackFont (preview), heartbeat }`
  - Window: `CreateTab`, `CreateTag`, `CreateSection` (sidebar headings), `SetProfile`, `Notify`, `Toast`, `Popup`, `Show/Hide/ToggleHide/ToggleMinimise`, `Navigate`, `Unload`, `ChangeTheme`, `SetLocale`, `SetTranslator`, `Save/Load/ListConfigs/DeleteConfig`, `Get/Set`, `.Flags`
  - Tab/Group: `CreateSection`, `CreateGroup` (row/column grids), `CreateButton`, `CreateToggle`, `CreateSlider` (`range`, `increment`, `suffix`), `CreateDropdown` (`multiSelect`, type-to-filter), `CreateInput` (`numeric`, `placeholder`), `CreateKeybind` (`hold` mode), `CreateColorPicker` (alpha, hex), `CreateStat` (rolling odometer number with delta), `CreateProgress`, `CreateConsole` (monospace log block), `CreateText`, `CreateDivider`
  - Element handles: `.value`, `Set(value, silent?)`, `Lock(reason)/Unlock()/IsLocked()`, `MoveTo/MoveToTop/MoveToBottom/MoveUp/MoveDown`, `flag`, `forgetState`
- 6 themes: default, cobalt, ember, amethyst, frost, rose; theme switching tweens colours live. Custom theme tables supported.
- Runtime **localization** (translation tables keyed by locale or a custom resolver; follows the player's Roblox locale by default).
- Config persistence restores values with original types; multiple named configs.
- Resizable window, sidebar or top-tab layout, draggable collapsed pill, mobile-first sizing, settings tab with rebindable toggle key (default **K**).
- Not (yet) in the Gen2 source on `main`: key system, Discord prompt, built-in analytics/monetization. The 2025 preview post promised monetization, developer analytics and a key system; the 2022 docs now point to the paid/free "Sirius Developer Platform" (developer.sirius.menu) for managed keys. Heartbeat (Sentivel) is in the docs/dev branch.

## Community forks / derivatives worth knowing

- `aesthetic143147-arch/Rayfield-preview-Gen2` – "Rayfield Columns": two-column layout edition of Gen2 (MPL-2.0, unofficial).
- `opploop/67676767` – self-styled "Rayfield Gen3": Gen2-based with auto-translation, guided tour, HUD chip, key system; single-file ~1.3 MB bundle.
- `dlyrr/mono-mm2-rayfield` – reconstructs the darklua-minified Gen2 bundle back into its 67-module Rojo tree.
- `syntaaxzz/kint1x-rayfield-ui` – modified Gen2.
- `Epixerty/StudioRayfield` – 2022 Rayfield made to run inside Roblox Studio (unmaintained).
- `VanPotent/Or2Field` – Python converter from Orion UI code to Rayfield.
- `jensonhirst/Orion` – Sirius's earlier library; the original `shlexware/Orion` was compromised in Jan 2025, so avoid old Orion loadstrings.

## Quick comparison

| | Rayfield (2022) | Rayfield Gen2 |
| --- | --- | --- |
| License | Apache-2.0 | MPL-2.0 |
| Code | one 190 KB Lua file | ~70 Luau modules, typed, tested |
| UI source | Roblox model asset | drawn in code |
| Elements | 9 (+section/divider) | 12 (+section/group/tag/toast/popup) |
| Themes | 9 | 6 (live tween switching) |
| Key system / Discord | built in | not in source (platform-based) |
| Localization | no | yes, runtime |
| Element lock/reorder | no | yes |
| Secure mode | hides asset refs, needs `RAYFIELD_ASSET_ID` to be truly safe | nothing to swap; local-file assets only |
| Props casing | PascalCase | camelCase (PascalCase accepted) |
| Status | maintenance; "use Gen2 for new scripts" | active, stable 1.2.0 |
