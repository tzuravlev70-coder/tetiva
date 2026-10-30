extends Node
## Shell: builds all UI in code, drives the menu / run / pause / game-over flow
## and exposes the --capture / --simulate debug entry points.

enum State { MENU, PLAY, PAUSED, OVER, HELP }

const CREAM := Color(0.95, 0.90, 0.82)
const GOLD := Color(0.95, 0.72, 0.40)
const MINT := Color(0.56, 0.95, 0.86)
const CORAL := Color(1.0, 0.48, 0.40)
const INK := Color(0.035, 0.055, 0.09)
const MUTED := Color(0.72, 0.70, 0.66)

var game
var ui_layer: CanvasLayer
var root: Control
var hud: Control
var menu: Control
var over_panel: Control
var pause_panel: Control
var help_panel: Control

var distance_label: Label
var best_label: Label
var gems_label: Label
var hearts_bar: Control
var hint_label: Label
var menu_record: Label
var mute_button: Button
var play_button: Button
var over_reason: Label
var over_distance: Label
var over_line: Label
var over_record: Label
var over_retry: Button
var pause_distance: Label
var pause_resume: Button

var state := State.MENU
var _theme: Theme
var _font: SystemFont
var _title_font: FontVariation
var _over_token := 0
var _hint_tween: Tween
var _capture := ""
var _sim_seconds := 0.0
var _sim_god := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_theme()
	game = preload("res://scenes/game.tscn").instantiate()
	add_child(game)
	_build_ui()
	game.stats_changed.connect(_on_stats)
	game.run_ended.connect(_on_run_ended)
	game.gem_collected.connect(_on_gem)
	show_menu()
	_handle_cli()


# --------------------------------------------------------------------- theme
func _build_theme() -> void:
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Segoe UI", "Arial", "Noto Sans", "DejaVu Sans"])
	_font.font_weight = 400
	_title_font = FontVariation.new()
	_title_font.base_font = _font
	_title_font.spacing_glyph = 12
	_theme = Theme.new()
	_theme.default_font = _font
	_theme.default_font_size = 20


func _build_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 20
	ui_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui_layer)

	root = Control.new()
	root.name = "UIRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _theme
	ui_layer.add_child(root)

	_build_hud()
	_build_menu()
	_build_over()
	_build_pause()
	_build_help()


func _label(text: String, font_size: int, color: Color = CREAM) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _spacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0.0, height)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _rule(width: float, color: Color) -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(0.0, 3.0)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar := ColorRect.new()
	bar.color = color
	bar.size = Vector2(width, 2.0)
	bar.custom_minimum_size = Vector2(width, 2.0)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(bar)
	return wrap


func _stylebox(bg: Color, border: Color, border_width: int = 3) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_width_left = border_width
	sb.border_color = border
	sb.content_margin_left = 20.0
	sb.content_margin_right = 16.0
	sb.content_margin_top = 10.0
	sb.content_margin_bottom = 10.0
	sb.corner_radius_top_right = 2
	sb.corner_radius_bottom_right = 2
	return sb


func _button(text: String, font_size: int, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.focus_mode = Control.FOCUS_ALL
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(320.0, 52.0)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", CREAM)
	b.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	b.add_theme_color_override("font_focus_color", Color(1.0, 0.93, 0.78))
	b.add_theme_color_override("font_pressed_color", Color(1.0, 0.88, 0.68))
	b.add_theme_stylebox_override("normal", _stylebox(Color(0, 0, 0, 0), Color(0, 0, 0, 0)))
	b.add_theme_stylebox_override("hover", _stylebox(Color(1, 0.9, 0.8, 0.035), Color(GOLD, 0.35)))
	b.add_theme_stylebox_override("focus", _stylebox(Color(0.95, 0.72, 0.4, 0.07), GOLD))
	b.add_theme_stylebox_override("pressed", _stylebox(Color(GOLD, 0.18), GOLD))
	b.pressed.connect(callback)
	return b


func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(INK, 0.95)
	sb.border_color = Color(GOLD, 0.32)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 38.0
	sb.content_margin_right = 38.0
	sb.content_margin_top = 32.0
	sb.content_margin_bottom = 32.0
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	sb.shadow_size = 22
	return sb


func _panel(width: float) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _panel_style())
	p.custom_minimum_size = Vector2(width, 0.0)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p


