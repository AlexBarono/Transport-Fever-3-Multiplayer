# Run 21 (probe v21, same-spot test)

- Installed by the owner (git pull + launcher), checked afterwards: clone at `f7b153e`, staging_area `main.PROBE_VERSION = 21`, `nodecfg.lua` present.
- `alut_proxy.ini`: `[net] mode=host port=47800 test=samespot`, DLL v7.
- Session 13:32:31Z to 13:35:10Z, normal shutdown. TF3 was closed when the logs were collected. No new UI error JSON in crash_dump.
- Owner: "das depo an der straße baut er nicht nach" (the depot at the road was not rebuilt).
- Files: `run21-stdout.txt` (complete), `run21-stdout-excerpt.txt` (capture/net/replay/weld/node-config lines plus assertions), `run21-alut_proxy.log` (this session).
