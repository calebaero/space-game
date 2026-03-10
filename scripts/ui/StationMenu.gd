extends CanvasLayer

signal undock_requested
signal galaxy_map_requested

enum StationTab {
	MISSIONS,
	MARKET,
	REFINERY,
	WORKSHOP,
	UPGRADES,
	REPAIR,
	GALAXY_MAP,
}

@onready var station_name_label: Label = %StationNameLabel
@onready var economy_label: Label = %EconomyLabel
@onready var credits_label: Label = %CreditsLabel

@onready var missions_tab_button: Button = %MissionsTabButton
@onready var market_tab_button: Button = %MarketTabButton
@onready var refinery_tab_button: Button = %RefineryTabButton
@onready var workshop_tab_button: Button = %WorkshopTabButton
@onready var upgrades_tab_button: Button = %UpgradesTabButton
@onready var repair_tab_button: Button = %RepairTabButton
@onready var galaxy_map_tab_button: Button = %GalaxyMapTabButton
@onready var undock_tab_button: Button = %UndockTabButton

@onready var missions_page: Control = %MissionsPage
@onready var market_page: Control = %MarketPage
@onready var refinery_page: Control = %RefineryPage
@onready var workshop_page: Control = %WorkshopPage
@onready var upgrades_page: Control = %UpgradesPage
@onready var repair_page: Control = %RepairPage
@onready var galaxy_map_page: Control = %GalaxyMapPage

@onready var sell_rows_vbox: VBoxContainer = %SellRowsVBox
@onready var buy_rows_vbox: VBoxContainer = %BuyRowsVBox
@onready var sell_all_button: Button = %SellAllButton
@onready var quick_sell_button: Button = %QuickSellButton

@onready var refinery_rows_vbox: VBoxContainer = %RefineryRowsVBox
@onready var workshop_rows_vbox: VBoxContainer = %WorkshopRowsVBox

@onready var hull_status_label: Label = %HullStatusLabel
@onready var repair_cost_label: Label = %RepairCostLabel
@onready var full_repair_button: Button = %FullRepairButton
@onready var repair_info_label: Label = %RepairInfoLabel
@onready var open_galaxy_map_button: Button = %OpenGalaxyMapButton

@onready var station_cargo_panel: CargoPanel = %StationCargoPanel

var _active_station_data: Dictionary = {}
var _active_station_id: StringName = &""
var _active_services: Dictionary = {}
var _active_tab: StationTab = StationTab.MARKET

var _tab_pages: Dictionary = {}
var _tab_buttons: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	visible = false
	set_process(true)

	_tab_pages = {
		StationTab.MISSIONS: missions_page,
		StationTab.MARKET: market_page,
		StationTab.REFINERY: refinery_page,
		StationTab.WORKSHOP: workshop_page,
		StationTab.UPGRADES: upgrades_page,
		StationTab.REPAIR: repair_page,
		StationTab.GALAXY_MAP: galaxy_map_page,
	}
	_tab_buttons = {
		StationTab.MISSIONS: missions_tab_button,
		StationTab.MARKET: market_tab_button,
		StationTab.REFINERY: refinery_tab_button,
		StationTab.WORKSHOP: workshop_tab_button,
		StationTab.UPGRADES: upgrades_tab_button,
		StationTab.REPAIR: repair_tab_button,
		StationTab.GALAXY_MAP: galaxy_map_tab_button,
	}

	missions_tab_button.pressed.connect(func() -> void: _switch_tab(StationTab.MISSIONS))
	market_tab_button.pressed.connect(func() -> void: _switch_tab(StationTab.MARKET))
	refinery_tab_button.pressed.connect(func() -> void: _switch_tab(StationTab.REFINERY))
	workshop_tab_button.pressed.connect(func() -> void: _switch_tab(StationTab.WORKSHOP))
	upgrades_tab_button.pressed.connect(func() -> void: _switch_tab(StationTab.UPGRADES))
	repair_tab_button.pressed.connect(func() -> void: _switch_tab(StationTab.REPAIR))
	galaxy_map_tab_button.pressed.connect(func() -> void: _switch_tab(StationTab.GALAXY_MAP))
	undock_tab_button.pressed.connect(_on_undock_button_pressed)

	sell_all_button.pressed.connect(_on_sell_all_pressed)
	quick_sell_button.pressed.connect(_on_quick_sell_pressed)
	full_repair_button.pressed.connect(_on_full_repair_pressed)
	open_galaxy_map_button.pressed.connect(_on_open_galaxy_map_pressed)

	if not GameStateManager.cargo_changed.is_connected(_on_cargo_changed):
		GameStateManager.cargo_changed.connect(_on_cargo_changed)
	if not GameStateManager.hull_changed.is_connected(_on_hull_changed):
		GameStateManager.hull_changed.connect(_on_hull_changed)

	_switch_tab(StationTab.MARKET, true)


