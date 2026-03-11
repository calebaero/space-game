extends CanvasLayer

signal undock_requested
signal galaxy_map_requested
signal save_requested
signal cargo_sold(total_quantity: int, total_credits: int)

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
@onready var save_tab_button: Button = %SaveTabButton
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
var _upgrades_initialized: bool = false
var _upgrade_summary_label: Label = null
var _upgrade_rows_vbox: VBoxContainer = null
var _module_sections_vbox: VBoxContainer = null
var _missions_initialized: bool = false
var _story_missions_vbox: VBoxContainer = null
var _available_contracts_vbox: VBoxContainer = null
var _active_missions_vbox: VBoxContainer = null
var _abandon_confirm_dialog: ConfirmationDialog = null
var _pending_abandon_mission_id: StringName = &""
var _pending_abandon_mission_title: String = ""
var _market_tutorial_highlight: bool = false
var _market_highlight_time: float = 0.0


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
	save_tab_button.pressed.connect(_on_save_button_pressed)
	undock_tab_button.pressed.connect(_on_undock_button_pressed)

	sell_all_button.pressed.connect(_on_sell_all_pressed)
	quick_sell_button.pressed.connect(_on_quick_sell_pressed)
	full_repair_button.pressed.connect(_on_full_repair_pressed)
	open_galaxy_map_button.pressed.connect(_on_open_galaxy_map_pressed)

	if not GameStateManager.cargo_changed.is_connected(_on_cargo_changed):
		GameStateManager.cargo_changed.connect(_on_cargo_changed)
	if not GameStateManager.hull_changed.is_connected(_on_hull_changed):
		GameStateManager.hull_changed.connect(_on_hull_changed)
	if not MissionManager.mission_state_changed.is_connected(_on_mission_state_changed):
		MissionManager.mission_state_changed.connect(_on_mission_state_changed)

	_abandon_confirm_dialog = ConfirmationDialog.new()
	_abandon_confirm_dialog.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_abandon_confirm_dialog.dialog_text = "Abandon this mission?"
	_abandon_confirm_dialog.title = "Confirm Abandon"
	_abandon_confirm_dialog.confirmed.connect(_on_abandon_confirmed)
	add_child(_abandon_confirm_dialog)

	_build_upgrades_page()
	_build_missions_page()
	_switch_tab(StationTab.MARKET, true)
	for static_button in [
		missions_tab_button,
		market_tab_button,
		refinery_tab_button,
		workshop_tab_button,
		upgrades_tab_button,
		repair_tab_button,
		galaxy_map_tab_button,
		save_tab_button,
		undock_tab_button,
		sell_all_button,
		quick_sell_button,
		full_repair_button,
		open_galaxy_map_button,
	]:
		_bind_ui_button_sound(static_button)


func _process(delta: float) -> void:
	if not visible:
		return
	credits_label.text = "Credits: %d" % GameStateManager.credits
	if _market_tutorial_highlight and not market_tab_button.disabled:
		_market_highlight_time += delta * 5.2
		var pulse: float = 0.45 + absf(sin(_market_highlight_time)) * 0.55
		market_tab_button.modulate = Color(1.0, 0.78 + pulse * 0.2, 0.24 + pulse * 0.24, 1.0)
	elif not market_tab_button.disabled:
		market_tab_button.modulate = Color(1.0, 1.0, 1.0, 1.0)


func open_for_station(station_data: Dictionary) -> void:
	_active_station_data = station_data.duplicate(true)
	_active_station_id = StringName(String(_active_station_data.get("id", "")))

	station_name_label.text = String(_active_station_data.get("name", "Unknown Station"))
	var economy_type: String = String(_active_station_data.get("economy_type", "unknown"))
	economy_label.text = "Economy: %s" % economy_type.capitalize()
	credits_label.text = "Credits: %d" % GameStateManager.credits

	_populate_service_flags()
	_apply_service_availability()
	MissionManager.generate_contracts(_active_station_id)

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
	_pending_abandon_mission_id = &""
	_pending_abandon_mission_title = ""
	_market_tutorial_highlight = false
	_market_highlight_time = 0.0
	if _abandon_confirm_dialog != null and is_instance_valid(_abandon_confirm_dialog):
		_abandon_confirm_dialog.hide()
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
	_refresh_missions_tab()
	_refresh_market_tab()
	_refresh_refinery_tab()
	_refresh_workshop_tab()
	_refresh_upgrades_tab()
	_refresh_repair_tab()
	if station_cargo_panel != null:
		station_cargo_panel.refresh_panel()


