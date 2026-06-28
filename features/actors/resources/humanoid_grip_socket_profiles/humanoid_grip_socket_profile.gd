@tool
extends Resource

class_name HumanoidGripSocketProfile

const RIGHT_HAND_BONE_NAME := "hand_r"
const LEFT_HAND_BONE_NAME := "hand_l"
const SOCKET_RIGHT_HAND_ONE_HAND := "right_hand_one_hand"
const SOCKET_LEFT_HAND_SHIELD := "left_hand_shield"
const SOCKET_RIGHT_HAND_TWO_HAND_PRIMARY := "right_hand_two_hand_primary"
const SOCKET_LEFT_HAND_TWO_HAND_SECONDARY := "left_hand_two_hand_secondary"
const SOCKET_RIGHT_HAND_POLEARM_PRIMARY := "right_hand_polearm_primary"
const SOCKET_LEFT_HAND_POLEARM_SECONDARY := "left_hand_polearm_secondary"
const SOCKET_LEFT_HAND_BOW_GRIP := "left_hand_bow_grip"
const SOCKET_RIGHT_HAND_BOW_DRAW := "right_hand_bow_draw"
const SOCKET_RIGHT_HAND_CROSSBOW_GRIP := "right_hand_crossbow_grip"
const SOCKET_LEFT_HAND_CROSSBOW_SUPPORT := "left_hand_crossbow_support"
const SOCKET_RIGHT_HAND_THROWN := "right_hand_thrown"

@export var profile_id := "default_humanoid"
@export var right_hand_one_hand := Transform3D.IDENTITY
@export var left_hand_shield := Transform3D.IDENTITY
@export var right_hand_two_hand_primary := Transform3D.IDENTITY
@export var left_hand_two_hand_secondary := Transform3D.IDENTITY
@export var right_hand_polearm_primary := Transform3D.IDENTITY
@export var left_hand_polearm_secondary := Transform3D.IDENTITY
@export var left_hand_bow_grip := Transform3D.IDENTITY
@export var right_hand_bow_draw := Transform3D.IDENTITY
@export var right_hand_crossbow_grip := Transform3D.IDENTITY
@export var left_hand_crossbow_support := Transform3D.IDENTITY
@export var right_hand_thrown := Transform3D.IDENTITY


func get_socket_ids() -> Array[String]:
	return [
		SOCKET_RIGHT_HAND_ONE_HAND,
		SOCKET_LEFT_HAND_SHIELD,
		SOCKET_RIGHT_HAND_TWO_HAND_PRIMARY,
		SOCKET_LEFT_HAND_TWO_HAND_SECONDARY,
		SOCKET_RIGHT_HAND_POLEARM_PRIMARY,
		SOCKET_LEFT_HAND_POLEARM_SECONDARY,
		SOCKET_LEFT_HAND_BOW_GRIP,
		SOCKET_RIGHT_HAND_BOW_DRAW,
		SOCKET_RIGHT_HAND_CROSSBOW_GRIP,
		SOCKET_LEFT_HAND_CROSSBOW_SUPPORT,
		SOCKET_RIGHT_HAND_THROWN,
	]


func get_socket_bone_name(socket_id: String) -> String:
	match socket_id:
		SOCKET_RIGHT_HAND_ONE_HAND, SOCKET_RIGHT_HAND_TWO_HAND_PRIMARY, SOCKET_RIGHT_HAND_POLEARM_PRIMARY, SOCKET_RIGHT_HAND_BOW_DRAW, SOCKET_RIGHT_HAND_CROSSBOW_GRIP, SOCKET_RIGHT_HAND_THROWN:
			return RIGHT_HAND_BONE_NAME
		SOCKET_LEFT_HAND_SHIELD, SOCKET_LEFT_HAND_TWO_HAND_SECONDARY, SOCKET_LEFT_HAND_POLEARM_SECONDARY, SOCKET_LEFT_HAND_BOW_GRIP, SOCKET_LEFT_HAND_CROSSBOW_SUPPORT:
			return LEFT_HAND_BONE_NAME
	return ""


