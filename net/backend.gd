extends Node
## The Skyloop game service: accounts, wallet, daily rewards, spin, missions, shop,
## matchmaking, match rooms and leaderboards. The same node runs inside the app (offline, one
## local player) and on the dedicated server (server/server.gd), so both behave identically.
## Transports call `handle(peer, msg)` / `disconnected(peer)` and deliver what `send` emits.

signal outbound(peer: int, msg: Dictionary)

const Economy = preload("res://core/economy.gd")
const Board = preload("res://core/board.gd")
const Room = preload("res://net/room.gd")
const Names = preload("res://net/names.gd")
const Bot = preload("res://core/bot.gd")

const PROTOCOL := 1

## Where profiles are stored. The app uses user://, the server sets an absolute folder.
var store_dir := "user://backend"
## Seconds a queue waits for people before the remaining seats are filled.
var queue_wait_min := 4.0
var queue_wait_max := 9.0
## Returns the current unix time; tests swap it to travel in time.
var now := func() -> float: return Time.get_unix_time_from_system()

var _profiles := {}  # token -> profile
var _peer_token := {}  # peer -> token
var _token_peer := {}  # token -> peer
var _queues := {}  # tier -> [{token, since, wait}]
var _rooms := {}  # room id -> Room
var _token_room := {}  # token -> room id
var _next_room := 1
var _rng := RandomNumberGenerator.new()
var _board_cache := {}
var _board_time := -1000.0


func _ready() -> void:
	_rng.randomize()
	DirAccess.make_dir_recursive_absolute(store_dir.path_join("profiles"))


func _process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	_tick_queues()
	for r in _rooms.values().duplicate():
		r.tick(delta)


func send(peer: int, msg: Dictionary) -> void:
	outbound.emit(peer, msg)


# ---------------------------------------------------------------- protocol

func handle(peer: int, msg: Dictionary) -> void:
	var t: String = msg.get("t", "")
	if t == "hello":
		_hello(peer, msg)
		return
	var token: String = _peer_token.get(peer, "")
	if token == "":
		send(peer, {"t": "error", "msg": "say hello first"})
		return
	match t:
		"profile":
			send(peer, {"t": "profile", "profile": public_profile(token)})
		"set_name":
			var p := _profile(token)
			p.name = _clean_name(str(msg.get("name", p.name)))
			_save(token)
			send(peer, {"t": "profile", "profile": public_profile(token)})
		"set_avatar":
			var av := str(msg.get("avatar", ""))
			if Names.AVATARS.has(av):
				_profile(token).avatar = av
				_save(token)
			send(peer, {"t": "profile", "profile": public_profile(token)})
		"claim_daily":
			_claim_daily(peer, token)
		"spin":
			_spin(peer, token, bool(msg.get("ad", false)))
		"claim_mission":
			_claim_mission(peer, token, str(msg.get("id", "")))
		"buy":
			_buy(peer, token, str(msg.get("item", "")))
		"equip":
			_equip(peer, token, str(msg.get("item", "")))
		"ad_reward":
			_ad_reward(peer, token, str(msg.get("kind", "")))
		"queue":
			_queue(peer, token, int(msg.get("tier", 1)))
		"cancel_queue":
			_leave_queues(token)
			send(peer, {"t": "queue_cancelled"})
		"practice":
			_start_room(0, [token])
		"choice":
			_room_call(token, func(r, seat: int) -> void: r.on_choice(seat, msg.get("choice", {})))
		"ack":
			_room_call(token, func(r, seat: int) -> void: r.on_ack(seat))
		"chat":
			var text := str(msg.get("text", ""))
			if Room.QUICK_CHAT.has(text):
				_room_call(token, func(r, seat: int) -> void: r.broadcast({"t": "chat", "seat": seat, "text": text}))
		"leave":
			_room_call(token, func(r, seat: int) -> void: r.on_disconnect(seat))
			_token_room.erase(token)
		"leaderboard":
			send(peer, {"t": "leaderboard", "scope": msg.get("scope", "country"),
				"rows": leaderboard(str(msg.get("scope", "country")), token)})


func disconnected(peer: int) -> void:
	var token: String = _peer_token.get(peer, "")
	_peer_token.erase(peer)
	if token == "":
		return
	if _token_peer.get(token, -1) == peer:
		_token_peer.erase(token)
	_leave_queues(token)
	_room_call(token, func(r, seat: int) -> void: r.on_disconnect(seat))


