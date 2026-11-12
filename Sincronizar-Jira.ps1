# Sincronizar-Jira.ps1 - busca as tarefas de um QUADRO (board) do Jira Cloud e grava
# C:\ProgramData\ReceberTela\jira-tarefas.json, que a tela de espera da TV le sozinha (recarrega em ~5 s).
# Roda por tarefa agendada a cada 1 min (criada por Configurar-Jira.ps1) e, dentro desse minuto, busca de novo a cada 15 s
# (a TV fica no maximo ~20 s atras do Jira). Nao precisa de administrador.
# Config (criada por Configurar-Jira.ps1): %APPDATA%\ReceberTela\jira.json  (o token fica protegido pelo Windows, so este usuario le).
# Teste manual (uma busca so, mostrando o resultado):  .\Sincronizar-Jira.ps1 -Mostrar
# Sem Agendador de Tarefas (politica da rede bloqueia): Configurar-Jira.ps1 -PastaIniciar usa -Continuo pela pasta Iniciar do Windows.
param(
  [string]$ConfigPath,
  [string]$Saida,
  [switch]$Mostrar,
  [switch]$Uma,                 # faz uma unica busca (sem repetir a cada 15 s)
  [switch]$Continuo,            # roda para sempre (busca a cada $Intervalo s); so uma copia por vez. Usado na pasta Iniciar do Windows
  [int]$Intervalo = 15          # segundos entre buscas dentro da execucao
)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
if (-not $ConfigPath) { $ConfigPath = Join-Path $env:APPDATA 'ReceberTela\jira.json' }
if (-not $Saida) { $Saida = Join-Path $env:ProgramData 'ReceberTela\jira-tarefas.json' }
$logArq = Join-Path (Split-Path $ConfigPath) 'jira-sync.log'
$script:ultimoLog = ''; $script:ultimoLogHora = [datetime]::MinValue
function Log($m, $sempre) {
  # evita encher o log: repete a mesma mensagem so a cada 30 min
  if (-not $sempre -and $m -eq $script:ultimoLog -and ((Get-Date) - $script:ultimoLogHora).TotalMinutes -lt 30) { return }
  $script:ultimoLog = $m; $script:ultimoLogHora = Get-Date
  try { Add-Content $logArq ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  ' + $m) -Encoding UTF8
        if ((Get-Item $logArq).Length -gt 200KB) { Get-Content $logArq -Tail 200 | Set-Content $logArq -Encoding UTF8 } } catch { }
}

