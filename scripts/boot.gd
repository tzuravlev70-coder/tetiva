extends Node
## Small persistent service: input map setup + settings/records storage.

const CONFIG_PATH := "user://settings.cfg"

var best_distance := 0
var best_gems := 0
var runs := 0
var no_save := false

var _cfg := ConfigFile.new()
var _loaded := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_register_input()
	_load_config()


# ------------------------------------------------------------------ input
func _register_input() -> void:
	_action("attach", [
		_key(KEY_SPACE), _mouse(MOUSE_BUTTON_LEFT),
		_joy_button(JOY_BUTTON_A), _joy_button(JOY_BUTTON_RIGHT_SHOULDER),
	])
	_axis_for("attach", JOY_AXIS_TRIGGER_RIGHT, 1.0)

	_action("left", [
		_key(KEY_A), _key(KEY_LEFT),
		_joy_button(JOY_BUTTON_DPAD_LEFT),
	])
	_axis_for("left", JOY_AXIS_LEFT_X, -1.0)

	_action("right", [
		_key(KEY_D), _key(KEY_RIGHT),
		_joy_button(JOY_BUTTON_DPAD_RIGHT),
	])
	_axis_for("right", JOY_AXIS_LEFT_X, 1.0)

	_action("restart", [_key(KEY_R), _joy_button(JOY_BUTTON_Y)])
	_action("pause", [_key(KEY_ESCAPE), _key(KEY_P), _joy_button(JOY_BUTTON_START)])
	_action("mute", [_key(KEY_M)])


func _action(name: String, events: Array) -> void:
	if InputMap.has_action(name):
		InputMap.erase_action(name)
	InputMap.add_action(name, 0.45)
	for event in events:
		InputMap.action_add_event(name, event)


func _axis_for(name: String, axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	InputMap.action_add_event(name, event)


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	return event


func _mouse(button: MouseButton) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	return event


func _joy_button(button: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	return event


# ----------------------------------------------------------------- config
func _load_config() -> void:
	var err := _cfg.load(CONFIG_PATH)
	if err == OK:
		best_distance = int(_cfg.get_value("records", "best_distance", 0))
		best_gems = int(_cfg.get_value("records", "best_gems", 0))
		runs = int(_cfg.get_value("records", "runs", 0))
	_loaded = true


func get_setting(section: String, key: String, default_value: Variant) -> Variant:
	if not _loaded:
		_load_config()
	return _cfg.get_value(section, key, default_value)


func set_setting(section: String, key: String, value: Variant) -> void:
	_cfg.set_value(section, key, value)
	_cfg.save(CONFIG_PATH)


## Stores the run and returns true when it beat the distance record.
func report_run(distance: int, gems: int) -> bool:
	runs += 1
	var is_record := distance > best_distance
	if is_record:
		best_distance = distance
	if gems > best_gems:
		best_gems = gems
	_cfg.set_value("records", "best_distance", best_distance)
	_cfg.set_value("records", "best_gems", best_gems)
	_cfg.set_value("records", "runs", runs)
	if not no_save:
		_cfg.save(CONFIG_PATH)
	return is_record
