"""Runs a Lua file with lupa (pip install lupa) for machines without a native Lua interpreter.

Usage: python3 tools/run_lua.py tests/run_tests.lua
"""
import re
import sys

import lupa.lua54 as lua54


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    runtime = lua54.LuaRuntime()
    # os.exit inside lupa would kill Python abruptly; report failures through the return value.
    runtime.execute("os.exit = function(code) error('__exit__' .. tostring(code), 0) end")
    with open(sys.argv[1], encoding="utf-8") as f:
        source = f.read()
    try:
        runtime.execute(source)
    except lua54.LuaError as exc:
        exit_code = re.match(r"__exit__(\d+)", str(exc))
        if exit_code:
            return int(exit_code.group(1))
        print(exc)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
