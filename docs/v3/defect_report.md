# 错误检查与修正记录

以下区分存量代码缺陷、原始工程配置问题及本次新增模块调试中发现的问题。每项均给出触发条件和防复发入口；最终是否通过以匹配源码的原始日志为准。

| 编号/来源 | 触发条件与原行为 | 修正方式 | 验证证据入口 |
|---|---|---|---|
| D01 原始 GUI 配置 | 本地 `.al` 移除三个 HDMI 源文件、含绝对路径，GUI 和脚本可能综合不同依赖 | 保存原文件与 SHA-256；V3 独立生产清单/模式工程，HDMI 依赖入板级 IP 目录 | GUI/CLI 源清单比对、TD elaboration |
| D02 存量 SD 错误码 | 数据 CRC16 错误只拉 `crc16_err`，`err_code` 仍为 0，某些上游只检查错误码而漏报 | 同时输出 02/22；V3 用完整扇区暂存器，在 CRC 确认前不向解析器发布任何字节 | checked_sector 好/坏/好、final_crc 尾扇区注错 |
| D03 存量事件输出 | 错误队列只有写入与队头，缺少下游消费握手及时间戳 | `evt_ready` 消费、`evt_ts` 出队，满队列丢失计数饱和；UART 事件回执保留源/码/毫秒 | recovery_events 1000 次、uart_link 队列并发 |
| D04 存量故障升级 | 先 WARNING 后 SAFE/FATAL 时首因锁存阻挡后续严重等级 | 保留首因/时刻，当前等级可升级；FATAL 全局复位才清，恢复 ACK 与新错误同拍时不清 | fault_manager 1000 轮、5012 断言 |
| D05 存量恢复握手 | 等待旧的 sticky watchdog 先清再接受配对 clear，可能互相等待 | 恢复动作与 watchdog 清除在同一拍配对；新错误仍阻止清除 | 配对清除与 recovery_ack 破坏负控 |
| D06 存量播放状态机 | 把历史 scan_done 当预取成功、部分恢复/转场无界、BOOT 应急可能被忽略 | 四图合法缓存、真实 preload_ok、全状态报警；复位/释放/重扫有界，失败 SAFE | playback_fsm、recovery_events |
| D07 存量报警切换 | 用 256 个采样点代替 48k 下 5ms 所需的 240 点 | 分数步进恰好 240 点到达目标增益，端点无回跳 | C audio / energy_acr |
| D08 新增常驻扫描 | 前四候选均坏，或目录候选超过 4 个；只看一批会误报没有可用图 | BCD 游标跨批次重扫，按已处理最大编号推进；冻结当前候选，四槽只存合法文件 | resident 四坏后四好、碎片链、独立 Pillow 核对 |
| D09 新增文件收尾 | sink 先完成但 streamer 仍在吃 BMP 尾部/扇区填充，下一 start 被忙状态吞掉 | 等 sink 完成、streamer done、扇区与 SPI 空闲；坏文件 drain→clean 后再开始 | resident 全 614400 字比较、无 SD 重读 |
| D10 新增读回/缓存 | 仅读首个 burst 时，第二至第五 burst 的错误可能通过 | 每行 320 字、64 字×5 burst 完整 CRC32；同步标签口注明 1 拍 | row_integrity 第 73 字故意破坏 |
| D11 新增视频数据 | 非转场目标 RAM 未初始化，alpha=0 仍有 X×0 污染 | 未用的前景显式置零；所有行需 valid/tag/CRC 后才有资格输出 | BASE/HD 完整逐像素帧、CRC 禁用负控 |
| D12 新增按键/命令 | 组合长按松开泄露 NEXT/AUTO；空参数、单负号、重复 ? 被误收 | 整组手势消费到双键释放；严格语法/XOR/范围/超时；出错无配置副作用 | controls、uart 1000 字节、uart_link 108 个回执 |
| D13 新增 WAV/环缓存 | inactive 轨预取暂停会误触文件超时；新代控制先于数据到达造成伪欠载 | 仅安全扇区边界暂停；新代最多 800 tick priming，首个匹配样本即撤销宽限；运行欠载正常累计 | WAV 长暂停、ring540、system2700、underflow1548 |
| D14 新增 WAV 目录 | checked-sector CRC 错误不等于目录格式 dir_bad，可能误把不完整目录当成功 | 同时检查 scanner.err_code，目录失败整组降级，单轨失败只降级该轨 | audio_wav_errors300 比较 |
| D15 新增验证模型 | media_reset 后仿真 SD 模型仍握旧扇区，导致恢复假死 | 模型和真实 reader 一致丢弃旧媒体 epoch；保留失败日志，不把超时算 DUT 通过 | audio_v3_current FAIL → audio_v3_final 正常完成 |
| D16 新增验证证据 | RTL 在长仿真中变化时，测试虽结束为零错仍不能代表最终源码 | 每个用例开始/结束比较源、include、资产、TB、清单和 runner SHA-256，变化一律失败 | resident_async_final 被拒绝复用，checked_release 重跑 |
| D17 新增顶层装配 | 视频仲裁水位常量为 0 会在无 DMA 时也永久预留总线；综合把永不工作的 BMP 写入和音频链裁掉，造成虚假的低资源结果 | 水位由真实 dma_busy 驱动，空闲释放写入/音频；补全顶层装配动态合同 | board_top 公共读写与物理 App 存储比较；shared_memory 并发测试 |
| D18 新增字体工程依赖 | TD 相对源文件解析初始化路径，裸 font 文件名可能导致实际 ROM 未初始化 | 显式绑定 compact 字体与字符 ROM 路径；所有资产进入 GUI/CLI 清单和 SHA；缺初始化 CRITICAL-WARNING 使构建失败 | layers 2635 独立字形比较、TD 日志与资产对账 |
| D19 新增 CRC 资源 | 预加载读回与显示查询两个独立读口让 TD 复制出分布式 RAM，增加约 8930 等效 LUT | 两者生命周期互斥，共用一个同步读口；显示查询在读回期间无效，保持完整 CRC32 | row_full_geometry 四槽 640×480、1920 行逐一对照 Python zlib，含末字注错、超时和越界 |
| D20 新增共用内存带宽 | 分别测视频和音频无法发现 40MHz 共享物理 App 总线在双图 HD 时的行截止时间失败 | 两行预取、交错读当前/目标行、每行 CRC 后发布；V3 专用 50MHz 配置需独立生成和时序验证 | shared_memory_interleaved：40MHz 明确失败；50MHz 5529600 邻点、799 PCM 对、2395 次模型刷新，零错；非实体 SDRAM AC 证明 |
| D21 存量 BMP 长度溢出 | bfOffBits=0xfffffff0 与 921600 相加发生 32bit 回卷，错误地通过头部范围校验；原始 directed test 精确复现三例错误 | 加法两端显式扩展到 33bit，比较保留进位；不缩小合法文件字段范围 | bmp_extent_fixed_final：265 组边界/随机字段、668 检查；原始版本 errors=3，恢复原式的隔离负控必须再次捕获 |
| D22 新增音频 ready/valid | 串行 FIFO 只在第三个 16bit word 接收时给 ready；环缓冲却在 ready 先高后才发读，双方循环等待 | 预留输出槽且水位<240即发读；读回后 valid/data 一直保持到最终消费，不依赖 ready 先高 | audio_nocopy_final3 完整 11 项、ring 消费者先等 valid 与反压保持断言、system2700 |
| D23 新增目录缓冲资源 | name/attr/clus/size 同时保留 raw 与 published 两份寄存，重复约160bit/实例 | 只在 ent_valid 无效时组装输出寄存，valid 等待期间拒绝新字节；接口有效语义不变 | directory_compact_candidate_r2：100扇区、68902原始字段与逐周期对照；legacy_b_compact_directory28项/672断言（后续BMP修改仍需最终回归） |
| D24 新增轮播配置 | 自动播放已累计10秒时把周期30秒改为2秒，旧32bit秒计数继续12、17……，只有回卷后才可能再次等于新阈值1，长时间不再切图 | 发现 period_select 变化即重启秒/周期计数；新周期从新计时窗口开始，至多1个SYS采样延迟；所有hold/cycle/seconds计数按可达上界精确收窄，不改变计时分辨率 | tb_v3_controls_period：旧源码正常结束errors=2（不能算通过），修正版3项通过；原controls29项通过；独立同开关模块面积931→880等效LUT、265→235FF，非整板布线结果 |
| D25 新增解析器资源 | 已验证的命令字段另复制一整组输出寄存器，十进制更新保留不必要的32bit宽度 | 字段仅在command_valid时从组装寄存器发布；合法数值最大9999999，使用24bit十进制运算及参数化超时位宽。最终保留常数乘法表达式：显式shift/add虽在模块测量省2DSP，同路径整机却增加216等效LUT | parser_digit_seen_reference：53212次逐拍旧实现与独立数字/查询参考比较；parser_digit_seen_uart_saved：UART1000及108回执。同路径HD组合multiply18648、shift18864等效LUT，两者均未达到80%资源门槛，不能称发布通过 |
| D26 新增约束执行 | TD read_sdc延迟解析，自定义过程包装未可靠执行create_clock/集合检查；日志文件也在实际执行前关闭，原对象表可能只有表头 | 生成完全展开标准SDC；普通Tcl单独检查当前网表48组对象；最终校验实际Total/Dominated/Shadowed/Ignored路径 | 已布线PLL探针：标准SDC的1ps负控命中2/2路径且setup=-1.160ns；原包装漏时钟并产生internal-clock警告，均保留原始报告，不算整机STA |
| D27 新增解析器数字状态 | 4bit数字计数在16个前导零后回到0，合法`A:BRIGHT=0000000000000000`被拒，非法`A:BRIGHT=0000000000000000-1`反被接受 | 语法只需知道是否已有数字，改为不会回卷的digit_seen位；保持24bit数值及32字符长度限制 | parser_digit_seen_original_negative正常结束errors=7；修正候选32项独立检查通过，包括正负前导零、32字符恰好/超限、嵌入负号、空参数、9999999/10000000边界。该专项进入v3必需回归；负控删除数字存在状态必须被捕获 |
| D28 新增 FIFO 复位跨域 | sv_async_fifo 把公共原始 rst 组合到 rd_valid/wr_ready，REF 域复位释放沿可经 PCM 有效信号直接进入 AUDIO 计数器 CE；整机预布局报告显示 0.020ns 异步窗口与 -8.648ns 建立时间 | 仅删除两个冗余原始 rst 组合门；保留厂商 FIFO 原始复位输入、写侧 wr_rst_done、读侧本域同步复位的 empty/valid，不对功能 CE 添加 false path | 同字节候选 audio_complete 11/11；裸消费者不复位且停读钟的 18 项、带槽标签 5139 值、真实共享内存模型 5529600 邻点/799 PCM/2395 刷新均正常零错；最终整机 routed STA 仍须重做 |
| D29 存量 WAV 容器解析 | 原算法把 fmt_size 截为低5位，合法48/64byte扩展fmt被拒；data长度3/5未检查完整stereo frame；byte_cnt+1+data_size的32bit加法回卷，使FFFFFFFC声明先泄漏PCM再在EOF报错；DATA后的W_END不再收字节，合法尾部chunk可堵住file_streamer | 隔离候选以111bit持久状态重构：共用字段/PCM装配word、逐字段检查后丢弃已知头字段；用加宽长度校验和RIFF剩余预算，拒绝零或非4倍data；跳过完整fmt扩展及奇数填充；继续处理data后chunk并排空RIFF外物理尾部。旧wav_parser与v3_wav_parser_ctx保留公共端口/445bit布局作最小修复，已在B冻结解除后推广；紧凑V3核心与FS136共18word上下文已按同路径资源对照推广到V3共享内核，旧公共接口继续保留 | wav_bound_original准确复现5缺陷，诊断PASS不算功能正确；188文件独立struct/标准库wave oracle，8689PCM+188完成检查通过；旧445bit最小修复的两种接口188oracle各8877检查及5音频68502通过，紧凑WP叠FS136的18word上下文同5项68502通过；新生产冻结版完整11项共71180次严格PCM比较、1548欠载观察正常结束；六组严格负控均正常结束并明确检出，源与资产保持。随后目录SV压缩的五项68502比较已通过；原B28/670汇总经原始日志审计作废；legacy_b_strict_final已正常完成28项/672检查且逐28原始日志复审通过。guarded真实SPI前次中断无结束/退出证据，仍未通过 |
| D30 存量报警斜坡参数 | RAMP_N=1时step=256，gain已为256时，9bit加法256+256回卷为0，持续报警反复回到WAV而非保持满增益 | 只将饱和比较的加法两端扩至10bit；保持原混合乘法结构和输出延迟。默认240样本斜坡不改变 | priority_single_tick_original_negative正常结束30425项错误；priority_saturation_saved在RAMP_N=1/240/1025、随机24bitPCM、正负满幅、valid气泡和复位下600040项独立64bit数值/原版逐拍比较零错；进入C必需清单及饱和进位负控。差分乘法资源实验因整机增加358等效LUT未采用 |
| D31 新增限定媒体目录资源 | 应用只接受SVdddd的BMP/WAV，但共享目录核仍保存完整11字节名字 | 新参数SV_MEDIA_ONLY默认0保持通用8.3枚举；仅V3共享服务设1，用16位数字及扩展位保存并重建完整88位名称，不缩窄簇号/长度/槽号 | directory_sv_production_final：参数1的1000扇区13890独立字段检查；参数0的68902旧实现逐拍比较；两个目录专项均正常结束且当前源SHA不变；原B28汇总发现两个测试台失败后已撤销，严格重跑另列。目录优化单变量HD18700→18590等效LUT，仍超80%门槛 |
| D32 新增初始化测试台观察周期 | quiet-CS模型正确在CS拉高时清零事务内ACMD41计数，旧T1却到44ms UART完成后才读取它；总命令累计6但事务计数0，被误判没发41 | 以o_cmd_valid独立累计历史，明确检查0/8/(55,41)+/58/17的次序、ACMD次数及读LBA；保留原事务计数作诊断，不改冻结DUT/卡模型 | 原始B日志T1正常finish但FAIL；legacy_b_strict_final完整28项/672检查正常零错，T1独立累计6命令/1次ACMD41，事务内旧计数0仅作诊断 |
| D33 新增WAV测试台新帧握手 | 旧测试先武装新文件再start；成功解析器W_END现在会排空物理尾部，提前消费新文件首字节R，使非PCM测试得到RIFF错误71而非格式错误72 | source valid为0时先start新解析epoch，再启动字节源；刺激在时钟下降沿改变；全部31条原数值/错误码断言保留 | wav_start_diagnostic确证idx0/state6消费R、随后T12 detail71；wav_start_fixed原31项全部正常零错，未改生产WAV解析器 |
| D34 新增验收工具漏失败 | 旧PS汇总将两条真实FAIL算通过；同一原始字节在Windows PowerShell默认Get-Content下锚定FAIL匹配false，显式UTF8为true。通用Python runner另漏掉带MODEL前缀的FAIL | B脚本显式UTF8并任意位置FAIL检查；Python legacy wrapper在整套结束后独立逐28原始log复核；证据清点器也独立检查正常finish、FAIL/SKIP/Fatal/错误数，不能信任汇总JSON | 原B结果保留并标记审计撤销；原生prefixed-FAIL哨兵旧runner返回0而隔离修正返回1；三份生产runner已修正，current_runner_sentinels六个原生正常结束测试证明三正控接受/三前缀FAIL负控拒绝；统一raw自测16项及实际两伪PASS重审均拒绝 |
| D35 新增证据元数据变量复用 | 生成资产扫描循环复用了测试top变量，使表格top标签变成generated文件名；补raw审计时被自测准确拦截 | top_name独立不可复用，源/资产循环各自命名；生成资产用例明确断言top保持tb | evidence_raw_log_selftest_r2完整18边界通过，包含伪PASS原始日志与缺finish拒绝；此项不是RTL故障 |
| D36 新增例外路径验收缺口 | TD主route.timing不包含部分MCP详细负路径，错误MISO/MOSI预算可能只在route.exceptions中暴露 | 审计全部MCP/SMD详细slack和汇总负值；路由后独立进程STA绑定数据库/约束SHA，比较404普通与16例外路径的角/组/边沿预算/逐路径裕量；正式健康报告在clock_summary诊断前生成 | 小探针四项原生负控正常结束并检出：缺时钟、MISO -6.190ns、MOSI hold -7.499ns、CS -1.600ns；37+31工具自测通过；这些不是完整BASE/HD签核 |

