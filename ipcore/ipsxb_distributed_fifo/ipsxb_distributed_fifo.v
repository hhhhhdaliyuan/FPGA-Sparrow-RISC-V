
//////////////////////////////////////////////////////////////////////////////
//
// Copyright (c) 2014 PANGO MICROSYSTEMS, INC
// ALL RIGHTS REVERVED.
//
// THE SOURCE CODE CONTAINED HEREIN IS PROPRIETARY TO PANGO MICROSYSTEMS, INC.
// IT SHALL NOT BE REPRODUCED OR DISCLOSED IN WHOLE OR IN PART OR USED BY
// PARTIES WITHOUT WRITTEN AUTHORIZATION FROM THE OWNER.
//
//////////////////////////////////////////////////////////////////////////////
//
// Library:
// Filename:ipsxb_distributed_fifo.v
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

`timescale 1 ns / 1 ps
module ipsxb_distributed_fifo
 (
  wr_data         ,
  wr_en           ,
  
  wr_clk          ,
  wr_rst          ,
  
  full            ,
  almost_full     ,
  
  wr_water_level  ,
  
  rd_data         ,
  rd_en           ,
  
  rd_clk          ,
  rd_rst          ,
  
  empty           ,
  
  rd_water_level  ,
  
  almost_empty
);

    localparam ADDR_WIDTH = 10 ; //@IPC int 4,10

    localparam DATA_WIDTH = 16 ; //@IPC int 1,256

    localparam OUT_REG = 0 ; //@IPC bool

    localparam RST_TYPE = "ASYNC" ; //@IPC enum ASYNC,SYNC

    localparam FIFO_TYPE = "ASYNC_FIFO" ; //@IPC enum ASYNC_FIFO,SYNC_FIFO

    localparam ALMOST_FULL_NUM = 32 ; //@IPC int 4,1024

    localparam ALMOST_EMPTY_NUM = 32 ; //@IPC int 4,1024

    localparam WR_WATER_LEVEL_ENABLE = 1 ; //@IPC bool

    localparam RD_WATER_LEVEL_ENABLE = 1 ; //@IPC bool

    input  wire  [DATA_WIDTH-1 : 0]      wr_data         ;  // input write data
    input  wire                          wr_en           ;  // input write enable 1 active
    
    input  wire                          wr_clk          ;  // async input write clock
    input  wire                          wr_rst          ;  // input write reset
    
    output wire                          full            ;  // input write full  flag 1 active
    output wire                          almost_full     ;  // output write almost full
    
    output wire  [ADDR_WIDTH : 0]        wr_water_level  ;  // output write water level
    

    output wire  [DATA_WIDTH-1 : 0]      rd_data         ;  // output read data
    input  wire                          rd_en           ;  // input  read enable
    
    input  wire                          rd_clk          ;  // async input  read clock
    input  wire                          rd_rst          ;  // input read reset
    
    output wire                          empty           ;  // output read empty
    output wire                          almost_empty    ;  // output read water level
    
    output wire  [ADDR_WIDTH : 0]        rd_water_level  ;
    

ipm_distributed_fifo_v1_4_ipsxb_distributed_fifo
 #(
  .ADDR_WIDTH       (ADDR_WIDTH      ) ,  // fifo ADDR_WIDTH width 4 -- 10
  .DATA_WIDTH       (DATA_WIDTH      ) ,  // write data width 4 -- 256
  .OUT_REG          (OUT_REG         ) ,  // output register   legal value:0 or 1
  .RST_TYPE         (RST_TYPE        ) ,
  .FIFO_TYPE        (FIFO_TYPE       ) ,  // fifo type legal value "SYN" or "ASYN"
  .ALMOST_FULL_NUM  (ALMOST_FULL_NUM ) ,  // almost full number
  .ALMOST_EMPTY_NUM (ALMOST_EMPTY_NUM)    // almost full number
)u_ipm_distributed_fifo_ipsxb_distributed_fifo
 (
  .wr_data          (wr_data         ) ,  // input write data
  .wr_en            (wr_en           ) ,  // input write enable 1 active
  
  .wr_clk           (wr_clk          ) ,  // input write clock
  .wr_rst           (wr_rst          ) ,  // input write reset
  
  .full             (full            ) ,  // input write full  flag 1 active
  .almost_full      (almost_full     ) ,  // output write almost full
  
  .wr_water_level   (wr_water_level  ) ,  // output write water level
  
  .rd_data          (rd_data         ) ,  // output read data
  .rd_en            (rd_en           ) ,  // input  read enable
  
  .rd_clk           (rd_clk          ) ,  // input  read clock
  .rd_rst           (rd_rst          ) ,  // input read reset
  
  .empty            (empty           ) ,  // output read empty
  
  .rd_water_level   (rd_water_level  ) ,
  
  .almost_empty     (almost_empty    )
);
endmodule
