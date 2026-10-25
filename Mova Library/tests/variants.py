#!/usr/bin/env python3
"""Drive the library through the mock under the environment variants the smoke test does not
cover: secure mode, mobile (touch only), and Studio mode. Each variant builds a window with one of
every element, exercises drag / resize / pill / configs / themes, and must finish without raising.

    python3 tests/variants.py
"""
import importlib
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

VARIANTS = [
    ("lupa.lua51", dict(mobile=False, secure=True, studio=False)),
    ("lupa.luajit21", dict(mobile=True, secure=False, studio=False)),
    ("lupa.lua54", dict(mobile=True, secure=True, studio=True)),
]

CODE = """
  local mock = dofile('tests/roblox_mock.lua')
  MOVA_SECURE = %(secure)s
  mock.StudioMode = %(studio)s
  if %(mobile)s then
    local UIS = mock.Services.UserInputService
    UIS.TouchEnabled = true UIS.MouseEnabled = false UIS.KeyboardEnabled = false
    UIS.GetPlatform = function() return Enum.Platform.Android end
  end
  local Mova = dofile('source.lua')
  local W = Mova:CreateWindow({ Name = "Variant", ConfigurationSaving = { Enabled = true } })
  local T = W:CreateTab("Tab")
  local tg = T:CreateToggle({ Name = "t", Flag = "t", Default = true })
  local kb = tg:AddKeybind({ Default = "F" })
  T:CreateSlider({ Name = "s", Range = {0, 10}, Default = 5, Flag = "s" })
  T:CreateDropdown({ Name = "d", Options = {"a","b"}, Default = "a", Flag = "d" })
  local cp = T:CreateColorPicker({ Name = "c", Color = Color3.fromRGB(1,2,3), Flag = "c" })
  T:CreateKeybind({ Name = "k", Default = "Q", Flag = "k" })
  T:CreateInput({ Name = "i", Flag = "i" })
  T:CreateLabel({ Name = "lbl", Icon = 4483362458 })
  T:CreateParagraph({ Title = "p", Content = "c" })
  T:CreateButton({ Name = "b", Callback = function() end })
  local row = T:CreateRow()
  row:CreateToggle({ Name = "grouped", Flag = "g" })
  row:CreateButton({ Name = "grouped button" })
  mock.flush()
  cp:Open() cp:Close()
  W:SaveConfig("x") W:LoadConfig("x")
  Mova:Notify({ Title = "hi", Content = "there" })
  -- pill drag + tap on mobile
  W:Hide() mock.flush()
  mock.click(W.Pill) mock.flush()
  assert(not W.Hidden, "pill tap restores window")
  -- touch drag on the topbar
  local tb = W.Topbar
  local i = mock.input(Enum.UserInputType.Touch, nil, Vector2.new(10, 10))
  tb.InputBegan:Fire(i, false)
  local mv = mock.input(Enum.UserInputType.Touch, nil, Vector2.new(60, 40))
  mock.Services.UserInputService.InputChanged:Fire(mv, false)
  i.UserInputState = Enum.UserInputState.End i.Changed:Fire()
  assert(W.Main.Position.X.Offset ~= 0 or W.Main.Position.X.Scale ~= 0, "window moved")
  -- resize handle
  local r = mock.input(Enum.UserInputType.MouseButton1, nil, Vector2.new(100, 100))
  W.ResizeHandle.InputBegan:Fire(r, false)
  mock.Services.UserInputService.InputChanged:Fire(mock.input(Enum.UserInputType.MouseMovement, nil, Vector2.new(300, 250)), false)
  r.UserInputState = Enum.UserInputState.End r.Changed:Fire()
  if Mova.IsMobile then assert(not W.DragBar.Visible, "drag bar stays off on mobile") end
  Mova:SetTheme("Light")
  for _, n in ipairs(Mova:GetThemeNames()) do Mova:SetTheme(n) end
  W:Destroy() Mova:Destroy()
  return string.format("mobile=%%s secure=%%s studio=%%s instances=%%d", tostring(Mova.IsMobile), tostring(Mova.SecureMode), tostring(mock.StudioMode), mock.Created())
"""


def main() -> int:
    os.chdir(ROOT)
    worst = 0
    for modname, flags in VARIANTS:
        try:
            lua = importlib.import_module(modname)
        except ImportError:
            print(f"[{modname}] not available, skipping")
            continue
        rt = lua.LuaRuntime(unpack_returned_tuples=True)
        code = CODE % {k: str(v).lower() for k, v in flags.items()}
        try:
            print(modname, "->", rt.execute(code))
        except Exception as exc:  # noqa: BLE001
            print(modname, "FAILED:", exc)
            worst = 1
    return worst


if __name__ == "__main__":
    sys.exit(main())
