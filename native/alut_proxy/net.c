/*
 * UDP peer link between two game instances (phase 1, step 2).
 *
 * Configured by alut_proxy.ini next to the DLL:
 *
 *   [net]
 *   mode=host          ; off (default), host or client
 *   port=47800         ; UDP port the host listens on
 *   host=192.168.1.10  ; client only: address of the host
 *
 * Both sides send a HELLO datagram every 2 seconds. The host answers to the
 * address it last heard from. Everything that happens is written to
 * alut_proxy.log: start, first packet from the peer, every 30th packet after
 * that, and when the peer goes quiet for 10 seconds.
 *
 * There is no game data yet; this only proves two instances can talk.
 */
#include "proxy.h"

#define HELLO_INTERVAL_MS 2000
#define PEER_TIMEOUT_MS 10000

static volatile LONG stopping;
static HANDLE thread;

static char mode[16];
static char host_addr[64];
static int port;

static void read_config(void)
{
	char ini[MAX_PATH];

	mode[0] = 0;
	if (!proxy_file_next_to_dll(ini, "alut_proxy.ini"))
		return;
	GetPrivateProfileStringA("net", "mode", "off", mode, sizeof(mode), ini);
	GetPrivateProfileStringA("net", "host", "", host_addr, sizeof(host_addr), ini);
	port = (int)GetPrivateProfileIntA("net", "port", 47800, ini);
}

static void addr_to_text(const struct sockaddr_in *a, char *out, int size)
{
	char ip[32];

	if (!InetNtopA(AF_INET, (void *)&a->sin_addr, ip, sizeof(ip)))
		lstrcpyA(ip, "?");
	wsprintfA(out, "%s:%d", ip, ntohs(a->sin_port));
	(void)size;
}

static DWORD WINAPI net_thread(LPVOID arg)
{
	int is_host = lstrcmpiA(mode, "host") == 0;
	WSADATA wsa;
	SOCKET s;
	struct sockaddr_in local, peer, from;
	int have_peer = 0, connected = 0, fromlen;
	DWORD timeout = 500, last_send = 0, last_recv = 0, now;
	unsigned long sent = 0, received = 0;
	char buf[512], peer_text[64];
	int n;

	(void)arg;
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
			n = wsprintfA(buf, "TF3MP/1 HELLO %s pid=%lu seq=%lu", is_host ? "host" : "client", GetCurrentProcessId(), sent);
			sendto(s, buf, n, 0, (struct sockaddr *)&peer, sizeof(peer));
			sent++;
			last_send = now;
		}

		fromlen = sizeof(from);
		n = recvfrom(s, buf, sizeof(buf) - 1, 0, (struct sockaddr *)&from, &fromlen);
		now = GetTickCount();
		if (n > 0) {
			buf[n] = 0;
			if (n < 8 || buf[0] != 'T' || buf[1] != 'F' || buf[2] != '3' || buf[3] != 'M' || buf[4] != 'P')
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
				proxy_log("net: connected to %s: %s", peer_text, buf);
			} else if (received % 30 == 0) {
				proxy_log("net: %lu packets received, %lu sent, last: %s", received, sent, buf);
			}
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
	read_config();
	if (lstrcmpiA(mode, "host") != 0 && lstrcmpiA(mode, "client") != 0) {
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
