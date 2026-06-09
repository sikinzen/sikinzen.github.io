---
title: "如何使用 AI 搭建自己的博客"
date: 2026-06-05T13:14:00+08:00
lastmod: 2026-06-09T20:57:00+08:00
draft: false
description: "从零到上线，全程用 AI 助手搭建 Hugo + GitHub Pages 个人技术博客的完整记录"
summary: "用 WorkBuddy AI 助手，从零搭建 Hugo + PaperMod + GitHub Pages 博客，记录完整过程和踩坑经验"
categories: ["工具"]
tags: ["Hugo", "GitHub Pages", "AI助手", "博客搭建", "PaperMod"]
keywords: ["Hugo", "GitHub Pages", "博客搭建", "静态站点", "PaperMod"]
series: []
---

## 为什么要自己搭博客？

在 CSDN 写了多年技术文章，一直想有一个**完全属于自己的空间**——文章存在自己硬盘里，域名自己定，不需要被平台审核，也没有广告。

恰巧最近在用 AI 助手（WorkBuddy），于是尝试让它全程帮我搭建。结果出乎意料地顺利，从零到上线只花了一个下午。

本文记录**完整过程**，每一步都可直接复现，供有类似需求的同学参考。

---

## 技术选型：为什么选 Hugo + GitHub Pages？

| 方案 | 优点 | 缺点 |
|------|------|------|
| **Hugo + GitHub Pages** | 免费、完全可控、Markdown 写作、随时可迁移 | 需要一点命令行基础 |
| Hexo + Vercel | 交互性强、现代感 | 配置相对复杂 |
| 语雀 / 知乎 | 零门槛、有流量 | 数据不在自己手里 |
| WordPress | 功能全面 | 维护成本高、需要服务器 |

最终选 **Hugo + GitHub Pages**，核心原因是：**文章用 Markdown 写，100% 可迁移，平台跑路也不怕。**

---

## 第一步：安装 Hugo

Hugo 是用 Go 写的静态站点生成器，特点是**构建速度极快**（几千页毫秒级）。

### Windows 安装（推荐 winget）

```bash
winget install Hugo.Hugo.Extended
```

> ⚠️ **务必安装 Extended 版本**，支持 SASS/SCSS，否则 PaperMod 等主题会构建失败。

### macOS / Linux 安装

```bash
# macOS（用 Homebrew）
brew install hugo

# Ubuntu / Debian
sudo apt install hugo

# 或者下载 release 二进制
# https://github.com/gohugoio/hugo/releases
```

### 验证安装

```bash
hugo version
# 输出：hugo v0.162.1+extended ...
```

> ✅ 本文后续 workflow 配置中指定 Hugo 版本为 `0.162.1`，建议安装相同版本避免兼容问题。

---

## 第二步：创建站点

```bash
# 创建新站点
hugo new site wenling-buyi-blog

# 进入目录
cd wenling-buyi-blog
```

目录结构如下：

```
wenling-buyi-blog/
├── archetypes/    # 文章模板（hugo new 时自动套用）
├── assets/        # 需要处理的前端资源
├── content/       # 【你的文章放这里】
├── data/          # 数据文件
├── layouts/       # 自定义布局
├── static/        # 图片等静态资源（直接复制到产出目录）
├── themes/        # 主题目录
├── .gitignore     # Git 忽略规则
└── config.toml    # 【核心配置文件】
```

> 💡 `hugo new site` 创建的只是骨架，主题和内容需要自己加。

---

## 第三步：配置 .gitignore

在站点根目录创建 `.gitignore`，避免把构建产物提交到 Git：

```gitignore
# Hugo 构建产物
/public/
/resources/_gen/
/.hugo_cache/

# 系统文件
.DS_Store
Thumbs.db

# IDE
.vscode/
.idea/

# 主题子模块的临时文件
/themes/*/node_modules/
/themes/*/package-lock.json
```

---

## 第四步：安装 PaperMod 主题

