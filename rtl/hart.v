module hart #(
    // After reset, the program counter (PC) should be initialized to this
    // address and start executing instructions from there.
    parameter RESET_ADDR = 32'h00000000
) (
    // Global clock.
    input  wire        i_clk,
    // Synchronous active-high reset.
    input  wire        i_rst,
    // Instruction fetch goes through a read only instruction memory (imem)
    // port. The port accepts a 32-bit address (e.g. from the program counter)
    // per cycle and combinationally returns a 32-bit instruction word. This
    // is not representative of a realistic memory interface; it has been
    // modeled as more similar to a DFF or SRAM to simplify phase 3. In
    // later phases, you will replace this with a more realistic memory.
    //
    // 32-bit read address for the instruction memory. This is expected to be
    // 4 byte aligned - that is, the two LSBs should be zero.
    output wire [31:0] o_imem_raddr,
    // Instruction word fetched from memory, available on the same cycle.
    input  wire [31:0] i_imem_rdata,
    // Data memory accesses go through a separate read/write data memory (dmem)
    // that is shared between read (load) and write (stored). The port accepts
    // a 32-bit address, read or write enable, and mask (explained below) each
    // cycle. Reads are combinational - values are available immediately after
    // updating the address and asserting read enable. Writes occur on (and
    // are visible at) the next clock edge.
    //
    // Read/write address for the data memory. This should be 32-bit aligned
    // (i.e. the two LSB should be zero). See `o_dmem_mask` for how to perform
    // half-word and byte accesses at unaligned addresses.
    output wire [31:0] o_dmem_addr,
    // When asserted, the memory will perform a read at the aligned address
    // specified by `i_addr` and return the 32-bit word at that address
    // immediately (i.e. combinationally). It is illegal to assert this and
    // `o_dmem_wen` on the same cycle.
    output wire        o_dmem_ren,
    // When asserted, the memory will perform a write to the aligned address
    // `o_dmem_addr`. When asserted, the memory will write the bytes in
    // `o_dmem_wdata` (specified by the mask) to memory at the specified
    // address on the next rising clock edge. It is illegal to assert this and
    // `o_dmem_ren` on the same cycle.
    output wire        o_dmem_wen,
    // The 32-bit word to write to memory when `o_dmem_wen` is asserted. When
    // write enable is asserted, the byte lanes specified by the mask will be
    // written to the memory word at the aligned address at the next rising
    // clock edge. The other byte lanes of the word will be unaffected.
    output wire [31:0] o_dmem_wdata,
    // The dmem interface expects word (32 bit) aligned addresses. However,
    // the processor supports byte and half-word loads and stores at unaligned and
    // 16-bit aligned addresses, respectively. To support this, the access
    // mask specifies which bytes within the 32-bit word are actually read
    // from or written to memory.
    //
    // To perform a half-word read at address 0x00001002, align `o_dmem_addr`
    // to 0x00001000, assert `o_dmem_ren`, and set the mask to 0b1100 to
    // indicate that only the upper two bytes should be read. Only the upper
    // two bytes of `i_dmem_rdata` can be assumed to have valid data; to
    // calculate the final value of the `lh[u]` instruction, shift the rdata
    // word right by 16 bits and sign/zero extend as appropriate.
    //
    // To perform a byte write at address 0x00002003, align `o_dmem_addr` to
    // `0x00002000`, assert `o_dmem_wen`, and set the mask to 0b1000 to
    // indicate that only the upper byte should be written. On the next clock
    // cycle, the upper byte of `o_dmem_wdata` will be written to memory, with
    // the other three bytes of the aligned word unaffected. Remember to shift
    // the value of the `sb` instruction left by 24 bits to place it in the
    // appropriate byte lane.
    output wire [ 3:0] o_dmem_mask,
    // The 32-bit word read from data memory. When `o_dmem_ren` is asserted,
    // this will immediately reflect the contents of memory at the specified
    // address, for the bytes enabled by the mask. When read enable is not
    // asserted, or for bytes not set in the mask, the value is undefined.
    input  wire [31:0] i_dmem_rdata,
	// The output `retire` interface is used to signal to the testbench that
    // the CPU has completed and retired an instruction. A single cycle
    // implementation will assert this every cycle; however, a pipelined
    // implementation that needs to stall (due to internal hazards or waiting
    // on memory accesses) will not assert the signal on cycles where the
    // instruction in the writeback stage is not retiring.
    //
    // Asserted when an instruction is being retired this cycle. If this is
    // not asserted, the other retire signals are ignored and may be left invalid.
    output wire        o_retire_valid,
    // The 32 bit instruction word of the instrution being retired. This
    // should be the unmodified instruction word fetched from instruction
    // memory.
    output wire [31:0] o_retire_inst,
    // Asserted if the instruction produced a trap, due to an illegal
    // instruction, unaligned data memory access, or unaligned instruction
    // address on a taken branch or jump.
    output wire        o_retire_trap,
    // Asserted if the instruction is an `ebreak` instruction used to halt the
    // processor. This is used for debugging and testing purposes to end
    // a program.
    output wire        o_retire_halt,
    // The first register address read by the instruction being retired. If
    // the instruction does not read from a register (like `lui`), this is
    // don't-care -- the grading testbench doesn't look at it in that case.
    output wire [ 4:0] o_retire_rs1_raddr,
    // The second register address read by the instruction being retired. If
    // the instruction does not read from a second register (like `addi`),
    // this is don't-care -- the grading testbench doesn't look at it in that
    // case.
    output wire [ 4:0] o_retire_rs2_raddr,
    // The first source register data read from the register file (in the
    // decode stage) for the instruction being retired. If rs1 is 5'd0, this
    // should also be 32'd0.
    output wire [31:0] o_retire_rs1_rdata,
    // The second source register data read from the register file (in the
    // decode stage) for the instruction being retired. If rs2 is 5'd0, this
    // should also be 32'd0.
    output wire [31:0] o_retire_rs2_rdata,
    // The destination register address written by the instruction being
    // retired. If the instruction does not write to a register (like `sw`),
    // this should be 5'd0.
    output wire [ 4:0] o_retire_rd_waddr,
    // The destination register data written to the register file in the
    // writeback stage by this instruction. If rd is 5'd0, this field is
    // ignored and can be treated as a don't care.
    output wire [31:0] o_retire_rd_wdata,
    // The current program counter of the instruction being retired - i.e.
    // the instruction memory address that the instruction was fetched from.
    output wire [31:0] o_retire_pc,
    // the next program counter after the instruction is retired. For most
    // instructions, this is `o_retire_pc + 4`, but must be the branch or jump
    // target for *taken* branches and jumps.
    output wire [31:0] o_retire_next_pc

`ifdef RISCV_FORMAL
    ,`RVFI_OUTPUTS,
`endif
);
    // PC & INSTRUCTION FETCH
    reg [31:0] pc;
    wire [31:0] pc_plus4;
    wire [31:0] next_pc;

    assign pc_plus4 = pc + 32'd4; // calculate next PC

    always @(posedge i_clk) begin
        if (i_rst)
            pc <= RESET_ADDR;
        else
            pc <= next_pc;
    end

    // Address sent to external instruction memory.
    assign o_imem_raddr = pc;

    // Instruction returned by external memory.
    wire [31:0] instr;
    assign instr = i_imem_rdata;

    // INSTRUCTION DECODE FIELDS
    wire [6:0] opcode;
    wire [4:0] rd;
    wire [2:0] funct3;
    wire [4:0] rs1;
    wire [4:0] rs2;
    wire [6:0] funct7;

    // BRANCH AND JUMP TARGETS
    wire [31:0] pc_plus_imm;
    wire branch;
    wire jal;
    wire jalr;

    wire mem_to_reg;
    wire mem_read;
    wire mem_write;
    wire alu_src;
    wire decoder_reg_write;

    assign opcode = instr[6:0];
    assign rd     = instr[11:7];
    assign funct3 = instr[14:12];
    assign rs1    = instr[19:15];
    assign rs2    = instr[24:20];
    assign funct7 = instr[31:25];

    // RV32I instruction classes.
    wire is_rtype;
    wire is_itype_alu;

    assign is_rtype     = (opcode == 7'b0110011);
    assign is_itype_alu = (opcode == 7'b0010011);

    // CONNECT IMMEDIATE VALUES FROM imm.v MODULE
    // connecting the imm.v file to get immediate values for the instruction
    wire [5:0] inst_format;
    wire [31:0] immediate;
    assign pc_plus_imm = pc + immediate;

    // IMMEDIATE FORMAT DECODER
    imm_format u_imm_format (
        .opcode(opcode),
        .imm_format(inst_format)
    );

    imm u_imm (
        .i_inst(instr),
        .i_format(inst_format),
        .o_immediate(immediate)
    );

    // ALU CONTROL SIGNALS ******
    wire [2:0] alu_opsel;
    wire alu_sub;
    wire alu_unsigned;
    wire alu_arith;
    wire illegal_instr;

    instruction_checker u_instr_checker (
        .instr(instr),
        .illegal_instr(illegal_instr)
    );

    instruction_decoder u_decoder (
        .opcode(opcode),
        .funct3(funct3),
        .funct7(funct7),

        .branch(branch),
        .jal(jal),
        .jalr(jalr),

        .MemToReg(mem_to_reg),
        .MemRead(mem_read),
        .MemWrite(mem_write),

        .alu_src(alu_src),
        .RegWrite(decoder_reg_write),

        .alu_unsigned(alu_unsigned),
        .alu_sub(alu_sub),
        .alu_arith(alu_arith),
        .alu_sel(alu_opsel)
    );

    // REGISTER FILE READ AND WRITE SIGNALS
    wire [31:0] rs1_data;
    wire [31:0] rs2_data;

    wire        reg_write_en;
    wire [31:0] reg_write_data;

    rf #(
        .BYPASS_EN(0)
    ) u_rf (
        .i_clk(i_clk),
        .i_rst(i_rst),

        .i_rs1_raddr(rs1),
        .o_rs1_rdata(rs1_data),

        .i_rs2_raddr(rs2),
        .o_rs2_rdata(rs2_data),

        .i_rd_wen(reg_write_en),
        .i_rd_waddr(rd),
        .i_rd_wdata(reg_write_data)
    );

    // ALU EXECUTION ********
    wire [31:0] alu_operand_a;
    wire [31:0] alu_operand_b;
    wire [31:0] alu_result;

    wire alu_eq;
    wire alu_slt;

    op1_selector u_op1_selector (
        .opcode(opcode),
        .pc(pc),
        .r1_data(rs1_data),
        .op1(alu_operand_a)
    );

    assign alu_operand_b = alu_src ? immediate : rs2_data;

    alu u_alu (
        .i_opsel(alu_opsel),
        .i_sub(alu_sub),
        .i_unsigned(alu_unsigned),
        .i_arith(alu_arith),

        .i_op1(alu_operand_a),
        .i_op2(alu_operand_b),

        .o_result(alu_result),
        .o_eq(alu_eq),
        .o_slt(alu_slt)
    );

    // Connecting brancher.v
    brancher u_brancher (
        .branch(branch),
        .jal(jal),
        .jalr(jalr),

        .slt(alu_slt),
        .eq(alu_eq),
        .funct3(funct3),

        .pcp4(pc_plus4),
        .pcpimm(pc_plus_imm),
        .alu_out(alu_result),

        .next_pc(next_pc)
    );

    // MEMORY INTERFACE ********

    wire misaligned_access;
    alignment_checker u_alignment_checker (
        .opcode(opcode),
        .funct3(funct3),
        .i_addr(alu_result),
        .misaligned_access(misaligned_access)
    );

    // mask and aligning for store and load
    dmem_adapter u_dmem_adapter (
        .funct3(funct3),
        .i_addr(alu_result),
        .i_data(rs2_data),
        .dmem_mask(o_dmem_mask),
        .o_addr(o_dmem_addr),
        .o_data(o_dmem_wdata)
    );

    // loaded value formatting (sign/zero extend, shift to correct byte)
    wire [31:0] load_data;
    load_formatter u_load_formatter (
        .funct3(funct3),
        .i_data(i_dmem_rdata),
        .dmem_mask(o_dmem_mask),
        .o_data(load_data)
    );

    assign reg_write_en = decoder_reg_write;
    assign reg_write_data = mem_to_reg ? load_data : alu_result;
    
    // per instructions: " For project 3, your single cycle processor should assert o_retire_valid every cycle."
    assign o_retire_valid = 1'b1;

    wire misaligned_nextpc;
    assign misaligned_nextpc = (next_pc[1:0] != 2'b00);

    // more complex logic for o_retire_trap and o_retire_halt:
    assign o_retire_trap = misaligned_access || illegal_instr || misaligned_nextpc; // placeholder
    assign o_retire_halt = (opcode == 7'b1110011); // check if ebreak

    // pipe along rest of the retire values:
    assign o_retire_inst = instr;
    assign o_retire_rs1_raddr = rs1;
    assign o_retire_rs2_raddr = rs2;
    assign o_retire_rs1_rdata = rs1_data;
    assign o_retire_rs2_rdata = rs2_data;
    assign o_retire_rd_waddr = rd;
    assign o_retire_rd_wdata = reg_write_data;
    assign o_retire_pc = pc;
    assign o_retire_next_pc = next_pc;
endmodule

`default_nettype wire