func _process(_delta: float) -> void:
	if not visible:
		return
	credits_label.text = "Credits: %d" % GameStateManager.credits


func open_for_station(station_data: Dictionary) -> void:
	_active_station_data = station_data.duplicate(true)
	_active_station_id = StringName(String(_active_station_data.get("id", "")))

	station_name_label.text = String(_active_station_data.get("name", "Unknown Station"))
	var economy_type: String = String(_active_station_data.get("economy_type", "unknown"))
	economy_label.text = "Economy: %s" % economy_type.capitalize()
	credits_label.text = "Credits: %d" % GameStateManager.credits

	_populate_service_flags()
	_apply_service_availability()

	if station_cargo_panel != null:
		station_cargo_panel.set_station_context(_active_station_id, true)
		station_cargo_panel.set_title("Cargo Review")
		station_cargo_panel.refresh_panel()

	_refresh_all_tab_content()
	_switch_tab(_find_first_available_tab(), true)
	UIManager.hide_tooltip()
	visible = true


func close_menu() -> void:
	visible = false
	_active_station_data.clear()
	_active_station_id = &""
	_active_services.clear()
	_clear_dynamic_rows()
	UIManager.hide_tooltip()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		undock_requested.emit()
		return
	if event.is_action_pressed("map_toggle") and _has_service("galaxy_map"):
		get_viewport().set_input_as_handled()
		galaxy_map_requested.emit()


func _populate_service_flags() -> void:
	_active_services.clear()
	var services: Array = _active_station_data.get("services", [])
	if services.is_empty():
		for fallback_service in ["missions", "market_sell", "market_buy", "refinery", "workshop", "upgrades", "repair", "galaxy_map"]:
			_active_services[fallback_service] = true
		return

	for service_variant in services:
		var service_name: String = String(service_variant)
		if service_name.is_empty():
			continue
		if service_name == "market":
			_active_services["market_sell"] = true
			_active_services["market_buy"] = true
			continue
		if service_name == "sell_only_market":
			_active_services["market_sell"] = true
			continue
		_active_services[service_name] = true


func _apply_service_availability() -> void:
	_set_tab_enabled(StationTab.MISSIONS, _has_service("missions"))
	_set_tab_enabled(StationTab.MARKET, _has_service("market_sell") or _has_service("market_buy"))
	_set_tab_enabled(StationTab.REFINERY, _has_service("refinery"))
	_set_tab_enabled(StationTab.WORKSHOP, _has_service("workshop"))
	_set_tab_enabled(StationTab.UPGRADES, _has_service("upgrades"))
	_set_tab_enabled(StationTab.REPAIR, _has_service("repair"))
	_set_tab_enabled(StationTab.GALAXY_MAP, _has_service("galaxy_map"))


func _set_tab_enabled(tab: StationTab, enabled: bool) -> void:
	if not _tab_buttons.has(tab):
		return
	var button: Button = _tab_buttons[tab]
	button.disabled = not enabled
	button.modulate = Color(1.0, 1.0, 1.0, 1.0) if enabled else Color(0.55, 0.58, 0.66, 0.9)


func _find_first_available_tab() -> StationTab:
	for tab in [StationTab.MARKET, StationTab.REPAIR, StationTab.MISSIONS, StationTab.REFINERY, StationTab.WORKSHOP, StationTab.UPGRADES, StationTab.GALAXY_MAP]:
		var button: Button = _tab_buttons.get(tab, null)
		if button != null and not button.disabled:
			return tab
	return StationTab.MISSIONS


