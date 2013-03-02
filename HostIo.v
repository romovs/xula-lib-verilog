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


//**************************************************************************************************
// Modules for passing bits back and forth from the host PC
// to FPGA application logic through the JTAG port.
//**************************************************************************************************

`timescale 1ns / 1ps

//**************************************************************************************************
// Convenience wrapper for the BSCAN primitive
//**************************************************************************************************
module BSCAN (drck1_o, reset_o, sel1_o, shift_o, tdi_o, tdo1_i);

   output      drck1_o;
   output      reset_o;
   output      sel1_o;
   output      shift_o;
   output      tdi_o;
   input       tdo1_i;
   
   BSCAN_SPARTAN3A BSCAN_SPARTAN3A_inst 
   (
      .DRCK1(drck1_o),  // Data register output for USER1 functions
      .RESET(reset_o),  // Reset output from TAP controller
      .SEL1(sel1_o),    // USER1 active output
      .SHIFT(shift_o),  // SHIFT output from TAP controller
      .TDI(tdi_o),      // TDI output from TAP controller
      .TDO1(tdo1_i),    // Data input for USER1 function
      .TDO2(1'b0)
   );

endmodule


//**************************************************************************************************
// This module sends/receives test vectors to/from a device-under-test (DUT).
//
// Write operations:
// Once ID and number of payload bits extracted,
// a write operation is activated by the opcode in the first two bits in the payload.
// This module then extracts a starting address from the payload bitstream.
// Then this module extracts data words from the payload bitstream and writes them to
// the memory device at sequentially increasing addresses beginning from that address.
//
//       |     Header reception     |                    Payload bits                        |
// TDI:  |  ID  | # of payload bits | Opcode | Starting address |  Data1  | ........ | DataN |
// TDO:  |xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx|
// Addr: |xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx|   Addr   | ..... | Addr + N - 1 |
// Data: |xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx|   Data1  | ..... | DataN        |
//
// Read operations:
// Once ID and number of payload bits extracted,
// a read operation is activated by the opcode in the first two bits in the payload.
// This module then extracts a starting address from the payload bitstream.
// Then this module reads data from the memory device at sequentially increasing addresses
// starting from that address, and it shifts them serially back to the host.
//
//       |     Header reception     |        Payload bits       |  RAM data goes back to host  |
// TDI:  |  ID  | # of payload bits | Opcode | Starting address |xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx|
// TDO:  |xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx|  Data1  | ... | DataN        |
// Addr: |xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx|  Addr   | ... | Addr + N - 1 |
// Data: |xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx|  Data1  | ... | DataN        |
//
// Parameter query operation:
// Once ID and number of payload bits extracted,
// a parameter query operation is activated by the opcode in the first two bits in the payload.
// This module then places the width of the memory address and data buses into a register
// and shifts it serially back to the host.
//
//       |     Header reception     | Payload bits |  Parameter data goes back to host  |
// TDI:  |  ID  | # of payload bits |    Opcode    |xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx|
// TDO:  |xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx|   Address width   |   Data width   |
// Addr: |xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx|
// Data: |xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx|
//**************************************************************************************************

module HostIODut (fromDut_i, toDut_o, clkDut_o, drck1_i, reset_i, sel1_i, shift_i, tdi_i, tdo1_o);

   parameter   [7:0] ID = 'b11111111;
   parameter   [7:0] FROM_DUT_LENGTH = 24;
   parameter   [7:0] TO_DUT_LENGTH = 24;
   
   input wire  [FROM_DUT_LENGTH-1:0] fromDut_i; // Gather inputs to send back to host thru this bus.
   output reg  [TO_DUT_LENGTH-1:0] toDut_o;     // Output test vector from the host to DUT thru this bus.
   output wire clkDut_o;                        // Rising edge clock signals arrival of vector to DUT.
   input wire  drck1_i;                         // Bit clock. TDI clocked in on rising edge, TDO sampled on falling edge.
   input wire  reset_i;                         // Active-high reset signal.
   input wire  sel1_i;                          // USER1 instruction enables user-I/O.
   input wire  shift_i;                         // True when USER JTAG instruction is active and the TAP FSM is in the Shift-D
   input wire  tdi_i;                           // Bit from the host to the DUT.
   output wire tdo1_o;                          // Bit from the DUT to the host.
                       

   localparam  OPCODE_SIZE    = 'b01;
   localparam  OPCODE_WRITE = 'b10;
   localparam  OPCODE_READ    = 'b11;

   localparam  PARAM_SIZE = 16;

   localparam  MAX_VECT_WIDTH = TO_DUT_LENGTH > FROM_DUT_LENGTH ? TO_DUT_LENGTH : FROM_DUT_LENGTH;
   localparam  SHIFT_REG_SIZE = MAX_VECT_WIDTH > PARAM_SIZE ? MAX_VECT_WIDTH : PARAM_SIZE;

   wire        inShiftDR;

   reg         [SHIFT_REG_SIZE-1:0] shiftReg;

   reg         activateClk;

   reg         [7:0] id;
   reg         [31:0] payloadCount;
   reg         headerReceived;
   
   wire        moduleActive;
   
   reg         [2:0] opcode;
   reg         opcodeReceived;
   reg         [15:0] bitCounter;

   assign inShiftDR = (reset_i == 0 && shift_i == 1 && sel1_i == 1);
   
   
   always @(posedge drck1_i) begin

      // Reset state if exited SHIFT-DR state or instruction has been fully received
      if (inShiftDR == 0 || (headerReceived == 1 && payloadCount == 1))  begin
         id <= 0;
         payloadCount[30:0] <= 0;
         payloadCount[31] <= 1;             // Signals end of receiving 32+8 bits.
         headerReceived <= 0;
      end
      else begin
         // Receive ID and Payload size (by shifting through payload counter -> id)
         if (headerReceived == 0) begin
               headerReceived <= id[0];   // This will signal end once we get 1 set in payloadCount[31] above
               id <= id >> 1;
               id[7] <= payloadCount[0];
               payloadCount <= payloadCount >> 1;
               payloadCount[31] <= tdi_i;
         end else begin                     // Once header is received decrement payload counter
            payloadCount <= payloadCount - 1;
         end
      end
      
      if (moduleActive == 1 && reset_i == 0) begin
         // Receive two-bit opcode
         if (opcodeReceived == 0) begin
            opcodeReceived <= opcode[0];
            opcode <= opcode >> 1;
            opcode[1] <= tdi_i;
         end else begin

            case(opcode)
               OPCODE_SIZE : begin
                  if (bitCounter == 0) begin
                     bitCounter <= PARAM_SIZE;  // Set the number of bits to send.
                     shiftReg[PARAM_SIZE-1:0] <= {FROM_DUT_LENGTH[7:0], TO_DUT_LENGTH[7:0]};
                  end else begin // Shift next bit of I/O parameters to the host.
                     shiftReg <= shiftReg >> 1;
                     bitCounter <= bitCounter - 1; // One more bit has been sent to the host.
                  end
               end
               
               OPCODE_WRITE : begin
                  if (TO_DUT_LENGTH == 1) begin
                     toDut_o <= tdi_i;
                     activateClk <= 1;
                  end
                  else begin
                     if (shiftReg[0] == 0) begin
                        shiftReg <= shiftReg >> 1;
                        shiftReg[TO_DUT_LENGTH-1] <= tdi_i;
                     end
                     else begin
                        toDut_o <= shiftReg[TO_DUT_LENGTH-1:0];
                        activateClk <= 1;
                        shiftReg <= 0;
                        shiftReg[TO_DUT_LENGTH-1] <= 1;
                     end
                  end
               end
               
               OPCODE_READ:begin
                  if (bitCounter == 0) begin   
                     bitCounter <= FROM_DUT_LENGTH;  // Set the number of bits to send.
                     shiftReg[FROM_DUT_LENGTH-1:0] <= fromDut_i;
                  end else begin // Shift next bit of I/O parameters to the host.
                     shiftReg <= shiftReg >> 1;
                     bitCounter <= bitCounter - 1; // One more bit has been sent to the host.
                  end
               end
            endcase
        
        end
      
      end else begin       // Reset everything when this module is not selected or is reset.
        opcode <= 2'b10;   // 1 at MSB used to signal end of opcode receival
        opcodeReceived <= 0;
        shiftReg <= 0;
        if (TO_DUT_LENGTH > 1) begin
            shiftReg[TO_DUT_LENGTH-1] <= 1;
        end
        bitCounter <= 0;
        activateClk <= 0;
      end
   
   end
   
   assign clkDut_o = activateClk == 1 ? !drck1_i : 0;
   assign tdo1_o = (moduleActive == 1) ? shiftReg[0] : 0;
   assign moduleActive = (id == ID && headerReceived == 1) ? 1 : 0;

endmodule


//**************************************************************************************************
// Synchronizes a HostIoRam read or write control signal to the clock domain of the memory device.
//**************************************************************************************************

module RamCtrlSync (drck_i, clk_i, ctrlIn_i, ctrlOut_o, opBegun_i, doneIn_i, doneOut_o);

   input       drck_i;           // Clock from JTAG domain.
   input       clk_i;            // Clock from RAM domain.
   input       ctrlIn_i;         // Control signal from JTAG domain.
   output reg  ctrlOut_o;        // Control signal to RAM domain.
   input       opBegun_i;        // R/W operation begun signal from RAM domain.
   input       doneIn_i;         // R/W operation done signal from RAM domain.
   output reg  doneOut_o;        // R/W operation done signal to the JTAG domain.
   wire        ctrlIn_s;         // JTAG domain control signal sync'ed to RAM domain.
   
   // Sync the RAM control signal from the JTAG clock domain to the RAM domain.
   SyncToClock sync
   (
      .clk_i(clk_i), 
      .unsynced_i(ctrlIn_i), 
      .synced_o(ctrlIn_s)
   );

   // Now raise-and-hold the output control signal to the RAM upon a rising edge of the input control signal.
   // Lower the output control signal if the input control signal goes low or if the RAM signals that the
   // operation has begun or has finished.
  
   reg prevCtrlIn_v = 1;
  
   always @(posedge clk_i) begin
      if (ctrlIn_s == 0) begin
         // Lower the RAM control signal if the input signal has been deactivated.
         ctrlOut_o <= 0;
      end else if (prevCtrlIn_v == 0) begin
         // Raise the RAM control signal upon a rising edge of the input control signal.
         ctrlOut_o <= 1;
      end else if (opBegun_i == 1 || doneIn_i == 1) begin
         // Lower the RAM control signal once the RAM has begun or completed the R/W operation.
         ctrlOut_o <= 0;
      end
      prevCtrlIn_v = ctrlIn_s; // Store the previous value of the input control signal.
   end
  
   // Inform the HostIoToRamCore when the memory operation is done. Latch the done signal
   // from the RAM until the HostIoToRamCore sees it and lowers its control signal.
   // Once the control signal is lowered, the RAM will eventually lower its done signal.
   always @(posedge clk_i) begin
      if (ctrlIn_s == 0) begin
         doneOut_o <= 0;
      end else if (doneIn_i == 1) begin
         doneOut_o <= 1;
      end
   end
endmodule


//**************************************************************************************************
// Clock domain crossing
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


//**************************************************************************************************
// This module performs read/write operations to memory devices.
//
// Write operations:
// Once ID and number of payload bits extracted,
// a write operation is activated by the opcode in the first two bits in the payload.
// This module then extracts a starting address from the payload bitstream.
// Then this module extracts data words from the payload bitstream and writes them to
// the memory device at sequentially increasing addresses beginning from that address.
//
//       |     Header reception     |                    Payload bits                        |
// TDI:  |  ID  | # of payload bits | Opcode | Starting address |  Data1  | ........ | DataN |
// TDO:  |xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx|
// Addr: |xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx|   Addr   | ..... | Addr + N - 1 |
// Data: |xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx|   Data1  | ..... | DataN        |
//
// Read operations:
// Once ID and number of payload bits extracted,
// a read operation is activated by the opcode in the first two bits in the payload.
// This module then extracts a starting address from the payload bitstream.
// Then this module reads data from the memory device at sequentially increasing addresses
// starting from that address, and it shifts them serially back to the host.
//
//       |     Header reception     |        Payload bits       |  RAM data goes back to host  |
// TDI:  |  ID  | # of payload bits | Opcode | Starting address |xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx|
// TDO:  |xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx|  Data1  | ... | DataN        |
// Addr: |xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx|  Addr   | ... | Addr + N - 1 |
// Data: |xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx|  Data1  | ... | DataN        |
//
// Parameter query operation:
// Once ID and number of payload bits extracted,
// a parameter query operation is activated by the opcode in the first two bits in the payload.
// This module then places the width of the memory address and data buses into a register
// and shifts it serially back to the host.
//
//       |     Header reception     | Payload bits |  Parameter data goes back to host  |
// TDI:  |  ID  | # of payload bits |    Opcode    |xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx|
// TDO:  |xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx|   Address width   |   Data width   |
// Addr: |xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx|
// Data: |xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx|
//**************************************************************************************************
module HostIoRam (addr_o, dataFromHost_o, dataToHost_i, wr_o, rd_o, rwDone_i, drck1_i, reset_i, sel1_i, shift_i, tdi_i, tdo1_o);
                  
                  
   parameter   [7:0] ID = 'b11111111;
   parameter   [7:0] DATA_WIDTH = 16;
   parameter   [7:0] ADDR_WIDTH = 16;

   output wire [ADDR_WIDTH-1:0] addr_o;
   output reg  [DATA_WIDTH-1:0] dataFromHost_o;
   input wire  [DATA_WIDTH-1:0] dataToHost_i;
   output wire wr_o;
   output wire rd_o;
   input wire  rwDone_i;
   input wire  drck1_i;
   input wire  reset_i;
   input wire  sel1_i;
   input wire  shift_i;
   input wire  tdi_i;
   output wire tdo1_o;     

   localparam  PARAM_SIZE = 16;

   localparam  OPCODE_SIZE    = 'b01;
   localparam  OPCODE_WRITE = 'b10;
   localparam  OPCODE_READ    = 'b11;
   
   localparam  SHIFT_REG_SIZE = PARAM_SIZE > DATA_WIDTH ? PARAM_SIZE : DATA_WIDTH;

   reg         [ADDR_WIDTH-1:0] addrFromHost = 0;
   reg         addrFromHostReceived;
   reg         dataFromMemReceived;
   reg         [DATA_WIDTH-1:0] dataFromMem;
   reg         readFromMem = 0;
   reg         writeToMem = 0;
   
   wire        inShiftDR;

   reg [SHIFT_REG_SIZE-1:0] shiftReg;

   reg         [7:0] id;
   reg         [31:0] payloadCount;
   reg         headerReceived;
   
   wire        moduleActive;
   
   reg         [2:0] opcode;
   reg         opcodeReceived;
   reg         [15:0] bitCounter;

   assign inShiftDR = (reset_i == 0 && shift_i == 1 && sel1_i == 1);
   
   
   always @(posedge drck1_i) begin

      // Reset state if exited SHIFT-DR state or instruction has been fully received
      if (inShiftDR == 0 || (headerReceived == 1 && payloadCount == 1))  begin
         id <= 0;
         payloadCount[30:0] <= 0;
         payloadCount[31] <= 1;           // signals end of receiving 32+8 bits.
         headerReceived <= 0;
      end
      else begin
         // Receive ID and Payload size (by shifting through payload counter -> id)
         if (headerReceived == 0) begin
               headerReceived <= id[0];   // This will signal end once we get 1 set in payloadCount[31] above
               id <= id >> 1;
               id[7] <= payloadCount[0];
               payloadCount <= payloadCount >> 1;
               payloadCount[31] <= tdi_i;
         end else begin                   // Once header is received decrement payload counter
            payloadCount <= payloadCount - 1;
         end
      end
      
      if ((moduleActive == 1 || writeToMem == 1) && reset_i == 0 ) begin
         // receive two-bit opcode
         if (opcodeReceived == 0) begin
            opcodeReceived <= opcode[0];
            opcode <= opcode >> 1;
            opcode[1] <= tdi_i;
         end else begin

            case(opcode)
      
               OPCODE_SIZE : begin
                  if (bitCounter == 0) begin
                     bitCounter <= PARAM_SIZE;  
                     shiftReg[PARAM_SIZE-1:0] <= {DATA_WIDTH[PARAM_SIZE/2-1:0], ADDR_WIDTH[PARAM_SIZE/2-1:0]};
                  end else begin 
                     shiftReg <= shiftReg >> 1;
                     bitCounter <= bitCounter - 1;
                  end
               end
               
               OPCODE_WRITE : begin
                  if (addrFromHostReceived == 0) begin
                     // get address
                     addrFromHostReceived <= addrFromHost[0];
                     addrFromHost <= addrFromHost >> 1;
                     addrFromHost[ADDR_WIDTH-1] <= tdi_i;
                  end
                  else begin
                     // get data
                     if (shiftReg[0] == 0) begin
                        shiftReg <= shiftReg >> 1;
                        shiftReg[DATA_WIDTH-1] <= tdi_i; 
                     end else begin
                     // write data memory
                        dataFromHost_o[DATA_WIDTH-1:0] <= {tdi_i, shiftReg[DATA_WIDTH-1:1] }; 
                        shiftReg <= 0;
                        shiftReg[DATA_WIDTH-1] <= 1;
                        writeToMem <= 1;
                     end
                     
                     if (writeToMem == 1 && rwDone_i == 1) begin
                        writeToMem <= 0;// Stop any further writes till another complete data word arrives from host.
                        addrFromHost <= addrFromHost + 1;  // Point to next memory location to be written.
                     end
                  end

               end
               
               OPCODE_READ:begin
               
                  if (addrFromHostReceived == 0) begin
                     // get address
                     readFromMem <= addrFromHost[0];// Initiate read as soon as address is received
                     addrFromHostReceived <= addrFromHost[0];
                     addrFromHost <= addrFromHost >> 1;
                     addrFromHost[ADDR_WIDTH-1] <= tdi_i;
                     
                     bitCounter <= DATA_WIDTH-1;// Output garbage word until 1st read has a chance to complete.
                  end else begin
                     if (dataFromMemReceived == 0) begin
                     // Receive a complete data word from the host.
                     
                        if (readFromMem == 1 && rwDone_i == 1) begin // Keep checking to see when memory data arrives.
                           readFromMem <= 0; // stop reading the mem
                           dataFromMem <= dataToHost_i; 
                           dataFromMemReceived <= 1;
                           addrFromHost <= addrFromHost + 1;  // Point to next memory location to read from.
                        end else if (payloadCount >= SHIFT_REG_SIZE) begin
                           readFromMem <= 1;// Initiate the next read unless the host shift reg already contains the final data read.
                        end
                     
                     end
                     
                     if (bitCounter != 0) begin// Shift data from memory to the host.
                        shiftReg <= shiftReg >> 1;
                        bitCounter <= bitCounter - 1;
                     end else begin // load data from memory into shift register (whether it's ready or not).
                        shiftReg <= dataFromMem; // Load the new data into the host shift register.
                        bitCounter <= DATA_WIDTH-1;
                        dataFromMemReceived <= 0;
                     end
                  end
            
               end
            endcase
        
        end
      
      end else begin // Reset everything when this module is not selected or is reset.
        opcode <= 2'b10;   // 1 at MSB used to signal end of opcode receival
        opcodeReceived <= 0;
        shiftReg <= 0;
        shiftReg[DATA_WIDTH-1] <= 1;
        bitCounter <= 0;

        addrFromHost <= 0;
        addrFromHost[ADDR_WIDTH-1] <= 1;
        addrFromHostReceived <= 0;
        
        writeToMem             <= 0;
        readFromMem            <= 0;
        dataFromMemReceived    <= 0;
        
      end
   
   end
   
   assign wr_o = writeToMem;
   assign rd_o = readFromMem;
   assign addr_o = addrFromHost;
   
   assign tdo1_o = (moduleActive == 1) ? shiftReg[0] : 0;
   
   assign moduleActive = (id == ID && headerReceived == 1) ? 1 : 0;

endmodule
