#ifndef PROXY_H
#define PROXY_H

#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <stdarg.h>

#define PROXY_VERSION "7"

/* Longest build line the DLL passes between the games, in characters. */
#define NET_LINE_MAX 16384

/* Appends one timestamped line to alut_proxy.log next to the DLL. */
void proxy_log(const char *fmt, ...);

/* Writes the full path of a file next to the DLL into out (MAX_PATH chars). */
int proxy_file_next_to_dll(char *out, const char *name);

/* UDP peer link (net.c). net_start and net_stop are safe to call from DllMain. */
enum { NET_OFF, NET_HOST, NET_CLIENT, NET_LOOPBACK };
void net_start(void);
void net_stop(void);
int net_mode(void);
/* Queues a captured build line for the other game, or for this one with mode=loopback. */
void net_send_line(const char *text);
/* Writes "line <token> <kind> <text>" for the oldest received line into out; 0 if there is none. */
int net_inbox_value(char *out, int size);
/* Drops the oldest received line if it has this token; 1 if it did. */
int net_inbox_ack(const char *token);

/* Lua <-> DLL bridge test through stdout.txt and the environment (bridge.c). */
void bridge_start(void);
void bridge_stop(void);

#endif
