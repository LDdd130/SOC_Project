/******************************************************************************
 * mission_ip_regs.h — 팀 공통 레지스터/인코딩 헤더
 *
 * 근거 : 00 공통명세 7장(상태·코드 정의), 9장(레지스터 맵), 15장(파일명 권장)
 *
 * 규칙
 *   - Offset 숫자를 다른 소스에 직접 쓰지 않는다. 반드시 이 헤더의 매크로를 쓴다.
 *   - Offset / 인코딩 변경은 00 공통명세 15장 CHANGE REQUEST 절차를 따른다.
 *   - 세 IP 모두 CTRL 이 RW(ENABLE) + W1P 혼합이다. RTL 이 CTRL Write 때마다
 *     ENABLE 을 wdata[0] 으로 덮어쓰므로, W1P 를 쏠 때 ENABLE 을 같이 실어야
 *     IP 가 꺼지지 않는다. 그래서 각 드라이버가 CTRL Shadow 를 들고 있다.
 *
 * 헤더가드 주의 :
 *   IP 패키징 시 Vivado 가 만든 드라이버 스켈레톤이 BSP 에 함께 복사된다
 *   (fault_manager_ip.h 등). 이름 충돌을 피하려고 이 헤더는 MISSION_IP_REGS_H
 *   를 쓰고, 드라이버 파일도 *_regs.c 로 분리한다. 되돌리지 말 것.
 ******************************************************************************/

#ifndef MISSION_IP_REGS_H
#define MISSION_IP_REGS_H

#include "xparameters.h"
#include "xil_io.h"
#include "xil_types.h"

/* ================================================================== */
/* Base Address (Vivado Address Editor 확정값)                         */
/* ================================================================== */
#define FM_BASE     XPAR_FAULT_MANAGER_IP_0_BASEADDR        /* 0x44A00000 */

#ifdef XPAR_MYIP_HEARTBEAT_MONIT_0_BASEADDR
  #define HB_BASE   XPAR_MYIP_HEARTBEAT_MONIT_0_BASEADDR    /* 0x44A10000 */
#else
  #define HB_BASE   XPAR_MYIP_HEARTBEAT_MONITOR_0_BASEADDR
#endif

#define SC_BASE     XPAR_SAFETY_CONTROLLER_0_BASEADDR       /* 0x44A20000 */

#define GPIO0_BASE  XPAR_AXI_GPIO_0_BASEADDR                /* 0x40000000 */
#define GPIO1_BASE  XPAR_AXI_GPIO_1_BASEADDR                /* 0x40010000 */
#define INTC_BASE   XPAR_XINTC_0_BASEADDR                   /* 0x41200000 */
#define UART_BASE   XPAR_AXI_UARTLITE_0_BASEADDR            /* 0x40600000 */

/* AXI GPIO 레지스터 Offset (PG144) */
#define GPIO_CH1_DATA   0x00u
#define GPIO_CH2_DATA   0x08u

/*
 * GPIO 용도 (Block Design 확정)
 *   axi_gpio_0 CH1 -> fault_manager_ip.error_flag[2:0]
 *   axi_gpio_0 CH2 -> fault_manager_ip.critical_fault[2:0]
 *   axi_gpio_1 CH1 -> myip_heartbeat_monitor.heartbeat_async[2:0]
 *
 * 주의 : axi_gpio_1 은 예전에 timeout 직접 주입용이었다. A 의 IP 가 통합되면서
 *        04 체크리스트 1.1 Freeze 대로 heartbeat 주입으로 용도가 바뀌었다.
 *        이제 timeout 은 heartbeat_monitor 가 만든다.
 */

/* ================================================================== */
/* 공통 인코딩 (00 공통명세 7장 — 변경 금지)                            */
/* ================================================================== */

/* 7.1 System State */
#define ST_NORMAL               0u
#define ST_WARNING              1u
#define ST_DEGRADED             2u
#define ST_SAFE_MODE            3u