func _hello(peer: int, msg: Dictionary) -> void:
	var token := str(msg.get("token", ""))
	if token == "" or not _load(token):
		token = Crypto.new().generate_random_bytes(16).hex_encode()
		_profiles[token] = _new_profile(token, msg)
		# A player's offline progress comes with them the first time they reach the server.
		var carry: Dictionary = msg.get("carry", {})
		if carry is Dictionary and not carry.is_empty():
			_import_carry(_profiles[token], carry)
		_save(token)
	var old: int = _token_peer.get(token, -1)
	if old >= 0 and old != peer:
		_peer_token.erase(old)
	_peer_token[peer] = token
	_token_peer[token] = peer
	var p := _profile(token)
	var country := str(msg.get("country", ""))
	if country != "" and p.country == "":
		p.country = country
	_refresh_day(p)
	_save(token)
	send(peer, {"t": "welcome", "protocol": PROTOCOL, "token": token, "profile": public_profile(token),
		"server_time": now.call()})
	if _token_room.has(token):
		_room_call(token, func(r, seat: int) -> void: r.on_reconnect(seat, peer))
	elif p.has("held_result"):
		var held: Dictionary = p.held_result
		p.erase("held_result")
		_save(token)
		held.profile = public_profile(token)
		send(peer, held)


# ---------------------------------------------------------------- profiles

func _new_profile(token: String, msg: Dictionary) -> Dictionary:
	return {
		"token": token, "name": _clean_name(str(msg.get("name", "Player"))),
		"country": str(msg.get("country", "")), "avatar": str(msg.get("avatar", "a01")),
		"coins": Economy.START_COINS, "gems": Economy.START_GEMS, "xp": 0, "level": 1,
		"trophies": 0, "week": _week(), "week_trophies": 0,
		"owned": [], "equipped": {"token": "", "dice": ""},
		"daily": {"last": -10, "streak": 0}, "spin": {"last": -10, "extra": 0},
		"missions": {"day": -1, "list": []},
		"stats": {"matches": 0, "wins": 0}, "created": now.call(),
	}


func _import_carry(p: Dictionary, carry: Dictionary) -> void:
	for k in ["name", "avatar", "coins", "gems", "xp", "level", "trophies", "owned", "equipped", "stats"]:
		if carry.has(k):
			p[k] = carry[k]
	p.coins = clampi(int(p.coins), 0, 1000000)
	p.gems = clampi(int(p.gems), 0, 5000)


func _clean_name(n: String) -> String:
	n = n.strip_edges().substr(0, 16)
	return n if n.length() >= 2 else "Player"


func _profile(token: String) -> Dictionary:
	return _profiles[token]


func public_profile(token: String) -> Dictionary:
	var p: Dictionary = _profiles[token].duplicate(true)
	var today := _day()
	p.daily_ready = int(p.daily.last) != today
	p.daily_index = _next_daily_index(p)
	p.spin_ready = int(p.spin.last) != today or int(p.spin.extra) > 0
	p.xp_next = Economy.xp_to_next(int(p.level))
	return p


func _path(token: String) -> String:
	return store_dir.path_join("profiles").path_join(token + ".res")


func _load(token: String) -> bool:
	if _profiles.has(token):
		return true
	if not token.is_valid_hex_number() or token.length() != 32:
		return false
	var f := FileAccess.open(_path(token), FileAccess.READ)
	if f == null:
		return false
	var p = str_to_var(f.get_as_text())
	if not p is Dictionary:
		return false
	_profiles[token] = p
	return true


func _save(token: String) -> void:
	var f := FileAccess.open(_path(token), FileAccess.WRITE)
	if f != null:
		f.store_string(var_to_str(_profiles[token]))


func _day() -> int:
	return int(floor(now.call() / 86400.0))


func _week() -> int:
	return int(floor((now.call() / 86400.0 + 3.0) / 7.0))


## Rolls daily missions and the weekly trophy count over when the day or week changes.
func _refresh_day(p: Dictionary) -> void:
	var today := _day()
	if int(p.missions.day) != today:
		var pool := range(Economy.MISSIONS.size())
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(str(p.token) + str(today))
		var list := []
		while list.size() < 3:
			var k: int = pool.pop_at(rng.randi_range(0, pool.size() - 1))
			list.append({"id": Economy.MISSIONS[k].id, "progress": 0, "claimed": false})
		p.missions = {"day": today, "list": list}
	if int(p.week) != _week():
		p.week = _week()
		p.week_trophies = 0


