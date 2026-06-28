@tool
extends Resource

class_name HumanoidCarryPoseProfile

@export var profile_id := "default"
@export var carried_local_position := Vector3.ZERO
@export var rotation_degrees := Vector3(-18.9, 164.1, -163.6)
@export_range(0.0, 1.0, 0.01) var carried_pose_time_ratio := 0.0
@export var carrier_anchor_bones := PackedStringArray(["upperarm_r", "clavicle_r", "spine_03"])
@export var carried_anchor_bones := PackedStringArray(["spine_02", "spine_03", "pelvis"])
@export var carrier_anchor_local_offset := Vector3.ZERO
@export var carried_anchor_local_offset := Vector3.ZERO
# OFF: pure WYSIWYG — the calibrator's saved carried_local_position is used
# verbatim (note: the frozen pose shifts ~0.7m between standing and ragdoll
# pickups, so a manual position is exact for one path and offset for the other).
# ON: the runtime derives position by pinning carried_anchor_bones[0] at the
# shoulder + carrier_anchor_local_offset; the calibrator then tunes rotation/ratio.
@export var pin_carried_anchor := false