func _switch_tab(next_tab: StationTab, force: bool = false) -> void:
	if not force:
		var button: Button = _tab_buttons.get(next_tab, null)
		if button != null and button.disabled:
			UIManager.show_toast("Service unavailable at this station.", &"warning")
			return

	_active_tab = next_tab
	for tab_key_variant in _tab_pages.keys():
		var tab_key: StationTab = tab_key_variant
		var page: Control = _tab_pages[tab_key]
		page.visible = tab_key == _active_tab

	for tab_button_key_variant in _tab_buttons.keys():
		var tab_button_key: StationTab = tab_button_key_variant
		var tab_button: Button = _tab_buttons[tab_button_key]
		if tab_button.disabled:
			tab_button.button_pressed = false
			continue
		tab_button.button_pressed = tab_button_key == _active_tab

	UIManager.hide_tooltip()


func _refresh_all_tab_content() -> void:
	UIManager.hide_tooltip()
	_refresh_market_tab()
	_refresh_refinery_tab()
	_refresh_workshop_tab()
	_refresh_repair_tab()
	if station_cargo_panel != null:
		station_cargo_panel.refresh_panel()


func _refresh_market_tab() -> void:
	_clear_container(sell_rows_vbox)
	_clear_container(buy_rows_vbox)

	var can_sell: bool = _has_service("market_sell")
	var can_buy: bool = _has_service("market_buy")
	sell_all_button.disabled = not can_sell
	quick_sell_button.disabled = not can_sell

	if can_sell:
		var sell_entries: Array[Dictionary] = _get_sellable_entries(false)
		var quick_entries: Array[Dictionary] = _get_sellable_entries(true)
		if sell_entries.is_empty():
			_add_info_label(sell_rows_vbox, "No sellable cargo currently in hold.")
			sell_all_button.disabled = true
			quick_sell_button.disabled = true
		else:
			sell_all_button.disabled = false
			quick_sell_button.disabled = quick_entries.is_empty()
			for entry in sell_entries:
				_create_sell_row(entry)
	else:
		_add_info_label(sell_rows_vbox, "This station does not buy cargo.")

	if can_buy:
		var offers: Array[Dictionary] = EconomyManager.get_station_commodity_offers(_active_station_id)
		if offers.is_empty():
			_add_info_label(buy_rows_vbox, "No commodity listings available.")
		else:
			for offer in offers:
				_create_buy_row(offer)
	else:
		_add_info_label(buy_rows_vbox, "This station only offers sell services.")


func _refresh_refinery_tab() -> void:
	_clear_container(refinery_rows_vbox)
	if not _has_service("refinery"):
		_add_info_label(refinery_rows_vbox, "Refinery service unavailable at this station.")
		return

	var economy_type: String = String(_active_station_data.get("economy_type", ""))
	var shown_any: bool = false
	for recipe in ContentDatabase.get_refining_recipes():
		var station_types: Array = recipe.get("station_types", [])
		if not station_types.has(economy_type):
			continue
		shown_any = true
		_create_recipe_row(refinery_rows_vbox, recipe, true)

	if not shown_any:
		_add_info_label(refinery_rows_vbox, "No refining recipes supported by this station type.")


func _refresh_workshop_tab() -> void:
	_clear_container(workshop_rows_vbox)
	if not _has_service("workshop"):
		_add_info_label(workshop_rows_vbox, "Workshop service unavailable at this station.")
		return

	var shown_any: bool = false
	for recipe in ContentDatabase.get_crafting_recipes():
		shown_any = true
		_create_recipe_row(workshop_rows_vbox, recipe, false)
	if not shown_any:
		_add_info_label(workshop_rows_vbox, "No workshop recipes configured.")


func _refresh_repair_tab() -> void:
	if not _has_service("repair"):
		hull_status_label.text = "Repair service unavailable at this station."
		repair_cost_label.text = ""
		repair_info_label.text = ""
		full_repair_button.disabled = true
		return

	var max_hull: float = GameStateManager.get_max_hull()
	var current_hull: float = GameStateManager.get_current_hull()
	var missing_hull: float = maxf(max_hull - current_hull, 0.0)
	var repair_cost: int = int(ceil(missing_hull * 2.0))

	hull_status_label.text = "Hull: %.0f / %.0f" % [current_hull, max_hull]
	repair_cost_label.text = "Cost: %d credits" % repair_cost

	if missing_hull <= 0.0:
		repair_info_label.text = "Ship in good condition."
		full_repair_button.disabled = true
	else:
		repair_info_label.text = "Full repairs cost 2 credits per missing hull point."
		full_repair_button.disabled = GameStateManager.credits < repair_cost


