#!/usr/bin/env python3
"""Run with python3 ~/.dotfiles/tests/hypridle-input-wake-test.py [--live].

Live mode uses inert callbacks, opens/closes a terminal and sends virtual Shift,
then waits for physical input. It never changes monitor power.
"""

import argparse
import importlib.util
import multiprocessing
from pathlib import Path
import struct
import subprocess
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("wake", ROOT / "home/bin/hypridle-input-wake.py")
wake = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wake)


class PhysicalWakeTest(unittest.TestCase):
    def test_only_physical_keyboards_and_pointers(self):
        keyboard = 1 << 30  # KEY_A
        mouse = 1 << 272  # BTN_LEFT
        self.assertTrue(wake.is_input_device("/sys/devices/pci0000/usb1/input/event4", keyboard))
        self.assertTrue(wake.is_input_device("/sys/devices/pci0000/usb2/input/event2", mouse))
        self.assertFalse(wake.is_input_device("/sys/devices/virtual/input/event21", keyboard))
        self.assertFalse(wake.is_input_device("/sys/devices/pci0000/sound/input/event17", 0))

    def test_activity_does_not_include_leds_or_sync(self):
        for kind, value, expected in ((1, 1, True), (1, 0, False), (2, 4, True),
                                      (2, 0, False), (3, 20, True), (0, 0, False), (17, 1, False)):
            with self.subTest(kind=kind, value=value):
                event = wake.EVENT.pack(0, 0, kind, 0, value)
                self.assertEqual(wake.has_activity(event), expected)

    def test_kernel_capability_words(self):
        self.assertEqual(wake.capabilities("1 0"), 1 << (struct.calcsize("L") * 8))

    def test_power_restore_has_no_compositor_resume_callback(self):
        config = (ROOT / "home/.config/hypr/hypridle.conf").read_text()
        self.assertNotRegex(config, r"on-resume\s*=\s*.*hypridle-resume\.sh")
        self.assertIn("after_sleep_cmd   = ~/bin/hypridle-resume.sh", config)


def observe(connection):
    wake.wait_for_input(lambda: connection.send("ready"))
    connection.send("physical")


def live():
    parent, child = multiprocessing.Pipe()
    process = multiprocessing.Process(target=observe, args=(child,))
    process.start()
    window = None
    try:
        assert parent.poll(5) and parent.recv() == "ready", "input watcher did not initialize"
        window = subprocess.Popen(["alacritty", "--class", "aorus-idle-regression", "-e", "sleep", "30"],
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(1)
        window.terminate()
        window.wait(timeout=5)
        subprocess.run(["wtype", "-k", "Shift_L"], check=True, timeout=5)
        assert not parent.poll(1), "window activity or virtual typing woke the physical watcher"
        print("PASS: window open/close and virtual typing did not wake; move the physical mouse now", flush=True)
        assert parent.poll(60) and parent.recv() == "physical", "no physical input received"
        print("PASS: physical keyboard/mouse wakes the same watcher", flush=True)
    finally:
        if window and window.poll() is None:
            window.terminate()
            window.wait(timeout=5)
        if process.is_alive():
            process.terminate()
        process.join(5)
        parent.close()
        child.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--live", action="store_true")
    args = parser.parse_args()
    result = unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromTestCase(PhysicalWakeTest))
    if not result.wasSuccessful():
        raise SystemExit(1)
    if args.live:
        live()
