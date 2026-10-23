# 真机测试（Android）

> 只在"打包后验收 / 触摸、视频、生命周期、联机出问题"时读这份。
> headless 测试证明逻辑对；这份证明**装到手机上以后那一层真的在跑**。

---

## 1. 为什么必须真机

headless 跑 `run_tests.gd` 时没有真实 GPU、解码器、触摸屏和系统栏，下列能力**完全测不到**：

| 能力 | headless 的状态 | 真机检验点 |
| --- | --- | --- |
| Ogg Theora 视频 | 不加载、不解码 | 菜单背景 / 英雄展示视频是否出帧、是否卡死 |
| 渲染与着色器 | 空渲染器 | gl_compatibility 下 HUD、3D、血条是否正常 |
| 触摸与拖拽 | 无输入设备 | 技能弧、摇杆、拖拽施法、取消区 |
| 多点触控 | 无法注入 | 摇杆 + 技能同时按、双指缩放 |
| 刘海 / 圆角 / 沉浸式 | 无窗口装饰 | 控件是否被切、状态栏是否隐藏 |
| HOME / 锁屏 / 恢复 | 无 Activity 生命周期 | 回前台后对局是否还在 |
| 音频 | 无输出设备 | 背景视频原声、技能音、静音策略 |
| 真实局域网 | 只能跑本机回环 | 第二台手机加入、延迟、断线重连 |
| 性能 / 温度 / 内存 | 无真实帧率 | 5v5 团战帧率、PSS、长时间发热 |
| 打包产物 | 不经过 APK | 签名、ABI、图标、权限、logcat 崩溃 |

---

## 2. 环境与命令

| 项 | 值 |
| --- | --- |
| 测试机 | vivo V2220A，2388×1080，480dpi（虚拟画布 1990×900） |
| 序列号 | `10AC9J0VZA0011K`（或设置 `ANDROID_SERIAL`） |
| 包名 / Activity | `com.fenghuoxiagu.game` / `com.godot.game.GodotAppLauncher` |
| APK | `godot/build/android/fenghuo-gorge-debug.apk` |
| 报告 | `godot/shots/device_checks/<时间戳>/report.json` + 截图 |

```cmd
:: 0) 逻辑基线（必须全绿）
godot --headless --path godot --script res://tests/run_tests.gd

:: 1) 重新导出（改了脚本 / UI / 资源后必须重打，旧 APK 不算数）
godot --headless --path godot --export-debug "Android" build/android/fenghuo-gorge-debug.apk

:: 1.5) 补齐 Godot 导出漏掉的 themed icon 并重签名（BUILD-05 会校验）
cd godot
python tools/fix_apk_theme_icon.py
cd ..

:: 2) 安装（vivo 可能弹"未知来源"，需在手机上手动确认一次）
adb install -r build/android/fenghuo-gorge-debug.apk

:: 3) 全局真机检查（从 godot 目录运行）
cd godot
python tools/device_checks.py
```

`device_checks.py` 用 ADB + 截图 + 像素差 + logcat 做黑盒验证，不改游戏代码。退出码 `0` = 无 FAIL；`1` = 有 FAIL；`2` = 静态检查就失败。

---

## 3. 自动化用例

### 3.1 构建 / 环境 / 布局

| ID | 场景 | 步骤 | 通过标准 |
| --- | --- | --- | --- |
| ENV-01 | ADB 设备在线 | `adb devices` | 序列号可见 |
| BUILD-01 | APK 与导出版本一致 | 读 APK / export_presets / 设备已装版本 | 版本号一致 |
| BUILD-02 | ABI / minSdk | `aapt2 dump badging` | 含 arm64-v8a，minSdk 符合预设 |
| BUILD-03 | 联机权限 | 读 manifest | INTERNET / ACCESS_NETWORK_STATE 等齐全 |
| BUILD-04 | 签名有效 | `apksigner verify` | 校验通过 |
| BUILD-05 | 自适应 / themed 图标 | 解包 `icon.xml`、`themed_icon.xml` + 资源表 | adaptive-icon 三层齐全且指向已打包资源；`themed_icon.xml` 存在（导出后需跑 `fix_apk_theme_icon.py`） |
| BUILD-06 | 视频打进包 | 读 APK zip | 5 个 `.ogv` ≥1MiB |
| UI-01 | 技能键不压功能键 | 静态几何 | Q/W/E/R 与回城/传送/召唤师无矩形重叠 |
| UI-02 | 触控键不出屏 | 静态几何 | 全部落在 2388×1080 内 |
| DISP-01 | 分辨率 / 密度 | `wm size` / `wm density` | 1080×2388 @480dpi |

### 3.2 启动与窗口

