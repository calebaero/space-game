extends CanvasLayer
class_name SettingsMenu

signal close_requested

@onready var root: Control = %Root
@onready var title_label: Label = %TitleLabel
@onready var audio_tab_button: Button = %AudioTabButton
@onready var display_tab_button: Button = %DisplayTabButton
@onready var controls_tab_button: Button = %ControlsTabButton
@onready var audio_page: Control = %AudioPage
@onready var display_page: Control = %DisplayPage
@onready var controls_page: Control = %ControlsPage
@onready var master_slider: HSlider = %MasterSlider
@onready var music_slider: HSlider = %MusicSlider
@onready var sfx_slider: HSlider = %SfxSlider
@onready var master_value_label: Label = %MasterValueLabel
@onready var music_value_label: Label = %MusicValueLabel
@onready var sfx_value_label: Label = %SfxValueLabel
@onready var fullscreen_check: CheckBox = %FullscreenCheck
@onready var vsync_check: CheckBox = %VsyncCheck
@onready var shake_slider: HSlider = %ShakeSlider
@onready var shake_value_label: Label = %ShakeValueLabel
@onready var controls_text: RichTextLabel = %ControlsText
@onready var reset_button: Button = %ResetButton
@onready var close_button: Button = %CloseButton
@onready var close_footer_button: Button = %CloseFooterButton

var _tab_pages: Dictionary = {}
var _tab_buttons: Dictionary = {}
var _active_tab: StringName = &"audio"
var _is_refreshing: bool = false
var _open_context: StringName = &"general"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	_tab_pages = {
		&"audio": audio_page,
		&"display": display_page,
		&"controls": controls_page,
	}
	_tab_buttons = {
		&"audio": audio_tab_button,
		&"display": display_tab_button,
		&"controls": controls_tab_button,
	}

	audio_tab_button.pressed.connect(func() -> void: _switch_tab(&"audio"))
	display_tab_button.pressed.connect(func() -> void: _switch_tab(&"display"))
	controls_tab_button.pressed.connect(func() -> void: _switch_tab(&"controls"))

	master_slider.value_changed.connect(_on_master_slider_changed)
	music_slider.value_changed.connect(_on_music_slider_changed)
	sfx_slider.value_changed.connect(_on_sfx_slider_changed)
	shake_slider.value_changed.connect(_on_shake_slider_changed)
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	vsync_check.toggled.connect(_on_vsync_toggled)
	reset_button.pressed.connect(_on_reset_pressed)
	close_button.pressed.connect(close_menu)
	close_footer_button.pressed.connect(close_menu)

	_build_controls_reference()
	_switch_tab(_active_tab)
	_refresh_from_settings()
	if not SaveManager.settings_changed.is_connected(_on_settings_changed):
		SaveManager.settings_changed.connect(_on_settings_changed)


func open_menu(context: StringName = &"general") -> void:
	_open_context = context
	title_label.text = "Settings"
	visible = true
	_refresh_from_settings()
	_switch_tab(_active_tab)


func close_menu() -> void:
	if not visible:
		return
	visible = false
	SaveManager.save_settings()
	close_requested.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close_menu()


func _switch_tab(tab_id: StringName) -> void:
	_active_tab = tab_id
	for tab_key_variant in _tab_pages.keys():
		var tab_key: StringName = tab_key_variant
		var page: Control = _tab_pages[tab_key]
		page.visible = tab_key == tab_id
		var button: Button = _tab_buttons[tab_key]
		button.button_pressed = tab_key == tab_id


func _refresh_from_settings() -> void:
	_is_refreshing = true
	master_slider.value = SaveManager.get_audio_setting(&"master_volume", 1.0) * 100.0
	music_slider.value = SaveManager.get_audio_setting(&"music_volume", 0.8) * 100.0
	sfx_slider.value = SaveManager.get_audio_setting(&"sfx_volume", 0.85) * 100.0
	fullscreen_check.button_pressed = bool(SaveManager.get_display_setting(&"fullscreen", false))
	vsync_check.button_pressed = bool(SaveManager.get_display_setting(&"vsync", true))
	shake_slider.value = SaveManager.get_screen_shake_intensity() * 100.0
	_update_percent_labels()
	_is_refreshing = false


func _on_master_slider_changed(value: float) -> void:
	if _is_refreshing:
		return
	SaveManager.set_audio_setting(&"master_volume", value / 100.0, true)
	_update_percent_labels()


func _on_music_slider_changed(value: float) -> void:
	if _is_refreshing:
		return
	SaveManager.set_audio_setting(&"music_volume", value / 100.0, true)
	_update_percent_labels()


func _on_sfx_slider_changed(value: float) -> void:
	if _is_refreshing:
		return
	SaveManager.set_audio_setting(&"sfx_volume", value / 100.0, true)
	_update_percent_labels()


func _on_shake_slider_changed(value: float) -> void:
	if _is_refreshing:
		return
	SaveManager.set_display_setting(&"screen_shake_intensity", value / 100.0, true)
	_update_percent_labels()


func _on_fullscreen_toggled(enabled: bool) -> void:
	if _is_refreshing:
		return
	SaveManager.set_display_setting(&"fullscreen", enabled, true)


func _on_vsync_toggled(enabled: bool) -> void:
	if _is_refreshing:
		return
	SaveManager.set_display_setting(&"vsync", enabled, true)


func _on_reset_pressed() -> void:
	SaveManager.reset_settings_to_defaults()
	_refresh_from_settings()
	UIManager.show_toast("Settings reset to defaults.", &"info")


func _on_settings_changed(_settings: Dictionary) -> void:
	if not visible:
		return
	_refresh_from_settings()


func _update_percent_labels() -> void:
	master_value_label.text = "%d%%" % int(round(master_slider.value))
	music_value_label.text = "%d%%" % int(round(music_slider.value))
	sfx_value_label.text = "%d%%" % int(round(sfx_slider.value))
	shake_value_label.text = "%d%%" % int(round(shake_slider.value))


func _build_controls_reference() -> void:
	var lines: Array[String] = []
	lines.append("[b]Controls Reference[/b]")
	lines.append("")
	lines.append("Mouse: Aim")
	lines.append("Left Click / W: Thrust")
	lines.append("Right Click: Primary Fire")
	lines.append("Shift or Space: Boost")
	lines.append("A / D: Rotational Assist")
	lines.append("S: Brake")
	lines.append("E: Interact / Dock")
	lines.append("F: Mining Beam")
	lines.append("Q: Scanner Pulse")
	lines.append("R: Secondary Fire")
	lines.append("C: Utility Module")
	lines.append("1 / 2: Cycle Weapon Group")
	lines.append("Tab: Cycle Target")
	lines.append("Y: Cycle Mission")
	lines.append("M: Galaxy Map")
	lines.append("Esc: Pause / Close Menus")
	controls_text.bbcode_enabled = true
	controls_text.text = "\n".join(lines)
