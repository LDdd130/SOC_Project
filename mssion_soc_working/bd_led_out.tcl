################################################################################
# bd_led_out.tcl
#
# 미연결로 남은 상태 출력들을 Basys3 LED 16개로 뺀다.
#
# 왜 필요한가
#   safety_controller 의 actuator_enable / control_valid 는 00 공통명세 9.3
#   레지스터 맵에 없다. C 의 AXI read mux 에도 없다(구현이 명세를 그대로 따른 결과).
#   즉 LED 로 빼지 않으면 04 체크리스트 4장 시연 9단계
#   "SAFE_MODE, ACTUATOR_ENABLE=0" 을 관측할 방법이 아예 없다.
#   나머지(alive/system_state/output_enable)는 AXI 로도 읽히지만
#   04 체크리스트 3장 T25 "LED/FND 상태와 일치" 산출물이라 같이 뺀다.
#
# LED 맵 (04 체크리스트 0장 : 보드 I/O 는 C 가 초안 -> C 확인 필요)
#   LD0-1   system_state[1:0]     C
#   LD2-4   output_enable[2:0]    C
#   LD5     actuator_enable       C   <- AXI 로 못 읽는 신호
#   LD6     control_valid         C   <- AXI 로 못 읽는 신호
#   LD7-9   alive[2:0]            A
#   LD10-12 timeout[2:0]          A
#   LD13-14 fault_level[1:0]      B
#   LD15    fault_valid           B
#
# 사용법 : Vivado Tcl Console
#          source /home/user7/workspace_ondevice_3/SOC_Project/bd_led_out.tcl
#
# 주의 : 이 스크립트는 BD 에 top-level port `led[15:0]` 을 새로 만든다.
#        XDC 의 LED 16줄 주석을 반드시 같이 풀어야 synth 가 통과한다.
################################################################################

set HB   myip_heartbeat_monit_0
set FM   fault_manager_ip_0
set SC   safety_controller_0
set CAT  led_concat

set ::ok_cnt   0
set ::skip_cnt 0
set ::err_cnt  0

proc say {msg} { puts "  $msg" }

proc cat_connect {src idx label} {
    global CAT
    set pa [get_bd_pins -quiet $src]
    set pb [get_bd_pins -quiet /$CAT/In$idx]
    if {$pa eq "" || $pb eq ""} {
        say "\[FAIL\] In$idx $label : 핀 없음 ($src)"
        incr ::err_cnt
        return
    }
    set nb [get_bd_nets -quiet -of_objects $pb]
    if {$nb ne ""} {
        say "\[skip\] In$idx $label : 이미 연결됨"
        incr ::skip_cnt
        return
    }
    if {[catch {connect_bd_net $pa $pb} e]} {
        say "\[FAIL\] In$idx $label : $e"
        incr ::err_cnt
    } else {
        say "\[ ok \] In$idx $label"
        incr ::ok_cnt
    }
}

puts "=============================================================="
puts " bd_led_out.tcl  -  상태 출력 -> LED\[15:0\]"
puts "=============================================================="

if {[catch {current_bd_design} cur]} {
    puts "ERROR: BD 가 열려 있지 않다."
    return
}
puts "\n\[0\] 현재 BD : $cur"

#-------------------------------------------------------------------------------
# 1. LED 전용 xlconcat 생성
#
#    IRQ 용 microblaze_riscv_0_xlconcat 과는 별개다. 절대 그쪽을 건드리지 않는다
#    (04 체크리스트 8장 : IRQ 연결 순서 변경 금지).
#
#    xlconcat 은 In0 이 dout 의 LSB 다.
#      dout[1:0]=In0  dout[4:2]=In1  dout[5]=In2   dout[6]=In3
#      dout[9:7]=In4  dout[12:10]=In5 dout[14:13]=In6 dout[15]=In7
#-------------------------------------------------------------------------------
puts "\n\[1\] LED 전용 xlconcat 생성"
if {[get_bd_cells -quiet /$CAT] ne ""} {
    say "\[skip\] /$CAT 이미 있음"
    incr ::skip_cnt
} else {
    create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 $CAT
    say "\[ ok \] /$CAT 생성"
    incr ::ok_cnt
}
set_property -dict [list \
    CONFIG.NUM_PORTS {8} \
    CONFIG.IN0_WIDTH {2} \
    CONFIG.IN1_WIDTH {3} \
    CONFIG.IN2_WIDTH {1} \
    CONFIG.IN3_WIDTH {1} \
    CONFIG.IN4_WIDTH {3} \
    CONFIG.IN5_WIDTH {3} \
    CONFIG.IN6_WIDTH {2} \
    CONFIG.IN7_WIDTH {1} ] [get_bd_cells /$CAT]
