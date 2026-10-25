# Windows UEFI 移植进度（Legion Y9000P IAH7H / 82RF）

> 目标：用 UEFI 预启动程序在 Windows 之前注入 GPU 解锁（Zagitta/gpu-unlock 的 Windows 端口路线）。
> 基线仓库：`Windows-GPU-UNLOCK`（impacifist，GPL-2.0-only），另克隆 `rtx30-unlock`、`rtx3080-unlock-public` 作参考。

## 机器身份（写进 profile 的常量）

| 项 | 值 |
|---|---|
| 机型 | LENOVO 82RF / Legion Y9000P IAH7H |
| 主板 | LNVNB161216 |
| BIOS | J2CN51WW（2023-03-08） |
| GPU | RTX 3060 Laptop GPU，`10de:2560`，subsystem `17aa:3ae8`，6 GB |
| 驱动 | 617.42（CUDA UMD 13.4） |
| VBIOS | 94.06.34.00.42 |
| 固件 | UEFI；Secure Boot **已关**（`UEFISecureBootEnabled=0`） |
| 快速启动 | 已关（`HiberbootEnabled=0`） |

## 磁盘改动（唯一一处）

- 磁盘 0（CT1000P3SSD8，NVMe）：E: 由 931.5 → **930.5 GB**，尾部 1 GiB 取出建 **S:**
- S: = 1 GiB FAT32，GPT 类型 EFI System，GUID `4c2a61ef-99fe-4a36-b797-e2b906058734`
- Windows 自带 ESP（磁盘 1，300 MB，GUID `2e82c91f-e37b-41c4-8205-0330180354b4`）**未改动**
- 回滚：删 S: 分区 → `Resize-Partition -DriveLetter E -Size <原大小>`

## 已对上游做的本地修改（全部必要，且有原因）

| 文件 | 改动 | 原因 |
|---|---|---|
| `internal-boot/Configure.ps1` | 增加 `lenovo-82rf-3060` profile 名 + 身份映射 | 上游白名单只有两台 ASUS |
| `internal-boot/install/headless-package.ps1` | 增加 `LENOVO-82RF-J2CN51WW-RTX3060-LAPTOP` 身份与许可 | 同上 |
| `research/headless/build-observe.ps1` | 增加 `-Python` / `-HardwareProfile` 透传 | 本机 `python` = Anaconda 2.7；profile 需可指定 |
| `research/headless/register-observe.ps1` | ①观察镜像 SHA256 改为本地构建值 ②`Ids()` 改为界面语言无关的解析 | ①我们编译的不是作者那台镜像 ②中文 `bcdedit` 把 `identifier` 印成「标识符」，原正则永不匹配 |
| `internal-boot/install/automatic-policy.ps1` | `Resolve-NewBootCopy` 由“整块文本比对”改为“device/path/locale 字段比对” | 同一中文界面的问题，整块比对永远不相等 |

## 当前状态

- 观察版 EFI：`research/headless/build/OBSERVE.EFI`（19,456 B，`CanUnlock=false`、`WritesFirmwareVariables=false`）
- 已放到 `S:\EFI\WindowsGPUUnlock\OBSERVE.EFI`
- 固件启动项：`GPU Headless Observe - NO UNLOCK`，`{b05c3bb5-d07b-11f1-b16c-30894a35f1b9}`，在 displayorder **末尾**
- BCD 备份：`C:\ProgramData\WindowsGPUUnlock\ResearchBackups\20261025-220011097`
- 抓取输出：开机后写到 `S:\RTX3090-UNLOCK\DIAG00.TXT`

## 抓取到的本机常量（2026-10-25 22:26，DIAG01.TXT）

已复制到 `captures/RTX3090-UNLOCK/`（DIAG00/DIAG01 两份 + 58 个驱动镜像转储）。

