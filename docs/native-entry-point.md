# Nativer Einstiegspunkt (Phase 0, Schritt 3)

Read-only-Analyse der TF3-Installation (`steamapps\common\Transport Fever 3`) vom 06.10.2026. Im Spielordner wurde nichts verändert. Die Import-Tabellen wurden mit einem eigenen PowerShell-PE-Parser gelesen (kein pefile).

## Ergebnis in Kürze

- **`alut.dll` gibt es auch in TF3**, sie liegt im Spielordner und wird von `TransportFever3.exe` statisch importiert. Der TF2-Ansatz (Proxy-`alut.dll`) ist damit grundsätzlich übertragbar.
- Das Spiel importiert aus `alut.dll` nur **6 Funktionen**. `alut.dll` selbst exportiert 20 und hängt nur an `OpenAL32.dll` und der CRT. Ein Proxy muss also nur wenige Funktionen weiterleiten.
- Weitere Kandidaten aus dem Spielordner: `OpenAL32.dll`, `SDL2.dll`, `PDXSDK.dll`, `steam_api64.dll`, `icuin61.dll`, `icuuc61.dll`, `MSVCP140.dll`, `VCRUNTIME140.dll`, `VCRUNTIME140_1.dll`. `alut.dll` ist mit Abstand der kleinste und risikoärmste.
- **Kein Anti-Cheat gefunden** (kein EasyAntiCheat, kein BattlEye, kein Denuvo, keine `*.sig`-Dateien).
- **Steam-DRM:** `TransportFever3.exe` hat eine `.bind`-Sektion, typisch für den SteamStub-Wrapper. Er entschlüsselt die exe beim Start; normale Proxy-DLLs im Spielordner sind davon erfahrungsgemäß nicht betroffen.
- **Signaturen:** `TransportFever3.exe` und `alut.dll` sind von Urban Games GmbH signiert (gültig). Das Spiel prüft die Signatur der DLLs beim Laden nach bisherigem Wissen nicht. Das muss ein echter Test mit einer Proxy-DLL bestätigen.

## Vom Spiel genutzte Funktionen aus alut.dll

```
alutExit
alutInitWithoutContext
alutCreateBufferFromFileImage
alutInit
alutGetError
alutGetErrorString
```

`alut.dll` exportiert insgesamt 20 Funktionen. Ein Proxy sollte alle 20 weiterleiten (z. B. an eine umbenannte `alut_orig.dll`).

Imports von `alut.dll`:

```
OpenAL32.dll
KERNEL32.dll
VCRUNTIME140.dll
api-ms-win-crt-*.dll (heap, environment, stdio, filesystem, string, utility, math, runtime)
```

## Imports von TransportFever3.exe

Keine Delay-Imports. `GAMEFOLDER` = DLL liegt im Spielordner (Proxy-Kandidat), `system32` = Windows-DLL, `apiset` = Windows-API-Set.

```
DLL                                 Herkunft    Funktionen
alut.dll                            GAMEFOLDER    6
OpenAL32.dll                        GAMEFOLDER   29
SDL2.dll                            GAMEFOLDER   80
PDXSDK.dll                          GAMEFOLDER   95
steam_api64.dll                     GAMEFOLDER   10
icuin61.dll                         GAMEFOLDER  122
icuuc61.dll                         GAMEFOLDER   55
MSVCP140.dll                        GAMEFOLDER  402
VCRUNTIME140.dll                    GAMEFOLDER   24
VCRUNTIME140_1.dll                  GAMEFOLDER    1
ADVAPI32.dll                        system32      8
KERNEL32.dll                        system32    128
ntdll.dll                           system32      3
ole32.dll                           system32      4
OPENGL32.dll                        system32      1
PSAPI.DLL                           system32      1
SHELL32.dll                         system32      4
USER32.dll                          system32      2
WINHTTP.dll                         system32     14
WS2_32.dll                          system32     21
api-ms-win-crt-convert-l1-1-0.dll   apiset        7
api-ms-win-crt-environment-l1-1-0   apiset        1
api-ms-win-crt-filesystem-l1-1-0    apiset        4
api-ms-win-crt-heap-l1-1-0.dll      apiset        8
api-ms-win-crt-locale-l1-1-0.dll    apiset        4
api-ms-win-crt-math-l1-1-0.dll      apiset       54
api-ms-win-crt-runtime-l1-1-0.dll   apiset       26
api-ms-win-crt-stdio-l1-1-0.dll     apiset       38
api-ms-win-crt-string-l1-1-0.dll    apiset       22
api-ms-win-crt-time-l1-1-0.dll      apiset        9
api-ms-win-crt-utility-l1-1-0.dll   apiset        3
```

## Sektionen von TransportFever3.exe

