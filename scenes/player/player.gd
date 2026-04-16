extends HumanoidActor
## Player controller with top-down movement physics.
## Only the owning peer processes input. Remote peers are rendered from a
## short snapshot buffer for smoother movement.

@export var move_speed: float = GameConstants.MOVE_SPEED
@export var move_acceleration: float = GameConstants.MOVE_ACCELERATION
@export var move_friction: float = GameConstants.MOVE_FRICTION

const LOOK_NEUTRAL_HOVER_RADIUS: float = 12.0

var _chunk_manager: Node
var _terrain_layer: TileMapLayer
var _structure_manager: Node
var _items_node: Node
var _players_node: Node
var _chunk_debug_overlay: Node
var _use_authority_service: Node
var _sync_timer: float = 0.0
var _state_buffer: Array[Dictionary] = []
@onready var _overhead_source: OverheadSource = $OverheadSource
@onready var _block_interaction: Node = $BlockInteraction
@onready var _hotbar_ui: CanvasLayer = $HotbarUI
@onready var _debug_overlay: CanvasLayer = $DebugOverlay
@onready var _camera: Camera2D = $Camera2D

var _look_dir: Vector2 = Vector2.RIGHT
var _visual_look_dir: Vector2 = Vector2.RIGHT
var _inventory_manager: Node
var _bound_inventory_manager: Node


func setup_session(
	inventory_manager: Node,
	items_node: Node,
	players_node: Node,
	terrain_layer: TileMapLayer,
	chunk_manager: Node,
	structure_manager: Node,
	use_authority_service: Node,
	chunk_debug_overlay: Node = null,
) -> void:
	_inventory_manager = inventory_manager
	_items_node = items_node
	_players_node = players_node
	_terrain_layer = terrain_layer
	_chunk_manager = chunk_manager
	_structure_manager = structure_manager
	_use_authority_service = use_authority_service
	_chunk_debug_overlay = chunk_debug_overlay
	if is_node_ready():
		_wire_session_dependencies()


func _ready() -> void:
	super._ready()
	_camera.enabled = is_multiplayer_authority()
	_wire_session_dependencies()

	if not is_multiplayer_authority():
		_push_remote_state(position, Vector2.ZERO)

	NetworkManager.player_identity_updated.connect(_on_player_identity_updated)
	_refresh_equipped_item_state()
	_update_actor_motion_state(velocity)
	_refresh_overhead()


func _wire_session_dependencies() -> void:
	_bind_inventory_manager_signals()
	if _block_interaction != null and _block_interaction.has_method("setup_session"):
		_block_interaction.setup_session(
			_terrain_layer,
			_chunk_manager,
			_structure_manager,
			_inventory_manager,
			_use_authority_service
		)
	if _hotbar_ui != null and _hotbar_ui.has_method("setup_session"):
		_hotbar_ui.setup_session(_block_interaction, _inventory_manager)
	if _humanoid_visual != null and _humanoid_visual.has_method("set_inventory_manager"):
		_humanoid_visual.set_inventory_manager(_inventory_manager)
	if _debug_overlay != null and _debug_overlay.has_method("setup_session"):
		_debug_overlay.setup_session(
			_chunk_manager,
			_items_node,
			_players_node,
			_chunk_debug_overlay
		)


func _bind_inventory_manager_signals() -> void:
	if _bound_inventory_manager == _inventory_manager:
		return
	if _bound_inventory_manager != null:
		if (
			_bound_inventory_manager.has_signal("local_inventory_synced")
			and _bound_inventory_manager.local_inventory_synced.is_connected(
				_on_local_inventory_synced
			)
		):
			_bound_inventory_manager.local_inventory_synced.disconnect(_on_local_inventory_synced)
		if (
			_bound_inventory_manager.has_signal("local_held_slot_changed")
			and _bound_inventory_manager.local_held_slot_changed.is_connected(
				_on_local_held_slot_changed
			)
		):
			_bound_inventory_manager.local_held_slot_changed.disconnect(
				_on_local_held_slot_changed
			)
	_bound_inventory_manager = _inventory_manager
	if _bound_inventory_manager == null:
		return
	if _bound_inventory_manager.has_signal("local_inventory_synced"):
		_bound_inventory_manager.local_inventory_synced.connect(_on_local_inventory_synced)
	if _bound_inventory_manager.has_signal("local_held_slot_changed"):
		_bound_inventory_manager.local_held_slot_changed.connect(_on_local_held_slot_changed)


func _process(delta: float) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if is_multiplayer_authority():
		_refresh_equipped_item_state()
		var mouse_offset := get_global_mouse_position() - get_body_center_global()
		var mouse_distance_sq := mouse_offset.length_squared()
		if mouse_distance_sq > 0.0:
			_look_dir = mouse_offset.normalized()
		if mouse_distance_sq <= LOOK_NEUTRAL_HOVER_RADIUS * LOOK_NEUTRAL_HOVER_RADIUS:
			_visual_look_dir = Vector2.ZERO
		else:
			_visual_look_dir = _look_dir
		if _humanoid_visual != null:
			_humanoid_visual.set_look_direction(_visual_look_dir)
	if not is_multiplayer_authority():
		_update_remote_motion(delta)


