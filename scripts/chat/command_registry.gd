class_name CommandRegistry
extends RefCounted
## Registry for chat commands.
## Each command maps a name to a Callable with signature:
##   func(sender_id: int, args: Array[String]) -> Array[String]
## The return value is the list of lines sent back to the caller as system messages.

# name (String) -> { "description": String, "callable": Callable }
var _commands: Dictionary = {}
var _help_entries: Array[Dictionary] = []


func register(name: String, description: String, callable: Callable) -> void:
	register_aliases([name], description, callable)


func register_aliases(names: Array[String], description: String, callable: Callable) -> void:
	var normalized_names: Array[String] = []
	for name: String in names:
		var key := name.to_lower()
		_commands[key] = {"description": description, "callable": callable}
		normalized_names.append(key)
	_help_entries.append({"names": normalized_names, "description": description})


## Execute a command by name. Returns output lines for the caller.
func execute(sender_id: int, name: String, args: Array[String]) -> Array[String]:
	var key: String = name.to_lower()
	if not _commands.has(key):
		return ["Unknown command: /%s. Use /help for a list of commands." % name]
	var raw: Variant = _commands[key]["callable"].call(sender_id, args)
	var lines: Array[String] = []
	if raw is Array:
		for line in raw:
			lines.append(str(line))
	else:
		lines.append(str(raw))
	return lines


func get_help_lines() -> Array[String]:
	var lines: Array[String] = ["Available commands:"]
	for entry: Dictionary in _get_sorted_help_entries():
		var names := PackedStringArray(entry["names"])
		var aliases: Array[String] = []
		for name: String in names:
			aliases.append("/%s" % name)
		lines.append("  %s - %s" % [", ".join(aliases), entry["description"]])
	return lines


func has_command(name: String) -> bool:
	return _commands.has(name.to_lower())


func _get_sorted_help_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for entry: Dictionary in _help_entries:
		entries.append(entry)
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["names"][0]) < String(b["names"][0])
	)
	return entries