func _give(p: Dictionary, coins: int, gems: int) -> void:
	p.coins = int(p.coins) + coins
	p.gems = int(p.gems) + gems


# ---------------------------------------------------------------- daily, spin, missions, shop

func _next_daily_index(p: Dictionary) -> int:
	var today := _day()
	var gap := today - int(p.daily.last)
	var streak := int(p.daily.streak)
	if gap == 0:
		return (streak - 1) % 7
	# One missed day is forgiven; two or more restart the week.
	return (streak % 7) if gap <= 2 else 0


func _claim_daily(peer: int, token: String) -> void:
	var p := _profile(token)
	var today := _day()
	if int(p.daily.last) == today:
		send(peer, {"t": "error", "msg": "already claimed"})
		return
	var idx := _next_daily_index(p)
	var gap := today - int(p.daily.last)
	p.daily.streak = (int(p.daily.streak) + 1) if gap <= 2 else 1
	p.daily.last = today
	var r: Dictionary = Economy.DAILY[idx]
	var reward := {"coins": 0, "gems": 0}
	match r.kind:
		"c":
			reward.coins = r.amount
		"g":
			reward.gems = r.amount
		"chest":
			reward.coins = Economy.CHEST.coins
			reward.gems = Economy.CHEST.gems
	_give(p, reward.coins, reward.gems)
	_save(token)
	send(peer, {"t": "reward", "source": "daily", "index": idx, "coins": reward.coins, "gems": reward.gems,
		"profile": public_profile(token)})


func _spin(peer: int, token: String, extra: bool) -> void:
	var p := _profile(token)
	var today := _day()
	if extra:
		if int(p.spin.extra) <= 0:
			send(peer, {"t": "error", "msg": "no extra spins"})
			return
		p.spin.extra = int(p.spin.extra) - 1
	elif int(p.spin.last) == today:
		send(peer, {"t": "error", "msg": "spin used"})
		return
	else:
		p.spin.last = today
	var total := 0
	for s: Dictionary in Economy.SPIN:
		total += int(s.w)
	var roll := _rng.randi_range(1, total)
	var idx := 0
	for i in Economy.SPIN.size():
		roll -= int(Economy.SPIN[i].w)
		if roll <= 0:
			idx = i
			break
	var prize: Dictionary = Economy.SPIN[idx]
	var coins := int(prize.amount) if prize.kind == "c" else 0
	var gems := int(prize.amount) if prize.kind == "g" else 0
	_give(p, coins, gems)
	_save(token)
	send(peer, {"t": "reward", "source": "spin", "index": idx, "coins": coins, "gems": gems,
		"profile": public_profile(token)})


func _claim_mission(peer: int, token: String, mid: String) -> void:
	var p := _profile(token)
	for m: Dictionary in p.missions.list:
		if m.id != mid or m.claimed:
			continue
		var spec := _mission_spec(mid)
		if int(m.progress) < int(spec.need):
			break
		m.claimed = true
		var coins := int(spec.reward.get("c", 0))
		var gems := int(spec.reward.get("g", 0))
		_give(p, coins, gems)
		_save(token)
		send(peer, {"t": "reward", "source": "mission", "coins": coins, "gems": gems, "profile": public_profile(token)})
		return
	send(peer, {"t": "error", "msg": "mission not ready"})


func _mission_spec(mid: String) -> Dictionary:
	for m: Dictionary in Economy.MISSIONS:
		if m.id == mid:
			return m
	return {}


func _buy(peer: int, token: String, item_id: String) -> void:
	var p := _profile(token)
	var it := Economy.shop_item(item_id)
	if it.is_empty() or int(p.gems) < int(it.gems) or (it.kind != "coins" and p.owned.has(item_id)):
		send(peer, {"t": "error", "msg": "cannot buy"})
		return
	p.gems = int(p.gems) - int(it.gems)
	if it.kind == "coins":
		p.coins = int(p.coins) + int(it.amount)
	else:
		p.owned.append(item_id)
		p.equipped[it.kind] = item_id
	_save(token)
	send(peer, {"t": "reward", "source": "shop", "item": item_id, "coins": int(it.get("amount", 0)) if it.kind == "coins" else 0,
		"gems": 0, "profile": public_profile(token)})


