extends RefCounted
## The look of each table: ground, tiles, frame, sky, light and the art kit its buildings and
## centrepiece come from. Tables climb from a small town to a futuristic city.

const THEMES := {
	"town": {
		"name": "Small Town",
		"sky": "res://art/ui/sky_bg.jpg",
		"frame": Color("8b6a4f"), "frame_lip": Color("6b4f3a"),
		"tile": Color("f6eedd"), "tile_lip": Color("d9c9a8"),
		"special": Color("ffe7b0"),
		"centre": Color("9fd67a"),
		"light": Color("ffe2c4"), "ambient": Color("fff0e6"),
	},
	"forest": {
		"name": "Forest",
		"sky": "res://art/ui/sky_bg.jpg",
		"frame": Color("5a7a45"), "frame_lip": Color("3f5a31"),
		"tile": Color("eef1dc"), "tile_lip": Color("c6d0a6"),
		"special": Color("ffe9b8"),
		"centre": Color("6fbf63"),
		"light": Color("fff0cf"), "ambient": Color("eaf6e4"),
	},
	"desert": {
		"name": "Desert",
		"sky": "res://art/ui/sky_bg.jpg",
		"frame": Color("c98b52"), "frame_lip": Color("a26a3b"),
		"tile": Color("fbecd2"), "tile_lip": Color("e2c79c"),
		"special": Color("ffd98f"),
		"centre": Color("f1cf8f"),
		"light": Color("ffd9a8"), "ambient": Color("fff0dc"),
	},
	"city": {
		"name": "City",
		"sky": "res://art/ui/sky_bg.jpg",
		"frame": Color("7d86a8"), "frame_lip": Color("5c6486"),
		"tile": Color("f3eee6"), "tile_lip": Color("d3cbbd"),
		"special": Color("ffe3a8"),
		"centre": Color("a6dc86"),
		"light": Color("ffe2c4"), "ambient": Color("fff0e6"),
	},
	"metro": {
		"name": "Big City",
		"sky": "res://art/ui/sky_bg.jpg",
		"frame": Color("4b5375"), "frame_lip": Color("343b58"),
		"tile": Color("eceef4"), "tile_lip": Color("c4c9d8"),
		"special": Color("ffd98a"),
		"centre": Color("8fcf7a"),
		"light": Color("ffd7b5"), "ambient": Color("f0ecf6"),
	},
	"future": {
		"name": "Future City",
		"sky": "res://art/ui/sky_bg.jpg",
		"frame": Color("2d3263"), "frame_lip": Color("1d2147"),
		"tile": Color("e9f1ff"), "tile_lip": Color("b4c4e6"),
		"special": Color("b8f3ff"),
		"centre": Color("7fe0d4"),
		"light": Color("e0e8ff"), "ambient": Color("e8ecff"),
	},
}

## Table (tier) -> theme, from the economy's table list. Tier 0 (practice) looks like table 1.
static func for_tier(tier: int) -> Dictionary:
	var tiers: Array = preload("res://core/economy.gd").TIERS
	return get_theme(str(tiers[clampi(tier, 1, tiers.size()) - 1].theme))


static func get_theme(id: String) -> Dictionary:
	var t: Dictionary = THEMES.get(id, THEMES.city).duplicate()
	t.id = id if THEMES.has(id) else "city"
	return t


## A theme's model if it has one, else the shared city kit's.
static func model(theme_id: String, name: String) -> String:
	var own := "res://art/themes/%s/%s.glb" % [theme_id, name]
	if ResourceLoader.exists(own):
		return own
	return "res://art/models/%s.glb" % name
