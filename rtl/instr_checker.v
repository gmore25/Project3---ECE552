`default_nettype none

// checks whether an instruction has an illegal value (used for o_retire_trap)
module instruction_checker (
    input  wire [31:0] instr,
    output wire        illegal_instr
);
    wire [6:0] opcode = instr[6:0];
    wire [2:0] funct3 = instr[14:12];
    wire [6:0] funct7 = instr[31:25];

    assign illegal_instr =
        (opcode == 7'b0110011) ? ( // Register ALU
            (funct7 == 7'b0100000) ?
                ((funct3 != 3'b000) && (funct3 != 3'b101)) : // SUB/SRA only if f7 = b0100000
                (funct7 != 7'b0000000)                       // otherwise must be 0
        ) :
        (opcode == 7'b0010011) ? ( // Immediate ALU
            (funct3 == 3'b001) ? (funct7 != 7'b0000000) : // SLLI
            (funct3 == 3'b101) ? ((funct7 != 7'b0000000) && (funct7 != 7'b0100000)) : // SRLI/SRAI
            1'b0
        ) :
        (opcode == 7'b0000011) ? // Load (check unused funct3)
            ((funct3 == 3'b011) || (funct3 == 3'b110) || (funct3 == 3'b111)) :
        (opcode == 7'b0100011) ? // Store (check unusued funct3)
            !((funct3 == 3'b000) || (funct3 == 3'b001) || (funct3 == 3'b010)) :
        (opcode == 7'b1100011) ? // Branch (check unused funct3)
            ((funct3 == 3'b010) || (funct3 == 3'b011)) : 
        (opcode == 7'b1100111) ? // JALR (funct3 must be 0)
            (funct3 != 3'b000) : 
        ((opcode == 7'b0110111) || (opcode == 7'b0010111) || (opcode == 7'b1101111)) ? // U/J (always good)
            1'b0 : 
        (opcode == 7'b1110011) ? (instr != 32'h00000073) : // EBREAK is all 0 except opcode according to spec
            1'b1; // Unsupported opcode
endmodule

`default_nettype wire
