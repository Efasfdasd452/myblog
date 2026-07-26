. (Join-Path $PSScriptRoot '_lib.ps1')

Set-Location $root

if (-not (Get-Command hugo -ErrorAction SilentlyContinue)) {
    Write-Host '[错误] 找不到 hugo 命令。' -ForegroundColor Red
    Write-Host '请确认 Hugo 已安装,并且加入了系统环境变量 PATH。'
    Pause-Key
    exit 1
}

if (-not (Test-Path (Join-Path $root 'themes\PaperMod\layouts'))) {
    Write-Host '[警告] 主题 themes\PaperMod 是空的,正在拉取子模块...' -ForegroundColor Yellow
    git submodule update --init --recursive
    Write-Host ''
}

# 上次异常退出可能残留锁文件,会让 hugo 直接报错
$lock = Join-Path $root '.hugo_build.lock'
if (Test-Path $lock) { Remove-Item $lock -Force -ErrorAction SilentlyContinue }

$drafts = @(Get-AllPosts | Where-Object { Get-PostDraft $_.Fm })

Write-Host '==================================='
Write-Host '  本地预览' -ForegroundColor Cyan
Write-Host '==================================='
Write-Host '浏览器打开 http://localhost:1313'
if ($drafts.Count -gt 0) {
    Write-Host "预览包含 $($drafts.Count) 篇草稿(线上看不到):" -ForegroundColor DarkYellow
    foreach ($d in $drafts) { Write-Host "  - $(Get-PostTitle $d.Fm) ($($d.Name).md)" -ForegroundColor DarkYellow }
}
Write-Host '按 Ctrl+C 停止预览'
Write-Host '==================================='
Write-Host ''

# -D 显示草稿; --disableFastRender 避免改了内容页面不刷新
hugo server -D --disableFastRender --navigateToChanged

if ($LASTEXITCODE -ne 0) {
    Write-Host ''
    Write-Host '[错误] 预览服务器启动失败。常见原因:' -ForegroundColor Red
    Write-Host '  1. 1313 端口被占用(上一个预览窗口没关) —— 关掉旧窗口再试'
    Write-Host '  2. 某篇文章的前言(front matter)写错了 —— 看上面的报错信息'
    Write-Host ''
}

Pause-Key
