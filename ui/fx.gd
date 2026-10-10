extends Node
## Autoload "Fx": sound effects, haptics and the player's settings for both.

const SETTINGS_PATH := "user://settings.cfg"
const GROUPS := {
	"dice": ["dice_1", "dice_2", "dice_3"],
	"coin": ["coin_1", "coin_2"],
}
const SINGLES := ["hop", "land", "pay", "buy", "build", "click", "jackpot", "win", "lose", "headline",
	"bailout", "toast", "auction", "your_turn", "landmark", "shuffle", "shake", "coin_tick", "levelup",
	"celebrate"]
const VOLUME := {"hop": -14.0, "toast": -10.0, "click": -6.0, "land": -4.0, "headline": -6.0}

var sound := true
var haptics := true

var _streams := {}
var _players: Array = []
var _next := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	for name: String in SINGLES:
		_streams[name] = [load("res://audio/sfx/%s.ogg" % name)]
	for group: String in GROUPS:
		var list := []
		for name: String in GROUPS[group]:
			list.append(load("res://audio/sfx/%s.ogg" % name))
		_streams[group] = list
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


func play(name: String, volume_db := 0.0, pitch_jitter := 0.06, pitch := 1.0) -> void:
	if not sound or not _streams.has(name):
		return
	var list: Array = _streams[name]
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = list[randi() % list.size()]
	p.volume_db = volume_db + VOLUME.get(name, 0.0)
	p.pitch_scale = pitch + randf_range(-pitch_jitter, pitch_jitter)
	p.play()


## Short vibration on phones; `strength` is 0..1.
func buzz(ms: int, strength := 0.5) -> void:
	if haptics and OS.has_feature("mobile"):
		Input.vibrate_handheld(ms, strength)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		sound = cfg.get_value("fx", "sound", true)
		haptics = cfg.get_value("fx", "haptics", true)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("fx", "sound", sound)
	cfg.set_value("fx", "haptics", haptics)
	cfg.save(SETTINGS_PATH)
