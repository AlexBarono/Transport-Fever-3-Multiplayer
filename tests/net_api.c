/* Test-only DLL API: exercise the real network and bridge code without loading TF3. */
#include "../native/alut_proxy/proxy.h"
#include "../native/alut_proxy/bridge.c"
int proxy_file_next_to_dll(char *out, const char *name) {
    HMODULE module; char *slash;
    GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
        (LPCSTR)proxy_file_next_to_dll, &module);
    GetModuleFileNameA(module, out, MAX_PATH);
    slash = out + lstrlenA(out); while (slash > out && *slash != '\\') slash--;
    wsprintfA(slash, "\\%s", name); return 1;
}
void proxy_log(const char *fmt, ...) { (void)fmt; }
__declspec(dllexport) void mp_start(void) {
    char path[MAX_PATH]; net_start();
    proxy_file_next_to_dll(path,"test.queue");
    spool = CreateFileA(path,GENERIC_READ|GENERIC_WRITE,FILE_SHARE_READ,NULL,CREATE_ALWAYS,FILE_ATTRIBUTE_NORMAL,NULL);
}
__declspec(dllexport) int mp_send(const char *text) { return queue_line(text); }
__declspec(dllexport) int mp_feed(const char *text) {
    line_len = lstrlenA(text)+10; if (line_len >= LINE_MAX_LEN) return 0;
    lstrcpyA(line_buf,"[mp_probe]"); lstrcpyA(line_buf+10,text); return handle_line();
}
__declspec(dllexport) int mp_log(const char *text) {
    line_len = lstrlenA(text); if (line_len >= LINE_MAX_LEN) return 0;
    lstrcpyA(line_buf, text); return handle_line();
}
__declspec(dllexport) void mp_pump(void) { drain_spool(); }
__declspec(dllexport) long long mp_spooled(void) { return spool_write.QuadPart-spool_read.QuadPart; }
__declspec(dllexport) int mp_inbox(char *out) { return net_inbox_value(out,NET_LINE_MAX+64); }
__declspec(dllexport) int mp_part(const char *token,int index) { return net_inbox_part_ack(token,index); }
__declspec(dllexport) int mp_result(const char *token,const char *result) { return net_inbox_result(token,result); }
__declspec(dllexport) void mp_status(char *out) { net_status(out,1024); }
__declspec(dllexport) void mp_stop(void) { net_stop(); }
