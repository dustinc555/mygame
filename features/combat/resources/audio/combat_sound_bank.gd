@tool
extends Resource
class_name CombatSoundBank

const CUE := preload("res://features/audio/resources/game_sound_cue.gd")
@export var cues: Array[CUE] = []

func get_cue(cue_id: StringName) -> CUE:
	for cue in cues:
		if cue != null and cue.cue_id == cue_id:
			return cue
	return null
