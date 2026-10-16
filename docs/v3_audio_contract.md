# V3 音频链的接口、资源与验证边界

本文件描述生产模块 `v3_audio_system`。源代码、RTL 仿真、资源综合、整机路由时序、厂商加密核内部和实体硬件分别验收；此说明本身不是上板或时序通过证据。

## 时钟、复位与原子跨域

生产时钟为 REF 50MHz、SYS 100MHz、MEM 50MHz、AUDIO 12.288136MHz、PIXEL 25.2MHz 或74.25MHz。独立音频接口回归仍使用MEM 40MHz，目的是验证握手和顺序；生产50MHz的实际共享负载由整机压力用例单独验证，不能拿直连内存模型代替。

所有时钟域均采用同一个原始复位断言事件、异步置复位、两级同步释放。`media_reset` 仅清SD/WAV上下文、媒体FIFO、环形指针和媒体提交邮箱。采样节拍、ROM音源、报警斜坡、HDMI样本与ACR属于global reset组，因此媒体恢复期间报警音继续。板级顶层必须在媒体复位时清除尚未提交的旧 `commit_pending`。

描述符和统计量通过 `video_cdc_mailbox` 原子传递。邮箱的 `dst_data` 本身是保持寄存器，整组同拍更新；消费者直接使用这份已保持的数据，不再复制第二组多位寄存器。新数据尚未到达时保持复位值或上次完整描述，不把多位总线逐位同步。三条样本跨域路径都使用官方TD参数化FIFO，打包/拆包逻辑只在各自本地域运行。

## 完整目录与一套共享解析内核

REF域遍历完整FAT32根目录，直接用四个已缓存BMP的四位BCD标识匹配 `SVdddd.WAV`。`cache_keys[15:0]`对应slot0，最高有效编号9999不受八个候选表容量限制。目录、文件和簇链采用现有scanner/walker/file_streamer算法；目录CRC错误必须同时检查 `scanner.err_code`，不能仅检查只代表结构错误的 `dir_bad`。

四个轨道共享一套file_streamer、WAV parser和cluster walker，保留各自文件位置、RIFF状态与跳簇计数。只在一个512byte扇区结束、没有待消费字节/完整PCM对、没有活动读卡事务后切换上下文；RIFF/PCM内部可以处于半个样本状态，这些字节会保存。未运行的轨道不会消耗活动SD事务的超时预算。每条文件结束后从头循环；离开图像时保留该轨队列读进度，返回该图像时继续消费队列。

接受格式为PCM code1、双声道、48kHz、16bit，未知chunk按长度跳过并处理奇数字节填充。输出每对样本为 `{right[15:0],left[15:0]}`。缺WAV、非法格式或单轨IO失败只让对应槽回退ROM提示音，其他合法轨继续。

### 上下文RAM的精确布局

每轨上下文279bit，补齐到288bit，使用18个16bit字。四轨地址分别为0…17、18…35、36…53、54…71，最高地址71小于官方16×256单口RAM的256字容量。布局为低111bit的WAV状态、随后136bit的文件持久状态、32bit的簇链hop计数、最高9bit填充。

SAVE时执行内核停止，按最低16bit到最高16bit顺序写官方SP RAM；每写一个字，借用LOAD接口将完整288bit状态循环右移16bit，18次后逐位恢复原状态。因此SAVE期间中间寄存器值不是功能状态，所有SD/PCM输出必须关闭。LOAD时直接把已有内核寄存器连成288bit移位链，每次固定右移16bit并从最高位插入一个RAM字，18次后恢复完整状态；不另存288bit staging副本。装载期间PCM有效、文件请求和walker_start均关闭，全部字到齐才重新RUN。媒体复位清上下文有效标记；RAM内容可保留，但没有有效标记的槽只能从复位状态重建，不能读取旧epoch内容。

## 三条无损样本FIFO与完整扇区储备

