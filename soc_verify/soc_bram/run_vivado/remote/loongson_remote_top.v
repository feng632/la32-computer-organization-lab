`default_nettype none

module looongson_remote_top(
    input wire clk_50M,           //50MHz ʱ������
    input wire clk_11M0592,       //11.0592MHz ʱ�����루���ã��ɲ��ã�

    input wire clock_btn,         //BTN5�ֶ�ʱ�Ӱ�ť���أ���������·������ʱΪ1
    input wire reset_btn,         //BTN6�ֶ���λ��ť���أ���������·������ʱΪ1

    input  wire[3:0]  touch_btn,  //BTN1~BTN4����ť���أ�����ʱΪ1
    input  wire[31:0] dip_sw,     //32λ���뿪�أ�������ON��ʱΪ1
    output wire[15:0] leds,       //16λLED�����ʱ1����
    output wire[7:0]  dpy0,       //����ܵ�λ�źţ�����С���㣬���1����
    output wire[7:0]  dpy1,       //����ܸ�λ�źţ�����С���㣬���1����
    
    //CPLD���ڿ������ź�
    output wire uart_rdn,         //�������źţ�����Ч
    output wire uart_wrn,         //д�����źţ�����Ч
    input  wire uart_dataready,    //��������׼����
    input  wire uart_tbre,         //�������ݱ�־
    input  wire uart_tsre,         //���ݷ�����ϱ�־

    //BaseRAM�ź�
    inout wire [31:0] base_ram_data,  //BaseRAM���ݣ���8λ��CPLD���ڿ���������
    output wire[19:0] base_ram_addr, //BaseRAM��ַ
    output wire[ 3:0] base_ram_be_n,  //BaseRAM�ֽ�ʹ�ܣ�����Ч�������ʹ���ֽ�ʹ�ܣ��뱣��Ϊ0
    output wire base_ram_ce_n,       //BaseRAMƬѡ������Ч
    output wire base_ram_oe_n,       //BaseRAM��ʹ�ܣ�����Ч
    output wire base_ram_we_n,       //BaseRAMдʹ�ܣ�����Ч

    //ExtRAM�ź�
    inout  wire[31:0] ext_ram_data,  //ExtRAM����
    output wire[19:0] ext_ram_addr, //ExtRAM��ַ
    output wire[ 3:0] ext_ram_be_n,  //ExtRAM�ֽ�ʹ�ܣ�����Ч�������ʹ���ֽ�ʹ�ܣ��뱣��Ϊ0
    output wire ext_ram_ce_n,       //ExtRAMƬѡ������Ч
    output wire ext_ram_oe_n,       //ExtRAM��ʹ�ܣ�����Ч
    output wire ext_ram_we_n,       //ExtRAMдʹ�ܣ�����Ч

    //ֱ�������ź�
    output wire txd,  //ֱ�����ڷ��Ͷ�
    input  wire rxd,  //ֱ�����ڽ��ն�

    //Flash�洢���źţ��ο� JS28F640 оƬ�ֲ�
    output wire [22:0]flash_a,      //Flash��ַ��a0����8bitģʽ��Ч��16bitģʽ������
    inout  wire [15:0]flash_d,      //Flash����
    output wire flash_rp_n,         //Flash��λ�źţ�����Ч
    output wire flash_vpen,         //Flashд�����źţ��͵�ƽʱ���ܲ�������д
    output wire flash_ce_n,         //FlashƬѡ�źţ�����Ч
    output wire flash_oe_n,         //Flash��ʹ���źţ�����Ч
    output wire flash_we_n,         //Flashдʹ���źţ�����Ч
    output wire flash_byte_n,       //Flash 8bitģʽѡ�񣬵���Ч����ʹ��flash��16λģʽʱ����Ϊ1

    //ͼ������ź�
    output wire[2:0] video_red,    //��ɫ���أ�3λ
    output wire[2:0] video_green,  //��ɫ���أ�3λ
    output wire[1:0] video_blue,   //��ɫ���أ�2λ
    output wire video_hsync,       //��ͬ����ˮƽͬ�����ź�
    output wire video_vsync,       //��ͬ������ֱͬ�����ź�
    output wire video_clk,         //����ʱ�����
    output wire video_de           //��������Ч�źţ���������������
);

wire [ 7:0] local_switch;
wire [15:0] local_leds;
wire        local_resetn;
wire [31:0] local_num_data;

remote2local remote2local
(  
    .remote_switch (dip_sw),
    .local_switch  (local_switch),
    .remote_reset  (reset_btn),
    .local_resetn  (local_resetn),
    
    .local_leds    (local_leds),
    .remote_leds   (leds),
    .local_num_data(local_num_data[7:0]),
    .remote_dpy0   (dpy0),
    .remote_dpy1   (dpy1)
);
// 评测版切回 BRAM：inst/data 走片内 BRAM（coe 内嵌程序随 bit 烧录）
// 板级 SRAM 版（soc_lite_sram_top）保留在文件历史中，需要时再切回
soc_lite_top  soc_lite
(
       .resetn      (local_resetn), 
       .clk         (clk_50M     ),
    
        //------gpio-------
        .num_csn    (              ),
        .num_a_g    (              ),
        .num_data   (local_num_data),
        .led        (local_leds    ),
        .led_rg0    (              ),
        .led_rg1    (              ),
        .switch     (local_switch  ),
        .btn_key_col(              ),
        .btn_key_row(4'b0000       ),
        .btn_step   (2'b11         )
    );
endmodule
