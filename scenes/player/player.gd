extends CharacterBody2D
## Player controller with swim physics.
## Only the owning peer processes input. Remote peers are rendered from a
## short snapshot buffer for smoother movement.

const CHARACTER_APPEARANCE := preload("res://scripts/player/character_appearance.gd")

@export var swim_speed: float = GameConstants.SWIM_SPEED
@export var swim_acceleration: float = GameConstants.SWIM_ACCELERATION
@export var swim_friction: float = GameConstants.SWIM_FRICTION

var _chunk_manager: Node
var _sync_timer: float = 0.0
var _state_buffer: Array[Dictionary] = []
@onready var _overhead_source: OverheadSource = $OverheadSource
@onready var _sprite: Sprite2D = $Sprite2D

var _character_name: String = ""


func _ready() -> void:
	$Camera2D.enabled = is_multiplayer_authority()
	var world := get_tree().get_root().get_node_or_null("Main/World")
	if world:
		_chunk_manager = world.get_node("ChunkManager")

	if not is_multiplayer_authority():
		_push_remote_state(position, Vector2.ZERO)

	NetworkManager.player_identity_updated.connect(_on_player_identity_updated)
	_refresh_overhead()


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

	if ChatManager.is_chat_open:
		velocity = velocity.move_toward(Vector2.ZERO, swim_friction * delta)
		move_and_slide()
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


func apply_server_teleport(pos: Vector2) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.is_server():
		_apply_server_teleport(pos)
		var authority_id := get_multiplayer_authority()
		if authority_id != multiplayer.get_unique_id():
			_apply_server_teleport.rpc_id(authority_id, pos)
	else:
		_apply_server_teleport(pos)


@rpc("any_peer", "reliable", "call_local")
func _apply_server_teleport(pos: Vector2) -> void:
	if not multiplayer.is_server():
		var sender_id := multiplayer.get_remote_sender_id()
		if sender_id != 1:
			return
	position = pos
	global_position = pos
	velocity = Vector2.ZERO
	_sync_timer = 0.0
	_state_buffer.clear()
	if not is_multiplayer_authority():
		_push_remote_state(pos, Vector2.ZERO)


func apply_character_data(character_name: String, body_color_preset: String) -> void:
	_character_name = character_name.strip_edges()
	if _sprite != null:
		_sprite.modulate = CHARACTER_APPEARANCE.get_color_for_preset(body_color_preset)
	_refresh_overhead()


func _on_player_identity_updated(peer_id: int, _display_name: String, character_name: String) -> void:
	if peer_id != get_multiplayer_authority():
		return
	_character_name = character_name.strip_edges()
	_refresh_overhead()


func _refresh_overhead() -> void:
	if _overhead_source == null:
		return
	_overhead_source.set_display_name(
		_character_name
		if not _character_name.is_empty()
		else NetworkManager.get_player_visible_name(get_multiplayer_authority())
	)
	_overhead_source.set_overhead_visible(not is_multiplayer_authority())
