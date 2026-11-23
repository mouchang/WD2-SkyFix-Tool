<#
  Watch Dogs 2 - Sky Flicker Fix Toolbox
  纯数据补丁管理：安装 / 删除 / 改编号 / 设置游戏位置
#>
param(
    [switch]$SelfTest,
    [switch]$Status
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$script:Root          = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:ConfigPath    = Join-Path $script:Root 'tool-config.ini'
$script:UninstallPath = Join-Path $script:Root 'uninstall.cmd'
$script:BuildDir      = Join-Path $script:Root 'build'
$script:GameDir       = ''

# 本补丁的特征：fat 52 字节、dat 57892 字节、fat 里只有一个条目且名字哈希为 0xBDA417D90674CED7
$script:FatSize   = 52
$script:DatSize   = 57892
$script:EntryHash = [byte[]](0xD7, 0xCE, 0x74, 0x06, 0xD9, 0x17, 0xA4, 0xBD)

function C([string]$text, [string]$color = 'Gray') {
    Write-Host $text -ForegroundColor $color
}

function Read-GameDir {
    $dir = ''
    if (Test-Path -LiteralPath $script:ConfigPath) {
        foreach ($line in (Get-Content -LiteralPath $script:ConfigPath -Encoding UTF8)) {
            if ($line -match '^\s*GameDir\s*=\s*(.*)$') {
                $dir = $Matches[1].Trim().Trim('"')
            }
        }
    }
    return $dir
}

function Save-GameDir([string]$dir) {
    $lines = @(
        '; Watch Dogs 2 sky-flicker fix toolbox',
        '; GameDir = path to the game data_win64 folder (leave empty to unset)',
        ('GameDir=' + $dir)
    )
    Set-Content -LiteralPath $script:ConfigPath -Value ($lines -join [Environment]::NewLine) -Encoding UTF8
}

function Test-Pair([string]$fat, [string]$dat) {
    if (-not (Test-Path -LiteralPath $fat)) { return $false }
    if (-not (Test-Path -LiteralPath $dat)) { return $false }
    if ((Get-Item -LiteralPath $fat).Length -ne $script:FatSize) { return $false }
    if ((Get-Item -LiteralPath $dat).Length -ne $script:DatSize) { return $false }
    $bytes = [System.IO.File]::ReadAllBytes($fat)
    if ($bytes.Length -lt 36) { return $false }
    if ([BitConverter]::ToUInt32($bytes, 24) -ne 1) { return $false }
    for ($i = 0; $i -lt 8; $i++) {
        if ($bytes[28 + $i] -ne $script:EntryHash[$i]) { return $false }
    }
    return $true
}

function Get-Installed([string]$dir) {
    $list = @()
    if ($dir -eq '' -or -not (Test-Path -LiteralPath $dir)) { return $list }
    $files = Get-ChildItem -LiteralPath $dir -Filter 'patch*.fat' -File -ErrorAction SilentlyContinue
    foreach ($f in $files) {
        if ($f.Name -match '^patch([0-9]+)\.fat$') {
            $n = [int]$Matches[1]
            $dat = Join-Path $dir ('patch{0}.dat' -f $n)
            if (Test-Pair $f.FullName $dat) {
                $list += [pscustomobject]@{
                    Number = $n
                    Name   = ('patch{0}' -f $n)
                    Fat    = $f.FullName
                    Dat    = $dat
                }
            }
        }
    }
    return $list
}

function Get-GameRunning {
    $p = Get-Process -Name WatchDogs2 -ErrorAction SilentlyContinue
    if ($p) { return $true }
    return $false
}

function Show-Header([string]$dir) {
    C ('=' * 62) 'DarkCyan'
    C '   Watch Dogs 2  ·  闪烁修复工具' 'White'
    C ('=' * 62) 'DarkCyan'
    C '   作者:the_box_mc(某尝)' 'DarkCyan'
    C '   github:https://github.com/mouchang' 'DarkCyan'
    C '   bilibili:https://space.bilibili.com/599130940' 'DarkCyan'
    C ('=' * 62) 'DarkCyan'
    $ready = ($dir -ne '' -and (Test-Path -LiteralPath $dir))
    if (-not $ready) {
        C '   看门狗2位置 : 请到设置中设置看门狗2文件位置！！！' 'Red'
    } else {
        C ('   看门狗2位置 : ' + $dir) 'Gray'
        $found = @(Get-Installed $dir)
        if ($found.Count -gt 0) {
            $names = ($found | ForEach-Object { $_.Name }) -join ', '
            C ('   补丁状态     : ' + $names + '   （已安装）') 'Green'
        } else {
            C '   补丁状态     : 未安装' 'Yellow'
        }
        if (Get-GameRunning) {
            C '   游戏进程     : 运行中（安装/删除/改名可能失败，建议先退出）' 'Yellow'
        }
    }
    C ('-' * 62) 'DarkGray'
}

function Show-Menu {
    C '   [1]  一键安装本修复补丁' 'White'
    C '   [2]  一键删除本修复补丁（只删本补丁，不动其它 mod）' 'White'
    C '   [3]  一键修改补丁编号（同时更新 uninstall.cmd）' 'White'
    C '   [4]  设置《看门狗2》文件位置' 'White'
    C '   [0]  退出' 'White'
    C ('-' * 62) 'DarkGray'
}

function Test-Ready([string]$dir, [string]$action) {
    if ($dir -eq '' -or -not (Test-Path -LiteralPath $dir)) {
        C ''
        C ('   还没有设置看门狗2位置，无法' + $action + '。') 'Red'
        C '   请先按 [4] 设置看门狗2文件位置。' 'Yellow'
        return $false
    }
    return $true
}

function Sync-UninstallName([int]$num) {
    if (-not (Test-Path -LiteralPath $script:UninstallPath)) { return $false }
    $text = Get-Content -LiteralPath $script:UninstallPath -Raw
    if ($text -notmatch 'patch[0-9]+\.(fat|dat)') { return $false }
    $repl = 'patch' + $num + '.$1'
    $newText = [regex]::Replace($text, 'patch[0-9]+\.(fat|dat)', $repl)
    if ($newText -ne $text) {
        Set-Content -LiteralPath $script:UninstallPath -Value $newText -Encoding ASCII -NoNewline
    }
    return $true
}

function Invoke-Install([string]$dir) {
    if (-not (Test-Ready $dir '安装')) { return }
    $found = @(Get-Installed $dir)
    C ''
    if ($found.Count -gt 0) {
        $names = ($found | ForEach-Object { $_.Name }) -join ', '
        C ('   本补丁已经安装：' + $names) 'Green'
        C '   如需换编号请用 [3]。' 'Gray'
        return
    }
    $srcFat = Join-Path $script:BuildDir 'patch3.fat'
    $srcDat = Join-Path $script:BuildDir 'patch3.dat'
    if (-not (Test-Path -LiteralPath $srcFat) -or -not (Test-Path -LiteralPath $srcDat)) {
        C '   找不到 build\patch3.fat / patch3.dat，无法安装。' 'Red'
        return
    }
    $target = 3
    while (Test-Path -LiteralPath (Join-Path $dir ('patch{0}.fat' -f $target))) { $target++ }
    if ($target -ne 3) {
        C ('   注意：patch3 已被其它文件占用，本次安装为 patch' + $target + '。') 'Yellow'
    }
    $dstFat = Join-Path $dir ('patch{0}.fat' -f $target)
    $dstDat = Join-Path $dir ('patch{0}.dat' -f $target)
    try {
        Copy-Item -LiteralPath $srcFat -Destination $dstFat -Force -ErrorAction Stop
        Copy-Item -LiteralPath $srcDat -Destination $dstDat -Force -ErrorAction Stop
    } catch {
        C ('   安装失败：' + $_.Exception.Message) 'Red'
        C '   游戏正在运行时无法写入，请先退出游戏。' 'Yellow'
        return
    }
    if (Test-Pair $dstFat $dstDat) {
        C ('   安装完成：patch' + $target + '（下次启动游戏生效）') 'Green'
    } else {
        C '   安装后校验失败，请检查 build 里的文件是否完整。' 'Red'
    }
    if (Sync-UninstallName $target) {
        C ('   uninstall.cmd 已同步指向 patch' + $target) 'Green'
    }
}

function Invoke-Delete([string]$dir) {
    if (-not (Test-Ready $dir '删除')) { return }
    $found = @(Get-Installed $dir)
    C ''
    if ($found.Count -eq 0) {
        C '   没有找到本补丁（patchN.fat 52 字节 / patchN.dat 57892 字节）。' 'Yellow'
        return
    }
    foreach ($p in $found) {
        C ('   将删除 : ' + $p.Fat) 'Gray'
        C ('            ' + $p.Dat) 'Gray'
    }
    if (Get-GameRunning) { C '   注意：游戏正在运行，文件可能被占用。' 'Yellow' }
    $answer = Read-Host '   确认删除？输入 Y 确认，其它取消'
    if ($answer -notmatch '^[Yy]') { C '   已取消。' 'DarkYellow'; return }
    $ok = 0
    foreach ($p in $found) {
        try {
            Remove-Item -LiteralPath $p.Fat -Force -ErrorAction Stop
            Remove-Item -LiteralPath $p.Dat -Force -ErrorAction Stop
            $ok++
        } catch {
            C ('   删除失败：' + $_.Exception.Message) 'Red'
            C '   若提示拒绝访问，请右键以管理员身份运行本工具。' 'Yellow'
        }
    }
    if ($ok -gt 0) { C ('   完成：已删除 ' + $ok + ' 组补丁文件。') 'Green' }
}

function Rename-Pair([string]$dir, [int]$oldNum, [int]$newNum) {
    $fat  = Join-Path $dir ('patch{0}.fat' -f $oldNum)
    $dat  = Join-Path $dir ('patch{0}.dat' -f $oldNum)
    $nFat = Join-Path $dir ('patch{0}.fat' -f $newNum)
    $nDat = Join-Path $dir ('patch{0}.dat' -f $newNum)
    if (Test-Path -LiteralPath $nFat) { throw ('目标已存在：' + $nFat) }
    if (Test-Path -LiteralPath $nDat) { throw ('目标已存在：' + $nDat) }
    Rename-Item -LiteralPath $fat -NewName ('patch{0}.fat' -f $newNum) -ErrorAction Stop
    Rename-Item -LiteralPath $dat -NewName ('patch{0}.dat' -f $newNum) -ErrorAction Stop
}

function Invoke-Rename([string]$dir) {
    if (-not (Test-Ready $dir '改名')) { return }
    $found = @(Get-Installed $dir)
    C ''
    if ($found.Count -eq 0) {
        C '   没有找到本补丁，无法改名。' 'Yellow'
        return
    }
    if ($found.Count -gt 1) {
        C '   检测到多组本补丁文件，请先手动清理多余的再改名。' 'Yellow'
        return
    }
    $cur = $found[0]
    C '   命名规则：' 'Cyan'
    C '     · 必须是 patch<数字>.fat 与 patch<数字>.dat，同号成对' 'Gray'
    C '     · 数字 >= 3（patch、patch2 是游戏自带的）' 'Gray'
    C '     · 数字越大加载越晚，冲突时优先级越高' 'Gray'
    C '     · 多个 mod 共存时保持编号连续，本补丁使用最大编号' 'Gray'
    C ''
    C ('   当前编号 : patch' + $cur.Number) 'Green'
    $answer = Read-Host '   请输入新的编号（直接回车取消）'
    if ([string]::IsNullOrWhiteSpace($answer)) { C '   已取消。' 'DarkYellow'; return }
    if ($answer -notmatch '^[0-9]+$') { C '   编号只能是数字。' 'Red'; return }
    $newNum = [int]$answer
    if ($newNum -lt 3) { C '   编号必须 >= 3。' 'Red'; return }
    if ($newNum -eq $cur.Number) { C '   编号没有变化。' 'DarkYellow'; return }
    try {
        Rename-Pair $dir $cur.Number $newNum
    } catch {
        C ('   改名失败：' + $_.Exception.Message) 'Red'
        if (Get-GameRunning) { C '   游戏正在运行，请先退出游戏。' 'Yellow' }
        return
    }
    C ('   文件已改名 : patch' + $cur.Number + '  ->  patch' + $newNum) 'Green'
    if (Sync-UninstallName $newNum) {
        C '   uninstall.cmd 已同步更新。' 'Green'
    } else {
        C '   未找到 uninstall.cmd，请手动检查。' 'Yellow'
    }
    C '   提示：install.cmd 仍会把 build 里的 patch3 复制成 patch3。' 'DarkYellow'
}

function Invoke-SetPath {
    C ''
    C '   请输入《看门狗2》的游戏目录，或它的 data_win64 目录' 'Cyan'
    C '   例如：D:\Program Files (x86)\Steam\steamapps\common\Watch_Dogs2' 'Gray'
    $answer = Read-Host '   路径'
    if ([string]::IsNullOrWhiteSpace($answer)) { C '   已取消。' 'DarkYellow'; return }
    $p = $answer.Trim().Trim('"').TrimEnd('\')
    if (-not (Test-Path -LiteralPath $p)) {
        C ('   路径不存在：' + $p) 'Red'
        return
    }
    $candidate = $p
    $sub = Join-Path $candidate 'data_win64'
    if (Test-Path -LiteralPath (Join-Path $sub 'patch.fat')) { $candidate = $sub }
    $hasData = (Test-Path -LiteralPath (Join-Path $candidate 'patch.fat')) -or
               (Test-Path -LiteralPath (Join-Path $candidate 'shadersobj.fat')) -or
               ((@(Get-ChildItem -LiteralPath $candidate -Filter 'patch*.fat' -ErrorAction SilentlyContinue)).Count -gt 0)
    if (-not $hasData) {
        C '   这个目录里没找到 patch.fat / shadersobj.fat。' 'Red'
        C '   看起来不是《看门狗2》的 data_win64，请确认后重试。' 'Yellow'
        return
    }
    $script:GameDir = $candidate
    Save-GameDir $candidate
    C ('   已保存：' + $candidate) 'Green'
}

function Invoke-SelfTest {
    $fail = 0
    $t = Join-Path $env:TEMP ('wd2fix-test-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $t -Force | Out-Null
    try {
        Copy-Item -LiteralPath (Join-Path $script:BuildDir 'patch3.fat') -Destination (Join-Path $t 'patch3.fat')
        Copy-Item -LiteralPath (Join-Path $script:BuildDir 'patch3.dat') -Destination (Join-Path $t 'patch3.dat')
        $u = Join-Path $t 'uninstall.cmd'
        Set-Content -LiteralPath $u -Value 'del /F /Q "G:\WD2\data_win64\patch3.fat"' -Encoding ASCII
        $script:UninstallPath = $u

        $found = @(Get-Installed $t)
        if ($found.Count -eq 1 -and $found[0].Number -eq 3) { C '[PASS] detect patch3' 'Green' }
        else { C '[FAIL] detect patch3' 'Red'; $fail++ }

        $foreign = Join-Path $t 'patch7.fat'
        Set-Content -LiteralPath $foreign -Value 'not-ours' -Encoding ASCII
        if ((@(Get-Installed $t)).Count -eq 1) { C '[PASS] ignore foreign patch7' 'Green' }
        else { C '[FAIL] foreign file' 'Red'; $fail++ }
        Remove-Item -LiteralPath $foreign -Force

        if (Sync-UninstallName 4) {
            $c = Get-Content -LiteralPath $u -Raw
            if ($c -match 'patch4\.fat' -and $c -notmatch 'patch3') { C '[PASS] uninstall.cmd sync' 'Green' }
            else { C '[FAIL] uninstall content' 'Red'; $fail++ }
        } else { C '[FAIL] uninstall sync' 'Red'; $fail++ }

        Rename-Pair $t 3 4
        if ((Test-Path (Join-Path $t 'patch4.fat')) -and (Test-Path (Join-Path $t 'patch4.dat')) -and -not (Test-Path (Join-Path $t 'patch3.fat'))) {
            C '[PASS] rename 3 -> 4' 'Green'
        } else { C '[FAIL] rename' 'Red'; $fail++ }

        Rename-Pair $t 4 3
        if ((Test-Path (Join-Path $t 'patch3.fat')) -and (Test-Path (Join-Path $t 'patch3.dat'))) { C '[PASS] rename back 4 -> 3' 'Green' }
        else { C '[FAIL] rename back' 'Red'; $fail++ }

        Remove-Item -LiteralPath (Join-Path $t 'patch3.fat') -Force
        Remove-Item -LiteralPath (Join-Path $t 'patch3.dat') -Force
        if ((@(Get-Installed $t)).Count -eq 0) { C '[PASS] delete' 'Green' }
        else { C '[FAIL] delete' 'Red'; $fail++ }
    } finally {
        Remove-Item -LiteralPath $t -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($fail -eq 0) { C 'SELFTEST OK' 'Green'; exit 0 }
    C ('SELFTEST FAILED: ' + $fail) 'Red'
    exit 1
}

if ($SelfTest) { Invoke-SelfTest }

$script:GameDir = Read-GameDir

if ($Status) {
    Show-Header $script:GameDir
    exit 0
}

while ($true) {
    Clear-Host
    Show-Header $script:GameDir
    Show-Menu
    $choice = Read-Host '   请选择'
    switch ($choice) {
        '1' { Invoke-Install $script:GameDir }
        '2' { Invoke-Delete $script:GameDir }
        '3' { Invoke-Rename $script:GameDir }
        '4' { Invoke-SetPath }
        '0' { C ''; C '   再见。' 'DarkCyan'; return }
        default { C '   无效选项，请输入 0-4。' 'Red' }
    }
    if ($choice -ne '0') {
        C ''
        Read-Host '   按回车返回菜单' | Out-Null
    }
}
