---
title: "Ubuntu 18.04 配置 Android 11–17 编译环境：依赖、ccache 分目录与下载避坑"
date: 2026-09-04T10:40:00+08:00
draft: false
description: "《Ubuntu 18.04 编译服务器实战》系列第二篇。在 18.04 上把一台无外网、走内网 gerrit 的编译机配成 Android 11–17 构建环境：apt 依赖、Samba/SSH、公钥+gerrit、git 全局配置、ccache 按「平台+Android 版本」自动切缓存目录，以及 repo 启动器/主机密钥/manifest 账号三处必踩坑修复。全部命令按作者实测给出，未验证项明确标注，并附完整脱敏参数对照表。"
summary: "无外网编译机装好后如何配 Android 11–17 构建环境：apt 依赖、ccache 分目录加速、gerrit 公钥、以及 repo 启动器/主机密钥/manifest 账号三坑修复。系列第二篇，含脱敏参数表。"
categories: ["Linux", "Android"]
tags: ["Ubuntu", "18.04", "Android", "AOSP", "编译服务器", "ccache", "gerrit", "repo", "构建环境", "展讯", "Unisoc", "MTK"]
keywords: ["Ubuntu18.04编译环境", "Android11编译", "Android17编译", "ccache分目录", "gerrit配置", "repo坑", "AOSP依赖", "编译服务器配置"]
series: ["Ubuntu18.04编译服务器实战"]
---

