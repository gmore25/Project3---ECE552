`default_nettype none

// RAW hazard detection with RF bypass and EX/MEM -> EX forwarding
// only remaining stalling hazard is use-after-load
// otherwise: it can come from EX/MEM via forwarding or WB via RF bypass
module hazard_detector (
    input wire       if_valid,
    input wire [6:0] opcode,
    input wire [4:0] rs1,
    input wire [4:0] rs2,
    input wire       ex_valid,
    input wire       ex_rewrite,
    input wire [4:0] ex_rd,
    input wire       ex_mread,
    output wire      stall
);
    // consider whether rs1/2 are used in read context
    wire uses_rs1 = (
        opcode == 7'b0110011 ||  // R
        opcode == 7'b0010011 ||  // I
        opcode == 7'b0000011 ||  // L
        opcode == 7'b0100011 ||  // S
        opcode == 7'b1100011 ||  // B
        opcode == 7'b1100111     // JALR
    );
    wire uses_rs2 = (
        opcode == 7'b0110011 ||  // R
        opcode == 7'b0100011 ||  // S
        opcode == 7'b1100011     // B
    );

    // A load in EX cannot forward its data to the next EX instruction.
    wire hazard_ex = ex_valid && ex_rewrite && ex_rd != 0 &&
        ((uses_rs1 && rs1 == ex_rd) || (uses_rs2 && rs2 == ex_rd));
    wire load_use_hazard = hazard_ex && ex_mread;

    // Forwarding resolves ALU dependencies.
    // A load-use dependency still needs one bubble.
    assign stall = if_valid && load_use_hazard;
endmodule

`default_nettype wire
