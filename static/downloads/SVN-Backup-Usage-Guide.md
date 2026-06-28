# SVN 仓库自动备份方案（VisualSVN Server Standard Edition 替代方案）

## 一、方案概述

VisualSVN Server 标准版**不提供内置的备份任务（Backup Jobs）功能**，只有企业版才支持。该方案使用 SVN 自带的 `svnadmin hotcopy` 命令配合 **Windows 计划任务**，实现每周自动全量备份，并自动清理超过保留期限的旧备份。

**适用场景：**

- 使用 VisualSVN Server Standard Edition 的仓库
- 需要稳定、低成本的定时备份
- 仓库大小约 100GB+，希望用简单方式实现自动备份

> ⚠️ 注意：`svnadmin hotcopy` 是**全量备份**，不是增量备份。每次备份都会完整复制整个仓库。

---

## 二、文件清单

| 文件 | 说明 | 部署位置 |
|------|------|---------|
| `svn_backup.ps1` | 备份主脚本（纯 PowerShell），执行热备份、空间检查、日志记录、旧备份清理 | SVN 服务器本地 |
| `setup_svn_backup_task.ps1` | 一键配置 Windows 计划任务 | SVN 服务器本地 |

> **为什么用 PowerShell 而不是批处理？** .bat 文件在 Windows 上存在 LF/CRLF 行尾解析、UTF-8 编码、管道转义、32 位整数溢出等多重陷阱，对于 100GB+ 的大仓库极易出错。PowerShell 原生支持 64 位运算、Unicode 和健壮的管道，彻底消除这些问题。

---

## 三、配置前准备

### 1. 确认仓库路径

VisualSVN Server 默认仓库路径为：

```
D:\Repositories
```

具体路径可通过 VisualSVN Server Manager 查看确认。

### 2. 确认备份目录

选择一个空间充足的盘符，例如：

```
E:\SVN_Backup
```

### 3. 评估磁盘空间

| 仓库大小 | 单次全量备份 | 保留 1 个月（4 份） | 推荐剩余可用空间 |
|---------|------------|-------------------|---------------|
| 100 GB | ~100-120 GB | ~400-500 GB | **≥ 600 GB** |

> 实际占用受版本历史、二进制文件等影响，建议预留 2 倍以上余量。

---

## 四、脚本配置

### 1. 修改 `svn_backup.ps1`

使用文本编辑器打开 `svn_backup.ps1`，修改以下配置项：

```powershell
$REPO_BASE         = "D:\Repositories"          # [必改] 仓库根目录
$BACKUP_ROOT       = "E:\SVN_Backup"             # [必改] 备份存放目录
$RETENTION_DAYS    = 30                          # [选改] 保留天数
$SPACE_SAFETY_FACTOR = 2                         # [选改] 空间安全系数（剩余空间 ≥ 仓库×2）
$REPOS = @("repo1", "repo2", "repo3")            # [必改] 仓库名称列表
```

**示例：** 如果你的仓库目录是 `D:\Repositories\MyProject`，则配置为：

```powershell
$REPOS = @("MyProject")
```

### 2. 修改 `setup_svn_backup_task.ps1`

配置计划任务执行周期：

```powershell
$ScriptPath   = "D:\Scripts\svn_backup.ps1"  # [必改] 脚本实际路径
$TaskName     = "SVN Hotcopy Backup"         # [选改] 任务名称
$ScheduleTime = "02:00"                      # [选改] 执行时间（24小时制）
```

---

## 五、部署步骤

### 第一步：将脚本拷贝到 SVN 服务器

