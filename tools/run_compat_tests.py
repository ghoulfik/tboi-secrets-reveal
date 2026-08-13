#!/usr/bin/env python3
"""Checks that Secrets Reveal behaves correctly with and without the optional
Guaranteed Crawlspaces integration.

Secrets Reveal finds a room's buried crawlspace through the engine's
Room:GetDungeonRockIdx(). Guaranteed Crawlspaces usually plants its rock on that
same index, but when the index is unusable it moves the crawlspace and publishes
where it went. Secrets Reveal consults that, nil-checked.

Since the whole point of a nil check is what happens when it fails, this loads
main.lua unmodified under stubs and drives it five ways: the integration absent,
present and reporting a moved rock, present and reporting nothing, present and
throwing, and present and returning nonsense.

    pip install lupa
    python tools/run_compat_tests.py
"""

import os
import sys

try:
    from lupa import LuaRuntime
except ImportError:
    sys.exit("lupa is not installed.  pip install lupa")

HERE = os.path.dirname(os.path.abspath(__file__))
HARNESS = os.path.join(HERE, "compat_harness.lua")
MAIN = os.path.join(os.path.dirname(HERE), "main.lua")


def main():
    if not os.path.exists(MAIN):
        sys.exit("main.lua not found next to tools/")

    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("arg = {}")
    run = lua.eval("function(harness, target)"
                   "  local chunk, err = loadfile(harness)"
                   "  if chunk == nil then error(err) end"
                   "  return chunk(target)"
                   "end")
    try:
        run(HARNESS.replace("\\", "/"), MAIN.replace("\\", "/"))
    except SystemExit:
        raise
    except Exception as exc:
        print("LUA ERROR:", exc)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
