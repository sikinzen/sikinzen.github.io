---
title: "把 Jenkins 流水线从内联脚本重构为从 SCM 读取：Pipeline as Code 实践与踩坑"
date: 2026-07-24T20:50:00+08:00
lastmod: 2026-07-24T20:50:00+08:00
draft: false
description: "记录一次把 Jenkins 构建流水线从「Pipeline script 内联框」重构为「Pipeline script from SCM」（Jenkinsfile 进 Git）的全过程：为什么做、怎么做、以及过程中纠正的几个关键误区与踩坑。"
summary: "以真实的 FM270 构建流水线 from-SCM 重构为例，讲清 Pipeline as Code 的动机、CpsScmFlowDefinition 与 CpsFlowDefinition 的区别、仓库布局与 lightweight checkout 等经验教训，并附脱敏后的完整 Jenkinsfile。"
categories: ["AI应用"]
tags: ["Jenkins", "Pipeline", "Pipeline-as-Code", "CI/CD", "DevOps", "SCM", "Jenkinsfile"]
keywords: ["jenkins", "pipeline", "from scm", "pipeline as code", "cpsscmflowdefinition", "cpsflowdefinition", "jenkinsfile", "ci/cd", "持续集成", "轻量检出"]
series: ["AI工具链"]
---

把流水线脚本从 Jenkins 任务的「Pipeline script」内联框，搬进 Git 仓库、改用 **Pipeline script from SCM** 读取，是一次典型的 *Pipeline as Code* 实践。本文用我们一条真实存在的构建流水线（FM270 RK 固件每日构建）作为案例，复盘**为什么要搬、怎么搬、以及中途纠正的几个误区**。

> 预期读者：已经会用 Jenkins 建过一两条流水线、知道 Pipeline 基本语法的同学。本文不从头讲 Jenkins 安装，重点在「内联 → SCM」这一跃迁的决策与坑。

## 一、为什么要把流水线搬进 Git

最初这条流水线是把整段 `pipeline { ... }` 直接贴在 Jenkins 任务的「Pipeline script」输入框里（底层是 `CpsFlowDefinition`，脚本存 `<script>` 节点）。能跑，但有几个越来越明显的痛点：

1. **流水线逻辑是「代码」，却没进版本库**。改一行 stage、调一个超时时间，要么进 Jenkins UI 手改，要么用 `curl` 把整份 `config.xml` POST 回去。没有 diff、没有 blame、改错了只能靠记忆回滚。
2. **不可评审**。同事想加个通知、改个分支，只能在 Jenkins 上改完告诉你「我改了」，没法走 PR 评审。
3. **扩展受限**。脚本藏在 UI 里，想抽公共脚本、加一个发布环节都很别扭——直到它变成仓库里的文件，才顺理成章地长出**新的能力**（见下文 Stage 7）。

把脚本抽成 `Jenkinsfile` 放进内部 Git（类似 GitHub 的 Gitea）之后，上述问题一次性解决：改动走 PR、可评审、可回滚、可 `blame`；也顺带解锁了**多项目复用**（FM270、FM256 共用同一个脚本仓库，各放子目录）和**摆脱 `curl` 手改含中文 `config.xml` 的那堆坑**（字符集、`holdOffBuildUntilSave`、409 之类）。

> 本文主线是「Pipeline as Code / 版本管理」。禅道发布、多项目复用、摆脱 REST 手改是它带来的**附带收益**，下面会点到但不展开成主角。

## 二、怎么搬：从内联到 from SCM

### 2.1 两种定义方式对比

Jenkins 的 Pipeline 定义有两种 `definition` class，记住这层对应关系就不会迷路：

| 方式 | definition class | 脚本存放 | 配置要点 |
|---|---|---|---|
| 内联（Pipeline script） | `CpsFlowDefinition` | Jenkins 任务内 `<script>` | 直接贴脚本 |
| **从 SCM（Pipeline script from SCM）** | `CpsScmFlowDefinition` | Git 仓库里的 `Jenkinsfile` | `<scm>` 指定仓库/分支/凭据 + `<scriptPath>` 指定文件路径 |

`from SCM` 的核心就是在任务配置里把「脚本来源」从「本任务内联」换成「去某个 Git 仓库的某个路径读 `Jenkinsfile`」。

### 2.2 仓库布局

我们没有给每条流水线单独开仓库，而是用一个**共享的脚本仓库**，按任务名分子目录：

```
jenkins-pipelines/                # 内部 Git 仓库（类 GitHub 的 Gitea）
├── FM270_RK_Build_Pipeline/
│   ├── Jenkinsfile              # 流水线定义
│   └── scripts/
│       └── publish_to_zentao.sh # 运行期调用的脚本（如发布到项目管理平台）
├── FM256_Pipeline/
│   └── Jenkinsfile
└── ...
```

