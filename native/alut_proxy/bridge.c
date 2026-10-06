/*
 * Lua <-> DLL bridge test (phase 1).
 *
 * TF3 mods run in a Lua sandbox without io, so the file exchange of the TF2
 * multiplayer mod is not possible. This tests two other ways:
 *   - Lua -> DLL: the mp_probe mod writes "[mp_probe]bridge out seq=N" with
 *     debugPrint into stdout.txt; this thread tails that file.
 *   - DLL -> Lua: this thread sets the environment variable TF3MP_IN with
 *     _putenv_s of ucrtbase.dll, the C runtime the game itself uses, so the
 *     mod's os.getenv("TF3MP_IN") should see it.
 * Results go to alut_proxy.log. Built without the C runtime (see build.bat),
 * so only kernel32 functions and hand-written string helpers are used.
 */
#include "proxy.h"

#define TAIL_INTERVAL_MS 500
#define READ_CHUNK 8192
#define LINE_MAX_LEN 1024

typedef int (__cdecl *putenv_s_fn)(const char *name, const char *value);

static HANDLE thread;
static volatile LONG stopping;
static putenv_s_fn putenv_s;
static char stdout_path[MAX_PATH];
static char read_buf[READ_CHUNK];
static char line_buf[LINE_MAX_LEN];
static int line_len;

/* Without the "[mp_probe]" tag, in case debugPrint separates its arguments. */
static const char MARKER[] = "bridge out seq=";
/* The mod logs this each time it stores a build; the DLL then asks for one replay of it. The mod
 * itself limits the number of replays and ignores the copy's own build event. */
static const char CAPTURE_MARKER[] = "capture stored for replay";
static int replay_requested;

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
	proxy_log("bridge: TF3MP_IN=%s (%s)", value, err == 0 ? "ok" : "failed");
}

/* Finds the newest Steam\userdata\<id>\3493540\local\crash_dump\stdout.txt.
 * The DLL sits in Steam\steamapps\common\Transport Fever 3, three levels below Steam. */
static int find_stdout(void)
{
	char steam[MAX_PATH], pattern[MAX_PATH], candidate[MAX_PATH];
	WIN32_FIND_DATAA entry;
	WIN32_FILE_ATTRIBUTE_DATA attr;
	FILETIME newest = { 0, 0 };
	HANDLE search;
	int i, levels = 0;

	if (!proxy_file_next_to_dll(steam, "x"))
		return 0;
	for (i = lstrlenA(steam) - 1; i > 0; i--) {
		if (steam[i] == '\\' && ++levels == 4) {
			steam[i] = 0;
			break;
		}
	}
	if (levels < 4)
		return 0;
	wsprintfA(pattern, "%s\\userdata\\*", steam);
	search = FindFirstFileA(pattern, &entry);
	if (search == INVALID_HANDLE_VALUE)
		return 0;
	do {
		if (entry.cFileName[0] == '.' || !(entry.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY))
			continue;
		wsprintfA(candidate, "%s\\userdata\\%s\\3493540\\local\\crash_dump\\stdout.txt", steam, entry.cFileName);
		if (GetFileAttributesExA(candidate, GetFileExInfoStandard, &attr) &&
		    CompareFileTime(&attr.ftLastWriteTime, &newest) > 0) {
			newest = attr.ftLastWriteTime;
			lstrcpyA(stdout_path, candidate);
		}
	} while (FindNextFileA(search, &entry));
	FindClose(search);
	return stdout_path[0] != 0;
}

static void handle_line(void)
{
	const char *hit, *p;
	char value[48];
	unsigned long seq = 0;

	line_buf[line_len] = 0;
	if (find(line_buf, CAPTURE_MARKER)) {
		proxy_log("bridge: the mod stored a build for replay");
		replay_requested = 1;
	}
	hit = find(line_buf, MARKER);
	if (!hit)
		return;
	for (p = hit + sizeof(MARKER) - 1; *p >= '0' && *p <= '9'; p++)
		seq = seq * 10 + (unsigned long)(*p - '0');
	proxy_log("bridge: got from Lua: bridge out seq=%lu", seq);
	if (replay_requested == 1) {
		/* One tick after the capture, ask the mod to rebuild it (phase 1 test on one PC). */
		replay_requested = 0;
		wsprintfA(value, "replay %lu", seq);
		proxy_log("bridge: asking the mod to replay the stored build");
	} else {
		wsprintfA(value, "ack %lu", seq);
	}
	set_env(value);
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
					} else if (c != '\r' && line_len < LINE_MAX_LEN - 1) {
						line_buf[line_len++] = c;
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