say "\[ ok \] 폭 설정 2+3+1+1+3+3+2+1 = 16"

#-------------------------------------------------------------------------------
# 2. 상태 신호 -> concat
#-------------------------------------------------------------------------------
puts "\n\[2\] 상태 신호 -> concat"
cat_connect /$SC/system_state    0 "LD0-1   system_state\[1:0\]  (C)"
cat_connect /$SC/output_enable   1 "LD2-4   output_enable\[2:0\] (C)"
cat_connect /$SC/actuator_enable 2 "LD5     actuator_enable     (C)"
cat_connect /$SC/control_valid   3 "LD6     control_valid       (C)"
cat_connect /$HB/alive           4 "LD7-9   alive\[2:0\]         (A)"
cat_connect /$HB/timeout         5 "LD10-12 timeout\[2:0\]       (A)"
cat_connect /$FM/fault_level     6 "LD13-14 fault_level\[1:0\]   (B)"
cat_connect /$FM/fault_valid     7 "LD15    fault_valid         (B)"

#-------------------------------------------------------------------------------
# 3. top-level port led[15:0]
#-------------------------------------------------------------------------------
puts "\n\[3\] top-level port led\[15:0\]"
if {[get_bd_ports -quiet /led] ne ""} {
    say "\[skip\] led 포트 이미 있음"
    incr ::skip_cnt
} else {
    create_bd_port -dir O -from 15 -to 0 led
    say "\[ ok \] led\[15:0\] 생성"
    incr ::ok_cnt
}

set dp [get_bd_pins -quiet /$CAT/dout]
set lp [get_bd_ports -quiet /led]
if {[get_bd_nets -quiet -of_objects $lp] ne ""} {
    say "\[skip\] led 이미 연결됨"
    incr ::skip_cnt
} elseif {[catch {connect_bd_net $dp $lp} e]} {
    say "\[FAIL\] dout -> led : $e"
    incr ::err_cnt
} else {
    say "\[ ok \] $CAT/dout -> led\[15:0\]"
    incr ::ok_cnt
}

#-------------------------------------------------------------------------------
# 4. 남은 미연결 출력 확인
#-------------------------------------------------------------------------------
puts "\n\[4\] 남은 미연결 출력"
foreach pr [list "$HB/alive" "$SC/system_state" "$SC/output_enable" \
                 "$SC/actuator_enable" "$SC/control_valid" "$SC/state_timer"] {
    set n [get_bd_nets -quiet -of_objects [get_bd_pins -quiet /$pr]]
    puts [format "    %-38s : %s" $pr [expr {$n eq "" ? "미연결" : $n}]]
}
say ""
say "state_timer\[31:0\] 는 일부러 안 뺀다. LED 32개가 없고"
say "AXI STATE_TIMER(0x14) 로 그대로 읽힌다. 경고만 나고 문제 없다."

puts "\n\[5\] Validate + Save"
if {[catch {validate_bd_design} e]} {
    puts "  \[warn\] validate_bd_design 메시지 발생. Messages 창 확인."
    puts "  $e"
} else {
    puts "  \[ ok \] validate_bd_design 통과"
}
save_bd_design

puts "\n=============================================================="
puts " 완료 :  ok=$::ok_cnt  skip=$::skip_cnt  fail=$::err_cnt"
puts "=============================================================="
puts " 다음에 반드시 : XDC 의 led\[0\]~led\[15\] 16줄 주석 해제"
puts "                 (안 하면 synth 에서 unconstrained port 로 막힌다)"
puts ""
