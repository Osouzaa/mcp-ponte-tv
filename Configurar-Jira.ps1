# Configurar-Jira.ps1 - liga a tela da TV a um quadro (board) do Jira Cloud. Rodar UMA vez na maquina-ponte,
# com o usuario que fica logado na ponte (nao precisa de administrador).
# O que faz: pede o site, e-mail, API token e numero do quadro; testa a conexao; guarda o token PROTEGIDO
# (so este usuario do Windows consegue ler) e cria uma tarefa agendada que atualiza as tarefas a cada 1 minuto.
# Criar o API token: https://id.atlassian.com/manage-profile/security/api-tokens  ("Create API token").
# Numero do quadro: abra o quadro no Jira; na URL aparece .../boards/NUMERO.
# Desfazer:  .\Configurar-Jira.ps1 -Remover
# So recriar a tarefa agendada (sem digitar tudo de novo; usa a configuracao ja salva):  .\Configurar-Jira.ps1 -SoAgendar
param([switch]$Remover, [switch]$SoAgendar, [switch]$PastaIniciar)
$ErrorActionPreference = 'Stop'
$nomeTarefa = 'ReceberTela-Jira'
$nomeAtalho = 'Sincronizar Jira (TV).lnk'
$pastaCfg = Join-Path $env:APPDATA 'ReceberTela'
$cfgArq = Join-Path $pastaCfg 'jira.json'
$sync = Join-Path $PSScriptRoot 'Sincronizar-Jira.ps1'
function Criar-Pasta-Iniciar {
  try {
    $lnkP = Join-Path ([Environment]::GetFolderPath('Startup')) $nomeAtalho
    $l = (New-Object -ComObject WScript.Shell).CreateShortcut($lnkP)
    $l.TargetPath = 'powershell.exe'
    $l.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $sync + '" -Continuo'
    $l.WorkingDirectory = $PSScriptRoot; $l.WindowStyle = 7; $l.Description = 'Atualiza as tarefas do Jira na tela da TV'
    $l.Save()
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like '*Sincronizar-Jira.ps1*-Continuo*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Process powershell.exe -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $sync + '" -Continuo') -WindowStyle Hidden
    Write-Host "Atalho criado na pasta Iniciar: $lnkP" -ForegroundColor Gray
    return $true
  } catch { Write-Host ("Aviso: pasta Iniciar falhou: " + $_.Exception.Message) -ForegroundColor Yellow; return $false }
}
function Criar-Tarefa {
  if ($PastaIniciar) { return (Criar-Pasta-Iniciar) }
  $ok = $false
  try {
    $acao = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $sync + '"')
    $gat1 = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 1) -RepetitionDuration (New-TimeSpan -Days 3650)
    $gat2 = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
    $conf = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 2) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName $nomeTarefa -Action $acao -Trigger @($gat1, $gat2) -Settings $conf -Description 'Atualiza as tarefas do Jira na tela da TV' -Force -ErrorAction Stop | Out-Null
    $ok = $true
  } catch { Write-Host ("Aviso: metodo 1 falhou: " + $_.Exception.Message) -ForegroundColor Yellow }
  if (-not $ok) {   # metodo alternativo: schtasks.exe
    Write-Host "Tentando o metodo alternativo (schtasks)..." -ForegroundColor Yellow
    $tr = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $sync + '"'
    & schtasks.exe /Create /TN $nomeTarefa /SC MINUTE /MO 1 /TR $tr /F
    $ok = ($LASTEXITCODE -eq 0)
  }
  if ($ok -and -not (Get-ScheduledTask -TaskName $nomeTarefa -ErrorAction SilentlyContinue)) { $ok = $false }
  if ($ok) { try { Start-ScheduledTask -TaskName $nomeTarefa } catch { } ; return $true }
  # sem permissao para o Agendador de Tarefas (politica da rede): inicia com o Windows pela pasta Iniciar
  Write-Host "Sem permissao para o Agendador de Tarefas. Usando a pasta Iniciar do Windows..." -ForegroundColor Yellow
  return (Criar-Pasta-Iniciar)
}
function Fim($m) { Write-Host ""; Write-Host $m; Read-Host "Pressione Enter para fechar" | Out-Null }

if ($Remover) {
  Unregister-ScheduledTask -TaskName $nomeTarefa -Confirm:$false -ErrorAction SilentlyContinue
  Remove-Item (Join-Path ([Environment]::GetFolderPath('Startup')) $nomeAtalho) -Force -ErrorAction SilentlyContinue
  Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like '*Sincronizar-Jira.ps1*-Continuo*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  Remove-Item $cfgArq -Force -ErrorAction SilentlyContinue
  Fim "Removido: tarefa agendada e configuracao do Jira. As tarefas voltam a vir do pauta.json."; exit 0
}
if (-not (Test-Path $sync)) { Fim "Nao encontrei Sincronizar-Jira.ps1 ao lado deste script."; exit 1 }

if ($SoAgendar) {
  if (-not (Test-Path $cfgArq)) { Fim "Nao ha configuracao salva ($cfgArq). Rode Configurar-Jira.bat sem parametros."; exit 1 }
  if (Criar-Tarefa) { Fim "Tarefa agendada criada. As tarefas do Jira atualizam sozinhas (a cada 15 s)."; exit 0 }
  Fim "Nao consegui criar a tarefa agendada (veja as mensagens acima e envie para o suporte)."; exit 1
}
Write-Host "=== Ligar a TV ao Jira ===" -ForegroundColor Cyan
Write-Host ""
$site = (Read-Host "Endereco do Jira (ex.: https://suaempresa.atlassian.net)").Trim().TrimEnd('/')
if ($site -notmatch '^https://[^/]+') { Fim "O endereco precisa comecar com https://"; exit 1 }
$email = (Read-Host "E-mail da sua conta Atlassian").Trim()
$tokenSec = Read-Host "API token (nao aparece enquanto digita)" -AsSecureString
$quadro = (Read-Host "Numero do quadro (board)").Trim()
if ($quadro -notmatch '^\d+$') { Fim "O numero do quadro deve conter so digitos."; exit 1 }

New-Item -ItemType Directory -Force $pastaCfg | Out-Null
$cfg = [ordered]@{ site = $site; email = $email; tokenProtegido = (ConvertFrom-SecureString $tokenSec); quadro = [int]$quadro; maximo = 100 }
[IO.File]::WriteAllText($cfgArq, ($cfg | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))

Write-Host ""; Write-Host "Testando a conexao..." -ForegroundColor Yellow
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $sync -Mostrar
if ($LASTEXITCODE -ne 0) {
  Remove-Item $cfgArq -Force -ErrorAction SilentlyContinue
  Fim "Nao deu certo (veja a mensagem acima). Confira site, e-mail, token e numero do quadro e rode de novo."; exit 1
}

if (-not (Criar-Tarefa)) { Fim "A conexao com o Jira funciona, mas NAO consegui criar a tarefa agendada (veja a mensagem acima). Sem ela a TV nao atualiza sozinha."; exit 1 }
Fim "Pronto! As tarefas do Jira aparecem na lateral direita da TV e atualizam a cada 15 segundos."
