extends RefCounted
## Static board data and tuning constants. No game state lives here.

enum Kind { PAYDAY, PROPERTY, AUDIT, JACKPOT, TAX_RAID, METRO, WINDFALL, PERMIT_OFFICE }

const TILE_COUNT := 28
const DISTRICT_COUNT := 7

# --- Tuning (balanced with tools/sim.gd) ---
# Everyone starts level: START_WORTH is cash plus the list price of the deeds they are dealt.
const START_WORTH := 1300
const START_DEEDS := 2
# Later seats reach unowned tiles second, so they start with a little more cash.
const SEAT_BONUS := 75
const SALARY := 200
const STEER_MAX := 3
const ROUNDS := 12
const RENT_RATE := 0.25
const LEVEL_MULT := [1.0, 2.0, 3.5, 5.5, 8.0, 12.0]
# Indexed by how many of a district's three tiles the owner holds.
const LEVEL_CAP := [0, 2, 3, 4]
const DISTRICT_MULT := [1.0, 1.0, 1.4, 2.0]
const MAX_LEVEL := 4
const LANDMARK_LEVEL := 5
const UPGRADE_RATE := 0.5  # of tile price, per level
const DEMAND_START := 2
const DEMAND_MAX := 5
const AUCTION_MIN_RATE := 0.5
const TAKEOVER_MULT := 2.0
const AUDIT_FEE := 100
const TAX_RAID_RATE := 0.15
const POT_SEED := 100
const PERK_CASH := 80
const DEBT_PENALTY := 1.25
const DEBT_INTEREST := 1.10
const DISTRICTS_TO_WIN := 3
const SPIRE_PRESTIGE := 500
const SWAP_PRICE_SLACK := 60

const DISTRICTS := [
	{"name": "Docklands", "color": Color("4fb6c9"), "landmark": "Lighthouse",
		"power": "Earn 30 whenever anyone passes Payday."},
	{"name": "Old Quarter", "color": Color("e0a15a"), "landmark": "Grand Bazaar",
		"power": "Pay 20% less on auctions you win."},
	{"name": "Garden Row", "color": Color("7ac77a"), "landmark": "Conservatory",
		"power": "Demand never decays in districts where you own a tile."},
	{"name": "Midtown", "color": Color("e8706a"), "landmark": "Transit Hub",
		"power": "Roll a third die."},
	{"name": "Arena District", "color": Color("c77ad9"), "landmark": "Arena",
		"power": "Demand here is always at maximum."},
	{"name": "Finance Row", "color": Color("f2cf5b"), "landmark": "Bank",
		"power": "Earn 5% interest on cash each round (max 150)."},
	{"name": "Skyline Heights", "color": Color("6f8cf0"), "landmark": "The Spire",
		"power": "Worth 500 prestige at the final count."},
]

