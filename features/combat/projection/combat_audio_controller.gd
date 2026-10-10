extends Node
class_name CombatAudioController

const SERVICE_ID := &"combat_audio"
const PROFILE := preload("res://features/combat/resources/combat_item_audio_profile.gd")
const SURFACE = PROFILE.Surface
const KIND = PROFILE.WeaponKind
const SETTINGS := preload("res://features/combat/resources/audio/combat_audio_settings.gd")
const BANK := preload("res://features/combat/resources/audio/combat_sound_bank.gd")
const RECENT_EVENT_LIMIT := 256
@export var settings: SETTINGS = preload("res://features/combat/resources/audio/default_combat_audio_settings.tres")
@export var bank: BANK = preload("res://features/combat/resources/audio/default_combat_sound_bank.tres")

var _context: BootstrapContext
var _source: Node
var _voices: Array[AudioStreamPlayer3D] = []
var _previous_paths: Dictionary = {}
var _recent_events: Dictionary = {}
var _play_serial := 0
var _rng := RandomNumberGenerator.new()


func initialize(context: BootstrapContext) -> void:
	teardown()
	_context = context
	_source = context.get_optional(&"gecs_world")
	if is_instance_valid(_source) and _source.has_signal("combat_audio_event"):
		_source.connect("combat_audio_event", _on_combat_audio_event)
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_process(false)


func teardown() -> void:
	if is_instance_valid(_source) and _source.is_connected("combat_audio_event", _on_combat_audio_event):
		_source.disconnect("combat_audio_event", _on_combat_audio_event)
	_source = null
	_context = null
	for voice in _voices:
		voice.stop()
		voice.free()
	_voices.clear()
	_recent_events.clear()
	_previous_paths.clear()


func _exit_tree() -> void:
	teardown()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		for voice in _voices:
			voice.stop()
			voice.stream = null


func _on_combat_audio_event(event: Dictionary) -> void:
	if not is_inside_tree() or get_tree().paused or not settings.enabled or not is_instance_valid(_source) or _source.is_queued_for_deletion():
		return
	var actor = _source.call("get_actor_by_stable_id", str(event.get("attacker_id", "")))
	if not is_instance_valid(actor) or actor.is_queued_for_deletion() or actor.get_instance_id() != int(event.get("source_instance_id", 0)):
		return
	var key := "%s:%s:%s" % [event.get("source_instance_id", 0), event.get("sequence", 0), event.get("phase", "")]
	if _recent_events.has(key):
		return
	_recent_events[key] = true
	if _recent_events.size() > RECENT_EVENT_LIMIT:
		_recent_events.erase(_recent_events.keys()[0])
	var attacker := snapshot_actor(actor)
	var target: Dictionary = {}
	if event.get("phase", "") == "contact":
		target = snapshot_actor(_source.call("get_actor_by_stable_id", str(event.get("target_id", ""))))
		if target.is_empty():
			return
	for layer in plan_event(event, attacker, target):
		play_cue(layer.cue_id, layer.position, layer.gain_db)


## Voices retain only a stream and captured position, never a disposable actor.
func play_cue(cue_id: StringName, position: Vector3, gain_db := 0.0) -> AudioStreamPlayer3D:
	if not is_inside_tree() or get_tree().paused or not settings.enabled or bank == null:
		return null
	var listener := get_viewport().get_camera_3d()
	var distance := maxf(settings.max_distance_m, 1.0)
	if listener == null or not position.is_finite() or listener.global_position.distance_squared_to(position) > distance * distance:
		return null
	var cue = bank.get_cue(cue_id)
	if cue == null:
		return null
	var path: String = cue.choose_path(str(_previous_paths.get(cue_id, "")), _rng)
	var stream: AudioStream = cue.get_stream(path)
	if stream == null:
		return null
	_previous_paths[cue_id] = path
	var limit := clampi(settings.max_voices, 2, 64)
	while _voices.size() > limit:
		var excess: AudioStreamPlayer3D = _voices.pop_back()
		excess.stop()
		excess.free()
	var player: AudioStreamPlayer3D
	for voice in _voices:
		if not voice.playing:
			player = voice
			break
	if player == null and _voices.size() < limit:
		player = AudioStreamPlayer3D.new()
		add_child(player)
		_voices.append(player)
		player.finished.connect(_on_voice_finished.bind(player))
	if player == null:
		player = _voices[0]
		for voice in _voices:
			if int(voice.get_meta("play_serial", 0)) < int(player.get_meta("play_serial", 0)):
				player = voice
	player.stop()
	player.stream = stream
	player.global_position = position
	player.bus = settings.bus if AudioServer.get_bus_index(settings.bus) >= 0 else &"Master"
	player.max_distance = distance
	player.unit_size = maxf(settings.unit_size_m, 0.1)
	player.volume_db = clampf(settings.volume_db + cue.volume_db + gain_db, -80.0, 6.0)
	player.pitch_scale = cue.choose_pitch(_rng)
	_play_serial += 1
	player.set_meta("play_serial", _play_serial)
	player.set_meta("clip_path", path)
	player.play()
	return player


func _on_voice_finished(player: AudioStreamPlayer3D) -> void:
	player.stream = null

