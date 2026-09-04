---
title: "Ubuntu 18.04 装系统趟坑实录：U盘启动 + 分区 + 黑屏（nomodeset）+ 花屏（LightDM）"
date: 2026-09-04T10:30:00+08:00
draft: false
description: "《Ubuntu 18.04 编译服务器实战》系列第一篇。本文记录的是最近给几台新机器装 Ubuntu 18.04 时踩到的坑（其中一台机型：72 核 Intel Xeon E5-2697 v4 / 128G 内存 / 三块 SSD 480G+1T+3.5T）。从 U 盘装机到进桌面可能会依次遇到：①进不去 U 盘安装界面（BIOS/UEFI 启动模式没配对，进 GRUB rescue）；②安装器分区异常（EFI 分区大小、整盘无分区表导致 +/- 置灰）；③128G 大内存要不要 swap；④安装/启动黑屏（老内核不支持新核显 KMS，加 nomodeset）；⑤进桌面花屏（GDM3 默认 Wayland 在老 Mesa 上渲染异常，换 LightDM）。本文按安装时间线给出现象速判、根因原理、已验证修复与未验证备选，并附脱敏参数对照表。"
summary: "新硬件装 Ubuntu 18.04 的四道坎：进不去 U 盘（UEFI 模式配对）、分区异常（EFI 分区 + 重建 GPT）、大内存 swap、黑屏用 nomodeset、花屏换 LightDM。按安装时间线组织，含速判表、原理、已验证步骤与未验证备选，系列第一篇。"
categories: ["Linux"]
tags: ["Ubuntu", "18.04", "安装", "U盘启动", "UEFI", "分区", "swap", "黑屏", "花屏", "nomodeset", "KMS", "Wayland", "GDM", "LightDM", "故障排查"]
keywords: ["Ubuntu18.04安装", "U盘启动GRUBrescue", "UEFI与BIOS区别", "EFI分区大小", "nomodeset", "KMS不支持新核显", "GDM Wayland花屏", "LightDM修复", "显示管理器", "编译服务器装系统"]
series: ["Ubuntu18.04编译服务器实战"]
---

> **系列说明**：本文是《Ubuntu 18.04 编译服务器实战》系列**第一篇**，按**安装时间线**讲「装系统 + 图形排障」全过程（U 盘启动、分区、swap、黑屏、花屏）。
> 系列第二篇《[Ubuntu 18.04 配置 Android 11–17 编译环境]({{< ref "ubuntu1804-android-build-env-setup.md" >}})》讲装好系统后如何配置 Android 11–17 的编译环境（依赖、ccache 分目录、代码下载避坑）。
> 两篇都做了**脱敏处理**，文末「参数对照表」汇总了所有需要你按自己环境替换的占位符。

---

## 〇、按安装阶段一眼分流

装一台「新硬件 + Ubuntu 18.04」机器，遇到的坑按**时间先后**排列如下。先定位自己卡在哪一阶段，再跳到对应章节。

