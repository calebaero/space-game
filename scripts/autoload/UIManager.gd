extends Node

signal toast_requested(message: String, category: StringName)
signal toast_state_changed(message: String, category: StringName, alpha: float, visible: bool)
signal tooltip_requested(text: String, position: Vector2)
signal tooltip_hidden
signal wreck_recovery_requested(wreck_beacon: Node)

# TODO(phase-later): centralize UI stack management, transitions, and menu routing.

const TOAST_DISPLAY_DURATION: float = 2.0
const TOAST_FADE_DURATION: float = 0.35

var _toast_queue: Array[Dictionary] = []
var _active_toast: Dictionary = {}
var _toast_display_time_remaining: float = 0.0
var _toast_fade_time_remaining: float = 0.0


func _ready() -> void:
	set_process(true)


func show_toast(message: String, category: StringName = &"info") -> void:
	var cleaned_message: String = message.strip_edges()
	if cleaned_message.is_empty():
		return

	_toast_queue.append({
		"message": cleaned_message,
		"category": category,
	})
	_try_activate_next_toast()


func _process(delta: float) -> void:
	if _active_toast.is_empty():
		_try_activate_next_toast()
		return

	if _toast_display_time_remaining > 0.0:
		_toast_display_time_remaining -= delta
		_emit_toast_state(1.0, true)
		if _toast_display_time_remaining <= 0.0:
			_toast_fade_time_remaining = TOAST_FADE_DURATION
		return

	if _toast_fade_time_remaining > 0.0:
		_toast_fade_time_remaining -= delta
		var alpha: float = clampf(_toast_fade_time_remaining / TOAST_FADE_DURATION, 0.0, 1.0)
		_emit_toast_state(alpha, true)
		return

	_emit_toast_state(0.0, false)
	_active_toast.clear()
	_try_activate_next_toast()


func show_tooltip(text: String, position: Vector2) -> void:
	tooltip_requested.emit(text, position)


func hide_tooltip() -> void:
	tooltip_hidden.emit()


func request_wreck_recovery(wreck_beacon: Node) -> void:
	if wreck_beacon == null:
		return
	wreck_recovery_requested.emit(wreck_beacon)


func transition_to_scene(scene_path: String) -> void:
	# TODO(phase-later): replace direct switch with fade/crosswipe transitions.
	get_tree().change_scene_to_file(scene_path)


func _try_activate_next_toast() -> void:
	if not _active_toast.is_empty():
		return
	if _toast_queue.is_empty():
		return

	_active_toast = _toast_queue.pop_front()
	_toast_display_time_remaining = TOAST_DISPLAY_DURATION
	_toast_fade_time_remaining = 0.0
	toast_requested.emit(_active_toast["message"], _active_toast["category"])
	_emit_toast_state(1.0, true)


func _emit_toast_state(alpha: float, visible: bool) -> void:
	if _active_toast.is_empty():
		return

	toast_state_changed.emit(
		String(_active_toast["message"]),
		StringName(String(_active_toast["category"])),
		alpha,
		visible
	)
