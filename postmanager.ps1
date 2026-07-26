# 博客文章/标签管理 - 由 new.bat 启动
. (Join-Path $PSScriptRoot '_lib.ps1')
# ---------- 选标签的交互 ----------

function Select-Tags($current = @()) {
    $tags = @(Get-Tags)
    Write-Host ''
    Write-Host '现有标签:' -ForegroundColor Cyan
    if ($tags.Count -eq 0) {
        Write-Host '  (还没有标签,直接输入新标签名即可)'
    } else {
        for ($i = 0; $i -lt $tags.Count; $i++) {
            $mark = if ($current -contains $tags[$i]) { ' *当前已选' } else { '' }
            Write-Host ("  {0}. {1}{2}" -f ($i + 1), $tags[$i], $mark)
        }
    }
    Write-Host ''
    Write-Host '输入编号选择已有标签,或直接输入新标签名(逗号分隔,可混用)。直接回车 = 不改动/不加标签。' -ForegroundColor DarkGray
    $tagInput = Read-Host '标签'

    if ([string]::IsNullOrWhiteSpace($tagInput)) { return $null }

    $selected = @()
    $parts = @($tagInput -split '[,，、]' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
    foreach ($p in $parts) {
        if ($tags.Count -gt 0 -and $p -match '^\d+$' -and [int]$p -ge 1 -and [int]$p -le $tags.Count) {
            $selected += $tags[[int]$p - 1]
        } else {
            if ($p -match '^\d+$') {
                Write-Host "  (提示: 编号 $p 超出范围,已当成新标签名「$p」)" -ForegroundColor DarkYellow
            }
            $selected += $p
            if ($tags -notcontains $p) { $tags += $p }
        }
    }
    Save-Tags $tags
    return ,@($selected | Select-Object -Unique)
}

# ---------- 新建文章 ----------

function New-Post {
    Clear-Host
    Write-Host '=== 新建文章 ===' -ForegroundColor Green
    $filename = Read-Host '文件名(英文/拼音,不要空格,例如 my-first-post)'
    if ([string]::IsNullOrWhiteSpace($filename)) { Write-Host '文件名不能为空' -ForegroundColor Red; return }
    $filename = $filename.Trim()
    if ($filename -match '[\\/:\*\?"<>\|\s]') {
        Write-Host '文件名里不能有空格和 \ / : * ? " < > | 这些字符' -ForegroundColor Red
        return
    }
    if ($filename.StartsWith('_')) {
        Write-Host '文件名不能以下划线开头,Hugo 会直接忽略这种文件,文章永远发不出去。' -ForegroundColor Red
        return
    }
    if ($filename -match '\.md$') { $filename = $filename -replace '\.md$', '' }

    $filePath = Join-Path $postsDir "$filename.md"
    if (Test-Path $filePath) {
        Write-Host "已经存在同名文章: $filePath" -ForegroundColor Red
        Write-Host '换个文件名,或先去"文章管理"里删掉它。' -ForegroundColor Red
        return
    }

    $title = Read-Host '文章标题(中文)'
    if ([string]::IsNullOrWhiteSpace($title)) { $title = $filename }

    $selectedTags = Select-Tags
    if ($null -eq $selectedTags) { $selectedTags = @() }

    $weight = 0
    if ((Read-Host '是否置顶?(y/n)') -match '^[yY]') {
        $w = Read-Host '置顶权重(数字越小越靠前,回车默认 1)'
        if ($w -match '^\d+$') { $weight = [int]$w } else { $weight = 1 }
    }

    $isDraft = $true
    if ((Read-Host '现在就发布吗?(y = 直接发布 / n = 先存草稿,默认草稿)') -match '^[yY]') { $isDraft = $false }

    $tagsYaml   = @($selectedTags | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }) -join ', '
    $dateStr    = Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz'
    $weightLine = if ($weight -gt 0) { "weight: $weight`n" } else { '' }
    $draftStr   = if ($isDraft) { 'true' } else { 'false' }
    $titleEsc   = $title -replace '"', '\"'

    $frontmatter = @"
---
title: "$titleEsc"
date: $dateStr
draft: $draftStr
${weightLine}tags: [$tagsYaml]
---

"@

    Write-TextFile $filePath $frontmatter

    Write-Host ''
    Write-Host "已创建: $filePath" -ForegroundColor Green
    Write-Host "标签: $(if ($selectedTags.Count) { $selectedTags -join ', ' } else { '(无)' })"
    if ($weight -gt 0) { Write-Host "已置顶,权重: $weight" }
    if ($isDraft) {
        Write-Host '当前是草稿,只有本地预览能看到。写完记得在"文章管理"里改成已发布,或手动把 draft 改成 false。' -ForegroundColor Yellow
    } else {
        Write-Host '状态: 已发布(下次 publish.bat 推送后就会上线)' -ForegroundColor Green
    }

    Start-Process notepad.exe -ArgumentList "`"$filePath`""
}

# ---------- 文章管理 ----------

function Show-PostList($posts) {
    if ($posts.Count -eq 0) {
        Write-Host '(还没有文章)'
        return
    }
    for ($i = 0; $i -lt $posts.Count; $i++) {
        $p      = $posts[$i]
        $draft  = Get-PostDraft $p.Fm
        $status = if ($draft) { '[草稿]' } else { '[已发布]' }
        $color  = if ($draft) { 'DarkYellow' } else { 'Green' }
        $w      = Get-PostWeight $p.Fm
        $pin    = if ($w -gt 0) { " [置顶$w]" } else { '' }
        $tags   = @(Get-PostTags $p.Fm)
        $tagStr = if ($tags.Count) { "  标签: $($tags -join ', ')" } else { '' }
        Write-Host ("  {0}. " -f ($i + 1)) -NoNewline
        Write-Host $status -ForegroundColor $color -NoNewline
        Write-Host "$pin $(Get-PostTitle $p.Fm)  ($($p.Name).md)$tagStr"
    }
}

function Select-Post($posts, $prompt) {
    $idx = Read-Host $prompt
    if ($idx -match '^\d+$' -and [int]$idx -ge 1 -and [int]$idx -le $posts.Count) {
        return $posts[[int]$idx - 1]
    }
    Write-Host '编号无效' -ForegroundColor Red
    return $null
}

function Manage-Posts {
    while ($true) {
        Clear-Host
        Write-Host '==================================='
        Write-Host '   文章管理'
        Write-Host '==================================='
        $posts = @(Get-AllPosts)
        Show-PostList $posts
        Write-Host ''
        Write-Host '1. 切换草稿/发布状态'
        Write-Host '2. 修改文章标签'
        Write-Host '3. 设置/取消置顶'
        Write-Host '4. 用记事本打开'
        Write-Host '5. 删除文章'
        Write-Host '0. 返回主菜单'
        Write-Host '==================================='
        $choice = Read-Host '选择'

        if ($choice -eq '0') { return }
        if ($posts.Count -eq 0) { Write-Host '还没有文章'; Pause-Key; continue }

        switch ($choice) {
            '1' {
                $p = Select-Post $posts '文章编号'
                if ($p) {
                    $cur = Get-PostDraft $p.Fm
                    Set-PostDraft $p.Fm (-not $cur)
                    Save-Post $p
                    Write-Host ("已改为: " + $(if ($cur) { '已发布' } else { '草稿' })) -ForegroundColor Green
                }
                Pause-Key
            }
            '2' {
                $p = Select-Post $posts '文章编号'
                if ($p) {
                    $cur = @(Get-PostTags $p.Fm)
                    Write-Host "当前标签: $(if ($cur.Count) { $cur -join ', ' } else { '(无)' })"
                    $new = Select-Tags $cur
                    if ($null -ne $new) {
                        Set-PostTags $p.Fm $new
                        Save-Post $p
                        Write-Host "已更新为: $($new -join ', ')" -ForegroundColor Green
                    } else {
                        Write-Host '没有改动'
                    }
                }
                Pause-Key
            }
            '3' {
                $p = Select-Post $posts '文章编号'
                if ($p) {
                    $w = Read-Host '置顶权重(数字越小越靠前,输入 0 或回车 = 取消置顶)'
                    if ($w -match '^\d+$' -and [int]$w -gt 0) {
                        Set-Field $p.Fm 'weight' $w
                        Write-Host "已置顶,权重 $w" -ForegroundColor Green
                    } else {
                        Remove-Field $p.Fm 'weight'
                        Write-Host '已取消置顶'
                    }
                    Save-Post $p
                }
                Pause-Key
            }
            '4' {
                $p = Select-Post $posts '文章编号'
                if ($p) { Start-Process notepad.exe -ArgumentList "`"$($p.Path)`"" }
            }
            '5' {
                $p = Select-Post $posts '文章编号'
                if ($p) {
                    Write-Host "即将删除: $($p.Path)" -ForegroundColor Red
                    if ((Read-Host '确认删除?不可撤销(y/n)') -match '^[yY]') {
                        Remove-Item $p.Path -Force
                        Write-Host '已删除' -ForegroundColor Green
                    } else { Write-Host '已取消' }
                }
                Pause-Key
            }
        }
    }
}

