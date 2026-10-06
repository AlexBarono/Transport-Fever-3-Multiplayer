@echo off
rem Builds build\alut.dll (x64) with the MSVC toolset of Visual Studio.
setlocal
cd /d "%~dp0"
if not exist build mkdir build
set VSDIR=
set VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe
if not exist "%VSWHERE%" set VSWHERE=%ProgramFiles%\Microsoft Visual Studio\Installer\vswhere.exe
if exist "%VSWHERE%" (
	"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath > build\vsdir.txt
	set /p VSDIR=<build\vsdir.txt
)
rem Without vswhere, the folder found by an earlier build is used.
if not defined VSDIR if exist build\vsdir.txt set /p VSDIR=<build\vsdir.txt
if not defined VSDIR (
	echo Visual Studio with C++ tools not found.
	exit /b 1
)
call "%VSDIR%\VC\Auxiliary\Build\vcvars64.bat" >nul || exit /b 1
cd /d "%~dp0"
cl /nologo /O2 /W4 /GS- /LD alut_proxy.c net.c bridge.c /Fobuild\ /Febuild\alut.dll /link /NODEFAULTLIB /ENTRY:DllMain kernel32.lib user32.lib advapi32.lib ws2_32.lib || exit /b 1
echo Built build\alut.dll
