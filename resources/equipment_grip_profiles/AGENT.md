# AGENT.md

## Equipment Grip Profiles
- Grip profiles describe how an item attaches and which animation stance family it belongs to.
- Current fully supported phase-1 profiles are `one_hand_melee` and `offhand_shield`.
- Future profiles should be added here before wiring items to them, such as `two_hand_sword`, `two_hand_axe`, `two_hand_blunt`, `polearm`, `bow`, `crossbow`, and `thrown`.
- A profile is not a full animation system by itself; it is metadata used by `HumanoidCharacter` and future animation/IK systems.
- `primary_bone` controls the main attachment bone. `secondary_bone` is reserved for future two-hand or IK support.
- `animation_stance_id` should name the animation stance family that this item should eventually request.

## Phase-1 Validation
- Validate `one_hand_melee` and `offhand_shield` against normal idle, walk, run, and fighting/combat poses when available.
- Sitting is not a primary validation target for hand-held gear in phase 1.
- For `one_hand_melee`, use the current dagger as the visual reference: handle seated in clenched fist, blade/head projecting naturally from the fist, no torso crossing, no reverse/downward knuckle-claw look unless intentionally authored for that item.
