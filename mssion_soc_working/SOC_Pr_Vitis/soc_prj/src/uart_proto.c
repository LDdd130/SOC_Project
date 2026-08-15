/******************************************************************************
 * uart_proto.c — PC 대시보드와의 UART 프로토콜
 *
 * 규격 : mission_soc_dashboard/README_PROTOCOL.md
 ******************************************************************************/

#include "uart_proto.h"
#include "mission_ip_regs.h"
#include "hb_gen.h"

#include "xil_printf.h"

#include <stdarg.h>

/* ================================================================== */
/* AXI UARTLite 레지스터 (PG142)                                        */
/* ================================================================== */
#define UL_RX_FIFO          0x00u
#define UL_TX_FIFO          0x04u
#define UL_STAT             0x08u
#define UL_STAT_RX_VALID    0x01u
#define UL_STAT_TX_FULL     0x08u

/* ================================================================== */
/* RX Ring Buffer                                                      */
/*                                                                     */
/* 예전에는 PROTO_PollRx 가 HW FIFO 를 직접 읽었다. 그래서 TX 로 루프가 */
/* 막혀 있는 동안 FIFO(16바이트)가 넘쳐서 명령이 잘렸다. 이제 TX 중에도 */
/* 계속 FIFO 를 이 Ring 으로 옮기고, 파서는 Ring 에서 읽는다.           */
/*                                                                     */
/* 256 은 $MISSION 한 줄 전송 시간(약 83ms) 동안 9600bps 로 들어올 수    */
/* 있는 최대 바이트(약 80)의 3배다. 명령 최대 길이(96)보다도 크다.       */
/* ================================================================== */
#define RX_RING_SZ          256u                /* 2의 거듭제곱        */
#define RX_RING_MASK        (RX_RING_SZ - 1u)

static volatile u8  s_rx_ring[RX_RING_SZ];
static volatile u16 s_rx_head = 0;              /* 넣는 쪽 */
static volatile u16 s_rx_tail = 0;              /* 빼는 쪽 */
static volatile u32 s_rx_dropped = 0;           /* Ring 까지 넘친 횟수 */

/* HW RX FIFO 를 Ring 으로 옮긴다. 언제 불러도 안전하다. */
void PROTO_RxPump(void)
{
    u16 next;

    while (REG_RD(UART_BASE, UL_STAT) & UL_STAT_RX_VALID) {
        u8 c = (u8)(REG_RD(UART_BASE, UL_RX_FIFO) & 0xFFu);

        next = (u16)((s_rx_head + 1u) & RX_RING_MASK);
        if (next == s_rx_tail) {
            /* Ring 이 가득 찼다. 여기까지 오면 설계 가정이 깨진 것이다.
             * 그래도 HW FIFO 는 계속 비워야 뒤 명령이 살아남는다. */
            s_rx_dropped++;
            continue;
        }
        s_rx_ring[s_rx_head] = c;
        s_rx_head = next;
    }
}

static int uart_getchar(void)
{
    int c;

    PROTO_RxPump();

    if (s_rx_tail == s_rx_head) return -1;

    c = (int)s_rx_ring[s_rx_tail];
    s_rx_tail = (u16)((s_rx_tail + 1u) & RX_RING_MASK);
    return c;
}

/* ================================================================== */
/* TX : 한 글자마다 RX 를 비우면서 내보낸다                             */
/* ================================================================== */
static void tx_putc(char c)
{
    /* TX FIFO 가 찼으면 빌 때까지 기다린다. 그 대기 시간이 바로 예전에
     * RX 를 굶기던 구간이므로, 기다리는 동안 RX 를 계속 퍼담는다. */
    while (REG_RD(UART_BASE, UL_STAT) & UL_STAT_TX_FULL) {
        PROTO_RxPump();
    }
    REG_WR(UART_BASE, UL_TX_FIFO, (u32)(u8)c);
    PROTO_RxPump();
}

static void tx_puts(const char *s)
{
    if (!s) s = "(null)";
    while (*s) tx_putc(*s++);
}

static void tx_u32(u32 v)
{
    char buf[11];
    int  n = 0;

    if (v == 0) { tx_putc('0'); return; }
    while (v > 0u && n < (int)sizeof(buf)) { buf[n++] = (char)('0' + (v % 10u)); v /= 10u; }
    while (n > 0) tx_putc(buf[--n]);
}

