# Transmitir-Tela.ps1 - envia a SUA tela para a TV (maquina-ponte). Nao precisa ser administrador.
# Uso normal: de duplo clique em "Transmitir-Tela.bat".
# Obs.: so ASCII neste arquivo de proposito (evita erro de acentos no PowerShell 5.1).

# ---------- CONFIGURACAO (so o responsavel muda) ----------
# O IP da ponte fica em "config.local.ps1" (ao lado deste arquivo), ex.:   $Ponte = "192.0.2.10"
$Destino = ""
$Porta   = 5004             # porta UDP da ponte
$cfg = Join-Path $PSScriptRoot 'config.local.ps1'
if (Test-Path $cfg) { . $cfg; if ($Ponte) { $Destino = $Ponte } }
# ----------------------------------------------------------

$ErrorActionPreference = "Stop"
function Atualizar-Path { $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User') }
function Pausa-Sair($m) { Write-Host ""; Write-Host $m -ForegroundColor Yellow; Read-Host "Pressione Enter para fechar" | Out-Null; exit 1 }
if (-not $Destino) { Pausa-Sair "IP da ponte nao configurado. Crie o arquivo config.local.ps1 ao lado deste script (veja config.exemplo.ps1)." }

Clear-Host
Write-Host "=== Transmitir minha tela para a TV ===" -ForegroundColor Cyan
Write-Host ""

# 1) FFmpeg
Atualizar-Path
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
  Write-Host "O FFmpeg (programa que envia a imagem) nao esta instalado neste computador."
  $r = Read-Host "Instalar agora? (S/N)"
  if ($r -notmatch '^[sSyY]') { Pausa-Sair "Sem o FFmpeg nao e possivel transmitir." }
  winget install --id Gyan.FFmpeg -e --silent --accept-package-agreements --accept-source-agreements
  Atualizar-Path
  if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) { Pausa-Sair "Instalado, mas o Windows ainda nao enxerga o FFmpeg. Feche esta janela e abra o atalho de novo." }
}

# 2) Ponte alcancavel e IP de origem
$ip = $null
try { $ip = (Find-NetRoute -RemoteIPAddress $Destino -ErrorAction Stop | Where-Object { $_.IPAddress } | Select-Object -First 1).IPAddress } catch {}
if (-not (Test-Connection $Destino -Count 1 -Quiet)) {
  Write-Host "Aviso: a maquina-ponte ($Destino) nao respondeu. Ela esta ligada e na mesma rede?" -ForegroundColor Yellow
}
Write-Host "Seu IP: $ip   ->   Ponte: $Destino"
Write-Host "(Se a imagem nao aparecer na TV, peca ao responsavel para liberar o seu IP na ponte.)"
Write-Host ""

# 3) Escolher a tela
Add-Type -AssemblyName System.Windows.Forms
$telas = [System.Windows.Forms.Screen]::AllScreens
Write-Host "Telas deste computador:"
for ($i = 0; $i -lt $telas.Count; $i++) {
  $p = if ($telas[$i].Primary) { " (principal)" } else { "" }
  Write-Host ("  {0}) {1}x{2}{3}" -f ($i+1), $telas[$i].Bounds.Width, $telas[$i].Bounds.Height, $p)
}
$n = 1
if ($telas.Count -gt 1) {
  $n = [int](Read-Host "Qual tela transmitir? (numero)")
  if ($n -lt 1 -or $n -gt $telas.Count) { Pausa-Sair "Numero de tela invalido." }
}
Write-Host "Se aparecer a tela errada na TV, pare e rode de novo escolhendo outro numero." -ForegroundColor DarkGray
Write-Host ""

# 4) Qualidade
Write-Host "Qualidade:"
Write-Host "  1) Alta    - 1080p, 60 fps (PC bom, rede por cabo)"
Write-Host "  2) Normal  - 1080p, 30 fps (recomendado)"
Write-Host "  3) Leve    - 720p, 30 fps (PC mais fraco ou Wi-Fi)"
$q = Read-Host "Escolha (Enter = 2)"
switch ($q) {
  "1" { $Fps = 60; $W = 1920; $H = 1080; $Br = "20M" }
  "3" { $Fps = 30; $W = 1280; $H = 720;  $Br = "6M" }
  default { $Fps = 30; $W = 1920; $H = 1080; $Br = "10M" }
}

# 5) Escolher encoder (hardware se houver, senao software)
$enc = $null
$candidatos = @(
  @{ nome = "Intel QSV";  args = @("-c:v","h264_qsv","-preset","veryfast","-look_ahead","0","-async_depth","1","-bf","0","-profile:v","high") },
  @{ nome = "NVIDIA";     args = @("-c:v","h264_nvenc","-preset","p1","-tune","ll","-zerolatency","1","-bf","0") },
  @{ nome = "AMD";        args = @("-c:v","h264_amf","-usage","ultralowlatency","-bf","0") },
  @{ nome = "Software";   args = @("-c:v","libx264","-preset","ultrafast","-tune","zerolatency","-bf","0") }
)
foreach ($c in $candidatos) {
  $teste = @("-hide_banner","-loglevel","error","-f","lavfi","-i","color=c=black:s=640x360:r=30","-frames:v","5") + $c.args + @("-pix_fmt","yuv420p","-f","null","-")
  & ffmpeg @teste 2>$null
  if ($LASTEXITCODE -eq 0) { $enc = $c; break }
}
if (-not $enc) { Pausa-Sair "Nao encontrei nenhum encoder de video funcionando." }
Write-Host ("Encoder: " + $enc.nome)

# 6) Transmitir
$vf = "hwdownload,format=bgra,scale=${W}:${H}:force_original_aspect_ratio=decrease:flags=bicubic,format=nv12"
$ff = @("-hide_banner","-loglevel","error","-fflags","nobuffer","-f","lavfi","-i","ddagrab=output_idx=$($n-1):framerate=${Fps}:draw_mouse=1,$vf") `
    + $enc.args + @("-b:v",$Br,"-maxrate",$Br,"-bufsize","1M","-g",$Fps,"-pix_fmt","nv12",
    "-flush_packets","1","-muxdelay","0","-muxpreload","0","-pat_period","0.2","-f","mpegts","udp://${Destino}:${Porta}?pkt_size=1316")
$proc = Start-Process ffmpeg -ArgumentList $ff -PassThru -WindowStyle Minimized
Start-Sleep 2
if ($proc.HasExited) { Pausa-Sair "A transmissao nao iniciou. Tente a qualidade 'Leve' ou outra tela." }

Write-Host ""
Write-Host "TRANSMITINDO a tela $n para a TV." -ForegroundColor Green
Write-Host "Na ponte, o atalho 'Receber tela' precisa estar aberto."
Write-Host "Para PARAR, pressione Enter nesta janela."
Read-Host | Out-Null
Stop-Process -Id $proc.Id -ErrorAction SilentlyContinue
Write-Host "Transmissao encerrada."
Start-Sleep 2

