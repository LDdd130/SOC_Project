################################################################################
# bd_connect.tcl
#
# mission_soc Block Design 의 fault_manager_ip_0 미연결 핀을 채운다.
#
# 사용법 : Vivado 에서 mission_soc BD 를 연 상태로 Tcl Console 에
#          source /home/user7/workspace_ondevice_3/SOC_Project/bd_connect.tcl
#
# 하는 일
#   1. eval_tick_generator_0/reset  <- proc_sys_reset_0/peripheral_reset (ACTIVE HIGH)
#   2. eval_tick_generator_0/eval_tick -> fault_manager_ip_0/eval_tick
#   3. fault_manager_ip_0/irq -> xlconcat/In1
#   4. axi_gpio_0 (Dual, 3bit x2) -> error_flag / critical_fault
#   5. axi_gpio_1 (Single, 3bit)  -> timeout   (A 의 heartbeat_monitor_ip 오면 교체)
#   6. 주소 배정 / Validate / Save
#
# 근거 : 00 공통명세 5.2(공통 eval_tick), 5.4(Level IRQ), 8.3(외부 입력)
#        04 체크리스트 1.1(직접 연결 Freeze), 8장(IRQ 연결 순서 변경 금지)
################################################################################

set BD_NAME       mission_soc
set FM            fault_manager_ip_0
set ETG           eval_tick_generator_0
set PSR           proc_sys_reset_0
set XLC           microblaze_riscv_0_xlconcat
set INTERCONNECT  microblaze_riscv_0_axi_periph
set CPU_MASTER    "/microblaze_riscv_0 (Data)"
set CLK_SRC       "/clk_wiz/clk_out1 (100 MHz)"

set ::ok_cnt   0
set ::skip_cnt 0
set ::err_cnt  0

proc say {msg} { puts "  $msg" }

# 이미 연결돼 있으면 건너뛰고, 아니면 연결한다
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
        say "\[skip\] $label : 이미 연결됨 ($na)"
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

puts "=============================================================="
puts " bd_connect.tcl  -  $BD_NAME"
puts "=============================================================="

#-------------------------------------------------------------------------------
# 0. BD 열려 있는지 확인
#-------------------------------------------------------------------------------
if {[catch {current_bd_design} cur]} {
    puts "ERROR: BD 가 열려 있지 않다. Sources 에서 $BD_NAME.bd 를 먼저 열어라."
    return
}
puts "\n\[0\] 현재 BD : $cur"

#-------------------------------------------------------------------------------
# 1. eval_tick_generator reset  (ACTIVE HIGH 주의)
#
#    eval_tick_generator.v :  if (reset) begin ... end   <- active HIGH
#    peripheral_aresetn 을 물리면 평상시 1 로 리셋이 계속 걸려서
#    eval_tick 이 영영 안 나오고 Persist Count 가 안 올라간다 -> Level 2 실종.
#    이름에 n 이 없는 peripheral_reset 이 정답이다.
#-------------------------------------------------------------------------------
puts "\n\[1\] eval_tick_generator reset (ACTIVE HIGH)"

set rst_pin [get_bd_pins -quiet /$ETG/reset]
set cur_net [get_bd_nets -quiet -of_objects $rst_pin]
if {$cur_net ne "" && [string match "*aresetn*" $cur_net]} {
    say "잘못된 active-low 리셋 발견 : $cur_net  -> 끊는다"
    disconnect_bd_net $cur_net $rst_pin
}
net_connect /$PSR/peripheral_reset /$ETG/reset "reset <- peripheral_reset"

#-------------------------------------------------------------------------------
# 2. eval_tick  (00 공통명세 5.2 : B 와 C 가 같은 소스를 쓴다)
#-------------------------------------------------------------------------------
puts "\n\[2\] eval_tick"
net_connect /$ETG/eval_tick /$FM/eval_tick "eval_tick -> $FM"

# DIVISOR 확인 (100MHz -> 1ms)
set div [get_property -quiet CONFIG.DIVISOR [get_bd_cells -quiet /$ETG]]
if {$div ne "" && $div != 100000} {
    say "\[warn\] DIVISOR=$div (권장 100000 = 1ms @100MHz)"
} else {
    say "\[ ok \] DIVISOR=100000 (1ms @100MHz)"
}

#-------------------------------------------------------------------------------
# 3. irq -> xlconcat
#
#    04 체크리스트 8장 : IRQ 연결 순서는 한 번 정하면 변경 금지.
#      In0 = axi_uartlite_0/interrupt      (이미 연결됨)
#      In1 = fault_manager_ip_0/irq        <- 여기
#      In2 = heartbeat_monitor_ip/irq      (A 자리, 나중에 NUM_PORTS 늘려서)
#      In3 = safety_controller_ip/irq      (C 자리)
#
#    지금 NUM_PORTS 를 4 로 늘리면 In2/In3 가 떠서 Validate 경고가 난다.
#    A/C 가 올 때 늘리는 편이 깔끔해서 2 로 둔다.
#-------------------------------------------------------------------------------
puts "\n\[3\] irq -> xlconcat/In1"
net_connect /$FM/irq /$XLC/In1 "irq -> In1"

