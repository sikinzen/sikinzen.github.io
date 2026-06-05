# 温陵布衣博客 — 使用指南

> 本文档帮助你从零开始使用这个博客站点。

---

## 一、环境准备

### 1.1 安装 Hugo Extended（必须）

Hugo 是静态网站生成器，**必须安装 Extended 版本**（用于 SCSS 支持）。

**Windows:**
```bash
# 方式 1：winget（推荐）
winget install Hugo.Hugo.Extended

# 方式 2：Chocolatey
choco install hugo-extended -y

# 方式 3：Scoop
scoop install hugo-extended
```

**macOS:**
```bash
brew install hugo
```

**Linux (Ubuntu/Debian):**
```bash
# 从 GitHub 下载最新版本
wget https://github.com/gohugoio/hugo/releases/download/v0.145.0/hugo_0.145.0_linux-amd64.deb
sudo dpkg -i hugo_0.145.0_linux-amd64.deb
```

验证安装：
```bash
hugo version
# 应输出类似：hugo v0.145.0-xxxxxxx+extended ...
```

### 1.2 安装 Git

如果还没装 Git，去 https://git-scm.com/downloads 下载安装。

---

## 二、初始化仓库

### 2.1 在 GitHub 创建仓库

1. 打开 https://github.com/new
2. **Repository name**: `sikinzen.github.io`（必须是这个名字！）
3. 选择 **Public**
4. **不要勾选** Add a README file
5. 点击 Create repository

### 2.2 初始化本地仓库并推送

```bash
cd wenling-buli-blog

# 初始化 Git
git init

# 添加 PaperMod 主题（作为 submodule）
git submodule add https://github.com/adityatelange/hugo-PaperMod themes/PaperMod

# 关联远程仓库（替换成你的实际路径）
git remote add origin git@github.com:sikinzen/sikinzen.github.io.git

# 首次提交和推送
git add .
git commit -m "init: 温陵布衣博客初始化"
git push -u origin main
```

### 2.3 开启 GitHub Pages

1. 进入仓库 Settings → Pages
2. **Source**: 选择 "GitHub Actions"
3. 保存

之后每次 push 到 main 分支都会自动部署。

---

## 三、日常写作流程

### 3.1 创建新文章

```bash
hugo new posts/我的新文章.md
```

这会在 `content/posts/` 下创建文件，自动填充 front matter。

### 3.2 编辑文章

用任何文本编辑器打开 Markdown 文件编辑：

```markdown
---
title: "文章标题"
date: 2026-06-05
draft: false          # true = 草稿不发布
description: "简短描述"
summary: "首页摘要文字"
categories: ["分类名"]
tags: ["标签1", "标签2"]
cover:
  image: /images/xxx.jpg   # 封面图
---

正文内容写在这里...
```

### 3.3 常用 Markdown 语法示例

#### 标题
```markdown
## 二级标题
### 三级标题
```

#### 代码块
\`\`\`python
def hello():
    print("Hello, 温陵布衣!")
\`\`\`

#### 表格
| 功能 | 快捷键 |
|------|--------|
| 加粗 | Ctrl+B |
| 斜体 | Ctrl+I |

#### 引用
> 这是一段引用文字

#### 图片
![图片说明](/images/photo.jpg)

> 图片放在 `static/images/` 目录下

#### 链接
[GitHub](https://github.com/sikinzen)

### 3.4 本地预览

```bash
hugo server -D
# -D 参数会显示 draft: true 的草稿文章
# 默认访问 http://localhost:1313
```

浏览器打开 http://localhost:1313 即可实时预览。

### 3.5 发布文章

```bash
# 确认无误后
git add .
git commit -m "new post: 文章标题"
git push
# → 等 1-2 分钟，GitHub Actions 自动构建部署完成
# → 访问 https://sikinzen.github.io 即可看到
```

---

## 四、常用命令速查

| 操作 | 命令 |
|------|------|
| 新建文章 | `hugo new posts/name.md` |
| 本地预览 | `hugo server -D` |
| 构建生产包 | `hugo --minify --gc` |
| 清理缓存 | `hugo --cleanDestinationDir` |
| 更新主题 | `git submodule update --rebase --remote` |
| 发布 | `git add . && git commit -m 'msg' && git push` |

---

## 五、定制化指南

### 5.1 修改博客信息

编辑 `config.toml`：

```toml
title = '温陵布衣'           # 博客名称
[params]
  description = "你的描述"    # 副标题/SEO 描述
  author = "sikinzen"         # 作者名
```

### 5.2 修改导航菜单

在 `config.toml` 的 `[menu]` 部分：

```toml
[[menu.main]]
  identifier = "posts"
  name = "文章"
  url = "/posts/"
  weight = 10
```

### 5.3 修改个人信息（首页）

在 `config.toml` 的 `[params.homeInfoParams]`：

```toml
[params.homeInfoParams]
  Title = "你好 👋"
  Content = "你的介绍..."
```

### 5.4 添加社交链接

```toml
[[params.socialIcons]]
  name = "twitter"
  url = "https://twitter.com/yourname"
```

支持的图标名：github, twitter, email, facebook, linkedin, telegram, weibo, zhihu, stackoverflow, etc.

### 5.5 修改颜色/样式

PaperMod 支持通过自定义 CSS 覆盖：

创建 `static/css/custom.css`：
```css
/* 自定义样式 */
body {
  font-family: "LXGW WenKai", sans-serif;  /* 霞鹜文楷字体 */
}
```

然后在 `config.toml` 添加引用（PaperMod 支持 customCSS）：

```toml
[params]
  [[params.customCSS]]
    href = "/css/custom.css"
```

---

## 六、迁移旧文章（从 CSDN）

### 方法一：手动迁移（推荐）

1. 在 CSDN 编辑器中切换到"Markdown 源码模式"
2. 复制全部内容
3. 用 `hugo new posts/title.md` 创建新文章
4. 粘贴内容并调整格式
5. 手动下载图片到 `static/images/`
6. 修改图片路径为 `/images/xxx.jpg`

### 方法二：工具辅助

可以用工具批量转换 CSDN HTML → Markdown：

```bash
# 使用 csdn-md-converter（如有需要可搜索相关开源项目）
pip install csdn-md-converter  # 示例
```

---

## 七、常见问题

### Q: push 之后多久上线？

A: 通常 1-3 分钟。可以在仓库的 Actions 标签页查看构建状态。

### Q: 如何写草稿（不发布）？

A: 在 front matter 中设置 `draft: true`。草稿只在 `hugo server -D` 时显示。

### Q: 如何添加自定义页面？

A: 在 `content/` 下直接创建 `.md` 文件即可，如 `content/links.md` 会生成 `/links/` 页面。

### Q: 想换主题怎么办？

A: 只需更换 theme 配置和 submodule。所有内容文件不受影响——这就是 Hugo 的优势。

### Q: 图片怎么管理？

A: 所有图片放在 `static/images/` 目录下，在 Markdown 中引用 `/images/图片名.jpg`。
建议按年份或文章分目录：`static/images/2026/hello.jpg`。

### Q: 备忘录/笔记类内容放哪里？

A: 不适合放博客的文章可以另外建一个 private repo 或用其他工具（语雀、Obsidian）。

---

## 八、推荐写作工具

| 工具 | 特点 |
|------|------|
| VS Code + Markdown Preview | 免费、插件丰富、支持图片粘贴 |
| Typora | 所见即所得、付费但好用 |
| Obsidian | 双链笔记、知识图谱 |
| 直接记事本 | 最简单、够用就行 |

---

*最后更新：2026-06-04*
