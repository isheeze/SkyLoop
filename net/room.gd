extends RefCounted
## One match on the backend: owns the authoritative Game, seats (people or bots), turn
## timers and the update/ack rhythm that keeps every client's animations in step.
##
## Rhythm: after every state change the room broadcasts an update and waits until each
## connected person has acked it (their animations finished) or ACK_TIMEOUT passes. Only then
## does the next actor start thinking: a bot after a human-like pause, a person against a
## TURN_TIME deadline. A person who times out twice, or disconnects, is played by a bot until
## they act again.

const Game = preload("res://core/game.gd")
const Bot = preload("res://core/bot.gd")
const Board = preload("res://core/board.gd")
const Economy = preload("res://core/economy.gd")

const TURN_TIME := 20.0
const ACK_TIMEOUT := 10.0
const QUICK_CHAT := ["Nice move!", "Oops!", "Hurry up!", "Thanks!", "Good game!", "Wow!", "My street!", "Lucky!"]

var id := 0
var tier := 1  # 0 = practice
var seats: Array = []  # {kind, token, peer, name, avatar, level, country, tycoon, persona, away, timeouts}
var g
var over := false
var stats: Array = []  # per seat match stats for missions

var _backend
var _rng := RandomNumberGenerator.new()
var _phase := "ack"  # ack | think | done
var _acks := {}
var _timer := 0.0
var _actor := -1


func _init(backend, room_id: int, room_tier: int, seat_list: Array, seed: int) -> void:
	_backend = backend
	id = room_id
	tier = room_tier
	seats = seat_list
	_rng.seed = seed
	var cfg := {"seed": seed, "players": [], "rounds": 12 if tier > 0 else 8}
	if tier > 0:
		cfg.rules = Economy.TIERS[tier - 1].rules
	for s: Dictionary in seats:
		# Nobody's seat is marked as a bot in the shared game state.
		cfg.players.append({"name": s.name, "tycoon": s.tycoon, "bot": false})
		stats.append({"rent_in": 0, "builds": 0, "landmarks": 0, "auctions_won": 0, "takeovers": 0,
			"jackpots": 0, "buys": 0})
	g = Game.new(cfg)


# ---------------------------------------------------------------- outbound

func players_meta() -> Array:
	var out := []
	for s: Dictionary in seats:
		out.append({"name": s.name, "avatar": s.avatar, "level": s.level, "country": s.country,
			"tycoon": s.tycoon, "ai": tier == 0 and s.kind == "bot"})
	return out


## The game state with everything a client must not know removed: the dice seed, the
## headline deck order and sealed bids.
func public_snapshot() -> Dictionary:
	var d: Dictionary = g.to_dict()
	d.rng_seed = 0
	d.rng_state = 0
	d._deck = []
	if d._auction is Dictionary and d._auction.has("bids"):
		d._auction = d._auction.duplicate(true)
		d._auction.bids = {}
	return d


func start() -> void:
	for i in seats.size():
		if seats[i].kind == "human":
			_send(i, {"t": "match_start", "room": id, "seat": i, "tier": tier, "players": players_meta(),
				"snapshot": public_snapshot(), "events": g.events.duplicate(true), "pending": g.pending})
	_count_events(g.events)
	g.events.clear()
	_wait_acks()


## Re-sends the whole match to a person who reconnected.
func resync(seat: int) -> void:
	_send(seat, {"t": "match_start", "room": id, "seat": seat, "tier": tier, "players": players_meta(),
		"snapshot": public_snapshot(), "events": [], "pending": g.pending})
	if _phase == "think" and _actor == seat:
		_send(seat, {"t": "deadline", "seconds": maxf(5.0, _timer)})


func _broadcast_update() -> void:
	var events: Array = g.events.duplicate(true)
	_count_events(events)
	g.events.clear()
	var msg := {"t": "update", "room": id, "snapshot": public_snapshot(), "events": events, "pending": g.pending}
	for i in seats.size():
		if seats[i].kind == "human":
			_send(i, msg)
	_wait_acks()


func _send(seat: int, msg: Dictionary) -> void:
	var s: Dictionary = seats[seat]
	if s.kind == "human" and s.peer >= 0:
		_backend.send(s.peer, msg)


func broadcast(msg: Dictionary) -> void:
	for i in seats.size():
		_send(i, msg)


# ---------------------------------------------------------------- inbound

func on_ack(seat: int) -> void:
	_acks.erase(seat)


