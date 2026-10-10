"""Load the packaged proxy in isolated child processes. TF3 is never started/stopped."""
import ctypes
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

if len(sys.argv) == 3:
    directory, expected = Path(sys.argv[1]), sys.argv[2]
    crt = ctypes.CDLL('ucrtbase.dll')
    crt.getenv.argtypes = [ctypes.c_char_p]
    crt.getenv.restype = ctypes.c_char_p
    # Prime the CRT cache before the DLL changes the Windows environment.
    crt.getenv(b'TF3MP_AUTOLOAD')
    proxy = ctypes.WinDLL(str(directory / 'alut.dll'))
    deadline = time.monotonic() + 3
    while True:
        actual = (crt.getenv(b'TF3MP_AUTOLOAD') or b'').decode('ascii')
        log = (directory / 'alut_proxy.log').read_text(errors='replace')
        if 'TF3MP_ROLE=' in log:
            actual = (crt.getenv(b'TF3MP_AUTOLOAD') or b'').decode('ascii')
            assert actual == expected, (actual, expected)
            break
        assert time.monotonic() < deadline, 'bridge did not initialize'
        time.sleep(.02)
    assert not (directory / 'alut_proxy.launch').exists(), 'request not consumed'
    sys.exit(0)

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='tf3mp-launch-request-') as temporary:
    for case, payload, old, expected in (
        ('valid', '57656c742ec3a4', False, '57656c742ec3a4'),
        ('expired', '6162', True, ''),
        ('invalid', 'xx', False, ''),
        ('odd', 'abc', False, ''),
        ('empty', '', False, ''),
    ):
        folder = Path(temporary) / case
        folder.mkdir()
        shutil.copyfile(root / 'launcher/bin/alut.dll', folder / 'alut.dll')
        (folder / 'alut_proxy.ini').write_text('[net]\nmode=off\n')
        request = folder / 'alut_proxy.launch'
        request.write_text('[launch]\nsave_hex=' + payload + '\n')
        if old:
            os.utime(request, (time.time() - 400, time.time() - 400))
        env = dict(os.environ, TF3MP_AUTOLOAD='stale_inherited_value')
        subprocess.run([sys.executable, __file__, str(folder), expected], env=env, check=True)
print('5 native one-shot launch request checks passed (including cached CRT environment).')
