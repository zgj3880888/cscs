# MobileFPS — 手机 3D 第一人称射击模板

用 **Godot 4.7.2** 写的安卓 FPS 起步工程。手机上虚拟摇杆操作，电脑上鼠标键盘操作，**同一套代码同一个关卡**。

推到 GitHub 之后由云端自动构建出 **APK**，本地不需要装 Android Studio、不需要装 JDK、不需要下载 5GB 的 SDK。

---

## 一、这个工程现在就能玩到什么

不是"Hello World"，是一个能完整游玩的游戏循环：

| 系统 | 状态 |
|---|---|
| 第一人称移动 | 走 / 跑 / 跳，带空中控制、贴地吸附、头部晃动 |
| **手机触屏操作** | 左半屏动态虚拟摇杆、右半屏拖拽转身、开火 / 跳跃 / 换弹 / **换枪**按钮，**支持多点触控** |
| 射击 | 射线命中、动态散布、后坐力、枪口火光、弹孔、命中火花、距离伤害衰减 |
| **武器** | **4 把枪**（步枪 / 冲锋枪 / 霰弹枪 / 手枪），各自独立的弹匣与备弹、**全自动与半自动区分**、切枪动作、空仓自动换弹 |
| **第一人称枪械动画** | 待机呼吸、走动摇摆、转身拖拽滞后、开火后坐、换弹下沉、切枪举起；**枪机 / 拉机柄 / 弹匣 / 套筒 / 击锤 / 泵 / 抛壳**都是真的在动（骨骼级动画，不是整体晃） |
| **敌人** | 带骨骼与 76 个动画的 CC0 角色模型（骑士 / 野蛮人）；**待机、奔跑、挥剑、受击、倒地**五个动作按状态切换，奔跑动画速度跟着实际移速走（脚不打滑），挥剑伤害在动画 45% 那一帧才结算（会走位能躲） |
| 波次 | 敌人分批刷新、间隔补给、逐波变难，血量越高敌人越偏红 |
| HUD | 动态准星（随真实散布张开）、命中标记、血条、弹药、**当前武器名**、分数、波次剩余数 |
| 反馈 | 受伤红屏、低血量脉冲、镜头震动、换弹进度条 |
| 菜单 | 暂停 / 灵敏度调节（**会记住**）/ 结算界面 / 重开 |
| 关卡 | 48×48 米竞技场：围墙、中央高台、四条坡道、掩体、箱子、立柱 |

### 素材来源与授权（重要）

枪械和角色模型**不是**从商业游戏里扒的，全部来自明确标注 **CC0 / 公有领域** 的免费素材包，可商用、无需署名、无需付费：

