extends RefCounted
## The Skyloop rules engine. Pure logic: no nodes, no rendering, deterministic for a given
## seed and sequence of submitted choices.
##
## Drive it by reading `pending` (the decision the game is waiting on) and calling
## `submit(choice)`. Everything that happened in between is appended to `events`, which the
## presentation layer drains and animates.

const Board = preload("res://core/board.gd")

const BANK := -1
const POT := -2

enum Stage { PERK, LAND, MANAGE, END }


class Player:
	var name := ""
	var tycoon := ""
	var is_bot := false
	var pos := 0
	var cash := 0
	var steer := 0  # tokens: spend one to move by a single die instead of the sum
	var debt := 0
	var frozen := false  # audited: collects no rent until their next turn
	var permit := false  # next build is half price
	var shield := false  # next rent paid is halved
	var squeeze := false  # next rent collected is doubled
	var power_used := false
	var bailouts := 0


var players: Array = []
var owner_of: Array = []  # tile -> player index, -1 if unowned
var level_of: Array = []  # tile -> 0..5
var demand: Array = []  # district -> 0..DEMAND_MAX
var pot := Board.POT_SEED
var round_no := 1
var rounds := Board.ROUNDS
var turn := 0
var headline := {}
var next_headline := {}
var mods := {}
var dice: Array = []
var pending := {}
var events: Array = []
var over := false
var winner := -1
var win_reason := ""
var rng := RandomNumberGenerator.new()
## Table rule twists (see core/economy.gd): salary_mult, auction_min, demand_start,
## takeover_mult, pot_seed. Missing keys mean the standard rules.
var rules := {}
var stats := {"rent": 0, "buys": 0, "auctions": 0, "auction_sales": 0, "takeovers": 0,
	"upgrades": 0, "landmarks": 0, "lead_changes": 0, "decisions": 0}

var _stage: int = Stage.END
var _perk_due := false
var _auction := {}
var _deck: Array = []
var _idle: Array = []  # district -> rounds in a row with no visitor
var _dtiles: Array = []
var _leader := -1


## config: {"players": [{"name", "tycoon", "bot"}], "seed": int, "rounds": int, "deeds": int}
## An empty config makes a blank game for `from_dict` to fill in.
func _init(config: Dictionary = {}) -> void:
	for d in Board.DISTRICT_COUNT:
		_dtiles.append(Board.district_tiles(d))
	if config.is_empty():
		return
	rng.seed = int(config.get("seed", 1))
	rounds = int(config.get("rounds", Board.ROUNDS))
	rules = config.get("rules", {}).duplicate()
	pot = int(rules.get("pot_seed", Board.POT_SEED))
	for pc: Dictionary in config.players:
		var p := Player.new()
		p.name = pc.get("name", "Player")
		p.tycoon = pc.get("tycoon", "developer")
		p.is_bot = pc.get("bot", false)
		p.cash = Board.START_WORTH + Board.SEAT_BONUS * players.size()
		p.steer = 2
		players.append(p)
	for i in Board.TILE_COUNT:
		owner_of.append(-1)
		level_of.append(0)
	for d in Board.DISTRICT_COUNT:
		demand.append(int(rules.get("demand_start", Board.DEMAND_START)))
		_idle.append(0)
	mods = {"rent": 1.0, "build": 1.0, "salary": 1.0, "price": 1.0, "blackout": -1}
	_deal_deeds(int(config.get("deeds", Board.START_DEEDS)))
	next_headline = _draw_headline()
	_begin_round()
	_start_turn()


## Deals each player starting tiles from different districts, paid for out of their cash,
## so every seat begins with the same net worth.
func _deal_deeds(count: int) -> void:
	for n in count:
		for pi in players.size():
			var pool := []
			for t in Board.TILE_COUNT:
				if is_property(t) and owner_of[t] == -1 and district_count(pi, Board.TILES[t].district) == 0:
					pool.append(t)
			if pool.is_empty():
				continue
			var tile: int = pool[rng.randi_range(0, pool.size() - 1)]
			owner_of[tile] = pi
			players[pi].cash -= Board.TILES[tile].price
			_ev("own", {"p": pi, "tile": tile, "paid": Board.TILES[tile].price, "how": "deed"})


