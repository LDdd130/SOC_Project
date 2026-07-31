`timescale 1 ns / 1 ps
//////////////////////////////////////////////////////////////////////////////////
// 파일 : fault_manager_ip_v1_0_S00_AXI.v
// 역할 : Vivado "Create and Package New IP" 마법사가 만드는 파일을 대체한다.
//        실제 로직은 fault_manager_axi.v 에 있고 여기는 연결만 한다.
//        (마법사 설정 : Lite / Slave / Data Width 32 / Number of Registers 16)
//////////////////////////////////////////////////////////////////////////////////

module fault_manager_ip_v1_0_S00_AXI #
(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 6
)
(
    // 사용자 포트
    input  wire [2:0] timeout,
    input  wire [2:0] error_flag,
    input  wire [2:0] critical_fault,
    input  wire       eval_tick,
    output wire [1:0] fault_level,
    output wire [1:0] fault_device,
    output wire [7:0] fault_code,
    output wire       fault_valid,
    output wire       irq,

    // AXI4-Lite
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

    fault_manager_axi #(
        .C_S_AXI_DATA_WIDTH (C_S_AXI_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH (C_S_AXI_ADDR_WIDTH)
    ) u_fault_manager_axi (
        .timeout            (timeout),
        .error_flag         (error_flag),
        .critical_fault     (critical_fault),
        .eval_tick          (eval_tick),
        .fault_level        (fault_level),
        .fault_device       (fault_device),
        .fault_code         (fault_code),
        .fault_valid        (fault_valid),
        .irq                (irq),
        .S_AXI_ACLK         (S_AXI_ACLK),
        .S_AXI_ARESETN      (S_AXI_ARESETN),
        .S_AXI_AWADDR       (S_AXI_AWADDR),
        .S_AXI_AWPROT       (S_AXI_AWPROT),
        .S_AXI_AWVALID      (S_AXI_AWVALID),
        .S_AXI_AWREADY      (S_AXI_AWREADY),
        .S_AXI_WDATA        (S_AXI_WDATA),
        .S_AXI_WSTRB        (S_AXI_WSTRB),
        .S_AXI_WVALID       (S_AXI_WVALID),
        .S_AXI_WREADY       (S_AXI_WREADY),
        .S_AXI_BRESP        (S_AXI_BRESP),
        .S_AXI_BVALID       (S_AXI_BVALID),
        .S_AXI_BREADY       (S_AXI_BREADY),
        .S_AXI_ARADDR       (S_AXI_ARADDR),
        .S_AXI_ARPROT       (S_AXI_ARPROT),
        .S_AXI_ARVALID      (S_AXI_ARVALID),
        .S_AXI_ARREADY      (S_AXI_ARREADY),
        .S_AXI_RDATA        (S_AXI_RDATA),
        .S_AXI_RRESP        (S_AXI_RRESP),
        .S_AXI_RVALID       (S_AXI_RVALID),
        .S_AXI_RREADY       (S_AXI_RREADY)
    );

endmodule
