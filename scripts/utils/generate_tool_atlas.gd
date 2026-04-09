extends SceneTree

const TILE_SIZE := 16
const COLUMNS := 4
const ROWS := 1
const OUTPUT_PATH := "res://assets/tilesets/tool_items.png"


func _initialize() -> void:
	var image := Image.create(TILE_SIZE * COLUMNS, TILE_SIZE * ROWS, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))

	_draw_stone_pickaxe(image, Vector2i.ZERO)

	var error := image.save_png(OUTPUT_PATH)
	if error != OK:
		push_error("Failed to save tool atlas: %s" % error_string(error))
		quit(error)
		return

	print("Saved tool atlas to %s" % OUTPUT_PATH)
	quit()


func _draw_stone_pickaxe(image: Image, cell: Vector2i) -> void:
	var origin := cell * TILE_SIZE

	var wood_light := Color8(150, 96, 53, 255)
	var wood_dark := Color8(97, 61, 31, 255)
	var stone_light := Color8(154, 165, 176, 255)
	var stone_mid := Color8(116, 126, 136, 255)
	var stone_dark := Color8(69, 78, 88, 255)

	var handle_points := [
		Vector2i(11, 13),
		Vector2i(10, 12),
		Vector2i(9, 11),
		Vector2i(8, 10),
		Vector2i(7, 9),
		Vector2i(6, 8),
		Vector2i(5, 7),
		Vector2i(4, 6),
	]
	for point in handle_points:
		_set_tool_px(image, origin, point, wood_light)
		_set_tool_px(image, origin, point + Vector2i(0, 1), wood_dark)

	var head_light := [
		Vector2i(3, 3),
		Vector2i(4, 2),
		Vector2i(5, 2),
		Vector2i(6, 3),
		Vector2i(5, 4),
		Vector2i(4, 4),
		Vector2i(2, 4),
		Vector2i(3, 4),
	]
	for point in head_light:
		_set_tool_px(image, origin, point, stone_light)

	var head_mid := [
		Vector2i(2, 5),
		Vector2i(3, 5),
		Vector2i(4, 5),
		Vector2i(5, 5),
		Vector2i(6, 4),
		Vector2i(7, 4),
		Vector2i(6, 2),
		Vector2i(7, 3),
	]
	for point in head_mid:
		_set_tool_px(image, origin, point, stone_mid)

	var head_dark := [
		Vector2i(1, 5),
		Vector2i(2, 6),
		Vector2i(3, 6),
		Vector2i(4, 6),
		Vector2i(5, 6),
		Vector2i(6, 5),
		Vector2i(7, 5),
		Vector2i(8, 4),
		Vector2i(8, 3),
		Vector2i(7, 2),
	]
	for point in head_dark:
		_set_tool_px(image, origin, point, stone_dark)

	var highlight_points := [
		Vector2i(6, 1),
		Vector2i(5, 1),
		Vector2i(4, 1),
		Vector2i(3, 2),
	]
	for point in highlight_points:
		_set_tool_px(image, origin, point, Color8(197, 205, 214, 255))


func _set_tool_px(image: Image, origin: Vector2i, local_point: Vector2i, color: Color) -> void:
	var mirrored_point := Vector2i(TILE_SIZE - 1 - local_point.x, local_point.y)
	_set_px(image, origin + mirrored_point, color)


func _set_px(image: Image, point: Vector2i, color: Color) -> void:
	if point.x < 0 or point.y < 0 or point.x >= image.get_width() or point.y >= image.get_height():
		return
	image.set_pixelv(point, color)
