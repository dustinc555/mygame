extends GutTest

class Actor extends HumanoidCharacter:
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _physics_process(_delta: float) -> void: pass
	func is_law_prisoner() -> bool: return true
	func is_in_cell_custody() -> bool: return true

class Law extends LawOrderController:
	var clock := 100
	var actors := {}
	var jail: Node
	var releases: Array[String] = []
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _now_minute() -> int: return clock
	func _find_actor_by_key(key: String) -> WorldActor: return actors.get(key)
	func _find_jail_by_id(_id: String) -> Node: return jail
	func _apply_actor_law_meta(_actor: WorldActor, _record: Dictionary) -> void: pass
	func _release_prisoner(actor: WorldActor, _record: Dictionary, _jail) -> void:
		releases.append(actor.stable_id)
		prisoner_records.erase(actor.stable_id)

class JailPort extends Node:
	var notifications := 0
	func tell_prisoner_sentence(_actor: WorldActor, _record: Dictionary) -> bool:
		notifications += 1
		return true

@warning_ignore("missing_tool")
class RealJail extends SettlementJail:
	var conversation: ConversationController
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _get_conversation_controller() -> Node: return conversation
	func get_warden_actor() -> Node: return null

class DialogueWindow extends Control:
	var shows := 0
	func hide_conversation() -> void: hide()
	func show_conversation(_title, _text, _responses, _speaker, _target) -> void:
		shows += 1

var law: Law
var npc: Actor
var window: DialogueWindow
var conversation: ConversationController
var viewport: SubViewport
var camera: Camera3D

func before_each() -> void:
	law = Law.new()
	add_child_autofree(law)
	law.jail = JailPort.new()
	law.add_child(law.jail)
	viewport = SubViewport.new()
	viewport.size = Vector2i(800, 600)
	add_child_autofree(viewport)
	camera = Camera3D.new()
	viewport.add_child(camera)
	camera.current = true
	npc = Actor.new()
	npc.stable_id = "raider"
	viewport.add_child(npc)
	npc.position = Vector3(0, 0, -5)
	law.actors[npc.stable_id] = npc
	window = DialogueWindow.new()
	viewport.add_child(window)
	conversation = ConversationController.new()
	viewport.add_child(conversation)
	conversation.conversation_window = window
	conversation._initialized = true

func sentence_record() -> Dictionary:
	return {"state": "jailed", "actor_key": "raider", "jail_id": "jail", "sentence_minutes": 60,
		"sentence_decision_at_minute": 90, "sentence_decision_given": false, "release_at_minute": -1}

func test_npc_sentence_does_not_request_a_player_conversation() -> void:
	law.prisoner_records[npc.stable_id] = sentence_record()
	law._process_prisoners()
	assert_true(law.prisoner_records[npc.stable_id].sentence_decision_given)
	assert_eq(law.jail.notifications, 0, "NPC custody is not a player dialogue event")
	law.clock = 151
	law._process_prisoners()
	assert_eq(law.releases, ["raider"], "Release cannot require a conversation")

func test_unrealized_prisoner_is_sentenced_at_recorded_world_deadline() -> void:
	law.actors.clear()
	law.prisoner_records["raider"] = sentence_record()
	law._process_prisoners()
	assert_true(law.prisoner_records.raider.sentence_decision_given)
	assert_eq(law.prisoner_records.raider.release_at_minute, 150)
	law.actors["raider"] = npc
	law.clock = 151
	law._process_prisoners()
	assert_eq(law.releases, ["raider"])
	assert_eq(law.jail.notifications, 0)

func test_system_conversation_refuses_npc_recipient_even_on_camera() -> void:
	assert_false(conversation.begin_system_conversation(npc, npc, "You serve a day."))
	assert_eq(window.shows, 0)
	assert_false(conversation._conversation_pause_requested)

func test_system_conversation_refuses_off_camera_party_recipient() -> void:
	npc.player_party_member = true
	npc.position = Vector3(0, 0, 5)
	assert_false(conversation.begin_system_conversation(npc, npc, "You serve a day."))
	assert_eq(window.shows, 0)

func test_system_conversation_accepts_visible_party_recipient_once() -> void:
	npc.player_party_member = true
	assert_true(conversation.begin_system_conversation(npc, npc, "You serve a day."))
	assert_eq(window.shows, 1)
	assert_false(conversation.begin_system_conversation(npc, npc, "Replacement"), "An active conversation must not be hijacked")
	conversation._end_conversation()

func test_jail_never_queues_npc_dialogue_and_discards_unwatched_party_queue() -> void:
	var jail := RealJail.new()
	add_child_autofree(jail)
	jail.conversation = conversation
	assert_false(jail.tell_prisoner_sentence(npc, {"sentence_minutes": 60}))
	assert_true(jail._pending_sentence_announcements.is_empty())
	npc.player_party_member = true
	assert_true(jail.tell_prisoner_sentence(npc, {"sentence_minutes": 60}))
	assert_eq(jail._pending_sentence_announcements.size(), 1)
	npc.position = Vector3(0, 0, 5)
	jail._process_sentence_announcements(0.1)
	assert_true(jail._pending_sentence_announcements.is_empty())
	assert_eq(window.shows, 0)

func test_jail_discards_destroyed_projection_in_pending_queue() -> void:
	var jail := RealJail.new()
	add_child_autofree(jail)
	jail.conversation = conversation
	npc.player_party_member = true
	assert_true(jail.tell_prisoner_sentence(npc, {"sentence_minutes": 60}))
	npc.free()
	jail._process_sentence_announcements(0.1)
	assert_true(jail._pending_sentence_announcements.is_empty())
	assert_eq(window.shows, 0)

func test_unwatched_party_sentence_expires_without_notification() -> void:
	npc.player_party_member = true
	npc.position = Vector3(0, 0, 5)
	var jail := RealJail.new()
	add_child_autofree(jail)
	jail.conversation = conversation
	law.jail = jail
	law.prisoner_records[npc.stable_id] = sentence_record()
	law._process_prisoners()
	assert_eq(law.prisoner_records[npc.stable_id].release_at_minute, 150)
	assert_true(jail._pending_sentence_announcements.is_empty())
	assert_eq(window.shows, 0)
	law.clock = 151
	law._process_prisoners()
	assert_eq(law.releases, ["raider"])
	assert_eq(window.shows, 0)
