class_name HumanoidCharacter
extends WorldActor

## Phase 0 stub — replaces the 5403-line god class.
##
## Provides the minimum interface for existing subclasses to compile.
## Humanoid-specific behavior will move to capabilities and child nodes
## as migration progresses (see plans/migration.md Phase 4).
##
## Do NOT add behavior here. Add it to a capability or child node instead.

# ---------------------------------------------------------------------------
# Equipment slots (humanoid-specific; EquipmentCapability validates against these)
# ---------------------------------------------------------------------------

const EQUIPMENT_SLOTS: Array[String] = ["undershirt", "hands", "chest", "legs", "feet", "backpack", "head", "weapon", "offhand"]
const EQUIPMENT_SLOT_LABELS := {
	"undershirt": "Undershirt",
	"hands": "Hands",
	"head": "Head",
	"chest": "Chest",
	"backpack": "Backpack",
	"legs": "Legs",
	"feet": "Feet",
	"weapon": "Weapon",
	"offhand": "Offhand",
}


func get_equipment_slot_names() -> Array[String]:
	return EQUIPMENT_SLOTS.duplicate()


func get_equipment_slot_label(slot_name: String) -> String:
	return str(EQUIPMENT_SLOT_LABELS.get(slot_name, slot_name.capitalize()))

# ---------------------------------------------------------------------------
# Properties subclasses reference directly
# ---------------------------------------------------------------------------

var is_selected: bool = false
var is_focused: bool = false
var is_inspected: bool = false

signal appearance_changed


## Authored appearance handed to the body projection (which owns it at runtime).
## Character definitions / scenes set this; null renders a default inferred human.
@export var appearance_data: CharacterAppearanceData

var _inspect_ring: Node3D = null
var _body: BodyProjection = null
var _is_getting_up: bool = false


const LOCOMOTION_SPEED_THRESHOLD := 0.05


func _ready() -> void:
	super._ready()
	# Group registrations consumed across the codebase: actor query + population
	# scans, pickup checks, the debug "Live bodies" metric, coordinator target
	# selection ("combat_actor" — literal to avoid a WorldActor-adjacent edge back
	# into combat_coordinator; keep in sync with CombatCoordinator.COMBAT_ACTOR_GROUP).
	add_to_group("humanoid_character")
	add_to_group("npc_character")
	add_to_group("combat_actor")
	_apply_canon_definition()
	_setup_body_projection()


## Canon characters (Mira, Tomas, ...) always use their disk definition. Enforced
## at the class layer so every scene gets it — no per-scene appearance authoring.
## An explicitly authored appearance_data still wins (records applied upstream).
func _apply_canon_definition() -> void:
	var canon := CanonCharacters.record_for_name(member_name)
	if canon == null:
		return
	if appearance_data == null and not canon.appearance.is_empty():
		appearance_data = PopulationController.appearance_from_record(canon.appearance)
	if starting_skill_levels.is_empty() and not canon.skill_levels.is_empty():
		starting_skill_levels = canon.skill_levels.duplicate(true)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_update_locomotion_animation(delta)
	_update_carried_pose()
	_update_ground_markers()
	if is_in_cell_custody():
		_update_cell_custody_animation(delta)
	elif life_state != NpcRules.LifeState.ALIVE and life_state != NpcRules.LifeState.ASLEEP:
		var carry := get_carry()
		# Carried bodies hold the limp pose; jailed bodies hold the cot lay pose.
		if carry == null or not carry.is_carried():
			var body := _body as HumanoidBodyProjection
			if body != null:
				body.process_downed_visuals(delta)


# Limp pose held while being carried; frozen at the profile's sample ratio.
const CARRY_POSE_ANIMATION_NAMES: Array[String] = ["LiftAir_Fall"]

# Cell custody presentation (ported verbatim from main): unconscious prisoners
# ANIMATE laying down (IdleToLay at speed) and freeze at the lay ratio; waking
# prisoners stand at the cell stand position and play LayToIdle from the wake
# ratio. Ratios are asserted by validate_law_order_jail.
const CELL_CUSTODY_LAY_ANIMATION_NAME := "IdleToLay"
const CELL_CUSTODY_WAKE_ANIMATION_NAME := "LayToIdle"
const CELL_CUSTODY_LAY_FREEZE_RATIO := 0.6
const CELL_CUSTODY_WAKE_START_RATIO := 0.25

var _cell_custody_unconscious_pose_animation := ""
var _cell_custody_lay_freeze_remaining := 0.0
var _cell_custody_lay_pose_frozen := false
var _cell_custody_wake_animation := ""
var _cell_custody_wake_remaining := 0.0


## ALIVE prisoners walk in and stand; downed prisoners are placed on the cot.
func enter_cell_custody(cell, cell_position: Vector3, cell_rotation: Vector3) -> void:
	var body := _body as HumanoidBodyProjection
	if body != null:
		body.cancel_downed_visual_transitions()
		body.stop_ragdoll_simulation(true)
	_restore_downed_collision_shape()
	var enter_position := cell_position
	if life_state == NpcRules.LifeState.ALIVE:
		var stand_position := _get_cell_custody_stand_position(cell)
		if stand_position != Vector3.INF:
			enter_position = stand_position
	running = false
	super.enter_cell_custody(cell, enter_position, cell_rotation)


func _on_enter_custody() -> void:
	super._on_enter_custody()
	rotation = Vector3(0.0, rotation.y, 0.0)
	var body := _body as HumanoidBodyProjection
	if is_recoverable_downed_state():
		_apply_downed_collision_shape()
		_play_cell_unconscious_pose()
	elif life_state == NpcRules.LifeState.ALIVE and body != null:
		body.stop_clip(true)
		body.play_random_idle_animation(true)


