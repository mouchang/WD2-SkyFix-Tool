# 技术说明

## 现象

RTX 20 系及以上（以及部分 AMD 显卡）上，天空、雾、天空光照的阴影持续闪烁。

## 根因

《看门狗2》每帧用一个 compute shader（DXBC 校验和 `e90c6810a486972691b6f798b5e2b0e0`）把天空投影成球谐系数：

- 256 线程，每线程把 29 个 float4 部分和写进 UAV（`SkyTempAccumulationBuffer`，stride 464）
- 随后 8 步 `if (tid < n) u1[tid] += u1[tid + n]` 在原地做折半归约
- 全程没有 `DeviceMemoryBarrierWithGroupSync`

线程读到别的 warp 尚未写完的部分和，输入相同、结果逐帧不同 → 天空环境光闪烁。

NVIDIA 登记为 bug 3858016，归类为应用程序 bug；DXVK 2025 年为同一缺失 barrier 加了 workaround。

## 补丁做了什么

1. 从 `data_win64\patch.dat` 按名字哈希 `0xBDA417D90674CED7` 取出原始着色器（4 字节 stub + 57,852 字节 DXBC 容器）
2. 在 SHEX 指令流每个顶层 `if` 前插入 `sync_uglobal_t`（`DeviceMemoryBarrierWithGroupSync`），共 9 条
3. 修正 SHEX chunk 大小、token 数、后续 chunk 偏移、容器总长，并用 DXBC 的变体 MD5 重新签名
4. 打包成 `patch3.fat` / `patch3.dat`（FAT5 v11，单条目、未压缩），引擎按 `patch%i` 递增加载

## 验证

- LZ4LW 解码器对 40/40 个真实条目输出长度精确匹配
- 零插入重建与原容器逐字节一致（证明打包逻辑无误）
- `D3D11CreateDevice` + `ID3D11Device::CreateComputeShader`：原版 `hr=0x0`，补丁版 `hr=0x0`
- 容器校验和用 D3D 的变体 MD5 复算，与原文件 `e90c6810...` 完全一致
- 实机：闪烁消失，联机正常，EAC 未拦截

## 与其它方案的区别

| 方案 | 问题 |
|---|---|
| NVIDIA Profile Inspector 的 `0x00FC7620` / `0x00A4F311` | 新驱动上会让同一着色器返回垃圾（白闪 / 粉蓝闪） |
| ReShade / ASI 注入 | 需要 `-eac_launcher` 关闭 EAC，联机不可用 |
| 旧 patch3 补丁 | 对应旧版着色器，与当前 build 的容器对不上 |

本方案只替换游戏的一段着色器数据，进程里不会多出任何模块。

## 命名规则（多个 mod 共存）

- 必须是 `patch<数字>.fat` 与 `patch<数字>.dat`，同号成对
- 数字 ≥ 3（`patch`、`patch2` 是游戏自带的）
- 数字越大越晚加载，冲突时优先级越高
- 多个模组共存时保持编号连续，本补丁建议使用最大编号