# ---------------------------------------------------------------- save / restore

const _PLAYER_FIELDS := ["name", "tycoon", "is_bot", "pos", "cash", "steer", "debt", "frozen",
	"permit", "shield", "squeeze", "power_used", "bailouts"]
const _STATE_FIELDS := ["rules", "owner_of", "level_of", "demand", "pot", "round_no", "rounds", "turn",
	"headline", "next_headline", "mods", "dice", "pending", "over", "winner", "win_reason", "stats",
	"_stage", "_perk_due", "_auction", "_deck", "_idle", "_leader"]
const SAVE_VERSION := 2


## A complete snapshot of the match (everything except unplayed `events`). Values keep their
## Godot types, so store it with `var_to_bytes` / `store_var`, not JSON.
func to_dict() -> Dictionary:
	var d := {"version": SAVE_VERSION, "rng_seed": rng.seed, "rng_state": rng.state, "players": []}
	for p: Player in players:
		var pd := {}
		for f: String in _PLAYER_FIELDS:
			pd[f] = p.get(f)
		d.players.append(pd)
	for f: String in _STATE_FIELDS:
		var v = get(f)
		d[f] = v.duplicate(true) if v is Array or v is Dictionary else v
	return d


static func from_dict(d: Dictionary):
	if int(d.get("version", 0)) != SAVE_VERSION:
		return null
	var g = new()
	g.rng.seed = d.rng_seed
	g.rng.state = d.rng_state
	for pd: Dictionary in d.players:
		var p := Player.new()
		for f: String in _PLAYER_FIELDS:
			p.set(f, pd[f])
		g.players.append(p)
	for f: String in _STATE_FIELDS:
		var v = d[f]
		g.set(f, v.duplicate(true) if v is Array or v is Dictionary else v)
	return g


# ---------------------------------------------------------------- queries

func salary() -> int:
	return int(Board.SALARY * mods.salary * float(rules.get("salary_mult", 1.0)))


func is_property(tile: int) -> bool:
	return Board.TILES[tile].kind == Board.Kind.PROPERTY


func price_of(tile: int) -> int:
	return _r5(Board.TILES[tile].price * mods.price)


## What this player pays to buy the tile outright.
func price_for(pi: int, tile: int) -> int:
	var m := 0.75 if players[pi].tycoon == "broker" else 1.0
	return _r5(Board.TILES[tile].price * mods.price * m)


static func steer_max(p: Player) -> int:
	return 5 if p.tycoon == "drifter" else Board.STEER_MAX


func district_count(pi: int, d: int) -> int:
	var n := 0
	for t: int in _dtiles[d]:
		if owner_of[t] == pi:
			n += 1
	return n


func owns_district(pi: int, d: int) -> bool:
	return district_count(pi, d) == _dtiles[d].size()


func full_districts(pi: int) -> int:
	var n := 0
	for d in Board.DISTRICT_COUNT:
		if owns_district(pi, d):
			n += 1
	return n


## Player who has built the landmark of district d, or -1.
func landmark_owner(d: int) -> int:
	for t: int in _dtiles[d]:
		if level_of[t] == Board.LANDMARK_LEVEL:
			return owner_of[t]
	return -1


func demand_of(d: int) -> int:
	if d == 4 and landmark_owner(4) != -1:
		return Board.DEMAND_MAX
	return demand[d]


## Rent a visitor would pay on this tile right now, before shields and squeezes.
func rent_for(tile: int) -> int:
	var o: int = owner_of[tile]
	if o == -1:
		return 0
	var t: Dictionary = Board.TILES[tile]
	var d: int = t.district
	if mods.blackout == d or players[o].frozen:
		return 0
	var r: float = t.price * Board.RENT_RATE * Board.LEVEL_MULT[level_of[tile]]
	r *= Board.DISTRICT_MULT[district_count(o, d)]
	r *= 0.7 + 0.15 * demand_of(d)
	r *= mods.rent
	if players[o].tycoon == "shark":
		r *= 1.2
	return maxi(5, _r5(r))


