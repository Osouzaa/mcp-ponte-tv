@echo off
rem De duplo clique para ligar a TV ao Jira (rodar na maquina-ponte, com o usuario que fica logado).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Configurar-Jira.ps1"
