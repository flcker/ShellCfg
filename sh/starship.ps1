################################################################################
# starship
$profileRoot = Split-Path $PSScriptRoot -Parent

# ── Config registry ───────────────────────────────────────────────────────────
$script:starshipRegistry = @{ "default" = ""; "d" = "" }
$script:starshipPool = @("")  # empty = starship default

# ── Detect submodule/starship (static configs) ────────────────────────────────
$staticDir = "$profileRoot\submodule\starship"
if (Test-Path $staticDir) {
    $staticMappings = @{
        "custom"           = "starship_custom.toml"
        "c"                = "starship_custom.toml"
        "powerline"        = "starship_powerline.toml"
        "pl"               = "starship_powerline.toml"
        "plaintextsymbols" = "starship_plaintextsymbols.toml"
        "pts"              = "starship_plaintextsymbols.toml"
        "nerdfontsymbols"  = "starship_nerdfontsymbols.toml"
        "nfs"              = "starship_nerdfontsymbols.toml"
        "pastelpowerline"  = "starship_pastelpowerline.toml"
        "ppl"              = "starship_pastelpowerline.toml"
        "nerdpowerline"    = "starship_nerdpowerline.toml"
        "npl"              = "starship_nerdpowerline.toml"
        "p10k_rainbow"     = "starship_p10k_rainbow.toml"
        "p10kr"            = "starship_p10k_rainbow.toml"
        "p10k_classic"     = "starship_p10k_classic.toml"
        "p10kc"            = "starship_p10k_classic.toml"
        "p10k_lean"        = "starship_p10k_lean.toml"
        "p10kl"            = "starship_p10k_lean.toml"
    }
    foreach ($entry in $staticMappings.GetEnumerator()) {
        $fullPath = Join-Path $staticDir $entry.Value
        if (Test-Path $fullPath) {
            $script:starshipRegistry[$entry.Key] = $fullPath
        }
    }
    $script:starshipPool += (
        $staticMappings.Values | Select-Object -Unique | ForEach-Object {
            $p = Join-Path $staticDir $_
            if (Test-Path $p) { $p }
        }
    )
}

# ── Detect submodule/starshipauto (generated configs) ─────────────────────────
$_autoModule = "$profileRoot\submodule\starshipauto\engines\pwsh\starshipauto.psm1"
if (Test-Path $_autoModule) {
    Import-Module $_autoModule -Global -ArgumentList $profileRoot
    $autoConfigs = Get-StarshipAutoConfigs
    foreach ($entry in $autoConfigs.GetEnumerator()) {
        $script:starshipRegistry[$entry.Key] = $entry.Value
        $script:starshipPool += $entry.Value
    }
}

# ── Lock file ────────────────────────────────────────────────────────────────
$script:starshipLockFile = "$profileRoot\.starship_lock"

function script:Get-StarshipLockedConfig {
    if (Test-Path $script:starshipLockFile) {
        $key = (Get-Content $script:starshipLockFile -Raw).Trim()
        if ($key -and $script:starshipRegistry.ContainsKey($key)) {
            return $key
        }
    }
    return $null
}

# ── Config selection (locked or random) ──────────────────────────────────────
$lockedKey = Get-StarshipLockedConfig
if ($lockedKey) {
    $env:STARSHIP_CONFIG = $script:starshipRegistry[$lockedKey]
} else {
    $env:STARSHIP_CONFIG = Get-Random -InputObject $script:starshipPool
}

# ── Functions ─────────────────────────────────────────────────────────────────
function global:Get-CurrentStarshipConfigName {
    if (-not $env:STARSHIP_CONFIG) { return "default" }
    foreach ($entry in $script:starshipRegistry.GetEnumerator()) {
        if ($entry.Value -eq $env:STARSHIP_CONFIG -and $entry.Key.Length -gt 3) {
            return $entry.Key
        }
    }
    return [System.IO.Path]::GetFileNameWithoutExtension($env:STARSHIP_CONFIG)
}

