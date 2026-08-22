extends SceneTree
## Run: godot --headless --path . --script res://tools/validation/validate_bulk_haul_performance.gd

const PROVIDER_PATH := "res://features/inventory/bridge/bulk_storage_haul_provider.gd"
const PLATFORM_COUNT := 300
const ACTOR_READ_COUNT := 300

var failures: Array[String] = []


class FakePlatform:
	extends Node
	signal inventory_changed
	var offer_query_count := 0
	var item_path := "res://features/inventory/resources/items/tomato.tres"

	func bind_haul_provider(_provider: Node) -> void:
		pass

	func unbind_haul_provider(_provider: Node) -> void:
		pass

	func get_automatic_haul_offers(_settlement_id := "") -> Array:
		offer_query_count += 1
		return [{
			"offer_id": "perf:%d" % get_instance_id(),
			"category": "haul",
			"job_entry_id": "category:haul",
			"settlement_id": "perf",
			"faction_neutral": true,
			"world_position": Vector3.ZERO,
			"platform": self,
			"item_path": item_path,
		}]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var provider_script := load(PROVIDER_PATH) as Script
	var provider = provider_script.new() if provider_script != null else null
	_expect(provider != null, "bulk haul provider loads")
	if provider == null:
		_finish()
		return
	var holder := Node.new()
	root.add_child(holder)
	holder.add_child(provider)
	var platforms: Array = []
	for _index in PLATFORM_COUNT:
		var platform := FakePlatform.new()
		holder.add_child(platform)
		platforms.append(platform)
		provider.register_platform(platform)
	var initial_queries := _offer_query_total(platforms)
	_expect(initial_queries == PLATFORM_COUNT, "registration computes each platform offer slice exactly once")
	var started := Time.get_ticks_usec()
	for _index in ACTOR_READ_COUNT:
		var offers: Array = provider.get_available_work_offers()
		_expect(offers.size() == PLATFORM_COUNT, "cached offer read remains complete")
	var elapsed_usec := Time.get_ticks_usec() - started
	_expect(_offer_query_total(platforms) == initial_queries, "300 actor reads perform zero platform offer scans")
	platforms[137].inventory_changed.emit()
	_expect(_offer_query_total(platforms) == initial_queries + 1, "one platform mutation recomputes only that platform's offer slice")
	_expect(elapsed_usec < 250000, "300 cached actor reads stay below a generous 250 ms microprofile ceiling")
	root.remove_child(holder)
	holder.free()
	_finish()


func _offer_query_total(platforms: Array) -> int:
	var total := 0
	for platform in platforms:
		total += int(platform.offer_query_count)
	return total


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("BULK_HAUL_PERFORMANCE_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("BULK_HAUL_PERFORMANCE_FAILED count=%d" % failures.size())
	quit(1)