| 常量 | 值 | 出处 |
|---|---|---|
| `GU_BOARD_ID` | `0x256010de` | cfg dword0 |
| `GU_BOARD_SUBSYSTEM` | `0x3ae817aa` | cfg[0x2c] |
| BAR0 | `0x5e000000`–`0x5effffff`（16 MiB，32 位非预取） | cfg[0x10] / probe-bar0 |
| 扩展 ROM BAR | `0xfff80000`（512 KB） | cfg[0x30] |
| `GU_CHIP_ID` | **`0xb76000a1`** | MMIO[0] |
| `GU_DEVICE_MEMORY_SIZE` | `0x1800`（6144 MiB） | MMIO 0x1183a4 |
| **`GU_PROM_SHA256`** | **`3ea00dfb0754ea1d2318106d6cfc583692c9e4afbc2783863c5ab9d24ae36cf3`** | probe PROM 读 |
| BDF | `0000:01:00.0`（bus 1 / dev 0 / func 0），rev `a1` | probe-target / cfg[2] |

## 显示拓扑结论（决定后续设计）

- `gops=0002`：`0x3d0bfb18` **带设备路径**（核显）；`0x3e0af318` **无设备路径**，而它正是 `ConsoleOutHandle`
- **没有任何 `version=0x600xx` 的 DriverBinding** → 上游用来识别 nvgop 的指纹在本机**不存在**（独显 GOP/nvgop 未加载）
- 因此上游 `DisplayCheck()`（强制 AMD 物理 GOP + `AmdGopParent`）在本机必然失败，需要新增本机分支：
  「唯一带路径的 GOP 不属于目标卡 + 控制台 GOP 无路径 + 没有任何 GOP 解析到目标卡」→ 判定可安全释放

## 固件资产（2026-10-25 23:21 全部就位并逐个校验）

