-- Canonical NVIDIA/Aquamarine output baseline. DP-1 stays 10-bit so the manual
-- HDR toggle can atomically switch between the normal sRGB desktop and BT.2020
-- PQ. DP-2 remains conservative at 8-bit because that monitor's link is flaky.

hl.monitor({
    output = "DP-1",
    mode = "3840x2160@240",
    position = "0x0",
    scale = 2.0,
    bitdepth = 10,
})

hl.monitor({
    output = "DP-2",
    mode = "2560x1440@120",
    position = "1920x0",
    scale = 1.0,
    bitdepth = 8,
})

-- --- Per-monitor workspaces (desc:-matched) ---------------------------------
hl.workspace_rule({
    workspace = "1",
    monitor = "DP-1",
    default = true,
})

hl.workspace_rule({
    workspace = "2",
    monitor = "DP-1",
})

hl.workspace_rule({
    workspace = "3",
    monitor = "DP-2",
})

hl.workspace_rule({
    workspace = "4",
    monitor = "DP-1",
})

hl.workspace_rule({
    workspace = "5",
    monitor = "DP-1",
})

hl.workspace_rule({
    workspace = "6",
    monitor = "DP-1",
})

hl.workspace_rule({
    workspace = "7",
    monitor = "DP-1",
})

hl.workspace_rule({
    workspace = "8",
    monitor = "DP-1",
})

hl.workspace_rule({
    workspace = "9",
    monitor = "DP-1",
})

hl.workspace_rule({
    workspace = "10",
    monitor = "DP-1",
})

hl.workspace_rule({
    workspace = "special:dropdown",
})

hl.workspace_rule({
    workspace = "special:spotify",
    on_created_empty = "[float; size 1500 950] spotify-launcher",
})

