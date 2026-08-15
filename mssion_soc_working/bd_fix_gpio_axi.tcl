################################################################################
# bd_fix_gpio_axi.tcl
#
# bd_connect.tcl 에서 실패한 2건을 처리한다.
#   - apply_bd_automation 의 Master 문자열이 microblaze_riscv 에서 안 먹혔다.
#     자동화 대신 AXI Interconnect 마스터 포트를 직접 증설해서 붙인다.
#   - validate 에서 뜬 BD 41-758 (clk 미연결) 도 같이 해결한다.
#
# 현재 Interconnect : NUM_MI=3
#   M00 -> microblaze_riscv_0_axi_intc
#   M01 -> axi_uartlite_0
#   M02 -> fault_manager_ip_0
# 여기에 M03, M04 를 늘려 axi_gpio_0 / axi_gpio_1 을 붙인다.
#
# 사용법 : mission_soc BD 를 연 상태로 Tcl Console 에
#          source /home/user7/workspace_ondevice_3/SOC_Project/bd_fix_gpio_axi.tcl
################################################################################

set ICN microblaze_riscv_0_axi_periph
set FM  fault_manager_ip_0
set ETG eval_tick_generator_0

set ::ok_cnt 0
set ::skip_cnt 0
set ::err_cnt 0
proc say {m} { puts "  $m" }

puts "=============================================================="
puts " bd_fix_gpio_axi.tcl"
puts "=============================================================="

if {[catch {current_bd_design} cur]} {
    puts "ERROR: BD 가 열려 있지 않다."
    return
}

#-------------------------------------------------------------------------------
# 공용 net 찾기 (이름 하드코딩 대신 드라이버 핀에서 역추적)
#-------------------------------------------------------------------------------
set CLKNET [get_bd_nets -quiet -of_objects [get_bd_pins -quiet /clk_wiz/clk_out1]]
set RSTNET [get_bd_nets -quiet -of_objects [get_bd_pins -quiet /proc_sys_reset_0/peripheral_aresetn]]

puts "\n\[0\] 공용 net"
say "clock  : $CLKNET"
say "aresetn: $RSTNET"
if {$CLKNET eq "" || $RSTNET eq ""} {
    puts "ERROR: 공용 clk/reset net 을 못 찾았다. 중단."
    return
}

# 기존 net 에 핀 하나 더 물리기
proc join_net {net pin label} {
    set p [get_bd_pins -quiet $pin]
    if {$p eq ""} { say "\[FAIL\] $label : 핀 없음 ($pin)" ; incr ::err_cnt ; return }
    set cn [get_bd_nets -quiet -of_objects $p]
    if {$cn ne ""} {
        if {$cn eq $net} { say "\[skip\] $label : 이미 연결됨" ; incr ::skip_cnt ; return }
        say "\[FAIL\] $label : 다른 net 에 물려 있음 ($cn)" ; incr ::err_cnt ; return
    }
    if {[catch {connect_bd_net -net [get_bd_nets $net] $p} e]} {
        say "\[FAIL\] $label : $e" ; incr ::err_cnt
    } else {
        say "\[ ok \] $label" ; incr ::ok_cnt
    }
}

proc intf_connect {a b label} {
    set pa [get_bd_intf_pins -quiet $a]
    set pb [get_bd_intf_pins -quiet $b]
    if {$pa eq "" || $pb eq ""} { say "\[FAIL\] $label : 인터페이스 핀 없음" ; incr ::err_cnt ; return }
    if {[get_bd_intf_nets -quiet -of_objects $pb] ne ""} {
        say "\[skip\] $label : 이미 연결됨" ; incr ::skip_cnt ; return
    }
    if {[catch {connect_bd_intf_net $pa $pb} e]} {
        say "\[FAIL\] $label : $e" ; incr ::err_cnt
    } else {
        say "\[ ok \] $label" ; incr ::ok_cnt
    }
}

#-------------------------------------------------------------------------------
# 1. eval_tick_generator clk  (BD 41-758 원인 중 하나)
#-------------------------------------------------------------------------------
puts "\n\[1\] eval_tick_generator clk"
join_net $CLKNET /$ETG/clk "clk <- clk_out1"

