[CmdletBinding()]
param(
    [ValidateSet('stable', 'latest')]
    [string]$Channel = 'stable',

    [string[]]$Install = @(),

    [string]$Proxy = '',

    [string]$GitHubProxy = '',

    [switch]$SkipClaude,

    [switch]$SkipCodex,

    [switch]$SkipHermes,

    [switch]$SkipCCSwitch,

    [switch]$DryRun,

    [switch]$NonInteractive,

    [switch]$SkipNetworkCheck,

    [switch]$Quiet,

    [switch]$NoProgress,

    [string]$LogFile = '',

    [switch]$DebugInstaller
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:ProgramName = 'AI CLI Installer Collector'
$script:ProgramVersion = '2.1.0'
$script:ClaudeInstallUrl = 'https://claude.ai/install.ps1'
$script:CodexInstallUrl = 'https://chatgpt.com/codex/install.ps1'
$script:HermesInstallUrl = 'https://hermes-agent.nousresearch.com/install.ps1'
$script:CCSwitchRepo = 'farion1231/cc-switch'
$script:GitHubApiUrl = "https://api.github.com/repos/$($script:CCSwitchRepo)/releases/latest"
$script:TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("ai-cli-installer-" + [guid]::NewGuid().ToString('N'))
$script:SelectedComponents = @()
$script:SuccessfulComponents = @()
$script:FailedComponents = @()
$script:SkippedComponents = @()
$script:FailureDetails = @()
$script:CurrentStep = 0
$script:TotalSteps = 1
$script:RunStarted = Get-Date
$script:UseDynamicProgress = (-not $NoProgress -and -not $Quiet -and -not $env:CI)
$script:ResolvedLogFile = $LogFile

function Initialize-InstallerLog {
    if ([string]::IsNullOrWhiteSpace($script:ResolvedLogFile)) {
        $logRoot = Join-Path $HOME '.ai-cli-installer\logs'
        $name = (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log'
        $script:ResolvedLogFile = Join-Path $logRoot $name
    }
    $directory = Split-Path -Parent $script:ResolvedLogFile
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    Set-Content -LiteralPath $script:ResolvedLogFile -Value '' -Encoding UTF8
    Write-InstallerLog -Level 'INFO' -Message "$($script:ProgramName) v$($script:ProgramVersion)"
}

function Write-InstallerLog {
    param(
        [Parameter(Mandatory = $true)][string]$Level,
        [Parameter(Mandatory = $true)][string]$Message
    )
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -LiteralPath $script:ResolvedLogFile -Value $line -Encoding UTF8
}

function Write-InstallerMessage {
    param(
        [Parameter(Mandatory = $true)][string]$Level,
        [Parameter(Mandatory = $true)][string]$Message,
        [switch]$Always
    )
    Write-InstallerLog -Level $Level -Message $Message
    if ($Quiet -and -not $Always -and $Level -notin @('WARN', 'ERROR', 'SUMMARY')) {
        return
    }
    switch ($Level) {
        'WARN' { Write-Warning $Message }
        'ERROR' { Write-Host "[ERROR] $Message" -ForegroundColor Red }
        'DEBUG' { Write-Host "[DEBUG] $Message" -ForegroundColor DarkGray }
        'PROGRESS' { Write-Host "[PROGRESS] $Message" -ForegroundColor Cyan }
        default { Write-Host "[$Level] $Message" }
    }
}

function Write-Info([string]$Message) { Write-InstallerMessage -Level 'INFO' -Message $Message }
function Write-Warn([string]$Message) { Write-InstallerMessage -Level 'WARN' -Message $Message -Always }
function Write-ErrorMessage([string]$Message) { Write-InstallerMessage -Level 'ERROR' -Message $Message -Always }
function Write-DebugMessage([string]$Message) {
    if ($DebugInstaller) { Write-InstallerMessage -Level 'DEBUG' -Message $Message }
}

function Show-InstallerProgress {
    param([Parameter(Mandatory = $true)][string]$Message)
    $script:CurrentStep++
    if ($script:CurrentStep -gt $script:TotalSteps) { $script:CurrentStep = $script:TotalSteps }
    $percent = [int](($script:CurrentStep * 100) / $script:TotalSteps)
    Write-InstallerLog -Level 'PROGRESS' -Message "${percent}% $Message"
    if ($Quiet) { return }
    if ($script:UseDynamicProgress) {
        Write-Progress -Activity $script:ProgramName -Status $Message -PercentComplete $percent
    }
    else {
        Write-InstallerMessage -Level 'PROGRESS' -Message "${percent}% $Message"
    }
}

function Complete-InstallerProgress {
    if ($script:UseDynamicProgress) {
        Write-Progress -Activity $script:ProgramName -Completed
    }
}

function Get-ComponentLabel([string]$Component) {
    switch ($Component) {
        'claude' { return 'Claude Code' }
        'codex' { return 'Codex CLI' }
        'hermes' { return 'Hermes Agent' }
        'cc-switch' { return 'CC Switch' }
        default { return $Component }
    }
}

function Add-SelectedComponent([string]$Component) {
    if ($script:SelectedComponents -notcontains $Component) {
        $script:SelectedComponents += $Component
    }
}

function Convert-SelectionToken([string]$Token) {
    $value = $Token.Trim().ToLowerInvariant()
    switch ($value) {
        { $_ -in @('1', 'claude', 'claude-code', 'claudecode') } { return 'claude' }
        { $_ -in @('2', 'codex', 'codex-cli', 'codexcli') } { return 'codex' }
        { $_ -in @('3', 'hermes', 'hermes-agent', 'hermesagent') } { return 'hermes' }
        { $_ -in @('4', 'cc-switch', 'ccswitch', 'cc_switch') } { return 'cc-switch' }
        { $_ -in @('5', 'all', '*') } { return 'all' }
        { $_ -in @('0', 'exit', 'quit', 'q') } { return 'exit' }
        '' { return '' }
        default { throw "未知组件: $Token。可选 claude、codex、hermes、cc-switch、all" }
    }
}

function Add-Selection([string]$RawSelection) {
    $tokens = $RawSelection -split '[,\s]+' | Where-Object { $_ }
    foreach ($token in $tokens) {
        $normalized = Convert-SelectionToken $token
        switch ($normalized) {
            '' { }
            'exit' { throw [System.OperationCanceledException]::new('用户取消安装') }
            'all' {
                Add-SelectedComponent 'claude'
                Add-SelectedComponent 'codex'
                Add-SelectedComponent 'hermes'
                Add-SelectedComponent 'cc-switch'
            }
            default { Add-SelectedComponent $normalized }
        }
    }
}

function Resolve-Selection {
    if ($Install.Count -gt 0) {
        Add-Selection ($Install -join ',')
    }
    elseif (-not $NonInteractive -and [Environment]::UserInteractive) {
        Write-Host ''
        Write-Host '请选择要安装的组件（可多选，例如 1,3,4）：'
        Write-Host '  1) Claude Code'
        Write-Host '  2) OpenAI Codex CLI'
        Write-Host '  3) Nous Research Hermes Agent'
        Write-Host '  4) CC Switch'
        Write-Host '  5) 全部安装'
        Write-Host '  0) 退出'
        Add-Selection (Read-Host '请输入选择')
    }
    else {
        Add-Selection 'claude,cc-switch'
        Write-Info '未检测到交互终端，使用兼容默认选择: Claude Code + CC Switch'
    }

    $filtered = @()
    foreach ($component in $script:SelectedComponents) {
        $skip = ($component -eq 'claude' -and $SkipClaude) -or
                ($component -eq 'codex' -and $SkipCodex) -or
                ($component -eq 'hermes' -and $SkipHermes) -or
                ($component -eq 'cc-switch' -and $SkipCCSwitch)
        if ($skip) { $script:SkippedComponents += (Get-ComponentLabel $component) }
        else { $filtered += $component }
    }
    $script:SelectedComponents = $filtered
    if ($script:SelectedComponents.Count -eq 0) { throw '没有可安装组件' }
}

function Get-RedactedUrl([string]$Url) {
    return ($Url -replace '://[^/@]+@', '://***@')
}

function Get-WebParameters {
    $parameters = @{
        UseBasicParsing = $true
        Headers = @{ 'User-Agent' = "ai-cli-installer/$($script:ProgramVersion)" }
        TimeoutSec = 1800
    }
    if ($Proxy) { $parameters['Proxy'] = $Proxy }
    return $parameters
}

function Invoke-LoggedCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Description,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )
    Write-Info $Description
    Write-InstallerLog -Level 'COMMAND' -Message $Description
    if ($DryRun) {
        Write-Info "Dry-run: $Description"
        return
    }
    if ($Quiet) {
        & $Action *>> $script:ResolvedLogFile
    }
    else {
        & $Action *>&1 | Tee-Object -FilePath $script:ResolvedLogFile -Append
    }
}

