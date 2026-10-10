#ifndef PROXY_H
#define PROXY_H

#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <stdarg.h>

#define PROXY_VERSION "15"

/* Longest build line the DLL passes between the games, in characters. */
#define NET_LINE_MAX 262145
#define NET_BRIDGE_CHUNK 6000

/* State texts (v8): the latest text per key, sent to the peer every second, nothing queued. */
#define NET_STATE_MAX 1024
#define NET_STATE_KEYS 8
#define NET_STATE_KEY_MAX 12

/* Appends one timestamped line to alut_proxy.log next to the DLL. */
void proxy_log(const char *fmt, ...);

/* Writes the full path of a file next to the DLL into out (MAX_PATH chars). */
int proxy_file_next_to_dll(char *out, const char *name);

/* UDP peer link (net.c). net_start and net_stop are safe to call from DllMain. */
enum { NET_OFF, NET_HOST, NET_CLIENT, NET_LOOPBACK };
void net_start(void);
void net_stop(void);
int net_mode(void);
/* "off", "host", "client" or "loopback". */
const char *net_mode_name(void);
/* Queues a captured build line for the other game, or for this one with mode=loopback. */
int net_send_line(const char *text);
/* Writes one "part <token> <kind> <index> <count> <text>" (up to NET_BRIDGE_CHUNK bytes). */
int net_inbox_value(char *out, int size);
/* Receipt only: holds this entry until net_inbox_result reports execution. */
int net_inbox_ack(const char *token);
int net_inbox_part_ack(const char *token, int part);
int net_inbox_result(const char *token, const char *result);
void net_status(char *out, int size);
/* Host-ordered remote replay permit; empty for explicit protocol-2 local tests. */
void net_order_value(char *out, int size);
int net_ordering_enabled(void);
int net_game_reload(void);
void net_game_initialized(void);
/* Original game load log, before Lua reports its first world initialization. Returns the new
 * resync epoch if this load is the armed in-game resync (v13), else 0. */
int net_world_loading(const char *name);
/* v13: the next load of the save called name is an in-game resync; returns its epoch, 0 if refused. */
int net_arm_resync(const char *name);
/* Received messages not yet executed by the game. */
int net_inbox_count(void);
/* Keeps text as this game's latest state under key for the peer; 0 if there is no room for the key. */
int net_set_state(const char *key, const char *text);
/* Takes the next peer state that changed since the last call: key and text ("" once the peer went
 * silent). Returns 0 if none changed. */
int net_take_peer_state(char *key, char *text);

/* Lua <-> DLL bridge test through stdout.txt and the environment (bridge.c). */
void bridge_start(void);
void bridge_stop(void);

#endif
