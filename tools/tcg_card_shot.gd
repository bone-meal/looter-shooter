# Purpose: developer picture of finished cards of "You got me Lobster?": a row of card faces (one per faction plus a
# spell, a legendary, a rainbow foil and a pony foil, the card back) drawn by game/tcg/card_face.gd with the real art,
# frames and fonts, saved to tools/userdata/tcg_cards.png. Two pictures half a second apart show the foils moving.
# Dependencies: game/tcg/card_face.gd, core/tcg/card_db.gd.
extends Control

const CardFace = preload("res://game/tcg/card_face.gd")
const CardDb = preload("res://core/tcg/card_db.gd")
const IDS := ["reef_crab", "raider_brute", "skeleton_swordsman", "apprentice_mage", "violet", "shell_bash", "mira_kestrel", "harbor_gull", "magma_imp", "back"]
const FINISH := {"harbor_gull": "rainbow", "magma_imp": "pony"}


func _ready() -> void:
	get_window().size = Vector2i(1800, 760)
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.13)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var db: RefCounted = CardDb.from_files()
	for i in IDS.size():
		var face: Control = CardFace.new()
		face.size = Vector2(250, 350)
		face.position = Vector2(20 + (i % 5) * 350, 20 + floorf(i / 5.0) * 370)
		add_child(face)
		if IDS[i] == "back":
			face.call("show_back")
		else:
			face.call("show_card", db, IDS[i])
		face.call("set_finish", FINISH.get(IDS[i], ""))
	for f in 30:
		await get_tree().process_frame
	_save("tcg_cards")
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	_save("tcg_cards_later")
	get_tree().quit()


func _save(file: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/userdata/"))
	get_viewport().get_texture().get_image().save_png("res://tools/userdata/%s.png" % file)
