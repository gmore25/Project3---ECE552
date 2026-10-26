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
    output wire [31:0] o_retire_dmem_addr,
    output wire [3:0] o_retire_dmem_mask,
    output wire o_retire_dmem_ren,
    output wire o_retire_dmem_wen,
    output wire [31:0] o_retire_dmem_rdata,
    output wire [31:0] o_retire_dmem_wdata,
    output wire [31:0] o_retire_pc,
    // the next program counter after the instruction is retired. For most
    // instructions, this is `o_retire_pc + 4`, but must be the branch or jump
    // target for *taken* branches and jumps.
    output wire [31:0] o_retire_next_pc

`ifdef RISCV_FORMAL
    ,`RVFI_OUTPUTS,
`endif
);

    localparam [31:0] NOP = 32'h00000013;
    reg [31:0] pc;
    wire [31:0] pc_plus4 = pc + 32'd4;
    assign o_imem_raddr = pc;

    // PC & INSTRUCTION FETCH
    // IF/ID holds the fetched instruction until the next stage can accept it.
    reg if_valid;
    reg [31:0] if_instr, if_pc;
    wire [31:0] if_pc4 = if_pc + 32'd4;

    // INSTRUCTION DECODE FIELDS
    wire [31:0] instr = if_instr;
    wire [6:0] opcode = instr[6:0];
    wire [4:0] rs1 = instr[19:15], rs2 = instr[24:20], rd = instr[11:7];
    wire [2:0] funct3 = instr[14:12];
    wire [6:0] funct7 = instr[31:25];
    // connecting the imm.v file to get immediate values for the instruction
    wire [5:0] fmt;
    wire [31:0] immediate;
    imm_format u_fmt (.opcode(opcode), .imm_format(fmt));
    imm u_imm (.i_inst(instr), .i_format(fmt), .o_immediate(immediate));

    wire dec_branch, dec_jal, dec_jalr, dec_m2r, dec_mread, dec_mwrite;
    wire dec_asrc, dec_rwrite, dec_uns, dec_sub, dec_arith;
    wire [2:0] dec_alu_sel;
    instruction_decoder u_dec (
        .opcode(opcode), .funct3(funct3), .funct7(funct7),
        .branch(dec_branch), .jal(dec_jal), .jalr(dec_jalr),
        .MemToReg(dec_m2r), .MemRead(dec_mread), .MemWrite(dec_mwrite),
        .alu_src(dec_asrc), .RegWrite(dec_rwrite),
        .alu_unsigned(dec_uns), .alu_sub(dec_sub), .alu_arith(dec_arith),
        .alu_sel(dec_alu_sel)
    );
    wire dec_illegal;
    instruction_checker u_chk (.instr(instr), .illegal_instr(dec_illegal));
    wire uses_rs1 = (opcode == 7'b0110011 || opcode == 7'b0010011 ||
                     opcode == 7'b0000011 || opcode == 7'b0100011 ||
                     opcode == 7'b1100011 || opcode == 7'b1100111);
    wire uses_rs2 = (opcode == 7'b0110011 || opcode == 7'b0100011 ||
                     opcode == 7'b1100011);

    // REGISTER FILE READ AND WRITE SIGNALS
    wire [31:0] wb_value;
    wire wb_wen;
    reg wb_valid, wb_rwrite, wb_m2r, wb_jlink, wb_trap, wb_halt;
    reg [31:0] wb_pc, wb_nextpc, wb_inst, wb_alu, wb_load, wb_pc4;
    reg [31:0] wb_rs1data, wb_rs2data;
    reg [4:0] wb_rs1, wb_rs2, wb_rd;
    reg [31:0] wb_daddr, wb_dwdata, wb_drdata;
    reg [3:0] wb_dmask;
    reg wb_dren, wb_dwen;
    assign wb_value = wb_jlink ? wb_pc4 : (wb_m2r ? wb_load : wb_alu);
    assign wb_wen = wb_valid && wb_rwrite && !wb_trap && (wb_rd != 0);

    wire [31:0] rs1_data, rs2_data;
    rf #(.BYPASS_EN(0)) u_rf (
        .i_clk(i_clk), .i_rst(i_rst),
        .i_rs1_raddr(rs1), .o_rs1_rdata(rs1_data),
        .i_rs2_raddr(rs2), .o_rs2_rdata(rs2_data),
        .i_rd_wen(wb_wen), .i_rd_waddr(wb_rd), .i_rd_wdata(wb_value)
    );

    // ID/EX: register operands and control signals for execution.
    reg ex_valid, ex_branch, ex_jal, ex_jalr, ex_m2r, ex_mread, ex_mwrite;
    reg ex_asrc, ex_rwrite, ex_uns, ex_sub, ex_arith, ex_illegal, ex_halt;
    reg [2:0] ex_alu_sel, ex_funct3;
    reg [6:0] ex_opcode;
    reg [4:0] ex_rs1, ex_rs2, ex_rd;
    reg [31:0] ex_pc, ex_pc4, ex_inst, ex_imm, ex_rs1data, ex_rs2data;

    // EX/MEM: hold ALU result and memory controls.
    reg mem_valid, mem_m2r, mem_mread, mem_mwrite, mem_rwrite, mem_jlink;
    reg mem_trap, mem_halt;
    reg [2:0] mem_funct3;
    reg [4:0] mem_rs1, mem_rs2, mem_rd;
    reg [31:0] mem_pc, mem_pc4, mem_nextpc, mem_inst, mem_alu;
    reg [31:0] mem_rs1data, mem_rs2data;

    // Stall on RAW dependencies until the needed register value is written back.
    wire hazard_ex = ex_valid && ex_rwrite && ex_rd != 0 &&
        ((uses_rs1 && rs1 == ex_rd) || (uses_rs2 && rs2 == ex_rd));
    wire hazard_mem = mem_valid && mem_rwrite && mem_rd != 0 &&
        ((uses_rs1 && rs1 == mem_rd) || (uses_rs2 && rs2 == mem_rd));
    wire hazard_wb = wb_valid && wb_rwrite && wb_rd != 0 &&
        ((uses_rs1 && rs1 == wb_rd) || (uses_rs2 && rs2 == wb_rd));
    wire stall = if_valid && (hazard_ex || hazard_mem || hazard_wb);

    // ALU EXECUTION and branch/jump targets
    wire [31:0] ex_op1, ex_op2, ex_alu_result;
    wire ex_eq, ex_slt;
    op1_selector u_op1 (
        .opcode(ex_opcode), .pc(ex_pc), .r1_data(ex_rs1data), .op1(ex_op1)
    );
    assign ex_op2 = ex_asrc ? ex_imm : ex_rs2data;
    alu u_alu (
        .i_opsel(ex_alu_sel), .i_sub(ex_sub),
        .i_unsigned(ex_uns), .i_arith(ex_arith),
        .i_op1(ex_op1), .i_op2(ex_op2),
        .o_result(ex_alu_result), .o_eq(ex_eq), .o_slt(ex_slt)
    );
    wire [31:0] ex_target;
    brancher u_branch (
        .branch(ex_branch), .jal(ex_jal), .jalr(ex_jalr),
        .slt(ex_slt), .eq(ex_eq), .funct3(ex_funct3),
        .pcp4(ex_pc4), .pcpimm(ex_pc + ex_imm),
        .alu_out(ex_alu_result), .next_pc(ex_target)
    );
    wire redirect = ex_valid && (ex_target != ex_pc4);
    wire [31:0] ex_nextpc = ex_target;
    wire ex_badalign;
    alignment_checker u_align (
        .opcode(ex_opcode), .funct3(ex_funct3),
        .i_addr(ex_alu_result), .misaligned_access(ex_badalign)
    );
    wire ex_trap = ex_illegal || ex_badalign ||
        ((ex_branch || ex_jal || ex_jalr) && ex_target[1:0] != 2'b00);

    // MEMORY INTERFACE: only valid instructions may read or write memory.
    wire [31:0] mem_addr, mem_wdata, mem_load;
    wire [3:0] mem_mask;
    dmem_adapter u_adapter (
        .funct3(mem_funct3), .i_addr(mem_alu), .i_data(mem_rs2data),
        .dmem_mask(mem_mask), .o_addr(mem_addr), .o_data(mem_wdata)
    );
    assign o_dmem_addr = mem_addr;
    assign o_dmem_mask = mem_mask;
    assign o_dmem_wdata = mem_wdata;
    assign o_dmem_ren = mem_valid && mem_mread && !mem_trap;
    assign o_dmem_wen = mem_valid && mem_mwrite && !mem_trap;
    load_formatter u_load (
        .funct3(mem_funct3), .i_data(i_dmem_rdata),
        .dmem_mask(mem_mask), .o_data(mem_load)
    );

    always @(posedge i_clk) begin
        if (i_rst) begin
            pc <= RESET_ADDR;
            if_valid <= 0;
            if_instr <= NOP;
            if_pc <= 0;
            ex_valid <= 0;
            mem_valid <= 0;
            wb_valid <= 0;
        end else begin
            // Redirect flushes wrong-path instructions; otherwise a stall holds IF/ID.
            if (redirect) begin
                pc <= ex_target;
                if_valid <= 0;
                if_instr <= NOP;
            end else if (!stall) begin
                pc <= pc_plus4;
                if_pc <= pc;
                if_instr <= i_imem_rdata;
                if_valid <= 1;
            end

            // ID/EX: register operands and control signals for execution.: insert bubble on RAW stall or redirect.
            if (redirect || stall) begin
                ex_valid <= 0;
            end else begin
                ex_valid <= if_valid;
                ex_pc <= if_pc; ex_pc4 <= if_pc4; ex_inst <= instr;
                ex_imm <= immediate; ex_rs1data <= rs1_data; ex_rs2data <= rs2_data;
                ex_rs1 <= rs1; ex_rs2 <= rs2; ex_rd <= rd;
                ex_funct3 <= funct3; ex_opcode <= opcode;
                ex_branch <= dec_branch; ex_jal <= dec_jal; ex_jalr <= dec_jalr;
                ex_m2r <= dec_m2r; ex_mread <= dec_mread; ex_mwrite <= dec_mwrite;
                ex_asrc <= dec_asrc; ex_rwrite <= dec_rwrite;
                ex_uns <= dec_uns; ex_sub <= dec_sub; ex_arith <= dec_arith;
                ex_alu_sel <= dec_alu_sel;
                ex_illegal <= dec_illegal; ex_halt <= instr == 32'h00100073;
            end

            // EX/MEM: hold ALU result and memory controls.
            mem_valid <= ex_valid;
            mem_pc <= ex_pc; mem_pc4 <= ex_pc4; mem_inst <= ex_inst;
            mem_nextpc <= ex_nextpc; mem_alu <= ex_alu_result;
            mem_rs1data <= ex_rs1data; mem_rs2data <= ex_rs2data;
            mem_rs1 <= ex_rs1; mem_rs2 <= ex_rs2; mem_rd <= ex_rd;
            mem_funct3 <= ex_funct3;
            mem_m2r <= ex_m2r; mem_mread <= ex_mread; mem_mwrite <= ex_mwrite;
            mem_rwrite <= ex_rwrite; mem_jlink <= ex_jal || ex_jalr;
            mem_trap <= ex_trap; mem_halt <= ex_halt;

            // MEM/WB
            wb_valid <= mem_valid;
            wb_pc <= mem_pc; wb_pc4 <= mem_pc4; wb_inst <= mem_inst;
            wb_nextpc <= mem_nextpc; wb_alu <= mem_alu; wb_load <= mem_load;
            wb_rs1data <= mem_rs1data; wb_rs2data <= mem_rs2data;
            wb_rs1 <= mem_rs1; wb_rs2 <= mem_rs2; wb_rd <= mem_rd;
            wb_m2r <= mem_m2r; wb_rwrite <= mem_rwrite; wb_jlink <= mem_jlink;
            wb_trap <= mem_trap; wb_halt <= mem_halt;
            wb_daddr <= mem_addr; wb_dmask <= mem_mask;
            wb_dren <= o_dmem_ren; wb_dwen <= o_dmem_wen;
            wb_drdata <= i_dmem_rdata; wb_dwdata <= mem_wdata;
        end
    end

    // Retire information follows the instruction through to WB.
    assign o_retire_valid = wb_valid;
    assign o_retire_inst = wb_inst;
    assign o_retire_trap = wb_trap;
    assign o_retire_halt = wb_halt;
    assign o_retire_rs1_raddr = wb_rs1;
    assign o_retire_rs2_raddr = wb_rs2;
    assign o_retire_rs1_rdata = wb_rs1data;
    assign o_retire_rs2_rdata = wb_rs2data;
    assign o_retire_rd_waddr = wb_wen ? wb_rd : 5'd0;
    assign o_retire_rd_wdata = wb_value;
    assign o_retire_pc = wb_pc;
    assign o_retire_next_pc = wb_nextpc;
    assign o_retire_dmem_addr = wb_daddr;
    assign o_retire_dmem_mask = wb_dmask;
    assign o_retire_dmem_ren = wb_dren;
    assign o_retire_dmem_wen = wb_dwen;
    assign o_retire_dmem_rdata = wb_drdata;
    assign o_retire_dmem_wdata = wb_dwdata;
endmodule
`default_nettype wire