| ID | 场景 | 通过标准 |
| --- | --- | --- |
| LAUNCH-01 | 冷启动进主菜单 | Activity 前台 + 菜单识别 |
| DISP-02 | 屏幕常亮 | `FLAG_KEEP_SCREEN_ON` 生效 |
| DISP-03 | 沉浸式全屏 | 状态栏/导航栏隐藏 |
| DISP-04 | 绘制进刘海区 | layoutInDisplayCutoutMode 生效 |
| DISP-05 | 横屏锁定 | requestedOrientation 为 landscape |
| DISP-06 | 帧缓冲与窗口一致 | 截图尺寸 = 物理分辨率 |
| DISP-07 | 安全区 / 圆角 | 控件不压刘海；圆角裁切只允许 cosmetic WARN |
| SAFE-01/02 | 对局内安全区 | 小地图/摇杆/攻击/技能/暂停不压刘海或圆角 |

### 3.3 视频（真机专属重点）

| ID | 场景 | 步骤 | 通过标准 |
| --- | --- | --- | --- |
| VIDEO-01 | 菜单背景视频 | 主菜单间隔 2s 截两帧 | 大区域像素差 >2.0 |
| VIDEO-03 | 视频流已加载 | logcat 查 `[background] video:` | 有加载行 |
| VIDEO-02 | 选中英雄展示视频 | 1v1 选人页间隔 2s 截两帧 | 第一张卡区域像素差 >2.0 |
| VIDEO-04 | 换英雄换视频 | 点第二张卡后同样采样 | 第二张卡区域像素差 >2.0 |

> 只看"画面在动"不够：VIDEO-03 证明资源加载，VIDEO-01/02/04 证明解码后确实上屏。两者要一起看。

### 3.4 导航 / 返回

| ID | 场景 | 通过标准 |
| --- | --- | --- |
| NAV-01/02 | 菜单 → 1v1 选人；点卡切换 | 选人页识别；卡片区域变化 |
| NAV-03 | 选人页返回菜单 | 菜单识别 |
| NAV-04/05/06 | 菜单 → 2P 联机 → 返回 | 页面识别正确 |
| NAV-07/08/09 | 创建房间 → 大厅 → 复制房号 → 离开 | 大厅识别；复制有反馈；离开回联机页 |
| BACK-01..05 | 硬件 BACK：选人 / 联机 / 大厅 / 对局 / 暂停 | 返回目标页；对局中 BACK 只开暂停，不退出应用 |

### 3.5 对局触控与 HUD

| ID | 场景 | 步骤 | 通过标准 |
| --- | --- | --- | --- |
| MATCH-01 | 进入 1v1 | 菜单 → 选人 → 确认 | 对局页识别 |
| HUD-01..07 | 小地图/摇杆/攻击/技能弧/暂停/比分/48dp | 截图 + 颜色/亮度统计 | 全部锚点正确，触摸目标 ≥48dp |
| INTEL-01/02 | 点小地图开情报；点 × 关闭 | 面板区域像素差 >2.0 |
| SHOP-01 | 商店按钮开面板 | 面板区域差 >3.0 |
| SHOP-02 | 快捷购买 | 面板有变化（金币不足时允许 WARN） |
| SHOP-03 | 关闭按钮回对局 | 面板区域差 >3.0 |
| ATK-01/02/03 | 补刀 / 推塔 / 常规模式 | 攻击键簇有变化 |
| CAST-01 | Q 按下并拖拽 | 瞄准区像素差显著高于世界运动基线 |
| CAST-02 | 拖进顶部取消区松手 | Q 不进入冷却 |
| CAST-03 | Q 拖向战场 | 出现瞄准预览 |
| CAST-04 | 松手 | Q 冷却遮罩出现 |
| CAST-05 | 点击召唤师闪现 | 按钮出现冷却 |
| SKILL-01/02/03 | Q / E 点击；按住攻击 | HUD 有响应 |
| MODE1-01 | 1v1 小地图 | 蓝红各 ≤8 个英雄标记（实际 1+1） |

### 3.6 暂停 / 生命周期 / 移动 / 性能

| ID | 场景 | 通过标准 |
| --- | --- | --- |
| PAUSE-01/02/03/04 | 暂停遮罩、冻结、恢复、恢复后继续跑 | 遮罩识别；冻结帧差 <0.05；恢复后帧差 >0.03 |
| PAUSE-05 | 暂停菜单离开对局 | 回主菜单 |
| LIFE-01 | HOME → 回前台 | 对局仍在（必要时自动恢复暂停） |
| MOVE-UP/DOWN/LEFT/RIGHT | 摇杆四方向 | 小地图标记位移方向正确 |
| MOVE-05 | 四方向正交/相反 | 余弦阈值 |
| MOVE-06 | 松手停住 | 标记漂移 <1px |
| PERF-01/03 | 1v1 帧率采样 + PSS | 帧率达标；PSS >600MiB 只 WARN |

