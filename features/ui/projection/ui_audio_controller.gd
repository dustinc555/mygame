extends Node
class_name UIAudioController

## Runtime-only observer of controls under the injected bootstrap root.
const SERVICE_ID := &"ui_audio"
const Settings := preload("res://features/ui/resources/ui_audio_settings.gd")
const SoundCue := preload("res://features/audio/resources/game_sound_cue.gd")

signal cue_played(cue_id: StringName, path: String)

@export var settings: Settings = preload("res://features/ui/resources/ui_audio_settings.tres")

var _root: WeakRef
var _tree: SceneTree
var _bindings: Dictionary = {}
var _generation := 0
var _rng := RandomNumberGenerator.new()
var _last_paths: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []


func initialize(context: BootstrapContext) -> void:
	_detach()
	_root = weakref(context.root_scene) if context != null and is_instance_valid(context.root_scene) else null
	_rng.randomize()
	_attach()


func _enter_tree() -> void:
	_attach()


func _exit_tree() -> void:
	_detach()


func _attach() -> void:
	if Engine.is_editor_hint() or not is_inside_tree() or _root == null or _tree != null:
		return
	var root := _root.get_ref() as Node
	if root == null or not root.is_inside_tree():
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	_tree = get_tree()
	_tree.node_added.connect(_bind)
	_tree.node_removed.connect(_on_node_removed)
	_scan(root)


func _detach() -> void:
	_generation += 1
	if is_instance_valid(_tree):
		_tree.node_added.disconnect(_bind)
		_tree.node_removed.disconnect(_on_node_removed)
	_tree = null
	for id: int in _bindings.keys():
		_unbind(id)
	for voice in _voices:
		voice.stop()
		voice.queue_free()
	_voices.clear()
	_last_paths.clear()


func _scan(node: Node) -> void:
	_bind(node)
	for child in node.get_children(true):
		_scan(child)


func _in_scope(node: Node) -> bool:
	var root := _root.get_ref() as Node if _root != null else null
	return root != null and is_instance_valid(node) and node.is_inside_tree() and (node == root or root.is_ancestor_of(node))


func _bind(node: Node) -> void:
	if not (node is BaseButton or node is PopupMenu or node is TabBar):
		return
	if not _in_scope(node) or _bindings.has(node.get_instance_id()):
		return
	var id := node.get_instance_id()
	_bindings[id] = {"node": weakref(node), "connections": [], "accepted_input": false, "popup_open": false}
	if node is BaseButton:
		_connect_node(node, &"gui_input", _on_button_input.bind(id))
		_connect_node(node, &"pressed", _on_pressed.bind(id))
	elif node is PopupMenu:
		# OptionButton's internal popup is observed here, not item_selected too.
		_connect_node(node, &"about_to_popup", _on_popup_opened.bind(id))
		_connect_node(node, &"popup_hide", _on_popup_hidden.bind(id))
		_connect_node(node, &"index_pressed", _on_popup_choice.bind(id))
		_bindings[id].popup_open = node.visible and _eligible(node)
	elif node is TabBar:
		_connect_node(node, &"tab_clicked", _on_tab_clicked.bind(id))


func _on_popup_opened(id: int) -> void:
	_bindings[id].popup_open = _eligible(_bindings[id].node.get_ref())


func _on_popup_hidden(id: int) -> void:
	# PopupMenu hides before index_pressed. Keep the opening eligibility for
	# that synchronous selection, then clear it even when the user cancelled.
	_clear_popup.call_deferred(id, _generation)


func _clear_popup(id: int, generation: int) -> void:
	if generation != _generation or not _bindings.has(id):
		return
	var popup := _bindings[id].node.get_ref() as PopupMenu
	_bindings[id].popup_open = popup != null and popup.visible and _eligible(popup)


func _on_popup_choice(index: int, id: int) -> void:
	var entry: Dictionary = _bindings[id]
	var popup := entry.node.get_ref() as PopupMenu
	if popup == null or not entry.popup_open or not _eligible(popup):
		return
	if index < 0 or index >= popup.item_count or popup.is_item_disabled(index) or popup.is_item_separator(index):
		return
	if not popup.get_item_submenu(index).is_empty():
		return
	entry.popup_open = popup.visible
	_play(settings.click if settings != null else null)


func _on_tab_clicked(index: int, id: int) -> void:
	var tabs := _bindings[id].node.get_ref() as TabBar
	if tabs == null or not _eligible(tabs) or index < 0 or index >= tabs.tab_count:
		return
	if tabs.is_tab_disabled(index) or tabs.is_tab_hidden(index):
		return
	_play(settings.click if settings != null else null)


