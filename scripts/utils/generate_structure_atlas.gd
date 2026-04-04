extends SceneTree
## Headless generator for large-structure placeholder art.

const TILE_SIZE := 16
const COLS := 2
const ROWS := 3
const ATLAS_PATH := "res://assets/tilesets/structure_tiles.png"
const PREVIEW_PATH := "res://assets/tilesets/large_furnace_preview.png"


func _initialize() -> void:
	_generate_structure_atlas()
	_generate_furnace_preview()
	quit()


func _generate_structure_atlas() -> void:
	var img := Image.create(TILE_SIZE * COLS, TILE_SIZE * ROWS, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	_draw_furnace_top_left(img)
	_draw_furnace_top_right(img)
	_draw_furnace_mid_left(img)
	_draw_furnace_mid_right(img)
	_draw_furnace_bottom_left(img)
	_draw_furnace_bottom_right(img)

	img.save_png(ATLAS_PATH)
	print("Saved structure atlas to %s" % ATLAS_PATH)


func _generate_furnace_preview() -> void:
	var atlas := Image.load_from_file(ProjectSettings.globalize_path(ATLAS_PATH))
	if atlas == null:
		push_error("Failed to load generated structure atlas")
		return

	var preview := Image.create(2 * TILE_SIZE, 3 * TILE_SIZE, false, Image.FORMAT_RGBA8)
	preview.fill(Color(0, 0, 0, 0))

	for y in range(ROWS):
		for x in range(COLS):
			_blit_tile(atlas, Vector2i(x, y), preview, Vector2i(x, y))

	preview.save_png(PREVIEW_PATH)
	print("Saved furnace preview to %s" % PREVIEW_PATH)


func _draw_furnace_top_left(img: Image) -> void:
	var ox := 0
	var oy := 0
	var frame := Color(0.13, 0.12, 0.14)
	var brass := Color(0.58, 0.42, 0.18)
	var brass_light := Color(0.76, 0.62, 0.28)
	var vent := Color(0.37, 0.36, 0.40)

	_fill_rect(img, Rect2i(ox + 3, oy + 10, 13, 6), frame)
	_fill_rect(img, Rect2i(ox + 4, oy + 11, 12, 4), brass)
	_fill_rect(img, Rect2i(ox + 4, oy + 11, 12, 1), brass_light)
	_fill_rect(img, Rect2i(ox + 9, oy + 2, 5, 8), frame)
	_fill_rect(img, Rect2i(ox + 10, oy + 3, 3, 7), vent)
	_fill_rect(img, Rect2i(ox + 5, oy + 12, 3, 2), vent)


func _draw_furnace_top_right(img: Image) -> void:
	var ox := TILE_SIZE
	var oy := 0
	var frame := Color(0.13, 0.12, 0.14)
	var brass := Color(0.58, 0.42, 0.18)
	var brass_light := Color(0.76, 0.62, 0.28)
	var vent := Color(0.37, 0.36, 0.40)
	var smoke := Color(0.70, 0.68, 0.64)

	_fill_rect(img, Rect2i(ox, oy + 10, 13, 6), frame)
	_fill_rect(img, Rect2i(ox, oy + 11, 12, 4), brass)
	_fill_rect(img, Rect2i(ox, oy + 11, 12, 1), brass_light)
	_fill_rect(img, Rect2i(ox + 2, oy + 1, 6, 9), frame)
	_fill_rect(img, Rect2i(ox + 3, oy + 2, 4, 7), vent)
	_fill_rect(img, Rect2i(ox + 4, oy, 2, 2), smoke)
	_fill_rect(img, Rect2i(ox + 5, oy + 12, 3, 2), vent)


func _draw_furnace_mid_left(img: Image) -> void:
	var ox := 0
	var oy := TILE_SIZE
	var frame := Color(0.16, 0.14, 0.15)
	var body := Color(0.48, 0.27, 0.16)
	var body_light := Color(0.66, 0.39, 0.22)
	var plate := Color(0.34, 0.33, 0.37)

	_fill_rect(img, Rect2i(ox + 1, oy, 15, 16), frame)
	_fill_rect(img, Rect2i(ox + 2, oy, 14, 15), body)
	_fill_rect(img, Rect2i(ox + 2, oy, 14, 2), body_light)
	_fill_rect(img, Rect2i(ox + 4, oy + 5, 12, 6), plate)
	_fill_rect(img, Rect2i(ox + 5, oy + 6, 11, 4), Color(0.22, 0.22, 0.24))
	_fill_rect(img, Rect2i(ox + 12, oy + 3, 2, 3), plate)


func _draw_furnace_mid_right(img: Image) -> void:
	var ox := TILE_SIZE
	var oy := TILE_SIZE
	var frame := Color(0.16, 0.14, 0.15)
	var body := Color(0.48, 0.27, 0.16)
	var body_light := Color(0.66, 0.39, 0.22)
	var plate := Color(0.34, 0.33, 0.37)

	_fill_rect(img, Rect2i(ox, oy, 15, 16), frame)
	_fill_rect(img, Rect2i(ox, oy, 14, 15), body)
	_fill_rect(img, Rect2i(ox, oy, 14, 2), body_light)
	_fill_rect(img, Rect2i(ox, oy + 5, 12, 6), plate)
	_fill_rect(img, Rect2i(ox, oy + 6, 11, 4), Color(0.22, 0.22, 0.24))
	_fill_rect(img, Rect2i(ox + 2, oy + 3, 2, 3), plate)


func _draw_furnace_bottom_left(img: Image) -> void:
	var ox := 0
	var oy := TILE_SIZE * 2
	var frame := Color(0.16, 0.14, 0.15)
	var body := Color(0.44, 0.23, 0.14)
	var body_light := Color(0.63, 0.36, 0.20)
	var ember := Color(0.92, 0.45, 0.08)
	var ember_hot := Color(1.00, 0.79, 0.20)

	_fill_rect(img, Rect2i(ox, oy, 16, 16), frame)
	_fill_rect(img, Rect2i(ox + 1, oy + 1, 15, 14), body)
	_fill_rect(img, Rect2i(ox + 1, oy + 1, 15, 2), body_light)
	_fill_rect(img, Rect2i(ox + 3, oy + 5, 13, 7), Color(0.20, 0.12, 0.08))
	_fill_rect(img, Rect2i(ox + 4, oy + 6, 12, 5), ember)
	_fill_rect(img, Rect2i(ox + 7, oy + 7, 6, 3), ember_hot)
	_fill_rect(img, Rect2i(ox + 1, oy + 14, 15, 2), frame)


func _draw_furnace_bottom_right(img: Image) -> void:
	var ox := TILE_SIZE
	var oy := TILE_SIZE * 2
	var frame := Color(0.16, 0.14, 0.15)
	var body := Color(0.44, 0.23, 0.14)
	var body_light := Color(0.63, 0.36, 0.20)
	var ash := Color(0.62, 0.60, 0.56)

	_fill_rect(img, Rect2i(ox, oy, 16, 16), frame)
	_fill_rect(img, Rect2i(ox, oy + 1, 15, 14), body)
	_fill_rect(img, Rect2i(ox, oy + 1, 15, 2), body_light)
	_fill_rect(img, Rect2i(ox, oy + 5, 12, 7), Color(0.20, 0.12, 0.08))
	_fill_rect(img, Rect2i(ox + 2, oy + 6, 3, 5), ash)
	_fill_rect(img, Rect2i(ox + 6, oy + 6, 5, 5), ash)
	_fill_rect(img, Rect2i(ox, oy + 14, 15, 2), frame)


func _fill_rect(img: Image, rect: Rect2i, color: Color) -> void:
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			img.set_pixel(x, y, color)


func _stroke_rect(img: Image, rect: Rect2i, color: Color) -> void:
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		img.set_pixel(x, rect.position.y, color)
		img.set_pixel(x, rect.position.y + rect.size.y - 1, color)
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		img.set_pixel(rect.position.x, y, color)
		img.set_pixel(rect.position.x + rect.size.x - 1, y, color)


func _mirror_tile_horizontally(img: Image, tile_coord: Vector2i) -> void:
	var ox := tile_coord.x * TILE_SIZE
	var oy := tile_coord.y * TILE_SIZE
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE / 2):
			var left := img.get_pixel(ox + x, oy + y)
			var right := img.get_pixel(ox + TILE_SIZE - 1 - x, oy + y)
			img.set_pixel(ox + x, oy + y, right)
			img.set_pixel(ox + TILE_SIZE - 1 - x, oy + y, left)


func _blit_tile(source: Image, source_tile: Vector2i, target: Image, dest_tile: Vector2i) -> void:
	var source_rect := Rect2i(
		source_tile.x * TILE_SIZE,
		source_tile.y * TILE_SIZE,
		TILE_SIZE,
		TILE_SIZE
	)
	target.blit_rect(source, source_rect, Vector2i(dest_tile.x * TILE_SIZE, dest_tile.y * TILE_SIZE))
