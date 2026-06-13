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
	-- Dimensions / colour
	"-ImageSize", "-Megapixels", "-ColorSpace", "-BitDepth", "-BitsPerSample",
	-- Descriptive: titles, captions, comments, keywords, authorship
	"-Title", "-ObjectName", "-Headline",
	"-ImageDescription", "-Caption-Abstract", "-Description",
	"-UserComment", "-Comment", "-Keywords", "-Subject",
	"-Creator", "-By-line",
	-- Camera
	"-Make", "-Model", "-LensModel", "-LensID",
	-- Exposure
	"-FNumber", "-ExposureTime", "-ISO", "-FocalLength", "-FocalLengthIn35mmFormat",
	"-ExposureCompensation", "-Flash", "-WhiteBalance",
	-- Time
	"-DateTimeOriginal", "-CreateDate",
	-- Location
	"-GPSPosition", "-GPSAltitude",
	-- Misc
	"-Software", "-Artist", "-Copyright", "-Orientation", "-Rating",
}

-- Your primary display (AORUS FO32U2 = 4K). Edit if it ever changes.
local SCREEN_W, SCREEN_H = 3840, 2160

local function gcd(a, b)
	while b ~= 0 do
		a, b = b, a % b
	end
	return a
end

local function round(x)
	return math.floor(x + 0.5)
end

-- Verdict on how a w×h image lands on the 4K screen: aspect ratio, the actual
-- pixel size it occupies fullscreen (contain-fit, aspect preserved), the bars
-- that leaves, and whether filling the screen needs upscaling (= soft).
local function display_rows(w, h)
	if not w or not h or w <= 0 or h <= 0 then
		return {}
	end

	local g = gcd(w, h)
	local aspect = string.format("%d:%d  (%.2f)", math.floor(w / g), math.floor(h / g), w / h)

	-- contain-fit: scale so the whole image fits inside the screen
	local scale = math.min(SCREEN_W / w, SCREEN_H / h)
	local dw, dh = round(w * scale), round(h * scale)

	local fits
	if dw >= SCREEN_W and dh >= SCREEN_H then
		fits = string.format("%dx%d  (fills screen)", dw, dh)
	elseif dw < SCREEN_W then
		fits = string.format("%dx%d  (pillarboxed, %dpx side bars)", dw, dh, SCREEN_W - dw)
	else
		fits = string.format("%dx%d  (letterboxed, %dpx bars)", dw, dh, SCREEN_H - dh)
	end

	-- scale <= 1 means at least one dimension already meets the screen, so the
	-- fullscreen fit downscales (or is exact) and stays sharp; > 1 means upscaling.
	local ready
	if scale <= 1.0 then
		ready = "yes - sharp at fullscreen"
	else
		ready = string.format("no - upscales x%.2f (soft)", scale)
	end

	return {
		ui.Row({ string.format("Display (%dx%d)", SCREEN_W, SCREEN_H) }):style(ui.Style():fg("green")),
		ui.Row { "  Aspect:", aspect },
		ui.Row { "  Fullscreen:", fits },
		ui.Row { "  4K-ready:", ready },
	}
end

-- exiftool isn't always on PATH for GUI/uwsm-spawned processes (Arch only adds
-- /usr/bin/vendor_perl via perlbin.sh in login shells), so fall back to it.
local EXIFTOOL = { "exiftool", "/usr/bin/vendor_perl/exiftool" }

local function exif_rows(job)
	local args = { "-S", "-fast", "-sep", ", ", "-charset", "filename=utf8" }
	for _, t in ipairs(TAGS) do
		args[#args + 1] = t
	end
	args[#args + 1] = tostring(job.file.url)

	local stdout
	for _, bin in ipairs(EXIFTOOL) do
		local output = Command(bin):arg(args):stdout(Command.PIPED):stderr(Command.NULL):output()
		if output and output.stdout ~= "" then
			stdout = output.stdout
			break
		end
	end
	if not stdout then
		return {} -- exiftool not found, or the file carries none of these tags
	end

	local rows = { ui.Row({ "EXIF" }):style(ui.Style():fg("green")) }
	for line in stdout:gmatch("[^\r\n]+") do
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

	-- 4K display verdict (aspect / fullscreen fit / sharpness).
	local info = ya.image_info(job.file.url)
	if info then
		local drows = display_rows(info.w, info.h)
		for _, r in ipairs(drows) do
			rows[#rows + 1] = r
		end
		if #drows > 0 then
			rows[#rows + 1] = ui.Row {}
		end
	end

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