/* 7.2 Fault Level */
#define FM_LEVEL_0_NORMAL       0u
#define FM_LEVEL_1_WARNING      1u
#define FM_LEVEL_2_DEGRADED     2u
#define FM_LEVEL_3_SAFE         3u

/* 7.3 Fault Code */
#define FM_FAULT_NONE           0x00u
#define FM_FAULT_TIMEOUT        0x01u
#define FM_FAULT_ERROR_CODE     0x02u
#define FM_FAULT_CRITICAL       0x03u
#define FM_FAULT_MULTI_DEVICE   0x04u
#define FM_FAULT_RECOVERY_REQ   0x05u

/* 7.4 Device ID */
#define FM_DEVICE_0             0u
#define FM_DEVICE_1             1u
#define FM_DEVICE_2             2u
#define FM_MULTIPLE_OR_NONE     3u

/* ================================================================== */
/* 9.1 heartbeat_monitor_ip  (팀원 A)                                  */
/* ================================================================== */
#define HB_CTRL             0x00u   /* RW/W1P bit0 ENABLE, bit1 CLEAR_ALL(W1P), bit2 AUTO_RECOVER */
#define HB_STATUS           0x04u   /* R   bit[2:0] ALIVE, bit[10:8] TIMEOUT   */
#define HB_TIMEOUT0         0x08u   /* RW  Device 0 Timeout clocks             */
#define HB_TIMEOUT1         0x0Cu   /* RW  Device 1                            */
#define HB_TIMEOUT2         0x10u   /* RW  Device 2                            */
#define HB_LAST_COUNT0      0x14u   /* R   Device 0 경과 Count                 */
#define HB_LAST_COUNT1      0x18u   /* R                                       */
#define HB_LAST_COUNT2      0x1Cu   /* R                                       */
#define HB_IRQ_EN           0x20u   /* RW  bit[2:0] Timeout IRQ Enable         */
#define HB_IRQ_STATUS       0x24u   /* R/W1C bit[2:0] Timeout Pending          */

#define HB_CTRL_ENABLE          0x1u
#define HB_CTRL_CLEAR_ALL       0x2u    /* W1P */
#define HB_CTRL_AUTO_RECOVER    0x4u
#define HB_IRQ_ALL              0x7u

/* ================================================================== */
/* 9.2 fault_manager_ip  (팀원 B)                                      */
/* ================================================================== */
#define FM_CTRL             0x00u   /* RW/W1P bit0 ENABLE, bit1 RESET_FAULT(W1P)            */
#define FM_FAULT_INPUT      0x04u   /* R   bit[2:0] timeout, [10:8] error, [18:16] critical */
#define FM_CRITICAL_MASK    0x08u   /* RW  bit[2:0], 기본 0x4                               */
#define FM_PERSIST_LIMIT    0x0Cu   /* RW  bit[7:0]                                         */
#define FM_FAULT_LEVEL      0x10u   /* R   bit[1:0]                                         */
#define FM_FAULT_DEVICE     0x14u   /* R   bit[1:0]                                         */
#define FM_FAULT_CODE       0x18u   /* R   bit[7:0]                                         */
#define FM_FAULT_COUNT      0x1Cu   /* R   [7:0] cnt0, [15:8] cnt1, [23:16] cnt2            */
#define FM_IRQ_EN           0x20u   /* RW  bit0 Fault Change                                */
#define FM_IRQ_STATUS       0x24u   /* R/W1C bit0 Fault Change Pending                      */
#define FM_ID               0x2Cu   /* R   0x464D4752 ("FMGR"). B 가 추가한 진단용          */

#define FM_CTRL_ENABLE          0x1u
#define FM_CTRL_RESET_FAULT     0x2u    /* W1P */
#define FM_IRQ_FAULT_CHANGE     0x1u
#define FM_ID_VALUE             0x464D4752u

