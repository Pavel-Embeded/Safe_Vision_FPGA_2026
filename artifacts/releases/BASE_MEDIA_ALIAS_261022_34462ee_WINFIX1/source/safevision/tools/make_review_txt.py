# -*- coding: utf-8 -*-
"""Concatenate the SafeVision red-frame review material into plain-text files so
they can be pasted into a text-only web assistant.

Outputs
  SafeVision_红框故障_全部代码与说明.txt        one big file
  SafeVision_红框故障_核心代码精简版.txt        compact one big file
  parts/..._第N部分.txt                         the big file split into ~800-line
                                                parts, never cutting a source file
Usage:  python make_review_txt.py [--compact] [--split] [--lines 800]
"""
import io, os, sys

ROOT = r"F:/workspace/fpga_competition/HX4S20_Contest_202606"
OUTDIR = os.path.join(ROOT, "code_review_pack_20261010")
OUT = os.path.join(OUTDIR, "SafeVision_红框故障_全部代码与说明.txt")
PARTS_DIR = os.path.join(OUTDIR, "parts")

BAR = "=" * 92
SUB = "-" * 92

BRIEF = """\
【这是什么】安路 EG4S20 / HX4S20C FPGA 上的一个播放器工程（SafeVision）：
  SD 卡 BMP -> FAT32 解析 -> 像素打包 -> SDRAM 帧缓存（双缓冲槽 0/1）-> HDMI 输出。
  工程根：F:/workspace/fpga_competition/HX4S20_Contest_202606
  分支：codex/normal-playback-integrity-fix-20261010（tip cbbe531）
  时钟：mem_clk = 40 MHz（MEM_CLK_HZ = 40_000_000），mem 域是存储与校验的主域。

【现象】上板后屏幕显示"红框"（安全画面 warning_level=2）。
  串口每 500 ms 打一包 189 字节（SV-PLAY 107 + SV-MEM 82），实测解码：
    包1  ST=8 FS=0 EC=00 SD=1 CARD=1 CNT=4 CUR=0 RD=0004EEC5 PX=1A542 F=0000 SLOT=0 CRC=0 ED=00
         SV-MEM ID=26101002 PH=0 BAD=00000000 EXP=00000000 GOT=00000000 W=0000CFF7 B=0000
    包2  ST=8 ... RD=000AA389 PX=38C98 ... SLOT=0
         SV-MEM ... PH=0 ... W=0001C3A1 B=0000
    包3  ST=A FS=7 EC=F3 SD=0 CARD=0 RD=000E1036 PX=4B000 F=0000 SLOT=1 CRC=0 ED=01
         SV-MEM ID=26101002 PH=3 BAD=000A0000 EXP=0D968558 GOT=FEA8A821 W=00025800 B=0000
    包4..7 与包3 完全相同（故障已锁存；多次上下电后数值仍逐位一致 => 确定性失败）

【字段含义（源码位置见后）】
  W  = integrity_words      guard 看到"被内存接口接受"的写字数：53239 -> 115617 -> 153600
                             => 整帧 153600 字 100% 写入成功。
  RD/PX = 921654 字节 / 307200 像素，比值 3.0002 => RGB24->RGB565，像素链自洽。
  PH = diagnostic_phase     3 = integrity_fault（guard 的整帧读回校验失败）；
                            4 才是 playback_fault（显示侧块校验）。本故障是 PH=3。
  BAD = integrity_bad_addr  0x000A0000，恰等于 SV_IMG1_BASE
                            => 失败地址 = base + 0*256 = 槽1 的第 0 块。
  B  = checked_blocks       0 => 一块都没通过（第 0 块即失败）。
  EXP = bad_expected        签名（写入侧算出的 CRC32）。
  GOT = bad_actual          读回数据算出的 CRC32。
  EC = sk_ec                0xF3，由 bmp_frame_sink.v 的
                            "REQUIRE_READBACK && verify_done && !verify_pass" 产生。
  SLOT = sk_swap_slot       1 => 本帧写的是槽 1（包1/2 的 0 是上一帧的旧值）。
  F  = sk_frame_cnt         0 => 从来没有一帧成功完成（这是开机第一帧）。

【结论：故障点在"读回"，不在"写入"】W 已到 153600 之后才校验失败。

【已经被证明为正确的东西（可复现）】
  1) frame_integrity_guard 逻辑：真几何 TB（WORDS=153600 / ROW_WORDS=320 / 2400 块）
     对理想存储 verify_pass=1、2400/2400 全过。
  2) sdram_app_adapter 读缓存 + 预读：板级配置
     （vsim -gPREFETCH_READ=1 -gFAST_READ=1 -gRD_LAT=11）22 checks / 0 errors。
  3) 集成往返 TB（tb_mem_roundtrip.sv）：
     memory_arbiter + mem_ctrl + 真实 sdram_app_adapter(预读) + SDRAM 契约模型，
     用板级真实突发粒度（写 = 逐字 wr_len=1；读 = 2400 次 64 字突发，正是 guard 的读回方式），
     并叠加一路 64 字显示并发读：
     => 153600/153600 字逐字一致，PASS。
  => 数字逻辑层面"写进去什么、读回来什么"逐字正确，仿真无法解释板上现象。

【与"上次能工作"的位流对比 —— 这是本次最重要的线索】
  项目证据索引记载：2026-10-06 23:31，位流 board_verify_d28 在板上"SD卡BMP->HDMI"整链通过
  （帧计数递增、CRC=1、SLOT 0/1/0 交替、自动换幅，画面确实在切换）。
  用 TD 的 route.area 对比：
    board_verify_d28（板上通过）         : 无 frame_integrity_guard 实例，BRAM 20/64
    board_verify_20261007                : 无 guard 实例，             BRAM 20/64
    board_verify_diag3 / fbk（含 guard） : 有 guard 实例，             BRAM 56/64 (87.5%)
  即：本次交付相对 d28，唯一新增的大逻辑就是 frame_integrity_guard。

【一次被证伪的假设（记录在此，避免重复走）】
  原先怀疑：signatures 是"一个数组 + 同一拍两个读口"，综合工具可能把两个读口
  "合并到一个口"（或复制不完整），于是 verify_expected 拿到的是"播放查找地址"的签名
  => 第 0 块必然比错、且 EXP 是个确定的非零 CRC。这与实测现象吻合。
  尝试的改动：拆成两个显式独立的 1 写 1 读数组 sig_verify / sig_lookup。
  结果：装不下。TD 在 Stage 2 直接报
        PHY-9013 ERROR: Design's emb number = 85, exceeds the limit 64
        （显式两份 32bit 副本需 85 个 BRAM，器件上限 64；原来隐式版只用 29 个）
  然后用 TD 的 write_verilog 把 board_verify_fbk/base/gate.db 导出为门级网表，
  直接核对 guard 的 29 个 BRAM 实例，发现端口接线完全一致：
        EG_PHY_BRAM  MODE="DP8K"  WRITEMODE_A="READBEFOREWRITE"
          .addra({integrity/second_index[9:0],3'b111})  .csa(second_index[12:10])
          .wea(signature_write)  .dia(integrity/signatures_b)
          .addrb({integrity/add3_syn_3[4:0], checked_read$dma/rd_addr[12:8], 3'b111})
          .csb(add3_syn_3[7:5])  .doa(校验读)  .dob(播放查找读)
  => TD 把它做成了"真双口 BRAM"：A 口同时承担"写 + 校验读"（addra = second_index，
     即 signature_write ? write_index : 校验地址），B 口承担"播放查找读"。
     两个读口各占一个端口，实现是正确的。原假设被证伪，改动已撤回。

【当前保留的改动：SAFEVISION_DIAG_WORDPROBE 字探针（默认位流逐位不变）】
  既然签名 RAM 被排除，剩下的分歧是"签名错"还是"读回数据错"。
  最小改动、不占 RAM、不改报文长度（RPT_LEN 仍 189）：
    · 新增宏 SAFEVISION_DIAG_WORDPROBE（未定义时综合结果与队友交付逐位一致）
    · word_at_base  ：写入阶段当 write_addr==base 时锁存 write_data
    · first_read_word：读回阶段第一个 capture 时锁存 rd_data
    · 首块 CHECK 失败时 bad_expected<=word_at_base、bad_actual<=first_read_word
      （即串口的 EXP / GOT），BAD 仍为块基址 0x000A0000
  判读：EXP == GOT => SDRAM 里存的确实是写进去的数据 => 问题在签名/CRC 侧；
        EXP != GOT => 写入或读回的数据真的不一致 => 问题在存储链。
  已用小 TB 验证（故意只破坏 block0 第 0 个字）：
        verify_done=1 fault=1 checked_blocks=0
        bad_addr=000A0000  bad_expected=5A501234  bad_actual=5A501235  RESULT: 0 error(s)

【请重点审的问题】
  Q1. guard 的 verify_expected 装载时序：从 RETIRE 发起 -> REQUEST -> COLLECT(64 拍) -> CHECK，
      比较时 verify_expected 是否必然是 signatures[slot_base + verify_index]？
      有没有可能慢/早一拍（尤其 A 口同时承担写与校验读、WRITEMODE_A="READBEFOREWRITE"
      的读-写先后语义），导致第 0 块就比错？
  Q2. guard 的签名计算（写入侧 source_crc 链）与读回侧 verify_crc 链都用同一个
      crc32_word 函数；写入侧"第 64 个字"用 `~crc32_word(source_crc,write_data)` 收尾、
      读回侧用 `~crc32_word(verify_crc,rd_data)` 收尾。两侧的"累计 63 拍 + 第 64 拍合并"
      是否严格等价？有没有 off-by-one（例如 source_words 与 response_count 的计数起点差异）？
  Q3. guard 的 accepted/write_addr/write_data 来自
      `accepted = prod_word_accepted && card_mode`、`prod_word_accepted = prod_wr_busy && mem_req && mem_wr && mem_ready`
      （见 platform/safevision_top.v 第 613-614、176 行）。请判断：
      在这个握手定义下，guard 采样到的 (write_addr, write_data) 是否严格等于
      适配器最终写进 SDRAM 的那一对？有没有某一拍 mem_ready 为高、但适配器
      并未真正接收该 word 的可能？
  Q4. 读回侧走的是 core 的 SD 通道（`sd_req=verify_req&&STORAGE_INTEGRITY`,
      `sd_wr=1'b0`, `sd_addr=verify_addr`, `sd_len=64`，见 safevision_top.v 第 633 行）。
      请审 memory_arbiter 的 SD 通道：`responses_left`/`words_left` 的结算、
      `sd_rdata_valid = response_fire && (cur_ch==CH_SD)`，
      在与显示读通道并发时是否可能把 64 拍数据错位/少给/多给？
  Q5. 有没有我遗漏的、能让"整帧写入 100% 但读回第 0 块必错"的确定性成因？
      （已知：多次上下电报文逐字节一致；B=0；BAD=base+0；PH=3）
"""

