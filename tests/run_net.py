"""Real Windows UDP + bridge tests, including loss, duplicate fragments, reconnect and overflow.
Run tests/build_net_tests.bat first, then python tests/run_net.py. Never loads or changes TF3.
"""
import ctypes as c
from pathlib import Path
import shutil
import socket
import tempfile
import threading
import time
import sys
import subprocess

ROOT = Path(__file__).resolve().parents[1]
work = Path(tempfile.mkdtemp(prefix="tf3mp-net-"))

def bind():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("127.0.0.1", 0)); sock.settimeout(.03)
    return sock

host_port_socket = bind(); host_port = host_port_socket.getsockname()[1]; host_port_socket.close()
route_port = host_port
front, back = bind(), bind()
paused = threading.Event()
stopping = threading.Event()
loss = {"fragment": False, "ack": False, "done": False}
order_loss = {b"ORDER": False, b"OACK": False, b"RELEASE": False, b"RACK": False}
order_trace = []
MANIFEST = {"id": "a1" * 16, "game": "b2" * 32, "package": "c3" * 32,
            "mods": "d4" * 32, "save": "e5" * 32, "name": "Det".encode().hex()}

def relay():
    client = None
    while not stopping.is_set():
        for sock in (front, back):
            try: data, address = sock.recvfrom(300000)
            except socket.timeout: continue
            if paused.is_set(): continue
            words = data.split(b" ")
            if len(words) > 2 and words[1] in order_loss:
                if words[1] == b"ORDER": order_trace.append((int(words[2]), words[3], words[4]))
                if not order_loss[words[1]]:
                    order_loss[words[1]] = True; continue
            if b" DONE " in data and not loss["done"]:
                loss["done"] = True; continue
            if sock is front:
                client = address
                if b" FRAG " in data and data.split(b" ", 4)[3] == b"1" and not loss["fragment"]:
                    loss["fragment"] = True; continue
                back.sendto(data, ("127.0.0.1", route_port))
                if b" FRAG " in data: back.sendto(data, ("127.0.0.1", route_port))
            elif client:
                if b" PART " in data and not loss["ack"]: loss["ack"] = True; continue
                front.sendto(data, client)

def dll(role, port, name=None, test="", manifest=MANIFEST, initialize=True):
    folder = work / (name or role); folder.mkdir()
    path = folder / "net_tests.dll"
    shutil.copyfile(ROOT / "native/alut_proxy/build/net_tests.dll", path)
    ini = f"[net]\nmode={role}\nport={port}\nhost=127.0.0.1\ntest={test}\n"
    if manifest is not None: ini += "[session]\n" + "".join(f"{k}={v}\n" for k,v in manifest.items())
    (folder / "alut_proxy.ini").write_text(ini)
    api = c.CDLL(str(path))
    api.mp_send.argtypes = [c.c_char_p]; api.mp_feed.argtypes = [c.c_char_p]
    api.mp_log.argtypes = [c.c_char_p]
    api.mp_part.argtypes = [c.c_char_p, c.c_int]; api.mp_result.argtypes = [c.c_char_p, c.c_char_p]
    api.mp_spooled.restype = c.c_longlong
    api.mp_start()
    if initialize and manifest is not None and not test and role != "loopback":
        source = bytes.fromhex(manifest["name"])
        api.mp_log(b"[2026-10-08 10:00:00Z - MESSAGE - Main] Loading game from file " + source)
        api.mp_feed(b"net reload")
    return api

def status(api):
    buf = c.create_string_buffer(1024); api.mp_status(buf)
    return dict(line.split("=", 1) for line in buf.value.decode().splitlines())

def wait(check, seconds=15):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        if check(): return
        time.sleep(.01)
    raise AssertionError("deadline exceeded")

def receive(api):
    chunks = []; token = None
    def step():
        nonlocal token
        buf = c.create_string_buffer(262209)
        if not api.mp_inbox(buf): return False
        _, current, kind, index, count, text = buf.value.split(b" ", 5)
        if token is None: token = current
        assert token == current and int(index) == len(chunks)
        chunks.append(text); assert api.mp_part(current, int(index)) == 1
        return len(chunks) == int(count)
    wait(step, 45)
    return token, b"".join(chunks)