func _on_exit_custody() -> void:
	super._on_exit_custody()
	_clear_cell_custody_visual_state(true)


func _clear_cell_custody_visual_state(restore_collision := true) -> void:
	_cell_custody_unconscious_pose_animation = ""
	_cell_custody_lay_freeze_remaining = 0.0
	_cell_custody_lay_pose_frozen = false
	_cell_custody_wake_animation = ""
	_cell_custody_wake_remaining = 0.0
	if restore_collision:
		_restore_downed_collision_shape()
	var body := _body as HumanoidBodyProjection
	if body != null:
		body.stop_clip(true)


func _play_cell_unconscious_pose() -> void:
	var body := _body as HumanoidBodyProjection
	var animation_name := CELL_CUSTODY_LAY_ANIMATION_NAME
	if body == null or not body.has_clip(animation_name):
		animation_name = body.pick_preferred_available_clip(CARRY_POSE_ANIMATION_NAMES) if body != null else ""
	if animation_name.is_empty() or body == null or body.get_primary_animation_player() == null:
		return
	_cell_custody_unconscious_pose_animation = animation_name
	_cell_custody_lay_pose_frozen = false
	_cell_custody_wake_animation = ""
	_cell_custody_wake_remaining = 0.0
	body.play_clip(animation_name, 0.0, true, 0.0)
	_cell_custody_lay_freeze_remaining = maxf(0.0, body.clip_length(animation_name) * CELL_CUSTODY_LAY_FREEZE_RATIO)
	if _cell_custody_lay_freeze_remaining <= 0.0:
		_freeze_cell_lay_pose()


func _freeze_cell_lay_pose() -> void:
	var body := _body as HumanoidBodyProjection
	if _cell_custody_unconscious_pose_animation.is_empty() or body == null or body.get_primary_animation_player() == null:
		return
	var animation_name := _cell_custody_unconscious_pose_animation
	body.seek_clip(animation_name, body.clip_length(animation_name) * CELL_CUSTODY_LAY_FREEZE_RATIO, true, 0.0)
	_cell_custody_lay_freeze_remaining = 0.0
	_cell_custody_lay_pose_frozen = true


func _start_cell_wake_animation() -> void:
	_cell_custody_unconscious_pose_animation = ""
	_cell_custody_lay_freeze_remaining = 0.0
	_cell_custody_lay_pose_frozen = false
	var body := _body as HumanoidBodyProjection
	var animation_name := CELL_CUSTODY_WAKE_ANIMATION_NAME
	if body == null or not body.has_clip(animation_name):
		_cell_custody_wake_animation = ""
		_cell_custody_wake_remaining = 0.0
		if body != null:
			body.stop_clip(true)
			body.play_random_idle_animation(true)
		return
	var animation_length := body.clip_length(animation_name)
	var start_time := animation_length * CELL_CUSTODY_WAKE_START_RATIO
	_cell_custody_wake_animation = animation_name
	_cell_custody_wake_remaining = maxf(0.0, animation_length - start_time)
	body.play_clip(animation_name, 0.0, true, 0.0)
	body.seek_clip(animation_name, start_time, true, 1.0)
	if _cell_custody_wake_remaining <= 0.0:
		_finish_cell_wake_animation()


func _finish_cell_wake_animation() -> void:
	_cell_custody_wake_animation = ""
	_cell_custody_wake_remaining = 0.0
	var body := _body as HumanoidBodyProjection
	if body != null:
		body.stop_clip(true)
		body.play_random_idle_animation(true)


## Per-frame custody driver (main's _update_cell_custody_animation): downed
## prisoners animate down onto the cot then hold; waking prisoners finish the
## LayToIdle clip then idle. Life-state transitions themselves are GECS-owned —
## this only presents them.
func _update_cell_custody_animation(delta: float) -> void:
	velocity = Vector3.ZERO
	var body := _body as HumanoidBodyProjection
	if is_recoverable_downed_state():
		if _cell_custody_unconscious_pose_animation.is_empty() or body == null or body.get_primary_animation_player() == null:
			_play_cell_unconscious_pose()
		elif body.get_current_clip() != _cell_custody_unconscious_pose_animation:
			# Something stomped the cot pose (a late visual transition, a sync
			# hiccup) — re-assert it, same self-healing as the carried pose.
			_play_cell_unconscious_pose()
		elif not _cell_custody_lay_pose_frozen:
			_cell_custody_lay_freeze_remaining = maxf(0.0, _cell_custody_lay_freeze_remaining - delta)
			if _cell_custody_lay_freeze_remaining <= 0.0:
				_freeze_cell_lay_pose()
		return
	if life_state == NpcRules.LifeState.ALIVE:
		_restore_downed_collision_shape()
		_cell_custody_unconscious_pose_animation = ""
		_cell_custody_lay_freeze_remaining = 0.0
		_cell_custody_lay_pose_frozen = false
		if not _cell_custody_wake_animation.is_empty():
			_cell_custody_wake_remaining = maxf(0.0, _cell_custody_wake_remaining - delta)
			if _cell_custody_wake_remaining <= 0.0:
				_finish_cell_wake_animation()


func _get_cell_custody_stand_position(cell) -> Vector3:
	if cell != null and is_instance_valid(cell) and cell.has_method("get_prisoner_stand_position"):
		var stand_position: Variant = cell.call("get_prisoner_stand_position", self)
		if stand_position is Vector3:
			return stand_position
	return Vector3.INF

var _carried_pose_animation := ""


