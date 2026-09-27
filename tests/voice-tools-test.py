#!/usr/bin/env python3
"""Audio CLI regression tests; all recordings, devices, and homes are fake.

Run: python3 tests/voice-tools-test.py
"""
import os
from pathlib import Path
import struct
import shlex
import subprocess
import tempfile
import unittest
import wave

ROOT = Path(__file__).resolve().parents[1]
LIBRARY = ROOT / 'home/.local/lib/voice-tools.sh'


class VoiceToolsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        self.mock = self.home / 'mock'
        self.mock.mkdir()
        library = self.home / '.local/lib/voice-tools.sh'
        library.parent.mkdir(parents=True)
        library.symlink_to(LIBRARY)
        config = self.home / '.config/pipewire/pipewire.conf.d/99-mic-chain.conf'
        config.parent.mkdir(parents=True)
        config.write_text('# preset=minimal\n')
        self.log = self.home / 'recorders'
        self.env = dict(os.environ, HOME=str(self.home),
                        PATH=f'{self.mock}:{os.environ["PATH"]}',
                        VOICE_TEST_LOG=str(self.log))
        self.command('pw-record', '''#!/usr/bin/env python3
import os, signal, struct, sys, wave
# Produce deterministic PCM, then stay alive until the owner stops us.
with wave.open(sys.argv[-1], 'wb') as wav:
    wav.setparams((1, 2, 48000, 0, 'NONE', 'not compressed'))
    wav.writeframes(struct.pack('<h', 16384) * 12000)
with open(os.environ['VOICE_TEST_LOG'], 'a') as log:
    log.write(str(os.getpid()) + ' ' + sys.argv[sys.argv.index('--target')+1] + '\\n')
signal.pause()
''')
        self.command('pactl', '#!/bin/sh\necho "1 voice_cleaned mock"\n')
        self.command('sleep', '#!/bin/sh\nexec /bin/sleep 0.08\n')
        self.command('audio-preset', '#!/bin/sh\nexit 0\n')
        self.command('pw-play', '#!/bin/sh\nexit 0\n')
        self.command('ffmpeg', '''#!/bin/sh
printf 'I: -18.0 LUFS\nTP: -3.0 dBFS\nLRA: 4.0 LU\n' >&2
''')

    def command(self, name, text):
        path = self.mock / name
        path.write_text(text)
        path.chmod(0o755)

    def shell(self, text, *args):
        return subprocess.run(['bash', '-c', 'source "$1"; shift; ' + text,
                               'voice-test', str(LIBRARY), *map(str, args)],
                              env=self.env, text=True, capture_output=True, timeout=10)

    def wav(self, name, samples, channels=1):
        path = self.home / name
        with wave.open(str(path), 'wb') as wav:
            wav.setparams((channels, 2, 48000, 0, 'NONE', 'not compressed'))
            wav.writeframes(struct.pack('<' + 'h' * len(samples), *samples))
        return path

    def assert_recorders_stopped(self, count):
        lines = self.log.read_text().splitlines()
        self.assertEqual(count, len(lines))
        for line in lines:
            with self.assertRaises(ProcessLookupError):
                os.kill(int(line.split()[0]), 0)
        return lines

    def test_shared_statistics_and_formats(self):
        path = self.wav('constant.wav', [16384] * 12000)
        for style in ('detail', 'bench', 'tui'):
            with self.subTest(style=style):
                result = self.shell('voice_analyze "$1" RAW "$2"', style, path)
                self.assertEqual(0, result.returncode, result.stderr)
                self.assertIn('-6.0', result.stdout)
                self.assertIn('Floor', result.stdout)
                self.assertEqual(style == 'detail', 'Crest:' in result.stdout)
                self.assertEqual(style == 'tui', '-18.0 LUFS' in result.stdout)

    def test_short_stereo_clipped_and_empty_recordings(self):
        short = self.wav('short.wav', [16384, 0] * 48, channels=2)
        result = self.shell('voice_analyze bench RAW "$1"', short)
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertNotIn('inf', result.stdout)
        self.assertIn('Floor   -6.0', result.stdout)
        clipped = self.wav('clipped.wav', [32767] * 12000)
        self.assertIn('CLIPPING!', self.shell('voice_analyze detail "" "$1"', clipped).stdout)
        empty = self.wav('empty.wav', [])
        self.assertIn('(empty)', self.shell('voice_analyze bench RAW "$1"', empty).stdout)

    def test_recording_pair_targets_and_cleanup(self):
        raw, cleaned = self.home / 'raw.wav', self.home / 'cleaned.wav'
        result = self.shell('progress() { :; }; voice_record_pair 2 "$1" "$2" raw-source cleaned-source progress', raw, cleaned)
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertTrue(raw.exists() and cleaned.exists())
        lines = self.assert_recorders_stopped(2)
        self.assertEqual({'raw-source', 'cleaned-source'}, {line.split()[1] for line in lines})

    def test_interrupt_stops_both_recorders(self):
        result = self.shell('progress() { /bin/sleep 0.15; kill -TERM "$BASHPID"; }; voice_record_pair 20 "$1" "$2" raw cleaned progress', self.home / 'raw.wav', self.home / 'cleaned.wav')
        self.assertEqual(143, result.returncode, result.stderr)
        self.assert_recorders_stopped(2)

    def test_invalid_duration_does_not_start_recorders(self):
        result = self.shell('voice_record_pair zero a b raw cleaned true')
        self.assertEqual(2, result.returncode)
        self.assertFalse(self.log.exists())

    def test_audio_test_quiet_entrypoint(self):
        result = subprocess.run(['bash', str(ROOT / 'home/bin/audio-test'), '2', 'quiet'],
                                env=self.env, text=True, capture_output=True, timeout=10)
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn('CLEANED (preset=minimal)', result.stdout)
        self.assertEqual(2, result.stdout.count('Crest:'))
        self.assert_recorders_stopped(2)

    def test_voice_bench_entrypoint(self):
        result = subprocess.run(['bash', str(ROOT / 'home/bin/voice-bench')],
                                input='\n' * 7, env=self.env, text=True,
                                capture_output=True, timeout=15)
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn('Bench complete.', result.stdout)
        self.assertEqual(12, sum(line.startswith(('    RAW ', '    CLEANED ')) and 'Floor' in line for line in result.stdout.splitlines()))  # two takes per preset
        self.assert_recorders_stopped(12)

    def test_tui_menu_starts_and_quits(self):
        result = subprocess.run(['script', '-q', '-c',
                                 'bash ' + shlex.quote(str(ROOT / 'home/bin/voice-tui')), '/dev/null'],
                                input='q\n', env=self.env, text=True,
                                capture_output=True, timeout=10)
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn('Quick bench', result.stdout)
        self.assertIn('bye.', result.stdout)
        self.assertFalse(self.log.exists())


if __name__ == '__main__':
    unittest.main()
