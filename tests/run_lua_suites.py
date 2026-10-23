"""Compile mod sources and run every Lua suite under Lua 5.4 and 5.2.

Requires lupa==2.8. Each suite runs in its own process with a bounded timeout.
"""
import argparse
import importlib
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def run_one(version: str, path: str) -> int:
    lua = importlib.import_module("lupa.lua" + version)
    runtime = lua.LuaRuntime()
    runtime.execute("os.exit = function(code) error('__exit__' .. tostring(code), 0) end")
    try:
        runtime.execute(Path(path).read_text(encoding="utf-8-sig"))
    except lua.LuaError as error:
        print(error)
        return 1
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--one", nargs=2, metavar=("VERSION", "SUITE"))
    args = parser.parse_args()
    os.chdir(ROOT)
    if args.one:
        return run_one(*args.one)
    failures = []
    suites = sorted(Path("tests").glob("run_*.lua"))
    sources = sorted(Path("mods").rglob("*.lua")) + [Path("tools/game-autoload.lua")]
    for version in ("54", "52"):
        lua = importlib.import_module("lupa.lua" + version)
        runtime = lua.LuaRuntime()
        compile_source = runtime.eval("function(s,n) local f,e=load(s,n); return f~=nil,e end")
        for path in sources:
            ok, error = compile_source(path.read_text(encoding="utf-8-sig"), str(path))
            if not ok:
                failures.append(f"Lua {version} {path}: {error}")
        print(f"Lua {version}: {len(sources)} sources compiled", flush=True)
        for path in suites:
            try:
                result = subprocess.run(
                    [sys.executable, __file__, "--one", version, str(path)],
                    capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=120,
                )
                print(f"Lua {version} {path.name}: {result.stdout.strip()}", flush=True)
                if result.returncode:
                    failures.append(f"Lua {version} {path}: {result.stderr.strip()}")
            except subprocess.TimeoutExpired:
                failures.append(f"Lua {version} {path}: exceeded 120 seconds")
    for failure in failures:
        print("FAIL:", failure, flush=True)
    print(f"{len(suites)} suites per runtime; {len(failures)} failures", flush=True)
    return int(bool(failures))


if __name__ == "__main__":
    sys.exit(main())