func _equip(peer: int, token: String, item_id: String) -> void:
	var p := _profile(token)
	var it := Economy.shop_item(item_id)
	if it.is_empty() or not p.owned.has(item_id):
		p.equipped[it.get("kind", "token")] = ""
	else:
		p.equipped[it.kind] = item_id
	_save(token)
	send(peer, {"t": "profile", "profile": public_profile(token)})


## Rewarded-ad payouts. The client only sends this after the ad network confirms a view.
func _ad_reward(peer: int, token: String, kind: String) -> void:
	var p := _profile(token)
	match kind:
		"spin":
			p.spin.extra = mini(int(p.spin.extra) + 1, 3)
		"refill":
			if int(p.coins) < Economy.TIERS[0].entry:
				_give(p, 500, 0)
	_save(token)
	send(peer, {"t": "profile", "profile": public_profile(token)})


# ---------------------------------------------------------------- matchmaking

func _queue(peer: int, token: String, tier: int) -> void:
	var p := _profile(token)
	if tier < 1 or tier > Economy.TIERS.size():
		return
	var spec: Dictionary = Economy.TIERS[tier - 1]
	if int(p.level) < int(spec.level):
		send(peer, {"t": "error", "msg": "locked"})
		return
	if int(p.coins) < int(spec.entry):
		send(peer, {"t": "error", "msg": "coins"})
		return
	if _token_room.has(token):
		_room_call(token, func(r, seat: int) -> void: r.resync(seat))
		return
	_leave_queues(token)
	if not _queues.has(tier):
		_queues[tier] = []
	_queues[tier].append({"token": token, "since": now.call(), "wait": _rng.randf_range(queue_wait_min, queue_wait_max)})
	send(peer, {"t": "queued", "tier": tier})


func _leave_queues(token: String) -> void:
	for tier in _queues:
		_queues[tier] = _queues[tier].filter(func(q: Dictionary) -> bool: return q.token != token)


func _tick_queues() -> void:
	var t: float = now.call()
	for tier in _queues:
		var q: Array = _queues[tier]
		while q.size() >= 4:
			var group := q.slice(0, 4)
			_queues[tier] = q.slice(4)
			q = _queues[tier]
			_start_room(tier, group.map(func(e: Dictionary) -> String: return e.token))
		if not q.is_empty() and t - float(q[0].since) >= float(q[0].wait):
			_queues[tier] = []
			_start_room(tier, q.map(func(e: Dictionary) -> String: return e.token))


func _start_room(tier: int, tokens: Array) -> void:
	var seats := []
	var taken := []
	var countries := []
	var levels := []
	var tycoons: Array = Board.TYCOONS.keys()
	for k in range(tycoons.size() - 1, 0, -1):
		var j := _rng.randi_range(0, k)
		var tmp = tycoons[k]
		tycoons[k] = tycoons[j]
		tycoons[j] = tmp
	for token: String in tokens:
		var p := _profile(token)
		if tier > 0:
			p.coins = int(p.coins) - int(Economy.TIERS[tier - 1].entry)
			_save(token)
		taken.append(p.name)
		countries.append(p.country)
		levels.append(int(p.level))
		seats.append({"kind": "human", "token": token, "peer": _token_peer.get(token, -1), "name": p.name,
			"avatar": p.avatar, "level": int(p.level), "country": p.country, "tycoon": "",
			"persona": "banker", "away": false, "timeouts": 0})
	var avatars_used := seats.map(func(s: Dictionary) -> String: return s.avatar)
	while seats.size() < 4:
		var country: String = countries[_rng.randi_range(0, countries.size() - 1)]
		var name := Names.pick(country, _rng, taken)
		taken.append(name)
		var avatar := _pick_avatar(avatars_used)
		avatars_used.append(avatar)
		var base: int = levels[_rng.randi_range(0, levels.size() - 1)]
		seats.append({"kind": "bot", "token": "", "peer": -1, "name": name, "avatar": avatar,
			"level": maxi(1, base + _rng.randi_range(-2, 3)), "country": country, "tycoon": "",
			"persona": Bot.PERSONAS.keys()[_rng.randi_range(0, Bot.PERSONAS.size() - 1)],
			"away": false, "timeouts": 0})
	# Shuffle seat order so people are not always first.
	for k in range(seats.size() - 1, 0, -1):
		var j := _rng.randi_range(0, k)
		var tmp = seats[k]
		seats[k] = seats[j]
		seats[j] = tmp
	for i in seats.size():
		seats[i].tycoon = tycoons[i]
	var room = Room.new(self, _next_room, tier, seats, _rng.randi())
	_rooms[_next_room] = room
	for token: String in tokens:
		_token_room[token] = _next_room
	_next_room += 1
	room.start()


