module msg_ctrl #(
                parameter cache_id = 0,
                parameter cache_num = 1,
                parameter addr_width = 32,
                parameter list_depth = 4,
                parameter data_width = 32,
                parameter list_width = 32
                )
                (
                    input    logic                                     clk,
                    input    logic                                     rst_n,
                        
    
    
                    output   logic [addr_width - 1 :0]                 acc_index,
                    input    logic [2:0]                               acc_status,
                    output   logic [2:0]                               acc_cmd,
                    output   logic [$clog2(list_depth) - 1 : 0]        acc_tag,
                    input    logic [$clog2(list_depth) - 1 : 0]        return_tag,
                    input    logic [addr_width - 1 :0]                 return_index,
                    output   logic                                     acc_req,
                    input    logic                                     acc_gnt,
    
    
                    output   logic [1:0]                               fetch_cmd,
                    output   logic                                     fetch_req,
                    output   logic [$clog2(list_depth) - 1 : 0]        fetch_tag,
                    output   logic [addr_width - 1 : 0]                fetch_addr,
                    input    logic                                     fetch_gnt,
                    input    logic                                     fetch_done,
    
                    input    logic                                     msg_req_0,
                    input    logic [3:0]                               msg_0,
                    input    logic [addr_width - 1 :0]                 msg_index_0,
                    output   logic [3:0]                               msg_rsp_0,
                    output   logic                                     msg_valid_0,
                    output   logic                                     msg_gnt_0,
    
                    input    logic                                     msg_req_1,
                    input    logic [3:0]                               msg_1,
                    input    logic [addr_width - 1 :0]                 msg_index_1,
                    output   logic [3:0]                               msg_rsp_1,
                    output   logic                                     msg_valid_1,
                    output   logic                                     msg_gnt_1,
    
    
                    output   logic                                     msg_req,
                    input    logic                                     msg_gnt,
                    output   logic [4 + 2 * $clog2(cache_num) - 1 : 0] msg,
                    input    logic                                     rsp_valid,
                    input    logic [4 + 2 * $clog2(cache_num) - 1 : 0] msg_rsp
                );

// msg
// 4'b010 : rd_normal_ack
// 4'b011 : rd_share_ack
// 4'b000 : wr_normal_ack
// 4'b100 : wr_req
// 4'b101 : rd_req
typedef struct packed {
    logic [3:0] msg;
    logic [$clog2(cache_num) - 1 : 0] ta;
    logic [$clog2(cache_num) - 1 : 0] ra;
} msg_t;

logic acc_hsked;
logic fetch_hsked;
logic msg_send_hsked;
logic msg_send_req;
logic msg_send_gnt;
msg_t msg_send;

msg_t msg_local;
logic [cache_num - 1 : 0] rsp_bitmap_wr;
logic [1:0]               rsp_owner_wr;
logic                     msg_wr_proc;
msg_t msg_wr;
logic msg_req_wr;
logic msg_gnt_wr;
logic [3:0]                msg_wr_local;

logic [cache_num - 1 : 0] rsp_bitmap_rd;
logic [1:0]               rsp_owner_rd;
logic                     msg_rd_proc;
logic msg_req_rd;
logic msg_gnt_rd;
msg_t msg_rd;
logic [3:0]               msg_rd_local;
logic                     share_ack_prenest;


logic        msg_wr_req_0;
logic        msg_wr_req_1;
logic        msg_rd_req_0;
logic        msg_rd_req_1;
logic        msg_wr_req;
logic        msg_wr_gnt;
logic        msg_rd_req;
logic        msg_rd_gnt;
logic [1:0]  msg_req_local;
logic [1:0]  msg_gnt_local;

typedef enum logic [3:0] {
    IDLE,
    REQ,
    WAIT_RSP,
    DONE
} msg_req_state_t;

typedef enum logic [3:0]  { 
    RSP_IDLE,
    RSP_REQ,
    RSP_WB_REQ,
    RSP_WAIT_WB_DONE,
    RSP_UPDATE,
    RSP_MSG_REQ,
    RSP_DONE
} rsp_state_t;



msg_req_state_t msg_wr_cs, msg_wr_ns, msg_rd_cs, msg_rd_ns;
rsp_state_t rsp_cs, rsp_ns;