/* ================================================================== */
/* 9.3 safety_controller_ip  (팀원 C)                                  */
/* ================================================================== */
#define SC_CTRL             0x00u   /* RW/W1P bit0 ENABLE, bit1 MANUAL_RESET(W1P) */
#define SC_SYSTEM_STATE     0x04u   /* R   bit[1:0]                               */
#define SC_OUTPUT_ENABLE    0x08u   /* R   bit[2:0]                               */
#define SC_DEGRADE_MASK     0x0Cu   /* RW  bit[2:0]                               */
#define SC_RECOVERY_COUNT   0x10u   /* RW  bit[15:0]                              */
#define SC_STATE_TIMER      0x14u   /* R   현재 상태 유지 Count                    */
#define SC_IRQ_EN           0x18u   /* RW  bit0 상태 변화                          */
#define SC_IRQ_STATUS       0x1Cu   /* R/W1C bit0 상태 변화 Pending                */

#define SC_CTRL_ENABLE          0x1u
#define SC_CTRL_MANUAL_RESET    0x2u    /* W1P */
#define SC_IRQ_STATE_CHANGE     0x1u

/*
 * actuator_enable / control_valid 는 00 공통명세 9.3 레지스터 맵에 없다.
 * C 의 RTL 도 명세대로 구현했으므로 AXI 로 읽을 수 없다.
 * 하드웨어 출력 핀 -> led_concat -> LED5 / LED6 으로만 관측한다.
 * UART $MISSION 의 actuator_enable / control_valid 필드는 00 공통명세 8.6
 * 정책표에 따라 system_state 에서 유도한다. MISSION_ActuatorFromState() 참고.
 */

/* ================================================================== */
/* 권장 초기값 (00 공통명세 12.2 / 04 체크리스트 1장, 6장)              */
/* ================================================================== */
#define CFG_CRITICAL_MASK       0x4u    /* Device 2 만 Critical            */
#define CFG_PERSIST_LIMIT       5u      /* eval_tick 5회 지속 -> Level 2   */
#define CFG_RECOVERY_COUNT      2u      /* RECOVERY_COUNT < PERSIST_LIMIT  */
#define CFG_DEGRADE_MASK        0x1u

/* 00 공통명세 6장 장치 정의. 100MHz 기준 clock count */
#define MISSION_CLK_HZ          100000000u
#define MS_TO_CLK(ms)           ((u32)((MISSION_CLK_HZ / 1000u) * (u32)(ms)))
/* SC_STATE_TIMER 는 레지스터에 100MHz clock count 로 남아 있다.
 * UART $MISSION 은 GUI가 그대로 ms 로 쓰므로 여기서 변환해 내보낸다. */
#define CLK_TO_MS(clk)          ((u32)((clk) / (MISSION_CLK_HZ / 1000u)))

#define CFG_TIMEOUT0_MS         300u    /* Device 0 일반 센서   */
#define CFG_TIMEOUT1_MS         600u    /* Device 1 통신        */
#define CFG_TIMEOUT2_MS         150u    /* Device 2 모터/핵심   */

#define CFG_HB_PERIOD0_MS       100u    /* Device 0 Heartbeat 주기 */
#define CFG_HB_PERIOD1_MS       200u
#define CFG_HB_PERIOD2_MS        50u

/* ================================================================== */
/* 공통 Read/Write                                                     */
/* ================================================================== */
#define REG_RD(base, off)       Xil_In32((base) + (off))
#define REG_WR(base, off, val)  Xil_Out32((base) + (off), (u32)(val))

/* ================================================================== */
/* 상태 스냅샷                                                         */
/* ================================================================== */
typedef struct {
    u8  alive;          /* bit[2:0] */
    u8  timeout;        /* bit[2:0] */
    u32 last_count[3];
} hb_status_t;

typedef struct {
    u8  level;          /* 0~3            */
    u8  device;         /* 0~3            */
    u8  code;           /* FM_FAULT_*     */
    u8  timeout;        /* bit[2:0]       */
    u8  error_flag;     /* bit[2:0]       */
    u8  critical_fault; /* bit[2:0]       */
    u8  count[3];       /* 장치별 지속 Count */
} fm_status_t;