function Buscar-Uma {
  if (-not (Test-Path $ConfigPath)) { throw "Config nao encontrada: $ConfigPath (rode Configurar-Jira.bat)." }
  $cfg = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
  $site = ("$($cfg.site)").TrimEnd('/')
  if ($cfg.tokenProtegido) { $token = (New-Object System.Net.NetworkCredential('', (ConvertTo-SecureString $cfg.tokenProtegido))).Password } else { $token = "$($cfg.token)" }
  $auth = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$($cfg.email):$token"))
  $max = 100; if ($cfg.maximo) { $max = [int]$cfg.maximo }

  function Jira-Get($caminho) {
    $r = Invoke-WebRequest -Uri ($site + $caminho) -Headers @{ Authorization = $auth; Accept = 'application/json' } -UseBasicParsing -TimeoutSec 20
    return ([Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray()) | ConvertFrom-Json)
  }

  $board = Jira-Get "/rest/agile/1.0/board/$($cfg.quadro)"
  $titulo = "$($board.name)"
  $campos = 'summary,status,assignee,duedate,priority,labels'
  $issues = @()

  # quadro Scrum: issues do sprint ativo. Quadro Kanban (sem sprint): issues nao concluidas + concluidas nos ultimos 7 dias.
  $sprintId = $null
  try {
    $sp = Jira-Get "/rest/agile/1.0/board/$($cfg.quadro)/sprint?state=active"
    $ativo = @($sp.values) | Select-Object -First 1
    if ($ativo) { $sprintId = $ativo.id; $titulo = "$($ativo.name)" }
  } catch { }
  $inicio = 0
  while ($issues.Count -lt $max) {
    if ($sprintId) { $url = "/rest/agile/1.0/sprint/$sprintId/issue?startAt=$inicio&maxResults=50&fields=$campos" }
    else { $url = "/rest/agile/1.0/board/$($cfg.quadro)/issue?startAt=$inicio&maxResults=50&fields=$campos&jql=" + [uri]::EscapeDataString('(statusCategory != Done OR resolved >= -7d) ORDER BY Rank ASC') }
    $pg = Jira-Get $url
    $issues += @($pg.issues)
    $inicio += @($pg.issues).Count
    if (@($pg.issues).Count -eq 0 -or $inicio -ge [int]$pg.total) { break }
  }

  $tarefas = @()
  foreach ($i in ($issues | Select-Object -First $max)) {
    $f = $i.fields
    $nomeSt = "$($f.status.name)"
    $cat = "$($f.status.statusCategory.key)"
    $labels = @($f.labels) | ForEach-Object { "$_".ToLower() }
    if ($cat -eq 'done') { $st = 'concluida' }
    elseif ($nomeSt -match '(?i)bloq|impedi|blocked|imped' -or $labels -contains 'bloqueada' -or $labels -contains 'blocked') { $st = 'bloqueada' }
    elseif ($nomeSt -match '(?i)valida') { $st = 'aguardando validacao' }
    elseif ($nomeSt -match '(?i)paus') { $st = 'pausada' }
    elseif ($cat -eq 'indeterminate') { $st = 'em andamento' }
    else { $st = 'a fazer' }
    $prio = ''; if ("$($f.priority.name)" -match '(?i)^(highest|high|alta|altissima|critica|critical|blocker)') { $prio = 'alta' }
    $prazo = ''; if ($f.duedate) { try { $prazo = ([datetime]::ParseExact("$($f.duedate)", 'yyyy-MM-dd', $null)).ToString('dd/MM') } catch { } }
    $resp = ''; if ($f.assignee -and $f.assignee.displayName) { $resp = ("$($f.assignee.displayName)" -split '\s+')[0] }
    $tarefas += [ordered]@{ chave = "$($i.key)"; titulo = "$($f.summary)"; responsavel = $resp; prazo = $prazo; status = $st; prioridade = $prio }
  }

  $obj = [ordered]@{ titulo = $titulo; atualizado = (Get-Date).ToString('s'); tarefas = $tarefas }
  $json = $obj | ConvertTo-Json -Depth 5
  # grava DIRETO no arquivo (usuario comum so tem permissao de escrita no proprio jira-tarefas.json, nao na pasta)
  [IO.File]::WriteAllText($Saida, $json, (New-Object Text.UTF8Encoding($false)))
  return "OK: $($tarefas.Count) tarefas de '$titulo'"
}

function Dica($msg) {
  if ($msg -match 'negad|denied|UnauthorizedAccess') { return "$msg  >> Sem permissao para gravar $Saida. Rode o Instalar-Ponte.bat de novo (como administrador) para liberar." }
  if ($msg -match '401|Unauthorized|Nao autorizado|N.o autorizado') { return "$msg  >> Login recusado: token vencido/revogado ou e-mail errado. Rode o Configurar-Jira.bat de novo." }
  if ($msg -match '404') { return "$msg  >> Quadro nao encontrado: confira o numero do quadro." }
  return $msg
}

if ($Continuo) {   # trava: se ja existe uma copia rodando nesta sessao, sai sem fazer nada
  $script:mx = New-Object System.Threading.Mutex($false, 'Local\ReceberTelaJiraSync')
  if (-not $script:mx.WaitOne(0)) { exit 0 }
}
$t0 = Get-Date
$ciclo = 0
do {
  $ciclo++
  try {
    $r = Buscar-Uma
    if ($Mostrar) { Write-Host $r }
    Log $r $false
  } catch {
    $m = Dica $_.Exception.Message
    Log ("ERRO: " + $m) $false   # o arquivo anterior continua: a TV mostra a ultima lista (e avisa que esta desatualizada)
    if ($Mostrar -or $Uma) { if ($Mostrar) { Write-Host ("ERRO: " + $m) }; exit 1 }
  }
  if ($Mostrar -or $Uma) { break }
  $prox = $t0.AddSeconds($ciclo * $Intervalo)
  if (-not $Continuo -and $prox -gt $t0.AddSeconds(50)) { break }   # modo tarefa agendada: reinicia a cada 1 min
  $esp = ($prox - (Get-Date)).TotalSeconds
  if ($esp -gt 0) { Start-Sleep -Milliseconds ([int]($esp * 1000)) }
} while ($true)
