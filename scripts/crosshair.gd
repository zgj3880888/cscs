extends Control
class_name Crosshair
## 动态准星
##
## 准星的四条线会随"当前散布"张开或收拢，所以它能真实反映子弹会飞到哪儿 ——
## 移动、跳跃、连射时准星张开，玩家能直观看到"现在打不准"。
## 用武器散布角（弧度）换算屏幕像素，这样准星永远和实际弹道一致。

const LINE_LENGTH := 11.0
const LINE_THICKNESS := 2.0
const BASE_GAP := 7.0
const COLOR_NORMAL := Color(1.0, 1.0, 1.0, 0.82)
const COLOR_HIT := Color(1.0, 0.72, 0.28, 0.98)
const COLOR_KILL := Color(1.0, 0.32, 0.28, 1.0)
const HIT_MARKER_DURATION := 0.16

## 当前散布（弧度），由武器每帧写入。
var spread := 0.0

var _hit_timer := 0.0
var _hit_was_kill := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 准星要在 UI 最上层，别被血条之类挡住。
	z_index = 10


func _process(delta: float) -> void:
	if _hit_timer > 0.0:
		_hit_timer -= delta
		queue_redraw()


## 命中反馈。击杀和普通命中用不同颜色。
func flash_hit(is_kill: bool = false) -> void:
	_hit_timer = HIT_MARKER_DURATION
	_hit_was_kill = is_kill
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var gap := BASE_GAP + _spread_to_pixels()

	var color := COLOR_NORMAL
	if _hit_timer > 0.0:
		color = COLOR_KILL if _hit_was_kill else COLOR_HIT

	# 四条线：上下左右各一条，中间留出 gap。
	var directions: Array[Vector2] = [
		Vector2(0.0, -1.0),
		Vector2(0.0, 1.0),
		Vector2(-1.0, 0.0),
		Vector2(1.0, 0.0),
	]
	for dir: Vector2 in directions:
		var from := center + dir * gap
		var to := center + dir * (gap + LINE_LENGTH)
		draw_line(from, to, color, LINE_THICKNESS, true)

	# 中心点
	draw_circle(center, 1.2, Color(color.r, color.g, color.b, color.a * 0.8))

	if _hit_timer > 0.0:
		_draw_hit_marker(center, color)


## 命中标记：四条 45 度斜线。
func _draw_hit_marker(center: Vector2, color: Color) -> void:
	var inner := 6.0
	var outer := 13.0
	var diagonals: Array[Vector2] = [
		Vector2(-1.0, -1.0),
		Vector2(1.0, -1.0),
		Vector2(-1.0, 1.0),
		Vector2(1.0, 1.0),
	]
	for dir: Vector2 in diagonals:
		var unit := dir.normalized()
		draw_line(
			center + unit * inner,
			center + unit * outer,
			color,
			LINE_THICKNESS + 0.5,
			true
		)


## 把散布角换算成屏幕像素间距。
## 原理：屏幕上 1 弧度对应的像素数 = (视口高度 / 2) / tan(fov / 2)。
func _spread_to_pixels() -> float:
	var viewport_height := get_viewport_rect().size.y
	if viewport_height <= 0.0:
		return 0.0
	var half_fov := deg_to_rad(GameConfig.CAMERA_FOV) * 0.5
	var pixels_per_radian := (viewport_height * 0.5) / tan(half_fov)
	return tan(spread) * pixels_per_radian
