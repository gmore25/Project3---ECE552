`default_nettype none

// main branch (combinational) logic processing block: 
// only one of branch, jal, jalr can be true at a time
// slight departure from schematic: eliminates the intermediate pc_sel and directly muxes
module brancher (
    input  wire branch,
    input  wire jal,
    input  wire jalr,
    input  wire slt,
    input  wire eq,
    input  wire [2:0] funct3,
    input  wire [31:0] pcp4,
    input  wire [31:0] pcpimm,
    input  wire [31:0] alu_out,
    output wire [31:0] next_pc
);
    // note signed and unsigned logic is the same here: 
    // that nuance should be handled in the ALU
    assign next_pc = 
        jalr ? {alu_out[31:1], 1'b0} : // jalr target is ALU output, but LSB is always 0
        jal  ? pcpimm :
        (branch && funct3 == 3'b000 && eq)   ? pcpimm : // beq
        (branch && funct3 == 3'b001 && !eq)  ? pcpimm : // bne
        (branch && funct3 == 3'b100 && slt)  ? pcpimm : // blt (these can probably be simplified as funct3[2] == 1'b1)
        (branch && funct3 == 3'b101 && !slt) ? pcpimm : // bge  |
        (branch && funct3 == 3'b110 && slt)  ? pcpimm : // bltu |
        (branch && funct3 == 3'b111 && !slt) ? pcpimm : // bgeu |
        pcp4 ;
endmodule
