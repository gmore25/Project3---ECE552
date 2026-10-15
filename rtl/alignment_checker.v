`default_nettype none

// checks that the addresses used in a memory access are aligned to correct granularity
module alignment_checker (
    input  wire [ 6:0] opcode,
    input  wire [ 2:0] funct3,
    input  wire [31:0] i_addr,
    output wire        misaligned_access
);
    wire load = (opcode == 7'b0000011);
    wire store = (opcode == 7'b0100011);

    assign misaligned_access = (load || store) ? (
        ((funct3 == 3'b001) || (load && (funct3 == 3'b101))) ? // LH/LHU/SH -- HW align
            i_addr[0] : 
        (funct3 == 3'b010) ? // LW/SW -- word align 
            (i_addr[1:0] != 2'b00) : 
        1'b0 // Byte accesses (unsupported will be filtered out by instruction checker)
    ) : 1'b0;
endmodule

`default_nettype wire
