/* v11: prepared-session compatibility and loaded-world gates before any gameplay traffic.
 * GOT means queued; only DONE OK releases the sender. A failure stops the queue for review.
 * Queues survive network interruptions within this process. Never replay after a game restart
 * without loading the same save on both PCs. No runtime imports: kernel32/Winsock only. */
#include "proxy.h"
#define QUEUE_SIZE 128
#define QUEUE_BYTES (16 * 1024 * 1024)
#define TOKEN_MAX 64
#define FRAGMENT 768
#define RESEND_MS 500
#define HELLO_INTERVAL_MS 2000
#define PEER_TIMEOUT_MS 10000
#define STATE_RESEND_MS 1000
struct entry { char token[TOKEN_MAX]; char kind[8]; char *text; int length, part, received, failed; };
struct queue { struct entry items[QUEUE_SIZE]; int head, count, bytes; };
struct state_slot { char key[NET_STATE_KEY_MAX]; char text[NET_STATE_MAX]; int changed; DWORD sent_at; unsigned long count; };
struct completed { char token[TOKEN_MAX]; char result[8]; };
static struct completed history[QUEUE_SIZE];
static int history_next;
static volatile LONG stopping;
static HANDLE thread;
static CRITICAL_SECTION lock;
static struct queue inbox, outbox;
static struct state_slot own_states[NET_STATE_KEYS], peer_states[NET_STATE_KEYS];
static char mode_text[16], host_addr[64], error_text[128];
static int mode = NET_OFF, port, link_connected, peer_protocol, session_changed, game_blocked;
static char peer_session[64];
static int same_spot_test, local_test, protocol = 3, prepared, peer_compatible, compatibility_failed;
static int world_loaded, world_initialized, world_ready, peer_ready;
static char prepared_id[66], game_hash[66], package_hash[66], mods_hash[66], save_hash[66];
static char expected_save[1025];
static unsigned long next_line;
static DWORD session_nonce;
static char packet[NET_LINE_MAX + 128], state_packet[NET_STATE_MAX + NET_STATE_KEY_MAX + 32];
static char assembling[NET_LINE_MAX], assembly_token[TOKEN_MAX];
static int assembly_part, assembly_count, assembly_length;
static void clear_peer_states(void);
static int append(char *out, int len, int size, const char *text) {
    while (*text && len < size - 1) out[len++] = *text++;
    out[len] = 0; return len;
}
static const char *take_word(const char *text, char *out, int size) {
    int n = 0;
    while (*text && *text != ' ') { if (n < size - 1) out[n++] = *text; text++; }
    out[n] = 0; return *text ? text + 1 : text;
}
static int starts_with(const char *text, const char *prefix) {
    while (*prefix) if (*text++ != *prefix++) return 0;
    return 1;
}
static int number(const char *text) {
    int n = 0;
    if (!*text) return -1;
    while (*text) { if (*text < '0' || *text > '9' || n > 1000000) return -1; n = n * 10 + *text++ - '0'; }
    return n;
}
static int hex_digit(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}
static int hex_length(const char *text, int length) {
    int i;
    if (lstrlenA(text) != length) return 0;
    for (i = 0; i < length; i++) if (hex_digit(text[i]) < 0) return 0;
    return 1;
}
static int decode_save_name(const char *hex) {
    int n = lstrlenA(hex), i, a, b;
    if (!n || n % 2 || n / 2 >= (int)sizeof(expected_save)) return 0;
    for (i = 0; i < n / 2; i++) {
        a = hex_digit(hex[i * 2]); b = hex_digit(hex[i * 2 + 1]);
        if (a < 0 || b < 0 || !(a * 16 + b)) return 0;
        expected_save[i] = (char)(a * 16 + b);
    }
    expected_save[n / 2] = 0; return 1;
}
static void fail_compatibility(const char *reason) {
    EnterCriticalSection(&lock);
    if (compatibility_failed) { LeaveCriticalSection(&lock); return; }
    lstrcpynA(error_text, reason, sizeof(error_text));
    compatibility_failed = 1; peer_compatible = 0; link_connected = 0;
    LeaveCriticalSection(&lock);
    clear_peer_states();
    proxy_log("net: session blocked: %s", reason);
}
static struct entry *queue_head(struct queue *q) { return q->count ? &q->items[q->head] : NULL; }
static int queue_push(struct queue *q, const char *token, const char *kind, const char *text) {
    struct entry *e;
    int length = lstrlenA(text);
    if (!length || length >= NET_LINE_MAX || q->count == QUEUE_SIZE || q->bytes + length > QUEUE_BYTES) return 0;
    e = &q->items[(q->head + q->count) % QUEUE_SIZE];
    e->text = HeapAlloc(GetProcessHeap(), 0, length + 1);
    if (!e->text) return 0;
    lstrcpyA(e->text, text); lstrcpynA(e->token, token, TOKEN_MAX); lstrcpynA(e->kind, kind, 8);
    e->length = length; e->part = e->received = e->failed = 0;
    q->bytes += length; q->count++; return 1;
}
static void queue_pop(struct queue *q) {
    struct entry *e = queue_head(q);
    if (!e) return;
    q->bytes -= e->length; HeapFree(GetProcessHeap(), 0, e->text); e->text = NULL;
    q->head = (q->head + 1) % QUEUE_SIZE; q->count--;
}
static void read_config(void) {
    char ini[MAX_PATH], test[32], name_hex[2051];
    if (!proxy_file_next_to_dll(ini, "alut_proxy.ini")) return;
    GetPrivateProfileStringA("net", "mode", "off", mode_text, sizeof(mode_text), ini);
    GetPrivateProfileStringA("net", "host", "", host_addr, sizeof(host_addr), ini);
    port = GetPrivateProfileIntA("net", "port", 47800, ini);
    GetPrivateProfileStringA("net", "test", "", test, sizeof(test), ini);
    same_spot_test = !lstrcmpA(test,"samespot");
    if (lstrcmpiA(mode_text, "host") == 0) mode = NET_HOST;
    else if (lstrcmpiA(mode_text, "client") == 0) mode = NET_CLIENT;
    else if (lstrcmpiA(mode_text, "loopback") == 0) mode = NET_LOOPBACK;
    local_test = mode == NET_LOOPBACK || same_spot_test || !lstrcmpA(test, "fakehost");
    protocol = local_test ? 2 : 3;
    if (mode == NET_OFF || local_test) { world_ready = 1; return; }
    GetPrivateProfileStringA("session", "id", "", prepared_id, sizeof(prepared_id), ini);
    GetPrivateProfileStringA("session", "game", "", game_hash, sizeof(game_hash), ini);
    GetPrivateProfileStringA("session", "package", "", package_hash, sizeof(package_hash), ini);
    GetPrivateProfileStringA("session", "mods", "", mods_hash, sizeof(mods_hash), ini);
    GetPrivateProfileStringA("session", "save", "", save_hash, sizeof(save_hash), ini);
    GetPrivateProfileStringA("session", "name", "", name_hex, sizeof(name_hex), ini);
    prepared = (hex_length(prepared_id, 32) || hex_length(prepared_id, 64)) &&
        hex_length(game_hash, 64) && hex_length(package_hash, 64) && hex_length(mods_hash, 64) &&
        hex_length(save_hash, 64) && decode_save_name(name_hex);
    if (!prepared) fail_compatibility("session not prepared; transfer the shared save before starting both games");
}
int net_mode(void) { return mode; }
const char *net_mode_name(void) {
    return mode == NET_HOST ? "host" : mode == NET_CLIENT ? "client" : mode == NET_LOOPBACK ? "loopback" : "off";
}
/* The slot for key, or a free one for it if create is set; NULL if there is none. Call under lock. */
static struct state_slot *state_slot(struct state_slot *slots, const char *key, int create)
{
	int i;

