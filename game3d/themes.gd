extends RefCounted
## Each table's city: its name, wall tints, sky tint and sunlight. The island and park art for a
## theme is art/toy/<id>/ (tools/blender/build_toy.py). Tables climb from a small town to a
## futuristic city.

const THEMES := {
	"town": {"name": "Small Town", "sky": Color(1, 1, 1), "light": Color("fff0d6"),
		"walls": [Color("fff4e2"), Color("fde6d8"), Color("e8f4ea"), Color("eae6fb"), Color("e3f1fb"), Color("fff0c8")]},
	"forest": {"name": "Forest", "sky": Color("e6f5e6"), "light": Color("fff3d9"),
		"walls": [Color("f3e2c6"), Color("e8d2ae"), Color("f5ead8"), Color("e2d5bd"), Color("efdcc0"), Color("f8eedc")]},
	"desert": {"name": "Desert", "sky": Color("fff0dc"), "light": Color("ffe2b8"),
		"walls": [Color("fbe3bd"), Color("f7d6a8"), Color("fff0d6"), Color("f2cf9e"), Color("fde8c8"), Color("f9dcb4")]},
	"city": {"name": "City", "sky": Color(1, 1, 1), "light": Color("fff0d6"),
		"walls": [Color("ffffff"), Color("fde6d8"), Color("e3f1fb"), Color("f2ecdf"), Color("e8f4ea"), Color("fff0c8")]},
	"metro": {"name": "Big City", "sky": Color("e9ecf7"), "light": Color("fff5e6"),
		"walls": [Color("eef1f6"), Color("dfe7f2"), Color("f5f0e8"), Color("e6e3f0"), Color("dcecf2"), Color("f2f2f2")]},
	"future": {"name": "Future City", "sky": Color("e6dcff"), "light": Color("eee8ff"),
		"walls": [Color("ffffff"), Color("e6f6ff"), Color("f0e6ff"), Color("e6fff7"), Color("fff0fb"), Color("eef0ff")]},
}


## Table (tier) -> theme, from the economy's table list. Tier 0 (practice) looks like table 1.
static func for_tier(tier: int) -> Dictionary:
	var tiers: Array = preload("res://core/economy.gd").TIERS
	return get_theme(str(tiers[clampi(tier, 1, tiers.size()) - 1].theme))


static func get_theme(id: String) -> Dictionary:
	var t: Dictionary = THEMES.get(id, THEMES.town).duplicate()
	t.id = id if THEMES.has(id) else "town"
	return t