| 内容 | 来源 | 授权 |
|---|---|---|
| 4 把枪的模型（含机械骨骼） | [`petroulacl/fps-asset-kit`](https://github.com/petroulacl/fps-asset-kit) | CC0 |
| 骑士 / 野蛮人角色（含 76 个动画） | [`KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0`](https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0) | CC0 |

原始授权文件已一并放进 `assets/licenses/`，自行核对。**其余全部内容**（地面棋盘格贴图、所有 UI、弹孔、枪口火光、关卡几何）仍然是代码生成的，没有一个额外资源文件。

> 想换成自己买的模型？把 `weapon_data.gd` / `enemy.gd` 里的 `model_path` 指向你的 `.glb` 即可，其余代码不用动。


---

## 二、拿到 APK：三步

### 第 1 步：建一个 GitHub 仓库

在 GitHub 上新建一个**空的**仓库（不要勾选 README / .gitignore，保持全空）。

### 第 2 步：把工程推上去

工程里的本地 Git 仓库**已经初始化好并完成首次提交了**，你只需要接上远程地址再推：

```bash
git remote add origin https://github.com/你的用户名/你的仓库名.git
git push -u origin main
```

就这两行。`git init` / `git add` / `git commit` 都已经做过了，不用重来。

> **提交署名**：首次提交用的是占位的 `MobileFPS <mobilefps@users.noreply.github.com>`。
> 想换成你自己的，先设置再改署名（此时还没推送，改起来是干净的）：
>
> ```bash
> git config user.name "你的名字"
> git config user.email "你的邮箱@example.com"
> git commit --amend --reset-author --no-edit
> git tag -f -a v1.0.0 -m "MobileFPS v1.0.0"   # 提交变了，标签要跟着重打
> ```
>
> 不改也完全不影响构建，只是提交历史里的作者名不好看。

### 第 3 步：等构建完成，下载 APK

推送完成后，打开仓库页面的 **Actions** 标签，会看到一个叫「构建游戏」的任务在跑，大约 **4～6 分钟**。

跑完点进去，**页面底部 Artifacts** 区域有两个下载项：

- **MobileFPS-构建产物** ← 里面就是 `MobileFPS.apk`（手机装这个）和 `MobileFPS.exe`（电脑试玩用）

> 注意：Artifacts 里的文件是压缩包，下载后需要**先解压**再传到手机。

**想要永久下载链接？** 打一个标签就会自动发 Release。

这个工程的本地仓库**已经建好了**，`v1.0.0` 标签也**已经打好了**（指向首次提交）。所以你只要在推完代码之后，把这个标签也推上去：

```bash
git push origin v1.0.0
```

云端会再跑一次构建，这次会额外在 **Releases** 页面生成一个版本，附件就是 APK 和 Windows 版，**下载链接不会过期**。

> 标签必须先推分支、再推标签。只推标签而分支上没有对应提交的话，Releases 页面点进源码会 404。

以后发新版本，改完 `export_presets.cfg` 里的 `version/name` 和 `version/code`，然后：

```bash
git add . && git commit -m "修了 xxx"
git tag -a v1.0.1 -m "v1.0.1"
git push origin main && git push origin v1.0.1
```

> `version/code` 每次发版**必须递增**（1、2、3…），否则手机会拒绝安装新包，或者把新包当成旧包不更新。

---

## 三、装到手机上

1. 把 `MobileFPS.apk` 传到手机（数据线、微信文件传输、网盘都行）
2. 手机上点开这个文件安装
3. 系统会提示「**未知来源应用**」——需要在弹出的提示里允许你的文件管理器安装应用。这是所有非商店渠道 APK 的正常流程，不是报错
4. 装好后桌面出现图标，**横屏**打开

### 操作说明（手机）

| 操作 | 手势 |
|---|---|
| 移动 | 左半屏任意位置按下并拖动（摇杆基座会出现在你按下的地方） |
| 冲刺 | 摇杆推到底 |
| 转身 / 抬枪 | 右半屏拖动 |
| 开火 | 右下角「开火」按钮。步枪 / 冲锋枪按住连发，霰弹枪 / 手枪一次一扣 |
| 跳跃 | 「跳跃」按钮 |
| 换弹 | 「换弹」按钮（打空时开火会自动换） |
| 换枪 | 「换枪」按钮，循环切到下一把 |
| 暂停 | 右上角「暂停」按钮 |

三根手指可以同时用：左手推摇杆、右手划屏幕转身、同时按开火。

### 操作说明（电脑，Windows 试玩版）

| 操作 | 按键 |
|---|---|
| 移动 | `W` `A` `S` `D` |
| 视角 | 鼠标（进游戏后鼠标会被锁定） |
| 开火 | 鼠标左键 |
| 跳跃 | `空格` |
| 冲刺 | `Shift` |
| 换弹 | `R` |
| 切枪（直选） | `1` `2` `3` `4` |
| 切枪（循环） | `Q` / 鼠标滚轮 |
| 暂停 | `Esc`（会释放鼠标） |

手柄的移动和动作键已经绑好了（左摇杆移动、`RT` 开火、`X` 换弹、十字键左右切枪），但**右摇杆转视角还没做** —— 需要的话在 `player.gd` 的 `_apply_look()` 里读 `JOY_AXIS_RIGHT_X/Y` 补上即可。

---

## 四、在电脑上改代码

1. 去 <https://godotengine.org/download> 下载 **Godot 4.7.2**（标准版，不是 .NET 版）
2. 它是绿色软件，解压后双击运行
3. 点「导入」→ 选中本目录的 `project.godot` → 打开
4. 按 **F5** 直接运行调试

改完代码推送到 GitHub，云端会自动重新构建。

---

## 五、工程结构

```
MobileFPS/
├── project.godot                 工程配置（渲染器、分辨率、自动加载）
├── export_presets.cfg            导出预设：Android + Windows 桌面
├── icon.svg                      工程图标（矢量，代码无关）
├── .github/workflows/build.yml   云端构建流程（含无头自检）
├── assets/                       CC0 素材（枪械模型 + 角色模型 + 授权文件）
│   ├── weapons/                  4 把枪的 .glb，自带机械骨骼
│   ├── characters/               骑士 / 野蛮人 .glb，各带 76 个动画
│   └── licenses/                 素材原始授权文件
├── scenes/
│   ├── main.tscn                 主场景：太阳光 + 关卡 + 敌人容器
│   ├── player.tscn               玩家：胶囊碰撞 + 头部 + 摄像机 + 武器挂点
│   ├── enemy.tscn                敌人（外观在代码里装配）
│   ├── hud.tscn                  HUD 层
│   └── touch_controls.tscn       触屏操作层
├── tools/
│   ├── selftest.gd               无头自检（不参与正式游戏，也不打进 APK）
│   └── selftest.tscn
└── scripts/
    ├── game_config.gd    ★ 自动加载：所有手感参数 + 输入映射注册
    ├── game_state.gd     ★ 自动加载：分数 / 波次 / 设置持久化
    ├── main.gd             总控：流程、波次、暂停、重开
    ├── player.gd           玩家控制器（移动 / 视角 / 生命）
    ├── weapon_data.gd    ★ 武器定义表：4 把枪的全部数值 + 机械动作时间轴
    ├── weapon.gd           武器逻辑：弹药、射速、换弹、射线命中、切枪
    ├── weapon_view.gd    ★ 第一人称武器视图：骨骼机械动画 + 整枪姿态动作
    ├── character_rig.gd  ★ 角色装配：加载模型、自动缩放、状态动画、材质
    ├── enemy.gd            敌人 AI（用 character_rig 当外观）
    ├── level.gd            关卡生成
    ├── hud.gd              HUD、暂停菜单、结算界面
    ├── touch_controls.gd   虚拟摇杆与按钮
    ├── crosshair.gd        动态准星
    └── impact.gd           弹孔与命中火花
```

**武器系统是数据驱动的**，这是整个工程里最值得学的一处设计。一把枪被拆成三层：

| 层 | 文件 | 管什么 |
|---|---|---|
| 数据 | `weapon_data.gd` | 弹匣容量、射速、伤害、散布、后坐、握持姿势、**机械动作时间轴** |
| 逻辑 | `weapon.gd` | 弹药状态、冷却、换弹、射线命中、切枪流程 |
| 画面 | `weapon_view.gd` | 模型、骨骼动画、整枪姿态（呼吸 / 摆动 / 后坐 / 换弹下沉 / 举枪） |

**想加第 5 把枪，只要在 `weapon_data.gd` 的 `build_all()` 里追加一条定义，其余代码一行都不用动。**

其中有一个坑值得单独说：枪模型的每根骨骼**局部坐标轴方向都不一样**（实测步枪 `Body` 的局部 Y 轴指向枪口，而 `Magazine` 的局部 Z 轴指向枪口）。所以时间轴里写的位移量是**模型空间**的方向，`weapon_view.gd` 会先换算到父骨骼空间：

```gdscript
local_dir = 父骨骼静止基向量的逆 × 模型空间方向
```

不这么做就得给每根骨骼手工配轴，换一把枪就要重配一遍。`tools/selftest.gd` 里有一段专门验证这个换算：开火时枪机只能沿枪管方向往复，如果零件斜着飞，说明换算写错了。


有一个设计决定值得说明：**输入映射不写在 `project.godot` 里，而是 `game_config.gd` 在运行时用 `InputMap` 注册**。原因是 `project.godot` 里存输入事件用的是引擎内部的序列化格式，跨 Godot 版本容易失效；用代码注册更稳、更好读、diff 也更清楚。

同理，触屏按钮不是直接改游戏状态，而是通过 `Input.action_press("fire")` 把它翻译成普通的输入动作。所以 `player.gd` 和 `weapon.gd` 里**完全没有**"判断是不是手机"的代码——它们只管读输入动作，手机和电脑走的是同一条路径。

---

## 六、调参速查

**九成的手感调整都在 `scripts/game_config.gd` 顶部**，全是带注释的常量：

```gdscript
const MOVE_SPEED := 6.0              # 移动速度（米/秒）
const JUMP_VELOCITY := 7.6           # 跳跃高度
const GRAVITY := 22.0                # 重力
const AIR_CONTROL := 0.35            # 空中控制力（0=完全不能转向）
const MOUSE_SENSITIVITY := 0.0022    # 电脑鼠标灵敏度
const TOUCH_LOOK_SENSITIVITY := 0.0040  # 手机拖屏灵敏度
const PLAYER_MAX_HEALTH := 100
const ENEMIES_BASE_PER_WAVE := 4     # 第一波敌人数
const ENEMIES_PER_WAVE_STEP := 2     # 每波递增
```

其他地方：

| 想改什么 | 去哪改 |
|---|---|
| **枪的手感**（射速、伤害、散布、弹匣、后坐力、握持位置） | `weapon_data.gd` 里对应那把枪的函数 |
| **枪的机械动作**（哪个零件怎么动、动多久） | `weapon_data.gd` 里那把枪的 `mech_fire` / `mech_reload` 时间轴 |
| **整枪姿态手感**（呼吸、摆动、后坐回落、换弹下沉幅度） | `weapon_view.gd` 顶部常量 |
| **角色动画**（换动作、奔跑动画速度范围、受击僵直） | `character_rig.gd` 顶部常量 |
| 敌人身高（主角模型是夸张比例，靠自动缩放拉齐） | `character_rig.gd` 的 `TARGET_HEIGHT` |
| 地图大小、掩体数量、高台尺寸 | `level.gd` 顶部的常量 |
| 敌人速度、血量、攻击力、出手频率 | `enemy.gd` 顶部的常量 |
| 换个地图布局 | 改 `level.gd` 的 `RANDOM_SEED`，地图会整体重排 |
| 渲染画质 / 兼容性 | `project.godot` 的 `renderer/rendering_method` |
| 应用名、包名、版本号 | `export_presets.cfg` |

### 改完代码先跑自检

工程带一个无头自检，能把你肉眼很难发现的问题挡在前面（比如"时间轴里骨骼名拼错了""角色缩放算错了"）：

```bash
godot --headless --fixed-fps 60 --path . res://tools/selftest.tscn
```

全过退出码是 `0`，有失败项是 `1`（失败项会逐条列出来）。CI 里也跑了这一步，**自检不过就不会出 APK**。

**关于渲染器**：现在用的是 `gl_compatibility`（OpenGL ES 3.0），这是**兼容性最好**的选择，老手机也能跑，代价是画质一般。如果你的目标手机都比较新，改成 `mobile`（基于 Vulkan）能明显提升光影效果：

```ini
renderer/rendering_method="mobile"
renderer/rendering_method.mobile="mobile"
```

---

## 七、发布前必须改的三件事

现在这个工程是**调试版**，自己玩没问题，但上架前必须处理：

**1. 改包名**（不改无法上架）
`export_presets.cfg` 里的 `package/unique_name="com.example.mobilefps"` 改成你自己的域名倒写，比如 `com.yourname.yourgame`。包名一旦上架就不能改了。

**2. 换成正式签名**
现在的 APK 用 debug 密钥签名，只能自己装。上架需要生成你自己的发布密钥，然后：

- 生成密钥库（本地执行一次，**这个文件丢了就永远无法更新你的应用，务必备份**）：
  ```bash
  keytool -genkeypair -v -keystore release.keystore -alias mykey \
          -keyalg RSA -keysize 2048 -validity 10000
  ```
- 把密钥库转成 base64：`base64 -w0 release.keystore`
- 在 GitHub 仓库的 **Settings → Secrets and variables → Actions** 里新建密钥存进去
- 在 `export_presets.cfg` 里填 `keystore/release`、`keystore/release_user`、`keystore/release_password`
- 把 CI 里的 `--export-debug` 改成 `--export-release`

**3. 换图标**
现在是 Godot 默认图标。Android 需要 192×192 和自适应图标（432×432 前景 + 背景），导出预设里的 `launcher_icons/*` 填上对应的 png 即可。

---

## 八、已知限制

- **渲染器是兼容模式**，光影比较朴素。想变好看就切 `mobile` 渲染器
- **敌人是直线追击**，靠物理碰撞绕开障碍。障碍物复杂的地图会卡住。想升级成真正的寻路，把 `enemy.gd` 的 `_steer()` 里的方向换成 `NavigationAgent3D` 的输出即可（需要在关卡里烘焙导航网格）
- **没有音效**。工程刻意不带音频文件。加音效的话，放 `.wav` 到工程里，用 `AudioStreamPlayer3D` 播放（枪声挂在 `weapon.gd` 的 `_fire()` 里、命中挂在 `_spawn_impact()` 里最省事）
- **角色模型带了一整套道具**（骑士右手挂 2 把剑、左手挂 4 个盾）。`character_rig.gd` 的做法是"每只手只留第一件，其余隐藏"。想要大盾配长剑这类组合，改 `_clean_up_props()` 的取舍规则
- **敌人只有一种攻击方式**（近身挥剑）。`enemy.gd` 是自带参数的单体，加远程敌人最直接的做法是复制一份改参数
- **右摇杆视角没做**，手柄只能移动和按动作键（见上文）
- **没有存档以外的持久化**，只有最高分和灵敏度会保存（存在 `user://settings.cfg`）

---

## 九、常见问题

**Q：Actions 里构建失败了怎么办？**

点开失败的步骤看日志。最可能的原因是：

- **`无头自检` 这一步失败** —— 说明改坏了武器 / 角色 / 数值表。日志里每一条失败项前面都是 `✗`，本地跑同一条命令即可复现（见「六、调参速查」末尾）
- **`Invalid export preset name`** —— `export_presets.cfg` 里的预设名被改了。CI 里用的名字必须和文件里的 `name=` 完全一致（`Android` 和 `Windows Desktop`）
- **`Unable to open Android 'build-tools' directory`** —— Android SDK 没配好。检查「准备 Android SDK 组件」那一步有没有报错
- **`APK 没有生成`** —— 看上面「导出 Android APK」那一步的完整输出
- **`ETC2/ASTC texture compression is required for Android export`** —— `project.godot` 里的 `textures/vram_compression/import_etc2_astc=true` 被删了。这一项**本地在 Windows 上导出时不会报错**，只有 Linux 构建机上才暴露，所以别删

**Q：为什么 CI 里不需要装 Android Studio？**

因为用了 `gradle_build/use_gradle_build=false`——直接用 Godot 自带的预编译 APK 模板，只需要 SDK 里的 `build-tools` 来签名。代价是不能写自定义安卓插件（Java/Kotlin）。将来要接广告、支付、推送这类需要原生代码的 SDK 时，把它改成 `true` 并补上 Gradle 步骤。

**Q：为什么自检脚本不能写成 `extends SceneTree` + `--script` 直接跑？**

因为在 `--script` 模式下 autoload 虽然会被实例化，但**不会注册成编译期标识符**，`player.gd` 里写着的 `GameConfig` 会直接编译失败，整条链路全崩。所以自检改成"把 `tools/selftest.tscn` 当主场景跑"，这样 autoload 的解析方式和真机完全一致；再配合 `--fixed-fps 60`，帧号和秒数严格对应，按帧号写的时间轴才可预测。

**Q：手机上摇杆位置不顺手？**

改 `scripts/touch_controls.gd` 的 `_relayout()`。里面按屏幕短边做缩放，`margin` 控制按钮离边缘的距离，`base_radius` 控制按钮大小。

**Q：改完代码本地跑没问题，但云构建出来的 APK 行为不一样？**

先确认推的是同一个分支。`.godot/` 目录是导入缓存，被 `.gitignore` 排除了，云端会重新生成——这是正常的，不影响行为。

---

## 十、下一步可以做什么

按性价比排序：

1. **加音效** —— 开枪、命中、敌人死亡的反馈，对"手感"的提升比画面大得多
2. **加第 5 把枪** —— 在 `weapon_data.gd` 的 `build_all()` 里追加一条定义（数值 + 机械动作时间轴），其他代码不用动
3. **给枪配瞄准镜（ADS）** —— 在 `weapon_view.gd` 的 `_apply_pose()` 里加一条"按右键时把 `hold_offset` 往相机中心插值"即可
4. **捡拾 / 补给** —— 敌人掉落弹药和血包，关卡里放拾取物
5. **做自己的关卡** —— 用 Godot 编辑器手搓场景，替换 `main.tscn` 里的 `Level` 节点，只要新场景提供 `get_player_spawn()` 和 `get_spawn_points()` 两个方法就行
6. **换更多角色 / 换枪模型** —— 从 KayKit、Quaternius、poly.pizza 这些站找 CC0 的 glTF，替换 `model_path`。注意角色模型的动画名要在 `character_rig.gd` 顶部对上号
7. **接存档 / 排行榜** —— 需要后端的话，可以用云数据库存分数

---

Godot 版本：4.7.2-stable ｜ 导出目标：Android (arm64-v8a) + Windows x86_64
