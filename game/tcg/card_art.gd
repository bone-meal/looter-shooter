# Purpose: one place that hands out a card's art (locked: art in atlases sized for the HD 620). The pictures live on
# 14 VRAM-compressed atlas pages with mipmaps (assets/tcg/atlas/page_<n>.jpg, map data/tcg/atlas.json, made by
# tools/pack_card_atlas.py); a card's art is an AtlasTexture region of its page (all regions of a page share one
# texture: faces batch, and a page is loaded once). A card missing from the atlas falls back to its own picture
# (assets/tcg/art/<id>.jpg); null when there is neither.
# Dependencies: data/tcg/atlas.json, assets/tcg/atlas/, assets/tcg/art/.
extends RefCounted

static var _map: Dictionary = {}
static var _pages := {}  # page number -> Texture2D
static var _regions := {}  # card id -> AtlasTexture


static func of(id: String) -> Texture2D:
	if _regions.has(id):
		return _regions[id]
	if _map.is_empty():
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/tcg/atlas.json")) if FileAccess.file_exists("res://data/tcg/atlas.json") else null
		_map = (raw as Dictionary).get("art", {}) if raw is Dictionary else {"": []}
	if _map.has(id):
		var at: Array = _map[id]
		var page := int(at[0])
		if not _pages.has(page):
			var path := "res://assets/tcg/atlas/page_%d.jpg" % page
			_pages[page] = load(path) if ResourceLoader.exists(path) else null
		if _pages[page] != null:
			var region := AtlasTexture.new()
			region.atlas = _pages[page]
			region.region = Rect2(float(at[1]), float(at[2]), float(at[3]), float(at[4]))
			_regions[id] = region
			return region
	var own := "res://assets/tcg/art/%s.jpg" % id
	return load(own) if ResourceLoader.exists(own) else null