#-------------------------------------------------------------------------------
# 2. Interconnect 마스터 포트 증설  3 -> 5
#-------------------------------------------------------------------------------
puts "\n\[2\] Interconnect 마스터 증설"
set icn_cell [get_bd_cells /$ICN]
set cur_mi [get_property CONFIG.NUM_MI $icn_cell]
say "현재 NUM_MI = $cur_mi"
if {$cur_mi < 5} {
    set_property CONFIG.NUM_MI {5} $icn_cell
    say "\[ ok \] NUM_MI = 5 로 변경 (M03, M04 생성)"
    incr ::ok_cnt
} else {
    say "\[skip\] 이미 $cur_mi 개"
    incr ::skip_cnt
}

#-------------------------------------------------------------------------------
# 3. M03 -> axi_gpio_0 , M04 -> axi_gpio_1
#    각 마스터 포트의 ACLK/ARESETN 도 같이 물려야 한다.
#-------------------------------------------------------------------------------
puts "\n\[3\] GPIO AXI 연결"

intf_connect /$ICN/M03_AXI /axi_gpio_0/S_AXI "M03_AXI -> axi_gpio_0"
join_net $CLKNET /$ICN/M03_ACLK    "M03_ACLK"
join_net $RSTNET /$ICN/M03_ARESETN "M03_ARESETN"

intf_connect /$ICN/M04_AXI /axi_gpio_1/S_AXI "M04_AXI -> axi_gpio_1"
join_net $CLKNET /$ICN/M04_ACLK    "M04_ACLK"
join_net $RSTNET /$ICN/M04_ARESETN "M04_ARESETN"

#-------------------------------------------------------------------------------
# 4. GPIO 자신의 clk / reset
#-------------------------------------------------------------------------------
puts "\n\[4\] GPIO clk / reset"
foreach g {axi_gpio_0 axi_gpio_1} {
    join_net $CLKNET /$g/s_axi_aclk    "$g/s_axi_aclk"
    join_net $RSTNET /$g/s_axi_aresetn "$g/s_axi_aresetn"
}

#-------------------------------------------------------------------------------
# 5. 주소 배정
#-------------------------------------------------------------------------------
puts "\n\[5\] 주소 배정"
if {[catch {assign_bd_address} e]} {
    say "\[warn\] $e"
} else {
    say "\[ ok \] assign_bd_address"
}

#-------------------------------------------------------------------------------
# 6. 최종 확인
#-------------------------------------------------------------------------------
puts "\n\[6\] fault_manager_ip_0 핀 연결"
foreach p {timeout error_flag critical_fault eval_tick irq s00_axi_aclk s00_axi_aresetn} {
    set n [get_bd_nets -quiet -of_objects [get_bd_pins -quiet /$FM/$p]]
    puts [format "  %-16s : %s" $p [expr {$n eq "" ? "*** 미연결 ***" : $n}]]
}
set n [get_bd_nets -quiet -of_objects [get_bd_pins -quiet /$ETG/reset]]
puts [format "  %-16s : %s" "ETG reset" [expr {$n eq "" ? "*** 미연결 ***" : $n}]]
if {[string match "*aresetn*" $n]} { puts "  ^^^ 경고 : active-low 다. eval_tick 안 나온다." }
set n [get_bd_nets -quiet -of_objects [get_bd_pins -quiet /$ETG/clk]]
puts [format "  %-16s : %s" "ETG clk" [expr {$n eq "" ? "*** 미연결 ***" : $n}]]

puts "\n\[7\] 주소 맵"
foreach seg [get_bd_addr_segs -quiet [current_bd_design]/*] { }
foreach c {fault_manager_ip_0 axi_gpio_0 axi_gpio_1 axi_uartlite_0 microblaze_riscv_0_axi_intc} {
    foreach seg [get_bd_addr_segs -quiet -of_objects [get_bd_cells -quiet /$c]] {
        set off [get_property -quiet OFFSET $seg]
        set rng [get_property -quiet RANGE  $seg]
        puts [format "  %-28s offset=%-12s range=%s" $c $off $rng]
    }
}

puts "\n\[8\] Validate + Save"
set vfail 0
if {[catch {validate_bd_design} e]} { set vfail 1 }
save_bd_design

puts "\n=============================================================="
puts " 완료 :  ok=$::ok_cnt  skip=$::skip_cnt  fail=$::err_cnt"
if {$vfail} {
    puts " validate 에서 메시지 있음 -> Messages 창 확인"
} else {
    puts " validate 통과"
    puts " 다음 : Create HDL Wrapper -> Generate Bitstream -> Export Hardware(XSA)"
}
puts "=============================================================="
puts ""
