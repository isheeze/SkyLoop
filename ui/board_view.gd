extends Control
## Greybox board: draws the tile ring and a status panel in the middle. Placeholder for the
## 3D board; it only reads game state.

const Board = preload("res://core/board.gd")

const BG := Color("141a26")
const TILE_BG := Color("222b3d")
const TEXT := Color("e8ecf4")
const DIM := Color("8b96ab")

var g
var colors: Array = []


func tile_rect(i: int) -> Rect2:
	var cell := size.x / 8.0
	var col := 0
	var row := 0
	if i <= 7:
		col = 7 - i
		row = 7
	elif i <= 14:
		col = 0
		row = 14 - i
	elif i <= 21:
		col = i - 14
		row = 0
	else:
		col = 7
		row = i - 21
	return Rect2(col * cell, row * cell, cell, cell).grow(-3)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	if g == null:
		return
	var font := ThemeDB.fallback_font
	for i in Board.TILE_COUNT:
		_draw_tile(i, font)
	_draw_center(font)


func _draw_tile(i: int, font: Font) -> void:
	var r := tile_rect(i)
	var t: Dictionary = Board.TILES[i]
	draw_rect(r, TILE_BG)
	var y := r.position.y + 6
	if t.kind == Board.Kind.PROPERTY:
		var d: int = t.district
		draw_rect(Rect2(r.position, Vector2(r.size.x, 20)), Board.DISTRICTS[d].color)
		y += 20
		var o: int = g.owner_of[i]
		if o != -1:
			draw_rect(r, colors[o], false, 5.0)
			draw_string(font, Vector2(r.position.x + 8, r.end.y - 34), "rent %d" % g.rent_for(i),
				HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 12, 18, TEXT)
			var lvl: int = g.level_of[i]
			for k in lvl:
				var c: Color = Color("ffd166") if lvl == Board.LANDMARK_LEVEL else TEXT
				draw_rect(Rect2(r.position.x + 8 + k * 16, r.end.y - 62, 12, 12), c)
		else:
			draw_string(font, Vector2(r.position.x + 8, r.end.y - 34), "$%d" % g.price_of(i),
				HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 12, 18, DIM)
	draw_multiline_string(font, Vector2(r.position.x + 8, y + 18), t.name,
		HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 12, 18, 2, TEXT)
	if t.kind == Board.Kind.JACKPOT:
		draw_string(font, Vector2(r.position.x + 8, r.end.y - 34), "$%d" % g.pot,
			HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 12, 20, Color("ffd166"))
	var n := 0
	for pi in g.players.size():
		if g.players[pi].pos == i:
			var c := Vector2(r.position.x + 18 + n * 26, r.end.y - 16)
			draw_circle(c, 11, Color.BLACK)
			draw_circle(c, 9, colors[pi])
			n += 1


func _draw_center(font: Font) -> void:
	var cell := size.x / 8.0
	var x := cell + 24
	var y := cell + 44
	var w := cell * 6 - 48
	for pi in g.players.size():
		var p = g.players[pi]
		var row := Rect2(x - 12, y - 34, w + 24, 104)
		if pi == g.turn and not g.over:
			draw_rect(row, Color(1, 1, 1, 0.08))
		draw_circle(Vector2(x + 12, y - 8), 12, colors[pi])
		draw_string(font, Vector2(x + 36, y), "%s  ·  %s" % [p.name, Board.TYCOONS[p.tycoon].name],
			HORIZONTAL_ALIGNMENT_LEFT, w - 36, 26, TEXT)
		var flags := ""
		if p.permit:
			flags += "  [permit]"
		if p.shield:
			flags += "  [shield]"
		if p.squeeze:
			flags += "  [squeeze]"
		if p.frozen:
			flags += "  [frozen]"
		if p.debt > 0:
			flags += "  debt %d" % p.debt
		if not p.power_used:
			flags += "  ★"
		draw_string(font, Vector2(x + 36, y + 34),
			"$%d   steer %d   worth %d%s" % [p.cash, p.steer, g.net_worth(pi), flags],
			HORIZONTAL_ALIGNMENT_LEFT, w - 36, 22, DIM)
		y += 110
	y += 6
	draw_string(font, Vector2(x, y), "Demand", HORIZONTAL_ALIGNMENT_LEFT, w, 22, DIM)
	for d in Board.DISTRICT_COUNT:
		var bx := x + 110 + d * 78
		draw_rect(Rect2(bx, y - 24, 64, 32), Board.DISTRICTS[d].color)
		draw_string(font, Vector2(bx, y), str(g.demand_of(d)), HORIZONTAL_ALIGNMENT_CENTER, 64, 22,
			Color.BLACK)
	y += 60
	var dice_txt := ""
	for v: int in g.dice:
		dice_txt += "[%d] " % v
	draw_string(font, Vector2(x, y), "Dice  %s      Jackpot  $%d" % [dice_txt, g.pot],
		HORIZONTAL_ALIGNMENT_LEFT, w, 28, TEXT)
