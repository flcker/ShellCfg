# update-submodules.ps1 — 更新 submodule/ 下各配置分支到远端最新
#
# 用法：
#   .\update-submodules.ps1           拉取最新提交并打印父仓指针提交命令
#   .\update-submodules.ps1 -Commit   拉取最新提交并自动提交父仓指针
#   .\update-submodules.ps1 -Help     显示帮助
#
# 分支取自 .gitmodules 的 branch 字段；更新使用 rebase，与 update = rebase
# 配置保持一致。子模块没有本地新提交时，更新等同于 fast-forward。

param(
    [switch]$Commit,
    [Alias('h')]
    [switch]$Help
)

if ($Help) {
    Write-Host '用法：'
    Write-Host '  .\update-submodules.ps1           拉取最新提交并打印父仓指针提交命令'
    Write-Host '  .\update-submodules.ps1 -Commit   拉取最新提交并自动提交父仓指针'
    Write-Host '  .\update-submodules.ps1 -Help     显示帮助'
    return
}

$updated = [System.Collections.Generic.List[string]]::new()
$failed = [System.Collections.Generic.List[string]]::new()
$exitCode = 0

Push-Location $PSScriptRoot
try {
    $configLines = @(& git config -f .gitmodules --get-regexp '^submodule\..*\.branch$')
    if ($LASTEXITCODE -ne 0) {
        throw '无法从 .gitmodules 读取 submodule 分支配置。'
    }

    foreach ($line in $configLines) {
        if ($line -notmatch '^(?<Key>\S+)\s+(?<Branch>.+)$') {
            Write-Host "[配置] 无法解析，跳过：$line" -ForegroundColor Red
            $failed.Add($line)
            continue
        }

        $key = $Matches.Key
        $branch = $Matches.Branch
        $path = $key.Substring('submodule.'.Length)
        $path = $path.Substring(0, $path.Length - '.branch'.Length)
        $name = if ($path.StartsWith('submodule/')) {
            $path.Substring('submodule/'.Length)
        } else {
            $path
        }

        # 未克隆时先按父仓记录的 commit 初始化；--checkout 可绕开
        # update = rebase 对未初始化/半初始化工作区的前置条件。
        $statusLine = & git submodule status -- $path 2>$null | Select-Object -First 1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[$name] 无法读取 submodule 状态，跳过" -ForegroundColor Red
            $failed.Add($name)
            continue
        }
        if ($statusLine -and $statusLine.StartsWith('-')) {
            Write-Host "[$name] 未初始化，先克隆到父仓记录的 commit"
            & git submodule update --init --checkout -- $path
            if ($LASTEXITCODE -ne 0) {
                Write-Host "[$name] 初始化失败，跳过" -ForegroundColor Red
                $failed.Add($name)
                continue
            }
        }

        & git -C $path fetch origin $branch
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[$name] fetch origin $branch 失败，跳过" -ForegroundColor Red
            $failed.Add($name)
            continue
        }

        $current = (& git -C $path rev-parse --abbrev-ref HEAD).Trim()
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[$name] 无法读取当前分支，跳过" -ForegroundColor Red
            $failed.Add($name)
            continue
        }

        if ($current -ne $branch) {
            & git -C $path checkout $branch 2>$null
            if ($LASTEXITCODE -ne 0) {
                & git -C $path checkout -b $branch FETCH_HEAD
            }
            if ($LASTEXITCODE -ne 0) {
                Write-Host "[$name] 切回 $branch 失败（工作区可能不干净），跳过：git -C $path status" -ForegroundColor Red
                $failed.Add($name)
                continue
            }
        }

        $old = (& git -C $path rev-parse HEAD).Trim()
        $new = (& git -C $path rev-parse FETCH_HEAD).Trim()
        if ($LASTEXITCODE -ne 0 -or -not $old -or -not $new) {
            Write-Host "[$name] 无法比较本地与远端提交，跳过" -ForegroundColor Red
            $failed.Add($name)
            continue
        }

        if ($old -eq $new) {
            Write-Host "[$name] 已是最新 ($branch @ $($old.Substring(0, 7)))"
            continue
        }

        & git -C $path rebase FETCH_HEAD
        if ($LASTEXITCODE -ne 0) {
            & git -C $path rebase --abort 2>$null
            Write-Host "[$name] rebase 失败（未提交改动或冲突），已保持原状：git -C $path status" -ForegroundColor Red
            $failed.Add($name)
            continue
        }

        $count = (& git -C $path rev-list --count "$old..$new").Trim()
        Write-Host "[$name] $($old.Substring(0, 7)) -> $($new.Substring(0, 7)) ($branch, +$count)" -ForegroundColor Green
        & git -C $path log --oneline "$old..$new" | ForEach-Object { Write-Host "    $_" }
        $updated.Add($name)
    }

    $pending = @(
        & git diff --name-only HEAD -- submodule/ |
            ForEach-Object { $_ -replace '^submodule/', '' }
    )
    if ($LASTEXITCODE -ne 0) {
        throw '无法读取父仓的 submodule 指针变化。'
    }

    Write-Host ''
    Write-Host '----------------------------------------'
    if ($updated.Count -gt 0 -or $pending.Count -gt 0) {
        if ($updated.Count -gt 0) {
            Write-Host "已更新：$($updated -join ' ')"
        }
        if ($failed.Count -gt 0) {
            Write-Host "失败/跳过：$($failed -join ' ')" -ForegroundColor Red
        }
        if ($pending.Count -gt 0) {
            $message = "chore: 更新 submodule 指针（$($pending -join ' ')）"
            if ($Commit) {
                & git add -- submodule/
                if ($LASTEXITCODE -ne 0) {
                    throw '暂存父仓 submodule 指针失败。'
                }
                & git commit -m $message
                if ($LASTEXITCODE -ne 0) {
                    throw '提交父仓 submodule 指针失败。'
                }
                Write-Host "已提交：$message" -ForegroundColor Green
            } else {
                Write-Host "待记录父仓指针：$($pending -join ' ')"
                Write-Host "    git add submodule/ && git commit -m `"$message`""
            }
        }
    } else {
        Write-Host '全部 submodule 均已是最新，父仓指针无待记录变化'
        if ($failed.Count -gt 0) {
            Write-Host "失败/跳过：$($failed -join ' ')" -ForegroundColor Red
        }
    }

    if ($failed.Count -gt 0) {
        $exitCode = 1
    }
} catch {
    Write-Error $_
    $exitCode = 1
} finally {
    Pop-Location
}

exit $exitCode
