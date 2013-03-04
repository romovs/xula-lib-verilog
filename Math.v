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
// Collection of helper math functions.
// 
//##################################################################################################



//**************************************************************************************************
// Returns ceil(log-base-2()).
//**************************************************************************************************

function integer clog2;
   input integer value;
   
   begin  
      value = value-1;
      for (clog2=0; value>0; clog2=clog2+1)
         value = value>>1;
   end  
   
endfunction
   

//**************************************************************************************************
// Returns the smallest integral value greater than or equal to input value. 
//**************************************************************************************************

function integer ceil;
   input real value;
   
   real val1;

   begin  
      val1 = value;

      if ( value > 1.0) begin
         while (val1 >= 1.0) begin
            val1 = val1 - 1.0;
         end 
         
         if (val1 > 0.0)
            ceil = value + 1.0;
         else
            ceil = value;
      end else if (value > 0.0) begin
         ceil = 1;
      end else begin
         ceil = 0;
      end

   end
   
endfunction

//**************************************************************************************************
// Returns 1 if input value is zero. Original value returned otherwise.
// This function is used as a convenience method for compensating possible precision loss durring
// division in localparam expressions.
//**************************************************************************************************

function integer pfx;
   input integer value;
   
   begin  
      pfx = (value == 0 ? 1 : value); 
   end
   
endfunction
