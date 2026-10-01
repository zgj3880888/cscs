extends CanvasLayer
## 游戏内 HUD + 暂停菜单 + 结算界面
##
## 所有界面元素都是代码构建的，不使用任何 UI 图片资源。
## 根节点 process_mode 设成 ALWAYS，这样场景树暂停（get_tree().paused = true）
## 之后，暂停菜单的按钮依然能点。

signal resume_requested()
signal restart_requested()
signal quit_requested()

const FONT_SIZE_HUD := 22
const FONT_SIZE_BIG := 34
const FONT_SIZE_BANNER := 46
const FONT_SIZE_TITLE := 40

const COLOR_HUD := Color(0.93, 0.95, 1.0, 0.95)
const COLOR_ACCENT := Color(1.0, 0.72, 0.28)
const COLOR_DANGER := Color(1.0, 0.36, 0.32)
const COLOR_GOOD := Color(0.45, 0.9, 0.55)

var _player: Player
var _weapon: Weapon

var _crosshair: Crosshair
var _damage_overlay: ColorRect
var _health_fill: ColorRect
var _health_label: Label
var _ammo_label: Label
var _score_label: Label
var _wave_label: Label
var _hint_label: Label
var _reload_bar_bg: ColorRect
var _reload_bar_fill: ColorRect

var _pause_menu: Control
var _game_over_menu: Control
var _game_over_score: Label

var _damage_alpha := 0.0
var _hint_timer := 0.0
var _banner_timer := 0.0

const HEALTH_BAR_SIZE := Vector2(260.0, 18.0)
const RELOAD_BAR_SIZE := Vector2(260.0, 6.0)


func _ready() -> void:
	# 暂停时 UI 仍需响应输入，所以不能跟着场景树一起停。
	process_mode = Node.PROCESS_MODE_ALWAYS

	_build_crosshair()
	_build_damage_overlay()
	_build_status_labels()
	_build_health_bar()
	_build_reload_bar()
	_build_hint_label()
	_build_pause_menu()
	_build_game_over_menu()

	_connect_game_state()

	var root := get_tree().root
	if not root.size_changed.is_connected(_on_viewport_resized):
		root.size_changed.connect(_on_viewport_resized)
	_on_viewport_resized()


## 把 HUD 和玩家/武器接起来（由 main.gd 调用）。
func bind_player(player: Player) -> void:
	_player = player
	_weapon = player.weapon

	player.health_changed.connect(_on_health_changed)
	player.damaged.connect(_on_player_damaged)

	if _weapon != null:
		_weapon.ammo_changed.connect(_on_ammo_changed)
		_weapon.reload_started.connect(_on_reload_started)
		_weapon.reload_finished.connect(_on_reload_finished)
		_weapon.hit_target.connect(_on_hit_target)
		_on_ammo_changed(_weapon.get_magazine(), _weapon.get_reserve())

	_on_health_changed(player.health, GameConfig.PLAYER_MAX_HEALTH)
	_reload_bar_bg.visible = false


func _process(delta: float) -> void:
	# 准星跟随武器的实时散布
	if _crosshair != null and _weapon != null:
		_crosshair.spread = _weapon.get_spread()

	# 换弹进度条
	if _reload_bar_bg.visible and _weapon != null:
		var progress := _weapon.get_reload_progress()
		_reload_bar_fill.size.x = RELOAD_BAR_SIZE.x * progress
		if progress >= 1.0:
			_reload_bar_bg.visible = false

	# 受伤红晕淡出
	if _damage_alpha > 0.0:
		_damage_alpha = maxf(_damage_alpha - delta * 1.8, 0.0)
		_update_damage_overlay()

	# 低血量：持续微弱红边提示
	if _player != null and not _player.is_dead:
		var ratio := float(_player.health) / float(GameConfig.PLAYER_MAX_HEALTH)
		if ratio < 0.3:
			var pulse := (sin(Time.get_ticks_msec() * 0.006) * 0.5 + 0.5) * 0.12
			_damage_overlay.color.a = maxf(_damage_overlay.color.a, pulse)

	# 提示文字自动消失
	if _hint_timer > 0.0:
		_hint_timer -= delta
		if _hint_timer <= 0.0:
			_hint_label.visible = false

	if _banner_timer > 0.0:
		_banner_timer -= delta
		var alpha := clampf(_banner_timer, 0.0, 1.0)
		_wave_label.modulate.a = alpha * 0.4 + 0.6


