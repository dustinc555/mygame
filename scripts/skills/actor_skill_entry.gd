extends Resource

class_name ActorSkillEntry

@export var skill_id := ""
@export var level := 1
@export var xp := 0.0


func setup(target_skill_id: String, target_level: int = 1, target_xp: float = 0.0) -> ActorSkillEntry:
	skill_id = target_skill_id
	level = maxi(0, target_level)
	xp = maxf(0.0, target_xp)
	return self