func _build_missions_page() -> void:
	if _missions_initialized:
		return

	for child in missions_page.get_children():
		child.queue_free()

	var root_vbox: VBoxContainer = VBoxContainer.new()
	root_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_theme_constant_override("separation", 8)
	missions_page.add_child(root_vbox)

	var story_header: Label = Label.new()
	story_header.text = "Story Missions"
	root_vbox.add_child(story_header)

	var story_panel: PanelContainer = PanelContainer.new()
	story_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	story_panel.custom_minimum_size = Vector2(0.0, 140.0)
	root_vbox.add_child(story_panel)

	var story_scroll: ScrollContainer = ScrollContainer.new()
	story_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	story_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	story_panel.add_child(story_scroll)

	_story_missions_vbox = VBoxContainer.new()
	_story_missions_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_story_missions_vbox.add_theme_constant_override("separation", 6)
	story_scroll.add_child(_story_missions_vbox)

	var contracts_header: Label = Label.new()
	contracts_header.text = "Available Contracts"
	root_vbox.add_child(contracts_header)

	var contracts_split: HSplitContainer = HSplitContainer.new()
	contracts_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contracts_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	contracts_split.split_offset = 420
	root_vbox.add_child(contracts_split)

	var available_panel: PanelContainer = PanelContainer.new()
	available_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contracts_split.add_child(available_panel)

	var available_scroll: ScrollContainer = ScrollContainer.new()
	available_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	available_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	available_panel.add_child(available_scroll)

	_available_contracts_vbox = VBoxContainer.new()
	_available_contracts_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_available_contracts_vbox.add_theme_constant_override("separation", 6)
	available_scroll.add_child(_available_contracts_vbox)

	var active_panel: PanelContainer = PanelContainer.new()
	active_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contracts_split.add_child(active_panel)

	var active_scroll: ScrollContainer = ScrollContainer.new()
	active_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	active_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	active_panel.add_child(active_scroll)

	_active_missions_vbox = VBoxContainer.new()
	_active_missions_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_active_missions_vbox.add_theme_constant_override("separation", 6)
	active_scroll.add_child(_active_missions_vbox)

	_missions_initialized = true


func _refresh_missions_tab() -> void:
	_build_missions_page()
	if _story_missions_vbox == null or _available_contracts_vbox == null or _active_missions_vbox == null:
		return

	_clear_container(_story_missions_vbox)
	_clear_container(_available_contracts_vbox)
	_clear_container(_active_missions_vbox)

	if not _has_service("missions"):
		_add_info_label(_story_missions_vbox, "Mission board unavailable at this station.")
		return

	var story_offers: Array[Dictionary] = MissionManager.get_story_missions_for_station(_active_station_id)
	if story_offers.is_empty():
		_add_info_label(_story_missions_vbox, "No story missions available at this station.")
	else:
		for story_offer in story_offers:
			_create_mission_offer_row(_story_missions_vbox, story_offer, true)

	var contract_offers: Array[Dictionary] = MissionManager.get_contracts_for_station(_active_station_id)
	if contract_offers.is_empty():
		_add_info_label(_available_contracts_vbox, "No contracts currently available.")
	else:
		for offer in contract_offers:
			_create_mission_offer_row(_available_contracts_vbox, offer, false)

	var active_missions: Array[Dictionary] = MissionManager.get_active_missions()
	if active_missions.is_empty():
		_add_info_label(_active_missions_vbox, "No active missions.")
		return
	for mission in active_missions:
		_create_active_mission_row(_active_missions_vbox, mission)