func _connect_node(node: Node, signal_name: StringName, callback: Callable) -> void:
	node.connect(signal_name, callback)
	_bindings[node.get_instance_id()].connections.append([signal_name, callback])


func _unbind(id: int) -> void:
	var entry: Dictionary = _bindings.get(id, {})
	if entry.is_empty():
		return
	var node: Node = entry.node.get_ref()
	if is_instance_valid(node):
		for connection: Array in entry.connections:
			if node.is_connected(connection[0], connection[1]):
				node.disconnect(connection[0], connection[1])
	_bindings.erase(id)


func _on_node_removed(node: Node) -> void:
	if _bindings.has(node.get_instance_id()):
		# Finish an accepted press whose existing handler removes its own control.
		_forget_if_outside.call_deferred(node.get_instance_id(), _generation)


func _forget_if_outside(id: int, generation: int) -> void:
	if generation != _generation or not _bindings.has(id):
		return
	if not _in_scope(_bindings[id].node.get_ref()):
		_unbind(id)


func _eligible(node: Node) -> bool:
	if not _in_scope(node) or node.is_queued_for_deletion() or not node.can_process():
		return false
	if node is CanvasItem and not node.is_visible_in_tree():
		return false
	if node is BaseButton and node.disabled:
		return false
	var ancestor: Node = node
	var root := _root.get_ref() as Node
	while ancestor != null:
		if ancestor.get_meta(&"ui_audio_disabled", false):
			return false
		if ancestor == root:
			break
		ancestor = ancestor.get_parent()
	return true


func _on_button_input(event: InputEvent, id: int) -> void:
	var button := _bindings[id].node.get_ref() as BaseButton
	var activates := false
	if event is InputEventMouseButton:
		var mask: int = 1 << (event.button_index - 1)
		activates = (mask & button.button_mask) != 0 and Rect2(Vector2.ZERO, button.size).has_point(event.position)
		activates = activates and event.pressed == (button.action_mode == BaseButton.ACTION_MODE_BUTTON_PRESS)
	elif event.is_action(&"ui_accept") and not event.is_echo():
		activates = event.is_pressed() == (button.action_mode == BaseButton.ACTION_MODE_BUTTON_PRESS)
	_bindings[id].accepted_input = activates and _eligible(button)
	_clear_input.call_deferred(id, _generation)


func _clear_input(id: int, generation: int) -> void:
	if generation == _generation and _bindings.has(id):
		_bindings[id].accepted_input = false


func _on_pressed(id: int) -> void:
	var entry: Dictionary = _bindings.get(id, {})
	if entry.is_empty():
		return
	var button := entry.node.get_ref() as BaseButton
	var accepted: bool = entry.accepted_input
	entry.accepted_input = false
	if settings == null or button == null or (not accepted and not _eligible(button)):
		return
	_play(settings.menu_close if button.get_meta(&"ui_audio_action", &"click") == &"close" else settings.click)


## Called only after merchant settlement, not from the Trade button observer.
func play_trade(net_silver: int) -> void:
	if settings != null:
		_play(settings.trade_money if net_silver != 0 else settings.trade_barter)


func _play(cue: SoundCue) -> void:
	if settings == null or not settings.enabled or cue == null or not is_inside_tree():
		return
	var path := cue.choose_path(_last_paths.get(cue.cue_id, ""), _rng)
	var stream := cue.get_stream(path)
	if stream == null:
		return
	var voice := _take_voice()
	voice.stop()
	voice.stream = stream
	voice.volume_db = settings.volume_db + cue.volume_db
	voice.pitch_scale = cue.choose_pitch(_rng)
	voice.play()
	_last_paths[cue.cue_id] = path
	cue_played.emit(cue.cue_id, path)


func _take_voice() -> AudioStreamPlayer:
	var budget := clampi(settings.polyphony, 1, 8)
	while _voices.size() > budget:
		var excess: AudioStreamPlayer = _voices.pop_front()
		excess.stop()
		excess.queue_free()
	var voice: AudioStreamPlayer
	for candidate in _voices:
		if not candidate.playing:
			voice = candidate
			break
	if voice != null:
		_voices.erase(voice)
	elif _voices.size() < budget:
		voice = AudioStreamPlayer.new()
		voice.max_polyphony = 1
		add_child(voice)
	else:
		voice = _voices.pop_front()
	_voices.append(voice)
	return voice
