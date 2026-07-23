extends Resource

class_name ItemBuildCommand

## Stable-ID command contract. A future placement bridge may submit this to
## fixed-tick inventory execution without carrying actor or scene references.
@export var command_id := ""
@export var actor_id := ""
@export var item_definition_path := ""
@export var count := 1


func to_record() -> Dictionary:
	return {
		"command_id": command_id,
		"actor_id": actor_id,
		"item_definition_path": item_definition_path,
		"count": count,
	}