`Windows-GPU-UNLOCK\assets\` 与 `fw-build\assets\` 各一份，5/5 与 `unlock\assets.json` 的 size+sha256 完全一致（共 84,427,316 B）：

| 文件 | 字节 | sha256 前 16 | 来源 |
|---|---:|---|---|
| `booter_load_ga102.bin` | 61,256 | `056cbc064a888f80` | NVIDIA-kernel-module-source-610.43.03.tar.xz（已下载）+ `extract_boot_assets.py` |
| `gsp_boot_ga102.bin` | 24,576 | `3df651acb174fd5f` | 同上 |
| `gsp_boot_desc_ga102.bin` | 84 | `cc5a3fc1f4c47f2f` | 同上 |
| `v67-ga102-610.43.03.bin` | 64,000 | `2a0aa1f86d0b6aff` | **本地合成**：64000 B 填 `0x0000019c` + 19 个 pinned dword 覆写，与 pinned sha256 逐字节吻合（该镜像本身是合成的，哈希即证明；`generate_v67.py` 对上游包做 sha 门禁只是为了取证/许可证，不承载内容） |
| `gsp_ga10x.bin` | 84,277,400 | `572373620a37418f` | NVIDIA-Linux-x86_64-610.43.03.run 内的 `firmware/gsp_ga10x.bin` |

**下载教训（重要）**：`archive.cachyos.org` 与 `archive.archlinux.org` 在本机被限速到 <200 KB/s（16 MiB 区间读取 >120 s），300 MB 的 `nvidia-utils` 包根本下不完 → 改用 `download.nvidia.com`（约 3.6 MB/s 单流、8 线程合计 ≈ 8 MB/s，440 MB 约 50 s）。

**`.run` 的结构**（下次直接用）：makeself 自解压 + **zstd** 载荷；makeself 自带的 `zstd` 是 Linux ELF，在 Windows/Git-Bash 下报 `Exec format error`。真正的 zstd 帧起点在本机这份文件里偏移 **160635**（`28 b5 2f fd`；96270 是假阳性，解压立刻 `Data corruption`）。抽取方式：`seek(160635)` → `zstandard.ZstdDecompressor().stream_reader(...)` → `tarfile.open(mode='r|')`。

## 外部同类方案调研（2026-10-25 23:10）

| 方案 | 机型 | 路线 | 结果 | 对我们的价值 |
|---|---|---|---|---|
| [Zagitta/gpu-unlock #58](https://github.com/Zagitta/gpu-unlock/issues/58) | ASUS TUF A15 FA506QM，**RTX 3060 Laptop 6GB / GA106M**，`10de:2520`，**`PMC_BOOT_0=0xb76000a1`**（与本机**完全相同**），6144 MiB | 自写 x64 UEFI 程序，FAT32 USB 或内部分区 → 事务 → **同一次启动**交棒 Windows Boot Manager | FP16 **+35.24%** / BF16 **+48.89%**；TF32/FP32 不变；**SS1 保持 0x4 不写** | **最贴近本机的一台**，两条关键坑见下 |
| [predator0321/rtx3060-ga106-uefi-experiment](https://github.com/predator0321/rtx3060-ga106-uefi-experiment) | ASUS 板，RTX 3060 12GB / GA106，`10de:2504`，subsystem `1043:881d` | 基于 [IHaBiS02/ga107-unlock](https://github.com/IHaBiS02/ga107-unlock) 的 GA106 UEFI 移植；**GNU-EFI 3.0.15 + Linux 侧 gcc 构建**；配置驱动 `ga106/config.txt`（target / board_vendor / board_device / execute / ss1_full / windows / windows_partition） | FP16 25.74→47.58 TFLOPS（**+84.8%**）、BF16 +84.9%；ComfyUI 出图 −30.8% | **唯一有完整 GA106 源码的方案**；同样因为 84 MB 的 `gsp_ga10x.bin` 塞不进 96 MB 的 Windows ESP，而**另开 1 GiB FAT32 分区**——和我们的 S: 做法一致 |
| [Zagitta #88](https://github.com/Zagitta/gpu-unlock/issues/88) | HP RTX 3080 Ti Laptop 16GB（GA103） | Windows UEFI | FP16 +56% / BF16 +58% | 说明 Windows 预启动路线在**多台笔记本**上成立 |
| [WildFlash1st/cmp90hx-unlock-for-windows](https://github.com/WildFlash1st/cmp90hx-unlock-for-windows) | CMP90HX | Windows 预启动 EFI | — | predator 文档里列为相关实现 |

### #58 提出的两条坑，逐条对照我们已改的代码

1. **混合显卡笔记本上 `PCI Command = 0x0000`**（BAR0 已分配、父桥已开 memory decode，但函数自己的 Command 是 0）→ 必须用 `PciIo->Attributes(OperationEnable, EFI_PCI_IO_ATTRIBUTE_MEMORY)` 把硬件态与协议缓存态对齐。
   **我们已经有**：`unlock/app.c:238-252` 依 `saved_command` 的缺失位算 `needed` 并 enable；`unlock/port.c:176` 预检要求 `Command&2`（memory space）且 `Command&4`（bus master）为 0。
2. **不要拿历史常量比 SS0**（他们某次开机 SS0=`0x02436005`，另一次 `0x02434005`，死比常量会返回 `EFI_NOT_READY`）。
   **我们已经有，而且更稳**：`port.c` 的 `GuLatchEntrySelectors()` 在**本次开机**首次通过身份/GFW/PLM/WPR/内存/布局检查后锁存 SS0/SS1，后续只和锁存值比；并拒绝 `0xffffffff`、`0xbadf****`、`0x88888888`、`Ss1>0xf`。

### 由此推翻一个此前的选型：SS1 应改成 **Preserve**

`build.ps1` 的 `-StockProfile` 两个候选都只做 `SS0=0x88888888`，差别在 SS1：
- `entryLatchedSs1Full` → 额外一次受控写 `SS1=0x8`，上游自己的日志里写明 *"SS1 target 8 effect remains hardware untested"*
- `entryLatchedSs1Preserve` → **不写 SS1**

而 #58（**+35%/+49%**，SS1 保持 `0x4`）与 predator（**+85%**，SS1 保持 `0x2`）**都是在不碰 SS1 的情况下拿到全部 FP16/BF16 收益**的。#58 还明确记录了「SS0-only 配置下 TF32/FP32 不变」。
→ **结论：走 `entryLatchedSs1Preserve`**。收益一样，少一次未经验证的寄存器写，风险更低。

## ⚠️ 23:40 自查发现的两处错误（必须在按 U 之前纠正）

**错误 1：把 profile 补丁打在了错误的源码树上。**

`unlock/` 与 `internal-boot/unlock/` 是**两套独立实现**，行为不同：

| | `unlock/`（legacy 手工版） | `internal-boot/unlock/`（profile 化） |
|---|---|---|
| `port.h` | 硬编码 `GU_BOARD_ID 0x220410de` 等 3090 常量，**不 include `machine-profile.h`** | 第 6 行 `#include "machine-profile.h"`，全部常量由 profile 给出 |
| chip 检查 | `app.c:338` 硬编码 `chip!=0xb72000a1` | `app.c:292` `chip!=GU_CHIP_ID` |
| PROM 检查 | `app.c:376` 硬编码 `8ea297373e…`（3090 的 PROM 哈希） | `app.c:325` `PromCheck()` 走 profile |
| 能否靠 `-D` 改目标 | **不能**（`GU_TARGET_PCI_ID` 全仓库 0 处引用，我加的 `-D` 是死参数） | 能，`-DGU_PROFILE_*` |

