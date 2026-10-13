@echo off
setlocal
cd /d "%~dp0..\native\alut_proxy"
set /p VSDIR=<build\vsdir.txt
call "%VSDIR%\VC\Auxiliary\Build\vcvars64.bat" >nul || exit /b 1
cl /nologo /O2 /W4 ..\..\tests\net_order_unit.c /Fobuild\net_order_unit.obj /Febuild\net_order_unit.exe /link kernel32.lib user32.lib advapi32.lib ws2_32.lib || exit /b 1
build\net_order_unit.exe
exit /b %errorlevel%
