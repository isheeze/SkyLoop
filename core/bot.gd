extends RefCounted
## Heuristic opponents. `decide` returns a legal choice for the game's pending decision.

const Board = preload("res://core/board.gd")

const PERSONAS := {
	"banker": {"label": "Cautious", "reserve": 1.0, "bid": 0.85, "build": 1.0, "takeover": 0.3},
	"builder": {"label": "Builder", "reserve": 0.6, "bid": 1.0, "build": 0.5, "takeover": 0.6},
	"raider": {"label": "Raider", "reserve": 0.35, "bid": 1.2, "build": 0.8, "takeover": 1.0},
}


static func decide(g, persona: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var pd: Dictionary = g.pending
	var pi: int = pd.player
	match pd.type:
		"move":
			return _move(g, pi, pd, persona)
		"metro":
			var best: int = pd.options[0]
			var best_v := -INF
			for s: int in pd.options:
				var v := _dest_value(g, pi, s)
				if v > best_v:
					best_v = v
					best = s
			return {"steps": best}
		"perk":
			return {"perk": _perk(g, pi, persona)}
		"buy":
			return {"buy": _wants_buy(g, pi, pd, persona)}
		"bid":
			return {"bid": _bid(g, pi, pd, persona, rng)}
		"audit":
			var loss := 0.0
			for t in Board.TILE_COUNT:
				if g.owner_of[t] == pi:
					loss += g.rent_for(t) * (g.players.size() - 1) * 0.07
			var cash: int = g.players[pi].cash
			return {"pay": loss > pd.fee * 0.8 and cash - pd.fee >= _reserve(g, pi, persona) * 0.5}
		"takeover":
			return {"accept": _wants_takeover(g, pi, pd, persona)}
		"manage":
			return _manage(g, pi, pd, persona)
	return {}


## Largest rent this player could be hit with right now.
static func _danger(g, pi: int) -> int:
	var worst := 0
	for t in Board.TILE_COUNT:
		var o: int = g.owner_of[t]
		if o != -1 and o != pi:
			worst = maxi(worst, g.rent_for(t))
	return worst


static func _reserve(g, pi: int, persona: Dictionary) -> float:
	return maxf(50.0, _danger(g, pi) * persona.reserve)


static func _rival_max_count(g, pi: int, d: int) -> int:
	var worst := 0
	for i in g.players.size():
		if i != pi:
			worst = maxi(worst, g.district_count(i, d))
	return worst


static func _tile_value(g, pi: int, tile: int) -> float:
	var t: Dictionary = Board.TILES[tile]
	var p = g.players[pi]
	match t.kind:
		Board.Kind.PROPERTY:
			var o: int = g.owner_of[tile]
			var d: int = t.district
			var own: int = g.district_count(pi, d)
			if o == -1:
				var price: int = g.price_for(pi, tile)
				if p.cash < price:
					return 10.0
				var v := price * 0.3 + own * price * 0.4
				if own == 2:
					v += 300.0
				if _rival_max_count(g, pi, d) == 2:
					v += price * 0.3
				return v
			if o == pi:
				return 5.0
			var rent: float = g.rent_for(tile)
			if p.shield:
				rent *= 0.5
			var v := -rent
			if own == 2 and g.can_takeover(pi, tile) and p.cash >= g.takeover_cost(pi, tile) + rent:
				v += 250.0
			return v
		Board.Kind.JACKPOT:
			return float(g.pot)
		Board.Kind.TAX_RAID:
			return -p.cash * Board.TAX_RAID_RATE
		Board.Kind.AUDIT:
			return -50.0
		Board.Kind.METRO:
			return 25.0
		Board.Kind.WINDFALL:
			return 40.0 + 10.0 * g.round_no
		Board.Kind.PERMIT_OFFICE:
			return 40.0
	return 0.0


static func _dest_value(g, pi: int, steps: int) -> float:
	var from: int = g.players[pi].pos
	var v := _tile_value(g, pi, (from + steps) % Board.TILE_COUNT)
	if from + steps >= Board.TILE_COUNT:
		v += 60.0
	return v


static func _move(g, pi: int, pd: Dictionary, persona: Dictionary) -> Dictionary:
	# A steer token is worth holding unless the detour clearly pays for itself.
	var steer_cost := 25.0 if pd.steer >= g.steer_max(g.players[pi]) else 45.0
	var best: int = pd.free[0]
	var best_v := -INF
	for s: int in pd.options:
		var v := _dest_value(g, pi, s)
		if not pd.free.has(s):
			v -= steer_cost
		if v > best_v:
			best_v = v
			best = s
	if pd.can_shortcut:
		var jump := -1
		var jump_v := -INF
		for t in Board.TILE_COUNT:
			if t == g.players[pi].pos or not g.is_property(t):
				continue
			var v := _tile_value(g, pi, t)
			if v > jump_v:
				jump_v = v
				jump = t
		var late: bool = g.round_no >= g.rounds - 1
		if jump_v >= 250.0 or (late and jump_v > best_v + 40.0):
			return {"shortcut": jump}
	return {"steps": best}


static func _perk(g, pi: int, persona: Dictionary) -> String:
	var p = g.players[pi]
	if not p.permit:
		for t in Board.TILE_COUNT:
			if g.can_upgrade(pi, t) and p.cash >= Board.upgrade_base_cost(t) * 0.5 \
					and Board.upgrade_base_cost(t) >= 2 * Board.PERK_CASH:
				return "permit"
	if not p.shield and _danger(g, pi) > 2 * Board.PERK_CASH:
		return "shield"
	return "cash"


static func _wants_buy(g, pi: int, pd: Dictionary, persona: Dictionary) -> bool:
	var d: int = Board.TILES[pd.tile].district
	if g.round_no <= 5 or g.district_count(pi, d) >= 1 or _rival_max_count(g, pi, d) == 2:
		return true
	return g.players[pi].cash - pd.price >= _reserve(g, pi, persona)


static func _bid(g, pi: int, pd: Dictionary, persona: Dictionary, rng: RandomNumberGenerator) -> int:
	var t: Dictionary = Board.TILES[pd.tile]
	var d: int = t.district
	var value: float = t.price * 0.9
	value += t.price * 0.35 * g.district_count(pi, d)
	if _rival_max_count(g, pi, d) == 2:
		value += t.price * 0.25
	value *= persona.bid
	var budget: float = pd.max_bid - _reserve(g, pi, persona) * 0.3
	var bid := int(minf(budget, value * rng.randf_range(0.7, 1.0)) / 5.0) * 5
	if bid >= pd.min_bid:
		return mini(bid, pd.max_bid)
	if value >= pd.min_bid and budget >= pd.min_bid:
		return pd.min_bid
	return 0


static func _wants_takeover(g, pi: int, pd: Dictionary, persona: Dictionary) -> bool:
	var d: int = Board.TILES[pd.tile].district
	var left: float = g.players[pi].cash - pd.cost
	if g.district_count(pi, d) == 2:
		return true
	var reserve := _reserve(g, pi, persona)
	if g.district_count(g.owner_of[pd.tile], d) == 2:
		return left >= reserve and persona.takeover >= 0.6
	return persona.takeover >= 0.6 and g.district_count(pi, d) >= 1 and left >= reserve * 1.5


static func _manage(g, pi: int, pd: Dictionary, persona: Dictionary) -> Dictionary:
	var p = g.players[pi]
	var power := _pick_power(g, pi, pd, persona)
	if not power.is_empty():
		return power
	var reserve := _reserve(g, pi, persona) * float(persona.build)
	var best := {}
	var best_roi := 0.0
	for act: Dictionary in pd.actions:
		if act.a != "upgrade" or p.cash - act.cost < reserve:
			continue
		var roi := _upgrade_gain(g, pi, act.tile) / maxf(1.0, act.cost)
		if roi > best_roi:
			best_roi = roi
			best = act
	if not best.is_empty():
		return best
	return {"a": "end"}


## Extra rent per visit that the next level on this tile would bring.
static func _upgrade_gain(g, pi: int, tile: int) -> float:
	var t: Dictionary = Board.TILES[tile]
	var lvl: int = g.level_of[tile]
	var gain: float = t.price * Board.RENT_RATE * (Board.LEVEL_MULT[lvl + 1] - Board.LEVEL_MULT[lvl])
	gain *= Board.DISTRICT_MULT[g.district_count(pi, t.district)]
	if lvl + 1 == Board.LANDMARK_LEVEL:
		gain *= 1.5
	return gain


static func _pick_power(g, pi: int, pd: Dictionary, persona: Dictionary) -> Dictionary:
	var p = g.players[pi]
	if p.power_used:
		return {}
	var half: bool = g.round_no * 2 >= g.rounds
	match p.tycoon:
		"developer":
			var best := {}
			var best_cost := 0
			for act: Dictionary in pd.actions:
				if act.a == "power":
					var c := Board.upgrade_base_cost(act.tile)
					if c > best_cost:
						best_cost = c
						best = act
			if best_cost >= 90 or (half and best_cost > 0):
				return best
		"shark":
			var top := 0
			for t in Board.TILE_COUNT:
				if g.owner_of[t] == pi:
					top = maxi(top, g.rent_for(t))
			if top >= 100 or (g.round_no >= g.rounds - 3 and top > 0):
				return {"a": "power"}
		"broker":
			var best := {}
			var best_s := 0.0
			for act: Dictionary in pd.actions:
				if act.a != "power":
					continue
				var s := _swap_score(g, pi, act)
				if s > best_s:
					best_s = s
					best = act
			if best_s >= 150.0 or (g.round_no >= g.rounds - 2 and best_s > 0.0):
				return best
	return {}


static func _swap_score(g, pi: int, act: Dictionary) -> float:
	var give_t: Dictionary = Board.TILES[act.give]
	var take_t: Dictionary = Board.TILES[act.take]
	var rival: int = g.owner_of[act.take]
	if give_t.district == take_t.district:
		return 0.0
	var s: float = take_t.price - give_t.price
	var mine: int = g.district_count(pi, take_t.district)
	s += mine * 100.0
	if mine == 2:
		s += 1000.0
	s -= (g.district_count(pi, give_t.district) - 1) * 100.0
	if g.district_count(rival, give_t.district) == 2:
		s -= 1000.0
	if g.owns_district(rival, take_t.district):
		s += 200.0
	return s
