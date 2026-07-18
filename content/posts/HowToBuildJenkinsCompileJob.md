---
title: "在 Jenkins 上搭建基于 Docker 的编译流水线：手把手教程"
date: 2026-07-18T14:50:00+08:00
draft: false
description: "以远程编译机用 Docker 编译嵌入式固件并自动上传为例，手把手教小白在 Jenkins 上搭建一条编译流水线，含节点注册、Docker 编译、6 段流水线脚本与常见坑"
summary: "基于真实的内网构建任务整理：如何在 Jenkins 上搭建一条『拉代码 → Docker 编译 → 自动上传制品』的流水线，覆盖 Agent 节点注册、Java 版本坑、docker run 去 -t、holdOffBuildUntilSave 等实战要点"
categories: ["CI/CD", "DevOps"]
tags: ["Jenkins", "Docker", "Pipeline", "编译", "持续集成", "自动化构建"]
keywords: ["Jenkins Pipeline", "Docker 编译", "Jenkins agent", "自动化构建", "Jenkins 节点"]
series: ["AI工具链"]
---

> ✅ **本文以"在远程编译机上用 Docker 编译一个嵌入式 Linux 固件，并自动上传到制品服务器"为真实案例整理**。所有 IP、账号、密钥、路径、产品名均已脱敏，文末附对照表与获取方式。

## 一、我们要解决什么问题？

假设你有一个嵌入式项目（比如某款 RK 平台的开发板固件），编译过程很重：

- 需要特定的交叉编译工具链、系统库（Ubuntu + 一堆依赖）
- 代码放在远程编译机（Linux 服务器）上
- 编译完要把产物（固件包）传到一台"制品服务器"供他人下载

如果每次都手动 SSH 上去敲命令，既累又容易出错。我们用 Jenkins 把它变成：**点一下（或说一句话）→ 自动拉代码 → Docker 里编译 → 自动上传**。

本文就按这个真实流程，一步步教你搭出来。

---

## 二、先搞懂 4 个核心概念（小白必看）

| 概念 | 大白话 | 本文里的角色 |
|------|--------|-------------|
| **Job / Pipeline（任务 / 流水线）** | 一连串自动步骤的"菜谱" | 我们的"固件构建"任务 |
| **Agent / Node（节点 / 编译机）** | 真正干活的机器（Jenkins 主控只调度，不编译） | 远程 Linux 服务器（示例 IP `192.168.100.20`） |
| **Stage（阶段）** | 把流程切成几段，方便看进度和日志 | 拉代码 / 编译 / 上传 各算一段 |
| **Docker** | 把"编译环境"打包成镜像，做到"换台机器编译结果一样" | 在编译机里用 Docker 容器跑编译 |

**为什么用 Docker 编译？** 直接在主机的环境编，容易遇到"我机器上能编，别人机器编不过"（环境不一致）。把工具链和依赖打进 Docker 镜像，所有人用同一个镜像，结果可复现，且不污染编译机系统。

## 三、整体架构（文字版）

```
[Jenkins 主控]  ──调度──▶  [编译机 Agent 192.168.100.20]
                                │
                                ├─ 拉代码（git / repo）
                                ├─ docker run 起编译容器
                                │     └─ 容器内：source 编译脚本 → 出固件
                                └─ scp 上传 ──▶  [制品服务器 192.168.100.30]
```

---

## 四、步骤 1：准备编译机（Agent）

登录你的远程 Linux 编译机，确认装好：

1. **SSH**：Jenkins 通过 SSH 连它（确保 22 端口开、能密码 / 密钥登录）。
2. **Docker**：`docker --version` 能看到版本。
3. **Java 17+**：⚠️ 这是大坑。Jenkins 的 agent 代理程序（`remoting.jar`）**需要 Java 17 及以上**。若系统默认是 Java 11，节点会连不上，报 `UnsupportedClassVersionError`。
   - **方案 A（内网友好、最省事）**：从局域网里已有的、装了 Java 21 的机器直接拷一份到编译机，例如 `/opt/java21/`；后面节点配置里显式指定这个 Java 路径。
   - **方案 B（没有现成可拷的机器时，在 Ubuntu 上直接装）**：
     - Ubuntu 22.04+ / Debian 12+ 且能上公网：
       ```bash
       sudo apt update
       sudo apt install -y openjdk-21-jdk
       # 装好后 Java 路径通常为 /usr/lib/jvm/java-21-openjdk-amd64/bin/java
       ```
     - 离线 / 其他发行版：下载 Eclipse Temurin 21 的 tarball 解压即可：
       ```bash
       wget https://api.adoptium.net/v3/binary/latest/21/ga/linux/x64/jdk/hotspot/normal/eclipse -O jdk21.tar.gz
       sudo tar -xzf jdk21.tar.gz -C /opt
       # 路径形如 /opt/jdk-21.0.x+xx/bin/java
       ```
   - 💡 编译机上的 agent **只需要 JRE**（不需要完整 JDK），装 `openjdk-21-jre-headless` 或对应 JRE 包即可更省空间；装好后把绝对路径填到节点配置的 `JavaPath`，节点即上线。
