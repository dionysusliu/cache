`include "cache_def.svh"
`include "sys_defs.svh"

// WRITE-BACK policy for this design
// for write-back cache, only eviction will issue write operation!!!
// only READ operation will be marked as is_req

// cannot make sure there are no duplicate entry in MSHR, therefore we need to keep the cache miss request and compare to the freed MSHR entry

// non-blocking:
// think of write-through: if cache hit, need to make sure memory is written until moving to the next request

// we don't consider MSHR full for now as well make sure the number of MSHR is enough

// For victim cache's LRU: when a new CL is allocated, assign its LRU with '1 and decrement all other CL's LRU

// For flushing: first, flush MSHR, then flush main cache, finally flush victim cache
module dcache(
    input clock,
    input reset,
    
    output stall_out, // when stall is high, pipeline should be stalled

    // from and to pipeline
    input  DCACHE_REQUEST  dcache_request,
    output DCACHE_RESPONSE dcache_response, // !!!@@@ no longer register

    // From memory
    input [3:0]  Dmem2proc_response, // Should be zero unless there is a response
    input [63:0] Dmem2proc_data,    // size of a cache block in bit
    input [3:0]  Dmem2proc_tag,

    // To memory
    output logic [1:0]  proc2Dmem_command,
    output logic [`XLEN-1:0] proc2Dmem_addr,
    output logic [63:0] proc2Dmem_data,

    // when program terminates
    input logic done,
    output logic flush_finished

    `ifdef DEBUG,
        // registers
        output CACHE_LINE [`N_CL-1 : 0] dbg_main_cache_lines,
        output VICTIM_CACHE_LINE [`N_VC_CL-1 : 0] dbg_victim_cache_lines,
        output logic [$clog2(`N_VC_CL) : 0] dbg_n_vc_avail,
        output MSHR_ENTRY [`N_MSHR-1 : 0] dbg_mshr_table,
        output logic [$clog2(`N_MSHR) : 0] dbg_n_mshr_avail,
        output DC_STATE_T dbg_state,
        output DCACHE_REQUEST  dbg_dcache_request_on_wait,
        output logic [$clog2(`N_MSHR):0] dbg_n_mshr_entry_freed_cnt,
        output logic [$clog2(`N_MSHR):0] dbg_n_mshr_entry_occupied_cnt,
        // registers peripherals
        output CACHE_LINE [`N_CL-1 : 0] dbg_next_main_cache_lines,
        output VICTIM_CACHE_LINE [`N_VC_CL-1 : 0] dbg_next_victim_cache_lines,
        output logic [$clog2(`N_VC_CL) : 0] dbg_next_n_vc_avail,
        output MSHR_ENTRY [`N_MSHR-1 : 0] dbg_next_mshr_table,
        output logic [$clog2(`N_MSHR) : 0] dbg_next_n_mshr_avail,
        output DC_STATE_T dbg_next_state,
        output DCACHE_REQUEST  dbg_next_dcache_request_on_wait,
        // combinationals
        output logic dbg_cache_hit,
        output logic dbg_main_cache_hit,
        output logic [`N_IDX_BITS:0] dbg_main_cache_hit_index,
        output logic dbg_vc_hit,
        output logic [$clog2(`N_VC_CL) : 0] dbg_vc_hit_index,
        output logic dbg_mshr_hit,
        output logic dbg_mshr_real_hit,
        output logic [$clog2(`N_MSHR): 0]  dbg_mshr_hit_index,
        output logic dbg_request_finished,
        // commuication wires
        output MSHR_ENTRY dbg_mshr2dcache_packet,  // when a memory response comes in, erase matched MSHR entry and transfer that cache line to main cache/victim cache
        output VICTIM_CACHE_LINE dbg_vic_cache_line_evicted,  // must be from victim cache to MSHR
        output CACHE_LINE dbg_main_cache_line_evicted, // from main cache to victim cache
        output MEM_ADDR_T dbg_main_cache_line_evicted_addr, // address of CL evicted from main cache
        output CACHE_LINE dbg_main_cache_line_upon_hit, // cache line hit at main cache
        output VICTIM_CACHE_LINE dbg_vic_cache_line_upon_hit, //cache line hit at victim cache
        // main cache related
        output logic [$clog2(`N_CL):0] dbg_cache_line_index_for_new_data,
        output logic dbg_need_to_evict,
        output logic dbg_mshr2dcache_packet_USED,
        output logic dbg_loaded_CL_same_addr_as_evicted_CL,
        output logic [$clog2(`N_CL):0] dbg_cache_line_index_for_MSHR_real_hit,
        output logic dbg_need_to_evict_MSHR_real_hit,
        output DBG_MAIN_CACHE_STATE_T dbg_main_cache_response_case,
        // victim cache related
        output logic dbg_vc_need_evict,
        output VICTIM_CACHE_LINE dbg_vc_CL_evicted,
        output logic [$clog2(`N_VC_CL) : 0] dbg_vc_CL_evicted_index,
        output logic [$clog2(`N_VC_CL) : 0] dbg_vc_free_index,
        output logic [$clog2(`N_VC_CL) : 0] dbg_current_smallest_index,
        output logic [$clog2(`N_VC_CL) : 0] dbg_current_smallest_lru,
        output logic [$clog2(`N_VC_CL) : 0] dbg_index_selector,
        // dcache response related
        // MSHR related
        output PREFETCH_ADDR_T [`N_PF:0] dbg_addrs2mshr,
        output MEM_ADDR_T dbg_base_addr,
        output logic [`N_PF:0] [$clog2(`N_MSHR):0]   dbg_free_mshr_entry_idx,
        output logic [`N_MSHR:0] [`N_PF:0] dbg_idx_wires,
        output logic [$clog2(`N_MSHR):0] dbg_mshr_index_to_issue,
        output logic [$clog2(`N_MSHR):0] dbg_mshr_index_to_issue_hi_priority,
        output logic [$clog2(`N_MSHR):0] dbg_mshr_index_to_issue_mid_priority,
        output logic [$clog2(`N_MSHR):0] dbg_mshr_index_to_issue_low_priority,
        output logic dbg_high_priority_exist,
        output logic dbg_mid_priority_exist,
        output logic dbg_low_priority_exist,
        output logic dbg_issue2mem,
        output logic dbg_can_allocate_new_mshr_entry,
        output MSHR_ENTRY [`N_MSHR - 1 : 0] dbg_tmp_next_1_mshr_table,
        output MSHR_ENTRY [`N_MSHR - 1 : 0] dbg_tmp_next_2_mshr_table,
        output MSHR_ENTRY [`N_MSHR - 1 : 0] dbg_tmp_next_3_mshr_table,
        output logic [`N_MSHR:0] [$clog2(`N_MSHR):0]  dbg_n_mshr_avail_wires


    `endif
);

/*** Registers ***/
CACHE_LINE [`N_CL-1 : 0] main_cache_lines;
VICTIM_CACHE_LINE [`N_VC_CL-1 : 0] victim_cache_lines;
logic [$clog2(`N_VC_CL) : 0] n_vc_avail;
MSHR_ENTRY [`N_MSHR-1 : 0] mshr_table;
logic [$clog2(`N_MSHR) : 0] n_mshr_avail;
DC_STATE_T state; // for dcache
DCACHE_REQUEST  dcache_request_on_wait;

