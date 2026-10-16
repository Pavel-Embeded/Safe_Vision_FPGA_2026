# 按键和 UART 使用

UART：115200，8N1；RX F12、TX D12。输入帧为 `$A|B|C:NAME[=十进制有符号整数|?]*HH\r\n`，这里竖线表示三选一，实际不发送竖线；HH 为从 A/B/C 开始到 `*` 前最后一个字符的逐字节 XOR，两个大写十六进制字符。仅完整、校验及范围都合法的命令产生副作用；100ms 不完整帧超时。名称仅大写字母，不含数字。

| 目标 | 名称 | 值/动作 |
|---|---|---|
| A | BRIGHT | -128..127 |
| A | CONTRAST | 0..255；128 为 1.0 |
| A | ALPHA | 0..255 |
| A | SCALER | 0 最近邻，1 双线性 |
| A | SCALE | 0 居中 1:1，1 等比例 fit |
| A | FADE | 0 直接提交，1 默认 32 帧转场 |
| C | VOL | 0..100 |
| C | PERIOD | 2/5/10/30 秒 |
| C | AUTO | 0/1 |
| C | NEXT | =1；缓存未就绪、SAFE 或转场忙返回 04 |
| C | RECOVER | =1；开始有限恢复；FATAL 需全局复位 |

BRIGHT、CONTRAST、ALPHA、SCALER、SCALE、FADE、VOL、PERIOD、AUTO 可用 `?` 查询。NEXT、RECOVER 是动作；RECOVER 的成功回执表示已提交请求，恢复结果通过 RECOVERY、RETRIES 和 FAULT 观察。运行中更改 PERIOD 会重启倒计时。

B 域只接受查询，例如 `B:CACHE?`，完整字段如下。除特别标注外均为无符号值，回执统一传输 32bit。

| 名称 | 数值含义 |
|---|---|
| STATUS | SD/BMP player 当前状态码 |
| SLOT | 当前显示槽，0..3 |
| CACHE | 四槽有效位图，bit0 对应槽0 |
| GEN | 音画提交代号，8bit 循环 |
| UNDERFLOW / VUNDERFLOW | 音频 / 视频欠载累计数 |
| FAULT / LEVEL | 锁存首个故障码 / 当前故障等级 |
| PRESENTATION | 转场同步超时标志 |
| INTEGRITY | 写入读回或显示行 CRC 错误标志 |
| RECOVERY / RETRIES | 恢复控制器状态 / 已尝试次数 |
| REJECTED | 本轮被拒绝 BMP 数量 |
| IDLOW / IDHIGH | 槽0、1 / 槽2、3的文件 BCD 编号，各编号占16bit，低槽在低位 |
| BADERROR / BADID | 最近被拒绝 BMP 的 `{主码,细分码}` / BCD 编号 |
| WAVFALLBACK | 四轨 WAV 降级位图 |
| OVERFLOW | 音频溢出累计数 |
| EVENTDROP | 错误事件队列丢失计数，16bit 饱和 |
| UARTREJECT | 解析器拒绝帧计数，32bit 饱和 |
| UARTFRAME / UARTOVERRUN | RX 帧格式错误 / 接收溢出计数 |
| UARTDROP | 回执队列丢失计数，32bit 饱和 |

返回 `$C:ACK=HH,XXXXXXXX*HH\r\n`。HH 的含义：00 已接受；01 校验和或十六进制校验字符错误；02 目标不是 A/B/C；03 名称、参数或数值范围不合法；04 语法/结束符错误，或 NEXT 的业务条件忙；06 帧过长或不完整帧超时。同一个04同时用于协议错误和业务忙，需要结合原命令判断。XXXXXXXX 为 32bit 数值十六进制，有符号亮度按二补码解读。错误事件 `$C:EVT=SS,CC,TTTTTTTT*HH\r\n` 含来源、错误码及毫秒时间戳。

下一张/轮播键在松开时触发，避免组合键泄露单键动作。两键同时保持 2 秒进入/退出配置菜单；菜单内短按下一张增加、轮播减少；长按下一张 1 秒选择下一字段，长按轮播 1 秒退出。应急键在菜单和 UART 操作期间仍优先。退出应急后按下一张可请求恢复；FATAL 锁定用全局复位。

此脚本给出实际帧（输出可直接通过串口工具发送）：

```python
body = 'A:BRIGHT=-16'
checksum = 0
for b in body.encode('ascii'): checksum ^= b
print(f'${body}*{checksum:02X}\r\n', end='')
```