function global:Show-StarshipUsage {
    $currentConfig = Get-CurrentStarshipConfigName
    $lockedConfig = Get-StarshipLockedConfig
    Write-Host "Switch-StarshipConfig (alias: ssc)" -ForegroundColor Cyan
    Write-Host "Current: $currentConfig" -ForegroundColor Cyan
    if ($lockedConfig) {
        Write-Host "Locked:  $lockedConfig" -ForegroundColor Magenta
    } else {
        Write-Host "Mode:    random" -ForegroundColor DarkGray
    }
    Write-Host ""
    Write-Host "Usage: ssc [-h] [-l] [-r] [-t <a|s> [index]] [--lock [cfg]] [--unlock] [Config]" -ForegroundColor Cyan
    Write-Host ""

    # Helper: group keys by path, show canonical (longest) + aliases
    function Format-ConfigGroup($registry) {
        $pathToKeys = @{}
        foreach ($entry in $registry.GetEnumerator()) {
            $path = $entry.Value
            if (-not $pathToKeys.ContainsKey($path)) { $pathToKeys[$path] = @() }
            $pathToKeys[$path] += $entry.Key
        }
        $pathToKeys.GetEnumerator() | Sort-Object { ($_.Value | Sort-Object { $_.Length } | Select-Object -Last 1) } | ForEach-Object {
            $keys = @($_.Value | Sort-Object { $_.Length })
            $canonical = $keys[-1]
            $aliases = ($keys | Where-Object { $_ -ne $canonical }) -join ', '
            $marker = if ($_.Key -eq $env:STARSHIP_CONFIG) { " *" } else { "" }
            $aliasStr = if ($aliases) { " ($aliases)" } else { "" }
            Write-Host "    ${canonical}${aliasStr}${marker}" -ForegroundColor Cyan
        }
    }

    # starshipauto generated configs
    if (Get-Module starshipauto) {
        $autoConfigs = Get-StarshipAutoConfigs
        $autoKeys = @($autoConfigs.Keys | Sort-Object)
        if ($autoKeys.Count -gt 0) {
            Write-Host "starshipauto (ssc -t a <index>):" -ForegroundColor Yellow
            for ($i = 0; $i -lt $autoKeys.Count; $i++) {
                $key = $autoKeys[$i]
                $marker = if ($autoConfigs[$key] -eq $env:STARSHIP_CONFIG) { " *" } else { "" }
                Write-Host ("    {0,2}  {1}{2}" -f ($i + 1), $key, $marker) -ForegroundColor Cyan
            }
            Write-Host ""
        }
    }

    # starship static configs (grouped by path)
    $autoValues = @()
    if (Get-Module starshipauto) {
        $autoValues = @((Get-StarshipAutoConfigs).Values)
    }
    $staticPathToKeys = [ordered]@{}
    foreach ($key in ($script:starshipRegistry.Keys | Sort-Object)) {
        $path = $script:starshipRegistry[$key]
        if ($path -and $autoValues -contains $path) { continue }
        if (-not $staticPathToKeys.Contains($path)) { $staticPathToKeys[$path] = @() }
        $staticPathToKeys[$path] += $key
    }
    if ($staticPathToKeys.Count -gt 0) {
        Write-Host "starship (ssc -t s <index>):" -ForegroundColor Yellow
        $idx = 0
        foreach ($path in $staticPathToKeys.Keys) {
            $idx++
            $keys = @($staticPathToKeys[$path] | Sort-Object { $_.Length })
            $label = $keys -join '|'
            $marker = if ($path -eq $env:STARSHIP_CONFIG) { " *" } else { "" }
            Write-Host ("    {0,2}  {1}{2}" -f $idx, $label, $marker) -ForegroundColor Cyan
        }
        Write-Host ""
    }

    Write-Host "Commands:" -ForegroundColor Yellow
    Write-Host "    --list,  -l            - List all config keys" -ForegroundColor Cyan
    Write-Host "    --type,  -t <a|s> [N]  - Filter by type: auto(a)/static(s), optional index" -ForegroundColor Cyan
    Write-Host "    --lock [Config]        - Lock current or specified config for all sessions" -ForegroundColor Cyan
    Write-Host "    --unlock               - Remove lock, restore random mode" -ForegroundColor Cyan
    if (Get-Module starshipauto) {
        Write-Host "    --rebuild, -r          - Regenerate starshipauto configs" -ForegroundColor Cyan
    }
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor Yellow
    Write-Host "    ssc ang_s              - Prefix match (pl_angled_sharp_*)" -ForegroundColor Cyan
    Write-Host "    ssc -t a               - List starshipauto configs with indices" -ForegroundColor Cyan
    Write-Host "    ssc -t a 3             - Switch to 3rd starshipauto config" -ForegroundColor Cyan
    Write-Host "    ssc --lock             - Lock current config" -ForegroundColor Cyan
    Write-Host "    ssc --lock pl_round    - Lock specified config (prefix match)" -ForegroundColor Cyan
    Write-Host "    ssc --unlock           - Unlock, next session uses random" -ForegroundColor Cyan
}

