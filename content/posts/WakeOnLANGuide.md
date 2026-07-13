---
title: "远程唤醒实战：把 Ubuntu 与 Windows 11 配置成可被局域网唤醒的电脑"
date: 2026-07-13T20:00:00+08:00
draft: false
description: "记录将 Ubuntu 与 Windows 11 配置为可被局域网其他电脑远程唤醒（Wake on LAN）的完整过程：Ubuntu 双机互唤已验证，Windows 11 被唤醒端的 BIOS/设备管理器/快速启动配置，PowerShell 魔术包发送脚本；并揭示一个关键限制——处于 Wi-Fi 的 Windows 因广播域/VLAN 隔离，暂时无法直接唤醒有线的 Windows，而同网段的 Ubuntu 可以。"
summary: "Wake on LAN 配置全记录：Ubuntu↔Ubuntu 已跑通，Windows 11 被唤醒端配置 + PowerShell 唤醒脚本；重点揭示 Windows(Wi-Fi) 无法直接唤醒 Windows(有线) 的广播域隔离问题，以及 .ps1 脚本编码陷阱。"
categories: ["运维实践"]
tags: ["Wake on LAN", "WoL", "远程唤醒", "Ubuntu", "Windows 11", "PowerShell", "网络排错", "踩坑记录"]
keywords: ["Wake on LAN 配置", "Windows 11 网络唤醒", "Ubuntu wakeonlan", "魔术包", "PowerShell WoL 脚本", "快速启动", "广播域隔离", "VLAN", "ErP"]
series: ["运维工具箱"]
---

## 背景

公司放了台 Windows 11 台式机，希望下班关机后，人在办公室另一台电脑（或家里）能随时把它唤醒，省得专门跑过去按电源键。**Wake on LAN（WoL，网络唤醒）** 就是干这个的。

本文记录把「被唤醒端」配好的完整过程，以及今天实测中踩到的一个反直觉的坑。结论先行：**Ubuntu 唤醒 Ubuntu 简单可靠；Windows 11 当被唤醒端配置不复杂；但当前环境下，处于 Wi-Fi 的 Windows 暂时无法直接唤醒处于有线的 Windows——这不是配置错，而是网络位置（广播域）问题。**

---

## 一、WoL 工作原理（30 秒版）

- 唤醒端向局域网**广播**一个「魔术包」（Magic Packet）：`6 个 0xFF` + `目标 MAC 重复 16 次`，共 102 字节，UDP 发往 `255.255.255.255:9`（或 `:7`）。
- 目标机网卡在关机/睡眠态仍保持微弱供电并监听该包，匹配到自己 MAC 就触发开机。
- 三个前提：
  1. 目标 BIOS/网卡支持并开启 WoL；
  2. **发送端与目标在同一广播域**（同网段；广播包不跨路由器）；
  3. 最好用**有线网卡**（无线从完全关机唤醒支持差，且高度依赖具体网卡）。

---

## 二、Ubuntu → Ubuntu（已验证）

**唤醒端**安装工具：

```bash
sudo apt install wakeonlan
```

**被唤醒端**：

1. BIOS 开启 `Wake on LAN`。
2. 查网卡名与 MAC：

```bash
ifconfig        # 找到网卡名（如 enp97s0f0）和 MAC
```

3. 安装并查看/开启 WoL：

```bash
sudo apt install ethtool
sudo ethtool enp97s0f0        # 看 Wake-on: g=已开, d=未开
sudo ethtool -s enp97s0f0 wol g
```

4. 持久化（部分机器重启会丢 WoL 状态）：把 `ethtool -s <网卡> wol g` 写进 `/etc/rc.local` 并 `chmod +x`，再启用 `rc-local` 服务。

**唤醒**：

```bash
wakeonlan 00:1A:2B:3C:4D:5E
```

这一步我实测可用。

---

## 三、让 Windows 11 成为「被唤醒端」

Win11 没有 `rc.local`，配置落在 BIOS + 设备管理器 + 电源选项三处。

### 3.1 BIOS/UEFI（必做）

开机进 BIOS，启用 `Wake on LAN` / `PCI-E Power On` / `Wake from S5`；**关键：关闭 `ErP Ready`**（欧盟节能选项，会在关机态切断给网卡的 `+5VSB` 待机供电，直接废掉 WoL）。

### 3.2 设备管理器配置网卡

设备管理器 → 网络适配器 → 右键你的**有线**网卡 → 属性：

- **电源管理**：✅ 允许此设备唤醒计算机 + ✅ 只允许幻数据包唤醒（防被普通流量误唤醒）
- **高级**：启用 `Wake on Magic Packet`（魔术包唤醒）；关闭 `Green Ethernet` / `Energy Efficient Ethernet`（节能会让网卡周期性掉电，错过魔术包）

### 3.3 关闭「快速启动」（Windows 特有坑，必做）

控制面板 → 电源选项 → 选择电源按钮的功能 → 更改当前不可用的设置 → **取消勾选「启用快速启动」**。

> 原因：快速启动本质是「混合关机」——把内核 hibern 到 `hiberfil.sys`，机器实际处于休眠而非真正的 S5。WoL 的 S5 唤醒事件无法在这种状态下触发。这是 Windows 上最常见的失效原因。

### 3.4 取 MAC 并验证

```powershell
ipconfig /all                      # 看「物理地址」
powercfg /devicequery wake_armed   # 列表里应出现你的有线网卡
```

---

## 四、从 Windows 发送唤醒包（PowerShell）

唤醒端不需要 `ethtool`，用一段 PowerShell 发魔术包即可。把下面内容存成 `wol.ps1`：

