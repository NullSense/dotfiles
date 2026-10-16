# Desktop capture

`~/bin/screenrecord` owns recording; `~/bin/screenshot` owns screenshots.
The `omarchy-capture-*` shims keep Print, existing recording shortcuts and the
Omarchy menu on these same implementations.

- **Win+Alt+R** opens audio setup, then selects a monitor/region. Press again to stop.
- Choose desktop and microphone sources (including cleaned mic inputs), or leave
  both off for silence. Choices are remembered in local state. **Audio mixer…**
  opens pavucontrol for system levels/mute; opening setup does not change levels.
  Adding **Shift** enables desktop audio initially; **Ctrl** enables the mic.
- Stopping automatically opens **Review & export** before any clipboard copy or
  conversion. Closing keeps the original and leaves the clipboard alone.
- **Win+Alt+C → Review last recording** reopens review later.
- The **Waybar recording pill** appears during desktop capture: left-click
  pauses/resumes, right-click stops and reviews, middle-click reviews the last
  finished recording. Its timer excludes paused time; amber means paused.
- **Print** captures an untinted lossless PNG and copies the image; click the
  notification to annotate in Satty. Enter copies and saves the edited PNG.

Desktop defaults are 1080p30 H.264 in MP4, NVIDIA GPU encoding, and AAC 128 kb/s
when audio is enabled. MP4 uses `faststart` for playback before a full download.
Small regions stay at their original resolution. On GSR 6.1.4 the faststart
flag explicitly disables its incompatible hybrid-fragmented mode; captures need
a graceful stop to finalize MP4, so the stop path never force-kills the encoder.
Stopping waits for the owned encoder to finish, validates the recording, then
opens review. **Copy original**, or **Export** with **Copy after export** enabled,
copies a percent-encoded file URI (`text/uri-list`). Paste attaches the file in
applications that support file clipboard data; apps accepting only text/images
may require their attachment picker. The clipboard holds a tiny reference, not
the video bytes. Files remain local; there is no automatic upload.

Review supports a visible caption, title/tags, precise in/out seconds with
playhead buttons, selection preview, mute, destination, quality, maximum MB and
output folder. Caption burns into the derivative; title/tags stay in a local
`.capture.json` sidecar and title prefixes the filename. There are no draw tools.
Preview sound starts off and can be enabled separately from export mute.
Copy original is disabled when caption/trim/mute edits would be discarded.
Uncheck **Copy after export** to save only. Cancel stops the owned export child.

App presets cover Discord free/Basic/Nitro and boosted servers, Signal,
WhatsApp video/document, Telegram free/Premium, Slack and Teams chat. The default
Discord free export budget is 19 decimal MB under its published 20 MB ceiling;
Signal uses 95 MB headroom under its remotely configurable source defaults.
WhatsApp video uses 60 MB / 480p; Document uses a separate larger preset and
requires that app's Document picker. Account/server limits can vary. See
[CHAT-ATTACHMENT-LIMITS.md](CHAT-ATTACHMENT-LIMITS.md) for current primary sources,
exact budgets, remote-limit caveats and Teams chat versus Files distinctions.

Exports default to `Shared/` beside the original. Limits are checked against
actual bytes, preserving the selected duration and audio unless muted.
An already-fitting compatible unedited MP4 can be reused without encoding.
Very low budgets reduce resolution; impossible budgets fail while preserving
the original. Custom limits range from 0.1–4000 decimal MB. With Custom / no app
limit selected, disable Limit size for a variable-size quality preset.
A maximum is an upper bound, not a promise to fill it.

Exports use NVDEC decoding, CUDA scaling, NVENC H.264 (`p4`, VBR, quarter-resolution
multipass), and AAC. Caption rendering briefly downloads frames for CPU drawtext,
then uploads them back for NVENC; decode and resize stay on the GPU.
GPU failures are reported rather than silently using a CPU
video encoder. HDR gameplay/replay capture retains its existing AV1 HDR settings;
these SDR sharing presets reject HDR sources because they need explicit tone mapping.

```sh
screenrecord --preset=small --with-desktop-audio # 720p30
screenrecord --preset=native                   # native resolution, 60fps
screenrecord --share-last                      # review/export
screenrecord --no-setup --with-desktop-audio    # automation: skip audio dialog
screenrecord-share --app signal --start 2 --end 12 --mute /path/to/recording.mp4
screenrecord-share --app discord-free --caption "Example" --no-copy /path/to/recording.mp4
screenrecord-share --target-mb 24.5 /path/to/recording.mp4
screenrecord-share --preset small /path/to/recording.mp4
```

Screenshots use PNG compression level 1 for quick capture and explicit
`image/png` clipboard data. Both tools honor XDG user directories and their
existing `SCREENRECORD_OUTPUT_DIR` / `OMARCHY_SCREENSHOT_DIR` overrides.
The desktop recording PID, filename and last encoder log live in
`$XDG_RUNTIME_DIR/screenrecord/`; the last finished file pointer lives in
`${XDG_STATE_HOME:-~/.local/state}/screenrecord/latest`.
Remembered audio choices live in that state directory's `audio.json`.

`screenrecord-review` uses system Python with PyGObject/GTK4, GStreamer playback
(`gst-libav`, `gst-plugins-good`), and the existing pavucontrol mixer. Both audio
setup and review have stable GTK app IDs (`local.screenrecord.Audio` and
`local.screenrecord.Review`); `home/.config/hypr/lua/windows.lua` floats and centers
them on the current workspace. The mixer already has a floating rule.

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
checks remain in `tests/screenrecord-game-test.sh`. In a graphical session,
`tests/capture-review-test.sh` checks real GTK video playback, controls, clipboard
ordering, export-only/cancellation, remembered audio choices and live Hyprland
floating rules. Its fixtures are synthetic, not desktop captures.

Implementation references: [FFmpeg MP4 faststart](https://ffmpeg.org/ffmpeg-formats.html#mov_002c-mp4_002c-ismv),
[CUDA scaling](https://ffmpeg.org/ffmpeg-filters.html#scale_005fcuda),
[NVENC options](https://github.com/FFmpeg/FFmpeg/blob/master/libavcodec/nvenc_h264.c),
[wl-clipboard](https://github.com/bugaevc/wl-clipboard),
[Waybar custom modules](https://github.com/Alexays/Waybar/wiki/Module:-Custom).