/*** Registers peripherals ***/
// DCACHE_RESPONSE next_dcache_response;
CACHE_LINE [`N_CL-1 : 0] next_main_cache_lines;
VICTIM_CACHE_LINE [`N_VC_CL-1 : 0] next_victim_cache_lines;
logic [$clog2(`N_VC_CL) : 0] next_n_vc_avail;
MSHR_ENTRY [`N_MSHR-1 : 0] next_mshr_table;
logic [$clog2(`N_MSHR) : 0] next_n_mshr_avail;
DC_STATE_T next_state;
DCACHE_REQUEST  next_dcache_request_on_wait;



/*** Combinationals ***/
logic cache_hit; // general meaning of cache hit
logic main_cache_hit; // main cache hit 
logic [`N_IDX_BITS:0] main_cache_hit_index;
logic vc_hit; // victim cache hit
logic [$clog2(`N_VC_CL) : 0] vc_hit_index; 
logic mshr_hit;  // mutual exclusive against mshr_real_hit
logic mshr_real_hit; // 1. memory response coming up from this cycle and match with current request 2. MSHR Reg is dirty CL that is requested by read/write
logic [$clog2(`N_MSHR): 0]  mshr_hit_index;  
logic request_finished; // request from pipeline is finished on this cycle

// flush control signals
logic mshr_flush_finished;
logic main_cache_flush_finished;
logic vic_cache_flush_finished;

// communication wires
MSHR_ENTRY mshr2dcache_packet;  // when a memory response comes in, erase matched MSHR entry and transfer that cache line to main cache/victim cache
VICTIM_CACHE_LINE vic_cache_line_evicted;  // must be from victim cache to MSHR
CACHE_LINE main_cache_line_evicted; // from main cache to victim cache
MEM_ADDR_T main_cache_line_evicted_addr; // address of CL evicted from main cache
CACHE_LINE main_cache_line_upon_hit; // cache line hit at main cache
VICTIM_CACHE_LINE vic_cache_line_upon_hit; //cache line hit at victim cache


logic [`XLEN - 1 : `N_IDX_BITS + `DC_BO] dcache_req_CL_tag; // cache line tag of dcache request (supposedly)

/*** when pipeline should stall ***/
assign stall_out = ~(state == READY);

/*** cache hit ***/
assign cache_hit = (main_cache_hit | vc_hit | mshr_real_hit) & (state == READY);

/*** determine internal state ***/
always_comb begin : manage_cache_internal_state
    case(state)
        READY: begin
            if (done) begin
                next_state = FLUSH;
            end else if(~dcache_request.valid | (dcache_request.valid & cache_hit) ) begin
                next_state = READY;
            end else if (n_mshr_avail < `N_PF + 1) begin
                next_state = WAIT_MSHR;
            end else begin
                next_state = WAIT;
            end
        end
        WAIT_MSHR: begin
            if (n_mshr_avail >= `N_PF+1) begin
                next_state = WAIT;
            end else begin
                next_state = WAIT_MSHR;
            end
        end
        WAIT: begin
            if (request_finished) begin
                next_state = READY;
            end else begin
                next_state = WAIT;
            end
        end
    endcase
end
`ifdef DEBUG
always_comb begin
    $display("/****** next_state TIME: %0d ******/", $time);
    case(next_state)
        READY: $display("next_state: READY");
        WAIT: $display("next_state: WAIT");
        WAIT_MSHR: $display("next_state: WAIT_MSHR");
        FLUSH: $display("next_state: FLUSH");
    endcase

end
`endif

/*** modify request_finished & next_dcache_request_on_wait  ***/
// for write-miss, the request finished when the CL needed to be written is brought to cache since it's WRITE-BACK
always_comb begin : process_cache_miss_request
    request_finished = '0;
    next_dcache_request_on_wait = dcache_request_on_wait;
    if ((state == READY) & ~cache_hit & dcache_request.valid) next_dcache_request_on_wait = dcache_request;
    if ((state == WAIT) & (mshr2dcache_packet.mem_op == MEM_READ) & (mshr2dcache_packet.cache_line_addr[`XLEN-1:`DC_BO] == dcache_request_on_wait.addr[`XLEN-1:`DC_BO]) ) begin
        request_finished = '1;
        next_dcache_request_on_wait = '0;
    end
end


/*** manage main cache ***/

/** for memory response from MSHR, determine the cache line to go to in main cache **/
logic [$clog2(`N_CL):0] cache_line_index_for_new_data; // can be missed request or PREFETCH!!!
logic need_to_evict; // can the newly loaded cache line be accommodate to main cache without eviction?
logic mshr2dcache_packet_USED;
logic loaded_CL_same_addr_as_evicted_CL;
`ifdef DIRECT_MAPPED
    assign cache_line_index_for_new_data = mshr2dcache_packet.cache_line_addr[`N_IDX_BITS + `DC_BO - 1:`DC_BO];
    assign need_to_evict = main_cache_lines[cache_line_index_for_new_data].valid;
    assign loaded_CL_same_addr_as_evicted_CL = need_to_evict & (main_cache_lines[cache_line_index_for_new_data].tag == mshr2dcache_packet.cache_line_addr[`XLEN-1:`XLEN-`DC_TAG_LEN]);
`elsif TWO_WAY_SET_ASSOCIATIVE
    assign cache_line_index_for_new_data = // TBD
    assign need_to_evict = // TBD (need to consider if a set already contain that cache line)
`endif 

/** for MSHR real hit: 1. current memory response match with current request 2. current request(read/write) match with MSHR entry with MEM_WRITE **/
logic [$clog2(`N_CL):0] cache_line_index_for_MSHR_real_hit;
logic need_to_evict_MSHR_real_hit; 
`ifdef DIRECT_MAPPED
    assign cache_line_index_for_MSHR_real_hit = mshr_table[mshr_hit_index].cache_line_addr[`N_IDX_BITS + `DC_BO - 1:`DC_BO];
    assign need_to_evict_MSHR_real_hit = main_cache_lines[cache_line_index_for_MSHR_real_hit].valid;
`elsif TWO_WAY_SET_ASSOCIATIVE
    assign cache_line_index_for_MSHR_real_hit = // TBD
    assign need_to_evict_MSHR_real_hit = // TBD (need to consider if a set already contain that cache line)
`endif 

