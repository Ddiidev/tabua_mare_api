@echo off
setlocal
pushd "%~dp0"

set "COMPAT_LIB_DIR=%~dp0out\msvc-libs"
if not defined OPENSSL_LIB set "OPENSSL_LIB=C:\Program Files\OpenSSL-Win64\lib\VC\x64\MD\libcrypto.lib"

if not exist "%OPENSSL_LIB%" (
    echo OpenSSL import library not found: "%OPENSSL_LIB%"
    echo Set OPENSSL_LIB to the installed libcrypto.lib path and retry.
    set "EXIT_CODE=1"
    goto :finish
)

if not exist "%COMPAT_LIB_DIR%" mkdir "%COMPAT_LIB_DIR%"
copy /Y "%OPENSSL_LIB%" "%COMPAT_LIB_DIR%\crypto.lib" >nul
if errorlevel 1 (
    echo Could not prepare the MSVC compatibility library.
    set "EXIT_CODE=1"
    goto :finish
)

v -cc msvc -g -ldflags "/LIBPATH:%COMPAT_LIB_DIRe %" -o "%~dp0out\tabua-mare-api.exe" -d using_sqlite -d dev_static_gzip watch --only-watch=*.v,*.html,*.css,*.js --before "taskkill /f /im tabua-mare-api.exe" --before "cls" run . 3330
set "EXIT_CODE=%errorlevel%"

:finish
popd
exit /b %EXIT_CODE%
