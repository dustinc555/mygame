extends "res://features/actors/bridge/capabilities/actor_capability.gd"

class_name CarryCapability

## Owns one concern: the durable relationship of one actor physically carrying
## another (who carries whom, eligibility, collision suppression). Pose/bone
## positioning is presentation and lives in CarryPoseSolver, driven by the
## carrier's projection node -- see features/actors/projection/carry_pose_solver.gd.
##
## This capability names NO WorldActor type. Actors are held as CharacterBody3D
## (engine transform/collision) plus the partner's CarryCapability (same-type,
## no new edge) and a sibling VitalsCapability wired in by the owning actor.
## Faction eligibility is evaluated by the actor facade (faction is a node
## property that changes at runtime) and passed in as a bool. Instead of reaching
## up to emit the actor's state_changed, this emits carry_changed, which the
## actor observes -- inverting the dependency so the capability never references
## the actor node's class.

const DEFAULT_CARRY_POSE_PROFILE: HumanoidCarryPoseProfile = preload("res://features/actors/resources/humanoid_carry_pose_profiles/default.tres")

## Emitted whenever this actor starts or stops carrying / being carried. The
## owning actor connects this to re-emit its own state_changed signal.
signal carry_changed()

## Pose data read by CarryPoseSolver on the carrier side. Data only -- no logic.
var carry_pose_profile: HumanoidCarryPoseProfile = DEFAULT_CARRY_POSE_PROFILE

var _owner_body: CharacterBody3D
var _vitals: VitalsCapability

var _carried_body: CharacterBody3D
var _carried_carry: CarryCapability
var _carrier_body: CharacterBody3D
var _carrier_carry: CarryCapability
var _stored_collision_layer := 1
var _stored_collision_mask := 1
var _has_stored_collision := false


func _init() -> void:
	super._init(&"carry")


func setup(target_actor: Node) -> void:
	super.setup(target_actor)
	_owner_body = target_actor as CharacterBody3D


## Wired by the owning actor at capability-creation time so eligibility can read
## life state without a get_capability lookup (which would need the actor type).
func bind_vitals(vitals: VitalsCapability) -> void:
	if _vitals != null and _vitals.life_state_changed.is_connected(_on_life_state_changed):
		_vitals.life_state_changed.disconnect(_on_life_state_changed)
	_vitals = vitals
	if _vitals != null and not _vitals.life_state_changed.is_connected(_on_life_state_changed):
		_vitals.life_state_changed.connect(_on_life_state_changed)


## The actor node this capability belongs to, as a plain physics body. Lets a
## partner CarryCapability reach the carried/carrier body without naming WorldActor.
func get_owner_body() -> CharacterBody3D:
	return _owner_body


func teardown() -> void:
	if _vitals != null and _vitals.life_state_changed.is_connected(_on_life_state_changed):
		_vitals.life_state_changed.disconnect(_on_life_state_changed)
	if _carried_carry != null:
		_detach_carried_character()
	if _carrier_carry != null and _carrier_carry._carried_carry == self:
		_carrier_carry._detach_carried_character()
	_restore_carried_collision()
	_owner_body = null
	_vitals = null
	_carried_body = null
	_carried_carry = null
	_carrier_body = null
	_carrier_carry = null
	super.teardown()

# ---------------------------------------------------------------------------
# Relationship state
# ---------------------------------------------------------------------------

func begin_carry(target_carry: CarryCapability, carrier_is_same_faction := false) -> bool:
	if _owner_body == null or not is_instance_valid(_owner_body):
		return false
	if _vitals == null or _vitals.life_state != NpcRules.LifeState.ALIVE:
		return false
	if target_carry == null or target_carry == self:
		return false
	var target_body := target_carry.get_owner_body()
	if target_body == null or not is_instance_valid(target_body) or target_body == _owner_body:
		return false
	# Carry relationships are a one-to-one matching, never a tree. An actor may
	# occupy either side of one relationship, but can never carry and be carried.
	if _carried_carry != null or _carrier_carry != null:
		return false
	if not target_carry.can_be_carried_by(carrier_is_same_faction):
		return false
	_attach_carried_character(target_carry, target_body)
	return true


