`ifndef MYCPU_HEAD_H
`define MYCPU_HEAD_H

// ID -> IF：是否跳转 + 跳转目标地址
`define BR_BUS_WD 33

// IF -> ID：指令 + PC
`define FS_TO_DS_BUS_WD 64

// ID -> EXE：控制信号、操作数、目的寄存器等
`define DS_TO_ES_BUS_WD 148

// EXE -> MEM：ALU结果、访存数据、写回信息等
`define ES_TO_MS_BUS_WD 104

// MEM -> WB：最终结果、目的寄存器、PC等
`define MS_TO_WS_BUS_WD 70

// WB -> 寄存器堆：写使能、目的寄存器、写回数据
`define WS_TO_RF_BUS_WD 38

`define ES_TO_DS_BUS_WD 40
`define MS_TO_DS_BUS_WD 39
`define WS_TO_DS_BUS_WD 39
`endif