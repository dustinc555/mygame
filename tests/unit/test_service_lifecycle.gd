extends GutTest
## Registry lifetime cases from validate_bootstrap_controller_wiring, without boot.

var context: BootstrapContext
var previous_context: BootstrapContext


func before_each() -> void:
	previous_context = BootstrapContext.active
	context = BootstrapContext.new(self)
	BootstrapContext.active = context


func after_each() -> void:
	BootstrapContext.active = previous_context


func test_freed_service_disappears_and_same_identity_can_bind_a_replacement() -> void:
	var service: Node = add_child_autofree(Node.new())
	context.register(&"unit.service", service)
	assert_eq(context.require(&"unit.service"), service)
	assert_true(context.has_service(&"unit.service"))
	service.free()

	assert_null(context.get_optional(&"unit.service"))
	assert_false(context.has_service(&"unit.service"))
	assert_null(BootstrapContext.service(&"unit.service"))
	var replacement: Node = add_child_autofree(Node.new())
	context.register(&"unit.service", replacement)
	assert_eq(context.require(&"unit.service"), replacement)
	assert_eq(BootstrapContext.service(&"unit.service"), replacement)


func test_queued_service_is_unavailable_before_the_deferred_free() -> void:
	var service: Node = add_child_autofree(Node.new())
	context.register(&"unit.service", service)
	assert_eq(context.get_optional(&"unit.service"), service)
	service.queue_free()

	assert_true(is_instance_valid(service), "Exercise retirement, not an already freed node")
	assert_null(context.get_optional(&"unit.service"))
	assert_false(context.has_service(&"unit.service"))
	assert_null(BootstrapContext.service(&"unit.service"))
	await get_tree().process_frame
	assert_false(is_instance_valid(service))


func test_duplicate_live_registration_reports_error_without_replacing_the_owner() -> void:
	var original: Node = add_child_autofree(Node.new())
	var intruder: Node = add_child_autofree(Node.new())
	context.register(&"unit.service", original)
	context.register(&"unit.service", intruder)

	assert_push_error("service 'unit.service' already registered")
	assert_eq(context.require(&"unit.service"), original)
	assert_eq(BootstrapContext.service(&"unit.service"), original)