function global:Switch-StarshipConfig {
    param(
        [Parameter(Position = 0)]
        [string]$Config = "",
        [Alias("h")]
        [switch]$Help,
        [Alias("l")]
        [switch]$List,
        [Alias("r")]
        [switch]$Rebuild,
        [Alias("t")]
        [string]$Type = "",
        [switch]$Lock,
        [switch]$Unlock
    )

    # Handle -- style arguments passed as positional $Config
    if ($Config -in '--help', '-h') { $Help = $true; $Config = "" }
    if ($Config -in '--list', '-l') { $List = $true; $Config = "" }
    if ($Config -in '--rebuild', '-r') { $Rebuild = $true; $Config = "" }
    if ($Config -in '--type', '-t') { $Type = "auto"; $Config = "" }
    if ($Config -eq '--lock') { $Lock = $true; $Config = "" }
    if ($Config -eq '--unlock') { $Unlock = $true; $Config = "" }

    # Unlock: remove lock file
    if ($Unlock) {
        if (Test-Path $script:starshipLockFile) {
            Remove-Item $script:starshipLockFile -Force
            Write-Host "Unlocked. Next session will use random config." -ForegroundColor Green
        } else {
            Write-Host "No lock active." -ForegroundColor Yellow
        }
        return
    }

    # Lock: lock current or specified config
    if ($Lock) {
        $lockTarget = if ($Config) { $Config } else { Get-CurrentStarshipConfigName }
        # Resolve prefix if needed
        if (-not $script:starshipRegistry.ContainsKey($lockTarget)) {
            $matched = @($script:starshipRegistry.Keys | Where-Object { $_ -like "$lockTarget*" })
            if ($matched.Count -eq 1) { $lockTarget = $matched[0] }
            elseif ($matched.Count -gt 1) {
                Write-Host "Multiple matches for '$lockTarget':" -ForegroundColor Yellow
                $matched | Sort-Object | ForEach-Object { Write-Host "  $_" -ForegroundColor Cyan }
                return
            } else {
                Write-Warning "No match for '$lockTarget'."
                return
            }
        }
        Set-Content -Path $script:starshipLockFile -Value $lockTarget -NoNewline
        Write-Host "Locked: $lockTarget" -ForegroundColor Green
        return
    }

    if ($Help -or (-not $Config -and -not $List -and -not $Rebuild -and -not $Type)) {
        Show-StarshipUsage
        return
    }

    if ($Rebuild) {
        if (Get-Module starshipauto) {
            $success = Invoke-StarshipAutoBuild
            if ($success) {
                $autoConfigs = Get-StarshipAutoConfigs
                foreach ($entry in $autoConfigs.GetEnumerator()) {
                    $script:starshipRegistry[$entry.Key] = $entry.Value
                }
                Write-Host "Configs regenerated." -ForegroundColor Green
            }
        } else {
            Write-Warning "starshipauto module not loaded."
        }
        return
    }

    # Resolve type filter
    $filteredGroups = @()  # each group: @{ Keys=@(...); Path="..." }
    $filteredKeys = @()
    if ($Type) {
        $typeMap = @{ "a" = "auto"; "auto" = "auto"; "s" = "static"; "static" = "static" }
        $resolvedType = $typeMap[$Type]
        if (-not $resolvedType) {
            Write-Warning "Unknown type: '$Type'. Use 'auto'(a) or 'static'(s)."
            return
        }
        $autoConfigs = if (Get-Module starshipauto) { Get-StarshipAutoConfigs } else { @{} }
        if ($resolvedType -eq "auto") {
            $filteredKeys = @($autoConfigs.Keys | Sort-Object)
            $filteredGroups = @($filteredKeys | ForEach-Object { @{ Keys = @($_); Path = $autoConfigs[$_] } })
        } else {
            $pathToKeys = [ordered]@{}
            foreach ($key in ($script:starshipRegistry.Keys | Sort-Object)) {
                $path = $script:starshipRegistry[$key]
                if ($autoConfigs.ContainsKey($key)) { continue }
                if (-not $pathToKeys.Contains($path)) { $pathToKeys[$path] = @() }
                $pathToKeys[$path] += $key
            }
            foreach ($path in $pathToKeys.Keys) {
                $keys = @($pathToKeys[$path] | Sort-Object { $_.Length })
                $filteredGroups += @{ Keys = $keys; Path = $path }
                $filteredKeys += $keys
            }
        }
    }

    # Type + index mode: ssc -t a 3
    if ($Type -and $Config -match '^\d+$') {
        $idx = [int]$Config
        if ($idx -lt 1 -or $idx -gt $filteredGroups.Count) {
            Write-Warning "Index out of range (1-$($filteredGroups.Count))."
            return
        }
        $Config = $filteredGroups[$idx - 1].Keys[-1]
    }
    # Type + no config: list with indices
    elseif ($Type -and -not $Config) {
        $label = if ($resolvedType -eq 'auto') { "starshipauto" } else { "starship" }
        Write-Host "${label} configs:" -ForegroundColor Yellow
        for ($i = 0; $i -lt $filteredGroups.Count; $i++) {
            $g = $filteredGroups[$i]
            $keys = @($g.Keys | Sort-Object { $_.Length })
            $display = $keys -join '|'
            $marker = if ($g.Path -eq $env:STARSHIP_CONFIG) { " *" } else { "" }
            Write-Host ("  {0,2}  {1}{2}" -f ($i + 1), $display, $marker) -ForegroundColor Cyan
        }
        return
    }
    # Type + prefix: match within filtered set
    elseif ($Type -and $Config) {
        $matched = @($filteredKeys | Where-Object { $_ -like "$Config*" })
        if ($matched.Count -eq 1) {
            $Config = $matched[0]
        } elseif ($matched.Count -gt 1) {
            Write-Host "Multiple matches for '$Config':" -ForegroundColor Yellow
            $matched | ForEach-Object { Write-Host "  $_" -ForegroundColor Cyan }
            return
        } else {
            Write-Warning "No match for '$Config' in $($resolvedType) configs."
            return
        }
    }

    if ($List) {
        Write-Host "Available configs:" -ForegroundColor Yellow
        $script:starshipRegistry.Keys | Sort-Object | ForEach-Object {
            $marker = if ($script:starshipRegistry[$_] -eq $env:STARSHIP_CONFIG) { " *" } else { "" }
            Write-Host "  $_$marker" -ForegroundColor Cyan
        }
        return
    }

    # Prefix matching (no --type)
    if (-not $Type -and -not $script:starshipRegistry.ContainsKey($Config)) {
        $matched = @($script:starshipRegistry.Keys | Where-Object { $_ -like "$Config*" })
        if ($matched.Count -eq 1) {
            $Config = $matched[0]
        } elseif ($matched.Count -gt 1) {
            Write-Host "Multiple matches for '$Config':" -ForegroundColor Yellow
            $matched | Sort-Object | ForEach-Object { Write-Host "  $_" -ForegroundColor Cyan }
            return
        } else {
            Write-Warning "No match for '$Config'. Use 'ssc -l' to see available options."
            return
        }
    }

    $env:STARSHIP_CONFIG = $script:starshipRegistry[$Config]
    Invoke-Expression (&starship init powershell)
    Write-Host "Switched to: $(Get-CurrentStarshipConfigName)" -ForegroundColor Green
}