static void tx_i32(s32 v)
{
    u32 mag;

    if (v < 0) { tx_putc('-'); mag = (u32)(-(v + 1)) + 1u; }  /* INT_MIN 안전 */
    else       { mag = (u32)v; }
    tx_u32(mag);
}

static void tx_hex(u32 v, int width)
{
    static const char HEX[] = "0123456789abcdef";
    char buf[8];
    int  i;

    for (i = 0; i < 8; i++) { buf[i] = HEX[v & 0xFu]; v >>= 4; }

    if (width > 8) width = 8;
    if (width < 1) {                       /* 폭 지정 없음 : 유효 자리만 */
        width = 8;
        while (width > 1 && buf[width - 1] == '0') width--;
    }
    while (width > 0) tx_putc(buf[--width]);
}

/*
 * 최소 printf. uart_proto.c 와 main.c 가 실제로 쓰는 지정자만 지원한다.
 *   %u  %d  %s  %x  %02x  %08x  %%
 * 모르는 지정자는 '%' 부터 그대로 흘려보낸다(조용히 깨지는 것보다 낫다).
 */
void PROTO_Printf(const char *fmt, ...)
{
    va_list ap;
    const char *p = fmt;

    va_start(ap, fmt);
    while (*p) {
        if (*p != '%') { tx_putc(*p++); continue; }

        p++;                                    /* '%' 소비 */
        {
            int width = 0;
            int zero  = 0;

            if (*p == '%') { tx_putc('%'); p++; continue; }

            if (*p == '0') { zero = 1; p++; }
            while (*p >= '0' && *p <= '9') { width = width * 10 + (*p - '0'); p++; }
            (void)zero;                         /* 16진수에만 의미가 있다 */

            switch (*p) {
                case 'u': tx_u32(va_arg(ap, u32));            p++; break;
                case 'd': tx_i32((s32)va_arg(ap, int));       p++; break;
                case 's': tx_puts(va_arg(ap, const char *));  p++; break;
                case 'x':
                case 'X': tx_hex(va_arg(ap, u32), width);     p++; break;
                default :
                    /* 지원하지 않는 지정자. 원문을 그대로 보낸다. */
                    tx_putc('%');
                    if (width > 0 || zero) tx_putc('?');
                    if (*p) tx_putc(*p++);
                    break;
            }
        }
    }
    va_end(ap);
}

/* ================================================================== */
/* FPGA -> PC                                                          */
/* ================================================================== */

/*
 * $MISSION,timestamp,state,fault_level,fault_device,fault_code,
 *          alive,timeout,output_enable,actuator_enable,
 *          control_valid,state_timer,fault_count0,fault_count1,fault_count2
 *
 * 1~9 번은 필수, 10 번 이후는 선택이지만 전부 보낸다.
 * actuator_enable / control_valid 는 AXI 로 읽을 수 없어 C 의 출력 논리에서
 * 유도한다 (sc_regs.c 주석 참고).
 */
void PROTO_SendMission(u32 ts_ms)
{
    hb_status_t hb;
    fm_status_t fm;
    sc_status_t sc;
    u8 act, cv;

    HBGEN_Pump();   /* 가장 긴 줄(약 73ms 블로킹)이라 특히 중요하다 */

    HB_ReadStatus(&hb);
    FM_ReadStatus(&fm);
    SC_ReadStatus(&sc);

    act = SC_ActuatorEnable(sc.state, SC_IsEnabled(), FM_IsEnabled());
    cv  = SC_ControlValid(sc.state, SC_IsEnabled(), FM_IsEnabled());

    PROTO_Printf("$MISSION,%u,%s,%d,%d,%d,0x%02x,0x%02x,0x%02x,%d,%d,%u,%d,%d,%d\r\n",
               ts_ms,
               SC_StateStr(sc.state),
               fm.level, fm.device, fm.code,
               hb.alive, hb.timeout, sc.output_enable,
               act, cv,
               sc.state_timer,
               fm.count[0], fm.count[1], fm.count[2]);
}

/* IRQ_EN 세 개를 SET,IRQ_EN 과 같은 인코딩(bit0=A, bit1=B, bit2=C)으로 묶는다.
 * 각 IP 의 IRQ_EN 폭이 달라서(A 는 3비트, B/C 는 1비트) 0/1 로 정규화한다. */
