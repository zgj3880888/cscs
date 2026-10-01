extends Node3D
class_name Level
## 关卡生成器
##
## 整个竞技场（地面、围墙、箱子、掩体、中央高台、灯）全部由代码生成。
## 这样做的好处：
##   * 工程 clone 下来直接能跑，不需要任何模型 / 贴图文件
##   * 改布局只要改下面的常量，不用在编辑器里拖节点
##   * 地面网格贴图也是代码画出来的（见 _make_checker_texture）
##
## 想换成自己做的关卡？把 main.tscn 里的 Level 节点换成你的场景，
## 并让它提供 get_player_spawn() 和 get_spawn_points() 两个方法即可。

# ---- 布局参数：想做大地图 / 小地图，改这几个数就行 ----
const ARENA_HALF := 24.0          ## 竞技场半径（米），实际边长 = 2 倍
const WALL_HEIGHT := 6.0
const WALL_THICKNESS := 1.0
const CRATE_COUNT := 22           ## 随机散落的掩体数量
const PILLAR_COUNT := 8
const RANDOM_SEED := 20261001     ## 固定种子，保证每次生成的地图完全一样

const PLATFORM_HALF := 6.0        ## 中央高台半径
const PLATFORM_HEIGHT := 1.4      ## 高台高度
const RAMP_LENGTH := 7.0          ## 坡道斜面长度
const RAMP_WIDTH := 4.0

var _rng := RandomNumberGenerator.new()
var _spawn_points: Array[Vector3] = []

var _mat_floor: StandardMaterial3D
var _mat_wall: StandardMaterial3D
var _mat_crate_a: StandardMaterial3D
var _mat_crate_b: StandardMaterial3D
var _mat_metal: StandardMaterial3D
var _mat_platform: StandardMaterial3D


func _ready() -> void:
	_rng.seed = RANDOM_SEED
	_build_materials()
	_build_floor()
	_build_walls()
	_build_central_platform()
	_build_pillars()
	_build_crates()
	_build_lights()
	_collect_spawn_points()


# =============================================================================
# 对外接口
# =============================================================================

## 玩家出生点。y 只给一点点高度，让玩家轻轻落地而不是从高处砸下来。
func get_player_spawn() -> Vector3:
	return Vector3(0.0, 0.3, 17.0)


## 敌人出生点列表。每波从这里挑，且会尽量避开玩家附近（见 main.gd）。
func get_spawn_points() -> Array[Vector3]:
	return _spawn_points


# =============================================================================
# 生成
# =============================================================================

func _build_floor() -> void:
	var size := Vector3(ARENA_HALF * 2.0, 1.0, ARENA_HALF * 2.0)

	# 让地面顶部正好落在 y = 0
	var body := _add_static_box("Floor", size, Vector3(0.0, -size.y * 0.5, 0.0), _mat_floor)
	body.set_meta("is_floor", true)


func _build_walls() -> void:
	var length := ARENA_HALF * 2.0 + WALL_THICKNESS
	var offset := ARENA_HALF + WALL_THICKNESS * 0.5
	var wall_y := WALL_HEIGHT * 0.5

	var walls: Array[Dictionary] = [
		{"size": Vector3(length, WALL_HEIGHT, WALL_THICKNESS), "pos": Vector3(0.0, wall_y, -offset)},
		{"size": Vector3(length, WALL_HEIGHT, WALL_THICKNESS), "pos": Vector3(0.0, wall_y, offset)},
		{"size": Vector3(WALL_THICKNESS, WALL_HEIGHT, length), "pos": Vector3(-offset, wall_y, 0.0)},
		{"size": Vector3(WALL_THICKNESS, WALL_HEIGHT, length), "pos": Vector3(offset, wall_y, 0.0)},
	]
	for wall in walls:
		_add_static_box("Wall", wall["size"], wall["pos"], _mat_wall)

	# 墙顶一圈压条，视觉上把竞技场"框"住
	var trim_y := WALL_HEIGHT + 0.15
	for side in [-1.0, 1.0]:
		_add_static_box("WallTrim", Vector3(length, 0.35, WALL_THICKNESS + 0.25),
			Vector3(0.0, trim_y, side * offset), _mat_metal)
		_add_static_box("WallTrim", Vector3(WALL_THICKNESS + 0.25, 0.35, length),
			Vector3(side * offset, trim_y, 0.0), _mat_metal)


