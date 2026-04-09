class_name ItemIconVisuals
extends RefCounted

## Shared presentation helpers for item icons used in UI and world-item visuals.
## Keeps icon styling separate from item data definitions.

const _OUTLINE_PADDING := 1
const _OUTLINE_COLOR := Color(0.0, 0.0, 0.0, 1.0)

static var _outlined_texture_cache: Dictionary = {}
static var _atlas_image_cache: Dictionary = {}


static func build_outlined_icon_texture(item_id: int) -> Texture2D:
	var cached: Variant = _outlined_texture_cache.get(item_id)
	if cached is Texture2D:
		return cached as Texture2D

	var props: ItemProperties = ItemProperties.get_properties(item_id)
	if props == null:
		return null

	var texture: Texture2D = _build_outlined_texture_from_properties(props)
	if texture != null:
		_outlined_texture_cache[item_id] = texture
	return texture


static func _build_outlined_texture_from_properties(props: ItemProperties) -> Texture2D:
	var atlas_coord := props.get_icon_atlas_coord()
	if atlas_coord == ItemProperties.INVALID_ICON_COORD:
		return null

	var atlas_image: Image = _get_cached_atlas_image(props.get_icon_atlas_path())
	if atlas_image == null:
		return null

	var tile_size := GameConstants.TILE_SIZE
	var source_x := atlas_coord.x * tile_size
	var source_y := atlas_coord.y * tile_size
	if (
		source_x < 0
		or source_y < 0
		or source_x + tile_size > atlas_image.get_width()
		or source_y + tile_size > atlas_image.get_height()
	):
		return null

	var source := Image.create(tile_size, tile_size, false, Image.FORMAT_RGBA8)
	source.fill(Color(0.0, 0.0, 0.0, 0.0))
	source.blit_rect(
		atlas_image,
		Rect2i(source_x, source_y, tile_size, tile_size),
		Vector2i.ZERO
	)
	return _build_outlined_texture_from_image(source)


static func _build_outlined_texture_from_image(source: Image) -> Texture2D:
	var outlined := Image.create(
		source.get_width() + (_OUTLINE_PADDING * 2),
		source.get_height() + (_OUTLINE_PADDING * 2),
		false,
		Image.FORMAT_RGBA8
	)
	outlined.fill(Color(0.0, 0.0, 0.0, 0.0))

	for y: int in range(source.get_height()):
		for x: int in range(source.get_width()):
			var pixel: Color = source.get_pixel(x, y)
			if pixel.a <= 0.0:
				continue

			var target_x := x + _OUTLINE_PADDING
			var target_y := y + _OUTLINE_PADDING
			for offset_y: int in range(-1, 2):
				for offset_x: int in range(-1, 2):
					if offset_x == 0 and offset_y == 0:
						continue
					var neighbor_x := target_x + offset_x
					var neighbor_y := target_y + offset_y
					if outlined.get_pixel(neighbor_x, neighbor_y).a <= 0.0:
						outlined.set_pixel(neighbor_x, neighbor_y, _OUTLINE_COLOR)

			outlined.set_pixel(target_x, target_y, pixel)

	return ImageTexture.create_from_image(outlined)


static func _get_cached_atlas_image(atlas_path: String) -> Image:
	var cached: Variant = _atlas_image_cache.get(atlas_path)
	if cached is Image:
		return cached as Image

	if atlas_path.is_empty() or not ResourceLoader.exists(atlas_path):
		return null

	var atlas_texture := load(atlas_path) as Texture2D
	if atlas_texture == null:
		return null

	var atlas_image := atlas_texture.get_image()
	if atlas_image == null:
		return null

	_atlas_image_cache[atlas_path] = atlas_image
	return atlas_image
