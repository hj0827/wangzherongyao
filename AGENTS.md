# AGENTS.md

> 给所有 AI 编程助手 / 大模型的入口。**动手前先读这一页。**

---

## 必读（约 5 分钟）

1. [`docs/ai/README.md`](docs/ai/README.md) — 索引与任务路由表
2. [`docs/ai/00-hard-rules.md`](docs/ai/00-hard-rules.md) — 十条硬规则
3. [`docs/ai/01-repo-reality.md`](docs/ai/01-repo-reality.md) — **仓库真实结构 vs 文档描述**

第 3 份最重要：`docs/ARCHITECTURE.md` 描述的是目标态，其中 `scripts/core/`、`scripts/infra/` **只有 README，没有任何代码**。往那里写代码等于写死代码。

---

## 然后按任务读

| 任务 | 读 |
| --- | --- |
| 改数值 / 技能 / 经济 | `docs/ai/04-combat-chain.md` + `03-tdd.md` |
| 加操作 / 技能键 | `docs/ai/05-ui-and-feel.md` + `04-combat-chain.md` |
| 改 HUD / 手感 / 特效 | `docs/ai/05-ui-and-feel.md` |
| 改联机 / 协议 | `docs/ai/06-net-sync.md` |
| 新建文件 | `docs/ai/07-files-and-git.md` |
| 写测试 / 修 bug | `docs/ai/03-tdd.md` |
| 跑起来 / 截图 / 打包 | `docs/ai/02-godot-pitfalls.md` |
| Android 真机测试 / 触摸·视频·联机验收 | `docs/ai/09-device-testing.md` |
| 收尾 | `docs/ai/08-delivery-checklist.md` |

机器可读路由：[`docs/ai/routing.yaml`](docs/ai/routing.yaml)

---

## 四条最容易踩的

1. **`scripts/core/`、`scripts/infra/` 是空壳**，真正的逻辑在 `godot/sim/`。往空目录写代码等于写死代码。
2. **加英雄字段要改 6 处**，少一处静默失效（GDScript 读不存在的键返回 `null`，不报错）。清单见 `docs/ai/04-combat-chain.md`。
3. **联机有白名单**，不加进 `godot/net/net_protocol.gd` 的字段只在单机生效，且不报错。
4. **"文件在 + 测试绿" ≠ "功能在跑"**。本仓库曾出现 8 个模块"文件在、测试绿、生产引用为 0"；2026-10-23 已全部接线。新增模块仍必须 `grep` 确认生产引用，并过 `08-delivery-checklist.md`。

---

## 环境硬约束：一律无窗口

- **所有 godot 命令必须带 `--headless`**，禁止启动编辑器（`--editor`）、禁止拉起带窗口的实例。用户会在同一台机器上工作，弹出的游戏窗口会打断他。
- `godot/tools/*_shot.gd`（17 个）、`*_gallery.gd`（`hero_ / monster_ / tower_` 3 个）与 `render_hero_showcase.gd` 依赖 `RenderingServer.frame_post_draw`，`--headless` 下**永远不触发、会挂死**。它们必须带真实渲染上下文跑，所以**不许直接调用**（会在用户桌面上闪窗）。
- 确实需要渲染 / 截图时，**只许走隐藏桌面**（窗口建在不可见桌面上，产物路径不变）：

  ```cmd
  powershell -ExecutionPolicy Bypass -File godot\tools\shot_offscreen.ps1 tools\ui_shot.gd
  ```

  脚本会自己加 `--audio-driver Dummy`、把 stdout 写进 `.tmp/offscreen_*.log`、跑完打印新增的 `godot/shots/*.png`。**不要绕过它直接 `godot --path godot --script res://tools/xxx_shot.gd`**，也不要靠 `--position 5200,3200` / `--resolution 1x1` 来"藏"窗口——窗口创建到 `_initialize()` 生效之间仍会在屏幕中央闪一下。
- 发现残留的窗口化 godot 进程时**先报告再处理**，不要静默杀进程。

---

## 基线命令

```cmd
godot --headless --path godot --script res://tests/run_tests.gd
```

改动前先跑一次，确认基线全绿。