4. **代码目录与脚本**：准备好项目代码路径（示例 `/data/build/example-rk/rv1103`），以及你们自己的编译辅助脚本（如生成软链的 `create_ln.sh`、切分支的 `zswitch_branch.sh`、拉代码的 `pull_code.sh`、进 Docker 编译的 `env_setup.sh`）。这些脚本名按你们项目实际来。

---

## 五、步骤 2：在 Jenkins 注册编译节点

1. Jenkins → **管理 Jenkins** → **节点（Nodes）** → **新建节点**
2. 节点名（例 `build-agent-01`），类型选**固定节点（Permanent Agent）**
3. 关键配置：
   - **远程根目录**：编译机上的一个目录，如 `/home/builduser`
   - **标签（Labels）**：填 `build-agent-01`（流水线靠这个标签挑机器）
   - **启动方式**：选 **Launch agents via SSH**
     - **主机**：`192.168.100.20`
     - **凭据**：点"添加"→ 用户名 `builduser`、密码 `BuildPass@123`（或用 SSH 私钥）
     - **Java 路径（JavaPath）**：填 `/opt/java21/bin/java`（**务必填你拷过去的 Java21，否则用系统默认老 Java 会连不上**）
4. 保存 → 节点状态小球变**绿**即上线成功。

> 💡 **标签（label）是流水线和机器的"接头暗号"**：流水线说"我要 label=build-agent-01 的机器"，Jenkins 就把任务派给这台。

---

## 六、步骤 3：准备 Docker 编译镜像

在编译机上拉取（或构建）你们的编译镜像，示例叫 `rockchip-build:v1.1`：

```bash
docker pull registry.example.com/rockchip-build:v1.1
# 或本地构建
docker build -t rockchip-build:v1.1 -f Dockerfile.build .
```

这个镜像里应预装好交叉编译工具链、repo、Python 等所有编译依赖。

