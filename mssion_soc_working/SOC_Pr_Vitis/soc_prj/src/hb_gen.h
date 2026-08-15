/******************************************************************************
 * hb_gen.h — Heartbeat 생성기 (Device Simulator 대체)
 *
 * 근거 : 00 공통명세 2장(Device 0~2 또는 Device Simulator), 6장(주기 정의),
 *        3장(별도 device_simulator_ip 는 핵심 3 IP 완성 후에만 확장)
 *
 * 실제 하위 장치가 없으므로 MicroBlaze 가 axi_gpio_1 CH1 을 토글해
 * heartbeat_async[2:0] 을 만든다. 04 체크리스트 1.1 의 직접 연결 Freeze 대로
 * heartbeat -> heartbeat_monitor -> timeout -> fault_manager 경로를 그대로 탄다.
 *
 * heartbeat_monitor_channel 이 2FF Synchronizer + Rising Edge Detector 를
 * 내장하므로 0 -> 1 상승 에지 하나가 Heartbeat 1회다.
 *
 * ── 시간 기준을 하드웨어로 잡는 이유 (중요) ──────────────────────────────
 * 예전 구현은 메인 루프가 세는 소프트웨어 ms 카운터로 주기를 판정했다.
 * 그런데 UART 가 9600bps 라 xil_printf 한 줄이 최대 73ms 동안 블로킹되고,
 * 그동안 루프가 멈춰 Heartbeat 가 전혀 나가지 않는다. 버튼 한 번 누르면
 * $ACK + $EVENT + irq + $MISSION 이 연달아 나가 236ms 가 막히는데,
 * Device 2 의 TIMEOUT 은 150ms 라 그 사이에 반드시 Timeout 이 뜬다.
 * CRITICAL_MASK=0x4 이므로 Device 2 Fault 는 지속 Count 없이 즉시 Level 3,
 * 즉 SAFE_MODE 로 래치되고 자동 복구가 금지되어 영원히 빠져나오지 못했다.
 *
 * 그래서 소프트웨어 시계를 버리고, heartbeat_monitor 가 하드웨어로 세는
 * LAST_COUNTn(마지막 Heartbeat 이후 경과 Clock)을 시간 기준으로 쓴다.
 * 소프트웨어가 얼마나 오래 멈춰 있었든 경과 시간이 정확히 반영된다.
 * ─────────────────────────────────────────────────────────────────────────
 ******************************************************************************/

#ifndef HB_GEN_H
#define HB_GEN_H

#include "xil_types.h"

void HBGEN_Init(void);

/* on=0 이면 그 장치의 Heartbeat 를 멈춘다.
 * -> heartbeat_monitor 의 Counter 가 TIMEOUTn 을 넘겨 timeout[i]=1
 * -> fault_manager 가 실제 Timeout Fault 로 판정한다.
 * 즉 이것이 통합 후의 "Timeout 주입" 방법이다. */
void HBGEN_SetDeviceEnable(u8 device, int on);
int  HBGEN_GetDeviceEnable(u8 device);

void HBGEN_SetPeriodMs(u8 device, u32 ms);
u32  HBGEN_GetPeriodMs(u8 device);

/*
 * Heartbeat 유지. 하드웨어 LAST_COUNTn 이 설정 주기를 넘긴 장치에만 Pulse 를 준다.
 *
 * 메인 루프뿐 아니라 UART 로 한 줄 내보내기 전마다 반드시 호출한다.
 * 그래야 TX 블로킹 구간에서도 Heartbeat 가 끊기지 않는다.
 * 여러 번 불러도 안전하다(주기 전이면 아무것도 안 한다).
 */
void HBGEN_Pump(void);

#endif /* HB_GEN_H */
