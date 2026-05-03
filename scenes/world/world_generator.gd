extends Node2D
var _world_object_catalog = preload("res://scripts/world/world_object_catalog.gd").new()
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

@onready var ground_layer: TileMapLayer = $GroundLayer
@onready var ground_collision_layer: TileMapLayer = $GroundCollisionLayer
@onready var liquid_layer: TileMapLayer = $LiquidLayer
@onready var terrain_layer: TileMapLayer = $TerrainLayer
@onready var base_visual_layer: TileMapLayer = $BaseVisualLayer
@onready var decor_layer: TileMapLayer = $DepthSorted/DecorLayer
@onready var chunk_manager: Node = $ChunkManager
@onready var world_object_manager: Node = $WorldObjectManager
@onready var structure_manager: Node = world_object_manager
@onready var depth_sorted: Node2D = $DepthSorted
@onready var players_node: Node = $DepthSorted/Players
@onready var chunk_debug_overlay: Node = $ChunkDebugCanvas/ChunkDebugOverlay


func _ready() -> void:
	if chunk_manager != null and chunk_manager.has_method("setup"):
		chunk_manager.setup(
			self,
			world_object_manager,
			ground_layer,
			ground_collision_layer,
			liquid_layer,
			terrain_layer,
			base_visual_layer,
			decor_layer,
			depth_sorted,
			players_node
		)
	if world_object_manager != null and world_object_manager.has_method("setup"):
		world_object_manager.setup(self, chunk_manager, depth_sorted)


## Initializes noise with the given seed. Must be called before generate_chunk().
func initialize(seed_value: int) -> void:
	world_seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.05
	noise.seed = seed_value
	_diagnose_and_fix_physics()
	_setup_decor_layer()
	_setup_ground_layer()
	_setup_ground_collision_layer()
	_setup_liquid_layer()


## Builds a runtime TileSet for the GroundLayer from ground_tiles.png.
## Each GroundTileProperties entry maps to a 16x16 cell at its atlas_coord.
func _setup_ground_layer() -> void:
	if ground_layer == null:
		return
	var texture := load("res://assets/tilesets/ground_tiles.png") as Texture2D
	if texture == null:
		push_warning("[WorldGenerator] ground_tiles.png not found at res://assets/tilesets/ground_tiles.png.")
		return
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(GameConstants.TILE_SIZE, GameConstants.TILE_SIZE)
	# Register only solid tiles — liquid tiles live in liquid_tiles.png, not here.
	for ground_id: int in GroundTileProperties.registry:
		var props := GroundTileProperties.get_properties(ground_id)
		if props.is_solid:
			source.create_tile(props.atlas_coord)
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(GameConstants.TILE_SIZE, GameConstants.TILE_SIZE)
	tile_set.add_source(source)
	ground_layer.tile_set = tile_set


