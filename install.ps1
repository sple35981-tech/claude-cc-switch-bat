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

    [switch]$SkipNetworkCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$ClaudeInstallUrl = 'https://claude.ai/install.ps1'
$CodexInstallUrl = 'https://chatgpt.com/codex/install.ps1'
$HermesInstallUrl = 'https://hermes-agent.nousresearch.com/install.ps1'
$CCSwitchRepo = 'farion1231/cc-switch'
$GitHubApiUrl = "https://api.github.com/repos/$CCSwitchRepo/releases/latest"
$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("ai-cli-installer-" + [guid]::NewGuid().ToString('N'))
$script:SelectedComponents = @()
$script:SuccessfulComponents = @()
$script:FailedComponents = @()
$script:SkippedComponents = @()

function Write-Info([string]$Message) {
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Warn([string]$Message) {
    Write-Warning $Message
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

function ConvertTo-ComponentName([string]$Token) {
    $normalized = $Token.Trim().ToLowerInvariant()
    switch ($normalized) {
        { $_ -in @('1', 'claude', 'claude-code', 'claudecode') } { return 'claude' }
        { $_ -in @('2', 'codex', 'codex-cli', 'codexcli') } { return 'codex' }
        { $_ -in @('3', 'hermes', 'hermes-agent', 'hermesagent') } { return 'hermes' }
        { $_ -in @('4', 'cc-switch', 'ccswitch', 'cc_switch') } { return 'cc-switch' }
        { $_ -in @('5', 'all', '*') } { return 'all' }
        { $_ -in @('0', 'exit', 'quit', 'q') } { return 'exit' }
        '' { return '' }
        default { throw "未知组件: $Token。可选 claude、codex、hermes、cc-switch、all。" }
    }
}

function Add-SelectionTokens([string[]]$Entries) {
    foreach ($entry in $Entries) {
        foreach ($token in ($entry -split '[,\s]+')) {
            if ([string]::IsNullOrWhiteSpace($token)) {
                continue
            }
            $component = ConvertTo-ComponentName -Token $token
            switch ($component) {
                '' { }
                'exit' { exit 0 }
                'all' {
                    Add-SelectedComponent 'claude'
                    Add-SelectedComponent 'codex'
                    Add-SelectedComponent 'hermes'
                    Add-SelectedComponent 'cc-switch'
                }
                default { Add-SelectedComponent $component }
            }
        }
    }
}

function Show-InstallMenu {
    Write-Host ''
    Write-Host '请选择要安装的组件（可多选，例如 1,3,4）：' -ForegroundColor Yellow
    Write-Host '  1) Claude Code'
    Write-Host '  2) OpenAI Codex CLI'
    Write-Host '  3) Nous Research Hermes Agent'
    Write-Host '  4) CC Switch'
    Write-Host '  5) 全部安装'
    Write-Host '  0) 退出'
    return (Read-Host '请输入选择')
}

function Resolve-ComponentSelection {
    if ($Install.Count -gt 0) {
        Add-SelectionTokens -Entries $Install
    }
    elseif (-not [string]::IsNullOrWhiteSpace($env:INSTALLER_TEST_SELECTION)) {
        Add-SelectionTokens -Entries @($env:INSTALLER_TEST_SELECTION)
    }
    elseif (-not $NonInteractive) {
        Add-SelectionTokens -Entries @(Show-InstallMenu)
    }
    else {
        Write-Info '非交互模式未指定组件，使用兼容默认选择: Claude Code + CC Switch'
        Add-SelectedComponent 'claude'
        Add-SelectedComponent 'cc-switch'
    }

    $filtered = @()
    foreach ($component in $script:SelectedComponents) {
        $skip = $false
        switch ($component) {
            'claude' { $skip = [bool]$SkipClaude }
            'codex' { $skip = [bool]$SkipCodex }
            'hermes' { $skip = [bool]$SkipHermes }
            'cc-switch' { $skip = [bool]$SkipCCSwitch }
        }
        if ($skip) {
            $script:SkippedComponents += (Get-ComponentLabel $component)
        }
        else {
            $filtered += $component
        }
    }
    $script:SelectedComponents = $filtered

    if ($script:SelectedComponents.Count -eq 0) {
        throw '没有可安装组件，请使用 -Install 选择至少一项。'
    }
}

function Test-ComponentSelected([string]$Component) {
    return ($script:SelectedComponents -contains $Component)
}

function Invoke-Step {
    param(
        [Parameter(Mandatory = $true)][string]$Description,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )

    Write-Info $Description
    if (-not $DryRun) {
        & $Action
    }
}

function Get-WebRequestParameters {
    $parameters = @{
        UseBasicParsing = $true
        Headers = @{ 'User-Agent' = 'ai-cli-installer/2.0' }
    }
    if ($Proxy) {
        $parameters['Proxy'] = $Proxy
    }
    return $parameters
}

function Get-RestMethodParameters {
    $parameters = @{
        Headers = @{ 'User-Agent' = 'ai-cli-installer/2.0' }
    }
    if ($Proxy) {
        $parameters['Proxy'] = $Proxy
    }
    return $parameters
}

function Invoke-Download {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    Write-Info "下载: $Url"
    if ($DryRun) {
        return
    }

    $params = Get-WebRequestParameters
    $params['Uri'] = $Url
    $params['OutFile'] = $Destination

    $lastError = $null
    for ($attempt = 1; $attempt -le 4; $attempt++) {
        try {
            Invoke-WebRequest @params
            return
        }
        catch {
            $lastError = $_
            if ($attempt -lt 4) {
                Write-Warn "下载失败，第 $attempt 次重试：$($_.Exception.Message)"
                Start-Sleep -Seconds ([Math]::Min(2 * $attempt, 6))
            }
        }
    }
    throw "下载失败: $Url`n$lastError"
}

function Test-NetworkUrl([string]$Url) {
    try {
        $params = Get-WebRequestParameters
        $params['Uri'] = $Url
        $params['Method'] = 'Head'
        $params['TimeoutSec'] = 15
        Invoke-WebRequest @params | Out-Null
    }
    catch {
        Write-Warn "无法访问 $Url。可使用 -Proxy；GitHub 下载还可使用 -GitHubProxy。"
    }
}

function Test-Network {
    if ($SkipNetworkCheck -or $DryRun) {
        return
    }

    Write-Info '检查所选组件网络连通性（失败只提示，不绕过地区、账号或服务条款限制）'
    if (Test-ComponentSelected 'claude') { Test-NetworkUrl 'https://claude.ai' }
    if (Test-ComponentSelected 'codex') { Test-NetworkUrl 'https://chatgpt.com' }
    if (Test-ComponentSelected 'hermes') { Test-NetworkUrl 'https://hermes-agent.nousresearch.com' }
    if (Test-ComponentSelected 'cc-switch') { Test-NetworkUrl 'https://api.github.com' }
}

function Add-GitHubProxyPrefix([string]$Url) {
    if ([string]::IsNullOrWhiteSpace($GitHubProxy)) {
        return $Url
    }
    return ($GitHubProxy.TrimEnd('/') + '/' + $Url)
}

function Get-WindowsArchitecture {
    $arch = if ($env:INSTALLER_TEST_ARCH) { $env:INSTALLER_TEST_ARCH } else { $env:PROCESSOR_ARCHITECTURE }
    switch -Regex ($arch) {
        '^(AMD64|x86_64)$' { return 'x64' }
        '^(ARM64|arm64|aarch64)$' { return 'arm64' }
        default { throw "不支持的 CPU 架构: $arch" }
    }
}

function Install-ClaudeCode {
    $installer = Join-Path $TempRoot 'claude-install.ps1'
    Write-Info "准备从 Anthropic 官方地址安装 Claude Code（通道: $Channel）"
    Invoke-Download -Url $ClaudeInstallUrl -Destination $installer
    Invoke-Step -Description "执行官方安装器: $ClaudeInstallUrl $Channel" -Action {
        & $installer $Channel
    }
}

function Install-Codex {
    $installer = Join-Path $TempRoot 'codex-install.ps1'
    Write-Info '准备从 OpenAI 官方地址安装 Codex CLI'
    Invoke-Download -Url $CodexInstallUrl -Destination $installer
    Invoke-Step -Description "执行官方安装器: $CodexInstallUrl" -Action {
        & $installer
    }
}

function Install-Hermes {
    $installer = Join-Path $TempRoot 'hermes-install.ps1'
    Write-Info '准备从 Nous Research 官方地址安装 Hermes Agent'
    Invoke-Download -Url $HermesInstallUrl -Destination $installer
    Invoke-Step -Description "执行官方安装器: $HermesInstallUrl" -Action {
        & $installer
    }
}

function Get-CCSwitchAssetUrl([string]$Architecture) {
    if ($env:INSTALLER_FAKE_ASSET_URL) {
        return $env:INSTALLER_FAKE_ASSET_URL
    }

    if ($DryRun) {
        $name = if ($Architecture -eq 'arm64') {
            'CC-Switch-LATEST-Windows-arm64.msi'
        }
        else {
            'CC-Switch-LATEST-Windows.msi'
        }
        return "https://github.com/$CCSwitchRepo/releases/latest/download/$name"
    }

    $params = Get-RestMethodParameters
    $params['Uri'] = $GitHubApiUrl
    $release = Invoke-RestMethod @params

    $pattern = if ($Architecture -eq 'arm64') {
        'CC-Switch-v.*-Windows.*arm64.*\.msi$'
    }
    else {
        'CC-Switch-v.*-Windows(?!.*arm64).*\.msi$'
    }

    $asset = $release.assets | Where-Object { $_.name -match $pattern } | Select-Object -First 1
    if (-not $asset) {
        throw "未找到 Windows $Architecture 对应的 CC Switch MSI。"
    }

    $uri = [Uri]$asset.browser_download_url
    $allowedHosts = @('github.com', 'objects.githubusercontent.com', 'github-releases.githubusercontent.com')
    if ($uri.Scheme -ne 'https' -or $allowedHosts -notcontains $uri.Host) {
        throw "Release 返回了非 GitHub HTTPS 下载地址，已拒绝: $uri"
    }
    return $uri.AbsoluteUri
}

function Install-CCSwitch {
    $architecture = Get-WindowsArchitecture
    Write-Info "准备安装 CC Switch（官方仓库: $CCSwitchRepo，架构: $architecture）"
    $assetUrl = Get-CCSwitchAssetUrl -Architecture $architecture
    $downloadUrl = Add-GitHubProxyPrefix -Url $assetUrl
    $msiPath = Join-Path $TempRoot 'cc-switch.msi'
    Invoke-Download -Url $downloadUrl -Destination $msiPath

    Invoke-Step -Description "使用 msiexec.exe 安装 CC Switch MSI: $assetUrl" -Action {
        $uiFlag = if ($NonInteractive) { '/quiet' } else { '/passive' }
        $arguments = "/i `"$msiPath`" $uiFlag /norestart"
        $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $arguments -Wait -PassThru
        if ($process.ExitCode -notin @(0, 3010)) {
            throw "CC Switch MSI 安装失败，退出码: $($process.ExitCode)"
        }
        if ($process.ExitCode -eq 3010) {
            Write-Warn '安装成功，但 Windows 建议重启。'
        }
    }
}

function Invoke-Component([string]$Component) {
    $label = Get-ComponentLabel $Component
    Write-Host ''
    Write-Info "========== $label =========="
    try {
        if ($env:INSTALLER_TEST_FAIL_COMPONENT -eq $Component) {
            throw "测试注入失败: $label"
        }
        switch ($Component) {
            'claude' { Install-ClaudeCode }
            'codex' { Install-Codex }
            'hermes' { Install-Hermes }
            'cc-switch' { Install-CCSwitch }
            default { throw "内部错误，未知组件: $Component" }
        }
        $script:SuccessfulComponents += $label
        Write-Info "$label`: 成功"
    }
    catch {
        $script:FailedComponents += $label
        Write-Warn "$label`: 失败，继续处理其他组件。$($_.Exception.Message)"
    }
}

function Test-InstallationResult {
    if ($DryRun) {
        return
    }
    Write-Info '安装结果检查'
    foreach ($component in $script:SelectedComponents) {
        switch ($component) {
            'claude' {
                if (Get-Command claude -ErrorAction SilentlyContinue) { & claude --version }
                else { Write-Warn '当前终端还找不到 claude，请重新打开终端。' }
            }
            'codex' {
                if (Get-Command codex -ErrorAction SilentlyContinue) { & codex --version }
                else { Write-Warn '当前终端还找不到 codex，请重新打开终端。' }
            }
            'hermes' {
                if (Get-Command hermes -ErrorAction SilentlyContinue) { & hermes --version }
                else { Write-Warn '当前终端还找不到 hermes，请重新打开终端。' }
            }
            'cc-switch' { Write-Info 'CC Switch 安装完成后可从开始菜单启动。' }
        }
    }
}

function Write-Summary {
    Write-Host ''
    Write-Info '========== 安装汇总 =========='
    if ($script:SuccessfulComponents.Count -gt 0) {
        Write-Info ('成功: ' + ($script:SuccessfulComponents -join ', '))
    }
    if ($script:SkippedComponents.Count -gt 0) {
        Write-Info ('跳过: ' + ($script:SkippedComponents -join ', '))
    }
    if ($script:FailedComponents.Count -gt 0) {
        Write-Warn ('失败: ' + ($script:FailedComponents -join ', '))
    }
}

try {
    Write-Info 'Claude Code / Codex / Hermes / CC Switch 安装集合器（Windows）'
    Write-Info '说明：只使用各项目官方安装源，不绕过地区、账号或服务条款限制。'

    Resolve-ComponentSelection

    if ($Proxy) {
        $env:HTTP_PROXY = $Proxy
        $env:HTTPS_PROXY = $Proxy
        Write-Info "已为当前进程启用代理: $Proxy"
    }
    if ($GitHubProxy) {
        Write-Warn '已启用用户指定的 GitHub 代理前缀，请确保该服务可信。'
    }

    if (-not $DryRun) {
        New-Item -ItemType Directory -Path $TempRoot -Force | Out-Null
    }

    Write-Info ('已选择: ' + (($script:SelectedComponents | ForEach-Object { Get-ComponentLabel $_ }) -join ', '))
    Test-Network
    foreach ($component in $script:SelectedComponents) {
        Invoke-Component -Component $component
    }

    Test-InstallationResult
    Write-Summary
    if ($DryRun) {
        Write-Info 'Dry-run 完成，未修改系统。'
    }

    if ($script:FailedComponents.Count -gt 0) {
        exit 1
    }
}
catch {
    Write-Error $_
    exit 1
}
finally {
    if (-not $DryRun -and (Test-Path $TempRoot)) {
        Remove-Item -Path $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
