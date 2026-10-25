#!/usr/bin/env python3
"""Run the Mova headless smoke test without a system Lua install (uses the `lupa` package).

    pip install lupa
    python3 tests/run.py            # Lua 5.4
    python3 tests/run.py --all      # Lua 5.1, LuaJIT 2.1 and Lua 5.4 (Luau sits between 5.1 and 5.4)
"""
import importlib
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
RUNTIMES = ["lupa.lua51", "lupa.luajit21", "lupa.lua54"] if "--all" in sys.argv else ["lupa.lua54"]


def run(modname: str) -> int:
    try:
        lua = importlib.import_module(modname)
    except ImportError:
        print(f"[{modname}] not available in this lupa build, skipping")
        return 0
    print(f"=== {modname} ===")
    rt = lua.LuaRuntime(unpack_returned_tuples=True)
    os.chdir(ROOT)
    status = {"code": 0}

    def _exit(code=0):
        status["code"] = int(code)
        raise SystemExit(int(code))

    rt.globals()["os"]["exit"] = _exit
    rt.globals()["MOVA_MOCK_PATH"] = os.path.join(HERE, "roblox_mock.lua")
    rt.globals()["MOVA_SOURCE_PATH"] = os.path.join(ROOT, "source.lua")
    try:
        rt.execute("local chunk = assert(loadfile('tests/smoke.lua')) chunk(MOVA_MOCK_PATH, MOVA_SOURCE_PATH)")
    except SystemExit:
        pass
    if status["code"] == 0:
        # fresh runtime so the example starts from a clean mock
        rt2 = lua.LuaRuntime(unpack_returned_tuples=True)
        try:
            rt2.execute("local chunk = assert(loadfile('tests/example_check.lua')) chunk('tests/roblox_mock.lua')")
        except Exception as exc:  # noqa: BLE001
            print("example_check FAILED:", exc)
            status["code"] = 1
    return status["code"]


if __name__ == "__main__":
    worst = 0
    for name in RUNTIMES:
        worst = max(worst, run(name))
    sys.exit(worst)
