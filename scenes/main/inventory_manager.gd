extends Node
## Host-authoritative manager for all player inventories.
## Lives as a child of Main -- server infrastructure, not player logic.
## Handles inventory RPCs: full sync on join, delta sync on changes.

## Host-only: authoritative inventory for each connected peer.
var _inventories: Dictionary = {}  # { peer_id: Inventory }
## Host-only: authoritative held cursor-slot for each connected peer.
var _held_slots: Dictionary = {}  # { peer_id: { "item_id": int, "count": int } }

## Client-only: local copy of this client's inventory (for UI reads).
var local_inventory: Inventory
## Client-only: local copy of this client's held cursor-slot.
var local_held_slot: Dictionary = {"item_id": ItemProperties.NONE, "count": 0}

## Emitted on the client that owns this inventory when a slot changes.
signal local_slot_changed(index: int)
## Emitted on the client when a full inventory snapshot was received/replaced.
signal local_inventory_synced
## Emitted on the client when the held cursor-slot changes.
signal local_held_slot_changed

## Reference to the item spawner (set by main.gd).
var item_spawner: MultiplayerSpawner

## Reference to the chunk manager (set by main.gd).
var chunk_manager: Node
var structure_manager: Node


# --- Lifecycle (called by main.gd) ---


## Host creates an inventory for a newly connected player.
func create_inventory(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var inv := Inventory.new(GameConstants.INVENTORY_SIZE)
	_inventories[peer_id] = inv
	_held_slots[peer_id] = _empty_slot()
	_sync_full_inventory_to_peer(peer_id, inv)
	_sync_held_slot_to_peer(peer_id, _held_slots[peer_id])


## Host cleans up when a player disconnects. Returns the inventory for
## potential persistence (save to disk) before it is erased.
func remove_inventory(peer_id: int) -> Inventory:
	if not multiplayer.is_server():
		return null
	var inv: Inventory = _inventories.get(peer_id)
	_inventories.erase(peer_id)
	_held_slots.erase(peer_id)
	return inv


## Returns the host-authoritative inventory for a peer, or null.
func get_inventory(peer_id: int) -> Inventory:
	return _inventories.get(peer_id)


## Returns a save-friendly inventory snapshot. Any currently held cursor-stack
## is merged back into a temporary copy so autosaves do not lose items.
func get_persistent_inventory_snapshot(peer_id: int) -> Array:
	var inv: Inventory = _inventories.get(peer_id)
	if inv == null:
		return []

	var snapshot := Inventory.deserialize(inv.serialize())
	var held: Dictionary = _held_slots.get(peer_id, _empty_slot())
	if not _is_empty_slot(held):
		var remainder: int = snapshot.add_item(held["item_id"], held["count"])
		if remainder > 0:
			push_warning(
				"[InventoryManager] Could not fully merge held slot for peer %d into save snapshot"
				% peer_id
			)
	return snapshot.serialize()


## Re-sends the full inventory to the owning client. Call after bulk changes
## (e.g. restoring from a save file) to bring the client up to date.
func sync_inventory(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var inv: Inventory = _inventories.get(peer_id)
	if inv == null:
		return
	_sync_full_inventory_to_peer(peer_id, inv)
	_sync_held_slot_to_peer(peer_id, _held_slots.get(peer_id, _empty_slot()))


# --- Host-side item operations ---


## Adds items to a player's inventory. Returns the remainder that did not fit.
## Automatically syncs changed slots to the owning client.
func server_add_item(peer_id: int, item_id: int, count: int) -> int:
	if not multiplayer.is_server():
		return count
	var inv: Inventory = _inventories.get(peer_id)
	if inv == null:
		return count

	# Track which slots change so we only sync those.
	var changed_slots: Array[int] = []
	var _on_change := func(index: int) -> void:
		_append_changed_slot(changed_slots, index)
	inv.slot_changed.connect(_on_change)

	var remainder: int = inv.add_item(item_id, count)

	inv.slot_changed.disconnect(_on_change)

	# Delta-sync each changed slot to the client.
	for slot_index in changed_slots:
		var slot: Dictionary = inv.get_slot(slot_index)
		_sync_slot_to_peer(peer_id, slot_index, slot)

	return remainder


## Removes items from a player's inventory. Returns true if successful.
## Automatically syncs changed slots to the owning client.
func server_remove_item(peer_id: int, item_id: int, count: int) -> bool:
	if not multiplayer.is_server():
		return false
	var inv: Inventory = _inventories.get(peer_id)
	if inv == null:
		return false

	var changed_slots: Array[int] = []
	var _on_change := func(index: int) -> void:
		_append_changed_slot(changed_slots, index)
	inv.slot_changed.connect(_on_change)

	var success: bool = inv.remove_item(item_id, count)

	inv.slot_changed.disconnect(_on_change)

	if success:
		for slot_index in changed_slots:
			var slot: Dictionary = inv.get_slot(slot_index)
			_sync_slot_to_peer(peer_id, slot_index, slot)

	return success


## Removes one item from a specific slot. Returns the item_id removed, or NONE.
## Used for block placing (player picks a specific hotbar slot).
func server_remove_from_slot(peer_id: int, slot_index: int) -> int:
	if not multiplayer.is_server():
		return ItemProperties.NONE
	var inv: Inventory = _inventories.get(peer_id)
	if inv == null:
		return ItemProperties.NONE

	var item_id: int = inv.remove_from_slot(slot_index)
	if item_id != ItemProperties.NONE:
		var slot: Dictionary = inv.get_slot(slot_index)
		_sync_slot_to_peer(peer_id, slot_index, slot)

	return item_id


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


# --- RPCs: Host -> Client (sync) ---


## Sends the full inventory to a client (on join or resync).
@rpc("authority", "reliable")
func _sync_full_inventory(data: PackedByteArray) -> void:
	var slots: Array = bytes_to_var(data)
	local_inventory = Inventory.deserialize(slots)
	local_inventory.slot_changed.connect(func(index: int) -> void:
		local_slot_changed.emit(index)
	)
	local_inventory_synced.emit()
	print("[InventoryManager] Received full inventory (%d slots)" % local_inventory.size)


## Updates a single slot on the client.
@rpc("authority", "reliable")
func _sync_slot(index: int, item_id: int, count: int) -> void:
	if local_inventory == null:
		return
	local_inventory.set_slot(index, item_id, count)


## Updates the held cursor-slot on the client.
@rpc("authority", "reliable")
func _sync_held_slot(item_id: int, count: int) -> void:
	local_held_slot = _slot_dict(item_id, count)
	local_held_slot_changed.emit()


# --- RPCs: Client -> Host (requests / intents) ---


## Client requests to place a block from a specific inventory slot.
@rpc("any_peer", "reliable")
func _request_place_block(slot_index: int, tx: int, ty: int) -> void:
	if not multiplayer.is_server():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()
	var inv: Inventory = _inventories.get(sender_id)
	if inv == null:
		return

	# Validate: slot has an item.
	var slot: Dictionary = inv.get_slot(slot_index)
	if _is_empty_slot(slot):
		return

	if not _validate_and_place_world_item(sender_id, slot["item_id"], tx, ty):
		return

	server_remove_from_slot(sender_id, slot_index)


## Client requests to place a block from the held cursor-stack.
@rpc("any_peer", "reliable")
func _request_place_held_block(tx: int, ty: int) -> void:
	if not multiplayer.is_server():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()

	var held: Dictionary = _held_slots.get(sender_id, _empty_slot())
	if _is_empty_slot(held):
		return

	if not _validate_and_place_world_item(sender_id, held["item_id"], tx, ty):
		return

	_set_held_slot(sender_id, held["item_id"], held["count"] - 1)


func _validate_and_place_world_item(sender_id: int, item_id: int, tx: int, ty: int) -> bool:
	if item_id == ItemProperties.NONE:
		return false

	# Validate: item is placeable.
	var item_props := ItemProperties.get_properties(item_id)
	if item_props == null or not item_props.is_placeable():
		return false

	# Validate: target cell / footprint is placeable.
	var coord := Vector2i(tx, ty)
	if chunk_manager == null:
		return false

	# Validate: player is in range.
	var players_node: Node = get_tree().get_root().get_node_or_null("Main/World/DepthSorted/Players")
	if players_node == null:
		return false
	var player_node := players_node.get_node_or_null(str(sender_id))
	if player_node == null:
		return false
	var tile_center := Vector2(
		tx * GameConstants.TILE_SIZE + GameConstants.TILE_SIZE / 2.0,
		ty * GameConstants.TILE_SIZE + GameConstants.TILE_SIZE / 2.0,
	)
	if player_node.global_position.distance_to(tile_center) > GameConstants.BLOCK_INTERACT_RANGE:
		return false

	# All checks passed -- place block and consume item.
	if item_props.places_tile():
		if not chunk_manager.is_cell_empty(coord):
			return false
		if structure_manager != null and structure_manager.is_cell_occupied(coord):
			return false
		chunk_manager.place_tile(coord, item_props.tile_id)
	elif item_props.places_structure():
		if structure_manager == null:
			return false
		if not structure_manager.place_structure(coord, item_props.structure_id):
			return false
	else:
		return false

	return true


## Client requests an inventory interaction on one slot.
@rpc("any_peer", "reliable")
func _request_inventory_action(action: String, slot_index: int) -> void:
	if not multiplayer.is_server():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()

	var inv: Inventory = _inventories.get(sender_id)
	if inv == null:
		return
	if slot_index < 0 or slot_index >= inv.size:
		return

	match action:
		"pickup_full":
			_server_pickup_full(sender_id, inv, slot_index)
		"pickup_half":
			_server_pickup_half(sender_id, inv, slot_index)
		"pickup_matching":
			_server_pickup_matching(sender_id, inv, slot_index)
		"place_full":
			_server_place_full(sender_id, inv, slot_index)
		"place_one":
			_server_place_one(sender_id, inv, slot_index)
		"quick_transfer":
			_server_quick_transfer(sender_id, inv, slot_index)


@rpc("any_peer", "reliable")
func _request_inventory_distribute_even(slot_indices: Array) -> void:
	if not multiplayer.is_server():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()

	var inv: Inventory = _inventories.get(sender_id)
	if inv == null:
		return

	_server_distribute_even(sender_id, inv, slot_indices)


@rpc("any_peer", "reliable")
func _request_pickup_matching_item(item_id: int) -> void:
	if not multiplayer.is_server():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()

	var inv: Inventory = _inventories.get(sender_id)
	if inv == null:
		return

	_server_pickup_matching_item(sender_id, inv, item_id)


func _server_pickup_full(peer_id: int, inv: Inventory, slot_index: int) -> void:
	var held: Dictionary = _held_slots.get(peer_id, _empty_slot())
	if not _is_empty_slot(held):
		return

	var slot: Dictionary = inv.get_slot(slot_index)
	if _is_empty_slot(slot):
		return

	inv.set_slot(slot_index, ItemProperties.NONE, 0)
	_sync_slot_to_peer(peer_id, slot_index, inv.get_slot(slot_index))
	_set_held_slot(peer_id, slot["item_id"], slot["count"])


func _server_pickup_half(peer_id: int, inv: Inventory, slot_index: int) -> void:
	var held: Dictionary = _held_slots.get(peer_id, _empty_slot())
	if not _is_empty_slot(held):
		return

	var slot: Dictionary = inv.get_slot(slot_index)
	if _is_empty_slot(slot):
		return

	var take_count: int = int(ceil(float(slot["count"]) / 2.0))
	var remaining: int = slot["count"] - take_count

	if remaining <= 0:
		inv.set_slot(slot_index, ItemProperties.NONE, 0)
	else:
		inv.set_slot(slot_index, slot["item_id"], remaining)

	_sync_slot_to_peer(peer_id, slot_index, inv.get_slot(slot_index))
	_set_held_slot(peer_id, slot["item_id"], take_count)


func _server_pickup_matching(peer_id: int, inv: Inventory, slot_index: int) -> void:
	var slot: Dictionary = inv.get_slot(slot_index)
	if _is_empty_slot(slot):
		return

	_server_pickup_matching_item(peer_id, inv, slot["item_id"])


func _server_pickup_matching_item(peer_id: int, inv: Inventory, item_id: int) -> void:
	var props: ItemProperties = ItemProperties.get_properties(item_id)
	if props == null:
		return

	var held: Dictionary = _held_slots.get(peer_id, _empty_slot())
	var held_count: int = 0
	if not _is_empty_slot(held):
		if held["item_id"] != item_id:
			return
		held_count = held["count"]

	if held_count >= props.max_stack:
		return

	var changed_slots: Array[int] = []
	for i: int in range(inv.size):
		var source: Dictionary = inv.get_slot(i)
		if source["item_id"] != item_id:
			continue

		var space: int = props.max_stack - held_count
		if space <= 0:
			break

		var moved: int = mini(space, source["count"])
		if moved <= 0:
			continue

		held_count += moved
		if moved >= source["count"]:
			inv.set_slot(i, ItemProperties.NONE, 0)
		else:
			inv.set_slot(i, item_id, source["count"] - moved)
		_append_changed_slot(changed_slots, i)

	for changed_index in changed_slots:
		_sync_slot_to_peer(peer_id, changed_index, inv.get_slot(changed_index))
	if not changed_slots.is_empty() or held_count > 0:
		_set_held_slot(peer_id, item_id, held_count)


func _server_place_full(peer_id: int, inv: Inventory, slot_index: int) -> void:
	var held: Dictionary = _held_slots.get(peer_id, _empty_slot())
	if _is_empty_slot(held):
		return

	var held_item_id: int = held["item_id"]
	var held_count: int = held["count"]
	var held_props: ItemProperties = ItemProperties.get_properties(held_item_id)
	if held_props == null:
		return

	var slot: Dictionary = inv.get_slot(slot_index)
	if _is_empty_slot(slot):
		inv.set_slot(slot_index, held_item_id, held_count)
		_sync_slot_to_peer(peer_id, slot_index, inv.get_slot(slot_index))
		_set_held_slot(peer_id, ItemProperties.NONE, 0)
		return

	if slot["item_id"] == held_item_id:
		var space: int = held_props.max_stack - slot["count"]
		if space <= 0:
			return
		var moved: int = mini(space, held_count)
		inv.set_slot(slot_index, held_item_id, slot["count"] + moved)
		_sync_slot_to_peer(peer_id, slot_index, inv.get_slot(slot_index))
		_set_held_slot(peer_id, held_item_id, held_count - moved)
		return

	inv.set_slot(slot_index, held_item_id, held_count)
	_sync_slot_to_peer(peer_id, slot_index, inv.get_slot(slot_index))
	_set_held_slot(peer_id, slot["item_id"], slot["count"])


func _server_place_one(peer_id: int, inv: Inventory, slot_index: int) -> void:
	var held: Dictionary = _held_slots.get(peer_id, _empty_slot())
	if _is_empty_slot(held):
		return

	var held_item_id: int = held["item_id"]
	var held_count: int = held["count"]
	var held_props: ItemProperties = ItemProperties.get_properties(held_item_id)
	if held_props == null:
		return

	var slot: Dictionary = inv.get_slot(slot_index)
	if _is_empty_slot(slot):
		inv.set_slot(slot_index, held_item_id, 1)
		_sync_slot_to_peer(peer_id, slot_index, inv.get_slot(slot_index))
		_set_held_slot(peer_id, held_item_id, held_count - 1)
		return

	if slot["item_id"] != held_item_id:
		return
	if slot["count"] >= held_props.max_stack:
		return

	inv.set_slot(slot_index, held_item_id, slot["count"] + 1)
	_sync_slot_to_peer(peer_id, slot_index, inv.get_slot(slot_index))
	_set_held_slot(peer_id, held_item_id, held_count - 1)


func _server_quick_transfer(peer_id: int, inv: Inventory, slot_index: int) -> void:
	var held: Dictionary = _held_slots.get(peer_id, _empty_slot())
	if not _is_empty_slot(held):
		return

	var target_start: int = GameConstants.HOTBAR_SIZE if slot_index < GameConstants.HOTBAR_SIZE else 0
	var target_end: int = inv.size if slot_index < GameConstants.HOTBAR_SIZE else GameConstants.HOTBAR_SIZE
	var changed_slots := _transfer_slot_to_range(inv, slot_index, target_start, target_end)
	for changed_index in changed_slots:
		_sync_slot_to_peer(peer_id, changed_index, inv.get_slot(changed_index))


func _server_distribute_even(peer_id: int, inv: Inventory, slot_indices: Array) -> void:
	var held: Dictionary = _held_slots.get(peer_id, _empty_slot())
	if _is_empty_slot(held):
		return

	var item_id: int = held["item_id"]
	var held_count: int = held["count"]
	var props: ItemProperties = ItemProperties.get_properties(item_id)
	if props == null or held_count <= 0:
		return

	var unique_slots: Array[int] = []
	for raw_slot in slot_indices:
		var slot_index: int = int(raw_slot)
		if slot_index < 0 or slot_index >= inv.size:
			continue
		if slot_index in unique_slots:
			continue

		var slot: Dictionary = inv.get_slot(slot_index)
		if _is_empty_slot(slot) or (
			slot["item_id"] == item_id and slot["count"] < props.max_stack
		):
			unique_slots.append(slot_index)

	if unique_slots.is_empty():
		return

	var changed_slots: Array[int] = []
	var remaining: int = held_count
	var placed_any: bool = false

	while remaining > 0:
		var placed_in_pass: bool = false
		for slot_index in unique_slots:
			if remaining <= 0:
				break
			var slot: Dictionary = inv.get_slot(slot_index)
			if _is_empty_slot(slot):
				inv.set_slot(slot_index, item_id, 1)
				remaining -= 1
				placed_in_pass = true
				placed_any = true
				_append_changed_slot(changed_slots, slot_index)
			elif slot["item_id"] == item_id and slot["count"] < props.max_stack:
				inv.set_slot(slot_index, item_id, slot["count"] + 1)
				remaining -= 1
				placed_in_pass = true
				placed_any = true
				_append_changed_slot(changed_slots, slot_index)
		if not placed_in_pass:
			break

	for changed_index in changed_slots:
		_sync_slot_to_peer(peer_id, changed_index, inv.get_slot(changed_index))
	if placed_any:
		_set_held_slot(peer_id, item_id, remaining)


func _transfer_slot_to_range(
	inv: Inventory, slot_index: int, target_start: int, target_end: int
) -> Array[int]:
	var source: Dictionary = inv.get_slot(slot_index)
	if _is_empty_slot(source):
		return []

	var item_id: int = source["item_id"]
	var remaining: int = source["count"]
	var props: ItemProperties = ItemProperties.get_properties(item_id)
	if props == null:
		return []

	var changed_slots: Array[int] = []

	for i: int in range(target_start, target_end):
		if i == slot_index:
			continue
		var target: Dictionary = inv.get_slot(i)
		if target["item_id"] != item_id or target["count"] >= props.max_stack:
			continue
		var moved: int = mini(props.max_stack - target["count"], remaining)
		if moved <= 0:
			continue
		inv.set_slot(i, item_id, target["count"] + moved)
		remaining -= moved
		_append_changed_slot(changed_slots, i)
		if remaining <= 0:
			break

	for i: int in range(target_start, target_end):
		if remaining <= 0:
			break
		if i == slot_index:
			continue
		var target: Dictionary = inv.get_slot(i)
		if not _is_empty_slot(target):
			continue
		var moved: int = mini(props.max_stack, remaining)
		inv.set_slot(i, item_id, moved)
		remaining -= moved
		_append_changed_slot(changed_slots, i)

	if remaining == source["count"]:
		return []

	if remaining <= 0:
		inv.set_slot(slot_index, ItemProperties.NONE, 0)
	else:
		inv.set_slot(slot_index, item_id, remaining)
	_append_changed_slot(changed_slots, slot_index)
	return changed_slots


func _set_held_slot(peer_id: int, item_id: int, count: int) -> void:
	var slot := _slot_dict(item_id, count)
	_held_slots[peer_id] = slot
	_sync_held_slot_to_peer(peer_id, slot)


func _append_changed_slot(changed_slots: Array[int], slot_index: int) -> void:
	if not (slot_index in changed_slots):
		changed_slots.append(slot_index)


func _slot_dict(item_id: int, count: int) -> Dictionary:
	if item_id == ItemProperties.NONE or count <= 0:
		return _empty_slot()
	return {"item_id": item_id, "count": count}


func _empty_slot() -> Dictionary:
	return {"item_id": ItemProperties.NONE, "count": 0}


func _is_empty_slot(slot: Dictionary) -> bool:
	return slot.get("item_id", ItemProperties.NONE) == ItemProperties.NONE or slot.get("count", 0) <= 0
