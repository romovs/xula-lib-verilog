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
// Helper modules for working with clock signals.
//
//##################################################################################################

`timescale 1ns / 1ps


//**************************************************************************************************
//
// Generates clock frequency. By default 100MHz from 12MHz clock signal is generated.
//
//**************************************************************************************************

module ClkGen (clk_i, clk_o, clk180_o);

   parameter   MUL = 25;
   parameter   DIV = 3;
   parameter   real IN_FREQ = 12.0;

   input       clk_i;
   output      clk_o;
   output      clk180_o;
   
   
   localparam  real CLK_PERIOD = 1000.0/IN_FREQ;
   
   DCM_SP 
   #(
      .CLKDV_DIVIDE(2.0), // Divide by: 1.5,2.0,2.5,3.0,3.5,4.0,4.5,5.0,5.5,6.0,6.5
                          //   7.0,7.5,8.0,9.0,10.0,11.0,12.0,13.0,14.0,15.0 or 16.0
      .CLKFX_DIVIDE(DIV),   // Can be any integer from 1 to 32
      .CLKFX_MULTIPLY(MUL), // Can be any integer from 2 to 32
      .CLKIN_DIVIDE_BY_2("FALSE"), // TRUE/FALSE to enable CLKIN divide by two feature
      .CLKIN_PERIOD(CLK_PERIOD),  // Specify period of input clock
      .CLKOUT_PHASE_SHIFT("NONE"), // Specify phase shift of NONE, FIXED or VARIABLE
      .CLK_FEEDBACK("1X"),  // Specify clock feedback of NONE, 1X or 2X
      .DESKEW_ADJUST("SYSTEM_SYNCHRONOUS"), // SOURCE_SYNCHRONOUS, SYSTEM_SYNCHRONOUS or
                                            //   an integer from 0 to 15
      .DLL_FREQUENCY_MODE("LOW"),  // HIGH or LOW frequency mode for DLL
      .DUTY_CYCLE_CORRECTION("TRUE"), // Duty cycle correction, TRUE or FALSE
      .PHASE_SHIFT(0),     // Amount of fixed phase shift from -255 to 255
      .STARTUP_WAIT("FALSE")   // Delay configuration DONE until DCM LOCK, TRUE/FALSE
   ) 
   DCM_SP_inst 
   (
      .CLKFX(clk_o),       // DCM CLK synthesis out (M/D)
      .CLKFX180(clk180_o), // 180 degree CLK synthesis out
      .CLKIN(clk_i),   // Clock input (from IBUFG, BUFG or DCM)
      .RST(1'b0)        // DCM asynchronous reset input
   );

endmodule


//**************************************************************************************************
// Convenience module for forwarding low skew copy of an internal clock to output pins.
// Useful when working with high frequencies.
//
// For a detailed explanation see Xilinx ug331.pdf p.116 Figures 3-28, 3-29. 
//**************************************************************************************************

module ClkToPin (clk_i, clk180_i, clk_o);

   input       clk_i;
   input       clk180_i;
   output      clk_o;

   ODDR2 
   #(
      .DDR_ALIGNMENT("NONE"), // Sets output alignment to "NONE", "C0" or "C1" 
      .INIT(1'b0),    // Sets initial state of the Q output to 1'b0 or 1'b1
      .SRTYPE("SYNC") // Specifies "SYNC" or "ASYNC" set/reset
   ) 
   ODDR2_inst 
   (
      .Q(clk_o),     // 1-bit DDR output data
      .C0(clk_i),    // 1-bit clock input
      .C1(clk180_i), // 1-bit clock input
      .CE(1'b1),     // 1-bit clock enable input
      .D0(1'b1),     // 1-bit data input (associated with C0)
      .D1(1'b0),     // 1-bit data input (associated with C1)
      .R(1'b0),      // 1-bit reset input
      .S(1'b0)       // 1-bit set input
   );

endmodule


//**************************************************************************************************
// n-stage synchronizer
//**************************************************************************************************

module SyncToClock (clk_i, unsynced_i, synced_o);

   parameter   syncStages = 2;   //number of stages in syncing register

   input       clk_i;
   input       unsynced_i;
   output      synced_o;
   
   reg         [syncStages:1] sync_r;

   always @(posedge clk_i)
      sync_r <= {sync_r[syncStages-1:1], unsynced_i};

   assign synced_o = sync_r[syncStages];
   
endmodule