我之前把混合 GOP 的 `DisplayCheck()` 加进了 `unlock/app.c`、把 profile 表加进了 `unlock/build.ps1` —— 那条路无论怎么传参，编出来的仍然是**认 3090 PROM 哈希的二进制**，会在 `Stage="prom"` 直接失败。

**正确做法**：改用 `internal-boot/unlock/` 树，需要两处移植（**已于 23:30 完成**）：
1. `internal-boot/unlock/build.ps1` 的 `$hwTable` + `-HardwareProfile` ValidateSet 增加 `lenovo-82rf-3060` 一行（`HeadlessOnly=$false`，我们要的是手工 U 确认路径）
2. 把 `unlock/app.c:128-192` 那段混合拓扑 `DisplayCheck()`（`HybridGopIsTarget`）搬到 `internal-boot/unlock/app.c`（那边的 `DisplayCheck()` 在第 90 行，仍是 AMD 专用 `AmdGopParent`）

**错误 2：`entryLatchedSs1Full` 是错的选择** —— 见上「由此推翻一个此前的选型」。

> 佐证：我们跑通的 `OBSERVE.EFI` 来自 `research/headless/build-observe.ps1`（走 `internal-boot/unlock/` 树），它能正确认出本机 GPU，正是因为那一树的 `machine-profile.h` 默认值已经是 `GU_PROFILE_LENOVO_82RF`。

## 溯源复核（2026-10-25 23:4x，独立子代理）

子代理用**上游 pinned 路径**独立重算了一遍全部资产：`ghfast.top` clone `Zagitta/gpu-unlock` → `checkout --detach 0ebdb1c6…` → `fetch_artifacts.py`（两个钉住输入都过 SHA256，`--offline` 复验也过）→ `tar.exe` 解源包 → `generate_v67.py` + `extract_boot_assets.py` → `verify_assets.py` **RESULT: PASS**。

它拿到了**那个 exact pinned 的 300 MB 包**（`nvidia-utils-610.43.03-1-x86_64_v3.pkg.tar.zst`，sha256 `e17e7c92…86e9`），手段是 `curl --resolve archive.cachyos.org:443:104.18.33.7` 钉到另一台 Cloudflare 边缘 IP（1.27 MB/s vs 20 KB/s）。

**关键结论**：它产出的 `fw-build/assets-pinned/` 与本文件上面记录的、我用两条捷径做出的 5 个文件 **逐字节相同，且都等于 `unlock/assets.json` 的钉值**；`NVIDIA-LICENSE` 也命中 notice 钉值 `c692fb14…07ad`。即：

- 「v67 本地合成」 ✔ 与官方 `build_payload()` 输出一致
- 「gsp 从 NVIDIA `.run` 抽取」 ✔ 与官方包内文件一致

→ 写进 S: 的那份资产链是有据可查的，不是"看起来能跑"。

