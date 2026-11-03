@echo off
setlocal
chcp 65001 >nul
set "ROOT=%~dp0"
set "JAVA=java"
if defined JAVA_HOME if exist "%JAVA_HOME%\bin\java.exe" set "JAVA=%JAVA_HOME%\bin\java.exe"

if not exist "%ROOT%out" (
    echo [ERRO] Projeto nao compilado. Execute build.bat primeiro.
    exit /b 1
)

cd /d "%ROOT%"
"%JAVA%" -Dfile.encoding=UTF-8 -cp "out;lib\sqlite-jdbc-3.54.1.0.jar" server.RowServer %*
