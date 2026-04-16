extends Node
const WORLD_PROP_CATALOG := preload("res://scripts/world/world_prop_catalog.gd")

const TARGET_KIND_TILE := "tile"
const TARGET_KIND_PROP := "prop"
const TARGET_KIND_STRUCTURE := "structure"

const _SAMPLE_COUNT: int = 12
const _PARTICLE_COUNT: int = 24
const _PARTICLE_SPEED_MIN: float = 12.0
const _PARTICLE_SPEED_MAX: float = 38.0
const _PARTICLE_LIFETIME_MIN: float = 0.3
const _PARTICLE_LIFETIME_MAX: float = 0.55

var world: Node2D
var _visual_parent: Node2D
var _visual_root: Node2D
var _crack_texture: Texture2D
var _visuals_by_key: Dictionary = {}
var _tile_colors_cache: Dictionary = {}
var _atlas_image_cache: Dictionary = {}
var _pixel_texture: ImageTexture = null


func setup(p_world: Node2D, p_visual_parent: Node2D) -> void:
	world = p_world
	_visual_parent = p_visual_parent
	_ensure_visual_root()
	_ensure_crack_texture()
	GameEvents.block_broken.connect(_on_block_broken)
	GameEvents.prop_broken.connect(_on_prop_broken)
	GameEvents.structure_broken.connect(_on_structure_broken)


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
	if (
		String(target_data.get("kind", "")) == TARGET_KIND_TILE
		or String(target_data.get("kind", "")) == TARGET_KIND_PROP
	):
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
	if _visual_parent == null:
		return
	_visual_root = Node2D.new()
	_visual_root.name = "BreakVisuals"
	_visual_parent.add_child(_visual_root)


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


func _on_block_broken(coord: Vector2i, tile_id: int) -> void:
	_spawn_break_particles(_cell_center(coord), _sample_tile_colors(tile_id))


func _on_structure_broken(structure_id: String, world_pos: Vector2) -> void:
	_spawn_break_particles(world_pos, _sample_structure_colors(structure_id))


func _on_prop_broken(coord: Vector2i, prop_id: int) -> void:
	_spawn_break_particles(_cell_center(coord), _sample_prop_colors(prop_id))


func _sample_tile_colors(tile_id: int) -> Array[Color]:
	if _tile_colors_cache.has(tile_id):
		return _tile_colors_cache[tile_id]

	var props := TileProperties.get_properties(tile_id)
	if props == null:
		return [Color.WHITE]

	var atlas_path := "res://assets/tilesets/terrain_tiles.png"
	var image := _load_atlas_image(atlas_path)
	if image == null:
		return [Color.WHITE]

	var ts := GameConstants.TILE_SIZE
	var region_x := props.atlas_coord.x * ts
	var region_y := props.atlas_coord.y * ts
	var sampled := _sample_region(image, region_x, region_y, ts, ts)

	_tile_colors_cache[tile_id] = sampled
	return sampled


func _sample_structure_colors(structure_id: String) -> Array[Color]:
	if _tile_colors_cache.has("s:" + structure_id):
		return _tile_colors_cache["s:" + structure_id]

	var definition := StructureCatalog.get_definition(structure_id)
	if definition == null or definition.visual_parts.is_empty():
		return [Color.WHITE]

	var image := _load_atlas_image(definition.atlas_texture_path)
	if image == null:
		return [Color.WHITE]

	var ts := GameConstants.TILE_SIZE
	var all_pixels: Array[Color] = []
	for part in definition.visual_parts:
		var coord := part.get("atlas_coord", Vector2i.ZERO) as Vector2i
		var part_pixels := _sample_region(image, coord.x * ts, coord.y * ts, ts, ts)
		all_pixels.append_array(part_pixels)

	# Shuffle and trim to _SAMPLE_COUNT so all parts contribute roughly equally.
	all_pixels.shuffle()
	var sampled: Array[Color] = all_pixels.slice(0, _SAMPLE_COUNT)
	if sampled.is_empty():
		sampled.append(Color.WHITE)

	_tile_colors_cache["s:" + structure_id] = sampled
	return sampled


func _sample_prop_colors(prop_id: int) -> Array[Color]:
	var cache_key := "p:%s" % prop_id
	if _tile_colors_cache.has(cache_key):
		return _tile_colors_cache[cache_key]

	var definition = WORLD_PROP_CATALOG.get_definition(prop_id)
	if definition == null:
		return [Color.WHITE]

	var image := _load_atlas_image(definition.atlas_texture_path)
	if image == null:
		return [Color.WHITE]

	var ts := GameConstants.TILE_SIZE
	var sampled := _sample_region(
		image,
		definition.atlas_coord.x * ts,
		definition.atlas_coord.y * ts,
		ts,
		ts
	)
	_tile_colors_cache[cache_key] = sampled
	return sampled


func _spawn_break_particles(center: Vector2, colors: Array[Color]) -> void:
	_ensure_visual_root()
	if _visual_root == null:
		return

	for i in range(_PARTICLE_COUNT):
		var angle := randf() * TAU
		var speed := randf_range(_PARTICLE_SPEED_MIN, _PARTICLE_SPEED_MAX)
		var end_pos := center + Vector2.from_angle(angle) * speed
		var duration := randf_range(_PARTICLE_LIFETIME_MIN, _PARTICLE_LIFETIME_MAX)

		var sprite := Sprite2D.new()
		sprite.texture = _get_pixel_texture()
		sprite.modulate = colors[i % colors.size()]
		sprite.scale = Vector2(2.0, 2.0)
		sprite.z_index = 25
		_visual_root.add_child(sprite)
		sprite.global_position = center

		var tween := sprite.create_tween()
		tween.set_parallel(true)
		(
			tween
			. tween_property(sprite, "global_position", end_pos, duration)
			. set_trans(Tween.TRANS_QUAD)
			. set_ease(Tween.EASE_OUT)
		)
		tween.tween_property(sprite, "modulate:a", 0.0, duration)
		tween.set_parallel(false)
		tween.tween_callback(sprite.queue_free)


func _load_atlas_image(atlas_path: String) -> Image:
	if _atlas_image_cache.has(atlas_path):
		return _atlas_image_cache[atlas_path]
	var tex := load(atlas_path) as Texture2D
	var image: Image = tex.get_image() if tex != null else null
	_atlas_image_cache[atlas_path] = image
	return image


func _sample_region(image: Image, region_x: int, region_y: int, w: int, h: int) -> Array[Color]:
	var sampled: Array[Color] = []
	var attempts := 0
	while sampled.size() < _SAMPLE_COUNT and attempts < 300:
		attempts += 1
		var px := region_x + randi() % w
		var py := region_y + randi() % h
		if px < image.get_width() and py < image.get_height():
			var color := image.get_pixel(px, py)
			if color.a > 0.5:
				sampled.append(color)
	if sampled.is_empty():
		sampled.append(Color.WHITE)
	return sampled


func _get_pixel_texture() -> ImageTexture:
	if _pixel_texture != null:
		return _pixel_texture
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color.WHITE)
	_pixel_texture = ImageTexture.create_from_image(img)
	return _pixel_texture
