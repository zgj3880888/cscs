extends Node3D
## 主控：把关卡、玩家、HUD、触屏控件、波次系统串起来
##
## 场景结构（main.tscn）：
##   Main
##   ├── WorldEnvironment   ← 由本脚本在代码里创建
##   ├── Sun                ← 平行光，在场景里
##   ├── Level              ← level.gd，代码生成竞技场
##   └── Enemies            ← 敌人的父容器
##
## 流程：准备 → 刷怪 → 打完 → 间隔 → 下一波 …… 玩家死亡 → 结算

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const ENEMY_SCENE := preload("res://scenes/enemy.tscn")
const HUD_SCENE := preload("res://scenes/hud.tscn")
const TOUCH_SCENE := preload("res://scenes/touch_controls.tscn")

## 每波敌人分批次出现，而不是一次性全冒出来。
const SPAWN_STAGGER := 0.42
## 开局准备时间。
const WARMUP_TIME := 2.2
## 玩家死亡到弹出结算界面的延迟。
const GAME_OVER_DELAY := 1.6

enum Phase { WARMUP, SPAWNING, FIGHTING, BREAK, GAME_OVER }

@onready var _level: Level = $Level
@onready var _enemies_root: Node3D = $Enemies

var _player: Player
# 这两个故意不写类型：它们的脚本类（hud.gd / touch_controls.gd）没有 class_name，
# 强转类型反而要绕弯，直接当动态对象用更清楚。
var _hud
var _touch_controls

var _phase: Phase = Phase.WARMUP
var _phase_timer := WARMUP_TIME
var _spawn_queue := 0
var _spawn_timer := 0.0
var _wave_total := 0
var _is_paused := false


func _ready() -> void:
	_build_environment()
	GameState.reset_run()

	_spawn_player()
	_build_ui()
	_connect_signals()

	_phase = Phase.WARMUP
	_phase_timer = WARMUP_TIME
	_hud.show_hint("准备迎战…", WARMUP_TIME)
	_hud.set_paused_visible(false)


# =============================================================================
# 初始化
# =============================================================================

func _build_environment() -> void:
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"

	var environment := Environment.new()
	# 天空用纯色（不加载 HDR 贴图，手机上也更省）
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.09, 0.10, 0.14)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.60, 0.72)
	environment.ambient_light_energy = 0.55
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# 雾：让远处的墙面柔和一点，同时遮住竞技场边界
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.11, 0.13, 0.18)
	environment.fog_density = 0.016

	world_env.environment = environment
	add_child(world_env)


func _spawn_player() -> void:
	var spawn := _level.get_player_spawn()
	_player = PLAYER_SCENE.instantiate() as Player
	_player.position = spawn
	# 出生点在 +Z 侧，朝 -Z（也就是竞技场中心）看，所以偏航角是 0。
	_player.rotation.y = 0.0
	add_child(_player)


func _build_ui() -> void:
	_hud = HUD_SCENE.instantiate()
	add_child(_hud)

	# 触屏控件单独放一个 CanvasLayer，层级比 HUD 高，按钮才盖得住血条。
	var touch_layer := CanvasLayer.new()
	touch_layer.name = "TouchLayer"
	touch_layer.layer = 3
	add_child(touch_layer)

	_touch_controls = TOUCH_SCENE.instantiate()
	touch_layer.add_child(_touch_controls)


func _connect_signals() -> void:
	# touch_controls 和 hud 都是上面刚 add_child 出来的，此时它们的 _ready 已经执行完。
	_hud.bind_player(_player)

	_hud.resume_requested.connect(_on_resume_requested)
	_hud.restart_requested.connect(_on_restart_requested)
	_hud.quit_requested.connect(_on_quit_requested)
	_touch_controls.pause_pressed.connect(_on_pause_pressed)
	_player.died.connect(_on_player_died)
	GameState.game_over.connect(_on_game_over)


# =============================================================================
# 波次流程
# =============================================================================

func _process(delta: float) -> void:
	if _is_paused:
		return

	match _phase:
		Phase.WARMUP, Phase.BREAK:
			_phase_timer -= delta
			if _phase_timer <= 0.0:
				_start_wave(GameState.wave + 1)
		Phase.SPAWNING:
			_tick_spawn_queue(delta)
			if _spawn_queue <= 0:
				_phase = Phase.FIGHTING
				_refresh_enemy_counts()
		Phase.FIGHTING:
			_refresh_enemy_counts()
			if _alive_enemy_count() == 0:
				_enter_break()
		Phase.GAME_OVER:
			pass


