-- chafa.yazi — high-fidelity block-art image previews for terminals with no
-- graphics protocol (Alacritty has neither Sixel nor the Kitty graphics
-- protocol, so Yazi's built-in `image` previewer draws nothing here).
--
-- This renders every image with chafa's densest sub-cell block glyphs
-- (octants = 2x4 subpixels per cell) in 24-bit colour, so on a powerful box
-- you get "loads of blocks" that approximate the real image closely.
--
-- Routed via `prepend_previewers = [{ mime = "image/*", run = "chafa" }]` in
-- yazi.toml so it wins over the stock (graphics-only) image previewer.
--
-- Tuning knobs live in CFG below. If you ever move to a graphics-capable
-- terminal (kitty/ghostty/foot), delete the prepend_previewers line and this
-- plugin is bypassed automatically.

local M = {}

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
