extends Control
## Hearts row for the HUD.

var lives := 3
var max_lives := 3


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(118.0, 26.0)


func set_lives(value: int) -> void:
	if lives == value:
		return
	lives = value
	queue_redraw()


func _draw() -> void:
	for i in max_lives:
		var center := Vector2(13.0 + i * 34.0, 13.0)
		var on := i < lives
		if on:
			Gfx.glow(self, center, 15.0, Color(1.0, 0.42, 0.36, 0.4), 3)
		Gfx.diamond(self, center, 9.0, 0.0, Color(1.0, 0.48, 0.40, 0.95) if on else Color(0.45, 0.30, 0.30, 0.25))
		Gfx.diamond_outline(self, center, 11.5, 0.0, Color(1.0, 0.62, 0.5, 0.45) if on else Color(0.45, 0.32, 0.32, 0.15), 1.2)
