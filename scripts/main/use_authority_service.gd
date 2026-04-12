extends Node

signal damaged_target_updated(target_key: String, target_data: Dictionary)
signal damaged_target_cleared(target_key: String)

const TARGET_KIND_TILE := "tile"
const TARGET_KIND_STRUCTURE := "structure"

var players_node: Node
var chunk_manager: Node
var structure_manager: Node
var inventory_manager: Node

var _active_uses_by_peer: Dictionary = {}
var _next_primary_use_time_by_peer: Dictionary = {}
var _damaged_targets: Dictionary = {}
var _replicated_targets: Dictionary = {}
var _is_initialized: bool = false


func setup(
	p_players_node: Node, p_chunk_manager: Node, p_structure_manager: Node, p_inventory_manager: Node
) -> void:
	players_node = p_players_node
	chunk_manager = p_chunk_manager
	structure_manager = p_structure_manager
	inventory_manager = p_inventory_manager

	if _is_initialized:
		return

	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	_is_initialized = true


func _process(_delta: float) -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return

	var now := _now_seconds()
	_process_active_uses(now)
	_process_damaged_targets(now)


func request_primary_use(coord: Vector2i, slot_index: int) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.is_server():
		_set_primary_use_for_peer(multiplayer.get_unique_id(), coord, slot_index)
	else:
		_request_primary_use.rpc_id(1, coord.x, coord.y, slot_index)


func stop_primary_use() -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.is_server():
		_clear_primary_use_for_peer(multiplayer.get_unique_id())
	else:
		_stop_primary_use.rpc_id(1)


func get_damaged_target(target_key: String) -> Dictionary:
	return (_replicated_targets.get(target_key, {}) as Dictionary).duplicate(true)


@rpc("any_peer", "reliable")
func _request_primary_use(tx: int, ty: int, slot_index: int) -> void:
	if not multiplayer.is_server():
		return
	_set_primary_use_for_peer(multiplayer.get_remote_sender_id(), Vector2i(tx, ty), slot_index)


@rpc("any_peer", "reliable")
func _stop_primary_use() -> void:
	if not multiplayer.is_server():
		return
	_clear_primary_use_for_peer(multiplayer.get_remote_sender_id())


@rpc("authority", "reliable")
func _sync_damaged_target(target_key: String, payload: Dictionary) -> void:
	_replicated_targets[target_key] = payload.duplicate(true)
	damaged_target_updated.emit(target_key, get_damaged_target(target_key))


@rpc("authority", "reliable")
func _clear_damaged_target(target_key: String) -> void:
	_replicated_targets.erase(target_key)
	damaged_target_cleared.emit(target_key)


func _set_primary_use_for_peer(peer_id: int, coord: Vector2i, slot_index: int) -> void:
	if peer_id <= 0:
		return

	var target := _resolve_break_target(coord)
	if target.is_empty() or not _is_target_in_range(peer_id, target):
		_clear_primary_use_for_peer(peer_id)
		return

	var target_key := String(target.get("key", ""))
	var use_state := {
		"coord": coord,
		"slot_index": slot_index,
		"target_key": target_key,
		"last_intent_time": _now_seconds(),
	}
	_active_uses_by_peer[peer_id] = use_state

	if not _damaged_targets.has(target_key):
		_damaged_targets[target_key] = _build_damaged_target(target)
		_broadcast_damaged_target(target_key, _damaged_targets[target_key])


func _clear_primary_use_for_peer(peer_id: int) -> void:
	_active_uses_by_peer.erase(peer_id)


