#!/usr/bin/env python3
import os
import subprocess
import sys

args = sys.argv[1:]
prompt = "Password: "

# Model the sudo prompt option closely enough for the P3 terminal regression.
for index, arg in enumerate(args):
    if arg == "-p" and index + 1 < len(args):
        prompt = args[index + 1]
    elif arg == "--prompt" and index + 1 < len(args):
        prompt = args[index + 1]
    elif arg.startswith("--prompt="):
        prompt = arg.split("=", 1)[1]

expected = os.environ.get("P3_TEST_SUDO_PASSWORD", "p3-secret")
prompts = int(os.environ.get("P3_TEST_SUDO_PROMPTS", "2"))

for attempt in range(prompts):
    sys.stdout.write(prompt)
    sys.stdout.flush()
    noecho = subprocess.run(["stty", "-echo"], check=False)
    if noecho.returncode != 0:
        print("__P3_SUDO_NOECHO_FAILED__", flush=True)
        sys.exit(97)
    try:
        supplied = sys.stdin.readline().rstrip("\r\n")
    finally:
        subprocess.run(["stty", "echo"], check=False)
    sys.stdout.write("\n")
    sys.stdout.flush()
    if supplied != expected:
        print(f"__P3_SUDO_BAD__{attempt + 1}", flush=True)
        sys.exit(98)

print(f"__P3_SUDO_OK__{prompts}", flush=True)