`ifdef DIRECT_MAPPED


DBG_MAIN_CACHE_STATE_T main_cache_response_case;

always_comb begin : manage_main_cache
    next_main_cache_lines = main_cache_lines;
    mshr2dcache_packet_USED = '0;
    main_cache_response_case = NONE;
    main_cache_line_evicted = '0;
    // cache hit (NO NEED TO ALLOCATE NEW CACHE LINE!) (mshr real hit dealt in another case)
    if (  (main_cache_hit==1'b1) && (state == READY) ) begin
        main_cache_response_case = HIT;
        if (dcache_request.mem_op == MEM_READ) begin // FOR LOAD
            `ifdef TWO_WAY_SET_ASSOCIATIVE
                // update lru
            `endif
            // for direct mapped, do nothing
        end else begin // FOR STORE
            `ifdef TWO_WAY_SET_ASSOCIATIVE
            // update lru
            `endif
            // write cache line and mark dirty bit
            next_main_cache_lines[main_cache_hit_index].dirty = '1;
            case (dcache_request.size)
                BYTE: next_main_cache_lines[main_cache_hit_index].block.byte_level[dcache_request.addr[2:0]] = dcache_request.write_content[7:0];
                HALF: next_main_cache_lines[main_cache_hit_index].block.half_level[dcache_request.addr[2:1]] = dcache_request.write_content[15:0];
                WORD: next_main_cache_lines[main_cache_hit_index].block.word_level[dcache_request.addr[2:2]] = dcache_request.write_content[31:0];
            endcase
        end
    end else if ( (state == READY) & mshr_real_hit & ~main_cache_hit & ~vc_hit & mshr_table[mshr_hit_index].mem_op == MEM_WRITE) begin /** Data forwarded from MSHR table **/
                main_cache_response_case = HIT_ON_MSHR_TABLE;
                // special case: dirty cache line in MSHR is hit by load/store
                next_main_cache_lines[cache_line_index_for_MSHR_real_hit].valid = '1;
                next_main_cache_lines[cache_line_index_for_MSHR_real_hit].block = mshr_table[mshr_hit_index].write_content;
                next_main_cache_lines[cache_line_index_for_MSHR_real_hit].dirty = '0;
                next_main_cache_lines[cache_line_index_for_MSHR_real_hit].tag   = mshr_table[mshr_hit_index].cache_line_addr[`XLEN-1:`XLEN-`DC_TAG_LEN];
                `ifdef DEBUG 
                    next_main_cache_lines[cache_line_index_for_MSHR_real_hit].addr  = mshr_table[mshr_hit_index].cache_line_addr;
                `endif 
                if (need_to_evict_MSHR_real_hit) begin
                    // transmit evicted cache line to victim cache
                    main_cache_line_evicted = main_cache_lines[cache_line_index_for_MSHR_real_hit];
                    main_cache_line_evicted_addr = {main_cache_lines[cache_line_index_for_MSHR_real_hit].tag, cache_line_index_for_MSHR_real_hit, 3'b0};
                end
                if (dcache_request.mem_op == MEM_WRITE) begin
                    next_main_cache_lines[cache_line_index_for_MSHR_real_hit].dirty = '1;
                    case(dcache_request.size)
                        BYTE:  next_main_cache_lines[cache_line_index_for_MSHR_real_hit].block.byte_level[dcache_request.addr[2:0]] = dcache_request.write_content[7:0];
                        HALF:  next_main_cache_lines[cache_line_index_for_MSHR_real_hit].block.half_level[dcache_request.addr[2:1]] = dcache_request.write_content[15:0];
                        WORD:  next_main_cache_lines[cache_line_index_for_MSHR_real_hit].block.word_level[dcache_request.addr[2:2]] = dcache_request.write_content[31:0];
                    endcase
                end
    end else if (state == READY & mshr_real_hit & ~main_cache_hit & ~vc_hit & mshr_table[mshr_hit_index].mem_op == MEM_READ) begin /** Data forwarded from MSHR broadcast packet **/
            main_cache_response_case = HIT_ON_MSHR_PKT;
            mshr2dcache_packet_USED = '1; // !used for simplifying the code
            next_main_cache_lines[cache_line_index_for_new_data].valid = '1;
            next_main_cache_lines[cache_line_index_for_new_data].block = mshr2dcache_packet.Dmem2proc_data;
            next_main_cache_lines[cache_line_index_for_new_data].dirty = '0;
            next_main_cache_lines[cache_line_index_for_new_data].tag   = mshr2dcache_packet.cache_line_addr[`XLEN-1:`XLEN-`DC_TAG_LEN];
            `ifdef DEBUG 
                next_main_cache_lines[cache_line_index_for_MSHR_real_hit].addr  = mshr2dcache_packet.cache_line_addr;
            `endif 
            if (dcache_request.mem_op == MEM_WRITE) begin
                next_main_cache_lines[cache_line_index_for_new_data].dirty = '1;
                case(dcache_request.size)
                    BYTE:  next_main_cache_lines[cache_line_index_for_new_data].block.byte_level[dcache_request.addr[2:0]] = dcache_request.write_content[7:0];
                    HALF:  next_main_cache_lines[cache_line_index_for_new_data].block.half_level[dcache_request.addr[2:1]] = dcache_request.write_content[15:0];
                    WORD:  next_main_cache_lines[cache_line_index_for_new_data].block.word_level[dcache_request.addr[2:2]] = dcache_request.write_content[31:0];
                endcase
            end
            if (need_to_evict & (~loaded_CL_same_addr_as_evicted_CL) ) begin
                // transmit evicted cache line to victim cache
                main_cache_line_evicted = main_cache_lines[cache_line_index_for_new_data];
                main_cache_line_evicted_addr = {main_cache_lines[cache_line_index_for_new_data].tag, cache_line_index_for_new_data, 3'b0};
            end
    end
    
    // cache miss, or response from MSHR
    if ( ~mshr2dcache_packet_USED & mshr2dcache_packet.valid & mshr2dcache_packet.mem_op == MEM_READ) begin /** Date forwarded from MSHR-memory response packet **/
        main_cache_response_case = FWD_FROM_MSHR_PKT;
        if (~need_to_evict | (need_to_evict & mshr2dcache_packet.is_req) ) begin
            next_main_cache_lines[cache_line_index_for_new_data].valid = '1;
            next_main_cache_lines[cache_line_index_for_new_data].block = mshr2dcache_packet.Dmem2proc_data;
            next_main_cache_lines[cache_line_index_for_new_data].dirty = '0;
            next_main_cache_lines[cache_line_index_for_new_data].tag   = mshr2dcache_packet.cache_line_addr[`XLEN-1:`XLEN-`DC_TAG_LEN];
            `ifdef DEBUG 
                next_main_cache_lines[cache_line_index_for_new_data].addr  = mshr2dcache_packet.cache_line_addr;
            `endif
        end
        $display("[INSIDE] need_to_evict & mshr2dcache_packet.is_req: %0d", need_to_evict & mshr2dcache_packet.is_req);
        if ( ( need_to_evict & mshr2dcache_packet.is_req & (~loaded_CL_same_addr_as_evicted_CL) )  ) begin
            // transmit evicted cache line to victim cache
            main_cache_line_evicted = main_cache_lines[cache_line_index_for_new_data];
            main_cache_line_evicted_addr = {main_cache_lines[cache_line_index_for_new_data].tag, cache_line_index_for_new_data, 3'b0};
        end
    end

    
end
`elsif  TWO_WAY_SET_ASSOCIATIVE

`endif 

`ifdef DEBUG_COMBS
always_comb begin
    $display("/*** MAIN CACHE DEBUG | TIME: %0d ***/", $time);
    if (dcache_request.valid) begin
        $write("dcache_request: VALID  ");
        $display("mem_op: %0d  addr: %0b  size: %0d", dcache_request.mem_op, dcache_request.addr, dcache_request.size);
    end else begin
        $display("dcache_request: INVALID");
    end
    case(main_cache_response_case)
        NONE: $display("MAIN_CACHE_STATE: NONE");
        HIT: $display("MAIN_CACHE_STATE: HIT");
        HIT_ON_MSHR_TABLE: $display("MAIN_CACHE_STATE: HIT_ON_MSHR_TABLE");
        HIT_ON_MSHR_PKT: $display("MAIN_CACHE_STATE: HIT_ON_MSHR_PKT");
        FWD_FROM_MSHR_PKT: $display("MAIN_CACHE_STATE: FWD_FROM_MSHR_PKT");
    endcase
    case(state)
        READY: $display("STATE: READY");
        WAIT: $display("STATE: WAIT");
        WAIT_MSHR: $display("STATE: WAIT_MSHR");
        FLUSH: $display("STATE: FLUSH");
    endcase
    $display("!!!@@@@ loaded_CL_same_addr_as_evicted_CL: %0b", loaded_CL_same_addr_as_evicted_CL);
    $display("mshr_real_hit: %0d  mshr_hit_index: %0d", mshr_real_hit, mshr_hit_index);
    $display("cache_hit: %0d  main_cache_hit: %0d  vc_hit: %0d", cache_hit, main_cache_hit, vc_hit);
    $display("needd_to_evict: %0d", need_to_evict);
    $display("cache_line_index_for_new_data: %0d", cache_line_index_for_new_data);
    $display("main_cache_hit: %0d  main_cache_hit_index: %0d", main_cache_hit,main_cache_hit_index);
    $display("mshr2dcache_packet_USED: %0b", mshr2dcache_packet_USED);
    $display("cache_line_index_for_MSHR_real_hit: %0d", cache_line_index_for_MSHR_real_hit);
    $display("need_to_evict_MSHR_real_hit: %0d", need_to_evict_MSHR_real_hit);
    if (main_cache_line_evicted.valid) begin
        $write("main_cache_line_evicted: VALID  ");
        $display(" addr: %0b, tag: %0b, dirty: %0d\n", main_cache_line_evicted.addr, main_cache_line_evicted.tag, main_cache_line_evicted.dirty);
        $display("main_cache_line_evicted_addr: %b", main_cache_line_evicted_addr);
    end


    for (int i=0; i<`N_CL; i++) begin
        $write("next_main_cache_lines[%0d] ", i);
        $display("valid: %0d addr: %0b, tag: %0b, dirty: %0d block: %0d\n", next_main_cache_lines[i].valid, next_main_cache_lines[i].addr, next_main_cache_lines[i].tag, next_main_cache_lines[i].dirty, next_main_cache_lines[i].block);
    end
end
`endif 

/*** manage victim cache ***/
logic vc_need_evict;
VICTIM_CACHE_LINE vc_CL_evicted;
logic [$clog2(`N_VC_CL) : 0] vc_CL_evicted_index;   // if need to evict, this index contains the cache line to be evicted
logic [$clog2(`N_VC_CL) : 0] vc_free_index;   // if no need to evict, this index means one cache line not in use by VC
// temporary variable signal
logic [$clog2(`N_VC_CL) : 0] current_smallest_index;
logic [$clog2(`N_VC_CL) : 0] current_smallest_lru;
always_comb begin : vc_evict_upon_full_find_avail_index
    vc_need_evict = '0;
    vc_CL_evicted = '0;
    vc_CL_evicted_index = '0;
    // temporary variable
    current_smallest_index = '0;
    current_smallest_lru = '1;
    
    if (n_vc_avail == 0) begin // victim cache full, need to evict
        for (int i=0; i<`N_VC_CL; i++) begin
            assert(victim_cache_lines[i].valid)  else $display("Error: victim cache valid bit");
            if ( victim_cache_lines[i].lru == 0) begin
                current_smallest_index = i;
                break;
            end else if (victim_cache_lines[i].lru < current_smallest_lru) begin
                current_smallest_index = i;
                current_smallest_lru = victim_cache_lines[i].lru;
            end
        end

        vc_need_evict = '1;
        vc_CL_evicted_index = current_smallest_index;
        vc_CL_evicted = victim_cache_lines[current_smallest_index];
    end else begin  // victim cache not full yet, can find at least one available entry
        for (int i=0; i<`N_VC_CL; i++) begin
            if (~victim_cache_lines[i].valid) begin
                vc_free_index = i;
                break;
            end
        end
    end
end

logic [$clog2(`N_VC_CL) : 0] index_selector; // select free_index if not full, select evict_index if full
assign index_selector = (vc_need_evict) ? vc_CL_evicted_index : vc_free_index;

