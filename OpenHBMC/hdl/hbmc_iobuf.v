/* 
 * ----------------------------------------------------------------------------
 *  Project:  OpenHBMC
 *  Filename: hbmc_iobuf.v
 *  Purpose:  HyperBus I/O logic.
 * ----------------------------------------------------------------------------
 *  Copyright © 2020-2022, Vaagn Oganesyan <ovgn@protonmail.com>
 *  
 *  Licensed under the Apache License, Version 2.0 (the "License");
 *  you may not use this file except in compliance with the License.
 *  You may obtain a copy of the License at
 *  
 *      http://www.apache.org/licenses/LICENSE-2.0
 *  
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 * ----------------------------------------------------------------------------
 */

 
`default_nettype none
`timescale 1ps / 1ps


module hbmc_iobuf #
(
    parameter   integer DRIVE_STRENGTH          = 8,
    parameter           SLEW_RATE               = "SLOW",
    parameter   integer USE_IDELAY_PRIMITIVE    = 0,
    parameter   real    IODELAY_REFCLK_MHZ      = 200.0,
    parameter           IODELAY_GROUP_ID        = "HBMC",
    parameter   [4:0]   IDELAY_TAPS_VALUE       = 0
)
(
    input   wire            arst,
    input   wire            oddr_clk,
    input   wire            iserdes_clk,
    input   wire            iserdes_clkdiv,
    input   wire            idelay_clk,
    
    inout   wire            buf_io,
    input   wire            buf_t,
    input   wire    [1:0]   sdr_i,
    output  reg     [5:0]   iserdes_o,
    output  wire            iserdes_comb_o
);
    
    wire            buf_o;
    wire            buf_i;
    wire            tristate;
    wire            idelay_o;
    wire            iserdes_data_in;
    wire    [5:0]   iserdes_q;
    wire    [7:0]   iserdes_q_ext;
    
    
/*----------------------------------------------------------------------------------------------------------------------------*/
    
    IOBUF #
    (
        .DRIVE  ( DRIVE_STRENGTH ),     // Specify the output drive strength
        .SLEW   ( SLEW_RATE      )      // Specify the output slew rate
    )
    IOBUF_io_buf
    (
        .O  ( buf_o     ),  // Buffer output
        .IO ( buf_io    ),  // Buffer inout port (connect directly to top-level port)
        .I  ( buf_i     ),  // Buffer input
        .T  ( tristate  )   // 3-state enable input, high = input, low = output
    );