func _physics_process(delta: float) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if not is_multiplayer_authority():
		return

	if ChatManager.is_chat_open:
		velocity = velocity.move_toward(Vector2.ZERO, move_friction * delta)
		move_and_slide()
		_update_actor_motion_state(velocity)
		return

	var input_dir := Vector2.ZERO
	input_dir.x = Input.get_axis("move_left", "move_right")
	input_dir.y = Input.get_axis("move_up", "move_down")

	if input_dir.length() > 1.0:
		input_dir = input_dir.normalized()

	var speed_factor: float = _get_tile_speed_factor()
	var effective_speed: float = move_speed * speed_factor

	if input_dir != Vector2.ZERO:
		velocity = velocity.move_toward(input_dir * effective_speed, move_acceleration * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, move_friction * delta)

	move_and_slide()
	_update_actor_motion_state(velocity)

	_sync_timer += delta
	if _sync_timer >= GameConstants.POSITION_SYNC_INTERVAL:
		_sync_timer = 0.0
		_sync_state.rpc(position, velocity, _held_item_id, _look_dir, _visual_look_dir)


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
	_update_actor_motion_state(velocity)


func _push_remote_state(pos: Vector2, vel: Vector2) -> void:
	_state_buffer.append({
		"position": pos,
		"velocity": vel,
		"time": Time.get_ticks_usec() * 0.000001,
	})
	while _state_buffer.size() > 4:
		_state_buffer.remove_at(0)


func get_look_direction() -> Vector2:
	return _look_dir


## Returns the movement speed factor for the top tile at the player's center position.
## 1.0 = empty cell, < 1.0 = slowed by non-solid decor (e.g. coral).
func _get_tile_speed_factor() -> float:
	if _chunk_manager == null:
		return 1.0

	var tile_coord := Vector2i(
		floori(global_position.x / GameConstants.TILE_SIZE),
		floori(global_position.y / GameConstants.TILE_SIZE),
	)
	var tile_id: int = _chunk_manager.get_top_tile_at(tile_coord)
	if tile_id == TileProperties.EMPTY:
		return 1.0

	var props: TileProperties = TileProperties.get_properties(tile_id)
	if props and not props.solid:
		return props.move_speed_factor

	return 1.0


@rpc("authority", "unreliable")
func _sync_state(
	pos: Vector2,
	vel: Vector2,
	held_item_id: int,
	look_dir: Vector2,
	visual_look_dir: Vector2
) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if not is_multiplayer_authority():
		_apply_remote_held_item_state(held_item_id)
		_push_remote_state(pos, vel)
		_look_dir = look_dir
		_visual_look_dir = visual_look_dir
		if _humanoid_visual != null:
			_humanoid_visual.set_look_direction(_visual_look_dir)


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
	_update_actor_motion_state(Vector2.ZERO)
	if not is_multiplayer_authority():
		_push_remote_state(pos, Vector2.ZERO)


func apply_character_data(character_name: String, appearance: Dictionary) -> void:
	_character_name = character_name.strip_edges()
	apply_appearance(appearance)
	_refresh_overhead()


func _on_player_identity_updated(peer_id: int, _display_name: String, character_name: String) -> void:
	if peer_id != get_multiplayer_authority():
		return
	_character_name = character_name.strip_edges()
	_refresh_overhead()


func _refresh_overhead() -> void:
	if _overhead_source == null:
		return
	_overhead_source.set_display_name(get_actor_display_name())
	_overhead_source.set_overhead_visible(not is_multiplayer_authority())


func get_actor_state() -> Dictionary:
	var state := super.get_actor_state()
	state["velocity"] = velocity
	return state


func get_actor_display_name() -> String:
	return (
		_character_name
		if not _character_name.is_empty()
		else NetworkManager.get_player_visible_name(get_multiplayer_authority())
	)


func get_actor_look_dir() -> Vector2:
	return _visual_look_dir


func _refresh_equipped_item_state() -> void:
	if not is_multiplayer_authority():
		return
	var next_item_id := _resolve_visual_held_item_id()
	if next_item_id == _held_item_id:
		return
	_held_item_id = next_item_id
	actor_state_changed.emit()
	if multiplayer.multiplayer_peer != null:
		_sync_held_item_state.rpc(_held_item_id)


func _resolve_visual_held_item_id() -> int:
	if _inventory_manager != null:
		var held_slot: Dictionary = _inventory_manager.local_held_slot
		var held_item_id: int = int(held_slot.get("item_id", ITEM_PROPERTIES.NONE))
		var held_count: int = int(held_slot.get("count", 0))
		if held_item_id != ITEM_PROPERTIES.NONE and held_count > 0:
			return held_item_id
	return _resolve_selected_hotbar_item_id()


func _resolve_selected_hotbar_item_id() -> int:
	if _inventory_manager == null or _inventory_manager.local_inventory == null:
		return ITEM_PROPERTIES.NONE
	if _block_interaction == null:
		return ITEM_PROPERTIES.NONE
	var slot_index: int = int(_block_interaction.selected_hotbar_slot)
	if slot_index < 0 or slot_index >= _inventory_manager.local_inventory.size:
		return ITEM_PROPERTIES.NONE
	var slot: Dictionary = _inventory_manager.local_inventory.get_slot(slot_index)
	return int(slot.get("item_id", ITEM_PROPERTIES.NONE))


func _on_local_inventory_synced() -> void:
	_refresh_equipped_item_state()


func _on_local_held_slot_changed() -> void:
	_refresh_equipped_item_state()


func _apply_remote_held_item_state(item_id: int) -> void:
	if _held_item_id == item_id:
		return
	_held_item_id = item_id
	actor_state_changed.emit()


@rpc("authority", "reliable", "call_local")
func _sync_held_item_state(item_id: int) -> void:
	if is_multiplayer_authority():
		return
	_apply_remote_held_item_state(item_id)
