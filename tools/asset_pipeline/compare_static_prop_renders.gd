extends SceneTree
## Dependency-free pixel comparison for fixed-angle static-prop review renders.
##
## This developer-only SceneTree script compares the RGB channels from the four
## render names emitted by render_static_prop_review.gd. It reports mean absolute
## error, RMS error, and the percentage of channels whose absolute delta is at
## least 16/255. Thresholds catch broad damage automatically, but a passing score
## cannot certify tiny fittings or artistic quality. Godot performs the comparison
## so the pipeline adds no Pillow or other Python package dependency.

const VIEWS := ["front_oblique", "rear_oblique", "side", "high"]
const CHANNELS_PER_PIXEL := 4
const COMPARED_CHANNELS := 3


func _initialize() -> void:
	var options := _parse_options()
	var baseline_directory: String = options.get("baseline-dir", "")
	var candidate_directory: String = options.get("candidate-dir", "")
	var baseline_prefix: String = options.get("baseline-prefix", "baseline")
	var candidate_prefix: String = options.get("candidate-prefix", "candidate")
	var max_mae := float(options.get("max-mae", "1.0"))
	var max_high_delta_percent := float(options.get("max-high-delta-percent", "1.0"))
	if baseline_directory.is_empty() or candidate_directory.is_empty():
		_fail("Usage: --baseline-dir=/path --candidate-dir=/path")
		return

	var comparisons := {}
	for view_name in VIEWS:
		var baseline_path := baseline_directory.path_join("%s_%s.png" % [baseline_prefix, view_name])
		var candidate_path := candidate_directory.path_join("%s_%s.png" % [candidate_prefix, view_name])
		var baseline := Image.load_from_file(baseline_path)
		var candidate := Image.load_from_file(candidate_path)
		if baseline.is_empty() or candidate.is_empty():
			_fail("Missing or unreadable comparison render for %s" % view_name)
			return
		if baseline.get_size() != candidate.get_size():
			_fail("Render dimensions differ for %s" % view_name)
			return
		baseline.convert(Image.FORMAT_RGBA8)
		candidate.convert(Image.FORMAT_RGBA8)
		var baseline_bytes := baseline.get_data()
		var candidate_bytes := candidate.get_data()
		var channel_count := baseline.get_width() * baseline.get_height() * COMPARED_CHANNELS
		var absolute_sum := 0.0
		var square_sum := 0.0
		var high_delta_count := 0
		for pixel_offset in range(0, baseline_bytes.size(), CHANNELS_PER_PIXEL):
			for channel_offset in COMPARED_CHANNELS:
				var delta := absi(
					int(baseline_bytes[pixel_offset + channel_offset])
					- int(candidate_bytes[pixel_offset + channel_offset])
				)
				absolute_sum += delta
				square_sum += delta * delta
				if delta >= 16:
					high_delta_count += 1
		var mae := absolute_sum / channel_count
		var rms := sqrt(square_sum / channel_count)
		var high_delta_percent := 100.0 * high_delta_count / channel_count
		comparisons[view_name] = {
			"mae_255": mae,
			"rms_255": rms,
			"delta_ge_16_percent": high_delta_percent,
		}
		if mae > max_mae:
			_fail("%s render drift MAE %.3f exceeds %.3f" % [view_name, mae, max_mae])
			return
		if high_delta_percent > max_high_delta_percent:
			_fail(
				"%s high-delta channels %.3f%% exceed %.3f%%"
				% [view_name, high_delta_percent, max_high_delta_percent]
			)
			return

	print("STATIC_PROP_COMPARE_JSON=" + JSON.stringify(comparisons))
	print("STATIC_PROP_COMPARE_OK")
	quit(0)


func _parse_options() -> Dictionary:
	var options := {}
	for argument in OS.get_cmdline_user_args():
		if not argument.begins_with("--") or not argument.contains("="):
			continue
		var separator := argument.find("=")
		options[argument.substr(2, separator - 2)] = argument.substr(separator + 1)
	return options


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
