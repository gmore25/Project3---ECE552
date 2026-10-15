// turn opcode into one hot immediate format selection signal
module imm_format(
    input  wire [6:0] opcode,
    output wire [5:0] imm_format
);
    assign imm_format =
        (opcode == 7'b0110011) ? 6'b000001 : // R
        (opcode == 7'b0010011 || opcode == 7'b0000011 || opcode == 7'b1100111) ? 6'b000010 : // I (arith I, load, JALR)
        (opcode == 7'b0100011) ? 6'b000100 : // S
        (opcode == 7'b1100011) ? 6'b001000 : // B
        (opcode == 7'b0110111 || opcode == 7'b0010111) ? 6'b010000 : // U (LUI / AUIPC)
        (opcode == 7'b1101111) ? 6'b100000 : // J (Jal)
        6'b000001; // R (no immediate as default)
endmodule