func can_upgrade(pi: int, tile: int) -> bool:
	if not is_property(tile) or owner_of[tile] != pi:
		return false
	var lvl: int = level_of[tile]
	var d: int = Board.TILES[tile].district
	if lvl < Board.LEVEL_CAP[district_count(pi, d)]:
		return true
	return lvl == Board.MAX_LEVEL and owns_district(pi, d) and landmark_owner(d) == -1


func upgrade_cost(pi: int, tile: int) -> int:
	var c: float = Board.upgrade_base_cost(tile) * mods.build
	var p: Player = players[pi]
	if p.tycoon == "developer":
		c *= 0.85
	if p.permit:
		c *= 0.5
	return maxi(5, _r5(c))


func tile_value(tile: int) -> int:
	return Board.TILES[tile].price + level_of[tile] * Board.upgrade_base_cost(tile)


## A visitor may buy out any rival tile they land on, buildings included, unless the owner
## holds the whole district.
func can_takeover(pi: int, tile: int) -> bool:
	var o: int = owner_of[tile]
	return o != -1 and o != pi and not owns_district(o, Board.TILES[tile].district)


func takeover_cost(pi: int, tile: int) -> int:
	var base: float = rules.get("takeover_mult", Board.TAKEOVER_MULT)
	var m := minf(1.5, base) if players[pi].tycoon == "broker" else base
	return _r5(tile_value(tile) * m)


func net_worth(pi: int) -> int:
	var p: Player = players[pi]
	var w := p.cash - p.debt
	for t in Board.TILE_COUNT:
		if owner_of[t] == pi:
			w += tile_value(t)
	if landmark_owner(6) == pi:
		w += Board.SPIRE_PRESTIGE
	return w


func leader() -> int:
	var best := 0
	for i in players.size():
		var a := net_worth(i)
		var b := net_worth(best)
		if a > b or (a == b and players[i].cash > players[best].cash):
			best = i
	return best


## What would happen to player pi moving `steps` from where they stand: a short label and
## a tone ("good", "bad" or "neutral") for the move preview.
func landing_preview(pi: int, steps: int) -> Dictionary:
	var p: Player = players[pi]
	var tile := (p.pos + steps) % Board.TILE_COUNT
	var passes := p.pos + steps >= Board.TILE_COUNT
	var t: Dictionary = Board.TILES[tile]
	var text := ""
	var tone := "neutral"
	match t.kind:
		Board.Kind.PROPERTY:
			var o: int = owner_of[tile]
			if o == -1:
				text = "Buy $%d" % price_for(pi, tile)
				tone = "good" if p.cash >= price_for(pi, tile) else "neutral"
			elif o == pi:
				text = "Yours"
			else:
				var r := rent_for(tile)
				if p.shield:
					r = _r5(r * 0.5)
				text = "Pay $%d" % r if r > 0 else "Free"
				tone = "bad" if r > 0 else "neutral"
		Board.Kind.JACKPOT:
			text = "+$%d" % pot
			tone = "good"
		Board.Kind.TAX_RAID:
			text = "-$%d" % _r5(p.cash * Board.TAX_RAID_RATE)
			tone = "bad"
		Board.Kind.AUDIT:
			text = "Audit"
			tone = "bad"
		Board.Kind.WINDFALL:
			text = "+$%d" % (40 + 10 * round_no)
			tone = "good"
		Board.Kind.METRO:
			text = "Ride"
		Board.Kind.PERMIT_OFFICE:
			text = "Permit"
			tone = "good"
		Board.Kind.PAYDAY:
			text = "Payday"
			tone = "good"
	if passes and t.kind != Board.Kind.PAYDAY:
		text += "  +$%d" % salary()
	return {"tile": tile, "text": text, "tone": tone}


# ---------------------------------------------------------------- choices