# ---------- 标签管理 ----------

function Manage-Tags {
    while ($true) {
        Clear-Host
        $tags = @(Get-Tags)
        Write-Host '==================================='
        Write-Host '   标签管理'
        Write-Host '==================================='
        if ($tags.Count -eq 0) {
            Write-Host '(还没有标签)'
        } else {
            for ($i = 0; $i -lt $tags.Count; $i++) { Write-Host ("  {0}. {1}" -f ($i + 1), $tags[$i]) }
        }
        Write-Host ''
        Write-Host '1. 新增标签'
        Write-Host '2. 重命名标签(自动同步修改所有用到的文章)'
        Write-Host '3. 删除标签(自动从所有文章里移除)'
        Write-Host '4. 从现有文章里扫描并导入标签'
        Write-Host '0. 返回主菜单'
        Write-Host '==================================='
        $choice = Read-Host '选择'

        switch ($choice) {
            '1' {
                $newTag = (Read-Host '新标签名').Trim()
                if ([string]::IsNullOrWhiteSpace($newTag)) {
                    Write-Host '标签不能为空' -ForegroundColor Red
                } elseif ($tags -contains $newTag) {
                    Write-Host '标签已存在' -ForegroundColor Red
                } else {
                    Save-Tags ($tags + $newTag)
                    Write-Host "已新增: $newTag" -ForegroundColor Green
                }
                Pause-Key
            }
            '2' {
                if ($tags.Count -eq 0) { Write-Host '没有标签'; Pause-Key; continue }
                $idx = Read-Host '要重命名的标签编号'
                if ($idx -match '^\d+$' -and [int]$idx -ge 1 -and [int]$idx -le $tags.Count) {
                    $oldTag = $tags[[int]$idx - 1]
                    $newTag = (Read-Host "新标签名(原名: $oldTag)").Trim()
                    if ([string]::IsNullOrWhiteSpace($newTag)) {
                        Write-Host '已取消' -ForegroundColor Yellow
                    } elseif ((Read-Host "确认把所有文章里的「$oldTag」改成「$newTag」?(y/n)") -match '^[yY]') {
                        $n = Update-PostsTag -oldTag $oldTag -newTag $newTag
                        Save-Tags (@($tags | Where-Object { $_ -ne $oldTag }) + $newTag)
                        Write-Host "已更新 $n 篇文章" -ForegroundColor Green
                    }
                } else { Write-Host '编号无效' -ForegroundColor Red }
                Pause-Key
            }
            '3' {
                if ($tags.Count -eq 0) { Write-Host '没有标签'; Pause-Key; continue }
                $idx = Read-Host '要删除的标签编号'
                if ($idx -match '^\d+$' -and [int]$idx -ge 1 -and [int]$idx -le $tags.Count) {
                    $oldTag = $tags[[int]$idx - 1]
                    if ((Read-Host "确认删除「$oldTag」?会从所有文章里移除,不可撤销(y/n)") -match '^[yY]') {
                        $n = Update-PostsTag -oldTag $oldTag -newTag $null
                        Save-Tags @($tags | Where-Object { $_ -ne $oldTag })
                        Write-Host "已删除,更新了 $n 篇文章" -ForegroundColor Green
                    }
                } else { Write-Host '编号无效' -ForegroundColor Red }
                Pause-Key
            }
            '4' {
                $found = @()
                foreach ($p in @(Get-AllPosts)) { $found += @(Get-PostTags $p.Fm) }
                $merged = @($tags + $found | Where-Object { $_ -ne '' } | Sort-Object -Unique)
                $added  = @($merged | Where-Object { $tags -notcontains $_ })
                Save-Tags $merged
                if ($added.Count) { Write-Host "导入了 $($added.Count) 个标签: $($added -join ', ')" -ForegroundColor Green }
                else { Write-Host '没有发现新标签' }
                Pause-Key
            }
            '0' { return }
        }
    }
}

# ---------- 主菜单 ----------

while ($true) {
    Clear-Host
    Write-Host '==================================='
    Write-Host '   博客文章管理'
    Write-Host '==================================='
    Write-Host '1. 新建文章'
    Write-Host '2. 文章管理(草稿/置顶/标签/删除)'
    Write-Host '3. 标签管理'
    Write-Host '0. 退出'
    Write-Host '==================================='
    $choice = Read-Host '选择'
    switch ($choice) {
        '1' { New-Post; Pause-Key '按回车返回主菜单' }
        '2' { Manage-Posts }
        '3' { Manage-Tags }
        '0' { exit }
    }
}
