extends Node
## 全局运行时状态（Autoload 单例，名字：GameState）
##
## 管三件事：
##   1. 计分 / 波次等本局数据
##   2. 玩家设置（灵敏度等）的读取与持久化
##   3. 用信号把变化广播给 UI，避免 UI 每帧轮询

signal score_changed(score: int)
signal wave_changed(wave: int)
signal enemies_changed(alive: int, total: int)
signal game_over(final_score: int, wave_reached: int)
signal sensitivity_changed(value: float)

const SETTINGS_PATH := "user://settings.cfg"

## 本局得分。
var score: int = 0
## 当前波次，从 1 开始。
var wave: int = 0
## 本波剩余敌人 / 本波总数。
var enemies_alive: int = 0
var enemies_total: int = 0
## 历史最高分，落盘保存。
var high_score: int = 0
## 玩家灵敏度倍率（0.25 ~ 3.0），落盘保存。
var sensitivity_scale: float = 1.0
## 本局是否已结束。
var is_game_over: bool = false


func _ready() -> void:
	_load_settings()


# =============================================================================
# 本局流程
# =============================================================================

## 开始新的一局：清空所有本局数据。
func reset_run() -> void:
	score = 0
	wave = 0
	enemies_alive = 0
	enemies_total = 0
	is_game_over = false
	score_changed.emit(score)
	wave_changed.emit(wave)
	enemies_changed.emit(enemies_alive, enemies_total)


func add_score(amount: int) -> void:
	score += amount
	score_changed.emit(score)


func set_wave(value: int) -> void:
	wave = value
	wave_changed.emit(wave)


func set_enemy_counts(alive: int, total: int) -> void:
	enemies_alive = alive
	enemies_total = total
	enemies_changed.emit(alive, total)


func trigger_game_over() -> void:
	if is_game_over:
		return
	is_game_over = true
	if score > high_score:
		high_score = score
		_save_settings()
	game_over.emit(score, wave)


# =============================================================================
# 设置持久化
# =============================================================================

func set_sensitivity_scale(value: float) -> void:
	sensitivity_scale = clampf(value, 0.25, 3.0)
	sensitivity_changed.emit(sensitivity_scale)
	_save_settings()


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	high_score = int(cfg.get_value("player", "high_score", 0))
	sensitivity_scale = float(cfg.get_value("player", "sensitivity_scale", 1.0))


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "high_score", high_score)
	cfg.set_value("player", "sensitivity_scale", sensitivity_scale)
	cfg.save(SETTINGS_PATH)
