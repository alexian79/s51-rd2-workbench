#!/bin/bash
# Apply the two proven Windows fixes to the native tree's tools/s51dbg.py:
#  1) TCP_NODELAY on the console socket (Nagle x delayed-ACK = 40ms stalls on Windows)
#  2) spawn with -b (black_and_white): fwio.cc pretends the -Z console socket is a tty
#     and paints ANSI into the JSON stream on Windows only. No-op on Linux.
set -e
F=/p/projects/s51-rd2-workbench/s51-workbench-win/s51-ucsim-rd2/tools/s51dbg.py
python3 - "$F" <<'EOF'
import sys
p = sys.argv[1]
s = open(p).read()
if "TCP_NODELAY" not in s:
    old = """        else:
            raise ConsoleError("no console on port %d" % self.port)
        self._sock.setblocking(False)"""
    new = """        else:
            raise ConsoleError("no console on port %d" % self.port)
        try:
            self._sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        except OSError:
            pass
        self._sock.setblocking(False)"""
    assert old in s, "nodelay anchor miss"
    s = s.replace(old, new, 1)
n = s.count('"-c", "-"') + s.count('("-c", "-")')
s = s.replace('["-c", "-", "-Z", str(self.port)]', '["-b", "-c", "-", "-Z", str(self.port)]')
s = s.replace('"89C51R", "-c", "-"', '"89C51R", "-b", "-c", "-"')
s = s.replace('flags=("-c", "-")', 'flags=("-b", "-c", "-")')
s = s.replace('                             ["-c", "-"],', '                             ["-b", "-c", "-"],')
assert '["-b", "-c", "-"]' in s or '"-b"' in s, "b-flag miss"
open(p, "w").write(s)
print("s51dbg patched")
EOF
grep -c '"-b"\|"-b",' "$F" | xargs echo "b-flag occurrences:"
grep -c TCP_NODELAY "$F" | xargs echo "nodelay:"