流水线里用 `PIPELINE_DIR = "${WORKSPACE}/FM270_RK_Build_Pipeline"` 引用本任务目录，运行期 `scripts/*.sh` 就靠它定位——这是「脚本进仓库」后才有的便利。

### 2.3 关键配置字段

`from SCM` 任务里最关键的几行（脱敏示意）：

```xml
<definition class="org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition" plugin="workflow-cps@...">
  <scm class="hudson.plugins.git.GitSCM" plugin="git@...">
    <userRemoteConfigs>
      <hudson.plugins.git.UserRemoteConfig>
        <url>http://scm.example.com:3000/team/jenkins-pipelines.git</url>
        <credentialsId>gitea-deploy</credentialsId>
      </hudson.plugins.git.UserRemoteConfig>
    </userRemoteConfigs>
    <branches>
      <hudson.plugins.git.BranchSpec>
        <name>*/main</name>
      </hudson.plugins.git.BranchSpec>
    </branches>
  </scm>
  <scriptPath>FM270_RK_Build_Pipeline/Jenkinsfile</scriptPath>
  <lightweight>true</lightweight>
</definition>
```

要点：

- `<url>` + `<credentialsId>`：SCM 拉取用的 Git 地址与 Jenkins 凭据（**注意这是「拉 Jenkinsfile 的凭据」，和运行时 scp 用的节点私钥是两回事，见 3.3**）。
- `<scriptPath>`：仓库内 `Jenkinsfile` 的相对路径，必须带任务子目录。
- `<branches>`：分支 `*/main`（refspec 写法）。
- `<lightweight>`：`true` 表示轻量检出，见 3.2。

## 三、经验教训与踩坑

### 3.1 误区澄清：from SCM 并不会报 500

我们早期一度认为 `CpsScmFlowDefinition`（from SCM）在本环境「会 500、不可用」，所以一度只用内联。后来实测证明：**from SCM 完全可用**，现在这条每日构建流水线就是 from SCM。

回头看，之前那些 500 的真正原因是**别的**：要么是 `config.xml` 本身的 XML 写得不合规（比如中文作业名在 Jenkins 主容器非 UTF-8 默认字符集下会抛 `InvalidPathException`），要么是 `curl` 推配置时没带 `Content-Type: application/xml; charset=UTF-8`。跟「是不是 from SCM」无关。

**结论**：在本环境优先用 from SCM；若某次配置报 500，先查 XML 合法性与中文字符集，别急着甩锅给 SCM 定义方式。

### 3.2 lightweight checkout 的边界

`lightweight=true` 只做**稀疏检出**——Jenkins 只把 `Jenkinsfile` 这一个文件拉下来用于解析流水线，速度快、节省空间。但它有一个边界：**流水线在「解析期」（还没真正 checkout 完整仓库时）不能依赖仓库里其它文件**。

本例里 `scripts/publish_to_zentao.sh` 是在 **运行期**（stage 执行时）才调用，此时完整仓库早已检出，`PIPELINE_DIR` 指向的就是完整路径，所以安全。如果你打算在 `Jenkinsfile` 顶部（解析期）`load` 别的 `.groovy` 文件，轻量检出就会找不到——要么关掉 `lightweight`，要么把那些文件也走正式 SCM step 引入。

### 3.3 两套凭据别混

- **SCM 凭据**（`credentialsId`，如 `gitea-deploy`）：仅用于 Jenkins **拉取 `Jenkinsfile`**。HTTPS 地址配一个 Jenkins 用户名/令牌凭据即可。
- **运行时凭据**（如节点上的 scp 私钥 `/home/builduser/.ssh/id_rsa_artifact`）：流水线真正跑 `scp` 上传产物时用的，是**构建节点本地文件**，不走 Jenkins 凭据系统。

两者职责不同，配置时别把运行时私钥误填进 SCM 凭据，也别指望 SCM 凭据能帮你免密 scp。

### 3.4 触发器 / 参数写进代码，消除配置漂移

内联时代，定时触发（`cron`）和参数常常靠 REST 注入进 `config.xml`，容易和「脚本本体」脱节（改了脚本忘了改触发器）。搬进 `Jenkinsfile` 后，我们把它们**明确写进代码**：

```groovy
triggers {
    cron('TZ=Asia/Shanghai\nH 2 * * 1-5')   // 上海时区，工作日 2 点附近
}
parameters {
    booleanParam(name: 'PUBLISH_TO_ZENTAO', defaultValue: true,
                 description: '编译并上传成功后，在项目管理平台创建构建记录')
}
```