func _build_central_platform() -> void:
	# 中央高台：给双方一个高低差，让战斗有层次。
	_add_static_box("Platform",
		Vector3(PLATFORM_HALF * 2.0, PLATFORM_HEIGHT, PLATFORM_HALF * 2.0),
		Vector3(0.0, PLATFORM_HEIGHT * 0.5, 0.0),
		_mat_platform)

	# 四条坡道，从四个方向通向高台。
	# 注意：这里显式用「先绕 X 轴倾斜，再绕 Y 轴旋转」的基向量相乘，
	# 而不是靠欧拉角赋值 —— 欧拉角顺序容易搞反，显式相乘没有歧义。
	var tilt := asin(PLATFORM_HEIGHT / RAMP_LENGTH)
	var horizontal_span := RAMP_LENGTH * cos(tilt)
	var ramp_center_dist := PLATFORM_HALF + horizontal_span * 0.5

	for i in 4:
		var yaw := float(i) * PI * 0.5
		var outward := Vector3(sin(yaw), 0.0, cos(yaw))  # 该方向朝外
		var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt)
		_add_static_box_with_basis(
			"Ramp",
			Vector3(RAMP_WIDTH, 0.3, RAMP_LENGTH),
			Transform3D(basis, Vector3(
				outward.x * ramp_center_dist,
				PLATFORM_HEIGHT * 0.5,
				outward.z * ramp_center_dist
			)),
			_mat_platform
		)

	# 高台边缘的矮墙，给玩家当掩体
	var cover_radius := PLATFORM_HALF - 0.5
	for i in 4:
		var yaw := float(i) * PI * 0.5 + PI * 0.25
		var outward := Vector3(sin(yaw), 0.0, cos(yaw))
		var basis := Basis(Vector3.UP, yaw)
		_add_static_box_with_basis(
			"Cover",
			Vector3(2.6, 0.9, 0.4),
			Transform3D(basis, Vector3(
				outward.x * cover_radius,
				PLATFORM_HEIGHT + 0.45,
				outward.z * cover_radius
			)),
			_mat_metal
		)


func _build_pillars() -> void:
	for i in PILLAR_COUNT:
		var angle := TAU * float(i) / float(PILLAR_COUNT) + 0.37
		var radius := _rng.randf_range(9.5, 18.0)
		var height := _rng.randf_range(3.2, WALL_HEIGHT - 0.6)
		var body := _add_static_box(
			"Pillar",
			Vector3(1.2, height, 1.2),
			Vector3(sin(angle) * radius, height * 0.5, cos(angle) * radius),
			_mat_metal
		)
		body.rotation.y = _rng.randf_range(0.0, TAU)


func _build_crates() -> void:
	for i in CRATE_COUNT:
		var angle := _rng.randf_range(0.0, TAU)
		# 避开中央高台区域
		var radius := _rng.randf_range(8.5, ARENA_HALF - 1.5)
		var size_x := _rng.randf_range(1.0, 2.4)
		var size_z := _rng.randf_range(1.0, 2.4)
		var height := _rng.randf_range(0.9, 2.6)
		var material := _mat_crate_a if i % 2 == 0 else _mat_crate_b

		var crate_pos := Vector3(sin(angle) * radius, height * 0.5, cos(angle) * radius)
		var crate := _add_static_box("Crate", Vector3(size_x, height, size_z), crate_pos, material)
		crate.rotation.y = _rng.randf_range(0.0, TAU)

		# 大约三分之一的箱子上面再叠一个小的，掩体更有层次
		if i % 3 == 0:
			var stacked_height := _rng.randf_range(0.6, 1.1)
			var stacked := _add_static_box(
				"CrateSmall",
				Vector3(size_x * 0.62, stacked_height, size_z * 0.62),
				crate_pos + Vector3(
					_rng.randf_range(-0.25, 0.25),
					height * 0.5 + stacked_height * 0.5,
					_rng.randf_range(-0.25, 0.25)
				),
				material
			)
			stacked.rotation.y = _rng.randf_range(0.0, TAU)


