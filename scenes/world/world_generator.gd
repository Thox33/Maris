extends Node2D
## Stateless procedural world generator.
## Produces ChunkData from noise — does not touch TileMapLayer directly.
## The ChunkManager orchestrates loading/unloading and network sync.

## Full-tile collision polygon (16x16 centered).
static var collision_polygon := PackedVector2Array(
	[
		Vector2(-8, -8),
		Vector2(8, -8),
		Vector2(8, 8),
		Vector2(-8, 8),
	]
)

var noise := FastNoiseLite.new()
var world_seed: int = 0

@onready var terrain_layer: TileMapLayer = $TerrainLayer
@onready var base_visual_layer: TileMapLayer = $BaseVisualLayer
@onready var decor_layer: TileMapLayer = $DepthSorted/DecorLayer
@onready var chunk_manager: Node = $ChunkManager
@onready var structure_manager: Node = $StructureManager
@onready var depth_sorted: Node2D = $DepthSorted
@onready var players_node: Node = $DepthSorted/Players
@onready var chunk_debug_overlay: Node = $ChunkDebugCanvas/ChunkDebugOverlay


func _ready() -> void:
	if chunk_manager != null and chunk_manager.has_method("setup"):
		chunk_manager.setup(
			self,
			terrain_layer,
			base_visual_layer,
			decor_layer,
			depth_sorted,
			players_node
		)
	if structure_manager != null and structure_manager.has_method("setup"):
		structure_manager.setup(self, chunk_manager, depth_sorted)


## Initializes noise with the given seed. Must be called before generate_chunk().
func initialize(seed_value: int) -> void:
	world_seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.05
	noise.seed = seed_value
	_diagnose_and_fix_physics()
	_setup_decor_layer()


func _setup_decor_layer() -> void:
	var shader := load("res://assets/shaders/vegetation_sway.gdshader") as Shader
	if shader == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("tile_size", float(GameConstants.TILE_SIZE))
	decor_layer.y_sort_enabled = true
	decor_layer.y_sort_origin = GameConstants.TILE_SIZE
	decor_layer.material = mat


## Generates a ChunkData for the given chunk coordinate.
func generate_chunk(coord: Vector2i) -> ChunkData:
	var chunk := ChunkData.new(coord)
	var origin_x: int = coord.x * GameConstants.CHUNK_SIZE
	var origin_y: int = coord.y * GameConstants.CHUNK_SIZE

	for local_y in range(GameConstants.CHUNK_SIZE):
		for local_x in range(GameConstants.CHUNK_SIZE):
			var world_x: int = origin_x + local_x
			var world_y: int = origin_y + local_y
			var tile_id: int = _get_tile_for_position(world_x, world_y)
			chunk.base_tiles[local_y * GameConstants.CHUNK_SIZE + local_x] = tile_id

	return chunk


## Diagnoses physics layer state from the .tres and fixes if needed.
func _diagnose_and_fix_physics() -> void:
	var ts: TileSet = terrain_layer.tile_set
	var source: TileSetAtlasSource = ts.get_source(0) as TileSetAtlasSource

	# --- Diagnose what the .tres actually loaded ---
	var layer_count: int = ts.get_physics_layers_count()
	print("[Physics] TileSet has %d physics layer(s)" % layer_count)

	if layer_count > 0:
		var col_layer: int = ts.get_physics_layer_collision_layer(0)
		var col_mask: int = ts.get_physics_layer_collision_mask(0)
		print("[Physics] Layer 0: collision_layer=%d, collision_mask=%d" % [col_layer, col_mask])

	for tile_id: int in TileProperties.registry:
		var props := TileProperties.get_properties(tile_id)
		var td: TileData = source.get_tile_data(props.atlas_coord, 0)
		var poly_count: int = 0
		if layer_count > 0:
			poly_count = td.get_collision_polygons_count(0)
		print("[Physics] Tile '%s' (%d): %d collision polygon(s)" % [props.name, tile_id, poly_count])

	# --- Fix if anything is missing ---
	var fixed := false

	if layer_count == 0:
		ts.add_physics_layer()
		print("[Physics] FIX: Added missing physics layer")
		fixed = true

	if ts.get_physics_layer_collision_layer(0) != 1:
		ts.set_physics_layer_collision_layer(0, 1)
		print("[Physics] FIX: Set collision_layer to 1")
		fixed = true

	# Ensure solid tiles have collision polygons; non-solid tiles have none.
	for tile_id: int in TileProperties.registry:
		var props := TileProperties.get_properties(tile_id)
		var td: TileData = source.get_tile_data(props.atlas_coord, 0)
		if props.solid:
			if td.get_collision_polygons_count(0) == 0:
				td.add_collision_polygon(0)
				td.set_collision_polygon_points(0, 0, collision_polygon)
				print("[Physics] FIX: Added collision polygon to '%s'" % props.name)
				fixed = true
		else:
			if td.get_collision_polygons_count(0) > 0:
				td.remove_collision_polygon(0, 0)
				print("[Physics] FIX: Removed collision polygon from '%s'" % props.name)
				fixed = true
	if not fixed:
		print("[Physics] All good — no fixes needed")


## Returns the tile type index for a world-space tile position.
func _get_tile_for_position(x: int, y: int) -> int:
	var n: float = noise.get_noise_2d(float(x), float(y))
	var depth_ratio: float = float(y) / float(GameConstants.WORLD_SCALE)
	var density: float = n + (depth_ratio * 1.5 - 0.5)

	if density > 0.6:
		return TileProperties.by_name["stone"]
	if density > 0.3:
		return TileProperties.by_name["sand"]
	if density > 0.2 and n > 0.1:
		# Pick a deterministic coral variant based on position.
		var variants := TileProperties.coral_variants
		var variant_index: int = absi(x * 73 + y * 137) % variants.size()
		return variants[variant_index]
	return TileProperties.EMPTY