/** add, modify, erase victim cache cache lines **/
always_comb begin : manage_victim_cache
    next_victim_cache_lines = victim_cache_lines;
    vic_cache_line_evicted = '0;
    next_n_vc_avail = n_vc_avail;
    // cache hit
    if (state == READY & vc_hit) begin
        // update lru
        for (int i=0; i<`N_VC_CL; i++) begin
            if (i==vc_hit_index) next_victim_cache_lines[i].lru = '1;
            else if(victim_cache_lines[i].lru > '0) next_victim_cache_lines[i].lru = victim_cache_lines[i].lru - 1;
        end
        // update cache block if it is store
        if (dcache_request.mem_op == MEM_WRITE) begin
            next_victim_cache_lines[vc_hit_index].dirty = '1;
            case(dcache_request.size)
                BYTE: next_victim_cache_lines[vc_hit_index].block.byte_level[dcache_request.addr[2:0]] = dcache_request.write_content[7:0];
                HALF: next_victim_cache_lines[vc_hit_index].block.half_level[dcache_request.addr[2:1]] = dcache_request.write_content[15:0];
                WORD: next_victim_cache_lines[vc_hit_index].block.word_level[dcache_request.addr[2:2]] = dcache_request.write_content[31:0];
            endcase
        end
    end

    /** evicted cache line comes in, add evicted CL from main cache, evict victim cache cachel line if necessary **/
    if (main_cache_line_evicted.valid) begin
        // if victim cache need to evict
        if (vc_need_evict) begin
            vic_cache_line_evicted = vc_CL_evicted;
            vic_cache_line_evicted.valid = vc_CL_evicted.dirty; /** NOTE: if cache line not DIRTY, no need to write back!!! **/
        end else begin
            next_n_vc_avail = n_vc_avail - 1;   // decrease number of VC entry avaible after allocation
        end
        // replace that old cache line with new one
        next_victim_cache_lines[index_selector].valid = '1;
        next_victim_cache_lines[index_selector].block = main_cache_line_evicted.block;
        next_victim_cache_lines[index_selector].dirty = main_cache_line_evicted.dirty;
        next_victim_cache_lines[index_selector].lru   = '0;
        next_victim_cache_lines[index_selector].tag   = main_cache_line_evicted_addr[`XLEN-1:3];
    end
end

