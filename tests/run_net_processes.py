"""Real Winsock/bridge smoke test across separate Windows host/client processes.

Build tests/build_net_tests.bat first. Uses temporary DLL copies and loopback sockets;
does not load TF3 or touch its installation, save files, or running processes.
"""
import ctypes as c
import multiprocessing as mp
from pathlib import Path
import shutil
import socket
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def worker(pipe, folder, role, port):
    api = None
    try:
        folder = Path(folder)
        folder.mkdir()
        shutil.copyfile(ROOT / "native/alut_proxy/build/net_tests.dll", folder / "net_tests.dll")
        manifest = {"id": "a1" * 16, "game": "b2" * 32, "package": "c3" * 32,
                    "mods": "d4" * 32, "save": "e5" * 32, "name": b"Det".hex()}
        ini = f"[net]\nmode={role}\nport={port}\nhost=127.0.0.1\n[session]\n"
        (folder / "alut_proxy.ini").write_text(ini + "".join(f"{k}={v}\n" for k, v in manifest.items()))
        api = c.CDLL(str(folder / "net_tests.dll"))
        api.mp_send.argtypes = api.mp_feed.argtypes = api.mp_log.argtypes = [c.c_char_p]
        api.mp_part.argtypes = [c.c_char_p, c.c_int]
        api.mp_result.argtypes = [c.c_char_p, c.c_char_p]
        api.mp_start()
        api.mp_log(b"[2026-10-11 20:00:00Z - MESSAGE - Main] Loading game from file Det")
        api.mp_feed(b"net reload")
        pipe.send(True)
        while True:
            command, *args = pipe.recv()
            if command == "stop":
                pipe.send(True)
                break
            if command == "status":
                buf = c.create_string_buffer(2048)
                api.mp_status(buf)
                result = dict(line.split("=", 1) for line in buf.value.decode().splitlines())
            elif command == "inbox":
                buf = c.create_string_buffer(262209)
                api.mp_inbox(buf)
                result = buf.value
            else:
                result = getattr(api, "mp_" + command)(*args)
            pipe.send(result)
    except Exception as exc:
        pipe.send({"worker_error": repr(exc)})
    finally:
        if api is not None:
            api.mp_stop()
        pipe.close()


def rpc(peer, command, *args):
    peer.send((command, *args))
    if not peer.poll(15):
        raise AssertionError(f"worker timeout: {command}")
    result = peer.recv()
    if isinstance(result, dict) and "worker_error" in result:
        raise AssertionError(result["worker_error"])
    return result


def wait(check, seconds=15):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        value = check()
        if value:
            return value
        time.sleep(.02)
    raise AssertionError("deadline exceeded")


def run():
    if not (ROOT / "native/alut_proxy/build/net_tests.dll").is_file():
        raise SystemExit("Run tests/build_net_tests.bat first")
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    work = Path(tempfile.mkdtemp(prefix="tf3mp-net-processes-"))
    children, peers = [], {}
    try:
        context = mp.get_context("spawn")
        for role in ("host", "client"):
            parent, child = context.Pipe()
            process = context.Process(target=worker, args=(child, str(work / role), role, port))
            process.start()
            children.append(process)
            child.close()
            assert parent.poll(15) and parent.recv() is True
            peers[role] = parent
        host, client = peers["host"], peers["client"]
        wait(lambda: all(rpc(peer, "status")["connected"] == "1" for peer in peers.values()))
        hs, cs = rpc(host, "status"), rpc(client, "status")
        assert hs["pid"] != cs["pid"]
        assert hs["ready"] == cs["ready"] == hs["peer_ready"] == cs["peer_ready"] == "1"
        assert hs["version"] == cs["version"] == "16"
        # More than eight independent state keys must leave room for the work receipt.
        for i in range(10):
            assert rpc(host, "feed", f"net state key{i} value={i}".encode())
        assert rpc(host, "feed", b"net state work token=host-test phase=handoff pending=0")
        wait(lambda: rpc(client, "status")["peer_work_token"] == "host-test")
        assert rpc(client, "status")["peer_work_phase"] == "handoff"
        # Both directions queue concurrently. World/issue reports are not game actions.
        assert rpc(host, "send", b"B5 host-action")
        assert rpc(host, "send", b"W2 host-world")
        assert rpc(host, "send", b"I1 host-issue")
        assert rpc(client, "send", b"A1 client-action")
        assert rpc(client, "send", b"W1 client-world")
        hs, cs = rpc(host, "status"), rpc(client, "status")
        assert (hs["outbox_actions"], hs["outbox_diagnostics"]) == ("1", "2")
        assert (cs["outbox_actions"], cs["outbox_diagnostics"]) == ("1", "1")
        received = []
        for _ in range(5):
            def available():
                for role, peer in peers.items():
                    value = rpc(peer, "inbox")
                    if value:
                        return role, peer, value
            role, receiver, value = wait(available)
            _, token, kind, index, count, text = value.split(b" ", 5)
            assert kind == b"net" and index == b"0" and count == b"1"
            assert token not in [entry[1] for entry in received]
            sender_pid = cs["pid"] if role == "host" else hs["pid"]
            assert token.startswith(sender_pid.encode() + b"-")
            # Receipt is deliberately withheld: the same delivery remains offered, no later
            # action can be offered on the opposite PC or consume its global permit.
            time.sleep(.15)
            assert rpc(receiver, "inbox") == value
            opposite = client if role == "host" else host
            assert not rpc(opposite, "inbox")
            assert rpc(receiver, "part", token, 0) == 1
            assert rpc(receiver, "part", token, 0) == 0
            assert not rpc(receiver, "inbox")
            state = rpc(receiver, "status")
            assert state["order_stage"] == "waiting_game_result"
            assert state["order_token"].encode() == token
            assert rpc(receiver, "result", token, b"OK") == 1
            assert rpc(receiver, "result", token, b"OK") == 0
            received.append((role, token, text))
        wait(lambda: all(rpc(peer, "status")["outbox"] == "0" and
                         rpc(peer, "status")["order_phase"] == "idle" for peer in peers.values()))
        assert sorted(text for _, _, text in received) == sorted(
            (b"B5 host-action", b"W2 host-world", b"I1 host-issue", b"A1 client-action", b"W1 client-world"))
        assert [text for role, _, text in received if role == "client"] == [b"B5 host-action", b"W2 host-world", b"I1 host-issue"]
        assert [text for role, _, text in received if role == "host"] == [b"A1 client-action", b"W1 client-world"]
        print("PASS separate native host/client processes: readiness, PID tokens, 11 state keys, accurate counts, global FIFO, delayed receipt and duplicate guards", flush=True)
    finally:
        for peer in peers.values():
            try:
                rpc(peer, "stop")
            except (AssertionError, EOFError, OSError):
                pass
            peer.close()
        for process in children:
            process.join(timeout=5)
            if process.is_alive():
                process.terminate()
                process.join(timeout=5)
        print(f"Test files: {work}", flush=True)


if __name__ == "__main__":
    run()