```
.text    VA=0x1000     size=0x3662F9C
.rdata   VA=0x3664000  size=0x64F300
.data    VA=0x3CB4000  size=0x4548D8
.pdata   VA=0x4109000  size=0x1983E4
_RDATA   VA=0x42A2000  size=0x210
.rsrc    VA=0x42A3000  size=0x423D8
.reloc   VA=0x42E6000  size=0x2B3E4
.bind    VA=0x4312000  size=0x39248    <- SteamStub (Steam-DRM)
```

## Alle .exe und .dll im Installationsordner

Pfad, Größe in Bytes, FileVersion, ProductName (leer = keine Versionsinfo).

```
TransportFever3.exe                          69711288
alut.dll                                        78192
Compressonator_MD_DLL.dll                     1304432
Compressonator_MT_DLL.dll                     1497456
concrt140.dll                                  322640  14.42.34433.0         Microsoft Visual Studio
EncodeWith_DXC.dll                            1485680
EncodeWith_GPU.dll                             683888
EncodeWith_OCL.dll                            1473904
icudt61.dll                                  26901360  61, 1, 0, 0           International Components for Unicode
icuin61.dll                                   2966384  61, 1, 0, 0           International Components for Unicode
icuuc61.dll                                   1999216  61, 1, 0, 0           International Components for Unicode
msvcp140.dll                                   575592  14.42.34433.0         Microsoft Visual Studio
msvcp140_1.dll                                  35944  14.42.34433.0         Microsoft Visual Studio
msvcp140_2.dll                                 267880  14.42.34433.0         Microsoft Visual Studio
msvcp140_atomic_wait.dll                        50256  14.42.34433.0         Microsoft Visual Studio
msvcp140_codecvt_ids.dll                        31824  14.42.34433.0         Microsoft Visual Studio
nvtt.dll                                       711024  2, 1, 0, 0            NVIDIA Texture Tools Dynamic Link Library
OpenAL32.dll                                  2047856  1.22.2                OpenAL Soft
PDXSDK.dll                                    2658672
SDL2.dll                                      3143536  2, 32, 8, 0           Simple DirectMedia Layer
steam_api64.dll                                319584  09.31.86.04           Steam Client API
vccorlib140.dll                                351824  14.42.34433.0         Microsoft Visual Studio
vcruntime140.dll                               120432  14.42.34433.0         Microsoft Visual Studio
vcruntime140_1.dll                              49744  14.42.34433.0         Microsoft Visual Studio
vcruntime140_threads.dll                        38504  14.42.34433.0         Microsoft Visual Studio
model_editor\ModelEditor.exe                 13084016
model_editor\plugins\FbxImportPlugin.dll      2087792
model_editor\plugins\icudt61.dll             26891776  61, 1, 0, 0           International Components for Unicode
model_editor\plugins\icuin61.dll              2956800  61, 1, 0, 0           International Components for Unicode
model_editor\plugins\icuuc61.dll              1990144  61, 1, 0, 0           International Components for Unicode
model_editor\plugins\libfbxsdk.dll            8000288  2020.3.7 Release (0)  FBX SDK
model_editor\plugins\SpeedTreeConvPlugin.dll  1244016
```

Weitere Einträge auf oberster Ebene: `api\`, `base\`, `mods\`, `vscode-template\`, `LICENSE.txt`, `ModelEditor.bat`.

## Anti-Cheat und Integrität

- Gesucht nach: EasyAntiCheat, BattlEye, Denuvo, `*.sig`, Launcher, DRM, Crash-Handler.
- Gefunden: nur `steam_api64.dll` (Steam Client API) und die `.bind`-Sektion (SteamStub) in der exe.
- Kein Anti-Cheat, keine Signaturdateien, kein separater Launcher.

## Nächste Schritte

1. Proxy-`alut.dll` bauen, die alle 20 Exporte an die Original-DLL weiterleitet und in `DllMain` nur eine Logzeile schreibt.
2. Testen, ob TF3 mit der Proxy-DLL normal startet (SteamStub, Signaturprüfung).
3. Erst danach Netzwerk-Code in die DLL einbauen.

## Testergebnis Proxy-DLL (06.10.2026)

Quelltext: `native/alut_proxy`. Installiert als `alut.dll`, Original als `alut_orig.dll`.

- TF3 startet und läuft normal mit dem Proxy (Spielstand geladen, Ton funktioniert).
- Im laufenden Prozess sind `alut.dll` (Proxy) und `alut_orig.DLL` geladen. Die Weiterleitung funktioniert.
- SteamStub und die Signaturen verhindern den Austausch nicht.
- `DllMain` läuft: Proxy v2 hat `loaded` und `unloaded` in `alut_proxy.log` im Spielordner geschrieben.
- Im Spielprozess fehlt offenbar `LOCALAPPDATA` (v1 konnte dorthin nicht loggen). Eigene Dateien deshalb relativ zur DLL ablegen.

```
2026-10-06 13:51:41 alut proxy v2 loaded pid=29388
2026-10-06 13:51:59 alut proxy v2 unloaded pid=29388
```
