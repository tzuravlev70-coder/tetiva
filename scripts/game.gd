extends Node2D
## Run orchestration: scoring, hearts, hazards, camera and attract mode.

signal started
signal stats_changed(distance: int, gems: int, hearts: int, speed: float)
signal gem_collected(value: int)
signal run_ended(reason: String, distance: int, gems: int, is_record: bool)

enum Mode { ATTRACT, PLAY, OVER }

const START_HEARTS := 3
const DEATH_Y := 650.0
const METERS_PER_PIXEL := 0.05

@onready var level = $Level
@onready var player = $Player
@onready var sparks = $Sparks
@onready var camera: Camera2D = $Camera2D
@onready var fx = $FX/Overlay

var mode := Mode.ATTRACT
var alive := false
var dying := false
var hearts := START_HEARTS
var gems_taken := 0
var distance := 0
var invuln_time := 0.0
var autopilot := false
var god := false
var last_death_reason := ""

var _cam_pos := Vector2.ZERO
var _zoom := 1.0
var _shake := 0.0
var _shake_offset := Vector2.ZERO
var _time := 0.0
var _run_time := 0.0
var _attract_x := 0.0
var _attract_timer := 0.0
var _last_stats := Vector3i(-1, -1, -1)
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	player.setup(level, camera)
	fx.setup(self)
	player.rope_attached.connect(_on_rope_attached)
	player.rope_released.connect(_on_rope_released)
	_rng.randomize()
	start_attract()


# -------------------------------------------------------------------- states
func start_run() -> void:
	get_tree().paused = false
	mode = Mode.PLAY
	alive = true
	dying = false
	god = false
	autopilot = false
	hearts = START_HEARTS
	gems_taken = 0
	distance = 0
	invuln_time = 0.0
	_run_time = 0.0
	last_death_reason = ""
	level.reset(_rng.randi())
	player.autopilot = false
	player.set_trail_enabled(true)
	player.reset(level.spawn())
	var first: Dictionary = level.first_anchor()
	if not first.is_empty():
		player.start_attached(int(first["id"]), first["pos"])
		sparks.attach_fx(first["pos"])
	player.set_invuln(0.75)
	invuln_time = 0.75
	_cam_pos = player.position + Vector2(210.0, -100.0)
	camera.position = _cam_pos
	camera.zoom = Vector2(1.2, 1.2)
	_zoom = 1.2
	_shake = 0.0
	_shake_offset = Vector2.ZERO
	sparks.clear()
	fx.flash(Color(0.9, 0.8, 0.6), 0.22)
	Sfx.play("start", 1.0, -4.0)
	Sfx.set_wind(0.25)
	_emit_stats(true)
	started.emit()


func start_attract() -> void:
	get_tree().paused = false
	mode = Mode.ATTRACT
	alive = true
	dying = false
	god = true
	autopilot = true
	hearts = START_HEARTS
	gems_taken = 0
	distance = 0
	invuln_time = 0.0
	_run_time = 0.0
	_attract_x = 0.0
	_attract_timer = 0.0
	level.reset(_rng.randi())
	player.autopilot = true
	player.set_trail_enabled(false)
	player.reset(level.spawn())
	player.set_invuln(0.0)
	_cam_pos = player.position + Vector2(210.0, -20.0)
	camera.position = _cam_pos
	camera.zoom = Vector2(1.2, 1.2)
	_zoom = 1.2
	_shake = 0.0
	sparks.clear()
	_emit_stats(true)


func set_autopilot(enabled: bool) -> void:
	autopilot = enabled
	player.autopilot = enabled


func debug_kill(reason: String = "СОРВАЛСЯ ВНИЗ") -> void:
	die(reason)


# ------------------------------------------------------------------ gameplay
func _physics_process(delta: float) -> void:
	_time += delta
	match mode:
		Mode.PLAY:
			_tick_run(delta)
		Mode.ATTRACT:
			_tick_attract(delta)
		Mode.OVER:
			pass
	level.active_anchor_id = player.attached_id
	level.candidate_anchor_id = player.candidate_id
	level.ensure_ahead(player.position.x)
	sparks.tick(delta)


func _tick_run(delta: float) -> void:
	if not alive or dying:
		return
	_run_time += delta
	invuln_time = maxf(0.0, invuln_time - delta)
	distance = maxi(distance, int(maxf(player.position.x, 0.0) * METERS_PER_PIXEL))

	if player.position.y > DEATH_Y:
		die("СОРВАЛСЯ ВНИЗ")
		return

	if invuln_time <= 0.0:
		for h in level.hazards:
			var hp: Vector2 = h["pos"]
			if hp.distance_to(player.position) < float(h["r"]) + 9.0:
				_hit(hp)
				break
		if not alive:
			return

	_collect_gems()
	_emit_stats()


func _tick_attract(delta: float) -> void:
	if player.position.y > 570.0:
		_attract_rescue()
	if player.position.x > _attract_x + 12.0:
		_attract_x = player.position.x
		_attract_timer = 0.0
	else:
		_attract_timer += delta
		if _attract_timer > 3.0:
			_attract_rescue()