## Applies a choice for the current `pending` decision. Returns false if it is illegal.
func submit(c: Dictionary) -> bool:
	if over or pending.is_empty():
		return false
	var pd := pending
	var p: Player = players[pd.player]
	match pd.type:
		"move":
			if c.has("shortcut"):
				var dest := int(c.shortcut)
				if not pd.can_shortcut or dest < 0 or dest >= Board.TILE_COUNT or dest == p.pos 						or not is_property(dest):
					return false
				p.power_used = true
				_ev("power", {"p": turn, "tycoon": p.tycoon})
				_ev("move", {"p": turn, "from": p.pos, "to": dest, "steps": 0, "jump": true})
				p.pos = dest
				pending = {}
				_stage = Stage.LAND
			else:
				var steps := int(c.get("steps", -1))
				if not pd.options.has(steps):
					return false
				if not pd.free.has(steps):
					p.steer -= 1
					_ev("steer", {"p": turn, "left": p.steer})
				pending = {}
				_step(steps)
				_stage = Stage.PERK
		"metro":
			var steps := int(c.get("steps", -1))
			if not pd.options.has(steps):
				return false
			pending = {}
			_step(steps)
			_stage = Stage.PERK
		"perk":
			var perk: String = c.get("perk", "")
			match perk:
				"cash":
					_gain(turn, Board.PERK_CASH)
				"permit":
					p.permit = true
				"shield":
					p.shield = true
				_:
					return false
			_ev("perk", {"p": turn, "perk": perk})
			pending = {}
		"buy":
			pending = {}
			if c.get("buy", false):
				p.cash -= pd.price
				stats.buys += 1
				_set_owner(pd.tile, turn, pd.price, "buy")
			else:
				_start_auction(pd.tile)
		"bid":
			var bid := int(c.get("bid", 0))
			if bid != 0 and (bid < pd.min_bid or bid > pd.max_bid):
				return false
			_auction.bids[pd.player] = bid
			_auction.i += 1
			pending = {}
			_ask_bid()
		"audit":
			pending = {}
			if c.get("pay", false):
				_pay(turn, POT, Board.AUDIT_FEE, "audit")
			else:
				p.frozen = true
				_ev("frozen", {"p": turn})
		"takeover":
			pending = {}
			if c.get("accept", false):
				var prev: int = owner_of[pd.tile]
				p.cash -= pd.cost
				_gain(prev, pd.cost)
				stats.takeovers += 1
				_ev("pay", {"from": turn, "to": prev, "amount": pd.cost, "why": "takeover"})
				_set_owner(pd.tile, turn, pd.cost, "takeover")
		"manage":
			var act := _find_action(pd.actions, c)
			if act.is_empty():
				return false
			pending = {}
			_do_manage(act)
		_:
			return false
	stats.decisions += 1
	_advance()
	return true


# ---------------------------------------------------------------- flow

func _advance() -> void:
	while pending.is_empty() and not over:
		match _stage:
			Stage.PERK:
				_stage = Stage.LAND
				if _perk_due:
					_perk_due = false
					pending = {"type": "perk", "player": turn, "options": ["cash", "permit", "shield"]}
			Stage.LAND:
				_stage = Stage.MANAGE
				_resolve_tile()
			Stage.MANAGE:
				pending = {"type": "manage", "player": turn, "actions": _manage_actions()}
			Stage.END:
				_end_turn()


func _begin_round() -> void:
	headline = next_headline
	next_headline = _draw_headline()
	mods = {"rent": 1.0, "build": 1.0, "salary": 1.0, "price": 1.0, "blackout": -1}
	_ev("headline", {"round": round_no, "headline": headline})
	var d: int = headline.district
	match headline.id:
		"boom":
			mods.rent = 1.5
		"blackout":
			mods.blackout = d
		"tax_reform":
			for i in players.size():
				_pay(i, POT, _r5(players[i].cash * 0.1), "tax")
		"stimulus":
			for i in players.size():
				_pay(BANK, i, 100, "stimulus")
		"subsidy":
			mods.build = 0.5
		"hot_spot":
			demand[d] = Board.DEMAND_MAX
		"slump":
			for i in Board.DISTRICT_COUNT:
				demand[i] = maxi(0, demand[i] - 1)
		"bonus":
			mods.salary = 2.0
		"rent_freeze":
			mods.rent = 0.5
		"gold_rush":
			pot += 200
		"wealth_tax":
			var rich := 0
			var poor := 0
			for i in players.size():
				if net_worth(i) > net_worth(rich):
					rich = i
				if net_worth(i) < net_worth(poor):
					poor = i
			if rich != poor:
				_pay(rich, poor, 100, "wealth_tax")
		"open_house":
			mods.price = 0.75


