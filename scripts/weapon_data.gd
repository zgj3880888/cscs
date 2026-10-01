extends RefCounted
class_name WeaponData
## 武器定义表
##
## 一把枪的全部参数都在这里：数值、模型、握持姿势、以及**机械动作时间轴**。
## 想加第五把枪，只要在 build_all() 里追加一条定义即可，其他代码不用动。
##
## ── 模型坐标约定（实测得出，见 assets/licenses/ 的来源说明）──
##   * 枪管朝 -Z（正好是 Godot 的前向），上方是 +Y，右侧是 +X
##   * 单位是米。步枪全长 0.70m、手枪 0.22m，都是真实比例
##   * 枪械自带骨骼，机械部件是独立骨骼：
##       步枪 Bolt / Charging Handle / Magazine / Trigger / Selector / Dust Cover
##       冲锋枪 Bolt / Bolt Release / Magazine / Trigger / Selector
##       霰弹枪 Pump / Shell / Lifter / Trigger / Safety
##       手枪   Slide / Hammer / Magazine / Trigger
##     所以开火和换弹是**真的在动那些零件**，不是整体晃一下。
##
## ── 时间轴写法 ──
##   mech_fire / mech_reload 是 { 骨骼名: [关键帧...] } 的结构，
##   每个关键帧是 [时间(秒), 模型空间位移(米), 旋转(度, 绕模型空间轴)]。
##   驱动逻辑在 weapon_view.gd 里，会在关键帧之间做线性插值。
##   位移方向按模型坐标：+Z 是把零件往后拉，-Y 是往下掉。

# =============================================================================
# 字段
# =============================================================================

var id: StringName                      ## 唯一标识，存档 / 切枪用
var display_name: String                ## 显示名（中文）
var model_path: String                  ## 模型路径，res:// 开头

# ---- 弹药 ----
var magazine_size: int
var reserve_ammo: int
var fire_interval: float                ## 两发之间最小间隔（秒）
var reload_time: float                  ## 换弹总时长（秒）
var is_automatic: bool                  ## true = 按住连发

# ---- 伤害 ----
var damage: int                         ## 单发（单弹丸）基础伤害
var pellets: int = 1                    ## 一次击发的弹丸数，霰弹枪 > 1

# ---- 弹道 ----
var max_range := 120.0
var falloff_start := 28.0
var falloff_end := 80.0
var falloff_min_mult := 0.45

# ---- 散布（弧度）----
var spread_base := 0.0045               ## 静止基础散布
var spread_per_shot := 0.0032           ## 每开一枪累加
var spread_max := 0.055                 ## 上限
var spread_recovery := 3.2              ## 回落速度倍率
var spread_move_factor := 0.010         ## 移动带来的额外散布

# ---- 后坐 ----
var recoil_pitch := 0.010               ## 每发视角上抬（弧度）
var recoil_yaw := 0.005                 ## 每发视角左右随机（弧度）
var view_kick := 0.035                  ## 视角模型后退量（米）

# ---- 握持姿势（相机空间）----
var hold_offset := Vector3.ZERO         ## 相对相机的位置
var hold_rotation_deg := Vector3.ZERO   ## 相对相机的欧拉角（度）

# ---- 机械动作时间轴 ----
var mech_fire := {}                     ## 开火时播放
var mech_reload := {}                   ## 换弹时播放


# =============================================================================
# 全部武器
# =============================================================================

static func build_all() -> Array[WeaponData]:
	var list: Array[WeaponData] = []
	list.append(_assault_rifle())
	list.append(_smg())
	list.append(_shotgun())
	list.append(_pistol())
	return list