这样「什么时候跑、带什么参数」和「跑什么」永远在同一个文件里，版本一致、一目了然。

### 3.5 旧内联任务留作回退

重构没有「原地覆盖」旧的 `FM270-RK-Build` 内联任务，而是**新建**一个 from-SCM 的任务（放在 `Daily_Build` 文件夹下），旧任务保留。等新任务连续跑稳几天、确认行为一致后，再考虑弃用旧的。这是低风险迁移的基本功：**新旧并存验证，而非一刀切替换**。

## 四、脱敏后的完整 Jenkinsfile 示例

下面是从真实仓库取出的 `Jenkinsfile`，已做脱敏（IP、账号、内部路径、仓库名、镜像名均替换为仿真值；真实映射见文末对照表）。它能完整反映这次重构后的形态——注意相比最初内联版，它**多了 Stage 7「发布到禅道」、参数、`buildDiscarder` 保留策略**，这些正是「脚本进仓库后易扩展」的实证。

```groovy
// FM270_RK_Build Pipeline（脱敏示例）
// 部署：Pipeline script from SCM → Script Path = FM270_RK_Build_Pipeline/Jenkinsfile

pipeline {
    agent { label 'build-node-01' }

    parameters {
        booleanParam(
            name: 'PUBLISH_TO_ZENTAO',
            defaultValue: true,
            description: '编译并上传成功后，在项目管理平台(禅道)创建构建记录'
        )
    }

    options {
        timeout(time: 8, unit: 'HOURS')
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '20'))
    }

    triggers {
        // 工作日 2 点附近（上海时区）
        cron('TZ=Asia/Shanghai\nH 2 * * 1-5')
    }

    environment {
        PIPELINE_DIR = "${WORKSPACE}/FM270_RK_Build_Pipeline"
        SDK_DIR = '/srv/sdk/fm270-rv1103b'
        ZPRJ    = 'zprj/fm270/yqjy/jm2x0_cd1xxx_4k_apps/'

        SCP_USER = 'artifact'
        SCP_HOST = '10.0.0.30'
        SCP_ROOT = '/srv/artifacts/fm270-build'
        SCP_KEY  = '/home/builduser/.ssh/id_rsa_artifact'

        FTP_DIR  = 'fm270-build'
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
                    sh './zswitch_branch.sh xm_uni_branch_linux'
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
                    // 进入编译容器，去掉 -t（无 TTY），直接执行编译命令
                    sh '''
                        docker run --rm -i --entrypoint /bin/bash \
                            --mount type=bind,source=$(pwd)/,target=/home/SDK_DIR \
                            --net host \
                            --user $(id -u):$(id -g) \
                            --workdir /home/SDK_DIR \
                            rk-build-image:v1.1 \
                            -c "source zmake zprj/fm270/yqjy/jm2x0_cd1xxx_4k_apps/"
                    '''
                }
            }
        }

        stage('6. 上传到产物服务器') {
            steps {
                dir("${SDK_DIR}") {
                    script {
                        def latest = sh(script: 'ls -t output | head -1', returnStdout: true).trim()
                        if (!latest) {
                            error '未在 output/ 下找到时间目录，编译产物可能缺失'
                        }
                        env.OUT_DIR = latest
                        env.verName = latest.replace('.zip', '')   // 去掉版本目录名里的 .zip
                        env.BUILD_NAME = env.verName
                    }
                    sh '''
                        R620_KEY="${SCP_KEY}"
                        chmod 600 "$R620_KEY"
                        verPath="${SCP_ROOT}/${verName}"
                        ssh -o StrictHostKeyChecking=no -i "$R620_KEY" ${SCP_USER}@${SCP_HOST} "mkdir -p ${verPath}"
                        if [ -d "output/${OUT_DIR}" ]; then
                            scp -o StrictHostKeyChecking=no -i "$R620_KEY" -r "output/${OUT_DIR}/." ${SCP_USER}@${SCP_HOST}:"${verPath}/"
                        else
                            scp -o StrictHostKeyChecking=no -i "$R620_KEY" -r "output/${OUT_DIR}" ${SCP_USER}@${SCP_HOST}:"${verPath}/"
                        fi
                        echo "${verName}" | ssh -o StrictHostKeyChecking=no -i "$R620_KEY" ${SCP_USER}@${SCP_HOST} "cat > ${SCP_ROOT}/latest.txt"
                    '''
                    echo "OK 已上传: fm270-build/${verName}/"
                }
            }
        }

        stage('7. 发布到项目管理平台') {
            when {
                expression { return params.PUBLISH_TO_ZENTAO }
            }
            steps {
                script {
                    if (!env.BUILD_NAME?.trim()) {
                        error 'BUILD_NAME 为空，无法发布（请确认上传阶段已产生 verName）'
                    }
                    sh """
                        export BUILD_NAME='${env.BUILD_NAME}'
                        export FTP_DIR='${env.FTP_DIR}'
                        export CHANGES_SINCE_LAST='自动构建发布（FM270_RK_Build Pipeline）'
                        bash '${PIPELINE_DIR}/scripts/publish_to_zentao.sh'
                    """
                }
            }
        }
    }

    post {
        always {
            emailext (
                subject: "FM270 每日构建 ${currentBuild.currentResult}：${env.JOB_NAME} #${env.BUILD_NUMBER}",
                body: """构建结果：${currentBuild.currentResult}
构建任务：${env.JOB_NAME} #${env.BUILD_NUMBER}
构建链接：${env.BUILD_URL}
编译产物已上传至产物服务器: fm270-build/${verName}/。
项目管理平台发布：${params.PUBLISH_TO_ZENTAO ? '已开启' : '未开启'}
详细日志请查看构建 Console Output。""",
                to: 'dev1@corp.example.com, dev2@corp.example.com, dev3@corp.example.com, dev4@corp.example.com, dev5@corp.example.com, dev6@corp.example.com'
            )
        }
        success { echo '构建并上传成功' }
        failure { echo '构建或上传失败，请查看上方各 Stage 日志' }
    }
}
```

