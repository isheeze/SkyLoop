extends SceneTree
## Headless test runner. Exits with code 1 if anything fails.
##   godot --headless --path . --script res://tools/test.gd            (fast suite)
##   godot --headless --path . --script res://tools/test.gd -- --balance  (adds the balance gate)

const Board = preload("res://core/board.gd")
const Game = preload("res://core/game.gd")
const Bot = preload("res://core/bot.gd")

var _failures: Array = []
var _checks := 0


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var tests := [
		"test_determinism", "test_save_restore_mid_game", "test_save_bytes_roundtrip",
		"test_rent_multipliers", "test_frozen_and_blackout", "test_debt_and_repayment",
		"test_takeover_rules", "test_level_caps", "test_steer_cost", "test_district_win",
		"test_bot_games_invariants",
	]
	if OS.get_cmdline_user_args().has("--balance"):
		tests.append("test_balance_gate")
	for name: String in tests:
		var before := _failures.size()
		call(name)
		print("%s %s" % ["PASS" if _failures.size() == before else "FAIL", name])
	print("%d checks, %d failures (%.1fs)" % [_checks, _failures.size(), (Time.get_ticks_msec() - t0) / 1000.0])
	for f: String in _failures:
		print("  - " + f)
	quit(1 if not _failures.is_empty() else 0)


