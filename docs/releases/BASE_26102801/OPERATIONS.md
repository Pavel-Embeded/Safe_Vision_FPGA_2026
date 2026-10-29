# BASE 26102801 使用与恢复

BASE 输出 640×480 HDMI 画面和 48 kHz 立体声 PCM。底部中文提示随视频帧移动，左下保留启动计时，右下显示 32 频段频谱。

## TF 卡

TF 卡使用 FAT32。根目录至少放四张合法的 24 位或 32 位 BI_RGB BMP；中文长文件名和不同图片尺寸均可使用。程序按确定的名称字典顺序选择前四张有效图片，保持长宽比并补黑边，再装载到 SDRAM。

伴音优先选择同名 WAV，再按轮播次序选择可用 WAV；固定提示音用于伴音回退。WAV 使用 48 kHz、双声道、16 位 PCM。图像和伴音按同一 generation 提交。

## 下载到 SRAM

当前批准位流位于 [SafeVision_BASE_75b34e6.bit](../../../artifacts/releases/BASE_26102801/SafeVision_BASE_75b34e6.bit)。核对身份时读取同目录的 [release.index.json](../../../artifacts/releases/BASE_26102801/release.index.json)，其中分别记录物理构建提交、发布批准提交和位流 SHA-256。

在项目根目录运行以下命令。输出目录须为新的英文路径。

```powershell
powershell -NoProfile -File .\safevision\tools\host\burn_ticker261028_sram.ps1 -Package .\artifacts\releases\BASE_26102801 -OutDir D:\Codex\SafeVision_Board_Check
```

脚本先核对当前源码、位流和证据包，再重放功能及完整时序检查，随后调用本机 TD BitWriter。下载回执保存实际器件、位流校验值、工具校验值和命令结束状态。串口使用板载 CH340，参数为 115200、8N1；主机脚本关闭 DTR、RTS。

板载 Flash 已固化 BASE 26102801。SRAM 下载用于临时加载，CONFIG1 或重新上电则从 Flash 加载。切勿把 KEY1 媒体复位与 CONFIG1 配置重载混用。

## Flash 固化与恢复

便携文件见 [Flash 安装包](../../../artifacts/releases/BASE_26102801/SafeVision_BASE_26102801_FLASH.zip)。ZIP 内的 `FLASH_INSTALL.md` 给出独立安装与恢复步骤，`package.index.json` 登记所含文件的校验值。完整源码和资格归档继续保存在项目仓库。

当前安装的原始回执见 [flash/receipt.json](../../../artifacts/releases/BASE_26102801/flash/receipt.json)。流程包括器件和 EF4015 识别、两次完整备份、写入、独立校验、两次完整读回及 Flash 重载。重载后串口读回本版固件、四槽有效位和零健康错误。

再次安装时，先运行预览。确认选择的版本后，加 `-Apply` 并指定新的英文输出目录。脚本核对位流及工具校验值，保留当时完整 Flash 的两次备份，任何阶段失败即停止。默认不触发硬件操作。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\artifacts\releases\BASE_26102801\flash\tools\program_flash.ps1 -Image Latest
powershell -NoProfile -ExecutionPolicy Bypass -File .\artifacts\releases\BASE_26102801\flash\tools\program_flash.ps1 -Image Latest -Apply -OutDir D:\Codex\SafeVision_Flash_Install
```

恢复到旧成功 BASE 26102301 时选择 `Previous`，输出路径同样使用新的空目录：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\artifacts\releases\BASE_26102801\flash\tools\program_flash.ps1 -Image Previous -Apply -OutDir D:\Codex\SafeVision_Flash_Rollback
```

`Previous` 使用随包保存的 `SafeVision_BASE_6a957b0.bit`。更早版本资料见 [BASE 26102301 操作说明](../BASE_26102301/OPERATIONS.md)。本次安装前读出的 Flash 与旧归档内容不同，因此按原始备份保存，不为它指定固件版本。

本版完全断电重接后由用户确认各项正常，后续只读串口回读通过；实体断电与机器采集分别留证，见 [用户反馈](../../../artifacts/releases/BASE_26102801/board/cold_boot_user_report.json)。旧版掉电反馈继续绑定旧版位流。独立复查命令如下：

```powershell
python -B safevision/tools/verify_ticker_flash261028.py --output D:\Codex\SafeVision_Flash_Check.json
```


## 离线复查环境

完整复查使用 Python 3.12、Node.js 24，以及与 GitHub Actions 相同的固定版本依赖。在独立的 Python 环境中运行：

```powershell
python -m pip install pypdf==6.10.0 numpy==2.3.5 PyYAML==6.0.3
python -B safevision/tools/verify_ticker_flash_delivery261029.py --run-dir D:\Codex\SafeVision_Offline_Check
```

输出目录须为新的英文路径。工具逐项复查当前源码、位流、原始功能和时序记录、串口采集及实体反馈，并在冻结的 BASE 26102301 中执行原验收。GitHub Actions 将旧基线和当前交付放在两个独立任务中运行；主检查要求旧基线成功，再执行本版的完整证据复查。

## 按键与菜单

正常播放时，KEY2 换图，KEY3 切换自动轮播，KEY4 控制应急显示。KEY2+KEY3 同时长按约两秒进入菜单。菜单内短按 KEY2 增加、短按 KEY3 减小；长按 KEY2 切换项目，长按 KEY3 退出。

八项参数沿用 [菜单说明](../BASE_26102301/MENU_CN.md)：亮度、对比度、缩放算法、缩放比例、Fade、音量、轮播周期和 OSD Alpha。默认亮度 80%、对比度 128、音量 70、轮播周期 5 秒，Fade 为 32 帧。相邻画面完成提交的间隔包含停留时间和约 0.534 秒的渐变时间。

KEY1 复位播放与显示通路，随后重新装载媒体、关闭菜单，字幕位置回到起点。已设置的参数和左下 UP 累计秒数保留；重新配置 FPGA 或断电启动才会重新计时。软件媒体恢复期间，系统计时与字幕位置继续推进。

## 字幕

固定正文为“安全提示：遇紧急情况，请保持冷静，听从工作人员指挥，并有序撤离。”正文共 32 个字格，随位流存入独立 ROM。

文字从右向左移动，每两帧推进一列，约为 30 像素/秒，一个循环约 34 秒。底条位于 BASE 画面的 x=120～631、y=456～475；正文白色、底色黑色，上沿有青色细线。字幕占用独立的显示区域，启动计时和频谱保留各自位置。模块接口、字模和时序契约见 [字幕模块](../../modules/scrolling_ticker.md)。

## 串口复查

以下是查询正文，主机工具负责协议封包和校验。

| 正文 | 观察内容 |
| --- | --- |
| `B:DIAG=0` | 固件标识 `26102801` |
| `B:STATUS?` | 媒体就绪状态，稳定播放为 7 |
| `B:CACHE?` | 四槽缓存有效位，全部有效为 15 |
| `B:DIAG=101` | 高 20 位 `544B1`，低 12 位为 0～1023 的字幕位置 |
| `B:INTEGRITY?`、`B:VUNDERFLOW?`、`B:UNDERFLOW?` | 图像校验、视频和音频欠载计数 |

自动板测入口为 `safevision/tools/host/exercise_ticker261028.ps1`。它记录有效换图、故障恢复、默认参数回读、字幕速度、自动轮播和连续运行状态，并保存原始发送、接收字节。配置、缩放和周期采集由 `ticker_host_profile261028.py` 使用冻结审计器逐条复查。

串口记录与显示器观察分别保存。文字是否清楚、滚动是否平滑、图片方向和比例以及声音输出，由实物观察确认。