| D37 新增FPS饱和进位与PLL标尺 | 帧计数已饱和255时，恰在秒边界再来一帧使8bit FPS由255回卷0；板级PLL实际名义BASE为680000000/27 Hz、HD为222500000/3 Hz，HUD原来仍用标准25.175/74.25MHz标尺 | FPS秒边界加法先饱和；秒计数宽度由PIXEL_HZ推导；通用显示核显式接收PIXEL_HZ，板级按官方PLL计数器四舍五入传入25185185/74166667。HD接口模型半周期按真实配置名义值量化至1ps；标准通用默认保留 | 私有独立整数oracle 16396比较正常零错，旧原件负控正常结束3075错误；推广后的FPS两项、双模式TOP参数/预置终点专项、TOP装配、BASE/HD音频两项已正常结束通过。五种PLL/SDC/参数链漂移全部被独立检查器拒绝。完整输出帧与最终资源/路由验收另计，不把本项当成物理PLL验证 |

| D38 新增FAT地址资源 | 对1..128的8种合法SPC采用8路32bit并行移位选择，重复存在于目录和共享文件内核 | 用1/2/4bit三层移位选择，显式检测SPC为非零单bit值；其他全部SPC仍返回0。保留32bit模运算、公开端口和所有状态机 | 全256SPC/每位/随机数234304比较正常通过；移位2改3负控正常结束检出。area_prior/ripple64同路径整机BASE 17374→17286、HD18117→17957 LUT，RAM/DSP不变；推广后A5/B28/系统/目录/几何已正常通过，真实SPI联合重测与最终物理门槛仍待完成 |

