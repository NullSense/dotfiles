-- Forked from omarchy's default/elephant/omarchy_background_selector.lua
-- Adds ~/Pictures/backgrounds/ and ~/Pictures/harpe/ as extra sources so
-- personal + harpe-art wallpapers show up in the Style → Background picker
-- for every theme. harpe is a nested website-dump tree, so the find below
-- recurses (maxdepth 4) instead of the upstream maxdepth 1.
-- Re-sync from upstream periodically; the only diffs are the extra `dirs`
-- entries and the maxdepth bump below.

Name = "omarchyBackgroundSelector"
NamePretty = "Omarchy Background Selector"
Cache = false
HideFromProviderlist = true
SearchName = true

local function ShellEscape(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

function FormatName(filename)
  -- Remove leading number and dash
  local name = filename:gsub("^%d+", ""):gsub("^%-", "")
  -- Remove extension
  name = name:gsub("%.[^%.]+$", "")
  -- Replace dashes with spaces
  name = name:gsub("-", " ")
  -- Capitalize each word
  name = name:gsub("%S+", function(word)
    return word:sub(1, 1):upper() .. word:sub(2):lower()
  end)
  return name
end

function GetEntries()
  local entries = {}
  local home = os.getenv("HOME")

  -- Read current theme name
  local theme_name_file = io.open(home .. "/.config/omarchy/current/theme.name", "r")
  local theme_name = theme_name_file and theme_name_file:read("*l") or nil
  if theme_name_file then
    theme_name_file:close()
  end

  -- Directories to search
  local dirs = {
    home .. "/.config/omarchy/current/theme/backgrounds",
    home .. "/Pictures/backgrounds", -- personal pool, theme-agnostic
    home .. "/Pictures/harpe",       -- harpe-art dump, theme-agnostic (recursed)
  }
  if theme_name then
    table.insert(dirs, home .. "/.config/omarchy/backgrounds/" .. theme_name)
  end

  -- Track added files to avoid duplicates
  local seen = {}

  for _, wallpaper_dir in ipairs(dirs) do
    local handle = io.popen(
      "find -L " .. ShellEscape(wallpaper_dir)
        .. " -maxdepth 4 -type f \\( -name '*.jpg' -o -name '*.jpeg' -o -name '*.png' -o -name '*.gif' -o -name '*.bmp' -o -name '*.webp' \\) 2>/dev/null | sort"
    )
    if handle then
      for background in handle:lines() do
        local filename = background:match("([^/]+)$")
        if filename and not seen[filename] then
          seen[filename] = true
          table.insert(entries, {
            Text = FormatName(filename),
            Value = background,
            Actions = {
              activate = "omarchy-theme-bg-set " .. ShellEscape(background),
            },
            Preview = background,
            PreviewType = "file",
          })
        end
      end
      handle:close()
    end
  end

  return entries
end