func _process_active_uses(now: float) -> void:
	var peer_ids := _active_uses_by_peer.keys()
	for peer_id_variant in peer_ids:
		var peer_id := int(peer_id_variant)
		var use_state := _active_uses_by_peer.get(peer_id, {}) as Dictionary
		if use_state.is_empty():
			continue

		if now - float(use_state.get("last_intent_time", 0.0)) > GameConstants.PRIMARY_USE_TIMEOUT:
			_active_uses_by_peer.erase(peer_id)
			continue

		var target := _resolve_break_target(use_state.get("coord", Vector2i.ZERO) as Vector2i)
		if target.is_empty():
			_active_uses_by_peer.erase(peer_id)
			continue

		var target_key := String(target.get("key", ""))
		if target_key != String(use_state.get("target_key", "")) or not _is_target_in_range(peer_id, target):
			_active_uses_by_peer.erase(peer_id)
			continue

		var next_allowed_use_time := float(_next_primary_use_time_by_peer.get(peer_id, 0.0))
		if now < next_allowed_use_time:
			continue

		var use_profile := _resolve_use_profile(peer_id, int(use_state.get("slot_index", -1)))
		_apply_break_hit(target, use_profile, now)
		_next_primary_use_time_by_peer[peer_id] = (
			now + float(use_profile.get("cooldown", GameConstants.PRIMARY_USE_COOLDOWN))
		)


func _process_damaged_targets(now: float) -> void:
	var target_keys := _damaged_targets.keys()
	for target_key_variant in target_keys:
		var target_key := String(target_key_variant)
		var target_state := _damaged_targets.get(target_key, {}) as Dictionary
		if target_state.is_empty():
			continue
		if not _does_target_exist(target_state):
			_remove_damaged_target(target_key)
			continue
		if now - float(target_state.get("last_hit_time", 0.0)) >= GameConstants.DAMAGED_TARGET_TIMEOUT:
			_remove_damaged_target(target_key)


func _apply_break_hit(target: Dictionary, use_profile: Dictionary, now: float) -> void:
	var target_key := String(target.get("key", ""))
	var target_state := _damaged_targets.get(target_key, {}) as Dictionary
	if target_state.is_empty():
		target_state = _build_damaged_target(target)

	target_state["damage"] = float(target_state.get("damage", 0.0)) + float(use_profile.get("damage", GameConstants.BREAK_BASE_DAMAGE))
	target_state["last_hit_time"] = now
	target_state["stage"] = _compute_stage(
		float(target_state.get("damage", 0.0)), float(target_state.get("durability", 1.0))
	)
	_damaged_targets[target_key] = target_state
	_broadcast_damaged_target(target_key, target_state)

	if float(target_state.get("damage", 0.0)) + 0.0001 < float(target_state.get("durability", 1.0)):
		return

	_complete_break_target(target_state)
	_remove_damaged_target(target_key)


func _build_damaged_target(target: Dictionary) -> Dictionary:
	return {
		"kind": String(target.get("kind", "")),
		"coord": target.get("coord", Vector2i.ZERO),
		"structure_id": String(target.get("structure_id", "")),
		"origin": target.get("origin", Vector2i.ZERO),
		"durability": float(target.get("durability", 1.0)),
		"damage": 0.0,
		"stage": 0,
		"last_hit_time": _now_seconds(),
	}


func _resolve_break_target(coord: Vector2i) -> Dictionary:
	if chunk_manager != null:
		var tile_id := int(chunk_manager.get_top_tile_at(coord))
		if tile_id != TileProperties.EMPTY:
			var tile_props := TileProperties.get_properties(tile_id)
			if tile_props != null and tile_props.breakable:
				return {
					"key": _tile_target_key(coord),
					"kind": TARGET_KIND_TILE,
					"coord": coord,
					"durability": tile_props.hardness,
				}

	if structure_manager != null:
		var structure_data := structure_manager.get_breakable_structure_data(coord) as Dictionary
		if not structure_data.is_empty():
			var structure_id := String(structure_data.get("structure_id", ""))
			var origin := structure_data.get("origin", Vector2i.ZERO) as Vector2i
			return {
				"key": _structure_target_key(structure_id, origin),
				"kind": TARGET_KIND_STRUCTURE,
				"coord": coord,
				"structure_id": structure_id,
				"origin": origin,
				"durability": float(structure_data.get("hardness", 1.0)),
			}

	return {}


func _resolve_use_profile(peer_id: int, slot_index: int) -> Dictionary:
	var item_id := ItemProperties.NONE
	if inventory_manager != null and slot_index >= 0:
		var inv: Inventory = inventory_manager.get_inventory(peer_id)
		if inv != null and slot_index < inv.size:
			item_id = int(inv.get_slot(slot_index).get("item_id", ItemProperties.NONE))
	var damage := GameConstants.BREAK_BASE_DAMAGE
	var cooldown := GameConstants.PRIMARY_USE_COOLDOWN
	var props := ItemProperties.get_properties(item_id)
	if props != null:
		damage = props.get_break_damage()
		cooldown = props.get_use_cooldown()
	return {
		"item_id": item_id,
		"damage": damage,
		"cooldown": cooldown,
	}