func _create_mission_offer_row(target_container: VBoxContainer, mission: Dictionary, is_story: bool) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	target_container.add_child(panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var row: HBoxContainer = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	margin.add_child(row)

	var info_vbox: VBoxContainer = VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.add_theme_constant_override("separation", 2)
	row.add_child(info_vbox)

	var title_label: Label = Label.new()
	var mission_title: String = String(mission.get("title", "Mission"))
	title_label.text = "%s%s" % ["[STORY] " if is_story else "", mission_title]
	if is_story:
		title_label.modulate = Color(1.0, 0.9, 0.42, 0.98)
	info_vbox.add_child(title_label)

	var desc_label: Label = Label.new()
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_label.text = String(mission.get("description", ""))
	desc_label.modulate = Color(0.74, 0.8, 0.92, 0.95)
	info_vbox.add_child(desc_label)

	var reward_label: Label = Label.new()
	var reward_credits: int = int((mission.get("rewards", {}) as Dictionary).get("credits", 0))
	reward_label.text = "Reward: %d credits" % reward_credits
	reward_label.modulate = Color(0.58, 0.95, 0.64, 0.96)
	info_vbox.add_child(reward_label)

	var accept_button: Button = Button.new()
	accept_button.custom_minimum_size = Vector2(108.0, 0.0)
	accept_button.text = "Accept"
	accept_button.pressed.connect(func() -> void:
		var result: Dictionary = {}
		if is_story:
			var template_identifier: StringName = StringName(String(mission.get("template_id", mission.get("id", ""))))
			result = MissionManager.accept_story_mission(template_identifier)
		else:
			result = MissionManager.accept_contract(_active_station_id, StringName(String(mission.get("id", ""))))
		if not bool(result.get("success", false)):
			UIManager.show_toast(String(result.get("message", "Could not accept mission.")), &"warning")
			return
		UIManager.show_toast("Mission accepted: %s" % mission_title, &"success")
		_refresh_missions_tab()
	)
	row.add_child(accept_button)


func _create_active_mission_row(target_container: VBoxContainer, mission: Dictionary) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	target_container.add_child(panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var root_vbox: VBoxContainer = VBoxContainer.new()
	root_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vbox.add_theme_constant_override("separation", 4)
	margin.add_child(root_vbox)

	var title_label: Label = Label.new()
	title_label.text = String(mission.get("title", "Mission"))
	if bool(mission.get("is_story", false)):
		title_label.text = "[STORY] %s" % title_label.text
		title_label.modulate = Color(1.0, 0.9, 0.42, 0.98)
	root_vbox.add_child(title_label)

	var objective_label: Label = Label.new()
	objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	objective_label.text = _build_mission_objective_lines(mission)
	root_vbox.add_child(objective_label)

	var button_row: HBoxContainer = HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 6)
	root_vbox.add_child(button_row)

	var mission_id: StringName = StringName(String(mission.get("id", "")))
	var track_button: Button = Button.new()
	track_button.text = "Track"
	track_button.disabled = MissionManager.get_tracked_mission_id() == mission_id
	track_button.pressed.connect(func() -> void:
		MissionManager.set_tracked_mission(mission_id)
		_refresh_missions_tab()
	)
	button_row.add_child(track_button)

	var abandon_button: Button = Button.new()
	abandon_button.text = "Abandon"
	abandon_button.disabled = bool(mission.get("is_story", false))
	abandon_button.pressed.connect(func() -> void:
		_prompt_abandon_mission(mission_id, String(mission.get("title", "Mission")))
	)
	button_row.add_child(abandon_button)

	var turn_in_button: Button = Button.new()
	turn_in_button.text = "Turn In"
	turn_in_button.disabled = not MissionManager.can_turn_in_mission(mission_id, _active_station_id)
	turn_in_button.pressed.connect(func() -> void:
		var result: Dictionary = MissionManager.turn_in_mission(mission_id, _active_station_id)
		if not bool(result.get("success", false)):
			UIManager.show_toast(String(result.get("message", "Cannot turn in mission.")), &"warning")
			return
		UIManager.show_toast("Mission turned in.", &"success")
		_refresh_all_tab_content()
	)
	button_row.add_child(turn_in_button)


func _build_mission_objective_lines(mission: Dictionary) -> String:
	var lines: Array[String] = []
	for objective_variant in mission.get("objectives", []):
		if objective_variant is not Dictionary:
			continue
		var objective: Dictionary = objective_variant
		var summary: String = MissionManager.format_objective_progress(objective)
		if summary.is_empty():
			continue
			var complete: bool = int(objective.get("current", 0)) >= max(int(objective.get("required", 1)), 1)
			lines.append("%s %s" % ["[x]" if complete else "[ ]", summary])
	return "\n".join(lines)


func _prompt_abandon_mission(mission_id: StringName, mission_title: String) -> void:
	_pending_abandon_mission_id = mission_id
	_pending_abandon_mission_title = mission_title
	if _abandon_confirm_dialog == null or not is_instance_valid(_abandon_confirm_dialog):
		var fallback_result: Dictionary = MissionManager.abandon_mission(mission_id)
		if not bool(fallback_result.get("success", false)):
			UIManager.show_toast(String(fallback_result.get("message", "Failed to abandon mission.")), &"warning")
			return
		UIManager.show_toast("Mission abandoned.", &"info")
		_refresh_missions_tab()
		return
	_abandon_confirm_dialog.dialog_text = "Abandon \"%s\"?\nThis mission progress will be lost." % mission_title
	_abandon_confirm_dialog.popup_centered_clamped(Vector2(440.0, 180.0))


func _on_abandon_confirmed() -> void:
	if _pending_abandon_mission_id == &"":
		return
	var result: Dictionary = MissionManager.abandon_mission(_pending_abandon_mission_id)
	if not bool(result.get("success", false)):
		UIManager.show_toast(String(result.get("message", "Failed to abandon mission.")), &"warning")
		return
	UIManager.show_toast("Mission abandoned: %s" % _pending_abandon_mission_title, &"info")
	_pending_abandon_mission_id = &""
	_pending_abandon_mission_title = ""
	_refresh_missions_tab()


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


func _build_upgrades_page() -> void:
	if _upgrades_initialized:
		return

	for child in upgrades_page.get_children():
		child.queue_free()

	var root_vbox: VBoxContainer = VBoxContainer.new()
	root_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_theme_constant_override("separation", 8)
	upgrades_page.add_child(root_vbox)

	_upgrade_summary_label = Label.new()
	_upgrade_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root_vbox.add_child(_upgrade_summary_label)

	var upgrades_title: Label = Label.new()
	upgrades_title.text = "Core Upgrades"
	root_vbox.add_child(upgrades_title)

	var upgrades_scroll: ScrollContainer = ScrollContainer.new()
	upgrades_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(upgrades_scroll)

	_upgrade_rows_vbox = VBoxContainer.new()
	_upgrade_rows_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_upgrade_rows_vbox.add_theme_constant_override("separation", 8)
	upgrades_scroll.add_child(_upgrade_rows_vbox)

	var modules_title: Label = Label.new()
	modules_title.text = "Module Loadout"
	root_vbox.add_child(modules_title)

	var modules_scroll: ScrollContainer = ScrollContainer.new()
	modules_scroll.custom_minimum_size = Vector2(0.0, 220.0)
	modules_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(modules_scroll)

	_module_sections_vbox = VBoxContainer.new()
	_module_sections_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_module_sections_vbox.add_theme_constant_override("separation", 10)
	modules_scroll.add_child(_module_sections_vbox)

	_upgrades_initialized = true


func _refresh_upgrades_tab() -> void:
	_build_upgrades_page()
	if _upgrade_summary_label == null or _upgrade_rows_vbox == null or _module_sections_vbox == null:
		return

	_clear_container(_upgrade_rows_vbox)
	_clear_container(_module_sections_vbox)

	if not _has_service("upgrades"):
		_upgrade_summary_label.text = "Upgrade and module services unavailable at this station."
		_add_info_label(_upgrade_rows_vbox, "Dock at a station with upgrade facilities.")
		return

	var power_used: float = GameStateManager.get_power_usage()
	var power_capacity: float = GameStateManager.get_power_capacity()
	var mass_total: float = GameStateManager.get_total_mass()
	var agility_multiplier: float = maxf(0.3, 1.0 - (mass_total * 0.01))
	var agility_penalty_percent: int = int(round((1.0 - agility_multiplier) * 100.0))
	_upgrade_summary_label.text = "Power: %.0f/%.0f used   |   Mass: %.1f   |   Agility: -%d%%" % [power_used, power_capacity, mass_total, agility_penalty_percent]

	var upgrade_paths: Array[Dictionary] = []
	for path_variant in ContentDatabase.get_all_upgrade_paths().values():
		if path_variant is not Dictionary:
			continue
		upgrade_paths.append((path_variant as Dictionary).duplicate(true))
	upgrade_paths.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("name", "")) < String(b.get("name", ""))
	)
	for path_data in upgrade_paths:
		_create_upgrade_row(path_data)

	_create_module_slot_section(&"primary_weapon", "Primary Weapons")
	_create_module_slot_section(&"secondary_weapon", "Secondary Weapons")
	_create_module_slot_section(&"utility_module", "Utility Modules")
	_create_module_slot_section(&"special_module", "Special Modules (Story Locked)")


