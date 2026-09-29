extends Resource

class_name CombatPursuitSettings

## Maximum horizontal distance between a committed fighter and its opponent.
## Not a home/camp tether or an acquisition radius. Exact player attack orders
## remain explicit orders; Defend does not gain autonomous pursuit.
@export_range(1.0, 500.0, 1.0, "suffix:m") var leash_distance := 100.0

func contains(fighter_position: Vector3, target_position: Vector3) -> bool:
	var offset := Vector2(target_position.x - fighter_position.x, target_position.z - fighter_position.z)
	return offset.length_squared() <= leash_distance * leash_distance
