#!/usr/bin/env python3
"""One idle cycle: wait for physical keyboard/mouse input, then restore OLED.

Started on demand by hypridle-suspend.sh through a Type=notify user service.
No input is grabbed, retained or logged. Virtual devices cannot trigger wake.
"""

import argparse
import os
from pathlib import Path
import selectors
import socket
import struct
import subprocess
import time

EVENT = struct.Struct("@llHHi")  # Linux input_event on the host Python ABI


def capabilities(text):
    bits = struct.calcsize("L") * 8
    return sum(int(word, 16) << (bits * index)
               for index, word in enumerate(reversed(text.split())))


def is_input_device(real_path, keys):
    # KEY_A or BTN_LEFT: exclude sound jack/power/LED/controller-only devices.
    return "/virtual/" not in real_path and bool(keys & ((1 << 30) | (1 << 272)))


def physical_devices():
    devices = []
    for event in Path("/sys/class/input").glob("event*"):
        device = event / "device"
        try:
            if is_input_device(str(device.resolve()), capabilities((device / "capabilities/key").read_text())):
                devices.append(Path("/dev/input") / event.name)
        except (OSError, ValueError):
            continue  # Device removed during enumeration.
    return devices


def has_activity(data):
    # EV_KEY press/repeat, EV_REL movement/scroll, EV_ABS touch/tablet motion.
    # Ignore key release, EV_SYN and LED updates caused by desktop focus changes.
    return any((kind == 1 and value > 0) or (kind == 2 and value != 0) or kind == 3
               for _, _, kind, _, value in EVENT.iter_unpack(data))


def wait_for_input(ready):
    with selectors.DefaultSelector() as selector:
        devices = {}
        try:
            def refresh():
                found = set(physical_devices())
                for path in set(devices) - found:
                    selector.unregister(devices[path])
                    os.close(devices.pop(path))
                for path in found - set(devices):
                    try:
                        fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_CLOEXEC)
                    except OSError:
                        continue
                    selector.register(fd, selectors.EVENT_READ, path)
                    devices[path] = fd

            refresh()
            if not devices:
                raise RuntimeError("No readable physical keyboard/mouse; refusing unattended OLED power-off")
            ready()  # The off command may proceed only once all FDs are open.
            refreshed = time.monotonic()
            while True:
                for key, _ in selector.select(timeout=0.5):
                    try:
                        data = os.read(key.fd, EVENT.size * 64)
                    except BlockingIOError:
                        continue
                    except OSError:
                        data = b""
                    if not data:
                        selector.unregister(key.fd)
                        os.close(devices.pop(key.data))
                    elif has_activity(data):
                        return
                if time.monotonic() - refreshed >= 1:
                    refresh()  # Keyboard/mouse unplug/replug while asleep.
                    refreshed = time.monotonic()
        finally:
            for fd in devices.values():
                os.close(fd)


def notify_ready():
    address = os.environ.get("NOTIFY_SOCKET")
    if address:
        if address.startswith("@"):
            address = "\0" + address[1:]
        with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as client:
            client.sendto(b"READY=1", address)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="list eligible physical input devices")
    args = parser.parse_args()
    if args.check:
        for device in physical_devices():
            print(device)
        return
    wait_for_input(notify_ready)
    subprocess.run([str(Path.home() / "bin/hypridle-resume.sh")], check=True)


if __name__ == "__main__":
    main()