function Invoke-Download {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$OutFile,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $safeUri = Get-RedactedUrl $Uri
    Write-Info "下载 ${Label}: $safeUri"
    Write-InstallerLog -Level 'DOWNLOAD' -Message "url=$safeUri destination=$OutFile"
    if ($DryRun) { return }
    New-Item -ItemType Directory -Path (Split-Path -Parent $OutFile) -Force | Out-Null
    $parameters = Get-WebParameters
    $parameters['Uri'] = $Uri
    $parameters['OutFile'] = $OutFile
    $lastError = $null
    for ($attempt = 1; $attempt -le 4; $attempt++) {
        try {
            if ($script:UseDynamicProgress) {
                Write-Progress -Activity "下载 $Label" -Status "尝试 $attempt/4" -PercentComplete ([Math]::Min(95, $attempt * 20))
            }
            Invoke-WebRequest @parameters | Out-Null
            if ($script:UseDynamicProgress) { Write-Progress -Activity "下载 $Label" -Completed }
            return
        }
        catch {
            $lastError = $_
            Write-Warn "下载失败（第 $attempt/4 次）: $($_.Exception.Message)"
            if ($attempt -lt 4) { Start-Sleep -Seconds ([Math]::Min(8, $attempt * 2)) }
        }
    }
    throw "下载 $Label 失败: $($lastError.Exception.Message)"
}

