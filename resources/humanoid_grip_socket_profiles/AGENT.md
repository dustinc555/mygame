# AGENT.md

## Humanoid Grip Socket Profiles
- Grip socket profiles calibrate where generated body grip sockets sit relative to the final animated hand bones.
- These resources are data, not the primary 3D editing surface. Runtime/generated sockets are actual `HumanoidGripSocketMarker` nodes named `RightHandGrip`, `LeftHandGrip`, etc.
- Use `scenes/tools/humanoid_grip_socket_calibrator.tscn` as the primary visual editing surface for shared socket transforms.
- Tune socket profile transforms when every compatible item sits wrong on a specific body shape or skeleton.
- Do not tune item-specific blade, handle, or shield orientation here; use `GripPoint_Primary` in the equipment wrapper scene for item-specific fixes.
- Current phase-1 sockets are `right_hand_one_hand`/`RightHandGrip` and `left_hand_shield`/`LeftHandGrip`.
- Future/generated/customized bodies should generate or refresh these sockets after final rig, hand size, and body proportion changes; do not edit the imported character model for equipment placement.
- A character scaled taller still uses the same named sockets because they are attached under the final hand bones; only hand-size/local palm offsets need profile recalibration.
- Grip socket transforms are per skeleton/rig family, not per character instance and not per weapon.
- Enable `HumanoidCharacter.show_grip_socket_markers` in a test scene when visually debugging socket direction; the marker colors match item grip markers.
- In the calibrator scene, move/rotate the saved `RightHandGrip` or `LeftHandGrip` scene node, then toggle `save_grips_to_profile` on the scene root to write the shared profile resource.
- Saving the calibrator scene alone is not enough; the root `save_grips_to_profile` action must update the profile fields consumed at runtime.
- Future metadata sockets include two-hand weapon, polearm, bow, crossbow, and thrown grips; they should stay profile-driven rather than hardcoded per item.
