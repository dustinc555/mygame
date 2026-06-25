extends Resource

class_name ConversationNode

@export var node_id := ""
@export var speaker_name := ""
@export_multiline var text := ""
@export var responses: Array[Resource] = []
@export var effects: Array[Resource] = []
@export var ends_conversation := false
