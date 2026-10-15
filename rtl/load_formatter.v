`default_nettype none

// handles data load complications (formatting resultant data)
module load_formatter (
    input  wire [ 2:0] funct3,
    input  wire [31:0] i_data,
    input  wire [ 3:0] dmem_mask,
    output wire [31:0] o_data
);
    // 1 = sign extend, 0 = zero extend (anded with the 'sign bit' for effect)
    wire signext = (funct3[2] == 1'b0);
    assign o_data = 
        (funct3[1:0] == 2'b00) ? (
            (dmem_mask == 4'b0001) ? {{24{i_data[7] & signext}}, i_data[7:0]} :    // 0001
            (dmem_mask == 4'b0010) ? {{24{i_data[15] & signext}}, i_data[15:8]} :  // 0010
            (dmem_mask == 4'b0100) ? {{24{i_data[23] & signext}}, i_data[23:16]} : // 0100
            {{24{i_data[31] & signext}}, i_data[31:24]}                            // 1000
        ) :
        ( funct3[1:0] == 2'b01) ? (
            (dmem_mask == 4'b0011) 
            ? {{16{i_data[15] & signext}}, i_data[15:0]}  // 0011
            : {{16{i_data[31] & signext}}, i_data[31:16]} // 1100
        ) :
        i_data; // 1111
endmodule