## Carried-side presentation: picked up = ragdoll off + frozen limp pose (the
## carrier's _update_carried_pose pins our transform to their skeleton each frame);
## put down = back to downed visuals on the ground.
func _on_carry_changed() -> void:
	super._on_carry_changed()
	var body := _body as HumanoidBodyProjection
	var carry := get_carry()
	if body == null or carry == null:
		return
	if carry.is_carried():
		if body.is_ragdoll_active():
			body.stop_ragdoll_simulation(true)
		_play_carried_pose_animation(carry)
	else:
		_carried_pose_animation = ""
		# The carried drape leaves the actor basis flipped; an upside-down basis makes
		# the ragdoll re-sync spawn bones BELOW the origin — inside the floor — so the
		# body free-falls out of the world. Stand the transform upright first.
		rotation = Vector3(0.0, rotation.y, 0.0)
		velocity = Vector3.ZERO
		if is_downed_state():
			body.enter_downed_visuals(life_state == NpcRules.LifeState.DEAD)
			_apply_downed_collision_shape()


func _play_carried_pose_animation(carry: CarryCapability) -> void:
	var body := _body as HumanoidBodyProjection
	if body == null:
		return
	var animation_name := body.pick_preferred_available_clip(CARRY_POSE_ANIMATION_NAMES)
	if animation_name.is_empty():
		return
	_carried_pose_animation = animation_name
	# Blend 0: the pose freezes immediately after play; blending into a speed-0
	# freeze snapshots a random mix of the previous animation (nondeterministic drape).
	if not body.play_clip(animation_name, 0.0, true, 0.0):
		return
	var profile := carry.carry_pose_profile
	var pose_ratio := clampf(profile.carried_pose_time_ratio, 0.0, 1.0) if profile != null else 0.0
	# speed_scale 0 freezes the sampled frame — a held limp pose, not a looping fall.
	body.seek_clip(animation_name, body.clip_length(animation_name) * pose_ratio, true, 0.0)


## Vitals (GECS) is the life-state authority; this override maps state changes onto
## downed/ragdoll presentation. ASLEEP is not a downed state — it keeps normal posing.
func _on_vitals_life_state_changed(previous_state: int, next_state: int) -> void:
	super._on_vitals_life_state_changed(previous_state, next_state)
	var body := _body as HumanoidBodyProjection
	if body == null:
		return
	var carry := get_carry()
	if carry != null and carry.is_carried():
		# Carried bodies keep the limp pose; ground presentation resumes on drop.
		return
	var was_downed := previous_state != NpcRules.LifeState.ALIVE and previous_state != NpcRules.LifeState.ASLEEP
	var is_downed := next_state != NpcRules.LifeState.ALIVE and next_state != NpcRules.LifeState.ASLEEP
	if is_downed and not was_downed:
		velocity = Vector3.ZERO
		rotation = Vector3(0.0, rotation.y, 0.0)
		body.enter_downed_visuals(next_state == NpcRules.LifeState.DEAD)
		_apply_downed_collision_shape()
	elif was_downed and not is_downed:
		if is_in_cell_custody():
			# Main's _wake_in_cell presentation: stand up at the cell stand position
			# and play the wake clip; the recovery itself came from the vitals sim.
			_restore_downed_collision_shape()
			var stand_position := _get_cell_custody_stand_position(get_cell_custody_target())
			if stand_position != Vector3.INF:
				global_position = stand_position
			velocity = Vector3.ZERO
			rotation = Vector3(0.0, rotation.y, 0.0)
			_start_cell_wake_animation()
		else:
			body.restore_from_downed_visuals()
			_restore_downed_collision_shape()


## Positions any actor this one is carrying against our own skeleton. Runs on the
## CARRIER (which owns the anchor skeleton) after super() has moved us this frame,
## so the carried body reads our post-move transform with no one-frame lag. Pose
## math lives in the projection-layer CarryPoseSolver; carry state lives in the
## capability. Neither names WorldActor -- see carry_pose_solver.gd.
func _update_carried_pose() -> void:
	var carry := get_carry()
	if carry == null or not carry.is_carrying_someone():
		return
	var carried := carry.get_carried_character()
	if carried == null:
		return
	var carrier_body := get_body_projection()
	if carrier_body == null:
		return
	var carried_humanoid := carried as HumanoidCharacter
	var carried_body := carried_humanoid.get_body_projection() if carried_humanoid != null else null
	carried.global_transform = CarryPoseSolver.solve_carried_transform(carrier_body, self, carry.carry_pose_profile, carried_body, carried)


# --- Stand-up presentation (rising from a seat) ---
# Rise where you sat: the Sitting_Exit clip plays in place for its full
# length, then the character settles one small step in front of the seat —
# instead of teleporting a body-length away mid-sit.
var _stand_up_exit_remaining := 0.0
var _stand_up_position := Vector3.INF


func process_world_actor_movement(delta: float) -> void:
	if _stand_up_exit_remaining > 0.0:
		velocity = Vector3.ZERO
		return
	super.process_world_actor_movement(delta)


func begin_stand_up_exit(final_position: Vector3) -> void:
	_begin_pose_exit(HumanoidBodyProjection.SITTING_EXIT_ANIMATION_NAME, final_position)


## Waking from a bed: play the get-up clip in place, then step off the bed.
func begin_lay_exit(final_position: Vector3) -> void:
	_begin_pose_exit(HumanoidBodyProjection.LAY_EXIT_ANIMATION_NAME, final_position)


func _begin_pose_exit(clip_name: String, final_position: Vector3) -> void:
	var body := get_body_projection() as HumanoidBodyProjection
	var clip_length := body.get_clip_length(clip_name) if body != null else 0.0
	_stand_up_position = final_position
	if clip_length <= 0.0:
		_finish_stand_up_exit()
		return
	_stand_up_exit_remaining = clip_length
	if body != null:
		body.play_clip(clip_name, 0.0, true, 0.1)