### 3.7 5v5 / 联机 / 日志

| ID | 场景 | 通过标准 |
| --- | --- | --- |
| MODE5-00/01/02 | 5v5 AI 对局、十英雄标记、表现 | 对局识别；蓝红各 5 个英雄标记；无崩溃 |
| ONLINE-01 | 单机开房到大厅 | 大厅识别 |
| ONLINE-03 | 联机菜单不冻结模拟 | 菜单打开时世界仍在动 |
| ONLINE-04 | 联机主动退出 | 回主菜单 |
| ONLINE-05 | BACK 只开菜单不退出应用 | 第二次 BACK 回对局 |
| NET-01 | 第二台手机加入房间 | **单机必 SKIP**，需第二台设备 |
| LOG-01/02/03 | 崩溃缓冲 / FATAL·ANR / GDScript 错误 | 全部为空 |

---

## 4. 必须人工执行的用例

自动化只覆盖"能截图、能点、能读日志"的部分。以下必须在真机上手动过：

| ID | 场景 | 步骤 | 通过标准 |
| --- | --- | --- | --- |
| MAN-01 | 音频 | 主菜单听背景视频原声；进选人/对局听是否按设计静音；放技能/受击 | 无爆音、无持续静音 bug、音量合理 |
| MAN-02 | 双指缩放 | 对局中双指捏合/张开 | 镜头缩放平滑，松手不漂移 |
| MAN-03 | 多点触控 | 左手摇杆移动 + 右手拖 Q + 右手点攻击 | 三个触点互不抢占 |
| MAN-04 | 第二台手机联机 | 主机建房，客机加入；走路/放技能/买装备/断线重连 | 客机预测无橡皮筋；断线可恢复或明确报错 |
| MAN-05 | 长局 / 发热 | 5v5 打满 15 分钟，观察帧率、温度、电量 | 无持续掉帧、无烫手降频、无 OOM |
| MAN-06 | 刘海 / 圆角 / 旋转 | 在另一台刘海机或折叠屏上检查；尝试旋转 | 关键控件不被切；横屏锁定 |
| MAN-07 | 联机中 HOME / 锁屏 | 联机对局按 HOME/锁屏 30s 再回来 | 不闪退；重连或明确提示 |
| MAN-08 | 低端机视频 | 在低端机上进菜单/选人 | 视频不出绿屏/黑屏，音画基本同步 |
| MAN-09 | 边缘触摸 | 贴边按 Q/R/攻击/回城 | 不误触、不穿透到下层控件 |
| MAN-10 | 安装 / 升级 | 覆盖安装保留数据；卸载重装 | 签名一致可覆盖；数据行为符合预期 |

---

## 5. 本轮静态发现与修复

**真机 UI 缺陷（静态几何即可复现）**：四技能弧半径 330 时，Q 的触摸矩形（虚拟 1503..1631 × 681..829）与回城键（1490..1586 × 710..806）重叠，且回城键在 Control 树中更靠后、会先吃到触摸——Q 中心点实际点不到，Q 技能无法通过点击施放。

修复：

- `scripts/ui/touch_layout.gd` 新增 `UTILITY_*_RECT`，把回城/传送/召唤师整体上移到技能弧上方（虚拟 y 574..670，x 1206..1502），Q 左边界 1503，彻底分离。
- `scripts/ui/game_hud.gd` 用 `_place_utility_button()` 读取同一组常量，避免两处坐标漂移。
- `tests/test_mobile_ui.gd` 新增 `test_utility_buttons_do_not_cover_the_skill_arc`，headless 即可拦截回归。
- `tools/device_checks.py` 的 `UI-01` 同步校验；`HUD-04`、`SKILL-01/02`、`SAFE-01` 的旧坐标也改为从 `SKILL_RECTS` 推导。

另外修正了自动化脚本自身的几处误判：

- 商店关闭改用面板右上角"关闭"按钮（打开商店时全屏遮罩会挡住顶部商店按钮）。
- 拖拽施法的指示器判定加入"世界运动基线"，避免小兵/镜头移动冒充瞄准指示器。

第三处是 BUILD-05 的打包事实与脚本假设不符：

- Godot 4.7 导出把 monochrome 自适应图标写进 `res/mipmap-anydpi-v26/icon.xml`，但**不会**打包 `res/mipmap-anydpi-v26/themed_icon.xml`；已编译的 `resources.arsc` 里仍有一条 `mipmap/themed_icon → res/mipmap-anydpi-v26/themed_icon.xml` 的悬空引用（`aapt2` 会打印 `no such path exists` 警告）。
- 仓库里的 `tools/fix_apk_theme_icon.py` 是既定修法：把已编译的 `icon.xml` 复制成 `themed_icon.xml`，`zipalign` 后用调试密钥库重签名。**导出后必须跑它，再安装**，否则资源表引用悬空、Android 13 themed icon 校验不干净。
- BUILD-05 因此同时校验两件事：`icon.xml` 是带 background/foreground/monochrome 的 adaptive-icon，且三个 drawable 引用能解析回 APK 内真实存在的 `mipmap/*`；`themed_icon.xml` 已打包且同样是带 monochrome 的 adaptive-icon。
- 附带一个 Windows 坑：`aapt2 dump resources` 输出含 UTF-8 中文，Python 默认按 GBK 解码会抛 `UnicodeDecodeError` 并让 `stdout` 变成 `None`；脚本显式用 `encoding="utf-8", errors="replace"`。

