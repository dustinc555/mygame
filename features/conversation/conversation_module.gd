extends RefCounted

## Conversation feature module.
##
## Bridge: the conversation controller that drives dialogue between the player and
## live actors and surfaces it on the HUD.
##
## Installed by GameBootstrap into BridgeRoot.

const CONVERSATION := preload("res://features/conversation/conversation_controller.gd")

const CORE := []
const PROJECTION := []
const SIM := []
const BRIDGE := [
	{"name": "ConversationController", "script": CONVERSATION, "service": CONVERSATION.SERVICE_ID},
]
