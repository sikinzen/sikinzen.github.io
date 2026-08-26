---
title: "通过 ccache 提高 Android 编译效率的优化方案"
date: 2026-08-25T23:30:00+08:00
draft: false
description: "在 Unisoc T615 / Android 16 编译服务器上配置 ccache，实测三种编译方式（冷编译、热编译、增量编译）的耗时差异。ccache 让全量重编提速 1.65×，配合保留 out 的增量编译可提速 2.35×，并整理了其他 8 种编译加速手段。"
summary: "Android 全量编译动辄 3 小时以上？本文在 Unisoc T615 / Android 16 服务器实测 ccache：全量重编提速 1.65×，保留 out 的增量编译提速 2.35×，并给出完整配置步骤与 8 种进阶加速手段。"
categories: ["Android"]
tags: ["Android", "ccache", "编译加速", "AOSP", "构建优化", "Unisoc", "展讯"]
keywords: ["Android编译加速", "ccache配置", "AOSP编译优化", "Soong Ninja", "增量编译", "展讯T615", "build缓存"]
series: ["编译效率优化"]
---

## 背景

做 Android 系统级开发，最让人抓狂的往往不是写代码，而是**等编译**。一套 Unisoc T615 / Android 16 代码树全量编译，在 20 线程的服务器上也要跑将近 4 个小时。每次改几行代码就要重编一遍，时间成本极高。

Ccache 是业界成熟的编译器缓存方案，能在「同样源码再次编译」时直接命中缓存、跳过实际编译。本文记录我在编译服务器 `192.168.1.209` 上配置 ccache，并用**三种编译方式**做对照实测的全过程，以及由此延伸出的其他加速手段。

> **一句话结论**：开启 ccache 后，「全量重编」从 3h49m 降到 2h18m（**1.65×**）；日常改文件后**保留 out/ 做增量编译**可进一步降到 **1h38m（2.35×）**。增量编译 + ccache 是当前性价比最高的两项加速手段。

---

## 一、优化总览

| 模式 | 耗时 | 相对冷编 | 节省时间 | ccache 命中 | 说明 |
|------|------|---------|---------|------------|------|
| **A · 冷编译**（基准） | 3h49m02s（13,742s） | 1.00× | — | 0% | 无缓存 + 删除 out 全编 |
| **B · 热编译**（ccache） | 2h18m25s（8,305s） | **1.65×** | **39.6%** | 100% | 有缓存 + 删除 out 全编 |
| **C · 增量编译**（推荐） | 1h37m38s（5,858s） | **2.35×** | **57.4%** | 100% | 有缓存 + 保留 out + 重铺 overlay |

结论很清晰：

- **ccache 对「全量重编」有效**：C/C++ 缓存命中率 100%，整体提速 1.65×。代价是首次需要冷编填满缓存。
- **增量编译比「删 out + ccache」更快**：保留 out/ 后，未改动模块的 `.o` 与链接产物直接复用，连 ccache 的 I/O 都省了，相对热编译再快约 29%。

---

## 二、Ccache 配置（已在 192.168.1.209 落地）

### 2.1 生效原理

本代码树**原生支持 ccache**：当 `USE_CCACHE=1` 且 `CCACHE_EXEC` 指向 ccache 可执行文件时，`build/make/core/ccache.mk` 与 `build/soong/cc/config/global.go` 两条路径均会用 ccache 包装 C/C++ 编译器。

> 注意：ccache 仅对 **C/C++（含 clang）** 生效，对 Java/Kotlin 无效。Android 的 native 代码主体是 C/C++，因此收益主要体现在 native 重编阶段。

### 2.2 环境变量（已写入 ~/.bashrc 与 ~/.bash_profile）

