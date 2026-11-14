# Purpose: the card vending machine in use: F in front of it frees the mouse and opens the menu
# (game/tcg/vendor_screen.gd); a click buys through core/tcg/pack_shop.gd (chips out of the wallet, packs / box / starter
# cards into the collection; play mats through core/tcg/mat_book.gd) and the session saves; Esc or Close leaves.
# Dependencies: core/tcg/pack_shop.gd, core/tcg/mat_book.gd, data/tcg/mats.json, game/tcg/vendor_screen.gd, game/tcg/card_vendor.gd (the model, in the casino
# dictionary as "card_vendor"), core/wallet.gd, core/tcg/collection.gd, core/text_book.gd, data/tcg/packs.json,
# starters.json, leaders.json, writing/cards.txt.
extends Node

const PackShop = preload("res://core/tcg/pack_shop.gd")
const VendorScreen = preload("res://game/tcg/vendor_screen.gd")
const DataStore = preload("res://core/data_store.gd")
const MatBook = preload("res://core/tcg/mat_book.gd")

signal bought  # chips and the collection changed: the session saves

var _wallet: RefCounted
var _owned: RefCounted
var _player: CharacterBody3D
var _machine: Node3D
var _screen: Control
var _cfg: Dictionary
var _mats: Dictionary  # data/tcg/mats.json
var _starters: Dictionary


func setup(wallet: RefCounted, owned: RefCounted, casino: Dictionary, layer: CanvasLayer, player: CharacterBody3D) -> void:
	_wallet = wallet
	_owned = owned
	_player = player
	_machine = casino.get("card_vendor")
	_cfg = DataStore.load_json("res://data/tcg/packs.json")
	_mats = DataStore.load_json("res://data/tcg/mats.json")
	_starters = DataStore.load_json("res://data/tcg/starters.json")["starters"]
	var leaders: Dictionary = DataStore.load_json("res://data/tcg/leaders.json")["leaders"]
	var named := {}  # leader names come from the writers' file
	for id: String in leaders:
		named[id] = {"name": id.replace("_", " ").capitalize()}
	var words := FileAccess.get_file_as_string("res://data/tcg/writing/cards.txt")
	var TextBook: GDScript = load("res://core/text_book.gd")
	var parsed: Dictionary = TextBook.call("parse", words)
	for id: String in (parsed.get("leader", {}) as Dictionary):
		if named.has(id):
			named[id]["name"] = String(parsed["leader"][id].get("name", id))
	_screen = VendorScreen.new()
	layer.add_child(_screen)
	_screen.call("setup", _cfg, _starters, named, _mats)
	_screen.connect("buy", _on_buy)
	_screen.connect("closed", close)


func near(pos: Vector3) -> bool:
	return _machine != null and bool(_machine.call("near", pos))


func is_open() -> bool:
	return _screen != null and _screen.visible


func open() -> void:
	_player.controls_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_screen.call("open", int(_wallet.get("balance")), int(_owned.call("pack_count")))


func close() -> void:
	_screen.visible = false
	_player.controls_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_buy(item: String) -> void:
	var before := int(_owned.call("pack_count"))
	var why := MatBook.buy(_owned, _mats, _wallet, item.trim_prefix("mat:")) if item.begins_with("mat:") else PackShop.buy(item, _wallet, _owned, _cfg, _starters)
	if why != "":
		_screen.call("show_refused", why.to_upper() + "!")
	else:
		var got := int(_owned.call("pack_count")) - before
		_screen.call("show_bought", item, "MAT ADDED!" if item.begins_with("mat:") else ("+%d PACK%s!" % [got, "" if got == 1 else "S"] if got > 0 else "DECK ADDED!"))
		bought.emit()
	_screen.call("refresh", int(_wallet.get("balance")), int(_owned.call("pack_count")))
