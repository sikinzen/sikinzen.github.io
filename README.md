# 温陵布衣

> 闽南一隅，以技术为业的一介普通人

**Hugo + PaperMod + GitHub Pages** 技术博客

## 🚀 快速开始

### 本地预览（需要安装 Hugo）

```bash
# 安装 Hugo Extended
# Windows: winget install Hugo.Hugo.Extended
# Mac:   brew install hugo
# Linux: sudo apt install hugo

# 克隆仓库
git clone https://github.com/sikinzen/sikinzen.github.io.git
cd sikinzen.github.io

# 添加主题（git submodule）
git submodule add https://github.com/adityatelange/hugo-PaperMod themes/PaperMod

# 本地预览
hugo server -D
```

### 写新文章

```bash
hugo new posts/my-article.md
# 编辑 content/posts/my-article.md
```

### 发布

```bash
git add . && git commit -m "new post: xxx" && git push
# → GitHub Actions 自动构建部署
```

## 📁 目录结构

```
├── config.toml          # 站点配置
├── content/
│   ├── posts/           # 文章存放目录
│   └── about.md         # 关于页面
├── static/              # 静态资源（图片等）
├── themes/
│   └── PaperMod/        # 主题（git submodule）
├── .github/workflows/
│   └── deploy.yml       # 自动部署配置
└── archetypes/
    └── default.md       # 新文章模板
```

## 🛠 技术栈

- [Hugo](https://gohugo.io/) — 静态站点生成器
- [PaperMod](https://github.com/adityatelange/hugo-PaperMod) — 主题
- [GitHub Pages](https://pages.github.com/) — 托管
- [GitHub Actions](https://github.com/features/actions) — CI/CD

## 📄 License

[CC BY-NC-SA 4.0](LICENSE)
