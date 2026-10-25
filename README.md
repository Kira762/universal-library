# universal-library

Reference collection of open-source Roblox UI libraries, one folder per library at the repo root,
plus **Mova Library** — an original library built after studying all of them.
Each vendored folder is a snapshot of the upstream default branch (no `.git`, pinned commit listed below).
Research notes live in [`docs/`](docs/).

## Mova Library (original)

[`Mova Library/`](Mova%20Library/) — single-file, MIT, drawn 100 % in code, zero telemetry, typed JSON configs,
live themes, Rayfield **and** Linoria/Obsidian style APIs, search across tabs, keybind modes, mobile support,
built-in key system / settings tab, and a headless test-suite. See its [README](Mova%20Library/README.md) and
[`example.lua`](Mova%20Library/example.lua).

```lua
local Mova = loadstring(game:HttpGet("https://raw.githubusercontent.com/Kira762/universal-library/main/Mova%20Library/source.lua"))()
```

## Vendored libraries

| Folder | Upstream | Commit | License |
| --- | --- | --- | --- |
| `Rayfield 2022/` | [SiriusSoftwareLtd/Rayfield](https://github.com/SiriusSoftwareLtd/Rayfield) | `a8ea172` | Apache-2.0 |
| `Rayfield Gen 2/` | [SiriusSoftwareLtd/rayfield-gen2](https://github.com/SiriusSoftwareLtd/rayfield-gen2) | `3c064e0` | MPL-2.0 |
| `Orion/` | [jensonhirst/Orion](https://github.com/jensonhirst/Orion) | `85c1ef4` | none |
| `Fluent/` | [dawid-scripts/Fluent](https://github.com/dawid-scripts/Fluent) | `78ba067` | MIT |
| `WindUI/` | [Footagesus/WindUI](https://github.com/Footagesus/WindUI) | `d2c9bac` | MIT |
| `LinoriaLib/` | [violin-suzutsuki/LinoriaLib](https://github.com/violin-suzutsuki/LinoriaLib) | `1be38aa` | MIT |
| `LinoriaLib (mstudio45 fork)/` | [mstudio45/LinoriaLib](https://github.com/mstudio45/LinoriaLib) | `a990198` | MIT |
| `Obsidian/` | [deividcomsono/Obsidian](https://github.com/deividcomsono/Obsidian) | `82d402b` | MIT |
| `Kavo/` | [xHeptc/Kavo-UI-Library](https://github.com/xHeptc/Kavo-UI-Library) | `541dec3` | none |
| `Luna/` | [Nebula-Softworks/Luna-Interface-Suite](https://github.com/Nebula-Softworks/Luna-Interface-Suite) | `f714cba` | BSD-3-Clause |
| `Starlight/` | [Nebula-Softworks/Starlight-Interface-Suite](https://github.com/Nebula-Softworks/Starlight-Interface-Suite) | `1ec0fb9` | NOASSERTION |
| `Maclib/` | [biggaboy212/Maclib](https://github.com/biggaboy212/Maclib) | `c5a5c47` | MIT |
| `Mercury/` | [deeeity/mercury-lib](https://github.com/deeeity/mercury-lib) | `406c409` | none |
| `Bracket/` | [AlexR32/Bracket](https://github.com/AlexR32/Bracket) | `2c348f3` | none |
| `OasisUI/` | [Mold53/OasisUI](https://github.com/Mold53/OasisUI) | `3b93dc4` | MIT |
| `Eazy UI/` | [akiradv/eazyuilib](https://github.com/akiradv/eazyuilib) | `3bc2a6f` | MIT |
| `Aetheris/` | [Saint0-0/Aetheris](https://github.com/Saint0-0/Aetheris) | `11704eb` | MIT |
| `Velvet/` | [DexCodeSX/Velvet](https://github.com/DexCodeSX/Velvet) | `0edd1e8` | MIT |
| `WindUI/src/Icons/` | [Footagesus/Icons](https://github.com/Footagesus/Icons) | `46d30c1` | MIT |

Snapshot taken 2026-10-25.

## Notes

- Only oversized promotional images were dropped to keep the repo small: three ~12 MB banners in `Aetheris/assets/`, the cover/ad PNGs in `Starlight/`, and the banner PNGs in `WindUI/docs/`. All source, docs, and functional assets are intact.
- `WindUI/src/Icons/` was a git submodule upstream; its contents were vendored from `Footagesus/Icons`.
- **Licensing**: Orion, Kavo, Mercury and Bracket ship with no license file, so they are effectively all-rights-reserved. Starlight uses a custom license (`Starlight/LICENSE`). Check each folder's `LICENSE` before reusing code. The copies here are for study/reference.
- **Security**: never load Orion from `shlexware/*` URLs — that account was taken over in Jan 2025 and served an obfuscated build. The copy here is from `jensonhirst/Orion`.
- Not included: `7GrandDadPGN/VapeV4ForRoblox` (a ~110 MB full script, not a UI library) and the collection repos (`GhostDuckyy/UI-Libraries`, `x2Swiftz/UI-Library`, …) which bundle dozens of dead libraries; see `docs/roblox-ui-libraries-research.md` if you want any of those pulled in.

## Refreshing a snapshot

```bash
curl -sL https://codeload.github.com/<owner>/<repo>/tar.gz/refs/heads/<branch> | tar -xz -C "<Folder>" --strip-components=1
```