def free_port():
    sock = bind(); port = sock.getsockname()[1]; sock.close(); return port

def hello(manifest=MANIFEST, runtime="peer-first", ready=1, proto=3):
    fields = " ".join(f"{('sid' if k == 'id' else k)}={manifest[k]}" for k in ("id", "game", "package", "mods", "save"))
    return f"TF3MP/1 HELLO client proto={proto} session={runtime} {fields} ready={ready} order=1".encode()

def send_probe(probe, port, text):
    probe.sendto(text, ("127.0.0.1", port))

def probe_until(probe, port, packet, check, seconds=15):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        if check(): return
        send_probe(probe, port, packet)
        time.sleep(.1)
    raise AssertionError("probe handshake deadline exceeded")

def no_payload(probe, seconds=.25):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        try: text, _ = probe.recvfrom(300000)
        except socket.timeout: continue
        assert b" FRAG " not in text and b" STATE " not in text, text

def await_packet(probe, kind, seconds=5):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        try: text, _ = probe.recvfrom(300000)
        except socket.timeout: continue
        if text.split(b" ")[1] == kind: return text
    raise AssertionError(f"missing {kind!r}")

def allow_host_head(probe, port):
    order = await_packet(probe, b"ORDER"); suffix = order.split(b" ", 2)[2]
    assert suffix.split(b" ")[1] == b"H", order
    send_probe(probe, port, b"TF3MP/1 OACK " + suffix)
    fragment = await_packet(probe, b"FRAG"); token = fragment.split(b" ")[2]
    send_probe(probe, port, b"TF3MP/1 GOT " + token)
    send_probe(probe, port, b"TF3MP/1 DONE " + token + b" OK")
    release = await_packet(probe, b"RELEASE")
    send_probe(probe, port, b"TF3MP/1 RACK " + release.split(b" ", 2)[2])

def send_ordered_line(probe, port, token, text, serial=1):
    send_probe(probe, port, b"TF3MP/1 WANT " + str(serial).encode() + b" " + token)
    order = await_packet(probe, b"ORDER"); suffix = order.split(b" ", 2)[2]
    assert suffix.split(b" ")[1:] == [b"C", token], order
    send_probe(probe, port, b"TF3MP/1 OACK " + suffix)
    send_probe(probe, port, b"TF3MP/1 LINE " + token + b" " + text)

missing = dll("host", free_port(), "missing-session", manifest=None, initialize=False)
assert status(missing)["blocked"] == "1" and status(missing)["prepared"] == "0"
assert "not prepared" in status(missing)["error"]
missing.mp_stop()
for key in ("id", "game", "package", "mods", "save", "name"):
    manifest = dict(MANIFEST); manifest[key] = "z" if key == "name" else manifest[key] + "a"
    invalid = dll("host", free_port(), "invalid-" + key, manifest=manifest, initialize=False)
    assert status(invalid)["blocked"] == "1", key
    invalid.mp_stop()
print("PASS missing/invalid prepared session and overlong fingerprint fields fail closed", flush=True)

