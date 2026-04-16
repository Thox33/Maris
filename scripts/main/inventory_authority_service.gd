extends Node

## Server-side authoritative inventory state and inventory interaction rules.

var _inventories: Dictionary = {}
var _held_slots: Dictionary = {}

var _sync_full_inventory_to_peer: Callable
var _sync_slot_to_peer: Callable
var _sync_held_slot_to_peer: Callable


func setup(
	p_sync_full_inventory_to_peer: Callable,
	p_sync_slot_to_peer: Callable,
	p_sync_held_slot_to_peer: Callable
) -> void:
	_sync_full_inventory_to_peer = p_sync_full_inventory_to_peer
	_sync_slot_to_peer = p_sync_slot_to_peer
	_sync_held_slot_to_peer = p_sync_held_slot_to_peer


func create_inventory(peer_id: int) -> void:
	var inv := Inventory.new(GameConstants.INVENTORY_SIZE)
	_inventories[peer_id] = inv
	_held_slots[peer_id] = _empty_slot()
	_sync_full_inventory_to_peer.call(peer_id, inv)
	_sync_held_slot_to_peer.call(peer_id, _held_slots[peer_id])


func remove_inventory(peer_id: int) -> Inventory:
	var inv: Inventory = _inventories.get(peer_id)
	_inventories.erase(peer_id)
	_held_slots.erase(peer_id)
	return inv


func get_inventory(peer_id: int) -> Inventory:
	return _inventories.get(peer_id)


func get_held_slot(peer_id: int) -> Dictionary:
	return (_held_slots.get(peer_id, _empty_slot()) as Dictionary).duplicate()


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
				"[InventoryAuthorityService] Could not fully merge held slot for peer %d into save snapshot"
				% peer_id
			)
	return snapshot.serialize()


func sync_inventory(peer_id: int) -> void:
	var inv: Inventory = _inventories.get(peer_id)
	if inv == null:
		return
	_sync_full_inventory_to_peer.call(peer_id, inv)
	_sync_held_slot_to_peer.call(peer_id, _held_slots.get(peer_id, _empty_slot()))


func server_add_item(peer_id: int, item_id: int, count: int) -> int:
	var inv: Inventory = _inventories.get(peer_id)
	if inv == null:
		return count

	var changed_slots: Array[int] = []
	var on_change := func(index: int) -> void:
		_append_changed_slot(changed_slots, index)
	inv.slot_changed.connect(on_change)

	var remainder: int = inv.add_item(item_id, count)

	inv.slot_changed.disconnect(on_change)

	for slot_index in changed_slots:
		_sync_slot_to_peer.call(peer_id, slot_index, inv.get_slot(slot_index))

	return remainder


func server_remove_item(peer_id: int, item_id: int, count: int) -> bool:
	var inv: Inventory = _inventories.get(peer_id)
	if inv == null:
		return false

	var changed_slots: Array[int] = []
	var on_change := func(index: int) -> void:
		_append_changed_slot(changed_slots, index)
	inv.slot_changed.connect(on_change)

	var success: bool = inv.remove_item(item_id, count)

	inv.slot_changed.disconnect(on_change)

	if success:
		for slot_index in changed_slots:
			_sync_slot_to_peer.call(peer_id, slot_index, inv.get_slot(slot_index))

	return success


func server_remove_from_slot(peer_id: int, slot_index: int) -> int:
	var inv: Inventory = _inventories.get(peer_id)
	if inv == null:
		return ItemProperties.NONE

	var item_id: int = inv.remove_from_slot(slot_index)
	if item_id != ItemProperties.NONE:
		_sync_slot_to_peer.call(peer_id, slot_index, inv.get_slot(slot_index))

	return item_id


func consume_slot_for_placement(peer_id: int, slot_index: int) -> void:
	server_remove_from_slot(peer_id, slot_index)


func consume_held_for_placement(peer_id: int) -> void:
	var held: Dictionary = _held_slots.get(peer_id, _empty_slot())
	if _is_empty_slot(held):
		return
	_set_held_slot(peer_id, held["item_id"], held["count"] - 1)


func process_inventory_action(peer_id: int, action: String, slot_index: int) -> void:
	var inv: Inventory = _inventories.get(peer_id)
	if inv == null:
		return
	if slot_index < 0 or slot_index >= inv.size:
		return

	match action:
		"pickup_full":
			_server_pickup_full(peer_id, inv, slot_index)
		"pickup_half":
			_server_pickup_half(peer_id, inv, slot_index)
		"pickup_matching":
			_server_pickup_matching(peer_id, inv, slot_index)
		"place_full":
			_server_place_full(peer_id, inv, slot_index)
		"place_one":
			_server_place_one(peer_id, inv, slot_index)
		"quick_transfer":
			_server_quick_transfer(peer_id, inv, slot_index)


func distribute_even(peer_id: int, slot_indices: Array) -> void:
	var inv: Inventory = _inventories.get(peer_id)
	if inv == null:
		return
	_server_distribute_even(peer_id, inv, slot_indices)