## Builds a runtime collision-only TileSet for GroundCollisionLayer.
## One transparent tile is enough: solid ground erases it, liquid/void place it.
func _setup_ground_collision_layer() -> void:
	if ground_collision_layer == null:
		return
	var image := Image.create(GameConstants.TILE_SIZE, GameConstants.TILE_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var texture := ImageTexture.create_from_image(image)
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(GameConstants.TILE_SIZE, GameConstants.TILE_SIZE)
	source.create_tile(Vector2i.ZERO)

	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(GameConstants.TILE_SIZE, GameConstants.TILE_SIZE)
	tile_set.add_physics_layer()
	tile_set.set_physics_layer_collision_layer(0, 1)
	tile_set.add_source(source)

	var tile_data := source.get_tile_data(Vector2i.ZERO, 0)
	tile_data.add_collision_polygon(0)
	tile_data.set_collision_polygon_points(0, 0, collision_polygon)

	ground_collision_layer.tile_set = tile_set


## Builds a runtime TileSet for LiquidLayer from liquid_tiles.png and applies
## the liquid animation shader.
func _setup_liquid_layer() -> void:
	if liquid_layer == null:
		return
	var texture := load("res://assets/tilesets/liquid_tiles.png") as Texture2D
	if texture == null:
		push_warning("[WorldGenerator] liquid_tiles.png not found at res://assets/tilesets/liquid_tiles.png.")
		return
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(GameConstants.TILE_SIZE, GameConstants.TILE_SIZE)
	# Register only liquid tiles — atlas coords are relative to liquid_tiles.png.
	for ground_id: int in GroundTileProperties.registry:
		var props := GroundTileProperties.get_properties(ground_id)
		if props.is_liquid:
			source.create_tile(props.atlas_coord)
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(GameConstants.TILE_SIZE, GameConstants.TILE_SIZE)
	tile_set.add_source(source)
	liquid_layer.tile_set = tile_set
	# Apply animation shader.
	var shader := load("res://assets/shaders/liquid.gdshader") as Shader
	if shader != null:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("tile_size", float(GameConstants.TILE_SIZE))
		liquid_layer.material = mat


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

	# Pass 1: ground + top tiles
	for local_y in range(GameConstants.CHUNK_SIZE):
		for local_x in range(GameConstants.CHUNK_SIZE):
			var world_x: int = origin_x + local_x
			var world_y: int = origin_y + local_y
			var idx: int = local_y * GameConstants.CHUNK_SIZE + local_x
			var ground_id := _get_ground_tile_for_position(world_x, world_y)
			chunk.ground_base_tiles[idx] = ground_id
			chunk.top_base_tiles[idx] = _get_top_tile_for_position(world_x, world_y, ground_id)

	# Pass 2: generated static world objects with multi-cell reservation
	var reserved_cells: Dictionary = {}
	for local_y in range(GameConstants.CHUNK_SIZE):
		for local_x in range(GameConstants.CHUNK_SIZE):
			var idx: int = local_y * GameConstants.CHUNK_SIZE + local_x
			if reserved_cells.has(idx):
				continue
			var world_x: int = origin_x + local_x
			var world_y: int = origin_y + local_y
			var ground_id: int = chunk.ground_base_tiles[idx]
			var object_id := _get_generated_world_object_for_position(world_x, world_y, ground_id)
			if object_id.is_empty():
				continue
			var definition = _world_object_catalog.call("get_definition", object_id)
			if definition == null:
				continue
			var offsets: Array = definition.hit_cells
			var can_place := true
			for offset in offsets:
				var nx: int = local_x + offset.x
				var ny: int = local_y + offset.y
				if nx < 0 or nx >= GameConstants.CHUNK_SIZE or ny < 0 or ny >= GameConstants.CHUNK_SIZE:
					can_place = false
					break
				var n_idx: int = ny * GameConstants.CHUNK_SIZE + nx
				if reserved_cells.has(n_idx):
					can_place = false
					break
				if chunk.top_base_tiles[n_idx] != TileProperties.EMPTY:
					can_place = false
					break
				var n_ground: int = chunk.ground_base_tiles[n_idx]
				var n_ground_props := GroundTileProperties.get_properties(n_ground)
				if n_ground_props == null or not n_ground_props.is_solid:
					can_place = false
					break
				if not definition.is_ground_allowed(n_ground_props.name):
					can_place = false
					break
			if not can_place:
				continue
			chunk.add_base_world_object(Vector2i(local_x, local_y), object_id)
			for offset in offsets:
				var rx: int = local_x + offset.x
				var ry: int = local_y + offset.y
				var r_idx: int = ry * GameConstants.CHUNK_SIZE + rx
				reserved_cells[r_idx] = true
				if chunk.top_base_tiles[r_idx] != TileProperties.EMPTY:
					chunk.top_base_tiles[r_idx] = TileProperties.EMPTY

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


## Returns the ground tile ID for a world-space tile position.
## Picks a deterministic visual variant per cell so neighboring tiles differ slightly.
func _get_ground_tile_for_position(x: int, y: int) -> int:
	var n: float = noise.get_noise_2d(float(x), float(y))
	var depth_ratio: float = float(y) / float(GameConstants.WORLD_SCALE)
	var density: float = n + (depth_ratio * 1.5 - 0.5)

	# Lava: rare deep pockets (depth > 70 %, noise strongly negative).
	if depth_ratio > 0.7 and density < -0.2:
		return GroundTileProperties.by_name["lava"]

	# Water: surface depressions (depth < 35 %, density low enough to be "sunken").
	if depth_ratio < 0.35 and density < -0.4:
		return GroundTileProperties.by_name["water"]

	var base_name: String
	if density > 0.6:
		base_name = "stone"
	elif density > 0.0:
		# Grass covers the top ~25 tiles (depth_ratio < 0.1 with WORLD_SCALE=256).
		base_name = "grass" if depth_ratio < 0.1 else "dirt"
	else:
		base_name = "sand"

	var group: Array = GroundTileProperties.variants[base_name]
	var variant_index: int = absi(x * 31 + y * 97) % group.size()
	return group[variant_index]


## Returns the top tile ID for a world-space tile position.
## Top tiles only spawn on solid ground.
## Solid blocks (stone, sand) form the natural terrain obstacles.
## Vegetation spawns in sparse open areas.
func _get_top_tile_for_position(x: int, y: int, ground_id: int) -> int:
	var ground_props := GroundTileProperties.get_properties(ground_id)
	if ground_props == null or not ground_props.is_solid:
		return TileProperties.EMPTY

	var n: float = noise.get_noise_2d(float(x), float(y))
	var depth_ratio: float = float(y) / float(GameConstants.WORLD_SCALE)
	var density: float = n + (depth_ratio * 1.5 - 0.5)

	if density > 0.6:
		return TileProperties.by_name["stone"]
	if density > 0.3:
		return TileProperties.by_name["sand"]
	return TileProperties.EMPTY


func _get_generated_world_object_for_position(x: int, y: int, ground_id: int) -> String:
	var ground_props := GroundTileProperties.get_properties(ground_id)
	if ground_props == null or not ground_props.is_solid:
		return ""

	var n: float = noise.get_noise_2d(float(x), float(y))
	var depth_ratio: float = float(y) / float(GameConstants.WORLD_SCALE)
	var density: float = n + (depth_ratio * 1.5 - 0.5)

	if density > 0.3:
		return ""

	# Coral: mid-density underwater-style areas
	if density > 0.2 and n > 0.1:
		var variants: Array = _world_object_catalog.get("coral_variants")
		var variant_index: int = absi(x * 73 + y * 137) % variants.size()
		return variants[variant_index]

	# Trees: sparse placement on grass ground (shallow overworld)
	if ground_props.name.begins_with("grass") and depth_ratio < 0.15:
		var tree_noise: float = noise.get_noise_2d(float(x) * 2.3 + 500.0, float(y) * 2.3 + 500.0)
		if tree_noise > 0.25:
			var variants: Array = _world_object_catalog.get("tree_variants")
			var variant_index: int = absi(x * 59 + y * 113) % variants.size()
			return variants[variant_index]

	return ""
