# Shared recording and analysis for audio-test, voice-bench, and voice-tui.
# Sourced library; callers retain their prompts, menus, and output directories.

voice_record_pair() (
  # Subshell scopes cleanup traps to this recording, preserving caller traps.
  # secs raw_path cleaned_path raw_source cleaned_source progress_fn [label]
  local secs=$1 raw=$2 cln=$3 raw_src=$4 cln_src=$5 progress=$6 label=${7:-}
  local raw_pid= cln_pid= remaining
  [[ $secs =~ ^[0-9]+$ ]] && (( secs > 0 )) || {
    printf 'voice-tools: duration must be a positive integer\n' >&2
    return 2
  }
  voice_stop_recorders() {
    local pid
    for pid in "$raw_pid" "$cln_pid"; do
      [[ -z $pid ]] || kill "$pid" 2>/dev/null || true
    done
    for pid in "$raw_pid" "$cln_pid"; do
      [[ -z $pid ]] || wait "$pid" 2>/dev/null || true
    done
  }
  trap voice_stop_recorders EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  rm -f -- "$raw" "$cln"
  pw-record --target "$raw_src" --channels 1 --rate 48000 --format s16 -- "$raw" >/dev/null 2>&1 &
  raw_pid=$!
  pw-record --target "$cln_src" --channels 1 --rate 48000 --format s16 -- "$cln" >/dev/null 2>&1 &
  cln_pid=$!
  for ((remaining=secs; remaining>0; remaining--)); do
    "$progress" "$remaining" "$label"
    sleep 1
  done
  "$progress" 0 "$label"
)

voice_analyze() {
  # style (detail/bench/tui), label, path. TUI also measures optional LUFS.
  python3 - "$1" "$2" "$3" <<'PY'
import wave, struct, math, sys, os, subprocess, re
style, label, f = sys.argv[1:4]
if style == "tui" and (not os.path.isfile(f) or os.path.getsize(f) < 100):
    print(f"    {label}: (empty)"); raise SystemExit
with wave.open(f, 'rb') as w:
    sr=w.getframerate(); n=w.getnframes(); ch=w.getnchannels()
    if w.getsampwidth() != 2:
        raise SystemExit("voice-tools: expected 16-bit PCM WAV")
    data=w.readframes(n)
    samples=struct.unpack('<'+'h'*(n*ch), data)
    samples=samples[::ch]
    if not samples:
        print("  (empty)" if style == "detail" else f"    {label}: (empty)"); raise SystemExit
    rms=math.sqrt(sum(s*s for s in samples)/len(samples))
    peak=max(abs(s) for s in samples)
    win=min(len(samples),max(1,int(0.2*sr))); s2=[s*s for s in samples]; csum=0.0; q=float('inf')
    for i,v in enumerate(s2):
        csum+=v
        if i>=win: csum-=s2[i-win]
        if i+1>=win: q=min(q, math.sqrt(csum/win))
    db = lambda x: 20*math.log10(max(x,1)/32768)
    flag = "  CLIPPING!" if peak>=32760 else ""

    # Objective EBU R128 LUFS measurement via ffmpeg's ebur128 filter
    lufs_str = ""
    if style == "tui":
        try:
            r = subprocess.run(
                ["ffmpeg","-hide_banner","-nostats","-i",f,
                 "-af","ebur128=peak=true","-f","null","-"],
                capture_output=True, text=True, timeout=15)
            text = r.stderr
            # last "I:" / "TP:" lines
            m_i = re.findall(r"\bI:\s+(-?\d+\.?\d*)\s+LUFS", text)
            m_tp = re.findall(r"\bTP:\s+(-?\d+\.?\d*)\s+dBFS", text)
            m_lra = re.findall(r"\bLRA:\s+(-?\d+\.?\d*)\s+LU", text)
            if m_i and m_tp and m_lra:
                lufs_str = f"   I {float(m_i[-1]):+5.1f} LUFS  TP {float(m_tp[-1]):+4.1f}  LRA {float(m_lra[-1]):4.1f} LU"
        except Exception:
            pass

    if style == "detail":
        print(f"    RMS:   {db(rms):+6.1f} dBFS")
        print(f"    Peak:  {db(peak):+6.1f} dBFS  ({'CLIPPING!' if peak >= 32760 else 'safe'})")
        print(f"    Floor: {db(q):+6.1f} dBFS  (quietest 200 ms — lower = cleaner silence)")
        print(f"    Crest: {(db(peak)-db(rms)):4.1f} dB    (lower = more compressed)")
    else:
        width = 10 if style == "tui" else 8
        print(f"    {label:{width}s}  RMS {db(rms):+5.1f}   Peak {db(peak):+5.1f}{flag}   Floor {db(q):+6.1f}  dBFS{lufs_str}")
PY
}