func _create_sell_row(entry: Dictionary) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var icon: ColorRect = ColorRect.new()
	icon.color = entry.get("icon_color", Color(0.86, 0.86, 0.9, 1.0))
	icon.custom_minimum_size = Vector2(10.0, 10.0)
	row.add_child(icon)

	var item_name: String = String(entry.get("name", "Unknown"))
	var item_label: Label = Label.new()
	item_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_label.text = item_name
	row.add_child(item_label)

	var quantity: int = int(entry.get("quantity", 0))
	var quantity_label: Label = Label.new()
	quantity_label.text = "x%d" % quantity
	quantity_label.custom_minimum_size = Vector2(54.0, 0.0)
	quantity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(quantity_label)

	var unit_price: int = int(entry.get("unit_price", 0))
	var value_label: Label = Label.new()
	value_label.custom_minimum_size = Vector2(130.0, 0.0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.text = "%d cr (%d)" % [unit_price * quantity, unit_price]
	row.add_child(value_label)

	var sell_button: Button = Button.new()
	sell_button.text = "Sell"
	sell_button.custom_minimum_size = Vector2(70.0, 0.0)
	var item_id: StringName = StringName(String(entry.get("item_id", "")))
	sell_button.pressed.connect(func() -> void:
		var earned: int = EconomyManager.sell_cargo(item_id, quantity, _active_station_id)
		if earned > 0:
			UIManager.show_toast("+%d credits" % earned, &"success")
			_refresh_all_tab_content()
	)
	row.add_child(sell_button)

	_attach_tooltip(item_label, item_id)
	_attach_tooltip(value_label, item_id)
	sell_rows_vbox.add_child(row)


func _create_buy_row(offer: Dictionary) -> void:
	var row: VBoxContainer = VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var top: HBoxContainer = HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)

	var icon: ColorRect = ColorRect.new()
	icon.color = offer.get("icon_color", Color(0.86, 0.86, 0.9, 1.0))
	icon.custom_minimum_size = Vector2(10.0, 10.0)
	top.add_child(icon)

	var item_name: String = String(offer.get("name", "Unknown"))
	var item_label: Label = Label.new()
	item_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_label.text = item_name
	top.add_child(item_label)

	var available_quantity: int = int(offer.get("available_quantity", 0))
	var stock_label: Label = Label.new()
	stock_label.text = "Stock: %d" % available_quantity
	stock_label.custom_minimum_size = Vector2(92.0, 0.0)
	stock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(stock_label)

	var buy_price: int = int(offer.get("buy_price", 0))
	var price_label: Label = Label.new()
	price_label.text = "%d cr" % buy_price
	price_label.custom_minimum_size = Vector2(72.0, 0.0)
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(price_label)

	row.add_child(top)

	var button_row: HBoxContainer = HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 6)
	row.add_child(button_row)

	var item_id: StringName = StringName(String(offer.get("item_id", "")))
	for amount in [1, 5, 10]:
		var buy_amount: int = amount
		var button: Button = Button.new()
		button.text = "Buy %d" % buy_amount
		button.disabled = available_quantity < buy_amount
		button.pressed.connect(func() -> void:
			if EconomyManager.buy_commodity(item_id, buy_amount, _active_station_id):
				_refresh_all_tab_content()
		)
		button_row.add_child(button)

	var max_buy: int = min(available_quantity, _compute_max_buy(item_id, buy_price, available_quantity))
	var buy_max_amount: int = max_buy
	var max_button: Button = Button.new()
	max_button.text = "Buy Max"
	max_button.disabled = buy_max_amount <= 0
	max_button.pressed.connect(func() -> void:
		if buy_max_amount <= 0:
			return
		if EconomyManager.buy_commodity(item_id, buy_max_amount, _active_station_id):
			_refresh_all_tab_content()
	)
	button_row.add_child(max_button)

	_attach_tooltip(item_label, item_id)
	_attach_tooltip(price_label, item_id)
	buy_rows_vbox.add_child(row)


