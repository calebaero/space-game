extends Node2D
class_name MissionMarker

@onready var marker_label: Label = %MarkerLabel
@onready var marker_line: Line2D = $MarkerLine

var marker_id: StringName = &""


func configure(data: Dictionary) -> void:
	marker_id = StringName(String(data.get("id", marker_id)))
	marker_label.text = String(data.get("label", "Mission"))
	if data.has("objective_text"):
		marker_label.text = "%s\n%s" % [marker_label.text, String(data.get("objective_text", ""))]
	if data.has("color"):
		var color_value: Variant = data.get("color", Color(1.0, 0.9, 0.2, 0.9))
		if color_value is Color:
			marker_line.default_color = color_value
			marker_label.modulate = color_value


func _ready() -> void:
	add_to_group("mission_marker")
