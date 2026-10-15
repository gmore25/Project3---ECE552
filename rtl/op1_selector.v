`default_nettype none

// helper module for operand 1 decoding.
module op1_selector (
    input  wire [ 6:0] opcode,
    input  wire [31:0] pc,
    input  wire [31:0] r1_data,
    output wire [31:0] op1
);
    // TODO: possibly handle other types (e.g. J/JALR) through this mechanism
    assign op1 =
        (opcode == 7'b0110111) ? 32'b0 : // LUI   -- op1 = 0
        (opcode == 7'b0010111) ? pc    : // AUIPC -- op1 = pc
        r1_data;                         // otherwise: use r[rs1]
endmodule
