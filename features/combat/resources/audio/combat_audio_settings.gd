@tool
extends Resource
class_name CombatAudioSettings
const PROFILE := preload("res://features/combat/resources/combat_item_audio_profile.gd")

@export var enabled := true
@export_group("Mix")
@export var bus: StringName = &"Master"
@export_range(-60.0, 0.0, 0.5) var volume_db := -4.0
@export_range(0.0, 3.0, 0.1) var critical_gain_db := 1.5
@export_group("Spatial playback")
@export_range(1.0, 150.0, 1.0) var max_distance_m := 35.0
@export_range(0.1, 20.0, 0.1) var unit_size_m := 5.0
@export_range(2, 64, 1) var max_voices := 24
@export_group("Contact approximation")
## No simulated hit locations: use these torso slots in order, never head/feet.
@export var torso_slots := PackedStringArray(["chest", "undershirt"])
## Values use CombatItemAudioProfile.Surface. Unlisted races use flesh.
@export var race_body_surfaces: Dictionary[String, int] = {"quadbot": PROFILE.Surface.METAL, "skeleton": PROFILE.Surface.BONE}
@export var zombie_race_ids := PackedStringArray(["rustdead"])
## Exact attack IDs; add an authored attack here when its contact is a thrust.
@export var stab_attack_ids := PackedStringArray(["stab", "sword_stab", "spear_thrust"])
