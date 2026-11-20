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
    localparam O = 4;            // 4 bit offset => 16 byte cache line
    localparam S = 5;            // 5 bit set index => 32 sets
    // ** and / are course-rules-banned (real hardware power/divide
    // operators synthesize poorly); O and S are fixed per the note above,
    // so these are equivalent shift-based constant expressions, not a
    // behavior change.
    localparam DEPTH = 1 << S;   // 32 sets
    localparam W = 2;            // 2 way set associative, NMRU
    localparam T = 32 - O - S;   // 23 bit tag
    localparam D = (1 << O) >> 2; // 16 bytes per line / 4 bytes per word = 4 words per line

    // The following memory arrays model the cache structure. As this is
    // an internal implementation detail, you are *free* to modify these
    // arrays as you please.

    // Backing memory, modeled as two separate ways.
    reg [   31:0] datas0 [DEPTH - 1:0][D - 1:0];
    reg [   31:0] datas1 [DEPTH - 1:0][D - 1:0];
    reg [T - 1:0] tags0  [DEPTH - 1:0];
    reg [T - 1:0] tags1  [DEPTH - 1:0];
    reg [1:0] valid [DEPTH - 1:0];
    reg       lru   [DEPTH - 1:0];

    // check there's a request
    wire request = i_req_ren || i_req_wen;

    // tag, set, word breakdown:
    // TTT..(23)..TTTTSSSSSWW__
    wire [S-1:0] set_num;
    wire [T-1:0] tag_num;
    wire [O-3:0] wrd_num;
    assign wrd_num = i_req_addr[O-1:2];
    assign set_num = i_req_addr[O+S-1:O];
    assign tag_num = i_req_addr[31:O+S];

    // valid and tags match => Hit.
    wire hit_0, hit_1, miss;
    wire [31:0] cached_word;
    assign hit_0 = valid[set_num][0] && (tags0[set_num] == tag_num);
    assign hit_1 = valid[set_num][1] && (tags1[set_num] == tag_num);
    assign miss  = !hit_0 && !hit_1;
    // use of `miss` should prevent eroneous use of this term
    assign cached_word = hit_1 ? datas1[set_num][wrd_num] : datas0[set_num][wrd_num];

    // read/write manipulation mask 
    // for read:  (1 = take from cache,   0 = leave blank)
    // for write: (1 = take from request, 0 = take from cache)
    wire [31:0] byte_mask = {
        {8{i_req_mask[3]}}, {8{i_req_mask[2]}}, {8{i_req_mask[1]}}, {8{i_req_mask[0]}}
    };
    
    // FSM shenanigans since fetching cache line can't be done in one swoop
    // At it's core cache semantics consist of 3 primary steps:
    // 1) check whether hit/miss (and which way) combinationally
    // 2) if miss, fetch the cache line from memory, and track what was the allocated cache line 
    //    (WA behavior, same in both R/W cases)
    // 3) take either hit line, or the line that was populated after a miss, and then:
    //    a) if read:  return the requested mem (masked word)
    //    b) if write: write the masked word to the cache and memory (write-through)
    localparam IDLE = 2'd0, MEM_FETCH = 2'd1, STORE = 2'd2;
    reg [1:0] state;
    wire [O-3:0] n_word_index; 
    wire n_word_valid, m_fetch_done; 
    wire [31:0] mem_fetch_addr;
    reg mem_fetch_way, pending_write;

    // more combinationally definable values 
    wire store_request = state == STORE || (state == IDLE && i_req_wen && !miss);
    wire victim = !valid[set_num][0] ? 1'b0 : // choose invalid if available
                  !valid[set_num][1] ? 1'b1 : // "                         "
                  lru[set_num];               // kick out LRU if both valid
    assign o_res_rdata = cached_word & byte_mask; // mask out the bytes that aren't requested

    // module to help w/ multi-step memory read for cache line fetch
    // do memory fetch if it's a miss and there's a request (and we're currently idle (not sure if this needed))
    wire mem_fetch_start = state == IDLE && request && miss;
    cache_line_reader reader (
        .i_clk(i_clk),                  // std boilerplate
        .i_rst(i_rst),
        .i_start(mem_fetch_start),    
        .i_line_addr(i_req_addr[31:4]), // 16-byte granular addr 
        .i_mem_ready(i_mem_ready),      // pass-thru mem interace (boilerplate)
        .i_mem_valid(i_mem_valid),
        .o_mem_ren(o_mem_ren),
        .o_mem_addr(mem_fetch_addr),
        .o_word_index(n_word_index),    // mem-cache interface: (word index) (which to read from mem / write to cache)
        .o_word_valid(n_word_valid),    //                      (word valid)
        .o_done(m_fetch_done)           //                      (done reading 4 words)
    );
    
    assign o_mem_addr = (state == MEM_FETCH) ? mem_fetch_addr : i_req_addr;
    // store if it's a store request and the memory's ready; only replace part that's masked for on store
    assign o_mem_wen = !i_rst && store_request && i_mem_ready;
    assign o_mem_wdata = (cached_word & ~byte_mask) | (i_req_wdata & byte_mask);
    // busy if cache miss or store w/ mem not yet ready
    assign o_busy = !i_rst && (state != IDLE || (request && miss) || (i_req_wen && !i_mem_ready));

    integer reset_set;
    always @(posedge i_clk) begin
        if (i_rst) begin
            state <= IDLE;
            // invalidate and reset LRU
            for (reset_set = 0; reset_set < DEPTH; reset_set = reset_set + 1) begin
                valid[reset_set] <= 2'b00;
                lru[reset_set]   <= 1'b0;
            end
        end else begin
            case (state)
                // if miss: start fetch and move to MEM_FETCH state
                // otherwise (hit): reset LRU and move to STORE state if write (WT)
                IDLE: begin 
                    if (mem_fetch_start) begin 
                        mem_fetch_way <= victim;
                        valid[set_num][victim] <= 1'b0;
                        pending_write <= i_req_wen;
                        state <= MEM_FETCH;
                    end else if (request) begin
                        lru[set_num] <= !hit_1;
                        if (i_req_wen && !i_mem_ready)
                            state <= STORE;
                    end
                end
                // fetch cache line (logic module handle this, n_word_index tells where to write)
                // once done (signaled by m_fetch_done), update line metadata and move to proper state 
                // based on whether input was W (STORE) or R (IDLE)
                MEM_FETCH: if (n_word_valid) begin
                    if (mem_fetch_way)
                        datas1[set_num][n_word_index] <= i_mem_rdata;
                    else
                        datas0[set_num][n_word_index] <= i_mem_rdata;

                    if (m_fetch_done) begin
                        if (mem_fetch_way)
                            tags1[set_num] <= tag_num;
                        else
                            tags0[set_num] <= tag_num;
                        valid[set_num][mem_fetch_way] <= 1'b1;
                        lru[set_num] <= !mem_fetch_way;
                        state <= pending_write ? STORE : IDLE;
                    end
                end
                // write to cache and memory (write-through): once done; move to IDLE state.
                STORE: if (i_mem_ready)
                    state <= IDLE;
            endcase
            // write to correct way at correct word
            if (o_mem_wen) begin
                if (hit_1)
                    datas1[set_num][wrd_num] <= o_mem_wdata;
                else
                    datas0[set_num][wrd_num] <= o_mem_wdata;
            end
        end
    end
endmodule

`default_nettype wire