RTL_SECTION = ("RTL / 存储与校验主路径（按重要性排序）", [
    ("safevision/rtl/memory/frame_integrity_guard.v", "★头号嫌疑：整帧读回校验器"),
    ("safevision/platform/anlogic_eg4s20_hx4s20c/rtl/sdram_app_adapter.v", "★SDRAM 适配器：写缓冲 + 读缓存 + 预读"),
    ("safevision/rtl/memory/memory_arbiter.v", "★仲裁器：读/写/SD 三通道，突发粒度切换"),
    ("safevision/rtl/memory/mem_ctrl.v", "字节地址 -> 字地址 转换"),
    ("safevision/platform/anlogic_eg4s20_hx4s20c/rtl/bmp_frame_sink.v", "帧接收器状态机；F3 错误码来源"),
    ("safevision/rtl/memory/video_read_dma_checked.v", "显示侧块校验（本故障中未报错）"),
    ("safevision/rtl/top/safevision_core/safevision_core.v", "core：把 guard 的 rd_* 接到仲裁器 SD 通道"),
    ("safevision/platform/anlogic_eg4s20_hx4s20c/rtl/safevision_top/safevision_top.v", "板级顶层：全部接线 + 串口报告格式 + 故障锁存"),
    ("safevision/rtl/top/safevision_core/bmp_frame_write_bridge.v", "行序重映射桥"),
    ("safevision/rtl/memory/frame_writer.v", "逐字写（wr_len=1）的产生者"),
])