```bash
# >>> ccache for Android/Unisoc builds (added by WorkBuddy 2026-08-25) >>>
export CCACHE_DIR=/media/D/ccache
export CCACHE_EXEC=/usr/bin/ccache
export USE_CCACHE=1
export CCACHE_MAXSIZE=100G
export CCACHE_COMPRESS=1
# <<< ccache >>>

# 持久化缓存参数
cd /media/D/Unisoc/T615_A16
ccache -M 100G
ccache -o compression=true
```

完整 Android 编译的缓存可达 20~50 GB，设 100 GB 并开启压缩比较稳妥。`.bashrc` 仅在交互式 shell 生效，若用非交互方式触发编译，需由脚本自行 `export` 兜底。

### 2.3 验证配置已生效

| 验证手段 | 命令 | 预期结果 |
|---------|------|---------|
| 查看配置 | `ccache --show-config` | `cache_dir = /media/D/ccache`、`max_size = 100.0G`、`compression = true` |
| 查看统计 | `ccache -s` | 编译中 `cache miss/hit` 持续增长；热编后 `cache hit rate` 接近 100% |
| 实时观察 | `watch -n 5 'ccache -s'` | 冷编见 miss 涨，热编见 hit 涨 |
| 源码确认 | `grep CC_WRAPPER sys/build/make/core/ccache.mk` | 能看到 `CC_WRAPPER := $(CCACHE_EXEC)` |

### 2.4 多版本共存建议

若同一台服务器同时编译 Android 14 与 Android 16，建议**按大版本拆分缓存目录**，避免工具链、宏定义差异导致相互淘汰：

```bash
# Android 14
export CCACHE_DIR=/media/D/ccache_a14
ccache -M 100G

# Android 16
export CCACHE_DIR=/media/D/ccache_a16
ccache -M 100G
```

也可通过编译脚本根据工程路径自动切换 `CCACHE_DIR`。

---

## 三、三种编译方式详解

