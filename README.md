# RTX 3060 Laptop 的 Windows 预启动解锁（独显直连模式实测）

> **一句话**：在 Windows 启动**之前**用 UEFI 程序执行一次 CMP V67 固件注入，把 RTX 3060 Laptop 的 FP16/BF16 指令发射率放开到专业卡水平 —— **不刷 VBIOS、不换驱动、不改 BCD 之外的任何东西**。本机实测 **FP16 +58~65%、BF16 +67~71%**，TF32/FP32/显存带宽完全不变。
>
> 本仓库记录的是「**独显直连（dGPU-only）笔记本**」这一非常规拓扑下的完整移植过程：上游实现假设显示输出与目标 GPU 隔离，而这台机器的屏幕**就是**由 3060 驱动的，因此需要四处额外改动。仓库里没有固件二进制，只有补丁、脚本、实测数据和踩坑记录。

---

## 1. 结果（可复现的实测数据）

### GEMM（`E:\AI\gpu-unlock-bench`，8192³ 与 4096³，FP32 累加）

| 组别 | 测试 | 解锁前 | 解锁后 | 变化 |
|---|---|---:|---:|---:|
| 🎯 目标 | FP16 8192³ | 23.21 | **36.67** TFLOPS | **+58.0%** |
| 🎯 目标 | BF16 8192³ | 23.23 | **38.85** TFLOPS | **+67.2%** |
| 🎯 目标 | FP16 4096³ | 21.26 | **37.63** TFLOPS | **+77.0%** |
| 🎯 目标 | BF16 4096³ | 21.47 | **38.51** TFLOPS | **+79.4%** |
| 🔧 负载 | MLP prefill (bf16) | 21.97 | **37.55** TFLOPS | **+70.9%** |
| ⚪ 对照 | TF32 | 11.19 | 11.33 | +1.3% |
| ⚪ 对照 | FP32 SIMT | 6.01 | 6.12 | +1.8% |
| ⚪ 对照 | 显存拷贝 | 224.12 | 224.52 GB/s | +0.2% |

> 单次测量最高见过 FP16 **38.37**、BF16 **39.74**（+65% / +71%），多次之间有数 % 抖动。

**为什么这个"形状"是对的**：解锁提高的是 FP16/BF16 的**发射率**（同一周期多发指令），不涉及显存带宽，也不改 TF32/FP32 通路。所以 4096³ 档（更吃发射率）涨幅高于 8192³ 档（更吃带宽），而后三行必须纹丝不动 —— 它们确实没动。

### LLM 真实前后对照（llama.cpp，同一 llama-server、同参数、同提示词）

**A. 9B 带 CPU 回退（`-ngl 28`）**

| 指标 | 解锁前 | 解锁后 | 变化 |
|---|---:|---:|---:|
| **prefill (pp)** | 804.12 t/s @1503 tok | **932.15 t/s @1465 tok** | **+15.9%** |
| decode (tg) | 23.68 t/s @60 tok | 24.20 t/s @60 tok | +2.2%（噪声内） |

模型 `Ornith-1.5-9B-Uncensored-Q4_K_M`，`-ngl 28 -c 8192`。解锁前取自本机 2026-09-04 历史日志（`prefillB.err.log`），解锁后为 2026-10-26 同参数复现。

**B. 4B 全在 GPU 上（`-ngl 99`）**

| 指标 | 解锁前 | 解锁后 | 变化 |
|---|---:|---:|---:|
| **prefill (pp)** | 940~1146 t/s @315 tok | **1617 t/s @361 tok** | **+41%~+72%** |
| decode (tg) | 53.3~54.6 t/s | 58.8 t/s | +8%~10%（噪声/配置差） |

模型 `Qwen3.8-Distill-4B`，`-ngl 99 -c 65536`（另有 1396 tok 时 **1943.7 t/s**）。⚠️ 两条标称同配置的历史记录彼此就差 22%，`-fa/-ub/KV 量化` 等细节未记录，**这是量级参考而非精确值**。

**这两个数字放在一起才是重点**：模型越纯在 GPU 上、越不吃 CPU 回退，端到端 prefill 就越接近 GEMM 的裸提升（+58~67%）；9B 有部分层在 CPU，所以只被摊到 +16%。**"跑分涨 60%、跑模型只涨 16%"不是矛盾，是部署方式决定的。**

**decode 基本不动是预期结果**——它吃显存带宽，而带宽没被动过（GEMM 侧 `mem_copy` 也是 ±0.2%）。

> 📌 对外引用时：9B 用 **+15.9%**、4B 全 GPU 用 **+41%~+72%（量级）**，**不要**拿 GEMM 的 +58~67% 直接冒充推理加速。

