@echo off
rem Abre o Desbostificar.ps1. Ele mesmo pede permissao de administrador (UAC).
rem O "-ExecutionPolicy Bypass" vale so para esta execucao; nao muda nada no sistema.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Desbostificar.ps1"
if errorlevel 1 pause
