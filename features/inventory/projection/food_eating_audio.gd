extends AudioStreamPlayer3D

## One lazy voice per eater, shared by every successful food-item action.
## The actor owns its lifetime; no actor registry, polling or saved audio state.
const SCENE_PATH := "res://features/inventory/projection/food_eating_audio.tscn"

@export var cue: GameSoundCue
var _previous_path := ""
var _rng := RandomNumberGenerator.new()


static func play_for(actor) -> void:
	# Inventory notifications can synchronously remove the actor before this call.
	if Engine.is_editor_hint() or not is_instance_valid(actor) \
		or actor.is_queued_for_deletion() or not actor.is_inside_tree():
		return
	var audio = actor.get_node_or_null("FoodEatingAudio")
	if audio == null:
		audio = (load(SCENE_PATH) as PackedScene).instantiate()
		actor.add_child(audio)
	audio.play_meal()


func _ready() -> void:
	finished.connect(_on_finished)


func play_meal() -> void:
	if cue == null or not is_inside_tree():
		return
	var path := cue.choose_path(_previous_path, _rng)
	var next_stream := cue.get_stream(path)
	if next_stream == null:
		return
	_previous_path = path
	stop()
	stream = next_stream
	volume_db = cue.volume_db
	pitch_scale = cue.choose_pitch(_rng)
	set_meta("clip_path", path)
	play()


func _on_finished() -> void:
	stream = null
