# 视觉 P0 第一批 · 实施与验收证据（2026-11-10）

日期：2026-11-10 ｜ 基线：`main` 工作树 ｜ 改动后：**TESTS: 952 PASSED: 952 FAILED: 0**
配套：[视觉升级开发文档](../../视觉升级开发文档.md) ｜ [视觉差距分析](../../视觉差距分析-对标王者荣耀.md)

---

## 0. 本批做了什么

| 任务 | 改动 | 主要文件 |
| --- | --- | --- |
| MON-01 受击/出手反馈 | `hit` 事件补 `source / source_type`；野怪/小兵受击闪白 + 缩身，出手前倾；arena 按 source 分发 | `sim/match_sim.gd`、`scripts/game/arena.gd`、`scripts/game/unit_visual.gd` |
| MON-03 小兵类型 | 近战/远程/炮车/超级兵四套配件 + 体型；池化复位时切换 | `scripts/game/unit_visual.gd` |
| STRUCT-01 建筑残骸 | 塔/主堡死亡保留 root，隐藏活体部件，显示碎石 + 断柱 + 阵营晶屑；碎石/晶屑走 MultiMesh | `scripts/game/arena.gd` |
| FX-02 状态表现 | 护盾泡、红/蓝 BUFF 光环、减速冰环，全部读现有快照字段 | `scripts/game/unit_visual.gd` |
| HERO-01 英雄剪影 | 5 英雄 `body_scale` + 武器比例拉开，身高仍锚 `HERO_HEIGHT` | `scripts/game/unit_visual.gd` |
| UI-01 技能图标（部分） | 17 个 kind 在 5 族图形之外增加专属印记 | `scripts/ui/skill_glyph.gd` |
| UI-03 商店 | 分类页签 + 详情（名称/属性/价格/品质）+ 品质边框 | `scripts/ui/shop_panel.gd`、`sim/item_shop.gd` |
| FX-01 柔光粒子（部分） | 粒子贴图从纯色方片换成程序化径向渐变柔光圆；环境粒子同用 | `scripts/game/fx_textures.gd`、`scripts/game/arena.gd` |

> 说明：MON-01 没有新增 `monster_attack` 事件。`hit` 事件原本就有 `source / source_type`
> 白名单键，直接复用，协议零改动；这比原任务卡方案更小、更安全。

---

## 1. G1 机器关

```cmd
godot --headless --path godot --script res://tests/run_tests.gd
```

结果：

```
TESTS: 952  PASSED: 952  FAILED: 0
```

`FAIL` 与 `SCRIPT ERROR` 扫描：**0 行**。

新增测试（8 个文件，25 条）：

| 文件 | 条数 | 覆盖 |
| --- | --- | --- |
| `test_monster_feedback.gd` | 5 | hit 事件 source/source_type、受击缩身/闪白/复位、出手前倾、arena 分发、小兵复用 |
| `test_unit_status_visuals.gd` | 4 | 护盾泡、红/蓝 BUFF 光环颜色、减速环、死亡隐藏/复活恢复 |
| `test_minion_visual_types.gd` | 3 | 四类型配件互斥、炮车/超级兵体型、池化切换 |
| `test_structure_destruction.gd` | 3 | 塔残骸、主堡残骸、残骸不伪装碰撞体 |
| `test_hero_silhouette.gd` | 3 | 身高契约、宽度差异、body/weapon scale 唯一 |
| `test_skill_glyph_uniqueness.gd` | 2 | 每个 kind 图形唯一、印记不顶圆环 |
| `test_shop_detail.gd` | 4 | 分类过滤、详情文案、品质颜色、详情不加 TextureRect |
| `test_fx_textures.gd` | 1 | 程序化柔光贴图、缓存、径向渐变、边缘透明 |

顺带修复一处既有假绿：`test_monster_forms.gd::test_camp_forms_have_distinct_silhouettes`
之前对 `MonsterForms.build("wolf")` 的空字典取 `root`，在断言前抛 `SCRIPT ERROR` 但仍 PASS。
现在 wolf 走 `UnitVisual` 单独量剪影，日志不再出现该错误。

---

## 2. G3 接线关

```bash
grep -rn "play_attack_reaction" --include="*.gd" godot/scripts godot/sim godot/net
grep -rn "destroy_hide\|_build_structure_rubble" --include="*.gd" godot/scripts
grep -rn "body_scale" --include="*.gd" godot/scripts
grep -rn "quality_of\|ids_by_category" --include="*.gd" godot/scripts godot/sim
```

结果均命中生产文件（不是只有 `tests/`）：

