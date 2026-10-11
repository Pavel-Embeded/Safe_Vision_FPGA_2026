# TD6.2.168116 board bring-up: synthesize/place/route/STA with real pins.
# Target: safevision_top on HX4S20C, HDMI B output, package-in SDRAM.
# Route/report only. A successful Tcl exit means the reports were produced;
# run_board_sta.ps1 performs the separate fail-closed timing gate. This flow
# alone does not prove HDMI electrical behavior or SDRAM AC correctness.
if {![info exists board_mode] || $board_mode ni {base hd}} {error "Select base or hd"}
set here [file dirname [file normalize [info script]]]
set root [file normalize [file join $here .. .. .. .. ..]]
if {[info exists ::env(SAFEVISION_REPO)]} {set root [file normalize $::env(SAFEVISION_REPO)]}
set platform [file join $root safevision platform anlogic_eg4s20_hx4s20c]
set vend [file join $root 7_lab_ex_2026_nosoft example lab_ex4_tf src user_source hdl_source]
if {[info exists ::env(SAFEVISION_HDMI_VENDOR)]} {set vend [file normalize $::env(SAFEVISION_HDMI_VENDOR)]}
set out [file join $root safevision build out board_verify $board_mode]
if {[info exists ::env(SAFEVISION_BOARD_OUT)]} {set out [file join [file normalize $::env(SAFEVISION_BOARD_OUT)] $board_mode]}
file mkdir $out
file copy -force [file join $root safevision assets fonts font8x16.mem] [file join $out font8x16.mem]
cd $out

set hd [expr {$board_mode eq "hd"}]
set video_pll [expr {$hd ? "sv_video_hd_pll.v" : "sv_video_vga_pll.v"}]

