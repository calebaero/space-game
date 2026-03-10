extends Node2D
class_name MissionMarker

@onready var marker_label: Label = %MarkerLabel


func configure(data: Dictionary) -> void:
	marker_label.text = String(data.get("label", "Mission"))
