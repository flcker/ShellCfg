################################################################################
# winget_path.ps1 — Keep winget shim path in WINGET_SHIM_PATH, separate from PATH
#
# USAGE
#   syncwp              扫描 User PATH，迁移 winget 路径 → WINGET_SHIM_PATH（持久化）
#   syncwp -WhatIf      预览，不做实际修改
#   syncws              扫描所有 winget 包，创建/更新 shims（解决 2047 字节溢出）
#   syncws -WhatIf      预览，不做实际修改
#
# HOW IT WORKS
#   WINGET_SHIM_PATH 是用户级环境变量，存储 shims 目录路径（约 45 字节），
#   彻底解决 User PATH 的 2047 字节溢出问题。
#   Import-WingetShimPath 在首次 syncwp 之前负责注入（之后为幂等 no-op）。
#
# DETECTION
#   路径以 $script:_WingetRoots 中的根目录为前缀即视为 winget 管理。
#
# INSPECT
#   $env:WINGET_SHIM_PATH -split ';'          当前会话条目
#   [Environment]::GetEnvironmentVariable('WINGET_SHIM_PATH','User')   持久化值
#   Get-Content "$env:LOCALAPPDATA\winget_shims\.manifest.json" | ConvertFrom-Json

$script:_WingetRoots = @(
    "$env:LOCALAPPDATA\Microsoft\WinGet\Packages",
    "$env:LOCALAPPDATA\Microsoft\WinGet\Links"
)
$script:_ShimsDir = "$env:LOCALAPPDATA\winget_shims"

# private functions
function _FindWingetExeDir {
    param([string]$PackageRoot)

    if (-not (Test-Path $PackageRoot)) { return $null }

    $exesInRoot = @(Get-ChildItem -Path $PackageRoot -Filter '*.exe' -File -ErrorAction SilentlyContinue)
    if ($exesInRoot.Count -gt 0) { return $PackageRoot }

    $best      = $null
    $bestScore = 0
    $dirs = Get-ChildItem -Path $PackageRoot -Directory -ErrorAction SilentlyContinue

    $scoreDir = {
        param($Path)
        $exes = @(Get-ChildItem -Path $Path -Filter '*.exe' -File -ErrorAction SilentlyContinue)
        if ($exes.Count -eq 0) { return 0 }
        $dlls = @(Get-ChildItem -Path $Path -Filter '*.dll' -File -ErrorAction SilentlyContinue)
        # DLL 同目录加权：有 DLL 的目录通常是主安装目录
        return $exes.Count + ($dlls.Count * 100)
    }

    foreach ($d1 in $dirs) {
        $s1 = & $scoreDir $d1.FullName
        if ($s1 -gt $bestScore) { $bestScore = $s1; $best = $d1.FullName }

        $dirs2 = Get-ChildItem -Path $d1.FullName -Directory -ErrorAction SilentlyContinue
        foreach ($d2 in $dirs2) {
            $s2 = & $scoreDir $d2.FullName
            if ($s2 -gt $bestScore) { $bestScore = $s2; $best = $d2.FullName }

            $dirs3 = Get-ChildItem -Path $d2.FullName -Directory -ErrorAction SilentlyContinue
            foreach ($d3 in $dirs3) {
                $s3 = & $scoreDir $d3.FullName
                if ($s3 -gt $bestScore) { $bestScore = $s3; $best = $d3.FullName }
            }
        }
    }

    return $best
}


function _GetShimName {
    param([string]$PackageId)

    $variantTags = @('shared', 'msvc', 'full', 'lite', 'portable', 'stable', 'beta')
    $segments    = $PackageId -split '\.' | Where-Object { $_ -ne '' }
    $name        = $segments[-1]
    if ($name.ToLower() -in $variantTags -and $segments.Count -ge 2) {
        $name = $segments[-2]
    }
    return $name.ToLower()
}