> **系列说明**：本文是《Ubuntu 18.04 编译服务器实战》系列**第二篇**，讲**装好系统后如何配置 Android 11–17 的编译环境**。
> 系列第一篇《[Ubuntu 18.04 安装与图形排障]({{< ref \"ubuntu1804-install-graphics-troubleshooting.md\" >}})》解决装系统黑屏（nomodeset）与进桌面花屏（LightDM）。
> 全文**脱敏**：所有内网 IP、账号、密码、公司邮箱域名、manifest/分支/编译目标均已替换为占位符，文末「参数对照表」一次性列出你要填的全部取值。

---

## 〇、环境与前置

| 项 | 值（编译机实测） |
|---|---|
| 系统 | Ubuntu 18.04.6（内核 5.4.0-150，用户态 18.04） |
| 账号 | `<BUILD_USER>` |
| 代码盘 | 独立分区挂载于 `<CODE_DISK>`（ext4，剩余空间充足） |
| 默认 shell | `/bin/bash` |
| Python | `python`→2.7.17（系统原生，Android 构建所需）、`python3`→3.6.9 |
| ccache | 3.4.1（apt 默认） |
| 代码服务器 | gerrit `<GERRIT_HOST>:<GERRIT_PORT>`，账号 `<GERRIT_USER>`（公钥已上传） |

> ⚠️ **步骤 1（安装系统）**：不在本文范围，详见系列第一篇。本文假设你已有一台能进桌面的 18.04 编译机。

---

## 一、常用 app（步骤 2）

```bash
sudo apt-get install patch bison flex gettext tcl net-tools repo
```

> 注：`repo` 这里装的是 apt 旧启动器（v1.23，仅 py2），**不能直接用**，见步骤 9 的修复。

---

## 二、Samba 共享（步骤 3）

Windows 端通过 Samba 直接读写代码盘，免逐文件 scp。

```bash
sudo apt-get install samba samba-common
sudo vi /etc/samba/smb.conf
```

在 `[global]` 之后添加（把 `<BUILD_USER>` 换成实际编译账号）：

```ini
[Project]
   comment = This is samba dir for project
   path = <CODE_DISK>/
   public = yes
   writable = yes
   valid users = <BUILD_USER>
   ;create mask = 0777
   ;directory mask = 0777
   ;force user = nobody
   ;force group = nogroup
   available = yes
   browseable = yes
```

设置 samba 密码并重启：

```bash
sudo smbpasswd -a <BUILD_USER>        # 输入两次密码
sudo service smbd restart
```

验证：`sudo systemctl is-active smbd` 应为 `active`；Windows 端用 `\\<BUILD_SERVER_IP>\Project` 访问。

---

## 三、SSH 服务（步骤 4）

```bash
sudo apt-get install openssh-server ssh
sudo systemctl enable ssh
sudo systemctl start ssh
```

---

## 四、Android 编译依赖（步骤 5）

```bash
sudo apt-get install -y git gnupg flex bison gperf build-essential zip curl \
  libc6-dev x11proto-core-dev g++-multilib gcc-multilib tofrodos python-markdown \
  libxml2-utils xsltproc lib32z-dev lib32z1 libc6-dev-i386 libgl1-mesa-dev \
  libncurses5 lib32ncurses5-dev libssl-dev libx11-dev m4 unzip zip zlib1g-dev \
  bsdmainutils cgpt libswitch-perl bc rsync xxd git-core parallel
```

> ⚠️ 清单里的 `lib32z-dev` 是笔误，Ubuntu 18.04 真实包名是 **`lib32z1-dev`**；`apt` 装 `lib32z-dev` 会报「无法定位」。实际需要的 32 位 zlib 由 `lib32z1-dev` 提供，上面已包含，无需单独改。
> `git-core` 是过渡虚包，装了 `git` 即满足，显示 MISSING 可忽略。

---

## 五、生成公钥 + 上传 gerrit（步骤 6–7）

```bash
ssh-keygen -t ed25519 -C "<YOUR_EMAIL>"
cat ~/.ssh/id_ed25519.pub     # 复制整行
```

把 `.pub` 内容加到 gerrit 账户 `<GERRIT_USER>` 的 SSH Keys 设置页。

验证：`ssh -p <GERRIT_PORT> <GERRIT_USER>@<GERRIT_HOST> "gerrit version"` 应返回 `gerrit version 3.8.0`。

---

## 六、Git 全局配置（步骤 8）

```bash
git config --global user.name  "<GERRIT_USER>"
git config --global user.email "<YOUR_EMAIL>"
```

---

## 七、配置 ccache（步骤 9，自动按平台+Android 版本切缓存目录）

> 原理：Android 全量编译动辄数小时，ccache 把预处理后的中间产物按哈希缓存，重编/换分支时命中缓存可大幅提速。难点是**不同平台（UNISOC/MTK）和不同 Android 版本（A11–A17）的缓存不能混用**——ABI、头文件、编译选项都不同，混用会编译异常。方案是「每个版本一个独立缓存目录 + 进代码树自动切换」。

### 7.1 安装

```bash
sudo apt-get install -y ccache
ccache --version        # 确认 3.4.1
```

### 7.2 写入 ~/.bashrc 配置块

把下面整段追加到 `~/.bashrc`（写入前先 `cp ~/.bashrc ~/.bashrc.bak.时间戳`）。**将下文所有 `<CODE_DISK>` 替换为你的代码盘挂载点（如 /media/Project）**。

```bash
# >>> ccache for Android builds >>>
export USE_CCACHE=1
export CCACHE_EXEC=$(command -v ccache)
export CC_WRAPPER=$(command -v ccache)
export CXX_WRAPPER=$(command -v ccache)
export CCACHE_COMPILERCHECK=content
export CCACHE_SLOPPINESS=include_file_mtime,file_macro
export CCACHE_BASEDIR=<CODE_DISK>
export CCACHE_DIR=<CODE_DISK>/.ccache
export CCACHE_CPP2=1

_auto_ccache() {
  [ "$PWD" = "${_ccache_last_dir:-}" ] && return 0
  _ccache_last_dir="$PWD"
  local d="$PWD" f="" bid="" old="$CCACHE_DIR" ap="" mc="" is_mtk="" mtk="" sprd=""
  while [ "$d" != "/" ]; do
    if [ -f "$d/sys/build/make/core/build_id.mk" ]; then f="$d/sys/build/make/core/build_id.mk"; break; fi
    if [ -f "$d/idh.code/build/make/core/build_id.mk" ]; then f="$d/idh.code/build/make/core/build_id.mk"; break; fi
    mc=$(ls -d "$d"/sprd.mocor*/build/make/core/build_id.mk 2>/dev/null | head -1)
    [ -n "$mc" ] && { f="$mc"; break; }
    ap=$(ls -d "$d"/mtk67xx_t*/alps/build/make/core/build_id.mk 2>/dev/null | head -1)
    [ -n "$ap" ] || ap=$(ls -d "$d"/mtk67xx_*/alps/build/make/core/build_id.mk 2>/dev/null | head -1)
    [ -n "$ap" ] && { f="$ap"; break; }
    if [ -f "$d/alps/build/make/core/build_id.mk" ]; then f="$d/alps/build/make/core/build_id.mk"; break; fi
    if [ -f "$d/build/make/core/build_id.mk" ]; then f="$d/build/make/core/build_id.mk"; break; fi
    d=$(dirname "$d")
  done
  if [ -z "$f" ]; then
    [ "$CCACHE_DIR" != "<CODE_DISK>/.ccache" ] && export CCACHE_DIR=<CODE_DISK>/.ccache
    return 0
  fi
  bid=$(sed -nE 's/^[[:space:]]*BUILD_ID[[:space:]]*:?=[[:space:]]*"?([^"[:space:]#]+)"?.*$/\1/p' "$f" | head -n1)
  [ -z "$bid" ] && { export CCACHE_DIR=<CODE_DISK>/.ccache; return 0; }
  case "$f" in
    *alps*) is_mtk=1 ;;
    */sprd.mocor*) is_mtk=0 ;;
    */idh.code/*) is_mtk=0 ;;
    */sys/*) sysroot="${f%/sys/build/make/core/build_id.mk}"
      [ -d "$sysroot/sys/vendor/mediatek" ] && mtk=1
      [ -d "$sysroot/sys/vendor/sprd" ] && sprd=1
      if [ "$mtk" = "1" ] && [ -z "$sprd" ]; then is_mtk=1
      elif [ "$sprd" = "1" ] && [ -z "$mtk" ]; then is_mtk=0
      else is_mtk=unknown; fi ;;
    *) is_mtk=unknown ;;
  esac
  [ "$is_mtk" = "unknown" ] && { export CCACHE_DIR=<CODE_DISK>/.ccache; return 0; }
  if [ "$is_mtk" = "1" ]; then
    case "$bid" in
      SP*|SQ*|SD*)              export CCACHE_DIR=<CODE_DISK>/.ccache_mtk_a12 ;;
      TP*|TQ*|TD*)              export CCACHE_DIR=<CODE_DISK>/.ccache_mtk_a13 ;;
      UP*|UQ*|UD*|AP1A*|AP2A*)  export CCACHE_DIR=<CODE_DISK>/.ccache_mtk_a14 ;;
      AP3A*|AP4A*|AP5A*)        export CCACHE_DIR=<CODE_DISK>/.ccache_mtk_a15 ;;
      BP*|BQ*|BD*)              export CCACHE_DIR=<CODE_DISK>/.ccache_mtk_a16 ;;
      *) export CCACHE_DIR=<CODE_DISK>/.ccache ;;
    esac
  else
    case "$bid" in
      RP*|RQ*|RD*)              export CCACHE_DIR=<CODE_DISK>/.ccache_a11 ;;
      SP*|SQ*|SD*)              export CCACHE_DIR=<CODE_DISK>/.ccache_a12 ;;
      TP*|TQ*|TD*)              export CCACHE_DIR=<CODE_DISK>/.ccache_a13 ;;
      UP*|UQ*|UD*|AP1A*|AP2A*)  export CCACHE_DIR=<CODE_DISK>/.ccache_a14 ;;
      AP3A*|AP4A*|AP5A*)        export CCACHE_DIR=<CODE_DISK>/.ccache_a15 ;;
      BP*|BQ*|BD*)              export CCACHE_DIR=<CODE_DISK>/.ccache_a16 ;;
      CP*|CQ*|CD*)              export CCACHE_DIR=<CODE_DISK>/.ccache_a17 ;;
      *) export CCACHE_DIR=<CODE_DISK>/.ccache ;;
    esac
  fi
}
if declare -p PROMPT_COMMAND >/dev/null 2>&1; then
  if declare -p PROMPT_COMMAND 2>/dev/null | grep -q 'declare -a'; then
    case " ${PROMPT_COMMAND[*]} " in *" _auto_ccache "*) : ;; *) PROMPT_COMMAND+=(_auto_ccache) ;; esac
  else
    printf '%s' "$PROMPT_COMMAND" | grep -q '_auto_ccache' || PROMPT_COMMAND="_auto_ccache;${PROMPT_COMMAND}"
  fi
else
  PROMPT_COMMAND='_auto_ccache'
fi
ccache_s() {
  for d in <CODE_DISK>/.ccache*; do
    [ -d "$d" ] || continue
    echo "=== ${d##*/} ==="; CCACHE_DIR="$d" ccache -s
  done
}
# <<< ccache <<<
```

> ⚠️ **注意**：本段按编译机实测保留了 `CCACHE_CPP2=1`。另一份《ccache 配置提示词》要求 ccache 3.x **不写** `CCACHE_CPP2`（因 `run_second_cpp` 默认 true）。若你的缓存命中异常，可对照该文档取舍。
>
> ⚠️ 18.04 的 `~/.bashrc` 第 8 行有 `case $- in *i*) ;; *) return;; esac`，**非交互 shell 会提前 return**，上面的块在非交互（脚本/SSH 命令）下不会加载。解决办法：另存一份无保护的 env 脚本到 `<CODE_DISK>/.ccache_env.sh`（内容同上，去掉 bashrc 的 return 保护），**自动化构建前 `source <CODE_DISK>/.ccache_env.sh`** 即可。

### 7.3 建目录 + 持久化 max_size/compression

```bash
mkdir -p <CODE_DISK>/.ccache <CODE_DISK>/.ccache_a16
for d in <CODE_DISK>/.ccache*; do
  [ -d "$d" ] || continue
  CCACHE_DIR="$d" ccache -M 100G
  CCACHE_DIR="$d" ccache -o compression=true
done
chmod -R 777 <CODE_DISK>/.ccache <CODE_DISK>/.ccache_a16
```

> soong 环境变量白名单会过滤 `CCACHE_MAXSIZE`/`CCACHE_COMPRESS`，所以必须写进 `ccache.conf`，**不要**在 .bashrc 里 `export CCACHE_MAXSIZE`。

---

## 八、下载代码（步骤 10）—— 含 3 处必踩坑修复

> 代码**必须下载到子目录**，不要直接放 `<CODE_DISK>` 根：
> `mkdir -p <CODE_DISK>/<BUILD_USER>/Unisoc/A16 && cd <CODE_DISK>/<BUILD_USER>/Unisoc/A16`

### 8.1 坑 1：apt 的 `repo` 是 py2 启动器，拉起 py3 的 main.py 会崩

现象：`repo init` 报 `SyntaxError` / `TypeError: startswith first arg must be bytes`。
原因：`/usr/bin/repo`(v1.23) shebang 是 `#!/usr/bin/python`(=2.7)，它从镜像下载现代 py3 `main.py` 到 `.repo/repo/`，仍用 py2 执行 → 报错。

**修复**：装现代 py3 启动器到 `/usr/local/bin/repo`（PATH 优先于 /usr/bin，不动 apt 原文件）：

```bash
sudo apt-get install -y git
cd /tmp && git clone --depth 1 https://mirrors.tuna.tsinghua.edu.cn/git/git-repo git-repo-launcher
sudo cp /tmp/git-repo-launcher/repo /usr/local/bin/repo
sudo chmod +x /usr/local/bin/repo
which -a repo        # 应优先显示 /usr/local/bin/repo
repo --version       # 应显示 v2.x（tracking stable）
```

### 8.2 坑 2：gerrit 主机密钥未信任

现象：`repo sync` 报 `Host key verification failed`。
**修复**：

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
ssh-keyscan -p <GERRIT_PORT> <GERRIT_HOST> >> ~/.ssh/known_hosts
sort -u ~/.ssh/known_hosts -o ~/.ssh/known_hosts
```

### 8.3 坑 3：manifest 写死 `<MANIFEST_OWNER>@`，但公钥上传的是 `<GERRIT_USER>`

现象：`repo sync` 报 `<MANIFEST_OWNER>@<GERRIT_HOST>:<GERRIT_PORT>: Permission denied (publickey)`；而 `ssh -p <GERRIT_PORT> <GERRIT_USER>@<GERRIT_HOST> "gerrit version"` 正常。
原因：manifest `<MANIFEST_XML>` 的 `<remote fetch="ssh://<MANIFEST_OWNER>@<GERRIT_HOST>:<GERRIT_PORT>/">` 用了仓库原主人的账号，而我们的公钥注册在 `<GERRIT_USER>` 下。

**修复**（不改 manifest、不改源码，用 git 全局改写）：

```bash
# 先确认 <GERRIT_USER> 对这些项目有读权限
git ls-remote ssh://<GERRIT_USER>@<GERRIT_HOST>:<GERRIT_PORT>/<MANIFEST_PROJECT>/sys   # 应能列出 HEAD
# 改写 fetch 用户
git config --global url."ssh://<GERRIT_USER>@<GERRIT_HOST>:<GERRIT_PORT>/".insteadOf \
  "ssh://<MANIFEST_OWNER>@<GERRIT_HOST>:<GERRIT_PORT>/"
```

### 8.4 下载命令

```bash
cd <CODE_DISK>/<BUILD_USER>/Unisoc/A16
repo init --repo-url=https://mirrors.tuna.tsinghua.edu.cn/git/git-repo \
  -u ssh://<GERRIT_USER>@<GERRIT_HOST>:<GERRIT_PORT>/manifest.git -m <MANIFEST_XML>
repo sync -j16 -c --no-clone-bundle
repo start master --all
# 关闭各子仓 core.fileMode（避免权限误判）
for d in google nvandmodem sys vnd zcommon zlib zprj; do
  [ -d "$d" ] && (cd "$d" && git config core.fileMode false)
done
```

> 附：Ubuntu 18.04 自带 OpenSSH 7.6 不支持 git 协议 v2 的 `SetEnv` 指令，日志会出现无害警告
> `command-line: line 0: Bad configuration option: setenv`，git 会优雅回退，不影响同步。
> 若要消除：`git config --global protocol.version 1`（步骤 11/12 前执行即可）。

---

## 九、切基线 + 冷/热编译（步骤 11–12）

```bash
cd <CODE_DISK>/<BUILD_USER>/Unisoc/A16
cd zcommon
git checkout <BRANCH_A16>
./create_ln.sh
cd ..
./zswitch_branch.sh <BRANCH_A16>
```

# 编译命令（具体目标按你的项目替换）：

```bash
cd <CODE_DISK>/<BUILD_USER>/Unisoc/A16
source zmake <BUILD_TARGET>
```

- **冷编译**：清空缓存（`ccache -C`）后首次完整编译，填充缓存。
- **热编译**：删 `out/` 后再次完整编译，缓存已热 → 应接近 100% 命中。
- 每次编译生成完成 log；最后用 `ccache -s` 两次统计做对比，出报告。

> 本步在代码全量下载完成后执行。实测数据（冷/热耗时对比、命中率）请在你环境跑完后回填。

---

## 十、进阶：长任务「自愈式检测」（可选，但强烈推荐）

> 问题背景：判断「代码下载完成 / 编译完成」若依赖「本地后台跑 SSH 长任务 + 等系统通知」，有两个致命脆弱点：
> 1. **SSH 会话断开即死**：长任务是 SSH 会话的子进程，会话一断就被 SIGHUP 杀掉。
> 2. **通知不触发就干等**：后台完成通知未送达则无任何兜底检测。
>
> 修复：改成「远端 `setsid` 脱离会话 + 完成哨兵文件 + 本地轮询器」三段式，彻底不依赖通知机制。

| 段 | 做法 | 作用 |
|---|---|---|
| ① 脱离会话 | `setsid bash job.sh >/dev/null 2>&1 </dev/null &` 启动长任务 | 任务成为独立 session，SSH 断开也继续跑 |
| ② 完成哨兵 | 每个 job 脚本末尾 `echo $rc > /path/.xxx_done`（含退出码，0=成功） | 「完成」= 哨兵文件存在，随时可查 |
| ③ 本地轮询 | 轮询器周期 SSH 检查哨兵 + 监控目录大小增长（连续不增长→卡死预警） | 轮询器本身后台运行，检测到哨兵即结束并通知 |

```bash
# 远端：setsid 脱离会话启动
ssh <BUILD_USER>@<BUILD_SERVER_IP>
setsid bash <CODE_DISK>/<BUILD_USER>/Unisoc/A16/download_code.sh >/dev/null 2>&1 </dev/null &

# 本地：轮询检测（检测到 .download_done 即结束并通知）
bash watch_job.sh <CODE_DISK>/<BUILD_USER>/Unisoc/A16/.download_done STEP10 220 30
```

> 配套脚本（`download_code.sh` / `switch_branch.sh` / `build_cold.sh` / `build_hot.sh` / `watch_job.sh`）按你的代码目录落地即可，内部 `pkill` 不要用含脚本名的 `pkill -f`，否则会误杀执行命令的 shell 自身——改用独立 kill 脚本或按 PID 精确杀。

---

## 十一、验证清单（编译机实测）

| 检查项 | 结果 |
|---|---|
| 18.04.6 | ✅ |
| 常用 app / samba / ssh / android 依赖 | ✅ |
| ed25519 公钥 + gerrit 可达 | ✅ `gerrit version 3.8.0` |
| git config | ✅ `<GERRIT_USER>` / `<YOUR_EMAIL>` |
| ccache 3.4.1 + 分目录 100G | ✅ |
| 现代 py3 repo 启动器 | ✅ v2.x @ /usr/local/bin/repo |
| gerrit 主机密钥 | ✅ known_hosts |
| `<MANIFEST_OWNER>`→`<GERRIT_USER>` insteadOf | ✅ 读权限已验证 |
| 代码下载到子目录 | ✅ `<CODE_DISK>/<BUILD_USER>/Unisoc/A16/` |
| 步骤 11/12（切基线 + 冷热处理） | ⏳ 待下载完成后执行 |

---

## 十二、参数对照表（脱敏 · 全文要替换的都在这里）

> 把下表占位符**全部**替换成你自己的环境值，文章里的命令即可直接跑。这是日后回看时一眼定位「要配置哪些参数」的唯一清单。

| 占位符 | 含义 | 你的取值（示例） |
|---|---|---|
| `<BUILD_SERVER_IP>` | 编译机内网 IP | 如 `192.168.1.205` |
| `<BUILD_USER>` | 编译机登录账号 | 如 `user` |
| `<BUILD_PASSWORD>` | 编译机登录/samba 密码 | **自建强密码，勿用弱口令** |
| `<CODE_DISK>` | 代码盘挂载点 | 如 `/media/Project` |
| `<GERRIT_HOST>` | 代码服务器（gerrit）主机 | 如 `192.168.1.47` 或域名 |
| `<GERRIT_PORT>` | gerrit SSH 端口 | 默认 `29418` |
| `<GERRIT_USER>` | gerrit 账号 / git user.name | 你的账号 |
| `<YOUR_EMAIL>` | git user.email 与 SSH 公钥注释 | 你的邮箱 |
| `<MANIFEST_XML>` | 项目 manifest 文件名 | 如 `Sprd.Android14.4G.xml` |
| `<MANIFEST_PROJECT>` | gerrit 上托管 manifest 的项目路径 | 如 `Sprd.Android14.4G` |
| `<MANIFEST_OWNER>` | manifest 中写死的原始 fetch 账号 | 原主人账号 |
| `<BRANCH_A16>` | 项目基线分支名 | 你的分支（如 `xm_uni_branch_a16`） |
| `<BUILD_TARGET>` | 具体编译目标（`source zmake ...`） | 你的目标（如 `zprj/.../WA09_CD3384_HONOR_GO`） |

> 说明：上表已剔除公司专属信息（原 `qualicom.com.cn` 邮箱域名、原 gerrit 账号 `sjinqian`/`jqiang`、原编译目标中的客户项目名等）。平台厂商名（UNISOC/展讯、MTK）属公开信息，予以保留以便检索。
