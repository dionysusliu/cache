

`ifndef __CACHE_DEFS_SVH__
`define __CACHE_DEFS_SVH__

`include "sys_defs.svh"



// data to pipeline registers
typedef logic [`XLEN-1:0] REG_DATA_T;

// program counter 
typedef logic [`XLEN-1:0] PC_T;

// Uniform memory request/ response structs
typedef enum logic { MEM_READ, MEM_WRITE } MEM_OP_T;

// memory address
typedef logic [`XLEN-1:0] MEM_ADDR_T;



// granularity of memory access
typedef enum logic [1:0] {
  BYTE   = 2'h0,
  HALF   = 2'h1,
  WORD   = 2'h2
} MEM_SIZE;

// ***** dcache related ***** //

// internal state of dcache
typedef enum logic [1:0] { READY, WAIT, WAIT_MSHR, FLUSH } DC_STATE_T;

// for main cache debug
typedef enum logic [3:0] { NONE, HIT, HIT_ON_MSHR_TABLE, HIT_ON_MSHR_PKT, FWD_FROM_MSHR_PKT} DBG_MAIN_CACHE_STATE_T;

// associativity
`define DIRECT_MAPPED
// `define TWO_WAY_SET_ASSOCIATIVE 

// cache size in Byte
`define DCACHE_SIZE 32

// victim cache size in Byte
`define VICTIM_CACHE_SIZE 16


// cache block size in Byte
`define DC_BLK_SZ 8

// number of index bits for block offset
`define DC_BO $clog2(`DC_BLK_SZ)


// number of cache lines
`define N_CL (`DCACHE_SIZE/`DC_BLK_SZ)

// number of victim cache line
`define N_VC_CL (`VICTIM_CACHE_SIZE/`DC_BLK_SZ)


`ifdef DIRECT_MAPPED
  // number of index bit for directed mapped
  `define N_IDX_BITS ( $clog2(`DCACHE_SIZE/`DC_BLK_SZ)  )
`elsif TWO_WAY_SET_ASSOCIATIVE
  // number of index bit for TWSA
  `define N_IDX_BITS ( $clog2(`DCACHE_SIZE/`DC_BLK_SZ) - 1 )
`else 
  `define N_IDX_BITS 100
`endif 

// number of bits for cache line tag
`define DC_TAG_LEN (`XLEN - `DC_BO - `N_IDX_BITS)


typedef struct packed {
  MEM_OP_T mem_op;  // read/write
  MEM_ADDR_T addr;  // {(`XLEN-3)'b?, 3'b0} last three bits must be zero
  MEM_SIZE size;    // byte, half, word
  REG_DATA_T write_content;
  logic valid;   
  PC_T pc;
} DCACHE_REQUEST;

typedef struct packed {
    REG_DATA_T reg_data;
    logic valid;
    MEM_OP_T mem_op;
} DCACHE_RESPONSE;


typedef struct packed {
    logic valid;
    EXAMPLE_CACHE_BLOCK block;
    logic dirty;
    logic [`DC_TAG_LEN-1:0] tag;
    `ifdef DEBUG
      MEM_ADDR_T addr;
    `endif
} CACHE_LINE;

typedef struct packed {
    logic valid;
    EXAMPLE_CACHE_BLOCK block;
    logic dirty;
    logic [$clog2(`N_VC_CL)-1:0] lru;
    logic [`XLEN-1:3] tag;
} VICTIM_CACHE_LINE;

// number of CLs to prefetch
`define N_PF 2

typedef struct packed {
    logic valid;
    MEM_ADDR_T addr;
    logic addr_not_in_main_cache;
    logic addr_not_in_victim_cache;
    logic addr_not_in_MSHR_packet;
    logic addr_not_in_MSHR_table;
} PREFETCH_ADDR_T;

// number of MSHR registers
`define N_MSHR 8

// MSHR entry
typedef struct packed {
  logic valid;
  logic is_req;  // 1 if it's request by pipeline; 0 means prefetch
  logic issued;  // 1 if it's issued to memory
  MEM_OP_T mem_op; // read(0) or write(1)
  logic [3:0] Dmem2proc_tag; // zero means no tag, also means not issued to memory yet.
  REG_DATA_T Dmem2proc_data; // data from memory
  MEM_ADDR_T cache_line_addr;
  REG_DATA_T write_content; // things to write to memory
} MSHR_ENTRY;
`endif