```powershell
# WakeOnLan magic packet sender (pure ASCII, UTF-8 safe)
function Send-WOL {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Mac,
        [string]$Broadcast = "255.255.255.255",
        [int]$Port = 9
    )
    $clean = $Mac -replace '[-:]', ''
    if ($clean.Length -ne 12) { throw "MAC '$Mac' invalid" }
    $macBytes = [byte[]]::new(6)
    for ($i = 0; $i -lt 6; $i++) { $macBytes[$i] = [System.Convert]::ToByte($clean.Substring($i*2,2),16) }
    $packet = [byte[]]::new(102)
    for ($i = 0; $i -lt 6; $i++) { $packet[$i] = 0xFF }
    for ($i = 1; $i -le 16; $i++) { $macBytes.CopyTo($packet, $i*6) }
    $ip = [System.Net.IPAddress]::Parse($Broadcast)
    $ep = New-Object System.Net.IPEndPoint($ip, $Port)
    $client = New-Object System.Net.Sockets.UdpClient
    $client.EnableBroadcast = $true
    $sent = $client.Send($packet, $packet.Length, $ep)
    $client.Close()
    Write-Host "Sent magic packet ($sent bytes) to $Mac"
}
# 用法：把 MAC 换成目标机
Send-WOL -Mac "00:1A:2B:3C:4D:5E"
```

运行：

```powershell
powershell -ExecutionPolicy Bypass -File "路径\wol.ps1"
```

> **坑 1（脚本编码）**：务必用 **VS Code 以 UTF-8 保存**这个 `.ps1`。别用 Git Bash 的 `cat >` / heredoc 重定向去写——中文或特殊字符会被存成乱码，导致文件变成「二进制」、PowerShell 一解析就报满屏 `UnexpectedToken`。脚本刻意写成纯 ASCII，就是从根上规避这点。
>
> **坑 2（UdpClient 写法）**：早期我用 `new UdpClient("255.255.255.255", 9)` 的构造函数写法，部分 Windows 会抛 `requested address is not valid`。改成「先建 `UdpClient` → 设 `EnableBroadcast=$true` → 再用 `Send(bytes, len, IPEndPoint)` 发往广播地址」就稳了。

---

## 五、实测发现的关键限制：Windows 暂无法直接唤醒 Windows ⚠️

这是今天最重要的结论，单独强调。

我在局域网内一台 **Windows（连接 Wi-Fi）** 上运行上面的脚本，目标是同局域网一台 **Windows 11（连接有线）**，处于完全关机态——脚本**不报错，但叫不醒**。

排查后，换成同局域网的一台 **Ubuntu（连接有线，与目标同网段）** 执行：

```bash
wakeonlan 00:E0:4C:69:6D:E2
```

**一次成功唤醒。**

这说明：

1. 目标机 WoL 配置**完全正确**（BIOS S5 唤醒、有线网卡 armed、ErP 关闭都对），MAC 也对；
2. 问题不在目标，而在**发送端能不能把广播包送到目标所在网段**。

**根因**：那台 Windows 走 **Wi-Fi**，目标走**有线**，公司网络把无线和有线划成了不同子网/VLAN（或开了无线客户端隔离）。Windows 发出的 `255.255.255.255` 广播被限制在自己网段内，到不了有线的目标；而 Ubuntu 和目标**同在有线网段**，广播能直达。

> **结论：目前 Windows（Wi-Fi 侧）还无法直接唤醒 Windows（有线侧）。**

可行的替代方案：

- 用与目标**同网段（同有线）**的机器当唤醒端（如那台 Ubuntu，已验证可用）；
- 若坚持从 Windows 发，把该 Windows 也接到与目标**相同的有线网段**再运行脚本；
- 必须跨网段唤醒时，需要 **WoL 中继**（让同网段设备转发魔术包）或路由器做 **UDP 9 端口转发 / 定向广播**。

> 顺带纠正一个我中途的误判：曾以为 WoL 被开错了网卡，但 Ubuntu 能用有线 MAC 唤醒，证明有线网卡 WoL 本就开启。真正的变量始终是「**发送端网络位置**」。

---

## 六、排错清单

- [ ] BIOS 开了 `Wake on LAN` 且关了 `ErP`？
- [ ] 设备管理器里**对应联网网卡**的电源管理两项已勾？
- [ ] 快速启动已关？
- [ ] `powercfg /devicequery wake_armed` 能看到目标网卡？
- [ ] 发送端与目标**同一网段/广播域**？（跨 VLAN、Wi-Fi 隔离是头号元凶）
- [ ] 用的是**有线 MAC**？`ipconfig /all` 里带 IP 的那张才是活动网卡
- [ ] 先测「睡眠」再测「完全关机」，缩小是 Windows 配置还是 BIOS S5 的问题

---

## 七、小结

- **Ubuntu ↔ Ubuntu** 的 WoL 简单可靠，已验证；
- **Windows 11 当被唤醒端**，重点在 BIOS（开 WoL、关 ErP）+ 设备管理器（武装有线网卡）+ 关快速启动；
- 唤醒脚本用 PowerShell 即可，注意脚本文件编码与 `UdpClient` 的广播写法两个坑；
- **最大的坑不是配置，而是网络位置**：Wi-Fi 与有线若被隔离，Windows 发往有线的唤醒包会石沉大海；此时让同网段的有线机器（如 Ubuntu）来发最稳。

---

*本文基于 2026-07-13 的真实配置与实测过程整理。MAC 地址在文中以占位符 `00:1A:2B:3C:4D:5E` 表示，实际使用时请替换为你目标机的真实物理地址。*
