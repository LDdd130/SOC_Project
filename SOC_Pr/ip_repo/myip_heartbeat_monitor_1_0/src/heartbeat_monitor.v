`timescale 1ns / 1ps

/*============================================================================*/
//heartbeat_monitor_axi
/*============================================================================*/

// =============================================================================
// heartbeat_monitor_axi
// -----------------------------------------------------------------------------
// heartbeat_monitor_core용 AXI4-Lite Wrapper
//
// Register Map (32-bit, word aligned)
//   0x00 CTRL        RW/W1P : bit0 ENABLE, bit1 CLEAR_ALL, bit2 AUTO_RECOVER
//   0x04 STATUS      R      : bit[2:0] ALIVE, bit[10:8] TIMEOUT
//   0x08 TIMEOUT0    RW
//   0x0C TIMEOUT1    RW
//   0x10 TIMEOUT2    RW
//   0x14 LAST_COUNT0 R
//   0x18 LAST_COUNT1 R
//   0x1C LAST_COUNT2 R
//   0x20 IRQ_EN      RW     : bit[2:0]
//   0x24 IRQ_STATUS  R/W1C  : bit[2:0]
//
// 특징
//   - AW/W 채널을 각각 독립적으로 수신한 뒤 하나의 Write로 Commit
//   - CLEAR_ALL은 레지스터에 저장하지 않고 정확히 1클럭 Pulse 생성
//   - IRQ_STATUS는 Timeout Event를 Latch하여 Level IRQ 생성
//   - IRQ_STATUS Set과 W1C Clear가 동시에 발생하면 Set 우선
//   - device_enable은 기본 구현 정책에 따라 3'b111로 고정
// =============================================================================
module heartbeat_monitor_axi #(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 6
) (
    // Heartbeat Interface
    input  wire [2:0] heartbeat_async,
    output wire [2:0] alive,
    output wire [2:0] timeout,
    output wire       irq,

    // AXI4-Lite Slave Interface
    input  wire                              S_AXI_ACLK,
    input  wire                              S_AXI_ARESETN,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]     S_AXI_AWADDR,
    input  wire [2:0]                        S_AXI_AWPROT,
    input  wire                              S_AXI_AWVALID,
    output wire                              S_AXI_AWREADY,
    input  wire [C_S_AXI_DATA_WIDTH-1:0]     S_AXI_WDATA,
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1:0] S_AXI_WSTRB,
    input  wire                              S_AXI_WVALID,
    output wire                              S_AXI_WREADY,
    output reg  [1:0]                        S_AXI_BRESP,
    output reg                               S_AXI_BVALID,
    input  wire                              S_AXI_BREADY,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]     S_AXI_ARADDR,
    input  wire [2:0]                        S_AXI_ARPROT,
    input  wire                              S_AXI_ARVALID,
    output wire                              S_AXI_ARREADY,
    output reg  [C_S_AXI_DATA_WIDTH-1:0]     S_AXI_RDATA,
    output reg  [1:0]                        S_AXI_RRESP,
    output reg                               S_AXI_RVALID,
    input  wire                              S_AXI_RREADY
);

    // 현재 프로젝트 명세는 AXI Data Width 32-bit로 고정한다.
    localparam [5:0] ADDR_CTRL        = 6'h00;
    localparam [5:0] ADDR_STATUS      = 6'h04;
    localparam [5:0] ADDR_TIMEOUT0    = 6'h08;
    localparam [5:0] ADDR_TIMEOUT1    = 6'h0C;
    localparam [5:0] ADDR_TIMEOUT2    = 6'h10;
    localparam [5:0] ADDR_LAST_COUNT0 = 6'h14;
    localparam [5:0] ADDR_LAST_COUNT1 = 6'h18;
    localparam [5:0] ADDR_LAST_COUNT2 = 6'h1C;
    localparam [5:0] ADDR_IRQ_EN      = 6'h20;
    localparam [5:0] ADDR_IRQ_STATUS  = 6'h24;

    localparam [1:0] AXI_RESP_OKAY = 2'b00;

    wire core_reset;
    assign core_reset = ~S_AXI_ARESETN;

    // -------------------------------------------------------------------------
    // Software-visible Registers
    // -------------------------------------------------------------------------
    reg [31:0] ctrl_reg;
    reg [31:0] timeout0_reg;
    reg [31:0] timeout1_reg;
    reg [31:0] timeout2_reg;
    reg [2:0]  irq_en_reg;
    reg [2:0]  irq_status_reg;

    wire core_enable;
    wire auto_recover;

    assign core_enable = ctrl_reg[0];
    assign auto_recover = ctrl_reg[2];

    // -------------------------------------------------------------------------
    // AXI Write Address/Data Holding Registers
    // AW와 W는 서로 다른 클럭에 들어올 수 있으므로 각각 보관한다.
    // -------------------------------------------------------------------------
    reg                              aw_pending;
    reg [C_S_AXI_ADDR_WIDTH-1:0]     awaddr_hold;
    reg                              w_pending;
    reg [C_S_AXI_DATA_WIDTH-1:0]     wdata_hold;
    reg [(C_S_AXI_DATA_WIDTH/8)-1:0] wstrb_hold;

    assign S_AXI_AWREADY = !aw_pending && !S_AXI_BVALID;
    assign S_AXI_WREADY  = !w_pending  && !S_AXI_BVALID;

    wire write_commit;
    wire [5:0] write_offset;

    assign write_commit = aw_pending && w_pending && !S_AXI_BVALID;
    assign write_offset = awaddr_hold[5:0];

    // W1P: Commit되는 한 클럭에만 High
    wire clear_all_pulse;
    assign clear_all_pulse = write_commit &&
                             (write_offset == ADDR_CTRL) &&
                             wstrb_hold[0] &&
                             wdata_hold[1];

    // W1C: 1을 쓴 비트만 Clear
    wire [2:0] irq_w1c_mask;
    assign irq_w1c_mask = (write_commit &&
                           (write_offset == ADDR_IRQ_STATUS) &&
                           wstrb_hold[0])
                         ? wdata_hold[2:0]
                         : 3'b000;

    // Byte Strobe 적용 함수
    function [31:0] apply_wstrb32;
        input [31:0] current_value;
        input [31:0] write_value;
        input [3:0]  write_strobe;
        integer byte_index;
        begin
            apply_wstrb32 = current_value;
            for (byte_index = 0; byte_index < 4; byte_index = byte_index + 1) begin
                if (write_strobe[byte_index])
                    apply_wstrb32[(byte_index*8) +: 8] =
                        write_value[(byte_index*8) +: 8];
            end
        end
    endfunction

    // AXI Write Channel + RW Register Update
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            aw_pending    <= 1'b0;
            awaddr_hold   <= {C_S_AXI_ADDR_WIDTH{1'b0}};
            w_pending     <= 1'b0;
            wdata_hold    <= {C_S_AXI_DATA_WIDTH{1'b0}};
            wstrb_hold    <= {(C_S_AXI_DATA_WIDTH/8){1'b0}};
            S_AXI_BRESP   <= AXI_RESP_OKAY;
            S_AXI_BVALID  <= 1'b0;

            ctrl_reg      <= 32'd0;
            timeout0_reg  <= 32'd0;
            timeout1_reg  <= 32'd0;
            timeout2_reg  <= 32'd0;
            irq_en_reg    <= 3'b000;
        end
        else begin
            // Write Address 수신
            if (S_AXI_AWREADY && S_AXI_AWVALID) begin
                aw_pending  <= 1'b1;
                awaddr_hold <= S_AXI_AWADDR;
            end

            // Write Data 수신
            if (S_AXI_WREADY && S_AXI_WVALID) begin
                w_pending  <= 1'b1;
                wdata_hold <= S_AXI_WDATA;
                wstrb_hold <= S_AXI_WSTRB;
            end

            // Address와 Data가 모두 준비되면 한 번만 Register Write 수행
            if (write_commit) begin
                case (write_offset)
                    ADDR_CTRL: begin
                        // bit1 CLEAR_ALL은 W1P이므로 저장하지 않는다.
                        ctrl_reg <= apply_wstrb32(ctrl_reg,
                                                 wdata_hold[31:0],
                                                 wstrb_hold[3:0]) &
                                    32'h0000_0005;
                    end

                    ADDR_TIMEOUT0: begin
                        timeout0_reg <= apply_wstrb32(timeout0_reg,
                                                     wdata_hold[31:0],
                                                     wstrb_hold[3:0]);
                    end

                    ADDR_TIMEOUT1: begin
                        timeout1_reg <= apply_wstrb32(timeout1_reg,
                                                     wdata_hold[31:0],
                                                     wstrb_hold[3:0]);
                    end

                    ADDR_TIMEOUT2: begin
                        timeout2_reg <= apply_wstrb32(timeout2_reg,
                                                     wdata_hold[31:0],
                                                     wstrb_hold[3:0]);
                    end

                    ADDR_IRQ_EN: begin
                        // 32-bit 함수 결과의 하위 3비트만 3-bit 레지스터에 저장된다.
                        irq_en_reg <= apply_wstrb32({29'd0, irq_en_reg},
                                                   wdata_hold[31:0],
                                                   wstrb_hold[3:0]);
                    end

                    // STATUS/LAST_COUNT/IRQ_STATUS는 여기서 저장하지 않는다.
                    // IRQ_STATUS Clear는 별도의 W1C 로직에서 처리한다.
                    default: begin
                    end
                endcase

                aw_pending   <= 1'b0;
                w_pending    <= 1'b0;
                S_AXI_BRESP  <= AXI_RESP_OKAY;
                S_AXI_BVALID <= 1'b1;
            end
            else if (S_AXI_BVALID && S_AXI_BREADY) begin
                S_AXI_BVALID <= 1'b0;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Heartbeat Core
    // -------------------------------------------------------------------------
    wire [31:0] last_count0;
    wire [31:0] last_count1;
    wire [31:0] last_count2;
    wire [2:0]  timeout_event;

    heartbeat_monitor_core u_heartbeat_monitor_core (
        .clk              (S_AXI_ACLK),
        .reset            (core_reset),
        .enable           (core_enable),
        .heartbeat_async  (heartbeat_async),
        .device_enable    (3'b111),
        .timeout0         (timeout0_reg),
        .timeout1         (timeout1_reg),
        .timeout2         (timeout2_reg),
        .clear_all_pulse  (clear_all_pulse),
        .auto_recover     (auto_recover),
        .alive            (alive),
        .timeout          (timeout),
        .last_count0      (last_count0),
        .last_count1      (last_count1),
        .last_count2      (last_count2),
        .timeout_event    (timeout_event)
    );

    // -------------------------------------------------------------------------
    // IRQ_STATUS W1C + Timeout Event Latch
    // Set과 Clear가 같은 클럭이면 OR 연산으로 Set이 우선한다.
    // IP Disable 중에는 core가 timeout_event=0이므로 새 Pending이 생기지 않는다.
    // -------------------------------------------------------------------------
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            irq_status_reg <= 3'b000;
        end
        else begin
            irq_status_reg <= (irq_status_reg & ~irq_w1c_mask) |
                              timeout_event;
        end
    end

    assign irq = |(irq_status_reg & irq_en_reg);

    // -------------------------------------------------------------------------
    // AXI Read Channel
    // -------------------------------------------------------------------------
    assign S_AXI_ARREADY = !S_AXI_RVALID;

    reg [31:0] read_data_mux;

    always @(*) begin
        read_data_mux = 32'd0;

        case (S_AXI_ARADDR[5:0])
            ADDR_CTRL: begin
                read_data_mux = ctrl_reg;
            end

            ADDR_STATUS: begin
                read_data_mux[2:0]  = alive;
                read_data_mux[10:8] = timeout;
            end

            ADDR_TIMEOUT0: begin
                read_data_mux = timeout0_reg;
            end

            ADDR_TIMEOUT1: begin
                read_data_mux = timeout1_reg;
            end

            ADDR_TIMEOUT2: begin
                read_data_mux = timeout2_reg;
            end

            ADDR_LAST_COUNT0: begin
                read_data_mux = last_count0;
            end

            ADDR_LAST_COUNT1: begin
                read_data_mux = last_count1;
            end

            ADDR_LAST_COUNT2: begin
                read_data_mux = last_count2;
            end

            ADDR_IRQ_EN: begin
                read_data_mux[2:0] = irq_en_reg;
            end

            ADDR_IRQ_STATUS: begin
                read_data_mux[2:0] = irq_status_reg;
            end

            default: begin
                read_data_mux = 32'd0;
            end
        endcase
    end

    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            S_AXI_RDATA  <= {C_S_AXI_DATA_WIDTH{1'b0}};
            S_AXI_RRESP  <= AXI_RESP_OKAY;
            S_AXI_RVALID <= 1'b0;
        end
        else begin
            if (S_AXI_ARREADY && S_AXI_ARVALID) begin
                S_AXI_RDATA  <= read_data_mux;
                S_AXI_RRESP  <= AXI_RESP_OKAY;
                S_AXI_RVALID <= 1'b1;
            end
            else if (S_AXI_RVALID && S_AXI_RREADY) begin
                S_AXI_RVALID <= 1'b0;
            end
        end
    end

    // AXI Protection 신호는 본 IP에서 사용하지 않는다.
    wire unused_axi_prot;
    assign unused_axi_prot = ^S_AXI_AWPROT ^ ^S_AXI_ARPROT;

endmodule

/*============================================================================*/
//heartbeat_monitor_core
/*============================================================================*/

// =============================================================================
// heartbeat_monitor_core
// -----------------------------------------------------------------------------
// 3개의 비동기 Heartbeat 입력을 동기화한 뒤 상승 에지를 검출하고,
// 장치별 Timeout Counter / Alive / Timeout / Timeout Event를 생성한다.
//
// Timeout 판정 기준:
//   - Heartbeat pulse를 받은 클럭에서 counter = 0
//   - 이후 Heartbeat가 없는 클럭마다 counter가 1씩 증가
//   - counter가 유효 timeout 값에 도달하는 정확한 클럭에 timeout이 Set
//   - timeout_setting == 0이면 유효값 1로 처리
//
// 우선순위:
//   reset
//   > enable=0 또는 device_enable=0
//   > clear_all_pulse
//   > heartbeat_pulse + auto_recover
//   > timeout set
//   > counter increment
// =============================================================================
module heartbeat_monitor_core (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire [2:0]  heartbeat_async,
    input  wire [2:0]  device_enable,
    input  wire [31:0] timeout0,
    input  wire [31:0] timeout1,
    input  wire [31:0] timeout2,
    input  wire        clear_all_pulse,
    input  wire        auto_recover,

    output wire [2:0]  alive,
    output wire [2:0]  timeout,
    output wire [31:0] last_count0,
    output wire [31:0] last_count1,
    output wire [31:0] last_count2,
    output wire [2:0]  timeout_event
);

    // -------------------------------------------------------------------------
    // Channel 0
    // -------------------------------------------------------------------------
    heartbeat_monitor_channel u_channel0 (
        .clk              (clk),
        .reset            (reset),
        .enable           (enable),
        .heartbeat_async  (heartbeat_async[0]),
        .device_enable    (device_enable[0]),
        .timeout_setting  (timeout0),
        .clear_all_pulse  (clear_all_pulse),
        .auto_recover     (auto_recover),
        .alive            (alive[0]),
        .timeout          (timeout[0]),
        .last_count       (last_count0),
        .timeout_event    (timeout_event[0])
    );

    // -------------------------------------------------------------------------
    // Channel 1
    // -------------------------------------------------------------------------
    heartbeat_monitor_channel u_channel1 (
        .clk              (clk),
        .reset            (reset),
        .enable           (enable),
        .heartbeat_async  (heartbeat_async[1]),
        .device_enable    (device_enable[1]),
        .timeout_setting  (timeout1),
        .clear_all_pulse  (clear_all_pulse),
        .auto_recover     (auto_recover),
        .alive            (alive[1]),
        .timeout          (timeout[1]),
        .last_count       (last_count1),
        .timeout_event    (timeout_event[1])
    );

    // -------------------------------------------------------------------------
    // Channel 2
    // -------------------------------------------------------------------------
    heartbeat_monitor_channel u_channel2 (
        .clk              (clk),
        .reset            (reset),
        .enable           (enable),
        .heartbeat_async  (heartbeat_async[2]),
        .device_enable    (device_enable[2]),
        .timeout_setting  (timeout2),
        .clear_all_pulse  (clear_all_pulse),
        .auto_recover     (auto_recover),
        .alive            (alive[2]),
        .timeout          (timeout[2]),
        .last_count       (last_count2),
        .timeout_event    (timeout_event[2])
    );

endmodule

/*============================================================================*/
//heartbeat_monitor_channel
/*============================================================================*/

// =============================================================================
// heartbeat_monitor_channel
// -----------------------------------------------------------------------------
// 단일 Heartbeat 채널 처리 모듈.
// 같은 파일 안에 두어 Vivado에서 heartbeat_monitor_core.v 하나만 추가해도 된다.
// =============================================================================
module heartbeat_monitor_channel (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire        heartbeat_async,
    input  wire        device_enable,
    input  wire [31:0] timeout_setting,
    input  wire        clear_all_pulse,
    input  wire        auto_recover,

    output wire        alive,
    output wire        timeout,
    output wire [31:0] last_count,
    output wire        timeout_event
);

    localparam [31:0] COUNTER_MAX = 32'hFFFF_FFFF;

    // -------------------------------------------------------------------------
    // 2FF Synchronizer + Rising Edge Detector
    // -------------------------------------------------------------------------
    (* ASYNC_REG = "TRUE" *) reg heartbeat_sync_ff1;
    (* ASYNC_REG = "TRUE" *) reg heartbeat_sync_ff2;
    reg heartbeat_sync_d;

    wire heartbeat_pulse;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            heartbeat_sync_ff1 <= 1'b0;
            heartbeat_sync_ff2 <= 1'b0;
            heartbeat_sync_d   <= 1'b0;
        end
        else begin
            heartbeat_sync_ff1 <= heartbeat_async;
            heartbeat_sync_ff2 <= heartbeat_sync_ff1;
            heartbeat_sync_d   <= heartbeat_sync_ff2;
        end
    end

    assign heartbeat_pulse = heartbeat_sync_ff2 & ~heartbeat_sync_d;

    // timeout_setting == 0이면 1클럭으로 처리
    wire [31:0] timeout_effective;
    assign timeout_effective = (timeout_setting == 32'd0)
                             ? 32'd1
                             : timeout_setting;

    // -------------------------------------------------------------------------
    // Timeout Counter / Timeout Latch / One-clock Event
    // -------------------------------------------------------------------------
    reg [31:0] counter_reg;
    reg        timeout_reg;
    reg        timeout_event_reg;

    wire [31:0] counter_incremented;
    assign counter_incremented = (counter_reg == COUNTER_MAX)
                               ? COUNTER_MAX
                               : counter_reg + 32'd1;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            counter_reg       <= 32'd0;
            timeout_reg       <= 1'b0;
            timeout_event_reg <= 1'b0;
        end
        else begin
            // Event는 기본적으로 매 클럭 0이며, Timeout 0→1 순간에만 1
            timeout_event_reg <= 1'b0;

            // 전체 Disable 또는 해당 Device Disable: 안전 출력으로 Clear
            if (!enable || !device_enable) begin
                counter_reg       <= 32'd0;
                timeout_reg       <= 1'b0;
                timeout_event_reg <= 1'b0;
            end
            // CLEAR_ALL은 Counter와 Timeout만 Clear한다.
            // AXI IRQ_STATUS는 wrapper에서 별도로 관리해야 한다.
            else if (clear_all_pulse) begin
                counter_reg       <= 32'd0;
                timeout_reg       <= 1'b0;
                timeout_event_reg <= 1'b0;
            end
            // Heartbeat 수신은 항상 경과 Counter를 0으로 초기화한다.
            else if (heartbeat_pulse) begin
                counter_reg <= 32'd0;

                // AUTO_RECOVER=1인 경우에만 Timeout 상태를 해제
                if (auto_recover)
                    timeout_reg <= 1'b0;
            end
            else begin
                // Overflow 방지를 위한 Saturating Counter
                counter_reg <= counter_incremented;

                // Timeout이 아직 Set되지 않은 경우에만 0→1 Event 발생
                // counter_incremented를 비교하므로 정확히 N번째 무-HB 클럭에 Set된다.
                if (!timeout_reg &&
                    (counter_incremented >= timeout_effective)) begin
                    timeout_reg       <= 1'b1;
                    timeout_event_reg <= 1'b1;
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Outputs
    // -------------------------------------------------------------------------
    assign timeout       = timeout_reg;
    assign last_count    = counter_reg;
    assign timeout_event = timeout_event_reg;

    // enable=0 또는 device_enable=0이면 Alive는 반드시 0
    assign alive = enable && device_enable && !timeout_reg;

endmodule
