class_name InkRipple
extends Control
## A small ink ring under the finger: instant feedback that a tap landed.

var t := 0.0
var color := UI.INK


static func at(host: Control, pos: Vector2, tint := UI.INK) -> void:
	var r := InkRipple.new()
	r.color = tint
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.position = pos
	host.add_child(r)


func _process(dt: float) -> void:
	t += dt / 0.32
	if t >= 1.0:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var e := 1.0 - pow(1.0 - t, 3.0)   # ease out
	draw_circle(Vector2.ZERO, 6.0 + 10.0 * e, Color(color, 0.16 * (1.0 - t)))
	draw_arc(Vector2.ZERO, 8.0 + 22.0 * e, 0.0, TAU, 32, Color(color, 0.55 * (1.0 - t)), 2.0, true)
