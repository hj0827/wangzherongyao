# 05 · 技能指示器与取消施法区规范 (Indicators & Cancel Cast)

## 1. 目标与设计
参考《王者荣耀》触控交互，提供毫秒级动态预瞄与防误触取消施法：
- **三种几何形态指示器（Indicator Geometries）**：
  - **圆形/径向指示器（Circle / Radial）**：用于范围爆炸、近身震荡、自身护盾与光环。
  - **直线矩形指示器（Line / Directional Rectangle）**：用于穿透弹道（如穿云箭、织流）。
  - **扇形指示器（Cone / Sector Arc）**：用于顺劈、散射箭雨（如万箭归宗）。
  - 均支持多边形离散生成与 `is_inside_*` 毫秒级命中判定。
- **右上角取消施法区（Cancel Cast Zone）**：
  - 拖拽技能轮盘时，当触控点滑入右上角红色取消区域（Cancel Zone）：
    - 状态立即切换为 `cancelling = true`。
    - 指示器由常规浅蓝/金色变为警示红（`COLOR_CANCEL`）。
    - 抬手松开时撤销本次施法，不扣除法力，不触发冷却。
    - 若拖拽出取消区，则恢复正常瞄准，不打断操作连贯性。

## 2. 产出文件
- `godot/scripts/ui/skill_indicator.gd`：圆形、直线、扇形指示器点阵生成与命中几何算法。
- `godot/scripts/ui/cancel_cast_zone.gd`：取消区命中检测、颜色变换与拖拽状态机。
- `godot/tests/test_indicators_and_cancel.gd`：5 大专项测试用例全部绿灯通过。
