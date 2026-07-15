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

    [string]$LogFile = '',

    [switch]$NoProgress,

    [switch]$Quiet,

    [switch]$DryRun,

    [switch]$NonInteractive,

    [switch]$SkipNetworkCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ProgramName = 'AI CLI Installer Collector'
$script:ProgramVersion = '3.0.0'
$script:ClaudeInstallUrl = 'https://claude.ai/install.ps1'
$script:CodexInstallUrl = 'https://chatgpt.com/codex/install.ps1'
$script:HermesInstallUrl = 'https://hermes-agent.nousresearch.com/install.ps1'
$script:CCSwitchRepo = 'farion1231/cc-switch'
$script:GitHubApiUrl = "https://api.github.com/repos/$($script:CCSwitchRepo)/releases/latest"
$script:TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("ai-cli-installer-" + [guid]::NewGuid().ToString('N'))
$script:SelectedComponents = @()
$script:SuccessfulComponents = @()
$script:FailedComponents = @()
$script:FailedDetails = @()
$script:SkippedComponents = @()
$script:TotalSteps = 0
$script:CompletedSteps = 0
$script:CurrentComponent = ''
$script:CurrentStage = ''
$script:CurrentComponentStage = 0
$script:LogEnabled = $false
$script:LogFilePath = $LogFile
$script:StartTime = Get-Date

function Protect-InstallerText {
    param([string]$Text)
    if ($null -eq $Text) { return '' }
    $clean = [regex]::Replace($Text, '(https?://)[^/@\s]+@', '$1***@')
    $clean = [regex]::Replace($clean, '(?i)(Authorization:\s*(Bearer|Basic))\s+\S+', '$1 ***')
    $clean = [regex]::Replace($clean, '(?i)((ANTHROPIC_AUTH_TOKEN|OPENAI_API_KEY|NOUS_API_KEY)=)\S+', '$1[REDACTED]')
    return $clean
}

function Write-InstallerLog {
    param(
        [string]$Level,
        [string]$Message
    )
    if (-not $script:LogEnabled) { return }
    $clean = Protect-InstallerText $Message
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $clean
    Add-Content -LiteralPath $script:LogFilePath -Value $line -Encoding UTF8
}

function Write-InstallerMessage {
    param(
        [string]$Level,
        [string]$Message
    )
    $clean = Protect-InstallerText $Message
    Write-InstallerLog -Level $Level -Message $clean
    if ($Quiet -and $Level -notin @('WARN', 'ERROR', 'SUMMARY')) { return }
    $prefix = switch ($Level) {
        'INFO' { '[INFO]' }
        'STEP' { '[STEP]' }
        'OK' { '[ OK ]' }
        'WARN' { '[WARN]' }
        'ERROR' { '[ERROR]' }
        'PROGRESS' { '[PROGRESS]' }
        'SUMMARY' { '[SUMMARY]' }
        default { "[$Level]" }
    }
    if ($Level -eq 'WARN') {
        Write-Warning $clean
    }
    elseif ($Level -eq 'ERROR') {
        Write-Host "$prefix $clean" -ForegroundColor Red
    }
    elseif ($Level -eq 'OK') {
        Write-Host "$prefix $clean" -ForegroundColor Green
    }
    else {
        Write-Host "$prefix $clean"
    }
}

function Initialize-InstallerLog {
    if ($DryRun -and [string]::IsNullOrWhiteSpace($script:LogFilePath)) {
        $script:LogEnabled = $false
        return
    }
    if ([string]::IsNullOrWhiteSpace($script:LogFilePath)) {
        $root = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'ai-cli-installer\logs' } else { Join-Path $env:TEMP 'ai-cli-installer\logs' }
        $script:LogFilePath = Join-Path $root ("install-{0}-{1}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $PID)
    }
    $parent = Split-Path -Parent $script:LogFilePath
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    Set-Content -LiteralPath $script:LogFilePath -Value '' -Encoding UTF8
    $script:LogEnabled = $true
    Write-InstallerLog -Level INFO -Message "$($script:ProgramName) v$($script:ProgramVersion) started"
}

