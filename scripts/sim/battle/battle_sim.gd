extends RefCounted

class_name BattleSim

const DEFAULT_ROUND_COUNT := 3
const MIN_POWER := 0.001
const MEMBER_POWER_EXPONENT := 1.35
const MAX_ENGAGEMENT_GROUP_SIZE := 4
const ENGAGEMENT_GROUP_STRATEGY := "deterministic_sorted_bounded"

const LIFE_STATE_ALIVE := 0
const LIFE_STATE_ASLEEP := 1
const LIFE_STATE_UNCONSCIOUS := 2
const LIFE_STATE_DEAD := 3
const LIFE_STATE_RECOVERY_COMA := 4
const LIFE_STATE_DYING := 5

const COMBAT_STANCE_AGGRESSIVE := 0
const COMBAT_STANCE_DEFENSIVE := 1
const COMBAT_STANCE_PASSIVE := 2

const ATTRIBUTE_STRENGTH := "attribute.strength"
const ATTRIBUTE_PERCEPTION := "attribute.perception"
const ATTRIBUTE_DEXTERITY := "attribute.dexterity"
const ATTRIBUTE_TOUGHNESS := "attribute.toughness"
const ATTRIBUTE_ENDURANCE := "attribute.endurance"
const COMBAT_SWORDS_ONE_HANDED := "combat.swords_one_handed"
const COMBAT_AXES_ONE_HANDED := "combat.axes_one_handed"
const COMBAT_DAGGERS := "combat.daggers"
const COMBAT_UNARMED := "combat.unarmed"
const COMBAT_SHIELDS := "combat.shields"


static func resolve_encounter(encounter_record: Dictionary, squad_a_record: Dictionary, squad_b_record: Dictionary, config: Dictionary) -> Dictionary:
	var squad_a_id := str(squad_a_record.get("squad_id", _squad_id_from_encounter(encounter_record, 0))).strip_edges()
	var squad_b_id := str(squad_b_record.get("squad_id", _squad_id_from_encounter(encounter_record, 1))).strip_edges()
	var rounds := maxi(1, int(config.get("rounds", DEFAULT_ROUND_COUNT)))
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_from_config(encounter_record, config)
	var profile_a := _combat_profile(squad_a_record)
	var profile_b := _combat_profile(squad_b_record)
	var power_a := _effective_power(profile_a, squad_a_record, encounter_record, rng)
	var power_b := _effective_power(profile_b, squad_b_record, encounter_record, rng)
	profile_a["effective_power"] = power_a
	profile_b["effective_power"] = power_b
	var total_power := maxf(power_a + power_b, MIN_POWER)
	var outcome := _outcome(power_a, power_b)
	var winner_id := ""
	var loser_id := ""
	if outcome == "squad_a_won":
		winner_id = squad_a_id
		loser_id = squad_b_id
	elif outcome == "squad_b_won":
		winner_id = squad_b_id
		loser_id = squad_a_id
	var casualty_count_a := _casualty_count_for(profile_a, squad_a_record, power_b / total_power, outcome == "squad_b_won", outcome == "draw", rng)
	var casualty_count_b := _casualty_count_for(profile_b, squad_b_record, power_a / total_power, outcome == "squad_a_won", outcome == "draw", rng)
	var member_casualties_a := _member_casualties_for(profile_a, casualty_count_a, outcome == "squad_b_won", rng)
	var member_casualties_b := _member_casualties_for(profile_b, casualty_count_b, outcome == "squad_a_won", rng)
	var casualties_a := member_casualties_a.size() if _profile_uses_members(profile_a) else casualty_count_a
	var casualties_b := member_casualties_b.size() if _profile_uses_members(profile_b) else casualty_count_b
	var morale_delta_a := _morale_delta(outcome, "squad_a_won", casualties_a, squad_a_record, profile_a)
	var morale_delta_b := _morale_delta(outcome, "squad_b_won", casualties_b, squad_b_record, profile_b)
	var supplies_delta_a := _supplies_delta(casualties_a, rounds, squad_a_record, profile_a)
	var supplies_delta_b := _supplies_delta(casualties_b, rounds, squad_b_record, profile_b)
	var encounter_id := _combat_beat_encounter_id(encounter_record, config)
	var engagement_groups := _engagement_groups(profile_a, profile_b, encounter_id, squad_a_id, squad_b_id)
	var beats := _combat_beats(profile_a, profile_b, power_a, power_b, rounds, int(config.get("current_tick", 0)), encounter_id, engagement_groups, rng)
	return {
		"outcome": outcome,
		"winner_squad_id": winner_id,
		"loser_squad_id": loser_id,
		"rounds": rounds,
		"casualties": {
			squad_a_id: casualties_a,
			squad_b_id: casualties_b,
		},
		"member_casualties": {
			squad_a_id: member_casualties_a,
			squad_b_id: member_casualties_b,
		},
		"morale_delta": {
			squad_a_id: morale_delta_a,
			squad_b_id: morale_delta_b,
		},
		"supplies_delta": {
			squad_a_id: supplies_delta_a,
			squad_b_id: supplies_delta_b,
		},
		"beats": beats,
		"summary": _summary(outcome, squad_a_id, squad_b_id, winner_id, loser_id, rounds),
		"final_outcome_reason": _outcome_reason(power_a, power_b, profile_a, profile_b),
		"power": {
			squad_a_id: power_a,
			squad_b_id: power_b,
		},
		"combat_profile": {
			squad_a_id: profile_a,
			squad_b_id: profile_b,
		},
		"engagement_groups": engagement_groups,
		"engagement_grouping": _engagement_grouping_summary(profile_a, profile_b, engagement_groups),
	}


