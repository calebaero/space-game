extends CanvasLayer
class_name WreckRecoveryPanel

signal close_requested

@onready var title_label: Label = %TitleLabel
@onready var cargo_list: VBoxContainer = %CargoList
@onready var recover_button: Button = %RecoverButton
@onready var close_button: Button = %CloseButton

var _active_wreck: WreckBeacon = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	visible = false
	recover_button.pressed.connect(_on_recover_pressed)
	close_button.pressed.connect(_on_close_pressed)


func open_for_wreck(wreck_beacon: WreckBeacon) -> void:
	_active_wreck = wreck_beacon
	title_label.text = "Wreck Recovery"
	visible = true
	_refresh_list()


func close_panel() -> void:
	visible = false
	_active_wreck = null
	_clear_rows()


func _on_recover_pressed() -> void:
	if _active_wreck == null or not is_instance_valid(_active_wreck):
		close_panel()
		close_requested.emit()
		return

	if _active_wreck.has_method("recover_all_cargo"):
		var result: Dictionary = _active_wreck.call("recover_all_cargo")
		if bool(result.get("fully_recovered", false)):
			close_panel()
			close_requested.emit()
			return
	_refresh_list()


func _on_close_pressed() -> void:
	close_panel()
	close_requested.emit()


func _refresh_list() -> void:
	_clear_rows()
	if _active_wreck == null or not is_instance_valid(_active_wreck):
		var missing_label: Label = Label.new()
		missing_label.text = "Wreck signal lost."
		cargo_list.add_child(missing_label)
		return

	var snapshot: Array = _active_wreck.get_cargo_snapshot()
	if snapshot.is_empty():
		var empty_label: Label = Label.new()
		empty_label.text = "No recoverable cargo remains."
		cargo_list.add_child(empty_label)
		return

	for entry_variant in snapshot:
		if entry_variant is not Dictionary:
			continue
		var entry: Dictionary = entry_variant
		var resource_id: StringName = StringName(String(entry.get("resource_id", "")))
		var quantity: int = int(entry.get("quantity", 0))
		if resource_id == &"" or quantity <= 0:
			continue
		var resource_def: Dictionary = ContentDatabase.get_resource_definition(resource_id)
		var resource_name: String = String(resource_def.get("name", String(resource_id)))
		var row: Label = Label.new()
		row.text = "%s x%d" % [resource_name, quantity]
		cargo_list.add_child(row)


func _clear_rows() -> void:
	for child in cargo_list.get_children():
		child.queue_free()