func _finish_stand_up_exit() -> void:
	_stand_up_exit_remaining = 0.0
	if _stand_up_position.is_finite():
		global_position = _stand_up_position
	_stand_up_position = Vector3.INF


# --- Counter duty (a shopkeeper working their counter) ---
# Set by BarServiceArea while the owner stands at the barkeeper service point.
var _counter_duty_active := false
var _counter_duty_face_position := Vector3.ZERO
var _counter_gesture_name := ""
var _counter_gesture_pending := ""


func begin_counter_duty(face_position: Vector3) -> void:
	_counter_duty_active = true
	_counter_duty_face_position = face_position


func end_counter_duty() -> void:
	if not _counter_duty_active:
		return
	_counter_duty_active = false
	_counter_gesture_name = ""
	_counter_gesture_pending = ""


func is_on_counter_duty() -> bool:
	return _counter_duty_active


## One-shot gesture (Counter_Show / Counter_Give) layered over the counter
## idle. Gestures play whole and in order: a request during a running gesture
## queues (one deep) instead of restarting it — rapid purchases must not chop
## the give animation into twitches.
func play_counter_gesture(animation_name: String) -> void:
	if not _counter_duty_active:
		return
	if _counter_gesture_name.is_empty():
		_counter_gesture_name = animation_name
	else:
		_counter_gesture_pending = animation_name


## Where a conversation partner should stand. On counter duty that is the
## customer side of the counter — a straight-line approach point can land
## behind the counter's wall and route the talker around the building.
func get_interaction_position(_member: Node) -> Vector3:
	if _counter_duty_active:
		var counter_front := _counter_customer_position()
		if counter_front.is_finite():
			return counter_front
	return global_position - global_basis.z * 1.4


func _counter_customer_position() -> Vector3:
	if not is_inside_tree():
		return Vector3.INF
	var best := Vector3.INF
	var best_distance := 2.5
	for counter in get_tree().get_nodes_in_group("shop_counter"):
		if not (counter is Node3D) or not counter.has_method("get_customer_position"):
			continue
		var distance: float = (counter as Node3D).global_position.distance_to(global_position)
		if distance < best_distance:
			best_distance = distance
			best = counter.get_customer_position()
	return best


func _play_counter_duty_animation(body: HumanoidBodyProjection) -> void:
	_face_world_position(_counter_duty_face_position)
	var current_clip := body.get_current_clip()
	if not _counter_gesture_name.is_empty():
		if current_clip == _counter_gesture_name:
			if body.is_current_clip_playing():
				return
			# Finished a full gesture; the queued one (if any) plays next,
			# force-restarted since it may be the same clip.
			_counter_gesture_name = _counter_gesture_pending
			_counter_gesture_pending = ""
			if not _counter_gesture_name.is_empty() and body.play_clip(_counter_gesture_name, 0.0, true, 0.1):
				return
			_counter_gesture_name = ""
		elif body.play_clip(_counter_gesture_name, 0.0, true, 0.15):
			return
		else:
			_counter_gesture_name = ""
			_counter_gesture_pending = ""
	if current_clip == HumanoidBodyProjection.COUNTER_ENTER_ANIMATION_NAME and body.is_current_clip_playing():
		return
	if current_clip != HumanoidBodyProjection.COUNTER_ENTER_ANIMATION_NAME \
			and current_clip != HumanoidBodyProjection.COUNTER_IDLE_ANIMATION_NAME \
			and body.play_clip(HumanoidBodyProjection.COUNTER_ENTER_ANIMATION_NAME, 0.0, false, 0.2):
		return
	body.play_clip(HumanoidBodyProjection.COUNTER_IDLE_ANIMATION_NAME, 0.0, false, 0.2)


## Feeds movement state to the body projection's locomotion animation driver.
func _update_locomotion_animation(delta: float) -> void:
	var body := get_body_projection() as HumanoidBodyProjection
	if body == null:
		return
	if life_state == NpcRules.LifeState.ASLEEP:
		# Lie down through the enter clip, then hold its final pose as the
		# sleeping loop (the library has no separate lying idle).
		if body.get_current_clip() != HumanoidBodyProjection.LAY_ENTER_ANIMATION_NAME:
			body.play_clip(HumanoidBodyProjection.LAY_ENTER_ANIMATION_NAME, 0.0, true, 0.2)
		return
	if life_state != NpcRules.LifeState.ALIVE:
		return
	# Combat action/reaction clips own the animation player while they run; feeding
	# locomotion during them stomps the swing back to idle mid-clip.
	if _system_combat_action_active or _system_combat_reaction_remaining > 0.0:
		return
	if is_in_cell_custody():
		return
	# Rising from a seat: hold the exit clip to its end, then step off.
	if _stand_up_exit_remaining > 0.0:
		_stand_up_exit_remaining -= delta
		if _stand_up_exit_remaining <= 0.0:
			_finish_stand_up_exit()
		return
	if is_sitting():
		# Hold the seated pose: after the enter clip finishes, loop the sitting idle.
		var current_clip := body.get_current_clip()
		if current_clip == HumanoidBodyProjection.SITTING_ENTER_ANIMATION_NAME and body.is_current_clip_playing():
			return
		if current_clip != HumanoidBodyProjection.SITTING_IDLE_ANIMATION_NAME:
			body.play_clip(HumanoidBodyProjection.SITTING_IDLE_ANIMATION_NAME, 0.0, true, 0.2)
		return
	# Counter duty holds the barkeeper pose while standing at the counter;
	# walking to/from the counter stays plain locomotion.
	if _counter_duty_active and not _has_move_target \
			and Vector2(velocity.x, velocity.z).length() <= LOCOMOTION_SPEED_THRESHOLD:
		_play_counter_duty_animation(body)
		return
	# Mining swings own the animation while actively working the node (main's rule:
	# face the node, loop the Mining clip; the walk-to-node phase stays locomotion).
	var interaction := get_interaction()
	if interaction != null and interaction.mining_active and interaction.current_mining_node is Node3D:
		_face_world_position((interaction.current_mining_node as Node3D).global_position)
		if body.play_clip(HumanoidBodyProjection.MINING_ANIMATION_NAME):
			return
	# Scavenging works the same way: kneel and rummage at the pile while the
	# roll timer runs; walking between piles stays locomotion.
	if interaction != null and interaction.scavenging_active and interaction.current_scavenging_node is Node3D:
		_face_world_position((interaction.current_scavenging_node as Node3D).global_position)
		if body.play_clip(HumanoidBodyProjection.SCAVENGING_ANIMATION_NAME):
			return
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	# System combat movement drives velocity without a nav move target, so it counts
	# as moving for locomotion the same way nav-agent movement does.
	var has_movement_intent := _has_move_target or (_system_move_active and not _system_move_settled)
	# Fighters square up (main's combat idle): fists raised unarmed, weapon guard
	# armed, shield loop with a shield — held while the live target is in striking
	# distance, and used instead of the relaxed idle whenever engaged and stopped.
	var hold_combat_idle := _should_hold_combat_idle_animation()
	var is_moving := horizontal_speed > LOCOMOTION_SPEED_THRESHOLD and has_movement_intent and not hold_combat_idle
	if (hold_combat_idle or (not is_moving and is_in_combat())) and _play_combat_idle_animation(body):
		return
	var wants_run := is_running_enabled() and is_moving and not sneaking
	# Exhausted actors slump into the tired idle (pre-migration rule).
	var use_tired_idle := get_fatigue_stage() == NpcRules.FatigueStage.EXHAUSTED
	body.update_locomotion(delta, horizontal_speed, move_speed, is_moving, wants_run, sneaking, use_tired_idle)