static func _combat_profile(record: Dictionary) -> Dictionary:
	var squad_id := str(record.get("squad_id", "")).strip_edges()
	var member_records := _dictionary_array(record.get("member_records", []))
	var member_profiles: Array[Dictionary] = []
	var participants: Array[Dictionary] = []
	for member_record in member_records:
		var member_profile := _member_profile(member_record, squad_id)
		if str(member_profile.get("member_id", "")).is_empty():
			continue
		member_profiles.append(member_profile)
		if bool(member_profile.get("can_participate", false)):
			participants.append(member_profile)
	if not member_profiles.is_empty():
		return _member_combat_profile(record, member_profiles, participants)
	return _fallback_combat_profile(record)


static func _member_combat_profile(record: Dictionary, member_profiles: Array[Dictionary], participants: Array[Dictionary]) -> Dictionary:
	var base_power := 0.0
	var offense := 0.0
	var defense := 0.0
	for member_profile in participants:
		base_power += float(member_profile.get("power", 0.0))
		offense += float(member_profile.get("offense", 0.0))
		defense += float(member_profile.get("defense", 0.0))
	return {
		"squad_id": str(record.get("squad_id", "")).strip_edges(),
		"source": "members",
		"member_records_used": true,
		"member_records_are_canonical": bool(record.get("member_records_are_canonical", false)),
		"member_record_count": member_profiles.size(),
		"member_count": member_profiles.size(),
		"participant_count": participants.size(),
		"excluded_member_count": maxi(0, member_profiles.size() - participants.size()),
		"base_power": base_power,
		"average_offense": offense / maxf(float(participants.size()), 1.0),
		"average_defense": defense / maxf(float(participants.size()), 1.0),
		"member_profiles": member_profiles,
		"participants": participants,
	}


static func _fallback_combat_profile(record: Dictionary) -> Dictionary:
	var members := maxi(0, int(record.get("member_count", 0)))
	return {
		"squad_id": str(record.get("squad_id", "")).strip_edges(),
		"source": "squad_fallback",
		"member_records_used": false,
		"member_records_are_canonical": false,
		"member_record_count": 0,
		"member_count": members,
		"participant_count": members,
		"excluded_member_count": 0,
		"base_power": _fallback_base_power(record),
		"average_offense": 0.0,
		"average_defense": 0.0,
		"member_profiles": [],
		"participants": [],
	}


