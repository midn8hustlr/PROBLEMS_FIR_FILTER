`timescale 1ns/1ps

module fir_filter_dec2 (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire signed [7:0]    x_in,
    output reg  signed [7:0]    y_out   // TODO: determine correct output width
);

    // 60 symmetric coefficients: H[k] = H[119-k]
    parameter signed [7:0] H0 =8'sd1,  H1 =8'sd2,  H2 =8'sd3,  H3 =8'sd4,  H4 =8'sd5,  H5 =8'sd6;
    parameter signed [7:0] H6 =8'sd7,  H7 =8'sd8,  H8 =8'sd9,  H9 =8'sd10, H10=8'sd11, H11=8'sd12;
    parameter signed [7:0] H12=8'sd13, H13=8'sd14, H14=8'sd15, H15=8'sd16, H16=8'sd17, H17=8'sd18;
    parameter signed [7:0] H18=8'sd19, H19=8'sd20, H20=8'sd21, H21=8'sd22, H22=8'sd23, H23=8'sd24;
    parameter signed [7:0] H24=8'sd25, H25=8'sd26, H26=8'sd27, H27=8'sd28, H28=8'sd29, H29=8'sd30;
    parameter signed [7:0] H30=8'sd31, H31=8'sd32, H32=8'sd33, H33=8'sd34, H34=8'sd35, H35=8'sd36;
    parameter signed [7:0] H36=8'sd37, H37=8'sd38, H38=8'sd39, H39=8'sd40, H40=8'sd41, H41=8'sd42;
    parameter signed [7:0] H42=8'sd43, H43=8'sd44, H44=8'sd45, H45=8'sd46, H46=8'sd47, H47=8'sd48;
    parameter signed [7:0] H48=8'sd49, H49=8'sd50, H50=8'sd51, H51=8'sd52, H52=8'sd53, H53=8'sd54;
    parameter signed [7:0] H54=8'sd55, H55=8'sd56, H56=8'sd57, H57=8'sd58, H58=8'sd59, H59=8'sd60;

    // TODO: Implement the symmetric FIR filter with decimation by 3

endmodule