Set-Alias -Name ssc -Value Switch-StarshipConfig -Scope Global

# ── Tab completion ───────────────────────────────────────────────────────────
Register-ArgumentCompleter -CommandName Switch-StarshipConfig -ParameterName Config -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    $script:starshipRegistry.Keys | Where-Object { $_ -like "$wordToComplete*" } | Sort-Object | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

# ── Init ──────────────────────────────────────────────────────────────────────
Invoke-Expression (&starship init powershell)

function global:Invoke-Starship-TransientFunction {
    $cwd = (Get-Location).Path
    if ($cwd.StartsWith($HOME, [System.StringComparison]::OrdinalIgnoreCase)) {
        $cwd = '~' + $cwd.Substring($HOME.Length)
    }
    $cwd = $cwd.Replace('\', '/')
    $parts = $cwd.Split('/') | Where-Object { $_ -ne '' }

    if ($parts.Count -gt 1) {
        $truncated = $parts.Count -gt 4
        if ($truncated) { $parts = @($parts[-4..-1]) }
        $last = $parts[-1]
        $ancestors = foreach ($p in $parts[0..($parts.Count - 2)]) {
            if ($p.Length -le 1) { $p }
            elseif ($p -match '^[A-Za-z]:$') { $p }
            elseif ($p[0] -eq '.') { $p.Substring(0, [Math]::Min(2, $p.Length)) }
            else { $p[0] }
        }
        $cwd = ($truncated ? '…/' : '') + ($ancestors -join '/') + '/' + $last
    }

    $env:STARSHIP_TRANSIENT_DIR = $cwd
    $env:STARSHIP_TRANSIENT_TIME = Get-Date -Format 'HH:mm'
    $result = (&starship prompt --profile transient) -join "`n"
    Remove-Item Env:STARSHIP_TRANSIENT_DIR -ErrorAction SilentlyContinue
    Remove-Item Env:STARSHIP_TRANSIENT_TIME -ErrorAction SilentlyContinue
    $result
}

Enable-TransientPrompt