static func _member_profile(record: Dictionary, squad_id: String) -> Dictionary:
	var skill_levels: Dictionary = record.get("skill_levels", {}) if record.get("skill_levels", {}) is Dictionary else {}
	var best_weapon_skill := maxf(
		maxf(_skill_level(skill_levels, COMBAT_SWORDS_ONE_HANDED), _skill_level(skill_levels, COMBAT_AXES_ONE_HANDED)),
		maxf(_skill_level(skill_levels, COMBAT_DAGGERS), _skill_level(skill_levels, COMBAT_UNARMED))
	)
	var shields := _skill_level(skill_levels, COMBAT_SHIELDS)
	var strength := _skill_level(skill_levels, ATTRIBUTE_STRENGTH)
	var perception := _skill_level(skill_levels, ATTRIBUTE_PERCEPTION)
	var dexterity := _skill_level(skill_levels, ATTRIBUTE_DEXTERITY)
	var toughness := _skill_level(skill_levels, ATTRIBUTE_TOUGHNESS)
	var endurance := _skill_level(skill_levels, ATTRIBUTE_ENDURANCE)
	var offense := 1.0 + best_weapon_skill * 1.2 + strength * 0.7 + dexterity * 0.55 + perception * 0.35
	var defense := 1.0 + toughness * 0.75 + endurance * 0.55 + dexterity * 0.35 + shields * 0.45
	offense += maxf(_record_combat_stat(record, "attack_damage", "base_attack_damage"), 0.0) * 0.08
	defense *= _chance_factor(_record_combat_stat(record, "dodge_chance", "base_dodge_chance"), 0.35)
	defense *= _chance_factor(_record_combat_stat(record, "block_chance", "base_block_chance"), 0.45)
	var life_state := _life_state(record.get("life_state", LIFE_STATE_ALIVE))
	var stance := _combat_stance(record.get("combat_stance", COMBAT_STANCE_DEFENSIVE))
	var initiative_factor := 1.0
	var survival_factor := 1.0
	match stance:
		COMBAT_STANCE_AGGRESSIVE:
			offense *= 1.08
			defense *= 0.96
			initiative_factor = 1.08
		COMBAT_STANCE_DEFENSIVE:
			offense *= 0.96
			defense *= 1.08
			survival_factor = 1.1
		COMBAT_STANCE_PASSIVE:
			offense *= 0.65
			initiative_factor = 0.65
	var condition := _condition_factor(record)
	var can_participate := _life_state_can_participate(life_state) and _vitals_allow_participation(record)
	var raw_power := (offense * 0.58 + defense * 0.42) * condition * initiative_factor
	var power := pow(maxf(raw_power, 1.0), MEMBER_POWER_EXPONENT) if can_participate else 0.0
	return {
		"member_id": _member_id(record),
		"actor_id": str(record.get("actor_id", "")).strip_edges(),
		"stable_id": str(record.get("stable_id", "")).strip_edges(),
		"member_name": str(record.get("member_name", record.get("actor_id", ""))).strip_edges(),
		"squad_id": squad_id,
		"faction_id": str(record.get("faction_id", "")).strip_edges(),
		"life_state": life_state,
		"combat_stance": stance,
		"can_participate": can_participate,
		"condition": condition,
		"best_weapon_skill": best_weapon_skill,
		"shield_skill": shields,
		"offense": offense,
		"defense": defense,
		"survival_score": maxf(defense * condition * survival_factor, 0.1),
		"power": power,
	}


static func _effective_power(profile: Dictionary, record: Dictionary, encounter_record: Dictionary, rng: RandomNumberGenerator) -> float:
	var base_power := maxf(float(profile.get("base_power", 0.0)), 0.0)
	if base_power <= 0.0:
		return 0.0
	var morale_factor := _scale_factor(float(record.get("morale", 1.0)), 0.25, 1.25)
	var supplies_factor := _scale_factor(float(record.get("supplies", 1.0)), 0.25, 1.1)
	var objective_modifier := _objective_modifier(record, encounter_record)
	var variation := rng.randf_range(0.92, 1.08)
	return base_power * morale_factor * supplies_factor * objective_modifier * variation


static func _record_combat_stat(record: Dictionary, stat_name: String, base_field: String) -> float:
	var effective_field := "effective_%s" % stat_name
	if record.has(effective_field):
		return float(record.get(effective_field, 0.0))
	return float(record.get(base_field, 0.0))


static func _fallback_base_power(record: Dictionary) -> float:
	var member_count := maxf(float(record.get("member_count", 0)), 0.0)
	if member_count <= 0.0:
		return 0.0
	var strength := maxf(float(record.get("strength", 0.0)), member_count)
	var strength_factor := maxf(strength / member_count, 1.0)
	return member_count * strength_factor


static func _scale_factor(value: float, minimum: float, maximum: float) -> float:
	var normalized := value if value <= 1.5 else value / 100.0
	return clampf(normalized, minimum, maximum)


static func _objective_modifier(record: Dictionary, encounter_record: Dictionary) -> float:
	var squad_id := str(record.get("squad_id", ""))
	var modifier := 1.0
	if str(encounter_record.get("initiator_squad_id", "")) == squad_id:
		modifier += 0.08
	match str(record.get("objective_id", "")):
		"raid", "patrol_for_raid_targets", "force_encounter_debug", "debug_force_encounter":
			modifier += 0.04
	return modifier


static func _outcome(power_a: float, power_b: float) -> String:
	var total_power := maxf(power_a + power_b, MIN_POWER)
	var margin := absf(power_a - power_b) / total_power
	if margin < 0.08:
		return "draw"
	return "squad_a_won" if power_a > power_b else "squad_b_won"


