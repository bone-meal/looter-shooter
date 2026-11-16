# Purpose: the home port's STORE CHEST (sea step 7b, storehouse): goods of the fantasy bag kept ashore in slots (one kind
# of item per slot, any number of it), as many slots as the storehouse's level gives (data/sea/town.json effects
# "slots"). Below the top level each player has his own chest (saved with him); at the top it is one chest of the host's
# world for the whole crew. Pure: nothing here touches the scene.
# Dependencies: none.
extends RefCounted

const MAX_STACK := 9999

var slots: Array = []  # [[item id, count], ...]
var capacity := 12


func count(item: String) -> int:
	for s: Array in slots:
		if String(s[0]) == item:
			return int(s[1])
	return 0


func can_put(item: String) -> bool:
	return count(item) > 0 or slots.size() < capacity


# Puts `n` of an item in (a new kind needs a free slot). Returns how many went in.
func put(item: String, n: int) -> int:
	if n <= 0 or item == "":
		return 0
	for s: Array in slots:
		if String(s[0]) == item:
			var room := MAX_STACK - int(s[1])
			var went := mini(n, room)
			s[1] = int(s[1]) + went
			return went
	if slots.size() >= capacity:
		return 0
	var first := mini(n, MAX_STACK)
	slots.append([item, first])
	return first


# Takes up to `n` out. Returns how many came out.
func take(item: String, n: int) -> int:
	for i in slots.size():
		var s: Array = slots[i]
		if String(s[0]) == item:
			var got := mini(n, int(s[1]))
			s[1] = int(s[1]) - got
			if int(s[1]) <= 0:
				slots.remove_at(i)
			return got
	return 0


func to_list() -> Array:
	return slots.duplicate(true)


# A saved or sent chest (bad entries dropped, counts clamped). Over capacity stays (nothing is lost when a level drops).
func from_list(list: Variant) -> void:
	slots.clear()
	if not list is Array:
		return
	for s: Variant in list:
		if s is Array and (s as Array).size() == 2 and (s as Array)[0] is String and ((s as Array)[1] is int or (s as Array)[1] is float):
			var n := clampi(int(s[1]), 0, MAX_STACK)
			if n > 0 and String(s[0]).length() <= 48 and slots.size() < 200:
				slots.append([String(s[0]), n])
