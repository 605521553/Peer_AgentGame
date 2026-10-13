class_name ClimbProfile
extends Resource
## Distances are metres; durations seconds. IK never scales bones.
@export_range(0.4, 2.0) var up_step_duration: float = 0.94
@export_range(0.4, 2.0) var down_step_duration: float = 1.08
@export var hand_clearance: float = 0.19
@export var foot_clearance: float = 0.24
@export var weight_shift: float = 0.045
@export var body_distance: float = 0.54
@export var arm_upper_length: float = 0.52
@export var arm_lower_length: float = 0.52
@export var leg_upper_length: float = 0.46
@export var leg_lower_length: float = 0.46
@export var ik_weight: float = 1.0
@export var turn_duration: float = 1.15
@export var taunt_duration: float = 1.65
@export var return_duration: float = 1.15
