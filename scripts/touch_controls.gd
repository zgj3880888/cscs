extends Control
## 手机触屏操作层：虚拟摇杆 + 射击/跳跃/换弹/暂停按钮
##
## 布局思路（横屏，这是手机 FPS 的通用布局）：
##   * 左半屏：动态虚拟摇杆。手指按在左半屏任意位置，摇杆基座就出现在那里，
##     不用去够固定的位置，手感更好。
##   * 右半屏：拖拽转身 / 抬枪。
##   * 右下角：开火（大）、跳跃、换弹三个按钮，拇指自然覆盖范围。
##
## 多点触控的实现：
##   每个手指用 event.index 跟踪，记录它当前扮演的角色（摇杆 / 视角 / 某按钮），
##   手指移动和抬起时按角色分派。这样一边推摇杆一边转身一边开火不会互相打断。
##
## 触屏控件通过 Input.action_press()/action_release() 把操作"翻译"成
## InputMap 动作，所以 Player 和 Weapon 的代码完全不用区分手机还是电脑。

## 暂停按钮被按下。
signal pause_pressed()

const STICK_MAX_RADIUS := 120.0
const STICK_DEAD_ZONE := 14.0
const KNOB_RADIUS := 52.0

const COLOR_STICK_RING := Color(1.0, 1.0, 1.0, 0.18)
const COLOR_STICK_FILL := Color(1.0, 1.0, 1.0, 0.05)
const COLOR_KNOB := Color(1.0, 1.0, 1.0, 0.20)
const COLOR_KNOB_RING := Color(1.0, 1.0, 1.0, 0.55)
const COLOR_BUTTON := Color(1.0, 1.0, 1.0, 0.13)
const COLOR_BUTTON_RING := Color(1.0, 1.0, 1.0, 0.42)
const COLOR_BUTTON_ACTIVE := Color(1.0, 0.65, 0.25, 0.45)
const COLOR_BUTTON_ACTIVE_RING := Color(1.0, 0.78, 0.4, 0.95)
const COLOR_LABEL := Color(1.0, 1.0, 1.0, 0.88)


## 一个圆形按钮的定义。center / radius 在 _relayout() 里按屏幕尺寸算出来。
class TouchButton:
	var action: StringName
	var label: String
	var center := Vector2.ZERO
	var base_radius := 50.0     ## 720p 基准下的半径
	var radius := 50.0          ## 按当前屏幕缩放后的实际半径
	var pressed_by := -1        ## 正在按它的手指 index，-1 表示没被按

	func _init(p_action: StringName, p_label: String, p_radius: float) -> void:
		action = p_action
		label = p_label
		base_radius = p_radius
		radius = p_radius


var _player: Player
var _buttons: Array[TouchButton] = []

# 摇杆状态
var _stick_touch_index := -1
var _stick_active := false
var _stick_base := Vector2.ZERO
var _stick_vector := Vector2.ZERO   ## 归一化方向（长度 0..1）

# 视角拖拽
var _look_touch_index := -1

# 是否用鼠标模拟触摸（桌面上调试手机布局用）
var _mouse_emulation := false
var _mouse_down := false

var _active := false
var _font: Font


func _ready() -> void:
	# 铺满整个屏幕
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_player = get_tree().get_first_node_in_group("player") as Player
	_active = GameConfig.should_use_touch_controls()
	_mouse_emulation = _active and not OS.has_feature("mobile")

	_build_buttons()
	_relayout()
	# _ready 时 Control 的 size 可能还是 0，等一帧再算一次布局。
	_relayout.call_deferred()

	resized.connect(_relayout)

	if not _active:
		visible = false
		set_process_input(false)


func _build_buttons() -> void:
	# 注意顺序：先出现的先做命中判定，所以大按钮放在前面不好 ——
	# 这里按半径从小到大排，保证小按钮不会被大按钮"吃掉"。
	_buttons = [
		TouchButton.new(&"pause", "暂停", 34.0),
		TouchButton.new(&"weapon_next", "换枪", 46.0),
		TouchButton.new(&"reload", "换弹", 54.0),
		TouchButton.new(&"jump", "跳跃", 58.0),
		TouchButton.new(&"fire", "开火", 82.0),
	]


## 按当前屏幕尺寸重新计算控件位置和大小。
func _relayout() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return

	# 以屏幕短边为基准做缩放，适配不同分辨率 / 不同比例的屏幕。
	# 不做缩放的话，在高分辨率手机上按钮会小得按不准。
	var unit := minf(size.x, size.y)
	var factor := clampf(unit / 720.0, 0.72, 1.7)
	var margin := 110.0 * factor

	for button in _buttons:
		button.radius = button.base_radius * factor
		match button.action:
			&"fire":
				button.center = Vector2(size.x - margin, size.y - margin)
			&"jump":
				button.center = Vector2(
					size.x - margin - 26.0 * factor,
					size.y - margin - 190.0 * factor
				)
			&"reload":
				button.center = Vector2(
					size.x - margin - 205.0 * factor,
					size.y - margin - 12.0 * factor
				)
			&"weapon_next":
				button.center = Vector2(
					size.x - margin - 335.0 * factor,
					size.y - margin - 25.0 * factor
				)
			&"pause":
				button.center = Vector2(size.x - 52.0 * factor, 52.0 * factor)

	queue_redraw()


# =============================================================================
# 供外部调用
# =============================================================================