# =============================================================================
# 构建界面
# =============================================================================

func _build_crosshair() -> void:
	_crosshair = Crosshair.new()
	add_child(_crosshair)


func _build_damage_overlay() -> void:
	_damage_overlay = ColorRect.new()
	_damage_overlay.color = Color(0.75, 0.06, 0.06, 0.0)
	_damage_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full_rect(_damage_overlay)
	add_child(_damage_overlay)


func _build_status_labels() -> void:
	# 左上：分数
	_score_label = _make_label("分数 0", FONT_SIZE_HUD, COLOR_HUD)
	_anchor(_score_label, Vector2(0.0, 0.0), Vector2(0.0, 0.0), Vector2(24.0, 18.0))
	add_child(_score_label)

	# 顶部居中：波次与剩余敌人
	_wave_label = _make_label("准备中", FONT_SIZE_BIG, COLOR_ACCENT)
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor(_wave_label, Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(0.0, 16.0), Vector2(0.0, 58.0))
	add_child(_wave_label)

	# 左下：生命数字
	_health_label = _make_label("100", FONT_SIZE_BIG, COLOR_HUD)
	_anchor(_health_label, Vector2(0.0, 1.0), Vector2(0.0, 1.0), Vector2(24.0, -78.0), Vector2(200.0, -34.0))
	add_child(_health_label)

	# 左下（血条下方）：弹药
	_ammo_label = _make_label("30 / 240", FONT_SIZE_BIG, COLOR_HUD)
	_anchor(_ammo_label, Vector2(0.0, 1.0), Vector2(0.0, 1.0), Vector2(24.0, -46.0), Vector2(300.0, -6.0))
	add_child(_ammo_label)


func _build_health_bar() -> void:
	var bar_bg := ColorRect.new()
	bar_bg.color = Color(0.0, 0.0, 0.0, 0.45)
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor(
		bar_bg,
		Vector2(0.0, 1.0), Vector2(0.0, 1.0),
		Vector2(24.0, -30.0), Vector2(24.0 + HEALTH_BAR_SIZE.x, -30.0 + HEALTH_BAR_SIZE.y)
	)
	add_child(bar_bg)

	_health_fill = ColorRect.new()
	_health_fill.color = COLOR_GOOD
	_health_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_health_fill.position = Vector2(2.0, 2.0)
	_health_fill.size = Vector2(HEALTH_BAR_SIZE.x - 4.0, HEALTH_BAR_SIZE.y - 4.0)
	bar_bg.add_child(_health_fill)


func _build_reload_bar() -> void:
	_reload_bar_bg = ColorRect.new()
	_reload_bar_bg.color = Color(0.0, 0.0, 0.0, 0.5)
	_reload_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor(
		_reload_bar_bg,
		Vector2(0.5, 1.0), Vector2(0.5, 1.0),
		Vector2(-RELOAD_BAR_SIZE.x * 0.5, -120.0),
		Vector2(RELOAD_BAR_SIZE.x * 0.5, -120.0 + RELOAD_BAR_SIZE.y)
	)
	add_child(_reload_bar_bg)

	_reload_bar_fill = ColorRect.new()
	_reload_bar_fill.color = COLOR_ACCENT
	_reload_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reload_bar_fill.position = Vector2.ZERO
	_reload_bar_fill.size = RELOAD_BAR_SIZE
	_reload_bar_bg.add_child(_reload_bar_fill)

	_reload_bar_bg.visible = false


func _build_hint_label() -> void:
	# 屏幕中下方：临时提示（换弹中、波次间隔等）
	_hint_label = _make_label("", FONT_SIZE_BIG, COLOR_HUD)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor(_hint_label, Vector2(0.0, 0.5), Vector2(1.0, 0.5), Vector2(0.0, 90.0), Vector2(0.0, 130.0))
	_hint_label.visible = false
	add_child(_hint_label)


