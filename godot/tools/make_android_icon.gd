extends SceneTree

const SOURCE := "res://icon.svg"
const TARGET := "res://assets/icons/icon_192.png"
const MONO_TARGET := "res://assets/icons/icon_monochrome_432.png"
const MONO_SVG := """<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">
  <path fill-rule="evenodd" fill="#ffffff" d="M64 14 104 34v34c0 24-17 38-40 46-23-8-40-22-40-46V34z M64 34l7 18 19 2-14 13 4 19-16-10-16 10 4-19-14-13 19-2z"/>
</svg>"""

func _initialize() -> void:
	var svg := FileAccess.get_file_as_string(SOURCE)
	if svg.is_empty():
		push_error("Cannot read " + SOURCE)
		quit(1)
		return
	var image := Image.new()
	var err := image.load_svg_from_string(svg, 1.5)
	if err != OK:
		push_error("Cannot rasterize icon: %s" % error_string(err))
		quit(1)
		return
	image.resize(192, 192, Image.INTERPOLATE_LANCZOS)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/icons"))
	err = image.save_png(ProjectSettings.globalize_path(TARGET))
	if err != OK:
		push_error("Cannot save icon: %s" % error_string(err))
		quit(1)
		return
	print("ICON ", image.get_width(), "x", image.get_height(), " -> ", TARGET)

	var mono := Image.new()
	err = mono.load_svg_from_string(MONO_SVG, 3.375)
	if err != OK:
		push_error("Cannot rasterize monochrome icon: %s" % error_string(err))
		quit(1)
		return
	mono.resize(432, 432, Image.INTERPOLATE_LANCZOS)
	err = mono.save_png(ProjectSettings.globalize_path(MONO_TARGET))
	if err != OK:
		push_error("Cannot save monochrome icon: %s" % error_string(err))
		quit(1)
		return
	print("ICON ", mono.get_width(), "x", mono.get_height(), " -> ", MONO_TARGET)
	quit()
