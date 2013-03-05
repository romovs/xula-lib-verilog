////////////////////////////////////////////////////////////////////////////////////////////////////
// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License
// as published by the Free Software Foundation; either version 2
// of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program; if not, write to the Free Software
// Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA
// 02111-1307, USA.
//
// ©2013 - Roman Ovseitsev <romovs@gmail.com>      
// Based on code ©2011 - X Engineering Software Systems Corp. (www.xess.com)
////////////////////////////////////////////////////////////////////////////////////////////////////

//##################################################################################################
//
// Single Port SDRAM controller for XuLA-200.
//
//##################################################################################################

`timescale 1ns / 1ps


module SdramCtrl (clk_i, lock_i, rst_i, rd_i, wr_i, earlyOpBegun_o, opBegun_o, rdPending_o, done_o, 
                  rdDone_o, addr_i, data_i, data_o, status_o, sdCke_o, sdCe_bo, sdRas_bo, sdCas_bo,
                  sdWe_bo, sdBs_o, sdAddr_o, sdData_io, sdDqmh_o, sdDqml_o);
                  
   `include "Math.v"           

         
   parameter   real FREQ = 12.0;          // Operating frequency in MHz.
   parameter   PIPE_EN = 0;               // If true, enable pipelined read operations.

   //`define     MULTIPLE_ACTIVE_ROWS_D     // If defined allow an active row in each bank.
   
   localparam  IN_PHASE = 1;              // SDRAM and controller work on same or opposite clock edge.
   localparam  MAX_NOPS = 10000;          // Number of NOPs before entering self-refresh.
   localparam  ENABLE_REFRESH = 1;        // If true, row refreshes are automatically inserted.
   
   `ifdef      MULTIPLE_ACTIVE_ROWS_D
      localparam  MULTIPLE_ACTIVE_ROWS = 1;  // If true, allow an active row in each bank. 
   `else
      localparam  MULTIPLE_ACTIVE_ROWS = 0;
   `endif
   
   localparam  DATA_WIDTH = 16;           // Host & SDRAM data width.

   // Parameters for Winbond W9812G6JH-6 (all times are in nanoseconds).
   localparam  NROWS = 4096;              // Number of rows in SDRAM array.
   localparam  NCOLS = 512;               // Number of columns in SDRAM array.
   localparam  HADDR_WIDTH = 23;          // Host-side address width.
   localparam  SADDR_WIDTH = 12;          // SDRAM-side address width.
   localparam  BANK_ADDR_WIDTH = 2;       // Width of the bank address. Requires additional changes
                                          // of logic related to activeRow_r if modified.
   localparam  real T_INIT = 200000.0;    // min initialization interval (ns).
   localparam  real T_RAS = 42.0;         // min interval between active to precharge commands (ns).
   localparam  real T_RCD = 15.0;         // min interval between active and R/W commands (ns).
   localparam  real T_REF = 64000000.0;   // maximum refresh interval (ns).
   localparam  real T_RFC = 60.0;         // duration of refresh operation (ns).
   localparam  real T_RP = 15.0;          // min precharge command duration (ns).
   localparam  real T_XSR = 72.0;         // exit self-refresh time (ns). 

   // Host side.
   input wire  clk_i;                     // Master clock.
   input wire  lock_i;                    // True if clock is stable.
   input wire  rst_i;                     // Reset.
   input wire  rd_i;                      // Initiate read operation.
   input wire  wr_i;                      // Initiate write operation.
   output reg  earlyOpBegun_o;            // Read/write/self-refresh op has begun (async).
   output wire opBegun_o;                 // Read/write/self-refresh op has begun (clocked).
   output reg  rdPending_o;               // True if read operation(s) are still in the pipeline.
   output reg  done_o;                    // Read or write operation is done_o.
   output reg  rdDone_o;                  // Read operation is done_o and data is available.
   input wire  [HADDR_WIDTH-1:0] addr_i;  // Address from host to SDRAM.
   input wire  [DATA_WIDTH-1:0] data_i;   // Data from host to SDRAM.
   output wire [DATA_WIDTH-1:0] data_o;   // Data from SDRAM to host.
   output reg  [3:0] status_o;            // Diagnostic status of the FSM         .

   // SDRAM side.
   output      sdCke_o;                   // Clock-enable to SDRAM.
   output      sdCe_bo;                   // Chip-select to SDRAM.
   output      sdRas_bo;                  // SDRAM row address strobe.
   output      sdCas_bo;                  // SDRAM column address strobe.
   output      sdWe_bo;                   // SDRAM write enable.
   output      [BANK_ADDR_WIDTH-1:0] sdBs_o; // SDRAM bank address.
   output      [SADDR_WIDTH-1:0] sdAddr_o;   // SDRAM row/column address.
   inout       [DATA_WIDTH-1:0] sdData_io;   // Data to/from SDRAM.
   output      sdDqmh_o;                  // Enable upper-byte of SDRAM databus if true.
   output      sdDqml_o;                  // Enable lower-byte of SDRAM databus if true.
   
   
   localparam  OUTPUT_C = 1;              // direction of dataflow w.r.t. this controller.
   localparam  INPUT_C = 0;
   localparam  NOP_C = 0;                 // no operation.
   localparam  READ_C = 1;                // read operation.
   localparam  WRITE_C = 1;               // write operation.

   // SDRAM timing parameters converted into clock cycles (based on FREQ).    
   localparam  INIT_CYCLES_C = ceil(T_INIT*FREQ/1000.0);    // SDRAM power-on initialization interval.
   localparam  RAS_CYCLES_C = ceil(T_RAS*FREQ/1000.0);      // active-to-precharge interval.
   localparam  RCD_CYCLES_C = pfx(ceil(T_RCD*FREQ/1000.0)); // active-to-R/W interval.
   localparam  REF_CYCLES_C = ceil(T_REF*FREQ/1000.0/NROWS);// interval between row refreshes.
   localparam  RFC_CYCLES_C = ceil(T_RFC*FREQ/1000.0);      // refresh operation interval. 
   localparam  RP_CYCLES_C = ceil(T_RP*FREQ/1000.0);        // precharge operation interval.
   localparam  WR_CYCLES_C = 2;                             // write recovery time.
   localparam  XSR_CYCLES_C = ceil(T_XSR*FREQ/1000.0);      // exit self-refresh time.
   localparam  MODE_CYCLES_C = 2;                           // mode register setup time.
   localparam  CAS_CYCLES_C = 3;                            // CAS latency.
   localparam  RFSH_OPS_C = 8;                              // number of refresh operations needed to init SDRAM.
  
   // timer registers that count down times for various SDRAM operations.
   reg         [clog2(INIT_CYCLES_C):0] timer_r = 0;     // current SDRAM op time.
   reg         [clog2(INIT_CYCLES_C):0] timer_x = 0;
   reg         [clog2(RAS_CYCLES_C):0] rasTimer_r = 0;   // active-to-precharge time.
   reg         [clog2(RAS_CYCLES_C):0] rasTimer_x = 0;
   reg         [clog2(WR_CYCLES_C):0] wrTimer_r = 0;     // write-to-precharge time.
   reg         [clog2(WR_CYCLES_C):0] wrTimer_x = 0;
   reg         [clog2(REF_CYCLES_C):0] refTimer_r = REF_CYCLES_C;// time between row refreshes.
   reg         [clog2(REF_CYCLES_C):0] refTimer_x = REF_CYCLES_C;
   reg         [clog2(NROWS):0] rfshCntr_r = 0;          // counts refreshes that are needed.
   reg         [clog2(NROWS):0] rfshCntr_x = 0;
   reg         [clog2(MAX_NOPS):0] nopCntr_r = 0;        // counts consecutive NOP_C operations.
   reg         [clog2(MAX_NOPS):0] nopCntr_x = 0;

   reg          doSelfRfsh_s;       // active when the NOP counter hits zero and self-refresh can start.

   // states of the SDRAM controller state machine.
   localparam  INITWAIT    = 'b000;       // initialization - waiting for power-on initialization to complete.
   localparam  INITPCHG    = 'b001;       // initialization - initial precharge of SDRAM banks.
   localparam  INITSETMODE = 'b010;       // initialization - set SDRAM mode.
   localparam  INITRFSH    = 'b011;       // initialization - do initial refreshes.
   localparam  RW          = 'b100;       // read/write/refresh the SDRAM.
   localparam  ACTIVATE    = 'b101;       // open a row of the SDRAM for reading/writing.
   localparam  REFRESHROW  = 'b110;       // refresh a row of the SDRAM.
   localparam  SELFREFRESH = 'b111;       // keep SDRAM in self-refresh mode with CKE low.

   reg         [2:0] state_r = INITWAIT;  // state register and next state.
   reg         [2:0] state_x = INITWAIT;  // state register and next state.
   
   // commands that are sent to the SDRAM to make it perform certain operations.
   // commands use these SDRAM input pins (ce_bo,ras_bo,cas_bo,we_bo,dqmh_o,dqml_o).
   localparam  [5:0] NOP_CMD_C      = 'b011100;
   localparam  [5:0] ACTIVE_CMD_C   = 'b001100;
   localparam  [5:0] READ_CMD_C     = 'b010100;
   localparam  [5:0] WRITE_CMD_C    = 'b010000;
   localparam  [5:0] PCHG_CMD_C     = 'b001000;
   localparam  [5:0] MODE_CMD_C     = 'b000000;
   localparam  [5:0] RFSH_CMD_C     = 'b000100;

   // SDRAM mode register.
   // the SDRAM is placed in a non-burst mode (burst length = 1) with a 3-cycle CAS.
   localparam  [11:0] MODE_C = 'b00_0_00_011_0_000;

   // the host address is decomposed into these sets of SDRAM address components.
   localparam  ROW_LEN_C = clog2(NROWS);  // number of row address bits.
   localparam  COL_LEN_C = clog2(NCOLS);  // number of column address bits.
   
   reg         [BANK_ADDR_WIDTH-1:0] bank_s; // bank address bits.
   reg         [ROW_LEN_C-1:0] row_s;        // row address within bank.
   reg         [SADDR_WIDTH-1:0] col_s;      // column address within row.

   // registers that store the currently active row in each bank of the SDRAM.
   localparam  NUM_ACTIVE_ROWS = (MULTIPLE_ACTIVE_ROWS == 0 ? 1 : 2**BANK_ADDR_WIDTH);
   localparam  NUM_ACTIVE_ROWS_WIDTH = (MULTIPLE_ACTIVE_ROWS == 0 ? 1 : BANK_ADDR_WIDTH);
   
   reg         [ROW_LEN_C-1:0] activeRow_r [NUM_ACTIVE_ROWS_WIDTH-1:0];
   reg         [ROW_LEN_C-1:0] activeRow_x [NUM_ACTIVE_ROWS_WIDTH-1:0];
   reg         [NUM_ACTIVE_ROWS-1:0] activeFlag_r = 0;   // indicates that some row in a bank is active.
   reg         [NUM_ACTIVE_ROWS-1:0] activeFlag_x = 0; 
   reg         [NUM_ACTIVE_ROWS_WIDTH-1:0] bankIndex_s;  // bank address bits.
   reg         [BANK_ADDR_WIDTH-1:0] activeBank_r;       // indicates the bank with the active row.
   reg         [BANK_ADDR_WIDTH-1:0] activeBank_x;
   reg         doActivate_s;    // indicates when a new row in a bank needs to be activated.

   // there is a command bit embedded within the SDRAM column address.
   localparam  CMDBIT_POS_C      = 10;       // position of command bit.
   localparam  AUTO_PCHG_ON_C    = 1;        // CMDBIT value to auto-precharge the bank.
   localparam  AUTO_PCHG_OFF_C   = 0;        // CMDBIT value to disable auto-precharge.
   localparam  ONE_BANK_C        = 0;        // CMDBIT value to select one bank.
   localparam  ALL_BANKS_C       = 1;        // CMDBIT value to select all banks.

   // status signals that indicate when certain operations are in progress.
   reg         wrInProgress_s;               // write operation in progress.
   reg         rdInProgress_s;               // read operation in progress.
   reg         activateInProgress_s;         // row activation is in progress.

   // these registers track the progress of read and write operations.
   reg         [CAS_CYCLES_C+1:0] rdPipeline_r = 0; 
   reg         [CAS_CYCLES_C+1:0] rdPipeline_x = 0;   // pipeline of read ops in progress.
   reg         wrPipeline_r = 0; 
   reg         wrPipeline_x = 0;                      // pipeline of write ops (only need 1 cycle).

   // registered outputs to host.
   reg         opBegun_r = 0; 
   reg         opBegun_x = 0; // true when SDRAM read or write operation is started.
   reg         [DATA_WIDTH-1:0] sdramData_r = 0; 
   reg         [DATA_WIDTH-1:0] sdramData_x = 0;      // holds data read from SDRAM and sent to the host.
   reg         [DATA_WIDTH-1:0] sdramDataOppPhase_r; 
   reg         [DATA_WIDTH-1:0] sdramDataOppPhase_x;  // holds data read from SDRAM on opposite clock edge.

   // registered outputs to SDRAM.
   reg         cke_r = 0; 
   reg         cke_x = 0;                             // Clock-enable bit.
   reg         [5:0] cmd_r = NOP_CMD_C;
   reg         [5:0] cmd_x = NOP_CMD_C;               // SDRAM command bits.
   reg         [BANK_ADDR_WIDTH-1:0] ba_r; 
   reg         [BANK_ADDR_WIDTH-1:0] ba_x;            // SDRAM bank address bits.
   reg         [SADDR_WIDTH-1:0] sAddr_r = 0; 
   reg         [SADDR_WIDTH-1:0] sAddr_x = 0;         // SDRAM row/column address.
   reg         [DATA_WIDTH-1:0] sData_r = 0;
   reg         [DATA_WIDTH-1:0] sData_x = 0;          // SDRAM out databus.
   reg         sDataDir_r = INPUT_C; 
   reg         sDataDir_x = INPUT_C;                  // SDRAM databus direction control bit. 


   // attach registered SDRAM control signals to SDRAM input pins
   assign {sdCe_bo, sdRas_bo, sdCas_bo, sdWe_bo, sdDqmh_o, sdDqml_o} = cmd_r;    // SDRAM operation control bits
   assign sdCke_o  = cke_r;   // SDRAM clock enable
   assign sdBs_o  = ba_r;     // SDRAM bank address
   assign sdAddr_o = sAddr_r; // SDRAM address
   assign sdData_io = (sDataDir_r == OUTPUT_C) ? sData_r : 16'bz;  // SDRAM output data bus
   
   // attach some port signals
   assign data_o = sdramData_r;     // data back to host
   assign opBegun_o = opBegun_r;    // true if requested operation has begun


   //*********************************************************************
   // compute the next state and outputs 
   //*********************************************************************
  
   always @(rd_i, wr_i, addr_i, data_i, sdramData_r, sdData_io, state_r, opBegun_x, activeFlag_r, 
            activeBank_r, rdPipeline_r, wrPipeline_r, sdramDataOppPhase_r, nopCntr_r, 
            lock_i, rfshCntr_r, timer_r, rasTimer_r, wrTimer_r, refTimer_r, cmd_r, col_s, ba_r, cke_r,
            rdInProgress_s, activateInProgress_s, wrInProgress_s, doActivate_s, doSelfRfsh_s,
            `ifdef      MULTIPLE_ACTIVE_ROWS_D
               activeRow_r[1], activeRow_r[0]
            `else
               activeRow_r[0]
            `endif
            ) begin

  
      //*********************************************************************
      // setup default values for signals 
      //*********************************************************************

      opBegun_x      = 0;              // no operations have begun
      earlyOpBegun_o = opBegun_x;
      cke_x          = 1;              // enable SDRAM clock
      cmd_x          = NOP_CMD_C;      // set SDRAM command to no-operation
      sDataDir_x     = INPUT_C;        // accept data from the SDRAM
      sData_x        = data_i;         // output data from host to SDRAM
      state_x        = state_r;        // reload these registers and flags
      activeFlag_x   = activeFlag_r;   // with their existing values

      `ifdef   MULTIPLE_ACTIVE_ROWS_D
         activeRow_x[0] = activeRow_r[0];
         activeRow_x[1] = activeRow_r[1];
      `else
         activeRow_x[0] = activeRow_r[0];
      `endif

      activeBank_x   = activeBank_r;
      rfshCntr_x     = rfshCntr_r;
      
      
      //*********************************************************************
      // setup default value for the SDRAM address 
      //*********************************************************************

      // extract bank field from host address
      ba_x = addr_i[BANK_ADDR_WIDTH + ROW_LEN_C + COL_LEN_C - 1 : ROW_LEN_C + COL_LEN_C];
      if (MULTIPLE_ACTIVE_ROWS == 1) begin
         bank_s      = 0;
         bankIndex_s = ba_x;
      end else begin
         bank_s      = ba_x;
         bankIndex_s = 0;
      end
      // extract row, column fields from host address
      row_s = addr_i[ROW_LEN_C + COL_LEN_C - 1 : COL_LEN_C];
      // extend column (if needed) until it is as large as the (SDRAM address bus - 1)
      col_s = 0; // set it to all zeroes
      col_s[COL_LEN_C-1 : 0] = addr_i[COL_LEN_C-1 : 0];
      // by default, set SDRAM address to the column address with interspersed
      // command bit set to disable auto-precharge
      sAddr_x   = {col_s[SADDR_WIDTH-1 : CMDBIT_POS_C], AUTO_PCHG_OFF_C, col_s[CMDBIT_POS_C-1 : 0]};
    

      //*********************************************************************
      // manage the read and write operation pipelines
      //*********************************************************************

      // determine if read operations are in progress by the presence of
      // READ flags in the read pipeline 
      if (rdPipeline_r[CAS_CYCLES_C+1 : 1] != 0) begin
         rdInProgress_s = 1;
      end else begin
         rdInProgress_s = 0;
      end
      rdPending_o = rdInProgress_s; // tell the host if read operations are in progress

      // enter NOPs into the read and write pipeline shift registers by default
      rdPipeline_x = {NOP_C, rdPipeline_r[CAS_CYCLES_C+1 : 1]};
      wrPipeline_x = NOP_C;

      // transfer data from SDRAM to the host data register if a read flag has exited the pipeline
      // (the transfer occurs 1 cycle before we tell the host the read operation is done)
      if (rdPipeline_r[1] == READ_C) begin
         sdramDataOppPhase_x = sdData_io[DATA_WIDTH-1:0];  // gets value on the SDRAM databus on the opposite phase
         if (IN_PHASE == 1) begin
           // get the SDRAM data for the host directly from the SDRAM if the controller and SDRAM are in-phase
           sdramData_x = sdData_io[DATA_WIDTH-1:0];
         end else begin
           // otherwise get the SDRAM data that was gathered on the previous opposite clock edge
           sdramData_x = sdramDataOppPhase_r[DATA_WIDTH-1:0];
         end
      end else begin
         // retain contents of host data registers if no data from the SDRAM has arrived yet
         sdramDataOppPhase_x = sdramDataOppPhase_r;
         sdramData_x         = sdramData_r;
      end

      done_o   = rdPipeline_r[0] | wrPipeline_r;   // a read or write operation is done
      rdDone_o = rdPipeline_r[0];                  // SDRAM data available when a READ flag exits the pipeline 

    
      //*********************************************************************
      // manage row activation
      //*********************************************************************

      // request a row activation operation if the row of the current address
      // does not match the currently active row in the bank, or if no row
      // in the bank is currently active
      if ((bank_s != activeBank_r) || (row_s != activeRow_r[bankIndex_s]) || (activeFlag_r[bankIndex_s] == 0)) begin
         doActivate_s = 1;
      end else begin
         doActivate_s = 0;
      end

      //*********************************************************************
      // manage self-refresh
      //*********************************************************************

      // enter self-refresh if neither a read or write is requested for MAX_NOP consecutive cycles.
      if ((rd_i == 1) || (wr_i == 1)) begin
         // any read or write resets NOP counter and exits self-refresh state
         nopCntr_x    = 0;
         doSelfRfsh_s = 0;
      end else if (nopCntr_r != MAX_NOPS) begin
         // increment NOP counter whenever there is no read or write operation 
         nopCntr_x    = nopCntr_r + 1;
         doSelfRfsh_s = 0;
      end else begin
         // start self-refresh when counter hits maximum NOP count and leave counter unchanged
         nopCntr_x    = nopCntr_r;
         doSelfRfsh_s = 1;
      end

    
      //*********************************************************************
      // update the timers 
      //*********************************************************************

      // row activation timer
      if (rasTimer_r != 0) begin
         // decrement a non-zero timer and set the flag
         // to indicate the row activation is still inprogress
         rasTimer_x           = rasTimer_r - 1;
         activateInProgress_s = 1;
      end else  begin
         // on timeout, keep the timer at zero and reset the flag
         // to indicate the row activation operation is done
         rasTimer_x           = rasTimer_r;
         activateInProgress_s = 0;
      end

      // write operation timer            
      if (wrTimer_r != 0) begin
         // decrement a non-zero timer and set the flag
         // to indicate the write operation is still inprogress
         wrTimer_x      = wrTimer_r - 1;
         wrInProgress_s = 1;
      end else begin
         // on timeout, keep the timer at zero and reset the flag that
         // indicates a write operation is in progress
         wrTimer_x      = wrTimer_r;
         wrInProgress_s = 0;
      end

      // refresh timer            
      if (refTimer_r != 0) begin
         refTimer_x = refTimer_r - 1;
      end else begin
         // on timeout, reload the timer with the interval between row refreshes
         // and increment the counter for the number of row refreshes that are needed
         refTimer_x = REF_CYCLES_C;
         if (ENABLE_REFRESH == 1) begin
            rfshCntr_x = rfshCntr_r + 1;
         end else begin
            rfshCntr_x = 0; // refresh never occurs if this counter never gets above zero
         end
      end

      // main timer for sequencing SDRAM operations               
      if (timer_r != 0) begin
         // decrement the timer and do nothing else since the previous operation has not completed yet.
         timer_x  = timer_r - 1;
         status_o = 'b0000;
      end else begin
         // the previous operation has completed once the timer hits zero
         timer_x = timer_r;             // by default, leave the timer at zero

         //*********************************************************************
         // compute the next state and outputs 
         //*********************************************************************
         case (state_r)

           //*********************************************************************
           // let clock stabilize and then wait for the SDRAM to initialize 
           //*********************************************************************
           INITWAIT: begin
                if (lock_i == 1) begin
                  // wait for SDRAM power-on initialization once the clock is stable
                  timer_x = INIT_CYCLES_C;  // set timer for initialization duration
                  state_x = INITPCHG;
                end else begin
                  // disable SDRAM clock and return to this state if the clock is not stable
                  // this insures the clock is stable before enabling the SDRAM
                  // it also insures a clean startup if the SDRAM is currently in self-refresh mode
                  cke_x = 0;
                end
                status_o = 'b0001;
             end

           //*********************************************************************
           // precharge all SDRAM banks after power-on initialization 
           //*********************************************************************
           INITPCHG: begin
                cmd_x                 = PCHG_CMD_C;
                sAddr_x[CMDBIT_POS_C] = ALL_BANKS_C; // precharge all banks
                timer_x               = RP_CYCLES_C; // set timer for precharge operation duration
                rfshCntr_x            = RFSH_OPS_C;  // set counter for refresh ops needed after precharge
                state_x               = INITRFSH;
                status_o              = 'b0010;
             end

           //*********************************************************************
           // refresh the SDRAM a number of times after initial precharge 
           //*********************************************************************
           INITRFSH: begin
                cmd_x      = RFSH_CMD_C;
                timer_x    = RFC_CYCLES_C;      // set timer to refresh operation duration
                rfshCntr_x = rfshCntr_r - 1;    // decrement refresh operation counter
                if (rfshCntr_r == 1) begin
                  state_x = INITSETMODE;        // set the SDRAM mode once all refresh ops are done
                end
                status_o = 'b0011;
             end
           //*********************************************************************
           // set the mode register of the SDRAM 
           //*********************************************************************
           INITSETMODE: begin
                cmd_x         = MODE_CMD_C;
                sAddr_x       = 0;
                sAddr_x[11:0] = MODE_C;         // output mode register bits on the SDRAM address bits
                timer_x       = MODE_CYCLES_C;  // set timer for mode setting operation duration
                state_x       = RW;
                status_o      = 'b0100;
            end
           //*********************************************************************
           // process read/write/refresh operations after initialization is done 
           //*********************************************************************
           RW: begin
               //*********************************************************************
               // highest priority operation: row refresh 
               // do a refresh operation if the refresh counter is non-zero
               //*********************************************************************
                if (rfshCntr_r != 0) begin
                  // wait for any row activations, writes or reads to finish before doing a precharge
                  if ((activateInProgress_s == 0) && (wrInProgress_s == 0) && (rdInProgress_s == 0)) begin
                    cmd_x                 = PCHG_CMD_C;  // initiate precharge of the SDRAM
                    sAddr_x[CMDBIT_POS_C] = ALL_BANKS_C; // precharge all banks
                    timer_x               = RP_CYCLES_C; // set timer for this operation
                    activeFlag_x          = 0; // all rows are inactive after a precharge operation
                    state_x               = REFRESHROW;  // refresh the SDRAM after the precharge
                  end
                  status_o = 'b0101;
               //*********************************************************************
               // do a host-initiated read operation 
               //*********************************************************************
                end else if (rd_i == 1) begin
                  // Wait one clock cycle if the bank address has just changed and each bank has its own active row.
                  // This gives extra time for the row activation circuitry.
                  if ((ba_x == ba_r) || (MULTIPLE_ACTIVE_ROWS == 0)) begin
                   // activate a new row if the current read is outside the active row or bank
                    if (doActivate_s == 1) begin
                      // activate new row only if all previous activations, writes, reads are done
                      if ((activateInProgress_s == 0) && (wrInProgress_s == 0) && (rdInProgress_s == 0)) begin
                        cmd_x                     = PCHG_CMD_C;  // initiate precharge of the SDRAM
                        sAddr_x[CMDBIT_POS_C]     = ONE_BANK_C; // precharge this bank
                        timer_x                   = RP_CYCLES_C;  // set timer for this operation
                        activeFlag_x[bankIndex_s] = 0; // rows in this bank are inactive after a precharge operation
                        state_x                   = ACTIVATE;  // activate the new row after the precharge is done
                      end
                    // read from the currently active row if no previous read operation
                    // is in progress or if pipeline reads are enabled
                    // we can always initiate a read even if a write is already in progress
                    end else if ((rdInProgress_s == 0) || PIPE_EN == 1) begin
                      cmd_x        = READ_CMD_C;   // initiate a read of the SDRAM
                      // insert a flag into the pipeline shift register that will exit the end
                      // of the shift register when the data from the SDRAM is available
                      rdPipeline_x = {READ_C, rdPipeline_r[CAS_CYCLES_C+1 : 1]};
                      opBegun_x    = 1;  // tell the host the requested operation has begun
                    end
                  end
                  status_o = 'b0110;
               //*********************************************************************
               // do a host-initiated write operation 
               //*********************************************************************
                end else if (wr_i == 1) begin
                  // Wait one clock cycle if the bank address has just changed and each bank has its own active row.
                  // This gives extra time for the row activation circuitry.
                  if ((ba_x == ba_r) || (MULTIPLE_ACTIVE_ROWS == 0)) begin
                   // activate a new row if the current write is outside the active row or bank
                    if (doActivate_s == 1) begin
                     // activate new row only if all previous activations, writes, reads are done
                      if ((activateInProgress_s == 0) && (wrInProgress_s == 0) && (rdInProgress_s == 0)) begin
                        cmd_x                     = PCHG_CMD_C;  // initiate precharge of the SDRAM
                        sAddr_x[CMDBIT_POS_C]     = ONE_BANK_C;  // precharge this bank
                        timer_x                   = RP_CYCLES_C;  // set timer for this operation
                        activeFlag_x[bankIndex_s] = 0;  // rows in this bank are inactive after a precharge operation
                        state_x                   = ACTIVATE; // activate the new row after the precharge is done
                      end
                    // write to the currently active row if no previous read operations are in progress
                    end else if (rdInProgress_s == 0) begin
                      cmd_x           = WRITE_CMD_C;  // initiate the write operation
                      sDataDir_x      = OUTPUT_C; // turn on drivers to send data to SDRAM
                      // set timer so precharge doesn't occur too soon after write operation
                      wrTimer_x       = WR_CYCLES_C;
                     // insert a flag into the 1-bit pipeline shift register that will exit on the
                     // next cycle.  The write into SDRAM is not actually done by that time, but
                     // this doesn't matter to the host
                      wrPipeline_x = WRITE_C;
                      opBegun_x       = 1;  // tell the host the requested operation has begun
                    end
                  end
                  status_o = 'b0111;
               //*********************************************************************
               // do a host-initiated self-refresh operation 
               //*********************************************************************
                end else if (doSelfRfsh_s == 1) begin
                  // wait until all previous activations, writes, reads are done
                  if ((activateInProgress_s == 0) && (wrInProgress_s == 0) && (rdInProgress_s == 0)) begin
                    cmd_x                 = PCHG_CMD_C;  // initiate precharge of the SDRAM
                    sAddr_x[CMDBIT_POS_C] = ALL_BANKS_C;  // precharge all banks
                    timer_x               = RP_CYCLES_C;  // set timer for this operation
                    activeFlag_x          = 0; // all rows are inactive after a precharge operation
                    state_x               = SELFREFRESH;  // self-refresh the SDRAM after the precharge
                  end
                  status_o = 'b1000;
               //*********************************************************************
               // no operation
               //*********************************************************************
                end else begin
                  state_x  = RW;  // continue to look for SDRAM operations to execute
                  status_o = 'b1001;
                end
             
             end

           //*********************************************************************
           // activate a row of the SDRAM 
           //*********************************************************************
           ACTIVATE: begin
                cmd_x                     = ACTIVE_CMD_C;
                sAddr_x                   = 0;        // output the address for the row to be activated
                sAddr_x[ROW_LEN_C - 1:0]  = row_s;
                activeBank_x              = bank_s;
                activeRow_x[bankIndex_s]  = row_s;    // store the new active SDRAM row address
                activeFlag_x[bankIndex_s] = 1;        // the SDRAM is now active
                rasTimer_x                = RAS_CYCLES_C;  // minimum time before another precharge can occur 
                timer_x                   = RCD_CYCLES_C;  // minimum time before a read/write operation can occur
                state_x                   = RW; // return to do read/write operation that initiated this activation
                status_o                  = 'b1010;
            end
           //*********************************************************************
           // refresh a row of the SDRAM         
           //*********************************************************************
           REFRESHROW: begin
                cmd_x      = RFSH_CMD_C;
                timer_x    = RFC_CYCLES_C;      // refresh operation interval
                rfshCntr_x = rfshCntr_r - 1;    // decrement the number of needed row refreshes
                state_x    = RW;                // process more SDRAM operations after refresh is done
                status_o   = 'b1011;
            end
           //*********************************************************************
           // place the SDRAM into self-refresh and keep it there until further notice           
           //*********************************************************************
           SELFREFRESH: begin
             if ((doSelfRfsh_s == 1) || (lock_i == 0)) begin
               // keep the SDRAM in self-refresh mode as long as requested and until there is a stable clock
               cmd_x = RFSH_CMD_C;// output the refresh command; this is only needed on the first clock cycle
               cke_x = 0;              // disable the SDRAM clock
             end else begin
              // else exit self-refresh mode and start processing read and write operations
               cke_x        = 1;       // restart the SDRAM clock
               rfshCntr_x   = 0;       // no refreshes are needed immediately after leaving self-refresh
               activeFlag_x = 0;       // self-refresh deactivates all rows
               timer_x      = XSR_CYCLES_C; // wait this long until read and write operations can resume
               state_x      = RW;
             end
             status_o = 'b1100;
            end
           //*********************************************************************
           // unknown state
           //*********************************************************************
           default: begin
             state_x  = INITWAIT;       // reset state if in erroneous state
             status_o = 'b1101;
             end

         endcase
         
      end // else

   end  // always
     
  
   //*********************************************************************
   // update registers on the appropriate clock edge     
   //*********************************************************************

   always @(posedge clk_i or posedge rst_i) begin
      if (rst_i == 1) begin
         // asynchronous reset
         state_r      <= INITWAIT;
         activeFlag_r <= 0;
         rfshCntr_r   <= 0;
         timer_r      <= 0;
         refTimer_r   <= REF_CYCLES_C;
         rasTimer_r   <= 0;
         wrTimer_r    <= 0;
         nopCntr_r    <= 0;
         opBegun_r    <= 0;
         rdPipeline_r <= 0;
         wrPipeline_r <= 0;
         cke_r        <= 0;
         cmd_r        <= NOP_CMD_C;
         ba_r         <= 0;
         sAddr_r      <= 0;
         sData_r      <= 0;
         sDataDir_r   <= INPUT_C;
         sdramData_r  <= 0;
      end else begin
         state_r      <= state_x;
         activeBank_r <= activeBank_x;
         `ifdef   MULTIPLE_ACTIVE_ROWS_D
            activeRow_r[0] = activeRow_x[0];
            activeRow_r[1] = activeRow_x[1];
         `else
            activeRow_r[0] = activeRow_x[0];
         `endif
         activeFlag_r <= activeFlag_x;
         rfshCntr_r   <= rfshCntr_x;
         timer_r      <= timer_x;
         refTimer_r   <= refTimer_x;
         rasTimer_r   <= rasTimer_x;
         wrTimer_r    <= wrTimer_x;
         nopCntr_r    <= nopCntr_x;
         opBegun_r    <= opBegun_x;
         rdPipeline_r <= rdPipeline_x;
         wrPipeline_r <= wrPipeline_x;
         cke_r        <= cke_x;
         cmd_r        <= cmd_x;
         ba_r         <= ba_x;
         sAddr_r      <= sAddr_x;
         sData_r      <= sData_x;
         sDataDir_r   <= sDataDir_x;
         sdramData_r  <= sdramData_x;
      end
   end
   
   // The register that gets data from the SDRAM and holds it for the host
   // is clocked on the opposite edge. We don't use this register if IN_PHASE=TRUE.
   always @(negedge clk_i or posedge rst_i) begin
      if (rst_i == 1) begin
         // asynchronous reset
         sdramDataOppPhase_r <= 0;
      end else begin
         sdramDataOppPhase_r <= sdramDataOppPhase_x;
      end
   end

endmodule