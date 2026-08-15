################################################################################
# bd_connect_ac.tcl
#
# mission_soc Block Design 에 A(heartbeat_monitor) / C(safety_controller) 를 붙인다.
#
# 사용법 : Vivado 에서 mission_soc BD 를 연 상태로 Tcl Console 에
#          source /home/user7/workspace_ondevice_3/SOC_Project/bd_connect_ac.tcl
#
# 전제 : myip_heartbeat_monit_0, safety_controller_0 셀이 BD 에 이미 올라가 있고
#        BD 가 저장돼 있다. (Add IP 만 한 상태)
#
# 하는 일
#   1. 두 IP 의 S00_AXI 를 Interconnect 에 붙인다 (NUM_MI 5->7, clk/reset 포함)
#   2. timeout 경로 교체  ← 04 체크리스트 1.1 직접 연결 Freeze
#        (구) axi_gpio_1/gpio_io_o        -> fault_manager_ip_0/timeout   [끊는다]
#        (신) myip_heartbeat_monit_0/timeout -> fault_manager_ip_0/timeout
#        (신) axi_gpio_1/gpio_io_o        -> myip_heartbeat_monit_0/heartbeat_async
#   3. fault_manager_ip_0 -> safety_controller_0 (level / device / code / valid)
#   4. 공통 eval_tick -> safety_controller_0
#   5. irq -> xlconcat In2(A) / In3(C)
#   6. 금지 연결 검사 / 주소 배정 / Validate / Save
#
# 근거 : 00 공통명세 2장(전체 구조), 5.2(공통 eval_tick), 8.2(A->B),
#                    8.4(eval_tick), 8.5(B->C)
#        04 체크리스트 1.1(직접 연결 Freeze), 8장(IRQ 연결 순서 변경 금지)
################################################################################

set BD_NAME       mission_soc
set FM            fault_manager_ip_0
set HB            myip_heartbeat_monit_0
set SC            safety_controller_0
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

# S_AXI 자동 연결 (Interconnect 마스터 포트 증설 + clk/reset 포함)
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

puts "=============================================================="
puts " bd_connect_ac.tcl  -  $BD_NAME  (A + C 통합)"
puts "=============================================================="

#-------------------------------------------------------------------------------
# 0. 전제 확인
#-------------------------------------------------------------------------------
if {[catch {current_bd_design} cur]} {
    puts "ERROR: BD 가 열려 있지 않다. Sources 에서 $BD_NAME.bd 를 먼저 열어라."
    return
}
puts "\n\[0\] 현재 BD : $cur"

set missing 0
foreach c [list $FM $HB $SC $ETG $XLC $INTERCONNECT] {
    if {[get_bd_cells -quiet /$c] eq ""} {
        puts "  ERROR: 셀 없음 -> /$c"
        set missing 1
    }
}
if {$missing} {
    puts "  Add IP 로 먼저 셀을 올려라. 중단한다."
    return
}
say "\[ ok \] 필요한 셀 전부 있음"

#-------------------------------------------------------------------------------
# 1. AXI4-Lite  (00 공통명세 2장 : 각 Custom IP -- AXI4-Lite -- MicroBlaze)
#
#    Interconnect NUM_MI 가 5 -> 7 로 자동 증설되고
#    M05/M06 의 ACLK/ARESETN, IP 쪽 aclk/aresetn 까지 automation 이 채운다.
#-------------------------------------------------------------------------------
puts "\n\[1\] AXI4-Lite 슬레이브 추가"
axi_auto /$HB/S00_AXI
axi_auto /$SC/S00_AXI

#-------------------------------------------------------------------------------
# 2. timeout 경로 교체  (04 체크리스트 1.1 직접 연결 Freeze)
#
#    heartbeat_async -> heartbeat_monitor_ip -> timeout -> fault_manager_ip
#
#    지금까지는 A 의 IP 가 없어서 axi_gpio_1 로 timeout 을 직접 주입했다.
#    A 가 왔으므로 그 임시 경로는 반드시 끊는다. 안 끊으면
#    "출력 2개가 한 net 을 구동" 이 되어 validate_bd_design 이 에러를 낸다.
#
#    비워진 axi_gpio_1 은 heartbeat 주입용으로 재사용한다.
#    heartbeat_monitor_channel 이 2FF Sync + Rising Edge Detector 를 내장하므로
#    MicroBlaze 가 GPIO 비트를 0->1 로 토글하면 그게 heartbeat 1회다.
#-------------------------------------------------------------------------------
puts "\n\[2\] timeout 경로 교체 (임시 GPIO -> heartbeat_monitor)"

