`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// 파일   : fault_manager_axi.v
// 담당   : 팀원 B (fault_manager_ip)
// 역할   : fault_manager_core 의 AXI4-Lite 레지스터 인터페이스
//
// 근거 문서 : 00 공통명세 5.2(공통 eval_tick), 5.4(W1P/W1C/Level IRQ), 9.2(레지스터 맵)
//             02 팀원B 6장(레지스터 맵), 6.1(RESET_FAULT), 7장(IRQ 규칙)
//
// eval_tick 은 이 IP 가 만들지 않는다. 공통 통합 RTL `eval_tick_generator.v` 가
// 만든 1클럭 Pulse 를 B/C 가 같은 포트명 `eval_tick` 으로 받는다 (00 문서 5.2).
//
// 레지스터 맵 (공통 명세 Offset 그대로, 변경 없음)
//   0x00 CTRL          RW/W1P  bit0 ENABLE, bit1 RESET_FAULT(W1P)
//   0x04 FAULT_INPUT   R       bit[2:0] timeout, bit[10:8] error_flag, bit[18:16] critical_fault
//   0x08 CRITICAL_MASK RW      bit[2:0], 리셋 기본값 3'b100
//   0x0C PERSIST_LIMIT RW      bit[7:0], 리셋 기본값 5
//   0x10 FAULT_LEVEL   R       bit[1:0]
//   0x14 FAULT_DEVICE  R       bit[1:0]
//   0x18 FAULT_CODE    R       bit[7:0]
//   0x1C FAULT_COUNT   R       bit[7:0] cnt0, bit[15:8] cnt1, bit[23:16] cnt2
//   0x20 IRQ_EN        RW      bit0 Fault Change
//   0x24 IRQ_STATUS    R/W1C   bit0 Fault Change Pending
//   --- 아래 1개는 기존 Offset 을 건드리지 않는 추가분. 팀 승인 필요 (문서 15장 CHANGE REQUEST) ---
//   0x2C ID            R       0x464D4752 ("FMGR"), 브링업 시 AXI 매핑 확인용
//
// AXI Write 채널 (2026-07-30 수정)
//   - AW/W 채널을 각각 독립적으로 수신한 뒤 하나의 Write로 Commit한다.
//     (AWVALID/WVALID 가 같은 클럭에 들어오지 않아도 정상 동작해야 하는
//      AXI4-Lite 규격 요구사항. Heartbeat Monitor IP와 동일한 방식.)
//   - WSTRB 를 실제로 반영한다. 이 IP의 RW 필드는 전부 byte0(bit[7:0]) 안에
//     있으므로 WSTRB[0]=0 인 Write는 무시한다.
//////////////////////////////////////////////////////////////////////////////////

module fault_manager_axi #(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 6
)(
    //-------------------- 사용자 포트 --------------------
    input  wire [2:0] timeout,             // heartbeat_monitor_ip -> 여기
    input  wire [2:0] error_flag,          // 외부/Simulator
    input  wire [2:0] critical_fault,      // 외부/Simulator
    input  wire       eval_tick,           // 공통 eval_tick_generator.v 의 1클럭 Pulse

    output wire [1:0] fault_level,         // -> safety_controller_ip
    output wire [1:0] fault_device,
    output wire [7:0] fault_code,
    output wire       fault_valid,
    output wire       irq,                 // Level 방식 (공통 명세 5.4)

    //-------------------- AXI4-Lite --------------------
    input  wire                                S_AXI_ACLK,
    input  wire                                S_AXI_ARESETN,
    input  wire [C_S_AXI_ADDR_WIDTH-1 : 0]     S_AXI_AWADDR,
    input  wire [2 : 0]                        S_AXI_AWPROT,
    input  wire                                S_AXI_AWVALID,
    output wire                                S_AXI_AWREADY,
    input  wire [C_S_AXI_DATA_WIDTH-1 : 0]     S_AXI_WDATA,
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1 : 0] S_AXI_WSTRB,
    input  wire                                S_AXI_WVALID,
    output wire                                S_AXI_WREADY,
    output wire [1 : 0]                        S_AXI_BRESP,
    output wire                                S_AXI_BVALID,
    input  wire                                S_AXI_BREADY,
    input  wire [C_S_AXI_ADDR_WIDTH-1 : 0]     S_AXI_ARADDR,
    input  wire [2 : 0]                        S_AXI_ARPROT,
    input  wire                                S_AXI_ARVALID,
    output wire                                S_AXI_ARREADY,
    output wire [C_S_AXI_DATA_WIDTH-1 : 0]     S_AXI_RDATA,
    output wire [1 : 0]                        S_AXI_RRESP,
    output wire                                S_AXI_RVALID,
    input  wire                                S_AXI_RREADY
);

    //--------------------------------------------------------------------------
    // AXI4-Lite Write 채널 : AW/W 를 각각 독립 보관 후 Commit
    //--------------------------------------------------------------------------
    reg                                aw_pending;
    reg [C_S_AXI_ADDR_WIDTH-1 : 0]     awaddr_hold;
    reg                                w_pending;
    reg [C_S_AXI_DATA_WIDTH-1 : 0]     wdata_hold;
    reg [(C_S_AXI_DATA_WIDTH/8)-1 : 0] wstrb_hold;

    reg [1 : 0] axi_bresp;
    reg         axi_bvalid;

    //--------------------------------------------------------------------------
    // AXI4-Lite Read 채널 (기존과 동일, AW/W 커플링 문제 없음)
    //--------------------------------------------------------------------------
    reg [C_S_AXI_ADDR_WIDTH-1 : 0] axi_araddr;
    reg                            axi_arready;
    reg [C_S_AXI_DATA_WIDTH-1 : 0] axi_rdata;
    reg [1 : 0]                    axi_rresp;
    reg                            axi_rvalid;

    localparam integer ADDR_LSB          = (C_S_AXI_DATA_WIDTH/32) + 1;  // = 2
    localparam integer OPT_MEM_ADDR_BITS = 3;                            // 16 registers

    assign S_AXI_AWREADY = !aw_pending && !axi_bvalid;
    assign S_AXI_WREADY  = !w_pending  && !axi_bvalid;
    assign S_AXI_BRESP   = axi_bresp;
    assign S_AXI_BVALID  = axi_bvalid;
    assign S_AXI_ARREADY = axi_arready;
    assign S_AXI_RDATA   = axi_rdata;
    assign S_AXI_RRESP   = axi_rresp;
    assign S_AXI_RVALID  = axi_rvalid;

    wire slv_reg_rden = axi_arready && S_AXI_ARVALID && ~axi_rvalid;

    wire write_commit = aw_pending && w_pending && !axi_bvalid;

    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            axi_arready <= 1'b0;
            axi_araddr  <= 0;
        end
        else if (~axi_arready && S_AXI_ARVALID) begin
            axi_arready <= 1'b1;
            axi_araddr  <= S_AXI_ARADDR;
        end
        else axi_arready <= 1'b0;
    end

    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            axi_rvalid <= 1'b0;
            axi_rresp  <= 2'b00;
        end
        else if (axi_arready && S_AXI_ARVALID && ~axi_rvalid) begin
            axi_rvalid <= 1'b1;
            axi_rresp  <= 2'b00;
        end
        else if (axi_rvalid && S_AXI_RREADY) axi_rvalid <= 1'b0;
    end

    //--------------------------------------------------------------------------
    // 레지스터
    //--------------------------------------------------------------------------
    localparam [31:0] IP_ID_VALUE = 32'h464D_4752;   // "FMGR"

    localparam [3:0] R_CTRL          = 4'h0,
                     R_FAULT_INPUT   = 4'h1,
                     R_CRITICAL_MASK = 4'h2,
                     R_PERSIST_LIMIT = 4'h3,
                     R_FAULT_LEVEL   = 4'h4,
                     R_FAULT_DEVICE  = 4'h5,
                     R_FAULT_CODE    = 4'h6,
                     R_FAULT_COUNT   = 4'h7,
                     R_IRQ_EN        = 4'h8,
                     R_IRQ_STATUS    = 4'h9,
                     R_ID            = 4'hB;

    reg         reg_enable;
    reg  [2:0]  reg_critical_mask;
    reg  [7:0]  reg_persist_limit;
    reg         reg_irq_en;
    reg         reg_irq_status;
    reg         reset_fault_pulse;

    wire reset = ~S_AXI_ARESETN;       // core 내부 리셋 (공통 명세 5.1)

    wire [7:0] fault_count0, fault_count1, fault_count2;
    wire       fault_change_event;

    // 현재 활성 Fault. RESET_FAULT 적용 여부 판단에 쓴다 (02 문서 6.1)
    wire [2:0] device_fault_in = timeout | error_flag | critical_fault;

    // AXI Write Channel 수신 + RW Register Update
    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            aw_pending        <= 1'b0;
            awaddr_hold       <= {C_S_AXI_ADDR_WIDTH{1'b0}};
            w_pending         <= 1'b0;
            wdata_hold        <= {C_S_AXI_DATA_WIDTH{1'b0}};
            wstrb_hold        <= {(C_S_AXI_DATA_WIDTH/8){1'b0}};
            axi_bresp         <= 2'b00;
            axi_bvalid        <= 1'b0;

            reg_enable        <= 1'b0;          // Enable 은 MicroBlaze 가 켠다 (공통 명세 12장)
            reg_critical_mask <= 3'b100;        // Device 2 가 Critical (공통 명세 9.2)
            reg_persist_limit <= 8'd5;          // 권장 초기값 (00 문서 10장, 04 문서 1장)
            reg_irq_en        <= 1'b0;
            reg_irq_status    <= 1'b0;
            reset_fault_pulse <= 1'b0;
        end
        else begin
            reset_fault_pulse <= 1'b0;          // W1P 는 항상 1클럭

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
                if (wstrb_hold[0]) begin  // 모든 RW 필드가 byte0(bit[7:0]) 안에 있다
                    case (awaddr_hold[ADDR_LSB+OPT_MEM_ADDR_BITS : ADDR_LSB])
                        R_CTRL: begin
                            reg_enable <= wdata_hold[0];
                            if (wdata_hold[1]) reset_fault_pulse <= 1'b1;
                        end
                        R_CRITICAL_MASK: reg_critical_mask <= wdata_hold[2:0];
                        R_PERSIST_LIMIT: reg_persist_limit <= wdata_hold[7:0];
                        R_IRQ_EN:        reg_irq_en        <= wdata_hold[0];
                        R_IRQ_STATUS:    if (wdata_hold[0]) reg_irq_status <= 1'b0;  // W1C
                        default: ;       // Read-only 레지스터에 대한 Write 는 무시 (공통 명세 5.4)
                    endcase
                end

                aw_pending <= 1'b0;
                w_pending  <= 1'b0;
                axi_bresp  <= 2'b00;
                axi_bvalid <= 1'b1;
            end
            else if (S_AXI_BREADY && axi_bvalid) begin
                axi_bvalid <= 1'b0;
            end

            // RESET_FAULT 는 현재 Fault 가 하나도 없을 때만 Pending 까지 Clear 한다.
            // Fault 가 남아 있으면 명령 자체를 무시한다 (02 문서 6.1).
            if (reset_fault_pulse && (device_fault_in == 3'b000)) reg_irq_status <= 1'b0;

            // Set 을 맨 뒤에 둬서 W1C/RESET_FAULT 보다 우선하게 한다.
            // 같은 클럭에 새 변화와 Clear 가 겹쳐도 Event 를 놓치지 않는다 (02 문서 7장).
            if (fault_change_event) reg_irq_status <= 1'b1;
        end
    end

    // 읽기
    reg [C_S_AXI_DATA_WIDTH-1:0] reg_data_out;
    always @(*) begin
        reg_data_out = 32'h0;
        case (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS : ADDR_LSB])
            R_CTRL:          reg_data_out = {30'b0, 1'b0, reg_enable};
            R_FAULT_INPUT:   reg_data_out = {13'b0, critical_fault, 5'b0, error_flag,
                                             5'b0, timeout};
            R_CRITICAL_MASK: reg_data_out = {29'b0, reg_critical_mask};
            R_PERSIST_LIMIT: reg_data_out = {24'b0, reg_persist_limit};
            R_FAULT_LEVEL:   reg_data_out = {30'b0, fault_level};
            R_FAULT_DEVICE:  reg_data_out = {30'b0, fault_device};
            R_FAULT_CODE:    reg_data_out = {24'b0, fault_code};
            R_FAULT_COUNT:   reg_data_out = {8'b0, fault_count2, fault_count1, fault_count0};
            R_IRQ_EN:        reg_data_out = {31'b0, reg_irq_en};
            R_IRQ_STATUS:    reg_data_out = {31'b0, reg_irq_status};
            R_ID:            reg_data_out = IP_ID_VALUE;
            default:         reg_data_out = 32'h0;
        endcase
    end

    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) axi_rdata <= 0;
        else if (slv_reg_rden) axi_rdata <= reg_data_out;
    end

    // IRQ 는 Level. ISR 이 W1C 로 지울 때까지 High 유지 (공통 명세 5.4)
    assign irq = reg_irq_status & reg_irq_en;

    //--------------------------------------------------------------------------
    // Core
    //--------------------------------------------------------------------------
    fault_manager_core u_core (
        .clk                (S_AXI_ACLK),
        .reset              (reset),
        .enable             (reg_enable),
        .eval_tick          (eval_tick),
        .timeout            (timeout),
        .error_flag         (error_flag),
        .critical_fault     (critical_fault),
        .critical_mask      (reg_critical_mask),
        .persist_limit      (reg_persist_limit),
        .reset_fault_pulse  (reset_fault_pulse),
        .fault_level        (fault_level),
        .fault_device       (fault_device),
        .fault_code         (fault_code),
        .fault_valid        (fault_valid),
        .fault_count0       (fault_count0),
        .fault_count1       (fault_count1),
        .fault_count2       (fault_count2),
        .fault_change_event (fault_change_event)
    );

endmodule