	for (i = 0; i < NET_STATE_KEYS; i++)
		if (slots[i].key[0] && lstrcmpA(slots[i].key, key) == 0)
			return &slots[i];
	if (!create)
		return NULL;
	for (i = 0; i < NET_STATE_KEYS; i++) {
		if (!slots[i].key[0]) {
			lstrcpynA(slots[i].key, key, NET_STATE_KEY_MAX);
			slots[i].text[0] = 0;
			return &slots[i];
		}
	}
	return NULL;
}

int net_set_state(const char *key, const char *text)
{
	struct state_slot *slot;

	EnterCriticalSection(&lock);
	slot = state_slot(own_states, key, 1);
	if (slot && lstrcmpA(slot->text, text) != 0) {
		lstrcpynA(slot->text, text, NET_STATE_MAX);
		slot->changed = 1;
	}
	LeaveCriticalSection(&lock);
	return slot != NULL;
}

int net_take_peer_state(char *key, char *text)
{
	int i, found = 0;

	EnterCriticalSection(&lock);
	for (i = 0; i < NET_STATE_KEYS && !found; i++) {
		if (peer_states[i].key[0] && peer_states[i].changed) {
			lstrcpynA(key, peer_states[i].key, NET_STATE_KEY_MAX);
			lstrcpynA(text, peer_states[i].text, NET_STATE_MAX);
			peer_states[i].changed = 0;
			found = 1;
		}
	}
	LeaveCriticalSection(&lock);
	return found;
}