func _center_panel(panel: PanelContainer, parent: Control) -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(panel)
	parent.add_child(center)


func _dim(parent: Control, alpha: float) -> ColorRect:
	var dim := ColorRect.new()
	dim.color = Color(0.012, 0.022, 0.04, alpha)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(dim)
	return dim


# ----------------------------------------------------------------------- HUD
func _build_hud() -> void:
	hud = Control.new()
	hud.name = "HUD"
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud)

	hearts_bar = Control.new()
	hearts_bar.set_script(load("res://scripts/lives_bar.gd"))
	hearts_bar.position = Vector2(46.0, 28.0)
	hearts_bar.size = Vector2(118.0, 26.0)
	hud.add_child(hearts_bar)

	distance_label = _label("0 м", 44, CREAM)
	distance_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	distance_label.offset_top = 14.0
	distance_label.offset_bottom = 78.0
	distance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	distance_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.55))
	distance_label.add_theme_constant_override("shadow_offset_x", 2)
	distance_label.add_theme_constant_override("shadow_offset_y", 3)
	hud.add_child(distance_label)

	best_label = _label("", 14, Color(CREAM, 0.5))
	best_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	best_label.offset_top = 82.0
	best_label.offset_bottom = 104.0
	best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(best_label)

	gems_label = _label("◆ 0", 30, MINT)
	gems_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	gems_label.offset_left = -260.0
	gems_label.offset_top = 20.0
	gems_label.offset_right = -46.0
	gems_label.offset_bottom = 62.0
	gems_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gems_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.5))
	gems_label.add_theme_constant_override("shadow_offset_x", 2)
	gems_label.add_theme_constant_override("shadow_offset_y", 2)
	hud.add_child(gems_label)

	hint_label = _label("ПРОБЕЛ / ЛКМ — держаться за верёвку    ·    A / D — маневр", 15, Color(CREAM, 0.58))
	hint_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint_label.offset_left = 46.0
	hint_label.offset_right = -46.0
	hint_label.offset_top = -62.0
	hint_label.offset_bottom = -40.0
	hud.add_child(hint_label)

	var hint2 := _label("отпусти внизу дуги — там скорость    ·    R — заново    ·    Esc — пауза", 13, Color(CREAM, 0.34))
	hint2.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint2.offset_left = 46.0
	hint2.offset_right = -46.0
	hint2.offset_top = -36.0
	hint2.offset_bottom = -18.0
	hud.add_child(hint2)

	hud.visible = false


func _build_menu() -> void:
	menu = Control.new()
	menu.name = "Menu"
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(menu)

	var shade := Control.new()
	shade.set_script(load("res://scripts/shade.gd"))
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(shade)

	var col := VBoxContainer.new()
	col.anchor_left = 0.0
	col.anchor_right = 0.0
	col.anchor_top = 0.5
	col.anchor_bottom = 0.5
	col.offset_left = 88.0
	col.offset_right = 690.0
	col.offset_top = -330.0
	col.offset_bottom = 330.0
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(col)

	var kicker := _label("2D-АРКАДА   ·   ВЕРЁВКА   ·   ЗАКАТ   ·   ПУСТОТА", 13, Color(GOLD, 0.85))
	col.add_child(kicker)
	col.add_child(_spacer(6.0))

	var title := _label("ТЕТИВА", 104, CREAM)
	title.add_theme_font_override("font", _title_font)
	title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.5))
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 4)
	col.add_child(title)

	var subtitle := _label("Цепляйся. Разгоняйся. Не смотри вниз.", 19, Color(CREAM, 0.72))
	col.add_child(subtitle)
	col.add_child(_spacer(10.0))
	col.add_child(_rule(74.0, Color(GOLD, 0.55)))
	col.add_child(_spacer(14.0))

	menu_record = _label("", 15, Color(GOLD, 0.9))
	col.add_child(menu_record)
	col.add_child(_spacer(16.0))

	play_button = _button("ИГРАТЬ", 30, start_game)
	col.add_child(play_button)
	mute_button = _button(_mute_text(), 23, _toggle_mute)
	col.add_child(_button("КАК ИГРАТЬ", 23, _open_help))
	col.add_child(mute_button)
	col.add_child(_button("ВЫХОД", 23, _quit))

	col.add_child(_spacer(18.0))
	var footer := _label("Enter / Space — старт    ·    M — звук    ·    F11 — полный экран", 12, Color(CREAM, 0.44))
	col.add_child(footer)


