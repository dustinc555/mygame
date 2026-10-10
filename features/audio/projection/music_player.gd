extends Node

var current_profile: AmbientMusicProfile

func play_music() -> void:
	if current_profile == null:
		return
	

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func set_music_profile(profile: AmbientMusicProfile) -> void:
	current_profile = profile