## 下一步

1. ~~生成固件资产~~ ✅ 5/5 校验通过，且已被独立复算确认
2. ~~`internal-boot/unlock/app.c` 混合拓扑 `DisplayCheck()`~~ ✅（已打在**正确的**树上）
3. ~~`internal-boot/unlock/build.ps1` 增加 `lenovo-82rf-3060` 表项~~ ✅
4. ~~编译手工版实验 EFI + 部署到 S: + 登记启动项~~ ✅
   - `RTX3060-LAPTOP-EXPERIMENTAL-entryLatchedSs1Preserve.EFI`，65,536 B，sha256 `403d7893…ec617`
   - S:`\EFI\WindowsGPUUnlock\UNLOCK-3060-MANUAL.EFI` + S:`\RTX3090-UNLOCK\ASSETS\`（5 个）
   - 启动项 `{b05c3bb8-d07b-11f1-b16c-30894a35f1b9}`「GPU Unlock 3060 Laptop - EXPERIMENTAL (press U)」，顺序末尾
   - BCD 备份 `C:\ProgramData\WindowsGPUUnlock\UnlockBackups\20261025-234034566`
   - 回滚：`powershell -File scripts\register-unlock.ps1 -Rollback`（需提权）
5. **冷启动 → F12 → 选该启动项 → 出现提示按一次 U → 回固件 → 进 Windows**
6. 读 `S:\RTX3090-UNLOCK\RUN00\REPORT.TXT` 确认事务与 SS0/SS1 读回 → 跑 `bench.py unlocked` 出新旧对照

## 手工版被放开的一处闸门（必须记下来）

手工版 `app_io.c` 的 `UsbPath()` 原本**只允许从 USB 设备路径启动**（设备路径里必须有 `MSG_USB` 节点）。本机 H:/U: 两块移动盘都是 NTFS 整盘、没有空 FAT32 U 盘，所以在我们这个 profile 下改成复用上游 internal-boot 自己的媒体策略 `GuAllowedMediaPath(path, TRUE)`：要求设备路径里**有且只有一个 GPT HARDDRIVE 节点、且其 16 字节分区签名 == `boot/platform-config.h` 里 Configure.ps1 生成的专用分区 GUID**（`4c2a61ef-…`，即 S:），Windows ESP 的 `2e82c91f-…` 仍然被拒。**仅 `GU_PROFILE_LENOVO_82RF` 生效**，其它 profile 行为不变。

## 风险

- 事务含 **FLR**：若那个无路径控制台 GOP 实际挂在独显上，操作瞬间会黑屏（程序 1~2 秒后返回固件，F12 可重进 Windows）
- 固件资产哈希不符会被拒，不要用近似版本凑
- 失败时若打印 `STOP: cleanup cannot be proven`：该分支**不重置、不重试、死循环**，必须长按电源键断电
- 实测硬编码检查（`0x030000a1`、cfg[0xc8]=`0x00050011`、`BAR0=0x5e000000`、`subsystem=0x3ae817aa`、ROM BAR 未使能、PCIe DevCtl bit21）在 DIAG01 的 PCI 配置转储里**全部吻合**；本机 `Command=0x0003`（Memory+IO 开、BusMaster 关）也正好满足预检

## 风险

- 事务含 **FLR**：若那个无路径控制台 GOP 实际挂在独显上，操作瞬间会黑屏（程序 1~2 秒后返回固件，F12 可重进 Windows）
- 固件资产哈希不符会被拒，不要用近似版本凑

## 环境注意

- 上游脚本必须用 **Windows PowerShell 5.1**（`Get-Partition`/`Get-Disk` 属 Storage 模块，PS7 无）
- 我们自己写的 `.ps1` 一律**纯 ASCII**（5.1 按 ANSI 读无 BOM 文件，中文会把正则变无效）
- 存储类 cmdlet 需要提权会话（本会话普通用户下 `拒绝访问`）
- GitHub 直连被 TLS 层干扰，克隆走 `https://ghfast.top/https://github.com/...`