function _NewWingetShim {
    param(
        [string]$SourceDir,
        [string]$PackageId,
        [string]$ShimsDir,
        [switch]$WhatIf
    )

    $exeFiles = @(Get-ChildItem -Path $SourceDir -Filter '*.exe' -File -ErrorAction SilentlyContinue)
    if ($exeFiles.Count -eq 0) {
        return [pscustomobject]@{ SourceDir = $SourceDir; ShimType = 'none'; Items = @() }
    }

    $dllFiles = @(Get-ChildItem -Path $SourceDir -Filter '*.dll' -File -ErrorAction SilentlyContinue)
    $items    = @()

    if ($dllFiles.Count -gt 0) {
        $junctionName = _GetShimName -PackageId $PackageId
        $junctionPath = Join-Path $ShimsDir $junctionName

        if (Test-Path $junctionPath) {
            $item = Get-Item $junctionPath -Force -ErrorAction SilentlyContinue
            if ($item -and ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
                cmd /c "rmdir `"$junctionPath`"" 2>&1 | Out-Null
            }
        }

        if (-not $WhatIf) {
            cmd /c "mklink /J `"$junctionPath`" `"$SourceDir`"" 2>&1 | Out-Null
        }
        $items = @($junctionName)
        return [pscustomobject]@{ SourceDir = $SourceDir; ShimType = 'junction'; Items = $items }
    } else {
        foreach ($exe in $exeFiles) {
            $linkPath = Join-Path $ShimsDir $exe.Name
            if (-not $WhatIf) {
                if (Test-Path $linkPath) { Remove-Item $linkPath -Force }
                New-Item -ItemType HardLink -Path $linkPath -Target $exe.FullName -ErrorAction SilentlyContinue | Out-Null
                if (-not (Test-Path $linkPath)) {
                    $cmdName = [System.IO.Path]::GetFileNameWithoutExtension($exe.Name) + '.cmd'
                    $cmdPath = Join-Path $ShimsDir $cmdName
                    [System.IO.File]::WriteAllText($cmdPath, "@`"$($exe.FullName)`" %*", [System.Text.Encoding]::ASCII)
                    $items += $cmdName
                    continue
                }
            }
            $items += $exe.Name
        }
        return [pscustomobject]@{ SourceDir = $SourceDir; ShimType = 'hardlink'; Items = $items }
    }
}


# public functions
function global:Import-WingetShimPath {
    <#
    .SYNOPSIS
        将 WINGET_SHIM_PATH 注入当前会话的 $env:Path（去重）。
    .DESCRIPTION
        读取用户级 WINGET_SHIM_PATH 环境变量，把其中不在 $env:Path 的条目追加进去。
        同时读取 manifest 把实际包路径注入会话（保证 .exe 可直接找到）。
        兼容旧版 WINGET_PATH：若 WINGET_SHIM_PATH 未设置则回退读取 WINGET_PATH。
        在 profile 加载时自动调用，reenv/Update-Env 后也会调用。
    #>
    $wp = [System.Environment]::GetEnvironmentVariable('WINGET_SHIM_PATH', 'User')
    if (-not $wp) {
        # 旧版兼容回退：首次 syncwp 之前 WINGET_SHIM_PATH 尚未创建
        $wp = [System.Environment]::GetEnvironmentVariable('WINGET_PATH', 'User')
    }
    if (-not $wp) { return }

    $wpEntries   = $wp -split ';' | Where-Object { $_ -ne '' }
    $pathEntries = $env:Path -split ';' | Where-Object { $_ -ne '' }
    $toAdd       = $wpEntries | Where-Object { $_ -notin $pathEntries }
    if ($toAdd) { $env:Path = ($pathEntries + $toAdd) -join ';' }

    $shimsDir = $script:_ShimsDir
    if (-not (Test-Path $shimsDir)) { return }
    if ($wpEntries -notcontains $shimsDir) { return }

    $junctions = @(Get-ChildItem -Path $shimsDir -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Attributes -band [System.IO.FileAttributes]::ReparsePoint })
    if ($junctions.Count -eq 0) { return }

    $curPath = $env:Path -split ';' | Where-Object { $_ -ne '' }
    $inject  = @($junctions | ForEach-Object { $_.FullName } |
        Where-Object { $_ -notin $curPath })
    if ($inject.Count -gt 0) {
        $env:Path = ($curPath + $inject) -join ';'
    }

    $broken = @($junctions | Where-Object {
        $target = $_.Target
        $target -and -not [System.IO.Directory]::Exists($target)
    })
    if ($broken.Count -gt 0) {
        Write-Warning "WINGET_SHIM_PATH: $($broken.Count) 个 shim 目标不存在，运行 syncws 修复"
    }
}

Set-Alias -Name Import-WingetPath -Value Import-WingetShimPath -Scope Global

Import-WingetShimPath


function global:Sync-WingetShims {
    <#
    .SYNOPSIS
        扫描 winget 包目录，为每个包创建 shim（.cmd 文件或目录 junction）。
    .DESCRIPTION
        解决 User PATH / WINGET_SHIM_PATH 的 2047 字节溢出问题。
        所有 shim 集中在 $script:_ShimsDir，WINGET_SHIM_PATH 只需存储该目录路径（约 45 字节）。
        - .cmd shim：无 DLL 依赖的包（fzf、jq、bat 等），每个 .exe 生成一个 .cmd 包装。
        - junction：有 DLL 依赖的包（ffmpeg、poppler 等），创建目录联结，保留 DLL 可见性。
    .EXAMPLE
        syncws
        扫描所有 winget 包并同步 shims。
    .EXAMPLE
        syncws -WhatIf
        预览，不做实际修改。
    .NOTES
        别名：syncws
        清单文件：$env:LOCALAPPDATA\winget_shims\.manifest.json
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string[]]$Paths,
        [Alias('h')] [switch]$Help
    )

    if ($Help) {
        Write-Host
        Write-Host "用法：" -ForegroundColor Cyan
        Write-Host "  syncws              扫描所有 winget 包，创建/更新 shims"
        Write-Host "  syncws -WhatIf      预览，不做实际修改"
        Write-Host "  syncws -Help / -h   显示此帮助"
        Write-Host
        Write-Host "Shims 目录：" -ForegroundColor Cyan
        Write-Host "  $($script:_ShimsDir)" -ForegroundColor DarkGray
        Write-Host
        Write-Host "Shim 类型：" -ForegroundColor Cyan
        Write-Host "  .cmd     无 DLL 依赖的包，每个 exe 生成一个 .cmd 包装"
        Write-Host "  junction 有 DLL 依赖的包，创建目录联结保留 DLL 可见性"
        Write-Host
        Write-Host "相关命令：" -ForegroundColor Cyan
        Write-Host "  syncwp   迁移 PATH 中的 winget 路径到 WINGET_SHIM_PATH"
        Write-Host
        return
    }

    $shimsDir    = $script:_ShimsDir
    $packagesDir = $script:_WingetRoots[0]
    $whatIfMode  = -not $PSCmdlet.ShouldProcess('shims 目录', '创建或更新 shims')

    if (-not $whatIfMode -and -not (Test-Path $shimsDir)) {
        New-Item -ItemType Directory -Path $shimsDir -Force | Out-Null
    }

    $useExplicitPaths = $Paths -and $Paths.Count -gt 0

    $packageDirs = @()
    if ($useExplicitPaths) {
        $packageDirs = $Paths | Where-Object { Test-Path $_ } | ForEach-Object { [pscustomobject]@{ FullName = $_; Name = Split-Path $_ -Leaf } }
    } else {
        if (Test-Path $packagesDir) {
            $packageDirs = @(Get-ChildItem -Path $packagesDir -Directory -ErrorAction SilentlyContinue)
        }
    }

    if ($packageDirs.Count -eq 0) {
        Write-Host "未找到 winget 包目录：$packagesDir" -ForegroundColor Yellow
        return
    }

    $manifest  = [System.Collections.Generic.List[object]]::new()
    $created   = 0
    $updated   = 0
    $skipped   = 0

    $existingItems = @{}
    if (Test-Path $shimsDir) {
        Get-ChildItem -Path $shimsDir -ErrorAction SilentlyContinue | ForEach-Object { $existingItems[$_.Name] = $_.FullName }
    }
    $seenItems = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($pkgDir in $packageDirs) {
        $pkgName = $pkgDir.Name
        $suffix  = '_Microsoft.Winget.Source_8wekyb3d8bbwe'

        if ($useExplicitPaths) {
            $pathStr = $pkgDir.FullName
            foreach ($root in $script:_WingetRoots) {
                if ($pathStr.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $rel = $pathStr.Substring($root.Length).TrimStart('\')
                    $topDir = ($rel -split '\\')[0]
                    $pkgName = $topDir
                    break
                }
            }
        }

        $pkgId = if ($pkgName.EndsWith($suffix)) { $pkgName.Substring(0, $pkgName.Length - $suffix.Length) } else { $pkgName }

        $exeDir = if ($useExplicitPaths) { $pkgDir.FullName } else { _FindWingetExeDir -PackageRoot $pkgDir.FullName }
        if (-not $exeDir) { $skipped++; continue }

        $result = _NewWingetShim -SourceDir $exeDir -PackageId $pkgId -ShimsDir $shimsDir -WhatIf:$whatIfMode

        if ($result.ShimType -eq 'none') { $skipped++; continue }

        $exeNames = @(Get-ChildItem -Path $exeDir -Filter '*.exe' -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)

        $mfEntry = [pscustomobject]@{
            package     = $pkgId
            sourcePath  = $exeDir
            shimType    = $result.ShimType
            executables = $exeNames
            items       = $result.Items
        }
        $manifest.Add($mfEntry)

        foreach ($item in $result.Items) { $seenItems.Add($item) | Out-Null }

        $isNew = $result.Items | Where-Object { -not $existingItems.ContainsKey($_) }
        if ($isNew) { $created++ } else { $updated++ }
    }

    $orphans = @($existingItems.Keys | Where-Object {
        $_ -ne '.manifest.json' -and -not $seenItems.Contains($_)
    })
    if ($orphans.Count -gt 0 -and -not $whatIfMode) {
        foreach ($orphan in $orphans) {
            $orphanPath = Join-Path $shimsDir $orphan
            if (Test-Path $orphanPath -PathType Container) {
                cmd /c "rmdir `"$orphanPath`"" 2>&1 | Out-Null
            } else {
                Remove-Item $orphanPath -Force -ErrorAction SilentlyContinue
            }
        }
    }

    if (-not $whatIfMode) {
        $manifestPath = Join-Path $shimsDir '.manifest.json'
        $manifestJson = ConvertTo-Json -InputObject @($manifest) -Depth 5
        [System.IO.File]::WriteAllText($manifestPath, $manifestJson, [System.Text.Encoding]::UTF8)
    }

    $whatIfTag = if ($whatIfMode) { ' [WhatIf]' } else { '' }
    Write-Host ("shims 同步完成{0}：新建 {1}，更新 {2}，跳过 {3}，孤立清理 {4}" -f $whatIfTag, $created, $updated, $skipped, $orphans.Count) -ForegroundColor Green
    Write-Host "  Shims 目录：$shimsDir" -ForegroundColor DarkGray
}

Set-Alias -Name syncws -Value Sync-WingetShims -Scope Global


function global:Show-WingetTools {
    <#
    .SYNOPSIS
        列出 WINGET_SHIM_PATH 管理的所有工具，或查看指定工具的用法。
    .EXAMPLE
        wgs
        列出所有 winget 管理的工具。
    .EXAMPLE
        wgs rg
        显示 rg 的帮助信息。
    .NOTES
        别名：wgs
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Command,
        [Alias('h')] [switch]$Help
    )

    if ($Help) {
        Write-Host
        Write-Host "用法：" -ForegroundColor Cyan
        Write-Host "  wgs              列出所有 winget 管理的工具"
        Write-Host "  wgs <command>    查看指定工具的帮助（--help）"
        Write-Host "  wgs -Help / -h   显示此帮助"
        Write-Host
        return
    }

    $manifestPath = Join-Path $script:_ShimsDir '.manifest.json'
    if (-not (Test-Path $manifestPath)) {
        Write-Host "未找到 shims 清单，请先运行 syncws。" -ForegroundColor Yellow
        return
    }

    $manifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json

    if ($Command) {
        $target = $Command -replace '\.exe$', ''
        $found  = $null
        foreach ($pkg in $manifest) {
            $match = $pkg.executables | Where-Object { [System.IO.Path]::GetFileNameWithoutExtension($_) -eq $target }
            if ($match) { $found = $pkg; break }
        }
        if (-not $found) {
            Write-Host "未找到命令 '$Command'。运行 wgs 查看可用工具。" -ForegroundColor Yellow
            return
        }
        $exePath = Join-Path $found.sourcePath "$target.exe"
        if (-not (Test-Path $exePath)) {
            Write-Host "可执行文件不存在：$exePath" -ForegroundColor Red
            return
        }
        Write-Host "$target — $($found.package) [$($found.shimType)]" -ForegroundColor Cyan
        Write-Host "  路径：$exePath" -ForegroundColor DarkGray
        Write-Host
        & $exePath --help 2>&1
        return
    }

    $cols = 5
    $colW = 14
    $totalExes = ($manifest | ForEach-Object { $_.executables.Count } | Measure-Object -Sum).Sum
    Write-Host "winget 工具（$($manifest.Count) 包，$totalExes 命令）" -ForegroundColor Cyan
    Write-Host "  wgs <command> 查看用法" -ForegroundColor DarkGray
    Write-Host

    foreach ($pkg in $manifest | Sort-Object package) {
        $typeTag = if ($pkg.shimType -eq 'junction') { '◆' } else { '·' }
        Write-Host "  $typeTag $($pkg.package)" -ForegroundColor White
        $names = @(@($pkg.executables) | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_) } | Sort-Object)
        for ($i = 0; $i -lt $names.Count; $i += $cols) {
            $line = ''
            $end  = [Math]::Min($i + $cols, $names.Count) - 1
            foreach ($n in $names[$i..$end]) { $line += $n.PadRight($colW) }
            Write-Host "    $line" -ForegroundColor Green
        }
    }
    Write-Host
    Write-Host "  · cmd shim  ◆ junction (DLL)" -ForegroundColor DarkGray
}