function Write-FileMetadata {
    param([string]$Path, [string]$Label)
    if ($DryRun) {
        Write-Info "${Label}: Dry-run，跳过本地 SHA-256 计算"
        return
    }
    if (-not (Test-Path -LiteralPath $Path)) { throw "文件不存在: $Path" }
    $item = Get-Item -LiteralPath $Path
    $hash = Get-FileHash -LiteralPath $Path -Algorithm SHA256
    Write-Info "${Label}: 大小 $($item.Length) bytes；本地 SHA-256 $($hash.Hash)"
    Write-InstallerLog -Level 'ARTIFACT' -Message "label=$Label path=$Path size=$($item.Length) SHA256=$($hash.Hash)"
}

function Test-ServiceEndpoint([string]$Label, [string]$Uri) {
    if ($SkipNetworkCheck -or $DryRun) { return }
    try {
        $parameters = Get-WebParameters
        $parameters['Uri'] = $Uri
        $parameters['Method'] = 'Head'
        $parameters['TimeoutSec'] = 20
        Invoke-WebRequest @parameters | Out-Null
        Write-Info "网络检查通过: $Label"
    }
    catch {
        Write-Warn "无法访问 ${Label}: $Uri；安装阶段仍会按重试策略继续"
    }
}

function Invoke-NetworkChecks {
    if ($SkipNetworkCheck -or $DryRun) {
        Write-Info '已跳过网络预检'
        return
    }
    if ($script:SelectedComponents -contains 'claude') { Test-ServiceEndpoint 'Claude' 'https://claude.ai' }
    if ($script:SelectedComponents -contains 'codex') { Test-ServiceEndpoint 'Codex' 'https://chatgpt.com' }
    if ($script:SelectedComponents -contains 'hermes') { Test-ServiceEndpoint 'Hermes' 'https://hermes-agent.nousresearch.com' }
    if ($script:SelectedComponents -contains 'cc-switch') { Test-ServiceEndpoint 'GitHub API' 'https://api.github.com' }
}

function Show-Stage([string]$Component, [string]$Message) {
    Show-InstallerProgress "$Component`: $Message"
}

function Test-InstalledCommand([string]$CommandName, [string]$Label) {
    if ($DryRun) { Write-Info "${Label}: Dry-run 验证通过"; return }
    $command = Get-Command $CommandName -ErrorAction SilentlyContinue
    if ($command) {
        $version = & $CommandName --version 2>&1 | Select-Object -First 1
        Write-Info "${Label}: 已检测到 $version"
    }
    else {
        Write-Warn "${Label}: 当前 PowerShell 尚未找到 $CommandName，通常重新打开终端后生效"
    }
}

function Install-ScriptComponent {
    param(
        [string]$Component,
        [string]$Label,
        [string]$Source,
        [string]$Url,
        [string]$InstallerPath
    )
    Show-Stage $Label '准备官方安装源'
    Write-Info "$Label 来源: $Source ($Url)"
    if ($env:INSTALLER_TEST_FAIL_COMPONENT -eq $Component) { throw "$Label 测试注入失败" }

    Show-Stage $Label '下载官方安装器'
    Invoke-Download -Uri $Url -OutFile $InstallerPath -Label "$Label 安装器"

    Show-Stage $Label '记录安装器信息'
    Write-FileMetadata -Path $InstallerPath -Label "$Label 安装器"

    Show-Stage $Label '执行安装'
    Invoke-LoggedCommand -Description "执行 $Label 官方安装器" -Action {
        if ($Component -eq 'claude') {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $InstallerPath $Channel
        }
        else {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $InstallerPath
        }
        if ($LASTEXITCODE -ne 0) { throw "$Label 安装器退出码: $LASTEXITCODE" }
    }

    Show-Stage $Label '验证安装结果'
    Test-InstalledCommand -CommandName $Component -Label $Label
}