port = free_port(); pending_world = dll("host", port, "pending-world", initialize=False); probe = bind()
try:
    assert status(pending_world)["ready"] == "0"
    send_probe(probe,port,b"TF3MP/1 PING " + b"a"*32)
    response=await_packet(probe,b"HEALTH")
    assert response==b"TF3MP/1 HEALTH "+b"a"*32+b" mode=host loaded=0 ready=0 proto=3", response
    assert status(pending_world)["hello_received"]=="0" and status(pending_world)["compatible"]=="0", "health probe changed peer handshake"
    for text in (b"TF3MP/1 LINE early B5 forbidden", b"TF3MP/1 FRAG early 0 1 B5 forbidden",
                 b"TF3MP/1 STATE health ck=1 status=diff fields=stations"):
        send_probe(probe, port, text)
    time.sleep(.15)
    assert status(pending_world)["inbox"] == "0" and status(pending_world)["connected"] == "0"
    assert pending_world.mp_feed(b"Loading game from file Det") == 1
    assert status(pending_world)["ready"] == "0", "mod-tagged text cannot impersonate a world load"
    pending_world.mp_log(b"[2026-10-08 10:00:00Z - MESSAGE - Main] Loading game from file Det")
    assert status(pending_world)["ready"] == "0", "wait for initial world initialization"
    pending_world.mp_feed(b"net reload")
    assert status(pending_world)["ready"] == "1" and status(pending_world)["blocked"] == "0"
    send_probe(probe, port, hello(ready=0)); wait(lambda: status(pending_world)["compatible"] == "1")
    assert status(pending_world)["connected"] == "0"
    intruder = bind()
    try:
        send_probe(intruder, port, hello(runtime="another-port", ready=1))
        time.sleep(.1)
        assert status(pending_world)["blocked"] == "0" and status(pending_world)["peer_ready"] == "0"
    finally:
        intruder.close()
    pending_world.mp_send(b"B5 queued-until-ready")
    pending_world.mp_feed(b"net state health ck=7 status=same fields=stations")
    for text in (b"TF3MP/1 LINE early B5 forbidden", b"TF3MP/1 FRAG early 0 1 B5 forbidden",
                 b"TF3MP/1 STATE health ck=1 status=diff fields=stations"):
        send_probe(probe, port, text)
    no_payload(probe)
    assert status(pending_world)["inbox"] == "0" and status(pending_world)["world_peer"] == "unknown"
    send_probe(probe, port, hello()); wait(lambda: status(pending_world)["connected"] == "1")
    allow_host_head(probe, port)
    send_probe(probe, port, b"TF3MP/1 STATE health ck=7 status=diff fields=stations")
    wait(lambda: status(pending_world)["world_peer"] == "diff")
    assert status(pending_world)["world"] == "same" and status(pending_world)["world_ck"] == "7"
    assert status(pending_world)["world_fields"] == "stations"
    send_ordered_line(probe, port, b"after-ready", b"B5 allowed")
    token, text = receive(pending_world); assert token == b"after-ready" and text == b"B5 allowed"
    pending_world.mp_result(token, b"OK")
    send_probe(probe, port, hello(ready=0)); wait(lambda: status(pending_world)["connected"] == "0")
    assert status(pending_world)["world_peer"] == "unknown"
finally:
    pending_world.mp_stop(); probe.close()
print("PASS no gameplay before HELLO and both loaded worlds; health status exposes and clears peer comparison", flush=True)

for key, reason in (("id", "session differs"), ("game", "game build differs"),
                    ("package", "package differs"), ("mods", "mods differ"), ("save", "source save differs")):
    port = free_port(); gated = dll("host", port, "different-" + key); probe = bind()
    try:
        changed = dict(MANIFEST); changed[key] = ("f" * len(changed[key]))
        send_probe(probe, port, hello(changed)); wait(lambda: status(gated)["blocked"] == "1")
        assert reason in status(gated)["error"], status(gated)
        send_probe(probe, port, hello())
        send_probe(probe, port, b"TF3MP/1 LINE bypass B5 forbidden")
        time.sleep(.1)
        assert status(gated)["connected"] == "0" and status(gated)["inbox"] == "0"
        assert reason in status(gated)["error"], "matching later HELLO cannot clear a failed session"
    finally:
        gated.mp_stop(); probe.close()

for suffix, packet in (("old", b"TF3MP/1 HELLO client proto=2 session=old"),
                       ("test-downgrade", b"TF3MP/1 HELLO client proto=2 test=fakehost session=old"),
                       ("missing", b"TF3MP/1 HELLO client proto=3 session=first"),
                       ("duplicate", hello() + b" ready=1")):
    port = free_port(); gated = dll("host", port, "bad-hello-" + suffix); probe = bind()
    try:
        send_probe(probe, port, packet); wait(lambda: status(gated)["blocked"] == "1")
        assert status(gated)["connected"] == "0"
    finally:
        gated.mp_stop(); probe.close()
print("PASS every compatibility fingerprint, old/malformed protocol and downgrade fail-stop", flush=True)