func _start_turn() -> void:
	var p: Player = players[turn]
	p.frozen = false
	_ev("turn", {"p": turn, "round": round_no})
	_roll()
	_ask_move()


func _roll() -> void:
	var n := 3 if landmark_owner(3) == turn else 2
	dice = []
	for i in n:
		dice.append(rng.randi_range(1, 6))
	_ev("roll", {"p": turn, "dice": dice.duplicate()})


func _ask_move() -> void:
	# Moving by the sum of two dice is free; moving by a single die costs a steer token.
	var p: Player = players[turn]
	var free := []
	var opts := []
	for i in dice.size():
		for j in range(i + 1, dice.size()):
			var s: int = dice[i] + dice[j]
			if not free.has(s):
				free.append(s)
	opts.append_array(free)
	if p.steer > 0:
		for v: int in dice:
			if not opts.has(v):
				opts.append(v)
	opts.sort()
	pending = {"type": "move", "player": turn, "dice": dice.duplicate(), "options": opts,
		"free": free, "steer": p.steer,
		"can_shortcut": p.tycoon == "drifter" and not p.power_used}


func _step(steps: int) -> void:
	var p: Player = players[turn]
	var from := p.pos
	p.pos = (from + steps) % Board.TILE_COUNT
	_ev("move", {"p": turn, "from": from, "to": p.pos, "steps": steps})
	if from + steps >= Board.TILE_COUNT:
		_pay(BANK, turn, salary(), "salary")
		var lh := landmark_owner(0)
		if lh != -1:
			_pay(BANK, lh, 30, "lighthouse")
		p.steer = mini(steer_max(p), p.steer + (2 if p.tycoon == "drifter" else 1))
		_perk_due = true


func _resolve_tile() -> void:
	var p: Player = players[turn]
	var tile := p.pos
	var t: Dictionary = Board.TILES[tile]
	match t.kind:
		Board.Kind.PROPERTY:
			var o: int = owner_of[tile]
			if o == -1:
				var price := price_for(turn, tile)
				if p.cash >= price:
					pending = {"type": "buy", "player": turn, "tile": tile, "price": price}
				else:
					_start_auction(tile)
			elif o != turn:
				_collect_rent(tile)
				if can_takeover(turn, tile):
					var cost := takeover_cost(turn, tile)
					if p.cash >= cost:
						pending = {"type": "takeover", "player": turn, "tile": tile, "cost": cost}
			var d: int = t.district
			_idle[d] = -1
			if demand[d] < Board.DEMAND_MAX:
				demand[d] += 1
		Board.Kind.AUDIT:
			if p.cash >= Board.AUDIT_FEE:
				pending = {"type": "audit", "player": turn, "fee": Board.AUDIT_FEE}
			else:
				p.frozen = true
				_ev("frozen", {"p": turn})
		Board.Kind.JACKPOT:
			_pay(POT, turn, pot, "jackpot")
			pot = int(rules.get("pot_seed", Board.POT_SEED))
		Board.Kind.TAX_RAID:
			_pay(turn, POT, _r5(p.cash * Board.TAX_RAID_RATE), "tax_raid")
		Board.Kind.METRO:
			pending = {"type": "metro", "player": turn, "options": [1, 2, 3, 4, 5, 6]}
		Board.Kind.WINDFALL:
			_pay(BANK, turn, 40 + 10 * round_no, "windfall")
		Board.Kind.PERMIT_OFFICE:
			if p.permit:
				_pay(BANK, turn, 50, "permit_refund")
			else:
				p.permit = true
				_ev("perk", {"p": turn, "perk": "permit"})