static u32 irq_en_mask(void)
{
    u32 m = 0;

    if (HB_ReadIrqEn()) m |= 0x1u;
    if (FM_ReadIrqEn()) m |= 0x2u;
    if (SC_ReadIrqEn()) m |= 0x4u;
    return m;
}

void PROTO_SendIrq(void)
{
    HBGEN_Pump();   /* TX 블로킹 전에 Heartbeat 유지 */
    PROTO_Printf("$IRQ,0x%02x,0x%02x,0x%02x,0x%02x\r\n",
                 (unsigned)irq_en_mask(),
                 (unsigned)HB_ReadIrqStatus(),
                 (unsigned)FM_ReadIrqStatus(),
                 (unsigned)SC_ReadIrqStatus());
}

void PROTO_SendEventFaultChange(u32 ts_ms, u8 level, u8 device, u8 code)
{
    HBGEN_Pump();   /* TX 블로킹 전에 Heartbeat 유지 */
    PROTO_Printf("$EVENT,%u,FAULT_CHANGE,%d,%d,%d\r\n", ts_ms, level, device, code);
}

void PROTO_SendEventStateChange(u32 ts_ms, const char *state)
{
    HBGEN_Pump();   /* TX 블로킹 전에 Heartbeat 유지 */
    PROTO_Printf("$EVENT,%u,STATE_CHANGE,%s\r\n", ts_ms, state);
}

void PROTO_SendEventHeartbeatTimeout(u32 ts_ms, u8 device)
{
    HBGEN_Pump();   /* TX 블로킹 전에 Heartbeat 유지 */
    PROTO_Printf("$EVENT,%u,HEARTBEAT_TIMEOUT,%d\r\n", ts_ms, device);
}

void PROTO_SendEventManualReset(u32 ts_ms, const char *result)
{
    HBGEN_Pump();   /* TX 블로킹 전에 Heartbeat 유지 */
    PROTO_Printf("$EVENT,%u,MANUAL_RESET,%s\r\n", ts_ms, result);
}

void PROTO_Ack1(const char *cmd)
{
    HBGEN_Pump();   /* TX 블로킹 전에 Heartbeat 유지 */
    PROTO_Printf("$ACK,%s\r\n", cmd);
}

void PROTO_Ack2(const char *cmd, const char *a0)
{
    HBGEN_Pump();   /* TX 블로킹 전에 Heartbeat 유지 */
    PROTO_Printf("$ACK,%s,%s\r\n", cmd, a0);
}

void PROTO_Ack3(const char *cmd, const char *a0, u32 a1)
{
    HBGEN_Pump();   /* TX 블로킹 전에 Heartbeat 유지 */
    PROTO_Printf("$ACK,%s,%s,%u\r\n", cmd, a0, a1);
}

void PROTO_Ack4(const char *cmd, const char *a0, u32 a1, u32 a2)
{
    HBGEN_Pump();   /* TX 블로킹 전에 Heartbeat 유지 */
    PROTO_Printf("$ACK,%s,%s,%u,%u\r\n", cmd, a0, a1, a2);
}

void PROTO_Err1(const char *code)
{
    HBGEN_Pump();   /* TX 블로킹 전에 Heartbeat 유지 */
    PROTO_Printf("$ERR,%s\r\n", code);
}

void PROTO_Err2(const char *code, const char *desc)
{
    HBGEN_Pump();   /* TX 블로킹 전에 Heartbeat 유지 */
    PROTO_Printf("$ERR,%s,%s\r\n", code, desc);
}

/* ================================================================== */
/* 수신 파서                                                           */
/* ================================================================== */

#define RX_LINE_MAX     96
#define MAX_TOKENS       6

static char s_line[RX_LINE_MAX];
static int  s_len      = 0;
static int  s_overflow = 0;    /* 줄이 너무 길면 '\n' 까지 버린다 */