func _create_recipe_row(target_container: VBoxContainer, recipe: Dictionary, is_refining: bool) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.mouse_filter = Control.MOUSE_FILTER_PASS

	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.12, 0.2, 0.8)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.24, 0.44, 0.78, 0.7)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	style.corner_radius_bottom_left = 4
	panel.add_theme_stylebox_override("panel", style)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	var title: Label = Label.new()
	title.text = String(recipe.get("name", "Recipe"))
	vbox.add_child(title)

	var description: Label = Label.new()
	description.text = String(recipe.get("description", ""))
	description.modulate = Color(0.74, 0.8, 0.92, 0.95)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(description)

	var flow_row: HBoxContainer = HBoxContainer.new()
	flow_row.add_theme_constant_override("separation", 6)
	flow_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(flow_row)

	var inputs: Array = recipe.get("inputs", [])
	for input_variant in inputs:
		if input_variant is not Dictionary:
			continue
		var input_data: Dictionary = input_variant
		var input_chip: Button = _create_item_chip(StringName(String(input_data.get("item_id", ""))), int(input_data.get("quantity", 1)), true)
		flow_row.add_child(input_chip)

	var arrow: Label = Label.new()
	arrow.text = "->"
	flow_row.add_child(arrow)

	var outputs: Array = recipe.get("outputs", [])
	for output_variant in outputs:
		if output_variant is not Dictionary:
			continue
		var output_data: Dictionary = output_variant
		var output_chip: Button = _create_item_chip(StringName(String(output_data.get("item_id", ""))), int(output_data.get("quantity", 1)), false)
		flow_row.add_child(output_chip)

	var requirements_label: Label = Label.new()
	requirements_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	requirements_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(requirements_label)

	var action_row: HBoxContainer = HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 6)
	action_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(action_row)

	var action_button: Button = Button.new()
	action_button.text = "Refine" if is_refining else "Craft"
	action_button.custom_minimum_size = Vector2(120.0, 0.0)
	action_row.add_child(action_button)

	if is_refining:
		var can_run_refinery: bool = _can_execute_refinery_recipe(recipe)
		requirements_label.text = "Ready" if can_run_refinery else "REQUIREMENTS NOT MET"
		requirements_label.modulate = Color(0.5, 0.95, 0.58, 1.0) if can_run_refinery else Color(1.0, 0.4, 0.4, 1.0)
		action_button.disabled = not can_run_refinery
		action_button.pressed.connect(func() -> void:
			if _execute_refinery_recipe(recipe):
				_refresh_all_tab_content()
		)
	else:
		var workshop_check: Dictionary = _check_workshop_recipe_requirements(recipe)
		var can_craft: bool = bool(workshop_check.get("can_craft", false))
		if can_craft:
			requirements_label.text = "Ready"
			requirements_label.modulate = Color(0.5, 0.95, 0.58, 1.0)
		else:
			requirements_label.text = "REQUIREMENTS NOT MET\n%s" % String(workshop_check.get("missing_text", ""))
			requirements_label.modulate = Color(1.0, 0.4, 0.4, 1.0)
		action_button.disabled = not can_craft
		action_button.pressed.connect(func() -> void:
			if _execute_workshop_recipe(recipe):
				_refresh_all_tab_content()
		)

	target_container.add_child(panel)


func _create_item_chip(item_id: StringName, quantity: int, is_input: bool) -> Button:
	var item_def: Dictionary = ContentDatabase.get_item_definition(item_id)
	var item_name: String = String(item_def.get("name", item_id))
	var chip: Button = Button.new()
	chip.text = "%s x%d" % [item_name, max(quantity, 1)]
	chip.flat = true
	chip.focus_mode = Control.FOCUS_NONE
	chip.disabled = true
	chip.modulate = Color(0.9, 0.96, 1.0, 1.0) if is_input else Color(0.62, 0.96, 0.72, 1.0)
	_attach_tooltip(chip, item_id)
	return chip


func _can_execute_refinery_recipe(recipe: Dictionary) -> bool:
	if not _has_required_inputs(recipe.get("inputs", []), false):
		return false
	return _has_output_capacity(recipe.get("outputs", []))


func _execute_refinery_recipe(recipe: Dictionary) -> bool:
	if not _can_execute_refinery_recipe(recipe):
		UIManager.show_toast("Requirements not met for this refining recipe.", &"warning")
		return false
	if not _consume_requirements(recipe.get("inputs", []), []):
		UIManager.show_toast("Refining failed due to missing inputs.", &"warning")
		return false
	_apply_outputs(recipe.get("outputs", []))
	UIManager.show_toast("Refining complete.", &"success")
	AudioManager.play_sfx(&"refine_complete", Vector2.ZERO)
	return true


