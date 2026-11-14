# Purpose: developer check of trading and shared drops WITHOUT a network: plays two players (and a third) against
# the host's rules (core/trade_desk.gd, core/shared_drops.gd) with real rolled guns and real armour, and applies
# what the desk says to two real inventories. Log tools/trade_check.log (ends TRADE_CHECK_DONE problems=n).
# Run with a window it also pictures the trade window: tools/shots/trade_window.jpg.
# The RPC layer (game/net_trade.gd, game/net_drops.gd) is NOT exercised: that needs two machines.
# Dependencies: core/trade_desk.gd, core/shared_drops.gd, core/gun_gen.gd, core/gun_db.gd, core/item_db.gd,
# core/inventory_state.gd, core/data_store.gd, game/trade_screen.gd, core/tcg/card_db.gd, core/tcg/collection.gd (card game cards).
extends Node

const TradeDesk = preload("res://core/trade_desk.gd")
const SharedDrops = preload("res://core/shared_drops.gd")
const GunGen = preload("res://core/gun_gen.gd")
const GunDb = preload("res://core/gun_db.gd")
const ItemDb = preload("res://core/item_db.gd")
const InventoryState = preload("res://core/inventory_state.gd")
const DataStore = preload("res://core/data_store.gd")
const TradeScreen = preload("res://game/trade_screen.gd")
const CardDb = preload("res://core/tcg/card_db.gd")
const CardCollection = preload("res://core/tcg/collection.gd")

const NAMES := {1: "Host", 2: "Bonk", 3: "Third"}

var _lines := PackedStringArray()
var _problems := 0
var _db: GunDb
var _items: ItemDb
var _cards: RefCounted  # core/tcg/card_db.gd


