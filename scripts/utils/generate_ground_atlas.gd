extends SceneTree
## Headless script — run via:
##   godot --headless --script scripts/utils/generate_ground_atlas.gd
##
## Produces ground_tiles.png — a 192x16 atlas with 12 top-down floor tiles:
##   cols 0-2: dirt variants
##   cols 3-5: sand variants
##   cols 6-8: stone variants
##   cols 9-11: grass variants
##
## Tiles are intentionally subtle — low contrast, soft noise —
## so they read as background floor rather than foreground objects.

const TW: int = 16
const COLS: int = 12


func _init() -> void:
	var img := Image.create(TW * COLS, TW, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	_draw_dirt(img, 0, 0.00)
	_draw_dirt(img, 1, 0.04)
	_draw_dirt(img, 2, -0.03)

	_draw_sand(img, 3, 0.00)
	_draw_sand(img, 4, 0.05)
	_draw_sand(img, 5, -0.04)

	_draw_stone(img, 6, 0.00)
	_draw_stone(img, 7, 0.03)
	_draw_stone(img, 8, -0.03)

	_draw_grass(img, 9, 0.00)
	_draw_grass(img, 10, 0.04)
	_draw_grass(img, 11, -0.03)

	img.save_png("res://assets/tilesets/ground_tiles.png")
	print("Saved ground_tiles.png (%dx%d)" % [TW * COLS, TW])
	quit()


# --- Shared helpers ---


## Fills a tile with a flat base color, then adds very subtle per-pixel noise.
## brightness_shift nudges each variant slightly lighter or darker.
func _soft_fill(img: Image, col: int, base: Color, shift: float, seed_offset: int) -> void:
	var ox: int = col * TW
	for y in range(TW):
		for x in range(TW):
			# Tiny deterministic brightness jitter — stays within ±4%.
			var jitter: float = (((x * 7 + y * 13 + seed_offset) % 17) / 17.0 - 0.5) * 0.08
			var c := base.lightened(shift + jitter)
			img.set_pixel(ox + x, y, c)


## Draws a single subtle speckling dot (2x2 max, low opacity blend).
func _speck(img: Image, x: int, y: int, c: Color, strength: float) -> void:
	if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
		img.set_pixel(x, y, img.get_pixel(x, y).lerp(c, strength))


# --- Ground tile drawers ---


func _draw_dirt(img: Image, col: int, shift: float) -> void:
	var base := Color(0.46, 0.30, 0.16)
	var dark := Color(0.32, 0.20, 0.10)
	var light := Color(0.58, 0.40, 0.22)
	_soft_fill(img, col, base, shift, col * 3)
	var ox: int = col * TW
	# A few low-contrast pebble specks — no hard edges.
	for data in [[3, 5], [9, 3], [5, 11], [12, 8], [7, 13], [1, 9]]:
		_speck(img, ox + data[0], data[1], dark, 0.22)
		_speck(img, ox + data[0] + 1, data[1], light, 0.14)


func _draw_sand(img: Image, col: int, shift: float) -> void:
	var base := Color(0.80, 0.71, 0.50)
	var dark := Color(0.68, 0.60, 0.40)
	var light := Color(0.88, 0.80, 0.60)
	_soft_fill(img, col, base, shift, col * 3 + 1)
	var ox: int = col * TW
	# Soft ripple hints — very low contrast.
	for x in range(1, TW - 1):
		_speck(img, ox + x, 5, dark, 0.10)
		_speck(img, ox + x, 11, dark, 0.08)
	# Grain specks.
	for data in [[4, 3], [10, 7], [6, 12], [13, 4], [2, 10]]:
		_speck(img, ox + data[0], data[1], light, 0.18)


func _draw_stone(img: Image, col: int, shift: float) -> void:
	var base := Color(0.50, 0.50, 0.54)
	var dark := Color(0.38, 0.38, 0.42)
	var light := Color(0.62, 0.62, 0.65)
	_soft_fill(img, col, base, shift, col * 3 + 2)
	var ox: int = col * TW
	# One subtle hairline crack per variant — changes direction per variant.
	var crack_start_x: int = [3, 8, 2][col % 3]
	var crack_start_y: int = [4, 7, 3][col % 3]
	for i in range(4):
		_speck(img, ox + crack_start_x + i, crack_start_y + i, dark, 0.28)
	# Corner highlight.
	_speck(img, ox + 1, 1, light, 0.20)
	_speck(img, ox + 2, 1, light, 0.14)
	_speck(img, ox + 1, 2, light, 0.14)


func _draw_grass(img: Image, col: int, shift: float) -> void:
	var base := Color(0.28, 0.55, 0.20)
	var dark := Color(0.18, 0.42, 0.13)
	var light := Color(0.38, 0.66, 0.27)
	_soft_fill(img, col, base, shift, col * 3 + 3)
	var ox: int = col * TW
	# Scattered blade-tip specks — subtle bright pixels.
	var blade_positions: Array = [[2, 4], [6, 2], [10, 5], [14, 3], [4, 10], [8, 13], [12, 9], [1, 13]]
	for i in range(blade_positions.size()):
		if i % 3 == col % 3:
			_speck(img, ox + blade_positions[i][0], blade_positions[i][1], light, 0.30)
		else:
			_speck(img, ox + blade_positions[i][0], blade_positions[i][1], dark, 0.18)
