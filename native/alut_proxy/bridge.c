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
 *   "net state <key> <text>"    v8: this game's latest state under key (a
 *                               short word in lower case), for the peer; it
 *                               is also put into TF3MP_OWN_<KEY>
 * The peer's states go into TF3MP_PEER_<KEY> (empty once the peer went
 * silent), and TF3MP_ROLE holds the mode from alut_proxy.ini.
 * v9: a line that arrives while TF3MP_IN holds none is offered at once
 * (checked every TAIL_INTERVAL_MS), not only on the next bridge tick.
 * Results go to alut_proxy.log. Built without the C runtime (see build.bat),
 * so only kernel32 functions and hand-written string helpers are used.
 */
#include "proxy.h"

#define TAIL_INTERVAL_MS 100
#define READ_CHUNK 8192
/* A captured build line plus the game's log prefix. */
#define LINE_MAX_LEN (NET_BRIDGE_CHUNK + 256)

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
static char state_key[NET_STATE_KEY_MAX];
static char state_text[NET_STATE_MAX];
static char own_logged[NET_STATE_KEYS][NET_STATE_KEY_MAX];
/* Whether TF3MP_IN holds a received line, and the last bridge tick number (v9). */
static int offering;
static unsigned long last_seq;
static unsigned long world_serial;
static int legacy_world_seen;
static char world_id[64], acknowledged_world[64];
static char upload[NET_LINE_MAX], upload_id[64];
static int upload_part, upload_count, upload_length, pending_line;
static HANDLE spool = INVALID_HANDLE_VALUE;
static LARGE_INTEGER spool_read, spool_write;
static char spool_text[NET_LINE_MAX];

/* Overflow captures go to disk, in order. Keep reading stdout so result/control messages can
 * drain BOTH peers' queues even when both games built more than 128 things while offline. */
static int queue_line(const char *text)
{
	DWORD length = (DWORD)lstrlenA(text), written;
	if (spool_read.QuadPart == spool_write.QuadPart && net_send_line(text)) return 1;
	if (spool == INVALID_HANDLE_VALUE) return 0;
	SetFilePointerEx(spool, spool_write, NULL, FILE_BEGIN);
	if (!WriteFile(spool, &length, sizeof(length), &written, NULL) || written != sizeof(length)) return 0;
	if (!WriteFile(spool, text, length, &written, NULL) || written != length) return 0;
	spool_write.QuadPart += sizeof(length) + length;
	FlushFileBuffers(spool);
	proxy_log("bridge: queue backpressure, capture retained on disk (%lu bytes)", length);
	return 1;
}

static void drain_spool(void)
{
	DWORD length, got;
	if (spool == INVALID_HANDLE_VALUE || spool_read.QuadPart >= spool_write.QuadPart) return;
	SetFilePointerEx(spool, spool_read, NULL, FILE_BEGIN);
	if (!ReadFile(spool, &length, sizeof(length), &got, NULL) || got != sizeof(length) || length >= NET_LINE_MAX) return;
	if (!ReadFile(spool, spool_text, length, &got, NULL) || got != length) return;
	spool_text[length] = 0;
	if (net_send_line(spool_text)) {
		spool_read.QuadPart += sizeof(length) + length;
		if (spool_read.QuadPart == spool_write.QuadPart) {
			spool_read.QuadPart = spool_write.QuadPart = 0;
			SetFilePointerEx(spool, spool_write, NULL, FILE_BEGIN); SetEndOfFile(spool);
			proxy_log("bridge: disk backlog drained");
		}
	}
}

/* Without the "[mp_probe]" tag, in case debugPrint separates its arguments. */
static const char MARKER[] = "bridge out seq=";
static const char SEND_MARKER[] = "net send ";
static const char RECEIVED_MARKER[] = "net received token=";
static const char STATE_MARKER[] = "net state ";

static int starts_with(const char *text, const char *prefix)
{
	while (*prefix) if (*text++ != *prefix++) return 0;
	return 1;
}

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

/* Sets TF3MP_<prefix><KEY> to value ("" removes it); returns 1 on success. */
static int set_state_env(const char *prefix, const char *key, const char *value)
{
	char name[64];
	int n;

	if (!putenv_s)
		return 0;
	n = wsprintfA(name, "TF3MP_%s", prefix);
	for (; *key && n < (int)sizeof(name) - 1; key++)
		name[n++] = (*key >= 'a' && *key <= 'z') ? (char)(*key - 'a' + 'A') : *key;
	name[n] = 0;
	return putenv_s(name, value) == 0;
}

