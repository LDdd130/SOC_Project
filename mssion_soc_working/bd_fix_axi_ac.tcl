################################################################################
# bd_fix_axi_ac.tcl
#
# bd_connect_ac.tcl 에서 실패한 [1] AXI4-Lite 부분만 수동으로 채운다.
#
# 실패 원인
#   apply_bd_automation 의 Master 문자열 "/microblaze_riscv_0 (Data)" 가 틀렸다.
#   이 MicroBlaze RISC-V 의 마스터 포트는 M_AXI_DP 라서 automation 이름은
#   "(Periph)" 다. 문자열 추측 대신 Interconnect 포트를 직접 연결한다.
#   기존 M02(fault_manager) / M03(gpio0) / M04(gpio1) 과 똑같은 패턴이다.
#
# 하는 일
#   1. Interconnect NUM_MI 5 -> 7
#   2. M05_AXI -> myip_heartbeat_monit_0/S00_AXI
#      M06_AXI -> safety_controller_0/S00_AXI
#   3. M05/M06 의 ACLK, ARESETN 연결
#   4. 두 IP 의 aclk / aresetn 연결
#   5. 주소 배정 -> Validate -> Save
#
# 사용법 : Vivado Tcl Console
#          source /home/user7/workspace_ondevice_3/SOC_Project/bd_fix_axi_ac.tcl
################################################################################

set HB    myip_heartbeat_monit_0
set SC    safety_controller_0
set ICN   microblaze_riscv_0_axi_periph
set CLK   /clk_wiz/clk_out1
set ARSTN /proc_sys_reset_0/peripheral_aresetn

set ::ok_cnt  0
set ::skip_cnt 0
set ::err_cnt 0

proc say {msg} { puts "  $msg" }

proc net_connect {a b label} {
    set pa [get_bd_pins -quiet $a]
    set pb [get_bd_pins -quiet $b]
    if {$pa eq "" || $pb eq ""} {
        say "\[FAIL\] $label : 핀 없음 ($a / $b)"
        incr ::err_cnt
        return
    }
    set na [get_bd_nets -quiet -of_objects $pa]
    set nb [get_bd_nets -quiet -of_objects $pb]
    if {$na ne "" && $na eq $nb} {
        say "\[skip\] $label : 이미 연결됨"
        incr ::skip_cnt
        return
    }
    if {[catch {connect_bd_net $pa $pb} e]} {
        say "\[FAIL\] $label : $e"
        incr ::err_cnt
    } else {
        say "\[ ok \] $label"
        incr ::ok_cnt
    }
}

proc intf_connect {a b label} {
    set pa [get_bd_intf_pins -quiet $a]
    set pb [get_bd_intf_pins -quiet $b]
    if {$pa eq "" || $pb eq ""} {
        say "\[FAIL\] $label : 인터페이스 핀 없음 ($a / $b)"
        incr ::err_cnt
        return
    }
    if {[get_bd_intf_nets -quiet -of_objects $pb] ne ""} {
        say "\[skip\] $label : 이미 연결됨"
        incr ::skip_cnt
        return
    }
    if {[catch {connect_bd_intf_net $pa $pb} e]} {
        say "\[FAIL\] $label : $e"
        incr ::err_cnt
    } else {
        say "\[ ok \] $label"
        incr ::ok_cnt
    }
}

puts "=============================================================="
puts " bd_fix_axi_ac.tcl  -  A/C AXI4-Lite 수동 연결"
puts "=============================================================="

if {[catch {current_bd_design} cur]} {
    puts "ERROR: BD 가 열려 있지 않다."
    return
}
puts "\n\[0\] 현재 BD : $cur"

#-------------------------------------------------------------------------------
# 1. Interconnect 마스터 포트 증설
#-------------------------------------------------------------------------------
puts "\n\[1\] Interconnect NUM_MI 증설"
set nmi [get_property CONFIG.NUM_MI [get_bd_cells /$ICN]]
say "현재 NUM_MI = $nmi"
if {$nmi < 7} {
    set_property CONFIG.NUM_MI {7} [get_bd_cells /$ICN]
    say "\[ ok \] NUM_MI 7 로 증설 (M05, M06 생성)"
    incr ::ok_cnt
} else {
    say "\[skip\] 이미 7 이상"
    incr ::skip_cnt
}

