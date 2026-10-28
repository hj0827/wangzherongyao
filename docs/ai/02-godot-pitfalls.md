# Godot 4.7 与 Windows 环境的坑

> 只在"要跑起来 / 要截图 / 要打包 / 环境报错"时读这份。

---

## 1. 启动方式

```cmd
run.cmd
```

`run.cmd` 里 `GODOT_EXE` 有两条 fallback：

1. `D:\Tools\Godot\Godot_v4.7.2-stable_win64.exe`
2. `D:\Software\Godot\Godot_v4.7-stable_win64.exe`

换机器改这两行之一。手动跑等价于：

```cmd
"D:\Software\Godot\Godot_v4.7-stable_win64.exe" --path godot
```

---

## 2. APPDATA 为空 → `user://` 会污染工程目录

某些终端（尤其是脚本/CI 里拉起的 shell）启动时 `APPDATA` 是空的，Godot 会把 `user://` 退化到**当前工作目录**，在工程里生成 `godot/Godot/app_userdata/`。

**规则**：命令行直接调 `godot` 前，显式设好 APPDATA：

```cmd
if not defined APPDATA set "APPDATA=%USERPROFILE%\AppData\Roaming"
```

`.gitignore` 里已经拦了 `godot/Godot/`，但那只防误提交，不防你被这个目录搞混。

---

## 3. 血条着色器不要"优化"成内置 billboard

`shaders/billboard_bar.gdshader` 在顶点着色器里**手动**实现 billboard，原因写在文件头注释里：

> Godot 4 的 `BaseMaterial3D.BILLBOARD_ENABLED` 会丢弃节点缩放，导致用 `scale.x` 控制血条填充完全失效。

**不要**为了"简化"把它换成 `BaseMaterial3D`。换了之后血条会变成永远满格或永远空，而且不报错。

---

## 4. `.uid` 文件必须跟着源码走

Godot 4.4+ 给每个资源生成 `.uid`（`hero_defs.gd.uid`、`main_menu.tscn.uid`、`blade.png.uid`…）。

- **重命名 / 移动文件时，`.uid` 要一起处理**。
- **不要删 `.uid`**：删了之后其他文件里按 UID 的引用会失效，Godot 会重新分配一个新 UID，引用变成"找不到资源"。
- `.uid` 要入库（它们不是缓存，是资源身份）。

---

## 5. 渲染后端是 gl_compatibility

`project.godot` 里桌面和移动都是 `gl_compatibility`。

- **没有** SDFGI、体积雾、SSAO、SSR。
- 自定义着色器用 `unshaded` + `EMISSION` 最稳，参考 `billboard_bar.gdshader`，以及 `_init_vfx_pools()` 里用 `_make_fx_material()` 一次性建好的材质（池节点各持一份，命中时只改颜色/透明度）——**不要在命中路径上再新建材质**。
- 不要用 Forward+ 才有的特性，本地可能能跑，打包到 Android 直接黑屏。

---

## 6. UI 是 1600×900 + canvas_items + expand

```
window/size/viewport_width=1600
window/size/viewport_height=900
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"
```

**UI 必须用 anchor + offset 相对布局**。写死像素坐标在宽屏/竖屏上会错位。`game_hud.gd` 里大量使用 `anchor_left/top/right/bottom` + `offset_*`，照着这个模式写。

另外：`game_hud.gd` 里几乎每个构建函数都有 `if touch_mode` 分支。**改 UI 必须同时考虑桌面和触控两条路径**，只改一条会在另一种模式下错位。

---

## 7. 战斗场景是代码搭的，不是 `.tscn`

`scenes/` 下只有 `main_menu.tscn` 和 `preview.tscn`。**没有 `match.tscn` 这种东西**，别去找。

战斗场景由 `arena.gd` 的 `_build_staged()` **分帧构建**（每帧做一点，通过 `_emit_build(progress, text)` 上报给加载界面）。想加场景元素，往 `_build_environment()` / `_build_ground()` / `_build_scenery()` 里加。

---

## 8. 对象池的预热常量

```gdscript
const MINION_PREWARM_PER_TEAM := 18
const MINION_POOL_LIMIT := 40
```

`_prewarm_minion_pool()` 在第一波兵线前预实例化。**改小会在首波兵线时卡一下**；改大只是多占内存，通常无害。

`_init_vfx_pools()` 还预热了 `_damage_labels_pool`（Label3D 飘字）与 `_ring_pool`（16 个共享 `TorusMesh` 的范围环）。`_spawn_damage_number()` / `_spawn_ring()` 只从池里借、用完 `visible=false` 放回；池空时抢占最老的活动节点，靠 `generation` 元数据防止同一节点被归还两次。**不要再给这两个函数加 `Label3D.new()` / 新建网格的兜底分支**——那等于把硬规则 4 重新破掉。

---

## 9. `entity.moving` 每 tick 会被统一重置

`match_sim.gd:tick()` 开头：

```gdscript
for entity in state.entities:
    entity.moving = false
```

然后各 `_update_*` 在真正移动时置 `true`。

**加新的移动逻辑时，一定要在移动分支里写 `entity.moving = true`**，否则动画不播（表现层靠这个字段判断跑/站）。

---

## 10. 打包 Android 的三个坑

```cmd
godot --headless --path godot --export-debug "Android" build/android/fenghuo-gorge-debug.apk
:: 导出后必须补 themed icon 并重签名，否则 APK 里 mipmap/themed_icon 引用悬空
cd godot && python tools/fix_apk_theme_icon.py && cd ..
adb install -r build/android/fenghuo-gorge-debug.apk
```

- **`export_presets.cfg` 的 `include_filter` 必须含 `*.ogv`**。否则 APK 里没有背景视频，运行时会**静默回落**成静态图——不报错，只是"主菜单不动了"。
- **Godot 导出不打包 `res/mipmap-anydpi-v26/themed_icon.xml`**，但已编译的 `resources.arsc` 仍引用它（`aapt2 dump` 报 `no such path exists`）。`tools/fix_apk_theme_icon.py` 负责补文件 + `zipalign` + 调试密钥重签名；真机套件的 `BUILD-05` 就是查这件事。
- 产物在 `godot/build/`，**不入库**（约 84MB）。`.gitignore` 已拦。

---

## 11. headless 测试不能碰渲染和音频

```cmd
godot --headless --path godot --script res://tests/run_tests.gd
```

`--headless` 下没有渲染上下文、没有音频设备。测试代码里不许出现 `MeshInstance3D`、`GPUParticles3D`、`AudioStreamPlayer` 的实例化——会崩或静默返回 null。

这也是 `sim/` 必须纯逻辑的原因之一。