func _check_workshop_recipe_requirements(recipe: Dictionary) -> Dictionary:
	var missing: Array[String] = []
	if not _has_required_inputs(recipe.get("inputs", []), false):
		for requirement_variant in recipe.get("inputs", []):
			if requirement_variant is not Dictionary:
				continue
			var requirement: Dictionary = requirement_variant
			var item_id: StringName = StringName(String(requirement.get("item_id", "")))
			var required_quantity: int = int(requirement.get("quantity", 0))
			if GameStateManager.has_cargo(item_id, required_quantity):
				continue
			missing.append("%s x%d" % [_get_item_name(item_id), required_quantity])

	for story_variant in recipe.get("story_requirements", []):
		if story_variant is not Dictionary:
			continue
		var story_requirement: Dictionary = story_variant
		var story_item_id: StringName = StringName(String(story_requirement.get("item_id", "")))
		var story_qty: int = int(story_requirement.get("quantity", 0))
		if GameStateManager.get_relic_quantity(story_item_id) < story_qty:
			missing.append("%s x%d" % [_get_item_name(story_item_id), story_qty])

	var credits_cost: int = int(recipe.get("credits_cost", 0))
	if GameStateManager.credits < credits_cost:
		missing.append("%d credits" % credits_cost)

	if bool(recipe.get("blueprint_required", false)):
		var recipe_id: String = String(recipe.get("id", ""))
		var blueprint_flag: StringName = StringName("blueprint_%s" % recipe_id)
		if not GameStateManager.has_progression_flag(blueprint_flag):
			missing.append("Blueprint")

	if not _has_output_capacity(recipe.get("outputs", [])):
		missing.append("Cargo space")

	return {
		"can_craft": missing.is_empty(),
		"missing_text": ", ".join(missing),
	}


func _execute_workshop_recipe(recipe: Dictionary) -> bool:
	var check: Dictionary = _check_workshop_recipe_requirements(recipe)
	if not bool(check.get("can_craft", false)):
		UIManager.show_toast("Crafting requirements not met.", &"warning")
		return false

	var credits_cost: int = int(recipe.get("credits_cost", 0))
	if GameStateManager.credits < credits_cost:
		UIManager.show_toast("Insufficient credits.", &"warning")
		return false

	if not _consume_requirements(recipe.get("inputs", []), recipe.get("story_requirements", [])):
		UIManager.show_toast("Missing required components.", &"warning")
		return false

	GameStateManager.credits -= credits_cost
	_apply_outputs(recipe.get("outputs", []))

	var progression_flag: StringName = StringName(String(recipe.get("progression_flag", "")))
	if progression_flag != &"":
		GameStateManager.set_progression_flag(progression_flag, true)
	var unlock_target: String = String(recipe.get("unlock_target", ""))
	if not unlock_target.is_empty():
		UIManager.show_toast("%s crafted. Unlock handling continues in Phase 06." % String(recipe.get("name", "Item")), &"success")
	else:
		UIManager.show_toast("Craft complete.", &"success")

	AudioManager.play_sfx(&"craft_complete", Vector2.ZERO)
	return true


func _has_required_inputs(requirements: Array, include_story_inventory: bool) -> bool:
	for requirement_variant in requirements:
		if requirement_variant is not Dictionary:
			continue
		var requirement: Dictionary = requirement_variant
		var item_id: StringName = StringName(String(requirement.get("item_id", "")))
		var quantity: int = int(requirement.get("quantity", 0))
		if quantity <= 0:
			continue
		if include_story_inventory and GameStateManager.get_relic_quantity(item_id) >= quantity:
			continue
		if not GameStateManager.has_cargo(item_id, quantity):
			return false
	return true


func _consume_requirements(inputs: Array, story_requirements: Array) -> bool:
	for requirement_variant in inputs:
		if requirement_variant is not Dictionary:
			continue
		var requirement: Dictionary = requirement_variant
		var item_id: StringName = StringName(String(requirement.get("item_id", "")))
		var quantity: int = int(requirement.get("quantity", 0))
		if quantity <= 0:
			continue
		if not GameStateManager.has_cargo(item_id, quantity):
			return false

	for story_variant in story_requirements:
		if story_variant is not Dictionary:
			continue
		var story_requirement: Dictionary = story_variant
		var story_item_id: StringName = StringName(String(story_requirement.get("item_id", "")))
		var story_qty: int = int(story_requirement.get("quantity", 0))
		if GameStateManager.get_relic_quantity(story_item_id) < story_qty:
			return false

	for requirement_variant in inputs:
		if requirement_variant is not Dictionary:
			continue
		var requirement_to_remove: Dictionary = requirement_variant
		var remove_item_id: StringName = StringName(String(requirement_to_remove.get("item_id", "")))
		var remove_qty: int = int(requirement_to_remove.get("quantity", 0))
		if remove_qty <= 0:
			continue
		GameStateManager.remove_cargo(remove_item_id, remove_qty)

	for story_variant in story_requirements:
		if story_variant is not Dictionary:
			continue
		var story_remove: Dictionary = story_variant
		var remove_story_id: StringName = StringName(String(story_remove.get("item_id", "")))
		var remove_story_qty: int = int(story_remove.get("quantity", 0))
		if remove_story_qty <= 0:
			continue
		GameStateManager.remove_cargo(remove_story_id, remove_story_qty)

	return true


