extends SceneTree
## Headless balance simulator: plays bot-only matches and prints aggregate stats.
##   godot --headless --path . --script res://tools/sim.gd -- --games 2000 --players 4 --rounds 12

const Board = preload("res://core/board.gd")
const Game = preload("res://core/game.gd")
const Bot = preload("res://core/bot.gd")


func _init() -> void:
	var games := 1000
	var n_players := 4
	var rounds := Board.ROUNDS
	var tier_rules := {}
	var args := OS.get_cmdline_user_args()
	for i in args.size() - 1:
		match args[i]:
			"--games":
				games = int(args[i + 1])
			"--players":
				n_players = int(args[i + 1])
			"--rounds":
				rounds = int(args[i + 1])
			"--tier":
				tier_rules = preload("res://core/economy.gd").TIERS[int(args[i + 1]) - 1].rules
	_rules = tier_rules
	_run(games, n_players, rounds)
	quit()


var _rules := {}


func _run(games: int, n_players: int, rounds: int) -> void:
	var tycoons: Array = Board.TYCOONS.keys()
	var personas: Array = Bot.PERSONAS.keys()
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345

	var seat_wins := []
	for i in n_players:
		seat_wins.append(0)
	var by_tycoon := {}
	var by_persona := {}
	var by_reason := {}
	var totals := {}
	var owned_frac := 0.0
	var max_level_sum := 0
	var bailouts := 0
	var margin_sum := 0.0
	var worth_sum := 0.0
	var cash_sum := 0.0
	var debt_sum := 0.0
	var close := 0
	var rounds_sum := 0
	var landmark_by_district := []
	var district_owned := []
	for d in Board.DISTRICT_COUNT:
		landmark_by_district.append(0)
		district_owned.append(0)
	var t0 := Time.get_ticks_msec()

	for gi in games:
		var cfg := {"seed": rng.randi(), "rounds": rounds, "players": [], "rules": _rules}
		var pers := []
		for i in n_players:
			var ty: String = tycoons[rng.randi_range(0, tycoons.size() - 1)]
			var pe: String = personas[rng.randi_range(0, personas.size() - 1)]
			cfg.players.append({"name": "P%d" % i, "tycoon": ty, "bot": true})
			pers.append(pe)
		var g := Game.new(cfg)
		var guard := 0
		while not g.over:
			guard += 1
			if guard > 20000:
				push_error("game %d did not terminate" % gi)
				break
			var who: int = g.pending.player
			var choice := Bot.decide(g, Bot.PERSONAS[pers[who]], rng)
			if not g.submit(choice):
				push_error("illegal bot choice %s for %s" % [choice, g.pending])
				break
			g.events.clear()
		_check(g)

		seat_wins[g.winner] += 1
		for i in n_players:
			_tally(by_tycoon, g.players[i].tycoon, i == g.winner)
			_tally(by_persona, pers[i], i == g.winner)
			bailouts += g.players[i].bailouts
			worth_sum += g.net_worth(i)
			cash_sum += g.players[i].cash
			debt_sum += g.players[i].debt
		by_reason[g.win_reason] = by_reason.get(g.win_reason, 0) + 1
		for k: String in g.stats:
			totals[k] = totals.get(k, 0) + g.stats[k]
		rounds_sum += g.round_no
		var owned := 0
		var top := 0
		for t in Board.TILE_COUNT:
			if g.owner_of[t] != -1:
				owned += 1
			top = maxi(top, g.level_of[t])
		owned_frac += owned / 21.0
		max_level_sum += top
		for d in Board.DISTRICT_COUNT:
			if g.landmark_owner(d) != -1:
				landmark_by_district[d] += 1
			for i in n_players:
				if g.owns_district(i, d):
					district_owned[d] += 1
		var worths := []
		for i in n_players:
			worths.append(g.net_worth(i))
		worths.sort()
		var first: float = worths[-1]
		var second: float = worths[-2]
		margin_sum += (first - second) / maxf(1.0, first)
		if first - second <= first * 0.1:
			close += 1

	var gf := float(games)
	print("=== Skyloop sim: %d games, %d players, %d rounds (%.1fs) ===" % [
		games, n_players, rounds, (Time.get_ticks_msec() - t0) / 1000.0])
	print("Seat win %:      ", _pct_list(seat_wins, gf))
	print("Tycoon win %:    ", _rates(by_tycoon))
	print("Persona win %:   ", _rates(by_persona))
	print("Win reason:      ", by_reason)
	print("Avg rounds played: %.1f   avg decisions/game: %.0f" % [rounds_sum / gf, totals.decisions / gf])
	print("Tiles owned at end: %.0f%%   avg top level: %.2f   landmarks/game: %.2f" % [
		owned_frac / gf * 100.0, max_level_sum / gf, totals.landmarks / gf])
	print("Per game: buys %.1f  auctions %.1f (sold %.1f)  takeovers %.2f  upgrades %.1f  bailouts %.2f" % [
		totals.buys / gf, totals.auctions / gf, totals.auction_sales / gf, totals.takeovers / gf,
		totals.upgrades / gf, bailouts / gf])
	print("Avg final cash: %.0f  debt: %.0f" % [cash_sum / gf / n_players, debt_sum / gf / n_players])
	print("Rent paid/game: %.0f   lead changes/game: %.1f" % [totals.rent / gf, totals.lead_changes / gf])
	print("Avg final net worth: %.0f   winner margin: %.0f%%   close finishes (<=10%%): %.0f%%" % [
		worth_sum / gf / n_players, margin_sum / gf * 100.0, close / gf * 100.0])
	print("Full districts per game by district: ", _pct_list(district_owned, gf * 100.0))
	print("Landmark built % by district:    ", _pct_list(landmark_by_district, gf))


func _tally(d: Dictionary, key: String, won: bool) -> void:
	if not d.has(key):
		d[key] = [0, 0]
	d[key][0] += 1
	if won:
		d[key][1] += 1


func _rates(d: Dictionary) -> String:
	var parts := []
	var keys := d.keys()
	keys.sort()
	for k: String in keys:
		parts.append("%s %.1f" % [k, 100.0 * d[k][1] / maxf(1.0, d[k][0])])
	return ", ".join(parts)


func _pct_list(a: Array, total: float) -> String:
	var parts := []
	for v: int in a:
		parts.append("%.1f" % (100.0 * v / total))
	return " ".join(parts)


## Invariants that must hold in every finished game.
func _check(g) -> void:
	for p in g.players:
		assert(p.cash >= 0, "negative cash")
		assert(p.debt >= 0, "negative debt")
	for t in Board.TILE_COUNT:
		assert(g.level_of[t] >= 0 and g.level_of[t] <= Board.LANDMARK_LEVEL, "level out of range")
		assert(g.level_of[t] == 0 or g.owner_of[t] != -1, "building on unowned tile")
		assert(g.is_property(t) or g.owner_of[t] == -1, "non-property owned")
	for d in Board.DISTRICT_COUNT:
		var marks := 0
		for t: int in Board.district_tiles(d):
			if g.level_of[t] == Board.LANDMARK_LEVEL:
				marks += 1
		assert(marks <= 1, "two landmarks in a district")
	assert(g.winner >= 0, "no winner")
