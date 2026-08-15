`timescale 1ns / 1ps

/*
 * safety_controller_axi
 *
 * Safety Controller Core를 AXI4-Lite 레지스터로 제어하기 위한 Wrapper
 *
 * 레지스터 맵
 *   0x00 CTRL            RW/W1P : bit0 ENABLE, bit1 MANUAL_RESET
 *   0x04 SYSTEM_STATE    RO     : bit[1:0]
 *   0x08 OUTPUT_ENABLE   RO     : bit[2:0]
 *   0x0C DEGRADE_MASK    RW     : bit[2:0]
 *   0x10 RECOVERY_COUNT  RW     : bit[15:0]
 *   0x14 STATE_TIMER     RO     : bit[31:0]
 *   0x18 IRQ_EN          RW     : bit0 State Change IRQ Enable
 *   0x1C IRQ_STATUS      R/W1C  : bit0 State Change Pending
 *
 * 주요 정책
 *   - MANUAL_RESET은 Write-1-Pulse이며 Core에 1클럭 Pulse로 전달한다.
 *   - IRQ_STATUS는 상태 변경 이벤트가 발생하면 Set된다.
 *   - IRQ_STATUS는 1을 쓴 비트만 Clear되는 W1C 방식이다.
 *   - 상태 변경 Event Set과 W1C가 같은 클럭에 발생하면 Event Set이 우선한다.
 *   - IRQ는 IRQ_STATUS와 IRQ_EN이 모두 1인 동안 High를 유지한다.
 *   - Read-only 레지스터에 대한 Write는 무시한다.
 */
module safety_controller_axi #(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 5
) (
    // AXI4-Lite Slave Interface
    input  wire                             S_AXI_ACLK,
    input  wire                             S_AXI_ARESETN,

    input  wire [C_S_AXI_ADDR_WIDTH-1:0]    S_AXI_AWADDR,
    input  wire                             S_AXI_AWVALID,
    output wire                             S_AXI_AWREADY,

    input  wire [C_S_AXI_DATA_WIDTH-1:0]    S_AXI_WDATA,
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1:0] S_AXI_WSTRB,
    input  wire                             S_AXI_WVALID,
    output wire                             S_AXI_WREADY,

    output reg  [1:0]                       S_AXI_BRESP,
    output reg                              S_AXI_BVALID,
    input  wire                             S_AXI_BREADY,

    input  wire [C_S_AXI_ADDR_WIDTH-1:0]    S_AXI_ARADDR,
    input  wire                             S_AXI_ARVALID,
    output wire                             S_AXI_ARREADY,

    output reg  [C_S_AXI_DATA_WIDTH-1:0]    S_AXI_RDATA,
    output reg  [1:0]                       S_AXI_RRESP,
    output reg                              S_AXI_RVALID,
    input  wire                             S_AXI_RREADY,

    // Fault Manager 입력
    input  wire [1:0]                       fault_level,
    input  wire [1:0]                       fault_device,
    input  wire [7:0]                       fault_code,
    input  wire                             fault_valid,
    input  wire                             eval_tick,

    // Safety Controller 출력
    output wire [1:0]                       system_state,
    output wire [2:0]                       output_enable,
    output wire                             actuator_enable,
    output wire                             control_valid,
    output wire [31:0]                      state_timer,

    // Level 방식 인터럽트 출력
    output wire                             irq
);

    // AXI 응답값
    localparam [1:0] AXI_RESP_OKAY = 2'b00;

    // 레지스터 주소
    localparam [C_S_AXI_ADDR_WIDTH-1:0] ADDR_CTRL           = 5'h00;
    localparam [C_S_AXI_ADDR_WIDTH-1:0] ADDR_SYSTEM_STATE   = 5'h04;
    localparam [C_S_AXI_ADDR_WIDTH-1:0] ADDR_OUTPUT_ENABLE  = 5'h08;
    localparam [C_S_AXI_ADDR_WIDTH-1:0] ADDR_DEGRADE_MASK   = 5'h0C;
    localparam [C_S_AXI_ADDR_WIDTH-1:0] ADDR_RECOVERY_COUNT = 5'h10;
    localparam [C_S_AXI_ADDR_WIDTH-1:0] ADDR_STATE_TIMER    = 5'h14;
    localparam [C_S_AXI_ADDR_WIDTH-1:0] ADDR_IRQ_EN         = 5'h18;
    localparam [C_S_AXI_ADDR_WIDTH-1:0] ADDR_IRQ_STATUS     = 5'h1C;

    // Software 설정 레지스터
    reg        reg_enable;
    reg [2:0]  reg_degrade_mask;
    reg [15:0] reg_recovery_count;
    reg        reg_irq_en;
    reg        reg_irq_status;

    // W1P Pulse
    reg manual_reset_pulse;

    // Core 상태 변경 이벤트
    wire state_change_event;

    // AW/W 채널은 서로 독립적으로 도착할 수 있으므로 각각 보관한다.
    reg [C_S_AXI_ADDR_WIDTH-1:0]     awaddr_hold;
    reg                              awaddr_valid;
    reg [C_S_AXI_DATA_WIDTH-1:0]     wdata_hold;
    reg [(C_S_AXI_DATA_WIDTH/8)-1:0] wstrb_hold;
    reg                              wdata_valid;

    wire write_commit;

    assign S_AXI_AWREADY = !awaddr_valid && !S_AXI_BVALID;
    assign S_AXI_WREADY  = !wdata_valid  && !S_AXI_BVALID;
    assign S_AXI_ARREADY = !S_AXI_RVALID;

    // 주소와 데이터가 모두 저장된 후 한 번만 레지스터 Write를 수행한다.
    assign write_commit = awaddr_valid && wdata_valid && !S_AXI_BVALID;

    // Pending과 Enable이 모두 설정된 동안 IRQ를 High로 유지한다.
    assign irq = reg_irq_status && reg_irq_en;

    /*
     * AXI Write 주소/데이터 채널 및 Write Response
     */
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            awaddr_hold <= {C_S_AXI_ADDR_WIDTH{1'b0}};
            awaddr_valid <= 1'b0;
            wdata_hold <= {C_S_AXI_DATA_WIDTH{1'b0}};
            wstrb_hold <= {(C_S_AXI_DATA_WIDTH/8){1'b0}};
            wdata_valid <= 1'b0;
            S_AXI_BRESP <= AXI_RESP_OKAY;
            S_AXI_BVALID <= 1'b0;
        end
        else begin
            // Write 주소 수신
            if (S_AXI_AWREADY && S_AXI_AWVALID) begin
                awaddr_hold <= S_AXI_AWADDR;
                awaddr_valid <= 1'b1;
            end

            // Write 데이터 수신
            if (S_AXI_WREADY && S_AXI_WVALID) begin
                wdata_hold <= S_AXI_WDATA;
                wstrb_hold <= S_AXI_WSTRB;
                wdata_valid <= 1'b1;
            end

            // 한 번의 Write Transaction 완료
            if (write_commit) begin
                awaddr_valid <= 1'b0;
                wdata_valid <= 1'b0;
                S_AXI_BRESP <= AXI_RESP_OKAY;
                S_AXI_BVALID <= 1'b1;
            end
            else if (S_AXI_BVALID && S_AXI_BREADY) begin
                S_AXI_BVALID <= 1'b0;
            end
        end
    end

    /*
     * AXI Read 채널
     *
     * AR Handshake 시점에 주소를 Decode해 RDATA에 저장한다.
     * RVALID이 유지되는 동안 RDATA도 그대로 유지된다.
     */
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            S_AXI_RDATA <= {C_S_AXI_DATA_WIDTH{1'b0}};
            S_AXI_RRESP <= AXI_RESP_OKAY;
            S_AXI_RVALID <= 1'b0;
        end
        else begin
            if (S_AXI_ARREADY && S_AXI_ARVALID) begin
                S_AXI_RDATA <= {C_S_AXI_DATA_WIDTH{1'b0}};

                case (S_AXI_ARADDR)
                    ADDR_CTRL: begin
                        S_AXI_RDATA[0] <= reg_enable;
                        // MANUAL_RESET은 Pulse이므로 Read 값은 항상 0이다.
                        S_AXI_RDATA[1] <= 1'b0;
                    end

                    ADDR_SYSTEM_STATE:
                        S_AXI_RDATA[1:0] <= system_state;

                    ADDR_OUTPUT_ENABLE:
                        S_AXI_RDATA[2:0] <= output_enable;

                    ADDR_DEGRADE_MASK:
                        S_AXI_RDATA[2:0] <= reg_degrade_mask;

                    ADDR_RECOVERY_COUNT:
                        S_AXI_RDATA[15:0] <= reg_recovery_count;

                    ADDR_STATE_TIMER:
                        S_AXI_RDATA[31:0] <= state_timer;

                    ADDR_IRQ_EN:
                        S_AXI_RDATA[0] <= reg_irq_en;

                    ADDR_IRQ_STATUS:
                        S_AXI_RDATA[0] <= reg_irq_status;

                    default:
                        S_AXI_RDATA <= {C_S_AXI_DATA_WIDTH{1'b0}};
                endcase

                S_AXI_RRESP <= AXI_RESP_OKAY;
                S_AXI_RVALID <= 1'b1;
            end
            else if (S_AXI_RVALID && S_AXI_RREADY) begin
                S_AXI_RVALID <= 1'b0;
            end
        end
    end

    /*
     * Software 설정 레지스터
     *
     * WSTRB가 설정된 Byte만 갱신한다.
     * Reset 후 설정값은 최신 공통 명세에 따라 모두 0이다.
     */
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            reg_enable <= 1'b0;
            reg_degrade_mask <= 3'b000;
            reg_recovery_count <= 16'd0;
            reg_irq_en <= 1'b0;
            manual_reset_pulse <= 1'b0;
        end
        else begin
            // W1P는 기본 0이며 해당 Write가 있을 때만 1클럭 Pulse가 된다.
            manual_reset_pulse <= 1'b0;

            if (write_commit) begin
                case (awaddr_hold)
                    ADDR_CTRL: begin
                        if (wstrb_hold[0]) begin
                            reg_enable <= wdata_hold[0];
                            if (wdata_hold[1])
                                manual_reset_pulse <= 1'b1;
                        end
                    end

                    ADDR_DEGRADE_MASK: begin
                        if (wstrb_hold[0])
                            reg_degrade_mask <= wdata_hold[2:0];
                    end

                    ADDR_RECOVERY_COUNT: begin
                        if (wstrb_hold[0])
                            reg_recovery_count[7:0] <= wdata_hold[7:0];
                        if (wstrb_hold[1])
                            reg_recovery_count[15:8] <= wdata_hold[15:8];
                    end

                    ADDR_IRQ_EN: begin
                        if (wstrb_hold[0])
                            reg_irq_en <= wdata_hold[0];
                    end

                    default: begin
                        // Read-only 또는 미정의 주소 Write는 무시한다.
                    end
                endcase
            end
        end
    end

    /*
     * IRQ_STATUS
     *
     * 상태 변경 Event Set을 W1C보다 우선 처리해,
     * 같은 클럭에 새 이벤트가 발생하면 Pending이 유실되지 않게 한다.
     */
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            reg_irq_status <= 1'b0;
        end
        else if (state_change_event) begin
            reg_irq_status <= 1'b1;
        end
        else if (write_commit &&
                 (awaddr_hold == ADDR_IRQ_STATUS) &&
                 wstrb_hold[0] &&
                 wdata_hold[0]) begin
            reg_irq_status <= 1'b0;
        end
    end

    /*
     * Safety Controller Core
     *
     * AXI Reset은 Active-Low이므로 Core에는 반전해 Active-High로 전달한다.
     */
    safety_controller_core u_safety_controller_core (
        .clk                    (S_AXI_ACLK),
        .reset                  (~S_AXI_ARESETN),
        .enable                 (reg_enable),
        .fault_level            (fault_level),
        .fault_device           (fault_device),
        .fault_code             (fault_code),
        .fault_valid            (fault_valid),
        .degrade_mask           (reg_degrade_mask),
        .recovery_count_setting (reg_recovery_count),
        .eval_tick              (eval_tick),
        .manual_reset_pulse     (manual_reset_pulse),
        .system_state           (system_state),
        .output_enable          (output_enable),
        .actuator_enable        (actuator_enable),
        .control_valid          (control_valid),
        .state_timer            (state_timer),
        .state_change_event     (state_change_event)
    );

endmodule
