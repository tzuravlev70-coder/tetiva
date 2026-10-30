extends Control
## Screen-space parallax backdrop: dusk sky, retro sun, stars, three ridges and
## a few radio towers. Follows the camera manually for the parallax offsets.

const TOP := Color(0.012, 0.024, 0.05)
const UPPER := Color(0.04, 0.085, 0.155)
const DUSK := Color(0.24, 0.19, 0.25)
const HORIZON := Color(0.76, 0.42, 0.26)
const SUN := Color(1.0, 0.64, 0.38)
const FAR_RIDGE := Color(0.075, 0.105, 0.17)
const MID_RIDGE := Color(0.05, 0.075, 0.13)
const NEAR_RIDGE := Color(0.03, 0.045, 0.08)

var _time := 0.0
var _stars: Array[Vector3] = []  # x (0..1), y (0..1), phase
var _rng := RandomNumberGenerator.new()
var _sky_tex: GradientTexture2D
var _ground_tex: GradientTexture2D
var _embers: Array[Vector3] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.seed = 20251030
	for i in 110:
		_stars.append(Vector3(_rng.randf(), _rng.randf() * 0.62, _rng.randf() * TAU))
	for i in 22:
		_embers.append(Vector3(_rng.randf(), _rng.randf(), _rng.randf() * TAU))
	_sky_tex = _make_gradient_texture(
		PackedFloat32Array([0.0, 0.5, 0.8, 1.0]),
		PackedColorArray([TOP, UPPER, DUSK, HORIZON]))
	_ground_tex = _make_gradient_texture(
		PackedFloat32Array([0.0, 1.0]),
		PackedColorArray([Color(0.07, 0.065, 0.10), Color(0.012, 0.02, 0.04)]))


func _make_gradient_texture(offsets: PackedFloat32Array, colors: PackedColorArray) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = offsets
	gradient.colors = colors
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = 4
	tex.height = 512
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(0.0, 1.0)
	return tex


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var s := size
	if s.x < 4.0 or s.y < 4.0:
		return
	var cam := get_viewport().get_camera_2d()
	var cx := 0.0
	var cy := 0.0
	if cam != null:
		cx = cam.get_screen_center_position().x
		cy = cam.get_screen_center_position().y

	var horizon := s.y * 0.615 + cy * 0.045

	_draw_sky(s, horizon)
	_draw_sun(s, horizon, cx)
	_draw_stars(s, cx, horizon)
	_draw_ridge(s, cx, cy, horizon + 24.0, 62.0, 0.16, FAR_RIDGE, 0.0, 0.0)
	_draw_ridge(s, cx, cy, horizon + 62.0, 54.0, 0.34, MID_RIDGE, 1.7, 0.0)
	_draw_ridge(s, cx, cy, horizon + 108.0, 44.0, 0.62, NEAR_RIDGE, 4.1, 1.0)
	_draw_haze(s, horizon)
	_draw_reflection(s, cx, horizon)
	_draw_embers(s, cx, horizon)


func _draw_embers(s: Vector2, cx: float, horizon: float) -> void:
	for i in _embers.size():
		var e := _embers[i]
		var speed := 7.0 + fmod(e.z, 1.0) * 10.0
		var x := fposmod(e.x * s.x + _time * speed * 0.6 - cx * 0.22, s.x + 60.0) - 30.0
		var y := horizon + 30.0 - fposmod(e.y * 220.0 + _time * speed, 260.0)
		var a := 0.10 + 0.10 * (0.5 + 0.5 * sin(_time * 1.4 + e.z))
		draw_circle(Vector2(x, y), 1.1 + fmod(e.z, 1.0) * 1.2, Color(1.0, 0.62, 0.38, a))
		draw_circle(Vector2(x, y), 4.0, Color(1.0, 0.55, 0.32, a * 0.10))


func _sun_x(s: Vector2, cx: float) -> float:
	return s.x * 0.79 - fmod(cx * 0.012, s.x * 0.30)


func _draw_reflection(s: Vector2, cx: float, horizon: float) -> void:
	var sun_x := _sun_x(s, cx)
	var bands := 9
	for i in bands:
		var k := float(i) / float(bands)
		var y := horizon + 12.0 + k * k * 150.0
		var w := 90.0 + k * 260.0
		var a := 0.065 * (1.0 - k * 0.75)
		var x := sun_x - w * 0.5 + sin(_time * 0.6 + i * 1.3) * 14.0
		draw_rect(Rect2(x, y, w, 2.0), Color(1.0, 0.58, 0.34, a))
		draw_rect(Rect2(x + w * 0.18, y + 5.0, w * 0.55, 1.0), Color(1.0, 0.7, 0.45, a * 0.7))


func _draw_sky(s: Vector2, horizon: float) -> void:
	draw_texture_rect(_sky_tex, Rect2(0.0, 0.0, s.x, horizon), false)
	# ground: dark valley below the horizon
	draw_texture_rect(_ground_tex, Rect2(0.0, horizon, s.x, s.y - horizon), false)


func _draw_sun(s: Vector2, horizon: float, cx: float) -> void:
	var radius := s.y * 0.098
	var pos := Vector2(_sun_x(s, cx), horizon - radius * 1.42)
	# halo
	for i in 5:
		var k := float(i) / 5.0
		draw_circle(pos, radius * (1.5 + k * 1.1), Color(SUN, 0.016 * (1.0 - k)))
	draw_circle(pos, radius, Color(SUN, 0.62))
	draw_circle(pos, radius * 0.80, Color(1.0, 0.76, 0.52, 0.38))
	# retro slats carved out of the disc
	var slats := 4
	for i in slats:
		var k := float(i) / float(slats)
		var y := pos.y + radius * 0.12 + radius * 0.92 * k
		var h := radius * (0.022 + k * 0.05)
		var dy := y - pos.y
		var half := sqrt(maxf(radius * radius - dy * dy, 0.0))
		if half > 1.0:
			draw_rect(Rect2(pos.x - half, y, half * 2.0, h), Color(0.10, 0.09, 0.14, 0.55))
	# inner glow
	draw_circle(pos, radius * 0.20, Color(1.0, 0.88, 0.7, 0.35))


