extends Control
## Left-side gradient that keeps the menu typography readable over the attract run.

@export var strength := 0.92


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w := size.x
	var h := size.y
	var steps := 38
	var width := w * 0.78
	for i in steps:
		var k := float(i) / float(steps)
		var a := pow(1.0 - k, 1.9) * strength
		draw_rect(Rect2(width * k, 0.0, width / float(steps) + 2.0, h), Color(0.012, 0.025, 0.05, a))
	draw_rect(Rect2(0.0, 0.0, w, h), Color(0.01, 0.02, 0.04, 0.16))
	# bottom fade for the footer
	for i in 8:
		var k := float(i) / 8.0
		draw_rect(Rect2(0.0, h - 90.0 + k * 90.0, w, 12.0), Color(0.01, 0.02, 0.04, 0.04 + k * 0.03))
