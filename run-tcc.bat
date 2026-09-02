@echo off
setlocal
pushd "%~dp0"

set "PG_BIN=%ProgramFiles%\PostgreSQL\18\bin"
if defined POSTGRES_BIN set "PG_BIN=%POSTGRES_BIN%"

if not exist "%PG_BIN%\libpq.dll" (
    echo PostgreSQL runtime library not found: "%PG_BIN%\libpq.dll"
    echo Set POSTGRES_BIN to the PostgreSQL bin directory and retry.
    set "EXIT_CODE=1"
    goto :finish
)

for %%I in ("%PG_BIN%") do set "PG_BIN_SHORT=%%~sI"
if not defined PG_BIN_SHORT (
    echo Could not resolve a linker path for: "%PG_BIN%"
    set "EXIT_CODE=1"
    goto :finish
)

set "PATH=%PG_BIN%;%PATH%"

v -cc tcc -g -ldflags "-L%PG_BIN_SHORT%" -o "%~dp0out\tabua-mare-api-tcc.exe" -d using_sqlite -d dev_static_gzip watch --only-watch=*.v,*.html,*.css,*.js --before "taskkill /f /im tabua-mare-api-tcc.exe" --before "cls" run . 3330
set "EXIT_CODE=%errorlevel%"

:finish
popd
exit /b %EXIT_CODE%