func _ready() -> void:
	_db = GunDb.new(DataStore.load_json("res://data/gun_loot.json"), DataStore.load_json("res://data/gun_parts.json"), DataStore.load_json("res://data/manufacturers.json"),
		DataStore.load_json("res://data/weapons.json"), DataStore.load_json("res://data/skills.json"), DataStore.load_json("res://data/gun_uniques.json"))
	_items = ItemDb.new(DataStore.load_json("res://data/items.json"))
	_cards = CardDb.from_files()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var bags := {1: InventoryState.new(_items), 2: InventoryState.new(_items)}
	for who: int in bags:
		(bags[who] as InventoryState).set_gun_db(_db)
		(bags[who] as InventoryState).add("pistol_basic", 1)  # both holsters taken, so the guns below sit in the backpack:
		(bags[who] as InventoryState).add("ak47", 1)  # only what is in the backpack can be traded
	var gun_a := GunGen.generate(_db, rng, 0.5)
	var gun_b := GunGen.generate(_db, rng, 0.9)
	(bags[1] as InventoryState).add_gun(gun_a)
	(bags[1] as InventoryState).add("iron_helm", 1)
	(bags[2] as InventoryState).add_gun(gun_b)
	var desk := TradeDesk.new()
	desk.legal = _legal
	# asking and answering
	var out := desk.ask(1, 2, NAMES, 0.0)
	_note("the asked player is told who asks", _has(out, 2, "asked") and _has(out, 1, "waiting"))
	_note("asking yourself or nobody ends at once", _has(desk.ask(1, 1, NAMES, 0.0), 1, "ended") and _has(desk.ask(1, 9, NAMES, 0.0), 1, "ended"))
	out = desk.answer(2, true, NAMES)
	_note("both get the empty table after a yes", _has(out, 1, "table") and _has(out, 2, "table"))
	_note("a third player cannot ask someone who is trading", _has(desk.ask(3, 2, NAMES, 1.0), 3, "ended"))
	# offering
	var slot_a := _slot_of(bags[1], true)
	var helm := _slot_of(bags[1], false)
	var slot_b := _slot_of(bags[2], true)
	out = desk.offer(1, {"ref": slot_a, "gun": gun_a}, NAMES)
	var seen: Dictionary = _args(out, 2, "table")[0]
	_note("the other side sees the offered gun without the owner's slot", (seen["theirs"] as Array).size() == 1 and not (seen["theirs"][0] as Dictionary).has("ref"))
	var forged := gun_a.duplicate(true)
	forged["tier"] = "pony"
	_note("an edited gun is refused", _has(desk.offer(2, {"ref": 30, "gun": forged}, NAMES), 2, "refused"))
	_note("a thing that is neither gun nor armour is refused", _has(desk.offer(2, {"ref": 31, "id": "worm"}, NAMES), 2, "refused"))
	out = desk.offer(2, {"ref": 1000, "card": "reef_crab", "finish": "rainbow", "leader": false, "extra": 9}, NAMES)
	var card_seen: Array = _args(out, 1, "table")[0]["theirs"]
	_note("a card can be offered; the other side sees only its card fields", card_seen.size() == 1 and card_seen[0] == {"card": "reef_crab", "finish": "rainbow", "leader": false})
	_note("a made-up card, a token or a made-up finish is refused", _has(desk.offer(2, {"ref": 1001, "card": "golden_god", "finish": "", "leader": false}, NAMES), 2, "refused")
		and _has(desk.offer(2, {"ref": 1002, "card": "slimelet", "finish": "", "leader": false}, NAMES), 2, "refused")
		and _has(desk.offer(2, {"ref": 1003, "card": "reef_crab", "finish": "gold", "leader": false}, NAMES), 2, "refused"))
	desk.withdraw(2, 1000, NAMES)
	_note("extra fields do not ride along", not (_args(desk.offer(1, {"ref": helm, "id": "iron_helm", "coins": 999999}, NAMES), 2, "table")[0]["theirs"][1] as Dictionary).has("coins"))
	desk.offer(2, {"ref": slot_b, "gun": gun_b}, NAMES)
	_note("the same slot cannot be offered twice", desk.offer(2, {"ref": slot_b, "gun": gun_b}, NAMES).is_empty())
	# ready, change, ready again, confirm
	_note("confirming before both are ready does nothing", desk.confirm(1, NAMES).is_empty())
	desk.set_ready(1, true, NAMES)
	out = desk.set_ready(2, true, NAMES)
	_note("both ready opens the confirm step", bool(_args(out, 1, "table")[0]["confirm"]))
	out = desk.withdraw(1, helm, NAMES)
	var after: Dictionary = _args(out, 2, "table")[0]
	_note("any change clears both ready ticks", not bool(after["ready_mine"]) and not bool(after["ready_theirs"]) and not bool(after["confirm"]))
	desk.offer(1, {"ref": helm, "id": "iron_helm"}, NAMES)
	desk.set_ready(1, true, NAMES)
	desk.set_ready(2, true, NAMES)
	out = desk.confirm(1, NAMES)
	_note("one confirm is not enough", _has(out, 2, "table") and not _has(out, 2, "done"))
	out = desk.confirm(2, NAMES)
	_note("both confirms finish the trade", _has(out, 1, "done") and _has(out, 2, "done") and not desk.busy(1))
	# what each machine does with "done" (as game_session._finish_trade)
	for who: int in bags:
		var done := _args(out, who, "done")
		var bag: InventoryState = bags[who]
		for ref: int in done[0]:
			if bag.take_gun(ref).is_empty() and bag.item_id(ref) != "":
				bag.remove(bag.item_id(ref), 1)
		for thing: Dictionary in done[1]:
			if thing.has("gun"):
				bag.add_gun(thing["gun"])
			else:
				bag.add(String(thing["id"]), 1)
	_note("the host's gun and helmet are now the other player's", _holds(bags[2], gun_a) and (bags[2] as InventoryState).count_of("iron_helm") == 1 and not _holds(bags[2], gun_b))
	_note("the other player's gun is now the host's, and nothing was doubled", _holds(bags[1], gun_b) and not _holds(bags[1], gun_a) and (bags[1] as InventoryState).count_of("iron_helm") == 0)
	# cancelling, leaving, walking apart, an ask that runs out
	desk.ask(1, 2, NAMES, 10.0)
	desk.answer(2, true, NAMES)
	out = desk.cancel(2, NAMES)
	_note("a cancel ends it for both", _has(out, 1, "ended") and _has(out, 2, "ended") and not desk.busy(2))
	desk.ask(1, 2, NAMES, 20.0)
	desk.answer(2, true, NAMES)
	out = desk.tick(NAMES, {1: Vector3.ZERO, 2: Vector3(30, 0, 0)}, 21.0)
	_note("walking apart ends it", _has(out, 1, "ended") and not desk.busy(1))
	desk.ask(1, 2, NAMES, 30.0)
	desk.answer(2, true, NAMES)
	out = desk.tick({1: "Host"}, {}, 31.0)
	_note("a player who left ends it for the one who stayed", _has(out, 1, "ended") and not _has(out, 2, "ended") and not desk.busy(1))
	desk.ask(1, 2, NAMES, 40.0)
	_note("an unanswered ask runs out", desk.tick(NAMES, {}, 45.0).is_empty() and _has(desk.tick(NAMES, {}, 61.0), 1, "ended"))
	desk.ask(1, 2, NAMES, 70.0)
	desk.answer(2, true, NAMES)
	for n in TradeDesk.MAX_THINGS:
		desk.offer(1, {"ref": n, "id": "iron_helm"}, NAMES)
	_note("no more than %d things a side" % TradeDesk.MAX_THINGS, _has(desk.offer(1, {"ref": 20, "id": "iron_helm"}, NAMES), 1, "refused"))
	# shared drops
	var book := SharedDrops.new()
	book.limit = 3
	var first: Dictionary = book.add(gun_a, Vector3(1, 0, 1), 0.0)
	_note("a dropped gun goes to the first who asks, once", book.take(int(first["id"])) == gun_a and book.take(int(first["id"])).is_empty())
	var ids: Array = []
	var pushed: Array = []
	for n in 4:
		var made := book.add(gun_b, Vector3(float(n), 0, 0), 100.0 + float(n))
		ids.append(int(made["id"]))
		pushed.append_array(made["gone"])
	_note("the oldest goes when too many lie around", pushed == [ids[0]] and book.all().size() == 3)
	_note("drops run out", book.expired(100.0 + book.seconds + 2.5) == [ids[1], ids[2]] and book.all().size() == 1)
	if DisplayServer.get_name() != "headless":
		await _picture(bags[2], gun_b)
	_lines.append("TRADE_CHECK_DONE problems=%d" % _problems)
	var file := FileAccess.open("res://tools/trade_check.log", FileAccess.WRITE)
	file.store_string("\n".join(_lines) + "\n")
	file.close()
	get_tree().quit()