func _attract_rescue() -> void:
	var rp: Dictionary = level.rescue_point(player.position)
	player.warp(rp["pos"], rp["vel"])
	sparks.ring(player.position, Color(0.55, 0.9, 1.0, 0.5), 10.0, 90.0, 0.4, 2.0)
	_attract_timer = 0.0
	_attract_x = player.position.x


func _collect_gems() -> void:
	for g in level.gems:
		if bool(g["taken"]):
			continue
		var gp: Vector2 = g["pos"]
		if gp.distance_to(player.position) < 30.0:
			g["taken"] = true
			var value := int(g["value"])
			gems_taken += value
			sparks.pickup_fx(gp, bool(g["big"]))
			Sfx.play("gem", 1.0 + (0.05 if bool(g["big"]) else 0.0), -3.0)
			gem_collected.emit(value)


func _hit(from_pos: Vector2) -> void:
	hearts -= 1
	invuln_time = 1.6
	player.set_invuln(1.6)
	player.flash()
	var dir: Vector2 = (player.position - from_pos).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2(0.0, -1.0)
	# make sure the player is pushed clear of the hazard, not just nudged
	player.position = from_pos + dir * 46.0
	player.velocity = player.velocity * 0.35 + dir * 210.0
	player.clear_trail()
	sparks.hit_fx(player.position, dir)
	_shake = maxf(_shake, 17.0)
	fx.flash(Color(1.0, 0.35, 0.28), 0.6)
	Sfx.play("hurt", _rng.randf_range(0.94, 1.06), -1.0)
	if hearts <= 0:
		die("СГОРЕЛ В ЛУЧАХ")
	_emit_stats(true)


func die(reason: String) -> void:
	if mode == Mode.OVER:
		return
	alive = false
	dying = true
	mode = Mode.OVER
	last_death_reason = reason
	player.kill()
	sparks.explode_fx(player.position)
	_shake = 26.0
	fx.flash(Color(1.0, 0.42, 0.3), 0.85)
	Sfx.play("death", _rng.randf_range(0.96, 1.03))
	Sfx.set_wind(0.0)
	var is_record := Boot.report_run(distance, gems_taken)
	run_ended.emit(reason, distance, gems_taken, is_record)


func _emit_stats(force: bool = false) -> void:
	var snapshot := Vector3i(distance, gems_taken, hearts)
	if not force and snapshot == _last_stats:
		return
	_last_stats = snapshot
	stats_changed.emit(distance, gems_taken, hearts, player.speed())


func _on_rope_attached(anchor_pos: Vector2) -> void:
	if mode == Mode.ATTRACT:
		return
	Sfx.play("attach", _rng.randf_range(0.96, 1.05), -4.0)
	sparks.attach_fx(anchor_pos)
	_shake = maxf(_shake, 2.6)


func _on_rope_released(at_pos: Vector2) -> void:
	if mode == Mode.ATTRACT:
		return
	Sfx.play("release", _rng.randf_range(0.94, 1.06), -6.0)
	sparks.burst(at_pos, 7, Color(0.72, 0.92, 1.0, 0.55), 30.0, 150.0, 0.4, 1.6, 30.0)


# -------------------------------------------------------------------- camera
func _process(delta: float) -> void:
	if player == null:
		return
	var target: Vector2 = player.position + Vector2(clampf(player.velocity.x * 0.20, -70.0, 270.0), -20.0)
	if mode == Mode.PLAY and player.attached_id != -1:
		# while hanging, keep the anchor in frame too
		target.y = player.position.y - 120.0
	if mode == Mode.ATTRACT:
		target.x = player.position.x - 230.0
	target.y = clampf(target.y, -350.0, 360.0)
	var k := 1.0 - exp(-7.5 * delta)
	_cam_pos = _cam_pos.lerp(target, k)

	var target_zoom := lerpf(1.2, 1.0, clampf((player.speed() - 500.0) / 1000.0, 0.0, 1.0))
	_zoom = lerpf(_zoom, target_zoom, 1.0 - exp(-3.0 * delta))

	_shake = maxf(0.0, _shake - delta * 45.0)
	var shake_target := Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * _shake
	_shake_offset = _shake_offset.lerp(shake_target, 0.55)
	camera.position = _cam_pos + _shake_offset
	camera.zoom = Vector2.ONE * _zoom

	var spd: float = player.speed()
	var wind := 0.0
	if mode != Mode.OVER:
		wind = clampf((spd - 260.0) / 950.0, 0.0, 1.0)
		if mode == Mode.ATTRACT:
			wind *= 0.35
	Sfx.set_wind(wind)


func speed_factor() -> float:
	return clampf((player.speed() - 280.0) / 950.0, 0.0, 1.0)


func danger_level() -> float:
	var d := clampf((player.position.y - 330.0) / 260.0, 0.0, 1.0)
	if mode == Mode.PLAY and hearts <= 1:
		d = maxf(d, 0.22)
	return d