/*** manage dcache response ***/
// no need to worry about read/write data response. For write, there is no need for data response, as long as the valid bit is high
EXAMPLE_CACHE_BLOCK data2output;
always_comb begin : output_selector
    // next_dcache_response = '0;
    dcache_response = '0;
    data2output = '0;
    // cache hit
    if ((state==READY) & cache_hit) begin
        // next_dcache_response.valid = '1;
        // next_dcache_response.mem_op = dcache_request.mem_op;
        dcache_response.valid = '1;
        dcache_response.mem_op = dcache_request.mem_op;
        if (main_cache_hit) begin
            data2output = main_cache_line_upon_hit.block;
        end else if (vc_hit) begin
            data2output = vic_cache_line_upon_hit.block;
        end else if (mshr_real_hit) begin
            data2output = (mshr_table[mshr_hit_index].mem_op == MEM_WRITE) ? mshr_table[mshr_hit_index].write_content : mshr2dcache_packet.Dmem2proc_data;
        end else begin
            $display("Error: cache hit condition wrong!");
        end
    end

    // cache miss, but now MSHR response match with waiting request
    if (request_finished) begin
        // next_dcache_response.valid = '1;
        // next_dcache_response.mem_op = dcache_request_on_wait.mem_op;
        dcache_response.valid = '1;
        dcache_response.mem_op = dcache_request_on_wait.mem_op;
        data2output = mshr2dcache_packet.Dmem2proc_data;
    end

    case (dcache_request_on_wait.size) 
        // BYTE: next_dcache_response.reg_data[7:0]  = data2output.byte_level[dcache_request_on_wait.addr[2:0]];
        // HALF: next_dcache_response.reg_data[15:0] = data2output.half_level[dcache_request_on_wait.addr[2:1]];
        // WORD: next_dcache_response.reg_data[31:0] = data2output.word_level[dcache_request_on_wait.addr[2:2]];
        BYTE: dcache_response.reg_data[7:0]  = data2output.byte_level[dcache_request_on_wait.addr[2:0]];
        HALF: dcache_response.reg_data[15:0] = data2output.half_level[dcache_request_on_wait.addr[2:1]];
        WORD: dcache_response.reg_data[31:0] = data2output.word_level[dcache_request_on_wait.addr[2:2]];
    endcase
    
end

/*** manage MSHR table ***/

