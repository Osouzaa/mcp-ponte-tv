# Envia UMA tela deste PC para a maquina-ponte (ffplay em tela cheia ligado a TV por HDMI).
# FFmpeg (captura DXGI + encoder Intel QSV) -> UDP -> ponte. Este PC so ENVIA; nao abre nenhuma porta.
# Uso: espelhar-ponte.ps1 -Tela 1|2|3
param(
  [int]$Tela = 1,
  [string]$Destino = "",
  [int]$Porta = 5004,
  [int]$Fps = 60,
  [string]$Bitrate = "20M",
  [int]$Largura = 1920,
  [int]$Altura = 1080,
  [ValidateSet("qsv","x264")][string]$Encoder = "qsv"
)
# IP da ponte: parametro -Destino, ou $Ponte em config.local.ps1 (copie config.exemplo.ps1)
$cfg = Join-Path $PSScriptRoot 'config.local.ps1'; if (Test-Path $cfg) { . $cfg }
if (-not $PSBoundParameters.ContainsKey('Destino') -and $Ponte) { $Destino = $Ponte }
if (-not $Destino) { Write-Host "Defina o IP da ponte: copie config.exemplo.ps1 para config.local.ps1 e edite, ou use -Destino IP."; exit 1 }
$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')

$vf = "hwdownload,format=bgra,scale=${Largura}:${Altura}:force_original_aspect_ratio=decrease:flags=bicubic,format=nv12"
if ($Encoder -eq "qsv") {
  $enc = @("-c:v","h264_qsv","-preset","veryfast","-look_ahead","0","-async_depth","1","-bf","0","-profile:v","high","-forced_idr","1","-repeat_pps","1")
} else {
  $enc = @("-c:v","libx264","-preset","ultrafast","-tune","zerolatency","-bf","0","-x264-params","repeat-headers=1")
}
$ff = @("-hide_banner","-loglevel","error","-fflags","nobuffer","-f","lavfi","-i","ddagrab=output_idx=$($Tela-1):framerate=${Fps}:draw_mouse=1,$vf") `
    + $enc + @("-b:v",$Bitrate,"-maxrate",$Bitrate,"-bufsize","1M","-g",[Math]::Max(10,[int]($Fps/2)),"-pix_fmt","nv12",
    "-flush_packets","1","-muxdelay","0","-muxpreload","0","-pat_period","0.2","-f","mpegts","udp://${Destino}:${Porta}?pkt_size=1316")

$p = Start-Process ffmpeg -ArgumentList $ff -PassThru -WindowStyle Minimized
Write-Host "Enviando a Tela $Tela para $Destino (${Largura}x${Altura} @ ${Fps}fps, $Bitrate, $Encoder). Pressione Enter para parar."
Read-Host | Out-Null
Stop-Process -Id $p.Id -ErrorAction SilentlyContinue

