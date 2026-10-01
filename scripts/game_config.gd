extends Node
## 全局配置（Autoload 单例，名字：GameConfig）
##
## 这里集中放两类东西：
##   1. 输入映射注册（键鼠 / 手柄 / 触屏共用的动作名）
##   2. 手感参数常量 —— 想调整移动、射击、视角手感，只改这个文件就够了
##
## 为什么用运行时注册 InputMap？
##   project.godot 里保存输入事件用的是引擎内部的序列化格式，跨版本容易失效；
##   用代码注册简单、可读、可版本控制 diff，而且不依赖编辑器。

# =============================================================================
# 一、手感参数（改这里就能调手感）
# =============================================================================

## 移动速度（米/秒）。手机上手感偏快一点比较舒服。
const MOVE_SPEED := 6.0
## 冲刺倍率。摇杆推到底自动冲刺。
const SPRINT_MULTIPLIER := 1.55
## 摇杆推过这个比例就视为冲刺。
const SPRINT_STICK_THRESHOLD := 0.92
## 跳起高度对应的初速度。
const JUMP_VELOCITY := 7.6
## 重力加速度。比现实大，为了"落地干脆、不飘"。
const GRAVITY := 22.0
## 空中还能控制多少（0 = 完全不能转向，1 = 和地面一样）。
const AIR_CONTROL := 0.35
## 地面加速度（越大越"贴脚"，越小越滑）。
const GROUND_ACCEL := 12.0
## 地面摩擦力（越大停得越快）。
const GROUND_FRICTION := 14.0

## 桌面鼠标灵敏度（弧度/像素）。
const MOUSE_SENSITIVITY := 0.0022
## 手机拖屏灵敏度。比鼠标低，因为手指像素位移更大。
const TOUCH_LOOK_SENSITIVITY := 0.0040
## 视角上下限（弧度），约 ±85 度，防止翻过头。
const PITCH_LIMIT := 1.48

## 走路时头部上下晃动的幅度（米）与频率。
const HEAD_BOB_AMPLITUDE := 0.035
const HEAD_BOB_FREQUENCY := 9.0

## 相机默认视野角度。手机上太窄会晕，稍微宽一点。
const CAMERA_FOV := 78.0

# =============================================================================
# 二、玩法参数
# =============================================================================

const PLAYER_MAX_HEALTH := 100
## 受击后多久开始回血（秒）。
const HEALTH_REGEN_DELAY := 6.0
## 回血速度（点/秒）。
const HEALTH_REGEN_RATE := 8.0

## 每个敌人被击杀得分。
const SCORE_PER_KILL := 100
## 每波敌人数 = 基础数 + 波次 * 增量。
const ENEMIES_BASE_PER_WAVE := 4
const ENEMIES_PER_WAVE_STEP := 2
## 波次之间的间隔（秒）。
const WAVE_BREAK_TIME := 4.0

# =============================================================================
# 三、碰撞层约定（改层号时同步改这里，别散落在各处）
# =============================================================================

## 第 1 层：静态世界（墙、地板、箱子）
const LAYER_WORLD := 1
## 第 2 层：玩家
const LAYER_PLAYER := 2
## 第 3 层：敌人
const LAYER_ENEMY := 4

# =============================================================================
# 四、调试开关
# =============================================================================

## 强制在桌面上也显示触屏控件（方便不插手机就能调试摇杆布局）。
const FORCE_TOUCH_CONTROLS := false

# =============================================================================


func _ready() -> void:
	_register_all_actions()


## 当前是否应该启用触屏控件。
func should_use_touch_controls() -> bool:
	if FORCE_TOUCH_CONTROLS:
		return true
	return OS.has_feature("mobile")


# =============================================================================
# 输入映射注册
# =============================================================================

func _register_all_actions() -> void:
	# ---- 移动 ----
	_add_action("move_forward", [_key(KEY_W), _key(KEY_UP), _pad_axis(JOY_AXIS_LEFT_Y, -1.0)])
	_add_action("move_back", [_key(KEY_S), _key(KEY_DOWN), _pad_axis(JOY_AXIS_LEFT_Y, 1.0)])
	_add_action("move_left", [_key(KEY_A), _key(KEY_LEFT), _pad_axis(JOY_AXIS_LEFT_X, -1.0)])
	_add_action("move_right", [_key(KEY_D), _key(KEY_RIGHT), _pad_axis(JOY_AXIS_LEFT_X, 1.0)])

	# ---- 动作 ----
	_add_action("jump", [_key(KEY_SPACE), _pad_button(JOY_BUTTON_A)])
	_add_action("sprint", [_key(KEY_SHIFT), _pad_button(JOY_BUTTON_LEFT_STICK)])
	_add_action("fire", [_mouse(MOUSE_BUTTON_LEFT), _pad_button(JOY_BUTTON_RIGHT_SHOULDER)])
	_add_action("reload", [_key(KEY_R), _pad_button(JOY_BUTTON_X)])
	_add_action("pause", [_key(KEY_ESCAPE), _pad_button(JOY_BUTTON_START)])

	# ---- UI（沿用引擎内置动作，不覆盖） ----
	for ui_action in ["ui_accept", "ui_cancel"]:
		if not InputMap.has_action(ui_action):
			InputMap.add_action(ui_action)


## 注册一个动作并绑定若干事件。已存在则跳过绑定（避免重复注册）。
func _add_action(action: StringName, events: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, 0.2)
	for event in events:
		InputMap.action_add_event(action, event)


func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	# 用 physical_keycode：跟随物理按键位置，不受输入法/键盘布局影响。
	event.physical_keycode = keycode
	return event


func _mouse(button: MouseButton) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	return event


func _pad_button(button: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	return event


func _pad_axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	return event
