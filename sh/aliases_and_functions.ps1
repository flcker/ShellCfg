################################################################################
# functions and aliases

# refresh profile without restart terminal
function global:repwsh {
    # 使用 $true（local scope）确保新函数定义覆盖全局作用域中的旧版本
    # 否则 InvokeScript($false) 会在子作用域中定义函数，被全局旧函数遮蔽
    $scriptBlock = [ScriptBlock]::Create((Get-Content -Raw $PROFILE))
    $ExecutionContext.InvokeCommand.InvokeScript($true, $scriptBlock, $null, $null)
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


function global:Write-ProxyCommandResult {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,

        [Parameter(Mandatory = $true)]
        [bool]$Success,

        [string[]]$Messages = @(),
        [string[]]$Details = @()
    )

    $status = if ($Success) { '成功' } else { '失败' }
    $statusColor = if ($Success) { 'Green' } else { 'Red' }

    Write-Host ''
    Write-Host "[$Command] $status" -ForegroundColor $statusColor

    if ($Messages.Count -gt 0) {
        Write-Host '  原因'
        foreach ($message in $Messages) {
            Write-Host "    - $message" -ForegroundColor $statusColor
        }
    }

    foreach ($detail in $Details) {
        Write-Host "  $detail"
    }
    Write-Host ''
}

# current-session HTTP proxy
function global:set_proxy_fun {
    $proxyUrl = 'http://127.0.0.1:7890'
    try {
        $env:HTTP_PROXY = $proxyUrl
        $env:HTTPS_PROXY = $proxyUrl
    }
    catch {
        Write-ProxyCommandResult -Command 'proxyon' -Success:$false -Messages @($_.Exception.Message) -Details @(
            '作用范围 : 当前 PowerShell 会话可能已部分修改'
        )
        return
    }

    Write-ProxyCommandResult -Command 'proxyon' -Success:$true -Details @(
        "代理地址 : $proxyUrl"
        '协议     : HTTP / HTTPS'
        '作用范围 : 当前 PowerShell 会话及之后启动的子进程；所有域名'
        '持久化   : 否'
    )
}
Set-Alias -Name proxyon -Value set_proxy_fun -Scope Global

function global:unset_proxy_fun {
    try {
        [System.Environment]::SetEnvironmentVariable('HTTP_PROXY', $null, 'Process')
        [System.Environment]::SetEnvironmentVariable('HTTPS_PROXY', $null, 'Process')
        [System.Environment]::SetEnvironmentVariable('ALL_PROXY', $null, 'Process')
    }
    catch {
        Write-ProxyCommandResult -Command 'proxyoff' -Success:$false -Messages @($_.Exception.Message) -Details @(
            '作用范围 : 当前 PowerShell 会话可能仍保留代理环境变量'
        )
        return
    }

    Write-ProxyCommandResult -Command 'proxyoff' -Success:$true -Details @(
        '作用范围 : 当前 PowerShell 会话及之后启动的子进程'
        '已启动进程 : 不受影响'
        '持久化   : 否'
    )
}
Set-Alias -Name proxyoff -Value unset_proxy_fun -Scope Global

