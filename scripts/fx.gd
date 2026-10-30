extends Control
## Screen-space overlay: speed streaks, vignette, damage flash and the abyss
## warning that creeps up when the player drops too low.

var game

var _flash := 0.0
var _flash_color := Color(1.0, 1.0, 1.0)
var _time := 0.0
var _danger := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func setup(game_node) -> void:
	game = game_node


func flash(color: Color, strength: float = 1.0) -> void:
	_flash_color = color
	_flash = maxf(_flash, clampf(strength, 0.0, 1.0))


func _process(delta: float) -> void:
	_time += delta
	_flash = maxf(0.0, _flash - delta * 3.2)
	if game != null and is_instance_valid(game):
		_danger = lerpf(_danger, game.danger_level(), 1.0 - exp(-6.0 * delta))
	queue_redraw()


func _draw() -> void:
	var s := size
	if s.x < 4.0 or s.y < 4.0:
		return

	var speed := 0.0
	if game != null and is_instance_valid(game):
		speed = game.speed_factor()

	_draw_speed_lines(s, speed)
	_draw_vignette(s)
	_draw_danger(s)
	if _flash > 0.001:
		draw_rect(Rect2(Vector2.ZERO, s), Color(_flash_color, _flash * 0.35))


func _draw_speed_lines(s: Vector2, speed: float) -> void:
	if speed < 0.08:
		return
	for i in 26:
		var phase := float(i) * 0.6180339
		var y := fposmod(float(i) * 97.31 + sin(float(i)) * 60.0, s.y)
		var length := 30.0 + 150.0 * speed * (0.4 + fposmod(float(i) * 0.773, 1.0))
		var x := fposmod(float(i) * 211.0 - _time * (420.0 + float(i % 7) * 90.0) * (0.4 + speed), s.x + 400.0) - 200.0
		var edge := 1.0 - clampf(absf(y - s.y * 0.5) / (s.y * 0.5), 0.0, 1.0)
		var alpha := speed * (0.04 + 0.10 * edge) * (0.5 + 0.5 * sin(phase * 10.0 + _time * 3.0))
		draw_line(Vector2(x, y), Vector2(x + length, y), Color(0.82, 0.92, 1.0, alpha), 1.0, true)


func _draw_vignette(s: Vector2) -> void:
	var bands := 12
	for i in bands:
		var k := float(i) / float(bands)
		var a := 0.030 * (1.0 - k) * (1.0 - k)
		var inset := k * 110.0
		draw_rect(Rect2(0.0, inset, s.x, 10.0), Color(0.0, 0.0, 0.0, a * 2.2))
		draw_rect(Rect2(0.0, s.y - inset - 10.0, s.x, 10.0), Color(0.0, 0.0, 0.0, a * 2.2))
		draw_rect(Rect2(inset, 0.0, 10.0, s.y), Color(0.0, 0.0, 0.0, a * 1.8))
		draw_rect(Rect2(s.x - inset - 10.0, 0.0, 10.0, s.y), Color(0.0, 0.0, 0.0, a * 1.8))


func _draw_danger(s: Vector2) -> void:
	if _danger < 0.02:
		return
	var pulse := 0.75 + 0.25 * sin(_time * 6.0)
	var bands := 14
	for i in bands:
		var k := float(i) / float(bands)
		var h := s.y * 0.34 / float(bands)
		var y := s.y - (k + 1.0) * h
		var a := _danger * pulse * 0.16 * (k * k)
		draw_rect(Rect2(0.0, y, s.x, h + 1.0), Color(0.55, 0.08, 0.10, a))
	# thin red frame pulse
	draw_rect(Rect2(0.0, 0.0, s.x, s.y), Color(0.8, 0.1, 0.12, _danger * 0.05 * pulse), false, 10.0)