- `play_attack_reaction`：`arena.gd:4272` 调用，`unit_visual.gd:1383` 定义；
- `_build_structure_rubble`：`arena.gd:3840` 调用；
- `body_scale`：`unit_visual.gd:78/92/106/120/134` 配置，`:446` 应用；
- `quality_of / ids_by_category`：`shop_panel.gd:205/213` 与 `:196` 使用；
- `hit.source / source_type`：`match_sim.gd:1410-1411` 发出，`arena.gd:4266-4272` 消费。

---

## 3. G2 变异关

**未执行**。本批是“先落地、后补验收”的实现批次；下一轮请至少补：

1. 把 `HIT_FLASH_SECONDS` 改成 0 → `test_monster_feedback` 必须红；
2. 删掉 `arena.gd` 里的 `attacker.play_attack_reaction()` → 必须红；
3. 把 `_select_category` 的过滤改成恒显示 → `test_shop_detail` 必须红；
4. 把 `rubble.visible = not alive` 改成 `false` → `test_structure_destruction` 必须红。

---

## 4. G4 视觉关

**未执行**（遵循当前工作约束：不启动任何 Godot 窗口）。

需要在可开窗/真机时补的截图：

| ID | 场景 | 看什么 |
| --- | --- | --- |
| S3 | 5v5 团战 | 受击闪白/缩身是否读得出来；小兵四类型是否可辨 |
| S4 | 蓝/红 BUFF 营地 | 野怪出手前倾、死亡残骸、英雄 BUFF 光环 |
| S7 | 塔毁前后 | 残骸是否保留、血条是否隐藏、不挡英雄 |
| S8 | 商店 | 分类页签、详情、品质边框、1280×720 不溢出 |
| S10 | 移动端 HUD | 新配件/状态特效是否掉帧、是否遮挡 |

---

## 5. G5 联机关

`hit` 事件新增的 `source / source_type` 两个键**本来就在** `net_protocol._sanitize_event` 白名单里
（`net/net_protocol.gd:561-574`），因此没有协议变更，`test_net_protocol` 全绿。
**双端实机未跑**：需要在有第二台设备时确认客机也能看到野怪出手前倾/受击闪白。

---

## 6. G6 性能关

**未测量**。本批的潜在热点与已做的缓解：

| 改动 | 风险 | 缓解 |
| --- | --- | --- |
| 每个小兵多 3 组配件 | 可见配件增加 draw call | 每组最多 7 个 mesh；只有当前类型可见；隐藏节点不绘制 |
| 每个单位多 4 个状态节点 | 5v5 单位数量多 | 默认全隐藏；只有护盾/BUFF/减速/受击时显示 |
| 塔/主堡残骸 | 18 座塔全毁时 draw call 爆炸 | 碎石 + 晶屑走 MultiMesh，单座残骸约 4 个 draw call |

需要在桌面 + 移动端跑 `tools/perf_check.gd` / `tools/device_checks.py` 后回填。

---

## 7. G7 资产合规关

本批**没有新增二进制资产**：全部是程序化几何、材质与矢量图形。
`docs/art-credits.md` 仍待建（P0 资产化批次再补）。

---

## 8. G8 真机关

**未执行**。本批改了 Android 可见行为（单位外观/商店 UI），下一轮需要重导 APK
并跑 `tools/device_checks.py`。

---

## 9. 未做 / 下一步

- [ ] G2 变异验证（4 条）
- [ ] G4 截图（S3/S4/S7/S8/S10）
- [ ] G6 性能（桌面 + 真机）
- [ ] G8 重导 APK + device_checks
- [ ] MON-02 死亡溶解 / 重生 scale-in
- [ ] FX-01 位图 VFX 贴图（当前只有程序化柔光圆）
- [ ] WALL-01 岩石变体 + 墙脚植被
- [ ] UI-02 英雄面板装备/Buff 格
- [ ] UI-01 位图技能图标资产（当前只是矢量唯一化）
- [ ] SCENE-01 基地/野区道具

---

## 10. 签字

| 项 | 结论 | 证据 | 签字 | 日期 |
| --- | --- | --- | --- | --- |
| G1 机器 | ✅ 952/952 | `.tmp/tests_final4.log` | 待签 | 2026-11-10 |
| G2 变异 | ⬜ 未做 | — | — | — |
| G3 接线 | ✅ grep 命中生产 | 本文件 §2 | 待签 | 2026-11-10 |
| G4 视觉 | ⬜ 未做（不弹窗） | — | — | — |
| G5 联机 | 🟨 白名单绿、双端未跑 | `test_net_protocol` | 待签 | 2026-11-10 |
| G6 性能 | ⬜ 未测 | — | — | — |
| G7 合规 | ✅ 无新增二进制资产 | 本文件 §7 | 待签 | 2026-11-10 |
| G8 真机 | ⬜ 未跑 | — | — | — |
