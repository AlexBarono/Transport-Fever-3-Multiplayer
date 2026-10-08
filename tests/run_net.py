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

ROOT = Path(__file__).resolve().parents[1]
work = Path(tempfile.mkdtemp(prefix="tf3mp-net-"))

def bind():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("127.0.0.1", 0)); sock.settimeout(.03)
    return sock

host_port_socket = bind(); host_port = host_port_socket.getsockname()[1]; host_port_socket.close()
front, back = bind(), bind()
paused = threading.Event()
stopping = threading.Event()
loss = {"fragment": False, "ack": False, "done": False}
MANIFEST = {"id": "a1" * 16, "game": "b2" * 32, "package": "c3" * 32,
            "mods": "d4" * 32, "save": "e5" * 32, "name": "Det".encode().hex()}

def relay():
    client = None
    while not stopping.is_set():
        for sock in (front, back):
            try: data, address = sock.recvfrom(300000)
            except socket.timeout: continue
            if paused.is_set(): continue
            if sock is front:
                client = address
                if b" FRAG " in data and data.split(b" ", 4)[3] == b"1" and not loss["fragment"]:
                    loss["fragment"] = True; continue
                back.sendto(data, ("127.0.0.1", host_port))
                if b" FRAG " in data: back.sendto(data, ("127.0.0.1", host_port))
            elif client:
                if b" PART " in data and not loss["ack"]: loss["ack"] = True; continue
                if b" DONE " in data and not loss["done"]: loss["done"] = True; continue
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
    return f"TF3MP/1 HELLO client proto={proto} session={runtime} {fields} ready={ready}".encode()

def send_probe(probe, port, text):
    probe.sendto(text, ("127.0.0.1", port))

def no_payload(probe, seconds=.25):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        try: text, _ = probe.recvfrom(300000)
        except socket.timeout: continue
        assert b" FRAG " not in text and b" STATE " not in text, text

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
    send_probe(probe, port, b"TF3MP/1 STATE health ck=7 status=diff fields=stations")
    wait(lambda: status(pending_world)["world_peer"] == "diff")
    assert status(pending_world)["world"] == "same" and status(pending_world)["world_ck"] == "7"
    assert status(pending_world)["world_fields"] == "stations"
    send_probe(probe, port, b"TF3MP/1 LINE after-ready B5 allowed")
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
    send_probe(probe, port, b"TF3MP/1 LINE held B5 not-yet-delivered")
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

thread = threading.Thread(target=relay, daemon=True); thread.start()
host = dll("host", host_port); client = dll("client", front.getsockname()[1])
try:
    wait(lambda: status(host)["connected"] == "1")
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
    probe = bind(); probe.sendto(b"TF3MP/1 HELLO client proto=2 session=intruder", ("127.0.0.1",host_port))
    time.sleep(.1)
    assert "peer restarted" not in status(host)["error"], "another endpoint must not take over the session"
    port_socket=bind(); new_port=port_socket.getsockname()[1]; port_socket.close()
    other=dll("host",new_port,"compatibility",test="fakehost",manifest=None)
    probe.sendto(b"TF3MP/1 HELLO client proto=1",("127.0.0.1",new_port))
    wait(lambda: "old protocol" in status(other)["error"])
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
    print(f"Test files: {work}", flush=True)
