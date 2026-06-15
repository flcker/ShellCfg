# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 仓库概览

这是一个模块化的 zsh 配置仓库（当前分支：`zsh`）。`main` 分支仅用于存放说明文档，`pwsh` 分支存放 PowerShell 7 配置。

## 架构

**入口文件**：`zshrc.zsh` — 由 `~/.zshrc` source。它通过 glob 遍历 `zsh/` 目录下所有 `*.zsh` 文件并逐一 source，加载顺序由文件系统 glob 顺序决定。

**模块目录**（`zsh/`）：每个文件自包含，工具依赖均通过 `command -v` 做可用性判断：
- `plugins.zsh` — 设置 `SHELDON_CONFIG_FILE` 后调用 `eval "$(sheldon source)"`，由 sheldon 统一管理所有插件
- `fzf.zsh` — 初始化 zsh 补全系统、Homebrew 环境变量和 fzf 快捷键（若 `~/.fzf.zsh` 不存在则回退到 `fzf --zsh`）
- `aliases.zsh` — 根据已安装工具条件性定义别名（`lsd`、`bat`、`zoxide`、`lazygit`、`ghostty` 等）
- `functions.zsh` — `color_echo`、`setproxy`/`unsetproxy`（代理地址 `127.0.0.1:7890`）、`ghostty_keybinds`
- `brew.zsh` — `brewswitch` 函数，用于切换 Homebrew 镜像源（清华/USTC/官方）；直接执行时默认使用清华源
- `nodejs.zsh` — `npmswitch` 函数，用于切换 npm 镜像源（官方/淘宝）；直接执行时默认使用淘宝源
- `starship.zsh` — 启动时随机选取 `submodule/starship/starship_*.toml` 中的一个主题；`ssc` 命令切换主题，支持短别名（`c`/`pl`/`r` 等），`ssc -h` 列出所有主题和别名
- `archive.zsh` — 归档两件套（`x`/`a`）：`extract [-o <dir>]` 解压、`archive [-C <dir>]` 打包或压缩；格式由扩展名决定；无参数显示用法
- `nvim.zsh` — 通过 `-u` 参数让 nvim 加载 `submodule/nvim/init.lua`，并将 `vim`/`vi` 别名指向该包装函数
- `cc-tools.zsh` — source `submodule/cc-tools/cc.zsh`，提供 `cc` 命令（模型切换 + CLI 版本管理）

**子模块**（`submodule/`）：
- `submodule/sheldon/` — sheldon 插件配置（`plugins.toml`）；`plugins.zsh` 通过 `SHELDON_CONFIG_FILE` 指向此文件。插件本体由 sheldon 在 `~/.local/share/sheldon/` 中管理（不入仓）
- `submodule/starship/` — starship TOML 配置文件集合（`starship_*.toml`）；由 `starship.zsh` 在启动时随机选取，`ssc` 命令可手动切换
- `submodule/nvim/` — 独立的 neovim 配置（`init.lua` + `lua/` 目录），通过 `-u` 参数加载，不影响系统 nvim 配置
- `submodule/cc-tools/` — Claude Code 工具集（`cc.zsh` 统一入口、`cc-model-switch.zsh` 模型切换、`cc-update.zsh` 版本管理）

## 初始化

```bash
bash ~/.config/zsh/init.sh                    # 安装所有依赖工具（含 sheldon、thefuck）
git submodule update --init --recursive       # 拉取所有 submodule（含 sheldon 配置）
# 在 ~/.zshrc 末尾添加：
source ~/.config/zsh/zshrc.zsh
# 首次启动 shell 时 sheldon 自动 clone 插件
```

## 常用命令

| 命令 | 说明 |
|---|---|
| `ssc [theme]` | 切换 starship 主题；短别名 `c` `pl` `npl` `ppl` `nfs` `pts` `r`；`ssc -h` 列出全部 |
| `brewswitch [tsinghua\|ustc\|official\|list]` | 切换 Homebrew 镜像源 |
| `npmswitch [official\|taobao\|list]` | 切换 npm 镜像源 |
| `setproxy` / `unsetproxy` | 开启/关闭 HTTP/SOCKS5 代理（`127.0.0.1:7890`） |
| `rezsh` | 重新加载 `~/.zshrc` |
| `z <dir>` / `zi <dir>` | 目录跳转 / 交互式跳转（zoxide） |
| `x [-o <dir>] <file> [...]` | 解压，`-o` 指定输出目录 |
| `a <output> [-C <dir>] [file ...]` | 打包或压缩，`-C` 指定源目录；`out.tar.gz` 归档，`out.gz` 压缩单文件 |
| `cc` | 显示当前模型配置（无参数） |
| `cc ds\|deepseek` / `glm` / `claude` / `gpt` | 切换 Claude Code 模型系列 |
| `cc official` | 恢复 Claude 官方默认模型 |
| `cc update [ver]` | 更新 Claude Code CLI；`--rollback` 回退、`--list` 列表、`--clean` 清理 |
| `fuck` | 自动纠正上一条命令（thefuck） |

## 添加/修改插件

编辑 `submodule/sheldon/plugins.toml`，在 `[plugins.zsh-syntax-highlighting]` **之前**添加新插件（syntax-highlighting 须最后加载）。示例：

```toml
[plugins.my-plugin]
github = "author/repo"
```

修改后在 submodule 目录内提交并推送：

```bash
cd submodule/sheldon
git add plugins.toml && git commit -m "..." && git push origin sheldon
cd ../..
git add submodule/sheldon && git commit -m "chore: update sheldon plugins"
```

## 添加新模块

在 `zsh/` 目录下新建 `*.zsh` 文件，下次启动 shell 时 `zshrc.zsh` 会自动 source 它。工具相关代码请用 `command -v <tool> >/dev/null 2>&1` 做可用性判断。