/* "0x1F" / "31" / "0b101" 모두 받는다. 실패하면 0 을 돌려주고 ok=0 */
static u32 parse_u32(const char *s, int *ok)
{
    u32 v = 0;
    int any = 0;
    int base = 10;

    *ok = 0;
    while (*s == ' ' || *s == '\t') s++;

    if (s[0] == '0' && (s[1] == 'x' || s[1] == 'X')) { base = 16; s += 2; }
    else if (s[0] == '0' && (s[1] == 'b' || s[1] == 'B')) { base = 2; s += 2; }

    while (*s) {
        int d;
        char c = *s;
        if      (c >= '0' && c <= '9') d = c - '0';
        else if (c >= 'a' && c <= 'f') d = c - 'a' + 10;
        else if (c >= 'A' && c <= 'F') d = c - 'A' + 10;
        else break;
        if (d >= base) break;
        v = v * (u32)base + (u32)d;
        any = 1;
        s++;
    }

    *ok = any;
    return v;
}

static int str_eq(const char *a, const char *b)
{
    while (*a && *b) { if (*a != *b) return 0; a++; b++; }
    return (*a == 0 && *b == 0);
}

/* 쉼표로 자르고 각 토큰 앞뒤 공백을 없앤다. 반환값 = 토큰 수 */
static int split_csv(char *line, char *tok[], int max_tok)
{
    int   n    = 0;
    int   done = 0;
    char *p    = line;

    while (n < max_tok && !done) {
        char *start = p;
        char *end;

        while (*p && *p != ',') p++;
        end = p;                        /* 구분자 또는 문자열 끝 */

        if (*p == ',') { *p = 0; p++; }
        else           { done = 1; }    /* 마지막 토큰 */

        while (*start == ' ' || *start == '\t') start++;
        while (end > start && (end[-1] == ' '  || end[-1] == '\t' ||
                               end[-1] == '\r' || end[-1] == '\n')) {
            end--;
        }
        *end = 0;

        tok[n++] = start;
    }
    return n;
}

/* ---------------- SET ---------------- */
static void handle_set(char *tok[], int n)
{
    int ok;
    u32 v;

    if (n < 3) { PROTO_Err2("INVALID_VALUE", "SET"); return; }

    if (str_eq(tok[1], "TIMEOUT")) {
        u32 dev;
        if (n < 4) { PROTO_Err2("INVALID_VALUE", "TIMEOUT"); return; }
        dev = parse_u32(tok[2], &ok);
        if (!ok || dev > 2) { PROTO_Err2("INVALID_VALUE", "TIMEOUT"); return; }
        v = parse_u32(tok[3], &ok);
        if (!ok) { PROTO_Err2("INVALID_VALUE", "TIMEOUT"); return; }
        HB_SetTimeout((u8)dev, v);              /* 0 은 RTL 이 1 로 간주 */
        PROTO_Ack4("SET", "TIMEOUT", dev, v);
        return;
    }

    v = parse_u32(tok[2], &ok);
    if (!ok) { PROTO_Err2("INVALID_VALUE", tok[1]); return; }

    if (str_eq(tok[1], "CRITICAL_MASK")) {
        if (v > 0x7u) { PROTO_Err2("INVALID_VALUE", "CRITICAL_MASK"); return; }
        FM_SetCriticalMask(v);
        PROTO_Ack3("SET", "CRITICAL_MASK", v);
    }
    else if (str_eq(tok[1], "PERSIST_LIMIT")) {
        if (v > 255u) { PROTO_Err2("INVALID_VALUE", "PERSIST_LIMIT"); return; }
        FM_SetPersistLimit(v);
        PROTO_Ack3("SET", "PERSIST_LIMIT", v);
    }
    else if (str_eq(tok[1], "RECOVERY_COUNT")) {
        if (v > 65535u) { PROTO_Err2("INVALID_VALUE", "RECOVERY_COUNT"); return; }
        SC_SetRecoveryCount(v);
        PROTO_Ack3("SET", "RECOVERY_COUNT", v);
    }
    else if (str_eq(tok[1], "DEGRADE_MASK")) {
        if (v > 0x7u) { PROTO_Err2("INVALID_VALUE", "DEGRADE_MASK"); return; }
        SC_SetDegradeMask(v);
        PROTO_Ack3("SET", "DEGRADE_MASK", v);
    }
    else if (str_eq(tok[1], "IRQ_EN")) {
        /*
         * bit0=A(heartbeat), bit1=B(fault), bit2=C(safety).
         *
         * 0 을 쓰면 irq 핀만 막힌다. IRQ_STATUS 는 계속 Set 되므로 ISR 이 W1C
         * 하지 못한 Pending 이 그대로 쌓여, GET,IRQ 로 래치를 눈으로 볼 수 있다.
         * 04 체크리스트 5.2 의 W1C 경로를 실제로 검증하는 유일한 수단이다.
         *
         * 끈 동안은 ISR 이 안 돌아 상태 Snapshot 이 안 쌓인다(짧은 WARNING 을
         * 놓친다). 메인 루프 폴링 백스톱은 살아 있어 상태 전이 자체는 계속
         * $EVENT 로 나간다. 검증이 끝나면 반드시 다시 켜야 한다.
         */
        if (v > 0x7u) { PROTO_Err2("INVALID_VALUE", "IRQ_EN"); return; }
        HB_EnableIrq((v & 0x1u) ? 1 : 0);
        FM_EnableIrq((v & 0x2u) ? 1 : 0);
        SC_EnableIrq((v & 0x4u) ? 1 : 0);
        PROTO_Ack3("SET", "IRQ_EN", v);
    }
    else {
        PROTO_Err1("UNKNOWN_COMMAND");
    }
}

