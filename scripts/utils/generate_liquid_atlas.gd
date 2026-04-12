extends SceneTree
## Headless script — run via:
##   godot --headless --script scripts/utils/generate_liquid_atlas.gd
##
## Produces liquid_tiles.png — a 32x16 atlas with 2 animated-base liquid tiles:
##   col 0: water  (blue tones)
##   col 1: lava   (red/orange tones with dark crust patches)
##
## Tiles are intentionally rich in mid-frequency detail so the liquid.gdshader
## shimmer pass has interesting base colours to modulate.

const TW: int = 16


func _init() -> void:
	var img := Image.create(TW * 2, TW, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	_draw_water(img, 0)
	_draw_lava(img, 1)

	img.save_png("res://assets/tilesets/liquid_tiles.png")
	print("Saved liquid_tiles.png (%dx%d)" % [TW * 2, TW])
	quit()


# --- Shared helpers ---


## Fills a tile column with a base colour + subtle per-pixel jitter.
func _soft_fill(img: Image, col: int, base: Color, seed_offset: int) -> void:
	var ox: int = col * TW
	for y in range(TW):
		for x in range(TW):
			var jitter: float = (((x * 7 + y * 13 + seed_offset) % 17) / 17.0 - 0.5) * 0.06
			img.set_pixel(ox + x, y, base.lightened(jitter))


## Blends a rectangle patch onto the tile (for hotspots / crust patches).
func _blend_rect(
	img: Image, col: int, rx: int, ry: int, rw: int, rh: int, c: Color, strength: float
) -> void:
	var ox: int = col * TW
	for dy in range(rh):
		for dx in range(rw):
			var px: int = ox + rx + dx
			var py: int = ry + dy
			if px >= 0 and px < img.get_width() and py >= 0 and py < TW:
				img.set_pixel(px, py, img.get_pixel(px, py).lerp(c, strength))


## Places a single blended speck.
func _speck(img: Image, x: int, y: int, c: Color, strength: float) -> void:
	if x >= 0 and x < img.get_width() and y >= 0 and y < TW:
		img.set_pixel(x, y, img.get_pixel(x, y).lerp(c, strength))


# --- Tile drawers ---


func _draw_water(img: Image, col: int) -> void:
	var base := Color(0.10, 0.28, 0.62)
	var light := Color(0.28, 0.52, 0.85)
	var dark := Color(0.05, 0.16, 0.42)
	var sparkle := Color(0.72, 0.88, 1.0)

	_soft_fill(img, col, base, 0)

	var ox: int = col * TW
	# Horizontal shimmer streaks — lighter bands crossing the tile.
	for x in range(1, TW - 1):
		_speck(img, ox + x, 3, light, 0.20)
		_speck(img, ox + x, 4, light, 0.12)
		_speck(img, ox + x, 10, light, 0.16)
		_speck(img, ox + x, 11, light, 0.08)

	# Slightly darker bottom-right shadow.
	_blend_rect(img, col, 10, 10, 6, 6, dark, 0.18)

	# A handful of bright sparkle specks.
	for data in [[2, 2], [7, 5], [13, 3], [5, 9], [11, 12], [3, 14], [14, 8]]:
		_speck(img, ox + data[0], data[1], sparkle, 0.35)


func _draw_lava(img: Image, col: int) -> void:
	var base := Color(0.72, 0.20, 0.03)
	var hot := Color(1.00, 0.55, 0.05)
	var bright := Color(1.00, 0.88, 0.20)
	var crust := Color(0.20, 0.06, 0.02)

	_soft_fill(img, col, base, 7)

	var ox: int = col * TW
	# Glowing hotspot blobs.
	_blend_rect(img, col, 1, 1, 4, 3, hot, 0.45)
	_blend_rect(img, col, 9, 6, 5, 4, hot, 0.40)
	_blend_rect(img, col, 3, 11, 3, 3, hot, 0.35)

	# Dark cooling crust patches.
	_blend_rect(img, col, 6, 2, 3, 2, crust, 0.50)
	_blend_rect(img, col, 0, 8, 2, 4, crust, 0.45)
	_blend_rect(img, col, 12, 12, 4, 4, crust, 0.40)

	# Bright yellow-white hottest-point specks.
	for data in [[2, 2], [10, 7], [4, 12], [13, 4]]:
		_speck(img, ox + data[0], data[1], bright, 0.55)
