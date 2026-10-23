# 烽火峡谷

Godot 4.7 制作的移动端 1v1 / 5v5 战场原型，含单人试炼、人机军团、局域网联机四种模式。
主菜单背景为 AI 生成的循环视频，UI 为分层立体风格（雾、火星、辉光与鼠标视差）。

---

## 目录结构

```
.
├── run.cmd                      # 启动器：调用本机 Godot 打开工程
├── .gitignore                   # 入库白名单式的忽略规则（见下）
├── .gitattributes               # 二进制资源标记、换行符统一
├── docs/                        # 工程规范与文档
│   └── ARCHITECTURE.md          # 【核心基准】游戏分层架构、目录规约与开发铁律
│
├── godot/                       # 游戏工程本体（Godot 项目根）
│   ├── project.godot            # 工程配置（主场景、分辨率、渲染后端）
│   ├── export_presets.cfg       # 导出预设（Android，含 *.ogv 打包规则）
│   ├── icon.svg / preview.png   # 工程图标、编辑器预览图
│   │
│   ├── assets/                  # 运行时资产（入库）
│   │   ├── animations/          # 骨骼动画库
│   │   ├── characters/          # 角色模型与贴图
│   │   ├── environment/         # 建筑、地形、植被模型
│   │   ├── weapons/             # 武器模型
│   │   ├── textures/            # PBR 贴图
│   │   ├── fonts/               # 思源黑体、马善政毛笔体
│   │   └── ui/                  # 主视觉、英雄立绘、主菜单背景视频
│   │
│   ├── scenes/                  # 场景文件（main_menu / preview）
│   ├── scripts/                 # 运行时代码
│   │   ├── app/                 # 应用壳：界面切换与主流程
│   │   ├── game/                # 战斗内逻辑与单位表现
│   │   └── ui/                  # 主题、HUD、摇杆、动态背景、立体卡片
│   ├── sim/                     # 战斗模拟（确定性权威逻辑）
│   ├── net/                     # 局域网发现、房间管理、协议与同步会话
│   ├── shaders/                 # 自定义着色器
│   ├── tests/                   # 自动化测试（含 device_refs 参考图）
│   └── tools/                   # 开发工具：截图、性能检查、资源巡检、设备验收
│
└── sources/                     # 【不入库】生成源料本地归档
    ├── design-images/           # AI 原始设计图（与 assets/ui 成品字节一致）
    └── ai-video/                # 背景视频源片（成品已转码为 assets/ui/menu_bg.ogv）
```

### 为什么这样分

- `godot/assets/` 是**运行时真正加载**的东西，必须入库；`sources/` 只是可重新生成的原料，入库等于重复占体积。
- `*.import` 文件是 Godot 导入配置（小文本），需要入库，队友拉下来即可直接打开；
  而 `.godot/` 是导入产物缓存（本项目约 350MB），与本机强相关，必须忽略。
- `godot/shots/` 下近 300 张验收截图约 365MB，属于「跑一次就重生成」的产物，只做本地留存。

---

## 运行

```cmd
run.cmd
```

或手动指定 Godot 路径：

```cmd
"D:\Software\Godot\Godot_v4.7-stable_win64.exe" --path godot
```

> `run.cmd` 里的 `GODOT_EXE` 默认指向 `D:\Software\Godot\`，换机器时改这一行即可。

## 测试与校验

```cmd
:: 全量单元测试（headless）
godot --headless --path godot --script res://tests/run_tests.gd

:: 全流程 UI 截图（输出到 godot/shots/，不入库）
godot --path godot --script res://tools/ui_shot.gd

:: 主菜单连拍（验证背景视频在动）
godot --path godot --script res://tools/menu_shot.gd
```

> Windows 下若命令行里 `APPDATA` 为空，启动 Godot 前请显式设置，
> 否则 `user://` 会退化到工作目录，生成类似 `godot/Godot/app_userdata/` 的垃圾目录。

## 游戏架构与代码分层规约

本项目严格执行 **「Core-View 严格解耦的分层领域架构」（Clean Game Architecture）**，详细架构规约与五大开发铁律参见：  
👉 **[完整架构规范文档 (docs/ARCHITECTURE.md)](docs/ARCHITECTURE.md)**

### 核心分层（六大核心域）
1. **`core/`（领域逻辑核）**：纯 GDScript 类，绝不继承 Node 节点，脱离渲染 100% 确定性运行。
2. **`view/`（3D 表现层）**：只读消费快照，负责平滑插值、模型动画装配、地面指示环与打击反馈。
3. **`ui/`（2D 交互层）**：HUD、触控摇杆、技能轮盘瞄准、全屏视差菜单，单向产生操作意图。
4. **`net/`（网络同步层）**：客户端 Jitter Buffer、主机状态广播、协议编解码、局域网房间发现。
5. **`infra/`（基础设施层）**：全局对象池（Pool，杜绝真机卡顿）、统一输入抽象、音频管理。
6. **`app/`（应用生命周期）**：全局启动器、着色器预热、场景状态机。

---

## 开发约定

### 1. 先写测试，再写实现（TDD）

`tests/run_tests.gd` 会自动发现 `godot/tests/test_*.gd`，**新增测试文件即生效**，不需要注册清单。
`test_base.gd` 是基类，不参与执行。

标准流程：