function Get-CCSwitchAsset {
    $architecture = if ($env:INSTALLER_TEST_ARCH) { $env:INSTALLER_TEST_ARCH } elseif ($env:PROCESSOR_ARCHITECTURE) { $env:PROCESSOR_ARCHITECTURE } else { 'AMD64' }
    $architecture = if ($architecture -match 'ARM64|AARCH64') { 'arm64' } else { 'x86_64' }
    if ($DryRun) {
        return [pscustomobject]@{
            Name = "CC-Switch-LATEST-Windows-$architecture.msi"
            Url = "https://github.com/$($script:CCSwitchRepo)/releases/latest/download/CC-Switch-LATEST-Windows-$architecture.msi"
        }
    }
    $parameters = Get-WebParameters
    $parameters['Uri'] = $script:GitHubApiUrl
    Write-Info "下载 CC Switch Release metadata: $($script:GitHubApiUrl)"
    $release = Invoke-RestMethod @parameters
    $asset = $release.assets | Where-Object { $_.name -match "Windows.*$architecture.*\.msi$|$architecture.*Windows.*\.msi$" } | Select-Object -First 1
    if (-not $asset) {
        $asset = $release.assets | Where-Object { $_.name -match '\.msi$' -and $_.name -match $architecture } | Select-Object -First 1
    }
    if (-not $asset) { throw "未找到 Windows $architecture MSI" }
    if ($asset.browser_download_url -notmatch '^https://(github\.com|objects\.githubusercontent\.com|github-releases\.githubusercontent\.com)/') {
        throw "Release 返回了非 GitHub 地址: $($asset.browser_download_url)"
    }
    return [pscustomobject]@{ Name = $asset.name; Url = $asset.browser_download_url }
}

function Apply-GitHubProxy([string]$Url) {
    if ([string]::IsNullOrWhiteSpace($GitHubProxy)) { return $Url }
    return $GitHubProxy.TrimEnd('/') + '/' + $Url
}

function Install-CCSwitch {
    $label = 'CC Switch'
    Show-Stage $label '获取官方 Release 信息'
    Write-Info "$label 来源: $($script:CCSwitchRepo) 官方 GitHub Releases"
    if ($env:INSTALLER_TEST_FAIL_COMPONENT -eq 'cc-switch') { throw "$label 测试注入失败" }
    $asset = Get-CCSwitchAsset
    $msiPath = Join-Path $script:TempRoot $asset.Name

    Show-Stage $label '下载 MSI 安装包'
    Invoke-Download -Uri (Apply-GitHubProxy $asset.Url) -OutFile $msiPath -Label 'CC Switch MSI'

    Show-Stage $label '记录安装包信息'
    Write-FileMetadata -Path $msiPath -Label 'CC Switch MSI'

    Show-Stage $label '安装 MSI'
    Invoke-LoggedCommand -Description '使用 Windows Installer 安装 CC Switch' -Action {
        $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/i', "`"$msiPath`"", '/qn', '/norestart') -Wait -PassThru
        $ExitCode = $process.ExitCode
        Write-InstallerLog -Level 'MSI' -Message "ExitCode=$ExitCode"
        if ($ExitCode -notin @(0, 3010)) { throw "msiexec.exe 退出码: $ExitCode" }
        if ($ExitCode -eq 3010) { Write-Warn 'CC Switch 安装完成，需要重启 Windows' }
    }

    Show-Stage $label '验证安装结果'
    if ($DryRun) { Write-Info 'CC Switch: Dry-run 验证通过' }
    else { Write-Info 'CC Switch 安装流程完成，请从开始菜单启动' }
}

function Invoke-Component([string]$Component) {
    switch ($Component) {
        'claude' { Install-ScriptComponent -Component 'claude' -Label 'Claude Code' -Source 'Anthropic 官方安装器' -Url $script:ClaudeInstallUrl -InstallerPath (Join-Path $script:TempRoot 'claude-install.ps1') }
        'codex' { Install-ScriptComponent -Component 'codex' -Label 'Codex CLI' -Source 'OpenAI 官方安装器' -Url $script:CodexInstallUrl -InstallerPath (Join-Path $script:TempRoot 'codex-install.ps1') }
        'hermes' { Install-ScriptComponent -Component 'hermes' -Label 'Hermes Agent' -Source 'Nous Research 官方安装器' -Url $script:HermesInstallUrl -InstallerPath (Join-Path $script:TempRoot 'hermes-install.ps1') }
        'cc-switch' { Install-CCSwitch }
        default { throw "未知组件: $Component" }
    }
}

