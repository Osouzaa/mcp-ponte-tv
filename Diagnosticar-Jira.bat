@echo off
rem Mostra por que as tarefas do Jira nao atualizam na TV (rodar na ponte).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Diagnosticar-Jira.ps1"