func get_socket_transform(socket_id: String) -> Transform3D:
	match socket_id:
		SOCKET_RIGHT_HAND_ONE_HAND:
			return right_hand_one_hand
		SOCKET_LEFT_HAND_SHIELD:
			return left_hand_shield
		SOCKET_RIGHT_HAND_TWO_HAND_PRIMARY:
			return right_hand_two_hand_primary
		SOCKET_LEFT_HAND_TWO_HAND_SECONDARY:
			return left_hand_two_hand_secondary
		SOCKET_RIGHT_HAND_POLEARM_PRIMARY:
			return right_hand_polearm_primary
		SOCKET_LEFT_HAND_POLEARM_SECONDARY:
			return left_hand_polearm_secondary
		SOCKET_LEFT_HAND_BOW_GRIP:
			return left_hand_bow_grip
		SOCKET_RIGHT_HAND_BOW_DRAW:
			return right_hand_bow_draw
		SOCKET_RIGHT_HAND_CROSSBOW_GRIP:
			return right_hand_crossbow_grip
		SOCKET_LEFT_HAND_CROSSBOW_SUPPORT:
			return left_hand_crossbow_support
		SOCKET_RIGHT_HAND_THROWN:
			return right_hand_thrown
	return Transform3D.IDENTITY


func set_socket_transform(socket_id: String, socket_transform: Transform3D) -> void:
	match socket_id:
		SOCKET_RIGHT_HAND_ONE_HAND:
			right_hand_one_hand = socket_transform
		SOCKET_LEFT_HAND_SHIELD:
			left_hand_shield = socket_transform
		SOCKET_RIGHT_HAND_TWO_HAND_PRIMARY:
			right_hand_two_hand_primary = socket_transform
		SOCKET_LEFT_HAND_TWO_HAND_SECONDARY:
			left_hand_two_hand_secondary = socket_transform
		SOCKET_RIGHT_HAND_POLEARM_PRIMARY:
			right_hand_polearm_primary = socket_transform
		SOCKET_LEFT_HAND_POLEARM_SECONDARY:
			left_hand_polearm_secondary = socket_transform
		SOCKET_LEFT_HAND_BOW_GRIP:
			left_hand_bow_grip = socket_transform
		SOCKET_RIGHT_HAND_BOW_DRAW:
			right_hand_bow_draw = socket_transform
		SOCKET_RIGHT_HAND_CROSSBOW_GRIP:
			right_hand_crossbow_grip = socket_transform
		SOCKET_LEFT_HAND_CROSSBOW_SUPPORT:
			left_hand_crossbow_support = socket_transform
		SOCKET_RIGHT_HAND_THROWN:
			right_hand_thrown = socket_transform


func get_socket_node_name(socket_id: String) -> String:
	match socket_id:
		SOCKET_RIGHT_HAND_ONE_HAND:
			return "RightHandGrip"
		SOCKET_LEFT_HAND_SHIELD:
			return "LeftHandGrip"
		SOCKET_RIGHT_HAND_TWO_HAND_PRIMARY:
			return "RightHandTwoHandGrip"
		SOCKET_LEFT_HAND_TWO_HAND_SECONDARY:
			return "LeftHandTwoHandGrip"
		SOCKET_RIGHT_HAND_POLEARM_PRIMARY:
			return "RightHandPolearmGrip"
		SOCKET_LEFT_HAND_POLEARM_SECONDARY:
			return "LeftHandPolearmGrip"
		SOCKET_LEFT_HAND_BOW_GRIP:
			return "LeftHandBowGrip"
		SOCKET_RIGHT_HAND_BOW_DRAW:
			return "RightHandBowDraw"
		SOCKET_RIGHT_HAND_CROSSBOW_GRIP:
			return "RightHandCrossbowGrip"
		SOCKET_LEFT_HAND_CROSSBOW_SUPPORT:
			return "LeftHandCrossbowSupport"
		SOCKET_RIGHT_HAND_THROWN:
			return "RightHandThrownGrip"
	return "GripSocket"