## 五、对照表与如何获取真实值

本文为安全起见对内部信息做了脱敏，下表给出「文中仿真值 → 真实环境」的对应关系，方便你自己环境落地时替换：

| 文中仿真值 | 真实含义（请在你的环境替换） | 如何获取 |
|---|---|---|
| `http://scm.example.com:3000/team/jenkins-pipelines.git` | 内部 Git（类 GitHub 的 Gitea）里的脚本仓库 | 问团队 SCM/CI 管理员，或自建 Gitea/GitLab 仓库 |
| `gitea-deploy` | Jenkins 中用于拉取该仓库的凭据 ID | Jenkins → 凭据 → 找到对应用 HTTPS 凭据的 ID |
| `build-node-01` | 实际构建节点的 agent label | Jenkins → 节点管理 → 看节点 `label` |
| `/srv/sdk/fm270-rv1103b` | 构建机上的 SDK 代码根目录 | 问固件负责人，或 `repo` 工作区根 |
| `zprj/fm270/yqjy/jm2x0_cd1xxx_4k_apps/` | 具体产品/客户/变体的工程相对路径 | 你们 SDK 里的实际 `zprj/...` 路径 |
| `10.0.0.30` / `/srv/artifacts/fm270-build` | 产物上传目标机与目录 | 问负责产物分发/门户的同事 |
| `artifact` / `id_rsa_artifact` | 上传用的 SSH 账号与节点私钥 | 构建节点 `~/ .ssh/` 下实际私钥文件 |
| `rk-build-image:v1.1` | 编译用 Docker 镜像名 | 你们编译容器的实际镜像 tag |
| `xm_uni_branch_linux` | 实际编译分支名 | `git branch -r` 看远端分支 |
| `dev1@corp.example.com...` | 构建通知邮件收件人 | 你们团队的邮箱列表 |
| `项目管理平台(禅道)` / `publish_to_zentao.sh` | 内部项目管理平台及发布脚本 | 问研发PM/配置管理；脚本逻辑对接你们平台的 Open API |

> 提示：脱敏值仅用于讲清结构与思路，**不要原样拷到生产**。把上表右列换成你自己的真实值即可。

## 小结

把流水线从「内联框」搬进 Git（Pipeline as Code），最大的收益不是某个花哨功能，而是**让构建逻辑重新变成「可版本化、可评审、可回滚」的代码**。这次重构还顺手证明了两件事：

- `Pipeline script from SCM`（`CpsScmFlowDefinition`）在本环境完全可用，早先的「500 不可用」是误判，真凶是 XML 合规性与中文字符集；
- 一旦脚本进了仓库，「加一个发布 stage、抽一个公共脚本、多项目复用同一仓库」都变得自然而然——重构后的 Stage 7「发布到禅道」就是最好的例子。

如果你的 Jenkins 里还躺着几条内联流水线，值得抽个下午把它们搬进 SCM；风险可控（新旧并存验证），回报长期。

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
- [把 Jenkins 流水线重构为从 SCM 读取（Pipeline as Code）](https://sikinzen.github.io/posts/refactorjenkinsinlinetoscm/)