func _apply_outputs(outputs: Array) -> void:
	for output_variant in outputs:
		if output_variant is not Dictionary:
			continue
		var output_data: Dictionary = output_variant
		var output_item_id: StringName = StringName(String(output_data.get("item_id", "")))
		var output_qty: int = int(output_data.get("quantity", 0))
		if output_qty <= 0:
			continue
		GameStateManager.add_cargo(output_item_id, output_qty)


func _has_output_capacity(outputs: Array) -> bool:
	var needed_slots: int = 0
	for output_variant in outputs:
		if output_variant is not Dictionary:
			continue
		var output_data: Dictionary = output_variant
		var output_item_id: StringName = StringName(String(output_data.get("item_id", "")))
		var output_qty: int = int(output_data.get("quantity", 0))
		if output_qty <= 0:
			continue
		var item_def: Dictionary = ContentDatabase.get_item_definition(output_item_id)
		if bool(item_def.get("store_in_relic_inventory", false)):
			continue
		var cargo_size: int = int(item_def.get("cargo_size", 1))
		needed_slots += max(cargo_size, 1) * output_qty
	return GameStateManager.get_cargo_free() >= needed_slots


func _compute_max_buy(item_id: StringName, unit_price: int, available_quantity: int) -> int:
	if unit_price <= 0:
		return 0
	var affordable: int = int(GameStateManager.credits / unit_price)
	var capped_by_stock: int = min(affordable, available_quantity)
	var capped_by_cargo: int = min(capped_by_stock, GameStateManager.get_cargo_free())
	return max(capped_by_cargo, 0)


func _get_sellable_entries(exclude_mission_items: bool) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for entry_variant in GameStateManager.get_cargo_manifest():
		if entry_variant is not Dictionary:
			continue
		var entry: Dictionary = entry_variant
		var quantity: int = int(entry.get("quantity", 0))
		if quantity <= 0:
			continue

		var item_id: StringName = StringName(String(entry.get("resource_id", "")))
		var item_def: Dictionary = ContentDatabase.get_item_definition(item_id)
		if item_def.is_empty():
			item_def = ContentDatabase.get_resource_definition(item_id)
		if item_def.is_empty():
			continue
		if not bool(item_def.get("tradeable", true)):
			continue
		if exclude_mission_items and String(item_def.get("category", "")) == "mission_item":
			continue

		entries.append({
			"item_id": String(item_id),
			"name": String(item_def.get("name", item_id)),
			"quantity": quantity,
			"unit_price": EconomyManager.get_sell_price(item_id, _active_station_id),
			"icon_color": item_def.get("icon_color", item_def.get("family_color", Color(0.86, 0.86, 0.9, 1.0))),
		})

	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("name", "")) < String(b.get("name", ""))
	)
	return entries


func _on_sell_all_pressed() -> void:
	var total_credits: int = 0
	for entry in _get_sellable_entries(false):
		var item_id: StringName = StringName(String(entry.get("item_id", "")))
		var quantity: int = int(entry.get("quantity", 0))
		if quantity <= 0:
			continue
		total_credits += EconomyManager.sell_cargo(item_id, quantity, _active_station_id)

	if total_credits > 0:
		UIManager.show_toast("+%d credits (Sell All)" % total_credits, &"success")
	else:
		UIManager.show_toast("No cargo sold.", &"info")
	_refresh_all_tab_content()


func _on_quick_sell_pressed() -> void:
	var total_credits: int = 0
	for entry in _get_sellable_entries(true):
		var item_id: StringName = StringName(String(entry.get("item_id", "")))
		var quantity: int = int(entry.get("quantity", 0))
		if quantity <= 0:
			continue
		total_credits += EconomyManager.sell_cargo(item_id, quantity, _active_station_id)

	if total_credits > 0:
		UIManager.show_toast("Quick Sell complete: +%d credits" % total_credits, &"success")
	else:
		UIManager.show_toast("No eligible cargo for Quick Sell.", &"info")
	_refresh_all_tab_content()


