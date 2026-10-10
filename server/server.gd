extends Node
## Dedicated Skyloop server: WebSocket in front of the same Backend the app runs offline.
##   godot --headless --path . res://server/server.tscn
## Environment: SKYLOOP_PORT (default 8910), SKYLOOP_DATA (profile folder, default user://server).

const Backend = preload("res://net/backend.gd")

var _tcp := TCPServer.new()
var _peers := {}  # id -> WebSocketPeer
var _next_id := 1
var _backend


func _ready() -> void:
	var port := int(OS.get_environment("SKYLOOP_PORT")) if OS.has_environment("SKYLOOP_PORT") else 8910
	_backend = Backend.new()
	_backend.store_dir = OS.get_environment("SKYLOOP_DATA") if OS.has_environment("SKYLOOP_DATA") else "user://server"
	add_child(_backend)
	_backend.outbound.connect(_send)
	var err := _tcp.listen(port)
	if err != OK:
		push_error("Skyloop server could not listen on %d (%s)" % [port, error_string(err)])
		get_tree().quit(1)
		return
	print("Skyloop server listening on :%d, data in %s" % [port, _backend.store_dir])


func _process(_delta: float) -> void:
	while _tcp.is_connection_available():
		var ws := WebSocketPeer.new()
		ws.inbound_buffer_size = 1 << 18
		ws.outbound_buffer_size = 1 << 20
		ws.accept_stream(_tcp.take_connection())
		_peers[_next_id] = ws
		_next_id += 1
	for id in _peers.keys():
		var ws: WebSocketPeer = _peers[id]
		ws.poll()
		match ws.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				while ws.get_available_packet_count() > 0:
					var msg = bytes_to_var(ws.get_packet())
					if msg is Dictionary:
						_backend.handle(id, msg)
			WebSocketPeer.STATE_CLOSED:
				_peers.erase(id)
				_backend.disconnected(id)


func _send(id: int, msg: Dictionary) -> void:
	var ws: WebSocketPeer = _peers.get(id)
	if ws != null and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.put_packet(var_to_bytes(msg))