static func _casualty_count_for(profile: Dictionary, record: Dictionary, opposing_power_share: float, lost: bool, draw: bool, rng: RandomNumberGenerator) -> int:
	var members := maxi(0, int(profile.get("participant_count", record.get("member_count", 0))))
	if members <= 0:
		return 0
	var base_rate := 0.16 + opposing_power_share * 0.28
	if lost:
		base_rate += 0.28
	if draw:
		base_rate += 0.08
	var casualty_rate := clampf(base_rate + rng.randf_range(-0.08, 0.08), 0.0, 1.0)
	return clampi(int(round(float(members) * casualty_rate)), 0, members)


static func _member_casualties_for(profile: Dictionary, casualty_count: int, lost: bool, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not _profile_uses_members(profile):
		return result
	var participants := _dictionary_array(profile.get("participants", []))
	if participants.is_empty() or casualty_count <= 0:
		return result
	var candidates: Array[Dictionary] = []
	for member_profile in participants:
		var survival_score := maxf(float(member_profile.get("survival_score", 1.0)), 0.1)
		var risk := rng.randf_range(0.0, 1.0) + 1.0 / survival_score
		if lost:
			risk += 0.15
		candidates.append({"member": member_profile, "risk": risk})
	candidates.sort_custom(func(first: Dictionary, second: Dictionary) -> bool: return float(first.get("risk", 0.0)) > float(second.get("risk", 0.0)))
	for index in range(mini(casualty_count, candidates.size())):
		var member: Dictionary = candidates[index].get("member", {})
		result.append({
			"member_id": str(member.get("member_id", "")),
			"actor_id": str(member.get("actor_id", "")),
			"stable_id": str(member.get("stable_id", "")),
			"member_name": str(member.get("member_name", "")),
			"squad_id": str(profile.get("squad_id", "")),
			"casualty_state": "dying",
			"life_state": LIFE_STATE_DYING,
			"fatal": false,
			"power_before": float(member.get("power", 0.0)),
		})
	return result


static func _morale_delta(outcome: String, winning_outcome: String, casualties: int, record: Dictionary, profile: Dictionary) -> float:
	var members := maxf(float(profile.get("participant_count", record.get("member_count", 0))), 1.0)
	var casualty_pressure := float(casualties) / members
	if outcome == "draw":
		return -0.12 - casualty_pressure * 0.25
	if outcome == winning_outcome:
		return 0.08 - casualty_pressure * 0.18
	return -0.22 - casualty_pressure * 0.35


static func _supplies_delta(casualties: int, rounds: int, record: Dictionary, profile: Dictionary) -> float:
	var members := maxf(float(profile.get("participant_count", record.get("member_count", 0))), 0.0)
	return -minf(float(rounds) * 0.35 + members * 0.08 + float(casualties) * 0.15, float(record.get("supplies", 0.0)))


static func _engagement_groups(profile_a: Dictionary, profile_b: Dictionary, encounter_id: String, squad_a_id: String, squad_b_id: String) -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	var group_encounter_id := encounter_id.strip_edges()
	if group_encounter_id.is_empty():
		group_encounter_id = "encounter:untracked"
	var side_a_participants := _sorted_engagement_participants(profile_a)
	var side_b_participants := _sorted_engagement_participants(profile_b)
	if side_a_participants.is_empty() and side_b_participants.is_empty():
		groups.append(_squad_fallback_engagement_group(group_encounter_id, squad_a_id, squad_b_id))
		return groups
	var paired_count := mini(side_a_participants.size(), side_b_participants.size())
	for index in range(paired_count):
		var group := _engagement_group_record(group_encounter_id, groups.size() + 1, squad_a_id, squad_b_id, "paired")
		_add_group_member(group, "a", side_a_participants[index], false, false)
		_add_group_member(group, "b", side_b_participants[index], false, false)
		groups.append(group)
	var next_a_index := _assign_support_members(groups, side_a_participants, paired_count, "a")
	var next_b_index := _assign_support_members(groups, side_b_participants, paired_count, "b")
	_append_reserve_groups(groups, side_a_participants, next_a_index, "a", group_encounter_id, squad_a_id, squad_b_id)
	_append_reserve_groups(groups, side_b_participants, next_b_index, "b", group_encounter_id, squad_a_id, squad_b_id)
	if groups.is_empty():
		groups.append(_squad_fallback_engagement_group(group_encounter_id, squad_a_id, squad_b_id))
	return groups


static func _combat_beats(profile_a: Dictionary, profile_b: Dictionary, power_a: float, power_b: float, rounds: int, current_tick: int, encounter_id: String, engagement_groups: Array[Dictionary], rng: RandomNumberGenerator) -> Array[Dictionary]:
	var beats: Array[Dictionary] = []
	var beat_encounter_id := encounter_id.strip_edges()
	if beat_encounter_id.is_empty():
		beat_encounter_id = "encounter:untracked"
	var squad_a_id := str(profile_a.get("squad_id", ""))
	var squad_b_id := str(profile_b.get("squad_id", ""))
	for round_index in range(1, rounds + 1):
		var beat_index := beats.size() + 1
		var a_advantage := power_a - power_b + rng.randf_range(-4.0, 4.0)
		var attacker_profile := profile_a if a_advantage >= 0.0 else profile_b
		var defender_profile := profile_b if attacker_profile == profile_a else profile_a
		var attacker_squad_id := str(attacker_profile.get("squad_id", ""))
		var defender_squad_id := squad_b_id if attacker_squad_id == squad_a_id else squad_a_id
		if not str(defender_profile.get("squad_id", "")).is_empty():
			defender_squad_id = str(defender_profile.get("squad_id", ""))
		var engagement_group := _pick_beat_group(engagement_groups, attacker_squad_id, defender_squad_id, round_index)
		var engagement_group_id := str(engagement_group.get("engagement_group_id", _engagement_group_id(beat_encounter_id, 1))).strip_edges()
		var attacker_member := _pick_beat_member_for_group(attacker_profile, engagement_group, attacker_squad_id, rng)
		var defender_member := _pick_beat_member_for_group(defender_profile, engagement_group, defender_squad_id, rng)
		var attacker_member_id := str(attacker_member.get("member_id", "")).strip_edges()
		var defender_member_id := str(defender_member.get("member_id", "")).strip_edges()
		var attacker_id := attacker_member_id if not attacker_member_id.is_empty() else attacker_squad_id
		var defender_id := defender_member_id if not defender_member_id.is_empty() else defender_squad_id
		var attacker_name := str(attacker_member.get("member_name", attacker_squad_id))
		var defender_name := str(defender_member.get("member_name", defender_squad_id))
		var damage := maxf(absf(a_advantage) / float(rounds), 0.1)
		beats.append({
			"beat_id": _combat_beat_id(beat_encounter_id, beat_index),
			"beat_index": beat_index,
			"encounter_id": beat_encounter_id,
			"engagement_group_id": engagement_group_id,
			"tick": current_tick,
			"presentation_tick": current_tick + beat_index - 1,
			"round": round_index,
			"attacker_squad_id": attacker_squad_id,
			"defender_squad_id": defender_squad_id,
			"attacker_member_id": attacker_member_id,
			"defender_member_id": defender_member_id,
			"attacker_actor_id": str(attacker_member.get("actor_id", "")).strip_edges(),
			"defender_actor_id": str(defender_member.get("actor_id", "")).strip_edges(),
			"attacker_stable_id": str(attacker_member.get("stable_id", "")).strip_edges(),
			"defender_stable_id": str(defender_member.get("stable_id", "")).strip_edges(),
			"attacker_id": attacker_id,
			"defender_id": defender_id,
			"attacker_name": attacker_name,
			"defender_name": defender_name,
			"action": "attack",
			"result": "hit",
			"damage": damage,
			"importance": "high" if round_index == rounds else "normal",
			"summary": _beat_summary(attacker_name, attacker_squad_id, defender_name, defender_squad_id, damage),
		})
	return beats


static func _engagement_grouping_summary(profile_a: Dictionary, profile_b: Dictionary, engagement_groups: Array[Dictionary]) -> Dictionary:
	var side_a_participants := _sorted_engagement_participants(profile_a)
	var side_b_participants := _sorted_engagement_participants(profile_b)
	return {
		"strategy": ENGAGEMENT_GROUP_STRATEGY,
		"complexity": "O(N log N) sort + O(N) assignment",
		"max_group_size": MAX_ENGAGEMENT_GROUP_SIZE,
		"group_count": engagement_groups.size(),
		"side_a_participant_count": side_a_participants.size(),
		"side_b_participant_count": side_b_participants.size(),
		"excluded_member_count": int(profile_a.get("excluded_member_count", 0)) + int(profile_b.get("excluded_member_count", 0)),
	}


static func _sorted_engagement_participants(profile: Dictionary) -> Array[Dictionary]:
	var participants := _dictionary_array(profile.get("participants", []))
	participants.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		var first_score := _engagement_sort_score(first)
		var second_score := _engagement_sort_score(second)
		if not is_equal_approx(first_score, second_score):
			return first_score > second_score
		return _member_group_id(first) < _member_group_id(second)
	)
	return participants