func _draw_stars(s: Vector2, cx: float, horizon: float) -> void:
	var parallax := 0.03
	for i in _stars.size():
		var st := _stars[i]
		var x := fposmod(st.x * s.x * 1.4 - cx * parallax + i * 13.37, s.x + 80.0) - 40.0
		var y := st.y * horizon * 0.92
		var twinkle := 0.35 + 0.65 * (0.5 + 0.5 * sin(_time * (1.0 + fmod(st.z, 1.7)) + st.z))
		var alpha := clampf((1.0 - y / (horizon + 1.0)) * 0.9, 0.0, 1.0) * twinkle
		var r := 0.8 if i % 9 != 0 else 1.6
		draw_circle(Vector2(x, y), r, Color(0.85, 0.92, 1.0, alpha * 0.55))
		if i % 23 == 0:
			draw_line(Vector2(x - 3.0, y), Vector2(x + 3.0, y), Color(0.8, 0.9, 1.0, alpha * 0.35), 1.0, true)
			draw_line(Vector2(x, y - 3.0), Vector2(x, y + 3.0), Color(0.8, 0.9, 1.0, alpha * 0.35), 1.0, true)


func _ridge_value(wx: float, seed: float) -> float:
	return (sin(wx * 0.0013 + seed) * 0.55
		+ sin(wx * 0.0037 + seed * 2.3) * 0.27
		+ sin(wx * 0.0102 + seed * 4.7) * 0.13
		+ sin(wx * 0.0241 + seed * 1.1) * 0.05)


func _draw_ridge(s: Vector2, cx: float, cy: float, base_y: float, amp: float, parallax: float,
		color: Color, seed: float, towers: float) -> void:
	var step := 26.0
	var offset := cx * parallax
	var pts := PackedVector2Array()
	pts.append(Vector2(-20.0, s.y + 20.0))
	var x := -20.0
	while x < s.x + step:
		var wx := x + offset
		var y := base_y + _ridge_value(wx, seed) * amp - cy * parallax * 0.22
		pts.append(Vector2(x, y))
		x += step
	pts.append(Vector2(s.x + 20.0, s.y + 20.0))
	draw_colored_polygon(pts, color)

	# faint crest highlight
	var crest := PackedVector2Array()
	x = -20.0
	while x < s.x + step:
		var wx := x + offset
		crest.append(Vector2(x, base_y + _ridge_value(wx, seed) * amp - cy * parallax * 0.22))
		x += step
	draw_polyline(crest, Color(color.lightened(0.22), 0.55), 1.2, true)

	if towers > 0.5:
		_draw_towers(s, cx, cy, base_y, amp, parallax, seed, color)


func _draw_towers(s: Vector2, cx: float, cy: float, base_y: float, amp: float, parallax: float, seed: float, color: Color) -> void:
	var spacing := 610.0
	var offset := cx * parallax
	var first := floorf((offset - 200.0) / spacing) * spacing
	var idx := 0
	while idx < 4:
		var world_x := first + idx * spacing
		var screen_x := world_x - offset
		idx += 1
		if screen_x < -120.0 or screen_x > s.x + 120.0:
			continue
		var base := Vector2(screen_x, base_y + _ridge_value(world_x, seed) * amp - cy * parallax * 0.22 + 4.0)
		var height := 118.0 + fmod(absf(world_x) * 0.013, 46.0)
		var half := 13.0
		var tower_col := Color(color.lightened(0.06), 0.98)
		draw_line(base + Vector2(-half, 0.0), base + Vector2(-3.0, -height), tower_col, 2.4)
		draw_line(base + Vector2(half, 0.0), base + Vector2(3.0, -height), tower_col, 2.4)
		draw_line(base + Vector2(-3.0, -height), base + Vector2(3.0, -height), tower_col, 2.0)
		for b in 4:
			var k := 0.2 + b * 0.2
			var y := -height * k
			var w := lerpf(half, 3.0, k)
			draw_line(base + Vector2(-w, y), base + Vector2(w, y), tower_col, 1.4)
			draw_line(base + Vector2(-w, y), base + Vector2(w * 0.75, y - height * 0.2), tower_col, 1.0)
			draw_line(base + Vector2(w, y), base + Vector2(-w * 0.75, y - height * 0.2), tower_col, 1.0)
		var blink := 0.5 + 0.5 * sin(_time * 2.6 + world_x * 0.01)
		draw_circle(base + Vector2(0.0, -height), 2.6, Color(1.0, 0.35, 0.28, 0.35 + 0.55 * blink))
		draw_circle(base + Vector2(0.0, -height), 8.0, Color(1.0, 0.3, 0.25, 0.05 + 0.06 * blink))


func _draw_haze(s: Vector2, horizon: float) -> void:
	var bands := 10
	for i in bands:
		var k := float(i) / float(bands)
		var y := horizon - 26.0 + k * 74.0
		var a := (1.0 - k) * 0.12
		draw_rect(Rect2(0.0, y, s.x, 9.0), Color(0.95, 0.62, 0.45, a))