func _create_upgrade_row(path_data: Dictionary) -> void:
	var path_id: StringName = StringName(String(path_data.get("id", "")))
	if path_id == &"":
		return

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
	_upgrade_rows_vbox.add_child(panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var row: HBoxContainer = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	margin.add_child(row)

	var left_vbox: VBoxContainer = VBoxContainer.new()
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_vbox.add_theme_constant_override("separation", 2)
	row.add_child(left_vbox)

	var current_tier: int = GameStateManager.get_upgrade_tier(path_id)
	var tiers: Array = path_data.get("tiers", [])
	var max_tier: int = tiers.size()
	var title_label: Label = Label.new()
	title_label.text = "%s  Mk %d/%d" % [String(path_data.get("name", path_id)), current_tier, max_tier]
	left_vbox.add_child(title_label)

	var preview_text: String = ""
	var next_tier_data: Dictionary = GameStateManager.get_next_upgrade_tier_data(path_id)
	if next_tier_data.is_empty():
		preview_text = "Maximum tier reached."
	else:
		var stat_preview: Dictionary = GameStateManager.preview_upgrade_stat(path_id)
		var stat_key: String = String(next_tier_data.get("stat_key", path_data.get("stat_key", "")))
		preview_text = "%s: %s -> %s" % [
			stat_key.capitalize().replace("_", " "),
			_format_stat_number(float(stat_preview.get("before", 0.0))),
			_format_stat_number(float(stat_preview.get("after", 0.0))),
		]
	var preview_label: Label = Label.new()
	preview_label.text = preview_text
	preview_label.modulate = Color(0.72, 0.82, 0.95, 0.95)
	left_vbox.add_child(preview_label)

	var cost_label: Label = Label.new()
	if next_tier_data.is_empty():
		cost_label.text = ""
	else:
		cost_label.text = "Cost: %s" % _format_cost_string(int(next_tier_data.get("cost_credits", 0)), Array(next_tier_data.get("cost_items", [])))
	left_vbox.add_child(cost_label)

	var purchase_button: Button = Button.new()
	if next_tier_data.is_empty():
		purchase_button.text = "MAX"
		purchase_button.disabled = true
	else:
		var next_tier: int = int(next_tier_data.get("tier", current_tier + 1))
		purchase_button.text = "Buy Mk %d" % next_tier
		var check: Dictionary = GameStateManager.can_purchase_upgrade(path_id)
		var can_purchase: bool = bool(check.get("can_purchase", false))
		purchase_button.disabled = not can_purchase
		if not can_purchase:
			purchase_button.tooltip_text = String(check.get("reason", "Requirements not met."))
		purchase_button.pressed.connect(func() -> void:
			var result: Dictionary = GameStateManager.purchase_upgrade(path_id)
			if not bool(result.get("success", false)):
				UIManager.show_toast(String(result.get("message", "Upgrade purchase failed.")), &"warning")
				return
			var stat_name: String = String(result.get("stat_key", "Stat"))
			var before_value: float = float(result.get("before_value", 0.0))
			var after_value: float = float(result.get("after_value", 0.0))
			UIManager.show_toast("%s (%s: %s -> %s)" % [
				String(result.get("message", "Upgrade purchased.")),
				stat_name.capitalize().replace("_", " "),
				_format_stat_number(before_value),
				_format_stat_number(after_value),
			], &"success")
			AudioManager.play_sfx(&"upgrade_purchase", Vector2.ZERO)
			_refresh_all_tab_content()
		)
	row.add_child(purchase_button)


func _create_module_slot_section(slot_name: StringName, title: String) -> void:
	var section_panel: PanelContainer = PanelContainer.new()
	section_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_module_sections_vbox.add_child(section_panel)

	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.11, 0.19, 0.84)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.22, 0.4, 0.68, 0.65)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	style.corner_radius_bottom_left = 4
	section_panel.add_theme_stylebox_override("panel", style)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	section_panel.add_child(margin)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	var equipped_module_id: StringName = GameStateManager.get_equipped_module_id(slot_name)
	var equipped_module_data: Dictionary = ContentDatabase.get_module_definition(equipped_module_id)
	var equipped_name: String = "None"
	if equipped_module_data.is_empty():
		if equipped_module_id != &"":
			equipped_name = String(equipped_module_id)
	else:
		equipped_name = String(equipped_module_data.get("name", equipped_module_id))

	var header_label: Label = Label.new()
	header_label.text = "%s  |  Equipped: %s" % [title, equipped_name]
	vbox.add_child(header_label)

	var modules_for_slot: Array[Dictionary] = []
	for module_variant in ContentDatabase.get_all_module_definitions().values():
		if module_variant is not Dictionary:
			continue
		var module_data: Dictionary = module_variant
		if String(module_data.get("slot", "")) != String(slot_name):
			continue
		modules_for_slot.append(module_data.duplicate(true))
	modules_for_slot.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("name", "")) < String(b.get("name", ""))
	)

	if modules_for_slot.is_empty():
		_add_info_label(vbox, "No modules available for this slot.")
		return

	for module_data in modules_for_slot:
		var module_id: StringName = StringName(String(module_data.get("id", "")))
		if module_id == &"":
			continue

		var row: HBoxContainer = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 8)
		vbox.add_child(row)

		var info_vbox: VBoxContainer = VBoxContainer.new()
		info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_vbox.add_theme_constant_override("separation", 2)
		row.add_child(info_vbox)

		var name_label: Label = Label.new()
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.text = "%s  (Pwr %.0f | Mass %.0f)" % [
			String(module_data.get("name", module_id)),
			float(module_data.get("power_draw", 0.0)),
			float(module_data.get("mass", 0.0)),
		]
		info_vbox.add_child(name_label)

		var cost_label: Label = Label.new()
		cost_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cost_label.modulate = Color(0.72, 0.82, 0.95, 0.95)
		var module_cost_text: String = _format_cost_string(int(module_data.get("cost_credits", 0)), Array(module_data.get("cost_items", [])))
		if module_cost_text.is_empty():
			cost_label.text = "Cost: Starting module"
		else:
			cost_label.text = "Cost: %s" % module_cost_text
		info_vbox.add_child(cost_label)

		var action_button: Button = Button.new()
		action_button.custom_minimum_size = Vector2(120.0, 0.0)
		var owned: bool = GameStateManager.is_module_owned(module_id)
		var equipped: bool = equipped_module_id == module_id
		if equipped:
			action_button.text = "Equipped"
			action_button.disabled = true
		elif not owned:
			action_button.text = "Buy"
			var buy_check: Dictionary = GameStateManager.can_purchase_module(module_id)
			action_button.disabled = not bool(buy_check.get("can_purchase", false))
			if action_button.disabled:
				action_button.tooltip_text = String(buy_check.get("reason", "Requirements not met."))
			action_button.pressed.connect(func() -> void:
				var buy_result: Dictionary = GameStateManager.purchase_module(module_id)
				if not bool(buy_result.get("success", false)):
					UIManager.show_toast(String(buy_result.get("message", "Purchase failed.")), &"warning")
					return
				UIManager.show_toast(String(buy_result.get("message", "Module purchased.")), &"success")
				AudioManager.play_sfx(&"module_purchase", Vector2.ZERO)
				if GameStateManager.get_equipped_module_id(slot_name) == &"":
					var equip_result: Dictionary = GameStateManager.equip_module(slot_name, module_id)
					if not bool(equip_result.get("success", false)):
						UIManager.show_toast(String(equip_result.get("message", "Auto-equip failed.")), &"warning")
				_refresh_all_tab_content()
			)
		else:
			action_button.text = "Equip"
			var equip_check: Dictionary = GameStateManager.can_equip_module(slot_name, module_id)
			action_button.disabled = not bool(equip_check.get("can_equip", false))
			if action_button.disabled:
				action_button.tooltip_text = String(equip_check.get("reason", "Cannot equip."))
			action_button.pressed.connect(func() -> void:
				var equip_result: Dictionary = GameStateManager.equip_module(slot_name, module_id)
				if not bool(equip_result.get("success", false)):
					UIManager.show_toast(String(equip_result.get("message", "Equip failed.")), &"warning")
					return
				UIManager.show_toast("%s equipped." % String(module_data.get("name", module_id)), &"success")
				AudioManager.play_sfx(&"module_equip", Vector2.ZERO)
				_refresh_all_tab_content()
			)
		row.add_child(action_button)

		var tooltip_text: String = _build_module_tooltip(slot_name, module_data)
		name_label.tooltip_text = tooltip_text
		cost_label.tooltip_text = tooltip_text
		action_button.tooltip_text = tooltip_text if action_button.tooltip_text.is_empty() else action_button.tooltip_text


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
	var repair_cost_per_hull: float = _get_repair_cost_per_hull_point()
	var repair_cost: int = int(ceil(missing_hull * repair_cost_per_hull))

	hull_status_label.text = "Hull: %.0f / %.0f" % [current_hull, max_hull]
	repair_cost_label.text = "Cost: %d credits" % repair_cost

	if missing_hull <= 0.0:
		repair_info_label.text = "Ship in good condition."
		full_repair_button.disabled = true
	else:
		repair_info_label.text = "Full repairs cost %.1f credits per missing hull point." % repair_cost_per_hull
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
			cargo_sold.emit(quantity, earned)
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
	return _has_output_capacity(recipe.get("outputs", []), recipe.get("inputs", []), [])


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

	if not _has_output_capacity(recipe.get("outputs", []), recipe.get("inputs", []), recipe.get("story_requirements", [])):
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
		GalaxyManager.apply_unlock_target(StringName(unlock_target))
		UIManager.show_toast("%s crafted." % String(recipe.get("name", "Item")), &"success")
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


