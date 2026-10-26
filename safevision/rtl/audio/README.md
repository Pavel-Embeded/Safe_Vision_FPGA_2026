# 音频链

`v3_audio_system` 连接生产音频链：WAV 描述符进入 PCM 队列与 SDRAM 环缓存，经 48 kHz 调度、音量和报警处理后送往 HDMI PCM/ACR 服务。

接口、时钟、复位和测试入口见 [生产模块手册](../../../docs/modules/README.md)。当前验收见 [BASE 26102301](../../../docs/releases/BASE_26102301/ACCEPTANCE.md)。本目录同时保留部分早期实现，生产选择以显式源清单为准。
