// ============================================================================
// fat32_directory_scanner.v — 根目录遍历（SafeVision B 链 · 学习阶段 6）
// ----------------------------------------------------------------------------
// 依据：手册 7.6「FAT32 要回答的是：一个文件占用了哪些簇、按什么顺序串起来」
//       「第一版刻意做简单：单分区、FAT32、根目录、8.3 文件名」
//       docs/interface_spec.md §3.2
//
// 只做一件事：把根目录里的目录项一条条读出来，把"可能是我们要的文件"的那些
//             抛给下游（file_index），其余的按规则跳过。
//             本模块不认识 SV0001.BMP 这种命名的含义，那是 file_index 的事。
//
// 输入：fat32_boot_parser 的全部输出
//   root_clus     根目录首簇        root_dir_lba  根目录首扇区
//   sec_per_clus  每簇扇区数        fat_start_lba FAT 表起始扇区
//   data_start_lba 数据区起始扇区   total_clus    总簇数（判环/判越界用）
// 输出：一条条候选目录项（8.3 名 + 属性 + 首簇 + 字节数 + 槽位号）
//
// ----------------------------------------------------------------------------
// ★ 跳过规则（手册 7.6 / interface_spec §3.2）
//     首字节 0x00   -> 其后全是空槽，目录到此结束，提前收工
//     首字节 0xE5   -> 已删除项，跳过
//     attr == 0x0F  -> 长文件名（LFN）碎片，跳过
//     attr[3] == 1  -> 卷标，跳过
//     attr[4] == 1  -> 子目录，跳过（首版不做子目录）
//
// ★ 为什么见到 0x00 还要把本扇区读完？
//   sd_sector_reader 的 rd_ready 只在 S_IDLE 有效，而它只有在把整块数据发完
//   才回得到 S_IDLE。如果在数据中途把 data_ready 拉低不放，它会永远停在
//   S_DATA，后续每一次读都拿不到 rd_ready。所以本模块见到 0x00 时只记下
//   "该收工了"(stop_pending)，仍然把当前扇区的 512 Byte 收干净，再收工。
//
// ★ 32 Byte 目录项在扇区内天然对齐（512 / 32 = 16），所以一条目录项绝不会
//   被扇区边界切成两半，不需要跨扇区拼接缓冲。
//
// ★ 根目录本身也是一条簇链（FAT32 里根目录不再占用固定区域）。
//   一个簇读完后去 FAT 表查下一个簇号，直到 EOC。
//     FAT 入口地址 = fat_start_lba + (clus*4)/512，扇区内偏移 = (clus*4)%512
//     高 4 位是保留位，必须掩掉，只取 [27:0]
//   簇号越界 -> DET_DIR_OOB；跳簇次数超过总簇数 -> DET_FS_LOOP
//
// ★ 依赖：sd_sector_reader 目前只支持单扇区读（rd_len 必须为 1，CMD18 未实现），
//   所以这里是"一个扇区一次 CMD17"。
//
// ★ 起点约定：必须在 fat32_boot_parser.mount_done 之后才拉 scan_en。
// ============================================================================
`include "safevision_defs.vh"

module fat32_directory_scanner (
    input  wire        clk,
    input  wire        rst_n,

    // ---- 控制 ----
    input  wire        scan_en,        // 单拍脉冲，触发一次根目录遍历
    output reg         scan_done,      // 电平：遍历已结束（成功或出错都置 1，下次 scan_en 清零）
    output reg         dir_bad,        // 电平：目录结构异常（簇链越界 / 成环），SD 层超时不算
    output reg  [7:0]  err_code,       // 对外主码
    output reg  [7:0]  err_detail,     // B 链内部细分码
    output reg  [3:0]  dbg_state,

    // ---- 来自 fat32_boot_parser ----
    input  wire [7:0]  sec_per_clus,
    input  wire [31:0] root_clus,
    input  wire [31:0] root_dir_lba,
    input  wire [31:0] data_start_lba,
    // 注：fat_start_lba / total_clus 不在这里 —— 它们归 fat32_cluster_walker，
    //     由它在顶层与 file_streamer 共用（见 interface_spec §3.2）

    // ---- 候选目录项输出 ----
    output reg  [87:0] ent_name,       // 11 Byte 8.3 名，如 "SV0001  BMP"（前 8 是主名，后 3 是扩展名）
    output reg  [7:0]  ent_attr,       // 属性字节
    output reg  [31:0] ent_first_clus, // 首簇号（高 16 + 低 16 拼起来）
    output reg  [31:0] ent_size,       // 文件字节数
    output reg  [15:0] ent_index,      // 该目录项在根目录里的槽位序号（0 基，含被跳过的项）
    output reg         ent_valid,      // 一条目录项有效
    input  wire        ent_ready,      // 下游反压

    // ---- 到 sd_sector_reader 的读请求（与 fat32_boot_parser 同一种接法）----
    output reg  [31:0] sd_rd_addr,
    output wire [15:0] sd_rd_len,
    output reg         sd_rd_en,
    input  wire        sd_rd_ready,
    input  wire [7:0]  sd_data,
    input  wire        sd_data_valid,
    output wire        sd_data_ready,
    input  wire        sd_data_last,
    input  wire        sd_rd_done,
    input  wire        sd_timeout_err,
    input  wire        sd_crc16_err,
    input  wire [7:0]  sd_err_code,
    input  wire [7:0]  sd_err_detail,

    // ---- 到 fat32_cluster_walker ----
    // 跳簇 / 判 EOC / 判越界 / 判环的逻辑与 file_streamer 共用同一个模块，
    // 禁止在本模块里再写一份（两份判环逻辑不一致是最难查的 bug）
    output reg  [31:0] wk_cur_clus,
    output reg         wk_start,
    output reg         wk_rst_walk,
    input  wire        wk_busy,
    input  wire        wk_done,
    input  wire [31:0] wk_next_clus,
    input  wire        wk_eoc,
    input  wire        wk_error,
    input  wire [7:0]  wk_err_code,
    input  wire [7:0]  wk_err_detail
);

    // ------------------------------------------------------------------------
    // 状态
    // ------------------------------------------------------------------------
    localparam [2:0] D_IDLE     = 3'd0,
                     D_SEC_REQ  = 3'd1,   // 请求读"当前目录扇区"
                     D_SEC_RECV = 3'd2,   // 收 512 Byte，边收边装配目录项
                     D_WALK     = 3'd3,   // 一个簇读完，交给 cluster_walker 查下一个簇
                     D_DONE     = 3'd5,
                     D_ERR      = 3'd6;

    reg  [2:0]  mstate;
    reg  [31:0] cur_clus;       // 正在遍历的簇号
    reg  [31:0] cur_lba;        // 正在遍历的扇区号
    reg  [7:0]  sec_in_clus;    // 本簇已经读了几个扇区
    reg  [8:0]  bcnt;           // 扇区内字节偏移 0..511
    reg  [31:0] to_cnt;         // 单次读事务的兜底超时

    // ---- 单条目录项的装配寄存器 ----
    reg  [87:0] name_raw;       // 11 Byte 名，收完后 byte0 在 [87:80]
    reg  [7:0]  attr_raw;
    reg  [15:0] fc_h;           // FstClusHI
    reg  [15:0] fc_l;           // FstClusLO
    reg  [31:0] size_raw;
    reg         skip_entry;     // 本条是 0xE5 删除项，跳过判定
    reg         stop_pending;   // 见到 0x00：本扇区读完就收工
    reg         wait_ent;       // 已抛出一条目录项，正等 ent_ready
    reg  [15:0] slot_cnt;       // 目录项槽位计数（含被跳过的）

    // ------------------------------------------------------------------------
    // 组合逻辑
    // ------------------------------------------------------------------------
    wire [4:0]  ent_off = bcnt[4:0];        // 本条目录项内的字节偏移 0..31

    // 下游没取走目录项时，把数据流按住（sd_sector_reader 会自然停 SCLK）
    assign sd_data_ready = (mstate == D_SEC_RECV) && !wait_ent;
    assign sd_rd_len     = 16'd1;          // 单扇区读

    // ------------------------------------------------------------------------
    // 主状态机
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mstate       <= D_IDLE;
            scan_done    <= 1'b0;
            dir_bad      <= 1'b0;
            err_code     <= `ERR_NONE;
            err_detail   <= `DET_NONE;
            dbg_state    <= D_IDLE;
            cur_clus     <= 32'd0;
            cur_lba      <= 32'd0;
            sec_in_clus  <= 8'd0;
            bcnt         <= 9'd0;
            to_cnt       <= 32'd0;
            name_raw     <= 88'h0;
            attr_raw     <= 8'h0;
            fc_h         <= 16'h0;
            fc_l         <= 16'h0;
            size_raw     <= 32'h0;
            skip_entry   <= 1'b0;
            stop_pending <= 1'b0;
            wait_ent     <= 1'b0;
            slot_cnt     <= 16'd0;
            ent_name       <= 88'h0;
            ent_attr       <= 8'h0;
            ent_first_clus <= 32'h0;
            ent_size       <= 32'h0;
            ent_index      <= 16'h0;
            ent_valid      <= 1'b0;
            sd_rd_addr     <= 32'd0;
            sd_rd_en       <= 1'b0;
            wk_cur_clus    <= 32'd0;
            wk_start       <= 1'b0;
            wk_rst_walk    <= 1'b0;
        end else begin
            dbg_state   <= mstate;
            sd_rd_en    <= 1'b0;            // 单拍脉冲
            wk_start    <= 1'b0;            // 单拍脉冲
            wk_rst_walk <= 1'b0;            // 单拍脉冲

            // ---- 下游把目录项取走了 ----------------------------------------
            if (wait_ent && ent_ready) begin
                wait_ent  <= 1'b0;
                ent_valid <= 1'b0;
            end

            case (mstate)
            // ------------------------------------------------------------------
            D_IDLE: begin
                if (scan_en) begin
                    scan_done    <= 1'b0;
                    dir_bad      <= 1'b0;
                    err_code     <= `ERR_NONE;
                    err_detail   <= `DET_NONE;
                    cur_clus     <= root_clus;
                    cur_lba      <= root_dir_lba;
                    sec_in_clus  <= 8'd0;
                    bcnt         <= 9'd0;
                    to_cnt       <= 32'd0;
                    name_raw     <= 88'h0;
                    attr_raw     <= 8'h0;
                    fc_h         <= 16'h0;
                    fc_l         <= 16'h0;
                    size_raw     <= 32'h0;
                    skip_entry   <= 1'b0;
                    stop_pending <= 1'b0;
                    wait_ent     <= 1'b0;
                    slot_cnt     <= 16'd0;
                    ent_valid    <= 1'b0;
                    wk_cur_clus  <= root_clus;
                    wk_rst_walk  <= 1'b1;       // 走新链前清跳簇计数
                    mstate       <= D_SEC_REQ;
                end
            end
            // ---- 请求读当前目录扇区 ------------------------------------------
            D_SEC_REQ: begin
                to_cnt <= to_cnt + 32'd1;
                if (to_cnt == `SD_TO_DATA) begin
                    err_code   <= `ERR_SD_IO;
                    err_detail <= `DET_SD_TOKEN_TO;
                    mstate     <= D_ERR;
                end else if (!wait_ent && (sd_timeout_err || sd_crc16_err)) begin
                    // 上一个扇区的 CRC 错会一直留到下次请求被清零，必须在这里收掉
                    err_code   <= sd_err_code;
                    err_detail <= sd_err_detail;
                    mstate     <= D_ERR;
                end else if (!wait_ent && sd_rd_ready) begin
                    sd_rd_addr <= cur_lba;
                    sd_rd_en   <= 1'b1;
                    bcnt       <= 9'd0;
                    to_cnt     <= 32'd0;
                    mstate     <= D_SEC_RECV;
                end
            end
            // ---- 收一个扇区，边收边装配目录项 --------------------------------
            D_SEC_RECV: begin
                // 被下游反压时不推进超时，否则"下游慢"会被误判成"卡超时"
                if (!wait_ent) to_cnt <= to_cnt + 32'd1;
                if (to_cnt == `SD_TO_DATA) begin
                    err_code   <= `ERR_SD_IO;
                    err_detail <= `DET_SD_TOKEN_TO;
                    mstate     <= D_ERR;
                end else if (sd_timeout_err || sd_crc16_err) begin
                    err_code   <= sd_err_code;
                    err_detail <= sd_err_detail;
                    mstate     <= D_ERR;
                end else if (sd_data_valid && sd_data_ready) begin
                    case (ent_off)
                    // 首字节：判断 0x00 结束 / 0xE5 删除
                    5'd0: begin
                        skip_entry <= (sd_data == 8'hE5);
                        if (sd_data == 8'h00) begin
                            stop_pending <= 1'b1;
                            skip_entry   <= 1'b1;
                        end
                        name_raw <= {name_raw[79:0], sd_data};
                    end
                    // 主名 8 + 扩展名 3，一路左移，收完 byte0 落在 [87:80]
                    5'd1, 5'd2, 5'd3, 5'd4, 5'd5, 5'd6, 5'd7, 5'd8, 5'd9, 5'd10:
                        name_raw <= {name_raw[79:0], sd_data};
                    5'd11: attr_raw <= sd_data;
                    5'd20: fc_h[15:8] <= sd_data;
                    5'd21: fc_h[7:0]  <= sd_data;
                    5'd26: fc_l[15:8] <= sd_data;
                    5'd27: fc_l[7:0]  <= sd_data;
                    5'd28: size_raw[7:0]   <= sd_data;
                    5'd29: size_raw[15:8]  <= sd_data;
                    5'd30: size_raw[23:16] <= sd_data;
                    // 末字节：本条装配完成，做跳过判定
                    5'd31: begin
                        size_raw[31:24] <= sd_data;
                        if (!stop_pending && !skip_entry) begin
                            if (attr_raw == 8'h0F) begin
                                // 长文件名碎片：跳过
                            end else if (attr_raw[3]) begin
                                // 卷标：跳过
                            end else if (attr_raw[4]) begin
                                // 子目录：跳过（首版不做子目录）
                            end else begin
                                ent_name       <= name_raw;
                                ent_attr       <= attr_raw;
                                ent_first_clus <= {fc_h, fc_l};
                                ent_size       <= {sd_data, size_raw[23:0]};
                                ent_index      <= slot_cnt;
                                ent_valid      <= 1'b1;
                                wait_ent       <= 1'b1;
                            end
                        end
                        slot_cnt <= slot_cnt + 16'd1;
                    end
                    default: ;
                    endcase

                    bcnt <= bcnt + 9'd1;
                    // ---- 本扇区读完：决定下一个扇区从哪来 ------------------
                    if (bcnt == 9'd511) begin
                        if (stop_pending) begin
                            mstate <= D_DONE;
                        end else if ((sec_in_clus + 8'd1) >= sec_per_clus) begin
                            // 本簇读完，交给 cluster_walker 查下一个簇
                            wk_start <= 1'b1;
                            mstate   <= D_WALK;
                        end else begin
                            cur_lba     <= cur_lba + 32'd1;
                            sec_in_clus <= sec_in_clus + 8'd1;
                            to_cnt      <= 32'd0;
                            mstate      <= D_SEC_REQ;
                        end
                    end
                end
            end
            // ---- 本簇读完：等 cluster_walker 给出下一个簇 ---------------------
            D_WALK: begin
                if (wk_done) begin
                    if (wk_eoc) begin
                        mstate <= D_DONE;                 // 簇链到头，正常收工
                    end else if (wk_error) begin
                        dir_bad    <= 1'b1;
                        err_code   <= wk_err_code;
                        err_detail <= wk_err_detail;      // DET_DIR_OOB / DET_FS_LOOP
                        mstate     <= D_ERR;
                    end else begin
                        cur_clus    <= wk_next_clus;
                        wk_cur_clus <= wk_next_clus;
                        cur_lba     <= data_start_lba +
                                       ((wk_next_clus - 32'd2) * sec_per_clus);
                        sec_in_clus <= 8'd0;
                        to_cnt      <= 32'd0;
                        mstate      <= D_SEC_REQ;
                    end
                end
            end
            // ------------------------------------------------------------------
            D_DONE: begin
                // 等最后一条目录项被下游取走再宣告结束
                if (!wait_ent) begin
                    scan_done <= 1'b1;
                    mstate    <= D_IDLE;
                end
            end
            D_ERR: begin
                if (!wait_ent) begin
                    scan_done <= 1'b1;      // 遍历结束（err_code / dir_bad 说明成败）
                    mstate    <= D_IDLE;
                end
            end
            default: mstate <= D_IDLE;
            endcase
        end
    end

endmodule