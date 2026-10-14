`default_nettype none

// helper module for getting specific address and mask to load/store to use
module dmem (
    input  wire [ 3:0] funct3,
    input  wire [31:0] i_addr,
    input  wire [31:0] r1_data,
    output wire [ 3:0] dmem_mask,
    output wire [31:0] o_addr
);
    // zero out last two bits (for byte / half word they get used in mask):
    wire [2:0] addr_low = i_addr[1:0];
    // address itself should still be word aligned
    assign o_addr = {i_addr[31:2], 2'b00};
    // mask based on funct3[1:0] (10 = word, 01 = half word, 00 = byte) and address low bits -- 11 should be unused in either L/S case
    assign dmem_mask = 
        (funct3[1:0] == 2'b00) ? ((addr_low == 2'b00) ? 4'b0001 : (addr_low == 2'b01) ? 4'b0010 : (addr_low == 2'b10) ? 4'b0100 : 4'b1000) : // byte
        (funct3[1:0] == 2'b01) ? ((addr_low == 2'b00) ? 4'b0011 : 4'b1100) : // half-word
        4'b1111;  // word 
endmodule