/* ---------------- CMD ---------------- */
static void handle_cmd(char *tok[], int n, u32 ts_ms)
{
    if (n < 2) { PROTO_Err1("UNKNOWN_COMMAND"); return; }

    if (str_eq(tok[1], "MANUAL_RESET")) {
        /*
         * 00 공통명세 11장 : fault_valid=1 이고 fault_level=0 일 때만 인정.
         * IP 도 같은 조건으로 걸러내지만, 거부 사유를 PC 에 알려주려면
         * 소프트웨어가 먼저 판정해야 한다.
         */
        fm_status_t fm;
        FM_ReadStatus(&fm);
        if (!FM_IsEnabled() || fm.level != FM_LEVEL_0_NORMAL) {
            PROTO_Err2("MANUAL_RESET", "FAULT_ACTIVE");
            PROTO_SendEventManualReset(ts_ms, "REJECTED");
            return;
        }
        SC_ManualReset();
        PROTO_Ack2("CMD", "MANUAL_RESET");
        PROTO_SendEventManualReset(ts_ms, "ACCEPTED");
    }
    else if (str_eq(tok[1], "RESET_FAULT")) {
        /* 02_MEMBER_B 6.1 : 현재 device_fault 가 있으면 IP 가 무시한다. */
        if (FM_HasActiveFault()) {
            PROTO_Err2("RESET_FAULT", "FAULT_ACTIVE");
            return;
        }
        FM_ResetFault();
        PROTO_Ack2("CMD", "RESET_FAULT");
    }
    else if (str_eq(tok[1], "CLEAR_IRQ")) {
        /* Pending 만 지운다. Fault / Timeout 상태는 바뀌지 않는다. */
        FM_ClearIrq(FM_IRQ_FAULT_CHANGE);
        HB_ClearIrq(HB_IRQ_ALL);
        SC_ClearIrq(SC_IRQ_STATE_CHANGE);
        PROTO_Ack2("CMD", "CLEAR_IRQ");
    }
    else if (str_eq(tok[1], "CLEAR_HEARTBEAT")) {
        /* Counter 와 Timeout 만 지운다. IRQ Pending 은 건드리지 않는다. */
        HB_ClearAll();
        PROTO_Ack2("CMD", "CLEAR_HEARTBEAT");
    }
    else {
        PROTO_Err1("UNKNOWN_COMMAND");
    }
}

