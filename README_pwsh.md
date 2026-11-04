# PowerShell 配置使用说明

---

## PowerShell 配置说明

1. 本仓库支持模块化拆分，所有功能性配置已拆分到 sh 文件夹下的子文件：
   - prompt.ps1：自定义提示符与窗口标题
   - starship.ps1：starship 主题配置与切换（动态检测 starship/starshipauto 模块）
   - winget_path.ps1：winget shim 管理，将 winget 安装路径通过 shims 目录集中管理，解决 PATH 2047 字节溢出（须在 modules 之前加载，PSFzf 等模块依赖 shims 已注入 PATH）
   - modules.ps1：模块导入与 PSReadLine 设置
   - aliases_and_functions.ps1：常用别名与函数
   - coreutils.ps1：检测 uutils coreutils 可执行文件，提供命令查询函数，并覆盖冲突的 PowerShell Alias
   - config.ps1：zoxide 等工具初始化配置
   - nvim.ps1：Neovim 别名与配置加载（自动使用 submodule/nvim 下的 init.lua/init.vim）
   - zed.ps1：Zed 编辑器窗口行为优化（目录新窗口打开，已打开目录复用窗口）

2. 主配置入口文件 pwsh_profile.ps1 只负责加载上述子文件。

3. 初始化依赖脚本 init_profile_dependencies.ps1 支持自动安装所有依赖，并分类输出安装结果与版本。

4. starship 配置文件路径已适配多层目录结构，支持 profile/sh 子文件夹调用。

5. 推荐使用 PowerShell 7+，并确保 winget 可用。

---

## 快速使用

1. 在系统 profile 中加载本仓库入口文件（仅需配置一次）：

   在 `$PROFILE` 对应的文件中添加以下内容（路径替换为实际克隆位置）：

   ```powershell
   . "C:\Users\<用户名>\.config\pwsh\pwsh_profile.ps1"
   ```

   **不同宿主对应的 profile 文件：**

   | 宿主 | profile 文件 |
   |------|-------------|
   | PowerShell 终端 | `Microsoft.PowerShell_profile.ps1` |
   | VSCode 集成终端 | `Microsoft.VSCode_profile.ps1` |

   两个文件通常位于 `C:\Users\<用户名>\Documents\PowerShell\` 下，可以添加上述 dot-source 行才能生效。
   当`Microsoft.VSCode_profile.ps1` 不存在时, VSCode 集成终端会使用 `Microsoft.PowerShell_profile.ps1`,
   如果不需要区别对待，可以只留 `Microsoft.PowerShell_profile.ps1`。

2. 运行 init_profile_dependencies.ps1 自动安装所有依赖：

   ```powershell
   pwsh -File .\init_profile_dependencies.ps1
   ```

   支持以下参数：

   | 参数 | 说明 |
   |------|------|
   | `-ModuleScope CurrentUser`（默认） | 为当前用户安装 PowerShell 模块 |
   | `-ModuleScope AllUsers` 或 `-s a` | 为所有用户安装（需管理员权限） |
   | `-Help` 或 `-h` | 打印帮助信息 |

   示例：
   ```powershell
   # 为当前用户安装（默认）
   pwsh -File .\init_profile_dependencies.ps1

   # 为所有用户安装（需管理员）
   pwsh -File .\init_profile_dependencies.ps1 -s a
   ```

3. 重新启动 PowerShell 即可自动加载所有配置。

4. GitHub Git 代理：

   ```powershell
   gitproxyon   # 为 github.com 启用 Git HTTP/HTTPS/SSH 代理
   gitproxyoff  # 移除 ShellCfg 管理的 GitHub 代理配置
   ```

   HTTP/HTTPS 使用 URL 级 Git 配置，存放于 ShellCfg 管理的 `~/.gitconfig.d/shellcfg-github-proxy.gitconfig`，不影响其他 Git 域名；SSH 使用 Git for Windows 自带的 `connect.exe`，经 `ssh.github.com:443` 连接，并写入 `~/.ssh/config.d/shellcfg-github-proxy.conf`。首次启用时会在 `~/.ssh/config` 顶部加入对应的 `Include`；关闭后保留这条无副作用的 SSH Include，供后续重新启用。

   四个代理命令调用后都会以多行中文格式输出状态、作用范围和持久化信息；失败时逐条列出原因。`proxyon` / `proxyoff` 只影响当前 PowerShell 会话及之后启动的子进程；`gitproxyon` / `gitproxyoff` 影响当前 Windows 用户，配置跨终端和重启持久化且仅匹配 GitHub。`gitproxyon` 不会覆盖已有的同名 Git 配置或非 ShellCfg 管理的配置文件。若已执行 `proxyon`，其他域名仍可能通过环境变量走代理。

5. starship 主题切换使用 `ssc` 命令，支持前缀匹配、类型筛选、序号选择、锁定配置：

   ```powershell
   ssc pl_round           # 前缀匹配切换
   ssc -t a               # 列出 starshipauto 配置（带序号）
   ssc -t a 3             # 按序号切换
   ssc -t s               # 列出 starship 静态配置（带序号，别名共享序号）
   ssc --lock             # 锁定当前配置
   ssc --lock pl_round    # 锁定指定配置
   ssc --unlock           # 解锁，恢复随机
   ssc --rebuild          # 重新生成 starshipauto 配置
   ```

   启动行为：有锁定则使用锁定配置，否则随机选择。

   自定义主题：
   - 静态：编辑 `submodule/starship/` 下的 toml 文件
   - 动态：编辑 `submodule/starshipauto/data/` 下的数据文件，然后 `ssc --rebuild`

---

## Submodule 说明

工具配置统一存放于 [ShellCfgSubmodule](https://github.com/flcker/ShellCfgSubmodule)，各工具对应独立分支，通过 git submodule 引入到 `submodule/` 目录下：

| Submodule | 路径 | 分支 | 说明 |
|-----------|------|------|------|
| starship | `submodule/starship/` | `starship` | starship 静态主题配置文件（toml） |
| starshipauto | `submodule/starshipauto/` | `starshipauto` | starship 动态配置生成器（layout × palette 组合生成） |
| nvim | `submodule/nvim/` | `nvim` | Neovim 配置，包含 init.lua 或 init.vim |
| git | `submodule/git/` | `git` | git alias & color 配置，通过 `[include]` 加载到 `~/.gitconfig` |

**初始化 submodule（首次克隆后执行）：**

```bash
git submodule update --init --recursive
```

**更新所有 submodule 到各分支最新：**

```powershell
.\update-submodules.ps1           # 更新并显示待提交的父仓指针
.\update-submodules.ps1 -Commit   # 更新并自动提交父仓指针
```

**新增工具配置：**

1. 在 ShellCfgSubmodule 创建对应分支（建议使用 `--orphan` 保持历史独立）
2. 在本仓库执行：

```bash
git submodule add -b <branch> git@github.com:flcker/ShellCfgSubmodule.git submodule/<name>
```

---

## 目录结构示例

```
pwsh/
├── pwsh_profile.ps1              # 主入口，dot-source 加载所有子文件
├── init_profile_dependencies.ps1 # 一键安装所有依赖
├── sh/
│   ├── prompt.ps1                # 自定义提示符与窗口标题
│   ├── starship.ps1              # starship 主题配置与切换
│   ├── winget_path.ps1           # winget shim 管理（须在 modules 之前加载）
│   ├── modules.ps1               # 模块导入与 PSReadLine 设置
│   ├── aliases_and_functions.ps1 # 常用别名与函数
│   ├── coreutils.ps1             # coreutils 存在时覆盖冲突 Alias
│   ├── config.ps1                # zoxide 等工具初始化
│   ├── nvim.ps1                  # Neovim 别名与配置加载
│   └── zed.ps1                   # Zed 编辑器窗口行为优化
└── submodule/
    ├── starship/                     # 静态 starship 主题配置
    │   ├── starship_custom.toml
    │   ├── starship_powerline.toml
    │   └── ...
    ├── starshipauto/                 # 动态 starship 配置生成器
    │   ├── data/                     # 数据层（layouts, palettes, modules, shared）
    │   ├── engines/                  # 切换引擎（pwsh, sh）
    │   ├── generate.py              # Python 生成器
    │   └── generated/               # 生成输出（.gitignore）
    ├── nvim/
    │   └── init.lua                  # Neovim 配置入口（优先加载，也支持 init.vim）
    └── git/
        └── config                    # git alias & color，~/.gitconfig 通过 [include] 加载
