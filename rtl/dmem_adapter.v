`default_nettype none

// helper module for getting specific address and mask to load/store to use
// additionally for store: does data shifting to align to correct byte/hw 
// note: this handles data alignment for Store. For Load, that has to be handled mem read side.
module dmem_adapter (
    input  wire [ 2:0] funct3,
    input  wire [31:0] i_addr,
    input  wire [31:0] i_data,
    output wire [ 3:0] dmem_mask,
    output wire [31:0] o_addr,
    output wire [31:0] o_data
);
    // zero out last two bits (for byte / half word they get used in mask):
    wire [1:0] addr_low = i_addr[1:0];
    // address itself should still be word aligned
    assign o_addr = {i_addr[31:2], 2'b00};

    // mask based on funct3[1:0] (10 = word, 01 = half word, 00 = byte) and address low bits
    // -- 11 should be unused in either L/S case
    assign dmem_mask =
        (funct3[1:0] == 2'b00) ? ( // byte
            (addr_low == 2'b00) ? 4'b0001 :
            (addr_low == 2'b01) ? 4'b0010 :
            (addr_low == 2'b10) ? 4'b0100 :
                                  4'b1000
        ) : 
        (funct3[1:0] == 2'b01) ? ( // half-word
            (addr_low == 2'b00) ? 4'b0011 :
                                  4'b1100
        ) : // word
        4'b1111; 

    // data to write is just the register value shifted to the correctly masked location:
    assign o_data =
        (funct3[1:0] == 2'b00) ? (
            (addr_low == 2'b00) ? {24'b0, i_data[7:0]} :
            (addr_low == 2'b01) ? {16'b0, i_data[7:0], 8'b0} :
            (addr_low == 2'b10) ? {8'b0, i_data[7:0], 16'b0} :
            {i_data[7:0], 24'b0}
        ) : // byte
        (funct3[1:0] == 2'b01) ? (
            (addr_low == 2'b00) ? {16'b0, i_data[15:0]} :
            {i_data[15:0], 16'b0}
        ) : // half-word
        i_data; // word
endmodule
