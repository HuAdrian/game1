class_name PenMark
extends Control
## A mark drawn over a document as if with a pen: underline, circle, tick, cross or strike.
## The "tape" kind sticks a strip of tape (assets/ui/tape.png) across the top edge instead.

var kind := "underline"
var color := UI.RED
var progress := 0.0:
	set(v):
		progress = v
		queue_redraw()


static func draw_on(target: Control, kind_ := "underline", color_ := UI.RED) -> PenMark:
	var m := PenMark.new()
	m.kind = kind_
	m.color = color_
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	target.add_child(m)
	var tw := m.create_tween()
	tw.tween_property(m, "progress", 1.0, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	return m


func _points() -> PackedVector2Array:
	var w := size.x
	var h := size.y
	var pts := PackedVector2Array()
	match kind:
		"circle":
			for i in 44:
				var t := float(i) / 40.0
				var a := -2.6 + t * TAU * 1.04
				var wob := 1.0 + 0.03 * sin(t * 9.0)
				pts.append(Vector2(w * 0.5 + cos(a) * (w * 0.5 - 3) * wob, h * 0.5 + sin(a) * (h * 0.5 - 2) * wob))
		"tick":
			var o := Vector2(w - 34, 8)
			pts.append(o + Vector2(0, 14))
			pts.append(o + Vector2(8, 22))
			pts.append(o + Vector2(24, 0))
		"cross":
			var o2 := Vector2(w - 32, 8)
			pts.append(o2)
			pts.append(o2 + Vector2(20, 20))
			pts.append(o2 + Vector2(10, 10))
			pts.append(o2 + Vector2(20, 0))
			pts.append(o2 + Vector2(0, 20))
		"strike":
			for i in 13:
				var t2 := float(i) / 12.0
				pts.append(Vector2(8 + (w - 16) * t2, h * 0.5 + sin(t2 * 11.0) * 1.6))
		_:
			for i in 13:
				var t3 := float(i) / 12.0
				pts.append(Vector2(10 + (w - 20) * t3, h - 5 + sin(t3 * 9.0) * 1.3))
	return pts


func _draw() -> void:
	if kind == "tape":
		var tex := UI.texture("res://assets/ui/tape.png")
		if tex:
			var w := 92.0 * progress
			draw_set_transform(Vector2(size.x * 0.42, -13), -0.07, Vector2.ONE)
			draw_texture_rect(tex, Rect2(0, 0, w, 26), false)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	var pts := _points()
	var n := int(ceil(pts.size() * progress))
	if n >= 2:
		draw_polyline(pts.slice(0, n), color, 3.0, true)