func _start_wave(index: int) -> void:
	_phase = Phase.SPAWNING
	GameState.set_wave(index)

	var count := GameConfig.ENEMIES_BASE_PER_WAVE
	count += GameConfig.ENEMIES_PER_WAVE_STEP * (index - 1)

	_spawn_queue = count
	_spawn_timer = 0.0
	_wave_total = count
	GameState.set_enemy_counts(0, count)

	# 每一波开始补一点弹药，避免玩家被弹药卡死。
	_player.weapon.refill_ammo()
	_player.heal_full()
	_hud.show_hint("第 %d 波来袭 · %d 个敌人" % [index, count], 2.0)


func _enter_break() -> void:
	_phase = Phase.BREAK
	_phase_timer = GameConfig.WAVE_BREAK_TIME
	_refresh_enemy_counts()
	_hud.show_hint("清空！%.0f 秒后下一波" % GameConfig.WAVE_BREAK_TIME, GameConfig.WAVE_BREAK_TIME)
	_player.weapon.refill_ammo()


func _tick_spawn_queue(delta: float) -> void:
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	_spawn_timer = SPAWN_STAGGER
	_spawn_queue -= 1
	_spawn_enemy()
	_refresh_enemy_counts()


func _spawn_enemy() -> void:
	var spawn_points := _level.get_spawn_points()
	if spawn_points.is_empty():
		return

	# 优先选离玩家远的点，避免敌人贴着玩家出生。
	var candidates: Array[Vector3] = []
	for point in spawn_points:
		if point.distance_to(_player.global_position) > 13.0:
			candidates.append(point)
	if candidates.is_empty():
		candidates = spawn_points

	var spawn := candidates[randi() % candidates.size()]

	var enemy := ENEMY_SCENE.instantiate() as Enemy
	enemy.position = spawn
	enemy.setup(_player, GameState.wave)
	enemy.connect("died", _on_enemy_died)
	_enemies_root.add_child(enemy)


func _alive_enemy_count() -> int:
	return _enemies_root.get_child_count()


func _refresh_enemy_counts() -> void:
	# "未解决"的敌人 = 场上活着的 + 还没刷出来的队列。
	var remaining := _enemies_root.get_child_count() + maxi(_spawn_queue, 0)
	GameState.set_enemy_counts(remaining, _wave_total)


# =============================================================================
# 事件响应
# =============================================================================

func _on_enemy_died(_enemy: Enemy) -> void:
	GameState.add_score(GameConfig.SCORE_PER_KILL)
	_refresh_enemy_counts()


func _on_player_died() -> void:
	if _phase == Phase.GAME_OVER:
		return
	_phase = Phase.GAME_OVER
	# 死亡后清掉还没刷出来的敌人，避免结算界面上还被打。
	_spawn_queue = 0
	_hud.show_hint("", 0.1)

	var timer := get_tree().create_timer(GAME_OVER_DELAY, true, false, true)
	timer.timeout.connect(func() -> void:
		GameState.trigger_game_over()
		_set_paused(true)
	)


func _on_game_over(_final_score: int, _wave: int) -> void:
	# HUD 自己会显示结算面板（见 hud.gd 的 _on_game_over）
	pass


func _on_pause_pressed() -> void:
	_set_paused(not _is_paused)


func _on_resume_requested() -> void:
	_set_paused(false)


func _on_restart_requested() -> void:
	get_tree().paused = false
	_is_paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if not GameConfig.should_use_touch_controls() else Input.MOUSE_MODE_VISIBLE
	GameState.reset_run()
	get_tree().reload_current_scene()


func _on_quit_requested() -> void:
	get_tree().quit()


# =============================================================================
# 暂停
# =============================================================================

func _set_paused(value: bool) -> void:
	_is_paused = value
	get_tree().paused = value

	_hud.set_paused_visible(value)
	# 暂停时关掉触屏输入，否则它会把事件全部吃掉，菜单按钮点不动。
	_touch_controls.set_active(not value)

	if value:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif not GameConfig.should_use_touch_controls():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_set_paused(not _is_paused)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and _is_paused:
		_set_paused(false)
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	# 手机切到后台 / 被电话打断时自动暂停，回来不会发现自己已经死了。
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and OS.has_feature("mobile"):
		if not _is_paused and _phase != Phase.GAME_OVER:
			_set_paused(true)