func _legal(thing: Dictionary) -> bool:
	if thing.has("gun"):
		return GunGen.validate(_db, thing["gun"]) == ""
	if thing.has("card"):  # as game/game_session.gd _legal_card
		var id := String(thing["card"])
		if not CardCollection.FINISHES.has(String(thing["finish"])):
			return false
		if bool(thing["leader"]):
			return (_cards.get("leaders") as Dictionary).has(id)
		return not _cards.card(id).is_empty() and String(_cards.card(id)["rarity"]) != "token"
	return _items.has_item(String(thing.get("id", ""))) and _items.equip_slot(String(thing["id"])) != ""


func _slot_of(bag: InventoryState, gun: bool) -> int:
	for slot in InventoryState.SIZE:
		if gun != bag.gun_at(slot).is_empty() and bag.item_id(slot) != "":
			return slot
	return -1


func _holds(bag: InventoryState, gun: Dictionary) -> bool:
	for slot in InventoryState.SIZE:
		if bag.gun_at(slot) == gun:
			return true
	return false


func _has(out: Array, peer: int, what: String) -> bool:
	return not _args(out, peer, what).is_empty()


func _args(out: Array, peer: int, what: String) -> Array:
	for entry: Array in out:
		if int(entry[0]) == peer and String(entry[1]) == what:
			return entry[2]
	return []


func _picture(bag: InventoryState, theirs: Dictionary) -> void:
	var screen := TradeScreen.new()
	add_child(screen)
	screen.setup(bag, _items, _db)
	var owned := CardCollection.new()
	for id: String in ["reef_crab", "harbor_gull", "riptide", "skeleton_archer", "slime_king"]:
		owned.add(id, "rainbow" if id == "harbor_gull" else "", 2, id == "slime_king")
	screen.set_cards(owned, _cards)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for n in 4:
		bag.add_gun(GunGen.generate(_db, rng, 0.2 * float(n)))
	bag.add("tin_hat", 1)
	var mine: Array = [{"ref": _slot_of(bag, true), "gun": bag.gun_at(_slot_of(bag, true))}]
	screen.show_table({"with": "Bonk", "mine": mine, "theirs": [{"gun": theirs}, {"id": "iron_helm"}, {"card": "great_slime", "finish": "", "leader": false}], "ready_mine": true, "ready_theirs": true, "confirm": true, "confirmed_mine": false})
	for _i in 4:
		await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/shots"))
	get_viewport().get_texture().get_image().save_jpg("res://tools/shots/trade_window.jpg", 0.9)
	# the hover card of the gun that is offered to us (as if the mouse were on its line)
	get_viewport().warp_mouse(Vector2(640, 180))
	screen.set("_hover", {"gun": theirs})
	(screen.get("_card") as Control).queue_redraw()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_jpg("res://tools/shots/trade_hover.jpg", 0.9)


func _note(text: String, good: bool) -> void:
	if not good:
		_problems += 1
	_lines.append(("ok   " if good else "FAIL ") + text)