port = free_port(); halted = dll("host", port, "halt-inbox"); probe = bind()
try:
    send_probe(probe, port, hello()); wait(lambda: status(halted)["connected"] == "1")
    send_ordered_line(probe, port, b"held", b"B5 not-yet-delivered")
    wait(lambda: status(halted)["inbox"] == "1")
    changed = dict(MANIFEST); changed["game"] = "f" * 64
    send_probe(probe, port, hello(changed)); wait(lambda: status(halted)["blocked"] == "1")
    assert not halted.mp_inbox(c.create_string_buffer(262209)), "blocked session must not offer queued work to Lua"
    assert halted.mp_result(b"held", b"FAIL")
    assert "game build differs" in status(halted)["error"], "execution failure must retain original compatibility reason"
finally:
    halted.mp_stop(); probe.close()
print("PASS compatibility fail-stop also holds queued Lua delivery and retains the original reason", flush=True)

for suffix, initial, later in (("wrong", b"Other save", None), ("missing", None, None),
                               ("again", b"Det", b"Det")):
    gated = dll("host", free_port(), "world-" + suffix, initialize=False)
    if initial is not None: gated.mp_log(b"Loading game from file " + initial)
    gated.mp_feed(b"net reload")
    if later is not None:
        assert status(gated)["ready"] == "1"
        gated.mp_log(b"Loading game from file " + later); gated.mp_feed(b"net reload")
    assert status(gated)["blocked"] == "1" and status(gated)["ready"] == "0", status(gated)
    gated.mp_stop()
unicode_manifest = dict(MANIFEST); unicode_manifest["name"] = "Bänhöfe und Züge".encode().hex()
unicode_world = dll("host", free_port(), "unicode-world", manifest=unicode_manifest)
assert status(unicode_world)["ready"] == "1" and status(unicode_world)["blocked"] == "0"
unicode_world.mp_feed(b"net reload")
assert status(unicode_world)["blocked"] == "1", "later reload without a loading log also blocks"
unicode_world.mp_stop()
print("PASS matching UTF8 source name, wrong/missing source and later reload guard", flush=True)

fresh = dll("host", free_port(), "world-no-legacy", initialize=False)
fresh.mp_log(b"Loading game from file Det")
token = c.create_string_buffer(64); fresh.mp_world(token)
assert token.value and status(fresh)["loaded"] == "1" and status(fresh)["initialized"] == "0"
fresh.mp_feed(b"net initialized wrong-token")
assert status(fresh)["ready"] == "0", "stale/wrong world token cannot initialize a world"
for _ in range(3): fresh.mp_feed(b"net initialized " + token.value)
assert status(fresh)["ready"] == "1" and status(fresh)["blocked"] == "0"
fresh.mp_feed(b"net reload")
assert status(fresh)["blocked"] == "0", "late legacy notification double-counted initialization"
fresh.mp_log(b"Loading game from file Det")
fresh.mp_feed(b"net initialized " + token.value)
assert status(fresh)["blocked"] == "1" and status(fresh)["ready"] == "0", "real reload must still stop"
fresh.mp_stop()
print("PASS first world without handleLegacy, duplicate/stale acknowledgements and real reload guard", flush=True)

port = free_port(); restarted = dll("host", port, "real-peer-restart"); probe = bind()
try:
    send_probe(probe, port, hello()); wait(lambda: status(restarted)["connected"] == "1")
    send_probe(probe, port, hello(runtime="peer-restarted"))
    wait(lambda: status(restarted)["blocked"] == "1")
    assert "peer restarted" in status(restarted)["error"]
finally:
    restarted.mp_stop(); probe.close()
fresh_manifest = dict(MANIFEST); fresh_manifest["id"] = "f6" * 16
fresh_port = free_port()
fresh_host = dll("host", fresh_port, "fresh-host", manifest=fresh_manifest)
upper_manifest = {k: (v.upper() if k != "name" else v) for k,v in fresh_manifest.items()}
fresh_client = dll("client", fresh_port, "fresh-client", manifest=upper_manifest)
try:
    wait(lambda: status(fresh_host)["connected"] == "1" and status(fresh_client)["connected"] == "1")
    assert fresh_client.mp_send(b"B5 new-prepared-session")
    token, text = receive(fresh_host); assert text == b"B5 new-prepared-session"
    assert fresh_host.mp_result(token, b"OK")
    wait(lambda: status(fresh_client)["outbox"] == "0")
