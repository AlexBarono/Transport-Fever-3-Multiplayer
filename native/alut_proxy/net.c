/*
 * UDP peer link between two game instances (phase 1, steps 2 and 4).
 *
 * Configured by alut_proxy.ini next to the DLL:
 *
 *   [net]
 *   mode=host          ; off (default), host, client or loopback
 *   port=47800         ; UDP port the host listens on
 *   host=192.168.1.10  ; client only: address of the host
 *
 * Both sides send a HELLO datagram every 2 seconds. The host answers to the
 * address it last heard from. Everything that happens is written to
 * alut_proxy.log: start, first packet from the peer, every 30th packet after
 * that, and when the peer goes quiet for 10 seconds.
 *
 * Build lines: bridge.c hands every line the mod captured to net_send_line.
 * It goes out as "TF3MP/1 LINE <token> <text>" and is sent again every second
 * until the peer answers "TF3MP/1 GOT <token>", one line at a time. Received
 * lines wait in the inbox until the mod confirms them (net_inbox_ack). With
 * mode=loopback nothing goes over the network: captured lines go straight
 * into this game's own inbox, which tests the whole chain on one PC.
 */
#include "proxy.h"

#define HELLO_INTERVAL_MS 2000
#define PEER_TIMEOUT_MS 10000
#define RESEND_MS 1000
#define QUEUE_SIZE 8
#define TOKEN_MAX 32

struct entry {
	char token[TOKEN_MAX];
	char kind[8];
	char text[NET_LINE_MAX];
};

/* Ring buffer; entries are never copied as a whole (no C runtime for memcpy). */
struct queue {
	struct entry items[QUEUE_SIZE];
	int head, count;
};

static volatile LONG stopping;
static HANDLE thread;

static char mode_text[16];
static int mode = NET_OFF;
static char host_addr[64];
static int port;

static CRITICAL_SECTION lock;
static struct queue inbox, outbox;
static unsigned long next_line;
static char packet[NET_LINE_MAX + 64];

static void read_config(void)
{
	char ini[MAX_PATH];

	lstrcpyA(mode_text, "off");
	if (!proxy_file_next_to_dll(ini, "alut_proxy.ini"))
		return;
	GetPrivateProfileStringA("net", "mode", "off", mode_text, sizeof(mode_text), ini);
	GetPrivateProfileStringA("net", "host", "", host_addr, sizeof(host_addr), ini);
	port = (int)GetPrivateProfileIntA("net", "port", 47800, ini);
	if (lstrcmpiA(mode_text, "host") == 0)
		mode = NET_HOST;
	else if (lstrcmpiA(mode_text, "client") == 0)
		mode = NET_CLIENT;
	else if (lstrcmpiA(mode_text, "loopback") == 0)
		mode = NET_LOOPBACK;
}

static int queue_push(struct queue *q, const char *token, const char *kind, const char *text)
{
	struct entry *e;

	if (q->count == QUEUE_SIZE)
		return 0;
	e = &q->items[(q->head + q->count) % QUEUE_SIZE];
	lstrcpynA(e->token, token, TOKEN_MAX);
	lstrcpynA(e->kind, kind, sizeof(e->kind));
	lstrcpynA(e->text, text, NET_LINE_MAX);
	q->count++;
	return 1;
}

static struct entry *queue_head(struct queue *q)
{
	return q->count ? &q->items[q->head] : NULL;
}

static void queue_pop(struct queue *q)
{
	if (!q->count)
		return;
	q->head = (q->head + 1) % QUEUE_SIZE;
	q->count--;
}

/* Appends text to out without going past size; returns the new length. */
static int append(char *out, int len, int size, const char *text)
{
	while (*text && len < size - 1)
		out[len++] = *text++;
	out[len] = 0;
	return len;
}

/* Copies the word at text (up to a space or the end) into out; returns the rest after one space. */
static const char *take_word(const char *text, char *out, int size)
{
	int n = 0;

	while (*text && *text != ' ') {
		if (n < size - 1)
			out[n++] = *text;
		text++;
	}
	out[n] = 0;
	return *text == ' ' ? text + 1 : text;
}

static int starts_with(const char *text, const char *prefix)
{
	while (*prefix)
		if (*text++ != *prefix++)
			return 0;
	return 1;
}

int net_mode(void)
{
	return mode;
}

