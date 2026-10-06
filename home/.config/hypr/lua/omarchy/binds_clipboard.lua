-- VENDORED SNAPSHOT of omarchy default/hypr/binds_clipboard (omarchy a3aedb0c, converted from hyprlang).
-- The old hyprland.conf `source`d the live file; Lua cannot, so omarchy updates no longer
-- propagate here automatically. Re-diff against ~/.local/share/omarchy after `omarchy` updates.

-- Copy / Paste
hl.bind("SUPER + C", hl.dsp.send_shortcut({ mods = "CTRL", key = "Insert", window = "" }), { description = "Universal copy" })
hl.bind("SUPER + V", hl.dsp.send_shortcut({ mods = "SHIFT", key = "Insert", window = "" }), { description = "Universal paste" })
hl.bind("SUPER + X", hl.dsp.send_shortcut({ mods = "CTRL", key = "X", window = "" }), { description = "Universal cut" })
hl.bind("SUPER + CTRL + V", hl.dsp.exec_cmd("omarchy-launch-walker -m clipboard"), { description = "Clipboard manager" })