---

## 2. 测试机器

| 项 | 值 |
|---|---|
| 机型 | LENOVO 82RF / Legion Y9000P IAH7H (2022) |
| CPU | i9-12900H（Iris Xe 核显**在 BIOS 中被禁用**） |
| GPU | RTX 3060 Laptop GPU 6 GB，`10de:2560`，subsystem `17aa:3ae8`，GA106M |
| VBIOS | `94.06.34.00.42` |
| BIOS | `J2CN51WW`（2023-03-08） |
| 系统 | Windows 11 23H2 (22631)，NVIDIA 驱动 617.42 |
| 关键前提 | **独显直连模式**（`nvidia-smi` 的 `display_active=Enabled`，核显 PnP `Status=Unknown`）、**Secure Boot 已关**、快速启动已关 |

可以正常工作的上游拓扑是「核显/AMD 核显持有 UEFI GOP，NVIDIA 只做计算」。**这台机器的屏幕由 3060 自己扫描输出**，这是它与所有已知成功案例的根本差别，也是本仓库存在的理由。

---

## 3. 原理（一句话版）

NVIDIA 在廉价卡上用固件微码把 FP16/BF16 的指令发射率封顶到专业卡的 1/N。上游项目在 `nvidia` 驱动绑定前把 **CMP V67 / PLM 固件**注入 GPU，改写 `SS0` 选择器（`0x88888888`），从而恢复发射率。整个过程发生在**开机时、Windows 之前**，只动 GPU 的易失寄存器：

- **不刷 VBIOS**（PROM 哈希前后不变）
- **不改注册表/驱动**
- **重启或断电即恢复出厂**

本项目走的是 Windows 路线：写一个 x86-64 UEFI 应用，由固件启动项在 BDS 阶段运行。

---

## 4. 与上游的差异（**这是本仓库的核心内容**）