// flush MSHR table completed
always_comb begin
    mshr_flush_finished = '1;
    if ( state == FLUSH ) begin
        for (int i=0; i<`N_MSHR; i++) begin
            if (mshr_table[i].valid) begin
                mshr_flush_finished = '0;
                break;
            end
        end
    end
end

// new MSHR entry for request and prefetch cache line
// NOTE: prefetch for both LOAD and STORE !!!
// PREVENT CACHE LINE WAITING TO BE WRITTEN BACK BE LOADED FROM MEMORY AGAIN, which will not be the most updated version of that CL
function addr_not_in_main_cache(MEM_ADDR_T addr);
`ifdef DIRECT_MAPPED
    if (main_cache_lines[addr[`N_IDX_BITS + `DC_BO - 1:`DC_BO]].valid & (main_cache_lines[addr[`N_IDX_BITS + `DC_BO - 1:`DC_BO]].tag == addr[`XLEN-1:`XLEN-`DC_TAG_LEN]) ) return 0;
    else return 1;
`elsif macro TWO_WAY_SET_ASSOCIATIVE
    // TBD
`endif 
endfunction

function addr_not_in_victim_cache(MEM_ADDR_T addr);
    for (int i=0; i<`N_VC_CL; i++) begin
        if (victim_cache_lines[i].valid & (victim_cache_lines[i].tag == addr[`XLEN-1:`DC_BO]) ) return 0;
    end
    return 1;
endfunction

function  addr_not_in_MSHR_packet(MEM_ADDR_T addr);
    if (mshr2dcache_packet.cache_line_addr == addr) return 0;
    else return 1;
endfunction

function addr_not_in_MSHR_table(MEM_ADDR_T addr);
    for (int i=0; i<`N_MSHR; i++) begin
        if (mshr_table[i].valid & mshr_table[i].cache_line_addr == addr) return 0;
    end
    return 1;
endfunction

PREFETCH_ADDR_T [`N_PF:0] addrs2mshr;
MEM_ADDR_T base_addr; // address of the memory request
/** modify addrs2mshr **/
always_comb begin : gen_new_mshr_entry
    addrs2mshr = '0;
    base_addr  = (state == READY) ? dcache_request.addr : dcache_request_on_wait.addr;
    for (int i=0; i<`N_PF+1;i++) begin
        addrs2mshr[i].addr = base_addr + i*8;
        addrs2mshr[i].valid = addr_not_in_main_cache(base_addr + i*8)   &
                              addr_not_in_victim_cache(base_addr + i*8) &
                              addr_not_in_MSHR_packet(base_addr + i*8) &
                              addr_not_in_MSHR_table(base_addr + i*8);
        addrs2mshr[i].addr_not_in_main_cache    = addr_not_in_main_cache(base_addr + i*8);
        addrs2mshr[i].addr_not_in_victim_cache  = addr_not_in_victim_cache(base_addr + i*8);
        addrs2mshr[i].addr_not_in_MSHR_packet   = addr_not_in_MSHR_packet(base_addr + i*8);
        addrs2mshr[i].addr_not_in_MSHR_table    = addr_not_in_MSHR_table(base_addr + i*8);

    end
end

// MSHR entries that are not occupied
logic [`N_PF:0] [$clog2(`N_MSHR):0]   free_mshr_entry_idx ;

/** modify free_mshr_entry_idx **/
logic [`N_MSHR:0] [`N_PF:0] idx_wires;
always_comb begin : free_mshr_entry_index_determination

    free_mshr_entry_idx = '0;
    idx_wires = '0;


    for (int i=0; i<`N_MSHR;i++) begin
        if (~mshr_table[i].valid) begin
            free_mshr_entry_idx[idx_wires[i]] = i;
            idx_wires[i+1] = idx_wires[i] + 1;
            if (idx_wires[i] == `N_PF) break;
        end else if (i>0) idx_wires[i] = idx_wires[i-1];
    end
end


// index of MSHR entry that can be issued to memory
logic [$clog2(`N_MSHR):0] mshr_index_to_issue;
logic [$clog2(`N_MSHR):0] mshr_index_to_issue_hi_priority;
logic [$clog2(`N_MSHR):0] mshr_index_to_issue_mid_priority;
logic [$clog2(`N_MSHR):0] mshr_index_to_issue_low_priority;
logic high_priority_exist;
logic mid_priority_exist;
logic low_priority_exist;
logic issue2mem;
logic can_allocate_new_mshr_entry;
// connecting wires for renaming
MSHR_ENTRY [`N_MSHR - 1 : 0] tmp_next_1_mshr_table;
MSHR_ENTRY [`N_MSHR - 1 : 0] tmp_next_2_mshr_table;
MSHR_ENTRY [`N_MSHR - 1 : 0] tmp_next_3_mshr_table;
// wires for counter
logic [`N_MSHR:0] [$clog2(`N_MSHR):0]  n_mshr_avail_wires;
`ifdef DIRECT_MAPPED
always_comb begin : manage_MSHR
    // int  n_mshr_entry_freed_cnt = 0;
    // int  n_mshr_entry_occupied_cnt = 0;
    // `ifdef DEBUG
    //     dbg_n_mshr_entry_freed_cnt = '0;
    //     dbg_n_mshr_entry_occupied_cnt = '0;
    // `endif

    tmp_next_1_mshr_table   = mshr_table;
    next_n_mshr_avail       = n_mshr_avail;
    n_mshr_avail_wires      = '0;
    mshr2dcache_packet = '0;


    /** flush MSHR when done, invalidate all LOAD operations **/
    if (state == FLUSH) begin
        for (int i=0; i<`N_MSHR; i++) begin
            tmp_next_1_mshr_table[i].valid = (mshr_table[i].mem_op == MEM_WRITE);
        end
    end

    /*** hit on dirty mshr table entry, remove that entry to main cache ***/
    if (main_cache_response_case == HIT_ON_MSHR_TABLE) begin
        tmp_next_1_mshr_table[mshr_hit_index].valid = '0;
    end

    /** deal with memory responses and free MSHR entry when STATE IS NOT FLUSH **/
    if ((Dmem2proc_tag != 0) & (state != FLUSH) ) begin
        for (int i=0; i<`N_MSHR;i++) begin
            if (mshr_table[i].valid & (mshr_table[i].Dmem2proc_tag == Dmem2proc_tag) & mshr_table[i].issued) begin
                assert(mshr_table[i].mem_op == MEM_READ) else $display("MSHR: memory response tag matched with STORE operation!");
                tmp_next_1_mshr_table[i] = '0;    // clear MSHR entry when finished
                mshr2dcache_packet = mshr_table[i];
                mshr2dcache_packet.Dmem2proc_data = Dmem2proc_data;
                break;
                // n_mshr_entry_freed_cnt ++;  // free one entry
            end
        end
    end

    tmp_next_2_mshr_table = tmp_next_1_mshr_table;  // initialize wires
    /** allocate new MSHR entry when cache eviction happens (don't need to worry about state is FLUSH) **/
    if (vic_cache_line_evicted.valid & vic_cache_line_evicted.dirty) begin
        for (int i=0; i<`N_MSHR; i++)begin
            if(~tmp_next_1_mshr_table[i].valid)begin
                tmp_next_2_mshr_table[i].valid = '1;
                tmp_next_2_mshr_table[i].is_req = '1;
                tmp_next_2_mshr_table[i].issued = '0;
                tmp_next_2_mshr_table[i].mem_op = MEM_WRITE;
                tmp_next_2_mshr_table[i].Dmem2proc_tag = '0;
                tmp_next_2_mshr_table[i].Dmem2proc_data = vic_cache_line_evicted.block;
                tmp_next_2_mshr_table[i].cache_line_addr = {vic_cache_line_evicted.tag, 3'b0};    // since it is fully associative cache, no index bits
                tmp_next_2_mshr_table[i].write_content = vic_cache_line_evicted.block;
                // n_mshr_entry_occupied_cnt ++; // occupy one entry
                break;
            end
        end
    end

    /** update mshr upon mshr hit **/
    // if request is read, change is_req to true
    // if request is write, change is_req NO NEED TO CHANGE MEMORY OPERATION SINCE IT'S WRITE-BACK!!!
    if (mshr_hit) begin
        tmp_next_2_mshr_table[mshr_hit_index].is_req = '1;
    end

    /** allocate new MSHR entry when there are enough MSHR free entry **/
`ifdef ALOC_MSHR_UPON_MSHR_ETY_HIY
    can_allocate_new_mshr_entry =  ( (state == READY) & (next_state == WAIT) ) |
                                   ( (state == WAIT_MSHR) & (next_state == WAIT) );
`else
    can_allocate_new_mshr_entry =  (~mshr_hit) &
                                   ( (state == READY) & (next_state == WAIT) ) |
                                   ( (state == WAIT_MSHR) & (next_state == WAIT) );
`endif
    for (int i=0; i<`N_PF+1;i++) begin
        tmp_next_2_mshr_table[free_mshr_entry_idx[i]].valid = addrs2mshr[i].valid & can_allocate_new_mshr_entry;
        tmp_next_2_mshr_table[free_mshr_entry_idx[i]].is_req = (i==0)? '1:'0; // index zero is the request, the rest are prefetch
        tmp_next_2_mshr_table[free_mshr_entry_idx[i]].issued = '0;
        tmp_next_2_mshr_table[free_mshr_entry_idx[i]].mem_op =  MEM_READ; // for write-back, all request needs to be loaded to cache first. Therefore even though it's store we load the cache line as load operation and write the dirty cache line in place in the cache
        tmp_next_2_mshr_table[free_mshr_entry_idx[i]].Dmem2proc_tag = '0;
        tmp_next_2_mshr_table[free_mshr_entry_idx[i]].Dmem2proc_data = '0;
        tmp_next_2_mshr_table[free_mshr_entry_idx[i]].cache_line_addr = addrs2mshr[i].addr;
        tmp_next_2_mshr_table[free_mshr_entry_idx[i]].write_content = '0;
        // n_mshr_entry_occupied_cnt += addrs2mshr[i].valid;
    end


    /** issue memory request (STILL NEED IT WHEN STATE IS FLUSH) **/
    // find the most proper index to issue
    tmp_next_3_mshr_table = tmp_next_2_mshr_table;    // for signal renaming
    mshr_index_to_issue = '0;
    mshr_index_to_issue_hi_priority = '0;
    mshr_index_to_issue_mid_priority = '0;
    mshr_index_to_issue_low_priority = '0;
    high_priority_exist = '0;
    mid_priority_exist = '0;
    low_priority_exist = '0;
    issue2mem = '0;
    for (int i=0;i<`N_MSHR;i++) begin
        // highest priority: request and write operation SINCE MSHR-WRITE ENTRY CAN BE FREED UPON MEMORY RESPONSE 
        if (tmp_next_2_mshr_table[i].valid & (~tmp_next_2_mshr_table[i].issued) & (tmp_next_2_mshr_table[i].mem_op == MEM_WRITE) ) begin
            mshr_index_to_issue_hi_priority = i;
            high_priority_exist = '1;
            issue2mem = '1;
            break;
        end
    end
    for (int i=0;i<`N_MSHR;i++) begin
        // read request next, should not be prefetch
        if (tmp_next_2_mshr_table[i].valid & (~tmp_next_2_mshr_table[i].issued) & tmp_next_2_mshr_table[i].is_req) begin 
            mshr_index_to_issue_mid_priority = i;
            mid_priority_exist = '1;
            issue2mem = '1;
            break;
        end
    end
    for (int i=0;i<`N_MSHR;i++) begin
        // prefetch is of the lowest priority
        if (tmp_next_2_mshr_table[i].valid & (~tmp_next_2_mshr_table[i].issued) ) begin 
            mshr_index_to_issue_low_priority = i;
            low_priority_exist = '1;
            issue2mem = '1;
            break;
        end
    end
    if (high_priority_exist) begin
        mshr_index_to_issue = mshr_index_to_issue_hi_priority;
    end else if (mid_priority_exist) begin
        mshr_index_to_issue = mshr_index_to_issue_mid_priority;
    end else if (low_priority_exist) begin
        mshr_index_to_issue = mshr_index_to_issue_low_priority;
    end
    // issue request to memory if there is any
    proc2Dmem_addr = '0;
    proc2Dmem_data = '0;
    if (issue2mem) begin
        // form request to memory
        proc2Dmem_command = (tmp_next_2_mshr_table[mshr_index_to_issue].mem_op == MEM_READ) ? BUS_LOAD : BUS_STORE;
        proc2Dmem_addr = tmp_next_2_mshr_table[mshr_index_to_issue].cache_line_addr;
        proc2Dmem_data = tmp_next_2_mshr_table[mshr_index_to_issue].write_content; 
        // wait response from memory
        tmp_next_3_mshr_table[mshr_index_to_issue].issued = '1;
        tmp_next_3_mshr_table[mshr_index_to_issue].Dmem2proc_tag = Dmem2proc_response;
        // if it's store, upon memory response, free the entry immediately
        if ( (tmp_next_2_mshr_table[mshr_index_to_issue].mem_op == MEM_WRITE) & (Dmem2proc_response) )begin
             tmp_next_3_mshr_table[mshr_index_to_issue] = '0; 
            //  n_mshr_entry_freed_cnt ++; // free one entry
        end
    end else begin
        proc2Dmem_command = BUS_NONE;
    end

    /** update mshr free entry count and final version of next_mshr_table**/
    for(int i=1; i<`N_MSHR+1; i++) begin
        if (~tmp_next_3_mshr_table[i-1].valid) begin
            n_mshr_avail_wires[i] = n_mshr_avail_wires[i-1] + 1; 
        end else begin
            n_mshr_avail_wires[i] = n_mshr_avail_wires[i-1];
        end
    end
    next_mshr_table = tmp_next_3_mshr_table;
    next_n_mshr_avail = n_mshr_avail_wires[`N_MSHR];
end
`endif


`ifdef DEBUG
always_ff @(negedge clock) begin

    $display("/*** MSHR self print | time: %0d ***/", $time);
    $display("time: %d MSHR: can_allocate_new_mshr_entry: %d", $time, can_allocate_new_mshr_entry);
    $display("mshr_issue_hi_prio_index: %0d  valid: %0d", mshr_index_to_issue_hi_priority, high_priority_exist);
    $display("mshr_issue_mid_prio_index: %0d  valid: %0d", mshr_index_to_issue_mid_priority, mid_priority_exist);
    $display("mshr_issue_low_prio_index: %0d  valid: %0d", mshr_index_to_issue_low_priority, low_priority_exist);
    $display("/*** issue2mem: %0d ***/", issue2mem);
    $display("/*** mshr_index_to_issue: %0d ***/", mshr_index_to_issue);
    $display("/*** MEMORY ***");
    $display("Dmem2proc_response: %0d", Dmem2proc_response);
    $display("Dmem2proc_tag: %0d", Dmem2proc_tag);
    $display("Dmem2proc_data: %0d", Dmem2proc_data);
    case(proc2Dmem_command)
        BUS_LOAD: $display("proc2Dmem_command: BUS_LOAD");
        BUS_STORE: $display("proc2Dmem_command: BUS_STORE");
        BUS_NONE: $display("proc2Dmem_command: BUS_NONE");
    endcase
    $display("proc2Dmem_addr: %0b", proc2Dmem_addr);
    $display("proc2Dmem_data: %0d", proc2Dmem_data);
    $display("/*** next_mshr_table (0 for READ) | TIME: %d ***/", $time);
    for (int i=0; i<`N_MSHR; i++) begin
        if (next_mshr_table[i].valid) begin
            $write("next_mshr_table[%0d]: ", i);
            $write("  valid: %0d, ", next_mshr_table[i].valid);
            $write("  is_req: %0d, ", next_mshr_table[i].is_req);
            $write("  issued: %0d, ", next_mshr_table[i].issued);
            $write("  mem_op: %0d, ", next_mshr_table[i].mem_op);
            $write("  Dmem2proc_tag: %0d, ", next_mshr_table[i].Dmem2proc_tag);
            $write("  Dmem2proc_data: %0d, ", next_mshr_table[i].Dmem2proc_data);
            $write("  cache_line_addr: %0b, ", next_mshr_table[i].cache_line_addr);
            $write("  write_content: %0d, ", next_mshr_table[i].write_content);
            $display("");
        end
    end
    $display("/*** addrs2mshr ***/");
    for (int i=0; i<`N_PF+1;i++) begin
        $write("addrs2mshr[%0d]  addr:%0b", i, addrs2mshr[i].addr);
        $write("  valid:%0b", addrs2mshr[i].valid);
        $write("  addr_not_in_mc:%0b", addrs2mshr[i].addr_not_in_main_cache);
        $write("  addr_not_in_vc:%0b", addrs2mshr[i].addr_not_in_victim_cache);
        $write("  addr_not_in_pkt:%0b", addrs2mshr[i].addr_not_in_MSHR_packet);
        $write("  addr_not_in_tbl:%0b", addrs2mshr[i].addr_not_in_MSHR_table);
        $write("\n");
    end
end
`endif

// `ifdef DEBUG
// always_ff @(negedge clock) begin
//     $display("/*** idx_wires for MSHR | TIME: %d ***/", $time);
//     for (int i=0; i<`N_MSHR; i++) begin
//         $display("idx_wires[%d]: %d", i, idx_wires[i]);
//     end

//     $display("/*** free_mshr_entry_idx ***/");
//     for (int i=0; i<`N_PF+1; i++) begin
//         $display("free_mshr_entry_idx[%d]: %d", i, free_mshr_entry_idx[i]);
//     end

//      $display("/*** n_mshr_avail_wires ***/");
//     for (int i=0; i<`N_MSHR+1; i++) begin
//         $display("n_mshr_avail_wires[%d]: %d", i, n_mshr_avail_wires[i]);
//     end
// end
// `endif 



/*** determine which cache line the request should go ***/
`ifdef DIRECT_MAPPED
    assign dcache_req_CL_tag = dcache_request.addr[`XLEN - 1 : `N_IDX_BITS + `DC_BO];
`elsif TWO_WAY_SET_ASSOCIATIVE
    assign dcache_req_CL_tag = dcache_request.addr[`XLEN - 1 : `N_IDX_BITS + `DC_BO - 1];
`endif 


/*** determine if it's cache hit ***/
`ifdef DIRECT_MAPPED
    logic [`N_IDX_BITS:0] hit_idx_expected;
    

    assign hit_idx_expected = dcache_request.valid ? dcache_request.addr[`N_IDX_BITS + `DC_BO - 1:`DC_BO] : 
                                                     'x; // debug this
    

    always_comb begin : determine_cache_hit
        main_cache_hit              = '0;
        main_cache_line_upon_hit    = '0;
        main_cache_hit_index        = '0;
        if (dcache_request.valid & (state == READY)) begin
            // check if that line has valid CL and if tag match
            if (main_cache_lines[hit_idx_expected].valid & (main_cache_lines[hit_idx_expected].tag == dcache_req_CL_tag) ) begin
                    main_cache_hit = '1;
                    main_cache_line_upon_hit = main_cache_lines[hit_idx_expected];
                    main_cache_hit_index = hit_idx_expected;
            end
        end
        
    end
`else
   // two way

`endif



/*** determine if it's victim cache hit ***/
always_comb begin : determine_victim_cache_hit
    vc_hit                  = '0;
    vc_hit_index            = '0;
    vic_cache_line_upon_hit = '0;
    if (dcache_request.valid & (state == READY)) begin
        for (int i = 0; i < `N_VC_CL; i++) begin
            if (victim_cache_lines[i].valid & (victim_cache_lines[i].tag == dcache_request.addr[`XLEN-1:`DC_BO]) ) begin
                vc_hit = '1;
                vc_hit_index = i;
                vic_cache_line_upon_hit = victim_cache_lines[i];
                break;
            end
        end
    end
    
end


/*** determine if it's MSHR hit ***/

always_comb begin : determine_MSHR_hit
    mshr_hit            = '0;
    mshr_real_hit       = '0;
    mshr_hit_index      = '0;
    if (dcache_request.valid & (state == READY)) begin
        // can the request be handled on this cycle?
        for (int i = 0; i < `N_MSHR; i++) begin
            if (mshr_table[i].valid & (mshr_table[i].cache_line_addr[`XLEN-1:`DC_BO] == dcache_request.addr[`XLEN-1:`DC_BO]) ) begin
                mshr_hit = '1;
                mshr_hit_index = i;
            end
        end

        for (int i = 0; i < `N_MSHR; i++) begin
            if (mshr_table[i].valid & (mshr_table[i].cache_line_addr[`XLEN-1:`DC_BO] == dcache_request.addr[`XLEN-1:`DC_BO]) & ( (mshr_table[i].Dmem2proc_tag == Dmem2proc_tag) | (mshr_table[i].mem_op == MEM_WRITE) ) ) begin
                mshr_real_hit = '1;
                mshr_hit_index = i;
            end
        end

        if (mshr_real_hit) mshr_hit = '0;

    end
    
end

always_ff @( posedge clock ) begin 
    if (reset) begin
        // dcache_response             <= '0;
        main_cache_lines            <= '0;
        victim_cache_lines          <= '0;
        n_vc_avail                  <= `N_VC_CL;
        mshr_table                  <= '0;
        n_mshr_avail                <= `N_MSHR;
        state                       <=  READY;
        dcache_request_on_wait      <= '0;
        $display("inside ff, N_MSHR: %d", `N_MSHR);
        $display("inside ff, N_VC_CL: %d", `N_VC_CL);
    end else begin
        // dcache_response             <= next_dcache_response;
        main_cache_lines            <= next_main_cache_lines;
        victim_cache_lines          <= next_victim_cache_lines;
        n_vc_avail                  <= next_n_vc_avail;
        mshr_table                  <= next_mshr_table;
        n_mshr_avail                <= next_n_mshr_avail;
        state                       <= next_state;
        dcache_request_on_wait      <= next_dcache_request_on_wait;
    end
end

`ifdef DEBUG
// registers
assign dbg_main_cache_lines             = main_cache_lines;
assign dbg_victim_cache_lines           = victim_cache_lines;
assign dbg_n_vc_avail                   = n_vc_avail;
assign dbg_mshr_table                   = mshr_table;
assign dbg_n_mshr_avail                 = n_mshr_avail;
assign dbg_state                        = state;
assign dbg_dcache_request_on_wait       = dcache_request_on_wait;
// register peripherals
assign dbg_next_main_cache_lines        = next_main_cache_lines;
assign dbg_next_victim_cache_lines      = next_victim_cache_lines;
assign dbg_next_n_vc_avail              = next_n_vc_avail;
assign dbg_next_mshr_table              = next_mshr_table;
assign dbg_next_n_mshr_avail            = next_n_mshr_avail;
assign dbg_next_state                   = next_state;
assign dbg_next_dcache_request_on_wait  = next_dcache_request_on_wait;
// combinationals
assign dbg_cache_hit                    = cache_hit;
assign dbg_main_cache_hit               = main_cache_hit;
assign dbg_main_cache_hit_index         = main_cache_hit_index;
assign dbg_vc_hit                       = vc_hit;
assign dbg_vc_hit_index                 = vc_hit_index;
assign dbg_mshr_hit                     = mshr_hit;
assign dbg_mshr_real_hit                = mshr_real_hit;
assign dbg_mshr_hit_index               = mshr_hit_index;
assign dbg_request_finished             = request_finished;
// communication wires
assign dbg_mshr2dcache_packet           = mshr2dcache_packet;
assign dbg_vic_cache_line_evicted       = vic_cache_line_evicted;
assign dbg_main_cache_line_evicted      = main_cache_line_evicted;
assign dbg_main_cache_line_evicted_addr  = main_cache_line_evicted_addr;
assign dbg_main_cache_line_upon_hit     = main_cache_line_upon_hit;
assign dbg_vic_cache_line_upon_hit      = vic_cache_line_upon_hit;
// main cache related
assign dbg_cache_line_index_for_new_data        = cache_line_index_for_new_data;
assign dbg_need_to_evict                        = need_to_evict;
assign dbg_mshr2dcache_packet_USED              = mshr2dcache_packet_USED;
assign dbg_loaded_CL_same_addr_as_evicted_CL    = loaded_CL_same_addr_as_evicted_CL;
assign dbg_cache_line_index_for_MSHR_real_hit   = cache_line_index_for_MSHR_real_hit;
assign dbg_need_to_evict_MSHR_real_hit          = need_to_evict_MSHR_real_hit;
assign dbg_main_cache_response_case             = main_cache_response_case;
// victim cache related
assign dbg_vc_need_evict                        = vc_need_evict;
assign dbg_vc_CL_evicted                        = vc_CL_evicted;
assign dbg_vc_CL_evicted_index                  = vc_CL_evicted_index;
assign dbg_vc_free_index                        = vc_free_index;
assign dbg_current_smallest_index               = current_smallest_index;
assign dbg_current_smallest_lru                 = current_smallest_lru;
assign dbg_index_selector                       = index_selector;
// MSHR related
assign dbg_addrs2mshr                          = addrs2mshr;
assign dbg_base_addr                           = base_addr;
assign dbg_free_mshr_entry_idx                 = free_mshr_entry_idx;
assign dbg_idx_wires                           = idx_wires;
assign dbg_mshr_index_to_issue                 = mshr_index_to_issue;
assign dbg_mshr_index_to_issue_hi_priority     = mshr_index_to_issue_hi_priority;
assign dbg_mshr_index_to_issue_mid_priority    = mshr_index_to_issue_mid_priority;
assign dbg_mshr_index_to_issue_low_priority    = mshr_index_to_issue_low_priority;
assign dbg_high_priority_exist                 = high_priority_exist;
assign dbg_mid_priority_exist                  = mid_priority_exist;
assign dbg_low_priority_exist                  = low_priority_exist;
assign dbg_issue2mem                           = issue2mem;
assign dbg_can_allocate_new_mshr_entry         = can_allocate_new_mshr_entry;
assign dbg_tmp_next_1_mshr_table               = tmp_next_1_mshr_table;
assign dbg_tmp_next_2_mshr_table               = tmp_next_2_mshr_table;
assign dbg_tmp_next_3_mshr_table               = tmp_next_3_mshr_table;
assign dbg_n_mshr_avail_wires                  = n_mshr_avail_wires;




`endif 
endmodule