func _has_output_capacity(outputs: Array, inputs: Array = [], story_requirements: Array = []) -> bool:
	var current_used: int = GameStateManager.get_cargo_used()
	var capacity: int = GameStateManager.get_cargo_capacity()
	var slots_freed_by_inputs: int = 0
	var slots_required_for_outputs: int = 0

	for input_variant in inputs:
		if input_variant is not Dictionary:
			continue
		var input_data: Dictionary = input_variant
		var input_item_id: StringName = StringName(String(input_data.get("item_id", "")))
		var input_qty: int = int(input_data.get("quantity", 0))
		if input_qty <= 0:
			continue
		var input_item_def: Dictionary = ContentDatabase.get_item_definition(input_item_id)
		if bool(input_item_def.get("store_in_relic_inventory", false)):
			continue
		var input_cargo_size: int = int(input_item_def.get("cargo_size", 1))
		slots_freed_by_inputs += max(input_cargo_size, 1) * input_qty

	for story_variant in story_requirements:
		if story_variant is not Dictionary:
			continue
		var story_data: Dictionary = story_variant
		var story_item_id: StringName = StringName(String(story_data.get("item_id", "")))
		var story_qty: int = int(story_data.get("quantity", 0))
		if story_qty <= 0:
			continue
		var story_item_def: Dictionary = ContentDatabase.get_item_definition(story_item_id)
		if bool(story_item_def.get("store_in_relic_inventory", false)):
			continue
		var story_cargo_size: int = int(story_item_def.get("cargo_size", 1))
		slots_freed_by_inputs += max(story_cargo_size, 1) * story_qty

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
		slots_required_for_outputs += max(cargo_size, 1) * output_qty

	var projected_used: int = max(current_used - slots_freed_by_inputs, 0) + slots_required_for_outputs
	return projected_used <= capacity


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
	var total_quantity: int = 0
	for entry in _get_sellable_entries(false):
		var item_id: StringName = StringName(String(entry.get("item_id", "")))
		var quantity: int = int(entry.get("quantity", 0))
		if quantity <= 0:
			continue
		total_credits += EconomyManager.sell_cargo(item_id, quantity, _active_station_id)
		total_quantity += quantity

	if total_credits > 0:
		UIManager.show_toast("+%d credits (Sell All)" % total_credits, &"success")
		cargo_sold.emit(total_quantity, total_credits)
	else:
		UIManager.show_toast("No cargo sold.", &"info")
	_refresh_all_tab_content()


