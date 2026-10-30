`default_nettype none

// RAW hazard detection for a pipeline without forwarding or RF bypass.
// check if instruction being decoded has a source used in write context
// by any instruction currently any future pipeline stage (X, M, W)
// in effect stalling until all such instructions finish W stage.
module hazard_detector (
    input wire       if_valid,
    input wire [6:0] opcode,
    input wire [4:0] rs1,
    input wire [4:0] rs2,
    input wire       ex_valid,
    input wire       ex_rewrite,
    input wire [4:0] ex_rd,
    input wire       mem_valid,
    input wire       mem_rewrite,
    input wire [4:0] mem_rd,
    input wire       wb_valid,
    input wire       wb_rewrite,
    input wire [4:0] wb_rd,
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

    // see if applicable read addrs overlap with currently pipelined write addrs
    // ex_rewrite signal used to prevent unneeded stalls (e.g. ignore rd check for S)
    wire hazard_ex = ex_valid && ex_rewrite && ex_rd != 0 &&
        ((uses_rs1 && rs1 == ex_rd) || (uses_rs2 && rs2 == ex_rd));
    wire hazard_mem = mem_valid && mem_rewrite && mem_rd != 0 &&
        ((uses_rs1 && rs1 == mem_rd) || (uses_rs2 && rs2 == mem_rd));
    wire hazard_wb = wb_valid && wb_rewrite && wb_rd != 0 &&
        ((uses_rs1 && rs1 == wb_rd) || (uses_rs2 && rs2 == wb_rd));

    assign stall = if_valid && (hazard_ex || hazard_mem || hazard_wb);
endmodule

`default_nettype wire
