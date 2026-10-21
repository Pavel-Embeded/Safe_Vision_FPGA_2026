// ============================================================================
// file_index.v — 编号扫描 + 数字后缀排序，冻结索引表（SafeVision 阶段 6 收尾）
// ----------------------------------------------------------------------------
// 依据：手册 7.6「本版采用'编号扫描 + 数字后缀排序'策略：候选文件为
//       SV0001.BMP 至 SV9999.BMP，扫描全部根目录项后按数字后缀排序，取前四个
//       合法文件；遇到删除项、卷标、子目录、坏簇或非法图片时继续寻找，直到
//       找到四幅或目录结束。该策略直接对标 B01，并与'固定文件名'的参考例程
//       形成差异。」
//       手册 8.6：WAV 与图片【数字后缀一致】（SV0001.BMP ↔ SV0001.WAV）
//       docs/interface_spec.md §3.2
//
// 输入：fat32_directory_scanner 抛出的目录项流（8.3 名 + 首簇 + 大小）
// 输出：冻结的索引表 —— A / C 通过 sel_* 查表口拿"第几槽用哪个文件"
//
// ★ 匹配规则（8.3 名，11 Byte，全大写、空格补齐）
//     "SV0001  BMP" -> 前缀 'S''V' + 4 位数字 + 两个空格 + 扩展名
//     扩展名 'B''M''P' = 图片；'W''A''V' = 音频
//     数字 0000 非法；大小写敏感（8.3 名本来就是大写，小写是别的文件）
//
// ★ 排序：只维护 4 个槽，用插入排序按数字升序排列，超过 4 个的后来的
//   （数字更大）直接落榜。这样"目录里塞 100 个图"也只占 4 个槽。
//
// ★ 为什么要 idx_commit 而不是边收边出：手册要求"扫描全部根目录项后再排序
//   取前四个"。扫描中途出来的前 4 个不一定是数字最小的 4 个。
//   idx_commit 之后表就冻结，只有 idx_clear + 重新扫描才会变。
//
// ★ 为什么单独抽出 file_index：原结构里没有对应模块，因为"编号扫描 + 数字
//   后缀排序"是本队相对参考例程的差异化设计；放在 rtl/storage/ 紧挨着
//   fat32_directory_scanner，接口仍按 interface_spec §3.2 冻结。
// ============================================================================
`include "safevision_defs.vh"

module file_index #(parameter integer CURSOR_MODE=0,CANDIDATE_SLOTS=4) (
    input  wire        clk,
    input  wire        rst_n,

    // ---- 来自 fat32_directory_scanner ----
    input  wire [87:0] ent_name,
    input  wire [7:0]  ent_attr,
    input  wire [31:0] ent_first_clus,
    input  wire [31:0] ent_size,
    input  wire [15:0] ent_index,
    input  wire        ent_valid,
    output wire        ent_ready,      // 本模块不反压，恒 1

    // ---- 提交 / 清表 ----
    input  wire        idx_clear,      // 单拍：清空索引表，准备新一轮扫描
    input  wire        idx_commit,     // 单拍：收到 scan_done 后提交并冻结
    output reg         idx_done,       // 单拍：提交完成
    output reg  [3:0]  file_cnt,       // 合法图片数 0..4
    output reg  [3:0]  file_valid,     // 每槽是否有合法文件（供 C 看全貌）
    output reg         insufficient,   // 不足 4 幅
    output reg  [7:0]  err_code,       // 对外主码
    output reg  [7:0]  err_detail,     // 内部细分码

    // Optional monotonic cursor. Resident loading scans bounded batches,
    // then continues ABOVE every processed candidate, including invalid BMPs.
    // No finite reject CAM can silently discard a later legal file.
    input wire [15:0] cursor_key,
    output wire [15:0] sel_key,
    // ---- 图片查表口（单口读，见 §7 决策 D-1）----
    input  wire [1:0]  sel_slot,
    output wire [31:0] sel_first_clus,
    output wire [31:0] sel_size,
    output wire        sel_valid,

    // ---- WAV 索引口（音画联动 E02 用，见 §3.6）----
    output wire [31:0] sel_wav_first_clus,
    output wire [31:0] sel_wav_size,
    output wire        sel_wav_valid,

    // ---- 观测 ----
    output reg  [15:0] bmp_seen,       // 目录里一共看到几幅编号合法的 BMP
    output reg  [15:0] wav_seen        // 目录里一共看到几个编号合法的 WAV
);

    // With a monotonic cursor the resident loader may retain one minimum
    // candidate, consume/reject it, then rescan above that key. The resulting
    // four legal resident images stay identical to the four-candidate mode.
    // The default preserves the original four-slot batching and lookup ports.
    // synthesis translate_off
    initial if(CANDIDATE_SLOTS<1 || CANDIDATE_SLOTS>4)
        $fatal(1,"invalid candidate capacity");
    // synthesis translate_on
    localparam integer NSLOT = 4;      // 图片槽数（手册：前四幅）
    localparam integer NWAV  = 8;      // WAV 候选表（够 4 幅图配对了）
    // idx_commit freezes BOTH table and counters, until the next idx_clear.
    reg collecting;

    // ------------------------------------------------------------------------
    // 1. 8.3 名解析（纯组合）
    // ------------------------------------------------------------------------
    wire [7:0] nb0 = ent_name[87:80];   // 'S'
    wire [7:0] nb1 = ent_name[79:72];   // 'V'
    wire [7:0] nd0 = ent_name[71:64];   // 数字 千
    wire [7:0] nd1 = ent_name[63:56];   // 数字 百
    wire [7:0] nd2 = ent_name[55:48];   // 数字 十
    wire [7:0] nd3 = ent_name[47:40];   // 数字 个
    wire [7:0] nsp0= ent_name[39:32];   // 空格
    wire [7:0] nsp1= ent_name[31:24];   // 空格
    wire [7:0] ne0 = ent_name[23:16];
    wire [7:0] ne1 = ent_name[15:8];
    wire [7:0] ne2 = ent_name[7:0];

    wire d0_ok = (nd0 >= 8'h30) && (nd0 <= 8'h39);
    wire d1_ok = (nd1 >= 8'h30) && (nd1 <= 8'h39);
    wire d2_ok = (nd2 >= 8'h30) && (nd2 <= 8'h39);
    wire d3_ok = (nd3 >= 8'h30) && (nd3 <= 8'h39);

    wire name_ok = (nb0 == 8'h53) && (nb1 == 8'h56) &&
                   d0_ok && d1_ok && d2_ok && d3_ok &&
                   (nsp0 == 8'h20) && (nsp1 == 8'h20);
    wire ext_bmp = (ne0 == 8'h42) && (ne1 == 8'h4D) && (ne2 == 8'h50);   // BMP
    wire ext_wav = (ne0 == 8'h57) && (ne1 == 8'h41) && (ne2 == 8'h56);   // WAV

    // 数字后缀：0000 非法（编号从 0001 起）
    // ★★ 2026-10-05 时序修改：比较键改用**4 个 nibble 打包**（每个数字 0..9），
    //   它与十进制数值**同序**（0001 < 0002 < ... < 9999），但**去掉了
    //   *1000/*100/*10 的十进制乘法** —— 那正是 TD 在 125MHz 下报出的
    //   MULT18+ADDER，也是 15.03ns 长路径（8ns 预算）的一部分。
    // ★★ 2026-10-06 复核修（缺陷 25）：**位宽截断**。原来写成
    //     `wire [15:0] ent_key = {(nd0-8'h30),(nd1-8'h30),(nd2-8'h30),(nd3-8'h30)};`
    //   四个操作数各是 **8 bit** ⇒ 拼接结果是 **32 bit**，赋给 16 bit 只留**低 16 位**
    //   ⇒ 实际只有【后两位数字】参与比较。后果（真卡/真目录就会踩到）：
    //     · 编号以 `00` 结尾（`SV0100`/`SV0200`…）⇒ ent_key==0 ⇒ `num_ok` 为假
    //       ⇒ **整幅图被静默忽略**（既不报错也不入槽）；
    //     · 只差前两位（`SV0001` vs `SV0101`）⇒ **键相同** ⇒ 被 `is_dup` 当重复丢弃 + 排序错。
    //   修法：先把每个数字**截成 4 bit**（`nk*`），再拼 16 bit ⇒ 键 = 千/百/十/个，
    //   与十进制同序且无截断。★ 仍然没有乘法，时序收益保持不变。
    //   （本仓库既有 TB 只用 SV0001..SV0006：既不撞车也不以 00 结尾 ⇒ 60 项断言守不住，
    //     已补 `tb_file_index` 的 T7x 用例。）
    wire [3:0]  nk0 = nd0 - 8'h30;      // 千
    wire [3:0]  nk1 = nd1 - 8'h30;      // 百
    wire [3:0]  nk2 = nd2 - 8'h30;      // 十
    wire [3:0]  nk3 = nd3 - 8'h30;      // 个
    wire [15:0] ent_key = { nk0, nk1, nk2, nk3 };
    wire num_ok = (ent_key != 16'd0);

    wire is_bmp_c = collecting && !idx_clear && ent_valid && name_ok && num_ok && ext_bmp && (!CURSOR_MODE || ent_key>cursor_key);
    wire is_wav_c = collecting && !idx_clear && ent_valid && name_ok && num_ok && ext_wav && (!CURSOR_MODE || ent_key>cursor_key);

    // ★★ 译码打一拍（流水第 1 段 → 第 2 段）：
    //   把「88 位名比较 + 数字归一化」与「4 槽插入排序 + 表移位」切开。
    //   实测（board_verify base）：两者压在一拍时最差 15.03ns / Logic Level 11，
    //   在 125MHz（8ns）下必违例；切开后第 2 段的输入全部来自寄存器。
    //   ★ 因此 idx_commit 需要在模块内**延后几拍**（见下方 COMMIT_DLY），
    //     保证最后一个目录项已经流过第 2 段之后再冻结表。
    reg        is_bmp_d, is_wav_d;
    reg [15:0] key_d;
    reg [31:0] clus_d, size_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            is_bmp_d <= 1'b0; is_wav_d <= 1'b0; key_d <= 16'd0;
            clus_d <= 32'd0; size_d <= 32'd0;
        end else begin
            is_bmp_d <= is_bmp_c;
            is_wav_d <= is_wav_c;
            key_d    <= ent_key;
            clus_d   <= ent_first_clus;
            size_d   <= ent_size;
        end
    end

    wire is_bmp = is_bmp_d;
    wire is_wav = is_wav_d;

    // idx_commit 内部延后 3 拍：等译码流水排空 + 表写完再冻结
    reg [2:0] cmit_pipe;
    reg       cmit_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin cmit_pipe <= 3'd0; cmit_d <= 1'b0; end
        else begin
            cmit_pipe <= {cmit_pipe[1:0], idx_commit};
            cmit_d    <= cmit_pipe[2];
        end
    end

    assign ent_ready = 1'b1;           // 本模块不反压（见接口文档）

    // ------------------------------------------------------------------------
    // 2. 图片槽（插入排序，只留数字最小的 4 个）
    //    以及 WAV 候选表（同样插入排序，只留数字最小的 8 个）
    // ------------------------------------------------------------------------
    reg [15:0] s_key [0:NSLOT-1];
    reg [31:0] s_clus[0:NSLOT-1];
    reg [31:0] s_size[0:NSLOT-1];
    reg        s_val [0:NSLOT-1];

    reg [15:0] w_key [0:NWAV-1];
    reg [31:0] w_clus[0:NWAV-1];
    reg [31:0] w_size[0:NWAV-1];
    reg        w_val [0:NWAV-1];

    // WAV 配对结果（提交后冻结，按图片槽号索引）
    reg [31:0] m_clus[0:NSLOT-1];
    reg [31:0] m_size[0:NSLOT-1];
    reg        m_val [0:NSLOT-1];

    integer i, j;
    integer ins_pos;
    reg     is_dup;
    reg     ins_keep;

    // 插入位置：1 + 最后一个"已存在且数字更小"的槽号
    always @(*) begin
        ins_pos = 0;
        for (i = 0; i < CANDIDATE_SLOTS; i = i + 1)
            if (s_val[i] && (s_key[i] < key_d)) ins_pos = i + 1;
        is_dup = 1'b0;
        for (i = 0; i < CANDIDATE_SLOTS; i = i + 1)
            if (s_val[i] && (s_key[i] == key_d)) is_dup = 1'b1;
        // ins_pos == NSLOT 说明新编号比榜上最大的还大 -> 落榜
        ins_keep = (ins_pos < CANDIDATE_SLOTS) && !is_dup;
    end

    // ------------------------------------------------------------------------
    // 3. 主逻辑
    // ------------------------------------------------------------------------
    reg [15:0] bcnt_bmp, bcnt_wav;
    integer    k;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < NSLOT; i = i + 1) begin
                s_key[i]  <= 16'd0;
                s_clus[i] <= 32'd0;
                s_size[i] <= 32'd0;
                s_val[i]  <= 1'b0;
                m_clus[i] <= 32'd0;
                m_size[i] <= 32'd0;
                m_val[i]  <= 1'b0;
            end
            for (i = 0; i < NWAV; i = i + 1) begin
                w_key[i]  <= 16'd0;
                w_clus[i] <= 32'd0;
                w_size[i] <= 32'd0;
                w_val[i]  <= 1'b0;
            end
            idx_done     <= 1'b0;
            file_cnt     <= 4'd0;
            file_valid   <= 4'd0;
            insufficient <= 1'b0;
            err_code     <= `ERR_NONE;
            err_detail   <= `DET_NONE;
            bcnt_bmp     <= 16'd0;
            bcnt_wav     <= 16'd0;
            bmp_seen     <= 16'd0;
            wav_seen     <= 16'd0;
            collecting   <= 1'b1;
        end else begin
            idx_done <= 1'b0;          // 单拍脉冲

            // ---- 清表：准备新一轮扫描 --------------------------------------
            if (idx_clear) begin
                collecting<=1'b1;
                for (i = 0; i < NSLOT; i = i + 1) begin
                    s_key[i]  <= 16'd0;
                    s_clus[i] <= 32'd0;
                    s_size[i] <= 32'd0;
                    s_val[i]  <= 1'b0;
                    m_clus[i] <= 32'd0;
                    m_size[i] <= 32'd0;
                    m_val[i]  <= 1'b0;
                end
                for (i = 0; i < NWAV; i = i + 1) begin
                    w_key[i]  <= 16'd0;
                    w_clus[i] <= 32'd0;
                    w_size[i] <= 32'd0;
                    w_val[i]  <= 1'b0;
                end
                bcnt_bmp     <= 16'd0;
                bcnt_wav     <= 16'd0;
                bmp_seen     <= 16'd0;
                wav_seen     <= 16'd0;
                file_cnt     <= 4'd0;
                file_valid   <= 4'd0;
                insufficient <= 1'b0;
                err_code     <= `ERR_NONE;
                err_detail   <= `DET_NONE;
            end

            // ---- 收目录项 --------------------------------------------------
            if (is_bmp && collecting && !idx_clear) begin
                bcnt_bmp <= bcnt_bmp + 16'd1;
                bmp_seen <= bcnt_bmp + 16'd1;
                if (ins_keep) begin
                    for (j = CANDIDATE_SLOTS - 1; j > 0; j = j - 1) begin
                        if (j > ins_pos) begin
                            s_key[j]  <= s_key[j-1];
                            s_clus[j] <= s_clus[j-1];
                            s_size[j] <= s_size[j-1];
                            s_val[j]  <= s_val[j-1];
                        end
                    end
                    s_key [ins_pos] <= key_d;
                    s_clus[ins_pos] <= clus_d;
                    s_size[ins_pos] <= size_d;
                    s_val [ins_pos] <= 1'b1;
                end
            end else if (is_wav && collecting && !idx_clear) begin
                bcnt_wav <= bcnt_wav + 16'd1;
                wav_seen <= bcnt_wav + 16'd1;
                // WAV 表同样插入排序，只留数字最小的 NWAV 个
                begin : wav_ins
                    integer wi;
                    integer wpos;
                    reg     wdup;
                    reg     wkeep;
                    wpos = 0;
                    for (wi = 0; wi < NWAV; wi = wi + 1)
                        if (w_val[wi] && (w_key[wi] < key_d)) wpos = wi + 1;
                    wdup = 1'b0;
                    for (wi = 0; wi < NWAV; wi = wi + 1)
                        if (w_val[wi] && (w_key[wi] == key_d)) wdup = 1'b1;
                    wkeep = (wpos < NWAV) && !wdup;
                    if (wkeep) begin
                        for (wi = NWAV - 1; wi > 0; wi = wi - 1) begin
                            if (wi > wpos) begin
                                w_key[wi]  <= w_key[wi-1];
                                w_clus[wi] <= w_clus[wi-1];
                                w_size[wi] <= w_size[wi-1];
                                w_val[wi]  <= w_val[wi-1];
                            end
                        end
                        w_key [wpos] <= key_d;
                        w_clus[wpos] <= clus_d;
                        w_size[wpos] <= size_d;
                        w_val [wpos] <= 1'b1;
                    end
                end
            end

            // ---- 提交：冻结索引表 + 配对 WAV ---------------------------------
            if (cmit_d) begin
                collecting<=1'b0;
                file_valid <= {s_val[3], s_val[2], s_val[1], s_val[0]};
                file_cnt   <= {2'b00, s_val[3]} + {2'b00, s_val[2]} +
                              {2'b00, s_val[1]} + {2'b00, s_val[0]};
                if (!(s_val[0] && s_val[1] && s_val[2] && s_val[3])) begin
                    insufficient <= 1'b1;
                    err_code     <= `ERR_MEDIA_INVALID;
                    err_detail   <= `DET_BMP_COUNT;
                end else begin
                    insufficient <= 1'b0;
                    err_code     <= `ERR_NONE;
                    err_detail   <= `DET_NONE;
                end

                // 按"数字后缀一致"给每个图片槽找同名 WAV
                for (i = 0; i < NSLOT; i = i + 1) begin
                    m_clus[i] <= 32'd0;
                    m_size[i] <= 32'd0;
                    m_val[i]  <= 1'b0;
                    if (s_val[i]) begin
                        for (k = 0; k < NWAV; k = k + 1) begin
                            if (w_val[k] && (w_key[k] == s_key[i])) begin
                                m_clus[i] <= w_clus[k];
                                m_size[i] <= w_size[k];
                                m_val[i]  <= 1'b1;
                            end
                        end
                    end
                end
                idx_done <= 1'b1;
            end
        end
    end

    // ------------------------------------------------------------------------
    // 4. 查表口（组合读）
    // ------------------------------------------------------------------------
    assign sel_key = s_key[sel_slot];
    assign sel_first_clus     = s_clus[sel_slot];
    assign sel_size           = s_size[sel_slot];
    assign sel_valid          = s_val[sel_slot];
    assign sel_wav_first_clus = m_clus[sel_slot];
    assign sel_wav_size       = m_size[sel_slot];
    assign sel_wav_valid      = m_val[sel_slot];

endmodule
