extends RefCounted
## Everything the meta game is tuned by: table tiers (one global ladder whose city names are
## localized per player), their rule twists, the coin/gem economy, levels, daily rewards,
## the spin wheel, missions and the shop. Pure data plus small helpers; no state.

const START_COINS := 1000
const START_GEMS := 20
const RAKE := 0.10  # the house keeps 10% of every pot so coins don't inflate

## The six tables, climbing from a small town to a city of the future. Players from different
## countries share a table; only the city name on their screen changes (each country's names
## are picked to suit the table's look). `rules` are passed straight into the engine config.
const TIERS := [
	{"id": 1, "theme": "town", "entry": 100, "level": 1, "twist": "Market Day",
		"desc": "Payday pays 50% more.", "rules": {"salary_mult": 1.5}},
	{"id": 2, "theme": "forest", "entry": 500, "level": 3, "twist": "Timber Rush",
		"desc": "Auctions open at 40% of the price.", "rules": {"auction_min": 0.4}},
	{"id": 3, "theme": "desert", "entry": 2000, "level": 6, "twist": "Oasis Boom",
		"desc": "Every district starts with hot demand.", "rules": {"demand_start": 3}},
	{"id": 4, "theme": "city", "entry": 5000, "level": 10, "twist": "Rush Hour",
		"desc": "Takeovers cost only 1.5x.", "rules": {"takeover_mult": 1.5}},
	{"id": 5, "theme": "metro", "entry": 10000, "level": 14, "twist": "High Rollers",
		"desc": "Jackpot starts at 500.", "rules": {"pot_seed": 500}},
	{"id": 6, "theme": "future", "entry": 25000, "level": 18, "twist": "Neon Nights",
		"desc": "Jackpot starts at 1,000 and Payday pays 25% more.", "rules": {"pot_seed": 1000, "salary_mult": 1.25}},
]

## City names per country, one per table, matched to its look: small town, forest, desert,
## city, big city, future city. Anything else falls back to WORLD.
const CITY_NAMES := {
	"PK": ["Hunza", "Murree", "Bahawalpur", "Lahore", "Karachi", "Neo Islamabad"],
	"IN": ["Shimla", "Munnar", "Jaisalmer", "Delhi", "Mumbai", "Neo Bengaluru"],
	"BD": ["Sylhet", "Sundarbans", "Cox's Bazar", "Chattogram", "Dhaka", "Neo Dhaka"],
	"AE": ["Hatta", "Al Ain", "Liwa", "Sharjah", "Dubai", "Masdar"],
	"SA": ["Taif", "Abha", "AlUla", "Jeddah", "Riyadh", "NEOM"],
	"GB": ["Bath", "Sherwood", "Dungeness", "Manchester", "London", "Neo London"],
	"US": ["Nantucket", "Yosemite", "Sedona", "Chicago", "New York", "Neo San Francisco"],
	"WORLD": ["Hallstatt", "Black Forest", "Marrakesh", "Paris", "Tokyo", "Neo Seoul"],
}

const COUNTRY_NAMES := {"PK": "Pakistan", "IN": "India", "BD": "Bangladesh", "AE": "UAE",
	"SA": "Saudi Arabia", "GB": "United Kingdom", "US": "United States", "WORLD": "World"}

# ---------------------------------------------------------------- levels and match rewards

## XP needed to go from `level` to `level + 1`.
static func xp_to_next(level: int) -> int:
	return 100 + (level - 1) * 60


## Coins for 1st place; everyone else wins nothing but XP and trophies (winner takes the pot).
static func prize(tier: int) -> int:
	return int(TIERS[tier - 1].entry * 4 * (1.0 - RAKE))


const PLACE_XP := [120, 70, 45, 30]
const PLACE_TROPHIES := [30, 10, -5, -12]
const PRACTICE_XP := [40, 25, 15, 10]

# ---------------------------------------------------------------- daily rewards