func check(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failures.append(what)


# ---------------------------------------------------------------- helpers

func _cfg(seed: int, deeds := 2) -> Dictionary:
	var cfg := {"seed": seed, "deeds": deeds, "players": []}
	var ty := ["developer", "shark", "broker", "drifter"]
	for i in 4:
		cfg.players.append({"name": "P%d" % i, "tycoon": ty[i], "bot": true})
	return cfg


func _play(g, rng: RandomNumberGenerator, max_decisions := 100000) -> void:
	var n := 0
	while not g.over and n < max_decisions:
		var who: int = g.pending.player
		var persona: Dictionary = Bot.PERSONAS.values()[who % 3]
		var ok: bool = g.submit(Bot.decide(g, persona, rng))
		if not ok:
			_failures.append("bot made an illegal choice: %s" % g.pending)
			return
		g.events.clear()
		n += 1


## A 4-player game with no deeds and neutral headline modifiers, at player 0's first decision.
func _fresh(seed := 1):
	var g = Game.new(_cfg(seed, 0))
	g.mods = {"rent": 1.0, "build": 1.0, "salary": 1.0, "price": 1.0, "blackout": -1}
	return g


# ---------------------------------------------------------------- tests

func test_determinism() -> void:
	for seed in [3, 77, 1234]:
		var a = Game.new(_cfg(seed))
		var b = Game.new(_cfg(seed))
		var ra := RandomNumberGenerator.new()
		var rb := RandomNumberGenerator.new()
		ra.seed = seed
		rb.seed = seed
		_play(a, ra)
		_play(b, rb)
		check(a.to_dict() == b.to_dict(), "same seed and choices give the same game (seed %d)" % seed)


func test_save_restore_mid_game() -> void:
	var a = Game.new(_cfg(42))
	var ra := RandomNumberGenerator.new()
	ra.seed = 9
	_play(a, ra, 60)
	var snap: Dictionary = a.to_dict()
	var b = Game.from_dict(snap)
	check(b != null, "snapshot restores")
	check(b.to_dict() == snap, "restored game equals its snapshot")
	var rb := RandomNumberGenerator.new()
	rb.state = ra.state
	rb.seed = ra.seed
	rb.state = ra.state
	_play(a, ra)
	_play(b, rb)
	check(a.to_dict() == b.to_dict(), "restored game plays out identically")
	check(a.winner == b.winner and a.over and b.over, "both games finish with the same winner")


func test_save_bytes_roundtrip() -> void:
	var a = Game.new(_cfg(5))
	var r := RandomNumberGenerator.new()
	r.seed = 5
	_play(a, r, 40)
	var bytes := var_to_bytes(a.to_dict())
	var b = Game.from_dict(bytes_to_var(bytes))
	check(b != null and b.to_dict() == a.to_dict(), "snapshot survives var_to_bytes")
	var bad: Dictionary = a.to_dict()
	bad.version = 999
	check(Game.from_dict(bad) == null, "unknown save version is rejected")


func test_rent_multipliers() -> void:
	var g = _fresh()
	var tiles := Board.district_tiles(2)
	g.demand[2] = 2  # multiplier 1.0
	g.owner_of[tiles[0]] = 0  # the Developer: no rent bonus
	var one: int = g.rent_for(tiles[0])
	check(one == Game._r5(Board.TILES[tiles[0]].price * Board.RENT_RATE), "base rent at level 0, demand 2")
	g.owner_of[tiles[1]] = 0
	var two: int = g.rent_for(tiles[0])
	g.owner_of[tiles[2]] = 0
	var three: int = g.rent_for(tiles[0])
	check(two > one and three > two, "owning more of a district raises rent (%d < %d < %d)" % [one, two, three])
	g.level_of[tiles[0]] = 3
	check(g.rent_for(tiles[0]) > three * 4, "buildings multiply rent")
	g.demand[2] = 5
	var hot: int = g.rent_for(tiles[0])
	g.demand[2] = 0
	check(hot > g.rent_for(tiles[0]), "demand raises rent")


func test_frozen_and_blackout() -> void:
	var g = _fresh()
	var t: int = Board.district_tiles(1)[0]
	g.owner_of[t] = 2
	check(g.rent_for(t) > 0, "owned tile charges rent")
	g.players[2].frozen = true
	check(g.rent_for(t) == 0, "frozen owner collects nothing")
	g.players[2].frozen = false
	g.mods.blackout = 1
	check(g.rent_for(t) == 0, "blackout district collects nothing")


func test_debt_and_repayment() -> void:
	var g = _fresh()
	var p = g.players[1]
	p.cash = 100
	g._pay(1, 0, 300, "test")
	check(p.cash == 0, "payer is emptied")
	check(p.debt == int(ceil(200 * Board.DEBT_PENALTY)), "shortfall becomes debt with penalty")
	check(p.bailouts == 1, "bailout is counted")
	var debt: int = p.debt
	g._gain(1, 100)
	check(p.debt == debt - 100 and p.cash == 0, "income repays debt first")
	g._gain(1, 1000)
	check(p.debt == 0 and p.cash == 1000 - (debt - 100), "leftover income becomes cash")


func test_takeover_rules() -> void:
	var g = _fresh()
	var tiles := Board.district_tiles(3)
	g.owner_of[tiles[0]] = 1
	g.level_of[tiles[0]] = 2
	check(g.can_takeover(0, tiles[0]), "rival tile can be taken over")
	check(not g.can_takeover(1, tiles[0]), "own tile cannot be taken over")
	check(g.takeover_cost(0, tiles[0]) == Game._r5(g.tile_value(tiles[0]) * Board.TAKEOVER_MULT),
		"takeover costs double the tile value, buildings included")
	g.owner_of[tiles[1]] = 1
	g.owner_of[tiles[2]] = 1
	check(not g.can_takeover(0, tiles[0]), "a fully owned district is takeover-proof")


func test_level_caps() -> void:
	var g = _fresh()
	var tiles := Board.district_tiles(0)
	g.owner_of[tiles[0]] = 0
	g.level_of[tiles[0]] = Board.LEVEL_CAP[1]
	check(not g.can_upgrade(0, tiles[0]), "one tile of a district caps at level %d" % Board.LEVEL_CAP[1])
	g.owner_of[tiles[1]] = 0
	g.owner_of[tiles[2]] = 0
	g.level_of[tiles[0]] = Board.MAX_LEVEL
	check(g.can_upgrade(0, tiles[0]), "full district allows a landmark")
	g.level_of[tiles[1]] = Board.LANDMARK_LEVEL
	check(not g.can_upgrade(0, tiles[0]), "only one landmark per district")


func test_steer_cost() -> void:
	var g = _fresh()
	g.dice = [2, 5]
	g.turn = 0
	g.players[0].steer = 1
	g._ask_move()
	check(g.pending.free == [7], "the sum is the only free move")
	check(g.pending.options == [2, 5, 7], "single dice are offered while steer remains")
	g.submit({"steps": 2})
	check(g.players[0].steer == 0, "a single-die move spends a steer token")
	var h = _fresh(2)
	h.dice = [3, 4]
	h.players[0].steer = 0
	h._ask_move()
	check(h.pending.options == [7], "no steer means only the sum")


func test_district_win() -> void:
	var g = _fresh()
	for d in [0, 1]:
		for t: int in Board.district_tiles(d):
			g.owner_of[t] = 3
	var last := Board.district_tiles(2)
	g.owner_of[last[0]] = 3
	g.owner_of[last[1]] = 3
	check(not g.over, "two districts is not a win")
	g._set_owner(last[2], 3, 0, "test")
	check(g.over and g.winner == 3 and g.win_reason == "districts", "three full districts win at once")


func test_bot_games_invariants() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	for i in 150:
		var g = Game.new(_cfg(rng.randi()))
		_play(g, rng)
		check(g.over and g.winner >= 0, "game %d finishes" % i)
		for p in g.players:
			check(p.cash >= 0 and p.debt >= 0, "no negative money (game %d)" % i)
		for t in Board.TILE_COUNT:
			check(g.level_of[t] == 0 or g.owner_of[t] != -1, "no buildings on unowned tiles (game %d)" % i)
		for d in Board.DISTRICT_COUNT:
			var marks := 0
			for t: int in Board.district_tiles(d):
				if g.level_of[t] == Board.LANDMARK_LEVEL:
					marks += 1
			check(marks <= 1, "at most one landmark per district (game %d)" % i)


func test_balance_gate() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var wins := {}
	var games := {}
	var tycoons: Array = Board.TYCOONS.keys()
	for i in 1500:
		var cfg := {"seed": rng.randi(), "players": []}
		var order := tycoons.duplicate()
		for k in range(order.size() - 1, 0, -1):
			var j := rng.randi_range(0, k)
			var tmp = order[k]
			order[k] = order[j]
			order[j] = tmp
		for k in 4:
			cfg.players.append({"name": "P%d" % k, "tycoon": order[k], "bot": true})
		var g = Game.new(cfg)
		_play(g, rng)
		for k in 4:
			games[order[k]] = games.get(order[k], 0) + 1
		wins[g.players[g.winner].tycoon] = wins.get(g.players[g.winner].tycoon, 0) + 1
	for t: String in tycoons:
		var rate: float = 100.0 * wins.get(t, 0) / games[t]
		print("    %s %.1f%%" % [t, rate])
		check(rate >= 19.0 and rate <= 31.0, "%s win rate %.1f%% is within 19-31%%" % [t, rate])
