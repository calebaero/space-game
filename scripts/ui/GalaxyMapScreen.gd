extends CanvasLayer

signal close_requested

const MAP_POSITIONS: Dictionary = {
	"anchor_station": Vector2(170, 190),
	"ferrite_belt": Vector2(340, 190),
	"red_corsair_run": Vector2(510, 190),
	"relay_market": Vector2(780, 160),
	"storm_fields": Vector2(950, 200),
	"drone_foundry": Vector2(1120, 230),
	"archive_gate": Vector2(780, 430),
	"silent_orbit": Vector2(950, 460),
	"core_bastion": Vector2(1120, 490),
}

@onready var root_control: Control = %Root
@onready var graph_canvas: Control = %GraphCanvas
@onready var connections_layer: Node2D = %ConnectionsLayer
@onready var nodes_layer: Control = %NodesLayer
@onready var detail_name_label: Label = %DetailNameLabel
@onready var detail_threat_label: Label = %DetailThreatLabel
@onready var detail_hazards_label: Label = %DetailHazardsLabel
@onready var detail_station_label: Label = %DetailStationLabel

var _current_sector_id: StringName = &""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	visible = false


func open_map(current_sector_id: StringName) -> void:
	_current_sector_id = current_sector_id
	_refresh_graph()
	_select_sector(current_sector_id)
	visible = true


func close_map() -> void:
	visible = false
	close_requested.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	if event.is_action_pressed("map_toggle") or event.is_action_pressed("cycle_target") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close_map()


func _refresh_graph() -> void:
	for child in connections_layer.get_children():
		child.queue_free()
	for child in nodes_layer.get_children():
		child.queue_free()

	var sectors: Dictionary = ContentDatabase.get_all_sectors()
	var drawn_links: Dictionary = {}

	for sector_data_variant in sectors.values():
		var sector_data: Dictionary = sector_data_variant
		var source_id: String = String(sector_data.get("id", ""))
		if source_id.is_empty() or not MAP_POSITIONS.has(source_id):
			continue

		for connection_variant in sector_data.get("connections", []):
			if connection_variant is not Dictionary:
				continue
			var connection: Dictionary = connection_variant
			var destination_id: String = String(connection.get("sector_id", ""))
			if destination_id.is_empty() or not MAP_POSITIONS.has(destination_id):
				continue

			var pair_key: String = "%s|%s" % [source_id, destination_id]
			if source_id > destination_id:
				pair_key = "%s|%s" % [destination_id, source_id]
			if drawn_links.has(pair_key):
				continue
			drawn_links[pair_key] = true

			var required_unlock: String = String(connection.get("required_unlock", ""))
			var locked: bool = not required_unlock.is_empty() and not GalaxyManager.is_galaxy_unlocked(StringName(required_unlock))
			_add_connection(MAP_POSITIONS[source_id], MAP_POSITIONS[destination_id], locked, required_unlock)

	for sector_id in MAP_POSITIONS.keys():
		if not sectors.has(sector_id):
			continue

		var sector_data: Dictionary = sectors[sector_id]
		var button: Button = Button.new()
		button.custom_minimum_size = Vector2(112, 34)
		button.position = MAP_POSITIONS[sector_id] - Vector2(56.0, 17.0)
		button.focus_mode = Control.FOCUS_NONE
		button.flat = false

		var discovered: bool = GameStateManager.is_sector_discovered(StringName(sector_id))
		if discovered:
			button.text = String(sector_data.get("name", sector_id))
			button.modulate = Color(1.0, 1.0, 1.0, 1.0)
		else:
			button.text = "?"
			button.modulate = Color(0.55, 0.55, 0.55, 1.0)

		if StringName(sector_id) == _current_sector_id:
			button.modulate = Color(0.32, 0.92, 1.0, 1.0)
			button.custom_minimum_size = Vector2(126, 38)
			button.position = MAP_POSITIONS[sector_id] - Vector2(63.0, 19.0)

		button.pressed.connect(_on_sector_button_pressed.bind(StringName(sector_id)))
		nodes_layer.add_child(button)


func _add_connection(start: Vector2, finish: Vector2, locked: bool, requirement: String) -> void:
	var color: Color = Color(0.74, 0.84, 0.96, 0.65)
	if locked:
		color = Color(0.95, 0.66, 0.28, 0.82)
		_add_dashed_line(start, finish, color)
		var lock_label: Label = Label.new()
		lock_label.text = "LOCK"
		lock_label.modulate = Color(1.0, 0.8, 0.36, 1.0)
		lock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lock_label.position = ((start + finish) * 0.5) - Vector2(30.0, 12.0)
		connections_layer.add_child(lock_label)
		if not requirement.is_empty():
			var req_label: Label = Label.new()
			req_label.text = requirement
			req_label.modulate = Color(1.0, 0.84, 0.4, 0.86)
			req_label.position = ((start + finish) * 0.5) - Vector2(54.0, -6.0)
			connections_layer.add_child(req_label)
	else:
		var line: Line2D = Line2D.new()
		line.width = 3.0
		line.default_color = color
		line.points = PackedVector2Array([start, finish])
		connections_layer.add_child(line)


func _add_dashed_line(start: Vector2, finish: Vector2, color: Color) -> void:
	var delta: Vector2 = finish - start
	var length: float = delta.length()
	if length <= 0.001:
		return

	var direction: Vector2 = delta / length
	var dash_length: float = 18.0
	var gap_length: float = 10.0
	var cursor: float = 0.0

	while cursor < length:
		var segment_end: float = minf(cursor + dash_length, length)
		var line: Line2D = Line2D.new()
		line.width = 3.0
		line.default_color = color
		line.points = PackedVector2Array([
			start + direction * cursor,
			start + direction * segment_end,
		])
		connections_layer.add_child(line)
		cursor += dash_length + gap_length


func _on_sector_button_pressed(sector_id: StringName) -> void:
	_select_sector(sector_id)


func _select_sector(sector_id: StringName) -> void:
	var sector_data: Dictionary = ContentDatabase.get_sector(sector_id)
	if sector_data.is_empty():
		return

	var discovered: bool = GameStateManager.is_sector_discovered(sector_id)
	if discovered:
		detail_name_label.text = String(sector_data.get("name", "Unknown"))
		detail_threat_label.text = "Threat: %d" % int(sector_data.get("threat_level", 0))
		var hazards: Array = sector_data.get("hazard_types", [])
		var hazard_parts: Array[String] = []
		for hazard_variant in hazards:
			hazard_parts.append(String(hazard_variant))
		detail_hazards_label.text = "Hazards: %s" % (", ".join(hazard_parts) if not hazard_parts.is_empty() else "None")
		var station_data: Dictionary = sector_data.get("station", {})
		if station_data.is_empty():
			detail_station_label.text = "Station: None"
		else:
			detail_station_label.text = "Station: %s" % String(station_data.get("name", "Unknown"))
	else:
		detail_name_label.text = "?"
		detail_threat_label.text = "Threat: Unknown"
		detail_hazards_label.text = "Hazards: Unknown"
		detail_station_label.text = "Station: Unknown"