finally:
    fresh_client.mp_stop(); fresh_host.mp_stop()
print("PASS real peer restart fail-stop and recovery through a new prepared session; hex case normalization", flush=True)

probe = bind(); guarded_client = dll("client", probe.getsockname()[1], "guarded-order-client")
try:
    while True:
        packet, address = probe.recvfrom(300000)
        if packet.split(b" ")[1] == b"HELLO": break
    probe.sendto(hello().replace(b"HELLO client", b"HELLO host"), address)
    wait(lambda: status(guarded_client)["connected"] == "1")
    assert guarded_client.mp_send(b"B5 client-first") and guarded_client.mp_send(b"B5 client-second")
    want = await_packet(probe, b"WANT"); own_token = want.split(b" ")[3]
    invalid = (b"0 C " + own_token, b"2 C " + own_token, b"4294967296 C " + own_token,
               b"000000000000001 C " + own_token, b"1 X " + own_token, b"1 C wrong-head",
               b"1 C " + own_token + b" extra")
    for suffix in invalid: probe.sendto(b"TF3MP/1 ORDER " + suffix, address)
    no_payload(probe)
    assert status(guarded_client)["order_seq"] == "0" and status(guarded_client)["order_phase"] == "idle"
    suffix = b"1 C " + own_token
    probe.sendto(b"TF3MP/1 ORDER " + suffix, address)
    assert await_packet(probe, b"OACK").endswith(suffix)
    assert await_packet(probe, b"FRAG").split(b" ")[2] == own_token
    for bad in (b"2 H later", b"1 H changed-token", b"0 C stale"):
        probe.sendto(b"TF3MP/1 ORDER " + bad, address)
    time.sleep(.1)
    assert status(guarded_client)["order_seq"] == "1" and status(guarded_client)["order_side"] == "C"
    probe.sendto(b"TF3MP/1 RELEASE " + suffix, address)
    assert await_packet(probe, b"RACK").endswith(suffix)
    assert status(guarded_client)["outbox"] == "1"
    probe.sendto(b"TF3MP/1 ORDER 1 H stale", address)
    probe.sendto(b"TF3MP/1 RELEASE 1 C wrong-token", address)
    probe.sendto(b"TF3MP/1 ORDER 2 H incoming-host", address)
    assert await_packet(probe, b"OACK").endswith(b"2 H incoming-host")
    probe.sendto(b"TF3MP/1 LINE wrong-host B5 forbidden", address)
    probe.sendto(b"TF3MP/1 RELEASE 2 H incoming-host", address)
    time.sleep(.1)
    assert status(guarded_client)["inbox"] == "0" and status(guarded_client)["order_phase"] == "active"
    probe.sendto(b"TF3MP/1 LINE incoming-host B5 allowed", address)
    token, text = receive(guarded_client); assert token == b"incoming-host" and text == b"B5 allowed"
    assert guarded_client.mp_result(token, b"OK")
    probe.sendto(b"TF3MP/1 RELEASE 2 H incoming-host", address)
    assert await_packet(probe, b"RACK").endswith(b"2 H incoming-host")
    assert status(guarded_client)["order_phase"] == "idle" and status(guarded_client)["outbox"] == "1"
finally:
    guarded_client.mp_stop(); probe.close()
print("PASS malformed/stale/premature ORDER and RELEASE cannot replace the active permit or execute another token", flush=True)

