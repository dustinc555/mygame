extends TextureRect

class_name PortraitImage
## Cached portrait sizing in physical screen pixels, independent of HUD layout.

signal capture_size_changed

## Render above the displayed pixel size, then filter down for clean small faces.
@export_range(1.0, 4.0, 0.25) var supersampling := 2.0
## Bound GPU/readback memory; preserve aspect ratio when the limit is reached.
@export_range(256, 8192, 256) var max_capture_dimension := 2048
@export var antialiasing: Viewport.MSAA = Viewport.MSAA_4X

const RESIZE_SETTLE_SECONDS := 0.15

var _capture_size := Vector2i.ZERO
var _pending_size := Vector2i.ZERO
var _resize_timer: Timer


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_resize_timer = Timer.new()
	_resize_timer.one_shot = true
	_resize_timer.wait_time = RESIZE_SETTLE_SECONDS
	_resize_timer.ignore_time_scale = true
	_resize_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_resize_timer.timeout.connect(_on_resize_settled)
	add_child(_resize_timer)
	resized.connect(_queue_resolution_check)
	visibility_changed.connect(_queue_resolution_check)
	get_viewport().size_changed.connect(_queue_resolution_check)
	set_notify_transform(true)
	_queue_resolution_check.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_queue_resolution_check()


func get_capture_size() -> Vector2i:
	# CanvasItem.get_screen_transform omits root-window stretch in a CanvasLayer.
	var screen_transform := get_viewport().get_screen_transform() * get_global_transform_with_canvas()
	var screen_scale := Vector2(screen_transform.x.length(), screen_transform.y.length())
	# Use one density for both axes so nonuniform UI scaling cannot change framing.
	var density := maxf(screen_scale.x, screen_scale.y) * supersampling
	var pixels := size.max(custom_minimum_size).max(Vector2.ONE) * density
	var longest := maxf(pixels.x, pixels.y)
	if longest > max_capture_dimension:
		pixels *= float(max_capture_dimension) / longest
	return Vector2i(maxi(2, ceili(pixels.x)), maxi(2, ceili(pixels.y)))


func prepare_capture(viewport: SubViewport) -> void:
	_capture_size = get_capture_size()
	_pending_size = _capture_size
	if _resize_timer != null:
		_resize_timer.stop()
	viewport.size = _capture_size
	viewport.msaa_3d = antialiasing


func _queue_resolution_check() -> void:
	if _resize_timer == null or not is_inside_tree() or not is_visible_in_tree():
		return
	var requested := get_capture_size()
	if requested == _capture_size:
		_resize_timer.stop()
		_pending_size = requested
	elif requested != _pending_size or _resize_timer.is_stopped():
		_pending_size = requested
		_resize_timer.start()


func _on_resize_settled() -> void:
	if is_visible_in_tree() and get_capture_size() != _capture_size:
		capture_size_changed.emit()
