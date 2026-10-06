/*
 * Test proxy for alut.dll (phase 0, step 3).
 *
 * All 20 exports are forwarded to alut_orig.dll via forwards.h, so the
 * game keeps using the original code. The only thing this DLL does on its
 * own is write one line to %LOCALAPPDATA%\TF3Multiplayer\proxy.log when it
 * is loaded and unloaded, which proves the game accepts a replaced alut.dll.
 *
 * Only kernel32 and user32 (wsprintfA) are used, because DllMain runs under the
 * loader lock. Both are already loaded by the game before alut.dll.
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include "forwards.h"

#define PROXY_VERSION "1"

static void log_line(const char *event)
{
	char dir[MAX_PATH];
	char path[MAX_PATH];
	char line[512];
	SYSTEMTIME t;
	DWORD n = GetEnvironmentVariableA("LOCALAPPDATA", dir, sizeof(dir));
	HANDLE h;
	int len;

	if (n == 0 || n >= sizeof(dir))
		return;
	wsprintfA(path, "%s\\TF3Multiplayer", dir);
	CreateDirectoryA(path, NULL);
	wsprintfA(path, "%s\\TF3Multiplayer\\proxy.log", dir);

	GetLocalTime(&t);
	len = wsprintfA(line, "%04d-%02d-%02d %02d:%02d:%02d alut proxy v" PROXY_VERSION " %s pid=%lu\r\n",
		t.wYear, t.wMonth, t.wDay, t.wHour, t.wMinute, t.wSecond, event, GetCurrentProcessId());

	OutputDebugStringA(line);
	h = CreateFileA(path, FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
	if (h != INVALID_HANDLE_VALUE) {
		DWORD written;
		WriteFile(h, line, (DWORD)len, &written, NULL);
		CloseHandle(h);
	}
}

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID reserved)
{
	(void)reserved;
	if (reason == DLL_PROCESS_ATTACH) {
		DisableThreadLibraryCalls(instance);
		log_line("loaded");
	} else if (reason == DLL_PROCESS_DETACH) {
		log_line("unloaded");
	}
	return TRUE;
}