REF→MEM采用单只官方16bit、AW10共享异步FIFO，可用1023个word；每对PCM32按左16、右16、2bit槽标签加14bit零填充，共三个word无损传输。上游valid/data保持至第三word接受；MEM输出完整PCM与onehot槽号，消费整对才弹出第三word。只有一个WAV执行内核，因此进入共享FIFO的槽标签与PCM顺序天然串行。

新的SD扇区只在没有半包且写侧字数不超过632时授权，至少剩391字，保留完整128对PCM所需384字及7字保守余量；不能依赖MEM及时消费才容纳整扇区。停止MEM读钟专项在边界水位继续写入完整128对，最终1015字仍正确。共享FIFO存在队首阻塞，因此生产默认PREFETCH=800的容量界限也属于接口：单轨上界保守为928预取阈值+342对共享FIFO+128对活动扇区+16对邮箱滞后+1对在途写<1415，远低于每轨16384对。独立整链另断言每轨不超过1440；任意改变预取或暂停策略均须重新证明该界限。

MEM→AUDIO传递40bit的 `{generation[7:0],PCM[31:0]}`，按三个16bit字无损写入官方16bit、AW10 FIFO，最高word未用的8bit置零。写侧保留原始valid/data到第三word接受；读侧把generation字留在FIFOhead，直到AUDIO消费整对。环形读DMA只在保守估算水位低于240对时再发请求，为在途响应留出余量。

AUDIO→PIXEL仍是三个16bit字传递完整48bit左右PCM24。此处上游是单拍采样脉冲，因此保留一份48bit pending，并在接受前一次预留三个空word。两端打包状态与官方FIFO使用同一个global复位epoch；媒体复位不清这条通道。

## SDRAM环形队列与音画提交

AUDIO_RING共256KiB，四个64KiB分区起点为 `0x00280000`、`0x00290000`、`0x002A0000`、`0x002B0000`，每分区可存16384对PCM。读写指针独立，按逻辑字节地址访问。`req`保持至`ack`；`ack`仅表示仲裁接纳，地址和写数据保持到`busy`完整结束。写完成才增加计数，真实`rvalid`才推进读指针。单次长度恒为1个32bit word，不能用grant猜测物理写入拍。

SYS域 `target_valid/target_slot/target_generation`是准备描述。目标槽已有至少800对PCM，或完整扫描后确认缺失/非法应回退ROM时，才返回同generation的 `media_ready`。视频在帧边界提交，板级把slot/gen寄存并保持 `commit_valid` 至 `commit_ready`。MEM与AUDIO经原子邮箱接收描述；旧generation样本快速丢弃，只有匹配新generation的完整对能播放。

读DMA以空闲的单对输出寄存器和240对水位上限预留容量，然后发读；不能把消费者ready先高作为产生valid的前提。串行FIFO只在最后一个word接受时ready握手，若读取端也先等ready，会形成循环等待。环形单元测试明确让消费者先等valid，并检查背压期间valid/data保持，整链同时检查该情形。

新generation允许最多800个采样节拍等待首个匹配对，期间输出确定的零样本。收到首对后即进入运行状态，后续空节拍是真欠载；首对迟迟不来而超过窗口，也必须累计故障。不能永久用启动静音隐藏失败。恢复后重新加载并提交新generation，音频源、环形队列与上下文都从新epoch起步。

## 满幅度、音量、报警音和HDMI ACR

PCM16到PCM24采用左移8bit，保留满幅度。ROM报警音优先，240个采样节拍完成5ms权重斜坡。音量0…100%按有符号PCM24乘音量再除100，向零截断；一套30bit shift-add/restoring核心先处理L再处理R：每声道7拍乘法和30拍除法，共74个后续AUDIO边沿完成双声道。输入左右声道、符号与百分比在接纳边沿完整捕获；乘积上界8388608×100小于2^30，负数按绝对值求商后恢复符号，向零截断。一般路径最小接纳间隔75周期，生产固定每256周期一对；0和100%仍为精确的一拍旁路。busy时新输入触发明确overrun断言，不静默丢样。

