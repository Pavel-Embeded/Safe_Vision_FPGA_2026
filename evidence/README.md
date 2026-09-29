# 证据目录

依据手册 V2.0 §11.4。按“需求编号 → 测试编号 → 原始文件 → 构建 tag”索引，不预填结果。`requirements/` 评审；`sim/` 日志与随机种子；`waveform/` 原始波形；`reports/` 综合/STA/CDC/资源；`board/` 实机；`measurements/` 带宽/水位/长稳；`provenance/` 许可与第三方来源。

文件名建议 `TC-B02-01_YYYYMMDD_<build-tag>_<run>.<ext>`，每个子目录的 `INDEX.md` 记录：测试编号、需求、Git 提交/bitstream 哈希、工具/板卡/外设、步骤、结论、原始文件。敏感个人资料与无许可第三方原件不得进入版本库。大文件可另存受控位置，但索引必须记录不可变哈希和可访问路径。空索引表示尚无证据，不是通过。
