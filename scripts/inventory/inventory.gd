class_name Inventory
extends RefCounted
## Generic container of item slots. Knows nothing about players or networking.
## Can be used for player inventories, chests, or any future container type.

## Emitted when a slot's contents change. index = which slot changed.
signal slot_changed(index: int)

## Total number of slots in this container.
var size: int

## Flat array of slots. Each slot is { "item_id": int, "count": int }.
## Empty slot: { "item_id": ItemProperties.NONE, "count": 0 }.
var slots: Array


func _init(p_size: int = GameConstants.INVENTORY_SIZE) -> void:
	size = p_size
	slots = []
	slots.resize(size)
	for i in range(size):
		slots[i] = _empty_slot()


## Attempts to add count items. Fills existing stacks first, then empty slots.
## Returns the remainder that did not fit (0 = everything was added).
func add_item(item_id: int, count: int) -> int:
	var props := ItemProperties.get_properties(item_id)
	if props == null:
		return count

	var remaining: int = count

	# First pass: top up existing stacks of the same item.
	for i in range(size):
		if remaining <= 0:
			break
		if slots[i]["item_id"] == item_id:
			var space: int = props.max_stack - slots[i]["count"]
			if space > 0:
				var to_add: int = mini(remaining, space)
				slots[i]["count"] += to_add
				remaining -= to_add
				slot_changed.emit(i)

	# Second pass: fill empty slots.
	for i in range(size):
		if remaining <= 0:
			break
		if slots[i]["item_id"] == ItemProperties.NONE:
			var to_add: int = mini(remaining, props.max_stack)
			slots[i] = {"item_id": item_id, "count": to_add}
			remaining -= to_add
			slot_changed.emit(i)

	return remaining


## Removes count items of the given type. Returns true if successful.
## Removes from highest-index slots first (preserves hotbar ordering).
func remove_item(item_id: int, count: int) -> bool:
	if not has_item(item_id, count):
		return false

	var remaining: int = count
	# Remove from last slots first to preserve hotbar items longer.
	for i in range(size - 1, -1, -1):
		if remaining <= 0:
			break
		if slots[i]["item_id"] == item_id:
			var to_remove: int = mini(remaining, slots[i]["count"])
			slots[i]["count"] -= to_remove
			remaining -= to_remove
			if slots[i]["count"] <= 0:
				slots[i] = _empty_slot()
			slot_changed.emit(i)

	return true


## Removes exactly one item from a specific slot. Returns the item_id removed, or NONE.
func remove_from_slot(index: int) -> int:
	if index < 0 or index >= size:
		return ItemProperties.NONE
	if slots[index]["item_id"] == ItemProperties.NONE:
		return ItemProperties.NONE

	var item_id: int = slots[index]["item_id"]
	slots[index]["count"] -= 1
	if slots[index]["count"] <= 0:
		slots[index] = _empty_slot()
	slot_changed.emit(index)
	return item_id


## Returns true if the inventory contains at least count of the given item.
func has_item(item_id: int, count: int = 1) -> bool:
	var total: int = 0
	for i in range(size):
		if slots[i]["item_id"] == item_id:
			total += slots[i]["count"]
			if total >= count:
				return true
	return false


## Returns the contents of a slot as a dictionary.
func get_slot(index: int) -> Dictionary:
	if index < 0 or index >= size:
		return _empty_slot()
	return slots[index]


## Directly sets a slot's contents. Used for network sync from the host.
func set_slot(index: int, item_id: int, count: int) -> void:
	if index < 0 or index >= size:
		return
	if item_id == ItemProperties.NONE or count <= 0:
		slots[index] = _empty_slot()
	else:
		slots[index] = {"item_id": item_id, "count": count}
	slot_changed.emit(index)


## Serializes the full inventory into an array of dictionaries (var_to_bytes compatible).
func serialize() -> Array:
	return slots.duplicate(true)


## Creates an Inventory from serialized data.
static func deserialize(data: Array) -> Inventory:
	var inv := Inventory.new(data.size())
	for i in range(data.size()):
		inv.slots[i] = data[i]
	return inv


static func _empty_slot() -> Dictionary:
	return {"item_id": ItemProperties.NONE, "count": 0}
