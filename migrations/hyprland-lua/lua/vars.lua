-- Shared variables (hyprlang `$var = ...` in the old hyprland.conf).
-- Lua `local`s do not cross files, so they live in one module.
return {
    mainMod = "SUPER",
    mod     = "SUPER",
    term    = "ghostty",
    browser = "helium",

    -- Gruvbox Dark Hard palette (mirrors sway $bg/$fg/$accent set vars)
    bgd    = "rgb(282828)",
    bgs    = "rgb(32302f)",
    bg1    = "rgb(3c3836)",
    bg2    = "rgb(504945)",
    bg3    = "rgb(665c54)",
    fg3    = "rgb(bdae93)",
    fg2    = "rgb(d5c4a1)",
    fg1    = "rgb(ebdbb2)",
    fg0    = "rgb(fbf1c7)",
    red    = "rgb(cc241d)",
    green  = "rgb(b8bb26)",
    yellow = "rgb(fabd2f)",
    blue   = "rgb(83a598)",
    purple = "rgb(d3869b)",
    aqua   = "rgb(83c07c)",
    orange = "rgb(d65d0e)",
}