port = free_port(); guarded_host = dll("host", port, "guarded-order-host"); probe = bind()
try:
    send_probe(probe, port, hello()); wait(lambda: status(guarded_host)["connected"] == "1")
    guarded_host.mp_send(b"B5 host-first")
    selected = await_packet(probe, b"ORDER"); suffix = selected.split(b" ", 2)[2]; token = suffix.split(b" ")[2]
    send_probe(probe, port, b"TF3MP/1 OACK 1 H wrong-token")
    send_probe(probe, port, b"TF3MP/1 RACK " + suffix)
    no_payload(probe)
    assert status(guarded_host)["order_phase"] == "ack"
    send_probe(probe, port, b"TF3MP/1 OACK " + suffix)
    assert await_packet(probe, b"FRAG").split(b" ")[2] == token
    send_probe(probe, port, b"TF3MP/1 WANT 1 waiting-client")
    guarded_host.mp_send(b"B5 host-second")
    send_probe(probe, port, b"TF3MP/1 DONE " + token + b" OK")
    release = await_packet(probe, b"RELEASE")
    send_probe(probe, port, b"TF3MP/1 RACK 2 H wrong")
    time.sleep(.1); assert status(guarded_host)["order_phase"] == "finish"
    send_probe(probe, port, b"TF3MP/1 RACK " + release.split(b" ", 2)[2])
    second = await_packet(probe, b"ORDER"); assert second.endswith(b"2 C waiting-client"), second
    send_probe(probe, port, b"TF3MP/1 WANT 999 injected-client")
    send_probe(probe, port, b"TF3MP/1 WANT 1 changed-client")
    send_probe(probe, port, b"TF3MP/1 LINE waiting-client B5 early")
    time.sleep(.1)
    assert status(guarded_host)["inbox"] == "0" and status(guarded_host)["order_token"] == "waiting-client"
    send_probe(probe, port, b"TF3MP/1 OACK 2 C waiting-client")
    send_probe(probe, port, b"TF3MP/1 LINE waiting-client B5 allowed")
    incoming, _ = receive(guarded_host); guarded_host.mp_result(incoming, b"OK")
    release = await_packet(probe, b"RELEASE")
    send_probe(probe, port, b"TF3MP/1 RACK " + release.split(b" ", 2)[2])
    assert await_packet(probe, b"ORDER").split(b" ")[2:4] == [b"3", b"H"]
finally:
    guarded_host.mp_stop(); probe.close()
print("PASS host OACK/RACK gates, fair pending-direction selection and stale/future WANT guards", flush=True)

