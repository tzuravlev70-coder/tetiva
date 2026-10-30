extends Node2D
## The runner. Custom pendulum physics: the rope is taut when stretched, slack
## when the player swings inward, and pumping builds speed.

signal rope_attached(anchor_pos: Vector2)
signal rope_released(at_pos: Vector2)

const GRAVITY := 1600.0
const AIR_ACCEL := 1250.0
const PUMP_ACCEL := 1500.0
const HORIZONTAL_DRAG := 0.10
const MAX_SPEED := 1600.0
const ATTACH_RANGE := 520.0
const MIN_ROPE := 110.0
const MAX_ROPE := 355.0
const ROPE_REEL := 300.0
const RADIUS := 13.0
const BODY_SCALE := 1.35

var velocity := Vector2.ZERO
var attached_id := -1
var candidate_id := -1
var rope_len := 0.0
var invuln_time := 0.0
var alive := true
var active := true
var autopilot := false
var attach_armed := true

var level
var camera: Camera2D

var _rope_target := 0.0
var _time := 0.0
var _flash := 0.0
var _attach_pulse := 0.0
var _trail: PackedVector2Array = PackedVector2Array()
var _input_dir := 0.0
var _auto_hold := false
var _last_released_id := -1
var _reattach_block := 0.0
var _stuck_timer := 0.0
var _attached_time := 0.0
var _trail_line: Line2D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	z_index = 5
	_build_trail_line()


func _build_trail_line() -> void:
	_trail_line = Line2D.new()
	_trail_line.name = "Trail"
	_trail_line.z_index = -1
	_trail_line.width = 8.5
	_trail_line.joint_mode = Line2D.LINE_JOINT_ROUND
	_trail_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_trail_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	_trail_line.antialiased = true
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.06))
	curve.add_point(Vector2(0.35, 0.28))
	curve.add_point(Vector2(0.75, 0.62))
	curve.add_point(Vector2(1.0, 1.0))
	_trail_line.width_curve = curve
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.4, 0.78, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.35, 0.95, 0.82, 0.0),
		Color(0.4, 1.0, 0.86, 0.16),
		Color(0.55, 1.0, 0.92, 0.48),
		Color(0.9, 1.0, 0.97, 0.82),
	])
	_trail_line.gradient = gradient
	add_child(_trail_line)


func setup(level_node, camera_node: Camera2D) -> void:
	level = level_node
	camera = camera_node


func set_trail_enabled(enabled: bool) -> void:
	if _trail_line != null:
		_trail_line.visible = enabled


## Start the run already hanging from an anchor. The rope stays until the
## player actually presses the attach button once — no instant death on spawn.
func start_attached(anchor_id: int, anchor_pos: Vector2) -> void:
	attached_id = anchor_id
	rope_len = position.distance_to(anchor_pos)
	_rope_target = clampf(rope_len, MIN_ROPE, MAX_ROPE)
	_attached_time = 0.0
	_attach_pulse = 1.0
	attach_armed = false


func reset(spawn_data: Dictionary) -> void:
	position = spawn_data.get("pos", Vector2.ZERO)
	velocity = spawn_data.get("vel", Vector2.ZERO)
	attached_id = -1
	candidate_id = -1
	rope_len = 0.0
	_rope_target = 0.0
	invuln_time = 0.0
	alive = true
	active = true
	visible = true
	modulate.a = 1.0
	_flash = 0.0
	_attach_pulse = 0.0
	_reattach_block = 0.0
	_last_released_id = -1
	_stuck_timer = 0.0
	_attached_time = 0.0
	_auto_hold = false
	_input_dir = 0.0
	attach_armed = true
	_clear_trail()
	queue_redraw()


func warp(pos: Vector2, vel: Vector2) -> void:
	position = pos
	velocity = vel
	attached_id = -1
	rope_len = 0.0
	_clear_trail()


func kill() -> void:
	alive = false
	active = false
	visible = false
	velocity = Vector2.ZERO
	attached_id = -1
	_clear_trail()


func set_invuln(time: float) -> void:
	invuln_time = maxf(invuln_time, time)


func flash() -> void:
	_flash = 1.0


func clear_trail() -> void:
	_clear_trail()


func speed() -> float:
	return velocity.length()


# ------------------------------------------------------------------ physics
func _physics_process(delta: float) -> void:
	if not active or not alive:
		return
	_time += delta
	invuln_time = maxf(0.0, invuln_time - delta)
	_flash = maxf(0.0, _flash - delta * 3.5)
	_attach_pulse = maxf(0.0, _attach_pulse - delta * 2.3)
	_reattach_block = maxf(0.0, _reattach_block - delta)
	if attached_id != -1:
		_attached_time += delta

	if autopilot:
		_autopilot_step(delta)

	var hold := _auto_hold if autopilot else Input.is_action_pressed("attach")
	var dir := _input_dir if autopilot else Input.get_axis("left", "right")
	_input_dir = dir
	if hold:
		attach_armed = true

	_refresh_candidate()
	if hold:
		if attached_id == -1:
			_try_attach()
	elif attached_id != -1 and attach_armed:
		_detach(true)

	_integrate(delta, dir)
	_update_trail()
	_update_blink()
	queue_redraw()