func _complete_break_target(target_state: Dictionary) -> void:
	var kind := String(target_state.get("kind", ""))
	if kind == TARGET_KIND_TILE and chunk_manager != null:
		chunk_manager.break_tile(target_state.get("coord", Vector2i.ZERO) as Vector2i)
		return
	if kind == TARGET_KIND_STRUCTURE and structure_manager != null:
		structure_manager.break_structure_instance(
			String(target_state.get("structure_id", "")),
			target_state.get("origin", Vector2i.ZERO) as Vector2i
		)


func _does_target_exist(target_state: Dictionary) -> bool:
	var kind := String(target_state.get("kind", ""))
	if kind == TARGET_KIND_TILE and chunk_manager != null:
		var tile_id := int(chunk_manager.get_top_tile_at(target_state.get("coord", Vector2i.ZERO) as Vector2i))
		return tile_id != TileProperties.EMPTY
	if kind == TARGET_KIND_STRUCTURE and structure_manager != null:
		return structure_manager.has_structure_instance(
			String(target_state.get("structure_id", "")),
			target_state.get("origin", Vector2i.ZERO) as Vector2i
		)
	return false


func _is_target_in_range(peer_id: int, target: Dictionary) -> bool:
	if players_node == null:
		return false
	var player_node := players_node.get_node_or_null(str(peer_id))
	if player_node == null:
		return false
	var coord := target.get("coord", Vector2i.ZERO) as Vector2i
	var world_pos := Vector2(
		coord.x * GameConstants.TILE_SIZE + GameConstants.TILE_SIZE / 2.0,
		coord.y * GameConstants.TILE_SIZE + GameConstants.TILE_SIZE / 2.0
	)
	return player_node.global_position.distance_to(world_pos) <= GameConstants.BLOCK_INTERACT_RANGE


func _broadcast_damaged_target(target_key: String, target_state: Dictionary) -> void:
	var payload := _serialize_target(target_state)
	_sync_damaged_target(target_key, payload)
	if multiplayer.multiplayer_peer != null:
		_sync_damaged_target.rpc(target_key, payload)


func _remove_damaged_target(target_key: String) -> void:
	_damaged_targets.erase(target_key)
	_clear_damaged_target(target_key)
	if multiplayer.multiplayer_peer != null:
		_clear_damaged_target.rpc(target_key)


func _serialize_target(target_state: Dictionary) -> Dictionary:
	var payload := {
		"kind": String(target_state.get("kind", "")),
		"stage": int(target_state.get("stage", 0)),
	}
	if String(target_state.get("kind", "")) == TARGET_KIND_TILE:
		var coord := target_state.get("coord", Vector2i.ZERO) as Vector2i
		payload["coord_x"] = coord.x
		payload["coord_y"] = coord.y
	else:
		var origin := target_state.get("origin", Vector2i.ZERO) as Vector2i
		payload["structure_id"] = String(target_state.get("structure_id", ""))
		payload["origin_x"] = origin.x
		payload["origin_y"] = origin.y
	return payload


func _compute_stage(damage: float, durability: float) -> int:
	var ratio := clampf(damage / maxf(durability, 0.001), 0.0, 1.0)
	return mini(int(floor(ratio * float(GameConstants.BREAK_STAGE_COUNT))), GameConstants.BREAK_STAGE_COUNT - 1)


func _tile_target_key(coord: Vector2i) -> String:
	return "tile:%s:%s" % [coord.x, coord.y]


func _structure_target_key(structure_id: String, origin: Vector2i) -> String:
	return "structure:%s:%s:%s" % [structure_id, origin.x, origin.y]


func _now_seconds() -> float:
	return Time.get_ticks_usec() * 0.000001


func _on_player_disconnected(peer_id: int) -> void:
	_active_uses_by_peer.erase(peer_id)
	_next_primary_use_time_by_peer.erase(peer_id)
