-- exif.yazi — richer image spot panel.
--
-- Press Tab while hovering an image to open it. Shows the built-in native info
-- (Format / Size / Color) plus a curated EXIF table read via `exiftool`, then
-- the generic file info (location, mime, modified, ...).
--
-- Degrades gracefully: if `exiftool` is missing or the file has no EXIF, you
-- still get exactly what the stock image spotter shows.

local M = {}

-- Curated, broadly-interesting tags. exiftool only emits tags that exist, so
-- the list self-filters per file (PNGs surface a few, camera JPEGs surface many).
local TAGS = {
	"-ImageSize", "-Megapixels", "-ColorSpace", "-BitDepth", "-BitsPerSample",
	"-Make", "-Model", "-LensModel", "-LensID",
	"-FNumber", "-ExposureTime", "-ISO", "-FocalLength", "-FocalLengthIn35mmFormat",
	"-ExposureCompensation", "-Flash", "-WhiteBalance",
	"-DateTimeOriginal", "-CreateDate",
	"-GPSPosition", "-GPSAltitude",
	"-Software", "-Artist", "-Copyright", "-Orientation", "-Rating",
}

local function exif_rows(job)
	local args = { "-S", "-fast2", "-charset", "filename=utf8" }
	for _, t in ipairs(TAGS) do
		args[#args + 1] = t
	end
	args[#args + 1] = tostring(job.file.url)

	local output = Command("exiftool"):arg(args):stdout(Command.PIPED):stderr(Command.NULL):output()
	if not output or output.stdout == "" then
		return {} -- exiftool not installed, or produced nothing
	end

	local rows = { ui.Row({ "EXIF" }):style(ui.Style():fg("green")) }
	for line in output.stdout:gmatch("[^\r\n]+") do
		local key, val = line:match("^(.-):%s*(.*)$")
		if key and val and val ~= "" then
			rows[#rows + 1] = ui.Row { "  " .. key .. ":", val }
		end
	end

	-- Only the header survived -> nothing useful, drop it entirely.
	return #rows > 1 and rows or {}
end

function M:spot(job)
	-- Native image info (Format / Size / Color), same as the stock spotter.
	local rows = require("image"):spot_base(job)
	rows[#rows + 1] = ui.Row {}

	local ex = exif_rows(job)
	for _, r in ipairs(ex) do
		rows[#rows + 1] = r
	end
	if #ex > 0 then
		rows[#rows + 1] = ui.Row {}
	end

	ya.spot_table(
		job,
		ui.Table(ya.list_merge(rows, require("file"):spot_base(job)))
			:area(ui.Pos { "center", w = 70, h = 24 })
			:row(job.skip)
			:row(1)
			:col(1)
			:col_style(th.spot.tbl_col)
			:cell_style(th.spot.tbl_cell)
			:widths { ui.Constraint.Length(22), ui.Constraint.Fill(1) }
	)
end

return M
