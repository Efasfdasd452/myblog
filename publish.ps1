. (Join-Path $PSScriptRoot '_lib.ps1')

Set-Location $root

function Fail($msg) {
    Write-Host ''
    Write-Host "[错误] $msg" -ForegroundColor Red
    Pause-Key
    exit 1
}

foreach ($cmd in 'git', 'hugo') {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Fail "找不到 $cmd 命令,请确认已安装并加入 PATH。"
    }
}

Write-Host '==================================='
Write-Host '  发布博客' -ForegroundColor Cyan
Write-Host '==================================='
Write-Host ''

# ---------- 1. 草稿提醒(草稿不会出现在线上) ----------
$drafts = @(Get-AllPosts | Where-Object { Get-PostDraft $_.Fm })
if ($drafts.Count -gt 0) {
    Write-Host "[提醒] 下面 $($drafts.Count) 篇文章还是草稿,不会出现在线上网站:" -ForegroundColor Yellow
    foreach ($d in $drafts) { Write-Host "  - $(Get-PostTitle $d.Fm) ($($d.Name).md)" -ForegroundColor Yellow }
    Write-Host ''
    Write-Host '想发布它们的话,先用 new.bat 里的"文章管理"改成已发布。'
    if ((Read-Host '还是继续发布?(y/n)') -notmatch '^[yY]') {
        Write-Host '已取消。'
        Pause-Key
        exit 0
    }
    Write-Host ''
}

# ---------- 2. 先本地构建,构建不过就不推送 ----------
Write-Host '正在构建网站...'
$lock = Join-Path $root '.hugo_build.lock'
if (Test-Path $lock) { Remove-Item $lock -Force -ErrorAction SilentlyContinue }

hugo --minify --cleanDestinationDir
if ($LASTEXITCODE -ne 0) { Fail '构建失败,已停止发布。请按上面的报错改好文章再试。' }
Write-Host '构建成功。' -ForegroundColor Green
Write-Host ''

# ---------- 3. 提交说明 ----------
$msg = Read-Host '本次提交说明(比如: 新增文章 xxx,直接回车用默认)'
if ([string]::IsNullOrWhiteSpace($msg)) {
    $msg = "更新博客 $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
}

# 写成 UTF-8 文件用 -F 提交:说明里带 % " & ! 中文都不会出错
$msgFile = Join-Path $env:TEMP 'hugo_commit_msg.txt'
Write-TextFile $msgFile ($msg + "`n")

try {
    # ---------- 4. 提交 ----------
    git add -A
    if ($LASTEXITCODE -ne 0) { Fail 'git add 失败。' }

    git diff --cached --quiet
    if ($LASTEXITCODE -eq 0) {
        Write-Host '没有任何改动需要提交。' -ForegroundColor Yellow
        Write-Host '如果线上还是旧的,可能是远端还在构建,等一两分钟再看。'
        Pause-Key
        exit 0
    }

    Write-Host ''
    Write-Host '本次要提交的改动:' -ForegroundColor Cyan
    git diff --cached --stat
    Write-Host ''

    git commit -F $msgFile
    if ($LASTEXITCODE -ne 0) { Fail 'git commit 失败,没有推送。' }
}
finally {
    if (Test-Path $msgFile) { Remove-Item $msgFile -Force -ErrorAction SilentlyContinue }
}

# ---------- 5. 推送 ----------
Write-Host ''
Write-Host '正在推送到 GitHub...'
git push
if ($LASTEXITCODE -ne 0) {
    Write-Host ''
    Write-Host '[错误] 推送失败。本地已经提交好了,常见原因:' -ForegroundColor Red
    Write-Host '  1. 网络问题 / 需要重新登录 GitHub'
    Write-Host '  2. 远端有别的改动 —— 先执行 git pull --rebase 再重新运行本脚本'
    Write-Host ''
    Pause-Key
    exit 1
}

Write-Host ''
Write-Host '===================================' -ForegroundColor Green
Write-Host '已推送成功!' -ForegroundColor Green
Write-Host 'Cloudflare Pages 构建完成后(通常 1-2 分钟)就能看到更新:'
Write-Host 'https://myblog-aya.pages.dev/'
Write-Host '===================================' -ForegroundColor Green
Pause-Key
