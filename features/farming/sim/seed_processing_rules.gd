extends RefCounted

class_name SeedProcessingRules


static func process_counts(produce_count: int, requested_produce: int, seeds_per_produce: int, free_seed_capacity: int) -> Dictionary:
	var yield_per_item := maxi(1, seeds_per_produce)
	var processable := mini(maxi(0, produce_count), maxi(0, requested_produce))
	processable = mini(processable, maxi(0, free_seed_capacity) / yield_per_item)
	return {
		"produce_used": processable,
		"produce_remaining": maxi(0, produce_count - processable),
		"seeds": processable * yield_per_item,
	}