func _on_full_repair_pressed() -> void:
	if not _has_service("repair"):
		return
	var max_hull: float = GameStateManager.get_max_hull()
	var current_hull: float = GameStateManager.get_current_hull()
	var missing_hull: float = maxf(max_hull - current_hull, 0.0)
	if missing_hull <= 0.0:
		UIManager.show_toast("Ship in good condition.", &"info")
		_refresh_repair_tab()
		return

	var repair_cost: int = int(ceil(missing_hull * 2.0))
	if GameStateManager.credits < repair_cost:
		UIManager.show_toast("Not enough credits for repairs.", &"warning")
		_refresh_repair_tab()
		return

	GameStateManager.credits -= repair_cost
	GameStateManager.repair_hull(missing_hull)
	AudioManager.play_sfx(&"repair_complete", Vector2.ZERO)
	UIManager.show_toast("Ship repaired for %d credits." % repair_cost, &"success")
	_refresh_repair_tab()
	if station_cargo_panel != null:
		station_cargo_panel.refresh_panel()


func _on_open_galaxy_map_pressed() -> void:
	galaxy_map_requested.emit()


func _on_undock_button_pressed() -> void:
	undock_requested.emit()


func _on_cargo_changed() -> void:
	if not visible:
		return
	_refresh_market_tab()
	_refresh_refinery_tab()
	_refresh_workshop_tab()
	if station_cargo_panel != null:
		station_cargo_panel.refresh_panel()


func _on_hull_changed(_current: float, _max_value: float) -> void:
	if not visible:
		return
	_refresh_repair_tab()


func _has_service(service_key: String) -> bool:
	return bool(_active_services.get(service_key, false))


func _attach_tooltip(target: Control, item_id: StringName) -> void:
	if target == null:
		return
	var tooltip_text: String = _build_item_tooltip(item_id)
	target.mouse_entered.connect(func() -> void:
		UIManager.show_tooltip(tooltip_text, get_viewport().get_mouse_position())
	)
	target.mouse_exited.connect(func() -> void:
		UIManager.hide_tooltip()
	)


func _build_item_tooltip(item_id: StringName) -> String:
	var item_def: Dictionary = ContentDatabase.get_item_definition(item_id)
	if item_def.is_empty():
		item_def = ContentDatabase.get_resource_definition(item_id)
	if item_def.is_empty():
		return String(item_id)

	var lines: Array[String] = []
	lines.append(String(item_def.get("name", item_id)))
	lines.append(String(item_def.get("description", "No description available.")))

	var category: String = String(item_def.get("category", ""))
	if not category.is_empty():
		lines.append("Category: %s" % category.capitalize())

	if item_def.has("base_buy_value"):
		lines.append("Base Buy: %d cr" % int(item_def.get("base_buy_value", 0)))
	if item_def.has("base_sell_value"):
		lines.append("Base Sell: %d cr" % int(item_def.get("base_sell_value", 0)))
	elif item_def.has("base_value"):
		lines.append("Base Value: %d cr" % int(item_def.get("base_value", 0)))

	if bool(item_def.get("tradeable", false)):
		lines.append("Best sold at: %s" % String(item_def.get("best_sold_at", "Any")))

	if category == "mission_item":
		lines.append("Mission-critical item. Not included in Quick Sell.")

	lines.append("Module stat comparison: coming in later phase.")
	return "\n".join(lines)


func _get_item_name(item_id: StringName) -> String:
	var item_def: Dictionary = ContentDatabase.get_item_definition(item_id)
	if item_def.is_empty():
		item_def = ContentDatabase.get_resource_definition(item_id)
	return String(item_def.get("name", item_id))


func _add_info_label(target: VBoxContainer, text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.modulate = Color(0.78, 0.84, 0.95, 0.92)
	target.add_child(label)


func _clear_dynamic_rows() -> void:
	_clear_container(sell_rows_vbox)
	_clear_container(buy_rows_vbox)
	_clear_container(refinery_rows_vbox)
	_clear_container(workshop_rows_vbox)


func _clear_container(container: Node) -> void:
	for child in container.get_children():
		child.queue_free()
