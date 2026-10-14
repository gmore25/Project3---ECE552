`default_nettype none

// helper module for instruction decoding.
// takes opcode + function fields and outputs several control signals
module instruction_decoder (
    input  wire [6:0] opcode,
    input  wire [2:0] funct3,
    input  wire [6:0] funct7,
    // branch instruction: signal to branch logic to use PC+imm if conditions fulfilled
    output wire       branch,
    // jump instruction: signal to branch logic to use PC+imm unconditionally
    output wire       jal,
    // jump and link register instruction: signal to branch logic to use ALU output unconditionally
    output wire       jalr,
    // load instruction: signal to memory to read from address in ALU output
    output wire       MemToReg,
    // store instruction: signal to memory to write to address in ALU output
    output wire       MemWrite,
    // ALU source: signal to ALU to use immediate as second operand instead of register
    output wire       alu_src,
    // Non-store/branch instruction: write to register file with either mem or ALU output
    output wire       RegWrite,
    // whether ALU should do unsigned comparison (for SLT(I)U, BLTU, BGEU)
    output wire       alu_unsigned,
    output wire       alu_sub,
    output wire       alu_arith,
    output wire [2:0] alu_sel
    // TODO: additional output to detect illegal instructions?
);
    assign branch   = (opcode == 7'b1100011); // B only
    assign jal      = (opcode == 7'b1101111); // J only
    assign jalr     = (opcode == 7'b1100111); // Jalr (I) only
    assign MemToReg = (opcode == 7'b0000011); // Load (I) only 
    assign MemWrite = (opcode == 7'b0100011); // Store (S) only
    // 0 only if R or B type, 1 otherwise
    assign alu_src  = (opcode != 7'b0110011) && (opcode != 7'b1100011);
    // 0 only if S or B type, 1 otherwise
    assign RegWrite = (opcode != 7'b0100011) && (opcode != 7'b1100011);
    // funct3 bits that denote unsigned different between SLT(I)U and BLTU/BGEU
    assign alu_unsigned = 
        ((opcode == 7'b0010011 || opcode == 7'b0110011) && funct3 == 3'b011) || // SLT(I)U 
        (opcode == 7'b1100011 && funct3[2:1] == 2'b11);   // BLT/GEU    
    assign alu_sub = (opcode == 7'b0110011) && (funct7 == 7'b0100000); // SUB only for R-type
    assign alu_arith = (opcode == 7'b0110011 || opcode == 7'b0010011) && (funct7 == 7'b0100000); // R/I type
    // R/I type: funct3, else default to ADD for other types (r[rs1] + imm for L, S, Jalr -- unused for rest (J/U))
    assign alu_sel = (opcode == 7'b0110011 || opcode == 7'b0010011) ?  funct3 : 3'b000;
endmodule