set paths {}
set source_file [open [file join $here board_sources.list] r]
set source_lines [split [read $source_file] "\n"]
close $source_file
foreach line $source_lines {
    set line [string trim $line]
    if {$line eq "" || [string index $line 0] eq "#"} {continue}
    set line [string map [list @video_pll@ $video_pll] $line]
    if {[string match vendor/* $line]} {
        lappend paths [file join $vend [string range $line 7 end]]
    } else {lappend paths [file join $root safevision $line]}
}
foreach f $paths {if {![file isfile $f]} {error "Missing source: $f"}}

if {[catch {
    import_device eagle_s20.db -package EG4S20BG256
    # Official TD 6.2 implementation options. Improve actual routed slack
    # without relaxing clock periods or exempting business data paths.
    set_param place effort high
    set_param place post_place_opt high
    set_param route timing greedy
    set_param route fix_hold on
    # read_hdl takes ONE include directory here (a Tcl list shifts the arguments
    # and silently blanks -include_dir). The vendor encrypted HDMI/SDRAM cores
    # resolve their own "global_def.v" from the directory that also holds the
    # .enc.v files, which is why ip/sdram/ and the vendor include/ dir need no
    # extra -include_dir entry.
    # ★ 诊断宏透传（2026-10-10）：env SAFEVISION_DIAG_DEFINE 非空时，把其中的宏
    #   追加到 -define。用于出"关掉存储校验"的二分位流：
    #     SAFEVISION_DIAG_DEFINE=SAFEVISION_DIAG_NO_INTEGRITY
    #   未设置时走原样，综合结果与队友交付**逐位一致**。
    if {[info exists ::env(SAFEVISION_DIAG_DEFINE)] && [string trim $::env(SAFEVISION_DIAG_DEFINE)] ne ""} {
        # ★★ 2026-10-10 修正（有实测证据，见 code_review_pack_20261010/02_*.md）：
        #   TD 的 read_hdl **只应用第一个 -define**，写成
        #     `-define "SAFEVISION_BOARD_HD=$hd" -define "$diag"`
        #   时第二个被静默丢弃（不报错、不警告，TD 日志里甚至会把最后一个回显出来）。
        #   实测（极小设计 + report_area 的 #DFF）：
        #     -define "BASE=0" -define "MY_DIAG"   ⇒ MY_DIAG 未定义（DFF=0）
        #     -define {BASE=0 MY_DIAG}             ⇒ 生效（DFF=64）
        #     -define "BASE=0 MY_DIAG"             ⇒ 生效（DFF=64）
        #   历史后果：此前所有带 SAFEVISION_DIAG_DEFINE 的位流（diag3 / fbk /
        #   nointg / nointg2）**都与正常交付版功能等价**（资源与位流大小逐项相同），
        #   串口抬头当然仍是 `SV-PLAY`。文档里"用 route.timing 字节数不同证明宏生效"
        #   是误判 —— 那只是布线噪声（同一份网表重跑字节数也会变）。
        #   ⇒ 必须把两个宏放进**同一个** -define 参数（空格分隔的单字符串）。
        set diag_define "SAFEVISION_BOARD_HD=$hd $::env(SAFEVISION_DIAG_DEFINE)"
        puts "DIAG DEFINE: $::env(SAFEVISION_DIAG_DEFINE)"
        puts "DEFINE ARG : <$diag_define>"
        read_hdl -file [join $paths " "] \
            -include_dir [file join $root safevision rtl include] \
            -define $diag_define -top safevision_top
    } else {
        read_hdl -file [join $paths " "] \
            -include_dir [file join $root safevision rtl include] \
            -define "SAFEVISION_BOARD_HD=$hd" -top safevision_top
    }
    read_adc [file join $here board_b.adc]
    optimize_rtl
    report_area -file rtl.area
    # ★ 失败即报错：宏没真正进 HDL 时，综合照常通过、位流照常产出，
    #   但上板行为与正常版一样 —— 必须在这里硬失败，不能让它静默溜过去。
    if {[info exists ::env(SAFEVISION_DIAG_DEFINE)] && [string trim $::env(SAFEVISION_DIAG_DEFINE)] ne ""} {
        set diag $::env(SAFEVISION_DIAG_DEFINE)
        if {$diag eq "SAFEVISION_DIAG_WORDPROBE"} {
            if {[llength [get_regs {integrity/blk_w0* integrity/blk_w1* integrity/last_read_word* integrity/fail_cnt*}]] == 0} {
                error "SAFEVISION_DIAG_WORDPROBE did not reach the HDL: probe registers (integrity/blk_w0 ...) are absent"
            }
            puts "DIAG VERIFY : SAFEVISION_DIAG_WORDPROBE registers present"
        }
    }
    read_sdc [file join $here board_b.sdc]
    read_sdc [file join $here board_cdc.sdc]
    optimize_gate
    legalize_phy_inst
    read_sdc [file join $here board_b.sdc]
    read_sdc [file join $here board_cdc.sdc]
    # Required integrity CRC state exists and remains fully single-cycle timed.
    # ★ 2026-10-11 修正：这条断言**只在 STORAGE_INTEGRITY=1 时成立**。
    #   `-define SAFEVISION_DIAG_NO_INTEGRITY`（STORAGE_INTEGRITY=0）时校验根本不会跑，
    #   于是 guard 的 source_crc / signatures 整条链成了死逻辑、被综合优化掉，
    #   `get_regs integrity/source_crc[*]` 返回空 ⇒ 断言失败、构建被挡死。
    #   这正是"作者设计的那个二分（关完整性看能不能出图）从没跑成"的第二个原因
    #   （第一个是 SAFEVISION_DIAG_DEFINE 透传坏掉，见上面的长注释）。
    set _diag_env ""
    if {[info exists ::env(SAFEVISION_DIAG_DEFINE)]} {set _diag_env [string trim $::env(SAFEVISION_DIAG_DEFINE)]}
    if {[string match "*SAFEVISION_DIAG_NO_INTEGRITY*" $_diag_env]} {
        puts "INTEGRITY OFF : STORAGE_INTEGRITY=0 -> CRC-state assertion intentionally skipped"
    } else {
        set crc_names {}
        for {set i 0} {$i < 32} {incr i} {lappend crc_names [format {integrity/source_crc[%d]} $i]}
        if {[llength [get_regs $crc_names]] != 32} {error "Incomplete source CRC32 state collection"}
    }
    if {[llength [get_nets {core/display/fetch/fifo_reset}]] == 0} {error "Missing preserved FIFO asynchronous assertion net"}
    update_timing -mode basic
    report_timing_summary -ep_num 30 -file gate.timing
    export_db gate.db
    report_param -detail -stage place -file place.params
    report_param -detail -stage route -file route.params
    place
    route
    update_timing -mode final
    report_timing_summary -ep_num 100 -path_num 3 -file route.timing
    report_timing_status -file route.status
    report_clock_summary -levels 20 -expand_buckets -debug -file route.clocks
    report_timing_exception -file route.exceptions
    check_design
    check_timing -verbose -file route.check
    report_area -io_info -file route.area
    export_sdc -file route.derived.sdc
    export_db route.db

    # Route/report only. run_board_sta.ps1 validates these final reports before
    # a separate import_db/bitgen invocation. Environment flags cannot bypass
    # that gate inside this flow.
} err]} {puts stderr "BOARD TD FAILED: $err";exit 1}
puts "BOARD TD ROUTED mode=$board_mode (inspect timing/I-O health before any programming)"
exit 0
