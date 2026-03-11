extends Node

const BUS_MASTER: StringName = &"Master"
const BUS_MUSIC: StringName = &"Music"
const BUS_SFX: StringName = &"SFX"
const SAMPLE_RATE: int = 22050
const COMBAT_RELEASE_DELAY: float = 5.0

var _music_player_a: AudioStreamPlayer = null
var _music_player_b: AudioStreamPlayer = null
var _engine_player: AudioStreamPlayer = null

var _using_music_a: bool = true
var _current_music_track: StringName = &""
var _exploration_track: StringName = &"exploration_calm"
var _combat_timer_remaining: float = 0.0
var _combat_override_active: bool = false

var _sfx_stream_cache: Dictionary = {}
var _music_stream_cache: Dictionary = {}
var _engine_stream_cache: Dictionary = {}


func _ready() -> void:
	_ensure_audio_buses()
	_music_player_a = _create_music_player("MusicA")
	_music_player_b = _create_music_player("MusicB")
	_engine_player = AudioStreamPlayer.new()
	_engine_player.name = "EngineLoop"
	_engine_player.bus = String(BUS_SFX)
	_engine_player.volume_db = -80.0
	add_child(_engine_player)
	set_process(true)


func _process(delta: float) -> void:
	if _combat_timer_remaining > 0.0:
		_combat_timer_remaining = maxf(_combat_timer_remaining - delta, 0.0)
		if _combat_timer_remaining <= 0.0 and _combat_override_active:
			_combat_override_active = false
			play_music(_exploration_track)


func play_sfx(sfx_id: StringName, _position: Vector2 = Vector2.ZERO) -> void:
	var stream: AudioStream = _get_sfx_stream(sfx_id)
	if stream == null:
		return
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.bus = String(BUS_SFX)
	player.stream = stream
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)


func play_music(track_id: StringName) -> void:
	if track_id == &"":
		return
	if _current_music_track == track_id and _get_active_music_player().playing:
		return

	var next_player: AudioStreamPlayer = _get_inactive_music_player()
	var current_player: AudioStreamPlayer = _get_active_music_player()
	next_player.stream = _get_music_stream(track_id)
	next_player.pitch_scale = 1.0
	next_player.volume_db = -80.0
	next_player.play()

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(next_player, "volume_db", _music_target_db(), 0.5)
	if current_player.playing:
		tween.tween_property(current_player, "volume_db", -80.0, 0.5)
	tween.finished.connect(func() -> void:
		if current_player.playing:
			current_player.stop()
	)

	_using_music_a = not _using_music_a
	_current_music_track = track_id


func stop_music() -> void:
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(_music_player_a, "volume_db", -80.0, 0.35)
	tween.tween_property(_music_player_b, "volume_db", -80.0, 0.35)
	tween.finished.connect(func() -> void:
		_music_player_a.stop()
		_music_player_b.stop()
	)
	_current_music_track = &""


func set_volume(bus_name: StringName, linear_value: float) -> void:
	var bus_index: int = _get_or_create_bus(bus_name)
	if bus_index < 0:
		return
	var clamped: float = clampf(linear_value, 0.0, 1.0)
	var db_value: float = -80.0 if clamped <= 0.0001 else linear_to_db(clamped)
	AudioServer.set_bus_volume_db(bus_index, db_value)


func set_exploration_context(threat_level: int, is_docked: bool = false) -> void:
	if is_docked:
		_exploration_track = &"station_ambient"
	else:
		_exploration_track = &"exploration_tense" if threat_level >= 6 else &"exploration_calm"
	if not _combat_override_active:
		play_music(_exploration_track)


func report_combat_activity() -> void:
	_combat_timer_remaining = COMBAT_RELEASE_DELAY
	if _combat_override_active:
		return
	_combat_override_active = true
	play_music(&"combat_music")


func play_boss_music() -> void:
	_combat_override_active = true
	_combat_timer_remaining = COMBAT_RELEASE_DELAY
	play_music(&"boss_music")


func end_boss_music() -> void:
	_combat_override_active = false
	_combat_timer_remaining = 0.0
	play_music(_exploration_track)