| 卡在哪个阶段 | 典型现象 | 跳到 |
|---|---|---|
| **① 进不去 U 盘安装界面** | 插 U 盘、设 U 盘启动后仍进 `grub rescue>`，或直接从硬盘启动 | [一](#一进不去-u-盘安装界面biosuefi-启动配置) |
| **② 安装器分区异常** | EFI 分区不知分多大；`/dev/sdc` 等整盘无分区表，`+`/`-` 按钮置灰 | [二](#二分区与磁盘准备安装器里的坑) |
| **③ 大内存要不要 swap** | 128G 内存，纠结是否开 swap、开多大 | [三](#三128g-内存要不要开-swap) |
| **④ 安装/启动黑屏** | 选 `Install Ubuntu` 后黑屏（NumLock 有响应），或装完重启进不去桌面 | [四](#四安装启动黑屏nomodeset-救安装) |
| **⑤ 进桌面后花屏** | 能进登录/桌面但撕裂、糊屏、残影；TTY 与 `startx` 正常；同硬件 22.04 没事 | [五](#五进桌面花屏lightdm-绕过-wayland) |

共同前提：**新硬件（新核显/新显卡）+ 老系统（18.04 内核 4.15 / Mesa 18.2）**。根因各不相同，但**都不是显卡坏了**。

---

## 一、进不去 U 盘安装界面（BIOS/UEFI 启动配置）

### 1.1 现象：进 GRUB rescue 而非安装界面

插好 Ubuntu 安装盘、设了 U 盘启动，屏幕却显示：

```
Booting from Hard drive C:
error: file `/boot/grub/i386-pc/normal.mod` not found.
Entering rescue mode...
grub rescue>
```

关键判断：**`Booting from Hard drive C:` 说明机器根本没从 U 盘启动，而是读了硬盘上旧的、已损坏的 GRUB**，才进 rescue。

> 若同一张 U 盘在别的电脑能正常进安装界面，那问题就集中在**这台机器的启动配置**，而不是 U 盘本身。

### 1.2 根因：启动模式 / 启动项没配对

| 排查项 | 说明 | 操作 |
|---|---|---|
| 1. BIOS 未真正保存 U 盘优先 | 改了 Boot Order 但没 `F10` 保存，或误选了 Hard Drive | Boot 选项卡把 USB 调到首位 → **Save & Exit** |
| 2. 启动模式不匹配 | U 盘是 UEFI 制作，BIOS 却设 Legacy；或相反 | BIOS 中切换 **UEFI / Legacy(CSM)**，与 U 盘一致 |
| 3. 选错 U 盘启动项 | 同个 U 盘可能同时出现带 "UEFI" 前缀和不带的两个项 | 分别试 **UEFI: USB** 和 **USB HDD** |
| 4. Secure Boot / Fast Boot 拦截 | 部分主板跳过第三方 USB 启动 | 关闭 **Secure Boot** 和 **Fast Boot** |
| 5. USB 接口兼容性 | 老主板在 USB 3.0 口识别不稳 | 换到 **USB 2.0 口（黑色）**，台式机优先后置口 |

### 1.3 快速修复步骤

1. 重启按 `DEL` / `F2` 进 BIOS / 启动菜单。
2. 找 Boot Mode，确认与 U 盘制作方式一致（Rufus/UNetbootin 默认多为 **UEFI**）。
3. Boot 选项卡确认启动顺序首位是 U 盘。
4. 保存退出，重启后立刻按 `F11` 手动调出**一次性启动菜单**，**手动选 U 盘**最稳妥（比改 Boot Order 更不易踩坑）。

### 1.4 原理：BIOS 与 UEFI 的区别与选择

| 对比项 | BIOS / Legacy（传统） | UEFI（现代） |
|---|---|---|
| 全称 | Basic Input/Output System | Unified Extensible Firmware Interface |
| 启动方式 | 通过 MBR 引导扇区读 GRUB 第一阶段 | 通过 FAT32 的 EFI 系统分区读取 `.efi` 文件 |
| 硬盘分区表 | 只认 **MBR**（最大 2TB、4 主分区） | 支持 **GPT**（盘更大、分区更多） |
| 启动速度 | 较慢 | 更快 |
| 安全性 | 无签名校验 | 支持 **Secure Boot** |
| 兼容性 | 老系统、老主板、MBR 盘 | Win8+ / 现代 Linux（含 Ubuntu 22.04+） |

**为什么切到 UEFI 就好了**：Ubuntu 安装盘是按 UEFI 方式制作的。原来 BIOS（Legacy）模式下，机器用传统方式找引导 → 硬盘上有**旧的、已损坏的 Legacy GRUB** → 找不到 `normal.mod` → 进 rescue；切到 **UEFI** 后改用 EFI 分区引导 → 正确加载 U 盘里的 Ubuntu 安装环境 → 正常。

> **核心原则：安装盘、硬盘引导、BIOS 设置三者的「模式」必须一致**，否则就找不到引导。

**事后要不要改回 BIOS？——不要改。**

- 用 UEFI 启动安装盘，装出来的 Ubuntu 引导也是 **UEFI 模式**（写 EFI 分区 + `grubx64.efi`）。
- 装完又切回 Legacy → 重启用 Legacy 找引导 → 硬盘上是 UEFI 引导，找不到 → **又回到 GRUB rescue**。
- **结论：保持 UEFI，装完也别动。**

**安装完成注意事项：**
1. 全程保持 UEFI，不要中途切换模式。
2. 让 Ubuntu 自动分区（会建 EFI 系统分区），或手动确保有 EFI 分区。
3. 装完重启直接保持 UEFI，无需再手动选 U 盘。
4. 若以后双系统（保留 Windows），也要保证 Windows 是 **UEFI 模式**，否则两系统模式打架。

---

## 二、分区与磁盘准备（安装器里的坑）

### 2.1 EFI 系统分区（ESP）该分多大

| 场景 | 推荐大小 | 说明 |
|---|---|---|
| 最小可用 | 100 MB | 单系统勉强够，不推荐 |
| 单系统 Ubuntu | **300–512 MB** | 能容纳多内核引导文件，升级不爆 |
| 双系统（Win+Ubuntu） | **512 MB** | 两系统共用一个 ESP |
| 保守上限 | 1 GB | 再大无意义 |

实操要点：
1. **自动分区**：选「清除整盘并安装」或「与 Win 共存」，安装器**自动建好合适大小 EFI 分区**。
2. **手动分区**：分区类型选 **EFI System Partition**（或挂载点 `/boot/efi`），格式 **FAT32**，大小 **512 MB**，放磁盘最前面最稳妥。
3. **不要**格式化成 ext4 或其它格式——必须是 **FAT32**，否则 UEFI 读不了。

### 2.2 磁盘直接格式化、无分区表（sdc/sdd 无法分区、+/- 置灰）

**现象（安装器分区界面）**：

| 设备 | 显示内容 | 异常点 |
|---|---|---|
| `/dev/sdc` | ext4，挂载点 `/`，480 GB | 是 `/dev/sdc`，**不是 `/dev/sdc1`** |
| `/dev/sdd` | ext4，挂载点 `/media/Project2`，960 GB | 是 `/dev/sdd`，**不是 `/dev/sdd1`** |

**原因**：`/dev/sdc`、`/dev/sdd` 是**整个磁盘直接被格式化为 ext4**（之前直接 `mkfs.ext4 /dev/sdc`），**没有分区表结构**。安装器认为「这块盘已用完」，无法再新建分区，`+`/`-` 按钮因此置灰。

**风险提醒（动手前先确认数据）**：

| 操作 | 风险 |
|---|---|
| 删除 `/dev/sdc` | 清空系统安装目标盘（预期操作） |
| 删除 `/dev/sdd` | 清空 Project2 数据盘，**先备份** |
| 重新分区前 | 确认 `/dev/sda` 的 EFI 分区（sda1）是否为引导分区 |

**解决方案：先用命令行 / GParted 重建分区表**

> ⚠️ 以下命令会清空 sdc 和 sdd 所有数据，执行前确认数据安全。

**步骤 1：打开终端**（安装界面按 `Ctrl + Alt + T`）

**步骤 2：查看磁盘结构，确认无分区**

```bash
sudo lsblk
sudo fdisk -l
```

确认 `/dev/sdc`、`/dev/sdd` 没有 `sdc1`、`sdd1` 这类分区。

**步骤 3：擦除并新建 GPT 分区表**

```bash
# 擦除 sdc 上的文件系统签名
sudo wipefs -a /dev/sdc
# 创建 GPT 分区表
sudo parted /dev/sdc mklabel gpt

# 同样处理 sdd
sudo wipefs -a /dev/sdd
sudo parted /dev/sdd mklabel gpt
```

若 `wipefs` 不存在，可用：

```bash
sudo dd if=/dev/zero of=/dev/sdc bs=1M count=100
sudo dd if=/dev/zero of=/dev/sdd bs=1M count=100
```

**步骤 4：返回安装器重新扫描**

关掉终端，回到安装器分区界面，点 **Back** 再 **Continue** 刷新，应能看到 `/dev/sdc`、`/dev/sdd` 变成 **free space**，`+`/`-` 按钮变亮。

**替代方案：GParted 图形化**

```bash
sudo gparted
```

1. 右上角选 `/dev/sdc` → 菜单 **Device → Create Partition Table → gpt** → Apply。
2. 同样处理 `/dev/sdd`。
3. 关闭 GParted，回安装器。

**处理完之后的分区建议**

| 磁盘 | 建议操作 |
|---|---|
| `/dev/sdc` | 新建 `/dev/sdc1`，全部空间，挂载点 `/`，ext4 |
| `/dev/sdd` | 新建 `/dev/sdd1`，全部空间，挂载点 `/media/Project2`，ext4 |

**关键提醒：**
- **Boot loader 安装位置**：若引导盘与系统盘不同（如系统装 sdc、EFI 在 sda1），建议把 boot loader 指向带 EFI 分区的那块盘，让 EFI 引导统一管理，避免多盘混乱。
- **不要只格式化不解分区表**：核心问题是盘被直接格式化、无分区表，格式化解决不了，必须先 `mklabel gpt`。

---

## 三、128G 内存要不要开 swap

### 3.1 结论

**128 GB 内存日常基本用不到 swap。但建议保留 2–4 GB swapfile 作安全阀，而不是完全不开。**

### 3.2 为什么基本用不到

- swap 是物理内存不够时把不常用内存页换到磁盘。
- 128 GB 对个人开发、编译、多开、日常办公几乎不可能耗尽。
- 现代内核有 **zram**（内存里压缩 swap），进一步降低对磁盘 swap 依赖。

### 3.3 何时需要 swap

| 场景 | 是否需要 swap |
|---|---|
| 正常开发 / 编译 / 多开浏览器 | 不需要，留小 swap 无妨 |
| 内存耗尽（OOM） | 有 swap 先换页、慢但活着；无 swap 时内核 **OOM killer 杀进程** |
| **休眠（hibernate）** | 需要 swap **≥ 内存**，即 128 GB——太浪费，**不建议** |
| 内核崩溃转储（kdump） | 需预留一小块，但很小 |
| 内存压缩兜底 | zram 已覆盖 |

> 关键区别：**休眠**需要 swap = 内存大小；**防 OOM**只需很小一块。128 GB 不该为休眠牺牲 128 GB 磁盘。

### 3.4 推荐配置与操作

| 方案 | 大小 | 适用 |
|---|---|---|
| **推荐：小 swapfile** | **2–4 GB** | 安全阀，防 OOM，不占空间 |
| 完全不开 | 0 | 内存极大且从不跑爆表任务，可接受偶尔进程被杀 |
| 休眠用 | = 内存 128 GB | 不推荐，纯浪费 NVMe 空间 |

手动分区时把空间全给 `/`，装完用 swapfile 补一个小的：

```bash
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

验证：

```bash
free -h
swapon --show
```

---

## 四、安装/启动黑屏（nomodeset 救安装）

### 4.1 根因一句话

内核已加载、NumLock 灯有响应 = **系统没死机，只是显示无输出**。本机是 18.04 默认内核（4.15 / HWE 5.4）太老，**不支持新主板 + 11/12 代 Intel 核显（UHD 750 / Xe）的 KMS（内核模式设置）**，导致黑屏。加 `nomodeset` 强制退回基础显示模式即可进系统。

### 4.2 术语速查

| 术语 | 说明 |
|---|---|
| **KMS** | 内核模式设置，让内核接管显卡分辨率切换；老内核 + 新核显易黑屏 |
| **nomodeset** | 启动参数，禁用 KMS，退回基础显示模式，绕开黑屏 |
| **HWE 内核** | 把新版 Ubuntu 的新内核回灌到旧 LTS，提升新硬件支持 |
| **grub>** | 按 Shift/Esc 时机不对时进入的 GRUB 命令行，不能直接编辑启动项 |

### 4.3 已验证步骤（按实际顺序）

#### 步骤 1：安装时加 `nomodeset` 进安装界面 ✅

在启动菜单操作（**不要按回车**）：

1. 方向键选中 **`Install Ubuntu`**
2. 按 **`e`** 进入启动参数编辑
3. 找到 `linux` 开头那行，行尾 `quiet splash` 后追加 `nomodeset`：
   ```
   ... quiet splash nomodeset ---
   ```
4. 按 **`Ctrl+X` 或 `F10`** 启动 → 进入安装界面，正常安装

#### 步骤 2：安装后重启又黑屏 → 进桌面 ✅

重启后再次黑屏，因为 `nomodeset` 只加在了 U 盘那次启动，硬盘里的 GRUB 没有它。

**2.1 调出 GRUB 菜单**

开机在主板 Logo 出现时，**连续点按 `Esc`（UEFI）**（不要按住，按住会进 `grub>` 命令行）。

**2.2 误入 `grub>` 命令行时退回菜单**

若不小心进了 `grub>` 命令行，输入：
```text
normal
```
此时开机后仍然无法回到 GRUB 菜单，一般是需要重启电脑后，连续点击 ESC 按键，等跳出 grub 菜单的时候就停止按按键，不能一直按着。

成功则回到 GRUB 菜单（无效再试 `exit`，仍不行 `reboot` 重来）。

**2.3 加 `nomodeset` 进桌面**

回到菜单后：
1. 选中 **`Ubuntu`**，按 **`e`**
2. `linux` 行末尾加 `nomodeset`
3. 按 `Ctrl+X` / `F10` 启动 → 进入桌面

#### 步骤 3：永久写死 `nomodeset`（保命，防重启再黑屏）✅

进桌面后终端执行：
```bash
sudo nano /etc/default/grub
```
改成：
```bash
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash nomodeset"
```
保存退出（`Ctrl+O` → 回车 → `Ctrl+X`），**必须**更新 GRUB：
```bash
sudo update-grub
```
> 此后每次启动都带 `nomodeset`，不再黑屏。

#### 步骤 4：确认显卡与系统版本 ✅

```bash
ubuntu-drivers devices     # 列出核显 + WiFi，确认有无独显
sudo ubuntu-drivers autoinstall   # 提示 No drivers found —— 正常，无独显可装
lsb_release -a             # 确认 Ubuntu 18.04.6 LTS
```

### 4.4 未验证备选（本次未实测，存疑备查）

> 以下方案**未在本机实际执行确认**，仅作为已知可行思路保留。

**方案 B：装 OpenSSH，远程编译（最省事）** ⚠️ 未验证

`nomodeset` 已永久写死后，本地显示器只需能开终端，真正的重活在另一台电脑 SSH 进来做：
```bash
sudo apt update
sudo apt install openssh-server -y
sudo systemctl enable ssh
sudo systemctl start ssh
ip addr show | grep inet        # 记下本机 IP
```
> 18.04 已 EOL，`apt update` 报 404 时先换源：
> ```bash
> sudo sed -i 's|http://.*ubuntu.com|http://old-releases.ubuntu.com|g' /etc/apt/sources.list
> sudo apt update
> ```

**方案 D：升级内核 + Mesa 让核显正常工作，再去掉 nomodeset** ⚠️ 未验证

若本地显示器分辨率/流畅度不满意，可升级内核 + Mesa 让新核显正常工作（存在稳定性风险，**操作前务必先完成步骤 3 的 `nomodeset` 永久化并确认 SSH 可用**，图形万一出问题也能远程救）：
```bash
# 升级内核到 5.15 LTS
sudo add-apt-repository ppa:cappelikan/ppa -y
sudo apt update && sudo apt install mainline -y
# 打开 mainline 图形工具，选 5.15.x LTS 安装，重启

# 升级 Mesa 驱动
sudo add-apt-repository ppa:kisak/kisak-mesa -y
sudo apt update && sudo apt upgrade -y

# 去掉 nomodeset 测试
sudo nano /etc/default/grub   # 改回：GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"
sudo update-grub && sudo reboot
```
- 不黑屏 → 核显正常；又黑屏 → 改回 `nomodeset` 保留。

### 4.5 命令速查

| 目的 | 命令 | 验证状态 |
|---|---|---|
| 永久 nomodeset | 编辑 `/etc/default/grub` 后 `sudo update-grub` | ✅ |
| 确认显卡 | `ubuntu-drivers devices` | ✅ |
| 看系统版本 | `lsb_release -a` | ✅ |
| 装 SSH 服务 | `sudo apt install openssh-server -y` | ⚠️ |
| 看本机 IP | `ip addr show \| grep inet` | ⚠️ |
| 升级主线内核工具 | `sudo apt install mainline -y` | ⚠️ |
| 升级 Mesa | `sudo add-apt-repository ppa:kisak/kisak-mesa -y && sudo apt upgrade -y` | ⚠️ |
| 18.04 换 EOL 源 | `sudo sed -i 's\|http://.*ubuntu.com\|http://old-releases.ubuntu.com\|g' /etc/apt/sources.list` | ⚠️ |

---

## 五、进桌面花屏（LightDM 绕过 Wayland）

### 5.1 30 秒判断（四者全中就是它）

| 现象 | 是否命中 |
|---|---|
| 开机自动进图形登录/桌面 → **花屏**（撕裂、糊屏、残影、色彩错乱） | ✅ |
| `Ctrl+Alt+F2~F6` 切到命令行（TTY）完全正常 | ✅ |
| 命令行里执行 **`startx` 能正常进入图形界面** | ✅ |
| 同一台硬件装 **Ubuntu 22.04 无此问题** | ✅ |

**四者全中 → 不是显卡坏了**，是 Ubuntu 18.04 的 **GDM3 登录界面默认跑在 Wayland 上**，而老图形栈对新显卡的 Wayland 渲染支持残缺，导致花屏。绕过 Wayland（用纯 X11 的 `startx` 或 LightDM）即可解决。

### 5.2 根因与原理

**图形启动分两层**：
- **显示管理器（Display Manager，如 GDM3 / LightDM）**：开机自动运行，负责画登录界面、把用户带进桌面。
- **X 会话（Xorg）**：真正的图形服务，`startx` 直接启动它。

`startx` 能正常显示，说明 **Xorg + 内核通用显卡驱动（modesetting）+ Mesa 用户态驱动这套组合是工作的**。问题被锁定在 **GDM 这一层**。

**真凶：GDM3 的 Wayland 登录界面**。Ubuntu 18.04 的 GDM3 默认用 **Wayland** 渲染登录界面（greeter）。Wayland 依赖更新的 EGL/GBM 渲染路径，而 2019 年后推出的新显卡（Intel 11 代及以后核显、AMD RX 5000 及以后、NVIDIA RTX 30/40 系），在 18.04 的**老内核 4.15 + 老 Mesa 18.2** 下，这条路径支持残缺 → 花屏。`startx` 走纯 X11，完全绕开 Wayland，所以正常。

**为什么 22.04 没事（对照）**：

| 组件 | 18.04 | 22.04 | 影响 |
|---|---|---|---|
| 内核 | 4.15（HWE 最高 5.4） | 5.15+ | 新显卡内核态驱动 5.8~5.16 才陆续合入 |
| Mesa | 18.2 | 22.0+ | Intel 11/12 代核显、AMD RDNA2/3 需 Mesa 21+ |
| GDM Wayland 路径 | 不成熟 | 成熟 | 新显卡 Wayland 渲染稳定 |

### 5.3 已验证方案：换成 LightDM（推荐，最稳）✅

```bash
# 1. 若当前花屏看不清，先用 Ctrl+Alt+F2 切到 TTY 登录
# 2. 安装 LightDM（安装过程会弹对话框，选 lightdm 为默认显示管理器）
sudo apt update
sudo apt install lightdm

# 3. 若没弹选择框，手动指定默认显示管理器：
sudo dpkg-reconfigure gdm3      # 在列表里选 lightdm

# 4. 重启使新的显示管理器生效（会结束当前图形会话，先存工作）
sudo reboot
```

**生效原理**：LightDM 是**纯 X11 的显示管理器**，不提供 Wayland 登录路径，登录界面与后续桌面会话全部走 X11，正好避开 18.04 老图形栈在新显卡上出问题的 Wayland 渲染路径，与 `startx` 正常是同一套机制。

**验证结果（本次实测）**：
- ✅ 重启后登录界面正常，无花屏；
- ✅ 进入桌面后拖动窗口、显示正常；
- ✅ 分辨率正常（非 fallback 低分辨率）；
- ✅ 整体可用，问题解决。

### 5.4 未验证备选

> 以下方案**未在当前机器上验证**，仅作备选思路保留。

**方案 A：禁用 GDM 的 Wayland（改动最小）** ❌ 尚未验证

让 GDM 登录界面也走 X11，不换显示管理器本身：
```bash
sudo nano /etc/gdm3/custom.conf
# 把被注释的行打开，设为：
WaylandEnable=false
sudo reboot
```

**方案 C：换 Xfce 轻量桌面（针对「登录后桌面仍花屏」）** ❌ 尚未验证

若换 LightDM 后登录界面正常、但登进 GNOME 后桌面依然花屏，说明 Mutter 合成器在老 Mesa 上渲染异常，可换更轻量的桌面：
```bash
sudo apt install xfce4
# 注销后，在登录界面右下角齿轮图标选 "Xfce Session"
```

---

## 六、诊断与常用命令速查

### 6.1 安装 / 图形排障诊断

```bash
# 1. 看显卡型号（定位根因最直接）
lspci -k | grep -EA3 'VGA|3D|Display'

# 2. 当前会话是不是 Wayland（Wayland 显示 "Type=wayland"）
loginctl show-session "$(loginctl | awk '/seat/{print $1}')" -p Type

# 3. 当前用的是哪个显示管理器
cat /etc/X11/default-display-manager

# 4. 另起一个 X 会话测试（见「五、进桌面花屏」四连判）
startx -- :1 &

# 5. 看当前 grub 启动参数里有没有 nomodeset（见「四、安装/启动黑屏」）
grep nomodeset /etc/default/grub
```

### 6.2 磁盘 / 分区 / swap 速查

```bash
# 查看磁盘与分区
sudo lsblk
sudo fdisk -l

# 擦除文件系统签名 + 建 GPT 分区表（会清数据，先备份！）
sudo wipefs -a /dev/sdc
sudo parted /dev/sdc mklabel gpt

# 图形化分区工具
sudo gparted

# 创建 swapfile（2–4 GB 即可）
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# 验证 swap
free -h
swapon --show
```

---

## 七、经验与建议

1. **新硬件 + 老系统（18.04）问题，优先怀疑「驱动/显示路径/启动模式不兼容」**，而非硬件坏了。命令行正常 + `startx` 正常（花屏）或 NumLock 有响应（黑屏）是关键判断依据。
2. **安装阶段先保证「模式一致」**：U 盘制作方式、BIOS 启动模式、硬盘引导方式三者统一（都 UEFI 或都 Legacy），否则进 GRUB rescue。装完**别改回**原模式。
3. **黑屏 → `nomodeset`，花屏 → 换 LightDM**，两条都是「绕开老栈不支持的新路径」，与历史成功经验一致。
4. **整盘被直接格式化会导致安装器无法分区**（`+/-` 置灰），本质是缺分区表，必须先 `mklabel gpt` 再分，光格式化没用。
5. **Ubuntu 18.04 标准支持已于 2023 年结束**，apt 安全更新已停。若这台机器是为跑老工具链（交叉编译、老 SDK），更推荐在 22.04 宿主机上用 `docker run -it ubuntu:18.04` 或虚拟机获得老环境——既避开图形坑，又持续获得宿主系统的安全性。

---

## 八、参数对照表（脱敏）

本文已对作者专属信息做脱敏。下表是**你按自己环境需要替换的全部占位符**，也是日后回看时一眼能找到的「要配置什么」：

| 占位符 | 含义 | 你的取值 |
|---|---|---|
| `<HOST_BOARD>` | 触发黑屏/启动异常的硬件特征（示例：技嘉 Z590 + 11/12 代 Intel 核显 UHD 750/Xe） | 任何「新硬件 + 老内核 4.15」组合都适用，换成你的主板/核显即可 |
| `<DISK_SYS>` / `<DISK_DATA>` | 系统盘 / 数据盘设备名（文中示例 `sdc` / `sdd`，实际以 `lsblk` 为准） | 以你机器的实际设备名为准，勿照抄 |
| `<EFI_DISK>` | 承载 EFI 系统分区的磁盘（文中示例 `sda`，其 `sda1` 为 ESP） | 以你机器 EFI 分区所在盘为准 |

> 说明：本篇**不含内网 IP、账号、密码、公司域名**等敏感信息，故脱敏表很轻。真正需要替换大量参数的场景在系列第二篇（Android 编译环境），那里有完整的脱敏对照表。