# -----------------------------------------------------------------------------
# 突击步枪
# -----------------------------------------------------------------------------
static func _assault_rifle() -> WeaponData:
	var w := WeaponData.new()
	w.id = &"assault_rifle"
	w.display_name = "突击步枪"
	w.model_path = "res://assets/weapons/rifle_assault.glb"

	w.magazine_size = 30
	w.reserve_ammo = 240
	w.fire_interval = 0.095             # 约 630 发/分
	w.reload_time = 2.15
	w.is_automatic = true

	w.damage = 23
	w.max_range = 120.0
	w.falloff_start = 28.0
	w.falloff_end = 80.0
	w.falloff_min_mult = 0.45

	w.spread_base = 0.0045
	w.spread_per_shot = 0.0032
	w.spread_max = 0.055
	w.spread_recovery = 3.2
	w.spread_move_factor = 0.010

	w.recoil_pitch = 0.010
	w.recoil_yaw = 0.005
	w.view_kick = 0.038

	# 模型局部 Z 范围 -0.339 ~ +0.359。把枪口摆到相机前 0.75m：
	#   原点 z = -0.75 + 0.339 = -0.411
	w.hold_offset = Vector3(0.155, -0.175, -0.411)
	w.hold_rotation_deg = Vector3(0.0, -1.5, 0.0)

	w.mech_fire = {
		# 枪机高速往复：这是自动步枪最核心的视觉反馈
		"Bolt": [
			[0.000, Vector3.ZERO, Vector3.ZERO],
			[0.028, Vector3(0.0, 0.0, 0.046), Vector3.ZERO],
			[0.075, Vector3.ZERO, Vector3.ZERO],
		],
		"Charging Handle": [
			[0.000, Vector3.ZERO, Vector3.ZERO],
			[0.028, Vector3(0.0, 0.0, 0.030), Vector3.ZERO],
			[0.075, Vector3.ZERO, Vector3.ZERO],
		],
		"Trigger": [
			[0.000, Vector3.ZERO, Vector3.ZERO],
			[0.020, Vector3.ZERO, Vector3(-14.0, 0.0, 0.0)],
			[0.090, Vector3.ZERO, Vector3.ZERO],
		],
		"Dust Cover": [
			[0.000, Vector3.ZERO, Vector3.ZERO],
			[0.028, Vector3.ZERO, Vector3(-6.0, 0.0, 0.0)],
			[0.075, Vector3.ZERO, Vector3.ZERO],
		],
	}

	w.mech_reload = {
		# 弹匣落下 → 停顿 → 新弹匣推入
		"Magazine": [
			[0.00, Vector3.ZERO, Vector3.ZERO],
			[0.32, Vector3(0.0, -0.165, 0.020), Vector3(0.0, 0.0, 9.0)],
			[0.72, Vector3(0.0, -0.165, 0.020), Vector3(0.0, 0.0, 9.0)],
			[1.02, Vector3.ZERO, Vector3.ZERO],
		],
		# 拉机柄：先空等，再干脆地拉到底推回去
		"Charging Handle": [
			[0.00, Vector3.ZERO, Vector3.ZERO],
			[1.38, Vector3.ZERO, Vector3.ZERO],
			[1.52, Vector3(0.0, 0.0, 0.062), Vector3.ZERO],
			[1.70, Vector3.ZERO, Vector3.ZERO],
		],
		"Trigger": [
			[0.00, Vector3.ZERO, Vector3.ZERO],
			[1.45, Vector3.ZERO, Vector3.ZERO],
			[1.58, Vector3.ZERO, Vector3(-10.0, 0.0, 0.0)],
			[1.80, Vector3.ZERO, Vector3.ZERO],
		],
	}
	return w


# -----------------------------------------------------------------------------
# 冲锋枪
# -----------------------------------------------------------------------------
static func _smg() -> WeaponData:
	var w := WeaponData.new()
	w.id = &"smg"
	w.display_name = "冲锋枪"
	w.model_path = "res://assets/weapons/smg_full.glb"

	w.magazine_size = 25
	w.reserve_ammo = 200
	w.fire_interval = 0.070             # 约 860 发/分，比步枪快
	w.reload_time = 1.85
	w.is_automatic = true

	w.damage = 16
	w.falloff_start = 18.0              # 近战武器，衰减更早
	w.falloff_end = 55.0
	w.falloff_min_mult = 0.32

	w.spread_base = 0.0075              # 基础散布比步枪大
	w.spread_per_shot = 0.0026
	w.spread_max = 0.060
	w.spread_recovery = 4.0
	w.spread_move_factor = 0.008

	w.recoil_pitch = 0.0075             # 但单发后坐更小，所以连射更稳
	w.recoil_yaw = 0.0045
	w.view_kick = 0.030

	# 模型 Z 范围 -0.222 ~ +0.339，枪口摆到相机前 0.65m
	w.hold_offset = Vector3(0.145, -0.170, -0.428)
	w.hold_rotation_deg = Vector3(0.0, -1.5, 0.0)

	w.mech_fire = {
		"Bolt": [
			[0.000, Vector3.ZERO, Vector3.ZERO],
			[0.020, Vector3(0.0, 0.0, 0.038), Vector3.ZERO],
			[0.058, Vector3.ZERO, Vector3.ZERO],
		],
		"Trigger": [
			[0.000, Vector3.ZERO, Vector3.ZERO],
			[0.015, Vector3.ZERO, Vector3(-13.0, 0.0, 0.0)],
			[0.070, Vector3.ZERO, Vector3.ZERO],
		],
		"Selector": [
			[0.000, Vector3.ZERO, Vector3.ZERO],
			[0.020, Vector3.ZERO, Vector3(0.0, -4.0, 0.0)],
			[0.060, Vector3.ZERO, Vector3.ZERO],
		],
	}

	w.mech_reload = {
		"Magazine": [
			[0.00, Vector3.ZERO, Vector3.ZERO],
			[0.28, Vector3(0.0, -0.140, 0.018), Vector3(0.0, 0.0, 10.0)],
			[0.62, Vector3(0.0, -0.140, 0.018), Vector3(0.0, 0.0, 10.0)],
			[0.90, Vector3.ZERO, Vector3.ZERO],
		],
		"Bolt Release": [
			[0.00, Vector3.ZERO, Vector3.ZERO],
			[0.95, Vector3.ZERO, Vector3.ZERO],
			[1.06, Vector3(0.0, -0.010, 0.0), Vector3.ZERO],
			[1.20, Vector3.ZERO, Vector3.ZERO],
		],
		"Bolt": [
			[0.00, Vector3.ZERO, Vector3.ZERO],
			[0.95, Vector3.ZERO, Vector3.ZERO],
			[1.08, Vector3(0.0, 0.0, 0.038), Vector3.ZERO],
			[1.26, Vector3.ZERO, Vector3.ZERO],
		],
	}
	return w


