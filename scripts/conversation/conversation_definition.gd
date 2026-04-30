extends Resource

class_name ConversationDefinition

@export var conversation_id := ""
@export var display_name := ""
@export var start_node_id := ""
@export var nodes: Array[Resource] = []


func get_node_by_id(node_id: String):
	for node in nodes:
		if node != null and node.node_id == node_id:
			return node
	return null