INC_SECTION = ("头文件", [
    ("safevision/rtl/include/pixel_format_defs.vh", "槽基址 SV_IMG0_BASE=0 / SV_IMG1_BASE=0xA0000"),
    ("safevision/rtl/include/crc32_word.vh", "CRC32 实现（纯组合逻辑，无查表/RAM）"),
    ("safevision/rtl/include/safevision_defs.vh", "其它常量"),
    ("safevision/rtl/include/fault_code_defs.vh", "故障码"),
    ("safevision/rtl/include/event_code_defs.vh", "事件码"),
    ("safevision/rtl/include/video_mode_defs.vh", "视频模式"),
])

TB_SECTION = ("验证 TB（可复现）", [
    ("safevision/verification/unit/tb_frame_integrity.sv", "队友缩小几何 TB"),
    ("safevision/verification/unit/tb_frame_integrity_fullgeom.sv", "真几何 TB：2400/2400 通过"),
    ("safevision/verification/unit/tb_mem_roundtrip.sv", "★本次新增：整条存储链往返（含并发显示读）"),
    ("safevision/verification/unit/tb_wordprobe_check.sv", "字探针行为验证 TB"),
    ("safevision/verification/unit/tb_sdram_app_adapter_streaming.sv", "adapter 预读 TB：22 checks/0 err"),
    ("safevision/verification/models/board_memory_contract_model.sv", "SDRAM 契约模型（16 字突发/16 拍静默）"),
    ("safevision/verification/models/frame_memory_model.sv", "理想行为级存储模型"),
])