func on_choice(seat: int, choice: Dictionary) -> void:
	if over or g.pending.is_empty() or int(g.pending.player) != seat:
		return
	seats[seat].away = false
	seats[seat].timeouts = 0
	if not g.submit(choice):
		_send(seat, {"t": "error", "msg": "illegal choice"})
		return
	_after_change()


func on_disconnect(seat: int) -> void:
	seats[seat].peer = -1
	seats[seat].away = true
	_acks.erase(seat)


func on_reconnect(seat: int, peer: int) -> void:
	seats[seat].peer = peer
	seats[seat].away = false
	seats[seat].timeouts = 0
	resync(seat)


# ---------------------------------------------------------------- clock

func tick(delta: float) -> void:
	if over:
		return
	_timer -= delta
	match _phase:
		"ack":
			if _acks.is_empty() or _timer <= 0.0:
				_begin_think()
		"think":
			if _timer <= 0.0:
				_act_for(_actor)


func _wait_acks() -> void:
	_acks.clear()
	for i in seats.size():
		if seats[i].kind == "human" and seats[i].peer >= 0:
			_acks[i] = true
	_phase = "ack"
	_timer = ACK_TIMEOUT


func _begin_think() -> void:
	if g.over:
		_finish()
		return
	_actor = int(g.pending.player)
	var s: Dictionary = seats[_actor]
	_phase = "think"
	if s.kind == "bot" or s.away:
		_timer = _think_time(g.pending.type)
	else:
		_timer = TURN_TIME
		broadcast({"t": "deadline", "seat": _actor, "seconds": TURN_TIME})


## How long a person would take for this kind of decision.
func _think_time(kind: String) -> float:
	match kind:
		"move":
			return _rng.randf_range(1.0, 2.6)
		"bid":
			return _rng.randf_range(1.4, 3.6)
		"buy", "takeover", "audit":
			return _rng.randf_range(0.9, 2.2)
		"manage":
			return _rng.randf_range(0.7, 1.8)
	return _rng.randf_range(0.8, 1.8)


func _act_for(seat: int) -> void:
	var s: Dictionary = seats[seat]
	if s.kind == "human" and not s.away:
		s.timeouts += 1
		if s.timeouts >= 2:
			s.away = true
	var persona: Dictionary = Bot.PERSONAS[s.persona]
	var choice := Bot.decide(g, persona, _rng)
	if not g.submit(choice):
		g.submit({"a": "end"} if g.pending.type == "manage" else {"bid": 0})
	_maybe_chat(seat)
	_after_change()


func _after_change() -> void:
	_broadcast_update()


## Bots occasionally use quick chat, like people do.
func _maybe_chat(seat: int) -> void:
	if seats[seat].kind != "bot" or _rng.randf() > 0.06:
		return
	broadcast({"t": "chat", "seat": seat, "text": QUICK_CHAT[_rng.randi_range(0, QUICK_CHAT.size() - 1)]})


# ---------------------------------------------------------------- stats and results

func _count_events(events: Array) -> void:
	for ev: Dictionary in events:
		match ev.t:
			"pay":
				if ev.why == "rent" and int(ev.to) >= 0:
					stats[ev.to].rent_in += int(ev.amount)
				if ev.why == "jackpot" and int(ev.to) >= 0:
					stats[ev.to].jackpots += 1
			"build":
				stats[ev.p].builds += 1
				if int(ev.level) == Board.LANDMARK_LEVEL:
					stats[ev.p].landmarks += 1
			"own":
				match ev.how:
					"auction":
						stats[ev.p].auctions_won += 1
					"takeover":
						stats[ev.p].takeovers += 1
					"buy":
						stats[ev.p].buys += 1


func standings() -> Array:
	var order := range(seats.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		if a == g.winner:
			return true
		if b == g.winner:
			return false
		return g.net_worth(a) > g.net_worth(b))
	return order


func _finish() -> void:
	over = true
	_phase = "done"
	var order := standings()
	var table := []
	for place in order.size():
		var i: int = order[place]
		table.append({"seat": i, "name": seats[i].name, "avatar": seats[i].avatar, "worth": g.net_worth(i)})
	for place in order.size():
		var i: int = order[place]
		if seats[i].kind != "human":
			continue
		var rewards: Dictionary = _backend.award(seats[i].token, tier, place, stats[i])
		var msg := {"t": "match_end", "room": id, "tier": tier, "standings": table, "place": place,
			"rewards": rewards, "reason": g.win_reason}
		if seats[i].peer >= 0:
			msg.profile = _backend.public_profile(seats[i].token)
			_send(i, msg)
		else:
			# They left before the end: show them the result when they come back.
			_backend.hold_result(seats[i].token, msg)
	_backend.close_room(id)