## A 7-day loop. "c" = coins, "g" = gems, "chest" = gold chest on day 7.
const DAILY := [
	{"kind": "c", "amount": 100}, {"kind": "c", "amount": 200}, {"kind": "c", "amount": 300},
	{"kind": "g", "amount": 5}, {"kind": "c", "amount": 600}, {"kind": "g", "amount": 10},
	{"kind": "chest", "amount": 1},
]

const CHEST := {"coins": 1500, "gems": 15}

# ---------------------------------------------------------------- spin wheel

## Weighted prizes. Order is the order of slices on the wheel.
const SPIN := [
	{"kind": "c", "amount": 100, "w": 26}, {"kind": "c", "amount": 250, "w": 22},
	{"kind": "g", "amount": 5, "w": 8}, {"kind": "c", "amount": 500, "w": 14},
	{"kind": "c", "amount": 150, "w": 24}, {"kind": "g", "amount": 10, "w": 3},
	{"kind": "c", "amount": 1000, "w": 2}, {"kind": "c", "amount": 50, "w": 1},
]

# ---------------------------------------------------------------- missions

## Daily mission pool. `stat` is counted from match events for the player.
const MISSIONS := [
	{"id": "win1", "text": "Win 1 match", "stat": "wins", "need": 1, "reward": {"c": 250}},
	{"id": "play3", "text": "Play 3 matches", "stat": "matches", "need": 3, "reward": {"c": 200}},
	{"id": "rent1000", "text": "Collect 1,000 rent", "stat": "rent_in", "need": 1000, "reward": {"c": 300}},
	{"id": "build6", "text": "Build 6 times", "stat": "builds", "need": 6, "reward": {"c": 200}},
	{"id": "landmark1", "text": "Raise a landmark", "stat": "landmarks", "need": 1, "reward": {"g": 5}},
	{"id": "auction2", "text": "Win 2 auctions", "stat": "auctions_won", "need": 2, "reward": {"c": 250}},
	{"id": "takeover1", "text": "Take over a tile", "stat": "takeovers", "need": 1, "reward": {"c": 300}},
	{"id": "jackpot1", "text": "Hit the Jackpot", "stat": "jackpots", "need": 1, "reward": {"g": 5}},
	{"id": "buy5", "text": "Buy 5 tiles", "stat": "buys", "need": 5, "reward": {"c": 200}},
]

# ---------------------------------------------------------------- shop

## Gem-priced cosmetics, and coin packs bought with gems. Real-money packs are placeholders
## until Play Billing is connected (prices are set in the Play Console).
const SHOP := [
	{"id": "token_gold", "kind": "token", "name": "Golden Pawn", "gems": 120, "color": "ffc23d"},
	{"id": "token_ruby", "kind": "token", "name": "Ruby Pawn", "gems": 80, "color": "e8364f"},
	{"id": "token_jade", "kind": "token", "name": "Jade Pawn", "gems": 80, "color": "19b37a"},
	{"id": "dice_marble", "kind": "dice", "name": "Marble Dice", "gems": 60, "color": "eef1f7"},
	{"id": "dice_neon", "kind": "dice", "name": "Neon Dice", "gems": 100, "color": "c77ad9"},
	{"id": "coins_5k", "kind": "coins", "name": "5,000 coins", "gems": 40, "amount": 5000},
	{"id": "coins_20k", "kind": "coins", "name": "20,000 coins", "gems": 140, "amount": 20000},
]

const GEM_PACKS := [
	{"id": "gems_80", "gems": 80}, {"id": "gems_500", "gems": 500}, {"id": "gems_1200", "gems": 1200, "best": true},
]


static func tier_name(tier: int, country: String) -> String:
	var names: Array = CITY_NAMES.get(country, CITY_NAMES.WORLD)
	return names[tier - 1]


static func shop_item(id: String) -> Dictionary:
	for it: Dictionary in SHOP:
		if it.id == id:
			return it
	return {}
