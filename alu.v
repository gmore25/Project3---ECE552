`default_nettype none

// The arithmetic logic unit (ALU) is responsible for performing the core
// calculations of the processor. It takes two 32-bit operands and outputs
// a 32 bit result based on the selection operation - addition, comparison,
// shift, or logical operation. This ALU is a purely combinational block, so
// you should not attempt to add any registers or pipeline it.
module alu (
    // NOTE: Both 3'b010 and 3'b011 are used for set less than operations and
    // your implementation should output the same result for both codes. The
    // reason for this will become clear in project 3.
    //
    // Major operation selection.
    // 3'b000: addition/subtraction if `i_sub` asserted
    // 3'b001: shift left logical
    // 3'b010,
    // 3'b011: set less than/unsigned if `i_unsigned` asserted
    // 3'b100: exclusive or
    // 3'b101: shift right logical/arithmetic if `i_arith` asserted
    // 3'b110: or
    // 3'b111: and
    input  wire [ 2:0] i_opsel,
    // When asserted, addition operations should subtract instead.
    // This is only used for `i_opsel == 3'b000` (addition/subtraction).
    input  wire        i_sub,
    // When asserted, comparison operations should be treated as unsigned.
    // This is used for branch comparisons and set less than unsigned. For
    // b ranch operations, the ALU result is not used, only the comparison
    // results.
    input  wire        i_unsigned,
    // When asserted, right shifts should be treated as arithmetic instead of
    // logical. This is only used for `i_opsel == 3'b101` (shift right).
    input  wire        i_arith,
    // First 32-bit input operand.
    input  wire [31:0] i_op1,
    // Second 32-bit input operand.
    input  wire [31:0] i_op2,
    // 32-bit output result. Any carry out should be ignored.
    output wire [31:0] o_result,
    // Equality result. This is used externally to determine if a branch
    // should be taken.
    output wire        o_eq,
    // Set less than result. This is used externally to determine if a branch
    // should be taken.
    output wire        o_slt
);
    wire [31:0] and_result;
    wire [31:0] or_result;
    wire [31:0] xor_result;

    assign and_result = i_op1 & i_op2; // Bitwise AND operation between the two operands
    assign or_result  = i_op1 | i_op2; // Bitwise OR operation between the two operands
    assign xor_result = i_op1 ^ i_op2; // Bitwise XOR operation between the two operands

    assign o_eq  = (i_op1 == i_op2); // Equality result based on the comparison of the two operands

    wire [31:0] adder_op2; // The second operand for the adder, which may be inverted for subtraction
    wire [31:0] add_result; // The result of the addition or subtraction operation

    assign adder_op2 = (i_sub) ? ~i_op2 : i_op2; // If subtracting, invert the second operand for two's complement addition
    assign add_result = i_op1 + adder_op2 + (i_sub ? 32'b1 : 32'b0); // Add the operands, adding 1 if subtracting to complete two's complement

    wire unsigned_slt;
    wire signed_slt;
    wire [31:0] slt_result;
    assign unsigned_slt = (i_op1 < i_op2); // Unsigned comparison
    assign signed_slt = (i_op1[31] != i_op2[31]) ? i_op1[31] : (i_op1 < i_op2); // Signed comparison

    assign o_slt = i_unsigned ? unsigned_slt : signed_slt; // Select signed or unsigned comparison
    assign slt_result = {31'b0, o_slt}; // SLT result is either 32'd0 or 32'd1

    // Shift left logical (SLL) operation. The shift amount is determined by the lower 5 bits of `i_op2`.
    wire [31:0] sll_1;
    wire [31:0] sll_2;
    wire [31:0] sll_4;
    wire [31:0] sll_8;
    wire [31:0] sll_result;

    assign sll_1 = i_op2[0] ? {i_op1[30:0], 1'b0} : i_op1;
    assign sll_2 = i_op2[1] ? {sll_1[29:0], 2'b0} : sll_1;
    assign sll_4 = i_op2[2] ? {sll_2[27:0], 4'b0} : sll_2;
    assign sll_8 = i_op2[3] ? {sll_4[23:0], 8'b0} : sll_4;
    assign sll_result = i_op2[4] ? {sll_8[15:0], 16'b0} : sll_8;

    // Shift right logical (SRL) operation. The shift amount is determined by the lower 5 bits of `i_op2`.
    wire [31:0] srl_1;
    wire [31:0] srl_2;
    wire [31:0] srl_4;
    wire [31:0] srl_8;
    wire [31:0] srl_result;

    assign srl_1 = i_op2[0] ? {1'b0, i_op1[31:1]} : i_op1;
    assign srl_2 = i_op2[1] ? {2'b0, srl_1[31:2]} : srl_1;
    assign srl_4 = i_op2[2] ? {4'b0, srl_2[31:4]} : srl_2;
    assign srl_8 = i_op2[3] ? {8'b0, srl_4[31:8]} : srl_4;
    assign srl_result = i_op2[4] ? {16'b0, srl_8[31:16]} : srl_8;

    // Shift right arithmetic (SRA) operation. The shift amount is determined by the lower 5 bits of `i_op2`.
    wire sign;
    wire [31:0] sra_1;
    wire [31:0] sra_2;
    wire [31:0] sra_4;
    wire [31:0] sra_8;
    wire [31:0] sra_result;

    assign sign = i_op1[31];

    assign sra_1 = i_op2[0]
                ? {sign, i_op1[31:1]}
                : i_op1;

    assign sra_2 = i_op2[1]
                ? {{2{sign}}, sra_1[31:2]}
                : sra_1;

    assign sra_4 = i_op2[2]
                ? {{4{sign}}, sra_2[31:4]}
                : sra_2;

    assign sra_8 = i_op2[3]
                ? {{8{sign}}, sra_4[31:8]}
                : sra_4;

    assign sra_result = i_op2[4]
                    ? {{16{sign}}, sra_8[31:16]}
                    : sra_8;

    // The final result is selected based on the operation selection input.
    // The priority of operations is determined by the order of the conditional
    // statements. If `i_opsel` does not match any of the specified cases,
    // the default operation is AND.
    assign o_result = (i_opsel == 3'b000) ? add_result :
                      (i_opsel == 3'b001) ? sll_result :
                      (i_opsel == 3'b010) ? slt_result :
                      (i_opsel == 3'b011) ? slt_result :
                      (i_opsel == 3'b100) ? xor_result :
                      (i_opsel == 3'b101) ? (i_arith ? sra_result : srl_result) :
                      (i_opsel == 3'b110) ? or_result :
                                           and_result;

endmodule

`default_nettype wire
