# =============================================================================
# run_one_testbench.tcl
#
# 시뮬레이션 top 을 하나만 돌린다.
#
# 4개를 한 세션에서 연속 실행하면 xsim 스냅샷과 파형 DB 가 계속 쌓여
# 메모리가 터진다(이 PC 는 RAM 15GB, Vivado peak 8.7GB, 실측 free 508MB 에서
# 크래시했다). 그래서 반드시 하나씩 돌린다.
#
# 사용법 : Tcl Console 에서 top 을 정하고 source 한다.
#
#     set tb_top tb_heartbeat_monitor_core
#     source /home/user7/workspace_ondevice_3/SOC_Project/run_one_testbench.tcl
#
# 돌릴 top 4개 (하나 끝나면 다음 것으로) :
#     tb_heartbeat_monitor_core
#     tb_heartbeat_monitor_axi
#     tb_safety_controller_core
#     tb_safety_controller_axi
# =============================================================================

if {![info exists tb_top]} {
    puts "ERROR: 먼저 top 을 정해라."
    puts "   set tb_top tb_heartbeat_monitor_core"
    puts "   source [info script]"
    return
}

set proj_dir [get_property DIRECTORY [current_project]]
set xsim_dir [file join $proj_dir soc_project.sim sim_1 behav xsim]
set log_dir  [file join $proj_dir tb_logs]
file mkdir $log_dir

puts ""
puts "=============================================================="
puts " RUN : $tb_top"
puts "=============================================================="

# 이전 시뮬레이션이 열려 있으면 닫아 메모리를 돌려받는다
catch {close_sim -quiet}

set_property top $tb_top [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]
update_compile_order -fileset sim_1

# 모든 TB 가 자유 발진 클럭(always #5 clk = ~clk)을 쓴다. 이벤트가 영원히
# 끊기지 않으므로 'run all' 은 $finish 이후에도 절대 끝나지 않고 파형 DB 만
# 계속 쌓아 메모리를 먹는다(실측: 10분에 free 787MB -> 266MB).
# 그래서 launch_simulation 이 유한한 시간만 돌게 하고 'run all' 은 쓰지 않는다.
# 모든 TB 가 $finish 를 호출하므로 실제로는 그보다 훨씬 먼저 멈춘다.
set_property -name {xsim.simulate.runtime} -value {2ms} -objects [get_filesets sim_1]

if {[catch {launch_simulation} err]} {
    puts ""
    puts " >> launch_simulation 실패. elaborate.log 의 ERROR 줄:"
    set elog [file join $xsim_dir elaborate.log]
    if {[file exists $elog]} {
        file copy -force $elog [file join $log_dir "$tb_top.elaborate.log"]
        set fh [open $elog r]; set etxt [read $fh]; close $fh
        foreach line [split $etxt "\n"] {
            if {[string match "*ERROR*" $line]} { puts "    $line" }
        }
        puts ""
        puts " 로그 -> [file join $log_dir $tb_top.elaborate.log]"
    } else {
        puts "    elaborate.log 없음: $elog"
    }
    return
}

# simulate.log 는 xsim 프로세스가 살아 있는 동안 버퍼링된다. 먼저 닫아야
# 로그가 flush 되고 메모리도 돌려받는다.
puts ""
puts " 시뮬레이터를 닫아 로그를 flush 하고 메모리를 회수한다."
catch {close_sim -quiet}

set src [file join $xsim_dir simulate.log]
set dst [file join $log_dir "$tb_top.log"]

if {![file exists $src]} {
    puts " >> simulate.log 없음: $src"
    return
}

file copy -force $src $dst
set fh [open $dst r]; set txt [read $fh]; close $fh

# TB 마다 태그 형식이 다르다:
#   heartbeat : [PASS]      / [FAIL]
#   safety    : [PASS 12]   / [FAIL 12] / [AXI PROTOCOL FAIL]
# 번호가 붙은 형식을 놓치면 진짜 실패해도 FAIL=0 으로 초록불이 떠서 위험하다.
set n_pass [regexp -all {\[PASS[^\]]*\]} $txt]
set n_fail [regexp -all {\[[^\]]*FAIL[^\]]*\]} $txt]

# $finish 로 끝났는지 확인한다. 없으면 xsim.simulate.runtime(2ms) 에 걸려
# 잘린 것이므로 검증이 끝까지 돌지 않은 상태다.
set finished [regexp {\$finish called at time} $txt]

puts ""
puts "=============================================================="
puts [format " %s   PASS=%d  FAIL=%d" $tb_top $n_pass $n_fail]
puts "=============================================================="

if {$n_fail > 0} {
    puts " 실패 항목:"
    foreach line [split $txt "\n"] {
        if {[string match "*FAIL*" $line]} { puts "   $line" }
    }
}

if {!$finished} {
    puts " >> 경고: \$finish 가 없다. 2ms 런타임에 잘렸다 - 검증이 끝까지 돌지 않았다."
} elseif {$n_pass == 0} {
    puts " >> 경고: PASS 태그를 하나도 못 찾았다. 로그를 직접 확인해라."
}

puts ""
puts " 로그 -> $dst"
puts ""
puts " 다음 top 실행 :"
puts "   set tb_top <다음것>"
puts "   source /home/user7/workspace_ondevice_3/SOC_Project/run_one_testbench.tcl"
puts ""
