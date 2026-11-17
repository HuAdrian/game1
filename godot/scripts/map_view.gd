class_name MapView
extends Control
## A street map drawn from case data. The player walks a marker from corner to corner
## (it leaves a trail and never moves by itself) and taps a building to choose it.

signal picked(block)

var map: Dictionary = {}
var dead: Array = []
var selected := ""
var path: Array = []
var walker := Vector2.ZERO:
	set(v):
		walker = v
		queue_redraw()
var pulse := 0.0
var hits: Array = []
var sfx: Callable


func setup(m: Dictionary, sound: Callable) -> void:
	map = m
	sfx = sound
	mouse_filter = Control.MOUSE_FILTER_PASS
	reset()
	for b in map.blocks:
		if b.has("id"):
			var hit := Control.new()
			hit.set_meta("block", b)
			UI.tappable(hit, "map-" + b.id, func() -> void: _pick(b))
			add_child(hit)
			hits.append(hit)
	if map.has("nodes"):
		for i in map.nodes.size():
			var nd: Array = map.nodes[i]
			var hit2 := Control.new()
			hit2.set_meta("node", nd)
			UI.tappable(hit2, "node-%d" % i, func() -> void: _walk(nd))
			add_child(hit2)
			hits.append(hit2)
	resized.connect(_place_hits)
	_place_hits()


func reset() -> void:
	path.clear()
	if map.has("nodes"):
		var s: Array = map.nodes[int(map.get("start", 0))]
		path.append(Vector2(s[0], s[1]))
		walker = path[0]
	queue_redraw()


func _scale() -> float:
	return size.x / float(map.w)


func _get_minimum_size() -> Vector2:
	return Vector2(0, 0)


func _place_hits() -> void:
	var k := _scale()
	custom_minimum_size.y = float(map.h) * k
	for hgt in hits:
		if hgt.has_meta("block"):
			var b: Dictionary = hgt.get_meta("block")
			hgt.position = Vector2(b.x, b.y) * k
			hgt.size = Vector2(b.w, b.h) * k
		else:
			var nd: Array = hgt.get_meta("node")
			hgt.position = (Vector2(nd[0], nd[1]) - Vector2(15, 15)) * k
			hgt.size = Vector2(30, 30) * k
	queue_redraw()


func _pick(b: Dictionary) -> void:
	if dead.has(b.id):
		return
	selected = b.id
	queue_redraw()
	picked.emit(b)


func _walk(nd: Array) -> void:
	var target := Vector2(nd[0], nd[1])
	var here: Vector2 = path[path.size() - 1]
	if target == here:
		return
	if target.x != here.x and target.y != here.y:
		return   # only along one street at a time
	path.append(target)
	if sfx.is_valid():
		sfx.call("step")
	var tw := create_tween()
	tw.tween_property(self, "walker", target, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(dt: float) -> void:
	pulse = fmod(pulse + dt, 1.4)
	if map.has("nodes"):
		queue_redraw()


func _draw() -> void:
	if map.is_empty():
		return
	var k := _scale()
	draw_rect(Rect2(Vector2.ZERO, Vector2(map.w, map.h) * k), Color("efe2c2"))
	for r in map.roads:
		draw_rect(Rect2(Vector2(r.x, r.y) * k, Vector2(r.w, r.h) * k), Color("faf3e1"))
	for l in map.labels:
		var pos := Vector2(l.x, l.y) * k
		if l.has("rot"):
			draw_set_transform(pos, deg_to_rad(float(l.rot)), Vector2.ONE)
			draw_string(UI.type_b, Vector2(-60, 4), l.text, HORIZONTAL_ALIGNMENT_CENTER, 120, int(10 * k), UI.SOFT)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		elif l.get("anchor", "") == "middle":
			draw_string(UI.type_b, pos - Vector2(70, 0), l.text, HORIZONTAL_ALIGNMENT_CENTER, 140, int(10 * k), UI.SOFT)
		else:
			draw_string(UI.type_b, pos, l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(10 * k), UI.SOFT)
	for b in map.blocks:
		var rect := Rect2(Vector2(b.x + 2, b.y + 2) * k, Vector2(b.w - 4, b.h - 4) * k)
		var c := rect.get_center()
		if b.has("id"):
			var sel: bool = selected == b.id
			var is_dead: bool = dead.has(b.id)
			draw_rect(rect, UI.RED_SOFT if sel else Color(UI.PAPER, 0.4 if is_dead else 1.0))
			draw_rect(rect, UI.RED if sel else Color(UI.INK, 0.3 if is_dead else 1.0), false, 3.5 if sel else 1.6)
			draw_circle(c, 15 * k, UI.RED if sel else Color(UI.PAPER, 0.0))
			draw_arc(c, 15 * k, 0, TAU, 28, UI.RED if sel else Color(UI.INK, 0.3 if is_dead else 1.0), 1.6, true)
			draw_string(UI.serif_b, c + Vector2(-20, 7 * k), b.id, HORIZONTAL_ALIGNMENT_CENTER, 40, int(20 * k), Color.WHITE if sel else Color(UI.INK, 0.3 if is_dead else 1.0))
			if is_dead:
				draw_line(rect.position, rect.end, Color(UI.RED, 0.6), 2.0, true)
		else:
			var kind: String = b.get("kind", "")
			var fill := Color("e2cf9f")
			var ink := UI.INK
			if kind == "park":
				fill = Color("cfd6b8")
			elif kind == "start":
				fill = UI.INK
				ink = UI.PAPER
			draw_rect(rect, fill)
			draw_rect(rect, UI.INK, false, 1.6)
			var names: Array = b.name
			for i in names.size():
				draw_string(UI.type_b, Vector2(rect.position.x, c.y + 4 * k + (i - (names.size() - 1) * 0.5) * 14 * k), names[i], HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, int(11 * k), ink)
	for m in map.get("marks", []):
		var p := Vector2(m.x, m.y) * k
		if m.type == "bus":
			draw_rect(Rect2(p - Vector2(28, 9) * k, Vector2(56, 16) * k), UI.INK)
			draw_string(UI.type_b, p - Vector2(28 * k, -3 * k), m.text, HORIZONTAL_ALIGNMENT_CENTER, 56 * k, int(9 * k), Color.WHITE)
		else:
			draw_colored_polygon(PackedVector2Array([p + Vector2(-7, 2) * k, p + Vector2(7, 2) * k, p + Vector2(0, -8) * k]), UI.RED)
			draw_string(UI.type_b, p + Vector2(-45 * k, 15 * k), m.text, HORIZONTAL_ALIGNMENT_CENTER, 90 * k, int(8.5 * k), UI.PAPER)
	if map.has("nodes"):
		for nd in map.nodes:
			var q := Vector2(nd[0], nd[1]) * k
			draw_circle(q, 4.0 * k, Color("faf3e1"))
			draw_arc(q, 4.0 * k, 0, TAU, 16, UI.SOFT, 1.4, true)
		if path.size() > 1:
			var pts := PackedVector2Array()
			for i in path.size() - 1:
				pts.append(path[i] * k)
			pts.append(walker * k)
			for i in pts.size() - 1:
				draw_dashed_line(pts[i], pts[i + 1], UI.RED, 3.5, 6.0)
		var wp := walker * k
		var t := pulse / 1.4
		draw_arc(wp, (7 + 12 * t) * k, 0, TAU, 24, Color(UI.RED, 1.0 - t), 2.0, true)
		draw_circle(wp, 6.5 * k, Color.WHITE)
		draw_circle(wp, 5.0 * k, UI.RED)