---

## 6. 执行记录

| 日期 | APK | 设备 | 结果 | 报告 |
| --- | --- | --- | --- | --- |
| 2026-10-23 17:24 | 0.1.7 (code 8) | 无（USB 掉线） | 静态阶段首轮：`BUILD-05` FAIL，导出漏打 `themed_icon.xml`；其余静态项全绿 | — |
| 2026-10-23 17:33 | 0.1.7 (code 8，已跑 `fix_apk_theme_icon.py`) | 无（USB 掉线） | 静态阶段 PASS=7 FAIL=1 WARN=1 SKIP=10；唯一 FAIL 为 `ENV-01` 设备不在线，属预期 | `godot/shots/device_checks/20261023_173310/report.json` |
| 2026-10-23 17:57 | 0.1.7 (code 8) | vivo V2220A (10AC9J0VZA0011K) | **真机全局全流程完整跑通**：PASS=78, WARN=3, SKIP=13, INFO=2；成功覆盖启动、窗口、OGV硬解双视频、UI导航栈、硬件BACK键、1v1对局、7大HUD、战局情报、商店面板与快捷购买、攻击模式切换、拖拽瞄准与取消施法、召唤师技能、回城与传送响应、全技能Q/W/E/R施法响应、5v5十英雄AI团战、SurfaceFlinger真实帧率采样、局域网建房大厅与开赛、GLES3 Shader编译与音频子系统 | `godot/shots/device_checks/20261023_174953/report.json` |

---

## 7. 本轮真机实测发现与修复

1. **生产代码缺陷修复（LOG-03 捕获）**：
   - 真机 logcat 捕获到 `ERROR: The object does not have any 'meta' values with the key 'lift_tween'`。
   - 原因：`godot/scripts/app/main.gd` 在 `_animate_lift` 中直接调用 `button.get_meta("lift_tween", null)`，在 Godot 4.7 引擎 C++ 层未设 meta 时会打印 ERROR。
   - 修复：改为先调用 `button.has_meta("lift_tween")` 检查后再获取，消除引擎层报错。

2. **真机环境动态视频背景识别优化**：
   - 主菜单背景为动态循环播放的 OGV 视频，两帧之间全屏灰度差在 10~18 波动。旧脚本写死 9.0 阈值导致 `classify` 将正常运行的菜单识别为 `unknown`。
   - 修复：更新 `classify` 结合局部固定按钮区特征与动态阈值判定，稳定识别主菜单。

3. **新增真机专属覆盖项**：
   - `CAST-06`: Recall 回城按钮真实触控与引导响应测试。
   - `CAST-07`: Teleport 传送按钮真实触控响应测试。
   - `SKILL-W` / `SKILL-R`: W 技能和大招 R 的真实触控与冷却响应。
   - `RENDER-01`: 真机 GPU GLES3 着色器编译与渲染错误日志扫描。
   - `AUDIO-01`: Android AudioFlinger / STREAM_MUSIC 系统音频通道活跃检测。

4. **1v1 流程与 AI 兵线推塔防干扰重构**：
   - 升级版地图中电脑 AI 和小兵推进较快，在对局第 20 秒左右即推平敌方水晶触发 Victory 弹窗，会遮挡后续暂停和摇杆测试。
   - 优化：将 `PAUSE` 冻结与恢复、`LIFE` 切后台与恢复、`MOVE` 摇杆四方向等核心用例前置在开局 10 秒内执行，并在退出对局逻辑中兼容胜利结算弹窗直接点击返回主菜单。

---

## 7. 失败时先看哪里

1. 先确认 APK 是**改动后重新导出**的，版本号与 `export_presets.cfg` 一致（旧包会造成"代码改了但真机没变"）。
2. 截图看 `shots/device_checks/<run>/`，按检查 ID 找对应帧。
3. 看 `logcat` 的 `GodotEngine` / `Godot` 行；脚本的 `LOG-01..03` 只抓崩溃和 `ERROR`。
4. 触摸类失败先用 `UI-01/02` 排除几何问题，再怀疑事件分发。
5. 视频类失败先看 `VIDEO-03` 的日志行，再看 `VIDEO-01/02/04` 的像素差，最后看设备解码能力。