## Pure, value-only sound planning; gameplay damage and defenses remain GECS-owned.
func plan_event(event: Dictionary, attacker: Dictionary, target: Dictionary) -> Array[Dictionary]:
	var layers: Array[Dictionary] = []
	var kind := int(attacker.get("weapon_kind", KIND.NONE))
	var zombie := settings.zombie_race_ids.has(str(attacker.get("race_id", "")))
	var attack_id := str(event.get("attack_id", ""))
	var natural_attack := zombie and attack_id in ["claw", "bite"]
	# The resolved animation owns the strike, even if equipment changed mid-action.
	if natural_attack:
		kind = KIND.NONE
	if event.get("phase", "") == "swing":
		if zombie and not natural_attack:
			layers.append({"cue_id": &"zombie_female" if attacker.get("female", false) else &"zombie_male", "layer": &"voice", "position": event.get("attacker_position", Vector3.ZERO), "gain_db": 0.0})
	elif event.get("phase", "") == "dodge" and event.get("outcome", "") == "dodged":
		# A whoosh reports the opponent's resolved dodge, never an ordinary windup.
		if kind != KIND.NONE or (natural_attack and attack_id == "claw"):
			var swing: StringName = &"swing_blade"
			if kind in [KIND.AXE, KIND.BLUNT, KIND.TOOL]:
				swing = &"swing_heavy"
			layers.append({"cue_id": swing, "layer": &"action", "position": event.get("attacker_position", Vector3.ZERO), "gain_db": 0.0})
	elif event.get("phase", "") == "contact" and event.get("outcome", "") in ["hit", "blocked"]:
		var surface := int(target.get("worn_surface", SURFACE.NONE))
		if surface == SURFACE.NONE:
			surface = int(target.get("body_surface", SURFACE.FLESH))
		var blocked: bool = event.get("outcome", "") == "blocked"
		var shield: bool = event.get("has_shield", false)
		if blocked:
			var guard := int(target.get("shield_guard_surface" if shield else "weapon_guard_surface", SURFACE.NONE))
			if guard != SURFACE.NONE:
				surface = guard
		# No generic unarmed or punch-based contact fallback is approved.
		var cue: StringName = &""
		if surface in [SURFACE.METAL, SURFACE.PLATE]:
			cue = &"impact_metal"
			if (blocked and not shield and not natural_attack
				and int(target.get("weapon_guard_surface", SURFACE.NONE)) in [SURFACE.METAL, SURFACE.PLATE]
				and int(attacker.get("strike_surface", SURFACE.FLESH)) in [SURFACE.METAL, SURFACE.PLATE]):
				cue = &"clash_metal"
		elif surface == SURFACE.CHAINMAIL:
			cue = &"impact_chain"
		elif surface == SURFACE.WOOD:
			cue = &"impact_wood"
		elif surface in [SURFACE.BONE, SURFACE.STONE]:
			return layers
		elif natural_attack and attack_id == "bite" and surface == SURFACE.FLESH:
			cue = &"zombie_bite"
		elif natural_attack and attack_id == "claw":
			cue = &"impact_slash"
		elif kind == KIND.AXE:
			cue = &"impact_axe"
		elif kind in [KIND.BLADE, KIND.POLEARM]:
			cue = &"impact_stab" if settings.stab_attack_ids.has(attack_id) else &"impact_slash"
		if cue == &"":
			return layers
		var gain := clampf(settings.critical_gain_db, 0.0, 3.0) if event.get("critical", false) else 0.0
		layers.append({"cue_id": cue, "layer": &"contact", "position": event.get("target_position", Vector3.ZERO), "gain_db": gain})
	return layers


## Called only on combat edges. Read live equipment now; retain only values.
func snapshot_actor(actor) -> Dictionary:
	if not is_instance_valid(actor) or not actor is Node or actor.is_queued_for_deletion():
		return {}
	var appearance = actor.get("appearance_data")
	var body = actor.call("get_resolved_body_archetype") if actor.has_method("get_resolved_body_archetype") else null
	var race_id := ""
	if appearance is CharacterAppearanceData:
		if appearance.character_race != null:
			race_id = str(appearance.character_race.get("race_id"))
		if body == null:
			body = appearance.body_archetype
	if race_id.is_empty() and body != null and body.has_method("get_race_id"):
		race_id = str(body.get_race_id())
	var body_type := int(actor.call("get_resolved_visual_body_type")) if actor.has_method("get_resolved_visual_body_type") else 0
	if body_type == 0 and appearance is CharacterAppearanceData:
		body_type = appearance.visual_body_type
	var weapon = _item_profile(actor, "weapon")
	var shield = _item_profile(actor, "offhand")
	var worn := SURFACE.NONE
	for slot: String in settings.torso_slots:
		var profile = _item_profile(actor, slot)
		if profile != null and profile.worn_surface != SURFACE.NONE:
			worn = profile.worn_surface
			break
	return {
		"race_id": race_id, "female": body_type == CharacterAppearanceData.VISUAL_BODY_TYPE_FEMALE,
		"body_surface": settings.race_body_surfaces.get(race_id, SURFACE.FLESH), "worn_surface": worn,
		"weapon_kind": weapon.weapon_kind if weapon != null else KIND.NONE,
		"strike_surface": weapon.strike_surface if weapon != null else SURFACE.FLESH,
		"weapon_guard_surface": weapon.guard_surface if weapon != null else SURFACE.NONE,
		"shield_guard_surface": shield.guard_surface if shield != null else SURFACE.NONE,
	}


func _item_profile(actor: Node, slot: String):
	if not actor.has_method("get_equipped_item"):
		return null
	var item = actor.call("get_equipped_item", slot)
	return item.combat_audio if item is ItemDefinition else null
