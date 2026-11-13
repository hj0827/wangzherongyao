extends "res://tests/test_base.gd"

# 合并冲突标记守卫。
#
# 2026-11-13 的事故：`git merge` 之后的提交里带着 `<<<<<<< HEAD` … `>>>>>>>`，
# 于是 `sim/match_sim.gd` 解析失败 → `arena.gd` preload 失败 → `Arena.new()`
# 拿不到脚本 → `build_complete` 永远 false，main.gd 的 `while ... await process_frame`
# 无限等下去。表现不是崩溃，而是**加载遮罩停在 0% 不动**，一点报错都看不到。
#
# 这类故障的共同点：没有任何一行代码"变红了"，只有终端里刷屏的 SCRIPT ERROR。
# 所以在源码层直接钉死：仓库里不许出现冲突标记。

const MARKERS := ["<<<<<<<", "=======", ">>>>>>>"]
# 只扫"会被引擎解析"的文件；.md/.txt 里的分隔线是合法的，不要误伤。
const SCAN_SUFFIXES := [".gd", ".tscn", ".tres", ".cfg", ".json"]
const SKIP_DIRS := [".godot", ".git", ".tmp", "shots", "sources"]

func _scan(dir_path: String, out: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with(".") and dir.current_is_dir():
			entry = dir.get_next()
			continue
		var full := dir_path.path_join(entry) if dir_path != "res://" else "res://" + entry
		if dir.current_is_dir():
			if not SKIP_DIRS.has(entry):
				_scan(full, out)
		else:
			for suffix in SCAN_SUFFIXES:
				if entry.ends_with(suffix):
					out.append(full)
					break
		entry = dir.get_next()
	dir.list_dir_end()

func _offending_lines(path: String) -> Array:
	var hits: Array = []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return hits
	var line_no := 0
	while not file.eof_reached():
		var line := file.get_line()
		line_no += 1
		for marker in MARKERS:
			# 冲突标记一定是行首顶格；缩进过的（`\t=======`）不算。
			if line.begins_with(marker):
				hits.append("%s:%d  %s" % [path.trim_prefix("res://"), line_no, line.strip_edges()])
				break
	return hits

func test_no_vcs_conflict_markers_survive_a_merge() -> void:
	var files: Array = []
	_scan("res://", files)
	gt(float(files.size()), 100.0, "扫描必须真的扫到文件（路径写错时会静默零命中）")
	var hits: Array = []
	for path in files:
		hits.append_array(_offending_lines(path))
	eq(hits.size(), 0, "仓库里不能残留 merge 冲突标记，否则整条 main→arena→sim 链路解析失败：%s" % str(hits.slice(0, 5)))