| D39 新增HD测试台结束标签 | `%s` 的 `HD?"hd":"base"` 为不同宽度的打包字符串，HD分支被补成带前导空格的 `  hd`。两次HD虽逐像素零错并正常finish，严格runner因缺少精确top结束标记正确判失败 | 只把最终输出改为HD/BASE两个字面量分支；全部像素、帧数、32帧Fade、超时和失败规则不变。保留原始FAIL结果，重新跑完整两模式，不以人工解释覆盖FAIL | current_100_20261016/rejected_hd_completion保存失败原件；video_final_base/hd为新执行，分别2150400/6451200像素、各7个完整输出帧正常结束零错。此项为测试台标签缺陷，不是HD像素算法缺陷 |

| D40 新增隔离构建依赖遗漏 | 音频runner始终登记gen_v3_audio_fixture.py，但原audio_complete/audio_v3清单未显式声明它。只按清单复制的候选快照缺文件，在仿真开始前失败；整个候选不能算通过 | 两份清单显式添加generator_dependencies，不改生产RTL、runner或断言；保留缺文件快照，另建完整快照。正式源码重新执行11项完整音频、6项子集及6项负控，候选另行检查 | current_100_20261016/audio_complete为11项新回归；negative_audio六个正常结束负控全部检出。子集是补充运行，不加到100个不重复正向top中。Alpha/descriptor候选的18项音频修复回归通过；FS104候选另触发旧18字上下文覆盖断言，仍不算通过或生产缺陷 |