## 暂停时关掉触屏输入，把事件让给暂停菜单的按钮。
func set_active(value: bool) -> void:
	_active = value
	set_process_input(value)
	if not value:
		_release_all()
	visible = value and GameConfig.should_use_touch_controls()


func is_active() -> bool:
	return _active


# =============================================================================
# 输入处理
# =============================================================================

func _input(event: InputEvent) -> void:
	if not _active:
		return

	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		_handle_touch(touch.index, touch.position, touch.pressed)
		get_viewport().set_input_as_handled()
		return

	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_handle_drag(drag.index, drag.position, drag.relative)
		get_viewport().set_input_as_handled()
		return

	if not _mouse_emulation:
		return

	# 桌面调试：鼠标左键当作一根手指。
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		_mouse_down = button.pressed
		_handle_touch(0, button.position, button.pressed)
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion and _mouse_down:
		var motion := event as InputEventMouseMotion
		_handle_drag(0, motion.position, motion.relative)
		get_viewport().set_input_as_handled()


func _handle_touch(index: int, position: Vector2, pressed: bool) -> void:
	if pressed:
		_on_touch_down(index, position)
	else:
		_on_touch_up(index)


func _on_touch_down(index: int, position: Vector2) -> void:
	# 1) 先判按钮
	var hit := _button_at(position)
	if hit != null:
		hit.pressed_by = index
		Input.action_press(hit.action)
		queue_redraw()
		return

	# 2) 左半屏 → 摇杆（动态基座：按哪儿哪儿就是中心）
	if position.x < size.x * 0.5:
		if _stick_touch_index == -1:
			_stick_touch_index = index
			_stick_active = true
			_stick_base = position
			_stick_vector = Vector2.ZERO
			queue_redraw()
		return

	# 3) 右半屏 → 视角拖拽
	if _look_touch_index == -1:
		_look_touch_index = index


func _on_touch_up(index: int) -> void:
	for button in _buttons:
		if button.pressed_by == index:
			button.pressed_by = -1
			Input.action_release(button.action)
			queue_redraw()

	if index == _stick_touch_index:
		_stick_touch_index = -1
		_stick_active = false
		_stick_vector = Vector2.ZERO
		_apply_stick_to_player()
		Input.action_release(&"sprint")
		queue_redraw()

	if index == _look_touch_index:
		_look_touch_index = -1


func _handle_drag(index: int, position: Vector2, relative: Vector2) -> void:
	if index == _stick_touch_index:
		var offset := position - _stick_base
		if offset.length() < STICK_DEAD_ZONE:
			_stick_vector = Vector2.ZERO
		else:
			_stick_vector = offset.limit_length(STICK_MAX_RADIUS) / STICK_MAX_RADIUS
		_apply_stick_to_player()
		queue_redraw()
		return

	if index == _look_touch_index:
		if _player != null:
			_player.add_look_delta(relative)


## 把摇杆状态写给玩家，并在推到底时触发冲刺。
func _apply_stick_to_player() -> void:
	if _player != null:
		_player.touch_move = _stick_vector

	if _stick_vector.length() >= GameConfig.SPRINT_STICK_THRESHOLD:
		Input.action_press(&"sprint")
	else:
		Input.action_release(&"sprint")


func _release_all() -> void:
	for button in _buttons:
		if button.pressed_by != -1:
			Input.action_release(button.action)
		button.pressed_by = -1
	Input.action_release(&"sprint")
	_stick_touch_index = -1
	_stick_active = false
	_stick_vector = Vector2.ZERO
	if _player != null:
		_player.touch_move = Vector2.ZERO
	_look_touch_index = -1


func _button_at(position: Vector2) -> TouchButton:
	# 倒序遍历：后定义的按钮（如开火）优先，因为它们通常更大、更常用。
	for i in range(_buttons.size() - 1, -1, -1):
		var button := _buttons[i]
		if position.distance_to(button.center) <= button.radius:
			return button
	return null


# =============================================================================
# 绘制
# =============================================================================

func _draw() -> void:
	if not _active:
		return

	_draw_stick()

	for button in _buttons:
		var is_pressed := button.pressed_by != -1
		var fill := COLOR_BUTTON_ACTIVE if is_pressed else COLOR_BUTTON
		var ring := COLOR_BUTTON_ACTIVE_RING if is_pressed else COLOR_BUTTON_RING
		draw_circle(button.center, button.radius, fill)
		draw_arc(button.center, button.radius, 0.0, TAU, 48, ring, 3.0, true)
		_draw_centered_text(button.label, button.center, int(button.radius * 0.42), COLOR_LABEL)


func _draw_stick() -> void:
	if not _stick_active:
		return

	draw_circle(_stick_base, STICK_MAX_RADIUS, COLOR_STICK_FILL)
	draw_arc(_stick_base, STICK_MAX_RADIUS, 0.0, TAU, 64, COLOR_STICK_RING, 3.0, true)

	var knob_position := _stick_base + _stick_vector * STICK_MAX_RADIUS
	draw_circle(knob_position, KNOB_RADIUS, COLOR_KNOB)
	draw_arc(knob_position, KNOB_RADIUS, 0.0, TAU, 48, COLOR_KNOB_RING, 3.0, true)


func _draw_centered_text(text: String, center: Vector2, font_size: int, color: Color) -> void:
	if _font == null:
		_font = ThemeDB.fallback_font
	if _font == null:
		return

	var text_size := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	# draw_string 的坐标是文字基线左端，所以要自己算出居中的起点。
	var origin := center - Vector2(text_size.x * 0.5, -text_size.y * 0.32)
	draw_string(_font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
