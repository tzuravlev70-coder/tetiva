extends Node2D
## Small hand-rolled particle system (additive-looking sparks + shock rings).
## Everything is a few hundred draw calls at most — cheap and easy to tint.

const MAX_PARTS := 420

var _parts: Array[Dictionary] = []
var _rings: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	z_index = 8


func burst(pos: Vector2, count: int, color: Color, speed_min: float = 60.0, speed_max: float = 340.0,
		life: float = 0.6, size: float = 3.0, gravity: float = 220.0, direction: Vector2 = Vector2.ZERO,
		spread: float = TAU) -> void:
	for i in count:
		if _parts.size() >= MAX_PARTS:
			break
		var ang := _rng.randf_range(0.0, TAU)
		if direction != Vector2.ZERO and spread < TAU:
			ang = direction.angle() + _rng.randf_range(-spread * 0.5, spread * 0.5)
		var spd := _rng.randf_range(speed_min, speed_max)
		var life_jitter := life * _rng.randf_range(0.6, 1.15)
		var col := color.lerp(Color(1.0, 0.98, 0.9, color.a), _rng.randf_range(0.0, 0.55))
		_parts.append({
			"pos": pos + Vector2(_rng.randf_range(-4.0, 4.0), _rng.randf_range(-4.0, 4.0)),
			"vel": Vector2(cos(ang), sin(ang)) * spd,
			"life": life_jitter,
			"max": life_jitter,
			"size": size * _rng.randf_range(0.5, 1.3),
			"color": col,
			"gravity": gravity,
			"drag": _rng.randf_range(0.4, 2.4),
			"streak": _rng.randf() < 0.55,
		})


func ring(pos: Vector2, color: Color, from_radius: float = 12.0, to_radius: float = 90.0, life: float = 0.45, width: float = 3.0) -> void:
	_rings.append({
		"pos": pos,
		"life": life,
		"max": life,
		"from": from_radius,
		"to": to_radius,
		"color": color,
		"width": width,
	})


func attach_fx(pos: Vector2) -> void:
	ring(pos, Color(1.0, 0.88, 0.6, 0.8), 10.0, 70.0, 0.35, 2.5)
	burst(pos, 12, Color(1.0, 0.85, 0.55, 0.9), 80.0, 260.0, 0.45, 2.4, -40.0)


func pickup_fx(pos: Vector2, big: bool) -> void:
	ring(pos, Color(0.5, 1.0, 0.9, 0.7), 8.0, 60.0 if big else 34.0, 0.35, 2.0)
	burst(pos, 14 if big else 8, Color(0.55, 1.0, 0.9, 0.95), 60.0, 220.0, 0.5, 2.2, -60.0)


func hit_fx(pos: Vector2, dir: Vector2) -> void:
	ring(pos, Color(1.0, 0.45, 0.35, 0.85), 10.0, 70.0, 0.3, 3.0)
	burst(pos, 24, Color(1.0, 0.42, 0.32, 1.0), 120.0, 460.0, 0.6, 3.0, 160.0, dir, PI * 1.2)


func explode_fx(pos: Vector2) -> void:
	ring(pos, Color(1.0, 0.7, 0.4, 0.9), 16.0, 190.0, 0.7, 4.0)
	ring(pos, Color(1.0, 0.45, 0.3, 0.6), 8.0, 110.0, 0.5, 2.0)
	burst(pos, 46, Color(1.0, 0.55, 0.3, 1.0), 80.0, 520.0, 0.95, 3.4, 190.0)
	burst(pos, 16, Color(1.0, 0.95, 0.8, 1.0), 40.0, 260.0, 0.5, 2.0, -80.0)


func speed_puff(pos: Vector2, dir: Vector2) -> void:
	burst(pos, 2, Color(0.65, 0.9, 0.95, 0.5), 20.0, 90.0, 0.35, 1.6, 0.0, -dir, 1.2)


func tick(delta: float) -> void:
	var i := _parts.size() - 1
	while i >= 0:
		var p := _parts[i]
		p["life"] = float(p["life"]) - delta
		if float(p["life"]) <= 0.0:
			_parts.remove_at(i)
		else:
			var vel: Vector2 = p["vel"]
			vel.y += float(p["gravity"]) * delta
			vel *= maxf(0.0, 1.0 - float(p["drag"]) * delta)
			p["vel"] = vel
			p["pos"] = Vector2(p["pos"]) + vel * delta
		i -= 1

	i = _rings.size() - 1
	while i >= 0:
		var r := _rings[i]
		r["life"] = float(r["life"]) - delta
		if float(r["life"]) <= 0.0:
			_rings.remove_at(i)
		i -= 1

	queue_redraw()


func _draw() -> void:
	for p in _parts:
		var k := clampf(float(p["life"]) / float(p["max"]), 0.0, 1.0)
		var col: Color = p["color"]
		var pos: Vector2 = p["pos"]
		var size := float(p["size"]) * (0.35 + k * 0.65)
		draw_circle(pos, size * 1.9, Color(col, col.a * k * 0.16))
		draw_circle(pos, size, Color(col, col.a * k))
		if bool(p["streak"]):
			var vel: Vector2 = p["vel"]
			draw_line(pos, pos - vel * 0.028, Color(col, col.a * k * 0.55), maxf(size * 0.8, 1.0), true)

	for r in _rings:
		var k := 1.0 - clampf(float(r["life"]) / float(r["max"]), 0.0, 1.0)
		var radius := lerpf(float(r["from"]), float(r["to"]), 1.0 - pow(1.0 - k, 2.0))
		var col: Color = r["color"]
		var a := (1.0 - k) * 0.9
		draw_arc(r["pos"], radius, 0.0, TAU, 48, Color(col, col.a * a), float(r["width"]) * (1.0 - k * 0.6), true)


func clear() -> void:
	_parts.clear()
	_rings.clear()
	queue_redraw()
