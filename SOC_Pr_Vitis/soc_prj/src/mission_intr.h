/******************************************************************************
 * mission_intr.h — AXI INTC 초기화와 세 IP ISR
 *
 * 근거 : 00 공통명세 12장(ISR 원칙), 04 체크리스트 5.2(IRQ 전체 경로),
 *        04 체크리스트 8장(IRQ 연결 순서 변경 금지)
 ******************************************************************************/

#ifndef MISSION_INTR_H
#define MISSION_INTR_H

#include "xil_types.h"

/*
 * xlconcat 연결 순서 = XIntc 인터럽트 ID (04 체크리스트 8장 — 변경 금지)
 *   In0 = axi_uartlite_0/interrupt
 *   In1 = fault_manager_ip_0/irq
 *   In2 = myip_heartbeat_monit_0/irq
 *   In3 = safety_controller_0/irq
 */
#define INTR_ID_UART    0u
#define INTR_ID_FM      1u
#define INTR_ID_HB      2u
#define INTR_ID_SC      3u

/*
 * ISR 이 남기는 것 (00 공통명세 12장)
 *   1. IRQ_STATUS 읽기
 *   2. 원인을 전역 변수/큐에 저장
 *   3. W1C Clear
 *   4. 메인 루프 처리 플래그 설정
 * ISR 안에서 UART 출력, 긴 Delay, 전체 로그 출력을 하지 않는다.
 */
typedef struct {
    volatile u32 flag;      /* 메인 루프가 읽고 0 으로 내린다 */
    volatile u32 cause;     /* ISR 이 읽은 IRQ_STATUS 값       */
    volatile u32 count;     /* 누적 진입 횟수 (경로 검증용)     */
} intr_record_t;

extern intr_record_t g_fm_irq;
extern intr_record_t g_hb_irq;
extern intr_record_t g_sc_irq;

/* ------------------------------------------------------------------ */
/* 상태 Snapshot 큐                                                    */
/*                                                                     */
/* 00 공통명세 12장 MicroBlaze 담당의 "필요 시 상태 Snapshot 저장" 이다. */
/*                                                                     */
/* 왜 필요한가 : 메인 루프는 TICK_MS(5ms)마다 레지스터를 폴링해 직전     */
/* 값과 비교한다. 그래서 폴링 주기보다 짧게 스쳐 가는 상태는 통째로      */
/* 사라진다. eval_tick 이 1ms 이므로 PERSIST_LIMIT=5 면 LEVEL_1          */
/* (WARNING) 이 5ms 만 유지되고, 폴링이 눈을 뜰 때는 이미 LEVEL_2 다.    */
/* 실제로 보드 로그(mission_events_20260731_*.csv)에 STATE_CHANGE,      */
/* WARNING 이 한 줄도 없고 FAULT_CHANGE 가 level 0 -> 2 로 1 을 건너뛴  */
/* 이유가 이것이다.                                                     */
/*                                                                     */
/* Snapshot 은 하드웨어가 IRQ 를 올린 그 순간의 값이라 유지 시간과       */
/* 무관하게 남는다. 한 번의 조작으로 0 -> 1 -> 2 처럼 연속 전이가        */
/* 일어나면 ISR 이 여러 번 들어오므로 슬롯 하나로는 앞의 값이 덮인다.    */
/* 그래서 Ring 으로 받는다.                                             */
/* ------------------------------------------------------------------ */
#define MISSION_SNAP_DEPTH  16u

typedef struct {
    u8 hb_timeout;      /* HB_STATUS   bit[10:8] */
    u8 fm_level;        /* 0~3                   */
    u8 fm_device;       /* 0~3                   */
    u8 fm_code;         /* FM_FAULT_*            */
    u8 sc_state;        /* ST_*                  */
} mission_snap_t;

/* 0 = 성공 */
int  MissionIntr_Init(void);

/* 메인 루프에서 호출. 플래그가 서 있으면 1 을 돌려주고 cause 를 꺼내며
 * 플래그를 내린다. 인터럽트를 잠깐 막고 원자적으로 처리한다. */
int  MissionIntr_Take(intr_record_t *rec, u32 *cause_out);

/* 메인 루프에서 호출. Snapshot 을 들어온 순서대로 하나 꺼낸다.
 * 1 = 꺼냈다, 0 = 큐가 비었다. */
int  MissionIntr_TakeSnap(mission_snap_t *out);

/* Ring 이 가득 차서 버린 Snapshot 개수. 정상 동작이면 0 이다. */
u32  MissionIntr_SnapDropped(void);

#endif /* MISSION_INTR_H */
