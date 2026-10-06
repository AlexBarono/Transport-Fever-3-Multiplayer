/*
 * Lua <-> DLL bridge (phase 1).
 *
 * TF3 mods run in a Lua sandbox without io, so the file exchange of the TF2
 * multiplayer mod is not possible. Instead:
 *   - Lua -> DLL: the mp_probe mod writes tagged lines with debugPrint into
 *     stdout.txt; this thread tails that file.
 *   - DLL -> Lua: this thread sets the environment variable TF3MP_IN with
 *     _putenv_s of ucrtbase.dll, the C runtime the game itself uses, and the
 *     mod reads it with os.getenv("TF3MP_IN") every bridge tick.
 *
 * Lines the DLL reacts to:
 *   "net send <line>"           a build the mod captured; goes to net.c
 *   "net received token=<t> "   the mod has the received line <t>; it is
 *                               dropped and the next one offered
 *   "bridge out seq=<n>"        a bridge tick; TF3MP_IN is refreshed with
 *                               "line <token> <kind> <line>" for the oldest
 *                               received line, or "ack <n>" if there is none
 * Results go to alut_proxy.log. Built without the C runtime (see build.bat),
 * so only kernel32 functions and hand-written string helpers are used.
 */
#include "proxy.h"

#define TAIL_INTERVAL_MS 500
#define READ_CHUNK 8192
/* A captured build line plus the game's log prefix. */
#define LINE_MAX_LEN (NET_LINE_MAX + 256)

typedef int (__cdecl *putenv_s_fn)(const char *name, const char *value);

static HANDLE thread;
static volatile LONG stopping;
static putenv_s_fn putenv_s;
static char stdout_path[MAX_PATH];
static char read_buf[READ_CHUNK];
static char line_buf[LINE_MAX_LEN];
static int line_len;
static int line_cut;
static char env_value[NET_LINE_MAX + 64];

/* Without the "[mp_probe]" tag, in case debugPrint separates its arguments. */
static const char MARKER[] = "bridge out seq=";
static const char SEND_MARKER[] = "net send ";
static const char RECEIVED_MARKER[] = "net received token=";

static const char *find(const char *hay, const char *needle)
{
	for (; *hay; hay++) {
		const char *h = hay, *n = needle;
		while (*n && *h == *n) {
			h++;
			n++;
		}
		if (!*n)
			return hay;
	}
	return NULL;
}

static void set_env(const char *value)
{
	int err;

	if (!putenv_s)
		return;
	err = putenv_s("TF3MP_IN", value);
	/* A build line is long; the log only needs its start. */
	proxy_log("bridge: TF3MP_IN=%.80s%s (%s)", value, lstrlenA(value) > 80 ? "..." : "", err == 0 ? "ok" : "failed");
}

/* Offers the oldest received line to the mod, or acknowledges the tick. */
static void refresh_env(unsigned long seq)
{
	if (!net_inbox_value(env_value, sizeof(env_value)))
		wsprintfA(env_value, "ack %lu", seq);
	set_env(env_value);
}

/* Picks the newest <steam>\userdata\<id>\3493540\local\crash_dump\stdout.txt into stdout_path. */
static void search_userdata(const char *steam, FILETIME *newest)
{
	char pattern[MAX_PATH], candidate[MAX_PATH];
	WIN32_FIND_DATAA entry;
	WIN32_FILE_ATTRIBUTE_DATA attr;
	HANDLE search;

	if (lstrlenA(steam) > MAX_PATH - 80)
		return;
	wsprintfA(pattern, "%s\\userdata\\*", steam);
	search = FindFirstFileA(pattern, &entry);
	if (search == INVALID_HANDLE_VALUE)
		return;
	do {
		if (entry.cFileName[0] == '.' || !(entry.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY))
			continue;
		wsprintfA(candidate, "%s\\userdata\\%s\\3493540\\local\\crash_dump\\stdout.txt", steam, entry.cFileName);
		if (GetFileAttributesExA(candidate, GetFileExInfoStandard, &attr) &&
		    CompareFileTime(&attr.ftLastWriteTime, newest) > 0) {
			*newest = attr.ftLastWriteTime;
			lstrcpyA(stdout_path, candidate);
		}
	} while (FindNextFileA(search, &entry));
	FindClose(search);
}

/* Finds stdout.txt under the Steam folder. Steam keeps userdata in its own folder, which the
 * registry names; the game may sit in another Steam library. As a fallback the DLL's own path is
 * used: in the main library it is Steam\steamapps\common\Transport Fever 3\alut.dll. */
