# 06 · 客户端输入预测与平滑纠错规范 (Client Prediction & Reconciliation)

## 1. 目标与设计
参考顶级商业移动 MOBA（如《王者荣耀》）网络同步模型，消除客机在移动和转向时的网络往返延迟感（RTT 延迟滞后），兼顾服务端权威与视觉流畅：
- **客户端本地即时预测（Client-Side Input Prediction）**：
  - 玩家触控虚拟摇杆发出移动指令瞬间，客机立即在本地推进角色位移（`predict_input`），无需等待服务器确认即可立刻响应。
  - 为每一个输入分配单调递增的序列号 `seq`，并保留在本地待决队列（Pending Inputs Buffer）。
- **服务端回执与状态校验（Server Reconciliation）**：
  - 服务端处理输入后下发权威位置 `server_pos` 及对应的已确认序号 `acked_seq`。
  - 客机收到后清理历史队列中 `<= acked_seq` 的条目。
- **双模纠偏（Snap vs Smooth Exponential Decay）**：
  - **严重脱节（Hard Snap，误差 > 4.0m）**：如被击飞、强制位移、敌方硬控打断或闪现瞬移时，立即瞬移至服务端权威坐标，重新回放未确认输入，杜绝拉扯穿墙。
  - **微小漂移（Smooth Decay，0.02m < 误差 <= 4.0m）**：如轻微碰撞滑动或受减速影响产生的微小误差，误差值计入平滑偏移量（`smooth_offset`），每帧以指数衰减（Decay Rate = 12.0/s）平滑消除，人眼完全无法察觉到抖动与顿挫。

## 2. 产出文件
- `godot/net/client_prediction.gd`：输入队列管理、预测计算、双模纠错与指数平滑衰减。
- `godot/tests/test_client_prediction.gd`：4 大专项单元测试全部绿灯通过。
