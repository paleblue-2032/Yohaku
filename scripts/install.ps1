# Yohaku インストーラ（Windows）
#
#   irm https://raw.githubusercontent.com/paleblue-2032/yohaku/main/scripts/install.ps1 | iex
#
# 環境変数:
#   YOHAKU_VERSION … 入れるバージョン（既定: latest）
$ErrorActionPreference = 'Stop'

$repo = 'paleblue-2032/yohaku'
$version = if ($env:YOHAKU_VERSION) { $env:YOHAKU_VERSION } else { 'latest' }
$asset = 'yohaku-windows-x86_64.zip'

if ($version -eq 'latest') {
    $url = "https://github.com/$repo/releases/latest/download/$asset"
} else {
    $url = "https://github.com/$repo/releases/download/v$($version.TrimStart('v'))/$asset"
}

$dest = Join-Path $env:LOCALAPPDATA 'Programs\Yohaku'
$tmp = Join-Path $env:TEMP ("yohaku-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

Write-Host "Yohaku をダウンロードしています: $asset"
Invoke-WebRequest -Uri $url -OutFile (Join-Path $tmp $asset) -UseBasicParsing
Expand-Archive -Path (Join-Path $tmp $asset) -DestinationPath $tmp -Force

New-Item -ItemType Directory -Force -Path $dest | Out-Null
Copy-Item -Path (Join-Path $tmp '*') -Destination $dest -Recurse -Force

# ユーザーの PATH に追加（新しいターミナルから yohaku で起動できるように）
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($null -eq $userPath) { $userPath = '' }
if ($userPath -notlike "*$dest*") {
    [Environment]::SetEnvironmentVariable('Path', ($userPath.TrimEnd(';') + ';' + $dest), 'User')
    Write-Host "PATH に追加しました（新しいターミナルから 'yohaku' で起動できます）"
}

$exe = Join-Path $dest 'yohaku.exe'
if (Test-Path $exe) {
    # スタートメニューのショートカット
    $programs = [Environment]::GetFolderPath('Programs')
    $ws = New-Object -ComObject WScript.Shell
    $sc = $ws.CreateShortcut((Join-Path $programs 'Yohaku.lnk'))
    $sc.TargetPath = $exe
    $sc.WorkingDirectory = $dest
    $sc.IconLocation = "$exe,0"
    $sc.Save()
    Write-Host "スタートメニューに Yohaku を追加しました"

    # デスクトップのショートカット（任意）
    if ($env:YOHAKU_DESKTOP_SHORTCUT -eq '1') {
        $desktop = [Environment]::GetFolderPath('Desktop')
        $sc2 = $ws.CreateShortcut((Join-Path $desktop 'Yohaku.lnk'))
        $sc2.TargetPath = $exe
        $sc2.WorkingDirectory = $dest
        $sc2.Save()
    }
}

Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
Write-Host "インストール完了: $exe"