assign msg_local = msg_rsp;

always_ff@(posedge clk or negedge rst_n)begin
    if(!rst_n) begin
        msg_wr_cs <= IDLE;
    end else if(msg_wr_cs != msg_wr_ns) begin
        msg_wr_cs <= msg_wr_ns;
    end
end

always_ff@(posedge clk or negedge rst_n)begin
    if(!rst_n) begin
        msg_rd_cs <= IDLE;
    end else if(msg_rd_cs != msg_rd_ns) begin
        msg_rd_cs <= msg_rd_ns;
    end
end

always_ff@(posedge clk or negedge rst_n)begin
    if(!rst_n) begin
        rsp_cs <= IDLE;
    end else if(rsp_cs != rsp_ns) begin
        rsp_cs <= rsp_ns;
    end
end

always_comb begin: MSG_WR_FSM

    case(msg_wr_cs)
    
    IDLE: begin
        if(|(msg_wr_req & msg_wr_gnt))begin
            msg_wr_ns = REQ;
        end else begin
            msg_wr_ns = IDLE
        end
    end

    REQ: begin
        if(msg_req_hsked) begin
            msg_wr_ns = WAIT_RSP;
        end else begin
            msg_wr_ns = REQ;
        end
    end

    WAIT_RSP: begin
        if(&rsp_bitmap_wr) begin
            msg_wr_ns = DONE;
        end else begin
            msg_wr_ns = WAIT_RSP;
        end
    end

    DONE: begin
        msg_wr_ns = IDLE;
    end

    default: begin
        msg_wr_ns = IDLE;
    end

    endcase

end

always_comb begin: MSG_RD_CS

    case(msg_rd_cs)
    
    IDLE: begin
        if(|(msg_rd_req & msg_rd_gnt))begin
            msg_rd_ns = REQ;
        end else begin
            msg_rd_ns = IDLE
        end
    end

    REQ: begin
        if(msg_req_hsked) begin
            msg_rd_ns = WAIT_RSP;
        end else begin
            msg_rd_ns = REQ;
        end
    end

    WAIT_RSP: begin
        if(&rsp_bitmap_rd) begin
            msg_rd_ns = DONE;
        end else begin
            msg_rd_ns = WAIT_RSP;
        end
    end

    DONE: begin
        msg_rd_ns = IDLE;
    end

    default: begin
        msg_rd_ns = IDLE;
    end

    endcase

end

