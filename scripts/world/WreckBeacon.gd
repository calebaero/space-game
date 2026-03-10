extends Area2D
class_name WreckBeacon

signal recovery_requested(beacon: WreckBeacon)

@export var wreck_id: StringName = &"active_wreck"
@export var wreck_sector_id: StringName = &""

@onready var icon_label: Label = %IconLabel

var cargo_snapshot: Array[Dictionary] = []
var _pulse_time: float = 0.0


func _ready() -> void:
	add_to_group("wreck_beacon")
	monitoring = true
	monitorable = true
	set_meta("interaction_owner", self)
	set_meta("interaction_type", "wreck_beacon")
	set_meta("interaction_priority", 88)
	set_process(true)
	_refresh_label()


func configure(data: Dictionary) -> void:
	wreck_id = StringName(String(data.get("id", wreck_id)))
	wreck_sector_id = StringName(String(data.get("sector_id", wreck_sector_id)))
	cargo_snapshot.clear()
	for entry_variant in data.get("cargo_snapshot", []):
		if entry_variant is not Dictionary:
			continue
		cargo_snapshot.append((entry_variant as Dictionary).duplicate(true))

	if is_inside_tree():
		_refresh_label()


func get_interaction_prompt() -> String:
	if cargo_snapshot.is_empty():
		return "Wreck Beacon Empty"
	return "Press E to Recover Wreck"


func interact(_player_ship: Node) -> bool:
	if cargo_snapshot.is_empty():
		UIManager.show_toast("Wreck beacon is empty.", &"info")
		return false

	UIManager.request_wreck_recovery(self)
	recovery_requested.emit(self)
	return true


func get_cargo_snapshot() -> Array[Dictionary]:
	return cargo_snapshot.duplicate(true)


func recover_all_cargo() -> Dictionary:
	var recovered: Array[Dictionary] = []
	var remaining: Array[Dictionary] = []

	for entry_variant in cargo_snapshot:
		if entry_variant is not Dictionary:
			continue
		var entry: Dictionary = (entry_variant as Dictionary).duplicate(true)
		var resource_id: StringName = StringName(String(entry.get("resource_id", "")))
		var quantity: int = max(int(entry.get("quantity", 0)), 0)
		if resource_id == &"" or quantity <= 0:
			continue

		var added: int = GameStateManager.add_cargo(resource_id, quantity)
		if added > 0:
			recovered.append({"resource_id": String(resource_id), "quantity": added})
		if added < quantity:
			remaining.append({"resource_id": String(resource_id), "quantity": quantity - added})

	cargo_snapshot = remaining
	if cargo_snapshot.is_empty():
		GameStateManager.clear_wreck_beacon_state()
		UIManager.show_toast("Wreck cargo fully recovered.", &"success")
		queue_free()
	else:
		UIManager.show_toast("Cargo hold full, some wreck cargo remains.", &"warning")

	_refresh_label()
	return {
		"recovered": recovered,
		"remaining": remaining,
		"fully_recovered": cargo_snapshot.is_empty(),
	}


func _refresh_label() -> void:
	if cargo_snapshot.is_empty():
		icon_label.text = "◇"
		icon_label.modulate = Color(0.7, 0.7, 0.72, 0.8)
	else:
		icon_label.text = "◆"
		icon_label.modulate = Color(1.0, 1.0, 1.0, 1.0)


func _process(delta: float) -> void:
	_pulse_time += delta
	var pulse: float = 0.55 + sin(_pulse_time * 3.5) * 0.35
	icon_label.scale = Vector2.ONE * (1.0 + pulse * 0.12)


func _draw() -> void:
	var color: Color = Color(1.0, 1.0, 1.0, 0.82)
	if cargo_snapshot.is_empty():
		color = Color(0.72, 0.72, 0.75, 0.68)
	var points: PackedVector2Array = PackedVector2Array([Vector2(0, -20), Vector2(18, 0), Vector2(0, 20), Vector2(-18, 0)])
	draw_colored_polygon(points, color)
	var outline: PackedVector2Array = points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, Color(0.1, 0.12, 0.16, 0.9), 2.0, true)
