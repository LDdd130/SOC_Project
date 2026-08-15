# =============================================================================
# run_all_testbenches.tcl
#
# 시뮬레이션 top 4개를 차례로 실행하고 PASS/FAIL 을 요약한다.
# 실패하면 elaborate.log 에서 원인 줄까지 뽑아 보여준다.
#
# 사용법 : add_testbenches.tcl 을 먼저 돌린 뒤
#     source /home/user7/workspace_ondevice_3/SOC_Project/run_all_testbenches.tcl
#
# 로그는 <프로젝트>/tb_logs/<top>.log 에 남는다.
# =============================================================================

set tops [list \
    tb_heartbeat_monitor_core  \
    tb_heartbeat_monitor_axi   \
    tb_safety_controller_core  \
    tb_safety_controller_axi   \
]

set proj_dir [get_property DIRECTORY [current_project]]
set xsim_dir [file join $proj_dir soc_project.sim sim_1 behav xsim]
set log_dir  [file join $proj_dir tb_logs]
file mkdir $log_dir

array set result {}

foreach top $tops {
    puts ""
    puts "=============================================================="
    puts " RUN : $top"
    puts "=============================================================="

    catch {close_sim -quiet}

    set_property top $top [get_filesets sim_1]
    set_property top_lib xil_defaultlib [get_filesets sim_1]
    update_compile_order -fileset sim_1

    set launch_ok 1
    if {[catch {launch_simulation} err]} {
        set launch_ok 0
    }

    if {!$launch_ok} {
        # elaborate 단계에서 죽은 경우 원인을 뽑아준다
        set elog [file join $xsim_dir elaborate.log]
        set reason "실행 실패"
        if {[file exists $elog]} {
            set fh [open $elog r]; set etxt [read $fh]; close $fh
            file copy -force $elog [file join $log_dir "$top.elaborate.log"]
            foreach line [split $etxt "\n"] {
                if {[string match "*ERROR*" $line]} {
                    puts "   $line"
                    if {[string match "*not found*" $line]} {
                        set reason "MODULE_NOT_FOUND"
                    }
                }
            }
        }
        set result($top) $reason
        continue
    }

    if {[catch {run all} err]} {
        puts "   (run all 종료: $err)"
    }

    set src [file join $xsim_dir simulate.log]
    set dst [file join $log_dir "$top.log"]
    if {[file exists $src]} {
        file copy -force $src $dst
        set fh [open $dst r]; set txt [read $fh]; close $fh
        set n_fail [regexp -all {\[FAIL\]} $txt]
        set n_pass [regexp -all {\[PASS\]} $txt]
        set n_err  [regexp -all {(?i)\merror\M} $txt]
        set result($top) [format "PASS=%-4d FAIL=%-4d ERROR=%d" $n_pass $n_fail $n_err]
        puts "   로그 -> $dst"
        # FAIL 줄은 바로 보여준다
        foreach line [split $txt "\n"] {
            if {[string match "*\[FAIL\]*" $line]} { puts "   $line" }
        }
    } else {
        set result($top) "NO_LOG"
        puts "   simulate.log 없음: $src"
    }
}

catch {close_sim -quiet}

puts ""
puts "=============================================================="
puts " 요약"
puts "=============================================================="
foreach top $tops {
    puts [format "  %-28s %s" $top $result($top)]
}
puts ""
puts " 로그 폴더 : $log_dir"
puts "=============================================================="
