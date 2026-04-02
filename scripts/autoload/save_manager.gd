extends Node
## Manages world persistence — chunk modifications, player data, and world metadata.
## Autoloaded as "SaveManager". All write operations are server-only.
##
## Directory layout per world:
##   user://saves/<world_name>/
##   ├── world.json                    ← seed, version, timestamps
##   ├── chunks/
##   │   └── chunk_<x>_<y>.dat        ← binary, modifications only
##   └── players/
##       └── player_<id>.json         ← inventory, position, stats

## Current save format version. Bump when the on-disk format changes,
## then add migration logic in _migrate_world_meta().
const SAVE_VERSION: int = 1

## Emitted on the server when an auto-save tick fires.
## Main connects to this to orchestrate saving all systems.
signal auto_save_requested

var _world_dir: String = ""
var _world_name: String = ""
var _auto_save_timer: float = 0.0


func _process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	if not multiplayer.is_server():
		return

	_auto_save_timer += delta
	if _auto_save_timer >= GameConstants.AUTO_SAVE_INTERVAL:
		_auto_save_timer = 0.0
		auto_save_requested.emit()


# --- World setup ---


## Activates a world save directory. Creates folders if they don't exist.
func set_world(world_name: String) -> void:
	_world_name = world_name
	_world_dir = GameConstants.SAVE_DIR + world_name + "/"
	DirAccess.make_dir_recursive_absolute(_world_dir + "chunks")
	DirAccess.make_dir_recursive_absolute(_world_dir + "players")


## Returns true if a save for the given world name exists on disk.
func has_world_save(world_name: String) -> bool:
	return FileAccess.file_exists(GameConstants.SAVE_DIR + world_name + "/world.json")


## Returns the active world name (empty string if none set).
func get_world_name() -> String:
	return _world_name


# --- World metadata ---


## Saves world-level metadata (seed, version, timestamps).
func save_world_meta(seed_value: int) -> void:
	var meta := {
		"version": SAVE_VERSION,
		"seed": seed_value,
		"saved_at": Time.get_datetime_string_from_system(),
	}
	# Preserve created_at from existing save.
	var existing := load_world_meta()
	if existing.has("created_at"):
		meta["created_at"] = existing["created_at"]
	else:
		meta["created_at"] = meta["saved_at"]
	_write_json(_world_dir + "world.json", meta)


## Loads world metadata. Returns empty Dictionary if no save exists.
func load_world_meta() -> Dictionary:
	return _read_json(_world_dir + "world.json")


# --- Chunk persistence ---


## Saves only the modifications dict for a chunk (base tiles are regenerated).
## Deletes the save file if the chunk has no modifications (keeps disk clean).
func save_chunk(coord: Vector2i, chunk: ChunkData) -> void:
	var path := _chunk_path(coord)
	if chunk.modifications.is_empty():
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
		return
	_write_bytes(path, var_to_bytes(chunk.modifications))


## Loads chunk modifications from disk. Returns empty Dictionary if none saved.
func load_chunk_modifications(coord: Vector2i) -> Dictionary:
	var path := _chunk_path(coord)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[SaveManager] Failed to read %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return {}
	var bytes := file.get_buffer(file.get_length())
	file.close()
	return bytes_to_var(bytes)


## Saves all loaded chunks that have modifications. Called during auto-save.
func save_all_chunks(loaded_chunks: Dictionary) -> void:
	var saved_count: int = 0
	for coord: Vector2i in loaded_chunks:
		var chunk: ChunkData = loaded_chunks[coord]
		if chunk != null and not chunk.modifications.is_empty():
			save_chunk(coord, chunk)
			saved_count += 1
	if saved_count > 0:
		print("[SaveManager] Saved %d modified chunk(s)" % saved_count)


# --- Player persistence ---


## Saves player state (inventory, position) to disk.
func save_player(player_id: String, data: Dictionary) -> void:
	_write_json(_player_path(player_id), data)


## Loads player state from disk. Returns empty Dictionary if no save exists.
func load_player(player_id: String) -> Dictionary:
	return _read_json(_player_path(player_id))


## Returns true if a save file exists for the given player.
func has_player_save(player_id: String) -> bool:
	return FileAccess.file_exists(_player_path(player_id))


# --- Internal helpers ---


func _chunk_path(coord: Vector2i) -> String:
	return _world_dir + "chunks/chunk_%d_%d.dat" % [coord.x, coord.y]


func _player_path(player_id: String) -> String:
	return _world_dir + "players/player_" + player_id + ".json"


## Writes a Dictionary as pretty-printed JSON with atomic rename.
func _write_json(path: String, data: Dictionary) -> void:
	var json_str := JSON.stringify(data, "\t")
	_write_string(path, json_str)


## Reads a JSON file into a Dictionary. Returns {} on any failure.
func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[SaveManager] Failed to read %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return {}
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("[SaveManager] Failed to parse %s: %s" % [path, json.get_error_message()])
		return {}
	if json.data is Dictionary:
		return json.data
	push_error("[SaveManager] Expected Dictionary in %s" % path)
	return {}


## Atomic write: data -> .tmp file -> rename to final path.
## Prevents corruption if the game crashes mid-write.
func _write_string(path: String, content: String) -> void:
	var tmp_path := path + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_error("[SaveManager] Failed to write %s: %s" % [tmp_path, error_string(FileAccess.get_open_error())])
		return
	file.store_string(content)
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	DirAccess.rename_absolute(tmp_path, path)


## Atomic write for binary data.
func _write_bytes(path: String, data: PackedByteArray) -> void:
	var tmp_path := path + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_error("[SaveManager] Failed to write %s: %s" % [tmp_path, error_string(FileAccess.get_open_error())])
		return
	file.store_buffer(data)
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	DirAccess.rename_absolute(tmp_path, path)
