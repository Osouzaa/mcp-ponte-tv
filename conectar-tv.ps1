# Abre o receptor Miracast na TV Android (via ADB) e o painel Win + K no PC.
# Endereco da TV: $TvEndereco em config.local.ps1 (copie config.exemplo.ps1), ex.: "192.0.2.20:5555"
$cfg = Join-Path $PSScriptRoot 'config.local.ps1'; if (Test-Path $cfg) { . $cfg }
$tv = $TvEndereco
if (-not $tv) { Write-Host "Defina TvEndereco em config.local.ps1 (veja config.exemplo.ps1)."; exit 1 }
$adb = (Get-Command adb -ErrorAction SilentlyContinue).Source
if (-not $adb) { $adb = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\adb.exe" }

Write-Host "Conectando na TV $tv ..."
& $adb connect $tv | Out-Null
$ok = (& $adb devices) -match [regex]::Escape($tv) + "\s+device"
if (-not $ok) { Write-Host "TV nao respondeu (ligada? mesma rede?)"; Start-Sleep 5; exit 1 }

& $adb -s $tv shell "input keyevent KEYCODE_WAKEUP; am start -n com.droidlogic.miracast/.WiFiDirectMainActivity" | Out-Null
Write-Host "Receptor Miracast aberto na TV. Abrindo Win + K..."
Start-Process "ms-settings-connectabledevices:devicediscovery"
Start-Sleep 2
