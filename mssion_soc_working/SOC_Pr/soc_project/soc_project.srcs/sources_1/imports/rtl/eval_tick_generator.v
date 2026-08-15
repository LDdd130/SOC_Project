`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// 파일   : eval_tick_generator.v
// 담당   : 공동 통합 RTL (A·B·C 공용). 팀원 B 전용 파일이 아니다.
//          04 체크리스트 2장 "공동 통합 RTL" 항목.
//
// 역할   : Fault 지속 Count 와 Safety Recovery Count 가 같은 시간 단위를 쓰도록
//          1클럭 폭 Pulse `eval_tick` 을 만든다 (00 공통명세 5.2).
//
//          공통 eval_tick
//          ├─ fault_manager_ip.eval_tick
//          └─ safety_controller_ip.eval_tick
//
// 규칙 (00 공통명세 5.2)
//   - AXI 레지스터가 없는 공통 보조 RTL. 네 번째 Custom IP 로 계산하지 않는다.
//   - Vivado Block Design 에 Module Reference 로 추가한다.
//   - 기본 주기 1ms = 100MHz 기준 100,000 클럭마다 1클럭 Pulse.
//   - reset=1 동안 eval_tick=0 이고 내부 Divider Counter 는 0 이다.
//   - Reset 해제 후 DIVISOR 개 클럭을 센 뒤 첫 Pulse 를 출력한다.
//   - Testbench 는 DIVISOR Parameter 만 작은 값으로 Override 한다.
//////////////////////////////////////////////////////////////////////////////////

module eval_tick_generator #(
    parameter integer DIVISOR = 100_000
) (
    input  wire clk,
    input  wire reset,          // active high
    output wire eval_tick
);

    // DIVISOR 를 담을 수 있는 Counter 폭 (00 공통명세 5.3 : 최소 32비트 권장)
    reg [31:0] div_cnt;
    reg        tick_r;

    always @(posedge clk) begin
        if (reset) begin
            div_cnt <= 32'd0;
            tick_r  <= 1'b0;
        end
        else if (div_cnt >= (DIVISOR[31:0] - 32'd1)) begin
            div_cnt <= 32'd0;
            tick_r  <= 1'b1;    // DIVISOR 클럭마다 정확히 1클럭 Pulse
        end
        else begin
            div_cnt <= div_cnt + 32'd1;
            tick_r  <= 1'b0;
        end
    end

    assign eval_tick = tick_r;

endmodule
