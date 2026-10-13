@echo off
cd /d "%~dp0"
".venv\Scripts\python.exe" -X utf8 app.py stop >nul 2>&1
".venv\Scripts\python.exe" -X utf8 restart_wait.py
if errorlevel 1 (
  echo Monitor did not stop within 60 seconds.
  pause
  exit /b 1
)
".venv\Scripts\python.exe" -X utf8 app.py start
if errorlevel 1 exit /b 1
".venv\Scripts\python.exe" -X utf8 app.py status
pause
