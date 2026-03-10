extends CanvasLayer

@onready var fade_rect: ColorRect = %FadeRect
@onready var speed_lines: Control = %SpeedLines


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	fade_rect.color.a = 0.0


func play_warp_prelude() -> void:
	visible = true
	if speed_lines.has_method("start_effect"):
		speed_lines.call("start_effect")
	await get_tree().create_timer(0.5).timeout
	if speed_lines.has_method("stop_effect"):
		speed_lines.call("stop_effect")
	await fade_to_black(0.3)


func fade_to_black(duration: float) -> void:
	visible = true
	var tween: Tween = create_tween()
	tween.tween_property(fade_rect, "color:a", 1.0, duration)
	await tween.finished


func fade_from_black(duration: float) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(fade_rect, "color:a", 0.0, duration)
	await tween.finished
	visible = false


func clear_overlay() -> void:
	fade_rect.color.a = 0.0
	visible = false
	if speed_lines.has_method("stop_effect"):
		speed_lines.call("stop_effect")
