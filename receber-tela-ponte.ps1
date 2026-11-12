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
  # abriu sem administrador (ex.: duplo clique): reabre elevado, com as mesmas opcoes, e deixa a janela aberta para ler mensagens/erros
  $al = @('-NoProfile','-ExecutionPolicy','Bypass','-NoExit','-File',('"' + $PSCommandPath + '"'))
  foreach ($k in $PSBoundParameters.Keys) {
    $v = $PSBoundParameters[$k]
    if ($v -is [System.Management.Automation.SwitchParameter]) { if ($v.IsPresent) { $al += "-$k" } }
    else { $al += "-$k"; $al += ('"' + (@($v) -join ',') + '"') }
  }
  if ($PSBoundParameters.Count -eq 0) {   # duplo clique puro: instala com os padroes (iniciar com o Windows + tema local, se houver)
    $al += '-IniciarComWindows'
    $tl = Join-Path $PSScriptRoot 'tema.local.json'; if (Test-Path $tl) { $al += '-TemaJson'; $al += ('"' + $tl + '"') }
  }
  Write-Host "Pedindo permissao de administrador..."
  try { Start-Process powershell.exe -Verb RunAs -ArgumentList $al } catch { Write-Host "Permissao negada. Clique com o botao direito no PowerShell > Executar como administrador." }
  Start-Sleep 3; exit
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
  Unregister-ScheduledTask -TaskName "ReceberTela-Jira" -Confirm:$false -ErrorAction SilentlyContinue
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
param([switch]$Janela, [string]$Previa, [string]$Pauta, [string]$Jira, [string]$Hora, [string]$Aba)
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

# ---------- pauta / reunioes (pauta.json; recarrega sozinho a cada ~20 s, sem reiniciar) ----------
$pautaArq = Join-Path $pasta 'pauta.json'
if ($Pauta) { $pautaArq = $Pauta }
# tarefas vindas do Jira (gravadas por Sincronizar-Jira.ps1); se existir, tem prioridade sobre "tarefas" do pauta.json
$jiraArq = Join-Path $pasta 'jira-tarefas.json'
if ($Jira) { $jiraArq = $Jira }
$script:dadosPauta = $null; $script:pautaMtime = $null; $script:pautaChk = [datetime]::MinValue
function Agora-Hora { if ($Hora) { return [datetime]::ParseExact($Hora, 'HH:mm', $null) }; return (Get-Date) }
# tarefas da equipe: status = a fazer | em andamento | aguardando validacao | pausada | bloqueada | concluida (ordem de exibicao: bloqueada, andamento, validacao, a fazer, pausada, concluida)
function Converter-Tarefas($lista) {
  $tars = @(); $ix = 0
  foreach ($tk in @($lista)) {
    if (-not $tk.titulo) { continue }
    $st = "$($tk.status)".ToLower()
    $ord = 3; $cod = 'fazer'
    if ($st -like 'conclu*' -or $st -like 'feit*' -or $st -like 'pronto*') { $ord = 5; $cod = 'ok' }
    elseif ($st -like 'bloq*' -or $st -like 'impedi*') { $ord = 0; $cod = 'bloq' }
    elseif ($st -like '*valida*') { $ord = 2; $cod = 'val' }
    elseif ($st -like 'paus*') { $ord = 4; $cod = 'paus' }
    elseif ($st -like '*andamento*' -or $st -like 'fazendo*') { $ord = 1; $cod = 'and' }
    $alta = 0; if ("$($tk.prioridade)".ToLower() -like 'alt*') { $alta = 1 }
    $tars += [pscustomobject]@{ titulo = "$($tk.titulo)"; chave = "$($tk.chave)"; resp = "$($tk.responsavel)"; prazo = "$($tk.prazo)"; cod = $cod; ord = $ord; alta = $alta; idx = $ix }
    $ix++
  }
  return @($tars | Sort-Object ord, @{ Expression = 'alta'; Descending = $true }, idx)
}
function Carregar-Pauta {
  if ($script:dadosPauta -ne $null -and ((Get-Date) - $script:pautaChk).TotalSeconds -lt 5) { return }
  $script:pautaChk = Get-Date
  if (-not (Test-Path $pautaArq)) { $script:dadosPauta = @{ titulo = ''; tituloProjetos = ''; tituloTarefas = ''; aviso = ''; itens = @(); projetos = @(); tarefas = @() }; return }
  $mt = [string](Get-Item $pautaArq).LastWriteTime.Ticks + '|' + $(if (Test-Path $jiraArq) { [string](Get-Item $jiraArq).LastWriteTime.Ticks } else { '' })
  if ($script:dadosPauta -ne $null -and $script:pautaMtime -eq $mt) { return }
  try {
    $j = Get-Content $pautaArq -Raw -Encoding UTF8 | ConvertFrom-Json
    $hoje = (Get-Date).ToString('yyyy-MM-dd')
    $lista = @()
    foreach ($i in @($j.itens)) {
      if ($i.data -and "$($i.data)" -ne $hoje) { continue }   # item de outro dia
      if (-not $i.inicio) { continue }
      $lista += [pscustomobject]@{ inicio = "$($i.inicio)"; fim = "$($i.fim)"; titulo = "$($i.titulo)"; local = "$($i.local)" }
    }
    $projs = @()
    foreach ($pj in @($j.projetos)) {
      if (-not $pj.nome) { continue }
      $pc = 0.0; try { $pc = [double]$pj.percentual } catch { }
      if ($pc -lt 0) { $pc = 0.0 }; if ($pc -gt 100) { $pc = 100.0 }
      $projs += [pscustomobject]@{ nome = "$($pj.nome)"; pct = $pc; resp = "$($pj.responsavel)"; prazo = "$($pj.prazo)"; sit = "$($pj.situacao)" }
    }
    $tars = Converter-Tarefas $j.tarefas
    $tituloTar = "$($j.tituloTarefas)"; $atualJira = $null
    if (Test-Path $jiraArq) {
      try {
        $jj = Get-Content $jiraArq -Raw -Encoding UTF8 | ConvertFrom-Json
        $tj = Converter-Tarefas $jj.tarefas
        # Jira ativo = o arquivo tem "atualizado" (gravado pelo Sincronizar-Jira). Nesse caso o Jira manda, mesmo com 0 tarefas (nao volta aos exemplos do pauta.json)
        try { $atualJira = [datetime]::Parse("$($jj.atualizado)", [Globalization.CultureInfo]::InvariantCulture); $tars = $tj } catch { if ($tj.Count -gt 0) { $tars = $tj } }
      } catch { }
    }
    $script:dadosPauta = @{ titulo = "$($j.titulo)"; tituloProjetos = "$($j.tituloProjetos)"; tituloTarefas = $tituloTar; atualizado = $atualJira; mostrarConcluidas = [bool]$j.mostrarConcluidas; aviso = "$($j.aviso)"; itens = @($lista | Sort-Object inicio); projetos = $projs; tarefas = $tars }
    $script:pautaMtime = $mt
  } catch { }
}
function Caminho-Arredondado($x, $y, $w, $h, $r) {
  $p = New-Object System.Drawing.Drawing2D.GraphicsPath; $d = 2 * $r
  $p.AddArc([single]$x, [single]$y, [single]$d, [single]$d, 180, 90); $p.AddArc([single]($x + $w - $d), [single]$y, [single]$d, [single]$d, 270, 90)
  $p.AddArc([single]($x + $w - $d), [single]($y + $h - $d), [single]$d, [single]$d, 0, 90); $p.AddArc([single]$x, [single]($y + $h - $d), [single]$d, [single]$d, 90, 90); $p.CloseFigure(); return $p
}