#-------------------------------------------------------------------------------
# 2. AXI 인터페이스 연결
#-------------------------------------------------------------------------------
puts "\n\[2\] AXI4-Lite 인터페이스"
intf_connect /$ICN/M05_AXI /$HB/S00_AXI "M05_AXI -> $HB/S00_AXI"
intf_connect /$ICN/M06_AXI /$SC/S00_AXI "M06_AXI -> $SC/S00_AXI"

#-------------------------------------------------------------------------------
# 3. Interconnect 쪽 clk / reset
#    (M05/M06 은 새로 생겼으므로 반드시 직접 물려야 BD 41-758 이 사라진다)
#-------------------------------------------------------------------------------
puts "\n\[3\] Interconnect M05/M06 clk/reset"
net_connect $CLK   /$ICN/M05_ACLK    "M05_ACLK"
net_connect $CLK   /$ICN/M06_ACLK    "M06_ACLK"
net_connect $ARSTN /$ICN/M05_ARESETN "M05_ARESETN"
net_connect $ARSTN /$ICN/M06_ARESETN "M06_ARESETN"

#-------------------------------------------------------------------------------
# 4. IP 쪽 clk / reset
#    포트 이름이 A 와 C 가 다르다.
#      A : s00_axi_aclk / s00_axi_aresetn
#      C : S_AXI_ACLK   / S_AXI_ARESETN
#    둘 다 ACTIVE_LOW 리셋이므로 peripheral_aresetn 이 맞다.
#    (eval_tick_generator 만 ACTIVE_HIGH 라 peripheral_reset 을 쓴다 - 건드리지 않는다)
#-------------------------------------------------------------------------------
puts "\n\[4\] IP clk/reset"
net_connect $CLK   /$HB/s00_axi_aclk    "$HB/s00_axi_aclk"
net_connect $ARSTN /$HB/s00_axi_aresetn "$HB/s00_axi_aresetn"
net_connect $CLK   /$SC/S_AXI_ACLK      "$SC/S_AXI_ACLK"
net_connect $ARSTN /$SC/S_AXI_ARESETN   "$SC/S_AXI_ARESETN"

#-------------------------------------------------------------------------------
# 5. 주소 배정
#-------------------------------------------------------------------------------
puts "\n\[5\] 주소 배정"
if {[catch {assign_bd_address} e]} {
    say "\[warn\] assign_bd_address : $e"
} else {
    say "\[ ok \] assign_bd_address"
}

puts "\n\[6\] 주소 맵 (Vitis xparameters.h 가 이 값으로 바뀐다)"
foreach seg [get_bd_addr_segs -quiet -of_objects [get_bd_addr_spaces /microblaze_riscv_0/Data]] {
    puts [format "    %-46s offset=%s range=%s" $seg \
          [get_property -quiet OFFSET $seg] [get_property -quiet RANGE $seg]]
}

#-------------------------------------------------------------------------------
# 6. 미연결 clk/reset 최종 확인
#-------------------------------------------------------------------------------
puts "\n\[7\] clk/reset 확인"
foreach pr [list "$HB/s00_axi_aclk" "$HB/s00_axi_aresetn" \
                 "$SC/S_AXI_ACLK"   "$SC/S_AXI_ARESETN"   \
                 "$ICN/M05_ACLK" "$ICN/M05_ARESETN" \
                 "$ICN/M06_ACLK" "$ICN/M06_ARESETN"] {
    set n [get_bd_nets -quiet -of_objects [get_bd_pins -quiet /$pr]]
    puts [format "    %-42s : %s" $pr [expr {$n eq "" ? "*** 미연결 ***" : $n}]]
}

puts "\n\[8\] Validate + Save"
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
puts ""