# -----------------------------------------------------------------------------
# 泵动霰弹枪
# -----------------------------------------------------------------------------
static func _shotgun() -> WeaponData:
	var w := WeaponData.new()
	w.id = &"shotgun"
	w.display_name = "泵动霰弹枪"
	w.model_path = "res://assets/weapons/shotgun_pump.glb"

	w.magazine_size = 6
	w.reserve_ammo = 36
	w.fire_interval = 0.75              # 打一发拉一次泵，慢
	w.reload_time = 3.20
	w.is_automatic = false              # 必须一次一次扣

	w.damage = 13                       # 单颗弹丸伤害
	w.pellets = 8                       # 一发 8 颗，近距离全中 = 104
	w.falloff_start = 8.0               # 霰弹衰减极快
	w.falloff_end = 26.0
	w.falloff_min_mult = 0.10

	w.spread_base = 0.030               # 本身就有锥形散布，准星会明显张开
	w.spread_per_shot = 0.0
	w.spread_max = 0.045
	w.spread_recovery = 6.0
	w.spread_move_factor = 0.0

	w.recoil_pitch = 0.022              # 后坐最大
	w.recoil_yaw = 0.007
	w.view_kick = 0.075

	# 模型 Z 范围 -0.277 ~ +0.319，枪口摆到相机前 0.70m
	w.hold_offset = Vector3(0.150, -0.180, -0.423)
	w.hold_rotation_deg = Vector3(0.0, -1.5, 0.0)

	w.mech_fire = {
		# 抽壳：弹壳弹出 + 托弹板动作
		"Shell": [
			[0.000, Vector3.ZERO, Vector3.ZERO],
			[0.050, Vector3(0.030, 0.055, 0.010), Vector3(0.0, 0.0, -40.0)],
			[0.180, Vector3(0.060, 0.020, -0.030), Vector3(0.0, 0.0, -90.0)],
			[0.200, Vector3.ZERO, Vector3.ZERO],
		],
		"Lifter": [
			[0.000, Vector3.ZERO, Vector3.ZERO],
			[0.060, Vector3(0.0, 0.012, 0.0), Vector3.ZERO],
			[0.220, Vector3.ZERO, Vector3.ZERO],
		],
		"Trigger": [
			[0.000, Vector3.ZERO, Vector3.ZERO],
			[0.020, Vector3.ZERO, Vector3(-12.0, 0.0, 0.0)],
			[0.100, Vector3.ZERO, Vector3.ZERO],
		],
		# 拉泵：打完之后手动推拉，这是泵动枪的灵魂
		"Pump": [
			[0.000, Vector3.ZERO, Vector3.ZERO],
			[0.200, Vector3.ZERO, Vector3.ZERO],
			[0.330, Vector3(0.0, 0.0, 0.078), Vector3.ZERO],
			[0.560, Vector3.ZERO, Vector3.ZERO],
		],
	}

	w.mech_reload = {
		# 装填：泵前后两个位置各塞几发，视觉上像在往弹仓里压弹
		"Pump": [
			[0.00, Vector3.ZERO, Vector3.ZERO],
			[0.30, Vector3(0.0, 0.0, 0.055), Vector3.ZERO],
			[2.60, Vector3(0.0, 0.0, 0.055), Vector3.ZERO],
			[2.95, Vector3.ZERO, Vector3.ZERO],
		],
		"Shell": [
			[0.00, Vector3.ZERO, Vector3.ZERO],
			[0.45, Vector3(0.0, 0.030, 0.0), Vector3.ZERO],
			[0.85, Vector3.ZERO, Vector3.ZERO],
			[1.70, Vector3(0.0, 0.030, 0.0), Vector3.ZERO],
			[2.10, Vector3.ZERO, Vector3.ZERO],
		],
		"Lifter": [
			[0.00, Vector3.ZERO, Vector3.ZERO],
			[1.20, Vector3.ZERO, Vector3.ZERO],
			[1.35, Vector3(0.0, 0.014, 0.0), Vector3.ZERO],
			[1.60, Vector3.ZERO, Vector3.ZERO],
		],
	}
	return w


