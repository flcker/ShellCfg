################################################################################
# functions and aliases

# refresh profile without restart terminal
function global:repwsh {
    $scriptBlock = [ScriptBlock]::Create((Get-Content -Raw $PROFILE))
    $ExecutionContext.InvokeCommand.InvokeScript($false, $scriptBlock, $null, $null)
}


# refresh user & system PATH (and all env vars) from registry without restarting session
function global:Update-Env {
    $machinePath = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath    = [System.Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path    = ($machinePath, $userPath | Where-Object { $_ }) -join ';'
    if (Get-Command Import-WingetPath -ErrorAction SilentlyContinue) { Import-WingetPath }

    foreach ($target in 'Machine', 'User') {
        [System.Environment]::GetEnvironmentVariables($target).GetEnumerator() |
            Where-Object  { $_.Key -ine 'Path' } |
            ForEach-Object { [System.Environment]::SetEnvironmentVariable($_.Key, $_.Value, 'Process') }
    }

    Write-Host "Environment refreshed." -ForegroundColor Green
}
Set-Alias -Name updateenv -Value Update-Env -Scope Global
Set-Alias -Name upenv -Value Update-Env -Scope Global
Set-Alias -Name reenv -Value Update-Env -Scope Global


# http proxy
function global:set_proxy_fun {
    $env:HTTP_PROXY = "http://127.0.0.1:7890"
    $env:HTTPS_PROXY = "http://127.0.0.1:7890"
    # $env:ALL_PROXY = "socks5://127.0.0.1:7890"
}
Set-Alias -Name proxyon -Value set_proxy_fun -Scope Global

function global:unset_proxy_fun {
    Remove-Item Env:HTTP_PROXY -ErrorAction SilentlyContinue
    Remove-Item Env:HTTPS_PROXY -ErrorAction SilentlyContinue
    Remove-Item Env:ALL_PROXY -ErrorAction SilentlyContinue
}
Set-Alias -Name proxyoff -Value unset_proxy_fun -Scope Global


# Batch alias registration helper for direct command names.
function global:Resolve-AliasCommandTarget {
    param(
        [Parameter(Mandatory = $true)]
        [object]$CommandTarget
    )

    if ($CommandTarget -is [string] -or $CommandTarget -is [scriptblock]) {
        return $CommandTarget
    }

    if ($CommandTarget -is [System.Management.Automation.CommandInfo]) {
        if ($CommandTarget.Source) { return [string]$CommandTarget.Source }
        return [string]$CommandTarget.Name
    }

    if ($CommandTarget.PSObject.Properties.Match('Source').Count -gt 0 -and $CommandTarget.Source) {
        return [string]$CommandTarget.Source
    }

    if ($CommandTarget.PSObject.Properties.Match('FullName').Count -gt 0 -and $CommandTarget.FullName) {
        return [string]$CommandTarget.FullName
    }

    return [string]$CommandTarget
}

function global:Set-AliasBatch {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$AliasMap,
        [System.Management.Automation.ScopedItemOptions]$Option = [System.Management.Automation.ScopedItemOptions]::AllScope
    )

    foreach ($name in $AliasMap.Keys) {
        $spec = $AliasMap[$name]
        $proxyFunctionName = "__alias_$name"

        if ($null -eq $spec) {
            continue
        }

        if ($spec -is [string]) {
            if (Test-Path "Function:Global:$proxyFunctionName") {
                Remove-Item "Function:Global:$proxyFunctionName" -Force
            }
            Set-Alias -Name $name -Value $spec -Option $Option -Scope Global -Force
            continue
        }

        $items = @($spec)
        if ($items.Count -lt 1) { continue }
        if ($null -eq $items[0]) { continue }

        $commandName = Resolve-AliasCommandTarget -CommandTarget $items[0]
        if ([string]::IsNullOrWhiteSpace([string]$commandName)) { continue }
        [object[]]$fixedArgs = if ($items.Count -gt 1) { @($items[1..($items.Count - 1)]) } else { @() }

        # Copy values per alias so closures do not share loop variables.
        $cmd = $commandName
        [object[]]$presetArgs = @($fixedArgs)

        $proxy = {
            param([Parameter(ValueFromRemainingArguments = $true)]$RemainingArgs)
            & $cmd @presetArgs @RemainingArgs
        }.GetNewClosure()

        Set-Item -Path "Function:Global:$proxyFunctionName" -Value $proxy -Force
        Set-Alias -Name $name -Value $proxyFunctionName -Option $Option -Scope Global -Force
    }
}


# git aliases — 已迁移至 submodule/git/config (git native aliases)

# extension tools aliases
# 同样先检查相关工具是否存在，避免设置无效别名。
$toolAliasMap = @(
    @{ Command = 'lsd.exe'   ;  Aliases = @{ ls = @('lsd.exe'); ll = @('lsd.exe', '-alF'); la = @('lsd.exe', '-a'); lr = @('lsd.exe', '-R') } },
    @{ Command = 'bat.exe'   ;  Aliases = @{ cat  = 'bat.exe'   } },
    @{ Command = 'pstop'     ;  Aliases = @{ htop = 'pstop'     } },
    @{ Command = 'zoxide'    ;  Aliases = @{ zo   = 'zoxide'    } },
    @{ Command = 'lazygit'   ;  Aliases = @{ lg   = 'lazygit'   } },
    @{ Command = 'btop4win'  ;  Aliases = @{ btop = 'btop4win'  } },
    @{ Command = 'rg.exe'    ;  Aliases = @{ rg   = @('rg.exe', '--color=auto') } }
)

foreach ($item in $toolAliasMap)
{
    if (Get-Command $item.Command -ErrorAction SilentlyContinue)
    {
        foreach ($aliasName in $item.Aliases.Keys) {
            if (Get-Alias $aliasName -ErrorAction SilentlyContinue) {
                Remove-Item "Alias:$aliasName" -ErrorAction SilentlyContinue
            }
        }
        Set-AliasBatch $item.Aliases
    }
}


# other aliases
Set-AliasBatch @{
    clcb  = @('Set-Clipboard', '')
    '~'   = 'Set-Location'
    # rm/mv/cp/mkdir/rmdir/touch — 已由 coreutils.ps1 按需覆盖
    find  = 'Get-ChildItem'
}
