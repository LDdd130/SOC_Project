
`timescale 1 ns / 1 ps

//////////////////////////////////////////////////////////////////////////////////
// 파일 : fault_manager_ip_slave_lite_v1_0_S00_AXI.v
// 역할 : AXI4-Lite Slave 인터페이스 계층.
//
//        마법사가 생성한 slv_reg0~15 / 핸드셰이크 / read mux 는 제거했다.
//        레지스터 맵, W1P, W1C, Level IRQ 는 이미 src/fault_manager_axi.v 에
//        00 공통명세 9.2 / 02 문서 6장 그대로 구현되어 있고 단위 Testbench 로
//        검증을 마쳤으므로 여기서는 그 모듈을 인스턴스화만 한다.
//        마법사 로직을 남겨두면 S_AXI_RDATA 등이 이중 드라이브 되어 에러가 난다.
//
// 근거 : 00 공통명세 5.4(W1P/W1C/Level IRQ), 9.2(레지스터 맵)
//        02 팀원B 6장(레지스터 맵), 6.1(RESET_FAULT), 7장(IRQ 규칙)
//////////////////////////////////////////////////////////////////////////////////

	module fault_manager_ip_slave_lite_v1_0_S00_AXI #
	(
		// Users to add parameters here

		// User parameters ends
		// Do not modify the parameters beyond this line

		// Width of S_AXI data bus
		parameter integer C_S_AXI_DATA_WIDTH	= 32,
		// Width of S_AXI address bus
		parameter integer C_S_AXI_ADDR_WIDTH	= 6
	)
	(
		// Users to add ports here
		// heartbeat_monitor_ip 의 timeout[2:0] (00 공통명세 8.2)
		input  wire [2:0] timeout,
		// 외부/Simulator 입력 (00 공통명세 8.3)
		input  wire [2:0] error_flag,
		input  wire [2:0] critical_fault,
		// 공통 eval_tick_generator.v 의 1클럭 Pulse (00 공통명세 5.2)
		input  wire       eval_tick,
		// safety_controller_ip 로 나가는 출력 (00 공통명세 8.5)
		output wire [1:0] fault_level,
		output wire [1:0] fault_device,
		output wire [7:0] fault_code,
		output wire       fault_valid,
		// Level 방식 IRQ. xlconcat -> AXI INTC (00 공통명세 5.4)
		output wire       irq,
		// User ports ends
		// Do not modify the ports beyond this line

		// Global Clock Signal
		input wire  S_AXI_ACLK,
		// Global Reset Signal. This Signal is Active LOW
		input wire  S_AXI_ARESETN,
		// Write address (issued by master, acceped by Slave)
		input wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_AWADDR,
		// Write channel Protection type. This signal indicates the
    		// privilege and security level of the transaction, and whether
    		// the transaction is a data access or an instruction access.
		input wire [2 : 0] S_AXI_AWPROT,
		// Write address valid. This signal indicates that the master signaling
    		// valid write address and control information.
		input wire  S_AXI_AWVALID,
		// Write address ready. This signal indicates that the slave is ready
    		// to accept an address and associated control signals.
		output wire  S_AXI_AWREADY,
		// Write data (issued by master, acceped by Slave)
		input wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_WDATA,
		// Write strobes. This signal indicates which byte lanes hold
    		// valid data. There is one write strobe bit for each eight
    		// bits of the write data bus.
		input wire [(C_S_AXI_DATA_WIDTH/8)-1 : 0] S_AXI_WSTRB,
		// Write valid. This signal indicates that valid write
    		// data and strobes are available.
		input wire  S_AXI_WVALID,
		// Write ready. This signal indicates that the slave
    		// can accept the write data.
		output wire  S_AXI_WREADY,
		// Write response. This signal indicates the status
    		// of the write transaction.
		output wire [1 : 0] S_AXI_BRESP,
		// Write response valid. This signal indicates that the channel
    		// is signaling a valid write response.
		output wire  S_AXI_BVALID,
		// Response ready. This signal indicates that the master
    		// can accept a write response.
		input wire  S_AXI_BREADY,
		// Read address (issued by master, acceped by Slave)
		input wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_ARADDR,
		// Protection type. This signal indicates the privilege
    		// and security level of the transaction, and whether the
    		// transaction is a data access or an instruction access.
		input wire [2 : 0] S_AXI_ARPROT,
		// Read address valid. This signal indicates that the channel
    		// is signaling valid read address and control information.
		input wire  S_AXI_ARVALID,
		// Read address ready. This signal indicates that the slave is
    		// ready to accept an address and associated control signals.
		output wire  S_AXI_ARREADY,
		// Read data (issued by slave)
		output wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_RDATA,
		// Read response. This signal indicates the status of the
    		// read transfer.
		output wire [1 : 0] S_AXI_RRESP,
		// Read valid. This signal indicates that the channel is
    		// signaling the required read data.
		output wire  S_AXI_RVALID,
		// Read ready. This signal indicates that the master can
    		// accept the read data and response information.
		input wire  S_AXI_RREADY
	);

	// Add user logic here

	//--------------------------------------------------------------------------
	// 레지스터 맵 / AXI 핸드셰이크 / IRQ 본체 : src/fault_manager_axi.v
	//   0x00 CTRL          RW/W1P  bit0 ENABLE, bit1 RESET_FAULT(W1P)
	//   0x04 FAULT_INPUT   R       bit[2:0] timeout, bit[10:8] error_flag,
	//                              bit[18:16] critical_fault
	//   0x08 CRITICAL_MASK RW      bit[2:0], 리셋 기본값 3'b100
	//   0x0C PERSIST_LIMIT RW      bit[7:0], 리셋 기본값 5
	//   0x10 FAULT_LEVEL   R       bit[1:0]
	//   0x14 FAULT_DEVICE  R       bit[1:0]
	//   0x18 FAULT_CODE    R       bit[7:0]
	//   0x1C FAULT_COUNT   R       bit[7:0] cnt0, bit[15:8] cnt1, bit[23:16] cnt2
	//   0x20 IRQ_EN        RW      bit0 Fault Change
	//   0x24 IRQ_STATUS    R/W1C   bit0 Fault Change Pending
	//   0x2C ID            R       0x464D4752 ("FMGR") — 추가분, 팀 승인 대기
	//--------------------------------------------------------------------------
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

	// User logic ends

	endmodule