func set_engine_state(thrust_active: bool, speed_ratio: float, boost_active: bool) -> void:
	if not thrust_active and not boost_active:
		if _engine_player.playing:
			var fade_out: Tween = create_tween()
			fade_out.tween_property(_engine_player, "volume_db", -80.0, 0.12)
			fade_out.finished.connect(func() -> void:
				_engine_player.stop()
			)
		return

	var stream_key: String = "boost" if boost_active else "thrust"
	if _engine_player.stream != _get_engine_stream(stream_key):
		_engine_player.stream = _get_engine_stream(stream_key)
	if not _engine_player.playing:
		_engine_player.volume_db = -80.0
		_engine_player.play()

	_engine_player.pitch_scale = lerpf(0.85, 1.35, clampf(speed_ratio, 0.0, 1.0))
	var target_db: float = -11.0 if boost_active else -17.0
	var fade_in: Tween = create_tween()
	fade_in.tween_property(_engine_player, "volume_db", target_db, 0.08)


func _ensure_audio_buses() -> void:
	_get_or_create_bus(BUS_MUSIC, BUS_MASTER)
	_get_or_create_bus(BUS_SFX, BUS_MASTER)


func _get_or_create_bus(bus_name: StringName, send_bus: StringName = BUS_MASTER) -> int:
	var existing: int = AudioServer.get_bus_index(String(bus_name))
	if existing >= 0:
		return existing
	AudioServer.add_bus(AudioServer.bus_count)
	var index: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, String(bus_name))
	AudioServer.set_bus_send(index, String(send_bus))
	return index


func _create_music_player(player_name: String) -> AudioStreamPlayer:
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.name = player_name
	player.bus = String(BUS_MUSIC)
	player.volume_db = -80.0
	add_child(player)
	return player


func _get_active_music_player() -> AudioStreamPlayer:
	return _music_player_a if _using_music_a else _music_player_b


func _get_inactive_music_player() -> AudioStreamPlayer:
	return _music_player_b if _using_music_a else _music_player_a


func _music_target_db() -> float:
	var music_bus_index: int = AudioServer.get_bus_index(String(BUS_MUSIC))
	if music_bus_index < 0:
		return -8.0
	return AudioServer.get_bus_volume_db(music_bus_index)


func _get_sfx_stream(sfx_id: StringName) -> AudioStream:
	var key: String = String(sfx_id)
	if key.is_empty():
		return null
	if _sfx_stream_cache.has(key):
		return _sfx_stream_cache[key]

	var spec: Dictionary = _get_sfx_spec(key)
	var stream: AudioStreamWAV = _create_tone_stream(
		float(spec.get("freq", 460.0)),
		float(spec.get("duration", 0.11)),
		float(spec.get("amp", 0.23)),
		bool(spec.get("loop", false))
	)
	_sfx_stream_cache[key] = stream
	return stream


func _get_music_stream(track_id: StringName) -> AudioStream:
	var key: String = String(track_id)
	if key.is_empty():
		return _create_tone_stream(180.0, 1.8, 0.08, true)
	if _music_stream_cache.has(key):
		return _music_stream_cache[key]

	var spec: Dictionary = {
		"menu_theme": {"freq": 228.0, "duration": 2.1, "amp": 0.09},
		"exploration_calm": {"freq": 196.0, "duration": 2.0, "amp": 0.08},
		"exploration_tense": {"freq": 254.0, "duration": 1.8, "amp": 0.09},
		"combat_music": {"freq": 308.0, "duration": 1.4, "amp": 0.1},
		"boss_music": {"freq": 346.0, "duration": 1.2, "amp": 0.11},
		"station_ambient": {"freq": 172.0, "duration": 2.2, "amp": 0.07},
		"victory_fanfare": {"freq": 410.0, "duration": 1.6, "amp": 0.1},
		"death_sting": {"freq": 148.0, "duration": 0.8, "amp": 0.1},
	}
	var track_spec: Dictionary = spec.get(key, {"freq": 196.0, "duration": 2.0, "amp": 0.08})
	var stream: AudioStreamWAV = _create_tone_stream(
		float(track_spec.get("freq", 196.0)),
		float(track_spec.get("duration", 2.0)),
		float(track_spec.get("amp", 0.08)),
		true
	)
	_music_stream_cache[key] = stream
	return stream


func _get_engine_stream(kind: String) -> AudioStream:
	if _engine_stream_cache.has(kind):
		return _engine_stream_cache[kind]
	var stream: AudioStreamWAV = _create_tone_stream(220.0 if kind == "boost" else 170.0, 0.6, 0.11, true)
	_engine_stream_cache[kind] = stream
	return stream