func _on_quick_sell_pressed() -> void:
	var total_credits: int = 0
	var total_quantity: int = 0
	for entry in _get_sellable_entries(true):
		var item_id: StringName = StringName(String(entry.get("item_id", "")))
		var quantity: int = int(entry.get("quantity", 0))
		if quantity <= 0:
			continue
		total_credits += EconomyManager.sell_cargo(item_id, quantity, _active_station_id)
		total_quantity += quantity

	if total_credits > 0:
		UIManager.show_toast("Quick Sell complete: +%d credits" % total_credits, &"success")
		cargo_sold.emit(total_quantity, total_credits)
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

	var repair_cost_per_hull: float = _get_repair_cost_per_hull_point()
	var repair_cost: int = int(ceil(missing_hull * repair_cost_per_hull))
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


func _get_repair_cost_per_hull_point() -> float:
	var repair_config: Dictionary = ContentDatabase.get_balance_config_data().get("repair", {})
	return maxf(float(repair_config.get("credits_per_hull_point", 2.0)), 0.1)


func _on_open_galaxy_map_pressed() -> void:
	galaxy_map_requested.emit()


func _on_save_button_pressed() -> void:
	save_requested.emit()


func _on_undock_button_pressed() -> void:
	undock_requested.emit()


func set_market_tab_tutorial_highlight(enabled: bool) -> void:
	_market_tutorial_highlight = enabled
	if not enabled:
		_market_highlight_time = 0.0
		if not market_tab_button.disabled:
			market_tab_button.modulate = Color(1.0, 1.0, 1.0, 1.0)