void net_send_line(const char *text)
{
	char token[TOKEN_MAX];
	int ok, length = lstrlenA(text);

	if (mode == NET_OFF) {
		proxy_log("net: captured line not sent, mode=off");
		return;
	}
	if (length >= NET_LINE_MAX) {
		proxy_log("net: captured line too long (%d characters), not sent", length);
		return;
	}
	EnterCriticalSection(&lock);
	/* The process id tells lines of different game sessions apart, so the mod's memory of the last
	 * token (kept in the savegame) never swallows a line after a restart. */
	wsprintfA(token, "%lu.%lu", GetCurrentProcessId(), ++next_line);
	if (mode == NET_LOOPBACK)
		ok = queue_push(&inbox, token, "loop", text);
	else
		ok = queue_push(&outbox, token, "net", text);
	LeaveCriticalSection(&lock);
	proxy_log("net: line %s (%d characters) %s", token, length,
		!ok ? "DROPPED, queue full" : mode == NET_LOOPBACK ? "queued for this game (loopback)" : "queued for the peer");
}

int net_inbox_value(char *out, int size)
{
	struct entry *e;
	int len = 0;

	EnterCriticalSection(&lock);
	e = queue_head(&inbox);
	if (e) {
		len = append(out, 0, size, "line ");
		len = append(out, len, size, e->token);
		len = append(out, len, size, " ");
		len = append(out, len, size, e->kind);
		len = append(out, len, size, " ");
		len = append(out, len, size, e->text);
	}
	LeaveCriticalSection(&lock);
	return e != NULL;
}

int net_inbox_ack(const char *token)
{
	struct entry *e;
	int done = 0;

	EnterCriticalSection(&lock);
	e = queue_head(&inbox);
	if (e && lstrcmpA(e->token, token) == 0) {
		queue_pop(&inbox);
		done = 1;
	}
	LeaveCriticalSection(&lock);
	return done;
}

static void addr_to_text(const struct sockaddr_in *a, char *out, int size)
{
	char ip[32];

	if (!InetNtopA(AF_INET, (void *)&a->sin_addr, ip, sizeof(ip)))
		lstrcpyA(ip, "?");
	wsprintfA(out, "%s:%d", ip, ntohs(a->sin_port));
	(void)size;
}

/* A LINE datagram from the peer: confirm it and keep it for the mod, once. */
static void receive_line(SOCKET s, const struct sockaddr_in *from, const char *rest, char *last_token)
{
	char token[TOKEN_MAX], reply[TOKEN_MAX + 16];
	const char *text = take_word(rest, token, sizeof(token));
	int ok = 1, n;

	if (!token[0] || !*text)
		return;
	if (lstrcmpA(token, last_token) != 0) {
		EnterCriticalSection(&lock);
		ok = queue_push(&inbox, token, "net", text);
		LeaveCriticalSection(&lock);
		if (!ok) {
			/* No GOT, so the peer sends it again later. */
			proxy_log("net: line %s from the peer dropped, inbox full", token);
			return;
		}
		lstrcpynA(last_token, token, TOKEN_MAX);
		proxy_log("net: line %s received from the peer (%d characters)", token, lstrlenA(text));
	}
	n = wsprintfA(reply, "TF3MP/1 GOT %s", token);
	sendto(s, reply, n, 0, (const struct sockaddr *)from, sizeof(*from));
}

/* A GOT datagram: the peer has the line at the head of the outbox. */
static void receive_got(const char *rest)
{
	char token[TOKEN_MAX];
	struct entry *e;
	int done = 0;

	take_word(rest, token, sizeof(token));
	EnterCriticalSection(&lock);
	e = queue_head(&outbox);
	if (e && lstrcmpA(e->token, token) == 0) {
		queue_pop(&outbox);
		done = 1;
	}
	LeaveCriticalSection(&lock);
	if (done)
		proxy_log("net: line %s delivered to the peer", token);
}

/* Sends the head of the outbox, again every RESEND_MS until the peer confirms it. */
static void send_pending(SOCKET s, const struct sockaddr_in *peer, DWORD now, DWORD *last_send,
	char *sending, unsigned long *attempts)
{
	struct entry *e;
	int len = 0;

	EnterCriticalSection(&lock);
	e = queue_head(&outbox);
	if (e && (lstrcmpA(e->token, sending) != 0 || now - *last_send >= RESEND_MS)) {
		if (lstrcmpA(e->token, sending) != 0) {
			lstrcpynA(sending, e->token, TOKEN_MAX);
			*attempts = 0;
		}
		len = append(packet, 0, sizeof(packet), "TF3MP/1 LINE ");
		len = append(packet, len, sizeof(packet), e->token);
		len = append(packet, len, sizeof(packet), " ");
		len = append(packet, len, sizeof(packet), e->text);
	}
	LeaveCriticalSection(&lock);
	if (!len)
		return;
	sendto(s, packet, len, 0, (const struct sockaddr *)peer, sizeof(*peer));
	*last_send = now;
	if (*attempts == 0)
		proxy_log("net: line %s sent to the peer (%d bytes)", sending, len);
	else if (*attempts % 10 == 0)
		proxy_log("net: line %s sent again (%lu tries, no answer yet)", sending, *attempts + 1);
	(*attempts)++;
}