func _create_tone_stream(freq: float, duration: float, amplitude: float, loop: bool) -> AudioStreamWAV:
	var sample_count: int = max(int(duration * float(SAMPLE_RATE)), 64)
	var data: PackedByteArray = PackedByteArray()
	data.resize(sample_count * 2)
	var amp: float = clampf(amplitude, 0.0, 1.0)
	for i in range(sample_count):
		var t: float = float(i) / float(SAMPLE_RATE)
		var sample: int = int(round(sin(TAU * freq * t) * amp * 32767.0))
		var sample_u16: int = sample & 0xFFFF
		data[i * 2] = sample_u16 & 0xFF
		data[i * 2 + 1] = (sample_u16 >> 8) & 0xFF

	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
	if loop:
		stream.loop_begin = 0
		stream.loop_end = sample_count
	return stream


func _get_sfx_spec(sfx_id: String) -> Dictionary:
	var map: Dictionary = {
		"engine_thrust": {"freq": 170.0, "duration": 0.15, "amp": 0.09},
		"engine_boost": {"freq": 240.0, "duration": 0.2, "amp": 0.12},
		"weapon_fire": {"freq": 520.0, "duration": 0.08, "amp": 0.2},
		"weapon_fire_pulse_laser": {"freq": 560.0, "duration": 0.07, "amp": 0.22},
		"weapon_fire_kinetic_cannon": {"freq": 340.0, "duration": 0.11, "amp": 0.24},
		"weapon_fire_railgun": {"freq": 690.0, "duration": 0.14, "amp": 0.26},
		"weapon_fire_missile_pod": {"freq": 310.0, "duration": 0.14, "amp": 0.24},
		"weapon_fire_emp_charge": {"freq": 460.0, "duration": 0.13, "amp": 0.23},
		"shield_hit": {"freq": 620.0, "duration": 0.08, "amp": 0.21},
		"hull_hit": {"freq": 190.0, "duration": 0.1, "amp": 0.25},
		"shield_down": {"freq": 130.0, "duration": 0.18, "amp": 0.24},
		"explosion_small": {"freq": 150.0, "duration": 0.13, "amp": 0.25},
		"explosion_large": {"freq": 110.0, "duration": 0.2, "amp": 0.27},
		"explosion_player": {"freq": 90.0, "duration": 0.24, "amp": 0.29},
		"mining_beam": {"freq": 420.0, "duration": 0.12, "amp": 0.13},
		"mining_complete": {"freq": 500.0, "duration": 0.1, "amp": 0.22},
		"scanner_pulse": {"freq": 470.0, "duration": 0.12, "amp": 0.22},
		"pickup_loot": {"freq": 640.0, "duration": 0.08, "amp": 0.18},
		"pickup_credits": {"freq": 700.0, "duration": 0.08, "amp": 0.18},
		"dock_confirm": {"freq": 360.0, "duration": 0.12, "amp": 0.2},
		"undock": {"freq": 280.0, "duration": 0.12, "amp": 0.2},
		"warp_transition": {"freq": 420.0, "duration": 0.2, "amp": 0.2},
		"ui_click": {"freq": 460.0, "duration": 0.06, "amp": 0.16},
		"ui_hover": {"freq": 540.0, "duration": 0.04, "amp": 0.1},
		"ui_buy": {"freq": 620.0, "duration": 0.07, "amp": 0.17},
		"ui_sell": {"freq": 580.0, "duration": 0.07, "amp": 0.17},
		"ui_craft": {"freq": 650.0, "duration": 0.09, "amp": 0.18},
		"cargo_full_warning": {"freq": 170.0, "duration": 0.1, "amp": 0.24},
		"boss_appear": {"freq": 180.0, "duration": 0.22, "amp": 0.27},
		"mission_accept": {"freq": 520.0, "duration": 0.09, "amp": 0.2},
		"mission_complete": {"freq": 760.0, "duration": 0.12, "amp": 0.22},
		"game_save": {"freq": 480.0, "duration": 0.08, "amp": 0.2},
		"loot_pickup": {"freq": 640.0, "duration": 0.08, "amp": 0.18},
		"market_sell": {"freq": 560.0, "duration": 0.08, "amp": 0.18},
		"market_buy": {"freq": 500.0, "duration": 0.08, "amp": 0.18},
		"upgrade_purchase": {"freq": 620.0, "duration": 0.1, "amp": 0.2},
		"module_purchase": {"freq": 600.0, "duration": 0.1, "amp": 0.2},
		"module_equip": {"freq": 540.0, "duration": 0.08, "amp": 0.18},
		"refine_complete": {"freq": 610.0, "duration": 0.1, "amp": 0.2},
		"craft_complete": {"freq": 650.0, "duration": 0.11, "amp": 0.2},
		"repair_complete": {"freq": 470.0, "duration": 0.09, "amp": 0.18},
	}
	if map.has(sfx_id):
		return map[sfx_id]
	return {"freq": 430.0, "duration": 0.08, "amp": 0.16}
