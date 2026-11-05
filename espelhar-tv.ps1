# Espelha UMA tela do PC na TV com baixa latencia: FFmpeg (captura DXGI + encoder Intel QSV) -> UDP -> VLC na TV.
# Uso: espelhar-tv.ps1 -Tela 1|2|3   (1 = principal, 2 e 3 = demais, na ordem do Windows)
# UDP: o PC so ENVIA para o IP da TV (nao abre nenhuma porta no PC) e nao forma fila: o que a TV nao consegue mostrar e descartado.
# -Tunel: usa TCP por tunel ADB (adb reverse), so em 127.0.0.1, mais sujeito a acumular atraso.
param(
  [int]$Tela = 1,
  [string]$Tv = "",
  [int]$Fps = 30,
  [string]$Bitrate = "6M",
  [int]$Largura = 1280,
  [int]$Altura = 720,
  [ValidateSet("qsv","x264")][string]$Encoder = "qsv",
  [switch]$Tunel
)
# Endereco da TV: parametro -Tv, ou $TvEndereco em config.local.ps1 (copie config.exemplo.ps1)
$cfg = Join-Path $PSScriptRoot 'config.local.ps1'; if (Test-Path $cfg) { . $cfg }
if (-not $PSBoundParameters.ContainsKey('Tv') -and $TvEndereco) { $Tv = $TvEndereco }
if (-not $Tv) { Write-Host "Defina o endereco da TV: config.local.ps1 (veja config.exemplo.ps1) ou -Tv IP:porta."; exit 1 }
$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
$porta = 5004
$tvIp = ($Tv -split ':')[0]

Write-Host "Conectando na TV $Tv ..."
adb connect $Tv | Out-Null
if (-not ((adb devices) -match ([regex]::Escape($Tv) + "\s+device"))) { Write-Host "TV nao respondeu (IP mudou? ligada?)"; Start-Sleep 6; exit 1 }
adb -s $Tv shell "input keyevent KEYCODE_WAKEUP" | Out-Null

# Captura da tela escolhida; mantem proporcao e cabe em Largura x Altura
$vf = "hwdownload,format=bgra,scale=${Largura}:${Altura}:force_original_aspect_ratio=decrease:flags=fast_bilinear,format=nv12"
if ($Encoder -eq "qsv") {
  $enc = @("-c:v","h264_qsv","-preset","veryfast","-look_ahead","0","-async_depth","1","-bf","0")
} else {
  $enc = @("-c:v","libx264","-preset","ultrafast","-tune","zerolatency","-bf","0")
}
if ($Tunel) {
  adb -s $Tv reverse "tcp:8554" "tcp:8554" | Out-Null
  $saida = @("-flush_packets","1","-muxdelay","0","-muxpreload","0","-f","mpegts","-listen","1","http://127.0.0.1:8554/")
  $urlTv = "http://127.0.0.1:8554/"
} else {
  $saida = @("-flush_packets","1","-muxdelay","0","-muxpreload","0","-pat_period","0.2","-f","mpegts","udp://${tvIp}:${porta}?pkt_size=1316")
  $urlTv = "udp://@:$porta"
}
$ff = @("-hide_banner","-loglevel","error","-fflags","nobuffer","-f","lavfi","-i","ddagrab=output_idx=$($Tela-1):framerate=${Fps}:draw_mouse=1,$vf") `
    + $enc + @("-b:v",$Bitrate,"-maxrate",$Bitrate,"-bufsize","1M","-g",$Fps,"-pix_fmt","nv12") + $saida

if ($Tunel) {
  $p = Start-Process ffmpeg -ArgumentList $ff -PassThru -WindowStyle Minimized
  Start-Sleep 2
  adb -s $Tv shell "am start -a android.intent.action.VIEW -d $urlTv -t video/mp2t -p org.videolan.vlc" | Out-Null
} else {
  # UDP: o VLC precisa estar ouvindo antes do FFmpeg comecar a enviar
  adb -s $Tv shell "am start -a android.intent.action.VIEW -d $urlTv -t video/mp2t -p org.videolan.vlc" | Out-Null
  Start-Sleep 3
  $p = Start-Process ffmpeg -ArgumentList $ff -PassThru -WindowStyle Minimized
}
$modo = if ($Tunel) { "TCP tunel ADB" } else { "UDP -> $tvIp" }
Write-Host "Espelhando a Tela $Tela (${Largura}x${Altura} @ ${Fps}fps, $Bitrate, $Encoder, $modo). Pressione Enter para parar."
Read-Host | Out-Null
Stop-Process -Id $p.Id -ErrorAction SilentlyContinue
if ($Tunel) { adb -s $Tv reverse --remove "tcp:8554" | Out-Null }
adb -s $Tv shell "input keyevent KEYCODE_HOME" | Out-Null