基线是 [impacifist/Windows-GPU-UNLOCK](https://github.com/impacifist/Windows-GPU-UNLOCK)（GPL-2.0-only）。补丁在 [`patches/`](patches/)，共 4 个：

| 补丁 | 作用 | 为什么必须 |
|---|---|---|
| `0001-fix-bcdedit-identifier` | `bcdedit` 输出解析改为**界面语言无关** | 中文 Windows 把标识符印成「标识符」而非 `identifier`，原正则永不匹配；两处整块文本比对也永远不等 |
| `0002-feat-lenovo-82rf-3060-profile` | 新增机型 profile（PCI/子系统/BAR0/chip/PROM/SHA）+ 混合拓扑显示判定 + 构建参数化 | 上游白名单只有两台 ASUS 台式机 |
| `0003-fix-python-profile` | 观察构建可指定 python 与 profile；握手失败打印失败步骤 | 本机默认 `python` 是 Anaconda 2.7；原来失败只报 "HANDOFF STOPPED"，无法定位 |
| `0004-feat-Windows-LENOVO-82RF` | **独显直连模式的四处核心改动**（见下） | 上游假设在此不成立 |

### 补丁 0004 里的四处改动

**① 显示判定降级为观测（`app.c`）**
上游要求「没有任何 GOP 解析到目标 GPU」。独显直连下这条恒假。改为逐条记录全部 GOP（原实现看到第一个不合规的就 `break`，看不到全局），并在 `GU_ALLOW_TARGET_CONSOLE` 下只记录不拦截。

**② 控制台失效不再当致命错（`app_io.c`）**
原实现里 `ConOut->OutputString` 失败会置 `LogFault`/`Gu.fault`，后续全线 abort。而**要释放的正是驱动这块屏幕的固件驱动** → 必然失败 → 必死。改为：失败只置 `ConsoleDead`，继续写 `REPORT.TXT`，屏幕没了但日志完整。

**③ 事务成功后自己交棒 Windows（`app.c` 的 `HandoffWindows()`）**
**这一条是实机撞出来的**：事务成功返回固件后，BDS 要重画启动菜单，而显示驱动已被摘除 → 黑屏挂死（风扇灯全亮），用户只能断电，而解锁是易失的，成果随之丢失。
正解：事务成功、资源全部释放后，按 **GPT 分区 GUID** 定位 Windows ESP，把该卷设备路径的 `END` 节点换成 `FILEPATH` 节点，`LoadImage` + `StartImage` 真正的 `bootmgfw.efi`。实机验证：事务成功后**直接进 Windows**，联想开机界面报**本次开机用时 19 秒**（这是固件自己统计的一次开机总时长，不是黑屏时长；黑屏段我没有单独计时）。

**④ 允许释放"带着自己子控制器"的驱动（`ownership.c`）**
目标卡挂着它自己的 GOP 子控制器（`BY_CHILD_CONTROLLER`），创建者是同一个 `PciIo BY_DRIVER` 所有者。上游 `GuFindReleaseOwner` 一律拒绝任何子关系（注释说明了理由：`DisconnectController` 会跨协议收子控制器，不能假设隔离）。本机放开**仅这一种**：`BY_CHILD_CONTROLLER && agent == 唯一 owner`；如果子句柄本身是控制台句柄，仍然拒绝。

> 其它 profile、以及没开 `-AllowTargetConsole` / `-HandoffWindows` 的构建，行为与原版逐字节一致。

---

## 5. 复现步骤

### 5.1 前置

1. **关闭 Secure Boot**（未签名 EFI）。BIOS：`Security → Secure Boot`。本机进 BIOS 按 **F2**（不响应用 `Fn+F2`），启动菜单 **F12**。
2. 关闭快速启动（保证关机是真冷启动）。
3. 准备一个**专用的 FAT32 EFI 分区**（不是 Windows 自带的那个 ESP）。本项目用了数据盘尾部 1 GiB；上游同源方案也是这么做的，因为固件资产里的 `gsp_ga10x.bin` 一个文件就有 **84 MB**。

### 5.2 生成固件资产（**本仓库不提供二进制**）

按上游 [`docs/ASSETS.en.md`](https://github.com/impacifist/Windows-GPU-UNLOCK) 走 pinned 流程，需要联网：

```powershell
# 从 NVIDIA 官方包/归档取得 610.43.03 的两个钉住输入，校验 SHA256 后：
python firmware\fetch_artifacts.py <inputs>
python run_generate.py <inputs>\nvidia-utils-610.43.03-1-x86_64_v3.pkg.tar.zst <out>
python firmware\extract_boot_assets.py <assets.src>\NVIDIA-kernel-module-source-610.43.03 <out>
```

产出 5 个文件，全部要与 `unlock/assets.json` 的 size + sha256 逐字节一致：

```
booter_load_ga102.bin          61256      056cbc06…dcaa4
v67-ga102-610.43.03.bin        64000      2a0aa1f8…e197
gsp_ga10x.bin                  84277400   57237362…4f3a
gsp_boot_ga102.bin             24576      3df651ac…5768
gsp_boot_desc_ga102.bin        84         cc5a3fc1…bf15
```

> 实测坑：`archive.cachyos.org` / `archive.archlinux.org` 会对单个出口 IP 限速到 ~20 KB/s 且每请求约 960 KB 断开。用 `curl --resolve archive.cachyos.org:443:<另一个 Cloudflare 边缘IP>` 可恢复到 1 MB/s 量级。`download.nvidia.com` 直连正常（约 3.6 MB/s 单流）。

### 5.3 打补丁并编译

```powershell
git clone https://github.com/impacifist/Windows-GPU-UNLOCK upstream
cd upstream
git am ..\patches\*.patch          # 4 个补丁
```

需要 **clang + lld-link**（本机用 Swift 工具链自带的 21.1.6）和 EDK2 MdePkg 头文件（`deps/edk2`）。

```powershell
cd internal-boot\unlock
.\build.ps1 -Clang <clang.exe> -LldLink <lld-link.exe> -Python <venv python> `
  -ExperimentalUnlock -StockProfile entryLatchedSs1Preserve -HardwareProfile lenovo-82rf-3060 `
  -AllowTargetConsole -HandoffWindows
```

两个 profile 参数的含义：

- `entryLatchedSs1Preserve`：**只写 `SS0=0x88888888`，不动 `SS1`**。已知成功案例（ASUS TUF A15 的 3060 Laptop、RTX 3060 12GB 的 GA106 移植）都是在不碰 SS1 的情况下拿到全部 FP16/BF16 收益；`SS1=8` 是上游自己标注"未在硬件上验证"的额外实验。
- `-AllowTargetConsole -HandoffWindows`：**独显直连模式必须带**，否则见第 4 节。

### 5.4 部署与运行

```powershell
# 提权：写入专用 ESP + 追加一个固件启动项（末尾），带 sha256 校验、BCD 备份、失败自动回滚
powershell -File scripts\register-unlock.ps1 -Register
```

然后在目标 ESP 上形成：

```
\EFI\WindowsGPUUnlock\UNLOCK-3060-MANUAL.EFI
\RTX3090-UNLOCK\ASSETS\{5 个固件文件}
```

运行：**关机 → F12 → 选 `GPU Unlock 3060 Laptop - EXPERIMENTAL (press U)` → 出现提示按一次 `U`**。
之后屏幕会黑，Windows 自身的驱动重新初始化显卡后才恢复画面。程序会自己交棒，**不会回到固件菜单**。本机实测联想开机界面报**本次开机用时 19 秒**（按电源键到进系统这一段，固件统计口径）；黑屏具体持续多久我没有单独测，别拿 19 秒当黑屏时长。

每次运行都会在 `\RTX3090-UNLOCK\RUNnn\REPORT.TXT` 留下完整日志（布局、FWSEC、SS0 读回、FLR、containment）。

### 5.5 撤销

```powershell
powershell -File scripts\register-unlock.ps1 -Rollback   # 提权，删启动项、恢复原顺序
```

**解锁本身不需要撤销** —— 它是易失的，重启/断电即恢复出厂。

---

## 6. 风险与恢复

| 现象 | 处理 |
|---|---|
| 按 U 后屏幕变黑，过一会儿 Windows 才亮起来 | **正常**。显示驱动被摘除，要等 Windows 重新初始化显卡。本机整个开机（联想计时）19 秒；黑屏段本身未单独计时 |
| 超过 2~3 分钟无任何反应 | **长按电源键 10 秒**断电，再正常开机。早已验证：断电即恢复出厂，不存在"改坏显卡" |
| 屏幕打印 `STOP: cleanup cannot be proven` | 该分支**故意不重置、不重试、死循环**（防止带着未证明的状态进 Windows）。长按电源键断电 |
| 想彻底放弃 | BIOS 里把 Windows 启动项调回第一，或跑 5.5 的撤销 |

**这台机器上已经验证过的安全网**：所有只读检查（身份、BAR0、PROM 哈希、冷态、资产哈希）都在任何写操作**之前**；事务前后各做一次 containment 检查（BME 清零、DMA 计数归零）；失败路径一律不交棒、直接返回固件。

---

## 7. 仓库结构

```
README.md                    本文件
PROGRESS.md                  完整移植过程：机型常量、四轮启动报告、上游改动清单、实时数据
patches/                     相对上游的 4 个补丁（git am 可直接应用）
scripts/
  create-esp.ps1             建专用 FAT32 ESP（含每步断言，替换过危险的 diskpart 脚本）
  register-unlock.ps1        部署 + 登记启动项 / -ReplaceEfi / -Rollback
  inspect-unlock-state.ps1   只读检查 ESP 内容、BCD 项、启动顺序
  collect-reports.ps1        把 ESP 上的 RUNnn/REPORT.TXT 取回本地
  ...                        观察构建、profile 配置等辅助脚本
captures/
  RTX3090-UNLOCK/            只读观察启动抓取的 DIAG 文本 + 58 个驱动镜像转储
  runs/                      RUN00~RUN02 的真实 REPORT.TXT（含成功那次）
```

---

## 8. 参考与致谢

- [Zagitta/gpu-unlock](https://github.com/Zagitta/gpu-unlock) —— 原始 Linux 内核模块与固件注入逻辑
- [impacifist/Windows-GPU-UNLOCK](https://github.com/impacifist/Windows-GPU-UNLOCK) —— 本项目基线（Windows UEFI 移植）
- [Zagitta/gpu-unlock#58](https://github.com/Zagitta/gpu-unlock/issues/58) —— ASUS TUF A15 + RTX 3060 Laptop 的 Windows UEFI 成功报告（**同 chip id `0xb76000a1`**，混合模式下 +35%/+49%）
- [predator0321/rtx3060-ga106-uefi-experiment](https://github.com/predator0321/rtx3060-ga106-uefi-experiment) / [IHaBiS02/ga107-unlock](https://github.com/IHaBiS02/ga107-unlock) —— GA106/GA107 的 UEFI 移植与"另开 1 GiB FAT32 分区"的同一思路
- [WildFlash1st/cmp90hx-unlock-for-windows](https://github.com/WildFlash1st/cmp90hx-unlock-for-windows) —— 相关 Windows 预启动实现

## 9. 许可

- 本仓库中的补丁与脚本沿用上游 **GPL-2.0-only**；`LICENSE` 与上游一致。
- **NVIDIA 固件二进制不在本仓库内，也不随本仓库分发**。它们受 NVIDIA 许可约束，需使用者按上游 `docs/ASSETS.*.md` 的 pinned 流程自行从 NVIDIA 官方发布中获取并校验哈希。
- 本项目仅供研究与个人实验。改动 GPU 固件行为可能影响稳定性、保修与某些反作弊/虚拟化场景，**风险自负**。

---

*实测于 2026-10-25/26。所有数字都来自本机，`captures/runs/` 里保留了原始 REPORT.TXT 可供核对。*