static int find_stdout(void)
{
	char steam[MAX_PATH];
	FILETIME newest = { 0, 0 };
	DWORD size = sizeof(steam);
	int i, levels = 0;

	if (RegGetValueA(HKEY_CURRENT_USER, "Software\\Valve\\Steam", "SteamPath", RRF_RT_REG_SZ, NULL, steam, &size) == ERROR_SUCCESS)
		search_userdata(steam, &newest);
	if (stdout_path[0] || !proxy_file_next_to_dll(steam, "x"))
		return stdout_path[0] != 0;
	for (i = lstrlenA(steam) - 1; i > 0; i--) {
		if (steam[i] == '\\' && ++levels == 4) {
			steam[i] = 0;
			break;
		}
	}
	if (levels == 4)
		search_userdata(steam, &newest);
	return stdout_path[0] != 0;
}

static void handle_line(void)
{
	const char *hit, *p;
	char token[32];
	unsigned long seq = 0;
	int n = 0;

	line_buf[line_len] = 0;
	hit = find(line_buf, SEND_MARKER);
	if (hit) {
		if (line_cut)
			proxy_log("bridge: captured line longer than %d characters, not sent", LINE_MAX_LEN - 1);
		else
			net_send_line(hit + sizeof(SEND_MARKER) - 1);
		return;
	}
	hit = find(line_buf, RECEIVED_MARKER);
	if (hit) {
		for (p = hit + sizeof(RECEIVED_MARKER) - 1; *p && *p != ' ' && n < (int)sizeof(token) - 1; p++)
			token[n++] = *p;
		token[n] = 0;
		if (net_inbox_ack(token)) {
			proxy_log("bridge: the mod has line %s", token);
			/* Offer the next line right away instead of on the next tick. */
			refresh_env(0);
		}
		return;
	}
	hit = find(line_buf, MARKER);
	if (!hit)
		return;
	for (p = hit + sizeof(MARKER) - 1; *p >= '0' && *p <= '9'; p++)
		seq = seq * 10 + (unsigned long)(*p - '0');
	refresh_env(seq);
}

static DWORD WINAPI bridge_thread(LPVOID arg)
{
	LARGE_INTEGER offset, size;
	HANDLE file;
	DWORD got, i;
	int first = 1;

	(void)arg;
	putenv_s = (putenv_s_fn)GetProcAddress(GetModuleHandleA("ucrtbase.dll"), "_putenv_s");
	proxy_log("bridge: ucrtbase _putenv_s %s", putenv_s ? "found" : "NOT found");
	set_env("hello");

	/* stdout.txt may be created a moment after the game starts. */
	for (i = 0; i < 60 && !stopping && !find_stdout(); i++)
		Sleep(1000);
	if (!stdout_path[0]) {
		proxy_log("bridge: stdout.txt not found, Lua -> DLL test skipped");
		return 0;
	}
	proxy_log("bridge: tailing %s", stdout_path);

	offset.QuadPart = 0;
	while (!stopping) {
		Sleep(TAIL_INTERVAL_MS);
		file = CreateFileA(stdout_path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
			NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
		if (file == INVALID_HANDLE_VALUE)
			continue;
		if (GetFileSizeEx(file, &size)) {
			/* Only lines written after the game started count; a smaller file was rewritten. */
			if (first || size.QuadPart < offset.QuadPart) {
				offset.QuadPart = first ? size.QuadPart : 0;
				line_len = 0;
				line_cut = 0;
				first = 0;
			}
			SetFilePointerEx(file, offset, NULL, FILE_BEGIN);
			while (ReadFile(file, read_buf, READ_CHUNK, &got, NULL) && got > 0) {
				offset.QuadPart += got;
				for (i = 0; i < got; i++) {
					char c = read_buf[i];
					if (c == '\n') {
						handle_line();
						line_len = 0;
						line_cut = 0;
					} else if (c != '\r') {
						if (line_len < LINE_MAX_LEN - 1)
							line_buf[line_len++] = c;
						else
							line_cut = 1;
					}
				}
			}
		}
		CloseHandle(file);
	}
	return 0;
}

void bridge_start(void)
{
	/* The thread only starts running after the loader lock is released. */
	thread = CreateThread(NULL, 0, bridge_thread, NULL, 0, NULL);
	if (!thread)
		proxy_log("bridge: CreateThread failed (%lu)", GetLastError());
}

void bridge_stop(void)
{
	InterlockedExchange(&stopping, 1);
}