实际采样频率为12.288136MHz/256≈48000.53125Hz。HDMI固定N=6144，在PIXEL域实测48个实际样本间隔得到CTS；没有用理想常数掩盖PLL频率差。1024对样本窗口统计双声道平均绝对值强度，归一化0…100%，快速上升、按差值八分之一衰减。能量、欠载、溢出通过一组71bit邮箱返回SYS。

## 验证入口与证据口径

总清单为 `safevision/build/manifests/audio_complete_sim.json`，正常运行11项：ring、WAV、坏WAV、整链、启动/真欠载、精确音量、半样本上下文、坏簇链上下文、HDMI48打包、REF ingress32打包、generation40打包。每项保存source/TB/include/assets/generator/manifest/runner的SHA-256，结束后重新计算；源变化、工具崩溃、缺结束标记或任一失败均不算通过。

上下文覆盖特意使用1byte JUNK加填充，使PCM起点为54而非56，四轨都在扇区边界保存phase2的半个stereo样本；检查全部4×18个RAM字和最高地址71、9999高编号、EOF循环及反压。另将最高槽簇链改成19→23→19，其他三个好轨不断正常循环并重置各自walk epoch；必须在坏轨自身hop超限后fallback，其他轨继续，证明共享walker没有把别轨清零当作坏轨计数清零。

负控执行器 `run_v3_audio_negative.py`只改隔离副本：破坏generation标签、交换左右声道、清除保存的hop上下文，要求独立测试命中相应具体断言。不能把编译错误或工具崩溃算作发现逻辑错误。

历史报告分别保留：原5项 `audio_v3_final`；共享内核6项 `audio_resource_final2`；8tile及中间10/11项 `audio_compact_complete` / `audio_eight_complete`。去副本版首次完整运行 `audio_nocopy_final` 发现上述真实valid/ready死锁，`audio_nocopy_final2` 被外部中断，均不计最终通过。修正后的 `audio_nocopy_final3` 11项全部正常结束、零失败，共71180次严格PCM数值比较；欠载用例另有1548次样本节拍观测，不能当作逐值PCM比较。`audio_nocopy_negative` 三项负控均命中预期具体断言，分别检测generation破坏、左右声道交换及hop上下文丢失。每项源码before/after哈希相等；这些报告对应历史去副本快照，2026-10-15 21:17共享服务与tag FIFO推广后需要新快照重新回归。

独立audio顶层原生TD综合已证明8个RAM9K tile的映射：ctx SP1、ingress4、sample2、HDMI1。单独顶层把所有内部接口暴露成633个端口，IO超量属于测量壳，不是可上板设计；资源数用于优化评估，不能代替真实板级top的容量、布局布线、Slow/Fast setup/hold/recovery/removal和约束健康检查。

去副本资源测量 `audio_nocopy_area` 为6484等效LUT、3817层级FF、8RAM9K、6DSP，相对同壳上一版6759/4540/8下降275等效LUT和723FF。该测量早于最后一行ring握手条件修正，不能作为最终快照的精确容量或时序签核；最终整机必须重新综合并绑定最终源码哈希。

实体SDRAM/SD长期稳定性、加密HDMI核内部、显示器/接收机兼容性、音频实测和实体长期运行仍按整机交付总表独立验收，不能从离线模块测试推出首次上板绝无错误。

## 2026-10-15共享服务推广与后续验证边界

21:17已按已验候选逐字节推广：sd_bmp_player共享服务参数默认0、resident单最小候选索引；v3_wav_source旋转SAVE与EXTERNAL_SERVICE默认0；v3_audio_system共享tag ingress；新增v3_shared_fs_service与v3_pcm_ingress_shared_fifo。BMP预加载和WAV播放生命周期互斥时共用一套scanner/file/walker，REF域445bit command、837bit response保持同域。owner改变后至少两次REF边沿保持服务复位/ready低/rsp零，清除原扫描done。正式top由板级层打开SHARED_SERVICE=1和EXTERNAL_SERVICE=1，文档不会代替实际顶层连线核查。