> 💡 **关于 Docker 本身的入门**（安装、镜像、容器基本操作）：本文聚焦"Jenkins 里如何调用 Docker 完成编译"，不展开 Docker 基础。需要入门的同学可参考 [Docker 官方文档](https://docs.docker.com/)，或关注本博客后续专门讲解 Docker 的文章。

---

## 七、步骤 4：写流水线脚本（Jenkinsfile）

下面是脱敏后的完整流水线（Declarative Pipeline），共 6 个阶段。直接复制改值即可用。

```groovy
pipeline {
    agent { label 'build-agent-01' }   // 指定用哪台编译机

    options {
        timeout(time: 8, unit: 'HOURS')   // 最多跑 8 小时，防卡死
        disableConcurrentBuilds()         // 禁止同时跑两个，避免产物互相覆盖
    }

    environment {
        SDK_DIR  = '/data/build/example-rk/rv1103'            // 代码根目录
        FTP_USER = 'artifact'                                  // 制品服务器账号
        FTP_HOST = '192.168.100.30'                           // 制品服务器 IP
        FTP_ROOT = '/srv/artifacts/example-rk_Build_Version'   // 上传根目录
    }

    stages {
        stage('1. 生成链接文件') {
            steps {
                dir("${SDK_DIR}") {
                    sh 'cd zcommon && ./create_ln.sh && cd ..'
                }
            }
        }
        stage('2. 切换分支') {
            steps {
                dir("${SDK_DIR}") {
                    sh './zswitch_branch.sh develop'   // 换成你的分支名
                }
            }
        }
        stage('3. 更新代码') {
            steps {
                dir("${SDK_DIR}") {
                    sh './pull_code.sh'
                }
            }
        }
        stage('4. 再次生成链接文件') {
            steps {
                dir("${SDK_DIR}") {
                    sh 'cd zcommon && ./create_ln.sh && cd ..'
                }
            }
        }
        stage('5. Docker 编译') {
            steps {
                dir("${SDK_DIR}") {
                    // 进 Docker 容器编译，等价于原 env_setup.sh 里 source 编译脚本
                    sh '''
                        docker run --rm -i --entrypoint /bin/bash \
                            --mount type=bind,source=$(pwd)/,target=/home/SDK_DIR \
                            --net host \
                            --user $(id -u):$(id -g) \
                            --workdir /home/SDK_DIR \
                            rockchip-build:v1.1 \
                            -c "source zmake zprj/example-rk/acme/ERK3568_4K_apps/"
                    '''
                }
            }
        }
        stage('6. 上传到制品服务器') {
            steps {
                dir("${SDK_DIR}") {
                    script {
                        // 找 output/ 下最新的时间目录作为本次产物
                        def latest = sh(script: 'ls -t output | head -1', returnStdout: true).trim()
                        if (!latest) {
                            error '未在 output/ 下找到时间目录，编译产物可能缺失'
                        }
                        env.OUT_DIR = latest
                    }
                    // 直接用编译机本地的私钥 scp 上传（不依赖 Jenkins 凭据）
                    sh '''
                        KEY=/home/builduser/.ssh/id_rsa_artifact
                        chmod 600 "$KEY"
                        verPath="${FTP_ROOT}/${OUT_DIR}"
                        ssh -o StrictHostKeyChecking=no -i "$KEY" ${FTP_USER}@${FTP_HOST} "mkdir -p ${verPath}"
                        scp -o StrictHostKeyChecking=no -i "$KEY" -r output/${OUT_DIR} ${FTP_USER}@${FTP_HOST}:${verPath}/
                        echo "${OUT_DIR}" | ssh -o StrictHostKeyChecking=no -i "$KEY" ${FTP_USER}@${FTP_HOST} "cat > ${FTP_ROOT}/latest.txt"
                    '''
                    echo "OK 已上传到制品服务器: example-rk_Build_Version/${OUT_DIR}/"
                }
            }
        }
    }

    post {
        failure {
            echo '构建或上传失败，请查看上方各 Stage 日志'
        }
    }
}
```

**逐段解释（小白重点）：**

- `agent { label 'build-agent-01' }`：声明"这个任务在标签为 build-agent-01 的机器上跑"。
- `dir("${SDK_DIR}")`：把后续命令的工作目录切到代码根目录，免得每条都写全路径。
- **stage 1~4**：你们项目的准备工作（生成软链、切分支、拉最新代码、再生成软链）。命令按你们实际脚本名改。
- **stage 5（Docker 编译）** 几个关键参数：
  - `--rm`：编完自动删容器，不留垃圾。
  - `-i`（不是 `-t`）：保持标准输入、可重定向日志，但**不要 `-t`**（TTY）—— 无界面的 CI 环境加 `-t` 会卡住不动。这是真实踩坑。
  - `--mount ... target=/home/SDK_DIR`：把编译机上的代码目录**挂进容器**，容器里改的东西映射到外面，产物才能拿到。
  - `--user $(id -u):$(id -g)`：用当前用户身份跑，避免产物文件变成 root 属主、后续 scp 没权限。
  - `-c "source zmake ..."`：在容器里执行你们的编译入口脚本。
- **stage 6（上传）**：用编译机本地已放好的私钥 `id_rsa_artifact` 走 scp。好处是**不用在 Jenkins 里建凭据**，和直接在机器上 scp 一模一样。

---

## 八、步骤 5：创建 Pipeline 任务

1. Jenkins 首页 → **新建任务（New Item）**
2. 输入任务名（例 `ExampleRK-Build`）→ 选 **Pipeline** → 确定
3. 往下翻到 **Pipeline** 配置区：
   - 选 **Pipeline script**，把上面那段脚本粘进文本框；或
   - 选 **Pipeline script from SCM**，填 Git 仓库地址和 Jenkinsfile 路径（推荐，便于版本管理）
4. 保存。

---

## 九、步骤 6：一个隐藏坑 —— holdOffBuildUntilSave

如果你是用**脚本 / REST 推送**配置（像上一篇文章那样），任务可能会处于"暂时不能构建"的状态，手动点构建会报 **409**。原因是 Jenkins 有个 `holdOffBuildUntilSave` 标志，REST 改配置后会置位。

**两种解法（任选）：**

- ✅ 在 Jenkins Web 界面打开这个任务 → 随便点一下**保存（Save）**，标志即清除；
- ✅ 或用脚本控制台（见上一篇文章 5.5）执行：
  ```groovy
  Jenkins.instance.getItemByFullName('ExampleRK-Build').save()
  ```

> 注意：**在 Web 界面里手动编辑并保存脚本，不会触发这个坑**；只有用 REST / API 批量推送配置时才会出现。所以如果你是自己手改流水线，直接保存就能跑。

---

## 十、步骤 7：触发构建 & 看日志

- **手动**：任务页点 **Build Now（立即构建）**
- **AI / REST**：`curl -X POST .../job/ExampleRK-Build/build`（见上一篇文章）
- 点构建号 → **Console Output（控制台输出）** 看实时日志，哪一步红了一目了然。

---

## 十一、常见错误速查

| 现象 | 原因 | 解决 |
|------|------|------|
| 节点小球红 / 无法连接，报 `UnsupportedClassVersionError` | 编译机 Java 版本太低（< 17） | 装 Java 21 并在节点配置里填 `JavaPath` |
| 推送含中文配置返回 HTTP 500 | `Content-Type` 没加 `charset=UTF-8` | 改成 `application/xml; charset=UTF-8` |
| 点构建报 409 not buildable | `holdOffBuildUntilSave` 标志 | 界面点保存，或脚本控制台 `save()` |
| Docker 步骤卡住不动 | 误加了 `-t`（TTY） | 去掉 `-t`，只留 `-i` |
| 上传 scp 报权限拒绝 | 私钥没 `chmod 600` 或用户不对 | `chmod 600` 私钥；确认 `--user` 与 ssh 用户一致 |

---

## 十二、脱敏对照表 & 小白如何获取真实值

| 文中示例值 | 真实对应什么 | 小白怎么获取 |
|-----------|-------------|-------------|
| `jenkins.example.com:8080` | 你们的 Jenkins 地址 | 问运维 / 浏览器地址栏复制 |
| `build-agent-01` / `192.168.100.20` | 编译机节点名 / IP | 你的编译服务器信息，问运维或 `ip addr` 查看 |
| `builduser` / `BuildPass@123` | 编译机 SSH 账号 / 密码 | 编译机管理员提供 |
| `/opt/java21/bin/java` | 编译机上的 Java 21 路径 | 在编译机上 `which java` 或你拷贝 Java 的目录 |
| `/data/build/example-rk/rv1103` | 项目代码根目录 | 你们项目的实际存放路径 |
| `develop` | 代码分支名 | `git branch` 看你们用的分支 |
| `rockchip-build:v1.1` | 编译用 Docker 镜像 | 你们镜像仓库里的镜像名，问编译环境负责人 |
| `192.168.100.30` / `artifact` | 制品服务器 IP / 账号 | 负责出包的同事 / 运维提供 |
| `/srv/artifacts/..._Build_Version` | 制品上传目录 | 制品服务器上约定的存放路径 |
| `/home/builduser/.ssh/id_rsa_artifact` | 编译机到制品服务器的 SSH 私钥 | 在编译机上 `ssh-keygen` 生成，并把公钥放到制品服务器 |

**一句话总结**：编译机信息问运维、分支问研发、Docker 镜像问编译环境负责人、制品服务器问出包同事。把这些值替换进脚本，再按第八~十节创建任务并构建，你就有了一条"点一下自动出包"的流水线。

---

## 系列文章（AI 工具链）

本博客「AI 工具链」系列，教你把各类研发工具接入 AI 助手（悟空）：

- [让 AI 管理你的代码仓库：Gitea MCP Server 接入指南](https://sikinzen.github.io/posts/howtoconnectgiteaandai/)
- [让 AI 帮你管代码评审：Gerrit 接入指南](https://sikinzen.github.io/posts/howtoconnectgerritandai/)
- [让 AI 管理你的项目：禅道接入指南](https://sikinzen.github.io/posts/howtoconnectzentaoandai/)
- [让 AI 读懂你的微信聊天记录：wechat-cli + wx_key 接入指南](https://sikinzen.github.io/posts/howtoconnectwechatandai/)
- [让 AI 读懂你的企业微信：wechat-decrypt 接入指南](https://sikinzen.github.io/posts/howtoconnectwecomandai/)
- [在 WorkBuddy 中通过 REST API 操作 Jenkins：原理与实战](https://sikinzen.github.io/posts/howtoconnectjenkinsandai/)
- [在 Jenkins 上搭建基于 Docker 的编译流水线：手把手教程](https://sikinzen.github.io/posts/howtobuildjenkinscompilejob/)
