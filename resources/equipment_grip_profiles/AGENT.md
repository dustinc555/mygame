# AGENT.md

## Equipment Grip Profiles
- Grip profiles describe how an item attaches and which animation stance family it belongs to.
- Current fully supported phase-1 profiles are `one_hand_melee` and `offhand_shield`.
- Future profiles should be added here before wiring items to them, such as `two_hand_weapon`, `polearm`, `bow`, `crossbow`, and `thrown`. These future profiles are metadata-only until matching animation/IK support lands.
- A profile is not a full animation system by itself; it is metadata used by `HumanoidCharacter` and future animation/IK systems.
- `primary_bone` controls the main attachment bone. `secondary_bone` is reserved for future two-hand or IK support.
- `primary_socket_id` selects the body-side grip socket calibration, such as `right_hand_one_hand` or `left_hand_shield`.
- Runtime socket pivots are generated body marker nodes with human-readable names from `HumanoidGripSocketProfile`, such as `RightHandGrip`, `LeftHandGrip`, or `RightHandTwoHandGrip`.
- `primary_grip_marker` names the item-side marker that should align to that socket, usually `GripPoint_Primary`.
- `animation_stance_id` should name the animation stance family that this item should eventually request.

## Phase-1 Validation
- Validate `one_hand_melee` and `offhand_shield` against normal idle, walk, run, and fighting/combat poses when available.
- Sitting is not a primary validation target for hand-held gear in phase 1.
- For `one_hand_melee`, use the current dagger as the visual reference: `GripPoint_Primary` aligns to `RightHandGrip`, handle seated in clenched fist, blade/head projecting naturally from the fist, no torso crossing, no reverse/downward knuckle-claw look unless intentionally authored for that item.
- If one item is wrong on every body, tune its `GripPoint_Primary`; if every item is wrong on one body, tune that body's grip socket profile.