function Get-ComponentLabel {
    param([string]$Component)
    switch ($Component) {
        'claude' { return 'Claude Code' }
        'codex' { return 'Codex CLI' }
        'hermes' { return 'Hermes Agent' }
        'cc-switch' { return 'CC Switch' }
        default { return $Component }
    }
}

function Add-SelectedComponent {
    param([string]$Component)
    if ($script:SelectedComponents -notcontains $Component) {
        $script:SelectedComponents += $Component
    }
}

function Add-SelectionToken {
    param([string]$Token)
    $normalized = $Token.Trim().ToLowerInvariant()
    switch ($normalized) {
        { $_ -in @('1', 'claude', 'claude-code', 'claudecode') } { Add-SelectedComponent 'claude'; break }
        { $_ -in @('2', 'codex', 'codex-cli', 'codexcli') } { Add-SelectedComponent 'codex'; break }
        { $_ -in @('3', 'hermes', 'hermes-agent', 'hermesagent') } { Add-SelectedComponent 'hermes'; break }
        { $_ -in @('4', 'cc-switch', 'ccswitch', 'cc_switch') } { Add-SelectedComponent 'cc-switch'; break }
        { $_ -in @('5', 'all', '*') } {
            foreach ($component in @('claude', 'codex', 'hermes', 'cc-switch')) { Add-SelectedComponent $component }
            break
        }
        { $_ -in @('0', 'exit', 'quit', 'q') } { exit 0 }
        '' { break }
        default { throw "未知组件: $normalized。可选 claude、codex、hermes、cc-switch、all" }
    }
}

function Resolve-InstallerSelection {
    $tokens = @()
    if ($Install.Count -gt 0) {
        foreach ($value in $Install) { $tokens += ($value -split '[,\s]+') }
    }
    elseif (-not $NonInteractive -and -not $env:CI) {
        Write-Host ''
        Write-Host '请选择要安装的组件（可多选，例如 1,3,4）：'
        Write-Host '  1) Claude Code'
        Write-Host '  2) OpenAI Codex CLI'
        Write-Host '  3) Nous Research Hermes Agent'
        Write-Host '  4) CC Switch'
        Write-Host '  5) 全部安装'
        Write-Host '  0) 退出'
        $tokens = (Read-Host '请输入选择') -split '[,\s]+'
    }
    else {
        $tokens = @('claude', 'cc-switch')
        Write-InstallerMessage INFO '未检测到交互终端，使用兼容默认选择: Claude Code + CC Switch'
    }
    foreach ($token in $tokens) { Add-SelectionToken $token }

    $filtered = @()
    foreach ($component in $script:SelectedComponents) {
        if ($component -eq 'claude' -and $SkipClaude) { $script:SkippedComponents += 'Claude Code'; continue }
        if ($component -eq 'codex' -and $SkipCodex) { $script:SkippedComponents += 'Codex CLI'; continue }
        if ($component -eq 'hermes' -and $SkipHermes) { $script:SkippedComponents += 'Hermes Agent'; continue }
        if ($component -eq 'cc-switch' -and $SkipCCSwitch) { $script:SkippedComponents += 'CC Switch'; continue }
        $filtered += $component
    }
    $script:SelectedComponents = $filtered
    if ($script:SelectedComponents.Count -eq 0) { throw '没有可安装组件，请使用 -Install 选择至少一项' }
    $script:TotalSteps = $script:SelectedComponents.Count * 4
}

function Show-InstallerProgress {
    param(
        [string]$Status,
        [string]$Detail
    )
    $percent = if ($script:TotalSteps -gt 0) { [int](($script:CompletedSteps * 100) / $script:TotalSteps) } else { 100 }
    $message = '{0}% {1} {2} / {3}' -f $percent, $Status, $script:CurrentComponent, $script:CurrentStage
    if ($Detail) { $message += " - $Detail" }
    Write-InstallerLog -Level PROGRESS -Message $message
    if (-not $Quiet) {
        Write-InstallerMessage PROGRESS $message
        if (-not $NoProgress -and -not $env:CI) {
            Write-Progress -Activity $script:ProgramName -Status $message -PercentComplete $percent
        }
    }
}