static func _engagement_sort_score(member_profile: Dictionary) -> float:
	return float(member_profile.get("power", 0.0))


static func _member_group_id(member_profile: Dictionary) -> String:
	for key in ["member_id", "actor_id", "stable_id"]:
		var value := str(member_profile.get(key, "")).strip_edges()
		if not value.is_empty():
			return value
	return ""


static func _squad_fallback_engagement_group(encounter_id: String, squad_a_id: String, squad_b_id: String) -> Dictionary:
	var group := _engagement_group_record(encounter_id, 1, squad_a_id, squad_b_id, "squad_fallback")
	group["side_a_primary_id"] = squad_a_id
	group["side_b_primary_id"] = squad_b_id
	group["uses_squad_fallback"] = true
	return group


static func _engagement_group_record(encounter_id: String, group_index: int, squad_a_id: String, squad_b_id: String, group_role: String) -> Dictionary:
	return {
		"engagement_group_id": _engagement_group_id(encounter_id, group_index),
		"encounter_id": encounter_id,
		"group_index": group_index,
		"group_role": group_role,
		"strategy": ENGAGEMENT_GROUP_STRATEGY,
		"max_group_size": MAX_ENGAGEMENT_GROUP_SIZE,
		"side_a_squad_id": squad_a_id,
		"side_b_squad_id": squad_b_id,
		"side_a_primary_id": "",
		"side_b_primary_id": "",
		"side_a_member_ids": [],
		"side_b_member_ids": [],
		"support_member_ids": [],
		"reserve_member_ids": [],
		"uses_squad_fallback": false,
	}