func _build_pause_menu() -> void:
	_pause_menu = _build_menu_shell("已暂停")

	var vbox: VBoxContainer = _pause_menu.get_node("Panel/Margin/VBox")

	# 灵敏度滑块
	var slider_label := _make_label("视角灵敏度", FONT_SIZE_HUD, COLOR_HUD)
	vbox.add_child(slider_label)

	var slider := HSlider.new()
	slider.min_value = 0.25
	slider.max_value = 3.0
	slider.step = 0.05
	slider.value = GameState.sensitivity_scale
	slider.custom_minimum_size = Vector2(320.0, 32.0)
	slider.value_changed.connect(_on_sensitivity_changed)
	vbox.add_child(slider)

	var tip := _make_label("调完直接生效，退出游戏也会记住", 15, Color(0.75, 0.78, 0.85))
	vbox.add_child(tip)

	vbox.add_child(_make_spacer(18.0))

	var resume_button := _make_menu_button("继续游戏")
	resume_button.pressed.connect(func() -> void: resume_requested.emit())
	vbox.add_child(resume_button)

	var restart_button := _make_menu_button("重新开始")
	restart_button.pressed.connect(func() -> void: restart_requested.emit())
	vbox.add_child(restart_button)

	var quit_button := _make_menu_button("退出游戏")
	quit_button.pressed.connect(func() -> void: quit_requested.emit())
	vbox.add_child(quit_button)

	_pause_menu.visible = false


func _build_game_over_menu() -> void:
	_game_over_menu = _build_menu_shell("战斗结束")

	var vbox: VBoxContainer = _game_over_menu.get_node("Panel/Margin/VBox")

	_game_over_score = _make_label("", FONT_SIZE_BIG, COLOR_ACCENT)
	_game_over_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_game_over_score)

	vbox.add_child(_make_spacer(22.0))

	var retry_button := _make_menu_button("再来一局")
	retry_button.pressed.connect(func() -> void: restart_requested.emit())
	vbox.add_child(retry_button)

	var quit_button := _make_menu_button("退出游戏")
	quit_button.pressed.connect(func() -> void: quit_requested.emit())
	vbox.add_child(quit_button)

	_game_over_menu.visible = false


