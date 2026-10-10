extends Node
## Autoload "Net": the app's only door to the game service. Talks to the dedicated server
## over WebSocket when one is configured and reachable, otherwise to a Backend running inside
## the app. Either way the rest of the game sees the same messages.
##
## Signals carry raw protocol messages (see net/backend.gd).

signal connected  # welcome received; `profile` is fresh
signal profile_changed(profile: Dictionary)
signal message(msg: Dictionary)  # everything else (match_start, update, reward, ...)

const Backend = preload("res://net/backend.gd")
const IDENTITY := "user://identity.cfg"
const CONNECT_TIMEOUT := 4.0

## Set in project.godot as skyloop/server_url, e.g. "wss://play.skyloop.example". Empty = offline.
var server_url := ""
var online := false
var is_ready := false
var profile := {}
var country := ""
var server_time_offset := 0.0

var _ws: WebSocketPeer
var _local: Node
var _connect_clock := 0.0
var _retry_clock := 0.0
var _id := ConfigFile.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	server_url = str(ProjectSettings.get_setting("skyloop/server_url", ""))
	if OS.has_environment("SKYLOOP_SERVER"):
		server_url = OS.get_environment("SKYLOOP_SERVER")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--server="):
			server_url = a.substr(9)
	_id.load(IDENTITY)
	country = str(_id.get_value("me", "country", ""))
	if country == "":
		country = detect_country()
		_id.set_value("me", "country", country)
		_id.save(IDENTITY)


## Connects to the server if configured, else starts the in-app backend.
func start() -> void:
	is_ready = false
	if server_url != "":
		_ws = WebSocketPeer.new()
		_ws.inbound_buffer_size = 1 << 20
		_ws.outbound_buffer_size = 1 << 18
		if _ws.connect_to_url(server_url) == OK:
			_connect_clock = CONNECT_TIMEOUT
			return
	_go_local()


func _go_local() -> void:
	online = false
	_ws = null
	if _local == null:
		_local = Backend.new()
		_local.store_dir = "user://local_backend"
		add_child(_local)
		_local.outbound.connect(func(_peer: int, msg: Dictionary) -> void: _receive.call_deferred(msg))
	_hello("local_token")


func _hello(token_key: String) -> void:
	var carry := {}
	if token_key == "server_token" and str(_id.get_value("me", "server_token", "")) == "" and not profile.is_empty():
		carry = profile
	send({"t": "hello", "token": str(_id.get_value("me", token_key, "")), "country": country,
		"name": str(_id.get_value("me", "name", _default_name())), "avatar": str(_id.get_value("me", "avatar", "a01")),
		"carry": carry})


func send(msg: Dictionary) -> void:
	if _ws != null and online:
		_ws.put_packet(var_to_bytes(msg))
	elif _local != null:
		_local.handle.call_deferred(1, msg)


func _process(delta: float) -> void:
	if _ws == null:
		return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_CONNECTING:
			_connect_clock -= delta
			if _connect_clock <= 0.0:
				_ws.close()
				_go_local()
		WebSocketPeer.STATE_OPEN:
			if not online:
				online = true
				_hello("server_token")
			while _ws.get_available_packet_count() > 0:
				var msg = bytes_to_var(_ws.get_packet())
				if msg is Dictionary:
					_receive(msg)
		WebSocketPeer.STATE_CLOSED:
			if online:
				# Lost the server mid-session: keep retrying; the server keeps our seat.
				online = false
				is_ready = false
				_retry_clock = 2.0
			_retry_clock -= delta
			if _retry_clock <= 0.0:
				_retry_clock = 3.0
				_ws.connect_to_url(server_url)


func _receive(msg: Dictionary) -> void:
	match msg.get("t", ""):
		"welcome":
			var key := "server_token" if online else "local_token"
			_id.set_value("me", key, msg.token)
			_id.save(IDENTITY)
			server_time_offset = float(msg.get("server_time", 0.0)) - Time.get_unix_time_from_system()
			_set_profile(msg.profile)
			is_ready = true
			connected.emit()
		"profile":
			_set_profile(msg.profile)
		_:
			if msg.has("profile"):
				_set_profile(msg.profile)
			message.emit(msg)


func _set_profile(p: Dictionary) -> void:
	profile = p
	profile_changed.emit(p)


func set_identity(name: String, avatar: String) -> void:
	_id.set_value("me", "name", name)
	_id.set_value("me", "avatar", avatar)
	_id.save(IDENTITY)


func _default_name() -> String:
	return "Player%d" % (randi() % 9000 + 1000)


## Country from the phone's locale, or from its time zone when the locale is generic
## (many phones in Pakistan and India run an en_US locale).
static func detect_country() -> String:
	var loc := OS.get_locale()
	var parts := loc.split("_")
	if parts.size() >= 2 and parts[1].length() == 2 and parts[1] != "US":
		return parts[1].to_upper()
	var bias: int = int(Time.get_time_zone_from_system().get("bias", 0))
	match bias:
		300:
			return "PK"
		330:
			return "IN"
		360:
			return "BD"
		240:
			return "AE"
		180:
			return "SA"
		0, 60:
			return "GB"
	if bias <= -240 and bias >= -600:
		return "US"
	return "WORLD"
