# 交付前自查清单

> 只在"任务收尾 / 提交前"读这份。8 项，每项挡一类"看起来完成"的假交付。

---

## 1. 测试真的绿了，而且你知道基线是多少

```cmd
godot --headless --path godot --script res://tests/run_tests.gd
```

- [ ] 末行 `FAILED: 0`
- [ ] 你能说出改动前后的用例总数（如果数字变了，说明你新增或删了测试，确认是有意的）

**假交付症状**：只说"测试通过"，说不出跑了多少条。

---

## 2. 做过变异验证

- [ ] 把关键代码故意改错 → 测试变红 → 改回来 → 再跑变绿

没做这一步，"测试通过"只证明代码能跑，不证明测试能抓问题。

---

## 3. 你写的模块真的被引用了

这是本仓库**最容易被忽略**的一项。测试绿、文件在、文档写着"已完成"——但生产代码引用是 0。

```bash
# 把 YourClass 换成你新写的类名
grep -rn "YourClass" --include="*.gd" godot/scripts godot/sim godot/net
```

- [ ] 结果里除了 `tests/`，还有**至少一个生产文件**
- [ ] 如果只有 `tests/`，要么接上，要么在汇报里写"已实现，未接入"

**历史上已有 8 个模块栽在这上面**（2026-10-23 已全部接线），清单见 `01-repo-reality.md` §4。不要成为第 9 个。

---

## 4. 联机路径想过了

对照 `04-combat-chain.md` §A 的 6 处清单：

- [ ] 新字段加进 `_sanitize_entity` 白名单了吗？
- [ ] 新输入键加进 `EMPTY_INPUT` + `sanitize_input` 了吗？
- [ ] 新顶层快照字段加进 `sanitize_snapshot` 了吗？
- [ ] 新事件的键在 `_sanitize_event` 名单里吗？

**做不到就说清楚**：如果这次只做了单机，**在交付说明里明确写"仅单机生效，联机未接"**。不要沉默——沉默会被当成"联机也能用"。

**假交付症状**：单机演示完美，一联机功能消失，且没人提前说过。

---

## 5. 文档与代码一致

- [ ] 改了目录/文件结构 → 更新 `README.md` 的目录树
- [ ] 改了本目录描述的行为 → **同一次提交**里更新 `docs/ai/` 对应文件
- [ ] 改了 `docs/ARCHITECTURE.md` 里的目录约定 → 同步 `docs/ai/01-repo-reality.md`
- [ ] **不要**往 `docs/upgrades/README.md` 的完成度表里填"未接线"的模块

**假交付症状**：文档写着"已完成"，但生产代码里没有任何引用（这个仓库历史上发生过 8 次，见 `00-hard-rules.md` 第 9 条）。

---

## 6. 仓库干净

```cmd
git status --porcelain
```

- [ ] 没有 `shots/`、`build/`、`*.log`、`.tmp/` 里的东西出现在未跟踪列表
- [ ] 新增的 `.uid` 已一起提交
- [ ] 没有把 `godot/.godot/` 加进来

---

## 7. 如果是表现层改动，补一条

- [ ] 桌面模式截图看过了
- [ ] 触控模式截图看过了
- [ ] 5v5 满员（10 英雄 + 多波小兵）时没有糊成一片

```cmd
godot --path godot --script res://tools/ui_shot.gd
godot --path godot --script res://tools/mobile_shot.gd
```

截图落 `godot/shots/`，**不入库**。

---

## 8. 如果这次改了 Android 可见行为（UI / 视频 / 输入 / 打包）

- [ ] 改了脚本或资源后**重新导出 APK**（旧包不算数），版本号与 `export_presets.cfg` 一致；导出后跑 `python tools/fix_apk_theme_icon.py` 补 themed icon 并重签名
- [ ] `cd godot && python tools/device_checks.py` **接上真机**跑完整套件、无 FAIL；设备离线时的 `ENV-01` FAIL + `PHASE-*` SKIP 不算通过。`NET-01` 在有第二台手机前允许 SKIP
- [ ] 人工用例按 `09-device-testing.md` §4 过一遍（音频、双指、第二台手机、长局）
- [ ] `report.json` 路径与结果记入 `09-device-testing.md` §6

**假交付症状**：headless 全绿、截图是旧的、APK 没重打，手机上还是上一版。

---

## 一句话总结

> **测试绿 ≠ 做完了。**
> 这个项目最常见的失败模式不是"算错了"，而是"算对了，但没送到该看到它的那一层"——
> 要么没接线（模块空转），要么没进白名单（联机丢字段），要么没进快照（UI 读不到）。
