extends Node
## RPC bridge + client sync surface for inventory.
## Server-side authoritative state and world placement rules live in dedicated services.

signal local_slot_changed(index: int)
signal local_inventory_synced
signal local_held_slot_changed

var local_inventory: Inventory
var local_held_slot: Dictionary = {"item_id": ItemProperties.NONE, "count": 0}

var _authority_service: Node
var _world_placement_service: Node


func setup(authority_service: Node, world_placement_service: Node) -> void:
	_authority_service = authority_service
	_world_placement_service = world_placement_service
	_authority_service.setup(
		Callable(self, "_sync_full_inventory_to_peer"),
		Callable(self, "_sync_slot_to_peer"),
		Callable(self, "_sync_held_slot_to_peer")
	)


func create_inventory(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_authority_service.create_inventory(peer_id)


func remove_inventory(peer_id: int) -> Inventory:
	if not multiplayer.is_server():
		return null
	return _authority_service.remove_inventory(peer_id)


func get_inventory(peer_id: int) -> Inventory:
	return _authority_service.get_inventory(peer_id)


func get_persistent_inventory_snapshot(peer_id: int) -> Array:
	return _authority_service.get_persistent_inventory_snapshot(peer_id)


func sync_inventory(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_authority_service.sync_inventory(peer_id)


func server_add_item(peer_id: int, item_id: int, count: int) -> int:
	if not multiplayer.is_server():
		return count
	return _authority_service.server_add_item(peer_id, item_id, count)


func server_remove_item(peer_id: int, item_id: int, count: int) -> bool:
	if not multiplayer.is_server():
		return false
	return _authority_service.server_remove_item(peer_id, item_id, count)


func server_remove_from_slot(peer_id: int, slot_index: int) -> int:
	if not multiplayer.is_server():
		return ItemProperties.NONE
	return _authority_service.server_remove_from_slot(peer_id, slot_index)


func _sync_full_inventory_to_peer(peer_id: int, inv: Inventory) -> void:
	var data: PackedByteArray = var_to_bytes(inv.serialize())
	if peer_id == multiplayer.get_unique_id():
		_sync_full_inventory(data)
	else:
		_sync_full_inventory.rpc_id(peer_id, data)


func _sync_slot_to_peer(peer_id: int, index: int, slot: Dictionary) -> void:
	if peer_id == multiplayer.get_unique_id():
		_sync_slot(index, slot["item_id"], slot["count"])
	else:
		_sync_slot.rpc_id(peer_id, index, slot["item_id"], slot["count"])


func _sync_held_slot_to_peer(peer_id: int, slot: Dictionary) -> void:
	if peer_id == multiplayer.get_unique_id():
		_sync_held_slot(slot["item_id"], slot["count"])
	else:
		_sync_held_slot.rpc_id(peer_id, slot["item_id"], slot["count"])


@rpc("authority", "reliable")
func _sync_full_inventory(data: PackedByteArray) -> void:
	var slots: Array = bytes_to_var(data)
	local_inventory = Inventory.deserialize(slots)
	local_inventory.slot_changed.connect(func(index: int) -> void:
		local_slot_changed.emit(index)
	)
	local_inventory_synced.emit()
	print("[InventoryManager] Received full inventory (%d slots)" % local_inventory.size)


@rpc("authority", "reliable")
func _sync_slot(index: int, item_id: int, count: int) -> void:
	if local_inventory == null:
		return
	local_inventory.set_slot(index, item_id, count)


@rpc("authority", "reliable")
func _sync_held_slot(item_id: int, count: int) -> void:
	local_held_slot = _slot_dict(item_id, count)
	local_held_slot_changed.emit()


@rpc("any_peer", "reliable")
func _request_place_block(slot_index: int, tx: int, ty: int) -> void:
	if not multiplayer.is_server():
		return

	var sender_id := _get_sender_id()
	var inv: Inventory = _authority_service.get_inventory(sender_id)
	if inv == null:
		return

	var slot: Dictionary = inv.get_slot(slot_index)
	if _is_empty_slot(slot):
		return

	var coord := Vector2i(tx, ty)
	if not _world_placement_service.validate_and_place_world_item(sender_id, slot["item_id"], coord):
		return

	_authority_service.consume_slot_for_placement(sender_id, slot_index)


@rpc("any_peer", "reliable")
func _request_place_held_block(tx: int, ty: int) -> void:
	if not multiplayer.is_server():
		return

	var sender_id := _get_sender_id()
	var held: Dictionary = _authority_service.get_held_slot(sender_id)
	if _is_empty_slot(held):
		return

	var coord := Vector2i(tx, ty)
	if not _world_placement_service.validate_and_place_world_item(sender_id, held["item_id"], coord):
		return

	_authority_service.consume_held_for_placement(sender_id)


@rpc("any_peer", "reliable")
func _request_inventory_action(action: String, slot_index: int) -> void:
	if not multiplayer.is_server():
		return
	_authority_service.process_inventory_action(_get_sender_id(), action, slot_index)


@rpc("any_peer", "reliable")
func _request_inventory_distribute_even(slot_indices: Array) -> void:
	if not multiplayer.is_server():
		return
	_authority_service.distribute_even(_get_sender_id(), slot_indices)


@rpc("any_peer", "reliable")
func _request_pickup_matching_item(item_id: int) -> void:
	if not multiplayer.is_server():
		return
	_authority_service.pickup_matching_item(_get_sender_id(), item_id)


func _get_sender_id() -> int:
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()
	return sender_id


func _slot_dict(item_id: int, count: int) -> Dictionary:
	if item_id == ItemProperties.NONE or count <= 0:
		return {"item_id": ItemProperties.NONE, "count": 0}
	return {"item_id": item_id, "count": count}


func _is_empty_slot(slot: Dictionary) -> bool:
	return (
		slot.get("item_id", ItemProperties.NONE) == ItemProperties.NONE
		or slot.get("count", 0) <= 0
	)
