# AGENT.md

## Tool Scenes
- Tool scenes are editor/operator workflows, not runtime gameplay implementations.
- Shared calibration tools may preview gameplay assets, but saved data must live in reusable resources such as `HumanoidGripSocketProfile`.
- Do not tune weapon placement per character instance. Shared humanoid grip calibration belongs in `resources/humanoid_grip_socket_profiles/`.
- `humanoid_grip_socket_calibrator.tscn` is the visual editing surface for shared generated body sockets like `RightHandGrip` and `LeftHandGrip`.
- `RightHandGrip` and `LeftHandGrip` must be real saved scene nodes so operators can select, move, and rotate them in the Godot editor without running the scene.
- In the calibrator scene, grip nodes must be selectable saved nodes under `GripHandles`; their parent guide nodes are synced to the preview skeleton's `hand_r` / `hand_l` bones.
- The preview model is only visual context for the rig family. Calibration data is hand-bone-local and must stay reusable across male, female, and generated bodies using the same base skeleton.
- The calibrator script may preview items and save/load profile data, but must not replace the saved grip marker nodes.
- The calibrator should show a non-gameplay skeleton overlay so operators can see both the generic humanoid mesh and the underlying rig while tuning hand sockets.
- The calibrator must write `right_hand_one_hand` and `left_hand_shield` directly into the assigned `HumanoidGripSocketProfile`; do not call profile helper methods from editor tool code.
- Expose a `last_status` message on the calibrator root so operators can confirm whether load/save affected the runtime profile.
- Moving grip handles should update the assigned profile in memory and mark `profile_dirty`; runtime tests still require toggling `save_grips_to_profile` so the `.tres` file on disk changes.
