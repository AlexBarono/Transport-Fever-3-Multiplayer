"""Exercise the fake host's replay failure against a UDP game stub; no TF3 needed."""
from pathlib import Path
import socket
import subprocess
import tempfile
import time


def main():
    root = Path(__file__).resolve().parents[1]
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    with tempfile.TemporaryDirectory(prefix="tf3mp-fake-test-") as folder:
        logfile = Path(folder) / "host.log"
        process = subprocess.Popen(
            ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
             str(root / "tools" / "fake-partner.ps1"), "-Port", str(port),
             "-Minutes", "1", "-LogFile", str(logfile)],
            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
            creationflags=subprocess.CREATE_NO_WINDOW,
        )
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as game:
                game.connect(("127.0.0.1", port))
                game.settimeout(0.15)

                def send(text):
                    game.send(text.encode("ascii"))

                def receive(prefix, seconds=5):
                    deadline = time.monotonic() + seconds
                    while time.monotonic() < deadline:
                        try:
                            packet = game.recv(4096).decode("ascii")
                            if packet.startswith(prefix):
                                return packet
                        except (TimeoutError, ConnectionResetError):
                            pass
                    raise AssertionError(f"Missing {prefix}; host exit={process.poll()}")

                deadline = time.monotonic() + 8
                while True:
                    send("TF3MP/1 PROBE startup")
                    try:
                        receive("TF3MP/1 READY startup", 0.3)
                        break
                    except AssertionError:
                        if time.monotonic() >= deadline:
                            raise

                def state(gt, heartbeat):
                    send(f"TF3MP/1 STATE gui gt={gt} hb={heartbeat} speed=1 ver=1 run=1 by=client src=gui")

                state(100000, 1)
                send("TF3MP/1 FRAG stub.1 0 1 B5 first")
                receive("TF3MP/1 DONE stub.1 OK")
                send("TF3MP/1 FRAG stub.2 0 1 B5 second")
                receive("TF3MP/1 DONE stub.2 OK")
                state(0, 2)  # Reload original save.
                state(21000, 3)
                packet = receive("TF3MP/1 FRAG ")
                token = packet.split()[2]
                assert packet.endswith("B5 first"), packet
                send(f"TF3MP/1 DONE {token} FAIL")
                assert process.wait(timeout=5) == 0, "Host failed to shut down cleanly after rejection"
                deadline = time.monotonic() + 1.3
                while time.monotonic() < deadline:
                    try:
                        assert not game.recv(4096).startswith(b"TF3MP/1 FRAG "), "Replay continued after FAIL"
                    except (TimeoutError, ConnectionResetError):
                        pass
                log = logfile.read_text(encoding="utf-8-sig")
                assert "REPLAY FAILED at line 1 of 2" in log, log
                assert "Following actions remain stopped" in log, log
                assert "replay stopped:" in log, log
                print("Fake-host UDP test passed: failure logged, replay stopped, host exits cleanly for restart")
        finally:
            if process.poll() is None:
                process.terminate()
            process.communicate(timeout=5)


if __name__ == "__main__":
    main()
