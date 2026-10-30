`default_nettype none

// Combinational branch/jump control. 
// Only one of branch, jal, jalr can be true at a time.
module brancher (
    input  wire branch,
    input  wire jal,
    input  wire jalr,
    input  wire slt,
    input  wire eq,
    input  wire [2:0] funct3,
    output wire is_hop,         // hop to specified value rather than step to +4
    output wire is_jalr_target  // choose between new PC value used for JALR or B/J
);
    // note signed and unsigned logic is the same here: 
    // that nuance should be handled in the ALU
    wire branch_condition =
        (funct3 == 3'b000 && eq)   || // BEQ
        (funct3 == 3'b001 && !eq)  || // BNE
        (funct3 == 3'b100 && slt)  || // BLT
        (funct3 == 3'b101 && !slt) || // BGE
        (funct3 == 3'b110 && slt)  || // BLTU
        (funct3 == 3'b111 && !slt);   // BGEU

    assign is_hop = jal || jalr || (branch && branch_condition);
    assign is_jalr_target = jalr;
endmodule

`default_nettype wire