function Start-InstallerStage {
    param([string]$Stage, [string]$Detail)
    $script:CurrentStage = $Stage
    $script:CurrentComponentStage++
    Write-InstallerMessage STEP "$($script:CurrentComponent) · $Stage`: $Detail"
}

function Complete-InstallerStage {
    param([string]$Detail)
    $script:CompletedSteps++
    Show-InstallerProgress -Status 'OK' -Detail $Detail
}

function Warn-InstallerStage {
    param([string]$Detail)
    $script:CompletedSteps++
    Show-InstallerProgress -Status 'WARN' -Detail $Detail
}

function Fail-InstallerStage {
    param([int]$ExitCode, [string]$Detail)
    $script:CompletedSteps++
    Show-InstallerProgress -Status 'FAIL' -Detail "$Detail（退出码 $ExitCode）"
    while ($script:CurrentComponentStage -lt 4) {
        $script:CurrentComponentStage++
        $script:CompletedSteps++
        $script:CurrentStage = '后续阶段'
        Show-InstallerProgress -Status 'SKIP' -Detail '因前序失败跳过'
    }
}

function Test-InjectedFailure {
    param([string]$Component)
    if ($env:INSTALLER_TEST_FAIL_COMPONENT -eq $Component) {
        throw "测试注入失败: $(Get-ComponentLabel $Component)"
    }
}

function Invoke-WebDownload {
    param([string]$Uri, [string]$Destination, [string]$Purpose = 'file')
    Write-InstallerMessage INFO "下载（$Purpose）: $Uri"
    if ($DryRun) { return }
    $oldProgress = $ProgressPreference
    try {
        if ($NoProgress -or $Quiet -or $env:CI) { $ProgressPreference = 'SilentlyContinue' } else { $ProgressPreference = 'Continue' }
        $parameters = @{
            Uri = $Uri
            OutFile = $Destination
            UseBasicParsing = $true
            ErrorAction = 'Stop'
            Headers = @{ 'User-Agent' = "ai-cli-installer/$($script:ProgramVersion)" }
        }
        if ($Proxy) { $parameters['Proxy'] = $Proxy }
        Invoke-WebRequest @parameters
    }
    finally {
        $ProgressPreference = $oldProgress
    }
}

function Test-InstallerNetwork {
    if ($SkipNetworkCheck -or $DryRun) { return }
    Write-InstallerMessage INFO '检查所选组件的网络连通性'
    $urls = @()
    if ($script:SelectedComponents -contains 'claude') { $urls += 'https://claude.ai' }
    if ($script:SelectedComponents -contains 'codex') { $urls += 'https://chatgpt.com' }
    if ($script:SelectedComponents -contains 'hermes') { $urls += 'https://hermes-agent.nousresearch.com' }
    if ($script:SelectedComponents -contains 'cc-switch') { $urls += 'https://api.github.com' }
    foreach ($url in $urls) {
        try {
            $parameters = @{ Uri = $url; Method = 'Head'; UseBasicParsing = $true; TimeoutSec = 15; ErrorAction = 'Stop' }
            if ($Proxy) { $parameters['Proxy'] = $Proxy }
            Invoke-WebRequest @parameters | Out-Null
        }
        catch {
            Write-InstallerMessage WARN "无法访问 $url；可使用 -Proxy，GitHub 下载还可使用 -GitHubProxy"
        }
    }
}

