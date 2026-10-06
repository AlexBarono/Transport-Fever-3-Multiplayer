#ifndef PROXY_H
#define PROXY_H

#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <stdarg.h>

#define PROXY_VERSION "6"

/* Appends one timestamped line to alut_proxy.log next to the DLL. */
void proxy_log(const char *fmt, ...);

/* Writes the full path of a file next to the DLL into out (MAX_PATH chars). */
int proxy_file_next_to_dll(char *out, const char *name);

/* UDP peer link (net.c). Both are safe to call from DllMain. */
void net_start(void);
void net_stop(void);

/* Lua <-> DLL bridge test through stdout.txt and the environment (bridge.c). */
void bridge_start(void);
void bridge_stop(void);

#endif