static func _engagement_group_id(encounter_id: String, group_index: int) -> String:
	return "%s:group:%03d" % [encounter_id, group_index]


static func _add_group_member(group: Dictionary, side: String, member_profile: Dictionary, support: bool, reserve: bool) -> void:
	var member_id := _member_group_id(member_profile)
	if member_id.is_empty():
		return
	var side_key := "side_a_member_ids" if side == "a" else "side_b_member_ids"
	var primary_key := "side_a_primary_id" if side == "a" else "side_b_primary_id"
	var side_member_ids := _string_array(group.get(side_key, []))
	if not side_member_ids.has(member_id):
		side_member_ids.append(member_id)
	group[side_key] = side_member_ids
	if str(group.get(primary_key, "")).strip_edges().is_empty():
		group[primary_key] = member_id
	if support:
		_append_unique_string_field(group, "support_member_ids", member_id)
	if reserve:
		_append_unique_string_field(group, "reserve_member_ids", member_id)


static func _assign_support_members(groups: Array[Dictionary], members: Array[Dictionary], start_index: int, side: String) -> int:
	var member_index := start_index
	var group_index := 0
	while member_index < members.size() and group_index < groups.size():
		var group := groups[group_index]
		if _engagement_group_size(group) >= MAX_ENGAGEMENT_GROUP_SIZE:
			group_index += 1
			continue
		_add_group_member(group, side, members[member_index], true, false)
		groups[group_index] = group
		member_index += 1
	return member_index


static func _append_reserve_groups(groups: Array[Dictionary], members: Array[Dictionary], start_index: int, side: String, encounter_id: String, squad_a_id: String, squad_b_id: String) -> void:
	var member_index := start_index
	while member_index < members.size():
		var group := _engagement_group_record(encounter_id, groups.size() + 1, squad_a_id, squad_b_id, "reserve")
		while member_index < members.size() and _engagement_group_size(group) < MAX_ENGAGEMENT_GROUP_SIZE:
			_add_group_member(group, side, members[member_index], false, true)
			member_index += 1
		groups.append(group)


static func _append_unique_string_field(group: Dictionary, field_name: String, value: String) -> void:
	var values := _string_array(group.get(field_name, []))
	if not values.has(value):
		values.append(value)
	group[field_name] = values


static func _engagement_group_size(group: Dictionary) -> int:
	return _string_array(group.get("side_a_member_ids", [])).size() + _string_array(group.get("side_b_member_ids", [])).size()


