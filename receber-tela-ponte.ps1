# RODAR NA MAQUINA-PONTE (a que fica no HDMI da TV), como ADMINISTRADOR. Uma unica vez.
# O que faz:
#   1) instala o FFmpeg (traz o ffplay) via winget, se ainda nao houver;
#   2) cria regra de firewall: libera UDP 5004 SOMENTE para a faixa de IPs informada (-IpDoPcQueEnvia ou $FaixaLiberada em config.local.ps1);
#   3) cria o atalho "Receber tela" (tela cheia, baixa latencia). Quando a transmissao para, mostra uma
#      TELA DE ESPERA (nome, relogio, data, passos) e volta a exibir sozinho quando alguem transmitir.
# Visual da tela de espera: edite C:\ProgramData\ReceberTela\tema.json (nome, cores, logo, passos).
# Opcoes:
#   -IpDoPcQueEnvia "192.0.2.0/24","198.51.100.5" quem pode transmitir (IPs ou faixas CIDR; obrigatorio se nao houver config)
#   -AdicionarIp 192.0.2.99                      acrescenta mais um IP/faixa na regra existente
#   -TemaJson .\tema.local.json                  aplica um tema (nome, cores, logos) a tela de espera
#   -IniciarComWindows                           abre o "Receber tela" sozinho quando o Windows iniciar
#   -Remover                                     desfaz tudo
# Tela de espera: Esc (na espera) fecha o receptor. Para sair durante a transmissao, pare o envio primeiro.
param(
  [string[]]$IpDoPcQueEnvia = @(),
  [int]$Porta = 5004,
  [string]$AdicionarIp,
  [string]$TemaJson,
  [switch]$IniciarComWindows,
  [switch]$Remover
)
# faixa liberada: -IpDoPcQueEnvia ou $FaixaLiberada em config.local.ps1 (copie config.exemplo.ps1)
$cfg = Join-Path $PSScriptRoot 'config.local.ps1'; if (Test-Path $cfg) { . $cfg }
if ($IpDoPcQueEnvia.Count -eq 0 -and $FaixaLiberada) { $IpDoPcQueEnvia = @($FaixaLiberada) }
$ErrorActionPreference = "Stop"
$regra = "Receber tela (UDP $Porta)"
$pasta = Join-Path $env:ProgramData "ReceberTela"
$atalhoNome = "Receber tela.lnk"

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Write-Host "Execute este script como ADMINISTRADOR (botao direito no PowerShell > Executar como administrador)."; exit 1
}

if ($AdicionarIp) {
  if ($AdicionarIp -notmatch '^\d{1,3}(\.\d{1,3}){3}(/\d{1,2})?$') { Write-Host "IP/faixa invalido: $AdicionarIp"; exit 1 }
  $existente = Get-NetFirewallRule -DisplayName $regra -ErrorAction SilentlyContinue
  if (-not $existente) { Write-Host "Regra '$regra' nao existe. Rode o script sem parametros primeiro."; exit 1 }
  $atuais = @(($existente | Get-NetFirewallAddressFilter).RemoteAddress) | Where-Object { $_ -and $_ -ne "Any" }
  $novos = @($atuais + $AdicionarIp) | Select-Object -Unique
  Set-NetFirewallRule -DisplayName $regra -RemoteAddress $novos
  Write-Host "Liberados agora: $($novos -join ', ')"; exit 0
}

if ($Remover) {
  Remove-NetFirewallRule -DisplayName $regra -ErrorAction SilentlyContinue
  Remove-Item $pasta -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item (Join-Path ([Environment]::GetFolderPath("Desktop")) $atalhoNome) -ErrorAction SilentlyContinue
  Remove-Item (Join-Path ([Environment]::GetFolderPath("CommonStartup")) $atalhoNome) -ErrorAction SilentlyContinue
  Write-Host "Removido (o FFmpeg continua instalado; desinstale pelo winget se quiser)."; exit 0
}