共享服务独立真实SPI测试shared_fs_spi2正常完成614400个BMP32bit字和24000对PCM；ROOT叠加旋转与单候选索引的v3_storage_combined_full同样正常完成614400+24000、1721.984秒。tagged ingress候选shared_ingress_audio2五项共68502次严格PCM数值比较，专项shared_ingress_fifo3共5139比较。它们证明各冻结候选，推广后完整整机仍需要新快照验证。LBA共享运算候选shared_lba_audio五项68502比较、shared_lba_geometry十六几何262268比较通过，尚未推广。

WAV边界诊断wav_bound_original复现五处原算法缺陷：扩展fmt48/64被错误拒绝，data长度3/5被静默接受，声明FFFFFFFC时32位边界加法回卷后输出一对PCM才报错。诊断的PASS只代表准确复现缺陷，绝不作为这些输入功能正确的证据；修正候选和后续重新冻结回归另记录。实体板验证边界不变。

当前生产真实SPI复现入口：在repo根目录执行 `python safevision/tools/run_v3_shared_storage.py --run-dir D:/Codex/2026-10-15/github-plugin-github-openai-curated-remote/work/runs/shared_storage_final`。清单为 `shared_storage_sim.json`，用例 `tb_v3_shared_storage` 固定REF/MEM各50MHz，保留四完整BMP的614400个word、1920行CRC读回、24000对PCM及坏文件/碎片链/owner交接。生成器及其依赖完全在repo内；原生runner将源、测试、include、manifest、自身、两层生成器、七份生成资产全部逐项前后SHA-256绑定，缺正常结束或非零errors不能通过。该入口已整理，待WAV边界修正后重新冻结执行最终长测；历史prototype报告仍单独保留。

### WAV存量修复与严格负控的新入口

B冻结解除后，仅将旧`wav_parser.v`与`v3_wav_parser_ctx.v`推广为最小修复，分别SHA-256为7c7566d0ce2198e9dc76ffcfe6a280e0f24e251e7282f87501ad78a8772f653a、2329e6d986bd489191d70f94eaa8468057afc1d75e2365bfb82bbcc987d7c8a9。公共端口与445bit上下文布局保持，复用已完成签名校验后不再需要的`riff_r[0]`保存data_seen。FMT首16字节完成校验后，既有SKIP计数器消耗全部扩展和奇数填充；全部chunk extent和RIFF末端加宽检查，拒绝零或非4倍data；解析data后的chunk并排空RIFF外尾部。不能只让新紧凑链正确而保留同一已知旧错误。

私有两接口188oracle和旧445链5音频68502逐值比较均正常通过。推广后的真实生产文件又通过`wav_legacy`两项各8877检查，`wav_legacy_production_final`没有source override，四份生成资产逐项前后保全。最终B兼容仍应重新运行本次修复后的文件。

`run_v3_audio_negative.py`现使用专门的正常结束测试台。故意破坏generation、左右声道、hop保存后，必须输出对应`[FAIL AUDIO_GENERATION]`、`[FAIL AUDIO_STEREO]`、`[FAIL AUDIO_HOP_CONTEXT]`及非零errors，同时出现本测试的literal结束标记和`$finish`，且不能含Fatal/ERROR。运行器记录全部source/include/asset/generator/manifest/runner的before/after哈希及mutant哈希；编译、工具错误或没有完成标记一律拒绝。`audio_normal_finish_negative_legacy2`三项正常完成并报告540、9408、1个预期错误，原件保持。此报告对应旧修复前的具体snapshot，不作为后续紧凑链的最终负控。

若实际source选择compact111，负控自动修改该实际模块，不再误改不参与执行的旧parser，并追加188文件oracle的stereo/bound/extension三项。`wav_container_sim.json`和`wav_container_negative_sim.json`已整理为仓库内入口；紧凑核心正式推广后应重新冻结并运行完整6负控。此前私有`wav_compact_negative`的3个Fatal诊断只证明特定断言能被触发，不能替代这一正常结束的最终负控标准。

### 21:00后紧凑状态正式推广