static func _pick_beat_group(engagement_groups: Array[Dictionary], attacker_squad_id: String, defender_squad_id: String, round_index: int) -> Dictionary:
	if engagement_groups.is_empty():
		return {}
	var matching_groups: Array[Dictionary] = []
	for group in engagement_groups:
		if _group_has_squad_members(group, attacker_squad_id) and _group_has_squad_members(group, defender_squad_id):
			matching_groups.append(group)
	if matching_groups.is_empty():
		return engagement_groups[0]
	return matching_groups[maxi(0, round_index - 1) % matching_groups.size()]


static func _group_has_squad_members(group: Dictionary, squad_id: String) -> bool:
	var trimmed_squad_id := squad_id.strip_edges()
	if trimmed_squad_id.is_empty():
		return false
	if str(group.get("side_a_squad_id", "")).strip_edges() == trimmed_squad_id:
		return not _string_array(group.get("side_a_member_ids", [])).is_empty() or str(group.get("side_a_primary_id", "")).strip_edges() == trimmed_squad_id
	if str(group.get("side_b_squad_id", "")).strip_edges() == trimmed_squad_id:
		return not _string_array(group.get("side_b_member_ids", [])).is_empty() or str(group.get("side_b_primary_id", "")).strip_edges() == trimmed_squad_id
	return false


static func _pick_beat_member_for_group(profile: Dictionary, engagement_group: Dictionary, squad_id: String, rng: RandomNumberGenerator) -> Dictionary:
	var member_ids := _group_member_ids_for_squad(engagement_group, squad_id)
	if member_ids.is_empty():
		return _pick_beat_member(profile, rng)
	return _pick_beat_member_by_ids(profile, member_ids, rng)


static func _group_member_ids_for_squad(group: Dictionary, squad_id: String) -> Array[String]:
	var trimmed_squad_id := squad_id.strip_edges()
	if str(group.get("side_a_squad_id", "")).strip_edges() == trimmed_squad_id:
		return _string_array(group.get("side_a_member_ids", []))
	if str(group.get("side_b_squad_id", "")).strip_edges() == trimmed_squad_id:
		return _string_array(group.get("side_b_member_ids", []))
	return []


static func _pick_beat_member_by_ids(profile: Dictionary, member_ids: Array[String], rng: RandomNumberGenerator) -> Dictionary:
	var allowed_ids := {}
	for member_id in member_ids:
		allowed_ids[member_id] = true
	var candidates: Array[Dictionary] = []
	for member_profile in _dictionary_array(profile.get("participants", [])):
		if allowed_ids.has(_member_group_id(member_profile)):
			candidates.append(member_profile)
	if candidates.is_empty():
		return _pick_beat_member(profile, rng)
	var total_power := 0.0
	for member_profile in candidates:
		total_power += maxf(float(member_profile.get("power", 0.0)), 0.0)
	if total_power <= 0.0:
		return candidates[rng.randi_range(0, candidates.size() - 1)]
	var roll := rng.randf_range(0.0, total_power)
	var cursor := 0.0
	for member_profile in candidates:
		cursor += maxf(float(member_profile.get("power", 0.0)), 0.0)
		if roll <= cursor:
			return member_profile
	return candidates[candidates.size() - 1]


static func _combat_beat_encounter_id(encounter_record: Dictionary, config: Dictionary) -> String:
	var config_id := str(config.get("encounter_id", "")).strip_edges()
	if not config_id.is_empty():
		return config_id
	return str(encounter_record.get("encounter_id", "")).strip_edges()


static func _combat_beat_id(encounter_id: String, beat_index: int) -> String:
	return "%s:beat:%03d" % [encounter_id, beat_index]