/* ---------------- INJECT ---------------- */
static void handle_inject(char *tok[], int n)
{
    int ok;
    u32 dev;
    int on;

    if (n < 2) { PROTO_Err1("UNKNOWN_COMMAND"); return; }

    if (str_eq(tok[1], "CLEAR")) {
        u8 i;
        INJ_ClearAll();
        for (i = 0; i < 3; i++) HBGEN_SetDeviceEnable(i, 1);
        PROTO_Ack2("INJECT", "CLEAR");
        return;
    }

    if (n < 4) { PROTO_Err2("INVALID_VALUE", tok[1]); return; }

    dev = parse_u32(tok[2], &ok);
    if (!ok || dev > 2) { PROTO_Err2("INVALID_VALUE", tok[1]); return; }

    on = str_eq(tok[3], "ON") ? 1 : 0;

    if (str_eq(tok[1], "ERROR")) {
        u32 m = INJ_GetError();
        if (on) m |=  (1u << dev);
        else    m &= ~(1u << dev);
        INJ_SetError(m);
        PROTO_Ack3("INJECT", "ERROR", dev);
    }
    else if (str_eq(tok[1], "CRITICAL")) {
        u32 m = INJ_GetCritical();
        if (on) m |=  (1u << dev);
        else    m &= ~(1u << dev);
        INJ_SetCritical(m);
        PROTO_Ack3("INJECT", "CRITICAL", dev);
    }
    else if (str_eq(tok[1], "TIMEOUT")) {
        /*
         * A 의 IP 통합 후 Timeout 은 GPIO 직접 주입이 아니다
         * (04 체크리스트 1.1 Freeze).
         * Heartbeat 를 멈추면 heartbeat_monitor 가 TIMEOUTn 초과를 판정해
         * 실제 timeout[i] 를 세운다. ON = Heartbeat 중단.
         */
        HBGEN_SetDeviceEnable((u8)dev, on ? 0 : 1);
        PROTO_Ack3("INJECT", "TIMEOUT", dev);
    }
    else {
        PROTO_Err1("UNKNOWN_COMMAND");
    }
}

/* ---------------- GET ---------------- */
static void handle_get(char *tok[], int n, u32 ts_ms)
{
    if (n < 2) { PROTO_Err1("UNKNOWN_COMMAND"); return; }

    if (str_eq(tok[1], "STATUS")) {
        PROTO_Ack2("GET", "STATUS");
        PROTO_SendMission(ts_ms);
    }
    else if (str_eq(tok[1], "CONFIG")) {
        PROTO_Ack2("GET", "CONFIG");
        PROTO_Ack4("SET", "TIMEOUT", 0, HB_GetTimeout(0));
        PROTO_Ack4("SET", "TIMEOUT", 1, HB_GetTimeout(1));
        PROTO_Ack4("SET", "TIMEOUT", 2, HB_GetTimeout(2));
        PROTO_Ack3("SET", "CRITICAL_MASK",  REG_RD(FM_BASE, FM_CRITICAL_MASK)  & 0x7u);
        PROTO_Ack3("SET", "PERSIST_LIMIT",  REG_RD(FM_BASE, FM_PERSIST_LIMIT)  & 0xFFu);
        PROTO_Ack3("SET", "RECOVERY_COUNT", REG_RD(SC_BASE, SC_RECOVERY_COUNT) & 0xFFFFu);
        PROTO_Ack3("SET", "DEGRADE_MASK",   REG_RD(SC_BASE, SC_DEGRADE_MASK)   & 0x7u);
        PROTO_Ack3("SET", "IRQ_EN",         irq_en_mask());
    }
    else if (str_eq(tok[1], "IRQ")) {
        PROTO_Ack2("GET", "IRQ");
        PROTO_SendIrq();
    }
    else {
        PROTO_Err1("UNKNOWN_COMMAND");
    }
}

/* ---------------- 한 줄 처리 ---------------- */
static void handle_line(char *line, u32 ts_ms)
{
    char *tok[MAX_TOKENS];
    int n;

    if (line[0] == 0) return;

    n = split_csv(line, tok, MAX_TOKENS);
    if (n < 1 || tok[0][0] == 0) return;

    if      (str_eq(tok[0], "GET"))    handle_get(tok, n, ts_ms);
    else if (str_eq(tok[0], "SET"))    handle_set(tok, n);
    else if (str_eq(tok[0], "CMD"))    handle_cmd(tok, n, ts_ms);
    else if (str_eq(tok[0], "INJECT")) handle_inject(tok, n);
    else                               PROTO_Err1("UNKNOWN_COMMAND");
}

void PROTO_PollRx(u32 ts_ms)
{
    int c;

    HBGEN_Pump();

    while ((c = uart_getchar()) >= 0) {
        if (c == '\n' || c == '\r') {
            if (s_overflow) {
                s_overflow = 0;
                s_len = 0;
                PROTO_Err2("INVALID_VALUE", "LINE_TOO_LONG");
                continue;
            }
            if (s_len > 0) {
                s_line[s_len] = 0;
                handle_line(s_line, ts_ms);
            }
            s_len = 0;
            continue;
        }

        if (s_len < (RX_LINE_MAX - 1)) {
            s_line[s_len++] = (char)c;
        } else {
            s_overflow = 1;     /* 다음 개행까지 버린다 */
        }
    }
}
