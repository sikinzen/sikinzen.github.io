---
title: "博客附件功能演示"
date: 2026-06-14T00:40:00+08:00
draft: true
description: "演示 Page Bundle 附件功能的文章，上线后删除"
categories: ["技术"]
tags: ["Hugo", "博客"]
keywords: ["Hugo附件", "Page Bundle"]
---

## 这是什么

这是一篇演示文章，用于验证 Hugo Page Bundle 附件功能是否正常工作。

## 附件引用方式

### 方式一：直接 Markdown 链接

可以在正文中直接引用同目录下的附件：

- [下载示例 PDF](sample.pdf)
- [查看示例图片](diagram.png)

### 方式二：自动附件列表

在文章末尾使用 `{{</* attachments */>}}` 短代码，自动列出所有附件。

{{< attachments >}}
