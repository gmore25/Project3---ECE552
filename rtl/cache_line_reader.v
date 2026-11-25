`default_nettype none

module cache_line_reader (
    input  wire        i_clk,
    input  wire        i_rst,
    input  wire        i_start,
    // must be stable until o_done for consistent behavior.
    input  wire [31:4] i_line_addr,
    input  wire        i_mem_ready,
    input  wire        i_mem_valid,
    output wire        o_mem_ren,
    output wire [31:0] o_mem_addr,
    output reg  [1:0]  o_word_index,
    output wire        o_word_valid,
    output wire        o_done
);
    // internal state machine for memory reading:
    // does 4 word read and sends high output on o_done when finished
    localparam IDLE = 2'd0, ISSUE = 2'd1, WAIT_DATA = 2'd2;
    reg [1:0] state;

    assign o_mem_addr = {i_line_addr, o_word_index, 2'b00};
    assign o_mem_ren = !i_rst && state == ISSUE && i_mem_ready;
    assign o_word_valid = !i_rst && state == WAIT_DATA && i_mem_valid;
    assign o_done = o_word_valid && o_word_index == 2'd3;

    always @(posedge i_clk) begin
        if (i_rst) begin
            state <= IDLE;
            o_word_index <= 0;
        end else begin
            case (state)
                // process request to read a line
                IDLE: if (i_start) begin 
                    o_word_index <= 0;
                    state <= ISSUE;
                end
                // wait for mem to be free
                ISSUE: if (i_mem_ready)
                    state <= WAIT_DATA;
                // read and increment index until all 4 words are read
                WAIT_DATA: if (i_mem_valid) begin 
                    if (o_done)
                        state <= IDLE;
                    else begin
                        o_word_index <= o_word_index + 1'b1;
                        state <= ISSUE;
                    end
                end
            endcase
        end
    end
endmodule

`default_nettype wire
