extends Resource

class_name EquipmentGripProfile

const SITTING_POLICY_KEEP_EQUIPPED := "keep_equipped"
const SITTING_POLICY_HIDE := "hide"
const SITTING_POLICY_RELAX := "relax"
const GRIP_CLASS_ONE_HAND_MELEE := "one_hand_melee"
const GRIP_CLASS_OFFHAND_SHIELD := "offhand_shield"
const GRIP_CLASS_TWO_HAND_WEAPON := "two_hand_weapon"
const GRIP_CLASS_POLEARM := "polearm"
const GRIP_CLASS_BOW := "bow"
const GRIP_CLASS_CROSSBOW := "crossbow"
const GRIP_CLASS_THROWN := "thrown"
const PRIMARY_GRIP_MARKER := "GripPoint_Primary"
const SECONDARY_GRIP_MARKER := "GripPoint_Secondary"

@export var profile_id := "one_hand_melee"
@export var display_name := "One-Hand Melee"
@export var grip_class_id := GRIP_CLASS_ONE_HAND_MELEE
@export var primary_bone := "hand_r"
@export var secondary_bone := ""
@export var primary_socket_id := "right_hand_one_hand"
@export var secondary_socket_id := ""
@export var primary_grip_marker := PRIMARY_GRIP_MARKER
@export var secondary_grip_marker := SECONDARY_GRIP_MARKER
@export var requires_two_hands := false
@export var animation_stance_id := "one_hand_melee"
@export var sitting_policy := SITTING_POLICY_KEEP_EQUIPPED
@export_multiline var authoring_notes := ""