# -----------------------------------------------------------------------------
# 手枪
# -----------------------------------------------------------------------------
static func _pistol() -> WeaponData:
	var w := WeaponData.new()
	w.id = &"pistol"
	w.display_name = "手枪"
	w.model_path = "res://assets/weapons/pistol_full.glb"

	w.magazine_size = 12
	w.reserve_ammo = 96
	w.fire_interval = 0.150
	w.reload_time = 1.60
	w.is_automatic = false

	w.damage = 26                       # 单发最高，打得准就划算
	w.falloff_start = 20.0
	w.falloff_end = 60.0
	w.falloff_min_mult = 0.55

	w.spread_base = 0.0055
	w.spread_per_shot = 0.0042
	w.spread_max = 0.050
	w.spread_recovery = 4.5
	w.spread_move_factor = 0.012

	w.recoil_pitch = 0.012              # 上跳明显
	w.recoil_yaw = 0.006
	w.view_kick = 0.032

	# 模型 Z 范围 -0.138 ~ +0.081。手枪举得离眼睛近一些，枪口在相机前 0.45m
	w.hold_offset = Vector3(0.100, -0.145, -0.312)
	w.hold_rotation_deg = Vector3(0.0, -2.0, 0.0)

	w.mech_fire = {
		# 套筒往复 + 击锤重新待击，手枪最标志性的两个动作
		"Slide": [
			[0.000, Vector3.ZERO, Vector3.ZERO],
			[0.022, Vector3(0.0, 0.0, 0.036), Vector3.ZERO],
			[0.075, Vector3.ZERO, Vector3.ZERO],
		],
		"Hammer": [
			[0.000, Vector3.ZERO, Vector3.ZERO],
			[0.022, Vector3.ZERO, Vector3(38.0, 0.0, 0.0)],
			[0.080, Vector3.ZERO, Vector3.ZERO],
		],
		"Trigger": [
			[0.000, Vector3.ZERO, Vector3.ZERO],
			[0.018, Vector3.ZERO, Vector3(-16.0, 0.0, 0.0)],
			[0.095, Vector3.ZERO, Vector3.ZERO],
		],
	}

	w.mech_reload = {
		"Magazine": [
			[0.00, Vector3.ZERO, Vector3.ZERO],
			[0.26, Vector3(0.0, -0.115, 0.015), Vector3(0.0, 0.0, 8.0)],
			[0.55, Vector3(0.0, -0.115, 0.015), Vector3(0.0, 0.0, 8.0)],
			[0.80, Vector3.ZERO, Vector3.ZERO],
		],
		# 套筒释放：啪一下复进到位
		"Slide": [
			[0.00, Vector3.ZERO, Vector3.ZERO],
			[0.90, Vector3.ZERO, Vector3.ZERO],
			[1.02, Vector3(0.0, 0.0, 0.036), Vector3.ZERO],
			[1.20, Vector3.ZERO, Vector3.ZERO],
		],
		"Trigger": [
			[0.00, Vector3.ZERO, Vector3.ZERO],
			[1.00, Vector3.ZERO, Vector3.ZERO],
			[1.12, Vector3.ZERO, Vector3(-10.0, 0.0, 0.0)],
			[1.30, Vector3.ZERO, Vector3.ZERO],
		],
	}
	return w
