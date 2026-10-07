# Run 22 (probe v22, same-spot test)

- Clone at `5d00f16`, installed `main.PROBE_VERSION = 22` (14 files, 10 modules). `alut_proxy.ini`: `mode=host port=47800 test=samespot`. DLL v7.
- Session 13:44:12Z to 13:45:44Z, ended with an ungraceful exit (fatal assert). TF3 was not running when the logs were collected.
- Owner: the depot was rebuilt and connected to the road. Afterwards TF3 died with "Assertion `it != components.end()` failed, Entity: 50833 ... Component Type Index: 3", while the EntityDetailsTool was open.
- Crash files of this session: `d3f427e4-d311-4cde-8715-4c4a5b9e3433_0.dmp` (820698 bytes, not uploaded), `_1.txt` (813560 bytes, a copy of stdout, not uploaded), `_3.json` (uploaded as `run22-d3f427e4-..._3.json`; minidumpId 772d8299-c816-436a-be37-5c173aeb6c73, ecs::Engine::GetComponentDataIndex, Engine.h:323).
- Files: `run22-stdout.txt` (complete), `run22-stdout-excerpt.txt` (key lines, every line mentioning 50833, and the 80 lines before the fatal error to the end), `run22-alut_proxy.log`.
