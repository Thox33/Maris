extends Node

const TARGET_KIND_TILE := "tile"
const TARGET_KIND_STRUCTURE := "structure"

var world: Node2D
var _visual_root: Node2D
var _crack_texture: Texture2D
var _visuals_by_key: Dictionary = {}


func setup(p_world: Node2D) -> void:
	world = p_world
	_ensure_visual_root()
	_ensure_crack_texture()


func apply_damaged_target(target_key: String, target_data: Dictionary) -> void:
	if world == null:
		return
	_ensure_visual_root()
	_ensure_crack_texture()

	var cells := _resolve_cells(target_data)
	if cells.is_empty():
		clear_damaged_target(target_key)
		return

	var sprites := _ensure_sprites(target_key, cells.size())
	for i in range(cells.size()):
		var sprite := sprites[i] as Sprite2D
		sprite.global_position = _cell_center(cells[i])
		sprite.frame = clampi(int(target_data.get("stage", 0)), 0, GameConstants.BREAK_STAGE_COUNT - 1)
		sprite.visible = true


func clear_damaged_target(target_key: String) -> void:
	var sprites := _visuals_by_key.get(target_key, []) as Array
	for sprite_variant in sprites:
		if sprite_variant is Node:
			(sprite_variant as Node).queue_free()
	_visuals_by_key.erase(target_key)


func _resolve_cells(target_data: Dictionary) -> Array[Vector2i]:
	if String(target_data.get("kind", "")) == TARGET_KIND_TILE:
		return [Vector2i(int(target_data.get("coord_x", 0)), int(target_data.get("coord_y", 0)))]

	var structure_id := String(target_data.get("structure_id", ""))
	var definition := StructureCatalog.get_definition(structure_id)
	if definition == null:
		return []
	return definition.get_breakable_world_cells(
		Vector2i(int(target_data.get("origin_x", 0)), int(target_data.get("origin_y", 0)))
	)


func _ensure_sprites(target_key: String, count: int) -> Array:
	var existing := _visuals_by_key.get(target_key, []) as Array
	if existing.size() == count:
		return existing

	clear_damaged_target(target_key)
	var sprites: Array = []
	for _i in range(count):
		var sprite := Sprite2D.new()
		sprite.texture = _crack_texture
		sprite.hframes = GameConstants.BREAK_STAGE_COUNT
		sprite.z_index = 30
		_visual_root.add_child(sprite)
		sprites.append(sprite)
	_visuals_by_key[target_key] = sprites
	return sprites


func _ensure_visual_root() -> void:
	if world == null:
		return
	if _visual_root != null and is_instance_valid(_visual_root):
		return
	_visual_root = world.get_node_or_null("DepthSorted/BreakVisuals")
	if _visual_root == null:
		_visual_root = Node2D.new()
		_visual_root.name = "BreakVisuals"
		world.get_node("DepthSorted").add_child(_visual_root)


func _ensure_crack_texture() -> void:
	if _crack_texture != null:
		return

	var frame_count: int = GameConstants.BREAK_STAGE_COUNT
	var size: int = GameConstants.TILE_SIZE
	var img := Image.create(size * frame_count, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var crack_color := Color(0.05, 0.08, 0.12, 0.72)
	var center := Vector2(float(size - 1) / 2.0, float(size - 1) / 2.0)
	for frame in range(frame_count):
		var offset_x: int = frame * size
		var progress := float(frame + 1) / float(frame_count)
		var primary_branches: int = 4 + frame
		for branch in range(primary_branches):
			var angle := (TAU * float(branch) / float(primary_branches)) + randf_range(-0.22, 0.22)
			var branch_length := lerpf(2.5, float(size) * 0.48, progress) + randf_range(-1.0, 1.0)
			_draw_crack_branch(img, offset_x, center, angle, branch_length, crack_color, progress)

			if frame >= 2:
				var split_count: int = 1 + int(progress * 2.0)
				for _split in range(split_count):
					var split_distance := branch_length * randf_range(0.35, 0.8)
					var split_origin := center + Vector2.from_angle(angle) * split_distance
					var split_angle := angle + randf_range(-0.9, 0.9)
					var split_length := branch_length * randf_range(0.2, 0.45)
					_draw_crack_branch(
						img,
						offset_x,
						split_origin,
						split_angle,
						split_length,
						crack_color,
						progress * 0.85
					)

	_crack_texture = ImageTexture.create_from_image(img)


func _cell_center(coord: Vector2i) -> Vector2:
	return Vector2(
		coord.x * GameConstants.TILE_SIZE + GameConstants.TILE_SIZE / 2.0,
		coord.y * GameConstants.TILE_SIZE + GameConstants.TILE_SIZE / 2.0
	)


func _draw_crack_branch(
	img: Image,
	offset_x: int,
	start: Vector2,
	angle: float,
	length: float,
	color: Color,
	progress: float,
) -> void:
	var direction := Vector2.from_angle(angle)
	var position_on_branch := start
	var steps := maxi(int(length * 1.6), 1)

	for step in range(steps):
		var t := float(step) / float(steps)
		var wiggle := sin(t * PI * 2.0) * lerpf(0.1, 0.65, progress)
		position_on_branch += direction * (length / float(steps))
		position_on_branch += direction.orthogonal() * wiggle * 0.12

		var px := clampi(int(round(position_on_branch.x)), 0, GameConstants.TILE_SIZE - 1)
		var py := clampi(int(round(position_on_branch.y)), 0, GameConstants.TILE_SIZE - 1)
		img.set_pixel(offset_x + px, py, color)

		if progress > 0.45 and px + 1 < GameConstants.TILE_SIZE:
			img.set_pixel(offset_x + px + 1, py, color)
		if progress > 0.7 and py + 1 < GameConstants.TILE_SIZE:
			img.set_pixel(offset_x + px, py + 1, color)