建议统一放到一个固定目录，例如 `D:\Scripts\`。

### 第二步：修改脚本配置

按第四节修改仓库路径、备份路径、仓库名称等。

### 第三步：手动测试运行

在 SVN 服务器上，以**管理员身份**打开 PowerShell，执行：

```powershell
PowerShell -NoProfile -ExecutionPolicy Bypass -File D:\Scripts\svn_backup.ps1
```

检查日志输出（路径为备份目录下的 `logs\backup_YYYYMMDD_HHMMSS.log`），确认备份成功、备份目录已生成。

### 第四步：创建计划任务

**方法一：使用 PowerShell 脚本（推荐）**

以管理员身份打开 PowerShell，执行：

```powershell
PowerShell -NoProfile -ExecutionPolicy Bypass -File D:\Scripts\setup_svn_backup_task.ps1
```

看到类似以下输出即表示成功：

```
Scheduled task 'SVN Hotcopy Backup' created successfully.
```

> ⚠️ Windows 默认禁止直接运行 `.ps1` 脚本（`.\setup_svn_backup_task.ps1` 会报 `UnauthorizedAccess` 错误）。上述命令通过 `-ExecutionPolicy Bypass` 参数绕过限制，仅影响本次执行，不会修改系统全局策略。

**验证任务是否创建成功：**

```powershell
Get-ScheduledTask -TaskName "SVN Hotcopy Backup"
```

**方法二：手动配置（备选）**

1. 打开"任务计划程序"（运行 `taskschd.msc`）
2. 右侧点击"创建任务"
3. 常规：名称 `SVN Hotcopy Backup`，勾选"使用最高权限运行"
4. 触发器：新建 → 按周 → 周日 → `02:00`
5. 操作：新建 → 启动程序 → `PowerShell.exe`，参数：`-NoProfile -ExecutionPolicy Bypass -File "D:\Scripts\svn_backup.ps1"`
6. 条件：取消"只有在计算机使用交流电源时才启动"
7. 保存并输入管理员凭据

---

## 六、在任务计划程序中查找任务

任务创建成功后，可通过以下方式找到它：

**方式一：直接搜索（最快）**

1. 按 `Win + R`，输入 `taskschd.msc`，回车打开任务计划程序
2. 在左侧树展开"任务计划程序库"
3. 按 `Ctrl + F`，搜索关键词 `SVN`
4. 即可看到名称为 `SVN Hotcopy Backup` 的任务

**方式二：用命令行验证**

```powershell
Get-ScheduledTask -TaskName "SVN Hotcopy Backup"
```

---

## 七、手动运行测试

找到任务后，可用以下方式手动触发：

**界面操作：** 选中任务 → 右侧点击"运行"

**命令行操作：**

```powershell
Start-ScheduledTask -TaskName "SVN Hotcopy Backup"
```

运行后到备份目录下的 `logs\` 查看日志，确认是否正常执行。

---

## 八、验证备份

### 检查备份目录结构

备份完成后，目录结构类似：

```
E:\SVN_Backup\
├── MyProject_20260628_020015\      # 本次备份
├── MyProject_20260621_020000\      # 上周备份
├── logs\
│   ├── backup_20260628_020015.log
│   └── ...
└── ...
```

### 验证备份可用性

`svnadmin hotcopy` 生成的备份是**可直接使用的仓库**，无需转换。验证方法：

```cmd
svnlook youngest E:\SVN_Backup\MyProject_20260628_020015
```

若能正常输出版本号，则备份可用。

---

## 九、备份恢复流程

详见博客文章第二节。

---

## 十、常见问题

### Q1：运行 .ps1 脚本报错 "在此系统上禁止运行脚本"

**原因：** Windows 默认 PowerShell 执行策略为 `Restricted`。

**解决（三选一）：**

| 方法 | 命令 | 影响范围 |
|------|------|---------|
| **单次绕过（推荐）** | `PowerShell -NoProfile -ExecutionPolicy Bypass -File 脚本路径` | 仅本次 |
| **当前会话允许** | `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` | 关闭窗口失效 |
| **永久允许当前用户** | `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned` | 永久生效 |

### Q2：备份失败，日志显示"空间不足"

备份盘剩余空间不足仓库大小的 2 倍。清理旧备份或扩容备份盘，或降低 `SPACE_SAFETY_FACTOR` 为 1.5（不推荐低于 1.5）。

### Q3：备份运行很久，是否正常？

100GB+ 仓库全量 hotcopy 可能需要 30-120 分钟，取决于磁盘性能。建议首次在维护时间窗口测试确认耗时。

### Q4：能否只保留最近 2 周备份？

可以，修改 `svn_backup.ps1` 中 `$RETENTION_DAYS = 14`。

### Q5：备份文件越来越大，是否正常？

正常。SVN 仓库包含所有历史版本。若需减少体积，可考虑：
- 使用 `svnadmin dump --incremental` 替代 hotcopy
- 使用 `svnsync` 做实时镜像
- 清理仓库中不必要的大文件历史

---

## 十一、可选升级：增量备份方案

如果全量备份占用的磁盘空间和备份时间难以接受，可考虑使用 `svnsync` 做增量镜像：

```cmd
:: 在目标机器创建镜像仓库
svnadmin create E:\SVN_Mirror\MyProject

:: 初始化同步
svnsync init file:///E:/SVN_Mirror/MyProject http://svn-server/svn/MyProject

:: 执行同步
svnsync sync file:///E:/SVN_Mirror/MyProject
```

将 `svnsync sync` 命令放入计划任务，即可实现每周/每日增量备份。

---

## 十二、总结

| 项目 | 内容 |
|------|------|
| 工具 | `svnadmin hotcopy` + Windows 任务计划程序 |
| 备份方式 | 全量热备份（无需停服） |
| 备份周期 | 每周一次（可调整） |
| 保留策略 | 自动清理超过 30 天的旧备份 |
| 空间要求 | 备份盘可用空间 ≥ 仓库大小 × 2 × 保留份数 |
| 验证方法 | `svnlook youngest` 读取备份目录版本号 |

该方案完全合法、免费，无需升级到 VisualSVN Server Enterprise Edition。