func _collect_rent(tile: int) -> void:
	var o: int = owner_of[tile]
	var r := rent_for(tile)
	if r <= 0:
		_ev("no_rent", {"p": turn, "tile": tile})
		return
	var p: Player = players[turn]
	var op: Player = players[o]
	if p.shield:
		p.shield = false
		r = _r5(r * 0.5)
	if op.squeeze:
		op.squeeze = false
		r *= 2
	stats.rent += r
	_pay(turn, o, r, "rent")


func _start_auction(tile: int) -> void:
	var order := []
	for i in players.size():
		order.append((turn + i) % players.size())
	_auction = {"tile": tile, "order": order, "i": 0, "bids": {},
		"min": _r5(price_of(tile) * float(rules.get("auction_min", Board.AUCTION_MIN_RATE)))}
	stats.auctions += 1
	_ev("auction_start", {"tile": tile, "min": _auction.min})
	_ask_bid()


func _ask_bid() -> void:
	var order: Array = _auction.order
	while _auction.i < order.size():
		var pi: int = order[_auction.i]
		if players[pi].cash >= _auction.min:
			pending = {"type": "bid", "player": pi, "tile": _auction.tile,
				"min_bid": _auction.min, "max_bid": players[pi].cash}
			return
		_auction.bids[pi] = 0
		_auction.i += 1
	_finish_auction()


func _finish_auction() -> void:
	var tile: int = _auction.tile
	var bids: Dictionary = _auction.bids
	var best := 0
	var win := -1
	for pi: int in _auction.order:
		var b: int = bids[pi]
		if b > best:
			best = b
			win = pi
	_ev("auction_end", {"tile": tile, "bids": bids.duplicate(), "winner": win})
	if win == -1:
		return
	var amount := best
	if landmark_owner(1) == win:
		amount = _r5(amount * 0.8)
	players[win].cash -= amount
	stats.auction_sales += 1
	_set_owner(tile, win, amount, "auction")


func _manage_actions() -> Array:
	var p: Player = players[turn]
	var acts := []
	for tile in Board.TILE_COUNT:
		if can_upgrade(turn, tile):
			var cost := upgrade_cost(turn, tile)
			if p.cash >= cost:
				acts.append({"a": "upgrade", "tile": tile, "cost": cost})
	if not p.power_used:
		match p.tycoon:
			"developer":
				for tile in Board.TILE_COUNT:
					if can_upgrade(turn, tile):
						acts.append({"a": "power", "tile": tile})
			"shark":
				acts.append({"a": "power"})
			"broker":
				for give in Board.TILE_COUNT:
					if owner_of[give] != turn or level_of[give] != 0:
						continue
					for take in Board.TILE_COUNT:
						var o: int = owner_of[take]
						if o == -1 or o == turn or level_of[take] != 0:
							continue
						if Board.TILES[take].price <= Board.TILES[give].price + Board.SWAP_PRICE_SLACK:
							acts.append({"a": "power", "give": give, "take": take})
	acts.append({"a": "end"})
	return acts


func _find_action(acts: Array, c: Dictionary) -> Dictionary:
	for act: Dictionary in acts:
		if act.a != c.get("a", ""):
			continue
		if act.get("tile", -1) == c.get("tile", -1) and act.get("give", -1) == c.get("give", -1) \
				and act.get("take", -1) == c.get("take", -1):
			return act
	return {}


func _do_manage(act: Dictionary) -> void:
	var p: Player = players[turn]
	match act.a:
		"end":
			_stage = Stage.END
		"upgrade":
			p.cash -= act.cost
			p.permit = false
			_build(act.tile, act.cost)
		"power":
			p.power_used = true
			_ev("power", {"p": turn, "tycoon": p.tycoon})
			match p.tycoon:
				"developer":
					_build(act.tile, 0)
				"shark":
					p.squeeze = true
				"broker":
					var rival: int = owner_of[act.take]
					_ev("swap", {"p": turn, "rival": rival, "give": act.give, "take": act.take})
					owner_of[act.give] = rival
					owner_of[act.take] = turn
					_check_district_win(turn)
					_check_district_win(rival)