## 生成一个"变暗背景 + 居中面板 + 标题 + 竖排内容"的菜单骨架。
## 返回的 Control 里固定有 Panel/Margin/VBox 三个节点，调用方往 VBox 里塞内容。
func _build_menu_shell(title_text: String) -> Control:
	var overlay := Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_full_rect(overlay)

	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.06, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_full_rect(dim)
	overlay.add_child(dim)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	var panel_width := 420.0
	var anchor_point := Vector2(0.5, 0.5)
	panel.anchor_left = anchor_point.x
	panel.anchor_top = anchor_point.y
	panel.anchor_right = anchor_point.x
	panel.anchor_bottom = anchor_point.y
	panel.offset_left = -panel_width * 0.5
	panel.offset_right = panel_width * 0.5
	panel.offset_top = -210.0
	panel.offset_bottom = 210.0
	overlay.add_child(panel)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 26)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title := _make_label(title_text, FONT_SIZE_TITLE, Color(1.0, 1.0, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	vbox.add_child(_make_spacer(10.0))

	add_child(overlay)
	return overlay


func _make_menu_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0.0, 48.0)
	button.add_theme_font_size_override("font_size", 20)
	return button


func _make_spacer(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, height)
	return spacer


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	# 描边让文字在任何背景上都看得清
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	label.add_theme_constant_override("outline_size", 5)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _full_rect(control: Control) -> void:
	control.anchor_left = 0.0
	control.anchor_top = 0.0
	control.anchor_right = 1.0
	control.anchor_bottom = 1.0
	control.offset_left = 0.0
	control.offset_top = 0.0
	control.offset_right = 0.0
	control.offset_bottom = 0.0


func _anchor(control: Control, anchor_min: Vector2, anchor_max: Vector2, offset_min: Vector2, offset_max: Vector2 = Vector2.INF) -> void:
	control.anchor_left = anchor_min.x
	control.anchor_top = anchor_min.y
	control.anchor_right = anchor_max.x
	control.anchor_bottom = anchor_max.y
	control.offset_left = offset_min.x
	control.offset_top = offset_min.y
	if offset_max != Vector2.INF:
		control.offset_right = offset_max.x
		control.offset_bottom = offset_max.y


# =============================================================================
# 信号响应
# =============================================================================

func _connect_game_state() -> void:
	GameState.score_changed.connect(_on_score_changed)
	GameState.wave_changed.connect(_on_wave_changed)
	GameState.enemies_changed.connect(_on_enemies_changed)
	GameState.game_over.connect(_on_game_over)
	_on_score_changed(GameState.score)


func _on_score_changed(score: int) -> void:
	_score_label.text = "分数 %d    最高 %d" % [score, maxi(GameState.high_score, score)]


func _on_wave_changed(wave: int) -> void:
	if wave <= 0:
		_wave_label.text = "准备中"
		return
	_wave_label.text = "第 %d 波" % wave
	_wave_label.modulate.a = 1.0
	_banner_timer = 1.2


func _on_enemies_changed(alive: int, total: int) -> void:
	if GameState.wave <= 0:
		return
	_wave_label.text = "第 %d 波    剩余 %d / %d" % [GameState.wave, alive, total]


func _on_health_changed(current: int, maximum: int) -> void:
	var ratio := 0.0 if maximum <= 0 else clampf(float(current) / float(maximum), 0.0, 1.0)
	_health_label.text = str(current)
	_health_fill.size.x = maxf((HEALTH_BAR_SIZE.x - 4.0) * ratio, 0.0)

	# 血量越低越红
	if ratio > 0.6:
		_health_fill.color = COLOR_GOOD
	elif ratio > 0.3:
		_health_fill.color = COLOR_ACCENT
	else:
		_health_fill.color = COLOR_DANGER


func _on_player_damaged(amount: int) -> void:
	# 掉血越多，红屏越明显
	_damage_alpha = clampf(maxf(_damage_alpha, float(amount) / 45.0), 0.0, 0.55)
	_update_damage_overlay()


func _update_damage_overlay() -> void:
	_damage_overlay.color.a = _damage_alpha


func _on_ammo_changed(magazine: int, reserve: int) -> void:
	_ammo_label.text = "%d / %d" % [magazine, reserve]
	_ammo_label.add_theme_color_override("font_color", COLOR_DANGER if magazine <= 5 else COLOR_HUD)


func _on_reload_started(_duration: float) -> void:
	_reload_bar_bg.visible = true
	_reload_bar_fill.size.x = 0.0
	show_hint("换弹中…", 1.6)


func _on_reload_finished() -> void:
	_reload_bar_bg.visible = false


func _on_hit_target(is_enemy: bool) -> void:
	if is_enemy and _crosshair != null:
		_crosshair.flash_hit(false)


func _on_sensitivity_changed(value: float) -> void:
	GameState.set_sensitivity_scale(value)


func _on_game_over(final_score: int, wave_reached: int) -> void:
	_game_over_score.text = "得分 %d · 到达第 %d 波\n最高分 %d" % [final_score, wave_reached, GameState.high_score]
	_game_over_menu.visible = true


func _on_viewport_resized() -> void:
	# 暂停菜单的面板高度固定，窄屏时按屏幕高度收一下，避免溢出。
	if _pause_menu == null:
		return
	var max_height := get_viewport().get_visible_rect().size.y - 80.0
	for menu in [_pause_menu, _game_over_menu]:
		var panel: Control = menu.get_node("Panel")
		var half := minf(210.0, max_height * 0.5)
		panel.offset_top = -half
		panel.offset_bottom = half


# =============================================================================
# 对外接口
# =============================================================================

## 弹出一句临时提示。
func show_hint(text: String, duration: float = 1.6) -> void:
	_hint_label.text = text
	_hint_label.visible = true
	_hint_timer = duration


func set_paused_visible(value: bool) -> void:
	_pause_menu.visible = value
	if not value:
		_game_over_menu.visible = false


func is_game_over_visible() -> bool:
	return _game_over_menu.visible
