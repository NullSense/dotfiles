# Desktop capture

`~/bin/screenrecord` owns recording; `~/bin/screenshot` owns screenshots.
The `omarchy-capture-*` shims keep Print, existing recording shortcuts and the
Omarchy menu on these same implementations.

- **Win+Alt+R** selects a monitor/region and toggles desktop recording.
- Add **Shift** for desktop audio or **Ctrl** for microphone audio.
- **Win+Alt+C → Share last recording** reopens sharing after a notification expires.
- The **Waybar recording pill** appears during desktop capture: left-click
  pauses/resumes, right-click stops and copies, middle-click shares the last
  finished recording. Its timer excludes paused time; amber means paused.
- **Print** captures an untinted lossless PNG and copies the image; click the
  notification to annotate in Satty. Enter copies and saves the edited PNG.

Desktop defaults are 1080p30 H.264 in MP4, NVIDIA GPU encoding, and AAC 128 kb/s
when audio is enabled. MP4 uses `faststart` for playback before a full download.
Small regions stay at their original resolution. On GSR 6.1.4 the faststart
flag explicitly disables its incompatible hybrid-fragmented mode; captures need
a graceful stop to finalize MP4, so the stop path never force-kills the encoder.
Stopping waits for the owned encoder to finish, validates the recording, then
copies a percent-encoded file URI (`text/uri-list`). Paste attaches the file in
applications that support file clipboard data; apps accepting only text/images
may require their attachment picker. The clipboard holds a tiny reference, not
the video bytes. Files remain local; there is no automatic upload.

Click **Share / resize** on the saved notification for 10/25/50 MB upper limits,
a custom decimal MB limit, or Small (720p), Balanced (1080p), Clear (1440p).
Exports go beside the original in `Shared/` and are copied when ready. Limits
are checked against actual bytes; the full duration and audio are preserved.
An already-small H.264 MP4 is reused. Very low budgets reduce resolution;
impossible budgets fail without changing the original. Quality presets have
variable file sizes. A maximum is an upper bound, not a promise to fill it.

Exports use NVDEC decoding, CUDA scaling, NVENC H.264 (`p4`, VBR, quarter-resolution
multipass), and AAC. GPU failures are reported rather than silently using a CPU
video encoder. HDR gameplay/replay capture retains its existing AV1 HDR settings;
these SDR sharing presets reject HDR sources because they need explicit tone mapping.

```sh
screenrecord --preset=small --with-desktop-audio # 720p30
screenrecord --preset=native                   # native resolution, 60fps
screenrecord --share-last                      # sharing menu
screenrecord-share --target-mb 24.5 /path/to/recording.mp4
screenrecord-share --preset small /path/to/recording.mp4
```

Screenshots use PNG compression level 1 for quick capture and explicit
`image/png` clipboard data. Both tools honor XDG user directories and their
existing `SCREENRECORD_OUTPUT_DIR` / `OMARCHY_SCREENSHOT_DIR` overrides.
The desktop recording PID, filename and last encoder log live in
`$XDG_RUNTIME_DIR/screenrecord/`; the last finished file pointer lives in
`${XDG_STATE_HOME:-~/.local/state}/screenrecord/latest`.

Waybar's inline `custom/recording` module runs `screenrecord-status --watch` as
a continuous JSON stream with `restart-interval: 5`, `exec-on-event: false` and
`hide-empty-text: true`. It has no `interval` or `signal`: inotify wakes the
watcher for start/stop/pause, with a one-second timer only while recording.
Pause uses GSR's `set-paused` IPC and updates the UI only after acknowledgement.
The three clicks call `screenrecord --toggle-pause`, `--stop-recording`, and
`--share-last`. Its classes are `recording`, `paused`, `finishing`, and `idle`.
Configuration and colors live in `home/.config/waybar/config.jsonc` and
`home/.config/waybar/style.css`.

Recurring validation: `tests/capture-test.sh` covers lifecycle/clipboard/menu
entrypoints without capturing the desktop. `tests/capture-test.sh --gpu` also
encodes a synthetic clip on the NVIDIA card and checks size, duration, audio,
pixel format, MP4 atom order and original preservation. Gameplay lifecycle
checks remain in `tests/screenrecord-game-test.sh`.

Implementation references: [FFmpeg MP4 faststart](https://ffmpeg.org/ffmpeg-formats.html#mov_002c-mp4_002c-ismv),
[CUDA scaling](https://ffmpeg.org/ffmpeg-filters.html#scale_005fcuda),
[NVENC options](https://github.com/FFmpeg/FFmpeg/blob/master/libavcodec/nvenc_h264.c),
[wl-clipboard](https://github.com/bugaevc/wl-clipboard),
[Waybar custom modules](https://github.com/Alexays/Waybar/wiki/Module:-Custom).