## True when this fighter should stand their ground in the combat idle: a live
## combat target within striking distance (main's rule + hysteresis).
func _should_hold_combat_idle_animation() -> bool:
	var target := get_current_combat_target()
	if target == null or not (target is Node3D):
		return false
	var target_position := (target as Node3D).global_position
	if absf(target_position.y - global_position.y) > move_target_vertical_tolerance:
		return false
	var flat := Vector2(target_position.x - global_position.x, target_position.z - global_position.z)
	return flat.length() <= get_attack_range() + 0.18


func _play_combat_idle_animation(body: HumanoidBodyProjection) -> bool:
	var idle_name := _get_current_combat_idle_animation_name(body)
	if idle_name.is_empty() or not body.has_clip(idle_name):
		return false
	return body.play_clip(idle_name)


## Main's priority: one-hand melee uses its set idle (Sword_Idle); a shield
## overrides other stances with the shield loop; otherwise the stance set's
## idle (unarmed = generated Unarmed_Combat_Idle — fists up).
func _get_current_combat_idle_animation_name(body: HumanoidBodyProjection) -> String:
	var animation_set = _get_current_combat_animation_set()
	if animation_set != null and str(animation_set.stance_id) == EquipmentGripProfile.GRIP_CLASS_ONE_HAND_MELEE:
		return str(animation_set.idle_animation_name)
	if _has_equipped_shield() and body.has_clip(HumanoidBodyProjection.SHIELD_COMBAT_IDLE_ANIMATION_NAME):
		return HumanoidBodyProjection.SHIELD_COMBAT_IDLE_ANIMATION_NAME
	if animation_set != null:
		return str(animation_set.idle_animation_name)
	return ""


func _has_equipped_shield() -> bool:
	var offhand_item := get_equipped_item(ItemDefinition.EQUIP_SLOT_OFFHAND)
	if offhand_item == null or offhand_item.grip_profile == null:
		return false
	return str(offhand_item.grip_profile.get("grip_class_id")) == EquipmentGripProfile.GRIP_CLASS_OFFHAND_SHIELD


## Creates the humanoid body projection child and builds its visual. The
## projection owns presentation; the actor just instantiates it and hands over
## authored appearance.
func _setup_body_projection() -> void:
	for child in get_children():
		if child is BodyProjection:
			child.free()
	_body = _create_body_projection()
	if _body == null:
		return
	_body.name = "BodyProjection"
	_body.bind_actor(self)
	var humanoid_body := _body as HumanoidBodyProjection
	if humanoid_body != null:
		humanoid_body.configure_appearance(appearance_data)
	add_child(_body)
	_body.setup_visual()
	var equipment := get_equipment()
	if equipment != null and not equipment.equipment_changed.is_connected(_on_equipment_changed):
		equipment.equipment_changed.connect(_on_equipment_changed)


## Rebuilds equipment visuals on the body when equipped items change at runtime.
func _on_equipment_changed(_changed_slots: Array) -> void:
	var body := get_body_projection()
	if body != null:
		body.rebuild_visual_for_equipment()


func get_body_projection() -> BodyProjection:
	return _body if _body != null and is_instance_valid(_body) else null


func get_character_visual_root() -> Node3D:
	var body := get_body_projection()
	return body.get_visual_root() if body != null else null


## Sneak toggles play the crouch enter/exit transition clips; state changes
## that must snap (death, sleep, being carried) pass play_transition=false.
## Reinstated after the reorganize dropped it — interaction_capability still
## calls _set_sneaking_state by name, and without it sneak state never drove
## the crouch transitions.
func set_sneaking_enabled(enabled: bool) -> bool:
	_set_sneaking_state(enabled, true)
	if enabled:
		running = false
	return true