set fm_to_pin [get_bd_pins -quiet /$FM/timeout]
set cur_net   [get_bd_nets -quiet -of_objects $fm_to_pin]
if {$cur_net ne ""} {
    set on_net [get_bd_pins -quiet -of_objects $cur_net]
    if {[lsearch -glob $on_net "*$HB/timeout"] >= 0} {
        say "\[skip\] timeout 이 이미 $HB 에서 온다"
        incr ::skip_cnt
    } else {
        say "임시 경로 발견 : $cur_net  -> $FM/timeout 에서 끊는다"
        if {[catch {disconnect_bd_net $cur_net $fm_to_pin} e]} {
            say "\[FAIL\] disconnect : $e"
            incr ::err_cnt
        }
    }
}

net_connect /$HB/timeout        /$FM/timeout          "timeout        : $HB -> $FM"
net_connect /axi_gpio_1/gpio_io_o /$HB/heartbeat_async "heartbeat_async: axi_gpio_1 CH1 -> $HB"

#-------------------------------------------------------------------------------
# 3. fault_manager_ip -> safety_controller_ip  (00 공통명세 8.5)
#
#    fault_valid 는 Level 신호다. Count Tick 으로 쓰지 않는다.
#-------------------------------------------------------------------------------
puts "\n\[3\] Fault 상태 : $FM -> $SC"
net_connect /$FM/fault_level  /$SC/fault_level  "fault_level\[1:0\]"
net_connect /$FM/fault_device /$SC/fault_device "fault_device\[1:0\]"
net_connect /$FM/fault_code   /$SC/fault_code   "fault_code\[7:0\]"
net_connect /$FM/fault_valid  /$SC/fault_valid  "fault_valid"

#-------------------------------------------------------------------------------
# 4. 공통 eval_tick  (00 공통명세 5.2 / 8.4)
#
#    B 와 C 가 반드시 같은 소스를 써야 PERSIST_LIMIT 와 RECOVERY_COUNT 의
#    시간 단위가 일치한다. (RECOVERY_COUNT < PERSIST_LIMIT 조건의 전제)
#-------------------------------------------------------------------------------
puts "\n\[4\] 공통 eval_tick -> $SC"
net_connect /$ETG/eval_tick /$SC/eval_tick "eval_tick -> $SC"

set div [get_property -quiet CONFIG.DIVISOR [get_bd_cells -quiet /$ETG]]
if {$div ne "" && $div != 100000} {
    say "\[warn\] DIVISOR=$div (권장 100000 = 1ms @100MHz)"
} else {
    say "\[ ok \] DIVISOR=100000 (1ms @100MHz)"
}

#-------------------------------------------------------------------------------
# 5. IRQ -> xlconcat   (04 체크리스트 8장 : 이 순서는 이후 변경 금지)
#
#      In0 = axi_uartlite_0/interrupt        (연결됨)
#      In1 = fault_manager_ip_0/irq          (연결됨, XIntc ID 1)
#      In2 = myip_heartbeat_monit_0/irq      <- 여기 (XIntc ID 2)
#      In3 = safety_controller_0/irq         <- 여기 (XIntc ID 3)
#-------------------------------------------------------------------------------
puts "\n\[5\] IRQ -> xlconcat"
set np [get_property -quiet CONFIG.NUM_PORTS [get_bd_cells /$XLC]]
say "xlconcat NUM_PORTS = $np"
if {$np < 4} {
    set_property CONFIG.NUM_PORTS {4} [get_bd_cells /$XLC]
    say "\[ ok \] NUM_PORTS 4 로 증설"
}
net_connect /$HB/irq /$XLC/In2 "In2 <- $HB/irq   (XIntc ID 2)"
net_connect /$SC/irq /$XLC/In3 "In3 <- $SC/irq   (XIntc ID 3)"