#-------------------------------------------------------------------------------
# 4. AXI GPIO 추가 : error_flag / critical_fault / timeout
#
#    00 공통명세 8.3 : error_flag, critical_fault 는 외부/Simulator 입력.
#    04 1.1 : A/C 를 거치지 않고 fault_manager_ip 로 직결.
#    보드 스위치로 뺄 수도 있으나 00 12.3 이 2FF Synchronizer 를 요구하므로
#    지금은 GPIO 로 받는다. MicroBlaze 에서 Fault Injection 하기도 편하다.
#-------------------------------------------------------------------------------
puts "\n\[4\] AXI GPIO 추가"

proc add_gpio {name dual} {
    if {[get_bd_cells -quiet /$name] ne ""} {
        say "\[skip\] $name 이미 있음"
        return
    }
    create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio $name
    set props [list CONFIG.C_GPIO_WIDTH {3} CONFIG.C_ALL_OUTPUTS {1}]
    if {$dual} {
        lappend props CONFIG.C_IS_DUAL {1} \
                      CONFIG.C_GPIO2_WIDTH {3} CONFIG.C_ALL_OUTPUTS_2 {1}
    } else {
        lappend props CONFIG.C_IS_DUAL {0}
    }
    set_property -dict $props [get_bd_cells /$name]
    say "\[ ok \] $name 생성 (width=3, all outputs, dual=$dual)"
}

add_gpio axi_gpio_0 1   ;# error_flag + critical_fault
add_gpio axi_gpio_1 0   ;# timeout (임시)

# --- S_AXI 자동 연결 (Interconnect 마스터 포트 증설 + clk/reset 포함) ---
proc axi_auto {slave_pin} {
    global CPU_MASTER CLK_SRC INTERCONNECT
    set ip [get_bd_intf_pins -quiet $slave_pin]
    if {$ip eq ""} { say "\[FAIL\] $slave_pin 없음" ; incr ::err_cnt ; return }
    if {[get_bd_intf_nets -quiet -of_objects $ip] ne ""} {
        say "\[skip\] $slave_pin 이미 AXI 연결됨"
        incr ::skip_cnt
        return
    }
    if {[catch {
        apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config \
            [list Clk_master $CLK_SRC Clk_slave {Auto} Clk_xbar {Auto} \
                  Master $CPU_MASTER Slave $slave_pin ddr_seg {Auto} \
                  intc_ip "/$INTERCONNECT" master_apm {0}] $ip
    } e]} {
        say "\[FAIL\] $slave_pin AXI 자동연결 : $e"
        say "        -> GUI 에서 Run Connection Automation 으로 이 슬레이브만 처리해라"
        incr ::err_cnt
    } else {
        say "\[ ok \] $slave_pin AXI 연결"
        incr ::ok_cnt
    }
}

axi_auto /axi_gpio_0/S_AXI
axi_auto /axi_gpio_1/S_AXI

# --- GPIO 출력 -> fault_manager 입력 ---
puts "\n\[5\] GPIO -> fault_manager_ip_0 입력"
net_connect /axi_gpio_0/gpio_io_o  /$FM/error_flag     "error_flag    <- axi_gpio_0 CH1"
net_connect /axi_gpio_0/gpio2_io_o /$FM/critical_fault "critical_fault<- axi_gpio_0 CH2"
net_connect /axi_gpio_1/gpio_io_o  /$FM/timeout        "timeout       <- axi_gpio_1 (임시)"

#-------------------------------------------------------------------------------
# 6. 주소 배정 / Validate / Save
#-------------------------------------------------------------------------------
puts "\n\[6\] 주소 배정"
if {[catch {assign_bd_address} e]} {
    say "\[warn\] assign_bd_address : $e"
} else {
    say "\[ ok \] assign_bd_address"
}

puts "\n\[7\] 연결 상태 최종 확인"
foreach p {timeout error_flag critical_fault eval_tick irq s00_axi_aclk s00_axi_aresetn} {
    set n [get_bd_nets -quiet -of_objects [get_bd_pins -quiet /$FM/$p]]
    if {$n eq ""} {
        puts [format "  %-16s : %s" $p "*** 미연결 ***"]
    } else {
        puts [format "  %-16s : %s" $p $n]
    }
}
set n [get_bd_nets -quiet -of_objects [get_bd_pins -quiet /$ETG/reset]]
puts [format "  %-16s : %s" "ETG reset" [expr {$n eq "" ? "*** 미연결 ***" : $n}]]
if {[string match "*aresetn*" $n]} {
    puts "  ^^^ 경고 : active-low 리셋이다. peripheral_reset 으로 바꿔야 eval_tick 이 나온다."
}

puts "\n\[8\] fault_manager_ip_0 주소"
foreach seg [get_bd_addr_segs -quiet -of_objects [get_bd_cells /$FM]] {
    puts "  $seg  offset=[get_property -quiet OFFSET $seg]  range=[get_property -quiet RANGE $seg]"
}

puts "\n\[9\] Validate + Save"
if {[catch {validate_bd_design} e]} {
    puts "  \[warn\] validate_bd_design 에서 메시지 발생. Messages 창을 확인해라."
}
save_bd_design

puts "\n=============================================================="
puts " 완료 :  ok=$::ok_cnt  skip=$::skip_cnt  fail=$::err_cnt"
puts "=============================================================="
if {$::err_cnt > 0} {
    puts " fail 항목은 GUI 에서 수동 연결해라."
} else {
    puts " 다음 : Create HDL Wrapper -> Generate Bitstream -> Export Hardware(XSA)"
}
puts ""
