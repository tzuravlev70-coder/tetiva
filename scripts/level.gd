extends Node2D
## Endless world: radio-tower anchors, crystals and hazards are generated ahead
## of the player in a reachable chain, then drawn in code.

const AHEAD := 2200.0
const KEEP_BEHIND := 2600.0
const FIRST_X := 300.0
const FIRST_Y := -120.0
const HAZARD_START := 3600.0
const DEATH_Y := 660.0

const GOLD := Color(1.0, 0.76, 0.38)
const GOLD_DIM := Color(0.86, 0.58, 0.26)
const CYAN := Color(0.48, 0.95, 0.86)
const CORAL := Color(1.0, 0.38, 0.32)
const INK := Color(0.03, 0.05, 0.08)

var anchors: Array[Dictionary] = []
var gems: Array[Dictionary] = []
var hazards: Array[Dictionary] = []

var rng := RandomNumberGenerator.new()
var gen_x := 0.0
var last_pos := Vector2.ZERO
var next_id := 1
var active_anchor_id := -1
var candidate_anchor_id := -1

var _by_id := {}
var _time := 0.0


func _ready() -> void:
	z_index = -5


func reset(run_seed: int) -> void:
	rng.seed = run_seed
	anchors.clear()
	gems.clear()
	hazards.clear()
	_by_id.clear()
	next_id = 1
	gen_x = 0.0
	_time = 0.0
	active_anchor_id = -1
	candidate_anchor_id = -1

	# Handcrafted, readable opening so the first seconds always teach the swing.
	_add_anchor(Vector2(FIRST_X, FIRST_Y))
	_add_anchor(Vector2(660.0, -40.0))
	_add_anchor(Vector2(1010.0, -150.0))
	gems.append(_make_gem(Vector2(470.0, 40.0), false))
	gems.append(_make_gem(Vector2(830.0, 60.0), false))

	while gen_x < AHEAD:
		_generate_next()


func ensure_ahead(player_x: float) -> void:
	while gen_x < player_x + AHEAD:
		_generate_next()
	_prune(player_x - KEEP_BEHIND)


func _prune(min_x: float) -> void:
	if anchors.is_empty():
		return
	var keep: Array[Dictionary] = []
	for a in anchors:
		var ap: Vector2 = a["pos"]
		if ap.x >= min_x:
			keep.append(a)
		else:
			_by_id.erase(a["id"])
	anchors = keep
	var gkeep: Array[Dictionary] = []
	for g in gems:
		var gp: Vector2 = g["pos"]
		if gp.x >= min_x:
			gkeep.append(g)
	gems = gkeep
	var hkeep: Array[Dictionary] = []
	for h in hazards:
		var hp: Vector2 = h["pos"]
		if hp.x >= min_x:
			hkeep.append(h)
	hazards = hkeep


# --------------------------------------------------------------- generation
func _add_anchor(pos: Vector2) -> void:
	var a := {
		"id": next_id,
		"pos": pos,
		"phase": rng.randf() * TAU,
		"spawn": _time,
	}
	next_id += 1
	anchors.append(a)
	_by_id[a["id"]] = a
	gen_x = pos.x
	last_pos = pos


func _generate_next() -> void:
	var prev := last_pos
	var d := clampf(gen_x / 24000.0, 0.0, 1.0)
	var gap := rng.randf_range(300.0, 470.0) + 50.0 * d
	var dy := rng.randf_range(-165.0, 155.0) * (1.0 - 0.45 * d)
	if rng.randf() < 0.22:
		dy *= 0.15
	var np := Vector2(gen_x + gap, clampf(last_pos.y + dy, -310.0, 90.0))
	var total := np.distance_to(prev)
	if total > 520.0:
		np = prev + (np - prev) * (520.0 / total)
		np.y = clampf(np.y, -310.0, 90.0)

	_add_anchor(np)

	# Hazards live in the lower half of the swing arcs, so a clean line exists
	# above them but sloppy swings get punished.
	if gen_x > HAZARD_START and rng.randf() < clampf(0.20 + 0.40 * d, 0.0, 0.60):
		var mid := prev.lerp(np, rng.randf_range(0.35, 0.7))
		var hp := Vector2(mid.x, maxf(prev.y, np.y) + rng.randf_range(210.0, 330.0))
		var h := {
			"pos": hp,
			"base": hp,
			"r": rng.randf_range(22.0, 30.0),
			"phase": rng.randf() * TAU,
			"kind": 1 if rng.randf() < 0.34 else 0,
			"amp": rng.randf_range(35.0, 75.0),
			"speed": rng.randf_range(0.45, 0.95),
		}
		if _clear_of_anchors(hp, 130.0):
			hazards.append(h)

	# Crystals hang under the chain: reward a deep, fast swing.
	if rng.randf() < 0.86:
		var count := rng.randi_range(2, 4)
		var drop := rng.randf_range(95.0, 185.0)
		for i in count:
			var t := 0.24 + 0.52 * float(i) / float(maxi(count - 1, 1))
			var gp := prev.lerp(np, t) + Vector2(0.0, drop + sin(t * PI) * 42.0)
			if not _clear_of_hazards(gp, 85.0):
				continue
			gems.append(_make_gem(gp, false))

	# Rare bonus crystal above the line.
	if rng.randf() < 0.10:
		var bp := prev.lerp(np, 0.5) + Vector2(0.0, -rng.randf_range(120.0, 190.0))
		if _clear_of_hazards(bp, 80.0):
			gems.append(_make_gem(bp, true))


