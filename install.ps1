[CmdletBinding()]
param(
    [ValidateSet('stable', 'latest')]
    [string]$Channel = 'stable',

    [string]$Proxy = '',

    [string]$GitHubProxy = '',

    [switch]$SkipClaude,

    [switch]$SkipCCSwitch,

    [switch]$DryRun,

    [switch]$NonInteractive,

    [switch]$SkipNetworkCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$ClaudeInstallUrl = 'https://claude.ai/install.ps1'
$CCSwitchRepo = 'farion1231/cc-switch'
$GitHubApiUrl = "https://api.github.com/repos/$CCSwitchRepo/releases/latest"
$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("cc-installer-" + [guid]::NewGuid().ToString('N'))

function Write-Info([string]$Message) {
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Warn([string]$Message) {
    Write-Warning $Message
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
        Headers = @{ 'User-Agent' = 'cc-switch-installer/1.0' }
    }
    if ($Proxy) {
        $parameters['Proxy'] = $Proxy
    }
    return $parameters
}

function Get-RestMethodParameters {
    $parameters = @{
        Headers = @{ 'User-Agent' = 'cc-switch-installer/1.0' }
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

function Test-Network {
    if ($SkipNetworkCheck -or $DryRun) {
        return
    }

    Write-Info '检查网络连通性（失败只提示，不绕过服务地区或账号限制）'
    foreach ($url in @('https://claude.ai', 'https://api.github.com')) {
        try {
            $params = Get-WebRequestParameters
            $params['Uri'] = $url
            $params['Method'] = 'Head'
            $params['TimeoutSec'] = 15
            Invoke-WebRequest @params | Out-Null
        }
        catch {
            Write-Warn "无法访问 $url。可使用 -Proxy；GitHub 下载还可使用 -GitHubProxy。"
        }
    }
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
    if ($SkipClaude) {
        Write-Info '已跳过 Claude Code'
        return
    }

    $installer = Join-Path $TempRoot 'claude-install.ps1'
    Write-Info "准备从 Anthropic 官方地址安装 Claude Code（通道: $Channel）"
    Invoke-Download -Url $ClaudeInstallUrl -Destination $installer

    Invoke-Step -Description "执行官方安装器: $ClaudeInstallUrl $Channel" -Action {
        & $installer $Channel
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
    if ($SkipCCSwitch) {
        Write-Info '已跳过 CC Switch'
        return
    }

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

function Test-InstallationResult {
    Write-Info '安装结果检查'
    if (-not $SkipClaude) {
        $claude = Get-Command claude -ErrorAction SilentlyContinue
        if ($claude) {
            & claude --version
        }
        else {
            Write-Warn '当前终端还找不到 claude。请关闭并重新打开终端，然后运行 claude --version。'
        }
    }
    if (-not $SkipCCSwitch) {
        Write-Info 'CC Switch 安装完成后可从开始菜单启动。'
    }
}

try {
    if ($SkipClaude -and $SkipCCSwitch) {
        throw 'Claude Code 和 CC Switch 不能同时跳过。'
    }

    Write-Info 'Claude Code + CC Switch 跨平台一键安装器（Windows）'
    Write-Info '说明：本脚本不绕过 Claude 的地区、账号或服务条款限制。'
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

    Test-Network
    Install-ClaudeCode
    Install-CCSwitch

    if ($DryRun) {
        Write-Info 'Dry-run 完成，未修改系统。'
    }
    else {
        Test-InstallationResult
        Write-Info '全部操作完成。运行 claude 开始登录，打开 CC Switch 配置供应商。'
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