/* A STATE datagram: the peer's latest text for a key. */
static void receive_state(const char *rest)
{
	char key[NET_STATE_KEY_MAX];
	const char *text = take_word(rest, key, sizeof(key));
	struct state_slot *slot;
	unsigned long count = 0;
	int changed = 0;

	if (!key[0] || lstrlenA(text) >= NET_STATE_MAX)
		return;
	EnterCriticalSection(&lock);
	slot = state_slot(peer_states, key, 1);
	if (slot) {
		count = ++slot->count;
		if (lstrcmpA(slot->text, text) != 0) {
			lstrcpynA(slot->text, text, NET_STATE_MAX);
			slot->changed = 1;
			changed = 1;
		}
	}
	LeaveCriticalSection(&lock);
	if (!slot)
		proxy_log("net: no room for state '%s' from the peer", key);
	else if (count == 1 || (changed && count % 100 == 0))
		proxy_log("net: state %s from the peer (%lu so far): %.120s", key, count, text);
}

/* The peer went silent: its states no longer hold. */
static void clear_peer_states(void)
{
	int i;

	EnterCriticalSection(&lock);
	for (i = 0; i < NET_STATE_KEYS; i++) {
		if (peer_states[i].key[0] && peer_states[i].text[0]) {
			peer_states[i].text[0] = 0;
			peer_states[i].changed = 1;
		}
	}
	LeaveCriticalSection(&lock);
}

/* Sends every state that changed, and each again every STATE_RESEND_MS. */
static void send_states(SOCKET s, const struct sockaddr_in *peer, DWORD now)
{
	int i, len;

	for (i = 0; i < NET_STATE_KEYS; i++) {
		len = 0;
		EnterCriticalSection(&lock);
		if (own_states[i].key[0] && own_states[i].text[0] &&
		    (own_states[i].changed || now - own_states[i].sent_at >= STATE_RESEND_MS)) {
			len = append(state_packet, 0, sizeof(state_packet), "TF3MP/1 STATE ");
			len = append(state_packet, len, sizeof(state_packet), own_states[i].key);
			len = append(state_packet, len, sizeof(state_packet), " ");
			len = append(state_packet, len, sizeof(state_packet), own_states[i].text);
			own_states[i].changed = 0;
			own_states[i].sent_at = now;
		}
		LeaveCriticalSection(&lock);
		if (len)
			sendto(s, state_packet, len, 0, (const struct sockaddr *)peer, sizeof(*peer));
	}
}


