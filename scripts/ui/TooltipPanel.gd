extends CanvasLayer

@onready var root: Control = %Root
@onready var panel: Panel = %Panel
@onready var tooltip_label: Label = %TooltipLabel

var _is_active: bool = false
var _target_position: Vector2 = Vector2.ZERO

const MIN_TOOLTIP_WIDTH: float = 220.0
const MAX_TOOLTIP_WIDTH: float = 520.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	if not UIManager.tooltip_requested.is_connected(_on_tooltip_requested):
		UIManager.tooltip_requested.connect(_on_tooltip_requested)
	if not UIManager.tooltip_hidden.is_connected(_on_tooltip_hidden):
		UIManager.tooltip_hidden.connect(_on_tooltip_hidden)


func _process(_delta: float) -> void:
	if not _is_active:
		return
	_follow_mouse()


func _on_tooltip_requested(text: String, position: Vector2) -> void:
	if text.strip_edges().is_empty():
		_on_tooltip_hidden()
		return

	tooltip_label.text = text
	_target_position = position
	_is_active = true
	visible = true
	_follow_mouse()


func _on_tooltip_hidden() -> void:
	_is_active = false
	visible = false


func _follow_mouse() -> void:
	_target_position = get_viewport().get_mouse_position() + Vector2(18.0, 16.0)
	var label_size: Vector2 = tooltip_label.get_combined_minimum_size()
	var content_width: float = clampf(label_size.x, MIN_TOOLTIP_WIDTH, MAX_TOOLTIP_WIDTH)
	var content_height: float = maxf(label_size.y, 20.0)
	var panel_size: Vector2 = Vector2(content_width + 24.0, content_height + 20.0)
	panel.size = panel_size
	root.size = panel_size
	tooltip_label.position = Vector2(12.0, 10.0)
	tooltip_label.size = Vector2(content_width, content_height)

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var clamped_x: float = clampf(_target_position.x, 8.0, viewport_size.x - panel_size.x - 8.0)
	var clamped_y: float = clampf(_target_position.y, 8.0, viewport_size.y - panel_size.y - 8.0)
	root.position = Vector2(clamped_x, clamped_y)
