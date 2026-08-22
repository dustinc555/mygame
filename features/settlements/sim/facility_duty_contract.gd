extends RefCounted

class_name FacilityDutyContract

const ACTIVE_DUTY_META := &"active_facility_duty"


static func begin(actor: Node, facility_id: String) -> void:
	if actor != null and not facility_id.strip_edges().is_empty():
		actor.set_meta(ACTIVE_DUTY_META, facility_id.strip_edges())


static func end(actor: Node, facility_id: String) -> void:
	if actor != null and str(actor.get_meta(ACTIVE_DUTY_META, "")) == facility_id.strip_edges():
		actor.remove_meta(ACTIVE_DUTY_META)


static func is_active(actor: Node) -> bool:
	return actor != null and not str(actor.get_meta(ACTIVE_DUTY_META, "")).is_empty()
