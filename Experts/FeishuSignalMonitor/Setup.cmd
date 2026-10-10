@echo off
cd /d "%~dp0"
python -X utf8 -m venv .venv
if errorlevel 1 exit /b 1
".venv\Scripts\python.exe" -X utf8 -m pip install -r requirements.txt
if errorlevel 1 exit /b 1
".venv\Scripts\python.exe" -X utf8 app.py status
pause
