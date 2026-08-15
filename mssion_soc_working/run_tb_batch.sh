#!/usr/bin/env bash
# =============================================================================
# run_tb_batch.sh
#
# 모든 testbench 를 Vivado GUI 없이 batch 모드(xvlog/xelab/xsim)로 돌린다.
#
# GUI 로 돌리면 Vivado 프로세스 하나가 8GB 를 잡고 있는 위에 시뮬레이터가
# 얹히면서 이 PC(RAM 15GB)에서 크래시했다. batch 모드는 xsim 프로세스만
# 뜨므로 TB 하나당 수백 MB 수준이고, 하나 끝나면 바로 반환된다.
#
# 사용법 :
#     ./run_tb_batch.sh              # 전체
#     ./run_tb_batch.sh tb_fault_manager_axi tb_heartbeat_monitor_core
#
# 결과 로그 : tb_logs_batch/<top>.log
# 종료 코드 : 실패한 TB 가 하나라도 있으면 1
# =============================================================================

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VIVADO_BIN="${VIVADO_BIN:-/media/user7/data/tools/Vivado/2024.2/bin}"
export PATH="$VIVADO_BIN:$PATH"

WORK="$ROOT/.tb_batch_work"
LOGDIR="$ROOT/tb_logs_batch"

SIM="$ROOT/sim"
IP="$ROOT/SOC_Pr/ip_repo"

# RTL 은 실제로 합성되는 ip_repo 쪽을 정본으로 쓴다.
# rtl/ 아래의 fault_manager_* 는 같은 내용의 사본이라 같이 넣으면 모듈이
# 중복 정의된다.
HB_RTL="$IP/myip_heartbeat_monitor_1_0/src/heartbeat_monitor.v"
FM_CORE="$IP/fault_manager_ip_1_0/src/fault_manager_core.v"
FM_AXI="$IP/fault_manager_ip_1_0/src/fault_manager_axi.v"
SC_CORE="$IP/safety_controller_1_0/hdl/safety_controller.v"
SC_AXI="$IP/safety_controller_1_0/hdl/safety_controller_slave_lite_v1_0_S00_AXI.v"
TICK="$ROOT/rtl/eval_tick_generator.v"

# top 이름 -> 컴파일에 필요한 소스 목록
sources_for() {
    case "$1" in
        tb_heartbeat_monitor_core|tb_heartbeat_monitor_axi)
            echo "$SIM/tb_heartbeat_monitor.v $HB_RTL" ;;
        tb_fault_manager_core)
            echo "$SIM/tb_fault_manager_core.v $FM_CORE" ;;
        tb_fault_manager_axi)
            echo "$SIM/tb_fault_manager_axi.v $FM_AXI $FM_CORE" ;;
        tb_safety_controller_core)
            echo "$SIM/tb_safety_controller_core.v $SC_CORE" ;;
        tb_safety_controller_axi)
            echo "$SIM/tb_safety_controller_axi.v $SC_AXI $SC_CORE" ;;
        tb_eval_tick_generator)
            echo "$SIM/tb_eval_tick_generator.v $TICK" ;;
        tb_mission_soc_top)
            echo "$SIM/tb_mission_soc_top.v $HB_RTL $FM_AXI $FM_CORE $SC_AXI $SC_CORE $TICK" ;;
        *)  echo "" ;;
    esac
}

ALL_TOPS=(
    tb_heartbeat_monitor_core
    tb_heartbeat_monitor_axi
    tb_fault_manager_core
    tb_fault_manager_axi
    tb_safety_controller_core
    tb_safety_controller_axi
    tb_eval_tick_generator
    tb_mission_soc_top
)