func _make_gem(pos: Vector2, big: bool) -> Dictionary:
	return {
		"pos": pos,
		"phase": rng.randf() * TAU,
		"value": 5 if big else 1,
		"big": big,
		"taken": false,
	}


func _clear_of_anchors(pos: Vector2, margin: float) -> bool:
	for a in anchors:
		if pos.distance_to(a["pos"]) < margin:
			return false
	return true


func _clear_of_hazards(pos: Vector2, margin: float) -> bool:
	for h in hazards:
		if pos.distance_to(h["pos"]) < margin + float(h["r"]):
			return false
	return true


# --------------------------------------------------------------------- query
func get_anchor(id: int) -> Dictionary:
	if id < 0:
		return {}
	return _by_id.get(id, {})


func first_anchor() -> Dictionary:
	if anchors.is_empty():
		return {}
	return anchors[0]


func find_attach_target(pos: Vector2, radius: float, exclude_id: int = -1) -> Dictionary:
	var best: Dictionary = {}
	var best_score := INF
	for a in anchors:
		if int(a["id"]) == exclude_id:
			continue
		var ap: Vector2 = a["pos"]
		var dv := ap - pos
		var dist := dv.length()
		if dist > radius or dist < 22.0:
			continue
		if dv.y > 100.0:
			continue
		var score := dist
		if ap.x < pos.x - 40.0:
			score += 190.0
		if ap.x < pos.x - 280.0:
			score += 380.0
		score -= clampf(-dv.y, 0.0, 320.0) * 0.28
		if score < best_score:
			best_score = score
			best = a
	return best