func _build(tile: int, cost: int) -> void:
	level_of[tile] += 1
	stats.upgrades += 1
	if level_of[tile] == Board.LANDMARK_LEVEL:
		stats.landmarks += 1
	_ev("build", {"p": turn, "tile": tile, "level": level_of[tile], "cost": cost})


func _set_owner(tile: int, pi: int, paid: int, how: String) -> void:
	owner_of[tile] = pi
	_ev("own", {"p": pi, "tile": tile, "paid": paid, "how": how})
	_check_district_win(pi)


func _check_district_win(pi: int) -> void:
	if not over and full_districts(pi) >= Board.DISTRICTS_TO_WIN:
		_finish(pi, "districts")


func _end_turn() -> void:
	var lead := leader()
	if _leader != -1 and lead != _leader:
		stats.lead_changes += 1
	_leader = lead
	turn += 1
	if turn >= players.size():
		turn = 0
		_end_round()
		if over:
			return
	_start_turn()


func _end_round() -> void:
	var keeper := landmark_owner(2)
	for d in Board.DISTRICT_COUNT:
		var protected := keeper != -1 and district_count(keeper, d) > 0
		# Demand cools by one after two quiet rounds in a row.
		_idle[d] += 1
		if _idle[d] >= 2:
			_idle[d] = 0
			if not protected and demand[d] > 0:
				demand[d] -= 1
	var banker := landmark_owner(5)
	if banker != -1:
		_pay(BANK, banker, mini(150, _r5(players[banker].cash * 0.05)), "interest")
	for p: Player in players:
		if p.debt > 0:
			p.debt = int(ceil(p.debt * Board.DEBT_INTEREST))
	_ev("round_end", {"round": round_no})
	round_no += 1
	if round_no > rounds:
		round_no = rounds
		_finish(leader(), "rounds")
	else:
		_begin_round()


func _finish(pi: int, reason: String) -> void:
	over = true
	winner = pi
	win_reason = reason
	pending = {}
	_ev("game_over", {"winner": pi, "reason": reason})


# ---------------------------------------------------------------- money

func _gain(pi: int, amount: int) -> void:
	var p: Player = players[pi]
	if p.debt > 0:
		var repay := mini(p.debt, amount)
		p.debt -= repay
		amount -= repay
	p.cash += amount


## Forced payment. Whatever the payer cannot cover becomes debt, so the payee is always paid.
func _charge(pi: int, amount: int) -> void:
	var p: Player = players[pi]
	if p.cash >= amount:
		p.cash -= amount
		return
	var short := amount - p.cash
	p.cash = 0
	p.debt += int(ceil(short * Board.DEBT_PENALTY))
	p.bailouts += 1
	_ev("bailout", {"p": pi, "amount": short})


func _pay(from: int, to: int, amount: int, why: String) -> void:
	if amount <= 0:
		return
	if from >= 0:
		_charge(from, amount)
	if to >= 0:
		_gain(to, amount)
	elif to == POT:
		pot += amount
	_ev("pay", {"from": from, "to": to, "amount": amount, "why": why})


# ---------------------------------------------------------------- misc

func _draw_headline() -> Dictionary:
	if _deck.is_empty():
		_deck = Board.HEADLINES.duplicate()
		for i in range(_deck.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp: Dictionary = _deck[i]
			_deck[i] = _deck[j]
			_deck[j] = tmp
	var h: Dictionary = _deck.pop_back().duplicate()
	if h.has("district"):
		var d := rng.randi_range(0, Board.DISTRICT_COUNT - 1)
		h.district = d
		h.text = h.text % Board.DISTRICTS[d].name
	else:
		h.district = -1
	return h


func _ev(type: String, data: Dictionary) -> void:
	data.t = type
	events.append(data)


static func _r5(x: float) -> int:
	return int(round(x / 5.0)) * 5