func drop() -> CharacterBody3D:
	if _owner_body == null or not is_instance_valid(_owner_body):
		return null
	var carried := _detach_carried_character()
	if carried == null:
		return null
	carried.global_position = _owner_body.global_position - _owner_body.transform.basis.z * 0.9
	carried.velocity = Vector3(_owner_body.transform.basis.z.x, 0.0, _owner_body.transform.basis.z.z) * 0.5
	carry_changed.emit()
	return carried


func can_be_carried() -> bool:
	return can_be_carried_by(false)


## Whether this actor may be picked up. Same-faction carriers may always carry
## (rescue an ally); otherwise the target must be asleep, dead, or downed. The
## same-faction test is resolved by the actor facade and passed in as data.
func can_be_carried_by(carrier_is_same_faction: bool) -> bool:
	if _owner_body == null or not is_instance_valid(_owner_body):
		return false
	# Reject both occupied relationship roles. Checking the capability links,
	# rather than only valid bodies, also keeps partially torn-down state from
	# ever becoming a recursive carry chain.
	if _carrier_carry != null or _carried_carry != null:
		return false
	if carrier_is_same_faction:
		return true
	if _vitals == null:
		return false
	var owner_life_state := _vitals.life_state
	return owner_life_state == NpcRules.LifeState.ASLEEP \
		or owner_life_state == NpcRules.LifeState.DEAD \
		or _vitals.is_downed_state()


func is_carried() -> bool:
	return _carrier_body != null and is_instance_valid(_carrier_body)


func is_carrying_someone() -> bool:
	return _carried_body != null and is_instance_valid(_carried_body)


func is_handling_carried_character() -> bool:
	return is_carrying_someone()


func get_carried_character() -> CharacterBody3D:
	return _carried_body if _carried_body != null and is_instance_valid(_carried_body) else null


func get_carrier() -> CharacterBody3D:
	return _carrier_body if _carrier_body != null and is_instance_valid(_carrier_body) else null


## Carrying requires an active carrier. Any incapacitating life-state transition
## releases the passenger immediately, before another actor can interact with
## either body. This also covers sleep and death, which cannot sustain carrying.
func _on_life_state_changed(_previous_state: int, next_state: int) -> void:
	if next_state != NpcRules.LifeState.ALIVE and _carried_carry != null:
		drop()


func _attach_carried_character(target_carry: CarryCapability, target_body: CharacterBody3D) -> void:
	_carried_carry = target_carry
	_carried_body = target_body
	target_carry._carrier_carry = self
	target_carry._carrier_body = _owner_body
	target_carry._stored_collision_layer = target_body.collision_layer
	target_carry._stored_collision_mask = target_body.collision_mask
	target_carry._has_stored_collision = true
	target_body.collision_layer = 0
	target_body.collision_mask = 0
	target_body.velocity = Vector3.ZERO
	carry_changed.emit()
	target_carry.carry_changed.emit()


func _detach_carried_character() -> CharacterBody3D:
	if _carried_carry == null:
		return null
	var carried_carry := _carried_carry
	var carried_body := _carried_body
	_carried_carry = null
	_carried_body = null
	carried_carry._carrier_carry = null
	carried_carry._carrier_body = null
	carried_carry._restore_carried_collision()
	carried_carry.carry_changed.emit()
	return carried_body if carried_body != null and is_instance_valid(carried_body) else null


func _restore_carried_collision() -> void:
	if _owner_body == null or not is_instance_valid(_owner_body) or not _has_stored_collision:
		return
	_owner_body.collision_layer = _stored_collision_layer
	_owner_body.collision_mask = _stored_collision_mask
	_has_stored_collision = false