ROOT独立审查、WP188文件oracle、旧5PCM回归68502、FS独立2163872项及WPFS组合5PCM回归68502均正常结束后，已逐字节推广冻结WP111+FS136四文件。REF物理服务ABI仍为445bit command/837bit response：FS字段高129bit保持零，仅低136bit参与持久旋转，顶层无需改变端口。FS只在F_SEC_REQ且!valid时保存；LOAD重建请求状态、字节偏移/timeout零、valid和SD/walker脉冲零、bytes_rd为当轨cnt。SAVE旋转中间重建状态始终禁止执行请求。

正式同路径同SDC整机HD资源对照为18608→18237等效LUT、13851→13489FF、RAM50不变；此候选在目前整机上仍超过80% LUT硬门槛，不能当作容量或时序通过。上面的6484/8tile等是历史优化快照，不能冒充当前整机资源。当前音频分配为ctx1、共享ingress2、samples2、HDMI1，共6个RAM9K。新freeze将重跑11项、tagged FIFO、188文件、FS边界及严格6负控；真SPI长测需待板级CS guard最终源码稳定后启动。

### 当前紧凑生产快照回归与双模式覆盖

`audio_wpfs_production_freeze/complete11` 的11项均正常结束、零失败：71180次严格PCM数值比较，欠载用例另1548次节拍观测。其整链固定MEM40MHz、HD像素时钟，实际输出5630对HDMI样本和117个ACR窗口，欠载/溢出均零；该旧时钟配置只作为接口/握手压力证明。新增 `audio_modes_sim.json` / `tb_v3_audio_modes.sv` 则明确使用生产MEM50MHz，分别运行BASE像素25.2MHz及HD像素74.25MHz，各自2700次严格PCM比较、5630对HDMI样本、117个实测CTS窗口，均正常结束、欠载/溢出零。入口为 `python safevision/tools/run_v3_sim.py --suite audio_modes --run-dir <ASCII新目录>`，不可改用不识别共享test_sources的旧入口。

同一快照的共享tag FIFO专项5139、188种RIFF文件8877、FS136上下文独立边界2163872项比较也正常通过。六个正常结束的隔离负控全部准确触发指定断言：generation错误540、左右声道9408、hop丢失1、容器声道8689、容器加法溢出6、fmt扩展截断150；全部mutant与原件/资产来源保全。汇总及每个原始日志哈希见 `work/audio_wpfs_production_handoff.json`，它是该冻结快照的记录，后续目录专用化、混音延迟或其他依赖变化后必须检查来源一致性，不能自动称为最终生产验收。

真实SPI清单现为29个显式HDL源：保留player/guard/SPI/CRC/FAT/BMP/帧写/官方FIFO/物理读回/WAV共享服务与紧凑上下文。移除原先并集带入但未实例化的priority、volume、audio_system、HDMI等40个源，避免将未执行逻辑纳入该测试的功能声明；双模式音频整链由独立清单验收。两层生成器、七份生成资产与全部实际源码仍逐项绑定SHA-256。`tb_v3_shared_storage` 已显式启用GUARDED_CS1及独立guard复位，等待目录专用化最终冻结后启动，不在未完成时计PASS。

### V3单DSP混音：保留完整24位的五拍延迟契约

生产V3装配现使用独立模块 `rtl/audio/v3_audio_priority_serial.v`；存量 `audio_priority_arbiter.v` 保持原一拍接口与原文件。WAV输入是PCM16左移8位，但ROM有98135等非256整数倍数值，不能将ROM低8位丢掉。令25位有符号差值 `delta=tone−wav`，拆成17位有符号 `high=delta[24:8]` 和8位无符号 `low=delta[7:0]`，则输出严格等于 `wav + high×gain + floor(low×gain/256)`。一个真实18×18 DSP依次做L高、L低、R高、R低；输入和新gain在接纳边沿完整捕获，第5个后续AUDIO边沿同时发布双声道valid，期间任何输入/报警控制变化都不能修改已捕获对。保留完整24bit输出，包括交叉淡变产生的真实小数低位。