func _refresh_candidate() -> void:
	if attached_id != -1:
		candidate_id = -1
		return
	var target: Dictionary = level.find_attach_target(position, ATTACH_RANGE)
	candidate_id = int(target.get("id", -1)) if not target.is_empty() else -1


func _try_attach() -> void:
	var exclude := _last_released_id if autopilot and _reattach_block > 0.0 else -1
	var target: Dictionary = level.find_attach_target(position, ATTACH_RANGE, exclude)
	if target.is_empty():
		return
	var anchor_pos: Vector2 = target["pos"]
	var dist := position.distance_to(anchor_pos)
	if dist < 18.0:
		return
	attached_id = int(target["id"])
	rope_len = minf(dist, ATTACH_RANGE)
	_rope_target = clampf(dist, MIN_ROPE, MAX_ROPE)
	_attach_pulse = 1.0
	_attached_time = 0.0
	_stuck_timer = 0.0
	rope_attached.emit(anchor_pos)


func _detach(with_sound: bool) -> void:
	if attached_id == -1:
		return
	_last_released_id = attached_id
	if autopilot:
		_reattach_block = 0.8
		_stuck_timer = 0.0
	attached_id = -1
	rope_len = 0.0
	_rope_target = 0.0
	_attached_time = 0.0
	if with_sound:
		rope_released.emit(position)


func _integrate(delta: float, dir: float) -> void:
	velocity.y += GRAVITY * delta

	if attached_id != -1:
		var anchor: Dictionary = level.get_anchor(attached_id)
		if anchor.is_empty():
			attached_id = -1
		else:
			var ap: Vector2 = anchor["pos"]
			var n := (position - ap).normalized()
			# tangential pumping towards the desired horizontal direction
			if absf(dir) > 0.01 and n != Vector2.ZERO:
				var tangent := Vector2(-n.y, n.x)
				if tangent.x * dir < 0.0:
					tangent = -tangent
				velocity += tangent * PUMP_ACCEL * absf(dir) * delta
			# the winch reels the rope in after a long attach
			rope_len = move_toward(rope_len, _rope_target, ROPE_REEL * delta)
			velocity.x -= velocity.x * 0.03 * delta
	else:
		velocity.x += dir * AIR_ACCEL * delta
		velocity.x -= velocity.x * HORIZONTAL_DRAG * delta

	velocity = velocity.limit_length(MAX_SPEED)
	position += velocity * delta

	if attached_id != -1:
		var anchor: Dictionary = level.get_anchor(attached_id)
		if anchor.is_empty():
			attached_id = -1
		else:
			var ap: Vector2 = anchor["pos"]
			var offset := position - ap
			var dist := offset.length()
			if dist > rope_len and dist > 0.001:
				var normal := offset / dist
				position = ap + normal * rope_len
				var radial := velocity.dot(normal)
				if radial > 0.0:
					velocity -= normal * radial * 1.08


func _update_trail() -> void:
	if _trail.size() > 0 and _trail[_trail.size() - 1].distance_to(position) < 2.0:
		return
	_trail.append(position)
	var limit := 20 + int(clampf(speed() / 200.0, 0.0, 8.0))
	while _trail.size() > limit:
		_trail.remove_at(0)
	if speed() < 140.0 and _trail.size() > 0 and _rng.randf() < 0.35:
		_trail.remove_at(0)
	_sync_trail_line()


func _sync_trail_line() -> void:
	if _trail_line == null:
		return
	var pts := PackedVector2Array()
	for p in _trail:
		pts.append(p - position)
	_trail_line.points = pts


func _clear_trail() -> void:
	_trail.clear()
	if _trail_line != null:
		_trail_line.clear_points()


func _update_blink() -> void:
	if invuln_time > 0.0:
		modulate.a = 0.35 if fmod(_time, 0.14) < 0.07 else 1.0
	else:
		modulate.a = 1.0


