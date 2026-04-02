extends CharacterBody2D
## Player controller with swim physics.
## Only the owning peer processes input. Remote peers are rendered from a
## short snapshot buffer for smoother movement.

@export var swim_speed: float = GameConstants.SWIM_SPEED
@export var swim_acceleration: float = GameConstants.SWIM_ACCELERATION
@export var swim_friction: float = GameConstants.SWIM_FRICTION

var _chunk_manager: Node
var _sync_timer: float = 0.0
var _state_buffer: Array[Dictionary] = []


func _ready() -> void:
	$Camera2D.enabled = is_multiplayer_authority()
	var world := get_tree().get_root().get_node_or_null("Main/World")
	if world:
		_chunk_manager = world.get_node("ChunkManager")

	if not is_multiplayer_authority():
		_push_remote_state(position, Vector2.ZERO)


func _process(delta: float) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if not is_multiplayer_authority():
		_update_remote_motion(delta)


func _physics_process(delta: float) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if not is_multiplayer_authority():
		return

	var input_dir := Vector2.ZERO
	input_dir.x = Input.get_axis("swim_left", "swim_right")
	input_dir.y = Input.get_axis("swim_up", "swim_down")

	if input_dir.length() > 1.0:
		input_dir = input_dir.normalized()

	var speed_factor: float = _get_tile_speed_factor()
	var effective_speed: float = swim_speed * speed_factor

	if input_dir != Vector2.ZERO:
		velocity = velocity.move_toward(input_dir * effective_speed, swim_acceleration * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, swim_friction * delta)

	move_and_slide()

	_sync_timer += delta
	if _sync_timer >= GameConstants.POSITION_SYNC_INTERVAL:
		_sync_timer = 0.0
		_sync_state.rpc(position, velocity)


func _update_remote_motion(delta: float) -> void:
	var now := Time.get_ticks_usec() * 0.000001
	var render_time := now - GameConstants.REMOTE_PLAYER_INTERPOLATION_BACK_TIME
	var target_position := position
	var target_velocity := velocity

	while _state_buffer.size() >= 2 and render_time > _state_buffer[1]["time"]:
		_state_buffer.remove_at(0)

	if _state_buffer.size() >= 2:
		var from_state: Dictionary = _state_buffer[0]
		var to_state: Dictionary = _state_buffer[1]
		var span: float = maxf(to_state["time"] - from_state["time"], 0.0001)
		var alpha: float = clampf((render_time - from_state["time"]) / span, 0.0, 1.0)
		target_position = (from_state["position"] as Vector2).lerp(to_state["position"], alpha)
		target_velocity = (from_state["velocity"] as Vector2).lerp(to_state["velocity"], alpha)
	elif _state_buffer.size() == 1:
		var latest: Dictionary = _state_buffer[0]
		var age: float = minf(
			now - latest["time"],
			GameConstants.REMOTE_PLAYER_MAX_EXTRAPOLATION
		)
		target_velocity = latest["velocity"]
		target_position = latest["position"] + target_velocity * age

	position = position.lerp(
		target_position,
		minf(GameConstants.REMOTE_PLAYER_SMOOTHING * delta, 1.0)
	)
	velocity = target_velocity


func _push_remote_state(pos: Vector2, vel: Vector2) -> void:
	_state_buffer.append({
		"position": pos,
		"velocity": vel,
		"time": Time.get_ticks_usec() * 0.000001,
	})
	while _state_buffer.size() > 4:
		_state_buffer.remove_at(0)


## Returns the swim speed factor for the tile at the player's center position.
## 1.0 = open water (full speed), < 1.0 = slowed (e.g. coral).
func _get_tile_speed_factor() -> float:
	if _chunk_manager == null:
		return 1.0

	var tile_coord := Vector2i(
		floori(global_position.x / GameConstants.TILE_SIZE),
		floori(global_position.y / GameConstants.TILE_SIZE),
	)
	var tile_id: int = _chunk_manager.get_tile_at(tile_coord)
	if tile_id == TileProperties.EMPTY:
		return 1.0

	var props: TileProperties = TileProperties.get_properties(tile_id)
	if props and not props.solid:
		return props.swim_speed_factor

	return 1.0


@rpc("authority", "unreliable")
func _sync_state(pos: Vector2, vel: Vector2) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if not is_multiplayer_authority():
		_push_remote_state(pos, vel)
