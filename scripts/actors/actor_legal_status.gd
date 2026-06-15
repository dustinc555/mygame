extends RefCounted

## Typed per-actor law / jurisprudence state.
##
## Replaces the loose "law_*" node-meta keys that used to be scattered across the
## law-order controller, settlement jail, world buildings, and UI. Owned by
## WorldActor; written by the law-order subsystem and read by combat protection +
## the details UI.
##
## Physical containment ("am I locked in a cage right now") is deliberately NOT
## here -- that lives on CustodyCapability. This object is purely the *legal*
## standing of an actor, so a caged wild beast can have containment with no legal
## status while a criminal humanoid has both.
class_name ActorLegalStatus

# Prisoner binding: set when admitted to a jail, cleared on release.
var is_prisoner := false
var jail_id := ""
var cell_id := ""

# Warrant / sentence display, re-derived each tick from the controller records.
var warrant_summary := ""
var status_label := ""
var status_kind := ""  # "jailed" | "caught" | ""
var sentence_summary := ""

# Active-crime markers, owned by the building currently witnessing the crime.
var active_crime_label := ""
var active_crime_kind := ""
var active_crime_source_id := 0


func clear_prisoner() -> void:
	is_prisoner = false
	jail_id = ""
	cell_id = ""


func clear_warrant_display() -> void:
	warrant_summary = ""
	status_label = ""
	status_kind = ""
	sentence_summary = ""


func clear_active_crime() -> void:
	active_crime_label = ""
	active_crime_kind = ""
	active_crime_source_id = 0


func is_empty() -> bool:
	return not is_prisoner \
		and warrant_summary.is_empty() \
		and status_label.is_empty() \
		and sentence_summary.is_empty() \
		and active_crime_label.is_empty()
