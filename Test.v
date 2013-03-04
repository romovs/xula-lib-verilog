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
////////////////////////////////////////////////////////////////////////////////////////////////////

//##################################################################################################
//
// Test module for HostIo functions and the SDRAM controller.
// 
//##################################################################################################

`timescale 1ns / 1ps


module test (clk_i, sdClk_o, sdClkFb_i, sdRas_bo, sdCas_bo, sdWe_bo, sdBs_o, sdAddr_o, sdData_io);

   localparam  SADDR_WIDTH  = 12;               // SDRAM-side address width.
   localparam  DATA_WIDTH   = 16;               // Host & SDRAM data width.

   input       clk_i;            
   output      sdClk_o;         // SDRAM master clock.
   input       sdClkFb_i;       // Clock feedback from SDRAM.
   output      sdRas_bo;        // SDRAM row address strobe.
   output      sdCas_bo;        // SDRAM column address strobe.
   output      sdWe_bo;         // SDRAM write enable.
   output      sdBs_o;          // SDRAM bank address.
   output      [SADDR_WIDTH-1:0] sdAddr_o;      // SDRAM row/column address.
   inout       [DATA_WIDTH-1:0] sdData_io;      // Data to/from SDRAM.

   wire        drck1; 
   wire        reset; 
   wire        sel1;
   wire        shift;
   wire        tdi;
   wire        tdo1;
   wire        tdo1_1;
   wire        tdo1_2;


   assign sdClk_o = clk_i;
   
   // Instantiate BSCAN primitive
   BSCAN bscan
   (
      .drck1_o(drck1), .reset_o(reset), .sel1_o(sel1), .shift_o(shift), .tdi_o(tdi), .tdo1_i(tdo1)
   );
      
   // SDRAM test   
   testRam #(.SADDR_WIDTH(SADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) test1
   (
      .clk_i(clk_i),
      .drck1_i(drck1), .reset_i(reset), .sel1_i(sel1), .shift_i(shift), .tdi_i(tdi), .tdo1_o(tdo1_1),
      .sdRas_bo(sdRas_bo), 
      .sdCas_bo(sdCas_bo),
      .sdWe_bo(sdWe_bo), 
      .sdBs_o(sdBs_o),   
      .sdAddr_o(sdAddr_o), 
      .sdData_io(sdData_io),
      .sdClkFb_i(sdClkFb_i)
   );

   // counter test
   testCnt test2
   (
      .drck1_i(drck1), .reset_i(reset), .sel1_i(sel1), .shift_i(shift), .tdi_i(tdi), .tdo1_o(tdo1_2)
   );
   
   assign tdo1 = tdo1_1 | tdo1_2;
   
endmodule


//**************************************************************************************************
// Setups SDRAM <-> PC communication. Application on the PC side can perform tests by writing and
// reading back from the SDRAM memory.
//**************************************************************************************************

module testRam (drck1_i, reset_i, sel1_i, shift_i, tdi_i, tdo1_o, clk_i,
               sdRas_bo, sdCas_bo, sdWe_bo, sdBs_o, sdAddr_o, sdData_io, sdClkFb_i);
                        
   parameter  SADDR_WIDTH  = 12;                // SDRAM-side address width.
   parameter  DATA_WIDTH   = 16;                // Host & SDRAM data width.
      
   output      sdRas_bo;                        // SDRAM row address strobe.
   output      sdCas_bo;                        // SDRAM column address strobe.
   output      sdWe_bo;                         // SDRAM write enable.
   output      [1:0] sdBs_o;                    // SDRAM bank address.
   output      [SADDR_WIDTH-1:0] sdAddr_o;      // SDRAM row/column address.
   inout       [DATA_WIDTH-1:0] sdData_io;      // Data to/from SDRAM.
   input       sdClkFb_i;                   
                        
   input       clk_i;
   
   input       drck1_i;
   input       reset_i;
   input       sel1_i;
   input       shift_i;
   input       tdi_i;
   output      tdo1_o;


   wire        wrDone;
   wire        rdDone;
   
   wire        [22:0] sdraddr;
   wire        [15:0] datai;
   wire        [15:0] datao;

   wire        wrJtag;
   wire        rdJtag;
   wire        wrSdram;
   wire        rdSdram;

   wire        rwDone_s;
   wire        rdDone_s;
   wire        wrDone_s;
   
   wire        opBegun_o;
   
   HostIoRam #(.ID(3), .DATA_WIDTH(16), .ADDR_WIDTH(23)) hostioram
   (
            .addr_o(sdraddr),.dataFromHost_o(datai),
            .dataToHost_i(datao), 
            .wr_o(wrJtag), .rd_o(rdJtag), .rwDone_i(rwDone_s),
            .drck1_i(drck1_i), .reset_i(reset_i), .sel1_i(sel1_i), .shift_i(shift_i), .tdi_i(tdi_i), .tdo1_o(tdo1_o)
   );


   RamCtrlSync syncRead
   (
      .drck_i(drck1_i),       // Clock from JTAG domain.
      .clk_i(sdClkFb_i),      // Clock from RAM domain.
      .ctrlIn_i(rdJtag),      // Control signal from JTAG domain.
      .ctrlOut_o(rdSdram),    // Control signal to RAM domain.
      .opBegun_i(opBegun_o),  // R/W operation begun signal from RAM domain.
      .doneIn_i(rdDone),      // R/W operation done signal from RAM domain.
      .doneOut_o(rdDone_s)    // R/W operation done signal to the JTAG domain.
   );

   RamCtrlSync syncWrite
   (
      .drck_i(drck1_i),       // Clock from JTAG domain.
      .clk_i(sdClkFb_i),      // Clock from RAM domain.
      .ctrlIn_i(wrJtag),      // Control signal from JTAG domain.
      .ctrlOut_o(wrSdram),    // Control signal to RAM domain.
      .opBegun_i(opBegun_o),  // R/W operation begun signal from RAM domain.
      .doneIn_i(wrDone),      // R/W operation done signal from RAM domain.
      .doneOut_o(wrDone_s)    // R/W operation done signal to the JTAG domain.
    );
    
    
   assign rwDone_s = rdDone_s | wrDone_s;
    
   SdramCtrl sdram 
   (
      .clk_i(sdClkFb_i),
      .lock_i(1'b1),     
      .rst_i(1'b0),     
      .rd_i(rdSdram),    
      .wr_i(wrSdram),      
      .opBegun_o(opBegun_o),     
      .done_o(wrDone),     
      .rdDone_o(rdDone),
      .addr_i(sdraddr),       
      .data_i(datai),    
      .data_o(datao),       
      .sdRas_bo(sdRas_bo), 
      .sdCas_bo(sdCas_bo),
      .sdWe_bo(sdWe_bo), 
      .sdBs_o(sdBs_o),   
      .sdAddr_o(sdAddr_o), 
      .sdData_io(sdData_io)
    );
   
endmodule

//**************************************************************************************************
// Simple counter for HostIoDut test. Application on the PC side can perform tests by sending 
// a value to DUT (pulsing the counter's clock) and reading back the new counter value.
//**************************************************************************************************

module testCnt (drck1_i, reset_i, sel1_i, shift_i, tdi_i, tdo1_o);

   input       drck1_i;
   input       reset_i;
   input       sel1_i;
   input       shift_i;
   input       tdi_i;
   output      tdo1_o;
   

   reg         [4:0] from = 0;
   (* BUFFER_TYPE="BUFG" *) 
   wire        clkDut;

   HostIODut #(.ID(1), .FROM_DUT_LENGTH(5), .TO_DUT_LENGTH(4)) hostiodut 
   (
      .fromDut_i(from), 
      //.toDut_o(to), 
      .clkDut_o(clkDut),
      .drck1_i(drck1_i), .reset_i(reset_i), .sel1_i(sel1_i), .shift_i(shift_i), .tdi_i(tdi_i), .tdo1_o(tdo1_o)
   );
   

   always @(posedge clkDut)
      from <= from + 1;
   
endmodule