/* A state line of the mod: "<key> <text>" after the marker. */
static void handle_state(const char *rest)
{
	int n = 0, i, first = 1, ok;

	while (rest[n] >= 'a' && rest[n] <= 'z' && n < 8)
		n++;
	if (n == 0 || rest[n] != ' ')
		return;
	/* lstrcpynA instead of a copy loop: MSVC turns the loop into memcpy (no C runtime here). */
	lstrcpynA(state_key, rest, n + 1);
	rest += n + 1;
	if (lstrlenA(rest) >= NET_STATE_MAX) {
		proxy_log("bridge: state %s longer than %d characters, not sent", state_key, NET_STATE_MAX - 1);
		return;
	}
	ok = net_set_state(state_key, rest);
	set_state_env("OWN_", state_key, rest);
	/* Every second or so; the log only notes the first of each key. */
	for (i = 0; i < NET_STATE_KEYS; i++) {
		if (lstrcmpA(own_logged[i], state_key) == 0)
			first = 0;
	}
	for (i = 0; first && i < NET_STATE_KEYS; i++) {
		if (!own_logged[i][0]) {
			lstrcpynA(own_logged[i], state_key, NET_STATE_KEY_MAX);
			break;
		}
	}
	if (first)
		proxy_log("bridge: first state %s of the mod%s: %.120s", state_key, ok ? "" : " (NO ROOM)", rest);
}

/* Puts the peer's changed states into the environment. */
static void refresh_peer_states(void)
{
	char order[192];
	while (net_take_peer_state(state_key, state_text)) {
		if (!set_state_env("PEER_", state_key, state_text))
			proxy_log("bridge: TF3MP_PEER_%s could not be set", state_key);
		else if (!state_text[0])
			proxy_log("bridge: state %s of the peer cleared", state_key);
	}
	net_order_value(order, sizeof(order));
	set_state_env("", "ORDER", order);
}

