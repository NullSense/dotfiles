### hyprwhspr-ai migration plan

1. Phase 1 — daemon scaffold
   1. asyncio Unix socket server
   2. dispatch table for ops
      - ping
      - rewrite
      - vision (subops: summarize / explain / ask)
      - translate
      - ocr (engines: gemma / chandra / surya / hybrid)
   3. keepalive task (50 min idle threshold)
2. Phase 2 — flip the rewrite hook
   1. 4.5 s self-cap wrapper
   2. empty-stdout fallthrough on daemon-down
   3. switch `post_transcription_hook` in chezmoi config
3. Phase 3 — port menu actions
   1. Summarize / Explain / Ask × Clipboard / Screen / Region / File
   2. Translate × Clipboard / Region / File
   3. OCR engine submenu
4. Phase 4 — retire the bash scripts
5. Phase 5 — cleanup and documentation
