# Purpose: pure rules for what a player's trophy cabinet shows (polish1 item 16; game/trophy_room.gd draws it). A cabinet
# has a PODIUM of 5 spots, an EYE-LEVEL row of 24 and 10 other SHELVES of 12. The player chooses: each podium spot can be
# switched to any trophy he has earned; he PINS favourites to the eye-level row (up to 24; empty places there show the
# hardest achievements, data/trophies.json middle_row); every other achievement is split into PAGES of 12 and each shelf
# shows one page, its button turning it to the next page. The choice is saved with the progress ("shelves") and goes out
# with the player card, so others see his cabinet as he set it.
# Saved form: {"pages": [10 ints], "pins": [achievement ids], "podium": [5 achievement ids or ""]}.
# Dependencies: none (data/trophies.json and the earned ids are passed in).
extends RefCounted

const PODIUM := 5
const EYE := 24
const SHELVES := 10
const PER_SHELF := 12
const PAGE_MAX := 999


# A saved (or received) choice made safe: known ids only, no repeats, right sizes. `known` = achievement id -> anything.
static func clean(d: Variant, known: Dictionary) -> Dictionary:
	var src: Dictionary = d if d is Dictionary else {}
	var pages: Array = []
	var raw_pages: Array = src["pages"] if src.get("pages") is Array else []
	for s in SHELVES:
		var n: Variant = raw_pages[s] if s < raw_pages.size() else s
		pages.append(clampi(int(n) if (n is int or n is float) else s, 0, PAGE_MAX))
	var pins: Array = []
	if src.get("pins") is Array:
		for id: Variant in src["pins"]:
			if id is String and known.has(id) and not pins.has(id) and pins.size() < EYE:
				pins.append(id)
	var podium: Array = []
	var raw_podium: Array = src["podium"] if src.get("podium") is Array else []
	for i in PODIUM:
		var id: Variant = raw_podium[i] if i < raw_podium.size() else ""
		podium.append(String(id) if id is String and known.has(id) and not podium.has(id) else "")
	return {"pages": pages, "pins": pins, "podium": podium}


# Every achievement in display order: the 3 hardest, the next hardest, then the rest as data/trophies.json lists them.
static func order(data: Dictionary) -> Array:
	var out: Array = []
	for list: Variant in [data.get("pedestal", []), data.get("middle_row", []), (data.get("trophies", {}) as Dictionary).keys()]:
		for id: Variant in list:
			if not out.has(String(id)):
				out.append(String(id))
	return out


# The podium's defaults by spot, middle spot first in importance: [next hardest, 2nd, HARDEST, 3rd, next hardest].
static func _podium_defaults(data: Dictionary) -> Array:
	var top: Array = order(data)
	var by_rank := [3, 1, 0, 2, 4]
	var out: Array = []
	for r: int in by_rank:
		out.append(String(top[r]) if r < top.size() else "")
	return out


# What a cabinet shows: {"podium": [5 ids], "eye": [up to 24 ids], "rows": [10 arrays of up to 12 ids], "pages": n}.
# `have` = earned id -> date. A chosen podium trophy or pin that is not earned (any more) falls back to the default.
static func layout(data: Dictionary, shelves: Dictionary, have: Dictionary) -> Dictionary:
	var all := order(data)
	var used := {}
	var podium: Array = []
	var chosen: Array = shelves.get("podium", [])
	var defaults := _podium_defaults(data)
	for i in PODIUM:
		var id := String(chosen[i]) if i < chosen.size() else ""
		podium.append(id if id != "" and have.has(id) else "")
		if podium[i] != "":
			used[podium[i]] = true
	for i in PODIUM:  # empty spots: their default, else the next achievement not shown yet
		if podium[i] != "":
			continue
		var id := String(defaults[i])
		if id == "" or used.has(id):
			id = ""
			for other: String in all:
				if not used.has(other):
					id = other
					break
		podium[i] = id
		if id != "":
			used[id] = true
	var eye: Array = []
	for id: Variant in shelves.get("pins", []):
		if eye.size() < EYE and have.has(id) and not used.has(id):
			eye.append(String(id))
			used[id] = true
	for id: Variant in data.get("middle_row", []) + all:  # the rest of the row: the hardest still not shown
		if eye.size() < EYE and not used.has(id):
			eye.append(String(id))
			used[id] = true
	var rest: Array = []
	for id: String in all:
		if not used.has(id):
			rest.append(id)
	var pages := maxi(ceili(float(rest.size()) / float(PER_SHELF)), 1)
	var rows: Array = []
	var page_of: Array = shelves.get("pages", [])
	for s in SHELVES:
		var page := (int(page_of[s]) if s < page_of.size() else s) % pages
		rows.append(rest.slice(page * PER_SHELF, mini((page + 1) * PER_SHELF, rest.size())))
	return {"podium": podium, "eye": eye, "rows": rows, "pages": pages}


# The shelf's button: the next page. When there are more pages than shelves it skips the pages other shelves show; when
# there are not, the shelf that showed that page takes this shelf's old one (every page stays on show, none twice).
static func cycle_shelf(shelves: Dictionary, s: int, data: Dictionary, have: Dictionary) -> Dictionary:
	var out := shelves.duplicate(true)
	var pages: int = layout(data, shelves, have)["pages"]
	var page_of: Array = out["pages"]
	var old := int(page_of[s]) % pages
	var page := (old + 1) % pages
	if pages > SHELVES:
		for _i in pages:
			var taken := false
			for other in SHELVES:
				if other != s and int(page_of[other]) % pages == page:
					taken = true
			if not taken:
				break
			page = (page + 1) % pages
	else:
		for other in SHELVES:
			if other != s and int(page_of[other]) % pages == page:
				page_of[other] = old
	page_of[s] = page
	return out


# Pin an earned trophy to the eye-level row, or take a pin off. A full row drops its oldest pin.
static func toggle_pin(shelves: Dictionary, id: String, have: Dictionary) -> Dictionary:
	var out := shelves.duplicate(true)
	var pins: Array = out["pins"]
	if pins.has(id):
		pins.erase(id)
	elif have.has(id):
		if pins.size() >= EYE:
			pins.remove_at(0)
		pins.append(id)
	return out


# Switch a podium spot to the next earned trophy (in display order) that is not on the podium already.
static func cycle_podium(shelves: Dictionary, spot: int, data: Dictionary, have: Dictionary) -> Dictionary:
	var out := shelves.duplicate(true)
	var now: Array = layout(data, shelves, have)["podium"]
	var all := order(data)
	var at := all.find(String(now[spot]))
	for k in range(1, all.size() + 1):
		var id := String(all[(at + k) % all.size()])
		if have.has(id) and not now.has(id):
			(out["podium"] as Array)[spot] = id
			return out
	return out


static func is_pinned(shelves: Dictionary, id: String) -> bool:
	return (shelves.get("pins", []) as Array).has(id)