/* Offers the oldest received line to the mod, or acknowledges the tick. */
static void refresh_env(unsigned long seq)
{
	char order[192];
	if (seq)
		last_seq = seq;
	offering = net_inbox_value(env_value, sizeof(env_value));
	if (!offering)
		wsprintfA(env_value, "ack %lu", last_seq);
	net_order_value(order, sizeof(order));
	set_state_env("", "ORDER", order);
	set_env(env_value);
	/* The entry remains in the inbox while the game executes it. */
	if (net_inbox_count()) offering = 1;
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

/* v13 in-game resync: the old lines in the disk backlog and this game's states are void. */
static void resync_loaded(void)
{
	int i;
	set_state_env("", "RELOAD", "");
	set_state_env("", "SAVE", "");
	for (i = 0; i < NET_STATE_KEYS; i++)
		if (own_logged[i][0]) set_state_env("OWN_", own_logged[i], "");
	if (spool != INVALID_HANDLE_VALUE) {
		spool_read.QuadPart = spool_write.QuadPart = 0;
		SetFilePointerEx(spool, spool_write, NULL, FILE_BEGIN); SetEndOfFile(spool);
	}
	offering = 0;
	refresh_env(0);
}

/* v13: requests of the launcher next to the DLL. alut_proxy.save asks the host's game to save the
 * resync save (TF3MP_SAVE=<n>); alut_proxy.reload ("name=<save>") asks the game to load that save
 * while it runs (TF3MP_RELOAD=<epoch> <save>). Each file is taken once and deleted. */
static int take_request(const char *file, char *text, int size)
{
	char path[MAX_PATH]; HANDLE h; DWORD got = 0;
	if (!proxy_file_next_to_dll(path, file)) return 0;
	h = CreateFileA(path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_DELETE, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
	if (h == INVALID_HANDLE_VALUE) return 0;
	if (!ReadFile(h, text, size - 1, &got, NULL)) got = 0;
	CloseHandle(h);
	text[got] = 0;
	DeleteFileA(path);
	return 1;
}

static void poll_requests(void)
{
	static unsigned long saves, polls;
	char text[400], value[320], number[16];
	const char *p;
	int n, epoch;

	/* About once a second. */
	if (++polls % 10) return;
	if (take_request("alut_proxy.save", text, sizeof(text))) {
		wsprintfA(number, "%lu", ++saves);
		set_state_env("", "SAVE", number);
		proxy_log("bridge: launcher asks this game to save for the resync (%s)", number);
	}
	if (!take_request("alut_proxy.reload", text, sizeof(text)))
		return;
	p = find(text, "name=");
	if (!p) { proxy_log("bridge: alut_proxy.reload without name="); return; }
	p += 5;
	for (n = 0; p[n] && p[n] != '\r' && p[n] != '\n' && n < 259; n++)
		value[n] = p[n];
	value[n] = 0;
	epoch = net_arm_resync(value);
	if (!epoch) return;
	wsprintfA(text, "%d %s", epoch, value);
	set_state_env("", "RELOAD", text);
	proxy_log("bridge: TF3MP_RELOAD=%s", text);
}

static int handle_line(void)
{
	const char *hit, *p, *command;
	char token[64], result[16];
	unsigned long seq = 0;
	int n = 0;

	line_buf[line_len] = 0;
	/* The source filename is emitted by the game before the mod initializes its world.
	 * Ignore mod-tagged lines here: a diagnostic or captured text is never a load notice. */
	if (!line_cut && !find(line_buf, "[mp_probe]")) {
		hit = find(line_buf, "Loading game from file ");
		if (hit) {
			set_state_env("", "AUTOLOAD", "");
			if (net_world_loading(hit + 23)) resync_loaded();
			wsprintfA(world_id, "%lu-%lu-%lu", GetCurrentProcessId(), GetTickCount(), ++world_serial);
			acknowledged_world[0] = 0;
			legacy_world_seen = 0;
			set_state_env("", "WORLD_ACK", ""); set_state_env("", "WORLD", world_id);
			return 1;
		}
	}
	command = find(line_buf, "[mp_probe]");
	if (!command) return 1;
	command += 10;
	while (*command == ' ' || *command == '\t') command++;
	if (starts_with(command, "autoload failed:")) {
		proxy_log("launcher: %.800s", command);
		return 1;
	}
	if (starts_with(command, "net initialized ")) {
		if (world_id[0] && !lstrcmpA(command + 16, world_id)) {
			net_game_initialized(); lstrcpyA(acknowledged_world, world_id);
			set_state_env("", "WORLD_ACK", world_id);
		}
		return 1;
	}
	if (starts_with(command, "net reload")) {
		/* The current world may already have acknowledged itself on its first update. */
		if (!legacy_world_seen && world_id[0] && !lstrcmpA(world_id, acknowledged_world)) { legacy_world_seen = 1; return 1; }
		legacy_world_seen = 1;
		if (net_game_reload() && spool != INVALID_HANDLE_VALUE) {
			spool_read.QuadPart = spool_write.QuadPart = 0;
			SetFilePointerEx(spool, spool_write, NULL, FILE_BEGIN); SetEndOfFile(spool);
		}
		if (world_id[0]) { lstrcpyA(acknowledged_world, world_id); set_state_env("", "WORLD_ACK", world_id); }
		refresh_env(0); return 1;
	}
	hit = starts_with(command, "net upload ") ? command : NULL;
	if (hit && !line_cut) {
		int index, count, used = 0, length;
		p = hit + 11;
		while (*p && *p != ' ' && used < 63) token[used++] = *p++;
		token[used] = 0;
		if (*p++ != ' ') return 1;
		index = count = 0;
		while (*p >= '0' && *p <= '9') index = index * 10 + *p++ - '0';
		if (*p++ != ' ') return 1;
		while (*p >= '0' && *p <= '9') count = count * 10 + *p++ - '0';
		if (*p++ != ' ' || count < 1 || count > 44 || index >= count) return 1;
		length = lstrlenA(p);
		if (lstrcmpA(upload_id, token)) {
			if (index != 0) return 1;
			lstrcpyA(upload_id, token); upload_part = upload_length = 0; upload_count = count;
		}
		if (count != upload_count || index > upload_part || length > NET_BRIDGE_CHUNK) return 1;
		if (index == upload_part) {
			if (upload_length + length >= NET_LINE_MAX) { proxy_log("bridge: upload too large"); return 1; }
			lstrcpyA(upload + upload_length, p); upload_length += length; upload_part++;
		}
		if (upload_part == upload_count) {
			if (!queue_line(upload)) return 0;
			upload_id[0] = 0;
		}
		return 1;
	}
	hit = starts_with(command, "net partreceived ") ? command : NULL;
	if (hit) {
		p = hit + 17;
		while (*p && *p != ' ' && n < 63) token[n++] = *p++;
		token[n] = 0; seq = 0;
		if (*p == ' ') p++;
		while (*p >= '0' && *p <= '9') seq = seq * 10 + *p++ - '0';
		if (net_inbox_part_ack(token, (int)seq)) refresh_env(0);
		return 1;
	}
	hit = starts_with(command, "net result ") ? command : NULL;
	if (hit) {
		p = hit + 11;
		while (*p && *p != ' ' && n < 63) token[n++] = *p++;
		token[n] = 0; if (*p == ' ') p++;
		n = 0; while (*p && *p != ' ' && n < 15) result[n++] = *p++;
		result[n] = 0;
		if (net_inbox_result(token, result)) refresh_env(0);
		return 1;
	}
	hit = starts_with(command, SEND_MARKER) ? command : NULL;
	if (hit) {
		if (line_cut)
			proxy_log("bridge: captured line longer than %d characters, not sent", LINE_MAX_LEN - 1);
		else
			return queue_line(hit + sizeof(SEND_MARKER) - 1);
		return 1;
	}
	hit = starts_with(command, STATE_MARKER) ? command : NULL;
	if (hit) {
		if (!line_cut)
			handle_state(hit + sizeof(STATE_MARKER) - 1);
		return 1;
	}
	hit = starts_with(command, RECEIVED_MARKER) ? command : NULL;
	if (hit) {
		for (p = hit + sizeof(RECEIVED_MARKER) - 1; *p && *p != ' ' && n < (int)sizeof(token) - 1; p++)
			token[n++] = *p;
		token[n] = 0;
		if (net_inbox_ack(token)) {
			proxy_log("bridge: the mod has line %s", token);
			/* Offer the next line right away instead of on the next tick. */
			refresh_env(0);
		}
		return 1;
	}
	hit = starts_with(command, MARKER) ? command : NULL;
	if (!hit)
		return 1;
	for (p = hit + sizeof(MARKER) - 1; *p >= '0' && *p <= '9'; p++)
		seq = seq * 10 + (unsigned long)(*p - '0');
	refresh_env(seq);
	return 1;
}

static DWORD WINAPI bridge_thread(LPVOID arg)
{
	LARGE_INTEGER offset, size;
	HANDLE file;
	DWORD got, i;
	int first = 1;

	(void)arg;
	{
		char path[MAX_PATH], backup[MAX_PATH], name[48]; WIN32_FILE_ATTRIBUTE_DATA attr; int create = 1;
		if (proxy_file_next_to_dll(path, "alut_proxy.queue")) {
			if (GetFileAttributesExA(path, GetFileExInfoStandard, &attr) && (attr.nFileSizeLow || attr.nFileSizeHigh)) {
				wsprintfA(name,"alut_pending_%lu.bin",GetTickCount());
				proxy_file_next_to_dll(backup,name);
				create = MoveFileA(path,backup);
				proxy_log("bridge: old disk backlog %s; restart requires a shared save",create ? "retained as a recovery file" : "could not be moved; not overwritten");
			}
			if (create) spool = CreateFileA(path, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
		}
	}
	putenv_s = (putenv_s_fn)GetProcAddress(GetModuleHandleA("ucrtbase.dll"), "_putenv_s");
	proxy_log("bridge: ucrtbase _putenv_s %s", putenv_s ? "found" : "NOT found");
	{
		char launch[1441];
		launch[0] = 0;
		if (GetEnvironmentVariableA("TF3MP_AUTOLOAD", launch, sizeof(launch)) >= sizeof(launch)) launch[0] = 0;
		/* Lua's os.getenv uses the CRT environment, which can already have been cached. */
		set_state_env("", "AUTOLOAD", launch);
	}
	set_env("hello");
	set_state_env("", "ROLE", net_mode_name());
	set_state_env("", "WORLD", ""); set_state_env("", "WORLD_ACK", "");
	set_state_env("", "ORDERING", net_ordering_enabled() ? "1" : "0");
	proxy_log("bridge: TF3MP_ROLE=%s", net_mode_name());

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
		poll_requests();
		refresh_peer_states();
		drain_spool();
		{
			char status[1280], path[MAX_PATH]; HANDLE status_file; DWORD written;
			net_status(status, sizeof(status) - 64);
			wsprintfA(status + lstrlenA(status), "backlog=%lu\r\n", (unsigned long)(spool_write.QuadPart - spool_read.QuadPart));
			if (proxy_file_next_to_dll(path, "alut_proxy.status")) {
				status_file = CreateFileA(path, GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
				if (status_file != INVALID_HANDLE_VALUE) { WriteFile(status_file, status, lstrlenA(status), &written, NULL); CloseHandle(status_file); }
			}
		}
		if (pending_line) {
			if (!handle_line()) continue;
			pending_line = line_len = line_cut = 0;
			proxy_log("bridge: queue available, continuing stdout without dropping actions");
		}
		/* v9: a line that arrived while none was offered goes to the mod right away; the mod looks
		 * every 10 updates, no longer only on the bridge tick every 50. */
		if (!offering && net_inbox_count() > 0)
			refresh_env(0);
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
						if (!handle_line()) {
							pending_line = 1;
							offset.QuadPart -= got - i - 1;
							proxy_log("bridge: queue full, holding stdout position (backpressure)");
							break;
						}
						line_len = 0;
						line_cut = 0;
					} else if (c != '\r') {
						if (line_len < LINE_MAX_LEN - 1)
							line_buf[line_len++] = c;
						else
							line_cut = 1;
					}
				}
				if (pending_line) break;
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