func next_anchor(pos: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_x := INF
	for a in anchors:
		var ap: Vector2 = a["pos"]
		if ap.x > pos.x + 40.0 and ap.x < best_x:
			best_x = ap.x
			best = a
	return best


func spawn() -> Dictionary:
	return {
		"pos": Vector2(120.0, 110.0),
		"vel": Vector2(260.0, -60.0),
	}


func rescue_point(pos: Vector2) -> Dictionary:
	var a := next_anchor(pos)
	var target := Vector2(pos.x + 380.0, -80.0)
	if not a.is_empty():
		target = a["pos"]
	return {
		"pos": target + Vector2(-40.0, 210.0),
		"vel": Vector2(520.0, -140.0),
	}


# ------------------------------------------------------------------ runtime
func _process(delta: float) -> void:
	_time += delta
	for h in hazards:
		if int(h["kind"]) == 1:
			var base: Vector2 = h["base"]
			h["pos"] = base + Vector2(sin(_time * float(h["speed"]) + float(h["phase"])) * float(h["amp"]), 0.0)
	queue_redraw()


func _draw() -> void:
	var cam := get_viewport().get_camera_2d()
	var cx := 0.0
	if cam != null:
		cx = cam.get_screen_center_position().x
	var left := cx - 1000.0
	var right := cx + 1000.0

	_draw_abyss(cx)

	for h in hazards:
		var hp: Vector2 = h["pos"]
		if hp.x < left or hp.x > right:
			continue
		_draw_hazard(h)

	for g in gems:
		if bool(g["taken"]):
			continue
		var gp: Vector2 = g["pos"]
		if gp.x < left or gp.x > right:
			continue
		_draw_gem(g)

	for a in anchors:
		var ap: Vector2 = a["pos"]
		if ap.x < left or ap.x > right:
			continue
		_draw_anchor(a)


func _draw_abyss(cx: float) -> void:
	var top := 380.0
	var bottom := 840.0
	var bands := 20
	for i in bands:
		var k := float(i) / float(bands)
		var y := lerpf(top, bottom, k)
		var a := 0.03 + k * 0.34
		var col := Color(0.035, 0.045, 0.075, a).lerp(Color(0.15, 0.045, 0.07, a), k * 0.8)
		draw_rect(Rect2(cx - 1500.0, y, 3000.0, (bottom - top) / float(bands) + 2.0), col)
	# slow drifts of mist
	for i in 4:
		var ox := fmod(_time * (8.0 + i * 5.0) + i * 500.0, 1400.0) - 700.0
		var my := 430.0 + i * 62.0
		var alpha := 0.045 + 0.02 * sin(_time * 0.7 + i)
		draw_line(Vector2(cx + ox - 520.0, my), Vector2(cx + ox + 520.0, my + 6.0), Color(0.6, 0.26, 0.30, alpha), 30.0, true)


func _draw_anchor(a: Dictionary) -> void:
	var ap: Vector2 = a["pos"]
	var phase := float(a["phase"])
	var active := int(a["id"]) == active_anchor_id
	var candidate := int(a["id"]) == candidate_anchor_id
	var pulse := 0.5 + 0.5 * sin(_time * 2.2 + phase)
	var r := 18.0 + pulse * 2.0

	if active:
		Gfx.glow(self, ap, 66.0, Color(1.0, 0.82, 0.5, 0.45), 5)
		for i in 4:
			var ang := _time * 1.6 + phase + i * TAU / 4.0
			draw_line(ap + Vector2(cos(ang), sin(ang)) * (r + 5.0), ap + Vector2(cos(ang), sin(ang)) * (r + 17.0), Color(1.0, 0.85, 0.55, 0.55), 2.4, true)
	else:
		Gfx.glow(self, ap, 52.0, Color(1.0, 0.7, 0.35, 0.20 + 0.10 * pulse), 4)

	# outer cage
	draw_circle(ap, r, Color(0.07, 0.09, 0.13, 0.92))
	Gfx.ring(self, ap, r, 3.0 if active else 2.2, Color(1.0, 0.79, 0.45, 0.95 if active else 0.72))
	Gfx.ring(self, ap, r + 5.0 + pulse * 2.5, 1.2, Color(1.0, 0.79, 0.45, 0.12 + 0.10 * pulse))
	# hub
	draw_circle(ap, 5.5, Color(1.0, 0.93, 0.8, 0.95 if active else 0.75))
	# rotating satellites
	for i in 3:
		var ang := _time * (1.1 if active else 0.5) + phase + i * TAU / 3.0
		var orbit := r + 10.0
		draw_circle(ap + Vector2(cos(ang), sin(ang)) * orbit, 2.2, Color(1.0, 0.82, 0.5, 0.65))

	if candidate and not active:
		Gfx.ring(self, ap, r + 15.0 + 2.0 * pulse, 1.4, Color(1.0, 0.9, 0.7, 0.35 + 0.25 * pulse))
		draw_circle(ap + Vector2(0.0, -r - 28.0), 2.6, Color(1.0, 0.9, 0.7, 0.7))


func _draw_gem(g: Dictionary) -> void:
	var gp: Vector2 = g["pos"]
	var big := bool(g["big"])
	var phase := float(g["phase"])
	var bob := sin(_time * 2.0 + phase) * 4.0
	var pos := gp + Vector2(0.0, bob)
	var rot := phase + sin(_time * 0.8 + phase) * 0.35
	var r := (18.0 if big else 12.0) + sin(_time * 3.0 + phase) * 1.2
	Gfx.glow(self, pos, r * 3.2, Color(0.45, 0.95, 0.86, 0.42 if big else 0.26), 4)
	Gfx.diamond(self, pos, r, rot, Color(0.45, 0.95, 0.86, 0.85))
	Gfx.diamond(self, pos, r * 0.55, rot + PI / 4.0, Color(0.92, 1.0, 0.98, 0.95))
	Gfx.diamond_outline(self, pos, r + 3.5, rot, Color(0.7, 1.0, 0.95, 0.35), 1.2)
	if big:
		Gfx.ring(self, pos, r + 11.0, 1.4, Color(0.8, 1.0, 0.95, 0.35))


func _draw_hazard(h: Dictionary) -> void:
	var hp: Vector2 = h["pos"]
	var phase := float(h["phase"])
	var radius := float(h["r"])
	var pulse := 0.5 + 0.5 * sin(_time * 3.0 + phase)
	var rot := _time * 0.5 + phase
	var drift := int(h["kind"]) == 1

	if drift:
		for i in 3:
			var off := Vector2(-radius - 8.0 - i * 7.0, 0.0)
			draw_line(hp + off, hp + off + Vector2(-8.0, 0.0), Color(1.0, 0.4, 0.35, 0.10), 2.0, true)

	Gfx.glow(self, hp, radius * 3.0, Color(1.0, 0.34, 0.30, 0.20 + 0.14 * pulse), 4)
	Gfx.ring(self, hp, radius + 9.0 + pulse * 2.0, 1.4, Color(1.0, 0.42, 0.36, 0.30))
	Gfx.spikes(self, hp, radius * 0.82, radius + 10.0, 8, rot, Color(0.72, 0.20, 0.22, 0.98))
	draw_circle(hp, radius, Color(0.13, 0.065, 0.10, 1.0))
	Gfx.ring(self, hp, radius * 0.78, 1.6, Color(1.0, 0.48, 0.40, 0.55))
	draw_circle(hp, 4.2 + pulse * 1.4, Color(1.0, 0.58, 0.44, 0.95))
	# a slit that keeps the thing looking alive
	draw_line(hp + Vector2(-radius * 0.35, 2.0), hp + Vector2(radius * 0.35, 2.0), Color(0.05, 0.02, 0.03, 0.9), 3.2)