func _build_over() -> void:
	over_panel = Control.new()
	over_panel.name = "GameOver"
	over_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	over_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(over_panel)

	_dim(over_panel, 0.45)

	var panel := _panel(500.0)
	_center_panel(panel, over_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	box.add_child(_label("ЗАБЕГ ОКОНЧЕН", 13, Color(GOLD, 0.85)))
	over_reason = _label("СОРВАЛСЯ ВНИЗ", 34, CREAM)
	box.add_child(over_reason)
	box.add_child(_spacer(6.0))
	over_distance = _label("0 м", 58, CREAM)
	box.add_child(over_distance)
	over_line = _label("", 16, Color(CREAM, 0.62))
	box.add_child(over_line)
	over_record = _label("НОВЫЙ РЕКОРД", 19, GOLD)
	box.add_child(over_record)
	box.add_child(_spacer(18.0))

	over_retry = _button("ЕЩЁ РАЗ  ·  R", 26, start_game)
	box.add_child(over_retry)
	box.add_child(_button("В МЕНЮ  ·  Esc", 20, show_menu))
	over_panel.visible = false


func _build_pause() -> void:
	pause_panel = Control.new()
	pause_panel.name = "Pause"
	pause_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(pause_panel)

	_dim(pause_panel, 0.55)

	var panel := _panel(440.0)
	_center_panel(panel, pause_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)

	box.add_child(_label("ПАУЗА", 40, CREAM))
	box.add_child(_spacer(2.0))
	pause_distance = _label("", 15, Color(CREAM, 0.6))
	box.add_child(pause_distance)
	box.add_child(_spacer(18.0))

	pause_resume = _button("ПРОДОЛЖИТЬ  ·  Esc", 24, resume_game)
	box.add_child(pause_resume)
	box.add_child(_button("НАЧАТЬ ЗАНОВО  ·  R", 20, start_game))
	box.add_child(_button("В МЕНЮ", 20, show_menu))
	pause_panel.visible = false


func _build_help() -> void:
	help_panel = Control.new()
	help_panel.name = "Help"
	help_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	help_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(help_panel)

	_dim(help_panel, 0.72)

	var panel := _panel(720.0)
	_center_panel(panel, help_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	box.add_child(_label("КАК ИГРАТЬ", 32, CREAM))
	box.add_child(_spacer(4.0))
	box.add_child(_rule(64.0, Color(GOLD, 0.5)))
	box.add_child(_spacer(14.0))

	var rows := [
		["ПРОБЕЛ / ЛКМ", "Держи, чтобы зацепиться за ближайший якорь. Отпусти — полетишь."],
		["A / D  ·  ← →", "Маневрируй в воздухе и раскачивайся на верёвке: внизу скорость выше."],
		["R", "Начать забег заново."],
		["ESC / P", "Пауза."],
		["M", "Звук вкл/выкл."],
		["F11", "Полный экран."],
	]
	for row in rows:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 18)
		var key := _label(row[0], 15, GOLD)
		key.custom_minimum_size = Vector2(150.0, 0.0)
		hb.add_child(key)
		var desc := _label(row[1], 15, Color(CREAM, 0.8))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		desc.custom_minimum_size = Vector2(470.0, 0.0)
		hb.add_child(desc)
		box.add_child(hb)

	box.add_child(_spacer(12.0))
	var tip := _label("Совет: отпускай верёвку в нижней точке дуги — там максимальная скорость.\nГеймпад: A / RT — зацеп, стик — маневр, Y — заново, Start — пауза.", 13, Color(MINT, 0.66))
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(tip)
	box.add_child(_spacer(14.0))

	var close := _button("ПОНЯТНО  ·  Esc", 22, _close_help)
	box.add_child(close)
	help_panel.visible = false


# --------------------------------------------------------------------- state
func show_menu() -> void:
	_over_token += 1
	get_tree().paused = false
	Sfx.duck_music(false)
	state = State.MENU
	hud.visible = false
	over_panel.visible = false
	pause_panel.visible = false
	help_panel.visible = false
	menu.visible = true
	if Boot.best_distance > 0:
		menu_record.text = "ЛУЧШИЙ ЗАБЕГ — %s м   ·   ◆ %d" % [_fmt(Boot.best_distance), Boot.best_gems]
	else:
		menu_record.text = "РЕКОРД — ВПЕРЕДИ"
	mute_button.text = _mute_text()
	game.start_attract()
	play_button.grab_focus()


func start_game() -> void:
	_over_token += 1
	get_tree().paused = false
	Sfx.duck_music(false)
	state = State.PLAY
	menu.visible = false
	over_panel.visible = false
	pause_panel.visible = false
	help_panel.visible = false
	hud.visible = true
	hint_label.modulate.a = 1.0
	game.start_run()
	_on_stats(game.distance, game.gems_taken, game.hearts, 0.0)
	if Boot.best_distance > 0:
		best_label.text = "ЛУЧШИЙ — %s м" % _fmt(Boot.best_distance)
	else:
		best_label.text = "ПЕРВЫЙ ЗАБЕГ"
	get_viewport().gui_release_focus()
	_fade_hint()


func pause_game() -> void:
	if state != State.PLAY:
		return
	state = State.PAUSED
	get_tree().paused = true
	pause_distance.text = "дистанция %s м  ·  кристаллы %d" % [_fmt(game.distance), game.gems_taken]
	pause_panel.visible = true
	pause_resume.grab_focus()
	Sfx.duck_music(true)
	Sfx.set_wind(0.0)


func resume_game() -> void:
	if state != State.PAUSED:
		return
	get_tree().paused = false
	state = State.PLAY
	pause_panel.visible = false
	Sfx.duck_music(false)
	get_viewport().gui_release_focus()


func _open_help() -> void:
	if state == State.PLAY:
		pause_game()
	help_panel.visible = true
	state = State.HELP


func _close_help() -> void:
	help_panel.visible = false
	if get_tree().paused:
		state = State.PAUSED
		pause_panel.visible = true
		pause_resume.grab_focus()
	else:
		state = State.MENU
		menu.visible = true
		play_button.grab_focus()


func _quit() -> void:
	Boot.set_setting("session", "last_quit", Time.get_unix_time_from_system())
	get_tree().quit()


func _fade_hint() -> void:
	if _hint_tween != null and _hint_tween.is_valid():
		_hint_tween.kill()
	_hint_tween = create_tween()
	_hint_tween.tween_interval(6.0)
	_hint_tween.tween_property(hint_label, "modulate:a", 0.0, 1.4)


# ------------------------------------------------------------------- signals
func _on_stats(distance: int, gems: int, hearts: int, _speed: float) -> void:
	distance_label.text = "%s м" % _fmt(distance)
	gems_label.text = "◆ %d" % gems
	hearts_bar.set_lives(hearts)


func _on_gem(value: int) -> void:
	gems_label.pivot_offset = gems_label.size * 0.5
	var tw := create_tween()
	tw.tween_property(gems_label, "scale", Vector2(1.18, 1.18), 0.07)
	tw.tween_property(gems_label, "scale", Vector2.ONE, 0.18)
	_gem_popup(value)


func _gem_popup(value: int) -> void:
	var l := _label("+%d" % value, 20, MINT)
	l.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	l.offset_left = -170.0
	l.offset_top = 64.0
	l.offset_right = -46.0
	l.offset_bottom = 92.0
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud.add_child(l)
	var start_y := l.position.y
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", start_y - 26.0, 0.7)
	tw.tween_property(l, "modulate:a", 0.0, 0.7).set_delay(0.18)
	tw.chain().tween_callback(l.queue_free)


func _on_run_ended(reason: String, distance: int, gems: int, is_record: bool) -> void:
	_over_token += 1
	var token := _over_token
	state = State.OVER
	hint_label.modulate.a = 0.0
	await get_tree().create_timer(0.7, true).timeout
	if token != _over_token:
		return
	over_reason.text = reason
	over_distance.text = "%s м" % _fmt(distance)
	over_line.text = "кристаллы %d   ·   лучший %s м   ·   забег №%d" % [gems, _fmt(Boot.best_distance), Boot.runs]
	over_record.visible = is_record
	hud.visible = false
	over_panel.visible = true
	over_retry.grab_focus()
	if is_record:
		Sfx.play("best", 1.0, -2.0)


func _toggle_mute() -> void:
	Sfx.toggle_mute()
	mute_button.text = _mute_text()
	Sfx.play("ui", 1.0, -4.0)


func _mute_text() -> String:
	return "ЗВУК: ВЫКЛ" if Sfx.is_muted() else "ЗВУК: ВКЛ"


# --------------------------------------------------------------------- input
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("mute"):
		_toggle_mute()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		_toggle_fullscreen()
		get_viewport().set_input_as_handled()
		return

	match state:
		State.PLAY:
			if event.is_action_pressed("pause"):
				pause_game()
				get_viewport().set_input_as_handled()
			elif event.is_action_pressed("restart"):
				start_game()
				get_viewport().set_input_as_handled()
		State.PAUSED:
			if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
				resume_game()
				get_viewport().set_input_as_handled()
			elif event.is_action_pressed("restart"):
				start_game()
				get_viewport().set_input_as_handled()
		State.OVER:
			if event.is_action_pressed("restart"):
				start_game()
				get_viewport().set_input_as_handled()
			elif event.is_action_pressed("ui_cancel"):
				show_menu()
				get_viewport().set_input_as_handled()
		State.HELP:
			if event.is_action_pressed("ui_cancel"):
				_close_help()
				get_viewport().set_input_as_handled()


func _toggle_fullscreen() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


# ---------------------------------------------------------------- formatting
func _fmt(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = " " + out
	if value < 0:
		out = "-" + out
	return out


# ------------------------------------------------------------- debug entry
func _handle_cli() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			_capture = arg.trim_prefix("--capture=")
		elif arg.begins_with("--simulate="):
			_sim_seconds = arg.trim_prefix("--simulate=").to_float()
		elif arg == "--god":
			_sim_god = true
		elif arg == "--flowtest":
			_run_flowtest()
	if _capture != "":
		_run_capture()
	elif _sim_seconds > 0.0:
		_run_simulation()


func _run_capture() -> void:
	Boot.no_save = true
	await get_tree().process_frame
	await get_tree().process_frame
	var shot := _capture
	if shot in ["play", "over", "pause", "swing"]:
		start_game()
		if shot != "swing":
			game.set_autopilot(true)
			game.god = true
		if shot == "swing":
			# the run starts on the rope; keep the player attached for this shot
			await get_tree().create_timer(1.8, true).timeout
		else:
			await get_tree().create_timer(4.0, true).timeout
		if shot == "over":
			game.debug_kill("СОРВАЛСЯ ВНИЗ")
			await get_tree().create_timer(1.3, true).timeout
		elif shot == "pause":
			pause_game()
			await get_tree().create_timer(0.4, true).timeout
	else:
		await get_tree().create_timer(1.5, true).timeout
		if shot == "help":
			_open_help()
			await get_tree().create_timer(0.4, true).timeout
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var dir_path := "res://captures"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [dir_path, shot]
	var err := image.save_png(path)
	var cam_center: Vector2 = game.camera.get_screen_center_position()
	var zoom: Vector2 = game.camera.zoom
	var screen: Vector2 = (game.player.position - cam_center) * zoom + get_viewport().get_visible_rect().size * 0.5
	var players := get_tree().get_root().find_children("Player", "Node2D", true, false)
	var anchor_pos := Vector2.ZERO
	if game.player.attached_id != -1:
		anchor_pos = game.level.get_anchor(game.player.attached_id).get("pos", Vector2.ZERO)
	print("CAPTURE %s size=%s err=%d distance=%d mode=%d" % [path, str(image.get_size()), err, game.distance, game.mode])
	print("DIAG player=%s screen=%s cam=%s zoom=%s att=%d rope=%.0f anchor=%s players=%d trail=%d" % [
		str(game.player.position), str(screen), str(cam_center), str(zoom),
		game.player.attached_id, game.player.rope_len, str(anchor_pos), players.size(), game.player._trail.size()
	])
	get_tree().quit()


func _run_simulation() -> void:
	Boot.no_save = true
	await get_tree().process_frame
	start_game()
	game.set_autopilot(true)
	game.god = _sim_god
	Engine.time_scale = 6.0
	var elapsed := 0.0
	while elapsed < _sim_seconds:
		await get_tree().create_timer(2.0, true, false, true).timeout
		elapsed += 2.0
		print("SIM t=%4.0f x=%6.0f y=%6.0f vx=%5.0f vy=%5.0f att=%3d rope=%5.0f dist=%4d hearts=%d gems=%d" % [
			elapsed, game.player.position.x, game.player.position.y,
			game.player.velocity.x, game.player.velocity.y,
			game.player.attached_id, game.player.rope_len,
			game.distance, game.hearts, game.gems_taken
		])
		if game.mode == 2:
			break
	Engine.time_scale = 1.0
	print("SIM distance=%d hearts=%d gems=%d mode=%d state=%d reason=%s" % [
		game.distance, game.hearts, game.gems_taken, game.mode, state, game.last_death_reason
	])
	print("AUDIO ", Sfx.music_status())
	get_tree().quit()


func _run_flowtest() -> void:
	Boot.no_save = true
	await get_tree().process_frame
	var report: Array[String] = []
	start_game()
	await get_tree().create_timer(3.0, true).timeout
	report.append("idle alive=%s hearts=%d dist=%d attached=%d" % [str(game.alive), game.hearts, game.distance, game.player.attached_id])
	pause_game()
	await get_tree().create_timer(0.2, true).timeout
	report.append("pause state=%d paused=%s panel=%s" % [state, str(get_tree().paused), str(pause_panel.visible)])
	resume_game()
	await get_tree().create_timer(0.2, true).timeout
	report.append("resume state=%d paused=%s" % [state, str(get_tree().paused)])
	game.debug_kill("ТЕСТ")
	await get_tree().create_timer(1.2, true).timeout
	report.append("over state=%d panel=%s hud=%s" % [state, str(over_panel.visible), str(hud.visible)])
	start_game()
	await get_tree().create_timer(0.3, true).timeout
	report.append("retry state=%d hud=%s pause=%s" % [state, str(hud.visible), str(pause_panel.visible)])
	show_menu()
	await get_tree().create_timer(0.3, true).timeout
	report.append("menu state=%d menu=%s hud=%s" % [state, str(menu.visible), str(hud.visible)])
	_open_help()
	await get_tree().create_timer(0.2, true).timeout
	report.append("help state=%d help=%s paused=%s" % [state, str(help_panel.visible), str(get_tree().paused)])
	_close_help()
	await get_tree().create_timer(0.2, true).timeout
	report.append("help_close state=%d help=%s menu=%s" % [state, str(help_panel.visible), str(menu.visible)])
	for line in report:
		print("FLOW ", line)
	get_tree().quit()
