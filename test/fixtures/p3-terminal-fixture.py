#!/usr/bin/env python3
import os
import subprocess
import sys

exit_code = int(sys.argv[1]) if len(sys.argv) > 1 else 0
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
sys.stdout.flush()

raw = subprocess.run(["stty", "raw", "-echo"], check=False)
if raw.returncode != 0:
    sys.stdout.write("\x1b[?1049l")
    sys.stdout.flush()
    print("__P3_RAW_MODE_FAILED__", flush=True)
    sys.exit(97)

try:
    byte = sys.stdin.buffer.read(1)
finally:
    subprocess.run(["stty", "sane"], check=False)

sys.stdout.write("\x1b[?1049l")
sys.stdout.flush()
print(f"__P3_INPUT__{byte.hex()}", flush=True)
sys.exit(exit_code)
