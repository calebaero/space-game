extends CanvasLayer
class_name GameOverScreen

signal continue_requested

@onready var subtitle_label: Label = %SubtitleLabel
@onready var details_label: Label = %DetailsLabel
@onready var continue_button: Button = %ContinueButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	visible = false
	continue_button.pressed.connect(_on_continue_pressed)


func show_game_over(repair_fee: int, wreck_sector_name: String, previous_wreck_destroyed: bool) -> void:
	var details: PackedStringArray = PackedStringArray()
	details.append("Repair fee: %d credits" % repair_fee)
	details.append("Wreck beacon placed in %s" % wreck_sector_name)
	if previous_wreck_destroyed:
		details.append("Previous wreck destroyed")

	subtitle_label.text = "Ship Destroyed"
	details_label.text = "\n".join(details)
	visible = true


func close_screen() -> void:
	visible = false


func _on_continue_pressed() -> void:
	continue_requested.emit()