三种方式的本质差异在于**是否清空缓存**与**是否删除 out/**：

| 模式 | 前置 | 清理 | 命令 | 结果 |
|------|------|------|------|------|
| **A · 冷编译** | `ccache -C` 清空缓存、`ccache -z` 清零统计 | 删除全部 5 个 out 目录 | `source zmake ... userdebug 24` | 缓存全 miss，耗时最长，作为基准 |
| **B · 热编译** | 保留 A 阶段填满的缓存 | 同样删除全部 5 个 out 目录 | `source zmake ... userdebug 24` | 缓存几乎全命中，验证 ccache 加速 |
| **C · 增量编译** | 保留缓存，且**不删除 out** | 仅重铺 overlay（`zgencode`） | `source zmake ... userdebug 24 r` | 复用 .o 与链接产物，日常改文件最快 |

> **关键**：若不清 out/ 直接二次编译，`make/ninja` 会因产物已存在而几乎不编译——那不是 ccache 的功劳，而是增量构建。要验证 ccache 命中，必须删 out/ 重新触发编译（即 B 模式）；而日常最快路径恰恰是故意保留 out/ 的 C 模式。

5 个 out 目录：

```text
sys/out
vnd/out
vnd/out_vendor
vnd/bsp/out
vnd/out_odm
```

实测数据明细：

| 模式 | 开始 | 结束 | 耗时 | 相对冷编 | 节省 | ccache 命中 |
|------|------|------|------|---------|------|------------|
| A 冷编译 | 12:39:04 | 16:28:06 | 3h49m02s（13,742s） | 1.00× | — | 0%（miss 85,505） |
| B 热编译 | 16:28:06 | 18:46:53 | 2h18m25s（8,305s） | 1.65× | 39.6% | 100%（hit 85,503 / miss 2） |
| C 增量编译 | 19:33:10 | 21:10:48 | 1h37m38s（5,858s） | 2.35× | 57.4% | 100%（hit 2,216 / miss 0） |

> B 模式命中率为 ccache 输出 `100.00%`，实际调用 85,505 次、命中 85,503 次、miss 2 次。C 模式因保留 out/，未改模块无需调用 ccache，故调用次数仅 2,216 次。

---

## 四、结论与最佳实践

1. **ccache 对全量重编有效**：在「删除 out 后完整重编」场景下，C/C++ 缓存命中率 100%，整体提速 1.65×。代价是首次需要冷编填满缓存。
2. **增量编译比「删 out + ccache」更快**：保留 out/ 后，未改动模块的 `.o` 与链接产物直接复用，连 ccache 的 I/O 都省了，再快约 29%。
3. **最佳实践**：
   - 日常改几文件 → 用 **C 增量**：`source zmake ... userdebug 24 r`（末尾 `r` = remake，跳过 cleanall、保留 out/）
   - 切换大版本 / 彻底重编 / 怀疑产物污染 → 用 **B 热编译**：先删全部 5 个 out 目录，再 `source zmake ...`
   - 调试单模块 → 用 `mm` / `mma`，秒级~分钟级

---

## 五、其他可进一步加速编译的方式

| 手段 | 原理 / 适用 | 预期收益 |
|------|------------|---------|
| 增量编译（保留 out/） | 日常改文件后不清理，仅重编受影响模块 | 本测试最快（1h38m） |
| 单模块编译 mm / mma | 仅编译当前调试模块，跳过全树 | 调试单模块秒级~分钟级 |
| 分布式编译 distcc / icecc | 多机并行分发编译任务 | 团队级线性扩展，需组网 |
| 远程缓存（如 Goma 类） | 跨机器共享编译产物 | 多机首次即命中 |
| 硬件升级 | 内存（破 OOM）、NVMe SSD（I/O 瓶颈）、更多 CPU 核 | 消除瓶颈，稳定提速 |
| 构建调优 | `SOONG_PARALLEL_LINK_EXECUTION`、`ninja -j`、关 sanitizer/调试符号 | 数分钟~数十分钟 |
| out/ 放 tmpfs/ramdisk | 内存充足时去磁盘 I/O（需大内存） | I/O 密集阶段明显 |
| 精简 lunch 目标 | 最小产品配置，少编模块 | 按需裁剪 |

---

## 六、环境与数据说明

| 项 | 值 |
|----|----|
| 服务器 | 192.168.1.209（Ubuntu 18.04） |
| CPU | Intel i9-10900K，20 线程 |
| 内存 / Swap | 31 GB 物理内存 + 33 GB Swap（原 2 GB，新增 32 GB 交换文件） |
| 代码树 | /media/D/Unisoc/T615_A16（AOSP Soong + Ninja） |
| 编译目标 | zprj/FS310L6/CF1/WA09_CD3384_HONOR_GO userdebug |
| ccache | /usr/bin/ccache 3.4.1，CCACHE_DIR=/media/D/ccache，100 GB，压缩开启，实测占用 ~10 GB |
| 关键修复 | Swap 2 GB → 33 GB，解决 soong_build 峰值 ~32 GB RSS 导致的 OOM |
| 退出码 rc=1 | 三次均为打包脚本索取本 GO 配置未生成的 GSI/OTA 镜像，核心 .pac 固件正常产出，非编译失败 |

### 日志与数据来源

- **服务器端（最全）**：`/media/D/Unisoc/T615_A16/ccache_test_logs/` 含 `build1_cold.log`、`build2_warm.log`、`build3_incremental.log`、`RESULT.txt`、`runner_stdout.log`
- **时间标记**：每个日志文件头部含 `# START`、尾部含 `# END ... duration=...s`

### 遗留事项

- 临时开启的 NOPASSWD sudo（`/etc/sudoers.d/zz_build`）与 32 GB 交换文件（`/media/D/swapfile_32g`）当前为临时生效，重启后失效；如需固化可写入 `/etc/fstab`，或按需撤回。
- 如需严格 rc=0，可在项目配置中关闭 GSI/OTA 打包项，或单独验证打包脚本；不影响 ccache 加速结论。
