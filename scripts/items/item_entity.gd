extends CharacterBody2D
## A dropped item floating in the world. Has physics (collides with terrain),
## gentle underwater drift, pickup via Area2D overlap, and a despawn timer.
## Host-authoritative: only the server runs physics and pickup logic.

var item_id: int = ItemProperties.NONE
var count: int = 1

## Position stream replicated by MultiplayerSynchronizer.
var replicated_position: Vector2 = Vector2.ZERO:
	set(value):
		_replicated_position = value
		if multiplayer.is_server():
			return
		_target_network_position = value
		if not _has_network_position:
			position = value
			_has_network_position = true
	get:
		return _replicated_position

## Accumulated lifetime in seconds.
var _lifetime: float = 0.0

## Initial velocity from the break (randomized on spawn).
var _drift_velocity: Vector2 = Vector2.ZERO

## Oscillation phase for the gentle float effect.
var _float_phase: float = 0.0

## Player currently attracting this item.
var _pickup_target: Node2D

## Reference to InventoryManager (resolved once on first physics frame).
var _inventory_manager: Node

var _replicated_position: Vector2 = Vector2.ZERO
var _target_network_position: Vector2 = Vector2.ZERO
var _has_network_position: bool = false


func _ready() -> void:
	replicated_position = position


## Called by the spawner's spawn_function to set item data and visuals.
func initialize(p_item_id: int, p_count: int) -> void:
	item_id = p_item_id
	count = p_count
	_float_phase = randf() * TAU
	# Random initial drift so items scatter slightly from the break point.
	_drift_velocity = Vector2(
		randf_range(-GameConstants.ITEM_DRIFT_SPEED, GameConstants.ITEM_DRIFT_SPEED),
		randf_range(-GameConstants.ITEM_DRIFT_SPEED, GameConstants.ITEM_DRIFT_SPEED),
	)
	_setup_sprite()


func _process(delta: float) -> void:
	if multiplayer.is_server() or not _has_network_position:
		return

	position = position.lerp(
		_target_network_position,
		minf(GameConstants.ITEM_POSITION_SMOOTHING * delta, 1.0)
	)


func _physics_process(delta: float) -> void:
	# Only the host runs item physics and lifetime.
	if not multiplayer.is_server():
		return

	_lifetime += delta

	# Despawn after timeout.
	if _lifetime >= GameConstants.ITEM_DESPAWN_TIME:
		queue_free()
		return

	if _lifetime >= GameConstants.ITEM_PICKUP_DELAY:
		_update_pickup_target()
		if _pickup_target != null:
			var to_target := _pickup_target.global_position - global_position
			if to_target.length() <= 8.0:
				_try_pickup(_pickup_target)
				if is_queued_for_deletion():
					return
			else:
				velocity = to_target.normalized() * GameConstants.ITEM_ATTRACT_SPEED
				move_and_slide()
				replicated_position = position
				return

	# Gentle underwater floating: sinusoidal vertical bob.
	_float_phase += delta * 2.0
	var float_offset := sin(_float_phase) * GameConstants.ITEM_FLOAT_SPEED

	# Drift decays over time (water friction).
	_drift_velocity = _drift_velocity.move_toward(Vector2.ZERO, 20.0 * delta)

	velocity = _drift_velocity + Vector2(0.0, float_offset)
	move_and_slide()
	replicated_position = position


## Called when a body enters the pickup area.
func _on_pickup_area_body_entered(body: Node2D) -> void:
	if not multiplayer.is_server():
		return

	if _is_valid_pickup_body(body):
		_pickup_target = body


func _update_pickup_target() -> void:
	if _is_valid_pickup_body(_pickup_target) and _is_body_in_pickup_range(_pickup_target):
		return

	_pickup_target = null
	var nearest_distance := INF
	for body in $PickupArea.get_overlapping_bodies():
		if not _is_valid_pickup_body(body):
			continue
		var distance := global_position.distance_to(body.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			_pickup_target = body


func _try_pickup(body: Node2D) -> void:
	if is_queued_for_deletion():
		return

	# Only pick up after the delay (prevents instant grab on break).
	if _lifetime < GameConstants.ITEM_PICKUP_DELAY:
		return

	# Only players can pick up items. Player nodes are named by peer ID.
	if not body.is_in_group("players"):
		return

	var peer_id: int = body.name.to_int()
	if peer_id <= 0:
		return

	if _inventory_manager == null:
		_inventory_manager = get_tree().get_root().get_node_or_null(
			"Main/InventoryManager"
		)
	if _inventory_manager == null:
		return

	var remainder: int = _inventory_manager.server_add_item(peer_id, item_id, count)

	if remainder <= 0:
		# Fully picked up — remove from world (spawner replicates the despawn).
		queue_free()
	else:
		# Partially picked up — update remaining count.
		count = remainder

	_pickup_target = null


func _is_valid_pickup_body(body: Node2D) -> bool:
	return body != null and is_instance_valid(body) and body.is_in_group("players")


func _is_body_in_pickup_range(body: Node2D) -> bool:
	return body in $PickupArea.get_overlapping_bodies()


## Creates a small sprite from the tile's atlas texture.
func _setup_sprite() -> void:
	var sprite: Sprite2D = $Sprite2D
	if sprite == null:
		return

	# Use the tile atlas as the item sprite source.
	var item_props := ItemProperties.get_properties(item_id)
	if item_props == null or item_props.tile_id == -1:
		return

	var tile_props := TileProperties.get_properties(item_props.tile_id)
	if tile_props == null:
		return

	# Load the terrain atlas image and extract this tile's region.
	var atlas_texture := AtlasTexture.new()
	atlas_texture.atlas = load("res://assets/tilesets/terrain_tiles.png")
	var ts: int = GameConstants.TILE_SIZE
	atlas_texture.region = Rect2(
		tile_props.atlas_coord.x * ts,
		tile_props.atlas_coord.y * ts,
		ts,
		ts,
	)
	sprite.texture = atlas_texture
	# Scale down slightly so the drop looks smaller than a placed tile.
	sprite.scale = Vector2(0.65, 0.65)