func _pick_avatar(used: Array) -> String:
	var free := Names.AVATARS.filter(func(a: String) -> bool: return not used.has(a))
	var pool: Array = free if not free.is_empty() else Names.AVATARS
	return pool[_rng.randi_range(0, pool.size() - 1)]


func _room_call(token: String, fn: Callable) -> void:
	var rid: int = _token_room.get(token, -1)
	if not _rooms.has(rid):
		return
	var r = _rooms[rid]
	for i in r.seats.size():
		if r.seats[i].token == token:
			fn.call(r, i)
			return


func hold_result(token: String, msg: Dictionary) -> void:
	_profile(token).held_result = msg
	_save(token)


func close_room(rid: int) -> void:
	var r = _rooms.get(rid)
	if r == null:
		return
	for s: Dictionary in r.seats:
		if s.token != "":
			_token_room.erase(s.token)
	_rooms.erase(rid)


## Pays out one person's result and advances missions. Returns what they earned.
func award(token: String, tier: int, place: int, match_stats: Dictionary) -> Dictionary:
	var p := _profile(token)
	_refresh_day(p)
	var coins := 0
	var xp: int = Economy.PRACTICE_XP[place] if tier == 0 else Economy.PLACE_XP[place]
	var trophies: int = 0 if tier == 0 else Economy.PLACE_TROPHIES[place]
	if tier > 0 and place == 0:
		coins = Economy.prize(tier)
	var level_before := int(p.level)
	p.coins = int(p.coins) + coins
	p.trophies = maxi(0, int(p.trophies) + trophies)
	p.week_trophies = maxi(0, int(p.week_trophies) + trophies)
	p.xp = int(p.xp) + xp
	while int(p.xp) >= Economy.xp_to_next(int(p.level)):
		p.xp = int(p.xp) - Economy.xp_to_next(int(p.level))
		p.level = int(p.level) + 1
	p.stats.matches = int(p.stats.get("matches", 0)) + 1
	if place == 0:
		p.stats.wins = int(p.stats.get("wins", 0)) + 1
	var counted := match_stats.duplicate()
	counted.matches = 1
	counted.wins = 1 if place == 0 else 0
	for m: Dictionary in p.missions.list:
		var spec := _mission_spec(m.id)
		if not spec.is_empty():
			m.progress = mini(int(spec.need), int(m.progress) + int(counted.get(spec.stat, 0)))
	_save(token)
	return {"coins": coins, "xp": xp, "trophies": trophies, "level_before": level_before, "level": int(p.level)}


# ---------------------------------------------------------------- leaderboards

## Weekly trophies: "country" (same country), "world", or "friends" (not yet: just you).
func leaderboard(scope: String, token: String) -> Array:
	var me := _profile(token)
	var t: float = now.call()
	if t - _board_time > 30.0:
		_board_time = t
		_board_cache.clear()
		var dir := DirAccess.open(store_dir.path_join("profiles"))
		if dir != null:
			for f in dir.get_files():
				var k := f.get_basename()
				if _load(k):
					var p := _profile(k)
					if int(p.week) == _week() and int(p.week_trophies) > 0:
						_board_cache[k] = p
	var rows := []
	for k in _board_cache:
		var p: Dictionary = _board_cache[k]
		if scope == "country" and p.country != me.country:
			continue
		rows.append({"name": p.name, "avatar": p.avatar, "score": int(p.week_trophies), "me": k == token})
	if not rows.any(func(r: Dictionary) -> bool: return r.me):
		rows.append({"name": me.name, "avatar": me.avatar, "score": int(me.week_trophies), "me": true})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score > b.score)
	for i in rows.size():
		rows[i].rank = i + 1
	return rows.slice(0, 50) + rows.filter(func(r: Dictionary) -> bool: return r.me and r.rank > 50)
