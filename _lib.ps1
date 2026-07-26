[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
try { [Console]::InputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$root     = $PSScriptRoot
$postsDir = Join-Path $root 'content\posts'
$tagsFile = Join-Path $root 'tags.txt'

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

if (-not (Test-Path $postsDir)) { New-Item $postsDir -ItemType Directory -Force | Out-Null }

# ---------- 基础读写(统一 UTF-8 无 BOM,避免 Hugo 解析前言出错) ----------

function Write-TextFile($path, $text) {
    [System.IO.File]::WriteAllText($path, $text, $Utf8NoBom)
}

function Read-TextFile($path) {
    $t = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    return $t.TrimStart([char]0xFEFF)
}

# -replace 的替换串里 $ 有特殊含义,必须转义
function ConvertTo-SafeReplacement($s) { return ($s -replace '\$', '$$$$') }

function Pause-Key($msg = '按回车继续') { Read-Host $msg | Out-Null }

# ---------- 标签表 ----------

# 注意: PowerShell 从函数 return 空数组时会把它"摊平"成 $null,
# 之后 $tags += "标签" 就变成字符串拼接(生活+技术 -> "生活技术")。
# 所以下面这些返回数组的函数,调用时一律要用 @(...) 包一层。
function Get-Tags {
    if (-not (Test-Path $tagsFile)) { return @() }
    $raw = Read-TextFile $tagsFile
    if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
    return @($raw -split "`r`n|`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
}

function Save-Tags($tagList) {
    $clean = @($tagList | Where-Object { $_ -and $_.Trim() -ne '' } | ForEach-Object { $_.Trim() } | Sort-Object -Unique)
    Write-TextFile $tagsFile (($clean -join "`r`n") + "`r`n")
}

# ---------- 文章前言(front matter)解析,YAML(---) 和 TOML(+++) 都支持 ----------

# 全部用 [regex]::Match 显式取结果,不用自动变量 $Matches。
# $Matches 在"管道 -> 函数"这种跨作用域调用里不一定会被填上,
# 之前草稿检测失灵、报 "Cannot index into a null array" 就是这个原因。
function Get-FrontMatter([string]$content) {
    $m = [regex]::Match($content, '(?s)\A(---\r?\n)(.*?)(\r?\n---)')
    if ($m.Success) {
        return [pscustomobject]@{ Kind = 'yaml'; Head = $m.Groups[1].Value; Body = $m.Groups[2].Value; Tail = $m.Groups[3].Value }
    }
    $m = [regex]::Match($content, '(?s)\A(\+\+\+\r?\n)(.*?)(\r?\n\+\+\+)')
    if ($m.Success) {
        return [pscustomobject]@{ Kind = 'toml'; Head = $m.Groups[1].Value; Body = $m.Groups[2].Value; Tail = $m.Groups[3].Value }
    }
    return $null
}

function Get-Post($path) {
    $c  = Read-TextFile $path
    $fm = Get-FrontMatter $c
    if ($null -eq $fm) { return $null }
    $len = $fm.Head.Length + $fm.Body.Length + $fm.Tail.Length
    return [pscustomobject]@{
        Path = $path
        Name = [System.IO.Path]::GetFileNameWithoutExtension($path)
        Fm   = $fm
        Rest = $c.Substring($len)
    }
}

function Save-Post($post) {
    Write-TextFile $post.Path ($post.Fm.Head + $post.Fm.Body + $post.Fm.Tail + $post.Rest)
}

function Get-FieldPattern($kind, $field, $valuePattern) {
    if ($kind -eq 'yaml') { return "(?m)^\s*$field\s*:\s*$valuePattern\s*$" }
    else                  { return "(?m)^\s*$field\s*=\s*$valuePattern\s*$" }
}

function Set-Field($fm, $field, $valueText) {
    $sep  = if ($fm.Kind -eq 'yaml') { ': ' } else { ' = ' }
    $line = "$field$sep$valueText"
    $pat  = Get-FieldPattern $fm.Kind $field '.*'
    if ([regex]::IsMatch($fm.Body, $pat)) {
        $fm.Body = [regex]::Replace($fm.Body, $pat, (ConvertTo-SafeReplacement $line))
    } else {
        $fm.Body = $fm.Body.TrimEnd() + "`n" + $line
    }
}

function Remove-Field($fm, $field) {
    $pat = Get-FieldPattern $fm.Kind $field '.*'
    $fm.Body = [regex]::Replace($fm.Body, ($pat + '\r?\n?'), '').TrimEnd()
}

function Get-PostTitle($fm) {
    $m = [regex]::Match($fm.Body, (Get-FieldPattern $fm.Kind 'title' '(.*)'))
    if ($m.Success) {
        # 去掉外层引号,并把写进文件的 \" 还原成 " 再显示
        return ($m.Groups[1].Value.Trim().Trim('"').Trim("'") -replace '\\"', '"')
    }
    return ''
}

function Get-PostDraft($fm) {
    $m = [regex]::Match($fm.Body, (Get-FieldPattern $fm.Kind 'draft' '(true|false)'))
    if ($m.Success) { return ($m.Groups[1].Value -eq 'true') }
    return $false
}

function Set-PostDraft($fm, [bool]$isDraft) {
    Set-Field $fm 'draft' $(if ($isDraft) { 'true' } else { 'false' })
}

function Get-PostWeight($fm) {
    $m = [regex]::Match($fm.Body, (Get-FieldPattern $fm.Kind 'weight' '(\d+)'))
    if ($m.Success) { return [int]$m.Groups[1].Value }
    return 0
}

function Get-PostTags($fm) {
    $m = [regex]::Match($fm.Body, (Get-FieldPattern $fm.Kind 'tags' '\[([^\]]*)\]'))
    if ($m.Success) {
        return @($m.Groups[1].Value -split ',' | ForEach-Object { $_.Trim().Trim('"').Trim("'").Trim() } | Where-Object { $_ -ne '' })
    }
    return @()
}

function Set-PostTags($fm, $tagList) {
    $quoted = @($tagList | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }) -join ', '
    Set-Field $fm 'tags' "[$quoted]"
}

function Get-AllPosts {
    if (-not (Test-Path $postsDir)) { return @() }
    # 只认 .md;下划线开头的文件 Hugo 会直接忽略,不算文章
    $files = @(Get-ChildItem $postsDir -Recurse -File -ErrorAction SilentlyContinue |
               Where-Object { $_.Extension -eq '.md' -and -not $_.Name.StartsWith('_') } |
               Sort-Object Name)
    $result = @()
    foreach ($f in $files) {
        $p = Get-Post $f.FullName
        if ($null -ne $p) { $result += $p }
        else { Write-Host "  (跳过没有前言的文件: $($f.Name))" -ForegroundColor DarkYellow }
    }
    return @($result)
}

# ---------- 批量改标签 ----------

function Update-PostsTag($oldTag, $newTag) {
    $count = 0
    foreach ($post in @(Get-AllPosts)) {
        $tags = @(Get-PostTags $post.Fm)
        if ($tags -contains $oldTag) {
            if ([string]::IsNullOrEmpty($newTag)) {
                $newList = @($tags | Where-Object { $_ -ne $oldTag })
            } else {
                $newList = @($tags | ForEach-Object { if ($_ -eq $oldTag) { $newTag } else { $_ } } | Select-Object -Unique)
            }
            Set-PostTags $post.Fm $newList
            Save-Post $post
            $count++
        }
    }
    return $count
}