#-------------------------------------------------------------------------------
# 6. 금지 연결 검사  (04 체크리스트 1.1)
#
#    금지 1 : heartbeat_monitor_ip.alive -> fault_manager_ip
#             alive 는 LED / MicroBlaze 표시용이다. Fault 판단에 쓰지 않는다.
#    금지 2 : safety_controller_ip.output_enable -> heartbeat_monitor_ip.device_enable
#             device_enable 은 감시 설정이고 output_enable 은 출력 차단이다.
#             A 의 IP 는 device_enable 을 3'b111 로 내부 고정했으므로 포트 자체가 없다.
#-------------------------------------------------------------------------------
puts "\n\[6\] 금지 연결 검사"

set alive_net [get_bd_nets -quiet -of_objects [get_bd_pins -quiet /$HB/alive]]
if {$alive_net eq ""} {
    say "\[ ok \] alive 미연결 (LED 로 뺄지는 팀 결정 사항)"
} else {
    set on_net [get_bd_pins -quiet -of_objects $alive_net]
    if {[lsearch -glob $on_net "*$FM/*"] >= 0} {
        say "\[FAIL\] 금지 연결 : alive 가 $FM 에 붙어 있다. 끊어라."
        incr ::err_cnt
    } else {
        say "\[ ok \] alive 가 $FM 에 붙어 있지 않음"
    }
}

if {[get_bd_pins -quiet /$HB/device_enable] eq ""} {
    say "\[ ok \] device_enable 포트 없음 (내부 3'b111 고정) -> 금지 연결 불가능"
} else {
    say "\[warn\] device_enable 포트가 있다. output_enable 을 절대 붙이지 마라."
}

#-------------------------------------------------------------------------------
# 7. 주소 배정
#-------------------------------------------------------------------------------
puts "\n\[7\] 주소 배정"
if {[catch {assign_bd_address} e]} {
    say "\[warn\] assign_bd_address : $e"
} else {
    say "\[ ok \] assign_bd_address"
}

#-------------------------------------------------------------------------------
# 8. 연결 상태 최종 확인
#-------------------------------------------------------------------------------
proc show_pin {cell pin} {
    set n [get_bd_nets -quiet -of_objects [get_bd_pins -quiet /$cell/$pin]]
    if {$n eq ""} {
        puts [format "    %-18s : %s" $pin "*** 미연결 ***"]
    } else {
        puts [format "    %-18s : %s" $pin $n]
    }
}

puts "\n\[8\] 연결 상태"
puts "  --- $HB (A) ---"
foreach p {heartbeat_async timeout alive irq s00_axi_aclk s00_axi_aresetn} { show_pin $HB $p }
puts "  --- $FM (B) ---"
foreach p {timeout error_flag critical_fault eval_tick fault_level fault_device fault_code fault_valid irq} { show_pin $FM $p }
puts "  --- $SC (C) ---"
foreach p {fault_level fault_device fault_code fault_valid eval_tick system_state output_enable actuator_enable control_valid irq S_AXI_ACLK S_AXI_ARESETN} { show_pin $SC $p }

puts "\n\[9\] 주소 맵 (Vitis xparameters.h 가 이 값으로 바뀐다)"
foreach c [list $HB $FM $SC] {
    foreach seg [get_bd_addr_segs -quiet -of_objects [get_bd_cells /$c]] {
        puts [format "    %-24s offset=%s range=%s" $c \
              [get_property -quiet OFFSET $seg] [get_property -quiet RANGE $seg]]
    }
}

#-------------------------------------------------------------------------------
# 9. Validate + Save
#-------------------------------------------------------------------------------
puts "\n\[10\] Validate + Save"
if {[catch {validate_bd_design} e]} {
    puts "  \[warn\] validate_bd_design 메시지 발생. Messages 창을 확인해라."
    puts "  $e"
}
save_bd_design

puts "\n=============================================================="
puts " 완료 :  ok=$::ok_cnt  skip=$::skip_cnt  fail=$::err_cnt"
puts "=============================================================="
if {$::err_cnt > 0} {
    puts " fail 항목은 GUI 에서 수동 연결해라."
} else {
    puts " 다음 : Generate Output Products -> Generate Bitstream"
    puts "        -> Export Hardware (include bitstream) -> Vitis 플랫폼 갱신"
}
puts ""
