# 文件归属与入库规则

> 只在"新建任何文件"时读这份。判断错了不会立刻出问题，但会在某次 clone 或回滚时爆炸。

---

## 1. 唯一判据

> **队友 clone 下来，需不需要它才能跑起来 / 复现问题？**

- 需要 → 入库
- 不需要 → 不入库
- 拿不准 → 丢 `.tmp/`（整个目录被 `.gitignore` 忽略，零风险）

不要用"这个文件重不重要"来判断，要用"**别人需不需要**"来判断。

---

## 2. 归属表

| 类型 | 例子 | 处理 |
| --- | --- | --- |
| 运行时源码 | `godot/sim/**`、`godot/scripts/**`、`godot/net/**` | 入库 |
| 场景 / 着色器 | `godot/scenes/*.tscn`、`godot/shaders/*.gdshader` | 入库 |
| 测试 | `godot/tests/test_*.gd` | 入库 |
| 可复用验收工具 | `godot/tools/*_shot.gd`、`perf_check.gd`、`device_checks.py` | 入库 |
| 运行时资产 | `godot/assets/**` | 入库 |
| **资源 UID** | 所有 `*.gd.uid`、`*.tscn.uid`、`*.png.uid` | **入库**（不是缓存） |
| 一次性诊断探针 | `godot/tools/probe_*.gd`、`grab_*.gd`、`.probe*.txt` | 忽略 |
| 截图 / 验收产物 | `godot/shots/**` | 忽略（约 365MB） |
| 编辑器缓存 | `godot/.godot/` | 忽略（约 350MB） |
| 构建 / 导出产物 | `godot/build/`、`build/`、`*.apk`、`*.pck`、`*.exe` | 忽略 |
| 日志 | `*.log` | 忽略 |
| 生成源料 | `sources/`、`.video_gen/` | 忽略（成品在 `godot/assets/`） |
| 对着截图做的临时裁剪 | `.crop*`、`*.orig`、`*.rej` | 忽略 |
| 本地助手状态 | `.workbuddy*/`、`.dumate/` | 忽略 |
| 依赖与环境 | `node_modules/`、`.venv/`、`.env` | 忽略 |

---

## 3. 三条容易搞错的

### 3.1 `.uid` 必须入库

Godot 4.4+ 给每个资源生成 `.uid`。它是**资源身份**，不是缓存。删了或漏提交，别处按 UID 的引用会失效。

### 3.2 `*_shot.gd` 要入库，`probe_*.gd` 不要

`tools/ui_shot.gd`、`arena_shot.gd`、`perf_check.gd` 是**可复用的验收工具**，队友需要。
`tools/probe_*.gd`、`grab_*.gd` 是**一次性诊断**，依赖本地现场，跑完即弃。`.gitignore` 已按前缀区分。

### 3.3 `sources/` 与 `godot/assets/` 的关系

`sources/` 放 AI 生成的原始素材与视频源片；`godot/assets/` 放**运行时真正加载的成品**（如 `menu_bg.ogv`）。
成品入库，源料不入库。改素材时改 `assets/`，不要指望 `sources/` 被别人拉到。

---

## 4. 每次新建文件后的强制动作

```cmd
git status --porcelain
```

看未跟踪列表里有没有**不该入库的东西**。有，就补 `.gitignore` 规则，**不要靠"下次注意"**。

判断标准：如果这个文件出现在别人的 clone 里会让人困惑或撑大仓库，就是漏了规则。

---

## 5. 拿不准就放 `.tmp/`

```
.tmp/           # 根目录
godot/.tmp/     # 工程内
```

两个目录整目录被忽略。写临时脚本、导临时数据、存中间截图，先扔这里。**清理时也只需要删这一个目录。**

---

## 6. 不要碰的东西

- **`godot/.godot/`**：编辑器缓存，删了要重新导入 1~2 分钟，但不会坏。不要手动改里面的内容。
- **`.gitignore` 的 `godot/Godot/` 规则**：这是拦 APPDATA 异常时误生成的 `user://` 目录，别删这条规则。
- **`.workbuddy-ai/`**：本地助手状态，已忽略。不要提交，也不要删（里面有工作记忆）。
