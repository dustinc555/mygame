extends Resource

class_name EquipmentGripProfile

const SITTING_POLICY_KEEP_EQUIPPED := "keep_equipped"
const SITTING_POLICY_HIDE := "hide"
const SITTING_POLICY_RELAX := "relax"

@export var profile_id := "one_hand_melee"
@export var display_name := "One-Hand Melee"
@export var primary_bone := "hand_r"
@export var secondary_bone := ""
@export var requires_two_hands := false
@export var animation_stance_id := "one_hand_melee"
@export var sitting_policy := SITTING_POLICY_KEEP_EQUIPPED
@export_multiline var authoring_notes := ""
