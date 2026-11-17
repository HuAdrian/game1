class_name ClockFace
extends Control
## The case clock: a small analog face whose hands sweep to the new time.

var minutes: int = 0:
	set(v):
		minutes = v
		var tw := create_tween()
		tw.tween_property(self, "shown", float(v), 0.9).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
var shown := 0.0:
	set(v):
		shown = v
		queue_redraw()
var late := false:
	set(v):
		late = v
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var c := size * 0.5
	var r: float = min(size.x, size.y) * 0.5 - 2.0
	draw_circle(c, r, UI.RED if late else UI.PAPER)
	draw_arc(c, r, 0, TAU, 40, UI.INK, 2.5, true)
	for i in 4:
		var a := i * PI * 0.5
		draw_line(c + Vector2(cos(a), sin(a)) * (r - 5), c + Vector2(cos(a), sin(a)) * (r - 1.5), UI.INK, 2.0)
	var ha := shown / 720.0 * TAU - PI * 0.5
	var ma := shown / 60.0 * TAU - PI * 0.5
	draw_line(c, c + Vector2(cos(ha), sin(ha)) * r * 0.5, UI.INK, 3.5, true)
	draw_line(c, c + Vector2(cos(ma), sin(ma)) * r * 0.78, UI.PAPER if late else UI.RED, 2.2, true)
	draw_circle(c, 2.6, UI.INK)
