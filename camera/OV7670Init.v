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
// Register configuration for OV7670 camera module.
//
// Initializes RGB565 VGA, with distorted colors... Image looks almost monochrome. I yet to 
// find the register settings to fix this. 
//
//##################################################################################################

`timescale 1ns / 1ps

module OV7670Init (index_i, data_o);

   input       [6:0] index_i;    // Register index.
   output reg  [16:0] data_o;    // {Register_address, register_value, rw_flag} :
                                 //  Where register_value is the value to write if rw_flag = 1
                                 //  otherwise it's not used when rw_flag = 0 (read).
   always @* begin
      case(index_i)
         //7'd0: data_o = {16'h0A76, 1'b0}; 
         //7'd1: data_o = {16'h1280, 1'b1}; 

         7'd0:  data_o = {8'h3a, 8'h04, 1'b1};  // no automatic window setup after resolution change
         7'd1:  data_o = {8'h40, 8'hd0, 1'b1};  // RGB full value range
         7'd2:  data_o = {8'h12, 8'h04, 1'b1};  // RGB565. 06 enables color bar overlay
         7'd3:  data_o = {8'h32, 8'h80, 1'b1};  // HREF 
         7'd4:  data_o = {8'h17, 8'h16, 1'b1};  // HSTART
         7'd5:  data_o = {8'h18, 8'h04, 1'b1};  // HSTOP
         7'd6:  data_o = {8'h19, 8'h03, 1'b1};  // VSTRT
         7'd7:  data_o = {8'h1a, 8'h7b, 1'b1};  // VSTOP
         7'd8:  data_o = {8'h03, 8'h00, 1'b1};  // VREF
         7'd9:  data_o = {8'h0c, 8'h00, 1'b1};  // DCW disable
         7'd10: data_o = {8'h3e, 8'h00, 1'b1};  // No clock divider, no scalling
         7'd11: data_o = {8'h70, 8'h00, 1'b1};
         7'd12: data_o = {8'h71, 8'h00, 1'b1};
         7'd13: data_o = {8'h72, 8'h11, 1'b1};  // DCW Control.  Hor/Vertical downsample by 2. Not relevant for RGB?
         7'd14: data_o = {8'h73, 8'hf8, 1'b1};  
         7'd15: data_o = {8'ha2, 8'h02, 1'b1};  
         7'd16: data_o = {8'h7a, 8'h20, 1'b1};  // Gamma curve
         7'd17: data_o = {8'h7b, 8'h1c, 1'b1};
         7'd18: data_o = {8'h7c, 8'h28, 1'b1};
         7'd19: data_o = {8'h7d, 8'h3c, 1'b1};
         7'd20: data_o = {8'h7e, 8'h55, 1'b1};
         7'd21: data_o = {8'h7f, 8'h68, 1'b1};
         7'd22: data_o = {8'h80, 8'h76, 1'b1};
         7'd23: data_o = {8'h81, 8'h80, 1'b1};
         7'd24: data_o = {8'h82, 8'h88, 1'b1};
         7'd25: data_o = {8'h83, 8'h8f, 1'b1};
         7'd26: data_o = {8'h84, 8'h96, 1'b1};
         7'd27: data_o = {8'h85, 8'ha3, 1'b1};
         7'd28: data_o = {8'h86, 8'haf, 1'b1};
         7'd29: data_o = {8'h87, 8'hc4, 1'b1};
         7'd30: data_o = {8'h88, 8'hd7, 1'b1};
         7'd31: data_o = {8'h89, 8'he8, 1'b1};
         7'd32: data_o = {8'h13, 8'ha0, 1'b1}; 
         7'd33: data_o = {8'h00, 8'h00, 1'b1};  // AGC - Gain control
         7'd34: data_o = {8'h10, 8'h00, 1'b1};  // Exposure Value
         7'd35: data_o = {8'h0d, 8'h00, 1'b1};
         7'd36: data_o = {8'h14, 8'he8, 1'b1};  // Limit the max gain. 
         7'd37: data_o = {8'ha5, 8'h05, 1'b1};  // 50Hz Banding Step Limit
         7'd38: data_o = {8'hab, 8'h07, 1'b1};  // 60Hz Banding Step Limit
         7'd39: data_o = {8'h24, 8'h65, 1'b1};  // AGC/AEC - Stable Operating Region (Upper Limit)
         7'd40: data_o = {8'h25, 8'h33, 1'b1};  // AGC/AEC - Stable Operating Region (Lower rLimit)
         7'd41: data_o = {8'h26, 8'he3, 1'b1};  // AGC/AEC Fast Mode Operating Region
         7'd42: data_o = {8'h9f, 8'h78, 1'b1};  // Histogram-based AEC/AGC Control 1
         7'd43: data_o = {8'ha0, 8'h68, 1'b1};  // Histogram-based AEC/AGC Control 2
         7'd44: data_o = {8'ha1, 8'h03, 1'b1};
         7'd45: data_o = {8'ha6, 8'hdf, 1'b1};  // Histogram-based AEC/AGC Control 3
         7'd46: data_o = {8'ha7, 8'hdf, 1'b1};  // Histogram-based AEC/AGC Control 4
         7'd47: data_o = {8'ha8, 8'hf0, 1'b1};  // Histogram-based AEC/AGC Control 5
         7'd48: data_o = {8'ha9, 8'h90, 1'b1};  // Histogram-based AEC/AGC Control 6
         7'd49: data_o = {8'haa, 8'h94, 1'b1};  // Histogram-based AEC algorithm
         7'd50: data_o = {8'h13, 8'he5, 1'b1};
         7'd51: data_o = {8'h0f, 8'h4b, 1'b1};
         7'd52: data_o = {8'h29, 8'h07, 1'b1}; 
         7'd53: data_o = {8'h33, 8'h0b, 1'b1};
         7'd54: data_o = {8'h35, 8'h0b, 1'b1};
         7'd55: data_o = {8'h37, 8'h1d, 1'b1};  // ADC Control 
         7'd56: data_o = {8'h38, 8'h71, 1'b1};  // ADC Control
         7'd57: data_o = {8'h39, 8'h0c, 1'b1};  // ADC Control
         7'd58: data_o = {8'h3c, 8'h78, 1'b1};  // Always HREF even when no VSYNC.
         7'd59: data_o = {8'h4d, 8'h40, 1'b1}; 
         7'd60: data_o = {8'h4e, 8'h20, 1'b1};
         7'd61: data_o = {8'h69, 8'h00, 1'b1};  // Gain Control
         7'd62: data_o = {8'h6b, 8'h0a, 1'b1};
         7'd63: data_o = {8'h74, 8'h19, 1'b1};
         7'd64: data_o = {8'h9a, 8'h80, 1'b1};
         7'd65: data_o = {8'hb1, 8'h0c, 1'b1};  // Enable ABLC function, overrides def bits
         7'd66: data_o = {8'hb3, 8'h82, 1'b1};  // ABLC Target
         7'd67: data_o = {8'h59, 8'h88, 1'b1};  // AWB Control
         7'd68: data_o = {8'h5a, 8'h88, 1'b1};
         7'd69: data_o = {8'h5b, 8'h44, 1'b1};
         7'd70: data_o = {8'h5c, 8'h67, 1'b1};
         7'd71: data_o = {8'h5d, 8'h49, 1'b1};
         7'd72: data_o = {8'h5e, 8'h0e, 1'b1};
         7'd73: data_o = {8'h6c, 8'h0a, 1'b1};  // AWB Control 3
         7'd74: data_o = {8'h6d, 8'h55, 1'b1};
         7'd75: data_o = {8'h6e, 8'h11, 1'b1};
         7'd76: data_o = {8'h6f, 8'h9f, 1'b1};
         7'd77: data_o = {8'h6a, 8'h40, 1'b1};  // G Channel AWB Gain
         7'd78: data_o = {8'h01, 8'h40, 1'b1};  // AWB - Blue channel gain setting
         7'd79: data_o = {8'h02, 8'h40, 1'b1};  // AWB - red channel gain setting
         7'd80: data_o = {8'h13, 8'he7, 1'b1};
         7'd81: data_o = {8'h4f, 8'h80, 1'b1};  // Matrix Coefficient 1
         7'd82: data_o = {8'h50, 8'h80, 1'b1};
         7'd83: data_o = {8'h51, 8'h00, 1'b1};
         7'd84: data_o = {8'h52, 8'h22, 1'b1};
         7'd85: data_o = {8'h53, 8'h5e, 1'b1};
         7'd86: data_o = {8'h54, 8'h80, 1'b1};
         7'd87: data_o = {8'h58, 8'h9e, 1'b1};
         7'd88: data_o = {8'h3f, 8'h00, 1'b1};  // Edge Enhancement Adjustment
         7'd89: data_o = {8'h75, 8'h05, 1'b1};  // Edge enhancement lower limit - default 0f
         7'd90: data_o = {8'h76, 8'he1, 1'b1};  // White/Black pixel correction enable.
         7'd91: data_o = {8'h4c, 8'h00, 1'b1};  // De-noise Strength
         7'd92: data_o = {8'h77, 8'h01, 1'b1};  // De-noise offset 
         7'd93: data_o = {8'h3d, 8'hc2, 1'b1};
         7'd94: data_o = {8'h4b, 8'h09, 1'b1};  // UV average enable.
         7'd95: data_o = {8'hc9, 8'h60, 1'b1};  // Saturation Control
         7'd96: data_o = {8'h41, 8'h38, 1'b1};  // AWB gain enable + De-noise threshold auto-adjustment
         7'd97: data_o = {8'h56, 8'h50, 1'b1};  // Contrast Control. was 45
         7'd98: data_o = {8'h3b, 8'h02, 1'b1};  // Exposure timing can be less than limit of banding filter
         7'd99: data_o = {8'ha4, 8'h89, 1'b1};  // Frame rate control
         7'd100: data_o = {8'h9d, 8'h4c, 1'b1}; // 50 Hz Banding Filter Value
         7'd101: data_o = {8'h9e, 8'h3f, 1'b1}; // 60 Hz Banding Filter Value
         default:data_o = {16'hffff, 1'b1};
      endcase
   end

endmodule