# GitHub-only Git proxy. HTTP(S) uses a managed Git include; SSH uses Git for
# Windows' SOCKS connector through a managed OpenSSH include file.
function global:gitproxyon {
    $proxyHost = '127.0.0.1'
    $proxyPort = 7890
    $proxyUrl = "http://${proxyHost}:${proxyPort}"
    $managedMarker = '# Managed by ShellCfg gitproxyon'
    $gitConfigKeys = @(
        'http.https://github.com/.proxy'
        'http.http://github.com/.proxy'
    )

    $gitCommand = Get-Command git.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $gitCommand) {
        Write-ProxyCommandResult -Command 'gitproxyon' -Success:$false -Messages @('未找到 git.exe') -Details @(
            '作用范围 : Git 和 SSH 代理配置均未修改'
        )
        return
    }

    $needsManagedGitConfig = $false
    foreach ($key in $gitConfigKeys) {
        $values = @(& $gitCommand.Source config --global --includes --get-all $key 2>$null)
        $exitCode = $LASTEXITCODE
        if ($exitCode -notin 0, 1) {
            Write-ProxyCommandResult -Command 'gitproxyon' -Success:$false -Messages @("无法读取 Git 配置：$key") -Details @(
                '作用范围 : Git 和 SSH 代理配置均未修改'
            )
            return
        }
        if ($values.Count -eq 0) {
            $needsManagedGitConfig = $true
            continue
        }
        if ($values | Where-Object { $_ -ne $proxyUrl }) {
            Write-ProxyCommandResult -Command 'gitproxyon' -Success:$false -Messages @("Git 配置已有不同值：$key") -Details @(
                '作用范围 : Git 和 SSH 代理配置均未修改'
            )
            return
        }
    }

    $connectCommand = Get-Command connect.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $connectPath = if ($connectCommand) { $connectCommand.Source } else { $null }

    if (-not $connectPath) {
        $gitExecPath = (& $gitCommand.Source --exec-path 2>$null | Select-Object -First 1)
        if ($gitExecPath) {
            $gitRuntimeRoot = Split-Path (Split-Path $gitExecPath -Parent) -Parent
            $candidate = Join-Path $gitRuntimeRoot 'bin/connect.exe'
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                $connectPath = (Resolve-Path -LiteralPath $candidate).Path
            }
        }
    }

    if (-not $connectPath) {
        Write-ProxyCommandResult -Command 'gitproxyon' -Success:$false -Messages @('未找到 connect.exe；请安装包含 Unix 工具的 Git for Windows') -Details @(
            '作用范围 : Git 和 SSH 代理配置均未修改'
        )
        return
    }

    $gitConfigDirectory = Join-Path $HOME '.gitconfig.d'
    $gitProxyConfigPath = Join-Path $gitConfigDirectory 'shellcfg-github-proxy.gitconfig'
    $gitIncludePath = $gitProxyConfigPath.Replace('\', '/')
    $gitProxyConfigExisted = Test-Path -LiteralPath $gitProxyConfigPath -PathType Leaf
    $oldGitProxyConfig = if ($gitProxyConfigExisted) { [System.IO.File]::ReadAllText($gitProxyConfigPath) } else { $null }
    if ($gitProxyConfigExisted) {
        if (-not $oldGitProxyConfig.StartsWith($managedMarker, [System.StringComparison]::Ordinal)) {
            Write-ProxyCommandResult -Command 'gitproxyon' -Success:$false -Messages @("文件不属于 ShellCfg：$gitProxyConfigPath") -Details @(
                '作用范围 : Git 和 SSH 代理配置均未修改'
            )
            return
        }
        $needsManagedGitConfig = $true
    }

    $sshDirectory = Join-Path $HOME '.ssh'
    $sshConfigDirectory = Join-Path $sshDirectory 'config.d'
    $sshMainConfigPath = Join-Path $sshDirectory 'config'
    $sshProxyConfigPath = Join-Path $sshConfigDirectory 'shellcfg-github-proxy.conf'
    $sshIncludeLine = 'Include ~/.ssh/config.d/shellcfg-*.conf'
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)

    $mainConfigExisted = Test-Path -LiteralPath $sshMainConfigPath -PathType Leaf
    $oldMainConfig = if ($mainConfigExisted) { [System.IO.File]::ReadAllText($sshMainConfigPath) } else { $null }
    $sshProxyConfigExisted = Test-Path -LiteralPath $sshProxyConfigPath -PathType Leaf
    $oldSshProxyConfig = if ($sshProxyConfigExisted) { [System.IO.File]::ReadAllText($sshProxyConfigPath) } else { $null }

    if ($sshProxyConfigExisted -and -not $oldSshProxyConfig.StartsWith($managedMarker, [System.StringComparison]::Ordinal)) {
        Write-ProxyCommandResult -Command 'gitproxyon' -Success:$false -Messages @("文件不属于 ShellCfg：$sshProxyConfigPath") -Details @(
            '作用范围 : Git 和 SSH 代理配置均未修改'
        )
        return
    }

    $gitIncludeAdded = $false
    try {
        if ($needsManagedGitConfig) {
            $null = New-Item -ItemType Directory -Path $gitConfigDirectory -Force
            $gitProxyConfig = @"
$managedMarker
[http "https://github.com/"]
    proxy = $proxyUrl

[http "http://github.com/"]
    proxy = $proxyUrl
"@ + [Environment]::NewLine
            [System.IO.File]::WriteAllText($gitProxyConfigPath, $gitProxyConfig, $utf8NoBom)

            $gitIncludes = @(& $gitCommand.Source config --global --get-all include.path 2>$null)
            if ($LASTEXITCODE -notin 0, 1) {
                throw 'Failed to read Git include.path values.'
            }
            if ($gitIncludePath -notin $gitIncludes) {
                & $gitCommand.Source config --global --add include.path $gitIncludePath
                if ($LASTEXITCODE -ne 0) {
                    throw 'Failed to add the managed Git proxy include.'
                }
                $gitIncludeAdded = $true
            }
        }

        $null = New-Item -ItemType Directory -Path $sshConfigDirectory -Force
        $mainConfig = if ($mainConfigExisted) { $oldMainConfig } else { '' }
        $includePattern = '(?m)^\s*' + [regex]::Escape($sshIncludeLine) + '\s*$'
        if ($mainConfig -notmatch $includePattern) {
            $separator = if ([string]::IsNullOrEmpty($mainConfig)) { '' } else { [Environment]::NewLine }
            $mainConfig = $sshIncludeLine + [Environment]::NewLine + $separator + $mainConfig
            [System.IO.File]::WriteAllText($sshMainConfigPath, $mainConfig, $utf8NoBom)
        }

        $sshConnectPath = $connectPath.Replace('\', '/')
        $sshProxyConfig = @"
$managedMarker
Host github.com
    HostName ssh.github.com
    Port 443
    User git
    ProxyCommand "$sshConnectPath" -S ${proxyHost}:${proxyPort} %h %p
"@ + [Environment]::NewLine
        [System.IO.File]::WriteAllText($sshProxyConfigPath, $sshProxyConfig, $utf8NoBom)
    }
    catch {
        if ($gitIncludeAdded) {
            & $gitCommand.Source config --global --fixed-value --unset-all include.path $gitIncludePath 2>$null
        }
        if ($gitProxyConfigExisted) {
            [System.IO.File]::WriteAllText($gitProxyConfigPath, $oldGitProxyConfig, $utf8NoBom)
        } else {
            Remove-Item -LiteralPath $gitProxyConfigPath -Force -ErrorAction SilentlyContinue
        }
        if ($sshProxyConfigExisted) {
            [System.IO.File]::WriteAllText($sshProxyConfigPath, $oldSshProxyConfig, $utf8NoBom)
        } else {
            Remove-Item -LiteralPath $sshProxyConfigPath -Force -ErrorAction SilentlyContinue
        }
        if ($mainConfigExisted) {
            [System.IO.File]::WriteAllText($sshMainConfigPath, $oldMainConfig, $utf8NoBom)
        } else {
            Remove-Item -LiteralPath $sshMainConfigPath -Force -ErrorAction SilentlyContinue
        }

        Write-ProxyCommandResult -Command 'gitproxyon' -Success:$false -Messages @($_.Exception.Message) -Details @(
            '作用范围 : 已尝试回滚本次修改'
        )
        return
    }

    Write-ProxyCommandResult -Command 'gitproxyon' -Success:$true -Details @(
        "代理地址 : ${proxyHost}:${proxyPort}"
        '协议     : Git HTTP / HTTPS / SSH'
        '作用范围 : 当前 Windows 用户；仅 github.com'
        '持久化   : 是，跨终端和重启'
        '提示     : proxyon 开启时，其他域名仍可能走会话代理'
    )
}

