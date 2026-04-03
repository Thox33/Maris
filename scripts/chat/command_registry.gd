class_name CommandRegistry
extends RefCounted
## Registry for chat commands.
## Each command maps a name to a Callable with signature:
##   func(sender_id: int, args: Array[String]) -> Array[String]
## The return value is the list of lines sent back to the caller as system messages.

# name (String) -> { "description": String, "callable": Callable }
var _commands: Dictionary = {}


func register(name: String, description: String, callable: Callable) -> void:
	_commands[name.to_lower()] = {"description": description, "callable": callable}


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
	var names: Array[String] = []
	for name: String in _commands:
		names.append(name)
	names.sort()

	var lines: Array[String] = ["Available commands:"]
	for name: String in names:
		lines.append("  /%s - %s" % [name, _commands[name]["description"]])
	return lines


func has_command(name: String) -> bool:
	return _commands.has(name.to_lower())