CONSTRAINT_SECTION = ("板级约束 / PLL / TD 时序取证（外部 AI 点名要的材料）", [
    ("safevision/platform/anlogic_eg4s20_hx4s20c/project/board_verify/board_b.sdc",
     "create_clock 20ns(50MHz) + derive_clocks —— 时钟口径由 PLL 派生"),
    ("safevision/platform/anlogic_eg4s20_hx4s20c/project/board_verify/board_cdc.sdc",
     "CDC 例外全文：唯一 multicycle 只给 ridx*；末段明写 CRC32 反馈路径按单周期 STA"),
    ("safevision/platform/anlogic_eg4s20_hx4s20c/constraints/timing.sdc",
     "bring-up 顶层约束（同一 create_clock/derive_clocks 口径）"),
    ("safevision/platform/anlogic_eg4s20_hx4s20c/ip/pll/sv_board_memory_pll.v",
     "PLL：FIN=50MHz, CLKC1_DIV=25→MEM 40MHz, CLKC2_DIV=25→SDRAM 40MHz, CPHASE=9"),
    ("code_review_pack_20261010/timing/TD_timing_excerpt.txt",
     "★ TD routed STA 摘录：Clock Summary（含 Max-Level）+ 全部 Path Group + MEM 组最差路径全文"),
    ("safevision/platform/anlogic_eg4s20_hx4s20c/project/board_verify/board_sources.list",
     "板级编译源清单（含 global_def.v 的 ifndef 覆盖顺序）"),
    ("safevision/platform/anlogic_eg4s20_hx4s20c/project/board_verify/td_flow.tcl",
     "TD 综合/布线/STA 流程脚本（含诊断宏透传）"),
])

DOC_SECTION = ("项目文档", [
    ("code_review_pack_20261010/bitstream/探针v4_烧写与判读.md",
     "★★★ 最新状态：v3 板上结果解码 + v4 判读表（当前该看的第一份）"),
    ("docs/B链-红框故障排查交接_20261010.md", "上一轮交接（本次任务的起点）"),
    ("code_review_pack_20261010/02_重大发现_诊断宏从未生效.md",
     "★★ 本轮最重要：SAFEVISION_DIAG_DEFINE 从未生效（TD read_hdl 只认第一个 -define）"),
    ("code_review_pack_20261010/01_对外部AI分析的核对与回答.md",
     "★ 对外部 AI 六轮分析的逐条核对：关闭 4 条、更正 3 处、剩余未取证清单"),
])

