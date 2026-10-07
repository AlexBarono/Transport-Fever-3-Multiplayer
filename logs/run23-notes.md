# Run 23 (probe v23, same-spot test)

- Clone at `0923713`, installed `main.PROBE_VERSION = 23`. `alut_proxy.ini`: `mode=host port=47800 test=samespot`. DLL v7.
- Session 13:54:41Z to 13:59:37Z, normal shutdown. TF3 was not running when the logs were collected.
- Owner: "es hat alles geklappt". The depot was rebuilt at the same spot and connected, with no crash when clicking.
- No assertion and no new crash file in this session (the only recent non-.dmp files in crash_dump are from run 22).
- Two builds were recorded twice: road and depot at 13:56, then again at 13:57. Only the second pair, `gs1791381509.1/.2`, was replayed.
- Files: `run23-stdout.txt` (complete), `run23-stdout-excerpt.txt`, `run23-alut_proxy.log`.
