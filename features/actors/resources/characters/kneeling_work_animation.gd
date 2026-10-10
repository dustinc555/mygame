extends Resource

## Cuts in the authored Fixing_Kneeling clip, in seconds. Used after rig retargeting.
## Reload the character to apply edits; the vendor animation remains untouched.
@export_range(0.1, 4.0, 0.001) var work_start_seconds := 1.066667
@export_range(0.2, 4.1, 0.001) var work_end_seconds := 2.0
@export_range(0.0, 1.0, 0.01) var loop_blend_seconds := 0.2
@export_range(0.2, 5.0, 0.01) var rise_start_seconds := 4.0
