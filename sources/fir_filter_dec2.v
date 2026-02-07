`timescale 1ns/1ps

module fir_filter_dec2 (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire signed [7:0]    x_in,
    output wire signed [22:0]   y_out
);

    // =========================================================================
    // 60 Symmetric Coefficients: H[k] = H[119-k]
    // Full 120-tap filter: [1,2,...,60, 60,59,...,2,1]
    // =========================================================================
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
    
    // Additional parameters to add input and output latency to check if tests
    // passes for flexibilty for latency in RTL implementation
    parameter integer INPUT_LATENCY = 0;
    parameter integer OUTPUT_LATENCY = 0;

    reg [7:0] x_in_r, x_in_r2;
    wire [7:0] x_in_mx;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_in_r <= 8'sd0;
            x_in_r2 <= 8'sd0;
        end else begin
            x_in_r <= x_in;
            x_in_r2 <= x_in_r;
        end
    end

    assign x_in_mx = (INPUT_LATENCY == 1) ? x_in_r :
                     (INPUT_LATENCY == 2) ? x_in_r2 : x_in;

    // Pack coefficients for indexed access: COEFF[k*8 +: 8] = H_k
    localparam [479:0] COEFF = {
        H59, H58, H57, H56, H55, H54, H53, H52, H51, H50,
        H49, H48, H47, H46, H45, H44, H43, H42, H41, H40,
        H39, H38, H37, H36, H35, H34, H33, H32, H31, H30,
        H29, H28, H27, H26, H25, H24, H23, H22, H21, H20,
        H19, H18, H17, H16, H15, H14, H13, H12, H11, H10,
        H9,  H8,  H7,  H6,  H5,  H4,  H3,  H2,  H1,  H0
    };

    // =========================================================================
    // Phase Counter (0 → 1 → 2 → 0 → ...)
    // =========================================================================
    reg [1:0] phase;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            phase <= 2'd0;
        else
            phase <= (phase == 2'd2) ? 2'd0 : phase + 2'd1;
    end

    // =========================================================================
    // Three Polyphase Shift Registers (40 entries each)
    //   sr0: sub-sequence 0 → x[0], x[3], x[6], ...
    //   sr1: sub-sequence 1 → x[1], x[4], x[7], ...
    //   sr2: sub-sequence 2 → x[2], x[5], x[8], ...
    // =========================================================================
    reg signed [7:0] sr0 [0:39];
    reg signed [7:0] sr1 [0:39];
    reg signed [7:0] sr2 [0:39];

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 40; i = i + 1) begin
                sr0[i] <= 8'sd0;
                sr1[i] <= 8'sd0;
                sr2[i] <= 8'sd0;
            end
        end else begin
            case (phase)
                2'd0: begin
                    for (i = 39; i > 0; i = i - 1) sr0[i] <= sr0[i-1];
                    sr0[0] <= x_in_mx;
                end
                2'd1: begin
                    for (i = 39; i > 0; i = i - 1) sr1[i] <= sr1[i-1];
                    sr1[0] <= x_in_mx;
                end
                2'd2: begin
                    for (i = 39; i > 0; i = i - 1) sr2[i] <= sr2[i-1];
                    sr2[0] <= x_in_mx;
                end
                default: ;
            endcase
        end
    end

    // =========================================================================
    // Tap-to-Sample Mapping (combinational)
    //
    // For output y[3n+2], tap k uses sample x[3n+2-k]:
    //   k%3==0 → sub-seq 2, delay k/3 (use x_in when delay=0)
    //   k%3==1 → sub-seq 1, delay k/3
    //   k%3==2 → sub-seq 0, delay k/3
    //
    // At end of phase 2: sr0/sr1 are up-to-date, sr2 is about to be
    // updated (so x_in provides the newest sr2 sample).
    // =========================================================================
    wire signed [7:0] tap_sample [0:119];

    genvar g;
    generate
        for (g = 0; g < 120; g = g + 1) begin : tap_map
            if (g % 3 == 0) begin : sub2
                if (g == 0) begin : newest
                    assign tap_sample[g] = x_in_mx;
                end else begin : delayed
                    assign tap_sample[g] = sr2[g/3 - 1];
                end
            end else if (g % 3 == 1) begin : sub1
                assign tap_sample[g] = sr1[g/3];
            end else begin : sub0
                assign tap_sample[g] = sr0[g/3];
            end
        end
    endgenerate

    // =========================================================================
    // Symmetric Pre-Sums (combinational)
    //   pre_sum[k] = tap_sample[k] + tap_sample[119-k]  for k = 0..59
    // =========================================================================
    wire signed [8:0] pre_sum [0:59];

    generate
        for (g = 0; g < 60; g = g + 1) begin : sym_add
            assign pre_sum[g] = tap_sample[g] + tap_sample[119 - g];
        end
    endgenerate

    // =========================================================================
    // Registered Symmetric Pre-Sums (captured at end of phase 2)
    // =========================================================================
    reg signed [8:0] sym_sum [0:59];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 60; i = i + 1)
                sym_sum[i] <= 9'sd0;
        end else if (phase == 2'd2) begin
            for (i = 0; i < 60; i = i + 1)
                sym_sum[i] <= pre_sum[i];
        end
    end

    // =========================================================================
    // 20 Time-Multiplexed Multipliers
    //   Phase 0: coeff indices 0, 3, 6, ..., 57
    //   Phase 1: coeff indices 1, 4, 7, ..., 58
    //   Phase 2: coeff indices 2, 5, 8, ..., 59
    // =========================================================================
    wire signed [16:0] mul_prod [0:19];

    generate
        for (g = 0; g < 20; g = g + 1) begin : mul_gen
            wire signed [7:0] c0, c1, c2;
            assign c0 = COEFF[(3*g  )*8 +: 8];
            assign c1 = COEFF[(3*g+1)*8 +: 8];
            assign c2 = COEFF[(3*g+2)*8 +: 8];

            wire signed [7:0] m_coeff;
            assign m_coeff = (phase == 2'd0) ? c0 :
                             (phase == 2'd1) ? c1 : c2;

            wire signed [8:0] m_samp;
            assign m_samp = (phase == 2'd0) ? sym_sum[3*g]   :
                            (phase == 2'd1) ? sym_sum[3*g+1] : sym_sum[3*g+2];

            assign mul_prod[g] = m_coeff * m_samp;
        end
    endgenerate

    // =========================================================================
    // Sum of 20 Products
    // =========================================================================
    integer j;
    reg signed [22:0] phase_sum;

    always @(*) begin
        phase_sum = 23'sd0;
        for (j = 0; j < 20; j = j + 1)
            phase_sum = phase_sum + mul_prod[j];
    end

    // =========================================================================
    // Accumulation and Output
    //   Phase 0: Start accumulator with first 20 products
    //   Phase 1: Add next 20 products
    //   Phase 2: Output total (60 products), also captures new sym_sum
    // =========================================================================
    reg signed [22:0] accum;
    reg signed [22:3] y_out_int;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            accum <= 23'sd0;
            y_out_int <= 23'sd0;
        end else begin
            case (phase)
                2'd0: accum <= phase_sum;
                2'd1: accum <= accum + phase_sum;
                2'd2: y_out_int <= accum + phase_sum;
                default: ;
            endcase
        end
    end

    reg signed [22:0] y_out_r, y_out_r2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            y_out_r <= 23'sd0;
            y_out_r2 <= 23'sd0;
        end else begin
            y_out_r <= y_out_int;
            y_out_r2 <= y_out_r;
        end
    end

    assign y_out = (OUTPUT_LATENCY == 1) ? y_out_r :
                   (OUTPUT_LATENCY == 2) ? y_out_r2 : y_out_int;

endmodule