/*----------------------------------------------------------------------------------------------------------------------------*/
    
    ODDRE1 #
    (
        .IS_C_INVERTED  ( 1'b0                      ),
        .SIM_DEVICE     ( "SPARTAN_ULTRASCALE_PLUS" ),
        .SRVAL          ( 1'b0                      )
    )
    ODDRE1_buf_i
    (
        .Q  ( buf_i     ),  // 1-bit DDR output
        .C  ( oddr_clk  ),  // 1-bit clock input
        .D1 ( sdr_i[0]  ),  // 1-bit data input 1
        .D2 ( sdr_i[1]  ),  // 1-bit data input 2
        .SR ( 1'b0      )   // 1-bit reset
    );
    
    
    ODDRE1 #
    (
        .IS_C_INVERTED  ( 1'b0                      ),
        .SIM_DEVICE     ( "SPARTAN_ULTRASCALE_PLUS" ),
        .SRVAL          ( 1'b0                      )
    )
    ODDRE1_buf_t
    (
        .Q  ( tristate  ),  // 1-bit DDR output
        .C  ( oddr_clk  ),  // 1-bit clock input
        .D1 ( buf_t     ),  // 1-bit data input 1
        .D2 ( buf_t     ),  // 1-bit data input 2
        .SR ( 1'b0      )   // 1-bit reset
    );
    
/*----------------------------------------------------------------------------------------------------------------------------*/
    
    generate
        if (USE_IDELAY_PRIMITIVE) begin
            
            (* IODELAY_GROUP = IODELAY_GROUP_ID *)  // Specifies group name for associated IDELAYs/ODELAYs and IDELAYCTRL
            
            IDELAYE2 #
            (
                .CINVCTRL_SEL           ( "FALSE"                                          ),   // Enable dynamic clock inversion (FALSE, TRUE)
                .DELAY_SRC              ( "IDATAIN"                                        ),   // Delay input (IDATAIN, DATAIN)
                .HIGH_PERFORMANCE_MODE  ( "FALSE"                                          ),   // Reduced jitter ("TRUE"), Reduced power ("FALSE")
                .IDELAY_TYPE            ( "FIXED"                                          ),   // FIXED, VARIABLE, VAR_LOAD, VAR_LOAD_PIPE
                .IDELAY_VALUE           ( (IDELAY_TAPS_VALUE > 31)? 31 : IDELAY_TAPS_VALUE ),   // Input delay tap setting (0-31)
                .PIPE_SEL               ( "FALSE"                                          ),   // Select pipelined mode, FALSE, TRUE
                .REFCLK_FREQUENCY       ( IODELAY_REFCLK_MHZ                               ),   // IDELAYCTRL clock input frequency in MHz (190.0-210.0).
                .SIGNAL_PATTERN         ( "DATA"                                           )    // DATA, CLOCK input signal
            )
            IDELAYE2_inst
            (
                .C              ( idelay_clk ),     // 1-bit input: Clock input
                .CINVCTRL       ( 1'b0       ),     // 1-bit input: Dynamic clock inversion input
                .DATAIN         ( 1'b0       ),     // 1-bit input: Internal delay data input
                .IDATAIN        ( buf_o      ),     // 1-bit input: Data input from the I/O
                .DATAOUT        ( idelay_o   ),     // 1-bit output: Delayed data output
                .CNTVALUEIN     ( 5'b00000   ),     // 5-bit input: Counter value input
                .CNTVALUEOUT    ( /*--NC--*/ ),     // 5-bit output: Counter value output
                .CE             ( 1'b0       ),     // 1-bit input: Active high enable increment/decrement input
                .INC            ( 1'b0       ),     // 1-bit input: Increment / Decrement tap delay input
                .LD             ( 1'b0       ),     // 1-bit input: Load IDELAY_VALUE input
                .LDPIPEEN       ( 1'b0       ),     // 1-bit input: Enable PIPELINE register to load data input
                .REGRST         ( 1'b0       )      // 1-bit input: Active-high reset tap-delay input
            );
            
            assign iserdes_data_in = idelay_o;
            
        end else begin
            /* Bypassing IDELAY primitive */
            assign iserdes_data_in = buf_o;
        end
    endgenerate

/*----------------------------------------------------------------------------------------------------------------------------*/
    
    /* ISERDESE3 D input must stay dedicated to IO data path.
     * Use a deserialized bit as a low-latency fabric-visible RWDS sample. */
    assign iserdes_comb_o = iserdes_q_ext[0];
    
    /* Keep the existing 6-bit output interface used by the DRU logic. */
    assign iserdes_q = iserdes_q_ext[5:0];
    
    
    ISERDESE3 #
    (
        .DATA_WIDTH         ( 8                         ),  // ISERDESE3 supports DDR widths 4 or 8
        .DDR_CLK_EDGE       ( "OPPOSITE_EDGE"           ),
        .FIFO_ENABLE        ( "FALSE"                   ),
        .FIFO_SYNC_MODE     ( "FALSE"                   ),
        .IDDR_MODE          ( "FALSE"                   ),
        .IS_CLK_B_INVERTED  ( 1'b1                      ),
        .IS_CLK_INVERTED    ( 1'b0                      ),
        .IS_RST_INVERTED    ( 1'b0                      ),
        .SIM_DEVICE         ( "SPARTAN_ULTRASCALE_PLUS" )
    )
    ISERDESE3_inst
    (
        .FIFO_EMPTY     ( /*-----NC-----*/  ),
        .INTERNAL_DIVCLK( /*-----NC-----*/  ),
        .Q              ( iserdes_q_ext     ),
        
        .CLK            ( iserdes_clk       ),
        .CLKDIV         ( iserdes_clkdiv    ),
        .CLK_B          ( iserdes_clk       ),
        .D              ( iserdes_data_in   ),
        .FIFO_RD_CLK    ( 1'b0              ),  // Tie off when FIFO is disabled
        .FIFO_RD_EN     ( 1'b0              ),  // Tie off when FIFO is disabled
        .RST            ( arst              )
    );
    
/*----------------------------------------------------------------------------------------------------------------------------*/
    
    /* Register ISERDESE3 output */
    always @(posedge iserdes_clkdiv or posedge arst) begin
        if (arst) begin
            iserdes_o <= {6{1'b0}};
        end else begin
            iserdes_o <= iserdes_q;
        end
    end
    
endmodule

/*----------------------------------------------------------------------------------------------------------------------------*/

`default_nettype wire
