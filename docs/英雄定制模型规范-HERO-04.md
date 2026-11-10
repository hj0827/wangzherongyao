# HERO-04 定制英雄模型规范

> 状态：接入骨架已就绪，等待 3D 美术交付。当前没有 5 套定制 glb；
> 缺失时 `UnitVisual` 自动回退现有共享模型，不影响对局。
> 代码契约：`scripts/game/hero_model_registry.gd`、`scripts/game/unit_visual.gd::_build_custom_hero`。

---

## 1. 交付目录与命名

```
godot/assets/characters/hero_models/
  blade/blade.glb
  mage/mage.glb
  tank/tank.glb
  archer/archer.glb
  assassin/assassin.glb
```

- 每个英雄一个目录，目录名和文件名必须等于 `hero_type`。
- GLB 内嵌贴图或同目录附带贴图均可；不得引用目录外资源。
- 放入后无需改代码；`HeroModelRegistry.has_custom_model()` 会自动切到定制分支。

---

## 2. 模型预算

| 项 | 桌面 | 移动端 |
| --- | --- | --- |
| 身体三角面 | ≤ 15,000 | ≤ 9,000 |
| 武器三角面 | ≤ 2,000 | ≤ 1,200 |
| 材质数 | ≤ 4 | ≤ 4 |
| 贴图 | 2048² × 3~4 张 | 1024² × 3~4 张 |
| 骨骼 | 标准 Humanoid，≤ 90 根 | 同左，可减手指/面部 |
| 蒙皮权重 | 每顶点 ≤ 4 | 同左 |

约束：
- 脚底 `y = 0`，朝向与现有 `hero_warrior.glb` / `hero_mage.glb` 一致。
- 模型自带服装与武器；不再由 `HERO_SETUPS` 拼 body/outfit/hair/weapon。
- 不带摄像机、灯光、碰撞体、动画事件之外的脚本。
- 不烘焙队伍色；队伍色由 `UnitVisual` 轻微 tint（0.06），需要可染色区域请保持中性底色。
- 透明/布料材质必须兼容 GL Compatibility，不使用屏幕空间效果。

---

## 3. 必需动作（名称必须完全一致）

| 动作名 | 循环 | 用途 | 备注 |
| --- | --- | --- | --- |
| `Idle` | 是 | 待机 | 呼吸/披风微动；不能原地漂移 |
| `Walk` | 是 | 移动 | 根位移留在引擎，动画内不前进 |
| `Run` | 是 | 加速移动 | 可选，缺失时回退 Walk |
| `Sword_Regular_A` | 否 | 普攻 / Q 默认 | 有明确出手帧 |
| `Sword_Regular_B` | 否 | W 默认 | 与 A 的起手/收势不同 |
| `Sword_Regular_C` | 否 | R 默认 | 需要更长的蓄力/收势 |
| `Roll` | 否 | E 默认（位移） | 位移由引擎结算，动画不位移 |
| `Hit_Chest` | 否 | 受击 | 短促、可被更高优先级动作打断 |
| `Death01` | 否 | 死亡 | 结尾保持倒地姿态，便于停留/沉地 |

补充：
- 若英雄有专属动作名，保留 `ANIM_ATTACK` / `ANIM_Q` / `ANIM_W` / `ANIM_E` / `ANIM_R` 表映射；
  规范默认按上表命名，减少代码改动。
- 攻击/技能动作必须在 0.3–0.6s 内出现可读的出手姿态；动作长度与 sim 冷却无关。
- 允许额外动作（`Victory`、`Recall`、`Taunt`），但不得替代必需动作。

---

## 4. 验收清单

### 机器关
```cmd
godot --headless --path godot --script res://tests/run_tests.gd
```
必须全绿；新增定制模型后，以下测试必须仍然绿：
- `test_hero_silhouette.gd`：5 英雄身高仍锚 `HERO_HEIGHT`；
- `test_hero_model_registry.gd`：路径/动作契约；
- `test_hero_presentation_and_perf.gd`：选人页/对局不崩。

### 视觉关
- 选人页 3D 预览（`scripts/app/hero_preview.gd`）能旋转展示，脚不悬空/不穿地。
- 对局 zoom 21 下：5 个英雄剪影两两可辨；武器不挡血条；披风/裙摆不穿模。
- 受击闪白、攻击前倾、死亡姿态在定制骨骼上仍然成立。
- 移动端 1600×900 截图无糊边、无材质爆白、无透明排序错误。

### 性能关
- 桌面目标机 ≥ 60fps；移动端 ≥ 30fps。
- 单英雄 draw call ≤ 6；不进战斗路径 new 节点/材质。
- 5 英雄同屏时，新增 draw call 不超过原共享模型的 1.5 倍。

---

## 5. 接入步骤（美术交付后）

1. 按第 1 节路径放入 5 个 GLB。
2. 运行 `godot --headless --path godot --import`。
3. 跑 `test_hero_model_registry.gd` 与 `test_hero_silhouette.gd`。
4. 打开选人页确认 3D 预览；进入对局确认 Idle/Walk/Attack/Q/W/E/R/Death。
5. 若模型损坏/动作缺失，`HeroModelRegistry.missing_animations()` 会报告；临时删除对应 GLB 即回退共享模型。

---

## 6. 当前替代方案

在定制模型到位前，现有共享模型 + 服装/发型/武器/体型/主色差异仍是运行时方案，
见 `HERO_SETUPS` 与 `test_hero_silhouette.gd`。不要为了“看起来不同”继续堆配件，
那会破坏剪影/血条/性能契约；正式差异应走本规范的定制模型。
