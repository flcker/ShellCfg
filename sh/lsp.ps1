# lsp 配置
# LSP 服务器安装与配置管理（submodule/lsp）
# 提供全局 lsp 命令：lsp install / configure / status / help

$profileRoot = Split-Path $PSScriptRoot -Parent
$lspEntry = "$profileRoot\submodule\lsp\lsp.ps1"
if (Test-Path $lspEntry) {
    & { . $lspEntry }
}
