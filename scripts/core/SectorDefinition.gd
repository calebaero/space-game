extends Resource
class_name SectorDefinition

@export var id: StringName = &""
@export var display_name: String = ""
@export var galaxy_id: StringName = &""
# Connection entries use: {"sector_id": StringName, "required_unlock": StringName}
@export var connections: Array[Dictionary] = []
@export var threat_level: int = 1
@export var background_tint: Color = Color(0.2, 0.3, 0.55, 1.0)
@export var station_data: Dictionary = {}
@export var planets: Array[Dictionary] = []
@export var warp_gates: Array[Dictionary] = []
@export var anomaly_points: Array[Dictionary] = []
@export var resource_nodes: Array[Dictionary] = []
@export var asteroid_fields: Array[Dictionary] = []
@export var hazard_zones: Array[Dictionary] = []
@export var loot_crates: Array[Dictionary] = []
@export var enemy_patrols: Array[Dictionary] = []
@export var hazard_types: PackedStringArray = PackedStringArray()
@export var content_tags: PackedStringArray = PackedStringArray()