EVIDENCE = [
    ("evidence/board/uart_report_wpr3_20261011_hex.txt",
     "★★★ 最新：字探针 v3 板上采集（BAD=末块基址、EXP/GOT/W 全 FFFFFFFF、B=C000）"),
    ("evidence/board/uart_play_status_20261010_1546_boot_to_fault_hex.txt", "主证据：开机->流式->故障 7 包"),
    ("evidence/board/uart_play_status_20261010_1503_PH3_fullframe_hex.txt", "故障态 1 包"),
    ("evidence/board/uart_play_status_20261010_1458_redfault_hex.txt", "早期 1 包"),
]

EXTRA = """\
board_verify_d28（2026-10-06 板上整链通过，无 guard 实例）:
    #bram 20 out of 64 (31.25%) ; #bram32k 0 out of 16

board_verify_fbk（含 guard 实例）:
    #lut     12800  out of 19600   65.31%
    #reg      8312  out of 19600   42.41%
    #bram       56  out of     64   87.50%
    #bram32k     0  out of     16    0.00%
    层次里: |  integrity |frame_integrity_guard | le=1030 lut=926 ripple=104 seq=424 bram=29 |

board_verify_wordprobe（本次字探针位流）:
    #bram 56 out of 64 (87.50%)   timing.gate.json: status=PASS, negative_path_count=0

releases/ab_multiround_26101002/BASE/timing.gate.json:
    "status": "PASS", "timing_passed": true, "negative_path_count": 0,
    "minima": {"setup": {"reported_min_ns": 0.448}}

=> 交付位流时序干净；BRAM 从 20/64 跳到 56/64 完全由 guard 引起。
"""


def read(path):
    with io.open(path, "r", encoding="utf-8", errors="replace") as f:
        return f.read()


def file_block(name, desc, section=""):
    p = os.path.join(ROOT, name)
    if not os.path.exists(p):
        return ("[缺失] " + name, ["[缺失] %s" % name])
    body = read(p).rstrip()
    lines = [SUB, "文件: %s" % name, "说明: %s" % desc]
    if section:
        lines.append("所属章节: %s" % section)
    lines += ["行数: %d" % body.count("\n"), SUB]
    lines += body.split("\n")
    return ("FILE " + name, lines)


def build_blocks():
    """Return [(label, [lines]), ...] in presentation order."""
    blocks = []
    brief = [BAR, "SafeVision  上板\"红框故障\" —— 全部相关代码与说明",
             BAR, ""] + BRIEF.split("\n")
    blocks.append(("说明 / 现象 / 已证明项 / 提问清单", brief))

    ev = [BAR, "板级原始证据（串口 HEX 导出，未解码，可直接核对）", BAR]
    for name, desc in EVIDENCE:
        p = os.path.join(ROOT, name)
        if not os.path.exists(p):
            continue
        ev += ["", SUB, "证据文件: %s   (%s)" % (name, desc), SUB, read(p).strip()]
    blocks.append(("板级串口原始证据", ev))

    for title, files in (RTL_SECTION, INC_SECTION, CONSTRAINT_SECTION, TB_SECTION, DOC_SECTION):
        if title == INC_SECTION[0]:
            # 6 tiny headers belong together; keep them in one block so they
            # never straddle two parts.
            lines = [BAR, "代码区：%s" % title, BAR]
            for name, desc in files:
                lines += file_block(name, desc)[1]
            blocks.append(("区 " + title, lines))
            continue
        # Attach the section heading to its FIRST file, so a heading can never
        # end a part while its files land in the next one.
        for i, (name, desc) in enumerate(files):
            lbl, fl = file_block(name, desc, title)
            if i == 0:
                fl = [BAR, "代码区：%s" % title, BAR, ""] + fl
                lbl = "区 " + title + " >> " + lbl
            blocks.append((lbl, fl))

    blocks.append(("附：TD 资源对比与位流时序门限",
                   [BAR, "附：TD 资源对比（route.area 摘录）与交付位流时序门限", BAR, ""]
                   + EXTRA.split("\n")))
    return blocks


