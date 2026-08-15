`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// 파일 : tb_eval_tick_generator.v
// 담당 : 공동 통합 RTL 검증 (04 체크리스트 2장 "공동 통합 RTL" 항목)
//
// 확인 항목 (00 공통명세 5.2)
//   - reset=1 동안 eval_tick=0, 내부 Divider Counter 는 0
//   - Reset 해제 후 DIVISOR 개 클럭을 센 뒤 첫 Pulse
//   - Pulse 폭은 정확히 1 클럭
//   - 이후 주기가 정확히 DIVISOR 클럭
//////////////////////////////////////////////////////////////////////////////////

module tb_eval_tick_generator;

    localparam integer DIV = 20;        // 시뮬 단축용. 실제 기본값은 100_000 (=1ms @100MHz)

    reg  clk = 0, reset = 1;
    wire eval_tick;
    always #5 clk = ~clk;               // 100 MHz

    eval_tick_generator #(.DIVISOR(DIV)) dut (
        .clk(clk), .reset(reset), .eval_tick(eval_tick));

    integer errors = 0, checks = 0;
    integer t_first = 0, t_second = 0, width = 0;
    integer clk_cnt = 0;

    always @(posedge clk) clk_cnt = clk_cnt + 1;
    always @(posedge clk) if (eval_tick) width = width + 1;

    task check_int(input integer got, input integer exp, input [8*44:1] name);
        begin
            checks = checks + 1;
            if (got !== exp) begin
                errors = errors + 1;
                $display("  [FAIL] %0s  got=%0d exp=%0d", name, got, exp);
            end
            else $display("  [PASS] %0s  (=%0d)", name, got);
        end
    endtask

    integer rel_clk;

    initial begin
        $display("=== E01 : reset 동안 eval_tick = 0 ===");
        repeat (12) @(posedge clk);
        checks = checks + 1;
        if (eval_tick !== 1'b0 || dut.div_cnt !== 32'd0) begin
            errors = errors + 1;
            $display("  [FAIL] reset 중 tick=%b div_cnt=%0d", eval_tick, dut.div_cnt);
        end
        else $display("  [PASS] reset 중 tick=0, div_cnt=0");

        @(negedge clk); reset = 0;
        rel_clk = clk_cnt;              // Reset 해제 시점의 클럭 수

        $display("=== E02 : 해제 후 DIVISOR 클럭 뒤 첫 Pulse ===");
        @(posedge eval_tick);
        t_first = clk_cnt;
        check_int(t_first - rel_clk, DIV, "first pulse after DIVISOR clocks");

        $display("=== E03 : Pulse 폭 = 1 클럭 ===");
        @(posedge clk); @(negedge clk);     // 다음 클럭 경계를 지난 뒤 확인
        check_int(eval_tick, 0, "tick low on next clock");

        $display("=== E04 : 주기 = DIVISOR 클럭 ===");
        @(posedge eval_tick);
        t_second = clk_cnt;
        check_int(t_second - t_first, DIV, "period == DIVISOR");

        $display("=== E05 : 10 주기 동안 Pulse 개수 = 10 ===");
        width = 0;
        repeat (10 * DIV) @(posedge clk);
        check_int(width, 10, "pulse count over 10 periods");

        $display("");
        $display("=====================================");
        $display(" checks = %0d, errors = %0d  -> %0s", checks, errors,
                 (errors == 0) ? "ALL PASS" : "FAIL");
        $display("=====================================");
        $finish;
    end

endmodule