func set_running_enabled(enabled: bool) -> bool:
	if enabled:
		_set_sneaking_state(false, true)
	running = enabled
	return true


func _set_sneaking_state(value: bool, play_transition: bool) -> bool:
	var next_sneaking := value and life_state == NpcRules.LifeState.ALIVE
	if sneaking == next_sneaking:
		return false
	sneaking = next_sneaking
	var body := get_body_projection() as HumanoidBodyProjection
	if body != null:
		if play_transition:
			if sneaking:
				body.cancel_run_transition()
				body.start_crouch_enter_animation()
			else:
				body.start_crouch_exit_animation()
		else:
			body.cancel_crouch_transition()
			body.cancel_run_transition()
	state_changed.emit()
	return true

# ---------------------------------------------------------------------------
# Selection / focus — visual concerns, will move to a child node
# ---------------------------------------------------------------------------

func set_selected(value: bool) -> void:
	is_selected = value


func set_focused(value: bool) -> void:
	is_focused = value

# ---------------------------------------------------------------------------
# Inventory display — get_inventory_for_display / is_displaying_work_inventory
# now live on WorldActor (delegating to InventoryCapability).
# ---------------------------------------------------------------------------

func get_inventory_display_title() -> String:
	return member_name


func shows_inventory_weight() -> bool:
	return true


func shows_inventory_equipment() -> bool:
	return true

# ---------------------------------------------------------------------------
# Life state helpers — will move to VitalsCapability
# ---------------------------------------------------------------------------

func is_downed_state() -> bool:
	return super.is_downed_state()


func force_kill(_attacker: Node = null) -> void:
	super.force_kill(_attacker)


func _enter_cinder_dead_state_in_place() -> void:
	pass


func _cancel_get_up() -> void:
	_is_getting_up = false


func is_carrying_someone() -> bool:
	var carry := get_carry()
	return carry.is_carrying_someone() if carry != null else false


func get_carried_character() -> HumanoidCharacter:
	var carry := get_carry()
	return carry.get_carried_character() as HumanoidCharacter if carry != null else null


func is_carried() -> bool:
	var carry := get_carry()
	return carry.is_carried() if carry != null else false


func can_be_carried() -> bool:
	var carry := get_carry()
	return carry.can_be_carried() if carry != null else false


func can_be_carried_by(carrier: HumanoidCharacter) -> bool:
	var carry := get_carry()
	if carry == null:
		return false
	# Faction is a node property (and mutable at runtime), so the same-faction
	# rescue rule is resolved here and passed to the capability as data.
	var same_faction := carrier != null and is_instance_valid(carrier) and carrier.faction_name == faction_name
	return carry.can_be_carried_by(same_faction)


func get_carrier() -> HumanoidCharacter:
	var carry := get_carry()
	return carry.get_carrier() as HumanoidCharacter if carry != null else null


func drop_carried_character() -> void:
	var carry := get_carry()
	if carry != null:
		carry.drop()

# ---------------------------------------------------------------------------
# Ground markers — selection/inspect rings are top-level nodes seated on the
# ground via raycast each physics frame, so they hug the floor instead of
# inheriting the actor origin (which sits below the surface by capsule offset).
# ---------------------------------------------------------------------------

# Ray starts at mid-torso: the actor origin sits below the floor surface by the
# collision capsule offset, so a low start point would begin inside the floor and miss.
const GROUND_MARKER_RAYCAST_UP := 1.0
const GROUND_MARKER_RAYCAST_DOWN := 24.0
const SELECTION_GROUND_MARKER_HEIGHT := 0.02
const UPRIGHT_SELECTION_GROUND_MARKER_HEIGHT := 0.34


func _update_ground_markers() -> void:
	if _inspect_ring != null and is_instance_valid(_inspect_ring) and _inspect_ring.visible:
		_seat_ground_marker(_inspect_ring, _selection_marker_height())


func _seat_ground_marker(marker: Node3D, marker_height: float) -> void:
	if marker == null or not is_instance_valid(marker) or not marker.is_inside_tree():
		return
	marker.top_level = true
	marker.global_position = get_ground_marker_position(marker_height)
	marker.global_rotation = Vector3.ZERO


func _selection_marker_height() -> float:
	if life_state == NpcRules.LifeState.ALIVE and not is_ragdoll_active():
		return UPRIGHT_SELECTION_GROUND_MARKER_HEIGHT
	return SELECTION_GROUND_MARKER_HEIGHT


func get_ground_marker_position(marker_height: float = 0.03) -> Vector3:
	var anchor_position := get_follow_anchor_position()
	var fallback := Vector3(anchor_position.x, anchor_position.y + marker_height, anchor_position.z)
	var world := get_world_3d()
	if world == null:
		return fallback
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(anchor_position.x, anchor_position.y + GROUND_MARKER_RAYCAST_UP, anchor_position.z),
		Vector3(anchor_position.x, anchor_position.y - GROUND_MARKER_RAYCAST_DOWN, anchor_position.z)
	)
	# World geometry only — markers must seat on the floor, not on actor capsules.
	query.collision_mask = ACTOR_COLLISION_MASK
	query.exclude = [get_rid()]
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.has("position"):
		return (hit["position"] as Vector3) + Vector3(0.0, marker_height, 0.0)
	return fallback


const WORLD_TEXT_NOTICE_SCENE = preload("res://features/world/projection/effects/world_text_notice.tscn")

@export var overhead_text_height := 2.4


const SPEECH_TEXT_COLOR := Color(0.94, 0.92, 0.86, 1.0)


func show_world_notice(text: String, color: Color = Color.WHITE, duration: float = 1.5) -> void:
	_show_world_notice(text, color, duration)


