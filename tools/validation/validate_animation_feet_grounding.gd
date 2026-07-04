extends Node

## Feet-grounding regression check for transplanted vendor animations.
## Baseline 2026-07-04: UAL1 "Idle" native on the vendor mannequin bottoms out
## at Y=0.0000; uncompensated transplant onto the browser avatar measured
## -0.0318 (feet 3.2 cm underground, visible in every level). With
## AnimationPositionScale compensation the transplant must stay within 8 mm.

const BROWSER_SCENE := preload("res://tools/animation_browser/animation_browser.tscn")
const UAL1 := preload("res://assets/vendor/quaternius/universal_animation_library_1_pro/UAL1_Pro.glb")
const FLOOR_TOLERANCE := 0.008

var _frames := 0
var _browser: Node3D
var _source_root: Node3D
var _source_player: AnimationPlayer
var _source_skeleton: Skeleton3D
var _min_browser_y := 1000.0
var _min_source_y := 1000.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	_browser = BROWSER_SCENE.instantiate()
	add_child(_browser)
	_source_root = UAL1.instantiate() as Node3D
	_source_root.position = Vector3(5, 0, 0)
	add_child(_source_root)
	_source_player = AnimationRetargetLib.find_animation_player(_source_root)
	_source_skeleton = AnimationRetargetLib.find_skeleton(_source_root)

func _lowest_bone_y(skeleton: Skeleton3D) -> float:
	var lowest := 1000.0
	for bone_index in range(skeleton.get_bone_count()):
		var y := (skeleton.global_transform * skeleton.get_bone_global_pose(bone_index)).origin.y
		lowest = minf(lowest, y)
	return lowest

func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 12:
		_source_player.play("Idle")
		for clip in _browser._clips:
			if String(clip["name"]) == "Idle" and String(clip["pack"]) == "UAL1 Pro":
				_browser._play_clip(clip)
	if _frames > 20 and _frames <= 140:
		_min_browser_y = minf(_min_browser_y, _lowest_bone_y(_browser._skeleton))
		_min_source_y = minf(_min_source_y, _lowest_bone_y(_source_skeleton))
	if _frames == 141:
		printerr("FEET_GROUNDING source-native=%.4f transplant=%.4f tolerance=%.3f" % [_min_source_y, _min_browser_y, FLOOR_TOLERANCE])
		if absf(_min_browser_y) < FLOOR_TOLERANCE and absf(_min_source_y) < FLOOR_TOLERANCE:
			printerr("FEET_GROUNDING_OK")
		else:
			printerr("FEET_GROUNDING_FAILED")
		get_tree().quit()
