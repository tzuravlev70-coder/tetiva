extends Node
## Tiny audio service: loads the generated WAV bank, pools SFX players and
## keeps a wind bed in sync with the player's speed.

const DIR := "res://assets/audio/"
const POOL_SIZE := 14
const MUSIC_DB := -11.0

var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _music: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _muted := false
var _music_db := MUSIC_DB


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_streams()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p)
		_pool.append(p)

	_music = AudioStreamPlayer.new()
	_music.process_mode = Node.PROCESS_MODE_ALWAYS
	_music.stream = _loop_stream(_streams.get("music"))
	_music.volume_db = MUSIC_DB
	add_child(_music)
	_music.play()

	_wind = AudioStreamPlayer.new()
	_wind.process_mode = Node.PROCESS_MODE_ALWAYS
	_wind.stream = _loop_stream(_streams.get("wind"))
	_wind.volume_db = -60.0
	add_child(_wind)
	_wind.play()

	_muted = bool(Boot.get_setting("audio", "muted", false))
	_apply_mute()


func _load_streams() -> void:
	for name in ["attach", "release", "gem", "hurt", "death", "ui", "best", "start"]:
		var path: String = DIR + "sfx_" + str(name) + ".wav"
		var res := load(path)
		if res != null:
			_streams[name] = res
	for pair in [["music", "music_loop.wav"], ["wind", "wind_loop.wav"]]:
		var res := load(DIR + String(pair[1]))
		if res != null:
			_streams[pair[0]] = res


func _loop_stream(stream: AudioStream) -> AudioStream:
	if stream == null:
		return null
	var wav := stream.duplicate() as AudioStreamWAV
	if wav == null:
		return stream
	var frames := int(round(wav.get_length() * float(wav.mix_rate)))
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = maxi(frames - 1, 1)
	return wav


# ------------------------------------------------------------------- sfx
func play(name: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if _muted or _pool.is_empty():
		return
	var stream: AudioStream = _streams.get(name)
	if stream == null:
		return
	var player := _pool[_next]
	_next = (_next + 1) % _pool.size()
	player.stream = stream
	player.pitch_scale = clampf(pitch, 0.25, 4.0)
	player.volume_db = volume_db
	player.play()


func set_wind(amount: float) -> void:
	if _wind == null:
		return
	var target := -60.0 if amount <= 0.02 else lerpf(-30.0, -13.0, clampf(amount, 0.0, 1.0))
	_wind.volume_db = lerpf(_wind.volume_db, target, 0.06)
	_wind.pitch_scale = lerpf(0.72, 1.3, clampf(amount, 0.0, 1.0))


func duck_music(ducked: bool) -> void:
	if _music == null:
		return
	_music_db = -18.0 if ducked else MUSIC_DB
	var tween := create_tween()
	tween.tween_property(_music, "volume_db", _music_db, 0.25)


func toggle_mute() -> bool:
	_muted = not _muted
	_apply_mute()
	Boot.set_setting("audio", "muted", _muted)
	return _muted


func is_muted() -> bool:
	return _muted


func music_status() -> String:
	if _music == null or _music.stream == null:
		return "none"
	var wav := _music.stream as AudioStreamWAV
	var loop_mode := -1
	var loop_end := -1
	if wav != null:
		loop_mode = wav.loop_mode
		loop_end = wav.loop_end
	return "playing=%s pos=%.2f len=%.2f loop_mode=%d loop_end=%d" % [
		str(_music.playing), _music.get_playback_position(), _music.stream.get_length(), loop_mode, loop_end
	]


func _apply_mute() -> void:
	AudioServer.set_bus_mute(0, _muted)
