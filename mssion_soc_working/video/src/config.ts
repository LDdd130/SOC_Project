// ─────────────────────────────────────────────────────────────
//  ↓↓↓  여기만 채우면 인트로/아웃트로 카드에 반영된다  ↓↓↓
// ─────────────────────────────────────────────────────────────

export const CREDITS = {
  /** 인트로 큰 제목 */
  title: '임무컴퓨터 상태 감시 · 고장 대응 SoC',
  /** 인트로 작은 제목 */
  subtitle: 'Mission SoC — Basys 3 / MicroBlaze',

  /** 소속 · 과정. 비우면 안 나온다. */
  org: '',
  /** 발표일. 비우면 안 나온다. */
  date: '',

  /**
   * 팀원. name 을 실명으로 바꿔라. 비운 항목은 자동으로 빠진다.
   * role 은 담당 IP 그대로 두면 된다.
   */
  members: [
    {name: '김민석', role: 'heartbeat_monitor'},
    {name: '이재운', role: 'fault_manager'},
    {name: '박기태', role: 'safety_controller'},
  ],
} as const;

/** 아웃트로에 띄우는 검증 수치. README.md 「주요 검증 결과」와 같은 값이다. */
export const VERIFICATION = [
  {label: 'RTL Testbench', value: '4,533 checks', note: '0 fail'},
  {label: 'Python 테스트', value: '202 passed', note: ''},
  {label: 'Routed Timing', value: 'WNS +0.963 ns', note: 'WHS +0.029 ns'},
  {label: '보드 UART 로그', value: '이 영상과 동일 테이크', note: 'mission_events_20260810_113104.csv'},
] as const;