static func _pick_beat_member(profile: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var participants := _dictionary_array(profile.get("participants", []))
	if participants.is_empty():
		return {}
	var total_power := 0.0
	for member_profile in participants:
		total_power += maxf(float(member_profile.get("power", 0.0)), 0.0)
	if total_power <= 0.0:
		return participants[rng.randi_range(0, participants.size() - 1)]
	var roll := rng.randf_range(0.0, total_power)
	var cursor := 0.0
	for member_profile in participants:
		cursor += maxf(float(member_profile.get("power", 0.0)), 0.0)
		if roll <= cursor:
			return member_profile
	return participants[participants.size() - 1]


static func _summary(outcome: String, squad_a_id: String, squad_b_id: String, winner_id: String, loser_id: String, rounds: int) -> String:
	if outcome == "draw":
		return "%s and %s fought to a draw after %d rounds." % [squad_a_id, squad_b_id, rounds]
	return "%s defeated %s after %d rounds." % [winner_id, loser_id, rounds]


static func _beat_summary(attacker_name: String, attacker_squad_id: String, defender_name: String, defender_squad_id: String, damage: float) -> String:
	var attacker_label := attacker_name if not attacker_name.is_empty() else attacker_squad_id
	var defender_label := defender_name if not defender_name.is_empty() else defender_squad_id
	return "%s pressured %s for %.1f combat damage." % [attacker_label, defender_label, damage]


static func _outcome_reason(power_a: float, power_b: float, profile_a: Dictionary, profile_b: Dictionary) -> String:
	var total_power := maxf(power_a + power_b, MIN_POWER)
	var margin := absf(power_a - power_b) / total_power
	if margin < 0.08:
		return "Combat power was too close for a decisive result."
	if _profile_uses_members(profile_a) or _profile_uses_members(profile_b):
		return "Resolved from member combat profiles; higher effective member power decided the battle."
	return "Higher effective squad power decided the battle."


static func _profile_uses_members(profile: Dictionary) -> bool:
	return str(profile.get("source", "")) == "members"


static func _dictionary_array(value) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not (value is Array):
		return result
	for entry in value:
		if entry is Dictionary:
			result.append(entry.duplicate(true))
	return result


static func _string_array(value) -> Array[String]:
	var result: Array[String] = []
	if not (value is Array) and not (value is PackedStringArray):
		return result
	for entry in value:
		var text := str(entry).strip_edges()
		if not text.is_empty():
			result.append(text)
	return result


static func _member_id(record: Dictionary) -> String:
	for key in ["actor_id", "stable_id", "member_id"]:
		var value := str(record.get(key, "")).strip_edges()
		if not value.is_empty():
			return value
	return ""


static func _skill_level(skill_levels: Dictionary, skill_id: String) -> float:
	return maxf(float(skill_levels.get(skill_id, 1.0)), 0.0)


static func _condition_factor(record: Dictionary) -> float:
	var condition := 1.0
	var max_hp := float(record.get("max_hp", 0.0))
	if max_hp > 0.0:
		condition = minf(condition, clampf(float(record.get("hp", max_hp)) / max_hp, 0.0, 1.0))
	var max_blood := float(record.get("max_blood", 0.0))
	if max_blood > 0.0:
		condition = minf(condition, clampf(float(record.get("blood", max_blood)) / max_blood, 0.0, 1.0))
	return condition


static func _vitals_allow_participation(record: Dictionary) -> bool:
	var max_hp := float(record.get("max_hp", 0.0))
	if max_hp > 0.0 and float(record.get("hp", max_hp)) <= 0.0:
		return false
	var max_blood := float(record.get("max_blood", 0.0))
	if max_blood > 0.0 and float(record.get("blood", max_blood)) <= 0.0:
		return false
	return true


static func _life_state_can_participate(life_state: int) -> bool:
	return life_state == LIFE_STATE_ALIVE


static func _life_state(value) -> int:
	if value is String:
		match str(value).strip_edges().to_upper():
			"ALIVE":
				return LIFE_STATE_ALIVE
			"ASLEEP":
				return LIFE_STATE_ASLEEP
			"UNCONSCIOUS":
				return LIFE_STATE_UNCONSCIOUS
			"DEAD":
				return LIFE_STATE_DEAD
			"RECOVERY_COMA":
				return LIFE_STATE_RECOVERY_COMA
			"DYING":
				return LIFE_STATE_DYING
	return int(value)


static func _combat_stance(value) -> int:
	if value is String:
		match str(value).strip_edges().to_upper():
			"AGGRESSIVE":
				return COMBAT_STANCE_AGGRESSIVE
			"DEFENSIVE":
				return COMBAT_STANCE_DEFENSIVE
			"PASSIVE":
				return COMBAT_STANCE_PASSIVE
	return int(value)


static func _chance_factor(value, scale: float) -> float:
	var chance := maxf(float(value), 0.0)
	if chance > 1.0:
		chance /= 100.0
	return 1.0 + clampf(chance, 0.0, 1.0) * scale


static func _squad_id_from_encounter(encounter_record: Dictionary, index: int) -> String:
	var squad_ids = encounter_record.get("squad_ids", [])
	if squad_ids is Array and index >= 0 and index < squad_ids.size():
		return str(squad_ids[index])
	return ""


static func _seed_from_config(encounter_record: Dictionary, config: Dictionary) -> int:
	var seed_text := str(config.get("seed", "")).strip_edges()
	if seed_text.is_empty():
		seed_text = "%s|%s" % [str(encounter_record.get("encounter_id", "")), str(encounter_record.get("created_tick", 0))]
	return abs(hash(seed_text))
