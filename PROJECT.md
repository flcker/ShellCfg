# PowerShell Config

Windows PowerShell 7+ 个人终端配置，模块化管理，通过 git submodule 维护跨平台工具配置（统一存放于 [ShellCfgSubmodule](https://github.com/flcker/ShellCfgSubmodule)，各工具对应独立分支）。

## 结构

```
pwsh/
├── pwsh_profile.ps1              # 主入口，按序加载 sh/ 下所有子文件
├── init_profile_dependencies.ps1 # 一键安装终端配置依赖（PS 模块 + 终端工具）
├── devtools_install.ps1          # 一键安装开发工具（交互式选择或参数指定）
├── update-submodules.ps1         # 更新所有 submodule 到各自配置分支最新
├── sh/
│   ├── prompt.ps1                # 自定义提示符 & 窗口标题
│   ├── starship.ps1              # starship 主题随机加载 & 切换
│   ├── modules.ps1               # PSReadLine / posh-git / PSFzf
│   ├── aliases_and_functions.ps1 # 别名与工具函数
│   ├── coreutils.ps1             # coreutils 命令查询与冲突 Alias 覆盖
│   ├── nvim.ps1                  # Neovim 别名 & submodule 配置加载
│   └── config.ps1                # zoxide 初始化
└── submodule/
    ├── starship/                 # starship 主题 toml（5 套）← ShellCfgSubmodule@starship
    ├── nvim/                     # Neovim 配置（init.lua 优先）← ShellCfgSubmodule@nvim
    └── git/                      # git alias & color 配置（config）← ShellCfgSubmodule@git
```

## 关键约定

- **所有函数必须用 `function global:Name` 定义**，`Set-Alias` 必须带 `-Scope Global`，否则 `repwsh` 热更新无效。
- `$PSScriptRoot` 用于定位 submodule 路径，`sh/` 内的脚本通过 `Split-Path $PSScriptRoot -Parent` 拿到项目根目录。
- 帮助标志统一用 `-h`（`[Alias("h")]`），遵循 PowerShell 单破折号惯例，不使用 `--help`。
- `ValidateSet` 在函数体执行前运行，无法拦截非法值来显示帮助，需去掉改为手动校验。

## 常用函数 & 别名

| 命令 | 说明 |
|------|------|
| `repwsh` | 热更新：重新加载 `$PROFILE` |
| `refreshenv` | 从注册表刷新用户 & 系统环境变量（含 PATH），无需重启会话 |
| `ssc [-h] [Config]` | 切换 starship 主题（custom/powerline/plaintextsymbols/nerdfontsymbols/pastelpowerline/default，支持缩写） |
| `setproxy` / `unsetproxy` | 开关 HTTP 代理（127.0.0.1:7890） |
| `vim` / `vi` / `nvim` | 调用 Neovim，自动加载 submodule/nvim 配置 |
| `dir` / `cp` / `mv` / `rm` / `mkdir` / `rmdir` / `touch` / `pwd` / `echo` | 检测到对应 coreutils `*.exe` 时，优先绑定（`ls` 由 lsd 接管，`cat` 由 bat 接管） |
| `Get-CoreutilsCommands` / `gcu` / `gcuu` | `gcu` 按分类查看 coreutils 命令，支持 `-a` / `-c text` 这类短参数，`gcu <命令>` 查看 usage |
| `ll` / `la` / `lr` | lsd 扩展列表命令 |
| `lg` | lazygit |
| `git st/co/sw/br/ci/wt/lg…` | git native aliases（见 submodule/git/config） |

## 依赖

### 终端配置依赖（init_profile_dependencies.ps1）

PowerShell 模块：`PSReadLine`、`posh-git`、`PSFzf`

外部工具（winget）：`starship`、`bat`、`lsd`、`nvim`、`zoxide`、`pstop`、`lazygit`、`btop4win`、`tlrc`、`uutils.coreutils`

```powershell
pwsh -File .\init_profile_dependencies.ps1        # 当前用户
pwsh -File .\init_profile_dependencies.ps1 -s a   # 所有用户（需管理员）
```

### 开发工具（devtools_install.ps1）

可选安装：`PowerShell 7`、`Git`、`VSCode`、`NanaZip`、`Rust`、`Python 3`、`Node.js LTS`、`Go`、`Java`、`CMake`、`WinDbg`

```powershell
pwsh -File .\devtools_install.ps1          # 交互式菜单
pwsh -File .\devtools_install.ps1 -All     # 全部安装
pwsh -File .\devtools_install.ps1 -Tools git,vscode,rust  # 指定安装
```

从 GitHub 直接运行（无需克隆）：
```powershell
irm https://raw.githubusercontent.com/flcker/Shell_Config/pwsh/devtools_install.ps1 | iex
```

## 接入方式

在 `$PROFILE`（`~/Documents/PowerShell/Microsoft.PowerShell_profile.ps1`）中添加：

```powershell
. "$HOME/.config/pwsh/pwsh_profile.ps1"
```

首次克隆后初始化 submodule：

```powershell
git submodule update --init --recursive
```

更新所有 submodule 到各分支最新：

```powershell
git submodule update --remote --merge
```

新增工具配置：在 [ShellCfgSubmodule](https://github.com/flcker/ShellCfgSubmodule) 创建对应分支，再执行：

```powershell
git submodule add -b <branch> git@github.com:flcker/ShellCfgSubmodule.git submodule/<name>
```