func _on_cargo_changed() -> void:
	if not visible:
		return
	_refresh_market_tab()
	_refresh_refinery_tab()
	_refresh_workshop_tab()
	_refresh_upgrades_tab()
	if station_cargo_panel != null:
		station_cargo_panel.refresh_panel()


func _on_hull_changed(_current: float, _max_value: float) -> void:
	if not visible:
		return
	_refresh_repair_tab()


func _on_mission_state_changed() -> void:
	if not visible:
		return
	_refresh_missions_tab()


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


func _build_module_tooltip(slot_name: StringName, module_data: Dictionary) -> String:
	var lines: Array[String] = []
	var module_name: String = String(module_data.get("name", "Module"))
	var module_id: StringName = StringName(String(module_data.get("id", "")))
	lines.append(module_name)
	lines.append(String(module_data.get("description", "No description available.")))
	lines.append("Power Draw: %.0f" % float(module_data.get("power_draw", 0.0)))
	lines.append("Mass: %.0f" % float(module_data.get("mass", 0.0)))

	var cost_text: String = _format_cost_string(int(module_data.get("cost_credits", 0)), Array(module_data.get("cost_items", [])))
	if not cost_text.is_empty():
		lines.append("Cost: %s" % cost_text)

	var equipped_module_id: StringName = GameStateManager.get_equipped_module_id(slot_name)
	var equipped_module_data: Dictionary = ContentDatabase.get_module_definition(equipped_module_id)
	if equipped_module_id == &"":
		lines.append("Current: None")
	elif equipped_module_data.is_empty():
		lines.append("Current: %s" % String(equipped_module_id))
	else:
		lines.append("Current: %s" % String(equipped_module_data.get("name", equipped_module_id)))

	var candidate_weapon_data: Dictionary = _get_weapon_data_for_module(module_data)
	if not candidate_weapon_data.is_empty():
		var candidate_dps: float = float(candidate_weapon_data.get("damage", 0.0)) / maxf(float(candidate_weapon_data.get("fire_rate", 0.2)), 0.05)
		lines.append("DPS: %.1f | Damage: %.0f | Range: %.0f" % [
			candidate_dps,
			float(candidate_weapon_data.get("damage", 0.0)),
			float(candidate_weapon_data.get("range", 0.0)),
		])
		var equipped_weapon_data: Dictionary = _get_weapon_data_for_module(equipped_module_data)
		if equipped_weapon_data.is_empty() and equipped_module_id != &"":
			equipped_weapon_data = ContentDatabase.get_weapon_definition(equipped_module_id)
		if not equipped_weapon_data.is_empty():
			lines.append("Compare: %.0f -> %.0f dmg | %.0f -> %.0f range" % [
				float(equipped_weapon_data.get("damage", 0.0)),
				float(candidate_weapon_data.get("damage", 0.0)),
				float(equipped_weapon_data.get("range", 0.0)),
				float(candidate_weapon_data.get("range", 0.0)),
			])

	var equip_check: Dictionary = GameStateManager.can_equip_module(slot_name, module_id)
	if bool(equip_check.get("can_equip", false)):
		var projected_mass: float = GameStateManager.preview_loadout_mass(slot_name, module_id)
		var projected_agility: float = GameStateManager.get_agility_multiplier_for_mass(projected_mass)
		lines.append("Equip Preview: Power %.0f/%.0f" % [
			float(equip_check.get("power_used", GameStateManager.get_power_usage())),
			float(equip_check.get("power_capacity", GameStateManager.get_power_capacity())),
		])
		lines.append("Equip Preview: Mass %.1f (Agility -%d%%)" % [
			projected_mass,
			int(round((1.0 - projected_agility) * 100.0)),
		])
	else:
		lines.append("Equip Blocked: %s" % String(equip_check.get("reason", "Requirements not met.")))
	return "\n".join(lines)