typedef struct {
    u8  state;          /* ST_*     */
    u8  output_enable;  /* bit[2:0] */
    u32 state_timer;
} sc_status_t;

/* ================================================================== */
/* 팀원 A — heartbeat_monitor_ip 함수 (00 공통명세 0장 역할표)          */
/* ================================================================== */
void HB_Init(u32 to0_clk, u32 to1_clk, u32 to2_clk);
void HB_Enable(int on);
void HB_SetAutoRecover(int on);
void HB_ClearAll(void);                     /* W1P. Counter/Timeout Clear, Pending 유지 */
void HB_SetTimeout(u8 device, u32 clocks);  /* clocks==0 은 RTL 이 1 로 간주 */
u32  HB_GetTimeout(u8 device);
/* 마지막 Heartbeat 이후 경과 Clock. 하드웨어가 세므로 소프트웨어가 멈춰 있어도
 * 정확하다. Heartbeat 생성 주기 판정의 시간 기준으로 쓴다 (hb_gen.c). */
u32  HB_GetLastCount(u8 device);
void HB_EnableIrq(int on);
u32  HB_ReadIrqStatus(void);
u32  HB_ReadIrqEn(void);
void HB_ClearIrq(u32 mask);                 /* W1C */
void HB_ReadStatus(hb_status_t *s);

/* ================================================================== */
/* 팀원 B — fault_manager_ip 함수                                      */
/* ================================================================== */
int  FM_SelfCheck(void);                    /* ID + RW 왕복. 0 = OK */
void FM_Init(u32 critical_mask, u32 persist_limit);
void FM_Enable(int on);
void FM_ResetFault(void);                   /* W1P. 활성 Fault 있으면 IP 가 무시 */
void FM_SetCriticalMask(u32 mask);
void FM_SetPersistLimit(u32 value);
void FM_EnableIrq(int on);
u32  FM_ReadIrqStatus(void);
u32  FM_ReadIrqEn(void);
void FM_ClearIrq(u32 mask);                 /* W1C */
void FM_ReadStatus(fm_status_t *s);
int  FM_HasActiveFault(void);               /* device_fault 가 하나라도 있으면 1 */
int  FM_IsEnabled(void);                    /* == fault_valid (02_MEMBER_B 2장) */

const char *FM_LevelStr(u8 level);
const char *FM_CodeStr(u8 code);
const char *FM_DeviceStr(u8 device);

/* ================================================================== */
/* 팀원 C — safety_controller_ip 함수                                  */
/* ================================================================== */
void SC_Init(u32 degrade_mask, u32 recovery_count);
void SC_Enable(int on);
void SC_ManualReset(void);                  /* W1P. fault_valid=1 && level=0 에서만 인정 */
void SC_SetDegradeMask(u32 mask);
void SC_SetRecoveryCount(u32 value);
void SC_EnableIrq(int on);
u32  SC_ReadIrqStatus(void);
u32  SC_ReadIrqEn(void);
void SC_ClearIrq(u32 mask);                 /* W1C */
void SC_ReadStatus(sc_status_t *s);

const char *SC_StateStr(u8 state);
int  SC_IsEnabled(void);

/* C 의 core 출력 논리를 그대로 옮긴 유도식. AXI 로 못 읽는 신호 대체용.
 * fault_valid 는 fault_manager 의 enable 과 같다 (FM_IsEnabled()). */
u8   SC_ActuatorEnable(u8 state, int enabled, int fault_valid);
u8   SC_ControlValid(u8 state, int enabled, int fault_valid);

/* ================================================================== */
/* Fault Injection (외부 입력 대체. 00 공통명세 8.3)                    */
/* ================================================================== */
void INJ_SetError(u32 mask3);       /* axi_gpio_0 CH1 */
void INJ_SetCritical(u32 mask3);    /* axi_gpio_0 CH2 */
u32  INJ_GetError(void);
u32  INJ_GetCritical(void);
void INJ_ClearAll(void);

#endif /* MISSION_IP_REGS_H */
