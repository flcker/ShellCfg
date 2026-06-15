$profileRoot = Split-Path $PSScriptRoot -Parent
$ccEntry = "$profileRoot\submodule\cc-tools\cc.ps1"
if (Test-Path $ccEntry) {
    . $ccEntry
}