const TILES := [
	{"kind": Kind.PAYDAY, "name": "Payday"},
	{"kind": Kind.PROPERTY, "name": "Pier Nine", "district": 0, "price": 60},
	{"kind": Kind.PROPERTY, "name": "Saltworks", "district": 0, "price": 60},
	{"kind": Kind.PROPERTY, "name": "Crane Row", "district": 0, "price": 70},
	{"kind": Kind.PROPERTY, "name": "Lantern Lane", "district": 1, "price": 100},
	{"kind": Kind.METRO, "name": "Metro"},
	{"kind": Kind.PROPERTY, "name": "Bell Court", "district": 1, "price": 100},
	{"kind": Kind.AUDIT, "name": "Audit"},
	{"kind": Kind.PROPERTY, "name": "Copper Alley", "district": 1, "price": 110},
	{"kind": Kind.PROPERTY, "name": "Fern Walk", "district": 2, "price": 140},
	{"kind": Kind.PROPERTY, "name": "Orchard Steps", "district": 2, "price": 140},
	{"kind": Kind.PROPERTY, "name": "Glasshouse", "district": 2, "price": 150},
	{"kind": Kind.PROPERTY, "name": "Union Street", "district": 3, "price": 180},
	{"kind": Kind.PROPERTY, "name": "Clocktower", "district": 3, "price": 180},
	{"kind": Kind.JACKPOT, "name": "Jackpot Plaza"},
	{"kind": Kind.PROPERTY, "name": "Arcade", "district": 3, "price": 190},
	{"kind": Kind.PROPERTY, "name": "Stadium Gate", "district": 4, "price": 220},
	{"kind": Kind.PROPERTY, "name": "Neon Mile", "district": 4, "price": 220},
	{"kind": Kind.PROPERTY, "name": "Encore Hall", "district": 4, "price": 230},
	{"kind": Kind.WINDFALL, "name": "Windfall"},
	{"kind": Kind.PROPERTY, "name": "Ledger Lane", "district": 5, "price": 260},
	{"kind": Kind.TAX_RAID, "name": "Tax Raid"},
	{"kind": Kind.PROPERTY, "name": "Mint Square", "district": 5, "price": 260},
	{"kind": Kind.PROPERTY, "name": "Vault Plaza", "district": 5, "price": 280},
	{"kind": Kind.PROPERTY, "name": "Cloud Terrace", "district": 6, "price": 320},
	{"kind": Kind.PERMIT_OFFICE, "name": "Permit Office"},
	{"kind": Kind.PROPERTY, "name": "Aurora Deck", "district": 6, "price": 320},
	{"kind": Kind.PROPERTY, "name": "The Summit", "district": 6, "price": 350},
]

const TYCOONS := {
	"developer": {"name": "The Developer",
		"passive": "Builds cost 15% less.",
		"power": "Overnight Build: upgrade one tile for free."},
	"shark": {"name": "The Shark",
		"passive": "Collects 20% more rent.",
		"power": "Squeeze: the next rent you collect is doubled."},
	"broker": {"name": "The Broker",
		"passive": "Buys tiles 25% under list price; takeovers cost 1.5x value instead of 2x.",
		"power": "Forced Swap: trade one of your unbuilt tiles for a rival's."},
	"drifter": {"name": "The Drifter",
		"passive": "Holds up to 5 steer tokens and earns 2 at every Payday.",
		"power": "Shortcut: jump to any district tile on the board."},
}

const HEADLINES := [
	{"id": "boom", "title": "Boom Times", "text": "All rents +50% this round."},
	{"id": "blackout", "title": "Blackout", "text": "%s collects no rent this round.", "district": true},
	{"id": "tax_reform", "title": "Tax Reform", "text": "Everyone pays 10% of their cash into the Jackpot."},
	{"id": "stimulus", "title": "Stimulus", "text": "Everyone receives 100."},
	{"id": "subsidy", "title": "Construction Subsidy", "text": "All builds are half price this round."},
	{"id": "hot_spot", "title": "Hot Spot", "text": "Demand in %s jumps to maximum.", "district": true},
	{"id": "slump", "title": "Slump", "text": "Demand falls by 1 everywhere."},
	{"id": "bonus", "title": "Payday Bonus", "text": "Payday salaries are doubled this round."},
	{"id": "rent_freeze", "title": "Rent Freeze", "text": "All rents are halved this round."},
	{"id": "gold_rush", "title": "Gold Rush", "text": "The Jackpot grows by 200."},
	{"id": "wealth_tax", "title": "Wealth Tax", "text": "The richest player pays 100 to the poorest."},
	{"id": "open_house", "title": "Open House", "text": "Unowned tiles are 25% cheaper this round."},
	{"id": "quiet", "title": "Quiet Day", "text": "Nothing happens. Enjoy it."},
]


static func district_tiles(d: int) -> Array:
	var out := []
	for i in TILE_COUNT:
		var t: Dictionary = TILES[i]
		if t.kind == Kind.PROPERTY and t.district == d:
			out.append(i)
	return out


static func upgrade_base_cost(tile: int) -> int:
	return int(TILES[tile].price * UPGRADE_RATE)