func pickup_matching_item(peer_id: int, item_id: int) -> void:
	var inv: Inventory = _inventories.get(peer_id)
	if inv == null:
		return
	_server_pickup_matching_item(peer_id, inv, item_id)


## Removes items from a slot and returns what should be dropped into the world.
## whole_stack=true drops the whole slot, otherwise one item.
func drop_from_slot(peer_id: int, slot_index: int, whole_stack: bool) -> Dictionary:
	if not multiplayer.is_server():
		return _empty_slot()
	var inv: Inventory = _inventories.get(peer_id)
	if inv == null:
		return _empty_slot()
	if slot_index < 0 or slot_index >= inv.size:
		return _empty_slot()

	var slot: Dictionary = inv.get_slot(slot_index)
	if _is_empty_slot(slot):
		return _empty_slot()

	var drop_count: int = slot["count"] if whole_stack else 1
	var remaining: int = slot["count"] - drop_count
	if remaining <= 0:
		inv.set_slot(slot_index, ItemProperties.NONE, 0)
	else:
		inv.set_slot(slot_index, slot["item_id"], remaining)

	_sync_slot_to_peer.call(peer_id, slot_index, inv.get_slot(slot_index))
	return {"item_id": slot["item_id"], "count": drop_count}


## Removes items from the held (cursor) slot and returns what should be dropped.
func drop_from_held(peer_id: int, whole_stack: bool) -> Dictionary:
	if not multiplayer.is_server():
		return _empty_slot()
	var held: Dictionary = _held_slots.get(peer_id, _empty_slot())
	if _is_empty_slot(held):
		return _empty_slot()

	var drop_count: int = held["count"] if whole_stack else 1
	var remaining: int = held["count"] - drop_count
	var item_id: int = held["item_id"]
	_set_held_slot(peer_id, item_id, remaining)
	return {"item_id": item_id, "count": drop_count}


func _server_pickup_full(peer_id: int, inv: Inventory, slot_index: int) -> void:
	var held: Dictionary = _held_slots.get(peer_id, _empty_slot())
	if not _is_empty_slot(held):
		return

	var slot: Dictionary = inv.get_slot(slot_index)
	if _is_empty_slot(slot):
		return

	inv.set_slot(slot_index, ItemProperties.NONE, 0)
	_sync_slot_to_peer.call(peer_id, slot_index, inv.get_slot(slot_index))
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

	_sync_slot_to_peer.call(peer_id, slot_index, inv.get_slot(slot_index))
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
		_sync_slot_to_peer.call(peer_id, changed_index, inv.get_slot(changed_index))
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
		_sync_slot_to_peer.call(peer_id, slot_index, inv.get_slot(slot_index))
		_set_held_slot(peer_id, ItemProperties.NONE, 0)
		return

	if slot["item_id"] == held_item_id:
		var space: int = held_props.max_stack - slot["count"]
		if space <= 0:
			return
		var moved: int = mini(space, held_count)
		inv.set_slot(slot_index, held_item_id, slot["count"] + moved)
		_sync_slot_to_peer.call(peer_id, slot_index, inv.get_slot(slot_index))
		_set_held_slot(peer_id, held_item_id, held_count - moved)
		return

	inv.set_slot(slot_index, held_item_id, held_count)
	_sync_slot_to_peer.call(peer_id, slot_index, inv.get_slot(slot_index))
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
		_sync_slot_to_peer.call(peer_id, slot_index, inv.get_slot(slot_index))
		_set_held_slot(peer_id, held_item_id, held_count - 1)
		return

	if slot["item_id"] != held_item_id:
		return
	if slot["count"] >= held_props.max_stack:
		return

	inv.set_slot(slot_index, held_item_id, slot["count"] + 1)
	_sync_slot_to_peer.call(peer_id, slot_index, inv.get_slot(slot_index))
	_set_held_slot(peer_id, held_item_id, held_count - 1)


func _server_quick_transfer(peer_id: int, inv: Inventory, slot_index: int) -> void:
	var held: Dictionary = _held_slots.get(peer_id, _empty_slot())
	if not _is_empty_slot(held):
		return

	var target_start: int = GameConstants.HOTBAR_SIZE if slot_index < GameConstants.HOTBAR_SIZE else 0
	var target_end: int = inv.size if slot_index < GameConstants.HOTBAR_SIZE else GameConstants.HOTBAR_SIZE
	var changed_slots := _transfer_slot_to_range(inv, slot_index, target_start, target_end)
	for changed_index in changed_slots:
		_sync_slot_to_peer.call(peer_id, changed_index, inv.get_slot(changed_index))


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
		_sync_slot_to_peer.call(peer_id, changed_index, inv.get_slot(changed_index))
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
	_sync_held_slot_to_peer.call(peer_id, slot)


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
	return (
		slot.get("item_id", ItemProperties.NONE) == ItemProperties.NONE
		or slot.get("count", 0) <= 0
	)
