extends CanvasLayer
class_name VictoryOverlay

signal sequence_finished

@onready var root: Control = %Root
@onready var text_label: Label = %TextLabel

var _is_playing: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	root.visible = false


func is_playing() -> bool:
	return _is_playing


func show_sequence(lines: PackedStringArray) -> void:
	if _is_playing:
		return
	_is_playing = true
	visible = true
	root.visible = true
	text_label.text = ""
	text_label.modulate = Color(1.0, 1.0, 1.0, 0.0)

	for line in lines:
		if line.is_empty():
			continue
		text_label.text = line
		text_label.modulate.a = 1.0
		await get_tree().create_timer(1.6).timeout
		var tween: Tween = create_tween()
		tween.tween_property(text_label, "modulate:a", 0.0, 0.35)
		await tween.finished

	await get_tree().create_timer(0.25).timeout
	root.visible = false
	visible = false
	_is_playing = false
	sequence_finished.emit()
