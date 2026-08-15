
`timescale 1 ns / 1 ps

//////////////////////////////////////////////////////////////////////////////////
// 파일 : fault_manager_ip.v
// 역할 : fault_manager_ip 의 IP 최상위. Block Design 에서 보이는 포트를 결정한다.
//
// Block Design 연결 (00 공통명세 2장, 04 체크리스트 1.1)
//   timeout[2:0]        <- heartbeat_monitor_ip.timeout
//   error_flag[2:0]     <- AXI GPIO 또는 보드 스위치 (Fault Injection)
//   critical_fault[2:0] <- AXI GPIO 또는 보드 스위치 (Device 2 가 기본 Critical)
//   eval_tick           <- 공통 eval_tick_generator.v 의 eval_tick.
//                          safety_controller_ip.eval_tick 과 같은 소스를 쓴다.
//   fault_level[1:0]    -> safety_controller_ip
//   fault_device[1:0]   -> safety_controller_ip
//   fault_code[7:0]     -> safety_controller_ip
//   fault_valid         -> safety_controller_ip
//   irq                 -> xlconcat -> AXI INTC (Level 방식, 00 공통명세 5.4)
//
// 금지 연결 (04 체크리스트 1.1)
//   heartbeat_monitor_ip.alive 는 이 IP 에 연결하지 않는다.
//////////////////////////////////////////////////////////////////////////////////

	module fault_manager_ip #
	(
		// Users to add parameters here

		// User parameters ends
		// Do not modify the parameters beyond this line


		// Parameters of Axi Slave Bus Interface S00_AXI
		parameter integer C_S00_AXI_DATA_WIDTH	= 32,
		parameter integer C_S00_AXI_ADDR_WIDTH	= 6
	)
	(
		// Users to add ports here
        input  wire [2:0] timeout,
        input  wire [2:0] error_flag,
        input  wire [2:0] critical_fault,
        input  wire       eval_tick,
        output wire [1:0] fault_level,
        output wire [1:0] fault_device,
        output wire [7:0] fault_code,
        output wire       fault_valid,
        output wire       irq,
		// User ports ends
		// Do not modify the ports beyond this line


		// Ports of Axi Slave Bus Interface S00_AXI
		input wire  s00_axi_aclk,
		input wire  s00_axi_aresetn,
		input wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_awaddr,
		input wire [2 : 0] s00_axi_awprot,
		input wire  s00_axi_awvalid,
		output wire  s00_axi_awready,
		input wire [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_wdata,
		input wire [(C_S00_AXI_DATA_WIDTH/8)-1 : 0] s00_axi_wstrb,
		input wire  s00_axi_wvalid,
		output wire  s00_axi_wready,
		output wire [1 : 0] s00_axi_bresp,
		output wire  s00_axi_bvalid,
		input wire  s00_axi_bready,
		input wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_araddr,
		input wire [2 : 0] s00_axi_arprot,
		input wire  s00_axi_arvalid,
		output wire  s00_axi_arready,
		output wire [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_rdata,
		output wire [1 : 0] s00_axi_rresp,
		output wire  s00_axi_rvalid,
		input wire  s00_axi_rready
	);
// Instantiation of Axi Bus Interface S00_AXI
	fault_manager_ip_slave_lite_v1_0_S00_AXI # ( 
		.C_S_AXI_DATA_WIDTH(C_S00_AXI_DATA_WIDTH),
		.C_S_AXI_ADDR_WIDTH(C_S00_AXI_ADDR_WIDTH)
	) fault_manager_ip_slave_lite_v1_0_S00_AXI_inst (
	    .timeout(timeout),
        .error_flag(error_flag),
        .critical_fault(critical_fault),
        .eval_tick(eval_tick),
        .fault_level(fault_level),
        .fault_device(fault_device),
        .fault_code(fault_code),
        .fault_valid(fault_valid),
        .irq(irq),
		.S_AXI_ACLK(s00_axi_aclk),
		.S_AXI_ARESETN(s00_axi_aresetn),
		.S_AXI_AWADDR(s00_axi_awaddr),
		.S_AXI_AWPROT(s00_axi_awprot),
		.S_AXI_AWVALID(s00_axi_awvalid),
		.S_AXI_AWREADY(s00_axi_awready),
		.S_AXI_WDATA(s00_axi_wdata),
		.S_AXI_WSTRB(s00_axi_wstrb),
		.S_AXI_WVALID(s00_axi_wvalid),
		.S_AXI_WREADY(s00_axi_wready),
		.S_AXI_BRESP(s00_axi_bresp),
		.S_AXI_BVALID(s00_axi_bvalid),
		.S_AXI_BREADY(s00_axi_bready),
		.S_AXI_ARADDR(s00_axi_araddr),
		.S_AXI_ARPROT(s00_axi_arprot),
		.S_AXI_ARVALID(s00_axi_arvalid),
		.S_AXI_ARREADY(s00_axi_arready),
		.S_AXI_RDATA(s00_axi_rdata),
		.S_AXI_RRESP(s00_axi_rresp),
		.S_AXI_RVALID(s00_axi_rvalid),
		.S_AXI_RREADY(s00_axi_rready)
	);

	// Add user logic here

	// User logic ends

	endmodule
