extends CanvasLayer

signal undock_requested

@onready var station_name_label: Label = %StationNameLabel
@onready var economy_label: Label = %EconomyLabel
@onready var undock_button: Button = %UndockButton
@onready var cargo_list_vbox: VBoxContainer = %CargoListVBox

var _active_station_data: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	visible = false
	undock_button.pressed.connect(_on_undock_button_pressed)
	if not GameStateManager.cargo_changed.is_connected(_on_cargo_changed):
		GameStateManager.cargo_changed.connect(_on_cargo_changed)


func open_for_station(station_data: Dictionary) -> void:
	_active_station_data = station_data.duplicate(true)
	station_name_label.text = String(_active_station_data.get("name", "Unknown Station"))
	economy_label.text = "Economy: %s" % String(_active_station_data.get("economy_type", "unknown")).capitalize()
	_refresh_cargo_list()
	visible = true


func close_menu() -> void:
	visible = false
	_active_station_data.clear()
	_clear_cargo_rows()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		undock_requested.emit()


func _on_undock_button_pressed() -> void:
	undock_requested.emit()


func _on_cargo_changed() -> void:
	if not visible:
		return
	_refresh_cargo_list()


func _refresh_cargo_list() -> void:
	_clear_cargo_rows()

	var manifest: Array[Dictionary] = GameStateManager.get_cargo_manifest()
	if manifest.is_empty():
		var empty_label: Label = Label.new()
		empty_label.text = "No cargo in hold."
		cargo_list_vbox.add_child(empty_label)
		return

	var station_economy_type: StringName = StringName(String(_active_station_data.get("economy_type", "")))
	for entry in manifest:
		var resource_id: StringName = StringName(String(entry.get("resource_id", "")))
		var quantity: int = int(entry.get("quantity", 0))
		if quantity <= 0:
			continue

		var resource_def: Dictionary = ContentDatabase.get_resource_definition(resource_id)
		var resource_name: String = String(resource_def.get("name", String(resource_id)))
		var base_value: int = int(resource_def.get("base_sell_value", 0))
		var display_value: int = base_value
		var economy_price: int = EconomyManager.get_price(resource_id, station_economy_type)
		if economy_price > 0:
			display_value = economy_price

		var row_label: Label = Label.new()
		row_label.text = "%s x%d  (Value: %d cr/unit)" % [resource_name, quantity, display_value]
		cargo_list_vbox.add_child(row_label)


func _clear_cargo_rows() -> void:
	for child in cargo_list_vbox.get_children():
		child.queue_free()