function Atualizar-Path { $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User') }
Atualizar-Path
if (-not (Get-Command ffplay -ErrorAction SilentlyContinue)) {
  Write-Host "Instalando FFmpeg..."
  winget install --id Gyan.FFmpeg -e --silent --accept-package-agreements --accept-source-agreements
  Atualizar-Path
}
if ($IpDoPcQueEnvia.Count -eq 0) { Write-Host "Informe quem pode transmitir: -IpDoPcQueEnvia ""192.0.2.0/24"" (ou defina FaixaLiberada em config.local.ps1)."; exit 1 }
$ffplay = (Get-Command ffplay -ErrorAction SilentlyContinue).Source
if (-not $ffplay) {
  $ffplay = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages","$env:ProgramFiles" -Recurse -Filter ffplay.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $ffplay) { Write-Host "Nao encontrei o ffplay. Instale o FFmpeg manualmente e rode de novo."; exit 1 }
Write-Host "ffplay: $ffplay"

Remove-NetFirewallRule -DisplayName $regra -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName $regra -Direction Inbound -Protocol UDP -LocalPort $Porta -RemoteAddress $IpDoPcQueEnvia -Action Allow -Profile Any | Out-Null
Write-Host "Firewall: UDP $Porta liberado para $($IpDoPcQueEnvia -join ', ')"

# ---- receptor: tela de espera + ffplay (modelo; so ASCII; acentos por codigo de caractere ou \u no JSON) ----
$modelo = @'
param([switch]$Janela, [string]$Previa)
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$ffplay = '__FFPLAY__'
$porta  = __PORTA__
$pasta  = Join-Path $env:ProgramData 'ReceberTela'

# ---------- tema (editavel em tema.json; sem o arquivo, usa o padrao) ----------
$tema = [pscustomobject]@{
  subtitulo = 'ESPELHAMENTO DE TELA'
  nome = 'Tela na TV'
  corFundo1 = '#06122B'; corFundo2 = '#10347A'; corDestaque = '#6699FF'
  logo = ''; logoSecundario = ''
  passos = @(
    ('Abra o Transmitir-Tela no PC'),
    ('Escolha a tela e a qualidade'),
    ('Sua tela aparece aqui na TV')
  )
}
$arq = Join-Path $pasta 'tema.json'
if (Test-Path $arq) {
  try { $j = Get-Content $arq -Raw -Encoding UTF8 | ConvertFrom-Json; foreach ($p in 'subtitulo','nome','corFundo1','corFundo2','corDestaque','logo','logoSecundario','passos') { if ($null -ne $j.$p -and "$($j.$p)" -ne '') { $tema.$p = $j.$p } } } catch { }
}
function Carregar-Imagem($nome) {
  if (-not $nome) { return $null }
  $lp = $nome; if (-not [IO.Path]::IsPathRooted($lp)) { $lp = Join-Path $pasta $lp }
  if (Test-Path $lp) { try { return [System.Drawing.Image]::FromFile($lp) } catch { } }
  return $null
}
$logoImg = Carregar-Imagem $tema.logo                    # logo principal (vai num cartao branco)
$logoPref = Carregar-Imagem $tema.logoSecundario         # segundo logo, versao branca (rodape)

$ci = [Globalization.CultureInfo]::GetCultureInfo('pt-BR')
$aTil = [string][char]0x00E3
$msgEspera = 'Aguardando transmiss' + $aTil + 'o'
$meuIp = $null
try { $meuIp = (Get-NetIPConfiguration -ErrorAction Stop | Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' } | Select-Object -First 1).IPv4Address.IPAddress } catch { }
if (-not $meuIp) { $meuIp = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike '169.254*' -and $_.IPAddress -ne '127.0.0.1' } | Select-Object -First 1).IPAddress }
$script:sair = $false
$script:bg = $null
$cron = [Diagnostics.Stopwatch]::StartNew()

function Cor($hex, $alpha) { $c = [System.Drawing.ColorTranslator]::FromHtml($hex); [System.Drawing.Color]::FromArgb($alpha, $c.R, $c.G, $c.B) }
function Texto($g, $txt, $fonte, $cor, $x, $y, $w, $h, $alin) {
  $sf = New-Object System.Drawing.StringFormat
  $sf.Alignment = $alin; $sf.LineAlignment = 'Center'; $sf.Trimming = 'EllipsisCharacter'
  $br = New-Object System.Drawing.SolidBrush $cor
  $g.DrawString($txt, $fonte, $br, (New-Object System.Drawing.RectangleF($x, $y, $w, $h)), $sf)
  $br.Dispose(); $sf.Dispose()
}

function Desenhar($g, $w, $h, $t) {
  $s = $h / 1080.0
  $g.SmoothingMode = 'AntiAlias'
  $g.TextRenderingHint = 'AntiAliasGridFit'
  # fundo em degrade (guardado em cache; so refaz se o tamanho mudar)
  if (-not $script:bg -or $script:bg.Width -ne $w -or $script:bg.Height -ne $h) {
    if ($script:bg) { $script:bg.Dispose() }
    $script:bg = New-Object System.Drawing.Bitmap $w, $h
    $gb = [System.Drawing.Graphics]::FromImage($script:bg)
    $rc = New-Object System.Drawing.Rectangle 0, 0, $w, $h
    $lg = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rc, (Cor $tema.corFundo1 255), (Cor $tema.corFundo2 255), 35.0
    $gb.FillRectangle($lg, $rc); $lg.Dispose(); $gb.Dispose()
  }
  $g.DrawImage($script:bg, 0, 0, $w, $h)

  # circulos suaves em movimento lento (efeito sutil)
  for ($i = 0; $i -lt 3; $i++) {
    $r = $h * (0.34 + 0.10 * $i)
    $cx = $w * (0.18 + 0.32 * $i) + [Math]::Sin($t * 0.17 + $i * 2.1) * $w * 0.05
    $cy = $h * (0.28 + 0.30 * ($i % 2)) + [Math]::Cos($t * 0.13 + $i * 1.3) * $h * 0.05
    $br = New-Object System.Drawing.SolidBrush (Cor $tema.corDestaque (14 + 4 * $i))
    $g.FillEllipse($br, [single]($cx - $r), [single]($cy - $r), [single](2 * $r), [single](2 * $r)); $br.Dispose()
  }

  # faixa tricolor no topo
  $fx = @('#FFC400', '#36CC99', '#6699FF'); $tw = $w / 3.0
  for ($i = 0; $i -lt 3; $i++) { $tb = New-Object System.Drawing.SolidBrush (Cor $fx[$i] 255); $g.FillRectangle($tb, [single]($i * $tw), 0, [single]($tw + 1), [single](10 * $s)); $tb.Dispose() }

  # logo principal (cartao branco arredondado, para logos escuros ficarem legiveis no fundo escuro)
  $y0 = 150 * $s
  if ($logoImg) {
    $lh = 170 * $s; $lw = $logoImg.Width * ($lh / $logoImg.Height)
    $cw2 = $lw + 70 * $s; $ch2 = $lh + 40 * $s; $cx2 = ($w - $cw2) / 2; $cy2 = 50 * $s
    $cp = New-Object System.Drawing.Drawing2D.GraphicsPath; $d = 40 * $s
    $cp.AddArc([single]$cx2, [single]$cy2, [single]$d, [single]$d, 180, 90); $cp.AddArc([single]($cx2 + $cw2 - $d), [single]$cy2, [single]$d, [single]$d, 270, 90)
    $cp.AddArc([single]($cx2 + $cw2 - $d), [single]($cy2 + $ch2 - $d), [single]$d, [single]$d, 0, 90); $cp.AddArc([single]$cx2, [single]($cy2 + $ch2 - $d), [single]$d, [single]$d, 90, 90); $cp.CloseFigure()
    $wb = New-Object System.Drawing.SolidBrush (Cor '#FFFFFF' 245); $g.FillPath($wb, $cp); $wb.Dispose(); $cp.Dispose()
    $g.DrawImage($logoImg, [single]($cx2 + 35 * $s), [single]($cy2 + 20 * $s), [single]$lw, [single]$lh)
    $y0 = $cy2 + $ch2 + 25 * $s
  }

  # nome / subtitulo
  $fSub = New-Object System.Drawing.Font('Segoe UI Semibold', [single](24 * $s), [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
  $fNome = New-Object System.Drawing.Font('Segoe UI Semibold', [single](78 * $s), [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
  Texto $g ($tema.subtitulo.ToUpper()) $fSub (Cor $tema.corDestaque 255) 0 $y0 $w (40 * $s) 'Center'
  Texto $g $tema.nome $fNome (Cor '#FFFFFF' 255) 0 ($y0 + 40 * $s) $w (110 * $s) 'Center'
  $pen = New-Object System.Drawing.Pen (Cor $tema.corDestaque 255), ([single](4 * $s))
  $g.DrawLine($pen, [single]($w / 2 - 60 * $s), [single]($y0 + 175 * $s), [single]($w / 2 + 60 * $s), [single]($y0 + 175 * $s)); $pen.Dispose()

  # relogio e data
  $agora = Get-Date
  $fRel = New-Object System.Drawing.Font('Segoe UI Light', [single](210 * $s), [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
  $fData = New-Object System.Drawing.Font('Segoe UI', [single](38 * $s), [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
  $yr = $y0 + 200 * $s
  Texto $g ($agora.ToString('HH:mm')) $fRel (Cor '#FFFFFF' 255) 0 $yr $w (250 * $s) 'Center'
  $data = $agora.ToString("dddd, d 'de' MMMM 'de' yyyy", $ci)
  $data = $data.Substring(0, 1).ToUpper() + $data.Substring(1)
  Texto $g $data $fData (Cor '#FFFFFF' 215) 0 ($yr + 245 * $s) $w (60 * $s) 'Center'

  # faixa "Aguardando transmissao" com ponto pulsante
  $fAg = New-Object System.Drawing.Font('Segoe UI Semibold', [single](30 * $s), [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
  $pw = 520 * $s; $ph = 70 * $s; $px = ($w - $pw) / 2; $py = $h - 300 * $s
  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  $rr = $ph / 2
  $path.AddArc([single]$px, [single]$py, [single]$ph, [single]$ph, 90, 180)
  $path.AddArc([single]($px + $pw - $ph), [single]$py, [single]$ph, [single]$ph, 270, 180)
  $path.CloseFigure()
  $fb = New-Object System.Drawing.SolidBrush (Cor '#FFFFFF' 22); $g.FillPath($fb, $path); $fb.Dispose()
  $bp = New-Object System.Drawing.Pen (Cor $tema.corDestaque 150), ([single](2 * $s)); $g.DrawPath($bp, $path); $bp.Dispose(); $path.Dispose()
  $pulso = [int](140 + 115 * (0.5 + 0.5 * [Math]::Sin($t * 3.0)))
  $db = New-Object System.Drawing.SolidBrush (Cor $tema.corDestaque $pulso)
  $g.FillEllipse($db, [single]($px + 38 * $s), [single]($py + $ph / 2 - 9 * $s), [single](18 * $s), [single](18 * $s)); $db.Dispose()
  Texto $g $msgEspera $fAg (Cor '#FFFFFF' 255) ($px + 70 * $s) $py ($pw - 90 * $s) $ph 'Center'

  # passos (3 colunas)
  $fN = New-Object System.Drawing.Font('Segoe UI Semibold', [single](30 * $s), [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
  $fP = New-Object System.Drawing.Font('Segoe UI', [single](26 * $s), [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
  $passos = @($tema.passos)
  $n = [Math]::Min(3, $passos.Count)
  if ($n -gt 0) {
    $cw = ($w * 0.86) / $n; $x0 = $w * 0.07; $yp = $h - 180 * $s
    for ($i = 0; $i -lt $n; $i++) {
      $cxp = $x0 + $i * $cw
      $cb = New-Object System.Drawing.SolidBrush (Cor $tema.corDestaque 255)
      $g.FillEllipse($cb, [single]($cxp + 12 * $s), [single]($yp + 8 * $s), [single](56 * $s), [single](56 * $s)); $cb.Dispose()
      Texto $g ([string]($i + 1)) $fN (Cor $tema.corFundo1 255) ($cxp + 12 * $s) ($yp + 8 * $s) (56 * $s) (56 * $s) 'Center'
      Texto $g ([string]$passos[$i]) $fP (Cor '#FFFFFF' 225) ($cxp + 82 * $s) $yp ($cw - 100 * $s) (72 * $s) 'Near'
    }
  }
  # segundo logo (versao branca, ex.: instituicao) no canto inferior esquerdo
  if ($logoPref) {
    $ph2 = 70 * $s; $pw2 = $logoPref.Width * ($ph2 / $logoPref.Height)
    $g.DrawImage($logoPref, [single](40 * $s), [single]($h - $ph2 - 30 * $s), [single]$pw2, [single]$ph2)
  }
  # IP da maquina (apoio a suporte)
  $fIp = New-Object System.Drawing.Font('Segoe UI', [single](20 * $s), [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
  Texto $g ('Ponte: ' + $meuIp) $fIp (Cor '#FFFFFF' 110) 0 ($h - 56 * $s) ($w - 40 * $s) (36 * $s) 'Far'
  foreach ($f in $fSub, $fNome, $fRel, $fData, $fAg, $fN, $fP, $fIp) { $f.Dispose() }
}

if ($Previa) {
  $bmp = New-Object System.Drawing.Bitmap 1920, 1080
  $gg = [System.Drawing.Graphics]::FromImage($bmp)
  Desenhar $gg 1920 1080 4.0
  $gg.Dispose(); $bmp.Save($Previa, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
  return
}

# ---------- repassador UDP: o receptor e dono da porta, sabe quando chegou o ultimo pacote e repassa ao ffplay (localhost) ----------
$cs = @"
using System;
using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Threading;
public class UdpRelay {
  private Socket rx; private Socket tx; private IPEndPoint dest; private Thread th;
  private volatile bool run; private long last; private long count;
  public volatile bool Forward;
  public UdpRelay(int port, int destPort) {
    dest = new IPEndPoint(IPAddress.Loopback, destPort);
    rx = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp);
    rx.ReceiveBufferSize = 4 * 1024 * 1024;
    rx.Bind(new IPEndPoint(IPAddress.Any, port));
    tx = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp);
  }
  public void Start() { run = true; th = new Thread(Loop); th.IsBackground = true; th.Start(); }
  private void Loop() {
    byte[] buf = new byte[65536];
    while (run) {
      try {
        int n = rx.Receive(buf);
        Interlocked.Exchange(ref last, Stopwatch.GetTimestamp());
        Interlocked.Increment(ref count);
        if (Forward) { tx.SendTo(buf, 0, n, SocketFlags.None, dest); }
      } catch (SocketException) { if (!run) break; }
      catch (ObjectDisposedException) { break; }
    }
  }
  public double AgeSeconds { get {
    if (Interlocked.Read(ref count) == 0) return 1e9;
    return (Stopwatch.GetTimestamp() - Interlocked.Read(ref last)) / (double)Stopwatch.Frequency; } }
  public void Stop() { run = false; try { rx.Close(); } catch (Exception) {} try { tx.Close(); } catch (Exception) {} }
}
"@
Add-Type -TypeDefinition $cs
$relay = $null
for ($i = 0; $i -lt 20 -and -not $relay; $i++) { try { $relay = New-Object UdpRelay($porta, ($porta + 1)) } catch { Start-Sleep -Seconds 1 } }
if (-not $relay) { [System.Windows.Forms.MessageBox]::Show('Nao foi possivel abrir a porta UDP ' + $porta + ' (outro programa esta usando?).', 'Receber tela') | Out-Null; exit 1 }
$relay.Start()

function Mostrar-Espera {
  $script:ticks = 0
  $f = New-Object System.Windows.Forms.Form
  $script:form = $f
  $f.Text = 'Receber tela - espera'
  $f.BackColor = [System.Drawing.Color]::Black
  $f.KeyPreview = $true
  # buffer duplo (evita piscar): DoubleBuffered e SetStyle sao membros protegidos, entao via reflexao
  $bf = [System.Reflection.BindingFlags]'Instance,NonPublic'
  $f.GetType().GetProperty('DoubleBuffered', $bf).SetValue($f, $true, $null)
  $f.GetType().GetMethod('SetStyle', $bf).Invoke($f, @([System.Windows.Forms.ControlStyles]'AllPaintingInWmPaint,UserPaint,OptimizedDoubleBuffer', $true))
  if ($Janela) { $f.ClientSize = New-Object System.Drawing.Size(960, 540); $f.StartPosition = 'CenterScreen' }
  else { $f.FormBorderStyle = 'None'; $f.WindowState = 'Maximized'; $f.TopMost = $true }
  $f.Add_Paint({ param($sender, $e) Desenhar $e.Graphics $sender.ClientSize.Width $sender.ClientSize.Height $cron.Elapsed.TotalSeconds })
  $f.Add_KeyDown({ if ($_.KeyCode -eq 'Escape') { $script:sair = $true; $script:form.Close() } })
  $t = New-Object System.Windows.Forms.Timer
  $t.Interval = 66
  $t.Add_Tick({
    $script:form.Invalidate()
    if ($relay.AgeSeconds -lt 0.8) { $script:form.Close() }   # chegou video: sai da espera
  })
  $t.Start()
  if (-not $Janela) { [System.Windows.Forms.Cursor]::Hide() }
  [void]$f.ShowDialog()
  if (-not $Janela) { [System.Windows.Forms.Cursor]::Show() }
  $t.Stop(); $t.Dispose()
  $f.Dispose()
}

while (-not $script:sair) {
  Mostrar-Espera
  if ($script:sair) { break }
  $fa = @('-hide_banner','-loglevel','error')
  if (-not $Janela) { $fa += '-fs' }
  $fa += @('-autoexit','-fflags','nobuffer','-flags','low_delay','-framedrop','-probesize','32','-analyzeduration','0','-strict','experimental','-vf','setpts=0','-window_title','TelaRecebida',('udp://127.0.0.1:' + ($porta + 1) + '?fifo_size=1000000&overrun_nonfatal=1'))
  $relay.Forward = $true
  $p = Start-Process -FilePath $ffplay -ArgumentList $fa -PassThru
  # Vigia exato: se passam 3 s sem NENHUM pacote na porta, a transmissao parou -> fecha o ffplay (ele nao sai sozinho e congelaria na ultima imagem)
  $ini = [Diagnostics.Stopwatch]::StartNew()
  while ($true) {
    Start-Sleep -Milliseconds 400
    if ($relay.AgeSeconds -gt 3) { break }
    if ($ini.Elapsed.TotalSeconds -gt 5 -and -not (Get-Process -Name ffplay -ErrorAction SilentlyContinue)) { break }   # janela fechada a mao
  }
  $relay.Forward = $false
  # o ffplay do winget e um atalho que abre o programa real: encerra pelo nome (maquina dedicada a ponte)
  Get-Process -Name ffplay -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep -Milliseconds 500
  # volta para a tela de espera
}
$relay.Stop()
'@
New-Item -ItemType Directory -Force $pasta | Out-Null
$launcher = Join-Path $pasta "receber.ps1"
$modelo.Replace('__FFPLAY__', $ffplay).Replace('__PORTA__', "$Porta") | Set-Content $launcher -Encoding UTF8

# tema.json padrao (so cria se ainda nao existir; assim suas edicoes sao preservadas). Acentos como \uXXXX.
$temaArq = Join-Path $pasta "tema.json"
if ($TemaJson) {
  if (Test-Path $TemaJson) { Copy-Item $TemaJson $temaArq -Force; Write-Host "Tema aplicado: $TemaJson" } else { Write-Host "Arquivo de tema nao encontrado: $TemaJson" }
}
if (-not (Test-Path $temaArq)) {
@'
{
  "subtitulo": "ESPELHAMENTO DE TELA",
  "nome": "Tela na TV",
  "corFundo1": "#06122B",
  "corFundo2": "#10347A",
  "corDestaque": "#6699FF",
  "logo": "",
  "logoSecundario": "",
  "passos": [
    "Abra o Transmitir-Tela no PC",
    "Escolha a tela e a qualidade",
    "Sua tela aparece aqui na TV"
  ]
}
'@ | Set-Content $temaArq -Encoding UTF8
  Write-Host "Tema criado em $temaArq (edite para colocar logo e cores oficiais)."
}

function Novo-Atalho($caminho) {
  $lnk = (New-Object -ComObject WScript.Shell).CreateShortcut($caminho)
  $lnk.TargetPath = "powershell.exe"
  $lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$launcher`""
  $lnk.IconLocation = "shell32.dll,18"
  $lnk.Save()
}
Novo-Atalho (Join-Path ([Environment]::GetFolderPath("Desktop")) $atalhoNome)
if ($IniciarComWindows) {
  Novo-Atalho (Join-Path ([Environment]::GetFolderPath("CommonStartup")) $atalhoNome)
  Write-Host "O 'Receber tela' vai abrir sozinho quando o Windows iniciar."
}
Write-Host "Pronto. De duplo clique em 'Receber tela' (ou reinicie, se usou -IniciarComWindows). Quando ninguem transmite, a TV mostra a tela de espera."



