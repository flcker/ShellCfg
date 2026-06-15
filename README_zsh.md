# zsh 配置使用说明

> 分支：`zsh`

---

## 快速开始

```bash
# 1. 克隆仓库并切换到 zsh 分支
git clone <repo> ~/.config/zsh
cd ~/.config/zsh && git checkout zsh

# 2. 拉取所有子模块
git submodule update --init --recursive

# 3. 安装依赖工具
bash ~/.config/zsh/init.sh

# 4. 在 ~/.zshrc 末尾添加
source ~/.config/zsh/zshrc.zsh

# 5. 重启 shell，sheldon 自动 clone 插件
```

---

## 模块说明

所有功能拆分在 `zsh/` 目录下，`zshrc.zsh` 通过 glob 自动 source 全部 `*.zsh` 文件。

| 文件 | 功能 |
|---|---|
| `plugins.zsh` | sheldon 插件管理入口（autosuggestions、syntax-highlighting、fzf-tab、zoxide、thefuck） |
| `fzf.zsh` | compinit 初始化、Homebrew 环境变量、fzf 快捷键 |
| `starship.zsh` | 启动时随机选取主题；`ssc` 命令切换主题 |
| `aliases.zsh` | 条件性别名（lsd、bat、zoxide、lazygit、ghostty 等） |
| `functions.zsh` | `proxyon`/`proxyoff`、`color_echo`、`ghostty_keybinds` |
| `brew.zsh` | `brewswitch` 切换 Homebrew 镜像源 |
| `nodejs.zsh` | `npmswitch` 切换 npm 镜像源 |
| `archive.zsh` | `x` 解压 / `a` 打包压缩（格式由扩展名决定） |
| `nvim.zsh` | nvim 通过 `-u` 加载 submodule 配置，`vim`/`vi` 别名指向包装函数 |

---

## 插件管理（sheldon）

插件配置位于 `submodule/sheldon/plugins.toml`，随 git 同步，插件本体安装在 `~/.local/share/sheldon/`（不入仓）。

**添加插件**：编辑 `plugins.toml`，新条目放在 `[plugins.zsh-syntax-highlighting]` 之前，然后：

```bash
cd submodule/sheldon
git add plugins.toml && git commit -m "..." && git push origin sheldon
cd ../..
git add submodule/sheldon && git commit -m "chore: update sheldon plugins"
```

---

## 常用命令

| 命令 | 说明 |
|---|---|
| `ssc [theme]` | 切换 starship 主题；短别名 `c` `pl` `npl` `ppl` `nfs` `pts` `r`；`ssc -h` 列出全部 |
| `brewswitch [tsinghua\|ustc\|official\|list]` | 切换 Homebrew 镜像源 |
| `npmswitch [official\|taobao\|list]` | 切换 npm 镜像源 |
| `proxyon` / `proxyoff` | 开启/关闭 HTTP/SOCKS5 代理（`127.0.0.1:7890`） |
| `rezsh` | 重新加载 `~/.zshrc` |
| `z <dir>` / `zi <dir>` | 目录跳转 / 交互式跳转（zoxide） |
| `x [-o <dir>] <file> [...]` | 解压，`-o` 指定输出目录 |
| `a <output> [-C <dir>] [file ...]` | 打包或压缩，`-C` 指定源目录 |
| `fuck` | 自动纠正上一条命令（thefuck） |

---

## 目录结构

```
~/.config/zsh/
├── zshrc.zsh          # 入口，glob source zsh/*.zsh
├── init.sh            # 依赖安装脚本
├── zsh/
│   ├── plugins.zsh    # sheldon 插件管理
│   ├── fzf.zsh        # fzf 初始化
│   ├── starship.zsh   # starship 主题
│   ├── aliases.zsh    # 命令别名
│   ├── functions.zsh  # 工具函数
│   ├── brew.zsh       # Homebrew 镜像源切换
│   ├── nodejs.zsh     # npm 镜像源切换
│   ├── archive.zsh    # 归档工具（x/a）
│   └── nvim.zsh       # neovim 配置集成
└── submodule/
    ├── sheldon/       # plugins.toml（sheldon 分支）
    ├── starship/      # starship_*.toml 主题文件
    ├── nvim/          # neovim 配置（init.lua）
    └── git/           # git 配置
```

---

## 新机器恢复

```bash
bash ~/.config/zsh/init.sh                  # 安装 sheldon、thefuck 等工具
git submodule update --init --recursive     # 拉取插件配置
zsh                                         # sheldon 自动 clone 插件
```
