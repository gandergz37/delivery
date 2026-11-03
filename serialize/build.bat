@echo off
setlocal
chcp 65001 >nul
set "ROOT=%~dp0"
set "SQLITE_JAR=%ROOT%lib\sqlite-jdbc-3.54.1.0.jar"

if not exist "%SQLITE_JAR%" (
    echo [ERRO] Driver SQLite nao encontrado: "%SQLITE_JAR%"
    exit /b 1
)

set "JAVAC=javac"
if defined JAVA_HOME if exist "%JAVA_HOME%\bin\javac.exe" set "JAVAC=%JAVA_HOME%\bin\javac.exe"
if not "%JAVAC%"=="javac" goto :havejavac
where javac >nul 2>nul
if errorlevel 1 (
    echo [ERRO] javac nao encontrado. Instale um JDK 17+ ou defina JAVA_HOME.
    exit /b 1
)
:havejavac

if exist "%ROOT%out" rmdir /s /q "%ROOT%out"
mkdir "%ROOT%out"

dir /s /b "%ROOT%src\*.java" > "%ROOT%sources.txt"

"%JAVAC%" -encoding UTF-8 -cp "%SQLITE_JAR%" -d "%ROOT%out" @"%ROOT%sources.txt"
set "RESULT=%ERRORLEVEL%"
del "%ROOT%sources.txt" >nul 2>nul

if not "%RESULT%"=="0" (
    echo.
    echo [ERRO] Falha na compilacao.
    exit /b %RESULT%
)

echo.
echo Compilacao concluida: "%ROOT%out"
exit /b 0
