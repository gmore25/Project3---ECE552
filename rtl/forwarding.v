`default_nettype none

// value forwarding (EX->EX, Mem->EX)
/*
    EX-EX forwarding   (alu-op -> alu-op -- immediate next instruction uses value)
    MEM-EX forwarding  (memread / alu passthru -> alu-op -- use output of mem read or 1 instr skip)
*/
module forwarding (
    input  wire [ 4:0] ex_rs1,
    input  wire [ 4:0] ex_rs2,
    input  wire [31:0] ex_rs1data,
    input  wire [31:0] ex_rs2data,
    input  wire        mem_valid,
    input  wire        mem_rewrite,
    input  wire        mem_trap,
    input  wire        mem_mread,
    input  wire [ 4:0] mem_rd,
    input  wire [31:0] mem_forward_value,
    input  wire        wb_valid,
    input  wire        wb_wen,
    input  wire [ 4:0] wb_rd,
    input  wire [31:0] wb_forward_value,
    output wire [31:0] rs1_out,
    output wire [31:0] rs2_out
);
    // TODO: have signal consolidation into a mem_wb signal that's reused in wb?
    wire mem_wen = mem_valid && !mem_trap && mem_rewrite && (mem_rd != 5'd0);
    wire forward_rs1_mem;
    wire forward_rs2_mem;
    wire forward_rs1_wb;
    wire forward_rs2_wb;
    wire [31:0] ex_rs1_forwarded;
    wire [31:0] ex_rs2_forwarded;

    // EX->EX forwarding (old ex result now in mem)
    // wb check alone should suffice: hazard check stalls a load instr after reg ALU op instr
    assign forward_rs1_mem = mem_wen && (ex_rs1 == mem_rd);
    assign forward_rs2_mem = mem_wen && (ex_rs2 == mem_rd);

    // MEM->EX forwarding (old mem in WB): used only when EX/MEM has no match.
    assign forward_rs1_wb = wb_wen && (ex_rs1 == wb_rd);
    assign forward_rs2_wb = wb_wen && (ex_rs2 == wb_rd);

    // Choose the newest available operand value
    // (hazard detection should make it so newest always works).
    assign rs1_out =
        forward_rs1_mem ? mem_forward_value :  //      try: EX->EX
        forward_rs1_wb  ? wb_forward_value :   // fallback: Mem->EX
                          ex_rs1data;          //      N/A: use existing value
    assign rs2_out =
        forward_rs2_mem ? mem_forward_value :
        forward_rs2_wb  ? wb_forward_value :
                          ex_rs2data;
endmodule

`default_nettype wire
