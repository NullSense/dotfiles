# Recurring check: python3 ~/.dotfiles/tests/hypr-waybar-bridge-test.py
import runpy
from pathlib import Path
import socket
import sys
import threading
import time
import unittest

bridge = runpy.run_path(str(Path(__file__).resolve().parents[1] / 'home/.local/bin/hypr-waybar-bridge'))
dispatch = bridge['dispatch_events']


class BridgeTest(unittest.TestCase):
    def setUp(self):
        self.reader, self.writer = socket.socketpair()
        self.calls = []
        self.errors = []
        dispatch.__globals__['signal_waybar'] = lambda: self.calls.append(time.monotonic())
        def run():
            try:
                dispatch(self.reader)
            except Exception as error:
                self.errors.append(error)
        self.thread = threading.Thread(target=run, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.writer.close()
        self.thread.join(1)
        self.reader.close()
        self.assertFalse(self.thread.is_alive(), 'bridge did not finish on EOF')
        self.assertEqual(self.errors, [])

    def test_burst_coalesces_and_partial_lines_survive(self):
        self.writer.sendall(b'workspace>>1\nfocusedmon>>DP-1,1\nopenwin')
        time.sleep(0.02)
        self.writer.sendall(b'dow>>abc\nclosewindow>>abc\n')
        time.sleep(0.18)
        self.assertEqual(len(self.calls), 1)

    def test_continuous_events_cannot_starve_refresh(self):
        start = time.monotonic()
        for _ in range(15):
            self.writer.sendall(b'workspace>>2\n')
            time.sleep(0.03)
        self.assertGreaterEqual(len(self.calls), 1)
        self.assertLess(self.calls[0] - start, 0.40)
        time.sleep(0.15)
        self.assertGreaterEqual(len(self.calls), 2)
        self.assertLessEqual(len(self.calls), 3)

    def test_ignored_events_do_not_refresh(self):
        self.writer.sendall(b'windowtitle>>changing\nactivewindow>>app,title\n')
        time.sleep(0.15)
        self.assertEqual(self.calls, [])

    def test_pending_event_flushes_on_disconnect(self):
        self.writer.sendall(b'urgent>>abc\n')
        self.writer.shutdown(socket.SHUT_WR)
        self.thread.join(1)
        self.assertEqual(len(self.calls), 1)


unittest.main(argv=['hypr-waybar-bridge-test'])