Set-Alias -Name wgs -Value Show-WingetTools -Scope Global


function global:Sync-WingetPath {
    <#
    .SYNOPSIS
        扫描 User PATH，将 winget 管理的路径迁移到 WINGET_SHIM_PATH 环境变量。
    .DESCRIPTION
        识别 User PATH 中属于已知 winget 安装目录的条目，将其从 PATH 移除，
        写入 WINGET_SHIM_PATH 并持久化（写入注册表）。同时刷新当前会话的 $env:Path。
        迁移完成后自动调用 syncws，将所有路径压缩为单一 shims 目录。
        若检测到旧版 WINGET_PATH 变量，自动迁移到 WINGET_SHIM_PATH 并删除旧变量。
    .EXAMPLE
        syncwp
        迁移所有检测到的 winget 路径，并重建 shims。
    .EXAMPLE
        syncwp -WhatIf
        预览将要迁移的路径，不做任何实际修改。
    .NOTES
        别名：syncwp
        Shims：syncws
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Alias('h')]
        [switch]$Help
    )

    if ($Help) {
        Write-Host
        Write-Host "用法：" -ForegroundColor Cyan
        Write-Host "  syncwp              扫描 User PATH，将 winget 路径迁移到 WINGET_SHIM_PATH（持久化）"
        Write-Host "  syncwp -WhatIf      预览将要迁移的路径，不做实际修改"
        Write-Host "  syncwp -Help / -h   显示此帮助"
        Write-Host
        Write-Host "Shims：" -ForegroundColor Cyan
        Write-Host "  syncws              为所有 winget 包创建/更新 shims（解决 PATH 溢出）"
        Write-Host "  syncws -WhatIf      预览 shims 操作"
        Write-Host
        Write-Host "查询：" -ForegroundColor Cyan
        Write-Host "  wgs                列出所有 winget 管理的工具"
        Write-Host "  wgs <command>      查看指定工具的帮助"
        Write-Host
        Write-Host "检测根目录（\$script:_WingetRoots）：" -ForegroundColor Cyan
        $script:_WingetRoots | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
        Write-Host
        Write-Host "查看当前 WINGET_SHIM_PATH：" -ForegroundColor Cyan
        Write-Host "  `$env:WINGET_SHIM_PATH -split ';'"
        Write-Host
        return
    }

    $roots = $script:_WingetRoots

    $regKey      = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment')
    $rawUserPath = $regKey.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    $regKey.Close()

    # --- 迁移旧版 %WINGET_PATH% 引用 → %WINGET_SHIM_PATH% ---
    if ($rawUserPath -match '%WINGET_PATH%') {
        $migratedPath = $rawUserPath -replace [regex]::Escape('%WINGET_PATH%'), '%WINGET_SHIM_PATH%'
        if ($PSCmdlet.ShouldProcess('User PATH', '将 %WINGET_PATH% 替换为 %WINGET_SHIM_PATH%')) {
            $regKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
            $regKey.SetValue('Path', $migratedPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
            $regKey.Close()
            Write-Host "已将 User PATH 中的 %WINGET_PATH% 替换为 %WINGET_SHIM_PATH%。" -ForegroundColor DarkGray
        }
        $rawUserPath = $migratedPath
    }

    # --- 迁移旧版 WINGET_PATH 变量值 → WINGET_SHIM_PATH ---
    $oldWingetPath = [System.Environment]::GetEnvironmentVariable('WINGET_PATH', 'User')
    $newShimPath   = [System.Environment]::GetEnvironmentVariable('WINGET_SHIM_PATH', 'User')
    if ($oldWingetPath -and -not $newShimPath) {
        if ($PSCmdlet.ShouldProcess('User 环境变量', "迁移 WINGET_PATH → WINGET_SHIM_PATH")) {
            [System.Environment]::SetEnvironmentVariable('WINGET_SHIM_PATH', $oldWingetPath, 'User')
            Write-Host "已将 WINGET_PATH 值迁移到 WINGET_SHIM_PATH。" -ForegroundColor DarkGray
        }
    }
    if ($oldWingetPath) {
        if ($PSCmdlet.ShouldProcess('User 环境变量', '删除旧版 WINGET_PATH')) {
            [System.Environment]::SetEnvironmentVariable('WINGET_PATH', $null, 'User')
            Remove-Item Env:\WINGET_PATH -ErrorAction SilentlyContinue
            Write-Host "已删除旧版 WINGET_PATH 环境变量。" -ForegroundColor DarkGray
        }
    }

    $wingetPath    = [System.Environment]::GetEnvironmentVariable('WINGET_SHIM_PATH', 'User') ?? ''
    $allEntries    = $rawUserPath -split ';' | Where-Object { $_ -ne '' }
    $wingetEntries = $wingetPath  -split ';' | Where-Object { $_ -ne '' }

    $alreadyRef  = $allEntries -contains '%WINGET_SHIM_PATH%'
    $realEntries = $allEntries | Where-Object { $_ -ne '%WINGET_SHIM_PATH%' }

    $keep   = [System.Collections.Generic.List[string]]::new()
    $moving = [System.Collections.Generic.List[string]]::new()

    foreach ($entry in $realEntries) {
        $expanded = [System.Environment]::ExpandEnvironmentVariables($entry)
        $isWinget = $roots | Where-Object {
            $expanded.StartsWith($_, [System.StringComparison]::OrdinalIgnoreCase)
        }
        if ($isWinget) { $moving.Add($entry) } else { $keep.Add($entry) }
    }

    $shimsDir     = $script:_ShimsDir
    $alreadyShims = ($wingetEntries.Count -eq 1 -and $wingetEntries[0] -eq $shimsDir)

    if ($moving.Count -eq 0) {
        if ($wingetEntries.Count -gt 0 -and -not $alreadyRef) {
            Write-Host "WINGET_SHIM_PATH 已有 $($wingetEntries.Count) 条，但 User PATH 未引用 %WINGET_SHIM_PATH%，正在补充..." -ForegroundColor Yellow
            $keepStr     = $realEntries -join ';'
            $newUserPath = if ($keepStr) { "$keepStr;%WINGET_SHIM_PATH%" } else { '%WINGET_SHIM_PATH%' }
            if ($PSCmdlet.ShouldProcess('User PATH', '写入 %WINGET_SHIM_PATH% 引用')) {
                $regKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
                $regKey.SetValue('Path', $newUserPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
                $regKey.Close()
                Write-Host "完成 — User PATH 已写入 %WINGET_SHIM_PATH% 引用（$($wingetEntries.Count) 条）。" -ForegroundColor Green
            }
            return
        }
        if (-not $alreadyShims -and $wingetEntries.Count -gt 0) {
            Write-Host "检测到 WINGET_SHIM_PATH 存储多条路径（$($wingetEntries.Count) 条），迁移到 shims 模式..." -ForegroundColor Yellow
        } else {
            $ref = if ($alreadyRef) { "已含 %WINGET_SHIM_PATH% 引用（$($wingetEntries.Count) 条）" } else { "无需迁移" }
            Write-Host "User PATH 中未检测到新的 winget 路径。WINGET_SHIM_PATH：$ref" -ForegroundColor Cyan
            if ($alreadyShims) { return }
        }
    } else {
        Write-Host "迁移 $($moving.Count) 条路径：PATH → WINGET_SHIM_PATH" -ForegroundColor Yellow
        $moving | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
    }

    $allWingetPaths = [string[]]($wingetEntries + $moving | Where-Object { $_ -ne $shimsDir } | Select-Object -Unique)
    $keepStr        = ($keep | Where-Object { $_ }) -join ';'
    $newUserPath    = if ($keepStr) { "$keepStr;%WINGET_SHIM_PATH%" } else { '%WINGET_SHIM_PATH%' }

    $desc = if ($moving.Count -gt 0) { "迁移 $($moving.Count) 条 winget 路径，启用 shims 模式" } else { "启用 shims 模式（压缩 $($allWingetPaths.Count) 条路径）" }

    if ($PSCmdlet.ShouldProcess('User 环境变量', $desc)) {
        Write-Host "正在扫描包目录并构建 shims..." -ForegroundColor DarkGray
        Sync-WingetShims

        $regKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
        $regKey.SetValue('Path', $newUserPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
        $regKey.Close()

        [System.Environment]::SetEnvironmentVariable('WINGET_SHIM_PATH', $shimsDir, 'User')

        $env:WINGET_SHIM_PATH = $shimsDir
        $machinePath          = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') ?? ''
        $env:Path             = ($machinePath, $keepStr | Where-Object { $_ }) -join ';'
        Import-WingetShimPath

        Write-Host "完成 — WINGET_SHIM_PATH 已压缩为单一 shims 目录，PATH 减少 $($moving.Count) 条。" -ForegroundColor Green
        Write-Host "  Shims：$shimsDir" -ForegroundColor DarkGray
    }
}

Set-Alias -Name syncwp -Value Sync-WingetPath -Scope Global
