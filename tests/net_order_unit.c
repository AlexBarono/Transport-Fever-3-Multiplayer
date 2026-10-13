/* Isolated tests of the production UDP state machine. No threads, sockets or game files. */
#include "../native/alut_proxy/proxy.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static char wire[512], warning[1024];
static int sends, warnings;
static int WSAAPI capture_sendto(SOCKET s, const char *buf, int len, int flags,
    const struct sockaddr *to, int tolen) {
    (void)s; (void)flags; (void)to; (void)tolen;
    if (len >= (int)sizeof(wire)) abort();
    memcpy(wire, buf, len); wire[len] = 0; sends++; return len;
}
#define sendto capture_sendto
#include "../native/alut_proxy/net.c"
#undef sendto
void proxy_log(const char *fmt, ...) {
    va_list args;
    if (!starts_with(fmt, "net: order stalled")) return;
    va_start(args, fmt); wvsprintfA(warning, fmt, args); va_end(args); warnings++;
}
int proxy_file_next_to_dll(char *out, const char *name) { (void)out; (void)name; return 0; }
static int checks;
#define CHECK(expr) do { checks++; if (!(expr)) { fprintf(stderr, "line %d: %s\n", __LINE__, #expr); exit(1); } } while (0)
static struct sockaddr_in address;
static void clean(void) {
    while (outbox.count) queue_pop(&outbox);
    while (inbox.count) queue_pop(&inbox);
    ZeroMemory(&outbox, sizeof(outbox)); ZeroMemory(&inbox, sizeof(inbox));
    ZeroMemory(history, sizeof(history)); ZeroMemory(own_states, sizeof(own_states));
    ZeroMemory(peer_states, sizeof(peer_states)); history_next = 0;
    mode = NET_CLIENT; local_test = game_blocked = compatibility_failed = session_changed = 0;
    order_seq = released_seq = client_want_serial = client_done_serial = active_client_serial = 0;
    order_side = released_side = 0; order_phase = ORDER_IDLE;
    order_token[0] = released_token[0] = assembly_token[0] = error_text[0] = 0;
    order_started_at = order_progress_at = order_warned_at = 0;
    assembly_part = assembly_count = assembly_length = 0;
    world_ready = peer_ready = 1; sends = warnings = 0; wire[0] = warning[0] = 0;
}
static void push(struct queue *q, const char *token, const char *text) {
    CHECK(queue_push(q, token, "net", text));
}
static void control(const char *kind, const char *rest) {
    receive_order_control(INVALID_SOCKET, &address, kind, rest);
}
/* Assert bytes and identity as well as count: stale packets must not consume the next entry. */
static void queued(struct queue *q, int count, const char *head) {
    int i, bytes = 0;
    CHECK(q->count == count);
    for (i = 0; i < q->count; i++) bytes += q->items[(q->head + i) % QUEUE_SIZE].length;
    CHECK(q->bytes == bytes);
    CHECK(count ? !strcmp(queue_head(q)->token, head) : queue_head(q) == NULL);
}
static void active(unsigned long seq, int side, const char *token) {
    CHECK(order_seq == seq); CHECK(order_side == side); CHECK(order_phase == ORDER_ACTIVE);
    CHECK(!strcmp(order_token, token));
}
static void test_counts_and_status(void) {
    char status[NET_STATUS_MAX], token[64], longwork[320], fields[97], health[256];
    struct { char before[16]; char text[NET_STATUS_MAX]; char after[16]; } bounded;
    int a, d, i;
    clean();
    /* Force ring wrap rather than only testing a queue with head zero. */
    for (i = 0; i < QUEUE_SIZE - 2; i++) { push(&outbox, "unused", "A1 x"); queue_pop(&outbox); }
    push(&outbox, "action", "B5 x"); push(&outbox, "world", "W2 x");
    push(&outbox, "info", "I1 x"); push(&outbox, "sync", "S1 x");
    push(&inbox, "legacy-world", "W1 x"); push(&inbox, "vehicle", "A1 x");
    queue_counts(&outbox, &a, &d); CHECK(a == 2 && d == 2);
    queue_counts(&inbox, &a, &d); CHECK(a == 1 && d == 1);
    net_status(status, sizeof(status));
    CHECK(strstr(status, "version=16\r\n") != NULL);
    CHECK(strstr(status, "outbox_actions=2\r\noutbox_diagnostics=2\r\n") != NULL);
    CHECK(strstr(status, "inbox_actions=1\r\ninbox_diagnostics=1\r\n") != NULL);
    CHECK(strstr(status, "outbox_oldest_token=action\r\n") != NULL);
    CHECK(strstr(status, "inbox_oldest_token=legacy-world\r\n") != NULL);
    CHECK(strstr(status, "order_age_ms=0\r\n") != NULL);
    CHECK(strstr(status, "order_stage=idle\r\n") != NULL);
    CHECK(strstr(status, "work_token=-\r\n") != NULL);
    CHECK(strstr(status, "peer_work_pending=-\r\n") != NULL);
    /* Work is the ninth key in a session that already uses the former eight slots. */
    for (i = 0; i < 8; i++) { wsprintfA(token, "key%d", i); CHECK(net_set_state(token, "value")); }
    CHECK(net_set_state("work", "token=action phase=commands pending=3"));
    receive_state("work token=vehicle phase=deferred pending=0");
    net_status(status, sizeof(status));
    CHECK(strstr(status, "work_token=action\r\nwork_phase=commands\r\nwork_pending=3\r\n") != NULL);
    CHECK(strstr(status, "peer_work_token=vehicle\r\npeer_work_phase=deferred\r\npeer_work_pending=0\r\n") != NULL);
    queue_pop(&outbox); queue_counts(&outbox, &a, &d); CHECK(a == 1 && d == 2);
    /* Worst bounded fields must preserve the complete final status field and sentinels. */
    memset(token, 't', sizeof(token) - 1); token[sizeof(token) - 1] = 0;
    wsprintfA(longwork, "token=%s phase=abcdefghijklmnopqrstuvwxyz0123456789 pending=12345678901234567890", token);
    CHECK(net_set_state("work", longwork)); receive_state(longwork); /* A separate key cannot change work. */
    lstrcpyA(state_slot(peer_states, "work", 0)->text, longwork);
    memset(fields, 'f', sizeof(fields) - 1); fields[sizeof(fields) - 1] = 0;
    wsprintfA(health, "status=abcdefghijklmno fields=%s ck=12345678901234567890123", fields);
    CHECK(net_set_state("health", health)); receive_state("health status=abcdefghijklmno");
    receive_state("resync req=12345678901234567890123");
    lstrcpyA(order_token, token); lstrcpyA(queue_head(&outbox)->token, token);
    lstrcpyA(queue_head(&inbox)->token, token);
    order_seq = 4294967295UL; order_phase = ORDER_ACTIVE; order_side = 'H';
    hello_sent = hello_received = 4294967295UL;
    memset(error_text, 'e', sizeof(error_text) - 1); error_text[sizeof(error_text) - 1] = 0;
    memset(&bounded, 'z', sizeof(bounded)); net_status(bounded.text, sizeof(bounded.text));
    CHECK(!memcmp(bounded.before, "zzzzzzzzzzzzzzzz", 16));
    CHECK(!memcmp(bounded.after, "zzzzzzzzzzzzzzzz", 16));
    CHECK(strstr(bounded.text, "peer_work_pending=123456789012345\r\n") != NULL);
    memset(&bounded, 'z', sizeof(bounded)); net_status(bounded.text, 32);
    CHECK(bounded.text[31] == 0 && bounded.text[32] == 'z');
}
static void test_client_ack_and_release(void) {
    DWORD progress;
    clean(); push(&outbox, "A", "B5 first"); push(&outbox, "B", "B5 second");
    control("ORDER", "1 C A"); active(1, 'C', "A"); CHECK(!strcmp(wire, "TF3MP/1 OACK 1 C A"));
    receive_ack("GOT", "A"); CHECK(queue_head(&outbox)->received == 1);
    order_progress_at = progress = 123; receive_ack("GOT", "A"); CHECK(order_progress_at == progress);
    receive_ack("GOT", "old"); receive_ack("DONE", "old OK"); receive_ack("PART", "old 0");
    receive_ack("RESET", "old"); receive_ack("DONE", "A INVALID");
    queued(&outbox, 2, "A"); active(1, 'C', "A"); CHECK(!game_blocked);
    receive_ack("DONE", "A OK"); queued(&outbox, 1, "B"); CHECK(order_phase == ORDER_DONE);
    receive_ack("DONE", "A OK"); receive_ack("GOT", "A"); receive_ack("DONE", "A FAIL"); receive_ack("RESET", "A");
    queued(&outbox, 1, "B"); CHECK(order_phase == ORDER_DONE && !game_blocked);
    control("RELEASE", "1 C A"); CHECK(order_phase == ORDER_IDLE); CHECK(!strcmp(wire, "TF3MP/1 RACK 1 C A"));
    control("RELEASE", "1 C A"); queued(&outbox, 1, "B"); CHECK(order_phase == ORDER_IDLE);
    control("ORDER", "2 C B"); active(2, 'C', "B");
    control("RELEASE", "1 C A"); active(2, 'C', "B"); CHECK(!strcmp(wire, "TF3MP/1 RACK 1 C A"));
    receive_ack("DONE", "A OK"); receive_ack("GOT", "A"); queued(&outbox, 1, "B"); active(2, 'C', "B");
}
static void test_lost_done_and_incoming_release(void) {
    int before;
    clean(); push(&outbox, "A", "B5 first"); push(&outbox, "B", "B5 second"); control("ORDER", "1 C A");
    before = sends;
    control("RELEASE", "2 C A"); control("RELEASE", "1 H A"); control("RELEASE", "1 C other");
    queued(&outbox, 2, "A"); active(1, 'C', "A"); CHECK(sends == before);
    /* Matching host release is the authoritative completion if the earlier DONE was lost. */
    control("RELEASE", "1 C A"); queued(&outbox, 1, "B"); CHECK(order_phase == ORDER_IDLE);
    control("RELEASE", "1 C A"); queued(&outbox, 1, "B");
    control("RELEASE", "2 C B"); queued(&outbox, 1, "B"); CHECK(order_phase == ORDER_IDLE);
    clean(); control("ORDER", "1 H A"); push(&inbox, "A", "B5 remote"); before = sends;
    control("RELEASE", "1 H A"); active(1, 'H', "A"); queued(&inbox, 1, "A"); CHECK(sends == before);
    CHECK(net_inbox_result("A", "OK")); CHECK(order_phase == ORDER_DONE); queued(&inbox, 0, "");
    control("RELEASE", "1 H A"); CHECK(order_phase == ORDER_IDLE); CHECK(!strcmp(wire, "TF3MP/1 RACK 1 H A"));
    control("RELEASE", "1 H A"); CHECK(order_phase == ORDER_IDLE);
}
static void test_host_controls(void) {
    clean(); mode = NET_HOST; push(&outbox, "A", "B5 first"); push(&outbox, "B", "B5 second");
    pump_order(INVALID_SOCKET, &address, 1000); CHECK(order_phase == ORDER_ACK && order_seq == 1);
    CHECK(!strcmp(wire, "TF3MP/1 ORDER 1 H A"));
    control("OACK", "2 H A"); control("OACK", "1 C A"); control("OACK", "1 H other");
    control("RACK", "1 H A"); CHECK(order_phase == ORDER_ACK); queued(&outbox, 2, "A");
    control("OACK", "1 H A"); active(1, 'H', "A");
    control("RACK", "1 H A"); active(1, 'H', "A");
    receive_ack("DONE", "A OK"); CHECK(order_phase == ORDER_FINISH); queued(&outbox, 1, "B");
    control("RACK", "2 H A"); control("RACK", "1 C A"); control("RACK", "1 H other"); CHECK(order_phase == ORDER_FINISH);
    control("RACK", "1 H A"); CHECK(order_phase == ORDER_IDLE);
    pump_order(INVALID_SOCKET, &address, 2000); CHECK(order_phase == ORDER_ACK && order_seq == 2);
    control("RACK", "1 H A"); CHECK(order_phase == ORDER_ACK && order_seq == 2); queued(&outbox, 1, "B");
}
static void test_duplicate_receipts_and_results(void) {
    char value[NET_BRIDGE_CHUNK + 128]; DWORD before;
    clean(); control("ORDER", "1 H A"); receive_line(INVALID_SOCKET, &address, "A B5 remote");
    queued(&inbox, 1, "A"); CHECK(!strcmp(wire, "TF3MP/1 GOT A"));
    before = order_progress_at = 456;
    receive_line(INVALID_SOCKET, &address, "A B5 remote"); CHECK(order_progress_at == before); queued(&inbox, 1, "A");
    CHECK(net_inbox_value(value, sizeof(value))); CHECK(net_inbox_part_ack("A", 0));
    CHECK(!net_inbox_part_ack("A", 0)); before = order_progress_at = 789;
    CHECK(net_inbox_ack("A")); CHECK(order_progress_at == before);
    CHECK(net_inbox_result("A", "OK")); CHECK(!net_inbox_result("A", "OK"));
    CHECK(answer_known(INVALID_SOCKET, &address, "A")); CHECK(!strcmp(wire, "TF3MP/1 DONE A OK"));
    queued(&inbox, 0, ""); CHECK(!answer_known(INVALID_SOCKET, &address, "unknown"));
    clean(); push(&inbox, "failed", "B5 rejected"); CHECK(net_inbox_result("failed", "FAIL"));
    CHECK(answer_known(INVALID_SOCKET, &address, "failed")); CHECK(!strcmp(wire, "TF3MP/1 DONE failed FAIL"));
    queued(&inbox, 0, "");
}
static void test_stall_warning_and_stages(void) {
    char status[NET_STATUS_MAX];
    clean(); push(&outbox, "A", "B5 first"); control("ORDER", "1 C A");
    order_started_at = order_progress_at = order_warned_at = 1000;
    CHECK(!strcmp(order_stage_locked(), "sending_payload"));
    order_warn(30999); CHECK(warnings == 0);
    order_warn(31000); CHECK(warnings == 1); CHECK(strstr(warning, "seq=1 token=A phase=active stage=sending_payload") != NULL);
    CHECK(strstr(warning, "age_ms=30000 progress_age_ms=30000") != NULL);
    queued(&outbox, 1, "A"); active(1, 'C', "A"); CHECK(!game_blocked);
    order_warn(60999); CHECK(warnings == 1); order_warn(61000); CHECK(warnings == 2);
    /* Callback progress raced ahead of pump_order's captured time: no unsigned underflow warning. */
    order_progress_at = 62001; order_warn(62000); CHECK(warnings == 2);
    receive_ack("GOT", "A"); CHECK(!strcmp(order_stage_locked(), "waiting_peer_execution"));
    order_progress_at = 62000; order_warn(91999); CHECK(warnings == 2);
    receive_ack("GOT", "A"); CHECK(order_progress_at == 62000);
    order_warn(92000); CHECK(warnings == 3); CHECK(strstr(warning, "outbox_received=1") != NULL);
    net_status(status, sizeof(status)); CHECK(strstr(status, "order_stage=waiting_peer_execution\r\n") != NULL);
    CHECK(strstr(status, "order_outbox_received=1\r\n") != NULL);
    receive_ack("DONE", "A OK"); CHECK(!strcmp(order_stage_locked(), "waiting_release"));
    order_warn(122000); CHECK(warnings == 3);
    clean(); control("ORDER", "1 H A"); CHECK(!strcmp(order_stage_locked(), "waiting_payload"));
    receive_line(INVALID_SOCKET, &address, "A B5 remote"); CHECK(!strcmp(order_stage_locked(), "delivering_to_game"));
    CHECK(net_inbox_ack("A")); CHECK(!strcmp(order_stage_locked(), "waiting_game_result"));
    CHECK(net_inbox_result("A", "OK")); CHECK(!strcmp(order_stage_locked(), "waiting_release"));
    control("RELEASE", "1 H A"); CHECK(!strcmp(order_stage_locked(), "idle"));
    clean(); push(&outbox, "A", "B5 first"); control("ORDER", "1 C A");
    /* GetTickCount wrap must still yield an ordinary 30-second wait. */
    order_started_at = order_progress_at = order_warned_at = 0xfffffff0UL;
    order_warn(29983); CHECK(warnings == 0);
    order_warn(29984); CHECK(warnings == 1); CHECK(strstr(warning, "progress_age_ms=30000") != NULL);
}
int main(void) {
    InitializeCriticalSection(&lock);
    test_counts_and_status(); test_client_ack_and_release(); test_lost_done_and_incoming_release();
    test_host_controls(); test_duplicate_receipts_and_results(); test_stall_warning_and_stages();
    clean(); DeleteCriticalSection(&lock);
    printf("Native isolated order/diagnostic tests passed: %d checks\n", checks); return 0;
}
