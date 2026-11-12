# Diagnosticar-Jira.ps1 - mostra por que as tarefas do Jira nao estao atualizando na TV. Rodar na maquina-ponte
# (com o mesmo usuario que fez o Configurar-Jira). Nao altera nada, so le e faz uma busca de teste.
# Dica: se aparecer "Task Scheduler: tarefa NAO encontrada" ou o caminho do script nao existir, rode Configurar-Jira.bat de novo.
$nomeTarefa = 'ReceberTela-Jira'
$cfgArq = Join-Path $env:APPDATA 'ReceberTela\jira.json'
$logArq = Join-Path $env:APPDATA 'ReceberTela\jira-sync.log'
$saida  = Join-Path $env:ProgramData 'ReceberTela\jira-tarefas.json'
function Ok($m) { Write-Host "[ OK ] $m" -ForegroundColor Green }
function Ruim($m) { Write-Host "[FALHA] $m" -ForegroundColor Red }
function Info($m) { Write-Host "       $m" -ForegroundColor Gray }
Write-Host "=== Diagnostico Jira -> TV ===  ($env:USERDOMAIN\$env:USERNAME, $(Get-Date -Format 'dd/MM HH:mm:ss'))" -ForegroundColor Cyan; Write-Host ""

# 1) configuracao
if (Test-Path $cfgArq) { $c = Get-Content $cfgArq -Raw -Encoding UTF8 | ConvertFrom-Json; Ok "Config encontrada: site $($c.site), quadro $($c.quadro), e-mail $($c.email)" }
else { Ruim "Config nao encontrada ($cfgArq). Rode Configurar-Jira.bat COM ESTE USUARIO." }

# 2) arquivo que a TV le
if (Test-Path $saida) {
  $it = Get-Item $saida; $idade = [int]((Get-Date) - $it.LastWriteTime).TotalMinutes
  try { $j = Get-Content $saida -Raw -Encoding UTF8 | ConvertFrom-Json; $n = @($j.tarefas).Count; $at = $j.atualizado } catch { $n = '?'; $at = '?' }
  if ($idade -le 3) { Ok "jira-tarefas.json atualizado ha $idade min ($n tarefas, atualizado=$at)" } else { Ruim "jira-tarefas.json parado ha $idade min (ultima escrita $($it.LastWriteTime.ToString('dd/MM HH:mm')); $n tarefas)" }
} else { Ruim "jira-tarefas.json NAO existe em $saida. Rode o Instalar-Ponte.bat (versao nova)." }

# 3) tarefa agendada
$t = Get-ScheduledTask -TaskName $nomeTarefa -ErrorAction SilentlyContinue
if (-not $t) {
  $lnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'Sincronizar Jira (TV).lnk'
  $proc = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like '*Sincronizar-Jira.ps1*-Continuo*' })
  if ((Test-Path $lnk) -and $proc.Count -gt 0) { Ok "Sem Agendador de Tarefas, mas a sincronizacao roda pela pasta Iniciar (processo ativo, PID $($proc[0].ProcessId))." }
  elseif (Test-Path $lnk) { Ruim "Atalho na pasta Iniciar existe, mas o processo NAO esta rodando. Rode Agendar-Jira.bat." }
  else { Ruim "Nem tarefa agendada nem atalho na pasta Iniciar. Rode Agendar-Jira.bat." }
}
else {
  $inf = $t | Get-ScheduledTaskInfo
  $arg = "$($t.Actions[0].Arguments)"
  $script = ''; if ($arg -match '-File\s+"([^"]+)"') { $script = $Matches[1] }
  Info "Estado: $($t.State)   Usuario: $($t.Principal.UserId)   Ultima execucao: $($inf.LastRunTime)   Resultado: 0x$('{0:X}' -f $inf.LastTaskResult)   Proxima: $($inf.NextRunTime)"
  Info "Repeticao: a cada $($t.Triggers[0].Repetition.Interval)   Script: $script"
  if ($t.State -eq 'Disabled') { Ruim "A tarefa esta DESABILITADA." }
  if ($script -and -not (Test-Path $script)) { Ruim "O script da tarefa NAO existe mais nesse caminho (pasta movida/renomeada). Rode Configurar-Jira.bat de novo na pasta atual." }
  elseif ($script) { Ok "Script da tarefa existe." }
  if ($inf.LastRunTime -lt (Get-Date).AddMinutes(-5)) { Ruim "A tarefa nao executa ha mais de 5 min (ultima: $($inf.LastRunTime))." }
  elseif ($inf.LastTaskResult -ne 0 -and $inf.LastTaskResult -ne 267009) { Ruim "A ultima execucao terminou com erro 0x$('{0:X}' -f $inf.LastTaskResult)." } else { Ok "Tarefa executando." }
}

# 4) log
Write-Host ""; Write-Host "Ultimas linhas do log ($logArq):" -ForegroundColor Cyan
if (Test-Path $logArq) { Get-Content $logArq -Tail 8 | ForEach-Object { Info $_ } } else { Info "(sem log: a sincronizacao nunca rodou com sucesso/erro por esta conta)" }

# 5) busca de teste agora
Write-Host ""; Write-Host "Busca de teste agora:" -ForegroundColor Cyan
$sync = Join-Path $PSScriptRoot 'Sincronizar-Jira.ps1'
if (Test-Path $sync) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $sync -Mostrar; if ($LASTEXITCODE -eq 0) { Ok "Busca de teste funcionou e gravou o arquivo." } else { Ruim "Busca de teste falhou (mensagem acima)." } }
else { Ruim "Sincronizar-Jira.ps1 nao esta ao lado deste script." }
Write-Host ""; Read-Host "Pressione Enter para fechar" | Out-Null