if [ $# -gt 0 ]; then TOPS=("$@"); else TOPS=("${ALL_TOPS[@]}"); fi

if ! command -v xvlog >/dev/null 2>&1; then
    echo "ERROR: xvlog 를 못 찾았다. VIVADO_BIN 을 확인해라 (현재: $VIVADO_BIN)"
    exit 2
fi

mkdir -p "$LOGDIR"
rm -rf "$WORK"; mkdir -p "$WORK"

overall=0
declare -a SUMMARY

for top in "${TOPS[@]}"; do
    srcs="$(sources_for "$top")"
    if [ -z "$srcs" ]; then
        echo "SKIP: 모르는 top '$top'"
        SUMMARY+=("$(printf '%-28s %s' "$top" 'UNKNOWN TOP')")
        overall=1
        continue
    fi

    log="$LOGDIR/$top.log"
    echo "=============================================================="
    echo " RUN : $top"
    echo "=============================================================="

    # TB 마다 라이브러리를 새로 만든다. 서로 다른 TB 가 같은 모듈명을
    # 다르게 정의해도 충돌하지 않는다.
    rm -rf "$WORK/$top"; mkdir -p "$WORK/$top"
    (
        cd "$WORK/$top" || exit 1
        # shellcheck disable=SC2086
        xvlog --nolog $srcs > compile.log 2>&1 \
          && xelab --nolog -debug off --snapshot "${top}_snap" "work.$top" > elab.log 2>&1 \
          && xsim "${top}_snap" --nolog --runall > sim.log 2>&1
        echo $? > rc.txt
    )
    rc="$(cat "$WORK/$top/rc.txt" 2>/dev/null || echo 1)"

    if [ "$rc" != "0" ]; then
        {
            echo "### COMPILE"; cat "$WORK/$top/compile.log" 2>/dev/null
            echo "### ELABORATE"; cat "$WORK/$top/elab.log" 2>/dev/null
            echo "### SIMULATE"; cat "$WORK/$top/sim.log" 2>/dev/null
        } > "$log"
        echo " >> 실행 실패. ERROR 줄:"
        grep -E "ERROR|Fatal" "$log" | head -10
        SUMMARY+=("$(printf '%-28s %s' "$top" 'RUN FAILED')")
        overall=1
        continue
    fi

    cp "$WORK/$top/sim.log" "$log"

    # TB 마다 태그 형식이 다르다: [PASS] / [PASS 12] / [FAIL] / [FAIL 12] /
    # [AXI PROTOCOL FAIL]. 번호가 붙은 형식을 놓치면 실패해도 0 으로 보인다.
    # $display("%0s", <reg 벡터>) 는 NUL 바이트를 같이 뱉는다. 그러면 grep 이
    # 로그를 바이너리로 보고 매치를 통째로 숨긴다. -a 로 항상 텍스트 취급한다.
    n_pass=$(grep -aoE '\[PASS[^]]*\]' "$log" | wc -l)
    n_fail=$(grep -aoE '\[[^]]*FAIL[^]]*\]' "$log" | wc -l)
    finished=$(grep -ac 'finish called at time' "$log")

    # TB 마다 결과 요약 형식이 다르다. 자기 자신이 센 숫자가 있으면 그게
    # 정본이다 (전수 검증 루프처럼 항목마다 태그를 안 찍는 TB 가 있다).
    #   checks = 4146, errors = 0
    #   ALL TESTS PASSED: 총 64개 검증 통과
    s_checks=$(grep -aoE 'checks = [0-9]+' "$log" | tail -1 | grep -aoE '[0-9]+')
    s_errors=$(grep -aoE 'errors = [0-9]+' "$log" | tail -1 | grep -aoE '[0-9]+')
    k_checks=$(grep -aoE '총 [0-9]+개 검증 통과' "$log" | tail -1 | grep -aoE '[0-9]+')

    if [ -n "$s_checks" ] && [ -n "$s_errors" ]; then
        n_pass=$(( s_checks - s_errors ))
        n_fail=$s_errors
    elif [ -n "$k_checks" ] && [ "$n_fail" -eq 0 ]; then
        n_pass=$k_checks
    fi

    note=""
    if [ "$finished" -eq 0 ]; then
        note=" (경고: \$finish 없음 - 중간에 잘렸다)"
        overall=1
    fi
    if [ "$n_fail" -gt 0 ]; then
        overall=1
        echo " 실패 항목:"
        grep -E '\[[^]]*FAIL[^]]*\]' "$log" | head -20
    fi

    printf ' %-28s PASS=%-4s FAIL=%-4s%s\n' "$top" "$n_pass" "$n_fail" "$note"
    SUMMARY+=("$(printf '%-28s PASS=%-5s FAIL=%-5s%s' "$top" "$n_pass" "$n_fail" "$note")")
    echo " 로그 -> $log"
    echo ""
done

rm -rf "$WORK"

echo "=============================================================="
echo " SUMMARY"
echo "=============================================================="
for line in "${SUMMARY[@]}"; do echo " $line"; done
echo "=============================================================="
if [ "$overall" -eq 0 ]; then echo " 전체 PASS"; else echo " 실패한 TB 가 있다"; fi
exit "$overall"