# cartao de vidro com titulo (usado por agenda, projetos e tarefas): fundo em degrade, borda, barra de destaque e divisor
function Painel($g, $x, $y, $pw, $ph, $s, $titulo, $direita) {
  $cp = Caminho-Arredondado $x $y $pw $ph (28 * $s)
  $rc = New-Object System.Drawing.RectangleF([single]$x, [single]$y, [single]$pw, [single]$ph)
  $lg = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rc, (Cor '#FFFFFF' 36), (Cor '#FFFFFF' 12), 90.0
  $g.FillPath($lg, $cp); $lg.Dispose()
  $bp = New-Object System.Drawing.Pen (Cor $tema.corDestaque 100), ([single](2 * $s)); $g.DrawPath($bp, $cp); $bp.Dispose(); $cp.Dispose()
  $ab = New-Object System.Drawing.SolidBrush (Cor $tema.corDestaque 255)
  $g.FillPath($ab, (Caminho-Arredondado ($x + 32 * $s) ($y + 30 * $s) (7 * $s) (30 * $s) (3.5 * $s))); $ab.Dispose()
  $fH = New-Object System.Drawing.Font('Segoe UI Semibold', [single](26 * $s), [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
  Texto $g $titulo $fH (Cor '#FFFFFF' 255) ($x + 54 * $s) ($y + 14 * $s) ($pw - 90 * $s - 110 * $s) (60 * $s) 'Near'
  if ($direita) { Texto $g $direita $fH (Cor $tema.corDestaque 255) ($x + $pw - 34 * $s - 110 * $s) ($y + 14 * $s) (110 * $s) (60 * $s) 'Far' }
  $fH.Dispose()
  $dp = New-Object System.Drawing.Pen (Cor '#FFFFFF' 40), ([single](1.5 * $s)); $g.DrawLine($dp, [single]($x + 30 * $s), [single]($y + 78 * $s), [single]($x + $pw - 30 * $s), [single]($y + 78 * $s)); $dp.Dispose()
}
# icone de status da tarefa (sem depender de fonte): aberto, meio cheio, check, alerta
function Icone-Tarefa($g, $cod, $cx, $cy, $r, $s) {
  $cor = '#9FB4E6'; if ($cod -eq 'ok') { $cor = '#36CC99' } elseif ($cod -eq 'and') { $cor = '#FFC400' } elseif ($cod -eq 'bloq') { $cor = '#FF6B6B' } elseif ($cod -eq 'val') { $cor = '#B388FF' } elseif ($cod -eq 'paus') { $cor = '#FFA040' }
  $x = [single]($cx - $r); $y = [single]($cy - $r); $d = [single](2 * $r)
  $pen = New-Object System.Drawing.Pen (Cor $cor 255), ([single](3 * $s))
  $br = New-Object System.Drawing.SolidBrush (Cor $cor 255)
  if ($cod -eq 'ok' -or $cod -eq 'bloq' -or $cod -eq 'paus') {
    $g.FillEllipse($br, $x, $y, $d, $d)
    $dk = New-Object System.Drawing.Pen (Cor '#06122B' 255), ([single](3.4 * $s)); $dk.StartCap = 'Round'; $dk.EndCap = 'Round'; $dk.LineJoin = 'Round'
    if ($cod -eq 'ok') {
      $g.DrawLines($dk, [System.Drawing.PointF[]]@((New-Object System.Drawing.PointF([single]($cx - $r * 0.42), [single]($cy + $r * 0.02))), (New-Object System.Drawing.PointF([single]($cx - $r * 0.1), [single]($cy + $r * 0.36))), (New-Object System.Drawing.PointF([single]($cx + $r * 0.46), [single]($cy - $r * 0.32)))))
    } elseif ($cod -eq 'paus') {
      $g.DrawLine($dk, [single]($cx - $r * 0.26), [single]($cy - $r * 0.4), [single]($cx - $r * 0.26), [single]($cy + $r * 0.4))
      $g.DrawLine($dk, [single]($cx + $r * 0.26), [single]($cy - $r * 0.4), [single]($cx + $r * 0.26), [single]($cy + $r * 0.4))
    } else {
      $g.DrawLine($dk, [single]$cx, [single]($cy - $r * 0.48), [single]$cx, [single]($cy + $r * 0.08))
      $g.FillEllipse((New-Object System.Drawing.SolidBrush (Cor '#06122B' 255)), [single]($cx - 2.4 * $s), [single]($cy + $r * 0.30), [single](4.8 * $s), [single](4.8 * $s))
    }
    $dk.Dispose()
  } else {
    $g.DrawEllipse($pen, $x, $y, $d, $d)
    if ($cod -eq 'and') { $g.FillPie($br, $x, $y, $d, $d, 90, 180) }
    if ($cod -eq 'val') { $g.FillPie($br, $x, $y, $d, $d, 270, 270) }   # aguardando validacao: tres quartos cheio
  }
  $pen.Dispose(); $br.Dispose()
}

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
  Carregar-Pauta
  $agora = Agora-Hora
  # so tarefas em aberto (bloqueada / em andamento / a fazer); concluidas ficam ocultas, salvo "mostrarConcluidas": true no pauta.json
  $nTarefas = 0; $mostrarOk = $false
  if ($script:dadosPauta) { $mostrarOk = [bool]$script:dadosPauta.mostrarConcluidas; $nTarefas = @(@($script:dadosPauta.tarefas) | Where-Object { $mostrarOk -or $_.cod -ne 'ok' }).Count }
  $temTar = $true   # o card de tarefas fica sempre na lateral; sem tarefas mostra "Sem tarefas"
  # layout: centro limpo (nome, relogio, data) + barra estreita de tarefas na direita + UMA faixa que alterna agenda/aviso/projetos
  # margem lateral unica (5%) = mesma dos passos; card termina na margem direita; coluna central centralizada entre a margem esquerda e o card
  $tw0 = $w * 0.29; $tx0 = $w * 0.95 - $tw0; $L = $w
  if ($temTar) { $L = $tx0 + $w * 0.02 }
  # altura do card de tarefas (calculada antes, para centralizar o bloco da esquerda no mesmo eixo vertical do card)
  $tyCard = 100 * $s
  $cardH = (142 + 6 * 92 + 52) * $s   # altura fixa (6 linhas): o card nao muda de tamanho e acompanha a coluna da esquerda
  $cardCy = $tyCard + $cardH / 2
  $estreito = $false
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
    $cw2 = $lw + 70 * $s; $ch2 = $lh + 40 * $s; $cx2 = ($L - $cw2) / 2; $cy2 = 50 * $s
    $cp = New-Object System.Drawing.Drawing2D.GraphicsPath; $d = 40 * $s
    $cp.AddArc([single]$cx2, [single]$cy2, [single]$d, [single]$d, 180, 90); $cp.AddArc([single]($cx2 + $cw2 - $d), [single]$cy2, [single]$d, [single]$d, 270, 90)
    $cp.AddArc([single]($cx2 + $cw2 - $d), [single]($cy2 + $ch2 - $d), [single]$d, [single]$d, 0, 90); $cp.AddArc([single]$cx2, [single]($cy2 + $ch2 - $d), [single]$d, [single]$d, 90, 90); $cp.CloseFigure()
    $wb = New-Object System.Drawing.SolidBrush (Cor '#FFFFFF' 245); $g.FillPath($wb, $cp); $wb.Dispose(); $cp.Dispose()
    $g.DrawImage($logoImg, [single]($cx2 + 35 * $s), [single]($cy2 + 20 * $s), [single]$lw, [single]$lh)
    $y0 = $cy2 + $ch2 + 25 * $s
  } else {
    $y0 = ($tyCard + $tyCard + $cardH - 62 * $s) / 2 - 252 * $s   # bloco nome/relogio/data (505 de altura) centralizado com o card de tarefas
  }

  # nome / subtitulo
  $fSub = New-Object System.Drawing.Font('Segoe UI Semibold', [single](24 * $s), [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
  $fNome = New-Object System.Drawing.Font('Segoe UI Semibold', [single](78 * $s), [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
  Texto $g ($tema.subtitulo.ToUpper()) $fSub (Cor $tema.corDestaque 255) 0 $y0 $L (40 * $s) 'Center'
  Texto $g $tema.nome $fNome (Cor '#FFFFFF' 255) 0 ($y0 + 40 * $s) $L (110 * $s) 'Center'
  $pen = New-Object System.Drawing.Pen (Cor $tema.corDestaque 255), ([single](4 * $s))
  $g.DrawLine($pen, [single]($L / 2 - 60 * $s), [single]($y0 + 175 * $s), [single]($L / 2 + 60 * $s), [single]($y0 + 175 * $s)); $pen.Dispose()

  # relogio e data
  $fRel = New-Object System.Drawing.Font('Segoe UI Light', [single](210 * $s), [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
  $fData = New-Object System.Drawing.Font('Segoe UI', [single]($(if ($estreito) { 28 } else { 38 }) * $s), [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
  $yr = $y0 + 200 * $s
  Texto $g ($agora.ToString('HH:mm')) $fRel (Cor '#FFFFFF' 255) 0 $yr $L (250 * $s) 'Center'
  $data = $agora.ToString("dddd, d 'de' MMMM 'de' yyyy", $ci)
  $data = $data.Substring(0, 1).ToUpper() + $data.Substring(1)
  Texto $g $data $fData (Cor '#FFFFFF' 215) 0 ($yr + 245 * $s) $L (60 * $s) 'Center'

  # faixa "Aguardando transmissao" com ponto pulsante
  $fAg = New-Object System.Drawing.Font('Segoe UI Semibold', [single](30 * $s), [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
  $pw = 520 * $s; ; $ph = 62 * $s; $px = ($L - $pw) / 2; $py = $h - 205 * $s; if (-not $logoImg) { $py = $tyCard + $cardH - $ph }   # sem logo: faixa no lugar da antiga faixa de aviso/agenda (abaixo da data)
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

  # faixa unica (abaixo da data): alterna a cada 7 s entre reuniao agora/em seguida, aviso e um projeto por vez
  $hm = $agora.ToString('HH:mm')
  $pgs = @()
  if ($script:dadosPauta) {
    $todos = @($script:dadosPauta.itens)
    $prox = $null
    foreach ($it0 in $todos) { $f0 = $it0.fim; if (-not $f0) { $f0 = '23:59' }; if ([string]::CompareOrdinal($hm, $f0) -lt 0) { $prox = $it0; break } }
    if ($prox) { $pgs += , @('agenda', $prox) }
    if ($script:dadosPauta.aviso) { $pgs += , @('aviso', $script:dadosPauta.aviso) }
    foreach ($pj0 in @($script:dadosPauta.projetos | Select-Object -First 6)) { $pgs += , @('proj', $pj0) }
  }
  $mostrarFaixa = $false   # a faixa de aviso/agenda/projetos foi substituida pela faixa "Aguardando transmissao"
  if ($mostrarFaixa -and $pgs.Count -gt 0) {
    $ciclo = 7.0
    $ip = [int][Math]::Floor($t / $ciclo) % $pgs.Count; if ($Aba -match '^\d+$') { $ip = [int]$Aba % $pgs.Count }
    $pg = $pgs[$ip]; $tq = $t % $ciclo
    $fd = [Math]::Min(1.0, [Math]::Min($tq / 0.5, ($ciclo - $tq) / 0.5)); if ($fd -lt 0) { $fd = 0 }
    $sw = [Math]::Min($L * 0.84, 1080 * $s); $sx = ($L - $sw) / 2; $sh = 112 * $s; $sy = $h - 330 * $s
    $fT = New-Object System.Drawing.Font('Segoe UI Semibold', [single](36 * $s), [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    $fM = New-Object System.Drawing.Font('Segoe UI', [single](25 * $s), [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    $fC = New-Object System.Drawing.Font('Segoe UI Semibold', [single](20 * $s), [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    $corF = '#FFFFFF'; $bordaF = $tema.corDestaque; $alF = 20
    if ($pg[0] -eq 'aviso') { $corF = '#FFC400'; $bordaF = '#FFC400'; $alF = 38 }
    $cpF = Caminho-Arredondado $sx $sy $sw $sh (26 * $s)
    $cbF = New-Object System.Drawing.SolidBrush (Cor $corF ([int]($alF * $fd))); $g.FillPath($cbF, $cpF); $cbF.Dispose()
    $bpF = New-Object System.Drawing.Pen (Cor $bordaF ([int](120 * $fd))), ([single](2 * $s)); $g.DrawPath($bpF, $cpF); $bpF.Dispose(); $cpF.Dispose()
    $a1 = [int](255 * $fd); $a2 = [int](190 * $fd)
    if ($pg[0] -eq 'agenda') {
      $it = $pg[1]
      $ag = ([string]::CompareOrdinal($hm, $it.inicio) -ge 0)
      $rot = 'EM SEGUIDA'; $cc = $tema.corDestaque; $cwid = 168 * $s; if ($ag) { $rot = 'AGORA'; $cc = '#36CC99'; $cwid = 124 * $s }
      $cpp = Caminho-Arredondado ($sx + 28 * $s) ($sy + ($sh - 38 * $s) / 2) $cwid (38 * $s) (19 * $s)
      $chb = New-Object System.Drawing.SolidBrush (Cor $cc $a1); $g.FillPath($chb, $cpp); $chb.Dispose(); $cpp.Dispose()
      Texto $g $rot $fC (Cor '#06122B' $a1) ($sx + 28 * $s) ($sy + ($sh - 38 * $s) / 2) $cwid (38 * $s) 'Center'
      $tx = $sx + 28 * $s + $cwid + 26 * $s; $twd = $sw - ($tx - $sx) - 24 * $s
      Texto $g $it.titulo $fT (Cor '#FFFFFF' $a1) $tx ($sy + 10 * $s) $twd (48 * $s) 'Near'
      $mt = $it.inicio; if ($it.fim) { $mt += ' ' + [string][char]0x2192 + ' ' + $it.fim }; if ($it.local) { $mt += '   ' + $it.local }
      Texto $g $mt $fM (Cor $tema.corDestaque $a2) $tx ($sy + 56 * $s) $twd (34 * $s) 'Near'
    } elseif ($pg[0] -eq 'aviso') {
      Texto $g $pg[1] $fM (Cor '#FFFFFF' $a1) ($sx + 32 * $s) $sy ($sw - 64 * $s) $sh 'Near'
    } else {
      $pj = $pg[1]; $sit = $pj.sit.ToLower(); $corB = $tema.corDestaque
      if ($pj.pct -ge 100 -or $sit -like 'conclu*') { $corB = '#36CC99' } elseif ($sit -like 'atras*') { $corB = '#FF6B6B' } elseif ($sit -like 'aten*') { $corB = '#FFC400' }
      $eas = [Math]::Min(1.0, $tq / 1.0); $eas = 1 - [Math]::Pow(1 - $eas, 3)
      Texto $g ('PROJETO  ' + [string][char]0x00B7 + '  ' + $pj.nome) $fT (Cor '#FFFFFF' $a1) ($sx + 30 * $s) ($sy + 8 * $s) ($sw - 60 * $s - 150 * $s) (48 * $s) 'Near'
      Texto $g ([string][int][Math]::Round($pj.pct * $eas) + '%') $fT (Cor $corB $a1) ($sx + $sw - 30 * $s - 150 * $s) ($sy + 8 * $s) (150 * $s) (48 * $s) 'Far'
      $bx = $sx + 30 * $s; $bw = $sw - 60 * $s; $by = $sy + 60 * $s; $bh = 12 * $s
      $tr = Caminho-Arredondado $bx $by $bw $bh ($bh / 2); $trb = New-Object System.Drawing.SolidBrush (Cor '#FFFFFF' ([int](40 * $fd))); $g.FillPath($trb, $tr); $trb.Dispose(); $tr.Dispose()
      $fw = $bw * ($pj.pct / 100.0) * $eas
      if ($fw -gt 2) { $fp = Caminho-Arredondado $bx $by $fw $bh ([Math]::Min($bh / 2, $fw / 2)); $fb2 = New-Object System.Drawing.SolidBrush (Cor $corB $a1); $g.FillPath($fb2, $fp); $fb2.Dispose(); $fp.Dispose() }
      $meta = @(); if ($pj.resp) { $meta += $pj.resp }; if ($pj.prazo) { $meta += ('Prazo: ' + $pj.prazo) }; if ($pj.sit) { $meta += ($pj.sit.Substring(0, 1).ToUpper() + $pj.sit.Substring(1)) }
      Texto $g ($meta -join '  -  ') $fC (Cor '#FFFFFF' $a2) ($sx + 30 * $s) ($sy + 76 * $s) ($sw - 60 * $s) (26 * $s) 'Near'
    }
    # pontinhos de pagina
    if ($pgs.Count -gt 1) {
      $dx = $L / 2 - ($pgs.Count * 22 * $s) / 2
      for ($k = 0; $k -lt $pgs.Count; $k++) { $ac = 60; if ($k -eq $ip) { $ac = 255 }; $dbr = New-Object System.Drawing.SolidBrush (Cor $tema.corDestaque $ac); $g.FillEllipse($dbr, [single]($dx + $k * 22 * $s), [single]($sy + $sh + 14 * $s), [single](10 * $s), [single](10 * $s)); $dbr.Dispose() }
    }
    foreach ($ff in $fT, $fM, $fC) { $ff.Dispose() }
  }

  # sem tarefas: card com mensagem (e a hora da ultima atualizacao, para saber que a sincronizacao esta viva)
  if ($temTar -and $nTarefas -eq 0) {
    $txP = $tx0; $twP = $tw0; $tyP = $tyCard; $thP = $cardH
    $titT = 'TAREFAS'; if ($script:dadosPauta -and $script:dadosPauta.tituloTarefas) { $titT = $script:dadosPauta.tituloTarefas.ToUpper() }
    Painel $g $txP $tyP $twP $thP $s $titT $null
    Icone-Tarefa $g 'ok' ($txP + $twP / 2) ($tyP + 150 * $s) (34 * $s) $s
    $fVz = New-Object System.Drawing.Font('Segoe UI Semibold', [single](40 * $s), [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    $fVz2 = New-Object System.Drawing.Font('Segoe UI', [single](24 * $s), [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    Texto $g 'Sem tarefas' $fVz (Cor '#FFFFFF' 255) $txP ($tyP + 200 * $s) $twP (60 * $s) 'Center'
    Texto $g 'no momento' $fVz2 (Cor '#FFFFFF' 160) $txP ($tyP + 255 * $s) $twP (36 * $s) 'Center'
    $atuV = $null; if ($script:dadosPauta) { $atuV = $script:dadosPauta.atualizado }
    if ($atuV) {
      $velhoV = (((Get-Date) - $atuV).TotalMinutes -gt 10) -and -not $Hora
      $txtV = 'Atualizado ' + $atuV.ToString('dd/MM HH:mm'); $corV = Cor '#FFFFFF' 150
      if ($velhoV) { $txtV = 'Sem atualizar desde ' + $atuV.ToString('dd/MM HH:mm'); $corV = Cor '#FFC400' 255 }
      Texto $g $txtV $fVz2 $corV ($txP + 34 * $s) ($tyP + $thP - 52 * $s) ($twP - 68 * $s) (36 * $s) 'Near'
    }
    $fVz.Dispose(); $fVz2.Dispose()
  }

  # painel de tarefas da equipe (lateral direita, sempre visivel): status, responsavel e prazo
  if ($temTar -and $nTarefas -gt 0) {
    $todasT = @($script:dadosPauta.tarefas)   # todas (para a barra de progresso)
    $listaT = @($todasT | Where-Object { $mostrarOk -or $_.cod -ne 'ok' })   # as que aparecem na lista
    $maxT = 6
    # muitas tarefas: 6 por pagina, troca a cada 10 s
    $nPag = [int][Math]::Ceiling($listaT.Count / [double]$maxT)
    $pagT = 0
    if ($nPag -gt 1) { $pagT = [int][Math]::Floor($t / 10) % $nPag; if ($Previa -and $Aba -match '^\d+$') { $pagT = [int]$Aba % $nPag } }
    $vt = @($listaT | Select-Object -Skip ($pagT * $maxT) -First $maxT)
    $extra = 0; if ($nPag -gt 1) { $extra = 1 }
    $qOk = @($todasT | Where-Object { $_.cod -eq 'ok' }).Count
    $qAnd = @($todasT | Where-Object { $_.cod -eq 'and' }).Count
    $qVl = @($todasT | Where-Object { $_.cod -eq 'val' }).Count
    $qPz = @($todasT | Where-Object { $_.cod -eq 'paus' }).Count
    $qBq = @($todasT | Where-Object { $_.cod -eq 'bloq' }).Count
    $qFz = @($todasT | Where-Object { $_.cod -eq 'fazer' }).Count
    $txP = $tx0; $twP = $tw0; $tyP = $tyCard
    $rowT = 92 * $s; $hdrT = 142 * $s; $rodT = 14 * $s; $atuJ = $script:dadosPauta.atualizado; if ($extra -gt 0 -or $atuJ) { $rodT = 52 * $s }
    $nLin = $vt.Count; if ($nPag -gt 1) { $nLin = $maxT }   # altura fixa quando ha varias paginas (o card nao pula)
    $thP = $cardH
    $titT = 'TAREFAS'; if ($script:dadosPauta.tituloTarefas) { $titT = $script:dadosPauta.tituloTarefas.ToUpper() }
    Painel $g $txP $tyP $twP $thP $s $titT $(if ($mostrarOk) { [string]$qOk + '/' + [string]$todasT.Count } else { [string]$listaT.Count })
    # barra de progresso geral (concluidas / total) e legenda
    $bx = $txP + 34 * $s; $bw = $twP - 68 * $s; $by = $tyP + 92 * $s; $bh = 12 * $s
    $trk = Caminho-Arredondado $bx $by $bw $bh ($bh / 2)
    $trb = New-Object System.Drawing.SolidBrush (Cor '#FFFFFF' 40); $g.FillPath($trb, $trk); $trb.Dispose(); $trk.Dispose()
    $fwT = $bw * ($qOk / [double]$todasT.Count)
    if ($fwT -gt 2) { $fpT = Caminho-Arredondado $bx $by $fwT $bh ([Math]::Min($bh / 2, $fwT / 2)); $fbT = New-Object System.Drawing.SolidBrush (Cor '#36CC99' 255); $g.FillPath($fbT, $fpT); $fbT.Dispose(); $fpT.Dispose() }
    $fLg = New-Object System.Drawing.Font('Segoe UI', [single](19 * $s), [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    $fTt = New-Object System.Drawing.Font('Segoe UI Semibold', [single](27 * $s), [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    $fMt = New-Object System.Drawing.Font('Segoe UI', [single](22 * $s), [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    $fCh = New-Object System.Drawing.Font('Segoe UI Semibold', [single](16 * $s), [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    $iA = [string][char]0x00ED
    $pl = @([string]$qAnd + ' andamento')
    if ($qVl -gt 0) { $pl += [string]$qVl + ' valida' + [string][char]0x00E7 + $aTil + 'o' }
    if ($mostrarOk) { $pl += [string]$qOk + ' conclu' + $iA + 'das' } else { $pl += [string]$qFz + ' a fazer' }
    if ($qPz -gt 0) { $pl += [string]$qPz + ' pausada' + $(if ($qPz -gt 1) { 's' } else { '' }) }
    if ($qBq -gt 0) { $pl += [string]$qBq + ' bloq.' }
    $leg = $pl -join ('  ' + [string][char]0x00B7 + '  ')
    Texto $g $leg $fLg (Cor '#FFFFFF' 170) $bx ($by + 12 * $s) $bw (28 * $s) 'Near'
    for ($i = 0; $i -lt $vt.Count; $i++) {
      $tk = $vt[$i]; $ry = $tyP + $hdrT + $i * $rowT
      $a = 255; if ($tk.cod -eq 'ok') { $a = 120 }
      if ($i -gt 0) { $lpT = New-Object System.Drawing.Pen (Cor '#FFFFFF' 30), ([single](1.5 * $s)); $g.DrawLine($lpT, [single]($txP + 30 * $s), [single]$ry, [single]($txP + $twP - 30 * $s), [single]$ry); $lpT.Dispose() }
      Icone-Tarefa $g $tk.cod ($txP + 34 * $s + 15 * $s) ($ry + $rowT / 2) (15 * $s) $s
      $tx1 = $txP + 34 * $s + 48 * $s; $wT = $twP - 34 * $s - 48 * $s - 30 * $s
      $wTit = $wT
      Texto $g $tk.titulo $fTt (Cor '#FFFFFF' $a) $tx1 ($ry + 8 * $s) $wTit (42 * $s) 'Near'
      $mt = @(); if ($tk.chave) { $mt += $tk.chave }; if ($tk.resp) { $mt += $tk.resp }; if ($tk.prazo) { $mt += ('at' + [string][char]0x00E9 + ' ' + $tk.prazo) }
      if ($mt.Count -gt 0) { Texto $g ($mt -join '  -  ') $fMt (Cor $tema.corDestaque ([int]($a * 0.85))) $tx1 ($ry + 50 * $s) ($wT - 80 * $s) (32 * $s) 'Near' }
      if ($tk.alta -eq 1 -and $tk.cod -ne 'ok') {
        $chx = $txP + $twP - 30 * $s - 70 * $s; $chy = $ry + 52 * $s
        $cpT = Caminho-Arredondado $chx $chy (70 * $s) (28 * $s) (14 * $s)
        $chb = New-Object System.Drawing.SolidBrush (Cor '#FF6B6B' 255); $g.FillPath($chb, $cpT); $chb.Dispose(); $cpT.Dispose()
        Texto $g 'ALTA' $fCh (Cor '#06122B' 255) $chx $chy (70 * $s) (28 * $s) 'Center'
      }
    }
    # rodape: hora da ultima atualizacao (vinda do Jira) + pagina/pontinhos quando ha varias paginas
    if ($atuJ) {
      $velho = (((Get-Date) - $atuJ).TotalMinutes -gt 10) -and -not $Hora   # sem atualizar ha mais de 10 min: avisa em amarelo
      $txtA = 'Atualizado ' + $atuJ.ToString('dd/MM HH:mm'); $corA = Cor '#FFFFFF' 150
      if ($velho) { $txtA = 'Sem atualizar desde ' + $atuJ.ToString('dd/MM HH:mm'); $corA = Cor '#FFC400' 255 }
      Texto $g $txtA $fLg $corA ($txP + 34 * $s) ($tyP + $thP - 46 * $s) ($twP - 68 * $s - 130 * $s) (36 * $s) 'Near'
    }
    if ($nPag -gt 1) {
      $dx = $txP + $twP - 34 * $s - $nPag * 22 * $s
      Texto $g ([string]($pagT + 1) + '/' + [string]$nPag) $fLg (Cor '#FFFFFF' 150) ($dx - 70 * $s) ($tyP + $thP - 46 * $s) (60 * $s) (36 * $s) 'Far'
      for ($k = 0; $k -lt $nPag; $k++) { $ac = 60; if ($k -eq $pagT) { $ac = 255 }; $dbr = New-Object System.Drawing.SolidBrush (Cor $tema.corDestaque $ac); $g.FillEllipse($dbr, [single]($dx + $k * 22 * $s), [single]($tyP + $thP - 33 * $s), [single](10 * $s), [single](10 * $s)); $dbr.Dispose() }
    }
    foreach ($ff in $fLg, $fTt, $fMt, $fCh) { $ff.Dispose() }
  }

  # passos (3 colunas)
  $fN = New-Object System.Drawing.Font('Segoe UI Semibold', [single](30 * $s), [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
  $fP = New-Object System.Drawing.Font('Segoe UI', [single](26 * $s), [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
  $passos = @($tema.passos)
  $n = [Math]::Min(3, $passos.Count)
  if ($n -gt 0) {
    $x0 = 0; $cw = $w / $n; $yp = $h - 128 * $s   # colunas iguais na largura toda; cada passo (bolinha + texto) centralizado na sua coluna
    for ($i = 0; $i -lt $n; $i++) {
      $tw1 = [Math]::Ceiling($g.MeasureString([string]$passos[$i], $fP).Width)
      $cxp = $x0 + $i * $cw + ($cw - (62 * $s + $tw1)) / 2
      $cb = New-Object System.Drawing.SolidBrush (Cor $tema.corDestaque 235)
      $g.FillEllipse($cb, [single]($cxp), [single]($yp + 8 * $s), [single](46 * $s), [single](46 * $s)); $cb.Dispose()
      Texto $g ([string]($i + 1)) $fN (Cor $tema.corFundo1 255) $cxp ($yp + 8 * $s) (46 * $s) (46 * $s) 'Center'
      Texto $g ([string]$passos[$i]) $fP (Cor '#FFFFFF' 205) ($cxp + 62 * $s) $yp ($tw1 + 20 * $s) (62 * $s) 'Near'
    }
  }
  # segundo logo (versao branca, ex.: instituicao) no canto inferior esquerdo
  if ($logoPref) {
    $ph2 = 70 * $s; $pw2 = $logoPref.Width * ($ph2 / $logoPref.Height)
    $g.DrawImage($logoPref, [single](40 * $s), [single]($h - $ph2 - 30 * $s), [single]$pw2, [single]$ph2)
  }
  # IP da maquina (apoio a suporte)
  $fIp = New-Object System.Drawing.Font('Segoe UI', [single](20 * $s), [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
  Texto $g ('Ponte: ' + $meuIp) $fIp (Cor '#FFFFFF' 110) 0 ($h - 44 * $s) ($w * 0.95) (30 * $s) 'Far'
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
  private readonly object trava = new object();
  private string emissor = ""; private long ultimoEmissor; private long inicioSessao;
  private long pktsTs, perdas, estrangeiros;
  private int[] cc = new int[8192];
  public volatile bool Forward;
  public UdpRelay(int port, int destPort) {
    dest = new IPEndPoint(IPAddress.Loopback, destPort);
    rx = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp);
    rx.ReceiveBufferSize = 8 * 1024 * 1024;
    rx.Bind(new IPEndPoint(IPAddress.Any, port));
    tx = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp);
  }
  public void Start() { run = true; th = new Thread(Loop); th.IsBackground = true; th.Start(); }
  private void NovaSessao(string ip, long agora) {
    lock (trava) {
      emissor = ip; inicioSessao = agora; pktsTs = 0; perdas = 0; estrangeiros = 0;
      for (int k = 0; k < cc.Length; k++) cc[k] = -1;
    }
  }
  private void Loop() {
    byte[] buf = new byte[65536];
    double freq = (double)Stopwatch.Frequency;
    EndPoint origem = new IPEndPoint(IPAddress.Any, 0);
    while (run) {
      try {
        origem = new IPEndPoint(IPAddress.Any, 0);
        int n = rx.ReceiveFrom(buf, ref origem);
        long agora = Stopwatch.GetTimestamp();
        string ip = ((IPEndPoint)origem).Address.ToString();
        // um emissor por vez: enquanto o atual transmite, pacotes de outro IP sao descartados (evita imagem misturada)
        if (emissor.Length == 0 || (agora - Interlocked.Read(ref ultimoEmissor)) / freq > 2.0) NovaSessao(ip, agora);
        else if (ip != emissor) { Interlocked.Increment(ref estrangeiros); continue; }
        Interlocked.Exchange(ref ultimoEmissor, agora);
        Interlocked.Exchange(ref last, agora);
        Interlocked.Increment(ref count);
        // MPEG-TS: cada pacote de 188 bytes tem contador de continuidade; salto = pacote perdido na rede
        long perdi = 0, vistos = 0;
        for (int o = 0; o + 188 <= n; o += 188) {
          if (buf[o] != 0x47) break;
          int pid = ((buf[o + 1] & 0x1F) << 8) | buf[o + 2];
          if (pid == 0x1FFF || (buf[o + 3] & 0x10) == 0) continue;
          int c = buf[o + 3] & 0x0F; int ant = cc[pid];
          if (ant >= 0 && c != ant && c != ((ant + 1) & 0x0F)) perdi++;
          cc[pid] = c; vistos++;
        }
        if (vistos > 0) { Interlocked.Add(ref pktsTs, vistos); if (perdi > 0) Interlocked.Add(ref perdas, perdi); }
        if (Forward) { tx.SendTo(buf, 0, n, SocketFlags.None, dest); }
      } catch (SocketException) { if (!run) break; }
      catch (ObjectDisposedException) { break; }
    }
  }
  public double AgeSeconds { get {
    if (Interlocked.Read(ref count) == 0) return 1e9;
    return (Stopwatch.GetTimestamp() - Interlocked.Read(ref last)) / (double)Stopwatch.Frequency; } }
  // resumo da sessao atual: ip|segundos|pacotes|perdas|descartados de outro emissor
  public string Resumo() {
    lock (trava) {
      double dur = (Interlocked.Read(ref ultimoEmissor) - inicioSessao) / (double)Stopwatch.Frequency;
      return emissor + "|" + dur.ToString("0") + "|" + Interlocked.Read(ref pktsTs) + "|" + Interlocked.Read(ref perdas) + "|" + Interlocked.Read(ref estrangeiros);
    }
  }
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
  $fa += @('-autoexit','-fflags','nobuffer+discardcorrupt','-flags','low_delay','-framedrop','-probesize','32','-analyzeduration','0','-strict','experimental','-vf','setpts=0','-window_title','TelaRecebida',('udp://127.0.0.1:' + ($porta + 1) + '?fifo_size=1000000&overrun_nonfatal=1'))
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
  # registra a qualidade da sessao (perdas de pacote por emissor): ajuda a achar quais PCs/redes quebram a imagem
  try {
    $rs = $relay.Resumo().Split('|')
    if ([int]$rs[2] -gt 0) {
      $tot = [double]$rs[2] + [double]$rs[3]; $pp = 0.0; if ($tot -gt 0) { $pp = 100.0 * [double]$rs[3] / $tot }
      $linha = '{0}  emissor {1}  duracao {2}s  pacotes {3}  perdas {4} ({5:N2}%)  descartados-outro-emissor {6}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $rs[0], $rs[1], $rs[2], $rs[3], $pp, $rs[4]
      $logQ = Join-Path $pasta 'qualidade.log'
      if ((Test-Path $logQ) -and (Get-Item $logQ).Length -gt 300KB) { Get-Content $logQ -Tail 500 | Set-Content $logQ -Encoding UTF8 }
      Add-Content $logQ $linha -Encoding UTF8
    }
  } catch { }
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

# pauta.json (reunioes do dia exibidas na tela de espera). So cria se nao existir. Edite no Bloco de Notas: recarrega sozinho.
$pautaCriar = Join-Path $pasta "pauta.json"
if (-not (Test-Path $pautaCriar)) {
  '{ "titulo": "Agenda de hoje", "aviso": "", "itens": [] }' | Set-Content $pautaCriar -Encoding UTF8
  Write-Host "Pauta criada em $pautaCriar (veja pauta.exemplo.json para o formato)."
}

# pauta.json e tema.json sao so dados: qualquer usuario pode editar (sem administrador). O receber.ps1 continua so para administradores.
$jiraCriar = Join-Path $pasta "jira-tarefas.json"
if (-not (Test-Path $jiraCriar)) { '{ "titulo": "", "tarefas": [] }' | Set-Content $jiraCriar -Encoding UTF8 }
foreach ($arqDados in $pautaCriar, $temaArq, $jiraCriar) { if (Test-Path $arqDados) { & icacls.exe $arqDados /grant '*S-1-5-32-545:(M)' | Out-Null } }

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