```

---

## Winget Shim 管理（winget_path.ps1）

通过 shims 目录（`%LOCALAPPDATA%\winget_shims`）集中管理 winget 安装的 CLI 工具，解决 User PATH 的 2047 字节溢出问题。

### 常用命令

| 命令 | 说明 |
|------|------|
| `syncwp` | 扫描 User PATH，迁移 winget 路径并构建 shims |
| `syncwp -WhatIf` | 预览迁移，不做实际修改 |
| `syncws` | 扫描所有 winget 包，创建/更新 shims |
| `wgs` | 列出所有 winget 管理的工具 |
| `wgs <command>` | 查看指定工具的帮助（--help） |

### 工作原理

1. `WINGET_SHIM_PATH` 用户级环境变量，仅存储 shims 目录路径（约 39 字节）
2. User PATH 引用 `%WINGET_SHIM_PATH%`（REG_EXPAND_SZ），Windows 启动时自动展开
3. 纯 exe 工具生成 `.cmd` shim，有 DLL 依赖的工具创建目录 junction
4. Profile 加载时 `Import-WingetShimPath` 注入实际包路径到会话 PATH（保证 .exe 直接可用）

### 查看当前状态

```powershell
wgs                                                                   # 列出所有工具
$env:WINGET_SHIM_PATH                                                 # shims 目录路径
Get-Content "$env:LOCALAPPDATA\winget_shims\.manifest.json" | ConvertFrom-Json  # 完整清单
```

---

## Zed 编辑器优化（zed.ps1）

优化 Zed 编辑器在 Windows 上的窗口行为：

- 打开**目录**时：若该目录已在 Zed 中打开，则复用现有窗口；否则以 `--new` 打开新窗口
- 打开**文件**时：直接在现有窗口中打开

---

## 常见问题

### 启动时提示模块未找到（如 posh-git、PSFzf）

**原因**：modules.ps1 在导入模块前会检查模块是否已安装，若未安装则会显示警告并跳过，不影响其他功能正常加载。但相关功能（如 git 状态提示、fzf 集成）将不可用。

**解决方法**：运行依赖安装脚本：

```powershell
pwsh -File path\to\init_profile_dependencies.ps1
```

安装完成后重启 PowerShell 即可。

### 安装了 coreutils，但 `ls` / `cat` / `cp` 仍然是 PowerShell 命令

**原因**：PowerShell 的同名 Alias 会优先于外部命令。`coreutils.ps1` 会优先检查 `PATH`，找不到时再回退到 winget 的 `uutils.coreutils` 安装目录，然后覆盖这些冲突 Alias。

**当前行为**：当 `uutils.coreutils` 已安装且命令在 `PATH` 中时，`dir`、`cp`、`mv`、`rm`、`mkdir`、`rmdir`、`touch`、`pwd`、`echo` 会优先调用对应的 coreutils 可执行文件；`ls` 由 `lsd` 接管，`cat` 由 `bat` 接管，`ll` / `la` / `lr` 仍然保持为 `lsd`。

可用以下命令查看当前 profile 识别到的 coreutils 命令与 usage：

```powershell
gcu                    # 按分类查看支持的 coreutils 命令
gcu -a                 # 只看当前可用命令
gcu -c text
gcu -c fs
gcu cp                 # 查看 cp 的 usage / help
gcuu cp                # 同上
```

分类短代码：

- `fs` = 文件与路径
- `text` = 文本与输出
- `hash` = 编码与校验
- `sys` = 系统与环境
- `exec` = 执行与控制
- `data` = 数据与计算

### 提示符显示乱码（如 `鉂?` 或 `([char]0x1B)[0m`）

**原因**：终端 console 编码未设为 UTF-8，导致 Unicode 字符（如 `❯`）显示为乱码，ANSI escape 序列被字面输出。

**解决方法**：`pwsh_profile.ps1` 已在顶部设置 UTF-8 编码：

```powershell
[Console]::InputEncoding  = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()
```

同时 `starship.ps1` 定义了 `Invoke-Starship-TransientFunction` 让 Starship 引擎渲染 transient prompt，避免使用硬编码 ANSI 序列。

若仍有问题，检查终端字体是否为 Nerd Font（推荐 Hack Nerd Font、JetBrainsMono Nerd Font）。

### $PROFILE 路径在哪里？

在 PowerShell 中执行以下命令查看：

```powershell
$PROFILE
```

通常为 `C:\Users\<用户名>\Documents\PowerShell\Microsoft.PowerShell_profile.ps1`。

VSCode 集成终端使用的是同目录下的 `Microsoft.VSCode_profile.ps1`，可以单独添加 dot-source 行；若不存在，则会共用`Microsoft.PowerShell_profile.ps1`。

---

## 开发工具安装（devtools_install.ps1）

`devtools_install.ps1` 用于一键安装 Windows 常用开发工具，支持交互式选择或参数指定。

### 直接从 GitHub 下载运行（无需克隆仓库）

以管理员身份打开 PowerShell，执行以下命令：

```powershell
# 交互式菜单选择安装
irm https://raw.githubusercontent.com/flcker/Shell_Config/pwsh/devtools_install.ps1 | iex
```

> `irm` 是 `Invoke-RestMethod` 的别名，`iex` 是 `Invoke-Expression` 的别名。

若需传递参数（`iex` 不支持直接传参），改用临时文件方式：

```powershell
# 全部安装
$tmp = New-TemporaryFile | Rename-Item -NewName { $_.Name -replace '\.tmp$', '.ps1' } -PassThru
irm https://raw.githubusercontent.com/flcker/Shell_Config/pwsh/devtools_install.ps1 | Set-Content $tmp
pwsh -File $tmp -All
Remove-Item $tmp

# 指定工具安装
pwsh -File $tmp -Tools git,vscode,nanazip
```

### 参数说明

| 参数 | 说明 |
|------|------|
| 无参数 | 显示交互式选择菜单（默认勾选常用工具） |
| `-All` | 安装全部工具 |
| `-Tools git,vscode,...` | 只安装指定工具（逗号分隔，不区分大小写） |
| `-Help` 或 `-h` | 打印帮助信息 |

### 可安装工具

| Key | 工具 | 默认选中 |
|-----|------|----------|
| `pwsh` | PowerShell 7 | 是 |
| `git` | Git | 是 |
| `vscode` | VSCode | 是 |
| `nanazip` | NanaZip | 是 |
| `rust` | Rust (rustup) | 是 |
| `python` | Python 3（自动获取最新版） | 是 |
| `node` | Node.js LTS | 否 |
| `go` | Go | 否 |
| `java` | Java (Temurin 21) | 否 |
| `cmake` | CMake | 是 |
| `windbg` | WinDbg | 是 |

---

如有问题或建议，欢迎 issue 或 PR。