def pack(blocks, target, overshoot=140):
    """Greedy pack into parts of ~target lines, never splitting a block.
    A small overshoot allowance stops a big block from leaving a nearly empty
    part behind it (which otherwise produces very uneven parts)."""
    parts, cur, cur_lines = [], [], 0
    for label, lines in blocks:
        n = len(lines) + 1
        if cur and cur_lines + n > target + overshoot:
            parts.append(cur)
            cur, cur_lines = [], 0
        cur.append((label, lines))
        cur_lines += n
    if cur:
        parts.append(cur)
    # merge a trailing runt into the previous part when that stays reasonable
    if len(parts) >= 2:
        last = sum(len(l) + 1 for _, l in parts[-1])
        prev = sum(len(l) + 1 for _, l in parts[-2])
        if last < target * 0.6 and prev + last <= target + overshoot:
            parts[-2] = parts[-2] + parts[-1]
            parts.pop()
    return parts


def render_part(part, idx, total, title):
    out = [BAR,
           "%s   ——  第 %d / %d 部分" % (title, idx, total),
           "本部分内容：" + " | ".join(lbl for lbl, _ in part),
           BAR, ""]
    for lbl, lines in part:
        out += lines
    out += ["", BAR, "（第 %d / %d 部分 结束）" % (idx, total), BAR]
    return "\n".join(out) + "\n"


def main():
    compact = "--compact" in sys.argv
    split = "--split" in sys.argv or not compact
    target = 800
    for i, a in enumerate(sys.argv):
        if a == "--lines" and i + 1 < len(sys.argv):
            target = int(sys.argv[i + 1])

    blocks = build_blocks()
    title = "SafeVision 红框故障 全部代码与说明"

    KEEP = ("说明 /", "板级串口", "区 头文件",
            "FILE safevision/rtl/memory/frame_integrity_guard.v",
            "FILE safevision/platform/anlogic_eg4s20_hx4s20c/rtl/sdram_app_adapter.v",
            "FILE safevision/rtl/memory/memory_arbiter.v",
            "FILE safevision/rtl/memory/mem_ctrl.v",
            "FILE safevision/rtl/include/",
            "FILE safevision/verification/unit/tb_frame_integrity_fullgeom.sv",
            "FILE safevision/verification/unit/tb_mem_roundtrip.sv",
            "FILE safevision/verification/unit/tb_wordprobe_check.sv",
            "FILE safevision/verification/models/board_memory_contract_model.sv",
            "FILE safevision/platform/anlogic_eg4s20_hx4s20c/project/board_verify/board_cdc.sdc",
            "FILE safevision/platform/anlogic_eg4s20_hx4s20c/ip/pll/sv_board_memory_pll.v",
            "FILE code_review_pack_20261010/timing/TD_timing_excerpt.txt",
            "FILE code_review_pack_20261010/01_对外部AI分析的核对与回答.md")
    use = [b for b in blocks if any(k in b[0] for k in KEEP)] if compact else blocks

    # single big file
    big = [BAR, title, BAR, ""]
    for lbl, lines in use:
        big += lines
    big += ["", BAR, "（文件结束）", BAR]
    big_text = "\n".join(big) + "\n"
    dst = OUT.replace("全部代码与说明", "核心代码精简版") if compact else OUT
    with io.open(dst, "w", encoding="utf-8", newline="\r\n") as f:
        f.write(big_text)
    print("WROTE", dst, os.path.getsize(dst), "bytes", big_text.count("\n"), "lines")

    if split:
        parts = pack(blocks, target)
        if os.path.isdir(PARTS_DIR):
            for fn in os.listdir(PARTS_DIR):
                if fn.endswith(".txt"):
                    os.remove(os.path.join(PARTS_DIR, fn))
        os.makedirs(PARTS_DIR, exist_ok=True)
        print("--- split into %d parts (target %d lines) ---" % (len(parts), target))
        for i, p in enumerate(parts, 1):
            body = render_part(p, i, len(parts), title)
            fn = os.path.join(PARTS_DIR, "%02d_%s_第%d部分.txt" % (i, "红框故障代码", i))
            with io.open(fn, "w", encoding="utf-8", newline="\r\n") as f:
                f.write(body)
            print("  %-52s %7d bytes %5d lines  <- %s"
                  % (os.path.basename(fn), os.path.getsize(fn), body.count("\n"),
                     " + ".join(lbl for lbl, _ in p)[:70]))


if __name__ == "__main__":
    main()