always_comb begin: RSP_FSM

    case(rsp_cs)

    RSP_IDLE: begin
        if(!req_fifo_empty) begin
            rsp_ns = RSP_REQ; 
        end else begin
            rsp_ns = RSP_IDLE; 
        end
    end

    RSP_REQ: begin
        if(acc_hsked) begin
            if(acc_status == 3'b000) begin
                rsp_ns = RSP_MSG_REQ;
            end else if(acc_status == 3'b010) begin
                rsp_ns = RSP_WB_REQ;
            end else if(acc_status == 3'b001 || acc_status == 3'b010) begin
                rsp_ns = RSP_UPDATE;
            end else begin
                rsp_ns = RSP_REQ;
            end
        end else begin
            rsp_ns = RSP_REQ;
        end
    end

    RSP_UPDATE: begin
        if(acc_hsked) begin
            rsp_ns = RSP_MSG_REQ;
        end else begin
            rsp_ns = RSP_UPDATE;
        end
    end

    RSP_WB_REQ: begin
        if(fetch_hsked) begin
            rsp_ns = RSP_WAIT_WB_DONE;
        end else begin
            rsp_ns = RSP_WB_REQ;
        end
    end

    RSP_WAIT_WB_DONE: begin
        if(fetch_done) begin
            rsp_ns = RSP_UPDATE;
        end else begin
            rsp_ns = RSP_WAIT_WB_DONE;
        end
    end

    RSP_UPDATE: begin
        if(acc_hsked) begin
            rsp_ns = RSP_MSG_REQ;
        end else begin
            rsp_ns = RSP_UPDATE;
        end
    end

    RSP_MSG_REQ: begin
        if(msg_send_hsked) begin
            rsp_ns = RSP_DONE;
        end else begin
            rsp_ns = RSP_MSG_REQ;
        end
    end

    RSP_DONE: begin
        rsp_ns = IDLE;
    end
    
    default: begin
        rsp_ns = IDLE;
    end


    endcase

end

assign msg_rd_req_0 = msg_req_0 && (msg_0 == 3'b101) && (msg_rd_cs == IDLE);
assign msg_rd_req_1 = msg_req_1 && (msg_1 == 3'b101) && (msg_rd_cs == IDLE);

assign msg_wr_req_0 = msg_req_0 && (msg_0 == 3'b100) && (msg_wr_cs == IDLE);
assign msg_wr_req_1 = msg_req_1 && (msg_1 == 3'b100) && (msg_wr_cs == IDLE);

assign msg_rd_req = {msg_rd_req_1, msg_rd_req_0};

assign msg_wr_req = {msg_wr_req_1, msg_wr_req_0};

assign {msg_gnt_1, msg_gnt_0} = msg_wr_gnt | msg_rd_gnt;


cache_rr_arb #(
        .WIDTH       (2       ),
        .REFLECTION  (0       ))
             cache_rr_arb_msg_wr_inst (
        .clk         (clk                ) ,//input   
        .rst_n       (rst_n              ) ,//input   
        .req         (msg_wr_req         ) ,//input   [WIDTH - 1 : 0]
        .req_end     (msg_wr_gnt         ) ,//input   [WIDTH - 1 : 0]
        .gnt         (msg_wr_gnt         ));//output  [WIDTH - 1 : 0]

cache_rr_arb #(
        .WIDTH       (2       ),
        .REFLECTION  (0       ))
             cache_rr_arb_msg_rd_inst (
        .clk         (clk                ) ,//input   
        .rst_n       (rst_n              ) ,//input   
        .req         (msg_rd_req         ) ,//input   [WIDTH - 1 : 0]
        .req_end     (msg_rd_gnt         ) ,//input   [WIDTH - 1 : 0]
        .gnt         (msg_rd_gnt         ));//output  [WIDTH - 1 : 0]


always_ff@(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        msg_wr_local <= 4'b0;
        rsp_owner_wr <= 2'b00;
    end else if(msg_wr_gnt[0]) begin
        msg_wr_local <= msg_0;
        rsp_owner_wr <= 2'b00;
    end else if(msg_wr_gnt[1]) begin
        msg_wr_local <= msg_1;
        rsp_owner_wr <= 2'b01;
    end
end

always_ff@(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        msg_rd_local <= 4'b0;
        rsp_owner_rd <= 2'b00;
    end else if(msg_rd_gnt[0]) begin
        msg_rd_local <= msg_0;
        rsp_owner_rd <= 2'b00;
    end else if(msg_rd_gnt[1]) begin
        msg_rd_local <= msg_1;
        rsp_owner_rd <= 2'b01;
    end
end

assign msg_wr_proc = msg_wr_cs != IDLE;
assign msg_rd_proc = msg_rd_cs != IDLE;

generate 

    for(genvar i = 0; i < cache_num; i++) begin: msg_bitmap_grp

        always_ff@(posedge clk or negedge rst_n) begin
            if(!rst_n) begin
                if(i == cache_id) begin
                    rsp_bitmap_wr[i] <= 1'b1;
                end else begin
                    rsp_bitmap_wr[i] <= 1'b0;
                end
            end else if(msg_wr_proc && rsp_valid && (msg_local.msg == 4'b010 || msg_local.msg == 4'b011) &&
                                                    msg_local.ra == cache_id && msg_local.ta == i) begin
                rsp_bitmap_wr[i] <= 1'b1;
            end else if(!msg_wr_proc) begin
                if(i == cache_id) begin
                    rsp_bitmap_wr[i] <= 1'b1;
                end else begin
                    rsp_bitmap_wr[i] <= 1'b0;
                end
            end
        end


        always_ff@(posedge clk or negedge rst_n) begin
            if(!rst_n) begin
                if(i == cache_id) begin
                    rsp_bitmap_rd[i] <= 1'b1;
                end else begin
                    rsp_bitmap_rd[i] <= 1'b0;
                end
            end else if(msg_rd_proc && rsp_valid && (msg_local.msg == 4'b000) &&
                                                    msg_local.ra == cache_id && msg_local.ta == i) begin
                rsp_bitmap_rd[i] <= 1'b1;
            end else if(!msg_rd_proc) begin
                if(i == cache_id) begin
                    rsp_bitmap_rd[i] <= 1'b1;
                end else begin
                    rsp_bitmap_rd[i] <= 1'b0;
                end
            end
        end

    end

endgenerate

always_ff@(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        share_ack_prenest <= 1'b0;
    end else if(msg_rd_proc && rsp_valid && ( msg_local.msg == 4'b011) &&
                                            msg_local.ra == cache_id ) begin
        share_ack_prenest <= 1'b1;
    end else if(!msg_rd_proc) begin
        share_ack_prenest <= 1'b0;
    end
end

assign msg_valid_0 = (wr_cs == DONE && rsp_owner_wr == 2'b00) || (rd_cs == DONE && rsp_owner_wr == 2'b00);
assign msg_valid_1 = (wr_cs == DONE && rsp_owner_wr == 2'b01) || (rd_cs == DONE && rsp_owner_wr == 2'b01);

always_comb begin
    if(wr_cs == DONE && rsp_owner_wr == 2'b00) begin
        msg_rsp_0 = 3'b000;
    end else if(rd_cs == DONE && rsp_owner_rd == 2'b00 && !share_ack_prenest) begin
        msg_rsp_0 = 3'b010;
    end else if(rd_cs == DONE && rsp_owner_rd == 2'b00 && share_ack_prenest) begin
        msg_rsp_0 = 3'b011;
    end else begin
        msg_rsp_0 = 3'b000;
    end
end

always_comb begin
    if(wr_cs == DONE && rsp_owner_rd == 2'b01) begin
        msg_rsp_1 = 3'b000;
    end else if(rd_cs == DONE && rsp_owner_rd == 2'b01 && !share_ack_prenest) begin
        msg_rsp_1 = 3'b010;
    end else if(rd_cs == DONE && rsp_owner_rd == 2'b01 && share_ack_prenest) begin
        msg_rsp_1 = 3'b011;
    end else begin
        msg_rsp_1 = 3'b000;
    end
end


always_comb begin
    msg_wr.msg = 4'b100;
    msg_wr.ta = cache_id;
    msg_wr.ra = {$clog2(cache_num){1'b1}};
end

always_comb begin
    msg_rd.msg = 4'b101;
    msg_rd.ta = cache_id;
    msg_rd.ra = {$clog2(cache_num){1'b1}};
end

//FIXME:
always_comb begin
    msg_rd.msg = u;
    msg_rd.ta = cache_id;
    msg_rd.ra = {$clog2(cache_num){1'b1}};
end


assign msg_req_wr = msg_wr_cs == REQ;
assign msg_req_rd = msg_rd_cs == REQ;

assign msg_send_hsked = msg_send_req && msg_send_gnt;

assign fetch_hsked = fetch_req && fetch_gnt;

assign acc_hsked = acc_req && acc_gnt;

assign msg_req = msg_req_wr || msg_req_rd || msg_send_req;

assign msg_req_local = {msg_req_wr, msg_req_rd, msg_send_req} & {msg_gnt, msg_gnt, msg_gnt};
assign {msg_gnt_wr, msg_gnt_rd, msg_send_gnt} = msg_gnt_local;

always_comb begin
    if(msg_req_wr && msg_gnt_wr) begin
        msg = msg_wr;
    end else if(msg_req_rd && msg_gnt_rd) begin
        msg = msg_rd;
    end else begin
        msg = msg_send;
    end
end


cache_rr_arb #(
        .WIDTH       (3       ),
        .REFLECTION  (0       ))
             rr_arb_wr_rd_inst (
        .clk         (clk                ) ,//input   
        .rst_n       (rst_n              ) ,//input   
        .req         (msg_req_local      ) ,//input   [WIDTH - 1 : 0]
        .req_end     (msg_gnt_local      ) ,//input   [WIDTH - 1 : 0]
        .gnt         (msg_gnt_local      ));//output  [WIDTH - 1 : 0]

endmodule