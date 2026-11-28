`default_nettype none

module cache (
    // Global clock.
    input  wire        i_clk,
    // Synchronous active-high reset.
    input  wire        i_rst,
    // External memory interface. See hart interface for details. This
    // interface is nearly identical to the phase 5 memory interface, with the
    // exception that the byte mask (`o_mem_mask`) has been removed. This is
    // no longer needed as the cache will only access the memory at word
    // granularity, and implement masking internally.
    input  wire        i_mem_ready,
    output wire [31:0] o_mem_addr,
    output wire        o_mem_ren,
    output wire        o_mem_wen,
    output wire [31:0] o_mem_wdata,
    input  wire [31:0] i_mem_rdata,
    input  wire        i_mem_valid,
    // Interface to CPU hart. This is nearly identical to the phase 5 hart memory
    // interface, but includes a stall signal (`o_busy`), and the input/output
    // polarities are swapped for obvious reasons.
    //
    // The CPU should use this as a stall signal for both instruction fetch
    // (IF) and memory (MEM) stages, from the instruction or data cache
    // respectively. If a memory request is made (`i_req_ren` for instruction
    // cache, or either `i_req_ren` or `i_req_wen` for data cache), this
    // should be asserted *combinationally* if the request results in a cache
    // miss.
    //
    // In case of a cache miss, the CPU must stall the respective pipeline
    // stage and deassert ren/wen on subsequent cycles, until the cache
    // deasserts `o_busy` to indicate it has serviced the cache miss. However,
    // the CPU must keep the other request lines constant. For example, the
    // CPU should not change the request address while stalling.
    output wire        o_busy,
    // 32-bit read/write address to access from the cache. This should be
    // 32-bit aligned (i.e. the two LSBs should be zero). See `i_req_mask` for
    // how to perform half-word and byte accesses to unaligned addresses.
    input  wire [31:0] i_req_addr,
    // When asserted, the cache should perform a read at the aligned address
    // specified by `i_req_addr` and return the 32-bit word at that address,
    // either immediately (i.e. combinationally) on a cache hit, or
    // synchronously on a cache miss. It is illegal to assert this and
    // `i_dmem_wen` on the same cycle.
    input  wire        i_req_ren,
    // When asserted, the cache should perform a write at the aligned address
    // specified by `i_req_addr` with the 32-bit word provided in
    // `o_req_wdata` (specified by the mask). This is necessarily synchronous,
    // but may either happen on the next clock edge (on a cache hit) or after
    // multiple cycles of latency (cache miss). As the cache is write-through
    // and write-allocate, writes must be applied to both the cache and
    // underlying memory.
    // It is illegal to assert this and `i_dmem_ren` on the same cycle.
    input  wire        i_req_wen,
    // The memory interface expects word (32 bit) aligned addresses. However,
    // the processor supports byte and half-word loads and stores at unaligned and
    // 16-bit aligned addresses, respectively. To support this, the access
    // mask specifies which bytes within the 32-bit word are actually read
    // from or written to memory.
    input  wire [ 3:0] i_req_mask,
    // The 32-bit word to write to memory, if the request is a write
    // (i_req_wen is asserted). Only the bytes corresponding to set bits in
    // the mask should be written into the cache (and to backing memory).
    input  wire [31:0] i_req_wdata,
    // THe 32-bit data word read from memory on a read request.
    output wire [31:0] o_res_rdata
);
    // These parameters are equivalent to those provided in the project
    // 6 specification. Feel free to use them, but hardcoding these numbers
    // rather than using the localparams is also permitted, as long as the
    // same values are used (and consistent with the project specification).
    //
    // 32 sets * 2 ways per set * 16 bytes per way = 1K cache
    // ** and / are course-rules-banned; use shift-based constant expressions.
    localparam O = 4;             // 4 bit offset => 16 byte cache line
    localparam S = 5;             // 5 bit set index => 32 sets
    localparam DEPTH = 1 << S;    // 32 sets
    localparam W = 2;             // 2 way set associative, NMRU
    localparam T = 32 - O - S;    // 23 bit tag
    localparam D = (1 << O) >> 2; // 4 words per line
    localparam IDLE=3'd0, REFILL_REQ=3'd1, REFILL_WAIT=3'd2,
               WRITE_UPDATE=3'd3, STORE_REQ=3'd4, COMPLETE=3'd5;
    reg [2:0] state;
    // The following memory arrays model the cache structure. As this is
    // an internal implementation detail, you are *free* to modify these
    // arrays as you please.
    // Backing memory, modeled as two separate ways.
    reg [31:0] datas0 [DEPTH-1:0][D-1:0];
    reg [31:0] datas1 [DEPTH-1:0][D-1:0];
    reg [T-1:0] tags0 [DEPTH-1:0];
    reg [T-1:0] tags1 [DEPTH-1:0];
    reg [1:0] valid [DEPTH-1:0];
    reg lru [DEPTH-1:0]; // stores the least-recently-used way

    // check there's a request
    // tag, set, word breakdown:
    // TTT..(23)..TTTTSSSSSWW__
    wire [S-1:0] req_set = i_req_addr[O+S-1:O];
    wire [T-1:0] req_tag = i_req_addr[31:O+S];
    wire [1:0] req_word = i_req_addr[3:2];
    // valid and tags match => Hit.
    wire hit0 = valid[req_set][0] && tags0[req_set] == req_tag;
    wire hit1 = valid[req_set][1] && tags1[req_set] == req_tag;
    wire hit = hit0 || hit1;
    wire request = i_req_ren || i_req_wen;
    // choose invalid if available; otherwise kick out NMRU way
    wire victim = !valid[req_set][0] ? 1'b0 :
                  !valid[req_set][1] ? 1'b1 : lru[req_set];
    wire [31:0] hit_word = hit1 ? datas1[req_set][req_word] : datas0[req_set][req_word];
    // read/write manipulation mask
    // for read:  (1 = take from cache,   0 = leave blank)
    // for write: (1 = take from request, 0 = take from cache)
    wire [31:0] req_mask32 = {{8{i_req_mask[3]}}, {8{i_req_mask[2]}},
                              {8{i_req_mask[1]}}, {8{i_req_mask[0]}}};

    // FSM shenanigans since fetching cache line can't be done in one swoop
    // At its core cache semantics consist of 3 primary steps:
    // 1) check whether hit/miss (and which way) combinationally
    // 2) if miss, fetch the cache line from memory, and track what was
    //    the allocated cache line (WA behavior, same in both R/W cases)
    // 3) take either hit line, or the line that was populated after a miss:
    //    a) if read: return the requested mem (masked word)
    //    b) if write: write the masked word to cache and memory (write-through)
    // Save request info so it stays stable while the CPU stalls.
    reg [31:0] saved_addr, saved_wdata;
    reg [3:0] saved_mask;
    reg saved_way, saved_write;
    reg [1:0] refill_word;
    reg [31:0] store_word;
    wire [S-1:0] saved_set = saved_addr[O+S-1:O];
    wire [T-1:0] saved_tag = saved_addr[31:O+S];
    wire [1:0] saved_word = saved_addr[3:2];
    wire [31:0] saved_mask32 = {{8{saved_mask[3]}}, {8{saved_mask[2]}},
                                {8{saved_mask[1]}}, {8{saved_mask[0]}}};
    wire [31:0] selected_word = saved_way ? datas1[saved_set][saved_word] :
                                            datas0[saved_set][saved_word];
    wire [31:0] merged_word = (selected_word & ~saved_mask32) |
                               (saved_wdata & saved_mask32);
    wire [31:0] hit_merged_word = (hit_word & ~req_mask32) |
                                   (i_req_wdata & req_mask32);

    // On a read hit the response is combinational. During/after a miss,
    // the CPU holds the address and mask stable until o_busy falls.
    assign o_res_rdata = hit_word & req_mask32;
    assign o_busy = !i_rst && ((state == IDLE) ?
                    (request && (!hit || i_req_wen)) : (state != COMPLETE));

    // Memory commands are held asserted until the ready handshake.
    assign o_mem_ren = !i_rst && (state == REFILL_REQ);
    assign o_mem_wen = !i_rst && (state == STORE_REQ);
    assign o_mem_addr = (state == REFILL_REQ || state == REFILL_WAIT) ?
                        {saved_addr[31:4], refill_word, 2'b00} : saved_addr;
    assign o_mem_wdata = store_word;

    integer k;
    always @(posedge i_clk) begin
        if (i_rst) begin
            state <= IDLE;
            saved_addr <= 32'b0;
            saved_wdata <= 32'b0;
            saved_mask <= 4'b0;
            saved_way <= 1'b0;
            saved_write <= 1'b0;
            refill_word <= 2'b0;
            store_word <= 32'b0;
            for (k=0; k<DEPTH; k=k+1) begin
                valid[k] <= 2'b00;
                lru[k] <= 1'b0;
            end
        end else begin
            case (state)
                // if miss: start fetch and move to REFILL_REQ state
                // otherwise (hit): update NMRU and write through if store
                IDLE: begin
                    if (request) begin
                        if (hit) begin
                            lru[req_set] <= hit0 ? 1'b1 : 1'b0;
                            if (i_req_wen) begin
                                saved_addr <= i_req_addr;
                                saved_wdata <= i_req_wdata;
                                saved_mask <= i_req_mask;
                                saved_way <= hit1;
                                saved_write <= 1'b1;
                                store_word <= hit_merged_word;
                                if (hit1)
                                    datas1[req_set][req_word] <= hit_merged_word;
                                else
                                    datas0[req_set][req_word] <= hit_merged_word;
                                state <= STORE_REQ;
                            end
                        end else begin
                            saved_addr <= i_req_addr;
                            saved_wdata <= i_req_wdata;
                            saved_mask <= i_req_mask;
                            saved_write <= i_req_wen;
                            saved_way <= victim;
                            refill_word <= 2'b00;
                            valid[req_set][victim] <= 1'b0;
                            state <= REFILL_REQ;
                        end
                    end
                end
                // Request one word of the missing cache line.
                // Wait for memory to accept the read request.
                REFILL_REQ: if (i_mem_ready) state <= REFILL_WAIT;
                // Fetch cache line word by word; store each received word.
                // Once done, update line metadata and choose read/write path.
                REFILL_WAIT: if (i_mem_valid) begin
                    if (saved_way)
                        datas1[saved_set][refill_word] <= i_mem_rdata;
                    else
                        datas0[saved_set][refill_word] <= i_mem_rdata;
                    if (refill_word == 2'd3) begin
                        if (saved_way) tags1[saved_set] <= saved_tag;
                        else tags0[saved_set] <= saved_tag;
                        valid[saved_set][saved_way] <= 1'b1;
                        lru[saved_set] <= !saved_way;
                        state <= saved_write ? WRITE_UPDATE : COMPLETE;
                    end else begin
                        refill_word <= refill_word + 2'd1;
                        state <= REFILL_REQ;
                    end
                end
                // write to correct way at correct word, merging byte mask
                WRITE_UPDATE: begin
                    store_word <= merged_word;
                    if (saved_way)
                        datas1[saved_set][saved_word] <= merged_word;
                    else
                        datas0[saved_set][saved_word] <= merged_word;
                    state <= STORE_REQ;
                end
                // write to cache and memory (write-through): once accepted,
                // move to COMPLETE state.
                STORE_REQ: if (i_mem_ready) state <= COMPLETE;
                COMPLETE: state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end
endmodule
`default_nettype wire