此执行核最小接纳间隔为6个AUDIO周期，实际生产为256；未提供ready的固定节拍调用方必须满足它。800样本启动/欠载计时专项改用DIV8加速，800这个样本节拍门槛不变。原DIV4测试源码留在 `experiments/priority_interval4_contract`，它在935870ps明确触发overrun断言，原runner记FAIL/complete=false；这是非法输入间隔被检测的诊断，绝不当作正常结束回归或严格负控PASS。

独立64bit数值oracle共270336对全24bit立体声向量，包含全部65536种PCM16字、ROM低8位、随机另一声道、全部257系数，以及RAMP_N=1/240/256、五个计算相位异步复位。两个隔离精度负控正常结束并发现190926个丢小数差异和64259个负号差异。可直接运行 `python safevision/tools/run_v3_sim.py --suite priority_serial --run-dir <新ASCII目录>`，负控入口为 `python safevision/tools/run_v3_priority_negative.py --run-dir <新ASCII目录>`。

候选BASE/HD各自完成2780次严格PCM比较和12158次独立混音声道队列比较；在五个计算相位分别提出真实用户commit、media_reset和alarm请求，每模式6079对HDMI样本、126个实测CTS窗口、欠载/溢出零。媒体复位不清全局混音核；队列保留接纳当时的样本，不用新generation改写旧捕获对。此证明与环形FIFO的generation过滤分别保留，不能用混音局部队列代替整条链的标签检查。推广后正以实际生产文件重新运行11项和两个模式；未结束的记录不计最终通过。

同路径、同完整时钟约束、ctrl1/ripple32原生整机资源对照：HD 19495→18743等效LUT、13407→13557寄存器、29→26 DSP；BASE 18460→18172等效LUT、13229→13389寄存器、16→13 DSP；RAM均50tile。这个对照证明当前工程的面积收益，仍超过80% LUT门槛，不是资源或路由时序签核。另有L后R共用74拍音量核、单ROM地址查表、描述符复用RAM候选；这些没有随本次混音推广，不能冒充生产功能或当前资源。

### 74拍音量核正式推广与组合验收

同路径原生全机资源对照以已推广单DSP混音为起点：HD 18743→18627等效LUT、寄存器减少85；BASE 18172→18005等效LUT、寄存器减少86；DSP/RAM均不变。源码按冻结候选e414ac4070f9907598fa7511b1a60727d27a4197285447fa0b3a8ee3f7b0c28c逐字节推广，旧音量单元测试数值公式保留，只将45拍等待上限改82以覆盖新的74拍一般路径。独立29404项全24bit/全部音量0…127/忙时输入变化/74相位异步复位均正常完成；故意将恢复除法减100改99的负控正常结束并发现6879个数值错误，不能用Fatal或工具错误代替该证据。

组合测试 `audio_priority_volume_sim.json` 覆盖37%、73%两种一般路径，分别运行BASE和HD、MEM50MHz、AUDIO真实/256；四项候选测试各2908次严格输出PCM比较、13600次优先混音声道队列比较、13600次音量声道队列比较，HDMI6800对、141个实测CTS窗口，欠载/溢出零。除五个混音相位外，还在音量L乘法1/7、L除法8/37、R乘法38/44、R除法45/74边界提出真实恢复/报警/提交请求，阶段覆盖mask为ff，已捕获样本在媒体复位中保持。音量核只用global reset；单独74相位全局复位检查确认中止后不泄漏旧结果。

上述四项首先是冻结候选证据；推广后正以生产无override重新运行完整11项、四种组合模式、共享tag FIFO、29404项独立数值及严格负控。新清单可直接运行 `python safevision/tools/run_v3_sim.py --suite audio_priority_volume --run-dir <新ASCII目录>`；严格音量负控为 `python safevision/tools/run_v3_volume_negative.py --run-dir <新ASCII目录>`。只有新运行正常结束、源码前后相等才列为当前生产通过。资源仍超过80%门槛，未生成最终签核位流，实体音频/HDMI及长稳边界不变。