internet_fixture = None
if "--internet" in sys.argv:
    ready, stop = work / "internet-ready.txt", work / "internet-stop.txt"
    internet_fixture = subprocess.Popen(["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", str(ROOT / "tests/internet_fixture.ps1"), "-HostPort", str(host_port),
        "-ReadyFile", str(ready), "-StopFile", str(stop)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        wait(lambda: ready.exists() or internet_fixture.poll() is not None)
        assert ready.exists(), internet_fixture.communicate(timeout=2)
        route_port = int(ready.read_text(encoding="utf-8-sig"))
    except BaseException:
        internet_fixture.terminate(); internet_fixture.wait(timeout=5); raise
    print("Testing native action ordering through an IPv6 TLS Internet tunnel", flush=True)
thread = threading.Thread(target=relay, daemon=True); thread.start()
host = dll("host", host_port); client = dll("client", front.getsockname()[1])
try:
    wait(lambda: status(host)["connected"] == "1")
    for index in range(8): assert host.mp_send(f"B5 H{index}".encode())
    for index in range(8): assert client.mp_send(f"B5 C{index}".encode())
    delivered = []; fifo = {b"H": 0, b"C": 0}
    for sequence in range(1, 17):
        ready = []
        def one_ready():
            ready.clear()
            for target, side in ((client, b"H"), (host, b"C")):
                buf = c.create_string_buffer(262209)
                if target.mp_inbox(buf): ready.append((target, side, buf.value))
            return bool(ready)
        wait(one_ready)
        assert len(ready) == 1, "both replay directions must never become visible at once"
        target, side, value = ready[0]
        _, token, kind, part, count, text = value.split(b" ", 5)
        assert part == b"0" and count == b"1" and text == b"B5 " + side + str(fifo[side]).encode()
        fifo[side] += 1; delivered.append(side)
        assert status(host)["order_seq"] == str(sequence) and status(client)["order_seq"] == str(sequence)
        assert status(host)["order_phase"] == "active"
        other = host if target is client else client
        # Until the actual game result arrives, neither next direction nor FIFO successor can execute.
        for _ in range(3):
            assert not other.mp_inbox(c.create_string_buffer(262209)); time.sleep(.02)
        assert target.mp_part(token, 0) and target.mp_result(token, b"OK")
    wait(lambda: status(host)["outbox"] == "0" and status(client)["outbox"] == "0" and status(host)["order_phase"] == "idle")
    assert delivered == [b"H", b"C"] * 8, delivered
    assert all(order_loss.values()), order_loss
    unique = []
    for record in order_trace:
        if not unique or unique[-1] != record: unique.append(record)
    assert [record[0] for record in unique] == list(range(1, 17)), unique
    assert [record[1] for record in unique] == delivered
    print("PASS simultaneous two-way FIFO and fair host order: one global replay, lost ORDER/OACK/RELEASE/RACK", flush=True)
    values = {b"gui": b"g", b"sim": b"s", b"health": b"status=same ck=1 fields=none",
              b"resync": b"r", b"clock": b"t=" + b"x" * 1021, b"testaa": b"a", b"testbb": b"b", b"testcc": b"c"}
    for key, value in values.items(): assert client.mp_feed(b"net state " + key + b" " + value)
    received_states = {}
    def all_states():
        key = c.create_string_buffer(12); value = c.create_string_buffer(1024)
        while host.mp_peer_state(key, value): received_states[key.value] = value.value
        return len(received_states) == len(values)
    wait(all_states)
    assert received_states == values
    print("PASS eight state channels including 1023-byte CLOCK payload without truncation", flush=True)
    assert client.mp_feed(b"snapshot name=net send B5 injected") == 1
    assert status(client)["outbox"] == "0", "log text must never be interpreted as a command"
    text = b"B5 " + b"x" * 262141
    # Exercise real stdout upload assembly as well as UDP and inbound environment chunks.
    count = (len(text) + 5999) // 6000
    for index in range(count):
        assert client.mp_feed(f"net upload large {index} {count} ".encode() + text[index*6000:(index+1)*6000]) == 1
    token, received = receive(host)
    assert received == text
    assert status(client)["outbox"] == "1", "GOT must not count as applied"
    assert host.mp_result(token, b"OK") == 1
    wait(lambda: status(client)["outbox"] == "0")
    assert all(loss.values()), loss
    print("PASS 256 KiB, duplicate/lost fragments and lost result ACK; receipt != applied", flush=True)

    assert client.mp_feed(b"net state health ck=8 status=same fields=none")
    wait(lambda: status(host)["world_peer"] == "same")
    paused.set(); time.sleep(10.3)
    assert status(client)["connected"] == "0"
    assert status(host)["world_peer"] == "unknown", "expired peer health cannot remain green"
    for index in range(140): assert client.mp_send(f"B5 {index}".encode()) == 1
    assert status(client)["outbox"] == "128" and client.mp_spooled() > 0
    paused.clear()
    for index in range(140):
        token, received = receive(host)
        assert received == f"B5 {index}".encode(), (index, received)
        assert host.mp_result(token, b"OK") == 1
        # Every pump is what the bridge thread does while continuing to read result messages.
        for _ in range(2): client.mp_pump(); time.sleep(.005)
    wait(lambda: status(client)["outbox"] == "0")
    assert client.mp_spooled() == 0
    print("PASS reconnect, 140 ordered actions, disk backpressure, no loss or duplicates", flush=True)

    assert client.mp_send(b"B5 reject") and client.mp_send(b"B5 must-wait")
    token, received = receive(host); assert received == b"B5 reject"
    assert host.mp_result(token, b"FAIL")
    wait(lambda: status(client)["blocked"] == "1")
    assert status(client)["outbox"] == "2"
    time.sleep(.6); buf = c.create_string_buffer(262209)
    assert not host.mp_inbox(buf), "dependent actions must not run after a failed command"
    print("PASS failed game result blocks dependent actions", flush=True)

    # v13: in-game resync. Both launchers ask their game to load the resync save; each DLL drops
    # the old actions when its game loads it, and the peers wait for each other in the new epoch.
    folder = {"host": work / "host", "client": work / "client"}
    (folder["client"] / "alut_proxy.reload").write_text("name=TF3MP-Neuabgleich\r\n")
    client.mp_requests()
    assert status(client)["resync"] == "armed" and not (folder["client"] / "alut_proxy.reload").exists()
    client.mp_log(b"[2026-10-08 10:05:00Z - MESSAGE - Main] Loading game from file TF3MP-Neuabgleich")
    st = status(client)
    assert st["epoch"] == "1" and st["resync"] == "-" and st["blocked"] == "0" and st["outbox"] == "0", st
    client.mp_feed(b"net reload")
    assert status(client)["error"] == "" and status(client)["ready"] == "1"
    assert client.mp_send(b"B5 after-resync")
    time.sleep(2.5)
    assert status(host)["inbox"] == "0", "nothing travels until both games are in the same epoch"
    # Another save is no resync; a wrong name is refused.
    (folder["host"] / "alut_proxy.reload").write_text("name=..\\other")
    host.mp_requests(); assert status(host)["resync"] == "-"
    (folder["host"] / "alut_proxy.reload").write_text("name=TF3MP-Neuabgleich")
    host.mp_requests(); assert status(host)["resync"] == "armed"
    host.mp_log(b"[2026-10-08 10:05:01Z - MESSAGE - Main] Loading game from file TF3MP-Neuabgleich")
    host.mp_feed(b"net reload")
    st = status(host); assert st["epoch"] == "1" and st["blocked"] == "0" and st["inbox"] == "0", st
    token, received = receive(host); assert received == b"B5 after-resync", received
    assert host.mp_result(token, b"OK")
    wait(lambda: status(client)["outbox"] == "0")
    assert host.mp_send(b"B5 host-after-resync")
    token, received = receive(client); assert received == b"B5 host-after-resync"
    assert client.mp_result(token, b"OK")
    wait(lambda: status(host)["outbox"] == "0")
    # The partner's launcher request reaches this launcher through the DLL status.
    assert status(host)["resync_peer"] == ""
    assert client.mp_feed(b"net state resync ck=0 req=4")
    wait(lambda: status(host)["resync_peer"] == "4")
    # A save request for the host's game, and a later load of another save still blocks.
    (folder["host"] / "alut_proxy.save").write_text("")
    host.mp_requests(); assert not (folder["host"] / "alut_proxy.save").exists()
    print("PASS in-game resync: old actions dropped, epochs wait for each other, fresh order afterwards", flush=True)
    probe = bind(); probe.sendto(b"TF3MP/1 HELLO client proto=2 session=intruder", ("127.0.0.1",host_port))
    time.sleep(.1)
    assert "peer restarted" not in status(host)["error"], "another endpoint must not take over the session"
    port_socket=bind(); new_port=port_socket.getsockname()[1]; port_socket.close()
    other=dll("host",new_port,"compatibility",test="fakehost",manifest=None)
    # DLL startup creates its socket asynchronously. Real peers retry HELLO too.
    probe_until(probe, new_port, b"TF3MP/1 HELLO client proto=1", lambda: "old protocol" in status(other)["error"])
    probe.sendto(b"TF3MP/1 HELLO client proto=2 session=first",("127.0.0.1",new_port))
    wait(lambda: status(other)["connected"]=="1")
    assert not status(other)["error"]
    probe.sendto(b"TF3MP/1 HELLO client proto=2 session=restarted",("127.0.0.1",new_port))
    wait(lambda: "peer restarted" in status(other)["error"])
    assert status(other)["blocked"]=="1"
    other.mp_stop(); probe.close()
    loop=dll("loopback",0,"reload")
    assert loop.mp_send(b"B5 pending")
    assert loop.mp_feed(b"net reload")
    assert status(loop)["blocked"]=="1" and status(loop)["inbox"]=="0"
    loop.mp_stop()
    port_socket=bind(); test_port=port_socket.getsockname()[1]; port_socket.close()
    spot=dll("host",test_port,"same-spot",test="samespot")
    assert spot.mp_send(b"B5 recording")
    assert spot.mp_feed(b"net reload")
    assert status(spot)["outbox"]=="0" and status(spot)["blocked"]=="0"
    spot.mp_stop()
    print("PASS endpoint pinning, version checks, restart/reload guard and same-spot compatibility", flush=True)
finally:
    client.mp_stop(); host.mp_stop(); stopping.set(); thread.join(timeout=1)
    front.close(); back.close()
    if internet_fixture:
        stop.write_text("stop")
        try: internet_fixture.communicate(timeout=5)
        except subprocess.TimeoutExpired: internet_fixture.terminate(); internet_fixture.communicate(timeout=5)
    print(f"Test files: {work}", flush=True)