## Spoken NPC lines (barks, alarms, warnings) render as slow-rising overhead
## text. Every reaction system routes through here; the WorldActor base is a
## silent stub, so this override IS the audible/visible layer.
func show_world_speech(text: String, duration: float = 2.0) -> void:
	_show_world_notice(text, SPEECH_TEXT_COLOR, duration, 0.22)


## Floating combat/world feedback text above the actor ("Hit", "Dodge", ...).
func _show_world_notice(message: String, color: Color = Color(1.0, 0.28, 0.28, 1.0), lifetime: float = 1.0, rise_height: float = 0.4) -> void:
	var tree := get_tree()
	if tree == null or tree.current_scene == null or message.is_empty():
		return
	var notice := WORLD_TEXT_NOTICE_SCENE.instantiate()
	tree.current_scene.add_child(notice)
	notice.setup(global_position + Vector3(0.0, overhead_text_height, 0.0), message, color, lifetime, rise_height)


## Override in subclasses to provide a custom BodyProjection type.
func _create_body_projection() -> BodyProjection:
	return HumanoidBodyProjection.new()


## Applies a new appearance to a LIVE actor and rebuilds the visual (barber,
## population profiles applied after realization, appearance editor saves).
## Pre-spawn callers just set appearance_data before add_child instead.
func apply_appearance_data(next_appearance: CharacterAppearanceData) -> void:
	if next_appearance == null:
		return
	appearance_data = next_appearance.make_copy()
	var body := _body as HumanoidBodyProjection
	if body != null:
		body.configure_appearance(appearance_data)
		body.apply_automatic_eyebrow_style()
		body.rebuild_visual_for_appearance()
	appearance_changed.emit()

# ---------------------------------------------------------------------------
# Combat attack presentation — overrides of the WorldActor hooks driven by
# GameCombatResolutionSystem. Attack CHOICE is weighted-random over the stance
# animation set owned by the body projection; damage stays GECS-owned.
# ---------------------------------------------------------------------------

const COMBAT_ACTION_BLEND_SECONDS := 0.05
const DEFAULT_COMBAT_ACTION_SECONDS := 0.45
const DEFAULT_COMBAT_IMPACT_RATIO := 0.45
const COMBAT_ATTACK_SKILL_XP := 0.85

var _combat_rng := RandomNumberGenerator.new()


func get_system_combat_attack_spec() -> Dictionary:
	var body := _body as HumanoidBodyProjection
	var attack = _choose_combat_attack(_get_current_combat_animation_set())
	if attack == null or body == null:
		return {}
	var action_names: Array[String] = attack.get_animation_names()
	var timing := body.get_combat_action_timing(action_names, float(attack.impact_ratio), DEFAULT_COMBAT_ACTION_SECONDS)
	return {
		"animation_names": PackedStringArray(action_names),
		"attack_id": str(attack.attack_id),
		"hit_reaction_names": PackedStringArray(attack.get_hit_reaction_names()),
		"total_seconds": float(timing.get("total_seconds", DEFAULT_COMBAT_ACTION_SECONDS)),
		"first_clip_seconds": float(timing.get("first_clip_seconds", 0.0)),
		"impact_seconds": float(timing.get("impact_seconds", DEFAULT_COMBAT_ACTION_SECONDS * DEFAULT_COMBAT_IMPACT_RATIO)),
	}


func on_system_combat_attack_started(target_actor: Node, animation_names: PackedStringArray) -> float:
	if target_actor is Node3D:
		_face_character(target_actor as Node3D)
	var body := _body as HumanoidBodyProjection
	if body != null:
		body.stop_clip(true)
	spend_fatigue(NpcRules.FATIGUE_ATTACK_COST)
	_award_combat_attack_xp()
	if animation_names.is_empty():
		return 0.0
	return play_system_combat_action_clip(str(animation_names[0]))


func play_system_combat_action_clip(animation_name: String) -> float:
	var body := _body as HumanoidBodyProjection
	if animation_name.is_empty() or body == null:
		return 0.0
	var clip_seconds := body.clip_length(animation_name)
	body.play_clip(animation_name, 0.0, true, COMBAT_ACTION_BLEND_SECONDS)
	return clip_seconds


func is_ragdoll_active() -> bool:
	var body := _body as HumanoidBodyProjection
	return body != null and body.is_ragdoll_active()


## Seated presentation: enter clip once, then hold the sitting idle (the locomotion
## driver stands down while seated — see _update_locomotion_animation).
func _start_sitting_enter_animation() -> void:
	var body := _body as HumanoidBodyProjection
	if body != null:
		body.play_clip(HumanoidBodyProjection.SITTING_ENTER_ANIMATION_NAME, 0.0, true, 0.15)


func _start_sitting_exit_animation() -> void:
	var body := _body as HumanoidBodyProjection
	if body != null:
		body.play_clip(HumanoidBodyProjection.SITTING_EXIT_ANIMATION_NAME, 0.0, true, 0.15)


func has_bandageable_wounds() -> bool:
	return get_open_cut_damage() > 0.0 or get_bleed_rate() > 0.0


func can_receive_bandage() -> bool:
	return life_state != NpcRules.LifeState.DEAD and has_bandageable_wounds()


func _face_character(character: Node3D) -> void:
	if character == null or not is_instance_valid(character):
		return
	_face_world_position(character.global_position)


func _face_world_position(world_position: Vector3) -> void:
	var look_position := world_position
	look_position.y = global_position.y
	if global_position.distance_squared_to(look_position) > 0.0001:
		look_at(look_position, Vector3.UP)


# Dodge clip candidates, first available in the animation library wins. The vendor
# library has NO dedicated dodge clip (verified against all 37 clips 2026-07-02), so
# Crouch_Enter — a quick duck — stands in until a real dodge animation is imported.
# When one lands, name it "Dodge" and it takes precedence automatically.
const DODGE_ANIMATION_CANDIDATES: Array[String] = ["Dodge", "Dodge_Left", "Dodge_Right", "Evade", "Crouch_Enter"]