# ----------------------------------------------------------------- autopilot
func _autopilot_step(delta: float) -> void:
	_auto_hold = false
	attach_armed = true
	_reattach_block = maxf(0.0, _reattach_block - delta)
	var next_anchor: Dictionary = level.next_anchor(position)
	var aim := Vector2(position.x + 340.0, position.y - 160.0)
	if not next_anchor.is_empty():
		aim = next_anchor["pos"]
	var gap_x: float = aim.x - position.x
	_input_dir = signf(gap_x) if absf(gap_x) > 14.0 else 0.0

	if attached_id == -1:
		if velocity.y > -40.0 and _reattach_block <= 0.0:
			_auto_hold = true
		return

	var anchor: Dictionary = level.get_anchor(attached_id)
	if anchor.is_empty():
		_auto_hold = true
		return
	var ap: Vector2 = anchor["pos"]
	var dx := position.x - ap.x
	var dy := position.y - ap.y
	var forward_angle := atan2(dx, dy)
	var release := forward_angle > 1.02 and velocity.y < 130.0 and _attached_time > 0.35
	if dy < -80.0 and velocity.y > -40.0:
		release = true
	if speed() < 120.0:
		_stuck_timer += delta
	else:
		_stuck_timer = 0.0
	if _stuck_timer > 1.0:
		release = true
	_auto_hold = not release


# --------------------------------------------------------------------- draw
func _draw() -> void:
	if not alive:
		return

	if attached_id != -1:
		var anchor: Dictionary = level.get_anchor(attached_id)
		if not anchor.is_empty():
			_draw_rope(anchor["pos"] - position)

	if attached_id == -1 and candidate_id != -1:
		var target: Dictionary = level.get_anchor(candidate_id)
		if not target.is_empty():
			var tp: Vector2 = target["pos"]
			Gfx.dashed(self, Vector2.ZERO, tp - position, Color(1.0, 0.88, 0.62, 0.16), 1.8, 11.0, 10.0)

	_draw_body()


func _draw_rope(anchor_local: Vector2) -> void:
	var dist := anchor_local.length()
	var slack := maxf(0.0, rope_len - dist)
	var sag := clampf(slack * 0.5 + 2.0, 2.0, 64.0)
	var shake := 0.0
	if slack < 4.0:
		shake = sin(_time * 34.0 + position.x * 0.05) * clampf(speed() / 1400.0, 0.0, 1.0) * 3.0
	var control := anchor_local * 0.5 + Vector2(0.0, sag * 2.0 + shake)
	var segments := 12
	var points := PackedVector2Array()
	for i in segments + 1:
		var t := float(i) / float(segments)
		var one := 1.0 - t
		points.append(anchor_local * one * one + control * 2.0 * one * t)

	draw_polyline(points, Color(1.0, 0.82, 0.5, 0.10), 11.0, true)
	draw_polyline(points, Color(1.0, 0.88, 0.66, 0.55), 3.4, true)
	draw_polyline(points, Color(1.0, 0.98, 0.9, 0.9), 1.3, true)
	draw_circle(anchor_local, 4.5, Color(1.0, 0.92, 0.75, 0.95))
	if slack < 4.0:
		draw_circle(Vector2.ZERO, 7.0, Color(1.0, 0.86, 0.6, 0.35))


func _draw_body() -> void:
	var ang := velocity.angle() if speed() > 70.0 else -PI * 0.25
	draw_set_transform(Vector2.ZERO, ang, Vector2.ONE * BODY_SCALE)

	# tail fins
	draw_colored_polygon(PackedVector2Array([
		Vector2(-8.0, -8.0), Vector2(-26.0, -13.0), Vector2(-20.0, 0.0),
	]), Color(0.30, 0.62, 0.62, 0.75))
	draw_colored_polygon(PackedVector2Array([
		Vector2(-8.0, 8.0), Vector2(-26.0, 13.0), Vector2(-20.0, 0.0),
	]), Color(0.30, 0.62, 0.62, 0.75))

	Gfx.glow(self, Vector2.ZERO, 26.0, Color(0.55, 1.0, 0.88, 0.30), 4)

	# hull
	var hull := PackedVector2Array([
		Vector2(21.0, 0.0),
		Vector2(6.0, -10.0),
		Vector2(-13.0, -8.0),
		Vector2(-16.0, 0.0),
		Vector2(-13.0, 8.0),
		Vector2(6.0, 10.0),
	])
	draw_colored_polygon(hull, Color(0.12, 0.34, 0.38, 0.98))
	draw_polyline(hull, Color(0.55, 0.98, 0.86, 0.95), 1.6, true)
	# core
	draw_circle(Vector2(2.0, 0.0), 5.0, Color(0.82, 1.0, 0.95, 0.98))
	draw_circle(Vector2(2.0, 0.0), 2.2, Color(1.0, 1.0, 1.0, 1.0))
	# visor slit
	draw_line(Vector2(7.0, -4.0), Vector2(13.0, -1.0), Color(0.05, 0.12, 0.16, 0.9), 2.0, true)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if _attach_pulse > 0.0:
		var k := 1.0 - _attach_pulse
		Gfx.ring(self, Vector2.ZERO, 18.0 + k * 54.0, 2.4 * _attach_pulse, Color(1.0, 0.9, 0.7, _attach_pulse * 0.5))
	if _flash > 0.0:
		Gfx.glow(self, Vector2.ZERO, 36.0, Color(1.0, 0.45, 0.35, 0.5 * _flash), 3)
