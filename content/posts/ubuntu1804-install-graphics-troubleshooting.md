---
title: "Ubuntu 18.04 安装与图形排障实录：黑屏（nomodeset 救安装）+ 花屏（LightDM 绕过 Wayland）"
date: 2026-09-04T10:30:00+08:00
draft: false
description: "《Ubuntu 18.04 编译服务器实战》系列第一篇。同一台「新硬件 + 老系统」机器在装 Ubuntu 18.04 时会遇到两类图形问题：①安装/启动黑屏（老内核 4.15 不支持新核显 KMS，加 nomodeset 即可）；②进桌面后花屏（GDM3 默认 Wayland 登录界面在老 Mesa 上渲染异常，换纯 X11 的 LightDM 即可）。本文给出现象速判、根因原理、已验证修复与未验证备选，并附脱敏参数对照表。"
summary: "新硬件装 Ubuntu 18.04 两道图形坎：安装黑屏用 nomodeset（老内核不支持新核显 KMS），进桌面花屏换 LightDM（GDM 的 Wayland 路径在老 Mesa 上崩）。本文含速判表、原理、已验证步骤与未验证备选，系列第一篇。"
categories: ["Linux"]
tags: ["Ubuntu", "18.04", "黑屏", "花屏", "nomodeset", "KMS", "Wayland", "GDM", "LightDM", "故障排查"]
keywords: ["Ubuntu18.04黑屏", "nomodeset", "KMS不支持新核显", "GDM Wayland花屏", "LightDM修复", "显示管理器", "编译服务器装系统"]
series: ["Ubuntu18.04编译服务器实战"]
---

> **系列说明**：本文是《Ubuntu 18.04 编译服务器实战》系列**第一篇**，聚焦**安装系统与图形排障**（装系统黑屏、进桌面花屏）。
> 系列第二篇《[Ubuntu 18.04 配置 Android 11–17 编译环境]({{< ref \"ubuntu1804-android-build-env-setup.md\" >}})》讲装好系统后如何配置 Android 11–17 的编译环境（依赖、ccache 分目录、代码下载避坑）。
> 两篇都做了**脱敏处理**，文末「参数对照表」汇总了所有需要你按自己环境替换的占位符。

---

## 〇、两种问题一眼分流

| 你遇到的是 | 典型现象 | 跳到 |
|---|---|---|
| **装系统 / 启动黑屏** | U 盘选 `Install Ubuntu` 后黑屏（NumLock 灯有响应），或装完重启进不去桌面 | [问题一](#问题一安装启动黑屏nomodeset-救安装) |
| **进桌面后花屏** | 能进登录/桌面但撕裂、糊屏、残影、色彩错乱；TTY 与 `startx` 正常；同硬件 22.04 没事 | [问题二](#问题二进桌面花屏lightdm-绕过-wayland) |

两类的共同前提：**新硬件（新核显/新显卡）+ 老系统（18.04 内核 4.15 / Mesa 18.2）**。根因不同，但都**不是显卡坏了**。

---

## 问题一：安装/启动黑屏（nomodeset 救安装）

### 1.1 根因一句话

内核已加载、NumLock 灯有响应 = **系统没死机，只是显示无输出**。本机是 18.04 默认内核（4.15 / HWE 5.4）太老，**不支持新主板 + 11/12 代 Intel 核显（UHD 750 / Xe）的 KMS（内核模式设置）**，导致黑屏。加 `nomodeset` 强制退回基础显示模式即可进系统。

### 1.2 术语速查

| 术语 | 说明 |
|---|---|
| **KMS** | 内核模式设置，让内核接管显卡分辨率切换；老内核 + 新核显易黑屏 |
| **nomodeset** | 启动参数，禁用 KMS，退回基础显示模式，绕开黑屏 |
| **HWE 内核** | 把新版 Ubuntu 的新内核回灌到旧 LTS，提升新硬件支持 |
| **grub>** | 按 Shift/Esc 时机不对时进入的 GRUB 命令行，不能直接编辑启动项 |

### 1.3 已验证步骤（按实际顺序）

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

### 1.4 未验证备选（本次未实测，存疑备查）

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

### 1.5 命令速查

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

## 问题二：进桌面花屏（LightDM 绕过 Wayland）

### 2.1 30 秒判断（四者全中就是它）

| 现象 | 是否命中 |
|---|---|
| 开机自动进图形登录/桌面 → **花屏**（撕裂、糊屏、残影、色彩错乱） | ✅ |
| `Ctrl+Alt+F2~F6` 切到命令行（TTY）完全正常 | ✅ |
| 命令行里执行 **`startx` 能正常进入图形界面** | ✅ |
| 同一台硬件装 **Ubuntu 22.04 无此问题** | ✅ |

**四者全中 → 不是显卡坏了**，是 Ubuntu 18.04 的 **GDM3 登录界面默认跑在 Wayland 上**，而老图形栈对新显卡的 Wayland 渲染支持残缺，导致花屏。绕过 Wayland（用纯 X11 的 `startx` 或 LightDM）即可解决。

### 2.2 根因与原理

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

### 2.3 已验证方案：换成 LightDM（推荐，最稳）✅

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

### 2.4 未验证备选

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

## 三、日后复现 / 确认用诊断命令

```bash
# 1. 看显卡型号（定位根因最直接）
lspci -k | grep -EA3 'VGA|3D|Display'

# 2. 当前会话是不是 Wayland（Wayland 显示 "Type=wayland"）
loginctl show-session "$(loginctl | awk '/seat/{print $1}')" -p Type

# 3. 当前用的是哪个显示管理器
cat /etc/X11/default-display-manager

# 4. 另起一个 X 会话测试（见问题二四连判）
startx -- :1 &

# 5. 看当前 grub 启动参数里有没有 nomodeset（问题一）
grep nomodeset /etc/default/grub
```

---

## 四、经验与建议

1. **新硬件 + 老系统（18.04）图形问题，优先怀疑「驱动/显示路径不兼容」**，而非显卡坏了。命令行正常 + `startx` 正常（花屏）或 NumLock 有响应（黑屏）是关键判断依据。
2. **黑屏 → `nomodeset`，花屏 → 换 LightDM**，两条都是「绕开老栈不支持的新路径」，与历史成功经验一致。
3. **Ubuntu 18.04 标准支持已于 2023 年结束**，apt 安全更新已停。若这台机器是为跑老工具链（交叉编译、老 SDK），更推荐在 22.04 宿主机上用 `docker run -it ubuntu:18.04` 或虚拟机获得老环境——既避开图形坑，又持续获得宿主系统的安全性。

---

## 五、参数对照表（脱敏）

本文已对作者专属信息做脱敏。下表是**你按自己环境需要替换的全部占位符**，也是日后回看时一眼能找到的「要配置什么」：

| 占位符 | 含义 | 你的取值 |
|---|---|---|
| `<HOST_BOARD>` | 触发黑屏的硬件特征（示例：技嘉 Z590 + 11/12 代 Intel 核显 UHD 750/Xe） | 任何「新硬件 + 老内核 4.15」组合都适用，换成你的主板/核显即可 |

> 说明：本篇**不含内网 IP、账号、密码、公司域名**等敏感信息，故脱敏表很轻。真正需要替换大量参数的场景在系列第二篇（Android 编译环境），那里有完整的脱敏对照表。