int net_send_line(const char *text) {
    char token[TOKEN_MAX]; int ok;
    if (mode == NET_OFF) return 1;
    if (lstrlenA(text) >= NET_LINE_MAX) {
        if (!compatibility_failed) lstrcpyA(error_text, "message exceeds 256 KiB"); return 1;
    }
    EnterCriticalSection(&lock);
    wsprintfA(token, "%lu-%lu.%lu", GetCurrentProcessId(), session_nonce, next_line + 1);
    ok = queue_push(mode == NET_LOOPBACK ? &inbox : &outbox, token, mode == NET_LOOPBACK ? "loop" : "net", text);
    if (ok) next_line++;
    LeaveCriticalSection(&lock);
    if (ok) proxy_log("net: line %s queued (%d bytes)", token, lstrlenA(text));
    return ok; /* 0 = backpressure: bridge must keep and retry this log line. */
}
int net_inbox_value(char *out, int size) {
    struct entry *e; int len = 0, offset, count;
    EnterCriticalSection(&lock); e = queue_head(&inbox);
    if (e && !e->received && !compatibility_failed && !session_changed &&
        (local_test || (world_ready && peer_ready))) {
        count = (e->length + NET_BRIDGE_CHUNK - 1) / NET_BRIDGE_CHUNK;
        offset = e->part * NET_BRIDGE_CHUNK;
        len = wsprintfA(out, "part %s %s %d %d ", e->token, e->kind, e->part, count);
        lstrcpynA(out + len, e->text + offset, size - len < NET_BRIDGE_CHUNK + 1 ? size - len : NET_BRIDGE_CHUNK + 1);
        len += lstrlenA(out + len);
    }
    LeaveCriticalSection(&lock); return len != 0;
}
int net_inbox_count(void) { int n; EnterCriticalSection(&lock); n = inbox.count; LeaveCriticalSection(&lock); return n; }
int net_inbox_part_ack(const char *token, int part) {
    struct entry *e; int ok = 0;
    EnterCriticalSection(&lock); e = queue_head(&inbox);
    if (e && lstrcmpA(token, e->token) == 0 && e->part == part && !e->received) {
        e->part++; if (e->part * NET_BRIDGE_CHUNK >= e->length) e->received = 1; ok = 1;
    }
    LeaveCriticalSection(&lock); return ok;
}
int net_inbox_ack(const char *token) {
    struct entry *e; int ok = 0;
    EnterCriticalSection(&lock); e = queue_head(&inbox);
    if (e && lstrcmpA(token, e->token) == 0) { e->received = 1; ok = 1; }
    LeaveCriticalSection(&lock); return ok;
}
int net_inbox_result(const char *token, const char *result) {
    struct entry *e; int ok = 0;
    if (lstrcmpA(result, "OK") && lstrcmpA(result, "FAIL")) return 0;
    EnterCriticalSection(&lock); e = queue_head(&inbox);
    if (e && lstrcmpA(token, e->token) == 0) {
        lstrcpynA(history[history_next].token, token, TOKEN_MAX);
        lstrcpynA(history[history_next].result, result, 8);
        history_next = (history_next + 1) % QUEUE_SIZE;
        if (!lstrcmpA(result, "FAIL")) {
            game_blocked = 1;
            if (!compatibility_failed) wsprintfA(error_text, "game rejected %.64s", token);
        }
        queue_pop(&inbox); ok = 1;
    }
    LeaveCriticalSection(&lock);
    if (ok) proxy_log("net: game result %s %s", token, result);
    return ok;
}
static void state_field(const char *text, const char *key, char *out, int size, const char *fallback) {
    char word[NET_STATE_MAX], prefix[32]; int n;
    lstrcpynA(out, fallback, size); n = wsprintfA(prefix, "%s=", key);
    while (*text) {
        text = take_word(text, word, sizeof(word));
        if (starts_with(word, prefix)) { lstrcpynA(out, word + n, size); return; }
    }
}
void net_status(char *out, int size) {
    struct entry *e; struct state_slot *own, *peer;
    char text[1024], world[16], peer_world[16], fields[97], ck[24];
    EnterCriticalSection(&lock); e = queue_head(&outbox);
    own = state_slot(own_states, "health", 0); peer = state_slot(peer_states, "health", 0);
    state_field(own ? own->text : "", "status", world, sizeof(world), "unknown");
    state_field(peer ? peer->text : "", "status", peer_world, sizeof(peer_world), "unknown");
    state_field(own ? own->text : "", "fields", fields, sizeof(fields), "");
    state_field(own ? own->text : "", "ck", ck, sizeof(ck), "");
    wsprintfA(text, "pid=%lu\r\nversion=" PROXY_VERSION "\r\nmode=%s\r\nconnected=%d\r\noutbox=%d\r\ninbox=%d\r\nblocked=%d\r\nerror=%s\r\nprotocol=%d\r\nprepared=%d\r\ncompatible=%d\r\nready=%d\r\npeer_ready=%d\r\nworld=%s\r\nworld_peer=%s\r\nworld_fields=%s\r\nworld_ck=%s\r\n",
        GetCurrentProcessId(), net_mode_name(), link_connected, outbox.count, inbox.count,
        game_blocked || session_changed || compatibility_failed || (e ? e->failed : 0), error_text,
        protocol, prepared, peer_compatible, world_ready, peer_ready, world, peer_world, fields, ck);
    if (size > 0) lstrcpynA(out, text, size);
    LeaveCriticalSection(&lock);
}
void net_world_loading(const char *name) {
    int previous;
    if (local_test || mode == NET_OFF) return;
    EnterCriticalSection(&lock);
    previous = world_loaded || world_initialized; world_loaded = 1; world_ready = 0;
    LeaveCriticalSection(&lock);
    if (previous) fail_compatibility("save loaded again; prepare a new shared session and restart both games");
    else if (lstrcmpA(name, expected_save)) fail_compatibility("wrong save loaded; load the prepared shared save and restart both games");
    else proxy_log("net: expected source save loaded; waiting for world initialization");
}
int net_game_reload(void) {
    struct entry *e; char token[TOKEN_MAX]; int pending;
    if (!local_test && mode != NET_OFF) {
        if (world_initialized) fail_compatibility("save reloaded; prepare a new shared session and restart both games");
        else if (!world_loaded) fail_compatibility("source save load not observed; restart and load the prepared shared save");
        EnterCriticalSection(&lock); world_initialized = 1;
        world_ready = prepared && world_loaded && !compatibility_failed;
        LeaveCriticalSection(&lock);
        if (world_ready) proxy_log("net: prepared source world initialized; ready for matching peer");
    }
    EnterCriticalSection(&lock);
    /* This explicit local test replays the recording through same-spot.ps1 after reloading. */
    if (same_spot_test) while (outbox.count) queue_pop(&outbox);
    pending = inbox.count || outbox.count || (assembly_part > 0 && assembly_part < assembly_count);
    LeaveCriticalSection(&lock);
    if (!pending) return same_spot_test;
    for (;;) {
        EnterCriticalSection(&lock); e = queue_head(&inbox);
        if (e) lstrcpyA(token,e->token);
        LeaveCriticalSection(&lock);
        if (!e) break;
        net_inbox_result(token,"FAIL");
    }
    EnterCriticalSection(&lock); game_blocked = 1;
    if (!compatibility_failed) lstrcpyA(error_text,"save reloaded with pending actions; restart both games from same save");
    LeaveCriticalSection(&lock);
    proxy_log("net: save reloaded with pending actions; resync required");
    return same_spot_test;
}
static void reply(SOCKET s, const struct sockaddr_in *from, const char *kind, const char *token, const char *suffix) {
    char text[200]; int n = wsprintfA(text, "TF3MP/1 %s %s%s%s", kind, token, *suffix ? " " : "", suffix);
    sendto(s, text, n, 0, (const struct sockaddr *)from, sizeof(*from));
}
/* A completed token remains queryable after its inbox entry was released. */
static int answer_known(SOCKET s, const struct sockaddr_in *from, const char *token) {
    int i, found = 0; char result[8]; result[0] = 0;
    EnterCriticalSection(&lock);
    for (i = 0; i < QUEUE_SIZE; i++) if (!lstrcmpA(history[i].token, token)) { lstrcpyA(result, history[i].result); found = 1; break; }
    if (!found) for (i = 0; i < inbox.count; i++) {
        if (!lstrcmpA(inbox.items[(inbox.head + i) % QUEUE_SIZE].token, token)) { found = 1; break; }
    }
    LeaveCriticalSection(&lock);
    if (found) reply(s, from, *result ? "DONE" : "GOT", token, result);
    return found;
}
static void receive_fragment(SOCKET s, const struct sockaddr_in *from, const char *rest) {
    char token[TOKEN_MAX], idx[16], cnt[16]; const char *text;
    int index, count, n, ok;
    rest = take_word(rest, token, sizeof(token)); rest = take_word(rest, idx, sizeof(idx));
    text = take_word(rest, cnt, sizeof(cnt)); index = number(idx); count = number(cnt); n = lstrlenA(text);
    if (!*token || index < 0 || count <= 0 || index >= count || count > (NET_LINE_MAX - 2) / FRAGMENT + 1 ||
        n <= 0 || n > FRAGMENT || (index < count - 1 && n != FRAGMENT)) return;
    if (answer_known(s, from, token)) return;
    if (game_blocked) { reply(s, from, "DONE", token, "FAIL"); return; }
    if (lstrcmpA(assembly_token, token)) {
        if (index != 0) { reply(s, from, "RESET", token, ""); return; }
        lstrcpyA(assembly_token, token); assembly_part = assembly_length = 0; assembly_count = count;
    }
    if (assembly_count != count || index > assembly_part) return;
    if (index == assembly_part) {
        if (assembly_length + n >= NET_LINE_MAX) return;
        lstrcpyA(assembling + assembly_length, text); assembly_length += n; assembly_part++;
    }
    if (assembly_part == count) {
        EnterCriticalSection(&lock); ok = queue_push(&inbox, token, "net", assembling); LeaveCriticalSection(&lock);
        if (!ok) return; /* No final ACK: sender retries after backpressure clears. */
        proxy_log("net: line %s received from the peer (%d bytes, %d fragments)", token, assembly_length, count);
        reply(s, from, "GOT", token, ""); return;
    }
    reply(s, from, "PART", token, idx);
}
static void receive_line(SOCKET s, const struct sockaddr_in *from, const char *rest) {
    char token[TOKEN_MAX]; int ok; const char *text = take_word(rest, token, sizeof(token));
    if (!*token || !*text || lstrlenA(text) >= NET_LINE_MAX || answer_known(s, from, token)) return;
    if (game_blocked) { reply(s, from, "DONE", token, "FAIL"); return; }
    EnterCriticalSection(&lock); ok = queue_push(&inbox, token, "net", text); LeaveCriticalSection(&lock);
    if (ok) reply(s, from, "GOT", token, "");
}
static void receive_ack(const char *kind, const char *rest) {
    char token[TOKEN_MAX], value[16]; struct entry *e; int done = 0;
    rest = take_word(rest, token, sizeof(token)); take_word(rest, value, sizeof(value));
    EnterCriticalSection(&lock); e = queue_head(&outbox);
    if (e && !lstrcmpA(e->token, token)) {
        if (!lstrcmpA(kind, "PART") && number(value) == e->part) e->part++;
        else if (!lstrcmpA(kind, "RESET")) { e->part = 0; e->received = 0; }
        else if (!lstrcmpA(kind, "GOT")) e->received = 1;
        else if (!lstrcmpA(kind, "DONE")) {
            if (!lstrcmpA(value, "OK")) { queue_pop(&outbox); done = 1; }
            else if (!lstrcmpA(value, "FAIL") && !e->failed) {
                e->failed = 1; game_blocked = 1; wsprintfA(error_text, "peer rejected %.64s", token); done = -1;
            }
        }
    }
    LeaveCriticalSection(&lock);
    if (done) proxy_log("net: line %s %s", token, done > 0 ? "APPLIED by the peer" : "FAILED at peer; queue blocked, resync required");
}
static void send_pending(SOCKET s, const struct sockaddr_in *peer, DWORD now, DWORD *last_send, char *sending, int *last_part) {
    struct entry *e; int len = 0, part = -1, count;
    EnterCriticalSection(&lock); e = queue_head(&outbox);
    if (e && !e->failed && !game_blocked) {
        part = e->received ? -1 : e->part;
        if (lstrcmpA(sending, e->token) || *last_part != part || now - *last_send >= RESEND_MS) {
            lstrcpyA(sending, e->token); count = (e->length + FRAGMENT - 1) / FRAGMENT;
            if (e->received || e->part >= count) len = wsprintfA(packet, "TF3MP/1 CHECK %s", e->token);
            else {
                len = wsprintfA(packet, "TF3MP/1 FRAG %s %d %d ", e->token, e->part, count);
                lstrcpynA(packet + len, e->text + e->part * FRAGMENT, FRAGMENT + 1);
                len += lstrlenA(packet + len);
            }
        }
    }
    LeaveCriticalSection(&lock);
    if (len) { sendto(s, packet, len, 0, (const struct sockaddr *)peer, sizeof(*peer)); *last_send = now; *last_part = part; }
}
static int same_address(const struct sockaddr_in *a, const struct sockaddr_in *b) {
    return a->sin_addr.s_addr == b->sin_addr.s_addr && a->sin_port == b->sin_port;
}
/* Required fields occur exactly once and are validated before any queued payload or state. */
static int receive_hello(const char *rest) {
    char role[16], word[96], runtime[64], sid[66], game[66], package[66], mods[66], save[66];
    const char *scan, *end; int seen = 0, remote_protocol = 0, ready = -1, bit, invalid = 0;
    char *target; int size;
    runtime[0] = sid[0] = game[0] = package[0] = mods[0] = save[0] = 0;
    scan = take_word(rest, role, sizeof(role));
    while (*scan) {
        end = scan; while (*end && *end != ' ') end++;
        if (end - scan >= (int)sizeof(word)) { invalid = 1; break; }
        scan = take_word(scan, word, sizeof(word)); target = NULL; size = bit = 0;
        if (starts_with(word, "proto=")) { bit = 1; remote_protocol = number(word + 6); }
        else if (starts_with(word, "session=")) { bit = 2; target = runtime; size = sizeof(runtime); }
        else if (starts_with(word, "sid=")) { bit = 4; target = sid; size = sizeof(sid); }
        else if (starts_with(word, "game=")) { bit = 8; target = game; size = sizeof(game); }
        else if (starts_with(word, "package=")) { bit = 16; target = package; size = sizeof(package); }
        else if (starts_with(word, "mods=")) { bit = 32; target = mods; size = sizeof(mods); }
        else if (starts_with(word, "save=")) { bit = 64; target = save; size = sizeof(save); }
        else if (starts_with(word, "ready=")) { bit = 128; ready = number(word + 6); }
        if (bit && (seen & bit)) { invalid = 1; break; }
        seen |= bit;
        if (target) {
            end = word; while (*end && *end != '=') end++;
            if (!*end || lstrlenA(end + 1) >= size) { invalid = 1; break; }
            lstrcpynA(target, end + 1, size);
        }
    }
    if (invalid || *scan || remote_protocol != protocol) {
        if (local_test) lstrcpyA(error_text, "peer uses old protocol; update both PCs");
        else fail_compatibility("peer protocol mismatch; update both PCs and prepare a shared session");
        return 0;
    }
    if (!local_test) {
        if (compatibility_failed) return 0;
        if (seen != 255 || !*runtime || (ready != 0 && ready != 1) ||
            (lstrcmpA(role, mode == NET_HOST ? "client" : "host"))) {
            fail_compatibility("peer session metadata missing or invalid; prepare both PCs again"); return 0;
        }
        if (lstrcmpiA(sid, prepared_id)) { fail_compatibility("prepared session differs; transfer the shared save again"); return 0; }
        if (lstrcmpiA(game, game_hash)) { fail_compatibility("game build differs; update Transport Fever 3 on both PCs"); return 0; }
        if (lstrcmpiA(package, package_hash)) { fail_compatibility("multiplayer package differs; use the same release on both PCs"); return 0; }
        if (lstrcmpiA(mods, mods_hash)) { fail_compatibility("installed mods differ; use identical mods on both PCs"); return 0; }
        if (lstrcmpiA(save, save_hash)) { fail_compatibility("source save differs; transfer the shared save again"); return 0; }
    } else if (starts_with(error_text, "peer uses old protocol")) error_text[0] = 0;
    if (*runtime) {
        if (*peer_session && lstrcmpA(peer_session, runtime)) {
            session_changed = 1; peer_compatible = 0; link_connected = 0;
            lstrcpyA(error_text, "peer restarted; reload the same save on both PCs and restart"); return 0;
        }
        lstrcpyA(peer_session, runtime);
    }
    peer_protocol = remote_protocol; peer_compatible = 1; peer_ready = local_test || ready;
    return 1;
}
static DWORD WINAPI net_thread(LPVOID arg) {
    WSADATA wsa; SOCKET s; struct sockaddr_in local, peer, from;
    int is_host = mode == NET_HOST, have_peer = 0, fromlen, n, last_part = -2;
    DWORD timeout = 30, last_hello = 0, last_recv = 0, last_line = 0, now;
    char hello[768], sending[TOKEN_MAX], token[TOKEN_MAX], kind[16]; const char *rest;
    (void)arg; sending[0] = 0;
    if (WSAStartup(MAKEWORD(2,2), &wsa)) { lstrcpyA(error_text, "WSAStartup failed"); return 1; }
    s = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (s == INVALID_SOCKET) { lstrcpyA(error_text, "socket failed"); WSACleanup(); return 1; }
    setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, (const char *)&timeout, sizeof(timeout));
    SecureZeroMemory(&local, sizeof(local)); local.sin_family = AF_INET;
    local.sin_port = htons((u_short)(is_host ? port : 0));
    if (bind(s, (struct sockaddr *)&local, sizeof(local))) {
        wsprintfA(error_text, "UDP bind failed (%d)", WSAGetLastError()); proxy_log("net: %s", error_text);
        closesocket(s); WSACleanup(); return 1;
    }
    SecureZeroMemory(&peer, sizeof(peer)); peer.sin_family = AF_INET; peer.sin_port = htons((u_short)port);
    if (!is_host) {
        if (InetPtonA(AF_INET, host_addr, &peer.sin_addr) != 1) { lstrcpyA(error_text, "invalid IPv4 host"); closesocket(s); WSACleanup(); return 1; }
        have_peer = 1;
    }
    proxy_log("net: %s on UDP %d, protocol fragments+results v%d", is_host ? "host listening" : "client", port, protocol);
    while (!stopping) {
        now = GetTickCount();
        if (have_peer && now - last_hello >= HELLO_INTERVAL_MS) {
            if (local_test) n = wsprintfA(hello, "TF3MP/1 HELLO %s pid=%lu proto=2 session=%lu-%lu", is_host ? "host" : "client", GetCurrentProcessId(), GetCurrentProcessId(), session_nonce);
            else n = wsprintfA(hello, "TF3MP/1 HELLO %s pid=%lu proto=3 session=%lu-%lu sid=%s game=%s package=%s mods=%s save=%s ready=%d",
                is_host ? "host" : "client", GetCurrentProcessId(), GetCurrentProcessId(), session_nonce,
                prepared_id, game_hash, package_hash, mods_hash, save_hash, world_ready && !compatibility_failed);
            sendto(s, hello, n, 0, (struct sockaddr *)&peer, sizeof(peer)); last_hello = now;
        }
        if (have_peer && peer_protocol == protocol && peer_compatible && world_ready && peer_ready &&
            !session_changed && !compatibility_failed && now - last_recv <= PEER_TIMEOUT_MS) {
            send_pending(s, &peer, now, &last_line, sending, &last_part); send_states(s, &peer, now);
        }
        fromlen = sizeof(from); n = recvfrom(s, packet, sizeof(packet)-1, 0, (struct sockaddr *)&from, &fromlen);
        now = GetTickCount();
        if (n > 8) {
            packet[n] = 0; if (!starts_with(packet, "TF3MP/1 ")) continue;
            if (have_peer && !same_address(&peer, &from)) {
                /* A timed-out partner may reconnect with another source port, but another VPN IP cannot steal this session. */
                if (!is_host || link_connected || now - last_recv <= PEER_TIMEOUT_MS ||
                    peer.sin_addr.s_addr != from.sin_addr.s_addr) continue;
            }
            rest = take_word(packet + 8, kind, sizeof(kind));
            if (!have_peer && lstrcmpA(kind,"HELLO") &&
                (!local_test || (lstrcmpA(kind,"FRAG") && lstrcmpA(kind,"LINE")))) continue;
            if (is_host) { peer.sin_family=from.sin_family; peer.sin_port=from.sin_port; peer.sin_addr.s_addr=from.sin_addr.s_addr; have_peer=1; }
            if (!lstrcmpA(kind,"HELLO")) {
                if (!receive_hello(rest)) continue;
                last_recv = now;
                if (!world_ready || !peer_ready) { link_connected = 0; clear_peer_states(); continue; }
            } else if (local_test && (!lstrcmpA(kind,"FRAG") || !lstrcmpA(kind,"LINE"))) {
                peer_protocol = 2; peer_compatible = peer_ready = 1;
            }
            if (session_changed || compatibility_failed || !peer_compatible || !world_ready || !peer_ready) continue;
            last_recv = now;
            if (!link_connected) { link_connected=1; proxy_log("net: connected to partner, port %d", ntohs(from.sin_port)); }
            if (!lstrcmpA(kind,"FRAG")) receive_fragment(s,&from,rest);
            else if (!lstrcmpA(kind,"LINE")) receive_line(s,&from,rest);
            else if (!lstrcmpA(kind,"CHECK")) {
                take_word(rest,token,sizeof(token));
                if (!answer_known(s,&from,token)) reply(s,&from,"RESET",token,"");
            }
            else if (!lstrcmpA(kind,"PART") || !lstrcmpA(kind,"GOT") || !lstrcmpA(kind,"DONE") || !lstrcmpA(kind,"RESET")) receive_ack(kind,rest);
            else if (!lstrcmpA(kind,"STATE")) receive_state(rest);
        }
        if (peer_compatible && now - last_recv > PEER_TIMEOUT_MS) {
            link_connected=0; peer_compatible=0; peer_ready=0; clear_peer_states(); proxy_log("net: peer silent; queues retained for reconnect");
        }
    }
    closesocket(s); WSACleanup(); return 0;
}
void net_start(void) {
    InitializeCriticalSection(&lock); session_nonce = GetTickCount(); read_config();
    if (mode == NET_OFF || mode == NET_LOOPBACK) { proxy_log("net: %s", net_mode_name()); return; }
    if (compatibility_failed) return;
    thread=CreateThread(NULL,0,net_thread,NULL,0,NULL);
    if (!thread) lstrcpyA(error_text,"network thread failed");
}
void net_stop(void) { InterlockedExchange(&stopping,1); }
