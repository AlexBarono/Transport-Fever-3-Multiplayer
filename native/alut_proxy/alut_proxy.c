/*
 * Proxy for alut.dll, the native entry point of the multiplayer mod.
 *
 * All 20 exports are forwarded to alut_orig.dll (the renamed original) via
 * forwards.h, so the game keeps using the original code.
 *
 * On its own this DLL
 *   - writes alut_proxy.log next to itself (the game process has no
 *     LOCALAPPDATA, see docs/native-entry-point.md), and
 *   - starts the UDP peer link from net.c if alut_proxy.ini enables it
 *     (phase 1, step 2), and
 *   - runs the Lua <-> DLL bridge from bridge.c (phase 1, step 3), which
 *     hands captured build lines to net.c and received ones to the mod
 *     (phase 1, step 4).
 *
 * DllMain runs under the loader lock, so it only uses kernel32/user32 and
 * leaves Winsock to the network thread.
 */
#include "proxy.h"

#include "forwards.h"

static HINSTANCE self;
static char log_path[MAX_PATH];

/* One fresh, local launcher request. Consume before the main menu is created;
 * Steam may already be running, so inherited environment variables are insufficient. */
static void consume_launch_request(void)
{
	char path[MAX_PATH], name[1441];
	HANDLE file;
	FILETIME written, now;
	ULARGE_INTEGER age, current;
	DWORD n, i;
	SetEnvironmentVariableA("TF3MP_AUTOLOAD", "");
	if (!proxy_file_next_to_dll(path, "alut_proxy.launch")) return;
	file = CreateFileA(path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
	if (file == INVALID_HANDLE_VALUE) return;
	if (!GetFileTime(file, NULL, NULL, &written)) { CloseHandle(file); return; }
	CloseHandle(file); GetSystemTimeAsFileTime(&now);
	age.LowPart = written.dwLowDateTime; age.HighPart = written.dwHighDateTime;
	current.LowPart = now.dwLowDateTime; current.HighPart = now.dwHighDateTime;
	if (current.QuadPart < age.QuadPart || current.QuadPart - age.QuadPart > 3000000000ULL) { DeleteFileA(path); return; }
	n = GetPrivateProfileStringA("launch", "save_hex", "", name, sizeof(name), path);
	if (!DeleteFileA(path) || !n || n >= sizeof(name)-1 || n % 2) return;
	for (i = 0; i < n; i++) if (!((name[i] >= '0' && name[i] <= '9') || (name[i] >= 'a' && name[i] <= 'f'))) return;
	SetEnvironmentVariableA("TF3MP_AUTOLOAD", name);
	proxy_log("launcher: one-shot automatic save load armed");
}

int proxy_file_next_to_dll(char *out, const char *name)
{
	DWORD n = GetModuleFileNameA(self, out, MAX_PATH);
	char *slash;

	if (n == 0 || n >= MAX_PATH - 32)
		return 0;
	slash = out + n;
	while (slash > out && *slash != '\\')
		slash--;
	wsprintfA(slash, "\\%s", name);
	return 1;
}

void proxy_log(const char *fmt, ...)
{
	/* wvsprintfA writes at most 1024 characters after the timestamp. */
	char line[1100];
	SYSTEMTIME t;
	va_list args;
	int len;
	HANDLE h;
	DWORD written;

	GetLocalTime(&t);
	len = wsprintfA(line, "%04d-%02d-%02d %02d:%02d:%02d [%lu] ",
		t.wYear, t.wMonth, t.wDay, t.wHour, t.wMinute, t.wSecond, GetCurrentProcessId());
	va_start(args, fmt);
	len += wvsprintfA(line + len, fmt, args);
	va_end(args);
	line[len++] = '\r';
	line[len++] = '\n';
	line[len] = 0;

	OutputDebugStringA(line);
	if (!log_path[0])
		return;
	h = CreateFileA(log_path, FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
	if (h != INVALID_HANDLE_VALUE) {
		WriteFile(h, line, (DWORD)len, &written, NULL);
		CloseHandle(h);
	}
}

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID reserved)
{
	(void)reserved;
	if (reason == DLL_PROCESS_ATTACH) {
		self = instance;
		DisableThreadLibraryCalls(instance);
		proxy_file_next_to_dll(log_path, "alut_proxy.log");
		proxy_log("alut proxy v" PROXY_VERSION " loaded");
		consume_launch_request();
		net_start();
		bridge_start();
	} else if (reason == DLL_PROCESS_DETACH) {
		net_stop();
		bridge_stop();
		proxy_log("alut proxy v" PROXY_VERSION " unloaded");
	}
	return TRUE;
}
