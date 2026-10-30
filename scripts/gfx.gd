class_name Gfx
extends RefCounted
## Shared drawing helpers for the whole game (everything is drawn in code).


static func glow(canvas: CanvasItem, pos: Vector2, radius: float, color: Color, layers: int = 4) -> void:
	var steps := maxi(layers * 2, 9)
	for i in steps:
		var k := float(i + 1) / float(steps)
		var a := color.a * pow(1.0 - k, 2.0) * 0.62
		canvas.draw_circle(pos, radius * k, Color(color, a))


static func ring(canvas: CanvasItem, pos: Vector2, radius: float, width: float, color: Color) -> void:
	canvas.draw_arc(pos, radius, 0.0, TAU, 40, color, width, true)


static func dashed(canvas: CanvasItem, a: Vector2, b: Vector2, color: Color, width: float, dash: float = 8.0, gap: float = 7.0) -> void:
	var delta := b - a
	var length := delta.length()
	if length < 0.5:
		return
	var dir := delta / length
	var t := 0.0
	while t < length:
		var end := minf(t + dash, length)
		canvas.draw_line(a + dir * t, a + dir * end, color, width, true)
		t = end + gap


static func diamond(canvas: CanvasItem, pos: Vector2, radius: float, rotation: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 4:
		var ang := rotation + i * TAU / 4.0
		pts.append(pos + Vector2(cos(ang), sin(ang)) * radius)
	canvas.draw_colored_polygon(pts, color)


static func diamond_outline(canvas: CanvasItem, pos: Vector2, radius: float, rotation: float, color: Color, width: float) -> void:
	var pts := PackedVector2Array()
	for i in 5:
		var ang := rotation + (i % 4) * TAU / 4.0
		pts.append(pos + Vector2(cos(ang), sin(ang)) * radius)
	canvas.draw_polyline(pts, color, width, true)


static func spikes(canvas: CanvasItem, pos: Vector2, inner: float, outer: float, count: int, rotation: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in count * 2:
		var ang := rotation + i * PI / float(count)
		var r := outer if i % 2 == 1 else inner
		pts.append(pos + Vector2(cos(ang), sin(ang)) * r)
	canvas.draw_colored_polygon(pts, color)


static func arrow(canvas: CanvasItem, pos: Vector2, dir: Vector2, size: float, color: Color) -> void:
	var d := dir.normalized()
	if d == Vector2.ZERO:
		return
	var side := Vector2(-d.y, d.x)
	canvas.draw_colored_polygon(PackedVector2Array([
		pos + d * size,
		pos - d * size * 0.6 + side * size * 0.55,
		pos - d * size * 0.6 - side * size * 0.55,
	]), color)


static func gradient_v(canvas: CanvasItem, rect: Rect2, top: Color, bottom: Color, steps: int = 24) -> void:
	for i in steps:
		var k := float(i) / float(steps)
		var k2 := float(i + 1) / float(steps)
		var c := top.lerp(bottom, (k + k2) * 0.5)
		canvas.draw_rect(Rect2(rect.position.x, rect.position.y + rect.size.y * k, rect.size.x, rect.size.y * (k2 - k) + 1.0), c)


static func gradient_h(canvas: CanvasItem, rect: Rect2, left: Color, right: Color, steps: int = 24) -> void:
	for i in steps:
		var k := float(i) / float(steps)
		var k2 := float(i + 1) / float(steps)
		var c := left.lerp(right, (k + k2) * 0.5)
		canvas.draw_rect(Rect2(rect.position.x + rect.size.x * k, rect.position.y, rect.size.x * (k2 - k) + 1.0, rect.size.y), c)
