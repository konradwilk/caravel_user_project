`default_nettype none
`timescale 1ns/1ns
`ifdef FORMAL
`define MPRJ_IO_PADS 38
`endif
`ifdef VERILATOR
`define MPRJ_IO_PADS 38
`endif

module sha1_wb #(
    parameter    [31:0] BASE_ADDRESS   = 32'h30000024,
    parameter  IDX_WIDTH = 6,
    parameter  DATA_WIDTH = 32
    ) (
    input wire reset,
    input wire [7:0] chicken_bits_in,
    output wire [15:0] chicken_bits_out,
    output wire done,
    output wire irq,

    /* WishBone logic */

    input wire wb_clk_i,
    input wire wb_rst_i,
    input wire wbs_stb_i, /* strobe */
    input wire wbs_cyc_i,
    input wire wbs_we_i,
    input wire [3:0] wbs_sel_i,
    input wire [31:0] wbs_dat_i,
    input wire [31:0] wbs_adr_i,
    output wire wbs_ack_o,
    output wire [31:0] wbs_dat_o

);
    wire wb_active = wbs_stb_i & wbs_cyc_i;

    reg [31:0] buffer;
    reg [31:0] buffer_o;

    reg sha1_on;
    reg sha1_reset;
    reg sha1_panic;
    reg sha1_done;
    wire finish;
    reg [2:0] sha1_digest_idx;
    reg [6:0] sha1_msg_idx;
    reg transmit;

    wire [159:0] digest;
    reg [DATA_WIDTH-1:0] message[79:0];
    reg [IDX_WIDTH:0] index;

    localparam STATE_INIT   = 0;
    localparam STATE_START  = 1;
    localparam LOOP_ONE     = 2; /* Really  0 <= i <= 19 */
    localparam LOOP_TWO     = 3; /*         20        39 */
    localparam LOOP_THREE   = 4; /*         40        59 */
    localparam LOOP_FOUR    = 5; /*         60        79 */
    localparam STATE_DONE   = 6;
    localparam STATE_FINAL  = 7;
    localparam STATE_PANIC  = 8;
    reg [3:0] state;

    wire [DATA_WIDTH-1:0] w;
    wire [DATA_WIDTH-1:0] a_left_5;
    wire [DATA_WIDTH-1:0] w_left_1;
    wire [DATA_WIDTH-1:0] b_old_left_30;

    reg [DATA_WIDTH-1:0] a;
    reg [DATA_WIDTH-1:0] a_old;
    reg [DATA_WIDTH-1:0] b;
    reg [DATA_WIDTH-1:0] b_old;
    reg [DATA_WIDTH-1:0] c;
    reg [DATA_WIDTH-1:0] c_old;
    reg [DATA_WIDTH-1:0] d;
    reg [DATA_WIDTH-1:0] d_old;
    reg [DATA_WIDTH-1:0] e;
    reg [DATA_WIDTH-1:0] e_old;

    reg [DATA_WIDTH-1:0] k;
    reg [DATA_WIDTH-1:0] f;
    reg [DATA_WIDTH-1:0] temp;
    reg [DATA_WIDTH-1:0] temp_old;

    reg [DATA_WIDTH-1:0] h0;
    reg [DATA_WIDTH-1:0] h1;
    reg [DATA_WIDTH-1:0] h2;
    reg [DATA_WIDTH-1:0] h3;
    reg [DATA_WIDTH-1:0] h4;

    reg panic;
    reg inc_counter;
    reg copy_values;
    reg compute;

    /* CTRL_GET parameters. */
    localparam CTRL_GET_NR		= BASE_ADDRESS;
    localparam CTRL_NR 			= 4;

    localparam CTRL_GET_ID		= BASE_ADDRESS + 'h4;
    localparam CTRL_ID			= 32'h53484131; /* SHA1 */
    localparam DEFAULT			= 32'hf00df00d;
    /*
     * When writing: The [2:0] are operations.
     * When reading: [10:4] in what loop we are [0->79]. [1:0] are operations.
     */
    localparam CTRL_SHA1_OPS    = BASE_ADDRESS + 'h8;
    localparam ON			    = 4'b0001;
    localparam OFF			    = 4'b0000;
    localparam RESET			= 4'b0010;
    localparam PANIC			= 4'b0100; /* Can only be read. */
    localparam DONE			    = 4'b1000; /* Can only be read. */

    /* This requires 16 CTRL_MSG_IN and after that we start processing. */
    localparam CTRL_MSG_IN		= BASE_ADDRESS + 'hC;
    localparam ACK			    = 32'h0000001;
    localparam EINVAL			= 32'hfffffea; /* -14 */

    /* Five reads for the digest. */
    localparam CTRL_SHA1_DIGEST 		= BASE_ADDRESS + 'h10;
    localparam EBUSY            = 32'hfffffff0; /* -10 */
    localparam CTRL_PANIC 			= BASE_ADDRESS + 'h14;

    always @(posedge wb_clk_i) begin
        if (reset) begin
            buffer_o <= DEFAULT;
            buffer <= DEFAULT;
            sha1_panic <= 1'b0;
            transmit <= 1'b0;
            sha1_msg_idx <= 0;
            sha1_digest_idx <= 0;
            sha1_done <= 0;
            sha1_reset <= 1'b1; /* Reset the SHA1 compute engine */
            sha1_on <= 1'b0;
        end else begin
            if (transmit)
                transmit <= 1'b0;

            if (sha1_reset) begin
                sha1_digest_idx <= 0;
                sha1_reset <= 1'b0;
            end
            if (finish)
                sha1_done <= 1'b1;
            if (chicken_bits_in) begin
		case (chicken_bits_in[7:0])
		   8'b0000_0001: sha1_on <= 1'b1;
		   8'b0000_0010: sha1_on <= 1'b0;
		   8'b0000_0100: sha1_reset <= 1'b1;
		   8'b0000_1000: sha1_reset <= 1'b0;
		   8'b0001_0000: sha1_panic <= 1'b1;
		   8'b0010_0000: sha1_panic <= 1'b0;
		   8'b0100_0000: sha1_done <= 1'b1;
		   8'b1000_0000: sha1_done <= 1'b0;
		   default: ;
                endcase
            end
            if (wb_active && !wbs_we_i) begin
                case (wbs_adr_i)
                    CTRL_GET_NR:
                    begin
                        buffer_o <= CTRL_NR;
                    end
                    CTRL_GET_ID:
                        buffer_o <= CTRL_ID;
                    CTRL_MSG_IN:
                        buffer_o <= EINVAL;
                    CTRL_SHA1_OPS:
                        buffer_o <= {21'b0, index, sha1_done, sha1_panic, sha1_reset, sha1_on};
                    CTRL_SHA1_DIGEST:
                    begin
                        if (sha1_done) begin
                            case (sha1_digest_idx)
                                'h4: buffer_o <= h4;
                                'h3: buffer_o <= h3;
                                'h2: buffer_o <= h2;
                                'h1: buffer_o <= h1;
                                'h0: buffer_o <= h0;
                                default: sha1_panic <= 1'b1;
                            endcase
                            if (!transmit) begin
                                if (sha1_digest_idx == 4)
                                    sha1_digest_idx <= 0;
                                else
                                    sha1_digest_idx <= sha1_digest_idx + 1'b1;
                            end
                        end else
                            buffer_o <= EBUSY;
                    end
                    CTRL_PANIC:
                        buffer_o <= {31'b0, sha1_panic};
                endcase
                if ((wbs_adr_i[31:0] >= BASE_ADDRESS) && (wbs_adr_i <= CTRL_PANIC))
                    transmit <= 1'b1;
            end
		    /* Write case */
            if (wb_active && wbs_we_i && &wbs_sel_i) begin
                case (wbs_adr_i)
                    CTRL_SHA1_OPS:
                    begin
                        sha1_on <= wbs_dat_i[0];
                        sha1_reset <= wbs_dat_i[1];
                        if (wbs_dat_i[0]) begin
                            sha1_msg_idx <= 0;
                            sha1_done <= 0;
                            sha1_digest_idx <= 0;
                        end
                        buffer_o <= {21'b0, index, sha1_done, sha1_panic, wbs_dat_i[1], wbs_dat_i[0]};
                    end
                    CTRL_MSG_IN:
                    begin
                        if (sha1_on)
                            buffer_o <= EINVAL;
                        else begin
                            buffer_o <= ACK;
                            if (sha1_msg_idx > 15)
                                    sha1_panic <= 1'b1;
                            else
                                message[sha1_msg_idx] <= wbs_dat_i;
                            if (!transmit) begin
                                if (sha1_msg_idx == 'hf) begin
                                    sha1_on <= 1'b1;
                                    sha1_msg_idx <= 0;
                                end else
                                    sha1_msg_idx <= sha1_msg_idx + 1'b1;
                            end
                        end
                    end
                    CTRL_PANIC:
                    begin
                        sha1_panic <= 1'b1;
                        buffer <= wbs_dat_i;
                        buffer_o <= ACK;
                    end
                endcase
                if ((wbs_adr_i[31:0] >= BASE_ADDRESS) && (wbs_adr_i <= CTRL_PANIC))
                    transmit <= 1'b1;
            end
        end
    end

    always @(posedge wb_clk_i) begin
        if (reset || sha1_reset) begin
            state <= STATE_INIT;
            temp <= DEFAULT;
            index <= 0;
            panic <= 0;
            inc_counter <= 1'b0;
            copy_values <= 1'b0;
            compute <= 1'b0;
        end else begin
            /* We are running and someone turned it off. */
            if ((index > 1) && !sha1_on)
                state <= STATE_INIT;

            /* Never should happen. TODO: Remove*/
            if (index > 80) begin
                panic <= 1'b1;
                state <= STATE_PANIC;
            end
            /* Increment if allowed to increment counter. */
            if (inc_counter) begin
                index <= index + 1'b1;
                inc_counter <= 1'b0;
            end
            /*
             * Every LOOP_ call ends up with copying the data, so
             * make it generic
             */
            if (compute) begin
                a_old <= a;
                b_old <= b;
                c_old <= c;
                d_old <= d;
            end
            if (copy_values) begin
                e <= d_old;
                d <= c_old;
                c <= b_old_left_30;
                b <= a_old;
                a <= temp;
                copy_values <= 1'b0;
                compute <= 1'b1;
                inc_counter <= 1'b1;
            end
            /*
             * For t = 16 to 79
             * w[i] = (w[i-3] xor w[i-8] xor w[i-14] xor w[i-16]) leftrotate 1
             *
             * This means we need this ready before we get to index=16 hence
             * the +1 adjustment for every offset.
             */
            if (index >= 15) begin
                message[index+1] <= {(message[index-3+1][30:0] ^ message[index-8+1][30:0] ^
                                     message[index-14+1][30:0] ^ message[index-16+1][30:0]),
                                     (message[index-3+1][31] ^ message[index-8+1][31] ^
                                      message[index-14+1][31] ^ message[index-16+1][31])};
            end
            case (state)
                STATE_INIT: begin
                    if (sha1_on)
                        state <= STATE_START;
                    else
                        state <= STATE_INIT;
                end
                STATE_START: begin
                    a <= 32'h67452301;
                    h0 <= 32'h67452301;
                    b <= 32'hEFCDAB89;
                    h1 <= 32'hEFCDAB89;
                    c <= 32'h98BADCFE;
                    h2 <= 32'h98BADCFE;
                    d <= 32'h10325476;
                    h3 <=  32'h10325476;
                    e <= 32'hC3D2E1F0;
                    h4 <= 32'hC3D2E1F0;

                    state <= LOOP_ONE;
                    k <= 32'h5A827999;
                    index <= 0;
                    inc_counter <= 1'b1;
                    compute <= 1'b1;
                    copy_values <= 1'b0;
                end

                LOOP_ONE: begin
                    if ((index == 19) && (inc_counter)) begin
                        state <= LOOP_TWO;
                        k <= 32'h6ED9EBA1;
                    end

                    if (compute) begin
                    /* f = (b and c) or ((not b) and d) */
                    /* temp = (a leftrotate 5) + f + e + k + w[i] */
                        temp <= (a_left_5) + ((b & c) | (~b) & d) + e + k + w;
                        copy_values <= 1'b1;
                        compute <= 1'b0;
                    end
                end
                LOOP_TWO: begin
                    if ((index == 39) && (inc_counter)) begin
                        state <= LOOP_THREE;
                        k <= 32'h8F1BBCDC;
                    end
                    if (compute) begin
                    /* f = b xor c xor d */
                    /* temp = (a leftrotate 5) + f + e + k + w[i] */
                        temp <= (a_left_5) + (b ^ c ^ d) + e + k + w;
                        copy_values <= 1'b1;
                        compute <= 1'b0;
                    end
                end
                LOOP_THREE: begin
                    if ((index == 59) && (inc_counter)) begin
                        state <= LOOP_FOUR;
                        k <= 32'hCA62C1D6;
                    end
                    if (compute) begin
                    /* f = (b and c) or (b and d) or (c and d) */
                    /* temp = (a leftrotate 5) + f + e + k + w[i] */
                        temp <= (a_left_5) + ((b & c) | (b & d) | (c & d)) + e + k + w;
                        copy_values <= 1'b1;
                        compute <= 1'b0;
                    end
                end
                LOOP_FOUR: begin
                    if ((index == 79)  && (inc_counter)) begin
                        state <= STATE_DONE;
                        k <= DEFAULT;
                    end
                    if (compute) begin
                    /* f = b xor c xor d
                    /* temp = (a leftrotate 5) + f + e + k + w[i] */
                        temp <= (a_left_5) + (b ^ c ^ d) + e + k + w;
                        copy_values <= 1'b1;
                        compute <= 1'b0;
                    end
                end
                STATE_DONE: begin
                    index <= 0;
                    inc_counter <= 1'b0;
                    if (compute) begin
                        h0 <= h0 + a;
                        h1 <= h1 + b;
                        h2 <= h2 + c;
                        h3 <= h3 + d;
                        h4 <= h4 + e;
                        state <= STATE_FINAL;
                        copy_values <= 1'b0;
                        compute <= 1'b0;
                    end
                end
                STATE_FINAL: begin
                    if (!sha1_on)
                        state <= STATE_INIT;
                end
                STATE_PANIC: begin
                end
            endcase
        end
    end

    assign a_left_5 = {a[26:0], a[31:27]};
    assign b_old_left_30 = {b_old[1:0], b_old[31:2]};

    /* Provides the w[index] funcionality */
    assign w =  message[index];

    assign digest = {h0, h1, h2, h3, h4};

    assign finish = (state == STATE_FINAL) ? 1'b1 : 1'b0;

    assign wbs_ack_o = reset ? 1'b0 : transmit;

    assign wbs_dat_o = reset ? 32'b0 : buffer_o;

    assign done = reset ? 1'b0 : sha1_done;

    assign irq = reset ? 1'b0: sha1_done;

    assign chicken_bits_out = {buffer_o[14:0], sha1_panic};
endmodule
`default_nettype wire