func _build_lights() -> void:
	# 四盏有色点光：给方块场景一点氛围，同时帮玩家判断纵深和方位。
	var light_specs: Array[Dictionary] = [
		{"pos": Vector3(-13.0, 5.0, -13.0), "color": Color(0.35, 0.55, 1.0)},
		{"pos": Vector3(13.0, 5.0, 13.0), "color": Color(1.0, 0.5, 0.3)},
		{"pos": Vector3(-13.0, 5.0, 13.0), "color": Color(0.4, 1.0, 0.7)},
		{"pos": Vector3(13.0, 5.0, -13.0), "color": Color(0.9, 0.4, 1.0)},
	]
	for spec in light_specs:
		var light := OmniLight3D.new()
		light.position = spec["pos"]
		light.light_color = spec["color"]
		light.light_energy = 3.2
		light.omni_range = 22.0
		light.shadow_enabled = false  # 点光阴影在手机上太贵，关掉
		add_child(light)


func _collect_spawn_points() -> void:
	_spawn_points.clear()
	# 沿着围墙内侧均匀布一圈出生点。
	var count := 16
	var radius := ARENA_HALF - 3.0
	for i in count:
		var angle := TAU * float(i) / float(count)
		_spawn_points.append(Vector3(sin(angle) * radius, 0.3, cos(angle) * radius))


# =============================================================================
# 建方块的工具函数
# =============================================================================

## 生成一个静态方块（碰撞体 + 可见网格），用位置和 Y 轴旋转放置。
func _add_static_box(node_name: String, size: Vector3, pos: Vector3, material: Material) -> StaticBody3D:
	return _add_static_box_with_basis(node_name, size, Transform3D(Basis.IDENTITY, pos), material)


## 用完整的 Transform3D 放置，适合需要倾斜的物体（坡道）。
func _add_static_box_with_basis(
	node_name: String,
	size: Vector3,
	transform: Transform3D,
	material: Material
) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = GameConfig.LAYER_WORLD
	body.collision_mask = 0
	body.transform = transform

	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)

	var mesh_instance := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh_instance.mesh = box_mesh
	mesh_instance.material_override = material
	body.add_child(mesh_instance)

	add_child(body)
	return body


# =============================================================================
# 材质
# =============================================================================

func _build_materials() -> void:
	_mat_floor = _make_material(Color(0.16, 0.17, 0.21), 0.85)
	# 地面铺程序生成的棋盘格：纯色地面在 3D 里没有参照物，加了格子才能感知移动。
	_mat_floor.albedo_texture = _make_checker_texture(
		64, 8, Color(0.155, 0.165, 0.205), Color(0.205, 0.215, 0.26)
	)
	_mat_floor.uv1_scale = Vector3(ARENA_HALF * 0.5, ARENA_HALF * 0.5, 1.0)

	_mat_wall = _make_material(Color(0.24, 0.25, 0.30), 0.9)
	_mat_crate_a = _make_material(Color(0.45, 0.36, 0.24), 0.8)
	_mat_crate_b = _make_material(Color(0.34, 0.40, 0.46), 0.8)
	_mat_metal = _make_material(Color(0.30, 0.32, 0.37), 0.45, 0.6)
	_mat_platform = _make_material(Color(0.20, 0.23, 0.28), 0.8)


func _make_material(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material


## 代码画一张棋盘格贴图，不依赖任何图片文件。
func _make_checker_texture(size: int, cells: int, color_a: Color, color_b: Color) -> ImageTexture:
	var image := Image.create(size, size, true, Image.FORMAT_RGB8)
	var cell_size := maxi(int(float(size) / float(cells)), 1)
	for y in size:
		for x in size:
			var cell := int(float(x) / float(cell_size)) + int(float(y) / float(cell_size))
			image.set_pixel(x, y, color_a if cell % 2 == 0 else color_b)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)
