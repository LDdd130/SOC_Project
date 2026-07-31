/******************************************************************************
 * uart_proto.h — PC 대시보드와의 UART 프로토콜
 *
 * 규격 : mission_soc_dashboard/README_PROTOCOL.md (팀 공동 확정, 변경 금지)
 * 근거 : 04 체크리스트 3장 T24(UART 필드 순서), 8장(UART 필드 순서 변경 금지)
 *
 * 물리 : AXI UARTLite 9600 8N1 (XPAR_AXI_UARTLITE_0_BAUDRATE = 0x2580)
 *
 * 출력은 전부 ASCII 로만 쓴다. 9600bps 링크에서 바이트가 한 개 유실되면
 * UTF-8 멀티바이트 문자열이 통째로 깨져 보이기 때문이다(보드 로그에서 확인됨).
 ******************************************************************************/

#ifndef UART_PROTO_H
#define UART_PROTO_H

#include "xil_types.h"

/* ---- FPGA -> PC ---- */
void PROTO_SendMission(u32 ts_ms);

/*
 * `$IRQ,<en_mask>,<hb_status>,<fm_status>,<sc_status>` 한 줄.
 *
 * `en_mask` 는 `SET,IRQ_EN` 과 같은 인코딩이다 (bit0=A, bit1=B, bit2=C).
 * status 3개는 각 IP 의 IRQ_STATUS 레지스터 원본값이다
 * (A 는 bit[2:0] Device 별 Timeout Pending, B/C 는 bit0).
 *
 * 평상시엔 ISR 이 us 안에 W1C 하므로 status 는 항상 0 으로 읽힌다. Pending 이
 * 살아 있는 걸 보려면 `SET,IRQ_EN,0` 으로 irq 핀을 막아 ISR 을 멈춘 뒤 고장을
 * 넣어야 한다. IRQ_STATUS 의 Set 은 IRQ_EN 과 무관하기 때문이다
 * (rtl/fault_manager_axi.v: `assign irq = reg_irq_status & reg_irq_en;`).
 */
void PROTO_SendIrq(void);
void PROTO_SendEventFaultChange(u32 ts_ms, u8 level, u8 device, u8 code);
void PROTO_SendEventStateChange(u32 ts_ms, const char *state);
void PROTO_SendEventHeartbeatTimeout(u32 ts_ms, u8 device);
void PROTO_SendEventManualReset(u32 ts_ms, const char *result);

void PROTO_Ack1(const char *cmd);
void PROTO_Ack2(const char *cmd, const char *a0);
void PROTO_Ack3(const char *cmd, const char *a0, u32 a1);
void PROTO_Ack4(const char *cmd, const char *a0, u32 a1, u32 a2);
void PROTO_Err1(const char *code);
void PROTO_Err2(const char *code, const char *desc);

/* ---- PC -> FPGA ---- */
/* 논블로킹. RX Ring Buffer 를 비우고 '\n' 이 오면 그 줄을 처리한다.
 * 명령 처리 중에 UART 로 응답을 보내므로 ISR 안에서 호출하지 않는다. */
void PROTO_PollRx(u32 ts_ms);

/* ---- 송신 (2026-07-30 추가) ----------------------------------------------
 * xil_printf 는 한 줄을 다 내보낼 때까지 블로킹한다. 9600bps 에서 $MISSION
 * 한 줄(약 80바이트)이면 83ms 다. 그동안 아무도 UARTLite 의 16바이트 RX FIFO
 * 를 비우지 않아서, 그 사이에 도착한 GUI 명령(18~23바이트)의 뒷부분과 개행이
 * 잘려 명령이 통째로 유실됐다. 프리셋 버튼처럼 명령 2개를 한 번에 쏘면 확정
 * 유실이다.
 *
 * PROTO_Printf 는 한 글자를 TX FIFO 에 넣을 때마다 RX FIFO 를 Ring Buffer 로
 * 옮긴다. TX 와 RX 가 같은 9600bps 라 글자당 최대 1바이트만 들어오므로 16단
 * FIFO 가 넘칠 수 없다.
 *
 * 지원 포맷 : %u %d %s %x %02x %08x %%  (uart_proto.c / main.c 가 쓰는 전부)
 * newlib 의 printf 계열은 LMB BRAM 128KB 에 안 들어가서 쓰지 않는다.
 * -------------------------------------------------------------------------*/
void PROTO_Printf(const char *fmt, ...);

/* HW RX FIFO -> Ring Buffer. 오래 블로킹하는 구간에서 직접 불러도 된다. */
void PROTO_RxPump(void);

#endif /* UART_PROTO_H */