时序检查还需实际 TD 报告。多驱动、位宽截断、未用输入、地址越界、CDC 和例外约束按最终 elaboration、综合日志和匹配路径审计补充；不以静态阅读替代工具结果。


| D41 物理诊断发现的 CDC 范围遗漏 | PIX 域 presentation_fault 经 present_s1/present_s2 两级进入 SYS，但 first-stage 清单遗漏 present_s1；BASE 放置诊断出现 0.294ns 异步采样边沿预算和 -0.959ns 路径 | 只加入 video/present_s1，单独审计首、次级各1对象；次级继续正常 setup/hold。没有屏蔽 PIX/SYS 整个时钟域 | resource_102_20261016/presentation_cdc_scope：BASE/HD 原生对照，旧范围首级/次级各2条路径；正确范围0/2；故意屏蔽次级负控0/0。属于范围证明，未替代 routed STA |
| D42 物理诊断发现的 GPIO 组合路径 | 状态/失锁选择逻辑直接驱动 LED/UART，放置诊断 LED 最坏约9.044ns，超过原5ns传播预算 | 在独立50MHz REF 域发布 LED 与 UART 输出，增加一个20ns参考时钟周期；REF继续支持 SYS PLL 失锁后的 FATAL 输出，不放宽5ns约束 | 当前102项中选用新顶层/双模式时钟/串口测试，包含独立 FATAL 的 F/A/T 字节。实际PAD寄存器数8→13；最终5ns传播与全角时序仍以新路由报告验收 |
| D43 新增命令 ROM 的网表定位检查 | TD 将 generate 层次导出为 uart/g_catalog$parser，初版checker只接受斜杠形式，正确ROM被严格拒绝 | 明确支持TD实际生成的这一层次，仍逐字节比较三个1024字节ROM，不按层次数量或综合完成标记跳过检查 | current_three_rom_check/portable证据：3072字节完全比较；9项来源/缺失映射负控通过；原 FAIL 清单与校正后独立读回分别保留 |
| D44 本次私有回归汇总路径 | 旧A runner实际写 native/top/xsim.log；新增汇总器误查 top/sim.log，将已通过的5项记成失败 | 独立读取runner记录的五个实际原始日志并比对源码，补跑未启动的B28；不覆盖原失败汇总 | resource_102_20261016 的标准化原始sim.log、每top源指纹与独立portable_audit。原生A退出0、五日志正常finish；私有编排器FAIL不被冒充RTL缺陷 |
