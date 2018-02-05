
`define OP_LOAD_A	4'h0
`define OP_LOAD_B	4'h1
`define OP_ADD		4'h2
`define OP_SUB		4'h3
`define OP_INC		4'h4
`define OP_DEC		4'h5
`define OP_ASL		4'h6
`define OP_LSR		4'h7
`define OP_OR		4'h8
`define OP_AND		4'h9
`define OP_XOR		4'ha
`define OP_NOP		4'hf

module ALU(
  input  [7:0] A,
  input  [7:0] B,
  output [8:0] Y,
  input  [3:0] aluop
);
  
  always @(*)
    case (aluop)
      `OP_LOAD_A:	Y = {1'b0, A};
      `OP_LOAD_B:	Y = {1'b0, B};
      `OP_ADD:		Y = A + B;
      `OP_SUB:		Y = A - B;
      `OP_INC:		Y = A + 1;
      `OP_DEC:		Y = A - 1;
      `OP_ASL:		Y = A + A;
      `OP_LSR:		Y = {A[0], A >> 1};
      `OP_OR:		Y = {1'b0, A | B};
      `OP_AND:		Y = {1'b0, A & B};
      `OP_XOR:		Y = {1'b0, A ^ B};
      default:		Y = 9'bx;
    endcase
  
endmodule

`define DEST_A   2'b00
`define DEST_B   2'b01
`define DEST_IP  2'b10
`define DEST_NOP 2'b11
`define I_COMPUTE(dest,op) { 2'b00, 2'(dest), 4'(op) }
`define I_LOAD_IMM_A { 2'b01, `DEST_A, `OP_LOAD_A }
`define I_LOAD_IMM_B { 2'b01, `DEST_B, `OP_LOAD_B }
`define I_JUMP_IMM { 2'b01, `DEST_IP, `OP_NOP }
`define I_STORE_B(op) { 4'b01100, 4'(op) }
`define I_STORE_IMM(op) { 4'b01101, 4'(op) }
`define I_RESET { 8'hff }

module CPU(
  input        clk,
  input        reset,
  output [7:0] address,
  input  [7:0] data_in,
  output [7:0] data_out,
  output       write
);
  
  reg [7:0] IP;
  reg [7:0] A, B;
  reg [8:0] Y;
  reg [2:0] state;
  
  reg carry;
  reg zero;
  wire [1:0] flags = { zero, carry };

  reg [7:0] opcode;
  wire [3:0] aluop = opcode[3:0];
  wire [1:0] opdest = opcode[5:4];

  localparam S_RESET = 0;
  localparam S_SELECT = 1;
  localparam S_DECODE = 2;
  localparam S_LOAD_ADDR = 3;
  localparam S_STORE_ADDR = 4;
  localparam S_COMPUTE = 5;

  ALU alu(.A(A), .B(B), .Y(Y), .aluop(aluop));
  
  always @(posedge clk)
    if (reset) begin
      state <= 0;
      write <= 0;
    end else begin
      case (state)
        // state 0: reset
        S_RESET: begin
          IP <= 8'h80;
          write <= 0;
          state <= S_SELECT;
        end
	// state 1: select opcode address
        S_SELECT: begin
          address <= IP;
          IP <= IP + 1;
          write <= 0;
          state <= S_DECODE;
        end
        // state 2: read/decode opcode
        S_DECODE: begin
          opcode <= data_in;
          casez (data_in)
            // ALU A + B -> dest
            8'b00??????: begin
              state <= S_COMPUTE;
            end
            // ALU A + immediate -> dest
            8'b01??????: begin
	      address <= IP;
       	      IP <= IP + 1;
              state <= S_LOAD_ADDR;
            end
            // read[B] -> dest, ALU A + B -> dest
            8'b10??????: begin
              address <= B;
              state <= S_LOAD_ADDR;
            end
            // ALU A + B -> write [B] -> dest
            8'b1100????: begin
              address <= B;
              state <= S_STORE_ADDR;
            end
            // ALU A + B -> write [immediate] -> dest
            8'b1101????: begin
	      address <= IP;
       	      IP <= IP + 1;
              state <= S_STORE_ADDR;
            end
            // fall-through RESET
            default: begin
              state <= S_RESET; // reset
            end
          endcase
        end
        // state 3: load address
        S_LOAD_ADDR: begin
          case (opdest)
            `DEST_A: A <= data_in;
            `DEST_B: B <= data_in;
            `DEST_IP: IP <= data_in;
            // use ALU-op for conditional branch
            `DEST_NOP: if (
              (aluop[0] && (aluop[1] ^ carry)) ||
              (aluop[2] && (aluop[3] ^ zero)))
                IP <= data_in;
          endcase
          // short-circuit ALU for branches
          state <= opdest[1] ? S_SELECT : S_COMPUTE;
        end
        // state 4: store address
        S_STORE_ADDR: begin
          data_out <= Y[7:0];
          write <= 1;
          state <= S_SELECT;
        end
        // state 5: compute ALU op and flags
        S_COMPUTE: begin
          case (opdest)
            `DEST_A: A <= Y[7:0];
            `DEST_B: B <= Y[7:0];
            `DEST_IP: IP <= Y[7:0];
            `DEST_NOP: ;
          endcase
          carry <= Y[8];
          zero <= ~|Y;
          state <= S_SELECT;
        end
      endcase
    end

endmodule

module test_CPU_top(
  input  clk,
  input  reset,
  output [7:0] address_bus,
  output reg [7:0] to_cpu,
  output [7:0] from_cpu,
  output write_enable,
  output [7:0] IP,
  output [7:0] A,
  output [7:0] B
);

  reg [7:0] ram[127:0];
  reg [7:0] rom[127:0];
  
  assign IP = cpu.IP;
  assign A = cpu.A;
  assign B = cpu.B;
  
  CPU cpu(.clk(clk),
          .reset(reset),
          .address(address_bus),
          .data_in(to_cpu),
          .data_out(from_cpu),
          .write(write_enable));

  // does not work as (posedge clk)
  always @(*)
    if (write_enable)
      ram[address_bus[6:0]] = from_cpu;
    else if (address_bus[7] == 0)
      to_cpu = ram[address_bus[6:0]];
    else
      to_cpu = rom[address_bus[6:0]];
  
  initial begin
    // address 0x80
    rom['h00] = `I_LOAD_IMM_A;
    rom['h01] = 42;
    rom['h02] = `I_COMPUTE(`DEST_A, `OP_ASL);
    rom['h03] = `I_COMPUTE(`DEST_B, `OP_INC);
    rom['h04] = `I_STORE_B(`OP_LOAD_B);
    rom['h05] = `I_RESET;
  end

endmodule