static DWORD WINAPI net_thread(LPVOID arg)
{
	int is_host = mode == NET_HOST;
	WSADATA wsa;
	SOCKET s;
	struct sockaddr_in local, peer, from;
	int have_peer = 0, connected = 0, fromlen;
	DWORD timeout = 200, last_send = 0, last_recv = 0, last_line = 0, now;
	unsigned long sent = 0, received = 0, attempts = 0;
	char hello[128], peer_text[64], last_token[TOKEN_MAX], sending[TOKEN_MAX];
	int n;

	(void)arg;
	last_token[0] = 0;
	sending[0] = 0;
	if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) {
		proxy_log("net: WSAStartup failed");
		return 1;
	}
	s = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
	if (s == INVALID_SOCKET) {
		proxy_log("net: socket failed (%d)", WSAGetLastError());
		WSACleanup();
		return 1;
	}
	setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, (const char *)&timeout, sizeof(timeout));

	SecureZeroMemory(&local, sizeof(local));
	local.sin_family = AF_INET;
	local.sin_addr.s_addr = htonl(INADDR_ANY);
	local.sin_port = htons((u_short)(is_host ? port : 0));
	if (bind(s, (struct sockaddr *)&local, sizeof(local)) != 0) {
		proxy_log("net: bind to port %d failed (%d)", is_host ? port : 0, WSAGetLastError());
		closesocket(s);
		WSACleanup();
		return 1;
	}

	SecureZeroMemory(&peer, sizeof(peer));
	if (is_host) {
		proxy_log("net: host listening on UDP port %d", port);
	} else {
		peer.sin_family = AF_INET;
		peer.sin_port = htons((u_short)port);
		if (InetPtonA(AF_INET, host_addr, &peer.sin_addr) != 1) {
			proxy_log("net: invalid host address '%s'", host_addr);
			closesocket(s);
			WSACleanup();
			return 1;
		}
		have_peer = 1;
		proxy_log("net: client sending to %s:%d", host_addr, port);
	}

	while (!stopping) {
		now = GetTickCount();
		if (have_peer && now - last_send >= HELLO_INTERVAL_MS) {
			n = wsprintfA(hello, "TF3MP/1 HELLO %s pid=%lu seq=%lu", is_host ? "host" : "client", GetCurrentProcessId(), sent);
			sendto(s, hello, n, 0, (struct sockaddr *)&peer, sizeof(peer));
			sent++;
			last_send = now;
		}
		if (have_peer)
			send_pending(s, &peer, now, &last_line, sending, &attempts);

		fromlen = sizeof(from);
		n = recvfrom(s, packet, sizeof(packet) - 1, 0, (struct sockaddr *)&from, &fromlen);
		now = GetTickCount();
		if (n > 0) {
			packet[n] = 0;
			if (n < 8 || !starts_with(packet, "TF3MP/1 "))
				continue;
			if (is_host) {
				peer = from;
				have_peer = 1;
			}
			received++;
			last_recv = now;
			if (!connected) {
				connected = 1;
				addr_to_text(&from, peer_text, sizeof(peer_text));
				proxy_log("net: connected to %s: %.100s", peer_text, packet);
			} else if (received % 30 == 0) {
				proxy_log("net: %lu packets received, %lu sent, last: %.100s", received, sent, packet);
			}
			if (starts_with(packet, "TF3MP/1 LINE "))
				receive_line(s, &from, packet + 13, last_token);
			else if (starts_with(packet, "TF3MP/1 GOT "))
				receive_got(packet + 12);
		}
		if (connected && now - last_recv > PEER_TIMEOUT_MS) {
			connected = 0;
			proxy_log("net: peer silent for %d s, waiting", PEER_TIMEOUT_MS / 1000);
		}
	}

	proxy_log("net: stopped (%lu sent, %lu received)", sent, received);
	closesocket(s);
	WSACleanup();
	return 0;
}

void net_start(void)
{
	InitializeCriticalSection(&lock);
	read_config();
	if (mode == NET_LOOPBACK) {
		proxy_log("net: loopback, captured lines come back to this game");
		return;
	}
	if (mode == NET_OFF) {
		proxy_log("net: off (no alut_proxy.ini or mode=off)");
		return;
	}
	/* The thread only starts running after the loader lock is released. */
	thread = CreateThread(NULL, 0, net_thread, NULL, 0, NULL);
	if (!thread)
		proxy_log("net: CreateThread failed (%lu)", GetLastError());
}

void net_stop(void)
{
	/* Do not wait for the thread here: DllMain holds the loader lock, and at
	 * process exit the thread is already gone. */
	InterlockedExchange(&stopping, 1);
}
