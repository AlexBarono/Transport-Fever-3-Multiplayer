# Run 24 (probe v23, same-spot test: stops, line, bus, demolition)

- Clone/worktree at `4ff21af` (mod v23 installed, `PROBE_VERSION = 23`). `alut_proxy.ini`: `mode=host port=47800 test=samespot`. DLL v7.
- Session 14:02:06Z to 14:06:45Z, normal shutdown. TF3 was not running when the logs were collected.
- Owner: everything worked (stops, a bus line, a bus bought in the depot, a bulldozed road end).
- No assertion and no new crash file in this session.
- Files: `run24-stdout.txt` (complete), `run24-stdout-excerpt.txt`, `run24-alut_proxy.log`.
