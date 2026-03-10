extends Panel
class_name CargoPanel

@export var simplified_mode: bool = false
@export var show_station_values: bool = true
@export var max_rows_when_simplified: int = 5

@onready var title_label: Label = %TitleLabel
@onready var rows_vbox: VBoxContainer = %RowsVBox

var _station_id: StringName = &""
var _custom_title: String = ""

const FAMILY_ORDER: Dictionary = {
	"ore": 0,
	"alloy": 1,
	"crystal": 2,
	"gas": 3,
	"commodity": 4,
	"weapon_parts": 5,
	"alien_tech": 6,
	"mission_item": 7,
}


func _ready() -> void:
	if not GameStateManager.cargo_changed.is_connected(_on_cargo_changed):
		GameStateManager.cargo_changed.connect(_on_cargo_changed)
	_refresh()


func set_station_context(station_id: StringName, show_values: bool = true) -> void:
	_station_id = station_id
	show_station_values = show_values
	_refresh()


func set_simplified_mode(enabled: bool) -> void:
	simplified_mode = enabled
	_refresh()


func set_title(text: String) -> void:
	_custom_title = text
	title_label.text = text


func refresh_panel() -> void:
	_refresh()


func _on_cargo_changed() -> void:
	_refresh()


func _refresh() -> void:
	_clear_rows()
	if _custom_title.strip_edges().is_empty():
		title_label.text = "Cargo" if simplified_mode else "Cargo Manifest"
	else:
		title_label.text = _custom_title

	var rows: Array[Dictionary] = _build_sorted_rows()
	if rows.is_empty():
		var empty_label: Label = Label.new()
		empty_label.text = "Cargo hold is empty."
		empty_label.modulate = Color(0.75, 0.8, 0.9, 0.9)
		rows_vbox.add_child(empty_label)
		return

	var max_rows: int = rows.size()
	if simplified_mode:
		max_rows = min(rows.size(), max_rows_when_simplified)

	for i in max_rows:
		_create_row(rows[i])

	if simplified_mode and rows.size() > max_rows:
		var more_label: Label = Label.new()
		more_label.text = "+%d more" % (rows.size() - max_rows)
		more_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		more_label.modulate = Color(0.68, 0.76, 0.9, 0.9)
		rows_vbox.add_child(more_label)


func _build_sorted_rows() -> Array[Dictionary]:
	var built: Array[Dictionary] = []
	for entry_variant in GameStateManager.get_cargo_manifest():
		if entry_variant is not Dictionary:
			continue
		var entry: Dictionary = entry_variant
		var quantity: int = int(entry.get("quantity", 0))
		if quantity <= 0:
			continue

		var item_id: StringName = StringName(String(entry.get("resource_id", "")))
		if item_id == &"":
			continue
		var item_def: Dictionary = ContentDatabase.get_item_definition(item_id)
		if item_def.is_empty():
			item_def = ContentDatabase.get_resource_definition(item_id)

		var name: String = String(item_def.get("name", item_id))
		var family_rank: int = _get_family_rank(item_def)
		var row: Dictionary = {
			"item_id": String(item_id),
			"name": name,
			"quantity": quantity,
			"icon_color": item_def.get("icon_color", item_def.get("family_color", Color(0.85, 0.85, 0.9, 1.0))),
			"family_rank": family_rank,
			"category": String(item_def.get("category", "")),
		}

		if show_station_values and _station_id != &"":
			var unit_value: int = EconomyManager.get_sell_price(item_id, _station_id)
			row["unit_value"] = unit_value
			row["total_value"] = unit_value * quantity

		built.append(row)

	built.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var rank_a: int = int(a.get("family_rank", 999))
		var rank_b: int = int(b.get("family_rank", 999))
		if rank_a == rank_b:
			return String(a.get("name", "")) < String(b.get("name", ""))
		return rank_a < rank_b
	)
	return built


func _create_row(row_data: Dictionary) -> void:
	var row_container: HBoxContainer = HBoxContainer.new()
	row_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_container.add_theme_constant_override("separation", 8)

	var icon: ColorRect = ColorRect.new()
	icon.color = row_data.get("icon_color", Color(0.82, 0.82, 0.86, 1.0))
	icon.custom_minimum_size = Vector2(10.0, 10.0)
	row_container.add_child(icon)

	var name_label: Label = Label.new()
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text = String(row_data.get("name", "Unknown"))
	row_container.add_child(name_label)

	var quantity_label: Label = Label.new()
	quantity_label.text = "x%d" % int(row_data.get("quantity", 0))
	quantity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	quantity_label.custom_minimum_size = Vector2(56.0, 0.0)
	row_container.add_child(quantity_label)

	if show_station_values and not simplified_mode and row_data.has("unit_value"):
		var value_label: Label = Label.new()
		value_label.text = "%d cr" % int(row_data.get("total_value", 0))
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.custom_minimum_size = Vector2(92.0, 0.0)
		value_label.modulate = Color(0.88, 0.93, 1.0, 1.0)
		row_container.add_child(value_label)

	_attach_item_tooltip(name_label, StringName(String(row_data.get("item_id", ""))))
	_attach_item_tooltip(icon, StringName(String(row_data.get("item_id", ""))))
	rows_vbox.add_child(row_container)


func _get_family_rank(item_def: Dictionary) -> int:
	var tags: Array = item_def.get("tags", [])
	for tag_variant in tags:
		var tag: String = String(tag_variant)
		if FAMILY_ORDER.has(tag):
			return int(FAMILY_ORDER[tag])

	var category: String = String(item_def.get("category", ""))
	if FAMILY_ORDER.has(category):
		return int(FAMILY_ORDER[category])
	return 999


func _clear_rows() -> void:
	for child in rows_vbox.get_children():
		child.queue_free()


func _attach_item_tooltip(control: Control, item_id: StringName) -> void:
	if control == null or item_id == &"":
		return
	var tooltip_text: String = _build_tooltip(item_id)
	control.mouse_entered.connect(func() -> void:
		UIManager.show_tooltip(tooltip_text, get_viewport().get_mouse_position())
	)
	control.mouse_exited.connect(func() -> void:
		UIManager.hide_tooltip()
	)


func _build_tooltip(item_id: StringName) -> String:
	var item_def: Dictionary = ContentDatabase.get_item_definition(item_id)
	if item_def.is_empty():
		item_def = ContentDatabase.get_resource_definition(item_id)
	if item_def.is_empty():
		return String(item_id)

	var lines: Array[String] = []
	lines.append(String(item_def.get("name", item_id)))
	lines.append(String(item_def.get("description", "No description available.")))
	if item_def.has("base_buy_value"):
		lines.append("Base Buy: %d cr" % int(item_def.get("base_buy_value", 0)))
	if item_def.has("base_sell_value"):
		lines.append("Base Sell: %d cr" % int(item_def.get("base_sell_value", 0)))
	elif item_def.has("base_value"):
		lines.append("Base Value: %d cr" % int(item_def.get("base_value", 0)))
	if bool(item_def.get("tradeable", false)):
		lines.append("Best sold at: %s" % String(item_def.get("best_sold_at", "Any")))
	return "\n".join(lines)