## Victim-side presentation for a resolved attack. Landed hits float the damage
## dealt; dodges and blocks are shown through animation only (no hover text).
## Returns the reaction clip length so the sim can stagger this fighter.
func play_system_combat_hit_reaction(attacker: Node, outcome: String, attack_id: String, hit_reaction_names: PackedStringArray, is_critical: bool, has_shield_block: bool, can_actively_defend: bool, final_damage: float) -> float:
	if attacker is Node3D:
		_face_character(attacker as Node3D)
	var body := _body as HumanoidBodyProjection
	match outcome:
		"dodged":
			if body == null:
				return 0.0
			for candidate in DODGE_ANIMATION_CANDIDATES:
				if body.has_clip(candidate):
					return body.play_combat_reaction_clip(candidate, COMBAT_ACTION_BLEND_SECONDS)
			return 0.0
		"blocked":
			if body == null or not can_actively_defend:
				return 0.0
			var block_clip := body.pick_block_reaction_clip(has_shield_block, _get_current_combat_animation_set(), HumanoidBodyProjection.SHIELD_BLOCK_ANIMATION_NAMES, HumanoidBodyProjection.BLOCK_ANIMATION_NAME)
			return body.play_combat_reaction_clip(block_clip, COMBAT_ACTION_BLEND_SECONDS) if not block_clip.is_empty() else 0.0
		_:
			var damage_points := maxi(1, int(round(final_damage)))
			_show_world_notice("%d%s" % [damage_points, "!" if is_critical else ""], Color(1.0, 0.62, 0.18, 1.0) if is_critical else Color(1.0, 0.42, 0.42, 1.0))
			if body == null or not can_actively_defend:
				return 0.0
			var reaction_names: Array[String] = []
			reaction_names.assign(hit_reaction_names)
			var hit_clip := body.pick_hit_reaction_clip(attack_id, reaction_names)
			return body.play_combat_reaction_clip(hit_clip, COMBAT_ACTION_BLEND_SECONDS) if not hit_clip.is_empty() else 0.0


func _get_current_combat_animation_set():
	var body := _body as HumanoidBodyProjection
	if body == null:
		return null
	return body.get_combat_animation_set(_get_current_combat_animation_stance_id())


func _get_current_combat_animation_stance_id() -> String:
	var weapon := get_equipped_item(ItemDefinition.EQUIP_SLOT_WEAPON)
	if weapon == null:
		return HumanoidBodyProjection.UNARMED_STANCE_ID
	if weapon.grip_profile != null:
		var stance_id := str(weapon.grip_profile.get("animation_stance_id"))
		if not stance_id.is_empty():
			return stance_id
	return EquipmentGripProfile.GRIP_CLASS_ONE_HAND_MELEE


func _choose_combat_attack(animation_set):
	if animation_set == null:
		return null
	var available_attacks: Array = []
	var total_weight := 0.0
	for attack in animation_set.attacks:
		if attack == null:
			continue
		var action_names: Array[String] = attack.get_animation_names()
		if _body == null or not (_body as HumanoidBodyProjection).can_play_combat_action(action_names):
			continue
		available_attacks.append(attack)
		total_weight += maxf(float(attack.weight), 0.0)
	if available_attacks.is_empty() or total_weight <= 0.0:
		return null
	var roll := _combat_rng.randf_range(0.0, total_weight)
	for attack in available_attacks:
		roll -= maxf(float(attack.weight), 0.0)
		if roll <= 0.0:
			return attack
	return available_attacks[available_attacks.size() - 1]


func _award_combat_attack_xp() -> void:
	var skill_id := _get_current_weapon_skill_id()
	add_skill_xp(skill_id, COMBAT_ATTACK_SKILL_XP, "combat_attack")
	add_skill_xp(SkillRules.ATTRIBUTE_DEXTERITY, COMBAT_ATTACK_SKILL_XP * 0.01, "weapon_attack")
	match skill_id:
		SkillRules.COMBAT_DAGGERS:
			add_skill_xp(SkillRules.ATTRIBUTE_DEXTERITY, COMBAT_ATTACK_SKILL_XP * 0.12, "finesse_attack")
		SkillRules.COMBAT_AXES_ONE_HANDED:
			add_skill_xp(SkillRules.ATTRIBUTE_STRENGTH, COMBAT_ATTACK_SKILL_XP * 0.08, "axe_attack")
		SkillRules.COMBAT_UNARMED:
			add_skill_xp(SkillRules.ATTRIBUTE_STRENGTH, COMBAT_ATTACK_SKILL_XP * 0.04, "unarmed_attack")
		_:
			add_skill_xp(SkillRules.ATTRIBUTE_DEXTERITY, COMBAT_ATTACK_SKILL_XP * 0.025, "weapon_attack")


func _get_current_weapon_skill_id() -> String:
	var weapon_item := get_equipped_item(ItemDefinition.EQUIP_SLOT_WEAPON)
	if weapon_item == null:
		return SkillRules.COMBAT_UNARMED
	var descriptor := "%s %s" % [weapon_item.display_name.to_lower(), weapon_item.resource_path.to_lower()]
	if descriptor.contains("dagger"):
		return SkillRules.COMBAT_DAGGERS
	if descriptor.contains("axe"):
		return SkillRules.COMBAT_AXES_ONE_HANDED
	if descriptor.contains("sword"):
		return SkillRules.COMBAT_SWORDS_ONE_HANDED
	return SkillRules.COMBAT_SWORDS_ONE_HANDED
