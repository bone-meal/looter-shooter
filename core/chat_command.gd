# Purpose: pure parsing of chat commands ("/give gun pony ak47") and their help text. No nodes.
# Dependencies: none. The command table is data/commands.json "commands" (name, usage, help, scope).
extends RefCounted

const MAX_CHAT := 160  # longest chat line that is sent or shown


# {"name": "give", "args": ["gun", "pony", "ak47"]} for a line starting with "/", {} for ordinary chat.
static func parse(text: String) -> Dictionary:
	var line := text.strip_edges()
	if not line.begins_with("/") or line.length() < 2:
		return {}
	var words := line.substr(1).split(" ", false)
	if words.is_empty():
		return {}
	var args: Array[String] = []
	for i in range(1, words.size()):
		args.append(words[i])
	return {"name": words[0].to_lower(), "args": args}


static func find(table: Array, command: String) -> Dictionary:
	for entry: Dictionary in table:
		if String(entry["name"]) == command:
			return entry
	return {}


# Lines for /help (every usage) or /help <command> (usage and what it does).
static func help(table: Array, command: String = "") -> PackedStringArray:
	var lines := PackedStringArray()
	if command != "":
		var entry := find(table, command.trim_prefix("/"))
		if entry.is_empty():
			lines.append("No such command: %s" % command)
		else:
			lines.append(String(entry["usage"]))
			lines.append(String(entry["help"]))
		return lines
	for entry: Dictionary in table:
		lines.append(String(entry["usage"]))
	return lines


# What other people may see of a chat line: trimmed, one line, limited length.
static func clean(text: String) -> String:
	return text.replace("\n", " ").replace("\r", " ").strip_edges().substr(0, MAX_CHAT)
