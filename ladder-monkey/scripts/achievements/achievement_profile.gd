class_name AchievementProfile
extends Resource
## Award heights are measured in world metres above the ladder's origin.
@export_group("Trophies")
@export var first_height: float = 3.10
@export_range(0.42, 5.0) var height_interval: float = 2.10
@export var spawn_ahead_distance: float = 2.80
@export var distance_from_ladder: float = 0.29
@export var rotation_speed: float = 0.85
@export var float_amplitude: float = 0.045
@export var float_frequency: float = 1.8
@export var pickup_radius: float = 0.19
@export var achievement_names: PackedStringArray = ["初攀新星", "云间行者", "树冠先锋", "金杯猎手", "攀登大师", "云端传奇"]
@export_group("Fragments")
@export_range(16, 48) var fragment_count: int = 24
@export var burst_speed: float = 1.65
@export var upward_speed: float = 1.55
@export var angular_speed: float = 9.0
@export_range(0.0, 1.0) var bounce: float = 0.44
@export var fragment_lifetime: float = 5.0
@export var fragment_fade_duration: float = 0.45
@export_range(24, 256) var max_active_fragments: int = 96
@export_group("Toast")
@export var toast_enter_duration: float = 0.34
@export var toast_hold_duration: float = 2.40
@export var toast_exit_duration: float = 0.28
@export var toast_bottom_margin: float = 19.0
