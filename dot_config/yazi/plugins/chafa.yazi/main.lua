-- chafa.yazi — terminal-adaptive image previews.
--
-- Routed via `prepend_previewers = [{ mime = "image/*", run = "chafa" }]` in
-- yazi.toml, so it owns image previews. It then picks per terminal:
--
--   * Graphics terminal (kitty/ghostty/wezterm) → hand off to Yazi's built-in
--     `image` previewer, which draws REAL pixels via the terminal's graphics
--     protocol. Use `yk` (kitty -e yazi) to get this on demand.
--   * Everything else (Alacritty has no Sixel / Kitty-graphics protocol) →
--     render chafa's densest sub-cell block glyphs (octants = 2x4 subpixels)
--     in 24-bit colour. "Loads of blocks" that approximate the image.
--
-- Why route chafa here instead of unsetting WAYLAND_DISPLAY to force Yazi's
-- built-in chafa fallback: that env strip would also reach Yazi's openers, so
-- GUI apps launched from Yazi (e.g. the tev image viewer) would lose their
-- Wayland socket. Doing it at the previewer layer leaves Yazi's env untouched.
--
-- Chafa tuning knobs live in CFG below.

local M = {}

-- Terminals whose graphics protocol Yazi can drive natively. In these we defer
-- to the built-in `image` previewer for real pixels; elsewhere we use chafa.
local function graphics_terminal()
	return os.getenv("KITTY_WINDOW_ID") ~= nil -- kitty
		or os.getenv("GHOSTTY_RESOURCES_DIR") ~= nil -- ghostty
		or os.getenv("WEZTERM_PANE") ~= nil -- wezterm
end

-- === tuning ================================================================
local CFG = {
	-- Sub-cell glyphs chafa may use. Pure block family only (no letters /
	-- borders / diagonals), densest first. octant=2x4, sextant=2x3, quad=2x2.
	symbols = "octant+sextant+quad+half+hhalf+vhalf+block+space+solid",
	colors = "full", -- 24-bit truecolor (Alacritty supports it)
	color_space = "din99d", -- perceptual matching (higher quality, more CPU)
	dither = "ordered", -- smooths gradients across the blocks
	work = "9", -- 1..9, max quality/CPU (this box can take it)
	font_ratio = "1/2", -- terminal cell w:h; chafa maps pixels correctly
}
-- ===========================================================================

local function chafa_args(area, url)
	return {
		"--format=symbols",
		"--symbols=" .. CFG.symbols,
		"--colors=" .. CFG.colors,
		"--color-space=" .. CFG.color_space,
		"--dither=" .. CFG.dither,
		"--work=" .. CFG.work,
		"--font-ratio=" .. CFG.font_ratio,
		-- CRITICAL: default --probe=auto writes a capability query to the
		-- controlling terminal and waits up to 5s for the reply. Under Yazi that
		-- reply leaks into stdin as phantom keystrokes (e.g. `d` -> trash prompt).
		-- We force symbols + explicit --size, so the probe is useless. Turn it off.
		"--probe=off",
		"--polite=on", -- don't emit terminal query/control sequences
		"--animate=off", -- first frame only for GIF/WebP
		"--relative=off",
		"--size=" .. area.w .. "x" .. area.h,
		tostring(url),
	}
end

function M:peek(job)
	-- Real pixels when the terminal supports a graphics protocol. Delegate to
	-- Yazi's built-in image previewer; fall through to chafa only if it errors.
	if graphics_terminal() then
		local ok = pcall(function() require("image"):peek(job) end)
		if ok then return end
	end

	local area = job.area
	local output, err = Command("chafa")
		:arg(chafa_args(area, job.file.url))
		:stdout(Command.PIPED)
		:stderr(Command.PIPED)
		:output()

	if not output then
		return ya.preview_widget(job, ui.Text("chafa: failed to spawn (" .. tostring(err) .. ")"):area(area))
	end
	if output.stdout == "" then
		local msg = output.stderr ~= "" and output.stderr or "no output"
		return ya.preview_widget(job, ui.Text("chafa: " .. msg):area(area))
	end

	-- chafa emits ANSI SGR colour + block glyphs; parse it into a coloured Text.
	-- No wrap: each chafa line is already exactly area.w cells wide.
	ya.preview_widget(job, ui.Text.parse(output.stdout):area(area))
end

-- Image previews don't scroll; nothing to do on wheel/seek.
function M:seek() end

return M