1. 在 `godot/tests/` 下新建 `test_<功能>.gd`，`extends "res://tests/test_base.gd"`；
2. 写一条**会失败**的断言，跑一次确认它红（证明测试真的能抓到问题，不是恒真）；
3. 写实现，跑到绿；
4. **做一次变异验证**：把关键代码改回错误写法，确认测试变红，再改回来。
   静默失效的 bug（`tsc`/构建/渲染都不报错的那类）必须靠这一步兜住。

可用断言：`check(cond, msg)`、`eq/ne(a, b, msg)`、`gt/lt(a, b, msg)`、`near(a, b, eps, msg)`。

### 2. 新建文件时先判断：入库还是忽略

写文件之前先问一句「这是过程文件吗？」，再决定放哪：

| 类型 | 例子 | 处理 |
| --- | --- | --- |
| 运行时源码 / 场景 / 着色器 / 测试 | `scripts/**`、`sim/**`、`tests/test_*.gd` | 入库 |
| 运行时资产 | `assets/**` | 入库 |
| 可复用的验收工具 | `tools/*_shot.gd`、`tools/perf_check.gd` | 入库 |
| 一次性诊断探针 | `tools/probe_*.gd`、`tools/grab_*.gd` | **忽略**（规则已就绪） |
| 脚本产出物 | `shots/**`、`build/**` | **忽略** |
| 对着截图做的临时裁剪/比对 | `.crop*`、`*.orig` | **忽略** |
| 可重新生成的源料 | `sources/**` | **忽略** |

判断依据只有一条：**队友 clone 下来需不需要它才能跑起来 / 复现问题**。
不需要，就别入库；不确定就先按忽略处理，规则集中在 `.gitignore` 里，改一处即可。

## 打包 Android

```cmd
godot --headless --path godot --export-debug "Android" build/android/fenghuo-gorge-debug.apk
```

产物在 `godot/build/`，**不入库**（约 84MB）。
`export_presets.cfg` 里已把 `*.ogv` 加入 `include_filter`，否则 APK 内没有背景视频，运行时会静默回落到原画动画。

---

## 版本管理约定

入库：源码、场景、着色器、测试、工具脚本、`godot/assets/` 全部运行时资产。
不入库：

| 类别 | 路径 | 原因 |
| --- | --- | --- |
| 编辑器缓存 | `godot/.godot/` | 约 350MB，Godot 自动生成 |
| 验收截图 | `godot/shots/` | 约 365MB，跑脚本即重生成 |
| 构建产物 / 导出产物 | `godot/build/`, `build/`, `dist/`, `out/`, `*.apk`, `*.aab`, `*.pck`, `*.exe` | 约 80MB+，衍生文件，CI/本地随时按需导出 |
| 依赖与本地环境 | `node_modules/`, `*.lock`, `.venv/` | 本地安装与开发环境，任何人 clone 后独立管理 |
| 一次性诊断探针 | `godot/tools/probe_*.gd`, `godot/tools/grab_*.gd` | 依赖本地现场，跑完即弃 |
| 临时分析产物 | `.crop*`, `*.orig`, `*.rej` | 对着截图裁剪/比对的一次性文件 |
| 日志 | `*.log` | 运行时产物 |
| Python 字节码 | `__pycache__/` | 工具脚本副作用 |
| 生成源料 | `sources/` | 与成品重复，可重新生成 |
| 本地助手状态 | `.workbuddy*/` | 仅本机会话使用 |

克隆后首次打开工程，Godot 会自动重建 `.godot/` 缓存并重新导入资产（首次约需 1–2 分钟）。

---

## 架构演进与 Web 端移除说明

本项目在早期原型探索阶段曾尝试基于 Vite + TypeScript + HTML5 Canvas / Three.js 的 Web 端实现。经技术评估与性能实测，现已**全面确立为纯 Godot 4.7 原生架构**，Web 端已被完全废弃并清理：

1. **Web 端彻底移除**：
   - 早期 Web 客户端（`src/client/`）、旧服务端（`src/server/`）、入口页面（`index.html`）、构建配置（`vite.config.ts`、`tsconfig.json`）及包管理配置（`package.json`、`package-lock.json`）均已全部删除。
   - 本地构建生成的 `dist/` 与依赖目录 `node_modules/` 已彻底清除，并在 `.gitignore` 中加入强制忽略，防止任何前端临时文件误入库。
   - 后续开发与测试**无需安装 Node.js、npm 或 pnpm**，不再存在任何前端打包链路。

2. **纯 Godot 原生架构优势**：
   - **渲染与交互**：基于 Godot 4.7 GL Compatibility 渲染管线，原生支持 Android 移动端触控摇杆/技能轮盘以及 PC 桌面端键鼠操作。
   - **核心玩法与网络**：采用确定性权威模拟逻辑（`godot/sim/`）结合 Godot 原生网络层（`godot/net/`），支持单人试炼、人机军团及局域网多人对战。
   - **极简工作流**：只需下载 Godot 4.7，运行 `run.cmd` 即可秒级开启游戏或运行全量无头自动化测试。

3. **构建产物零入库原则**：
   - 任何平台编译/导出生成的最终二进制（如 Android APK/AAB、Godot PCK 包、Windows/Linux 可执行程序等）均不属于版本库资产，必须被 `.gitignore` 拦截，严禁上传到 Git 远程仓库。
   - 仓库仅保存源码、场景与必要运行时素材，保证远程代码库体量轻盈、拉取与合并迅速。
