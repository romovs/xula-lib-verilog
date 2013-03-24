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
// Module for receiving RGB565 pixel data from OV camera.
//
//##################################################################################################

module RGB656Receive (d_i, vsync_i, href_i, pclk_i, rst_i, pixelReady_o, pixel_o);
                     
   input       [7:0] d_i;        // D0 - D7
   input       vsync_i;          // VSYNC
   input       href_i;           // HREF
   input       pclk_i;           // PCLK
   input       rst_i;            // 0 - Reset.
   output reg  pixelReady_o;     // Indicates that a pixel has been received.
   output reg  [15:0] pixel_o;   // RGB565 pixel.
   
   
   reg         odd = 0;
   reg         frameValid = 0;

   always @(posedge pclk_i) begin
      pixelReady_o <= 0;
      if (rst_i == 0) begin
         odd <= 0;
         frameValid <= 0;
      end else begin
         if (frameValid == 1 && vsync_i == 0 && href_i == 1) begin
            if (odd == 0) begin    
               pixel_o[7:0] <= d_i;
            end else begin
               pixel_o[15:8] <= d_i;
               pixelReady_o <= 1;   
            end
            odd <= ~odd;
         // skip inital frame in case we started receiving in the middle of it
         end else if (frameValid == 0 && vsync_i == 1) begin
            frameValid <= 1;            
         end
      end
   end
   
endmodule
