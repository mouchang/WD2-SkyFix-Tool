# WD2-SkyFix-Tool

修复《看门狗2》在 **RTX 20 系及以上（以及部分 AMD 显卡）** 上出现的 **天空 / 雾 / 阴影持续闪烁** 问题。

纯数据补丁：不加 DLL、不注入进程、不改任何现有文件、不加启动参数，**不影响联机**。

---

## 问题原因

游戏每帧用一个 compute shader 把天空投影成球谐系数（天空环境光）：

- 256 个线程各自把 29 个 float4 部分和写进 UAV（`SkyTempAccumulationBuffer`）
- 然后用 8 步 `if (tid < n) u1[tid] += u1[tid + n]` 在原地做折半归约
- **全程没有一条 `DeviceMemoryBarrierWithGroupSync`**

线程会读到别的 warp 还没写完的部分和，于是同一帧输入相同、结果却每次不同 ——
天空环境光逐帧跳变，表现为闪屏。

NVIDIA 已把它登记为 bug 3858016 并归类为应用程序 bug；DXVK 也在 2025 年为同一个缺失 barrier 加了 workaround。

## 解决方式

把修正后的着色器以数据形式覆盖进 `data_win64`：

1. 从 `patch.dat` 按名字哈希 `0xBDA417D90674CED7` 取出原始着色器
2. 在 8 步归约的每个顶层 `if` 前插入 `sync_uglobal_t`（`DeviceMemoryBarrierWithGroupSync`）
3. 重算 DXBC 校验和与容器结构，打包成 `patch3.fat` + `patch3.dat`
4. 引擎按 `patch%i` 递增加载，编号越大越晚加载、优先级越高

细节见 [docs/TECHNICAL.md](docs/TECHNICAL.md)。

## 使用方法

1. 下载本仓库（或 Release 里的 zip）
2. 双击 `WD2SkyFixTool.cmd` 打开工具箱
3. 按 **[4]** 设置《看门狗2》位置（游戏根目录或 `data_win64` 都行）
4. 按 **[1]** 安装，然后正常启动游戏

```
==============================================================
   Watch Dogs 2  ·  闪烁修复工具
==============================================================
   作者:the_box_mc(某尝)
   github:https://github.com/mouchang
   bilibili:https://space.bilibili.com/599130940
==============================================================
   看门狗2位置 : <你的游戏路径>
--------------------------------------------------------------
   [1]  一键安装本修复补丁
   [2]  一键删除本修复补丁（只删本补丁，不动其它 mod）
   [3]  一键修改补丁编号（同时更新 uninstall.cmd）
   [4]  设置《看门狗2》文件位置
   [0]  退出
```

卸载：工具箱按 **[2]**，或直接删掉游戏目录 `data_win64` 下的 `patchN.fat` / `patchN.dat`。

## 目录结构

| 路径 | 说明 |
|---|---|
| `WD2SkyFixTool.cmd` | 启动器，双击运行 |
| `WD2SkyFixTool.ps1` | 工具箱逻辑（安装 / 删除 / 改编号 / 设置路径） |
| `tool-config.ini` | 游戏路径配置，默认留空，首次使用按 [4] 设置 |
| `build/patch3.fat` | 补丁索引（52 字节，单条目） |
| `build/patch3.dat` | 补丁本体（57,892 字节，修正后的着色器） |

## 兼容性

- PC 版《看门狗2》（Steam / Ubisoft Connect），同一游戏 build 下二进制一致
- 可与其它 `patchN` 模组共存：编号越大加载越晚、冲突时优先级越高
- 不适用于《看门狗1》《看门狗：军团》

## 已验证

- LZ4LW 解码器对 40/40 个真实条目输出长度精确匹配
- 零插入重建与原容器逐字节一致
- `D3D11CreateDevice` + `CreateComputeShader`：原版 `hr=0x0`，补丁版 `hr=0x0`（驱动接受）
- 实机：闪屏消失，联机正常，EAC 未拦截

## 免责声明

非官方补丁，与 Ubisoft 无关。`build/` 下的数据由游戏自身的着色器文件修改而来，
仅供已购买本游戏的玩家个人使用；如有侵权请联系删除。

## 作者

**the_box_mc(某尝)**

- GitHub: <https://github.com/mouchang>
- Bilibili: <https://space.bilibili.com/599130940>
