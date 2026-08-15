# =============================================================================
# add_testbenches.tcl
#
# Heartbeat / Safety Controller 단위 Testbench 와 그 DUT RTL 을
# 시뮬레이션 파일셋(sim_1)에 등록한다.
#
# 사용법 : Vivado 에서 soc_project.xpr 을 연 뒤 Tcl Console 에
#     source /home/user7/workspace_ondevice_3/SOC_Project/add_testbenches.tcl
#
# -----------------------------------------------------------------------------
# 왜 RTL 도 같이 넣는가
#   단위 TB 를 시뮬레이션 top 으로 잡으면 Vivado 는 그 top 의 계층만 컴파일한다.
#   Block Design 은 아예 elaborate 되지 않으므로, IP 로 패키징된 모듈
#   (heartbeat_monitor_axi 등)은 컴파일 범위에 들어오지 않는다.
#   실제로 RTL 없이 돌리면 다음 에러가 난다.
#       ERROR: [VRFC 10-2063] Module <heartbeat_monitor_core> not found
#   fault_manager 는 예전에 raw RTL 이 sources_1/imports/rtl/ 에 등록돼 있어서
#   돌았던 것이고, heartbeat/safety 는 그게 없어서 실패했다.
#
# 왜 sources_1 이 아니라 sim_1 인가
#   sources_1 에 넣으면 UsedIn 에 synthesis/implementation 이 포함되어 BD 의
#   IP 사본과 모듈 이름이 겹칠 수 있다. 이미 정상 생성된 BIT/XSA 를 깨뜨릴
#   위험이 있으므로 시뮬레이션 전용으로만 등록한다.
#
# 왜 RTL 은 복사(import)하지 않고 참조(add)하는가
#   IP 패키지 원본을 그대로 가리켜야 한다. 복사본을 두면 나중에 RTL 을 고쳤을 때
#   시뮬레이션은 옛 사본을 보게 되어 "고친 줄 알았는데 안 고쳐진" 상황이 생긴다.
#   (이 프로젝트에서 fault_manager_axi.v 로 실제 겪은 문제다.)
# =============================================================================

set root    /home/user7/workspace_ondevice_3/SOC_Project
set tb_dir  $root/sim
set ip_repo $root/SOC_Pr/ip_repo

# ---- 1) Testbench : 프로젝트로 복사해서 등록 --------------------------------
set tb_files [list \
    $tb_dir/tb_heartbeat_monitor.v      \
    $tb_dir/tb_safety_controller_core.v \
    $tb_dir/tb_safety_controller_axi.v  \
]

# ---- 2) DUT RTL : 원본을 그대로 참조 ---------------------------------------
#   heartbeat_monitor.v        -> heartbeat_monitor_axi / _core / _channel
#   safety_controller.v        -> safety_controller_core
#   ..._slave_lite_..._S00_AXI -> safety_controller_axi (core 를 instantiate)
set rtl_files [list \
    $ip_repo/myip_heartbeat_monitor_1_0/src/heartbeat_monitor.v                     \
    $ip_repo/safety_controller_1_0/hdl/safety_controller.v                          \
    $ip_repo/safety_controller_1_0/hdl/safety_controller_slave_lite_v1_0_S00_AXI.v   \
]

# ---- 존재 확인 -------------------------------------------------------------
foreach f [concat $tb_files $rtl_files] {
    if {![file exists $f]} {
        puts "ERROR: 파일 없음 -> $f"
        return
    }
}

# ---- 등록 ------------------------------------------------------------------
# TB : 이미 들어가 있으면 -force 로 갱신
import_files -fileset sim_1 -norecurse -force $tb_files

# RTL : 참조 등록. 이미 있으면 add_files 가 조용히 넘어간다.
foreach f $rtl_files {
    if {[llength [get_files -quiet -of_objects [get_filesets sim_1] [file tail $f]]] == 0} {
        add_files -fileset sim_1 -norecurse $f
    }
}

# RTL 은 시뮬레이션에만 쓴다 (합성/구현에서 제외)
foreach f $rtl_files {
    set obj [get_files -quiet -of_objects [get_filesets sim_1] [file tail $f]]
    if {[llength $obj] > 0} {
        set_property used_in {simulation} $obj
    }
}

update_compile_order -fileset sim_1

puts ""
puts "== sim_1 에 등록된 파일 =="
foreach f [get_files -of_objects [get_filesets sim_1]] {
    puts [format "   %-52s used_in=%s" [file tail $f] [get_property used_in $f]]
}

puts ""
puts "== 다음 단계 =="
puts "   source $root/run_all_testbenches.tcl"
puts ""