func _get_weapon_data_for_module(module_data: Dictionary) -> Dictionary:
	if module_data.is_empty():
		return {}
	var weapon_id: StringName = StringName(String(module_data.get("weapon_id", module_data.get("id", ""))))
	if weapon_id == &"":
		return {}
	return ContentDatabase.get_weapon_definition(weapon_id)


func _format_cost_string(credit_cost: int, cost_items: Array) -> String:
	var tokens: Array[String] = []
	if credit_cost > 0:
		tokens.append("%dcr" % credit_cost)
	for cost_variant in cost_items:
		if cost_variant is not Dictionary:
			continue
		var cost_data: Dictionary = cost_variant
		var item_id: StringName = StringName(String(cost_data.get("item_id", "")))
		var quantity: int = int(cost_data.get("quantity", 0))
		if quantity <= 0:
			continue
		tokens.append("%s x%d" % [_get_item_name(item_id), quantity])
	return ", ".join(tokens)


func _format_stat_number(value: float) -> String:
	if absf(value - round(value)) <= 0.01:
		return str(int(round(value)))
	return "%.2f" % value


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


func _bind_ui_button_sound(button: Button) -> void:
	if button == null:
		return
	button.pressed.connect(func() -> void:
		AudioManager.play_sfx(&"ui_click", Vector2.ZERO)
	)
	button.mouse_entered.connect(func() -> void:
		AudioManager.play_sfx(&"ui_hover", Vector2.ZERO)
	)
