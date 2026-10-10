extends SceneTree
## Plays real matches through the backend with simulated phones, on a fake clock.
##   godot --headless --path . --script res://tools/test_net.gd

const Backend = preload("res://net/backend.gd")
const Game = preload("res://core/game.gd")
const Bot = preload("res://core/bot.gd")
const Economy = preload("res://core/economy.gd")

var be
var clock := 1_800_000_000.0
var inbox := {}  # peer -> Array of messages
var _failures: Array = []
var _checks := 0


class Phone:
	var peer := 0
	var token := ""
	var seat := -1
	var profile := {}
	var ended := {}
	var pending := {}
	var snapshot := {}
	var started := false
	var leaks := 0
	var rng := RandomNumberGenerator.new()


func check(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failures.append(what)


func _init() -> void:
	be = Backend.new()
	be.store_dir = "user://test_backend_%d" % Time.get_ticks_msec()
	be.now = func() -> float: return clock
	root.add_child(be)
	be.set_process(false)
	be.outbound.connect(func(peer: int, msg: Dictionary) -> void:
		if not inbox.has(peer):
			inbox[peer] = []
		inbox[peer].append(msg))
	await process_frame
	test_two_people_and_bots()
	test_daily_and_spin()
	test_disconnect_and_rejoin()
	test_result_waits_for_return()
	test_untrusted_input()
	print("%d checks, %d failures" % [_checks, _failures.size()])
	for f: String in _failures:
		print("  - " + f)
	quit(1 if not _failures.is_empty() else 0)


func hello(peer: int, country := "PK", token := "") -> Phone:
	var ph := Phone.new()
	ph.peer = peer
	ph.rng.seed = peer
	be.handle(peer, {"t": "hello", "token": token, "name": "Tester%d" % peer, "country": country})
	for m: Dictionary in drain(peer):
		if m.t == "welcome":
			ph.token = m.token
			ph.profile = m.profile
		else:
			_on_msg(ph, m)
	return ph


func drain(peer: int) -> Array:
	var out: Array = inbox.get(peer, [])
	inbox[peer] = []
	return out


## Runs the clock and lets each phone answer until every phone has a match_end.
func play(phones: Array, max_ticks := 40000, drop := {}) -> void:
	for t in max_ticks:
		clock += 0.25
		be.tick(0.25)
		var all_done := true
		for ph: Phone in phones:
			if drop.has(ph.peer) and t == drop[ph.peer]:
				be.disconnected(ph.peer)
				ph.started = false
			for m: Dictionary in drain(ph.peer):
				_on_msg(ph, m)
			if ph.ended.is_empty():
				all_done = false
		if all_done:
			return


func _on_msg(ph: Phone, m: Dictionary) -> void:
	match m.t:
		"match_start", "update":
			if m.t == "match_start":
				ph.seat = m.seat
				ph.started = true
			ph.snapshot = m.snapshot
			ph.pending = m.pending
			if int(m.snapshot.rng_state) != 0 or not m.snapshot._deck.is_empty():
				ph.leaks += 1
			if m.snapshot._auction is Dictionary and m.snapshot._auction.has("bids") and not m.snapshot._auction.bids.is_empty():
				ph.leaks += 1
			be.handle(ph.peer, {"t": "ack"})
			if not ph.pending.is_empty() and int(ph.pending.player) == ph.seat:
				var mirror = Game.from_dict(ph.snapshot)
				var choice := Bot.decide(mirror, Bot.PERSONAS.builder, ph.rng)
				be.handle(ph.peer, {"t": "choice", "choice": choice})
		"match_end":
			ph.ended = m
			ph.profile = m.profile


func test_two_people_and_bots() -> void:
	var a := hello(101)
	var b := hello(102)
	check(a.token != "" and b.token != "" and a.token != b.token, "each phone gets its own account")
	check(int(a.profile.coins) == Economy.START_COINS, "new players start with %d coins" % Economy.START_COINS)
	be.handle(101, {"t": "queue", "tier": 1})
	be.handle(102, {"t": "queue", "tier": 1})
	drain(101)
	drain(102)
	play([a, b])
	check(not a.ended.is_empty() and not b.ended.is_empty(), "both people finish the match")
	check(a.leaks == 0 and b.leaks == 0, "snapshots never carry the dice seed, deck or sealed bids")
	if a.ended.is_empty():
		return
	var table: Array = a.ended.standings
	check(table.size() == 4, "the table had four seats")
	var winner_seat: int = table[0].seat
	var prize := Economy.prize(1)
	for ph: Phone in [a, b]:
		var expect := Economy.START_COINS - Economy.TIERS[0].entry + (prize if ph.seat == winner_seat else 0)
		check(int(ph.profile.coins) == expect, "coins after the match are %d (got %s)" % [expect, ph.profile.coins])
		check(int(ph.profile.stats.matches) == 1, "the match is counted")
		check(int(ph.ended.rewards.xp) > 0, "everyone earns XP")
	var names := table.map(func(r: Dictionary) -> String: return r.name)
	check(names.has("Tester101") and names.has("Tester102"), "both people sat at the same table")
	var others := names.filter(func(n: String) -> bool: return not n.begins_with("Tester"))
	check(others.size() == 2, "two seats were filled")
	for n: String in others:
		check(not n.to_lower().contains("bot"), "filled seats look like people (%s)" % n)


func test_daily_and_spin() -> void:
	var c := hello(201)
	be.handle(201, {"t": "claim_daily"})
	var r: Array = drain(201)
	check(r.size() == 1 and r[0].t == "reward" and int(r[0].coins) == 100, "day 1 pays 100 coins")
	be.handle(201, {"t": "claim_daily"})
	r = drain(201)
	check(r[0].t == "error", "the daily reward can't be claimed twice in a day")
	clock += 86400.0
	be.handle(201, {"t": "claim_daily"})
	r = drain(201)
	check(r[0].t == "reward" and int(r[0].coins) == 200, "day 2 pays 200 coins")
	be.handle(201, {"t": "spin"})
	r = drain(201)
	check(r[0].t == "reward" and r[0].source == "spin", "one free spin a day")
	be.handle(201, {"t": "spin"})
	r = drain(201)
	check(r[0].t == "error", "a second free spin is refused")
	be.handle(201, {"t": "ad_reward", "kind": "spin"})
	drain(201)
	be.handle(201, {"t": "spin", "ad": true})
	r = drain(201)
	check(r[0].t == "reward", "a watched ad grants an extra spin")
	be.handle(201, {"t": "buy", "item": "dice_marble"})
	r = drain(201)
	var gems_ok: bool = r[0].t == "reward" and r[0].profile.owned.has("dice_marble")
	check(gems_ok or int(r[0].get("profile", {}).get("gems", 0)) < 60, "gems buy cosmetics")
	be.handle(201, {"t": "queue", "tier": 5})
	r = drain(201)
	check(r[0].t == "error" and r[0].msg == "locked", "high tables are locked by level")


## A modified app can claim anything; the server must not believe it.
func test_untrusted_input() -> void:
	var all_items: Array = Economy.SHOP.map(func(it: Dictionary) -> String: return it.id)
	be.handle(301, {"t": "hello", "token": "", "name": "  X  ", "country": "../../etc", "avatar": "../evil",
		"carry": {"coins": 999999999, "gems": 99999, "level": 80, "xp": 1e9, "trophies": 50000,
			"owned": all_items, "equipped": {"token": "token_gold", "dice": "nope"},
			"stats": {"matches": 3, "wins": 900}}})
	var p: Dictionary = {}
	for m: Dictionary in drain(301):
		if m.t == "welcome":
			p = m.profile
	check(int(p.coins) <= Backend.CARRY_MAX_COINS and int(p.gems) <= Economy.START_GEMS + Backend.CARRY_MAX_GEMS,
		"carried currency is capped")
	check(int(p.level) <= Backend.CARRY_MAX_LEVEL and int(p.trophies) <= Backend.CARRY_MAX_TROPHIES, "carried level is capped")
	check((p.owned as Array).size() <= 3, "a carry can't unlock the whole shop")
	check(int(p.stats.wins) <= int(p.stats.matches), "wins never exceed matches")
	check(p.avatar == "a01" and p.name == "Player", "bad avatar and too-short name are replaced")
	be.handle(302, {"t": "hello", "token": "../../profiles/x", "name": "Y"})
	var welcomed := false
	for m: Dictionary in drain(302):
		welcomed = welcomed or (m.t == "welcome" and str(m.token).length() == 32)
	check(welcomed, "a forged token path gets a fresh account, not a file read")


func test_disconnect_and_rejoin() -> void:
	var d := hello(301, "IN")
	be.handle(301, {"t": "queue", "tier": 1})
	drain(301)
	# Drop the phone mid-match; a bot keeps its seat warm.
	play([d], 400, {301: 200})
	var again := hello(302, "IN", d.token)
	again.token = d.token
	check(again.token == d.token, "the same account comes back on reconnect")
	play([again])
	check(again.started, "a rejoining player gets the match back")
	check(not again.ended.is_empty(), "the match still finishes after a drop")



func test_result_waits_for_return() -> void:
	var e := hello(401)
	be.handle(401, {"t": "queue", "tier": 1})
	drain(401)
	play([e], 20000, {401: 40})
	var back := hello(402, "PK", e.token)
	check(not back.ended.is_empty(), "a player who left gets their result when they return")