function Invoke-ScriptInstaller {
    param(
        [string]$Component,
        [string]$Label,
        [string]$Uri,
        [string]$VerifyCommand,
        [string[]]$Arguments = @()
    )
    $installer = Join-Path $script:TempRoot "$Component-install.ps1"
    Start-InstallerStage '准备' '确认官方安装源'
    Test-InjectedFailure $Component
    Complete-InstallerStage "官方源: $Uri"

    Start-InstallerStage '下载' '获取官方安装器'
    Invoke-WebDownload -Uri $Uri -Destination $installer -Purpose 'installer'
    Complete-InstallerStage '安装器已准备'

    Start-InstallerStage '安装' '运行官方安装器'
    if ($DryRun) {
        Write-InstallerMessage INFO "计划执行: PowerShell -File $installer $($Arguments -join ' ')"
        Complete-InstallerStage 'dry-run：未修改系统'
    }
    else {
        $engine = (Get-Process -Id $PID).Path
        & $engine -NoProfile -ExecutionPolicy Bypass -File $installer @Arguments
        if ($LASTEXITCODE -ne 0) { throw "官方安装器退出码 $LASTEXITCODE" }
        Complete-InstallerStage '官方安装器执行完成'
    }

    Start-InstallerStage '验证' "检查 $VerifyCommand 命令"
    if ($DryRun) {
        Complete-InstallerStage "dry-run：计划验证 $VerifyCommand"
    }
    elseif (Get-Command $VerifyCommand -ErrorAction SilentlyContinue) {
        Complete-InstallerStage "已检测到 $VerifyCommand"
    }
    else {
        Warn-InstallerStage "当前终端尚未找到 $VerifyCommand，请重新打开终端后检查"
    }
}

function Get-CCSwitchAssetUrl {
    if ($DryRun) { return 'https://github.com/farion1231/cc-switch/releases/latest/download/CC-Switch-LATEST-Windows.msi' }
    $parameters = @{ Uri = $script:GitHubApiUrl; UseBasicParsing = $true; ErrorAction = 'Stop'; Headers = @{ 'User-Agent' = "ai-cli-installer/$($script:ProgramVersion)" } }
    if ($Proxy) { $parameters['Proxy'] = $Proxy }
    $release = Invoke-RestMethod @parameters
    $arm = $env:PROCESSOR_ARCHITECTURE -eq 'ARM64'
    $asset = $release.assets | Where-Object {
        $_.name -match 'CC-Switch-v.*-Windows.*\.msi$' -and (($arm -and $_.name -match 'arm64') -or (-not $arm -and $_.name -notmatch 'arm64'))
    } | Select-Object -First 1
    if (-not $asset) { throw '未找到匹配的 CC Switch Windows MSI' }
    if ($asset.browser_download_url -notmatch '^https://(github\.com|objects\.githubusercontent\.com|github-releases\.githubusercontent\.com)/') {
        throw 'Release 返回了非 GitHub 下载地址，已拒绝'
    }
    return [string]$asset.browser_download_url
}

function Invoke-CCSwitchInstaller {
    Start-InstallerStage '准备' '读取官方 GitHub Release'
    Test-InjectedFailure 'cc-switch'
    $url = Get-CCSwitchAssetUrl
    Complete-InstallerStage "官方安装包: $url"

    Start-InstallerStage '下载' '获取 CC Switch MSI'
    $downloadUrl = if ($GitHubProxy) { $GitHubProxy.TrimEnd('/') + '/' + $url } else { $url }
    $msiPath = Join-Path $script:TempRoot 'cc-switch.msi'
    Invoke-WebDownload -Uri $downloadUrl -Destination $msiPath -Purpose 'package'
    Complete-InstallerStage 'MSI 已准备'

    Start-InstallerStage '安装' '运行 Windows Installer'
    if ($DryRun) {
        Write-InstallerMessage INFO "计划执行: msiexec.exe /i `"$msiPath`" /passive /norestart"
        Complete-InstallerStage 'dry-run：未修改系统'
    }
    else {
        $mode = if ($NonInteractive) { '/quiet' } else { '/passive' }
        $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/i', "`"$msiPath`"", $mode, '/norestart') -Wait -PassThru
        if ($process.ExitCode -notin @(0, 3010)) { throw "MSI 安装失败，退出码 $($process.ExitCode)" }
        Complete-InstallerStage 'MSI 安装完成'
    }

    Start-InstallerStage '验证' '检查桌面应用'
    if ($DryRun) { Complete-InstallerStage 'dry-run：计划验证安装结果' }
    else { Warn-InstallerStage '安装命令已成功；请从开始菜单启动 CC Switch' }
}

