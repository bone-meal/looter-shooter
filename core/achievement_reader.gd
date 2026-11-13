# Purpose: reads the number a "stat" achievement measures (data/achievements.json) from the combat record and a few
# extra readings the session supplies. Pure rules: no nodes, no rendering.
# Keys: total:<name>, group:<group>:<id>, sum:<group>, count:<group> (ids above zero), prefix:<group>:<start> (sum of ids
# starting so), countprefix:<group>:<start>, every:<group>:<id,id,...> (how many of those ids are above zero),
# ctx:<name> (from `extra`), below:<key>:<limit> (1 when the reading is above zero and at most the limit, else 0).
# Dependencies: core/stat_book.gd (passed in).
extends RefCounted


static func read(key: String, book: RefCounted, extra: Dictionary) -> int:
	var parts := key.split(":")
	match parts[0]:
		"total":
			return floori(book.total(key.substr(6)))
		"group":
			return floori(book.count_in(parts[1], key.substr(7 + parts[1].length())))
		"sum":
			return floori(book.group_sum(parts[1]))
		"count", "prefix", "countprefix", "every":
			return _over_group(parts, book)
		"ctx":
			return int(extra.get(key.substr(4), 0))
		"below":
			var limit := float(parts[parts.size() - 1])
			var inner := key.substr(6, key.length() - 7 - parts[parts.size() - 1].length())
			var value := _raw(inner, book, extra)
			return 1 if value > 0.0 and value <= limit else 0
	return 0


# Readings of one group: count / prefix / countprefix / every.
static func _over_group(parts: PackedStringArray, book: RefCounted) -> int:
	var group: Dictionary = book.group(parts[1])
	var rest := ":".join(parts.slice(2))
	var wanted := rest.split(",") if parts[0] == "every" else PackedStringArray()
	var n := 0.0
	for id: String in group:
		var v := float(group[id])
		if v <= 0.0:
			continue
		match parts[0]:
			"count":
				n += 1.0
			"prefix":
				if id.begins_with(rest):
					n += v
			"countprefix":
				if id.begins_with(rest):
					n += 1.0
			"every":
				if wanted.has(id):
					n += 1.0
	return floori(n)


# The unrounded reading (for below:, where times have decimals).
static func _raw(key: String, book: RefCounted, extra: Dictionary) -> float:
	if key.begins_with("ctx:"):
		return float(extra.get(key.substr(4), 0.0))
	return float(read(key, book, extra))