[PaperMod](https://github.com/adityatelange/hugo-PaperMod) 是一款非常流行的 Hugo 主题，简洁、响应式、对中文支持好，GitHub Stars 超过 10k。

### 用 Git 子模块方式安装（推荐）

```bash
git init
git submodule add https://github.com/adityatelange/hugo-PaperMod themes/PaperMod
```

> ✅ **为什么用 submodule？** 主题后续有更新时，只需 `git submodule update --remote` 即可同步，不会和你自己的修改冲突。

### 在 config.toml 中指定主题

```toml
theme = "PaperMod"
```

---

## 第五步：配置 config.toml（最核心的一步）

直接上我的最终配置（已验证可用），逐项加了注释：

```toml
baseURL = 'https://sikinzen.github.io/'
languageCode = 'zh-CN'
locale = 'zh-CN'          # Hugo v0.158+ 使用，替代 languageCode 的废弃警告
title = '温陵布衣'

theme = "PaperMod"

# ===== 基础参数 =====
[params]
  description = "技术探索与实践心得"

  # ===== 首页 Profile 模式（展示个人信息）=====
  [params.homeInfoParams]
    Title = "你好 👋，我是 sikinzen"
    Content = """
    📍 厦门思明  
    🔧 手机方案设计 / AI 设备 / 对俄外贸  
    💻 技术栈：嵌入式 Linux、Android、AI 应用开发  
    这里记录技术探索与实践心得，偶尔也聊聊工具与方法论。
    """

# ===== 导航栏 =====
[[params.mainSections]]
section = "posts"

# ===== 文章目录（右侧 TOC）=====
[params.toc]
  enable = true
  endLevel = 4          # 最多显示到 #### 四级标题

# ===== 代码高亮 =====
[markup.highlight]
  anchorLineNos = true
  lineAnchors = true
  lineNumbersInTable = true

# ===== 分页 =====
[pagination]
  pagerSize = 10

# ===== 社会化链接（右上角）=====
# 在 config.toml 的 [params] 下添加：
# [[params.socialIcons]]
#   name = "github"
#   url  = "https://github.com/sikinzen"
```

> 📝 **更多 PaperMod 配置选项** 参见官方文档：https://github.com/adityatelange/hugo-PaperMod/wiki/Variables

---

## 第六步：配置文章模板（archetypes）

`hugo new` 创建新文章时，会自动从 `archetypes/default.md` 读取模板。创建一个好用的模板能大幅提升写作体验：

在 `archetypes/default.md` 写入：

```markdown
---
title: "{{ replace .Name "-" " " | title }}"
date: {{ .Date }}
draft: true
description: ""
summary: ""
categories: []
tags: []
keywords: []
series: []
---
```

> 💡 `draft: true` 表示文章是草稿，构建时**不会发布到线上**。`draft: false` 才正式发布。

---

## 第七步：写第一篇文章

```bash
# ⚠️ 必须在博客根目录下运行！
cd G:\AiStudy\MyBlog\Wenling-buyi-blog
hugo new posts/hello.md
```

打开生成的 `content/posts/hello.md`，编辑内容：

```markdown
---
title: "温陵布衣，开张了"
date: 2026-06-04T22:00:00+08:00
draft: false
description: "从 CSDN 迁移到 Hugo + GitHub Pages，一个属于我自己的技术角落"
tags: ["开篇"]
categories: ["随笔"]
---

从 CSDN 迁移到 Hugo + GitHub Pages，一个属于我自己的技术角落 🎉

## 为什么迁移？

CSDN 虽然方便，但广告多、审核严、数据不在自己手里。
用自己的域名、自己的平台，写起来更自在。

## 接下来

会把之前在 CSDN 上的技术文章逐步迁移过来，
同时也在这里记录新的技术探索。
```

---

## 第八步：本地预览

在发布之前，先本地预览确认效果：

```bash
hugo server -D
```

> `-D` 参数表示**包含草稿文章**（draft: true 的也会显示）。

然后在浏览器打开 **http://localhost:1313** 就能实时预览。修改 Markdown 文件后会自动刷新，非常方便。

按 `Ctrl + C` 停止本地服务器。

---

## 第九步：创建 About 页面 + 搜索/归档页

### 9.1 关于页

```bash
# 创建 about 页面
hugo new content/about.md
```

编辑 `content/about.md`：

```markdown
---
title: "关于"
description: "关于温陵布衣"
---
这里是「温陵布衣」的技术博客。

温陵是泉州古称，布衣取"布衣之士"之意。

- GitHub：https://github.com/sikinzen
- 邮箱：sikinzen@example.com（替换为真实邮箱）
```

### 9.2 搜索页（⚠️ 很多人会漏掉这步！）

PaperMod 导航栏自带搜索按钮，但**需要手动创建对应页面文件**，否则点击后 404：

```bash
mkdir -p content/search
```

创建 `content/search/_index.md`：

```markdown
---
title: "Search"
layout: search
description: "搜索文章"
---
```

> ⚠️ **必须是 `_index.md`（下划线开头）**，不能写成 `search.md`！详见踩坑记录 #10~#12。

### 9.3 归档页（同上，不创建会 404）

```bash
mkdir -p content/archives
```

创建 `content/archives/_index.md`：

```markdown
---
title: "Archives"
layout: archives
description: "文章归档"
---
```

---

## 第十步：配置 GitHub Pages 自动部署（最容易踩坑的一步）

### 10.1 在 GitHub 创建仓库

1. 打开 https://github.com/new
2. **Repository name 必须填：`你的用户名.github.io`**
   - 例如我的用户名是 `sikinzen`，仓库名就是 `sikinzen.github.io`
3. 选择 **Public**
4. **不要**勾选 "Add a README file"
5. 点击 **Create repository**

### 10.2 创建 GitHub Actions workflow

在本地博客目录创建文件 `.github/workflows/deploy.yml`：

```yaml
name: Deploy Hugo to GitHub Pages

on:
  push:
    branches: ["main", "master"]

  workflow_dispatch: # 支持手动触发

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: "pages"
  cancel-in-progress: false

defaults:
  run:
    shell: bash

jobs:
  build:
    runs-on: ubuntu-latest
    env:
      HUGO_VERSION: 0.162.1
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          submodules: true      # ⚠️ 关键：拉取 PaperMod 子模块
          fetch-depth: 0

      - name: Setup Hugo
        uses: peaceiris/actions-hugo@v2
        with:
          hugo-version: ${{ env.HUGO_VERSION }}
          extended: true

      - name: Build with Hugo
        run: hugo --minify --gc

      - name: Upload artifact
        uses: actions/upload-pages-artifact@v3
        with:
          path: ./public

  deploy:
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    runs-on: ubuntu-latest
    needs: build
    steps:
      - name: Deploy to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@v4
```

> ⚠️ **注意 branches 要同时包含 `"main"` 和 `"master"`**，因为不同人的 GitHub 默认分支可能不同。

### 10.3 关联远程仓库并推送

```bash
# 在博客根目录执行
git add .
git commit -m "init: 温陵布衣博客初始化"
git branch -M master
git remote add origin https://github.com/sikinzen/sikinzen.github.io.git
git push -u origin master
```

> 把 `sikinzen` 替换成你自己的 GitHub 用户名。

---

## 第十一步：在 GitHub 开启 Pages

这一步**必须手动操作**，AI 没法替你点：

1. 打开 https://github.com/你的用户名/你的用户名.github.io/settings/pages
2. 找到 **Source（源）** 部分
3. 把选项从 **"Deploy from a branch"** 改成 **"GitHub Actions"**
4. 点击 **Save** 保存

设置完之后，GitHub Actions 会自动运行，约 **1~2 分钟**博客就上线了。

---

## 第十二步：验证部署状态

推送后，访问你的仓库 **Actions** 标签页，查看部署进度：

- 🟡 **in progress** — 正在构建，等 1~2 分钟
- 🟢 **green checkmark** — 部署成功！访问 `https://你的用户名.github.io/` 查看
- 🔴 **red X** — 构建失败，点进去看 Logs 找原因

### 常见构建失败原因

| 错误信息 | 原因 | 解决方法 |
|---------|------|---------|
| `process exited with error: 1` | Hugo 版本太旧，与 PaperMod 不兼容 | workflow 里指定 `hugo-version: '0.162.1'` |
| `theme not found` | 没拉取 PaperMod 子模块 | checkout 步骤加 `submodules: true` |
| 推送后没触发 Actions | workflow 里只监听 `main`，但仓库默认分支是 `master` | 在 `branches` 里加上 `"master"` |
| 404 页面 | GitHub Pages 没开启，或 Source 没选 "GitHub Actions" | 去 Settings → Pages 手动开启 |

---

## 日常写作与发布流程（最重要的一节）

博客搭好之后，**以后每次写文章只需要 4 步**：

### 完整流程

```bash
# ========== 第 1 步：创建新文章 ==========
cd G:\AiStudy\MyBlog\Wenling-buyi-blog
hugo new posts/文章标题.md
# 注意：必须在博客根目录运行！
# 生成位置：content/posts/文章标题.md

# ========== 第 2 步：编辑文章内容 ==========
# 用 VS Code 或任何 Markdown 编辑器打开
# content/posts/文章标题.md
#
# 重要字段说明：
#   draft: true   → 草稿，构建时不发布（本地 hugo server -D 可以看到）
#   draft: false  → 正式发布，git push 后就上线
#   description   → 文章摘要，显示在文章列表页
#   tags          → 标签，便于分类检索
#   categories    → 分类，比 tags 更粗粒度

# ========== 第 3 步：本地预览（可选）==========
hugo server -D
# 浏览器打开 http://localhost:1313 预览
# 确认效果后按 Ctrl+C 停止

# ========== 第 4 步：发布上线 ==========
git add .
git commit -m "new post: 文章标题"
git push
# → 自动触发 GitHub Actions 部署
# → 约 1~2 分钟后访问 https://你的用户名.github.io/ 看到新文章 ✅
```

### Front Matter 字段速查表

每篇文章顶部的 `---` 包裹的部分叫做 **Front Matter**，常见字段：

| 字段 | 说明 | 示例 |
|------|------|------|
| `title` | 文章标题（必填） | `"如何使用 Hugo 搭建博客"` |
| `date` | 发布时间（必填） | `2026-06-05T13:00:00+08:00` |
| `draft` | 是否为草稿 | `true`（不发布）/ `false`（发布） |
| `description` | 文章摘要 | `"本文介绍..."` |
| `summary` | 自定义摘要（覆盖 description） | `"..."` |
| `tags` | 标签（可多个） | `["Hugo", "GitHub Pages"]` |
| `categories` | 分类（可多个） | `["工具", "教程"]` |
| `keywords` | 关键词（SEO 用） | `["博客搭建"]` |
| `series` | 文章系列 | `["Hugo 教程"]` |

---

## 进阶：常用自定义配置

### 修改主题颜色

PaperMod 支持通过 `style` 参数自定义主题色，在 `config.toml` 的 `[params]` 下添加：

```toml
[params]
  # 亮色模式主题色
  [params.style]
    desktopTheme = "light"   # 桌面端默认主题：light / dark / auto
```

### 添加头像/作者图片

1. 把头像图片放到 `static/images/avatar.jpg`
2. 在 `config.toml` 的 `[params.homeInfoParams]` 上方添加：

```toml
[params]
  # 头像（显示在首页）
  [params.profileMode]
    enabled = true
    title = "你好 👋，我是 sikinzen"
    subtitle = "技术探索与实践心得"
    imageUrl = "images/avatar.jpg"
    imageTitle = "my avatar"
    imageWidth = 120
    imageHeight = 120
```

### 添加评论系统（可选）

PaperMod 内置支持多个评论系统，以 **Giscus**（基于 GitHub Discussions，免费）为例：

1. 先按 https://giscus.app/ 的指引配置好 GitHub Discussions
2. 在 `config.toml` 添加：

```toml
[params]
  [params.giscus]
    repo = "sikinzen/sikinzen.github.io"
    repoId = "你的 repo ID"
    category = "Announcements"
    categoryId = "你的 category ID"
    mapping = "pathname"
    reactionsEnabled = true
    theme = "preferred_color_scheme"
```

---

## 从 CSDN 迁移旧文章

如果你之前在 CSDN 有文章想迁移过来：

### 方法一：手动复制（适合文章少的情况）

1. 在 CSDN 打开旧文章，复制正文 Markdown（CSDN 编辑器支持导出 Markdown）
2. `hugo new posts/旧文章标题.md`
3. 粘贴内容，补充 front matter
4. `git add . && git commit && git push`

### 方法二：批量转换（适合文章多的情况）

CSDN 文章导出后通常是 HTML 或 Markdown，可以用 `pandoc` 做格式转换：

```bash
# 安装 pandoc
winget install pandoc

# HTML 转 Markdown
pandoc old-article.html -t markdown -o content/posts/old-article.md
```

> 💡 转换后务必人工检查一遍，特别是代码块和图片链接。

### 图片处理

CSDN 的图片在 `https://img-blog.csdn.net/` 等地址，建议下载到本地：

```
static/images/
├── 2024-01-01-article1/
│   ├── img1.png
│   └── img2.jpg
```

然后在 Markdown 里引用：

```markdown
![图片说明](/images/2024-01-01-article1/img1.png)
```

---

## 踩坑完整记录

以下是我搭建过程中真实遇到的所有坑，逐一记录解决方法：

| # | 问题 | 根本原因 | 解决方法 |
|---|------|---------|---------|
| 1 | `hugo new` 执行后找不到生成的文件 | 当前目录不在博客根目录 | 先 `cd` 到博客根目录再执行 |
| 2 | push 后博客 404 | GitHub Pages 默认没开启 | Settings → Pages → Source 选 **"GitHub Actions"** |
| 3 | Build 失败（`exit code 1`） | Hugo 版本太旧，与 PaperMod 不兼容 | workflow 指定 `hugo-version: '0.162.1'` |
| 4 | 触发不了 Actions | workflow 只监听 `main`，但仓库默认分支是 `master` | `branches` 加上 `"master"` |
| 5 | 主题没生效 / 构建报错找不到主题 | checkout 没拉取子模块 | 加 `submodules: true` |
| 6 | `fatal: 'themes/PaperMod' already exists and is not a valid git repo` | 之前有残留目录但不是合法子模块 | `rm -rf themes/PaperMod` 后重新 `git submodule add` |
| 7 | `*** Please tell me who you are.` | Git 未配置用户信息 | `git config user.email "xxx"` + `git config user.name "xxx"` |
| 8 | 本地 `hugo server` 正常，但 GitHub Actions 构建失败 | 本地 Hugo 版本与 workflow 指定版本不一致 | 统一版本号 |
| 9 | `languageCode` 废弃警告 | Hugo v0.158+ 改用 `locale` | 同时保留 `languageCode`（兼容旧版）和 `locale`（新版） |
| 10 | **🔍 导航栏"搜索"按钮点击后 404** | PaperMod 需要搜索页文件，但未创建 | 创建 `content/search/_index.md`（注意是 `_index.md`，不是 `.md`） |
| 11 | **📂 导航栏"归档"按钮点击后 404** | PaperMod 需要归档页文件，但未创建 | 创建 `content/archives/_index.md`（同上） |
| 12 | **创建了 search.md / archives.md 但仍然 404** | 用了普通 `.md` 文件格式，Hugo 把它当单页面处理，找不到 PaperMod 的内置模板 | 改用 `_index.md` 格式（section 首页），并放在对应的子目录中 |

### 🔥 重点展开：搜索和归档页 404 问题（问题 #10~#12）

这个问题**非常容易遇到**，因为 PaperMod 主题的导航栏默认就有「搜索」和「归档」两个按钮，但**不会自动创建对应页面**。

#### 现象

博客上线后，点击右上角：

- **🔍 搜索** → 跳转到 `/search/` → 显示 **404**
- **📂 归档** → 跳转到 `/archives/` → 显示 **404**

#### 错误做法（第一次尝试 ❌）

```bash
# ❌ 这样写不行！
echo '---\nlayout: search\n---' > content/search.md
echo '---\nlayout: archives\n---' > content/archives.md
# 结果：部署成功但访问仍然是 404
```

原因：普通 `.md` 文件在 Hugo 中被当作**独立单页面**处理，而 PaperMod 的搜索/归档功能需要的是 **Section 首页**——即该目录下的 `_index.md`。

#### 正确做法 ✅

```bash
# 第一步：创建子目录
mkdir -p content/search content/archives

# 第二步：创建 _index.md（注意下划线开头！）
```

创建 `content/search/_index.md`：

```markdown
---
title: "Search"
layout: search
description: "搜索文章"
---
```

创建 `content/archives/_index.md`：

```markdown
---
title: "Archives"
layout: archives
description: "文章归档"
---
```

> 💡 **关键知识点：Hugo 的两种页面类型**
>
> | 类型 | 文件路径 | 用途 | 示例 |
> |------|---------|------|------|
> | **普通页面** | `content/about.md` | 独立的单篇文章或页面 | 关于页、联系页 |
> | **Section 首页** | `content/posts/_index.md` | 该 section 的索引/列表页 | 文章列表、搜索、归档 |
>
> 搜索和归档都属于后者，必须用 `_index.md` 格式，否则 Hugo 找不到对应的 layout 模板。

#### 提交并发布

```bash
cd G:\AiStudy\MyBlog\Wenling-buyi-blog
git add content/search/ content/archives/
git commit -m "fix: 添加搜索和归档页，修复导航 404"
git push
# → 1~2 分钟后生效 ✅
```

### 其他值得注意的问题

#### 推送后 Actions 没有自动触发

如果先推送代码、再去 Settings → Pages 开启 GitHub Actions，**之前的推送不会触发 Actions**。需要再推一次（哪怕是空提交）来触发首次部署：

```bash
git commit --allow-empty -m "trigger: 启动 GitHub Pages 部署"
git push
```

#### 博客目录迁移后 Git 远程仓库丢失

如果用 `robocopy` 或手动复制方式迁移了博客目录，`.git` 目录可能不完整。迁移后务必验证：

```bash
cd 新目录
git status          # 应显示 On branch master, working tree clean
git remote -v        # 应显示 origin → https://github.com/xxx/xxx.git
git log --oneline -5 # 应看到完整的提交历史
```

如果 `git remote -v` 无输出，需要重新关联：

```bash
git remote add origin https://github.com/sikinzen/sikinzen.github.io.git
```

---

## 后续完善记录

博客上线后，又陆续做了不少优化。以下按时间线记录，方便后续追溯。

### 一、Bug 修复

**1. `languageCode` 弃用警告**

Hugo v0.158+ 中 `languageCode` 被标记为废弃，改用 `locale`。`config.toml` 中已删除 `languageCode` 字段，仅保留 `locale = 'zh-CN'`。

**2. 搜索页 & 归档页 404**

根因：`content/search/_index.md` 和 `content/archives/_index.md` 中 Front Matter 的 `---` 结束符缺失，导致 Hugo 无法正确解析，构建后这两个页面为空白/404。补全结束符后恢复正常。

### 二、功能增强

**1. 显示文章修改时间（`ShowLastMod`）**

三步实现：

```toml
# config.toml
enableGitInfo = true     # 让 Hugo 从 git log 自动提取每个文件的最后提交时间

[params]
  ShowLastMod = true      # 在文章页显示"修改: YYYY年M月D日"
```

创建自定义模板 `layouts/partials/post_meta.html`，覆盖 PaperMod 主题默认的元信息渲染逻辑，新增 lastmod 显示行：

```html
{{- if and site.Params.ShowLastMod (not .Lastmod.IsZero) (ne .Lastmod .Date) -}}
  <span title="最后修改: {{ .Lastmod }}">
    修改: {{ .Lastmod | time.Format ":date_long" }}
  </span>
{{- end }}
```

> ⚠️ 前提：GitHub Actions workflow 中 `fetch-depth: 0` 确保拉取完整 git 历史，否则 `.GitInfo` 只能获取最近一次提交时间。

**2. 文章修改记录链接（`editPost`）**

在每篇文章底部添加"📝 修改记录"链接，点击跳转到 GitHub 上该文件的完整 commit 历史，每一次修改的时间、作者、commit message 一目了然：

```toml
# config.toml [params] 下新增
[params.editPost]
  URL = "https://github.com/sikinzen/sikinzen.github.io/commits/master/content"
  Text = "📝 修改记录"
  appendFilePath = true   # 自动拼接当前文件相对路径
```

生成的实际链接示例：`https://github.com/sikinzen/sikinzen.github.io/commits/master/content/posts/HowToBuildBlog.md`

**3. 分类页面与导航栏**

创建 `content/categories/_index.md`，并在 `config.toml` 导航菜单中添加「🏷️ 分类」入口：

```toml
[[menu.main]]
  identifier = "categories"
  name = "🏷️ 分类"
  url = "/categories/"
  weight = 15
```

**4. 评论系统（Giscus）**

基于 GitHub Discussions 的免费评论系统，无需数据库、无需后端，评论者用 GitHub 账号登录即可留言，且**自动区分仓库主人（Owner）与普通访客**。

实现方式：PaperMod 主题的 `comments.html` 是空占位符，通过**模板覆盖**方式注入 Giscus 脚本。

第一步：创建 `layouts/partials/comments.html`：

```html
<!-- Giscus 评论系统 -->
<div class="giscus">
  <script src="https://giscus.app/client.js"
          data-repo="sikinzen/sikinzen.github.io"
          data-repo-id="R_kgDOSxL0IQ"
          data-category="General"
          data-category-id="DIC_kwDOSxL0Ic4C-0wi"
          data-mapping="pathname"
          data-strict="0"
          data-reactions-enabled="1"
          data-emit-metadata="0"
          data-input-position="bottom"
          data-theme="preferred_color_scheme"
          data-lang="zh-CN"
          data-loading="lazy"
          crossorigin="anonymous"
          async>
  </script>
</div>
```

第二步：在 `config.toml` 中启用评论：

```toml
[params]
  comments = true
```

关键参数说明：

| 参数 | 值 | 作用 |
|------|-----|------|
| `data-repo` | `sikinzen/sikinzen.github.io` | 绑定的 GitHub 仓库 |
| `data-mapping` | `pathname` | 每篇文章按 URL 路径映射到独立 Discussion 线程 |
| `data-theme` | `preferred_color_scheme` | 自动跟随系统/博客深浅色模式 |
| `data-lang` | `zh-CN` | 评论区界面语言 |

前置条件（需在 GitHub 上完成）：

1. 仓库 Settings → Features → 勾选 **Discussions**
2. 安装 [giscus GitHub App](https://github.com/apps/giscus) 到该仓库
3. 访问 [giscus.app](https://giscus.app/zh-CN) 获取 `data-category-id`

> 💡 Giscus 自动标记仓库 Owner（sikinzen）为 `👑 Owner`，普通 GitHub 用户仅显示用户名，天然区分主人与访客，无需额外开发。

### 三、内容建设

博客上线后陆续发布了以下文章：

| 文件 | 内容 |
|------|------|
| `grill-me-devs-popularity.md` | Grill Me 深度解析：20个词的AI技能凭什么火遍开发者圈 |
| `HowToUseWorkBuddy1st.md` | 我重度使用 WorkBuddy 后，总结出 6 条真实经验 |
| `HowToUseWorkBuddy2nd.md` | WorkBuddy 从入门到精通——10个上手技巧 |
| `HowToUseVPN.md` | 科学上网配置指南：从服务选购到多端部署 |
| `HowToConnectZentaoAndAI.md` | 禅道接入 AI 实操指南 |
| `HowToConnectGerritAndAI.md` | Gerrit 接入 AI 实操指南 |
| `HowToConnectGiteaAndAI.md` | Gitea 接入 AI 实操指南 |
| `HowToConnectWechatAndAI.md` | 微信本地数据查询接入 AI |
| `HowToConnectWeComAndAI.md` | 企业微信本地数据查询接入 AI |

### 四、WorkBuddy 写博客的积分优化经验

用 WorkBuddy 写博客时，发现单篇文章可能消耗上百积分，分析根因后总结出**三板斧**：

| 策略 | 效果 | 原理 |
|------|------|------|
| **粘贴内容替代链接** | 省 60~80% | 微信链接有反爬机制，AI 需要多轮 WebFetch + 搜索重试才能获取内容，直接粘贴免除所有抓取开销 |
| **新博客开新会话** | 省 30~50% | 上下文会随对话轮次膨胀，旧会话中每次响应都携带大量历史 token |
| **精简指令不加验证** | 省 10~20% | 去掉"检查格式""预览效果"等非必要步骤，直接生成并交付 |

> 💡 最佳实践：开新会话 → 粘贴文章原始内容 → 一句指令"按博客规范整理成 md 文件"→ 完成。整个过程通常控制在 20 积分以内。

---

## 总结

| 环节 | 工具 | 难度 | 预计耗时 |
|------|------|------|---------|
| 安装 Hugo | winget / brew | ⭐ | 5 分钟 |
| 创建站点 + 安装主题 | hugo + git | ⭐ | 10 分钟 |
| 配置 config.toml | 文本编辑器 | ⭐⭐ | 15 分钟 |
| 写第一篇文章 | Markdown | ⭐ | 随意 |
| 创建搜索/归档页（PaperMod 必需） | Markdown + mkdir | ⭐ | **5 分钟（容易漏！）** |
| 配置 GitHub Actions | YAML + GitHub Settings | ⭐⭐⭐ | 30~60 分钟（主要是踩坑） |
| **日常写文章发布** | `hugo new` + `git push` | ⭐ | **3 分钟** |

最花时间的其实是 **GitHub Actions 的配置和调试**，其他环节半小时就能搞定。

但一旦搭好，**以后写文章的体验是非常流畅的**：用 Markdown 写 → `git push` → 自动上线，没有广告、没有审核、文章永远在自己硬盘里。

如果你也在考虑搭建个人博客，**Hugo + GitHub Pages 是目前性价比最高的方案，没有之一**。

欢迎来我的博客逛逛 👉 https://sikinzen.github.io/

---

*本文由 AI 助手（WorkBuddy）辅助整理，但所有踩坑经验均为真实记录。*
