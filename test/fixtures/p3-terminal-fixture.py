#!/usr/bin/env python3
import os
import subprocess
import sys

exit_code = int(sys.argv[1]) if len(sys.argv) > 1 else 0
mode = sys.argv[2] if len(sys.argv) > 2 else "byte"
stdin_tty = int(sys.stdin.isatty())
stdout_tty = int(sys.stdout.isatty())

try:
    size = os.get_terminal_size(sys.stdout.fileno())
    columns, lines = size.columns, size.lines
except OSError:
    columns, lines = 0, 0

print(f"__P3_TTY__{stdin_tty}:{stdout_tty}", flush=True)
print(f"__P3_SIZE__{columns}:{lines}", flush=True)
sys.stdout.write("\x1b[?1049h\x1b[2J\x1b[H__P3_TOP__")
sys.stdout.write("\x1b[2;5H__P3_CURSOR__")
if mode == "paste":
    # Tell the terminal emulator to wrap pasted text in the standard bracketed
    # paste markers.  This is the mode interactive TUIs such as Codex use to
    # distinguish one multiline paste from separately submitted input lines.
    sys.stdout.write("\x1b[?2004h")
sys.stdout.flush()

raw = subprocess.run(["stty", "raw", "-echo"], check=False)
if raw.returncode != 0:
    sys.stdout.write("\x1b[?2004l\x1b[?1049l")
    sys.stdout.flush()
    print("__P3_RAW_MODE_FAILED__", flush=True)
    sys.exit(97)

try:
    if mode == "paste":
        pasted = bytearray()
        terminator = b"\x1b[201~"
        while not pasted.endswith(terminator):
            byte = sys.stdin.buffer.read(1)
            if not byte:
                break
            pasted.extend(byte)
        payload = bytes(pasted)
    else:
        payload = sys.stdin.buffer.read(1)
finally:
    subprocess.run(["stty", "sane"], check=False)

sys.stdout.write("\x1b[?2004l\x1b[?1049l")
sys.stdout.flush()
if mode == "paste":
    print(f"__P3_PASTE__{payload.hex()}", flush=True)
else:
    print(f"__P3_INPUT__{payload.hex()}", flush=True)
sys.exit(exit_code)
