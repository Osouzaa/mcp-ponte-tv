@echo off
rem Recria so a tarefa agendada que atualiza as tarefas do Jira (usa a configuracao ja salva).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Configurar-Jira.ps1" -SoAgendar
