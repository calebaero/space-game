extends Area2D
class_name AnomalyPoint

@export var anomaly_id: StringName = &""
@export var anomaly_type: StringName = &"data_cache"

@onready var icon_label: Label = %IconLabel

var _pulse_time: float = 0.0
var _is_scanned: bool = false
var _is_consumed: bool = false


func _ready() -> void:
	add_to_group("anomaly_point")
	add_to_group("scannable_anomaly")
	monitoring = true
	monitorable = true
	set_meta("interaction_owner", self)
	set_meta("interaction_type", "anomaly_point")
	set_meta("interaction_priority", 65)
	_refresh_label()
	set_process(true)


func configure(data: Dictionary) -> void:
	anomaly_id = StringName(String(data.get("id", anomaly_id)))
	anomaly_type = StringName(String(data.get("type", anomaly_type)))
	_is_scanned = bool(data.get("scanned", false))
	_is_consumed = false

	if is_inside_tree():
		_refresh_label()
		queue_redraw()


func on_scanned(_duration: float = 5.0) -> void:
	if _is_consumed:
		return
	_is_scanned = true
	_refresh_label()
	queue_redraw()


func get_interaction_prompt() -> String:
	if _is_consumed:
		return ""
	if not _is_scanned:
		return "Scan anomaly to identify"
	return "Press E to Investigate %s" % _get_display_type_name()


func interact(_player_ship: Node) -> bool:
	if _is_consumed:
		return false
	if not _is_scanned:
		UIManager.show_toast("Anomaly requires scan.", &"warning")
		return false

	_is_consumed = true
	_apply_stub_reward()
	_refresh_label()
	queue_redraw()
	return true


func is_scanned() -> bool:
	return _is_scanned


func is_consumed() -> bool:
	return _is_consumed


func _apply_stub_reward() -> void:
	match String(anomaly_type):
		"relic_fragment":
			GameStateManager.add_relic(StringName(anomaly_type), 1)
			UIManager.show_toast("Recovered relic fragment.", &"success")
		"data_cache":
			var cache_credits: int = randi_range(35, 70)
			GameStateManager.credits += cache_credits
			UIManager.show_toast("Data cache recovered: +%d credits" % cache_credits, &"success")
		"distress_signal":
			var distress_credits: int = randi_range(25, 55)
			GameStateManager.credits += distress_credits
			UIManager.show_toast("Distress salvage secured.", &"info")
		"energy_reading":
			GameStateManager.restore_shield(18.0)
			UIManager.show_toast("Energy surge boosted shields.", &"success")
		"pirate_cache":
			GameStateManager.credits += 45
			GameStateManager.add_cargo(&"common_ore", 2)
			UIManager.show_toast("Pirate cache looted.", &"warning")
		_:
			UIManager.show_toast("Anomaly logged (stub).", &"info")


func _refresh_label() -> void:
	if _is_consumed:
		icon_label.text = "x"
		icon_label.modulate = Color(0.62, 0.62, 0.65, 0.8)
		return

	if _is_scanned:
		icon_label.text = _abbreviate_type()
		icon_label.modulate = Color(0.98, 0.94, 0.54, 1.0)
	else:
		icon_label.text = "?"
		icon_label.modulate = Color(1.0, 1.0, 1.0, 1.0)


func _abbreviate_type() -> String:
	var words: PackedStringArray = String(anomaly_type).replace("_", " ").split(" ", false)
	if words.is_empty():
		return "?"
	var abbreviation: String = ""
	for word in words:
		if word.is_empty():
			continue
		abbreviation += word.substr(0, 1).to_upper()
	return abbreviation


func _get_display_type_name() -> String:
	return String(anomaly_type).replace("_", " ").capitalize()


func _process(delta: float) -> void:
	_pulse_time += delta
	var pulse: float = 0.42 + (sin(_pulse_time * 4.0) * 0.2)
	icon_label.modulate.a = clampf(pulse, 0.2, 1.0)
	icon_label.scale = Vector2.ONE * (1.0 + pulse * 0.1)


func _draw() -> void:
	var ring_color: Color = Color(0.65, 0.35, 0.88, 0.55)
	if _is_scanned:
		ring_color = Color(0.92, 0.82, 0.35, 0.75)
	if _is_consumed:
		ring_color = Color(0.4, 0.4, 0.45, 0.5)
	draw_arc(Vector2.ZERO, 26.0, 0.0, TAU, 32, ring_color, 2.0)