function global:gitproxyoff {
    $managedMarker = '# Managed by ShellCfg gitproxyon'
    $gitProxyConfigPath = Join-Path $HOME '.gitconfig.d/shellcfg-github-proxy.gitconfig'
    $gitIncludePath = $gitProxyConfigPath.Replace('\', '/')
    $sshProxyConfigPath = Join-Path $HOME '.ssh/config.d/shellcfg-github-proxy.conf'
    $failures = [System.Collections.Generic.List[string]]::new()

    $gitProxyConfigExists = Test-Path -LiteralPath $gitProxyConfigPath -PathType Leaf
    $gitProxyConfigOwned = $false
    if ($gitProxyConfigExists) {
        $gitProxyConfig = [System.IO.File]::ReadAllText($gitProxyConfigPath)
        if ($gitProxyConfig.StartsWith($managedMarker, [System.StringComparison]::Ordinal)) {
            $gitProxyConfigOwned = $true
        } else {
            $failures.Add("Git 配置文件不属于 ShellCfg：$gitProxyConfigPath")
        }
    }

    $gitIncludeRemoved = -not $gitProxyConfigOwned
    if ($gitProxyConfigOwned) {
        $gitCommand = Get-Command git.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $gitCommand) {
            $failures.Add('未找到 git.exe，无法移除 Git include')
        } else {
            $gitIncludes = @(& $gitCommand.Source config --global --get-all include.path 2>$null)
            if ($LASTEXITCODE -notin 0, 1) {
                $failures.Add('无法读取 Git include.path')
            } elseif ($gitIncludePath -in $gitIncludes) {
                & $gitCommand.Source config --global --fixed-value --unset-all include.path $gitIncludePath
                if ($LASTEXITCODE -eq 0) {
                    $gitIncludeRemoved = $true
                } else {
                    $failures.Add('无法移除 ShellCfg 管理的 Git include')
                }
            } else {
                $gitIncludeRemoved = $true
            }
        }
    }

    if ($gitProxyConfigOwned -and $gitIncludeRemoved) {
        try {
            Remove-Item -LiteralPath $gitProxyConfigPath -Force -ErrorAction Stop
        }
        catch {
            $failures.Add("无法删除 Git 配置文件：$($_.Exception.Message)")
        }
    }

    if (Test-Path -LiteralPath $sshProxyConfigPath -PathType Leaf) {
        $sshProxyConfig = [System.IO.File]::ReadAllText($sshProxyConfigPath)
        if ($sshProxyConfig.StartsWith($managedMarker, [System.StringComparison]::Ordinal)) {
            try {
                Remove-Item -LiteralPath $sshProxyConfigPath -Force -ErrorAction Stop
            }
            catch {
                $failures.Add("无法删除 SSH 配置文件：$($_.Exception.Message)")
            }
        } else {
            $failures.Add("SSH 配置文件不属于 ShellCfg：$sshProxyConfigPath")
        }
    }

    if ($failures.Count -eq 0) {
        Write-ProxyCommandResult -Command 'gitproxyoff' -Success:$true -Details @(
            '作用范围 : 当前 Windows 用户；ShellCfg 管理的 GitHub HTTP / HTTPS / SSH 代理已移除'
            '会话代理 : 不受影响；如需关闭请执行 proxyoff'
            '持久化   : GitHub 代理配置已关闭'
        )
    } else {
        Write-ProxyCommandResult -Command 'gitproxyoff' -Success:$false -Messages $failures -Details @(
            '作用范围 : 当前 Windows 用户；部分 GitHub 代理配置可能仍然存在'
            '会话代理 : 不受影响；如需关闭请执行 proxyoff'
        )
    }
}


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