function Invoke-ComponentSafely([string]$Component) {
    $label = Get-ComponentLabel $Component
    $before = $script:CurrentStep
    Write-Info "========== $label =========="
    try {
        Invoke-Component $Component
        $script:SuccessfulComponents += $label
        Write-Info "$label`: 成功"
    }
    catch {
        $script:FailedComponents += $label
        $script:FailureDetails += "$label`: $($_.Exception.Message)"
        Write-Warn "$label`: 失败，继续处理其他组件。$($_.Exception.Message)"
    }
    $completed = $script:CurrentStep - $before
    while ($completed -lt 5) {
        Show-InstallerProgress "$label`: 因失败跳过后续阶段"
        $completed++
    }
}

function Write-Summary {
    Complete-InstallerProgress
    $elapsed = [int]((Get-Date) - $script:RunStarted).TotalSeconds
    Write-InstallerMessage -Level 'SUMMARY' -Message '========== 安装汇总 ==========' -Always
    if ($script:SuccessfulComponents.Count -gt 0) { Write-InstallerMessage -Level 'SUMMARY' -Message ("成功: " + ($script:SuccessfulComponents -join ', ')) -Always }
    if ($script:SkippedComponents.Count -gt 0) { Write-InstallerMessage -Level 'SUMMARY' -Message ("跳过: " + ($script:SkippedComponents -join ', ')) -Always }
    if ($script:FailedComponents.Count -gt 0) { Write-Warn ("失败: " + ($script:FailedComponents -join ', ')) }
    Write-InstallerMessage -Level 'SUMMARY' -Message "耗时: ${elapsed}s" -Always
    Write-InstallerMessage -Level 'SUMMARY' -Message "日志: $($script:ResolvedLogFile)" -Always
}

$exitCode = 0
try {
    Initialize-InstallerLog
    if (-not $Quiet) {
        Write-Host "[INFO] $($script:ProgramName) v$($script:ProgramVersion)"
        Write-Host '[INFO] 官方源安装；不绕过地区、账号或服务条款限制'
    }
    Resolve-Selection
    $script:TotalSteps = 2 + ($script:SelectedComponents.Count * 5) + 1
    New-Item -ItemType Directory -Path $script:TempRoot -Force | Out-Null

    Show-InstallerProgress '检测 Windows 与 CPU 架构'
    $arch = if ($env:PROCESSOR_ARCHITECTURE) { $env:PROCESSOR_ARCHITECTURE } else { 'unknown' }
    Write-Info "检测到: OS=windows ARCH=$arch"
    Write-InstallerLog -Level 'CONTEXT' -Message "OS=windows ARCH=$arch selected=$($script:SelectedComponents -join ',') dry_run=$DryRun non_interactive=$NonInteractive"
    Write-DebugMessage "temp_dir=$($script:TempRoot) dynamic_progress=$($script:UseDynamicProgress) proxy_enabled=$(-not [string]::IsNullOrWhiteSpace($Proxy))"
    if ($GitHubProxy) { Write-Warn '已启用用户指定的 GitHub 下载前缀，请确认该服务可信' }

    Show-InstallerProgress '检查所选官方服务的网络连通性'
    Invoke-NetworkChecks
    foreach ($component in $script:SelectedComponents) { Invoke-ComponentSafely $component }
    Show-InstallerProgress '生成安装汇总'
    if ($script:FailedComponents.Count -gt 0) { $exitCode = 1 }
}
catch [System.OperationCanceledException] {
    $exitCode = 0
    if ($script:ResolvedLogFile) { Write-InstallerLog -Level 'INFO' -Message '用户取消安装' }
}
catch {
    $exitCode = 2
    if ($script:ResolvedLogFile) { Write-ErrorMessage $_.Exception.Message }
    else { Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red }
}
finally {
    if ($script:ResolvedLogFile) { Write-Summary }
    if ((Test-Path -LiteralPath $script:TempRoot) -and -not $DebugInstaller) {
        Remove-Item -LiteralPath $script:TempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($exitCode -ne 0) {
    $global:LASTEXITCODE = $exitCode
    if ($PSCommandPath) { exit $exitCode }
    throw "安装集合器完成，但存在失败项。ExitCode=$exitCode"
}
