# 这个文件是 PowerShell 的本仓库配置的入口文件
# 需要在 Microsoft.PowerShell_profile.ps1 中加载这个文件，以便在 PowerShell 中使用这些配置

# ── Encoding & VT ────────────────────────────────────────────────────────────
[Console]::InputEncoding  = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()
if ($PSVersionTable.PSVersion.Major -lt 7) {
    $null = [System.Environment]::SetEnvironmentVariable('TERM', 'xterm-256color', 'Process')
}

# 输出当前目录调试信息，确保正确加载了配置文件
# Write-Host "Loading PowerShell profile"
# Write-Host "Current directory: $PSScriptRoot"

# 需要加载的ps list
$psFiles = @(
    "prompt",       # 这个文件负责 PowerShell 提示符的环境变量和别名配置
    "starship",     # 这个文件负责 starship 提示符的环境变量和别名配置
    "winget_path",  # 须在 modules 之前加载，PSFzf 等模块依赖 shims 目录已注入 PATH
    "modules",
    "aliases_and_functions",
    "nvim",         # 这个文件负责 Neovim 的环境变量和别名配置
    "coreutils",
    "config",
    "zed",          # 这个文件负责 zed 编辑器的环境变量和别名配置
    "cc-tools"      # Claude Code 工具集（模型切换、更新等）
)

# 循环加载每个 ps 文件
foreach ($psFile in $psFiles) {
    $filePath = Join-Path $PSScriptRoot "sh\$psFile.ps1"
    if (Test-Path $filePath) {
        . $filePath
        # Write-Host "Loaded $psFile" -ForegroundColor Green
    } else {
        Write-Host "Warning: $psFile not found at $filePath" -ForegroundColor Yellow
    }
}