function Invoke-InstallerComponent {
    param([string]$Component)
    $label = Get-ComponentLabel $Component
    $script:CurrentComponent = $label
    $script:CurrentStage = ''
    $script:CurrentComponentStage = 0
    Write-InstallerMessage INFO "========== $label =========="
    try {
        switch ($Component) {
            'claude' { Invoke-ScriptInstaller -Component 'claude' -Label $label -Uri $script:ClaudeInstallUrl -VerifyCommand 'claude' -Arguments @($Channel) }
            'codex' { Invoke-ScriptInstaller -Component 'codex' -Label $label -Uri $script:CodexInstallUrl -VerifyCommand 'codex' }
            'hermes' { Invoke-ScriptInstaller -Component 'hermes' -Label $label -Uri $script:HermesInstallUrl -VerifyCommand 'hermes' }
            'cc-switch' { Invoke-CCSwitchInstaller }
            default { throw "内部错误，未知组件: $Component" }
        }
        $script:SuccessfulComponents += $label
        Write-InstallerMessage OK "$label`: 成功"
    }
    catch {
        $message = $_.Exception.Message
        if ($script:CurrentComponentStage -eq 0) {
            Start-InstallerStage '准备' '组件初始化'
        }
        $failedStage = $script:CurrentStage
        Fail-InstallerStage -ExitCode 1 -Detail $message
        $script:FailedComponents += $label
        $script:FailedDetails += "$label`: 失败阶段=$failedStage，退出码=1，原因=$message"
        Write-InstallerMessage WARN "$label`: 失败阶段 $failedStage，继续处理其他组件"
    }
}

function Write-InstallerSummary {
    if (-not $NoProgress -and -not $env:CI) { Write-Progress -Activity $script:ProgramName -Completed }
    $elapsed = [int]((Get-Date) - $script:StartTime).TotalSeconds
    Write-InstallerMessage SUMMARY '========== 安装汇总 =========='
    if ($script:SuccessfulComponents.Count -gt 0) { Write-InstallerMessage SUMMARY ("成功: " + ($script:SuccessfulComponents -join ', ')) }
    if ($script:SkippedComponents.Count -gt 0) { Write-InstallerMessage SUMMARY ("跳过: " + ($script:SkippedComponents -join ', ')) }
    if ($script:FailedComponents.Count -gt 0) {
        Write-InstallerMessage SUMMARY ("失败: " + ($script:FailedComponents -join ', '))
        foreach ($detail in $script:FailedDetails) { Write-InstallerMessage SUMMARY $detail }
    }
    Write-InstallerMessage SUMMARY "耗时: $elapsed 秒"
    if ($script:LogEnabled) { Write-InstallerMessage SUMMARY "详细日志: $($script:LogFilePath)" }
}

try {
    Initialize-InstallerLog
    Write-InstallerMessage INFO "$($script:ProgramName) v$($script:ProgramVersion)"
    Write-InstallerMessage INFO '说明：只使用各项目官方安装源，不绕过地区、账号或服务条款限制。'
    if ($Proxy) { Write-InstallerMessage INFO "当前进程代理: $Proxy" }
    if ($script:LogEnabled) { Write-InstallerMessage INFO "详细日志: $($script:LogFilePath)" }
    Resolve-InstallerSelection
    New-Item -ItemType Directory -Path $script:TempRoot -Force | Out-Null
    Write-InstallerMessage INFO ("已选择: " + (($script:SelectedComponents | ForEach-Object { Get-ComponentLabel $_ }) -join ', '))
    Test-InstallerNetwork
    foreach ($component in $script:SelectedComponents) { Invoke-InstallerComponent $component }
    Write-InstallerSummary
    if ($script:FailedComponents.Count -gt 0) { exit 1 }
    exit 0
}
catch {
    Write-InstallerMessage ERROR $_.Exception.Message
    Write-InstallerSummary
    exit 2
}
finally {
    if (Test-Path -LiteralPath $script:TempRoot) { Remove-Item -LiteralPath $script:TempRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
